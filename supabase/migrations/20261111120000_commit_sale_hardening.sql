-- commit_sale: idempotent replay payload checks, aggregated stock pre-check, stock_movements insert lockdown.

create or replace function private.commit_sale_payload_matches(
  p_sale_id uuid,
  p_store_id uuid,
  p_lines jsonb
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with payload_lines as (
    select
      (elem ->> 'id')::uuid as line_id,
      (elem ->> 'variant_id')::uuid as variant_id,
      (elem ->> 'quantity')::integer as qty,
      (elem ->> 'unit_price_pesewas')::integer as unit_price_pesewas
    from jsonb_array_elements(p_lines) as t(elem)
  )
  select exists (
    select 1
    from public.sales as s
    where s.id = p_sale_id
      and s.store_id = p_store_id
  )
  and (
    select count(*)::bigint
    from payload_lines
  ) = (
    select count(*)::bigint
    from public.sale_items as si
    where si.sale_id = p_sale_id
  )
  and not exists (
    select 1
    from payload_lines as p
    left join public.sale_items as si
      on si.sale_id = p_sale_id
     and si.id = p.line_id
    where si.id is null
       or si.variant_id is distinct from p.variant_id
       or si.qty is distinct from p.qty
       or si.unit_price_pesewas is distinct from p.unit_price_pesewas
  );
$$;

revoke all on function private.commit_sale_payload_matches(uuid, uuid, jsonb) from public, anon, authenticated, service_role;
grant execute on function private.commit_sale_payload_matches(uuid, uuid, jsonb) to postgres;

drop policy if exists stock_movements_insert on public.stock_movements;

revoke insert on table public.stock_movements from authenticated;

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

  select s.*
  into existing
  from public.sales as s
  where s.id = p_idempotency_key;

  if found then
    if not private.commit_sale_payload_matches(p_idempotency_key, p_store_id, p_lines) then
      raise exception 'idempotency_key_reuse'
        using errcode = 'P0004';
    end if;
    return pg_catalog.jsonb_build_object(
      'sale_id', existing.id,
      'replayed', true
    );
  end if;

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
        using errcode = 'PSTCK';
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
      select s.*
      into existing
      from public.sales as s
      where s.id = p_idempotency_key;
      if found then
        if not private.commit_sale_payload_matches(p_idempotency_key, p_store_id, p_lines) then
          raise exception 'idempotency_key_reuse'
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
