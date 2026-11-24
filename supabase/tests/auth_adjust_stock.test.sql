begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(23);

create temporary table fx as
select
  (select id from auth.users where email = 'owner@example.com') as owner_id,
  (select id from auth.users where email = 'manager@example.com') as manager_id,
  (select id from auth.users where email = 'cashier@example.com') as cashier_id,
  (
    select id
    from public.product_variants
    where stock_qty >= 5
    order by sku
    limit 1
  ) as variant_id,
  null::integer as starting_qty;

update fx
set starting_qty = (
  select stock_qty from public.product_variants where id = fx.variant_id
);

grant select on fx to authenticated;

select set_config('test.variant_id', (select variant_id::text from fx), true);
select set_config('test.owner_id', (select owner_id::text from fx), true);
select set_config('test.manager_id', (select manager_id::text from fx), true);
select set_config('test.cashier_id', (select cashier_id::text from fx), true);
select set_config('test.starting_qty', (select starting_qty::text from fx), true);

select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', current_setting('test.owner_id'),
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  current_setting('test.owner_id'),
  true
);
set local role authenticated;

select is(
  public.adjust_stock(
    (select variant_id from fx),
    2,
    '  cycle count  '
  ),
  (select starting_qty + 2 from fx),
  'owner adjust_stock returns the new stock_qty'
);

select ok(
  exists (
    select 1
    from public.stock_movements as m
    cross join fx as f
    where m.variant_id = f.variant_id
      and m.qty_delta = 2
      and m.sale_id is null
      and m.sale_item_id is null
      and m.reason = 'cycle count'
      and m.actor_id = f.owner_id
  ),
  'owner ledger row records actor, trimmed reason, and delta'
);

select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', manager_id, 'role', 'authenticated')::text from fx),
  true
);
select set_config(
  'request.jwt.claim.sub',
  (select manager_id::text from fx),
  true
);

select is(
  public.adjust_stock(
    (select variant_id from fx),
    -1,
    'shrinkage'
  ),
  (select starting_qty + 1 from fx),
  'manager adjust_stock succeeds'
);

select ok(
  exists (
    select 1
    from public.stock_movements as m
    cross join fx as f
    where m.variant_id = f.variant_id
      and m.qty_delta = -1
      and m.reason = 'shrinkage'
      and m.actor_id = f.manager_id
  ),
  'manager ledger row records manager as actor_id'
);

select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', cashier_id, 'role', 'authenticated')::text from fx),
  true
);
select set_config(
  'request.jwt.claim.sub',
  (select cashier_id::text from fx),
  true
);

select throws_ok(
  $$
    select public.adjust_stock(
      (select variant_id from fx),
      1,
      'cashier attempt'
    )
  $$,
  '42501',
  null,
  'cashier cannot adjust stock'
);

set local role anon;

select ok(
  not has_function_privilege('anon', 'public.adjust_stock(uuid, integer, text)', 'execute'),
  'anon cannot execute adjust_stock'
);

select throws_ok(
  format(
    $$ select public.adjust_stock(%L::uuid, 1, 'anon attempt') $$,
    current_setting('test.variant_id')
  ),
  '42501',
  null,
  'anon cannot adjust stock'
);

reset role;

select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', current_setting('test.owner_id'),
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  current_setting('test.owner_id'),
  true
);
set local role authenticated;

select throws_ok(
  $$
    select public.adjust_stock(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
      1,
      'missing variant'
    )
  $$,
  'P0002',
  null,
  'unknown variant raises P0002'
);

select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', owner_id)::text from fx),
  true
);

select throws_ok(
  $$
    select public.adjust_stock(
      (select variant_id from fx),
      1,
      'jwt role missing'
    )
  $$,
  '42501',
  null,
  'authenticated jwt without role claim is rejected'
);

select set_config(
  'request.jwt.claims',
  json_build_object('role', 'authenticated')::text,
  true
);
select set_config('request.jwt.claim.sub', '', true);

select throws_ok(
  $$
    select public.adjust_stock(
      (select variant_id from fx),
      1,
      'null uid'
    )
  $$,
  '42501',
  null,
  'authenticated caller without sub claim is rejected'
);

select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', owner_id, 'role', 'authenticated')::text from fx),
  true
);
select set_config(
  'request.jwt.claim.sub',
  (select owner_id::text from fx),
  true
);

