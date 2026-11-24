-- POS-06: manual stock adjustments via adjust_stock; stock_movements ledger supports sale and adjustment rows.

alter table public.stock_movements
  alter column sale_id drop not null,
  alter column sale_item_id drop not null;

alter table public.stock_movements
  add column reason text,
  add column actor_id uuid references auth.users (id) on delete restrict;

alter table public.stock_movements
  add constraint stock_movements_origin_check check (
    (
      sale_id is not null
      and sale_item_id is not null
      and reason is null
      and actor_id is null
    )
    or (
      sale_id is null
      and sale_item_id is null
      and reason is not null
      and length(btrim(reason)) > 0
      and actor_id is not null
    )
  );

comment on table public.stock_movements is
  'Append-only inventory deltas: committed sale lines (sale_id + sale_item_id) or manual adjustments (reason + actor_id via adjust_stock).';

-- Stock changes must go through adjust_stock or commit_sale, not a direct UPDATE.
revoke update on table public.product_variants from authenticated;
grant update (
  product_id,
  sku,
  size_name,
  colour_name,
  price_pesewas,
  low_stock_threshold
) on table public.product_variants to authenticated;

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
  new_qty integer;
  actor uuid;
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

  select v.stock_qty
  into current_qty
  from public.product_variants as v
  where v.id = p_variant_id
  for update;

  if not found then
    raise exception 'no such variant'
      using errcode = 'P0002';
  end if;

  new_qty := current_qty + p_delta;
  if new_qty < 0 then
    raise exception 'insufficient stock'
      using errcode = 'PSTCK';
  end if;

  update public.product_variants as v
  set stock_qty = new_qty
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
    btrim(p_reason),
    actor
  );

  return new_qty;
end;
$$;

revoke all on function public.adjust_stock(uuid, integer, text) from public, anon, service_role;
grant execute on function public.adjust_stock(uuid, integer, text) to authenticated;