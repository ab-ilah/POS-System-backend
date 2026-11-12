begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(1);

create temporary table fx as
select
  (select id from auth.users where email = 'cashier@example.com') as cashier_id;

insert into public.sales (
  id, receipt_no, store_id, cashier_id, status,
  subtotal_pesewas, total_pesewas, tendered_pesewas, change_pesewas, credit_applied_pesewas
)
select
  'a8a8a8a8-a8a8-48a8-88a8-a8a8a8a8a8a8'::uuid,
  'FORGE-CASHIER',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
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
select set_config('private.commit_sale_completing', '1', true);

select throws_ok(
  $$
    update public.sales as s
    set status = 'completed'
    where s.id = 'a8a8a8a8-a8a8-48a8-88a8-a8a8a8a8a8a8'::uuid
  $$,
  '42501',
  'sales can only be completed through commit_sale',
  'cashier JWT session cannot complete without a completion token even with a forged GUC'
);

select * from finish();
rollback;
