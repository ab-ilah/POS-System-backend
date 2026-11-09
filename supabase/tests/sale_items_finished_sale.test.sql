begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(5);

create temporary table pgtap_ids as
select
  (select id from auth.users where email = 'cashier@example.com') as cashier_id,
  (select id from public.product_variants limit 1) as variant_id,
  (
    select id
    from public.sales
    where cashier_id = (select id from auth.users where email = 'cashier@example.com')
      and status = 'completed'
    limit 1
  ) as finished_sale_id;

insert into public.sales (
  store_id,
  receipt_no,
  cashier_id,
  status,
  void_reason,
  voided_at,
  subtotal_pesewas,
  total_pesewas,
  tendered_pesewas,
  change_pesewas,
  credit_applied_pesewas
)
select
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
  'PGTAP-VOID-' || gen_random_uuid()::text,
  cashier_id,
  'voided',
  'pgTAP void',
  now(),
  1000,
  1000,
  1000,
  0,
  0
from pgtap_ids;

select throws_ok(
  $$
    insert into public.sale_lines (
      sale_id, variant_id, product_name, size_name, colour_name,
      quantity, unit_price_pesewas, line_total_pesewas
    )
    select finished_sale_id, variant_id, 'Probe', 'M', 'Black', 1, 1000, 1000
    from pgtap_ids
  $$,
  '42501',
  'cannot change lines on a finished sale',
  'a completed sale rejects a new line'
);

select throws_ok(
  $$
    update public.sale_lines as item
    set product_name = item.product_name
    from public.sales as sale
    where sale.id = item.sale_id
      and sale.status = 'completed'
  $$,
  '42501',
  'cannot change lines on a finished sale',
  'a completed sale rejects a line edit'
);

select throws_ok(
  $$
    insert into public.sale_lines (
      sale_id, variant_id, product_name, size_name, colour_name,
      quantity, unit_price_pesewas, line_total_pesewas
    )
    select sale.id, ids.variant_id, 'Probe', 'M', 'Black', 1, 1000, 1000
    from public.sales as sale
    cross join pgtap_ids as ids
    where sale.receipt_no like 'PGTAP-VOID-%'
    limit 1
  $$,
  '42501',
  'cannot change lines on a finished sale',
  'a voided sale rejects a new line'
);

insert into public.sales (
  store_id,
  id,
  receipt_no,
  cashier_id,
  status,
  subtotal_pesewas,
  total_pesewas,
  tendered_pesewas,
  change_pesewas,
  credit_applied_pesewas
)
select
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
  '88888888-8888-4888-8888-888888888888'::uuid,
  'PGTAP-OPEN-1',
  cashier_id,
  'open',
  1000,
  1000,
  1000,
  0,
  0
from pgtap_ids;

grant select on table pgtap_ids to authenticated;

select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', cashier_id, 'role', 'authenticated')::text from pgtap_ids),
  true
);
select set_config(
  'request.jwt.claim.sub',
  (select cashier_id::text from pgtap_ids),
  true
);
set local role authenticated;

select throws_ok(
  $$
    insert into public.sale_lines (
      sale_id, variant_id, product_name, size_name, colour_name,
      quantity, unit_price_pesewas, line_total_pesewas
    )
    select finished_sale_id, variant_id, 'Probe', 'M', 'Black', 1, 1000, 1000
    from pgtap_ids
  $$,
  '42501',
  'cannot change lines on a finished sale',
  'a cashier cannot add a line to their own finished sale'
);

select lives_ok(
  $$
    insert into public.sale_lines (
      sale_id,
      variant_id,
      product_name,
      size_name,
      colour_name,
      quantity,
      unit_price_pesewas,
      line_total_pesewas
    )
    select
      '88888888-8888-4888-8888-888888888888',
      variant_id,
      'Probe',
      'M',
      'Black',
      1,
      1000,
      1000
    from pgtap_ids
  $$,
  'a cashier can add a line to their own open sale'
);

select * from finish();

rollback;
