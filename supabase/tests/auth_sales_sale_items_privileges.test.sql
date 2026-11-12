begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(14);

select ok(
  not has_table_privilege('service_role', 'public.sales', 'INSERT'),
  'service_role cannot insert sales'
);
select ok(
  not has_table_privilege('service_role', 'public.sales', 'UPDATE'),
  'service_role cannot update sales'
);
select ok(
  not has_table_privilege('service_role', 'public.sales', 'DELETE'),
  'service_role cannot delete sales'
);
select ok(
  has_table_privilege('service_role', 'public.sales', 'SELECT'),
  'service_role can still select sales'
);

select ok(
  not has_table_privilege('service_role', 'public.sale_items', 'INSERT'),
  'service_role cannot insert sale_items'
);
select ok(
  not has_table_privilege('service_role', 'public.sale_items', 'UPDATE'),
  'service_role cannot update sale_items'
);
select ok(
  not has_table_privilege('service_role', 'public.sale_items', 'DELETE'),
  'service_role cannot delete sale_items'
);
select ok(
  has_table_privilege('service_role', 'public.sale_items', 'SELECT'),
  'service_role can still select sale_items'
);

select ok(
  not has_table_privilege('authenticated', 'public.sales', 'INSERT'),
  'authenticated cannot insert sales'
);
select ok(
  not has_table_privilege('authenticated', 'public.sales', 'DELETE'),
  'authenticated cannot delete sales'
);
select ok(
  has_column_privilege('authenticated', 'public.sales', 'status', 'UPDATE'),
  'authenticated retains column update on sales.status for void path'
);

select ok(
  not has_table_privilege('authenticated', 'public.sale_items', 'INSERT'),
  'authenticated cannot insert sale_items'
);
select ok(
  not has_table_privilege('authenticated', 'public.sale_items', 'UPDATE'),
  'authenticated cannot update sale_items'
);
select ok(
  not has_table_privilege('authenticated', 'public.sale_items', 'DELETE'),
  'authenticated cannot delete sale_items'
);

select * from finish();
rollback;
