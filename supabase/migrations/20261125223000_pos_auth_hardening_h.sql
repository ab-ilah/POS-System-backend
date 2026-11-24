-- POS-AUTH-01h: auth guards, stock hardening, append-only stock_movements ledger.

-- ---------- (a) Drop redundant manager-vs-owner branches in staff role writers ----------

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
  if new_role = 'owner'::public.app_role then
    raise exception 'the owner role cannot be assigned here'
      using errcode = '42501';
  end if;
  existing := private.app_role_of(target);
  if existing = 'owner'::public.app_role then
    raise exception 'the owner cannot be reassigned'
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

create or replace function public.assign_staff_role(target uuid, new_role public.app_role)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  caller public.app_role;
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
  if new_role = 'owner'::public.app_role then
    raise exception 'the owner role cannot be assigned here'
      using errcode = '42501';
  end if;
  if private.target_is_owner(target) then
    raise exception 'the owner cannot be reassigned'
      using errcode = '42501';
  end if;
  perform private.write_staff_role(target, new_role);
end;
$$;

-- ---------- (e) profiles_delete: null target_is_owner fails closed ----------

drop policy if exists profiles_delete on public.profiles;

create policy profiles_delete
on public.profiles
for delete
to authenticated
using (
  (select private.current_app_role()) = 'owner'
  and (select private.target_is_owner(id)) is false
);

-- ---------- (g) service_role cannot UPDATE stock_qty directly ----------

revoke update (stock_qty) on table public.product_variants from service_role;

-- ---------- (h) adjust_stock: bigint range, reason cap ----------

create or replace function public.adjust_stock(
  p_variant_id uuid,
  p_delta integer,
  p_reason text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_role public.app_role;
  current_qty integer;
  new_qty bigint;
  actor uuid;
  trimmed_reason text;
begin
  if (select auth.role()) is distinct from 'authenticated' then
    raise exception 'only an owner or manager can adjust stock'
      using errcode = '42501';
  end if;
  if coalesce((select auth.jwt() ->> 'role'), '') is distinct from 'authenticated' then
    raise exception 'only an owner or manager can adjust stock'
      using errcode = '42501';
  end if;
  actor := (select auth.uid());
  if actor is null then
    raise exception 'only an owner or manager can adjust stock'
      using errcode = '42501';
  end if;
  caller_role := private.current_app_role();
  if caller_role is null
     or caller_role not in ('owner'::public.app_role, 'manager'::public.app_role) then
    raise exception 'only an owner or manager can adjust stock'
      using errcode = '42501';
  end if;

  if p_delta is null or p_delta = 0 then
    raise exception 'stock adjustment delta must be non-zero'
      using errcode = 'P0004';
  end if;
  if p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'stock adjustment requires a reason'
      using errcode = 'P0004';
  end if;

  trimmed_reason := btrim(p_reason);
  if length(trimmed_reason) > 500 then
    raise exception 'stock adjustment reason must be at most 500 characters'
      using errcode = 'P0004';
  end if;

  select v.stock_qty
  into current_qty
  from public.product_variants as v
  where v.id = p_variant_id
  for update;

  if not found then
    raise exception 'no such variant'
      using errcode = 'P0002';
  end if;

  new_qty := current_qty::bigint + p_delta::bigint;
  if new_qty < 0 then
    raise exception 'insufficient stock'
      using errcode = 'PSTCK';
  end if;
  if new_qty > 2147483647 then
    raise exception 'stock quantity would exceed the maximum allowed value'
      using errcode = '22003';
  end if;

  update public.product_variants as v
  set stock_qty = new_qty::integer
  where v.id = p_variant_id;

  insert into public.stock_movements (
    sale_id,
    sale_item_id,
    variant_id,
    qty_delta,
    reason,
    actor_id
  )
  values (
    null,
    null,
    p_variant_id,
    p_delta,
    trimmed_reason,
    actor
  );

  return new_qty::integer;
end;
$$;

-- ---------- (i) stock_movements append-only even for privileged roles ----------

create or replace function private.guard_stock_movements_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'stock_movements is append-only'
    using errcode = '42501';
end;
$$;

drop trigger if exists stock_movements_append_only_guard on public.stock_movements;

create trigger stock_movements_append_only_guard
before update or delete on public.stock_movements
for each row
execute function private.guard_stock_movements_append_only();

revoke all on function private.guard_stock_movements_append_only() from public, anon, authenticated, service_role;
grant execute on function private.guard_stock_movements_append_only() to postgres;