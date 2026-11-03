-- Clothing-store POS baseline.
-- Amounts are whole pesewas (100 pesewas = 1 cedi). Shelf prices already include tax.
-- There is no fractional rate and no card-number column.
--
-- Row level security is enabled on every application table. Policies follow
-- shared/permissions.matrix.ts. The table owner bypasses RLS so local seed and
-- migrations can write; do not FORCE ROW LEVEL SECURITY or that path breaks.
-- The Supabase service_role also bypasses RLS. It may live only in Edge
-- Function secrets or other server-side config, never in a client bundle.
-- Triggers still fire for service_role. A missing auth.uid() is not a bypass.

create schema if not exists private;

revoke all on schema private from public;
grant usage on schema private to authenticated, service_role, supabase_auth_admin;

create type public.app_role as enum ('owner', 'manager', 'cashier');

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is
  'Staff profile. Authorization is auth.users.raw_app_meta_data.role. A new user has no role until an owner or manager assigns one.';

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
  status text not null default 'open',
  void_reason text,
  voided_at timestamptz,
  subtotal_pesewas integer not null,
  total_pesewas integer not null,
  tendered_pesewas integer not null,
  change_pesewas integer not null,
  credit_applied_pesewas integer not null default 0,
  sold_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sales_status_check check (status in ('open', 'completed', 'voided')),
  constraint sales_subtotal_pesewas_check check (subtotal_pesewas >= 0),
  constraint sales_total_pesewas_check check (total_pesewas >= 0),
  constraint sales_tendered_pesewas_check check (tendered_pesewas >= 0),
  constraint sales_change_pesewas_check check (change_pesewas >= 0),
  constraint sales_credit_applied_pesewas_check check (credit_applied_pesewas >= 0),
  constraint sales_settlement_check check (
    tendered_pesewas + credit_applied_pesewas = total_pesewas + change_pesewas
  ),
  constraint sales_void_shape_check check (
    (
      status in ('open', 'completed')
      and void_reason is null
      and voided_at is null
    )
    or (
      status = 'voided'
      and void_reason is not null
      and length(btrim(void_reason)) > 0
      and voided_at is not null
    )
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

-- Reads app_metadata for a user id. This does not decide whether the caller is that user.
create or replace function private.app_role_of(target uuid)
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when u.raw_app_meta_data ->> 'role' in ('owner', 'manager', 'cashier')
      then (u.raw_app_meta_data ->> 'role')::public.app_role
    else null
  end
  from auth.users as u
  where u.id = target
$$;

-- Security invoker so current_user is the session that issued the statement.
-- Inside a security-definer function, current_user is the owner instead.
create or replace function private.session_is_trusted_db()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select session_user in ('postgres', 'supabase_admin')
     and current_user = session_user
$$;

create or replace function private.session_is_authenticated_staff()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select current_user = 'authenticated'
     and coalesce((select auth.jwt() ->> 'role'), '') = 'authenticated'
$$;

create or replace function private.current_app_role()
returns public.app_role
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not private.session_is_authenticated_staff() then
    return null;
  end if;
  return private.app_role_of((select auth.uid()));
end;
$$;

comment on function private.current_app_role() is
  'Role from auth.users.raw_app_meta_data for an authenticated session. A service_role JWT is not a staff session, even when its subject is an owner id. Never read user_metadata.';

-- Internal lookup. Not an API. Returns null unless the caller is an authenticated staff session.
create or replace function private.staff_role(target uuid)
returns public.app_role
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not (private.session_is_trusted_db() or private.session_is_authenticated_staff()) then
    return null;
  end if;
  return private.app_role_of(target);
end;
$$;

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
      and private.staff_role(target) is distinct from 'owner'::public.app_role
    )
    or (
      private.current_app_role() = 'cashier'::public.app_role
      and target = (select auth.uid())
    )
$$;

revoke all on function private.app_role_of(uuid) from public, anon, authenticated, service_role;
revoke all on function private.current_app_role() from public, anon;
revoke all on function private.session_is_trusted_db() from public, anon;
revoke all on function private.session_is_authenticated_staff() from public, anon;
revoke all on function private.staff_role(uuid) from public, anon, authenticated;
revoke all on function private.caller_may_update_profile(uuid) from public, anon;
revoke all on function private.touch_updated_at() from public, anon;

grant execute on function private.app_role_of(uuid) to authenticated;
grant execute on function private.current_app_role() to authenticated, service_role;
grant execute on function private.session_is_trusted_db() to authenticated, service_role;
grant execute on function private.session_is_authenticated_staff() to authenticated, service_role;
grant execute on function private.staff_role(uuid) to authenticated;
grant execute on function private.caller_may_update_profile(uuid) to authenticated, service_role;
grant execute on function private.touch_updated_at() to authenticated, service_role;

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), 'Staff')
  );
  return new;
end;
$$;

revoke all on function private.handle_new_user() from public, anon, authenticated;
grant execute on function private.handle_new_user() to supabase_auth_admin, postgres, service_role;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_user();

