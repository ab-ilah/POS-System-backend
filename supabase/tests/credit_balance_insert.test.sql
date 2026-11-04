begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(7);

select set_config('test.owner', (select id::text from auth.users where email = 'owner@example.com'), true);
select set_config('test.manager', (select id::text from auth.users where email = 'manager@example.com'), true);
select set_config('test.cashier', (select id::text from auth.users where email = 'cashier@example.com'), true);

select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.cashier'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', current_setting('test.cashier'), true);
set local role authenticated;

select lives_ok(
  $$
    insert into public.customers (full_name, phone, credit_balance_pesewas)
    values ('pgTAP cashier zero', '0200000101', 0)
  $$,
  'a cashier can insert a customer at zero credit'
);

select throws_ok(
  $$
    insert into public.customers (full_name, phone, credit_balance_pesewas)
    values ('pgTAP cashier debt', '0200000102', 500)
  $$,
  '42501',
  'only the owner can set a credit balance',
  'a cashier cannot insert a customer with a credit balance'
);

reset role;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.manager'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', current_setting('test.manager'), true);
set local role authenticated;

select throws_ok(
  $$
    insert into public.customers (full_name, phone, credit_balance_pesewas)
    values ('pgTAP manager debt', '0200000103', 500)
  $$,
  '42501',
  'only the owner can set a credit balance',
  'a manager cannot insert a customer with a credit balance'
);

reset role;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.owner'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', current_setting('test.owner'), true);
set local role authenticated;

select lives_ok(
  $$
    insert into public.customers (full_name, phone, credit_balance_pesewas)
    values ('pgTAP owner debt', '0200000104', 500)
  $$,
  'the owner can insert a customer with a credit balance'
);

reset role;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.cashier'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', current_setting('test.cashier'), true);
set local role authenticated;

select throws_ok(
  $$
    update public.customers
    set credit_balance_pesewas = credit_balance_pesewas + 1
    where full_name = 'Akosua Mensah'
  $$,
  '42501',
  'only the owner can set a credit balance',
  'a cashier cannot change a credit balance'
);

reset role;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.manager'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', current_setting('test.manager'), true);
set local role authenticated;

select throws_ok(
  $$
    update public.customers
    set credit_balance_pesewas = credit_balance_pesewas + 1
    where full_name = 'Akosua Mensah'
  $$,
  '42501',
  'only the owner can set a credit balance',
  'a manager cannot change a credit balance'
);

reset role;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.owner'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', current_setting('test.owner'), true);
set local role authenticated;

select lives_ok(
  $$
    update public.customers
    set credit_balance_pesewas = credit_balance_pesewas + 1
    where full_name = 'Akosua Mensah'
  $$,
  'the owner can write a credit balance'
);

select * from finish();

rollback;
