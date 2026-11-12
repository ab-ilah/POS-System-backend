begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(10);

-- Allowlist reasons: migration 20261112200000_pos_auth_hardening_e.sql (re-grant block).

select is_empty(
  $$
    select p.oid::regprocedure::text
    from pg_proc as p
    inner join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and pg_catalog.has_function_privilege('public', p.oid, 'execute')
    order by 1
  $$,
  'no private function is executable by PUBLIC'
);

select is_empty(
  $$
    select p.oid::regprocedure::text
    from pg_proc as p
    inner join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and pg_catalog.has_function_privilege('anon', p.oid, 'execute')
    order by 1
  $$,
  'no private function is executable by anon'
);

select is(
  has_function_privilege('authenticated', 'private.app_role_of(uuid)', 'execute'),
  false,
  'authenticated cannot execute app_role_of'
);

select is(
  has_function_privilege('authenticated', 'private.session_staff_app_role()', 'execute'),
  false,
  'authenticated cannot execute session_staff_app_role'
);

select bag_eq(
  $$
    select p.oid::regprocedure::text
    from pg_proc as p
    inner join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and pg_catalog.has_function_privilege('authenticated', p.oid, 'execute')
    order by 1
  $$,
  $$
    values
      ('private.caller_may_update_profile(uuid)'::text),
      ('private.current_app_role()'::text),
      ('private.session_is_authenticated_staff()'::text),
      ('private.session_is_trusted_db()'::text),
      ('private.target_is_owner(uuid)'::text),
      ('private.touch_updated_at()'::text),
      ('private.write_staff_role(uuid,app_role)'::text)
    order by 1
  $$,
  'authenticated private EXECUTE matches the allowlist'
);

select is(
  has_function_privilege('authenticated', 'public.commit_sale(uuid,uuid,jsonb)', 'execute'),
  true,
  'commit_sale granted to authenticated'
);

select is(
  has_function_privilege('authenticated', 'public.my_role()', 'execute'),
  true,
  'my_role granted to authenticated'
);

select is(
  has_function_privilege('authenticated', 'public.assign_staff_role(uuid,public.app_role)', 'execute'),
  true,
  'assign_staff_role granted to authenticated'
);

select is(
  has_function_privilege('service_role', 'public.consume_staff_invite_slot(uuid)', 'execute'),
  true,
  'consume_staff_invite_slot granted to service_role'
);

select is(
  has_function_privilege('service_role', 'public.assign_staff_role(uuid,public.app_role)', 'execute'),
  false,
  'assign_staff_role is not granted to service_role'
);

select * from finish();
rollback;
