begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(12);

select set_config('test.owner', (select id::text from auth.users where email = 'owner@example.com'), true);
select set_config('test.manager', (select id::text from auth.users where email = 'manager@example.com'), true);
select set_config('test.cashier', (select id::text from auth.users where email = 'cashier@example.com'), true);

insert into public.sales (
  store_id,
  id, receipt_no, cashier_id, status,
  subtotal_pesewas, total_pesewas, tendered_pesewas, change_pesewas, credit_applied_pesewas
)
select
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
  '66666666-6666-4666-8666-666666666661'::uuid,
  'PGTAP-ROLE-OPEN',
  id,
  'open',
  1000, 1000, 1000, 0, 0
from auth.users
where email = 'cashier@example.com';

select set_config(
  'request.jwt.claims',
  json_build_object('sub', current_setting('test.owner'), 'role', 'service_role')::text,
  true
);
select set_config('request.jwt.claim.sub', current_setting('test.owner'), true);
set local role service_role;

select throws_ok(
  $$
    insert into public.customers (full_name, phone, credit_balance_pesewas)
    values ('pgTAP service owner sub', '0200000301', 500)
  $$,
  '42501',
  'only the owner can set a credit balance',
  'service_role with the owner subject cannot insert a credit balance'
);

select throws_ok(
  $$
    update public.customers
    set credit_balance_pesewas = credit_balance_pesewas + 1
    where full_name = 'Akosua Mensah'
  $$,
  '42501',
  'only the owner can set a credit balance',
  'service_role with the owner subject cannot change a credit balance'
);

select set_config('app.seed', 'on', true);
set local app.seed = 'on';

select throws_ok(
  $$
    insert into public.customers (full_name, phone, credit_balance_pesewas)
    values ('pgTAP service seed flag', '0200000302', 500)
  $$,
  '42501',
  'only the owner can set a credit balance',
  'set_config app.seed has no effect for service_role'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', current_setting('test.owner'), 'role', 'authenticated')::text,
  true
);

select throws_ok(
  $$
    insert into public.customers (full_name, phone, credit_balance_pesewas)
    values ('pgTAP service forged jwt', '0200000303', 500)
  $$,
  '42501',
  'only the owner can set a credit balance',
  'a forged authenticated JWT role does not make service_role the owner'
);

select throws_ok(
  $$
    select public.assign_staff_role(current_setting('test.cashier')::uuid, 'manager')
  $$,
  '42501',
  'only an owner or manager can assign a staff role',
  'service_role cannot assign a staff role'
);

select throws_ok(
  $$
    update public.sales
    set status = 'completed'
    where id = '66666666-6666-4666-8666-666666666661'
  $$,
  '42501',
  'only an owner or manager can update a sale',
  'service_role cannot change a sale status'
);

reset role;
select set_config('app.seed', 'off', true);

select lives_ok(
  $$
    insert into public.customers (full_name, phone, credit_balance_pesewas)
    values ('pgTAP postgres debt', '0200000304', 500)
  $$,
  'a postgres session with no SET ROLE can set a credit balance'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', current_setting('test.owner'), 'role', 'authenticated')::text,
  true
);
select set_config('request.jwt.claim.sub', current_setting('test.owner'), true);
set local role authenticated;

select lives_ok(
  $$
    insert into public.customers (full_name, phone, credit_balance_pesewas)
    values ('pgTAP authenticated owner', '0200000305', 500)
  $$,
  'an authenticated owner can insert a credit balance'
);

reset role;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', current_setting('test.cashier'), 'role', 'authenticated')::text,
  true
);
select set_config('request.jwt.claim.sub', current_setting('test.cashier'), true);
set local role authenticated;

select throws_ok(
  $$
    insert into public.customers (full_name, phone, credit_balance_pesewas)
    values ('pgTAP authenticated cashier', '0200000306', 500)
  $$,
  '42501',
  'only the owner can set a credit balance',
  'an authenticated cashier cannot insert a credit balance'
);

select set_config('app.seed', 'on', true);
set local app.seed = 'on';

select throws_ok(
  $$
    insert into public.customers (full_name, phone, credit_balance_pesewas)
    values ('pgTAP cashier seed flag', '0200000307', 500)
  $$,
  '42501',
  'only the owner can set a credit balance',
  'set_config app.seed has no effect for an authenticated cashier'
);

reset role;
select set_config('app.seed', 'off', true);
select set_config(
  'request.jwt.claims',
  json_build_object('sub', current_setting('test.manager'), 'role', 'authenticated')::text,
  true
);
select set_config('request.jwt.claim.sub', current_setting('test.manager'), true);
set local role authenticated;

select throws_ok(
  $$
    insert into public.customers (full_name, phone, credit_balance_pesewas)
    values ('pgTAP authenticated manager', '0200000308', 500)
  $$,
  '42501',
  'only the owner can set a credit balance',
  'an authenticated manager cannot insert a credit balance'
);

select lives_ok(
  $$
    update public.sales
    set status = 'completed'
    where id = '66666666-6666-4666-8666-666666666661'
  $$,
  'an authenticated manager can complete an open sale'
);

select * from finish();

rollback;
