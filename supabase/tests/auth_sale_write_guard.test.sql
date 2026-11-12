begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(6);

create temporary table fx as
select
  (select id from auth.users where email = 'cashier@example.com') as cashier_id,
  (select id from auth.users where email = 'manager@example.com') as manager_id,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid as store_id,
  (
    select id from public.product_variants where stock_qty >= 2 order by sku limit 1
  ) as variant_id,
  (
    select price_pesewas from public.product_variants where stock_qty >= 2 order by sku limit 1
  ) as shelf_price;

grant select on fx to authenticated;

select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', cashier_id, 'role', 'authenticated')::text from fx),
  true
);
set local role authenticated;

select throws_ok(
  $$
    insert into public.sales (
      id, receipt_no, store_id, cashier_id, status,
      subtotal_pesewas, total_pesewas, tendered_pesewas, change_pesewas, credit_applied_pesewas
    )
    values (
      'a0a0a0a0-a0a0-40a0-80a0-a0a0a0a0a0a0',
      'DIRECT',
      (select store_id from fx),
      (select cashier_id from fx),
      'open',
      100, 100, 100, 0, 0
    )
  $$,
  '42501',
  null,
  'cashier cannot insert sales directly'
);

select lives_ok(
  $$
    select public.commit_sale(
      'e0e0e0e0-e0e0-40e0-80e0-e0e0e0e0e0e0'::uuid,
      (select store_id from fx),
      jsonb_build_array(
        jsonb_build_object(
          'id', 'e1e1e1e1-e1e1-41e1-81e1-e1e1e1e1e1e1',
          'variant_id', (select variant_id from fx),
          'quantity', 1,
          'unit_price_pesewas', (select shelf_price from fx)
        )
      )
    )
  $$,
  'commit_sale still works for cashiers'
);

reset role;

insert into public.sales (
  id, receipt_no, store_id, cashier_id, status,
  subtotal_pesewas, total_pesewas, tendered_pesewas, change_pesewas, credit_applied_pesewas
)
select
  'f0f0f0f0-f0f0-40f0-80f0-f0f0f0f0f0f0',
  'GUC-PROBE',
  store_id,
  cashier_id,
  'open',
  100, 100, 100, 0, 0
from fx;

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
set local role authenticated;

select set_config('private.commit_sale_completing', '1', true);

create or replace function pg_temp.cashier_try_complete_with_forged_guc() returns integer
language plpgsql
as $$
declare
  rows_updated integer;
begin
  update public.sales
  set status = 'completed'
  where id = 'f0f0f0f0-f0f0-40f0-80f0-f0f0f0f0f0f0'::uuid;
  get diagnostics rows_updated = row_count;
  return rows_updated;
end;
$$;

select is(
  pg_temp.cashier_try_complete_with_forged_guc(),
  0,
  'forged commit_sale_completing GUC leaves direct complete at zero rows'
);

select is(
  (select status from public.sales where id = 'f0f0f0f0-f0f0-40f0-80f0-f0f0f0f0f0f0'::uuid),
  'open',
  'forged GUC leaves the probe sale open'
);

select lives_ok(
  $$
    select public.commit_sale(
      'f2f2f2f2-f2f2-42f2-82f2-f2f2f2f2f2f2'::uuid,
      (select store_id from fx),
      jsonb_build_array(
        jsonb_build_object(
          'id', 'f3f3f3f3-f3f3-43f3-83f3-f3f3f3f3f3f3',
          'variant_id', (select variant_id from fx),
          'quantity', 1,
          'unit_price_pesewas', (select shelf_price from fx)
        )
      )
    )
  $$,
  'commit_sale still completes after a forged GUC attempt'
);

reset role;

insert into public.sales (
  id, receipt_no, store_id, cashier_id, status,
  subtotal_pesewas, total_pesewas, tendered_pesewas, change_pesewas, credit_applied_pesewas
)
select
  'b0b0b0b0-b0b0-40b0-80b0-b0b0b0b0b0b0',
  'TRIGGER',
  store_id,
  cashier_id,
  'open',
  100, 100, 100, 0, 0
from fx;

reset role;
select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', manager_id, 'role', 'authenticated')::text from fx),
  true
);
set local role authenticated;

select throws_ok(
  $$
    update public.sales
    set store_id = '00000000-0000-4000-8000-000000000001'::uuid
    where id = 'b0b0b0b0-b0b0-40b0-80b0-b0b0b0b0b0b0'
  $$,
  '42501',
  NULL,
  'store_id cannot be changed by a manager (privilege or trigger)'
);

select throws_ok(
  $$
    update public.sales
    set status = 'open'
    where id = 'e0e0e0e0-e0e0-40e0-80e0-e0e0e0e0e0e0'::uuid
  $$,
  '42501',
  'a sale can only be completed from open, or voided',
  'manager cannot rewind a completed sale at trigger level'
);

select * from finish();
rollback;