select throws_ok(
  $$
    select public.adjust_stock(
      (select variant_id from fx),
      0,
      'noop'
    )
  $$,
  'P0004',
  null,
  'zero delta is rejected'
);

select throws_ok(
  $$
    select public.adjust_stock(
      (select variant_id from fx),
      1,
      '   '
    )
  $$,
  'P0004',
  null,
  'blank reason is rejected'
);

select throws_ok(
  format(
    $$ select public.adjust_stock(%L::uuid, 1, %L) $$,
    (select variant_id from fx),
    repeat('x', 501)
  ),
  'P0004',
  null,
  'reason longer than 500 characters is rejected'
);

select throws_ok(
  $$
    select public.adjust_stock(
      (select variant_id from fx),
      -99999,
      'overdraw'
    )
  $$,
  'PSTCK',
  null,
  'negative stock raises PSTCK'
);

select is(
  (select stock_qty from public.product_variants cross join fx where id = fx.variant_id),
  (select starting_qty + 1 from fx),
  'stock_qty unchanged after PSTCK failure'
);

reset role;

update public.product_variants
set stock_qty = 2147483640
where id = (select variant_id from fx);

select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', owner_id, 'role', 'authenticated')::text from fx),
  true
);
select set_config(
  'request.jwt.claim.sub',
  (select owner_id::text from fx),
  true
);
set local role authenticated;

select throws_ok(
  $$
    select public.adjust_stock(
      (select variant_id from fx),
      10,
      'overflow'
    )
  $$,
  '22003',
  null,
  'adjustment that overflows integer stock_qty is rejected'
);

select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', manager_id, 'role', 'authenticated')::text from fx),
  true
);
select set_config(
  'request.jwt.claim.sub',
  (select manager_id::text from fx),
  true
);

select throws_ok(
  $$
    update public.product_variants
    set stock_qty = stock_qty + 1
    where id = (select variant_id from fx)
  $$,
  '42501',
  null,
  'manager cannot update stock_qty directly'
);

select lives_ok(
  $$
    update public.product_variants
    set price_pesewas = price_pesewas + 1
    where id = (select variant_id from fx)
  $$,
  'manager can update price_pesewas'
);

reset role;

update public.product_variants
set stock_qty = current_setting('test.starting_qty')::integer + 1
where id = current_setting('test.variant_id')::uuid;

select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', current_setting('test.manager_id'),
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  current_setting('test.manager_id'),
  true
);
set local role authenticated;

select is(
  public.adjust_stock((select variant_id from fx), 1, 'still via rpc'),
  (select starting_qty + 2 from fx),
  'adjust_stock still updates stock after column grant change'
);

select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', owner_id, 'role', 'authenticated')::text from fx),
  true
);
select set_config(
  'request.jwt.claim.sub',
  (select owner_id::text from fx),
  true
);

select throws_ok(
  $$
    insert into public.stock_movements (
      variant_id, qty_delta, reason, actor_id
    )
    values (
      (select variant_id from fx),
      1,
      'direct insert',
      (select owner_id from fx)
    )
  $$,
  '42501',
  null,
  'authenticated cannot insert stock_movements directly'
);

reset role;

select throws_ok(
  format(
    $$ insert into public.stock_movements (
         sale_id, sale_item_id, variant_id, qty_delta, reason, actor_id
       )
       select sale_id, sale_item_id, variant_id, 1, 'mixed origin', %L::uuid
       from public.stock_movements
       where sale_id is not null
       limit 1 $$,
    (select owner_id from fx)
  ),
  '23514',
  null,
  'stock_movements_origin_check rejects mixed sale and adjustment fields'
);

select throws_ok(
  format(
    $$ update public.stock_movements set qty_delta = qty_delta + 1 where id = %L::uuid $$,
    (select id from public.stock_movements limit 1)
  ),
  '42501',
  'stock_movements is append-only',
  'stock_movements rejects updates'
);

select throws_ok(
  format(
    $$ delete from public.stock_movements where id = %L::uuid $$,
    (select id from public.stock_movements limit 1)
  ),
  '42501',
  'stock_movements is append-only',
  'stock_movements rejects deletes'
);

select * from finish();

rollback;