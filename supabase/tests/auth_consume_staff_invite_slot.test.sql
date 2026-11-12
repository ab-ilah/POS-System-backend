begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(7);

select set_config('test.manager', (select id::text from auth.users where email = 'manager@example.com'), true);
select set_config('test.cashier', (select id::text from auth.users where email = 'cashier@example.com'), true);

select ok(
  not has_function_privilege('anon', 'public.consume_staff_invite_slot(uuid)', 'EXECUTE'),
  'anon cannot execute public.consume_staff_invite_slot'
);
select ok(
  not has_function_privilege('authenticated', 'public.consume_staff_invite_slot(uuid)', 'EXECUTE'),
  'authenticated cannot execute public.consume_staff_invite_slot'
);
select ok(
  not has_function_privilege('anon', 'private.consume_staff_invite_slot(uuid)', 'EXECUTE'),
  'anon cannot execute private.consume_staff_invite_slot'
);

select set_config(
  'request.jwt.claims',
  json_build_object('role', 'service_role')::text,
  true
);
set local role service_role;

select throws_ok(
  format(
    $$ select public.consume_staff_invite_slot(%L::uuid) $$,
    'aaaaaaaa-aaaa-4000-8000-000000000099'
  ),
  '42501',
  null,
  'random uuid caller is rejected'
);

select throws_ok(
  format(
    $$ select public.consume_staff_invite_slot(%L::uuid) $$,
    current_setting('test.cashier')
  ),
  '42501',
  null,
  'cashier caller is rejected'
);

select lives_ok(
  format(
    $$ select public.consume_staff_invite_slot(%L::uuid) $$,
    current_setting('test.manager')
  ),
  'manager caller passes gate once'
);

do $$
declare
  i integer;
  mid uuid := current_setting('test.manager')::uuid;
begin
  for i in 2..10 loop
    perform public.consume_staff_invite_slot(mid);
  end loop;
end;
$$;

select throws_ok(
  format(
    $$ select public.consume_staff_invite_slot(%L::uuid) $$,
    current_setting('test.manager')
  ),
  'P0004',
  null,
  'eleventh invite in the same hour is rate limited'
);

select * from finish();
rollback;
