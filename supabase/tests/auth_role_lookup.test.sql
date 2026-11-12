begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(9);

create temporary table fx as
select
  (select id from auth.users where email = 'owner@example.com') as owner_id,
  (select id from auth.users where email = 'manager@example.com') as manager_id,
  (select id from auth.users where email = 'cashier@example.com') as cashier_id;

grant select on fx to authenticated;

select is(
  has_function_privilege('authenticated', 'private.app_role_of(uuid)', 'execute'),
  false,
  'authenticated cannot execute app_role_of'
);
select is(
  has_function_privilege('anon', 'private.app_role_of(uuid)', 'execute'),
  false,
  'anon cannot execute app_role_of'
);
select is(
  has_function_privilege('public', 'private.app_role_of(uuid)', 'execute'),
  false,
  'PUBLIC cannot execute app_role_of'
);
select hasnt_function('private', 'staff_role', array['uuid'], 'staff_role removed');

select set_config(
  'request.jwt.claims',
  json_build_object('sub', (select cashier_id from fx), 'role', 'authenticated')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$ select private.app_role_of((select owner_id from fx)) $$,
  '42501',
  null,
  'cashier cannot look up another role'
);
select is(public.my_role(), 'cashier'::public.app_role, 'cashier resolves own role');
select is(
  private.target_is_owner((select owner_id from fx)),
  null::boolean,
  'cashier gets no owner oracle'
);
select isnt_empty($$ select 1 from public.products $$, 'RLS still works for cashier after rewrite');

reset role;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', (select manager_id from fx), 'role', 'authenticated')::text,
  true
);
set local role authenticated;

select throws_ok(
  $$ select public.assign_staff_role((select owner_id from fx), 'cashier') $$,
  '42501',
  null,
  'manager still cannot demote owner'
);

select * from finish();
rollback;
