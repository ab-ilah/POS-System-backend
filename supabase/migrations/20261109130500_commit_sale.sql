-- POS-02b: commit_sale RPC, stores, sale_lines rename, stock_movements.
-- Follows ab-ilah/POS-system- src/types/database.ts and docs/commit-sale.md.
-- Existing sale_items is renamed to sale_lines (quantity column) to match the frontend contract.

create table public.stores (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.stores is
  'Physical shop location. The seed inserts one default store for single-site POS.';

insert into public.stores (id, name)
values (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'Main shop'
);

alter table public.sales
  add column store_id uuid references public.stores (id) on delete restrict;

update public.sales
set store_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
where store_id is null;

alter table public.sales
  alter column store_id set not null;

create index sales_store_id_idx on public.sales (store_id);

alter table public.sale_items rename to sale_lines;
alter table public.sale_lines rename column qty to quantity;

alter table public.sale_lines
  rename constraint sale_items_qty_check to sale_lines_quantity_check;

alter table public.sale_lines
  rename constraint sale_items_unit_price_pesewas_check to sale_lines_unit_price_pesewas_check;

alter table public.sale_lines
  rename constraint sale_items_line_total_pesewas_check to sale_lines_line_total_pesewas_check;

alter table public.sale_lines
  drop constraint sale_items_line_total_identity_check;

alter table public.sale_lines
  add constraint sale_lines_line_total_identity_check check (
    line_total_pesewas = quantity * unit_price_pesewas
  );

alter index sale_items_sale_id_idx rename to sale_lines_sale_id_idx;
alter index sale_items_variant_id_idx rename to sale_lines_variant_id_idx;

alter trigger sale_items_require_open_sale on public.sale_lines rename to sale_lines_require_open_sale;

alter table public.sale_lines enable row level security;

drop policy sale_items_select on public.sale_lines;
drop policy sale_items_insert on public.sale_lines;

create policy sale_lines_select
on public.sale_lines
for select
to authenticated
using ((select private.current_app_role()) in ('owner', 'manager', 'cashier'));

create policy sale_lines_insert
on public.sale_lines
for insert
to authenticated
with check (
  (select private.current_app_role()) in ('owner', 'manager', 'cashier')
  and exists (
    select 1
    from public.sales as s
    where s.id = sale_id
      and s.cashier_id = (select auth.uid())
      and s.status = 'open'
  )
);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales (id) on delete restrict,
  sale_line_id uuid not null references public.sale_lines (id) on delete restrict,
  variant_id uuid not null references public.product_variants (id) on delete restrict,
  qty_delta integer not null,
  created_at timestamptz not null default now(),
  constraint stock_movements_qty_delta_check check (qty_delta <> 0),
  constraint stock_movements_sale_line_id_key unique (sale_line_id)
);

comment on table public.stock_movements is
  'Append-only inventory deltas tied to committed sale lines. Negative qty_delta is stock leaving the shelf.';

create index stock_movements_sale_id_idx on public.stock_movements (sale_id);
create index stock_movements_variant_id_idx on public.stock_movements (variant_id);

create trigger stores_touch_updated_at
before update on public.stores
for each row execute function private.touch_updated_at();

alter table public.stores enable row level security;
alter table public.stock_movements enable row level security;

revoke all on table public.stores, public.stock_movements from anon, public;

grant select, insert, update, delete on table public.stores to authenticated, service_role;
grant select, insert on table public.stock_movements to authenticated, service_role;

create policy stores_select
on public.stores
for select
to authenticated
using ((select private.current_app_role()) in ('owner', 'manager', 'cashier'));

create policy stores_insert
on public.stores
for insert
to authenticated
with check ((select private.current_app_role()) in ('owner', 'manager'));

create policy stores_update
on public.stores
for update
to authenticated
using ((select private.current_app_role()) in ('owner', 'manager'))
with check ((select private.current_app_role()) in ('owner', 'manager'));

