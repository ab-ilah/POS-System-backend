begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(3);

create temporary table fx as
select
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid as store_id,
  (select id from auth.users where email = 'cashier@example.com') as cashier_id,
  (select id from auth.users where email = 'owner@example.com') as owner_id,
  (select id from auth.users where email = 'manager@example.com') as manager_id,
  (
    select id
    from public.product_variants
    where stock_qty >= 2
    order by sku
    limit 1
  ) as variant_id,
  (
    select price_pesewas
    from public.product_variants
    where stock_qty >= 2
    order by sku
    limit 1
  ) as shelf_price;

grant select on fx to authenticated;

insert into public.sales (
  id, receipt_no, store_id, cashier_id, status,
  subtotal_pesewas, total_pesewas, tendered_pesewas, change_pesewas, credit_applied_pesewas
)
select
  'f5f5f5f5-f5f5-45f5-85f5-f5f5f5f5f5f5'::uuid,
  'NO-DIRECT',
  store_id,
  cashier_id,
  'open',
  100, 100, 100, 0, 0
from fx;

select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', owner_id, 'role', 'authenticated')::text from fx),
  true
);
select set_config(
  'request.jwt.claim.sub',
  (select owner_id::text from fx),
  true
);
set local role authenticated;

select throws_ok(
  $$
    update public.sales as s
    set status = 'completed'
    where s.id = 'f5f5f5f5-f5f5-45f5-85f5-f5f5f5f5f5f5'::uuid
  $$,
  '42501',
  null,
  'owner cannot complete an open sale by direct UPDATE'
);

select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', manager_id, 'role', 'authenticated')::text from fx),
  true
);
select set_config(
  'request.jwt.claim.sub',
  (select manager_id::text from fx),
  true
);

select throws_ok(
  $$
    update public.sales as s
    set status = 'completed'
    where s.id = 'f5f5f5f5-f5f5-45f5-85f5-f5f5f5f5f5f5'::uuid
  $$,
  '42501',
  null,
  'manager cannot complete an open sale by direct UPDATE'
);

select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', cashier_id, 'role', 'authenticated')::text from fx),
  true
);
select set_config(
  'request.jwt.claim.sub',
  (select cashier_id::text from fx),
  true
);

select lives_ok(
  $$
    select public.commit_sale(
      'f6f6f6f6-f6f6-46f6-86f6-f6f6f6f6f6f6'::uuid,
      (select store_id from fx),
      jsonb_build_array(
        jsonb_build_object(
          'id', 'f7f7f7f7-f7f7-47f7-87f7-f7f7f7f7f7f7',
          'variant_id', (select variant_id from fx),
          'quantity', 1,
          'unit_price_pesewas', (select shelf_price from fx)
        )
      )
    )
  $$,
  'commit_sale still completes over authenticated'
);

select * from finish();
rollback;
