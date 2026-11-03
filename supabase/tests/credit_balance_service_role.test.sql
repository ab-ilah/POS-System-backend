begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(4);

set local role service_role;

select throws_ok(
  $$
    insert into public.customers (full_name, phone, credit_balance_pesewas)
    values ('pgTAP service debt', '0200000201', 500)
  $$,
  '42501',
  'only the owner can set a credit balance',
  'service_role cannot insert a customer with a credit balance'
);

select throws_ok(
  $$
    update public.customers
    set credit_balance_pesewas = credit_balance_pesewas + 1
    where full_name = 'Akosua Mensah'
  $$,
  '42501',
  'only the owner can set a credit balance',
  'service_role cannot change a credit balance'
);

reset role;

select lives_ok(
  $$
    insert into public.customers (full_name, phone, credit_balance_pesewas)
    values ('pgTAP postgres debt', '0200000202', 500)
  $$,
  'a postgres session can set a credit balance for seed and migrations'
);

set local app.seed = 'on';
set local role service_role;

select lives_ok(
  $$
    insert into public.customers (full_name, phone, credit_balance_pesewas)
    values ('pgTAP seed flag debt', '0200000203', 500)
  $$,
  'the transaction-local app.seed flag can set a credit balance'
);

select * from finish();

rollback;
