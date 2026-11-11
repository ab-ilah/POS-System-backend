-- Replay idempotency: each payload line id must match sale_items.id with identical variant/qty/price.

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
    where p.line_id is null
       or p.variant_id is null
       or p.qty is null
       or p.unit_price_pesewas is null
       or si.id is null
       or si.variant_id is distinct from p.variant_id
       or si.qty is distinct from p.qty
       or si.unit_price_pesewas is distinct from p.unit_price_pesewas
  )
  and not exists (
    select 1
    from public.sale_items as si
    left join payload_lines as p
      on p.line_id = si.id
    where si.sale_id = p_sale_id
      and (
        p.line_id is null
        or si.variant_id is distinct from p.variant_id
        or si.qty is distinct from p.qty
        or si.unit_price_pesewas is distinct from p.unit_price_pesewas
      )
  );
$$;

revoke all on function private.commit_sale_payload_matches(uuid, uuid, jsonb) from public, anon, authenticated, service_role;
grant execute on function private.commit_sale_payload_matches(uuid, uuid, jsonb) to postgres;
