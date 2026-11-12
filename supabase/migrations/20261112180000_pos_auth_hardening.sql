-- POS-AUTH-01: caller-only role lookup, signup/bootstrap hardening, commit_sale replay scope,
-- block direct sale inserts, enforce_sale completion latch, stock PSTCK detail.

-- ---------- helpers (new) ----------

create or replace function private.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when u.raw_app_meta_data ->> 'role' in ('owner', 'manager', 'cashier')
      then (u.raw_app_meta_data ->> 'role')::public.app_role
  end
  from auth.users as u
  where u.id = (select auth.uid())
    and pg_catalog.current_setting('role', true) = 'authenticated'
    and coalesce((select auth.jwt() ->> 'role'), '') = 'authenticated'
$$;

comment on function private.current_app_role() is
  'Caller role from auth.users.raw_app_meta_data. Table-derived; JWT app_metadata is ignored.';

create or replace function private.target_is_owner(target uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when private.current_app_role() in ('owner'::public.app_role, 'manager'::public.app_role) then
      coalesce(
        (select u.raw_app_meta_data ->> 'role' = 'owner'
         from auth.users as u
         where u.id = target),
        false
      )
  end
$$;

create or replace function public.my_role()
returns public.app_role
language sql
stable
security invoker
set search_path = ''
as $$
  select private.current_app_role()
$$;

create table private.bootstrap_state (
  id boolean primary key default true check (id),
  owner_bootstrapped_at timestamptz
);

insert into private.bootstrap_state default values;

create or replace function private.bootstrap_first_owner(p_email text)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  target uuid;
begin
  if session_user not in ('postgres', 'supabase_admin')
     or current_user <> session_user then
    raise exception 'bootstrap is SQL-editor only'
      using errcode = '42501';
  end if;
  perform 1 from private.bootstrap_state where id for update;
  if (select owner_bootstrapped_at from private.bootstrap_state) is not null
     or exists (
       select 1 from auth.users as u
       where u.raw_app_meta_data ->> 'role' = 'owner'
     ) then
    raise exception 'owner already bootstrapped'
      using errcode = '42501';
  end if;
  select u.id
  into strict target
  from auth.users as u
  where lower(u.email) = lower(p_email);
  update auth.users as u
  set raw_app_meta_data = coalesce(u.raw_app_meta_data, '{}'::jsonb) || '{"role":"owner"}'::jsonb
  where u.id = target;
  update private.bootstrap_state
  set owner_bootstrapped_at = pg_catalog.now();
  return target;
end;
$$;

create table private.staff_invite_buckets (
  caller_id uuid not null,
  bucket_start timestamptz not null,
  invite_count integer not null default 0,
  primary key (caller_id, bucket_start)
);

create or replace function private.consume_staff_invite_slot(p_caller uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  bucket timestamptz := date_trunc('hour', pg_catalog.now());
  cnt integer;
begin
  if coalesce((select auth.jwt() ->> 'role'), '') is distinct from 'service_role' then
    raise exception 'invite rate limit is service only'
      using errcode = '42501';
  end if;
  insert into private.staff_invite_buckets as b (caller_id, bucket_start, invite_count)
  values (p_caller, bucket, 1)
  on conflict (caller_id, bucket_start) do update
  set invite_count = b.invite_count + 1
  returning invite_count into cnt;
  if cnt > 10 then
    raise exception 'invite rate limit exceeded'
      using errcode = 'P0004';
  end if;
end;
$$;

-- Used only from enforce_sale_update (SECURITY INVOKER) while commit_sale completes a sale.
-- EXECUTE is postgres-only: the trigger runs as postgres inside commit_sale (SECURITY DEFINER).
comment on function private.session_staff_app_role() is
  'Staff app role for the JWT subject. Callable only from postgres-owned triggers, not from clients.';

create or replace function private.session_staff_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select private.app_role_of((select auth.uid()));
$$;

-- ---------- dependents on helpers ----------

create or replace function private.caller_may_update_profile(target uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select
    private.current_app_role() = 'owner'::public.app_role
    or (
      private.current_app_role() = 'manager'::public.app_role
      and private.target_is_owner(target) is not true
    )
    or (
      private.current_app_role() = 'cashier'::public.app_role
      and target = (select auth.uid())
    )
$$;

create or replace function public.assign_staff_role(target uuid, new_role public.app_role)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  caller public.app_role;
  existing public.app_role;
begin
  if current_user is distinct from 'authenticated'
     or coalesce((select auth.jwt() ->> 'role'), '') is distinct from 'authenticated' then
    raise exception 'only an owner or manager can assign a staff role'
      using errcode = '42501';
  end if;
  caller := private.current_app_role();
  if caller is null or caller not in ('owner'::public.app_role, 'manager'::public.app_role) then
    raise exception 'only an owner or manager can assign a staff role'
      using errcode = '42501';
  end if;
  if caller = 'manager'::public.app_role and private.target_is_owner(target) then
    raise exception 'a manager cannot change the owner'
      using errcode = '42501';
  end if;
  if caller = 'manager'::public.app_role and new_role = 'owner'::public.app_role then
    raise exception 'a manager cannot assign the owner role'
      using errcode = '42501';
  end if;
  perform private.write_staff_role(target, new_role);
end;
$$;

create or replace function private.stock_qty_apply_for_commit(
  p_variant_id uuid,
  p_delta integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  locked_qty integer;
  rows_updated integer;
begin
  select v.stock_qty
  into locked_qty
  from public.product_variants as v
  where v.id = p_variant_id
  for update;
  if not found then
    raise exception 'no such variant'
      using errcode = 'P0002';
  end if;
  if locked_qty + p_delta < 0 then
    raise exception 'insufficient stock'
      using errcode = 'PSTCK',
            detail = 'variant_id=' || p_variant_id::text;
  end if;
  update public.product_variants as v
  set stock_qty = v.stock_qty + p_delta
  where v.id = p_variant_id;
  get diagnostics rows_updated = row_count;
  if rows_updated <> 1 then
    raise exception 'stock row was not updated'
      using errcode = 'P0006';
  end if;
end;
$$;

create or replace function private.enforce_sale_update()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.status = 'voided' then
    raise exception 'a voided sale is frozen'
      using errcode = '42501';
  end if;
  if not (
    private.session_is_trusted_db()
    or (
      coalesce(pg_catalog.current_setting('private.commit_sale_completing', true), '') = '1'
      and (select auth.role()) = 'authenticated'
      and coalesce((select auth.jwt() ->> 'role'), '') = 'authenticated'
      and private.session_staff_app_role() in (
        'owner'::public.app_role,
        'manager'::public.app_role,
        'cashier'::public.app_role
      )
      and old.status = 'open'
      and new.status = 'completed'
      and new.void_reason is null
      and new.voided_at is null
    )
    or (
      current_user = 'authenticated'
      and coalesce((select auth.jwt() ->> 'role'), '') = 'authenticated'
      and private.current_app_role() in ('owner'::public.app_role, 'manager'::public.app_role)
    )
  ) then
    raise exception 'only an owner or manager can update a sale'
      using errcode = '42501';
  end if;
  if new.receipt_no is distinct from old.receipt_no
     or new.store_id is distinct from old.store_id
     or new.customer_id is distinct from old.customer_id
     or new.cashier_id is distinct from old.cashier_id
     or new.subtotal_pesewas is distinct from old.subtotal_pesewas
     or new.total_pesewas is distinct from old.total_pesewas
     or new.tendered_pesewas is distinct from old.tendered_pesewas
     or new.change_pesewas is distinct from old.change_pesewas
     or new.credit_applied_pesewas is distinct from old.credit_applied_pesewas
     or new.sold_at is distinct from old.sold_at
     or new.created_at is distinct from old.created_at
  then
    raise exception 'sale amounts and identity columns are immutable'
      using errcode = '42501';
  end if;
  if new.status is distinct from old.status
     and not (
       old.status = 'open'
       and new.status = 'completed'
       and new.void_reason is null
       and new.voided_at is null
     )
     and new.status <> 'voided' then
    raise exception 'a sale can only be completed from open, or voided'
      using errcode = '42501';
  end if;
  if new.status = 'voided' and (new.void_reason is null or length(btrim(new.void_reason)) = 0) then
    raise exception 'voiding a sale requires a reason'
      using errcode = '42501';
  end if;
  if new.status = 'voided' and old.status is distinct from 'voided' and new.voided_at is null then
    new.voided_at := pg_catalog.now();
  end if;
  return new;
end;
$$;

create or replace function public.commit_sale(
  p_idempotency_key uuid,
  p_store_id uuid,
  p_lines jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid;
  staff_role public.app_role;
  existing public.sales%rowtype;
  other_cashier_sale boolean;
  line jsonb;
  line_id uuid;
  variant_id uuid;
  quantity integer;
  unit_price integer;
  line_total integer;
  shelf_price integer;
  computed_subtotal integer := 0;
  computed_total integer := 0;
  variant_ids uuid[] := '{}';
  stock_qty integer;
  demanded_qty integer;
  product_name text;
  size_name text;
  colour_name text;
  receipt text;
  line_ids uuid[] := '{}';
  rows_affected integer;
  i integer;
begin
  if (select auth.role()) is distinct from 'authenticated' then
    raise exception 'only staff can commit a sale'
      using errcode = '42501';
  end if;
  if coalesce((select auth.jwt() ->> 'role'), '') is distinct from 'authenticated' then
    raise exception 'only staff can commit a sale'
      using errcode = '42501';
  end if;
  caller := (select auth.uid());
  if caller is null then
    raise exception 'only staff can commit a sale'
      using errcode = '42501';
  end if;
  staff_role := private.app_role_of(caller);
  if staff_role is null
     or staff_role not in (
       'owner'::public.app_role, 'manager'::public.app_role, 'cashier'::public.app_role
     ) then
    raise exception 'only staff can commit a sale'
      using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('commit_sale:' || p_idempotency_key::text)
  );

  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'a sale needs at least one line'
      using errcode = 'P0004';
  end if;

  if not exists (
    select 1
    from public.stores as st
    where st.id = p_store_id
  ) then
    raise exception 'no such store'
      using errcode = 'P0002';
  end if;

  for line in select elem from jsonb_array_elements(p_lines) as t(elem) loop
    if jsonb_typeof(line) <> 'object' then
      raise exception 'invalid sale line'
        using errcode = 'P0004';
    end if;
    line_id := (line ->> 'id')::uuid;
    variant_id := (line ->> 'variant_id')::uuid;
    quantity := (line ->> 'quantity')::integer;
    unit_price := (line ->> 'unit_price_pesewas')::integer;
    if line_id is null or variant_id is null or quantity is null or unit_price is null then
      raise exception 'invalid sale line'
        using errcode = 'P0004';
    end if;
    if quantity <= 0 or unit_price < 0 then
      raise exception 'invalid sale line'
        using errcode = 'P0004';
    end if;
    if line_id = any (line_ids) then
      raise exception 'duplicate sale line id'
        using errcode = 'P0005';
    end if;
    line_ids := line_ids || line_id;
    if variant_id = any (variant_ids) then
      null;
    else
      variant_ids := variant_ids || variant_id;
    end if;
    line_total := quantity * unit_price;
    computed_subtotal := computed_subtotal + line_total;
  end loop;

  computed_total := computed_subtotal;

  variant_ids := array(
    select distinct unnest(variant_ids)
    order by 1
  );

  for i in 1 .. coalesce(array_length(variant_ids, 1), 0) loop
    select v.price_pesewas, v.stock_qty
    into shelf_price, stock_qty
    from public.product_variants as v
    inner join public.products as p on p.id = v.product_id and p.active = true
    where v.id = variant_ids[i]
    for update of v;
    if not found then
      raise exception 'no such variant'
        using errcode = 'P0002';
    end if;
  end loop;

  for line in select elem from jsonb_array_elements(p_lines) as t(elem) loop
    variant_id := (line ->> 'variant_id')::uuid;
    quantity := (line ->> 'quantity')::integer;
    unit_price := (line ->> 'unit_price_pesewas')::integer;
    select v.price_pesewas
    into shelf_price
    from public.product_variants as v
    inner join public.products as p on p.id = v.product_id and p.active = true
    where v.id = variant_id;
    if not found then
      raise exception 'no such variant'
        using errcode = 'P0002';
    end if;
    if unit_price is distinct from shelf_price then
      raise exception 'unit price does not match shelf price'
        using errcode = 'P0003';
    end if;
  end loop;

  for variant_id, demanded_qty in
    select
      (elem ->> 'variant_id')::uuid,
      sum((elem ->> 'quantity')::integer)::integer
    from jsonb_array_elements(p_lines) as t(elem)
    group by 1
    order by 1
  loop
    select v.stock_qty
    into stock_qty
    from public.product_variants as v
    where v.id = variant_id;
    if stock_qty < demanded_qty then
      raise exception 'insufficient stock'
        using errcode = 'PSTCK',
              detail = 'variant_id=' || variant_id::text;
    end if;
  end loop;

  select exists (
    select 1
    from public.sales as s
    where s.id = p_idempotency_key
      and s.cashier_id is distinct from caller
  )
  into other_cashier_sale;

  if other_cashier_sale then
    raise exception 'idempotency_key_conflict'
      using errcode = 'P0004';
  end if;

  select s.*
  into existing
  from public.sales as s
  where s.id = p_idempotency_key
    and s.cashier_id = caller;

  if found then
    perform private.commit_sale_assert_lines_payload(p_lines);
    if not private.commit_sale_payload_matches(p_idempotency_key, p_store_id, p_lines) then
      raise exception 'idempotency_key_conflict'
        using errcode = 'P0004';
    end if;
    return pg_catalog.jsonb_build_object(
      'sale_id', existing.id,
      'replayed', true
    );
  end if;

  receipt := upper('C-' || substr(replace(p_idempotency_key::text, '-', ''), 1, 12));

  begin
    insert into public.sales (
      id,
      receipt_no,
      store_id,
      customer_id,
      cashier_id,
      status,
      subtotal_pesewas,
      total_pesewas,
      tendered_pesewas,
      change_pesewas,
      credit_applied_pesewas
    )
    values (
      p_idempotency_key,
      receipt,
      p_store_id,
      null,
      caller,
      'open',
      computed_subtotal,
      computed_total,
      computed_total,
      0,
      0
    );

    for line in select elem from jsonb_array_elements(p_lines) as t(elem) loop
      line_id := (line ->> 'id')::uuid;
      variant_id := (line ->> 'variant_id')::uuid;
      quantity := (line ->> 'quantity')::integer;
      unit_price := (line ->> 'unit_price_pesewas')::integer;
      line_total := quantity * unit_price;

      select p.name, v.size_name, v.colour_name
      into product_name, size_name, colour_name
      from public.product_variants as v
      join public.products as p on p.id = v.product_id
      where v.id = variant_id;

      insert into public.sale_items (
        id,
        sale_id,
        variant_id,
        product_name,
        size_name,
        colour_name,
        qty,
        unit_price_pesewas,
        line_total_pesewas
      )
      values (
        line_id,
        p_idempotency_key,
        variant_id,
        product_name,
        size_name,
        colour_name,
        quantity,
        unit_price,
        line_total
      );

      insert into public.stock_movements (
        sale_id,
        sale_item_id,
        variant_id,
        qty_delta
      )
      values (
        p_idempotency_key,
        line_id,
        variant_id,
        -quantity
      );

      perform private.stock_qty_apply_for_commit(variant_id, -quantity);
    end loop;

    perform pg_catalog.set_config('private.commit_sale_completing', '1', true);

    update public.sales as s
    set status = 'completed'
    where s.id = p_idempotency_key
      and s.status = 'open'
      and s.cashier_id = caller;
    get diagnostics rows_affected = row_count;
    if rows_affected <> 1 then
      raise exception 'sale was not completed'
        using errcode = 'P0006';
    end if;

    return pg_catalog.jsonb_build_object(
      'sale_id', p_idempotency_key,
      'replayed', false
    );
  exception
    when unique_violation then
      select exists (
        select 1
        from public.sales as s
        where s.id = p_idempotency_key
          and s.cashier_id is distinct from caller
      )
      into other_cashier_sale;
      if other_cashier_sale then
        raise exception 'idempotency_key_conflict'
          using errcode = 'P0004';
      end if;
      select s.*
      into existing
      from public.sales as s
      where s.id = p_idempotency_key
        and s.cashier_id = caller;
      if found then
        perform private.commit_sale_assert_lines_payload(p_lines);
        if not private.commit_sale_payload_matches(p_idempotency_key, p_store_id, p_lines) then
          raise exception 'idempotency_key_conflict'
            using errcode = 'P0004';
        end if;
        return pg_catalog.jsonb_build_object(
          'sale_id', existing.id,
          'replayed', true
        );
      end if;
      raise;
    when others then
      raise;
  end;
end;
$$;

comment on function public.commit_sale(uuid, uuid, jsonb) is
  'Trusted one-shot sale: open header, sale_items, stock moves, then complete. Idempotent on p_idempotency_key when the store and lines match.';

-- ---------- privilege hardening (revokes last) ----------

revoke insert on table public.sales from authenticated;
revoke insert on table public.sale_items from authenticated;

drop policy if exists sales_insert on public.sales;
drop policy if exists sale_items_insert on public.sale_items;

revoke all on function private.app_role_of(uuid) from public, anon, authenticated, service_role;
revoke all on function private.current_app_role() from public, anon;
grant execute on function private.current_app_role() to authenticated, service_role;
revoke all on function private.target_is_owner(uuid) from public, anon, service_role;
grant execute on function private.target_is_owner(uuid) to authenticated;
revoke all on function public.my_role() from public, anon;
grant execute on function public.my_role() to authenticated;

drop function if exists private.staff_role(uuid);

alter default privileges for role postgres in schema private
  revoke execute on functions from public;

revoke all on table private.bootstrap_state from public, anon, authenticated, service_role;
revoke all on function private.bootstrap_first_owner(text) from public, anon, authenticated, service_role;

revoke all on table private.staff_invite_buckets from public, anon, authenticated, service_role;
revoke all on function private.consume_staff_invite_slot(uuid) from public, anon, authenticated;
grant execute on function private.consume_staff_invite_slot(uuid) to service_role, postgres;

create or replace function public.consume_staff_invite_slot(p_caller uuid)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.consume_staff_invite_slot(p_caller);
$$;

revoke all on function public.consume_staff_invite_slot(uuid) from public, anon, authenticated;
grant execute on function public.consume_staff_invite_slot(uuid) to service_role;

revoke all on function private.session_staff_app_role() from public, anon, authenticated, service_role;
grant execute on function private.session_staff_app_role() to postgres;
