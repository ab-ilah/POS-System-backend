begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(9);

select set_config('test.owner', (select id::text from auth.users where email = 'owner@example.com'), true);
select set_config('test.manager', (select id::text from auth.users where email = 'manager@example.com'), true);
select set_config('test.cashier', (select id::text from auth.users where email = 'cashier@example.com'), true);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current, phone_change, phone_change_token, reauthentication_token
)
values (
  '00000000-0000-0000-0000-000000000000',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'authenticated',
  'authenticated',
  'spare@example.com',
  extensions.crypt('local-dev-only', extensions.gen_salt('bf')),
  now(),
  '{"role":"cashier"}',
  '{"full_name":"Spare"}',
  now(), now(),
  '', '', '', '', '', '', '', ''
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', current_setting('test.owner'), 'role', 'authenticated')::text,
  true
);
set local role authenticated;

select throws_ok(
  format(
    $$ select public.assign_staff_role(%L::uuid, 'owner'::public.app_role) $$,
    current_setting('test.cashier')
  ),
  '42501',
  'the owner role cannot be assigned here',
  'owner cannot assign the owner role'
);

select throws_ok(
  format(
    $$ select public.assign_staff_role(%L::uuid, 'owner'::public.app_role) $$,
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  ),
  '42501',
  'the owner role cannot be assigned here',
  'owner cannot promote staff to owner'
);

select throws_ok(
  format(
    $$ select public.assign_staff_role(%L::uuid, 'cashier'::public.app_role) $$,
    current_setting('test.owner')
  ),
  '42501',
  'the owner cannot be reassigned',
  'owner cannot demote the sole owner'
);

delete from public.profiles where id = current_setting('test.owner')::uuid;

select ok(
  exists (
    select 1 from public.profiles where id = current_setting('test.owner')::uuid
  ),
  'owner profile cannot be deleted'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', current_setting('test.manager'), 'role', 'authenticated')::text,
  true
);

select throws_ok(
  format(
    $$ select public.assign_staff_role(%L::uuid, 'owner'::public.app_role) $$,
    current_setting('test.cashier')
  ),
  '42501',
  'the owner role cannot be assigned here',
  'manager cannot assign the owner role'
);

select throws_ok(
  format(
    $$ select public.assign_staff_role(%L::uuid, 'cashier'::public.app_role) $$,
    current_setting('test.owner')
  ),
  '42501',
  'the owner cannot be reassigned',
  'manager cannot demote the owner'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', current_setting('test.owner'), 'role', 'authenticated')::text,
  true
);
set local role authenticated;

select lives_ok(
  format(
    $$ select public.assign_staff_role(%L::uuid, 'manager'::public.app_role) $$,
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  ),
  'owner can still promote cashier to manager'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', current_setting('test.manager'), 'role', 'authenticated')::text,
  true
);

select lives_ok(
  format(
    $$ select public.assign_staff_role(%L::uuid, 'cashier'::public.app_role) $$,
    current_setting('test.cashier')
  ),
  'manager can still assign cashier'
);

reset role;

select is(
  (select raw_app_meta_data ->> 'role' from auth.users where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  'manager',
  'promotion persisted'
);

select * from finish();
rollback;