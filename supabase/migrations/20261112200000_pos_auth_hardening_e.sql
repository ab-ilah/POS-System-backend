-- POS-AUTH-01e: anon on public functions, xact tokens, trimmed EXECUTE allowlist, drop GUC helpers.

truncate table private.sale_completion_tokens;

alter table private.sale_completion_tokens drop column txid;

alter table private.sale_completion_tokens
  add column xact_id xid8 not null;

create or replace function private.sale_completion_token_pending(p_sale_id uuid)
returns boolean
language sql
volatile
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.sale_completion_tokens as t
    where t.sale_id = p_sale_id
      and t.xact_id = pg_catalog.pg_current_xact_id()
  );
$$;

create or replace function private.sale_completion_token_consume(p_sale_id uuid)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  delete from private.sale_completion_tokens as t
  where t.sale_id = p_sale_id
    and t.xact_id = pg_catalog.pg_current_xact_id();
$$;

drop function if exists private.set_commit_sale_completing();
drop function if exists private.clear_commit_sale_completing();

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
  if private.session_is_trusted_db()
     and not (
       old.status = 'open'
       and new.status = 'completed'
       and new.void_reason is null
       and new.voided_at is null
     ) then
    null;
  elsif
    current_user = 'authenticated'
    and coalesce((select auth.jwt() ->> 'role'), '') = 'authenticated'
    and private.current_app_role() in ('owner'::public.app_role, 'manager'::public.app_role)
  then
    if
      old.status = 'open'
      and new.status = 'completed'
      and new.void_reason is null
      and new.voided_at is null
    then
      raise exception 'sales can only be completed through commit_sale'
        using errcode = '42501';
    end if;
    null;
  elsif
    current_user in ('postgres', 'supabase_admin')
    and old.status = 'open'
    and new.status = 'completed'
    and new.void_reason is null
    and new.voided_at is null
  then
    if not private.sale_completion_token_pending(new.id) then
      raise exception 'sales can only be completed through commit_sale'
        using errcode = '42501';
    end if;
    if coalesce((select auth.jwt() ->> 'role'), '') is distinct from 'authenticated' then
      raise exception 'sales can only be completed through commit_sale'
        using errcode = '42501';
    elsif
      private.session_staff_app_role() in (
        'owner'::public.app_role,
        'manager'::public.app_role,
        'cashier'::public.app_role
      )
    then
      perform private.sale_completion_token_consume(new.id);
    else
      raise exception 'sales can only be completed through commit_sale'
        using errcode = '42501';
    end if;
  else
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

  select s.*
  into existing
  from public.sales as s
  where s.id = p_idempotency_key
  for share;

  if found then
    if existing.cashier_id is distinct from caller then
      raise exception 'idempotency_key_conflict'
        using errcode = 'P0004';
    end if;
    perform private.commit_sale_assert_lines_payload(p_lines);
    if not private.commit_sale_payload_matches(p_idempotency_key, p_store_id, p_lines) then
      raise exception 'idempotency_key_conflict'
        using errcode = 'P0004';
    end if;
    return pg_catalog.jsonb_build_object(
      'sale_id', existing.id,
      'replayed', true,
      'status', existing.status
    );
  end if;

  if not exists (
    select 1
    from public.stores as st
    where st.id = p_store_id
  ) then
    raise exception 'no such store'
      using errcode = 'P0002';
  end if;

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

    insert into private.sale_completion_tokens (sale_id, xact_id)
    values (p_idempotency_key, pg_catalog.pg_current_xact_id())
    on conflict (sale_id) do update
    set xact_id = excluded.xact_id;

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
      'replayed', false,
      'status', 'completed'
    );
  exception
    when unique_violation then
      select s.*
      into existing
      from public.sales as s
      where s.id = p_idempotency_key
      for share;
      if found then
        if existing.cashier_id is distinct from caller then
          raise exception 'idempotency_key_conflict'
            using errcode = 'P0004';
        end if;
        perform private.commit_sale_assert_lines_payload(p_lines);
        if not private.commit_sale_payload_matches(p_idempotency_key, p_store_id, p_lines) then
          raise exception 'idempotency_key_conflict'
            using errcode = 'P0004';
        end if;
        return pg_catalog.jsonb_build_object(
          'sale_id', existing.id,
          'replayed', true,
          'status', existing.status
        );
      end if;
      raise;
    when others then
      raise;
  end;
end;
$$;


alter default privileges for role postgres in schema public
  revoke execute on functions from anon;

do $$
declare
  fn regprocedure;
begin
  for fn in
    select p.oid::regprocedure
    from pg_proc as p
    inner join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
  loop
    execute format('revoke all on function %s from anon', fn);
  end loop;
end;
$$;

revoke all on function public.assign_staff_role(uuid, public.app_role) from service_role;

revoke all on function private.enforce_sale_update() from public, anon, authenticated, service_role;
revoke all on function private.enforce_sale_item_open_sale() from public, anon, authenticated, service_role;
revoke all on function private.enforce_credit_balance_owner() from public, anon, authenticated, service_role;
revoke all on function private.session_staff_app_role() from public, anon, authenticated;

comment on function private.session_staff_app_role() is
  'Staff app role for auth.uid() (via app_role_of). EXECUTE is granted to postgres only; the commit_sale completion token path invokes it from SECURITY DEFINER callers inside enforce_sale_update.';

grant execute on function private.current_app_role() to authenticated, service_role;
grant execute on function private.target_is_owner(uuid) to authenticated;
grant execute on function private.session_staff_app_role() to postgres;
grant execute on function private.session_is_trusted_db() to authenticated, service_role;
grant execute on function private.session_is_authenticated_staff() to authenticated, service_role;
grant execute on function private.caller_may_update_profile(uuid) to authenticated, service_role;
grant execute on function private.write_staff_role(uuid, public.app_role) to authenticated;

revoke all on function private.touch_updated_at() from public, anon, authenticated, service_role;

grant execute on function public.commit_sale(uuid, uuid, jsonb) to authenticated;
grant execute on function public.my_role() to authenticated;
grant execute on function public.assign_staff_role(uuid, public.app_role) to authenticated;
grant execute on function public.consume_staff_invite_slot(uuid) to service_role;
