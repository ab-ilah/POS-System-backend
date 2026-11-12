begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(6);

select throws_ok(
  $$ select private.bootstrap_first_owner('owner@example.com') $$,
  '42501',
  'owner already bootstrapped',
  'refuses while an owner exists'
);

update auth.users
set raw_app_meta_data = raw_app_meta_data - 'role'
where email = 'owner@example.com';

select lives_ok(
  $$ select private.bootstrap_first_owner('owner@example.com') $$,
  'bootstraps when no owner'
);
select is(
  (select raw_app_meta_data ->> 'role' from auth.users where email = 'owner@example.com'),
  'owner',
  'role written to app_metadata'
);

update auth.users
set raw_app_meta_data = raw_app_meta_data - 'role'
where email = 'owner@example.com';

select throws_ok(
  $$ select private.bootstrap_first_owner('owner@example.com') $$,
  '42501',
  'owner already bootstrapped',
  'latch blocks reuse even with no owner'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current, phone_change, phone_change_token, reauthentication_token
)
values (
  '00000000-0000-0000-0000-000000000000',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'authenticated',
  'authenticated',
  'stranger@example.com',
  extensions.crypt('local-dev-only', extensions.gen_salt('bf')),
  now(),
  '{}',
  '{"full_name":"Kofi (new cashier)"}',
  now(), now(),
  '', '', '', '', '', '', '', ''
);

select set_config(
  'request.jwt.claims',
  '{"sub":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","role":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$ select private.bootstrap_first_owner('stranger@example.com') $$,
  '42501',
  null,
  'authenticated cannot call bootstrap'
);
select is_empty(
  $$ select 1 from public.customers union all select 1 from public.sales $$,
  'role-less signed-up user sees nothing'
);

select * from finish();
rollback;