-- Writes app_metadata. Callers cannot use this to skip the authenticated-session check:
-- current_user inside this definer is the owner, so the caller's role is the SET ROLE
-- value, which is the same role current_user had in the invoker.
create or replace function private.write_staff_role(target uuid, new_role public.app_role)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller public.app_role;
  existing public.app_role;
begin
  if pg_catalog.current_setting('role', true) is distinct from 'authenticated'
     or coalesce((select auth.jwt() ->> 'role'), '') is distinct from 'authenticated' then
    raise exception 'only an owner or manager can assign a staff role'
      using errcode = '42501';
  end if;
  caller := private.app_role_of((select auth.uid()));
  if caller is null or caller not in ('owner'::public.app_role, 'manager'::public.app_role) then
    raise exception 'only an owner or manager can assign a staff role'
      using errcode = '42501';
  end if;
  existing := private.app_role_of(target);
  if caller = 'manager'::public.app_role and existing = 'owner'::public.app_role then
    raise exception 'a manager cannot change the owner'
      using errcode = '42501';
  end if;
  if caller = 'manager'::public.app_role and new_role = 'owner'::public.app_role then
    raise exception 'a manager cannot assign the owner role'
      using errcode = '42501';
  end if;
  update auth.users
  set raw_app_meta_data =
    case
      when raw_app_meta_data is null then pg_catalog.jsonb_build_object('role', new_role)
      else raw_app_meta_data || pg_catalog.jsonb_build_object('role', new_role)
    end
  where id = target;
  if not found then
    raise exception 'no such staff user'
      using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function private.write_staff_role(uuid, public.app_role) from public, anon, authenticated, service_role;
grant execute on function private.write_staff_role(uuid, public.app_role) to authenticated;

-- Owner or manager assigns a role by writing app_metadata. Signup does not.
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
  existing := private.staff_role(target);
  if caller = 'manager'::public.app_role and existing = 'owner'::public.app_role then
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

revoke all on function public.assign_staff_role(uuid, public.app_role) from public, anon;
grant execute on function public.assign_staff_role(uuid, public.app_role) to authenticated, service_role;

create or replace function private.enforce_sale_update()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Any write, including a no-op and an updated_at bump, is rejected.
  if old.status = 'voided' then
    raise exception 'a voided sale is frozen'
      using errcode = '42501';
  end if;
  if not (
    private.session_is_trusted_db()
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

revoke all on function private.enforce_sale_update() from public, anon;
grant execute on function private.enforce_sale_update() to authenticated, service_role;

create trigger sales_enforce_void_only
before update on public.sales
for each row execute function private.enforce_sale_update();

create or replace function private.enforce_sale_item_open_sale()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  parent_status text;
begin
  if tg_op in ('INSERT', 'UPDATE') then
    select s.status
    into parent_status
    from public.sales as s
    where s.id = new.sale_id;
    if parent_status is distinct from 'open' then
      raise exception 'cannot change lines on a finished sale'
        using errcode = '42501';
    end if;
  end if;
  if tg_op in ('UPDATE', 'DELETE') then
    select s.status
    into parent_status
    from public.sales as s
    where s.id = old.sale_id;
    if parent_status is distinct from 'open' then
      raise exception 'cannot change lines on a finished sale'
        using errcode = '42501';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function private.enforce_sale_item_open_sale() from public, anon;
grant execute on function private.enforce_sale_item_open_sale() to authenticated, service_role;

create trigger sale_items_require_open_sale
before insert or update or delete on public.sale_items
for each row execute function private.enforce_sale_item_open_sale();

create or replace function private.enforce_credit_balance_owner()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Migrations and seed run as postgres or supabase_admin with no SET ROLE.
  -- A service_role JWT is a different current_user even when its subject is the owner.
  if session_user in ('postgres', 'supabase_admin') and current_user = session_user then
    return new;
  end if;
  if current_user = 'authenticated'
     and coalesce((select auth.jwt() ->> 'role'), '') = 'authenticated'
     and private.current_app_role() = 'owner'::public.app_role then
    return new;
  end if;
  if tg_op = 'INSERT' and new.credit_balance_pesewas is distinct from 0 then
    raise exception 'only the owner can set a credit balance'
      using errcode = '42501';
  end if;
  if tg_op = 'UPDATE'
     and new.credit_balance_pesewas is distinct from old.credit_balance_pesewas then
    raise exception 'only the owner can set a credit balance'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function private.enforce_credit_balance_owner() from public, anon;
grant execute on function private.enforce_credit_balance_owner() to authenticated, service_role;

create trigger customers_enforce_credit_owner
before insert or update on public.customers
for each row execute function private.enforce_credit_balance_owner();

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

-- A sale update may complete an open sale or void it. Amounts and identity columns stay immutable.
revoke update on table public.sales from authenticated;
grant update (status, void_reason, voided_at, updated_at) on table public.sales to authenticated;

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
using ((select private.caller_may_update_profile(id)))
with check ((select private.caller_may_update_profile(id)));

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
