begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(9);

select set_config('test.owner', (select id::text from auth.users where email = 'owner@example.com'), true);
select set_config('test.manager', (select id::text from auth.users where email = 'manager@example.com'), true);
select set_config('test.cashier', (select id::text from auth.users where email = 'cashier@example.com'), true);

insert into private.staff_invite_buckets (caller_id, bucket_start, invite_count)
values (
  current_setting('test.owner')::uuid,
  date_trunc('hour', now()),
  4
);

select ok(
  not has_function_privilege('anon', 'public.consume_staff_invite_slot()', 'EXECUTE'),
  'anon cannot execute public.consume_staff_invite_slot'
);
select ok(
  has_function_privilege('authenticated', 'public.consume_staff_invite_slot()', 'EXECUTE'),
  'authenticated can execute public.consume_staff_invite_slot'
);
select ok(
  not has_function_privilege('service_role', 'public.consume_staff_invite_slot()', 'EXECUTE'),
  'service_role cannot execute public.consume_staff_invite_slot'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', current_setting('test.cashier'), 'role', 'authenticated')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$ select public.consume_staff_invite_slot() $$,
  '42501',
  null,
  'cashier cannot consume an invite slot'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', current_setting('test.manager'), 'role', 'authenticated')::text,
  true
);

select lives_ok(
  $$ select public.consume_staff_invite_slot() $$,
  'manager consumes one slot from own bucket'
);

reset role;

select is(
  (
    select invite_count
    from private.staff_invite_buckets
    where caller_id = current_setting('test.manager')::uuid
      and bucket_start = date_trunc('hour', now())
  ),
  1,
  'manager bucket count is one'
);

reset role;

select is(
  (
    select invite_count
    from private.staff_invite_buckets
    where caller_id = current_setting('test.owner')::uuid
      and bucket_start = date_trunc('hour', now())
  ),
  4,
  'owner bucket count unchanged while manager invites'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', current_setting('test.manager'), 'role', 'authenticated')::text,
  true
);
set local role authenticated;

select lives_ok(
  $$ select public.consume_staff_invite_slot() $$,
  'second manager consume touches only manager bucket'
);

do $$
declare
  i integer;
begin
  for i in 3..10 loop
    perform public.consume_staff_invite_slot();
  end loop;
end;
$$;

select throws_ok(
  $$ select public.consume_staff_invite_slot() $$,
  'P0004',
  null,
  'eleventh manager invite in the same hour is rate limited'
);

select * from finish();
rollback;