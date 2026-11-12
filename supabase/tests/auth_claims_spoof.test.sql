begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(4);

create temporary table fx as
select (select id from auth.users where email = 'cashier@example.com') as cashier_id;

grant select on fx to authenticated;

update auth.users
set raw_user_meta_data = coalesce(raw_user_meta_data, '{}') || '{"role":"owner"}'
where id = (select cashier_id from fx);

select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', (select cashier_id from fx),
    'role', 'authenticated',
    'app_metadata', json_build_object('role', 'owner'),
    'user_metadata', json_build_object('role', 'owner')
  )::text,
  true
);
set local role authenticated;

select is(public.my_role(), 'cashier'::public.app_role, 'claims and user_metadata are ignored');
select throws_ok(
  $$ insert into public.products (name, category) values ('x', 'shirts') $$,
  '42501',
  null,
  'spoofed owner claim cannot write products'
);

reset role;

select is_empty(
  $$
    select p.oid::regprocedure
    from pg_proc as p
    join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname in ('public', 'graphql_public')
      and p.prosrc ~* '(set_config|\mexecute\M\s)'
  $$,
  'no exposed function calls set_config or dynamic EXECUTE'
);
select is_empty(
  $$
    select p.oid::regprocedure
    from pg_proc as p
    join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and not exists (
        select 1 from unnest(p.proconfig) as c where c like 'search_path=%'
      )
  $$,
  'every public SECURITY DEFINER pins search_path'
);

select * from finish();
rollback;
