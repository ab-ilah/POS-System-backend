-- Clothing-store POS baseline.
-- Amounts are whole pesewas (100 pesewas = 1 cedi). Shelf prices already include tax.
-- There is no fractional rate and no card-number column.
--
-- Row level security is enabled on every application table. Policies follow
-- shared/permissions.matrix.ts. The table owner bypasses RLS so local seed and
-- migrations can write; do not FORCE ROW LEVEL SECURITY or that path breaks.
-- The Supabase service_role also bypasses RLS. It may live only in Edge
-- Function secrets or other server-side config, never in a client bundle.

create schema if not exists private;

revoke all on schema private from public;
grant usage on schema private to authenticated, service_role, supabase_auth_admin;

create type public.app_role as enum ('owner', 'manager', 'cashier');

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  role public.app_role not null default 'cashier',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is
  'Staff profile. Role is the authorization source. Do not read role from user_metadata.';

create table public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null,
  description text not null default '',
  image_path text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint products_category_check check (
    category in ('shirts', 'dresses', 'kaftans', 'jeans', 'shoes', 'accessories')
  )
);

comment on column public.products.image_path is
  'Optional object path. Null means the item has no picture yet.';

create table public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  sku text not null unique,
  size_name text not null,
  colour_name text not null,
  price_pesewas integer not null,
  stock_qty integer not null,
  low_stock_threshold integer not null default 5,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_variants_price_pesewas_check check (price_pesewas >= 0),
  constraint product_variants_stock_qty_check check (stock_qty >= 0),
  constraint product_variants_low_stock_threshold_check check (low_stock_threshold >= 0)
);

comment on column public.product_variants.price_pesewas is
  'Tax-inclusive shelf price in whole pesewas.';

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text,
  credit_balance_pesewas integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint customers_credit_balance_pesewas_check check (credit_balance_pesewas >= 0)
);

comment on column public.customers.credit_balance_pesewas is
  'Amount the customer currently owes the shop, in whole pesewas.';

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  receipt_no text not null unique,
  customer_id uuid references public.customers (id) on delete restrict,
  cashier_id uuid not null references public.profiles (id) on delete restrict,
  status text not null default 'completed',
  subtotal_pesewas integer not null,
  total_pesewas integer not null,
  tendered_pesewas integer not null,
  change_pesewas integer not null,
  credit_applied_pesewas integer not null default 0,
  sold_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sales_status_check check (status in ('completed', 'voided')),
  constraint sales_subtotal_pesewas_check check (subtotal_pesewas >= 0),
  constraint sales_total_pesewas_check check (total_pesewas >= 0),
  constraint sales_tendered_pesewas_check check (tendered_pesewas >= 0),
  constraint sales_change_pesewas_check check (change_pesewas >= 0),
  constraint sales_credit_applied_pesewas_check check (credit_applied_pesewas >= 0),
  constraint sales_settlement_check check (
    tendered_pesewas + credit_applied_pesewas = total_pesewas + change_pesewas
  )
);

comment on column public.sales.total_pesewas is
  'Tax-inclusive amount due, in whole pesewas. Equal to the sum of line totals.';

create table public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales (id) on delete restrict,
  variant_id uuid not null references public.product_variants (id) on delete restrict,
  product_name text not null,
  size_name text not null,
  colour_name text not null,
  qty integer not null,
  unit_price_pesewas integer not null,
  line_total_pesewas integer not null,
  created_at timestamptz not null default now(),
  constraint sale_items_qty_check check (qty > 0),
  constraint sale_items_unit_price_pesewas_check check (unit_price_pesewas >= 0),
  constraint sale_items_line_total_pesewas_check check (line_total_pesewas >= 0),
  constraint sale_items_line_total_identity_check check (
    line_total_pesewas = qty * unit_price_pesewas
  )
);

comment on column public.sale_items.unit_price_pesewas is
  'Tax-inclusive unit price copied from the shelf at the time of sale, in whole pesewas.';

create index product_variants_product_id_idx on public.product_variants (product_id);
create index products_category_idx on public.products (category);
create index sales_cashier_id_idx on public.sales (cashier_id);
create index sales_customer_id_idx on public.sales (customer_id);
create index sale_items_sale_id_idx on public.sale_items (sale_id);
create index sale_items_variant_id_idx on public.sale_items (variant_id);

create or replace function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = pg_catalog.now();
  return new;
end;
$$;

create trigger profiles_touch_updated_at
before update on public.profiles
for each row execute function private.touch_updated_at();

create trigger products_touch_updated_at
before update on public.products
for each row execute function private.touch_updated_at();

create trigger product_variants_touch_updated_at
before update on public.product_variants
for each row execute function private.touch_updated_at();

create trigger customers_touch_updated_at
before update on public.customers
for each row execute function private.touch_updated_at();

create trigger sales_touch_updated_at
before update on public.sales
for each row execute function private.touch_updated_at();

create or replace function private.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
  from public.profiles as p
  where p.id = (select auth.uid())
$$;

comment on function private.current_app_role() is
  'Staff role from profiles. Not from user_metadata, which the account holder can edit.';

create or replace function private.profile_role(target uuid)
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
  from public.profiles as p
  where p.id = target
