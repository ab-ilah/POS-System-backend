begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(8);

insert into public.sales (
  store_id,
  id, receipt_no, cashier_id, status,
  subtotal_pesewas, total_pesewas, tendered_pesewas, change_pesewas, credit_applied_pesewas
)
select
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
  id, receipt_no, cashier_id, 'open', 1000, 1000, 1000, 0, 0
from (
  values
    ('77777777-7777-4777-8777-777777777771'::uuid, 'PGTAP-MOVE-OPEN'),
    ('77777777-7777-4777-8777-777777777772'::uuid, 'PGTAP-MOVE-VOID'),
    ('77777777-7777-4777-8777-777777777773'::uuid, 'PGTAP-MOVE-OPEN-2')
) as sale(id, receipt_no)
cross join lateral (
  select id as cashier_id from auth.users where email = 'cashier@example.com'
) as cashier;

insert into public.sale_lines (
  id, sale_id, variant_id, product_name, size_name, colour_name,
  quantity, unit_price_pesewas, line_total_pesewas
)
select
  item_id, sale_id, variant.id, 'Probe', 'M', 'Black', 1, 1000, 1000
from (
  values
    ('77777777-7777-4777-8777-777777777781'::uuid, '77777777-7777-4777-8777-777777777771'::uuid),
    ('77777777-7777-4777-8777-777777777782'::uuid, '77777777-7777-4777-8777-777777777772'::uuid)
) as item(item_id, sale_id)
cross join lateral (
  select id from public.product_variants limit 1
) as variant;

update public.sales
set status = 'voided', void_reason = 'pgTAP void', voided_at = now()
where id = '77777777-7777-4777-8777-777777777772';

select throws_ok(
  $$
    delete from public.sale_lines
    where sale_id in (select id from public.sales where status = 'completed')
  $$,
  '42501',
  'cannot change lines on a finished sale',
  'a completed sale rejects a line delete'
);

select throws_ok(
  $$
    delete from public.sale_lines
    where id = '77777777-7777-4777-8777-777777777782'
  $$,
  '42501',
  'cannot change lines on a finished sale',
  'a voided sale rejects a line delete'
);

select throws_ok(
  $$
    update public.sale_lines
    set sale_id = '77777777-7777-4777-8777-777777777771'
    where sale_id in (select id from public.sales where status = 'completed')
  $$,
  '42501',
  'cannot change lines on a finished sale',
  'a line cannot move off a completed sale onto an open sale'
);

select throws_ok(
  $$
    update public.sale_lines
    set sale_id = (select id from public.sales where status = 'completed' limit 1)
    where id = '77777777-7777-4777-8777-777777777781'
  $$,
  '42501',
  'cannot change lines on a finished sale',
  'a line cannot move from an open sale onto a completed sale'
);

set local role service_role;

select throws_ok(
  $$
    delete from public.sale_lines
    where sale_id in (select id from public.sales where status = 'completed')
  $$,
  '42501',
  'cannot change lines on a finished sale',
  'service_role cannot delete a line from a finished sale'
);

select throws_ok(
  $$
    update public.sale_lines
    set sale_id = '77777777-7777-4777-8777-777777777771'
    where id = '77777777-7777-4777-8777-777777777782'
  $$,
  '42501',
  'cannot change lines on a finished sale',
  'service_role cannot move a line off a voided sale'
);

select lives_ok(
  $$
    update public.sale_lines
    set sale_id = '77777777-7777-4777-8777-777777777773'
    where id = '77777777-7777-4777-8777-777777777781'
  $$,
  'service_role can move a line between two open sales'
);

select lives_ok(
  $$
    delete from public.sale_lines
    where id = '77777777-7777-4777-8777-777777777781'
  $$,
  'service_role can delete a line from an open sale'
);

select * from finish();

rollback;
