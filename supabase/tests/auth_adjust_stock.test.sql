begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(13);

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

reset role;

select throws_ok(
  $$
    select public.adjust_stock(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
      1,
      'anon attempt'
    )
  $$,
  '42501',
  null,
  'anon cannot adjust stock'
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
set local role authenticated;

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

select * from finish();

rollback;