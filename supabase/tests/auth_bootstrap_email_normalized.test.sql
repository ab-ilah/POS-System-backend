begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(2);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current, phone_change, phone_change_token, reauthentication_token
)
values (
  '00000000-0000-0000-0000-000000000000',
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
  'authenticated',
  'authenticated',
  'a@x.com',
  extensions.crypt('local-dev-only', extensions.gen_salt('bf')),
  now(),
  '{}',
  '{}',
  now(), now(),
  '', '', '', '', '', '', '', ''
);

update auth.users
set raw_app_meta_data = raw_app_meta_data - 'role'
where email = 'owner@example.com';

update private.bootstrap_state
set owner_bootstrapped_at = null;

select lives_ok(
  $$ select private.bootstrap_first_owner('  A@X.com ') $$,
  'bootstrap_first_owner matches trimmed and case-normalized email'
);

select is(
  (
    select raw_app_meta_data ->> 'role'
    from auth.users
    where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
  ),
  'owner',
  'bootstrap assigns owner to the lowercased address row'
);

select * from finish();
rollback;
