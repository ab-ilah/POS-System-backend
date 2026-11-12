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

select throws_ok(
  $$
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change, email_change_token_new,
      email_change_token_current, phone_change, phone_change_token, reauthentication_token
    )
    values (
      '00000000-0000-0000-0000-000000000000',
      'ffffffff-ffff-4fff-8fff-ffffffffffff',
      'authenticated',
      'authenticated',
      'A@x.com',
      extensions.crypt('local-dev-only', extensions.gen_salt('bf')),
      now(),
      '{}',
      '{}',
      now(), now(),
      '', '', '', '', '', '', '', ''
    )
  $$,
  '23505',
  null,
  'inserting A@x.com after a@x.com violates case-insensitive uniqueness'
);

select * from finish();
rollback;
