begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(2);

insert into public.sales (
  id,
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
  '99999999-9999-4999-8999-999999999999',
  'PGTAP-FROZEN-VOID',
  id,
  'voided',
  'original reason',
  timestamptz '2026-01-01 00:00:00+00',
  1000,
  1000,
  1000,
  0,
  0
from auth.users
where email = 'cashier@example.com';

select throws_ok(
  $$
    update public.sales
    set void_reason = 'rewritten reason'
    where id = '99999999-9999-4999-8999-999999999999'
  $$,
  '42501',
  'a voided sale is frozen',
  'void_reason cannot change after the sale is voided'
);

select throws_ok(
  $$
    update public.sales
    set voided_at = now()
    where id = '99999999-9999-4999-8999-999999999999'
  $$,
  '42501',
  'a voided sale is frozen',
  'voided_at cannot change after the sale is voided'
);

select * from finish();

rollback;