create policy stores_delete
on public.stores
for delete
to authenticated
using ((select private.current_app_role()) = 'owner');

create policy stock_movements_select
on public.stock_movements
for select
to authenticated
using ((select private.current_app_role()) in ('owner', 'manager', 'cashier'));

create policy stock_movements_insert
on public.stock_movements
for insert
to authenticated
with check ((select private.current_app_role()) in ('owner', 'manager', 'cashier'));

-- Cashiers cannot update variant rows directly. Stock leaves the shelf inside commit_sale.
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
begin
  if coalesce(pg_catalog.current_setting('private.commit_sale_active', true), '') <> '1' then
    raise exception 'stock adjustment is only allowed during commit_sale'
      using errcode = '42501';
  end if;
  if pg_catalog.current_setting('role', true) is distinct from 'authenticated'
     or coalesce((select auth.jwt() ->> 'role'), '') is distinct from 'authenticated' then
    raise exception 'only staff can commit a sale'
      using errcode = '42501';
  end if;
  if private.app_role_of((select auth.uid())) is null
     or private.app_role_of((select auth.uid())) not in (
       'owner'::public.app_role, 'manager'::public.app_role, 'cashier'::public.app_role
     ) then
    raise exception 'only staff can commit a sale'
      using errcode = '42501';
  end if;
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
      using errcode = 'PSTCK';
  end if;
  update public.product_variants as v
  set stock_qty = v.stock_qty + p_delta
  where v.id = p_variant_id;
end;
$$;

revoke all on function private.stock_qty_apply_for_commit(uuid, integer) from public, anon, authenticated, service_role;
grant execute on function private.stock_qty_apply_for_commit(uuid, integer) to authenticated;

create or replace function public.commit_sale(
  p_idempotency_key uuid,
  p_store_id uuid,
  p_lines jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  caller uuid;
  role public.app_role;
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
  product_name text;
  size_name text;
  colour_name text;
  receipt text;
  line_ids uuid[] := '{}';
  i integer;
begin
  if not private.session_is_authenticated_staff() then
    raise exception 'only staff can commit a sale'
      using errcode = '42501';
  end if;
  role := private.current_app_role();
  if role is null or role not in ('owner'::public.app_role, 'manager'::public.app_role, 'cashier'::public.app_role) then
    raise exception 'only staff can commit a sale'
      using errcode = '42501';
  end if;
  caller := (select auth.uid());
  if caller is null then
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
    select v.price_pesewas, v.stock_qty
    into shelf_price, stock_qty
    from public.product_variants as v
    where v.id = variant_id;
    if not found then
      raise exception 'no such variant'
        using errcode = 'P0002';
    end if;
    if unit_price is distinct from shelf_price then
      raise exception 'unit price does not match shelf price'
        using errcode = 'P0003';
    end if;
    if stock_qty < quantity then
      raise exception 'insufficient stock'
        using errcode = 'PSTCK';
    end if;
  end loop;

  perform pg_catalog.set_config('private.commit_sale_active', '1', true);

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

      insert into public.sale_lines (
        id,
        sale_id,
        variant_id,
        product_name,
        size_name,
        colour_name,
        quantity,
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
        sale_line_id,
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
      and s.status = 'open';

    perform pg_catalog.set_config('private.commit_sale_active', '0', true);

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
        return pg_catalog.jsonb_build_object(
          'sale_id', existing.id,
          'replayed', true
        );
      end if;
      raise;
    when others then
      perform pg_catalog.set_config('private.commit_sale_active', '0', true);
      raise;
  end;
end;
$$;

comment on function public.commit_sale(uuid, uuid, jsonb) is
  'One-shot sale: open header, lines, stock moves, then complete. Idempotent on p_idempotency_key (client sale id).';

revoke all on function public.commit_sale(uuid, uuid, jsonb) from public, anon, service_role;
grant execute on function public.commit_sale(uuid, uuid, jsonb) to authenticated;