$$;

revoke all on function private.current_app_role() from public, anon;
revoke all on function private.profile_role(uuid) from public, anon;
revoke all on function private.touch_updated_at() from public, anon;

grant execute on function private.current_app_role() to authenticated, service_role;
grant execute on function private.profile_role(uuid) to authenticated, service_role;
grant execute on function private.touch_updated_at() to authenticated, service_role;

create or replace function private.enforce_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Seed and other server-side sessions have no end-user id. They may set the
  -- initial role. A signed-in staff member may change a role only as owner.
  if new.role is distinct from old.role
     and (select auth.uid()) is not null
     and private.current_app_role() is distinct from 'owner'::public.app_role then
    raise exception 'only the owner can change a staff role'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function private.enforce_profile_role_change() from public, anon;
grant execute on function private.enforce_profile_role_change() to authenticated, service_role;

create trigger profiles_enforce_role_change
before update on public.profiles
for each row execute function private.enforce_profile_role_change();

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), 'Staff'),
    'cashier'
  );
  return new;
end;
$$;

revoke all on function private.handle_new_user() from public, anon, authenticated;
grant execute on function private.handle_new_user() to supabase_auth_admin, postgres, service_role;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_user();

alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.customers enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;

revoke all on table
  public.profiles,
  public.products,
  public.product_variants,
  public.customers,
  public.sales,
  public.sale_items
from anon, public;

grant select, insert, update, delete on table
  public.profiles,
  public.products,
  public.product_variants,
  public.customers,
  public.sales,
  public.sale_items
to authenticated, service_role;

-- profiles: no insert policy. The auth trigger creates rows.
create policy profiles_select
on public.profiles
for select
to authenticated
using (
  (select private.current_app_role()) in ('owner', 'manager')
  or (
    (select private.current_app_role()) = 'cashier'
    and id = (select auth.uid())
  )
);

create policy profiles_update
on public.profiles
for update
to authenticated
using (
  (select private.current_app_role()) = 'owner'
  or (
    (select private.current_app_role()) = 'manager'
    and role <> 'owner'
  )
  or (
    (select private.current_app_role()) = 'cashier'
    and id = (select auth.uid())
  )
)
with check (
  (select private.current_app_role()) = 'owner'
  or (
    (select private.current_app_role()) = 'manager'
    and role <> 'owner'
  )
  or (
    (select private.current_app_role()) = 'cashier'
    and id = (select auth.uid())
  )
);

create policy profiles_delete
on public.profiles
for delete
to authenticated
using ((select private.current_app_role()) = 'owner');

create policy products_select
on public.products
for select
to authenticated
using ((select private.current_app_role()) in ('owner', 'manager', 'cashier'));

create policy products_insert
on public.products
for insert
to authenticated
with check ((select private.current_app_role()) in ('owner', 'manager'));

create policy products_update
on public.products
for update
to authenticated
using ((select private.current_app_role()) in ('owner', 'manager'))
with check ((select private.current_app_role()) in ('owner', 'manager'));

create policy products_delete
on public.products
for delete
to authenticated
using ((select private.current_app_role()) in ('owner', 'manager'));

create policy product_variants_select
on public.product_variants
for select
to authenticated
using ((select private.current_app_role()) in ('owner', 'manager', 'cashier'));

create policy product_variants_insert
on public.product_variants
for insert
to authenticated
with check ((select private.current_app_role()) in ('owner', 'manager'));

create policy product_variants_update
on public.product_variants
for update
to authenticated
using ((select private.current_app_role()) in ('owner', 'manager'))
with check ((select private.current_app_role()) in ('owner', 'manager'));

create policy product_variants_delete
on public.product_variants
for delete
to authenticated
using ((select private.current_app_role()) in ('owner', 'manager'));

create policy customers_select
on public.customers
for select
to authenticated
using ((select private.current_app_role()) in ('owner', 'manager', 'cashier'));

create policy customers_insert
on public.customers
for insert
to authenticated
with check ((select private.current_app_role()) in ('owner', 'manager', 'cashier'));

create policy customers_update
on public.customers
for update
to authenticated
using ((select private.current_app_role()) in ('owner', 'manager', 'cashier'))
with check ((select private.current_app_role()) in ('owner', 'manager', 'cashier'));

create policy customers_delete
on public.customers
for delete
to authenticated
using ((select private.current_app_role()) in ('owner', 'manager'));

create policy sales_select
on public.sales
for select
to authenticated
using ((select private.current_app_role()) in ('owner', 'manager', 'cashier'));

create policy sales_insert
on public.sales
for insert
to authenticated
with check (
  (select private.current_app_role()) in ('owner', 'manager', 'cashier')
  and cashier_id = (select auth.uid())
);

create policy sales_update
on public.sales
for update
to authenticated
using ((select private.current_app_role()) in ('owner', 'manager'))
with check ((select private.current_app_role()) in ('owner', 'manager'));

create policy sale_items_select
on public.sale_items
for select
to authenticated
using ((select private.current_app_role()) in ('owner', 'manager', 'cashier'));

create policy sale_items_insert
on public.sale_items
for insert
to authenticated
with check ((select private.current_app_role()) in ('owner', 'manager', 'cashier'));
