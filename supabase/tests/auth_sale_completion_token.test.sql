begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(6);

create temporary table fx as
select
  (select id from auth.users where email = 'cashier@example.com') as cashier_id,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid as store_id,
  (
    select id from public.product_variants where stock_qty >= 2 order by sku limit 1
  ) as variant_id,
  (
    select price_pesewas from public.product_variants where stock_qty >= 2 order by sku limit 1
  ) as shelf_price;

grant select on fx to authenticated;

create or replace function private.pgtap_forge_guc_and_complete(p_sale_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_catalog.set_config('private.commit_sale_completing', '1', true);
  update public.sales as s
  set status = 'completed'
  where s.id = p_sale_id;
end;
$$;

revoke all on function private.pgtap_forge_guc_and_complete(uuid) from public, anon, authenticated, service_role;
grant execute on function private.pgtap_forge_guc_and_complete(uuid) to postgres;

insert into public.sales (
  id, receipt_no, store_id, cashier_id, status,
  subtotal_pesewas, total_pesewas, tendered_pesewas, change_pesewas, credit_applied_pesewas
)
select
  'c0c0c0c0-c0c0-40c0-80c0-c0c0c0c0c0c0'::uuid,
  'GUC-FORGE',
  store_id,
  cashier_id,
  'open',
  100, 100, 100, 0, 0
from fx;

select throws_ok(
  $$
    select private.pgtap_forge_guc_and_complete('c0c0c0c0-c0c0-40c0-80c0-c0c0c0c0c0c0'::uuid)
  $$,
  '42501',
  null,
  'definer GUC forge cannot complete a sale'
);

insert into public.sales (
  id, receipt_no, store_id, cashier_id, status,
  subtotal_pesewas, total_pesewas, tendered_pesewas, change_pesewas, credit_applied_pesewas
)
select
  'c1c1c1c1-c1c1-41c1-81c1-c1c1c1c1c1c1'::uuid,
  'CASHIER-FORGE',
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

select is(
  (
    update public.sales as s
    set status = 'completed'
    where s.id = 'c1c1c1c1-c1c1-41c1-81c1-c1c1c1c1c1c1'::uuid
    returning 1
  ),
  null,
  'cashier forged GUC cannot complete sale directly (RLS blocks update)'
);

select is(
  (select s.status from public.sales as s where s.id = 'c1c1c1c1-c1c1-41c1-81c1-c1c1c1c1c1c1'::uuid),
  'open',
  'forged GUC probe sale stays open'
);

reset role;

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

select lives_ok(
  $$
    select public.commit_sale(
      'c2c2c2c2-c2c2-42c2-82c2-c2c2c2c2c2c2'::uuid,
      (select store_id from fx),
      jsonb_build_array(
        jsonb_build_object(
          'id', 'c3c3c3c3-c3c3-43c3-83c3-c3c3c3c3c3c3',
          'variant_id', (select variant_id from fx),
          'quantity', 1,
          'unit_price_pesewas', (select shelf_price from fx)
        )
      )
    )
  $$,
  'commit_sale completes over authenticated'
);

reset role;

select is_empty(
  $$ select 1 from private.sale_completion_tokens where sale_id = 'c2c2c2c2-c2c2-42c2-82c2-c2c2c2c2c2c2'::uuid $$,
  'completion token row is consumed'
);

insert into public.sales (
  id, receipt_no, store_id, cashier_id, status,
  subtotal_pesewas, total_pesewas, tendered_pesewas, change_pesewas, credit_applied_pesewas
)
select
  'c4c4c4c4-c4c4-44c4-84c4-c4c4c4c4c4c4'::uuid,
  'WRONG-TXID',
  store_id,
  cashier_id,
  'open',
  100, 100, 100, 0, 0
from fx;

insert into private.sale_completion_tokens (sale_id, txid)
values ('c4c4c4c4-c4c4-44c4-84c4-c4c4c4c4c4c4'::uuid, 0);

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

select throws_ok(
  $$
    update public.sales as s
    set status = 'completed'
    where s.id = 'c4c4c4c4-c4c4-44c4-84c4-c4c4c4c4c4c4'::uuid
  $$,
  '42501',
  null,
  'stale txid token does not unlock completion'
);

select * from finish();
rollback;
