begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(2);

-- Intentional anon EXECUTE on public schema functions: none (staff RPCs are authenticated-only).

select is_empty(
  $$
    select p.oid::regprocedure::text
    from pg_proc as p
    inner join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and pg_catalog.has_function_privilege('anon', p.oid, 'execute')
    order by 1
  $$,
  'no public function is executable by anon'
);

select is(
  has_function_privilege('anon', 'public.commit_sale(uuid,uuid,jsonb)', 'execute'),
  false,
  'commit_sale is not granted to anon'
);

select * from finish();
rollback;
