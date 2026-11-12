begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(6);

create temporary table fx as
select
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid as store_id,
  (select id from auth.users where email = 'cashier@example.com') as cashier_id,
  (
    select id
    from public.product_variants
    where stock_qty >= 3
    order by sku
    limit 1
  ) as variant_id,
  (
    select price_pesewas
    from public.product_variants
    where stock_qty >= 3
    order by sku
    limit 1
  ) as shelf_price,
  (
    select stock_qty
    from public.product_variants
    where stock_qty >= 3
    order by sku
    limit 1
  ) as stock_before;

grant select on fx to authenticated;

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
set local role authenticated;

select lives_ok(
  $$
    select public.commit_sale(
      'd0d0d0d0-d0d0-40d0-80d0-d0d0d0d0d0d0'::uuid,
      (select store_id from fx),
      jsonb_build_array(
        jsonb_build_object(
          'id', 'd1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d1d1',
          'variant_id', (select variant_id from fx),
          'quantity', 1,
          'unit_price_pesewas', (select shelf_price from fx)
        )
      )
    )
  $$,
  'initial commit_sale succeeds'
);

reset role;

update public.product_variants as v
set stock_qty = 0,
    price_pesewas = v.price_pesewas + 9999
where v.id = (select variant_id from fx);

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
set local role authenticated;

select is(
  (public.commit_sale(
    'd0d0d0d0-d0d0-40d0-80d0-d0d0d0d0d0d0'::uuid,
    (select store_id from fx),
    jsonb_build_array(
      jsonb_build_object(
        'id', 'd1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d1d1',
        'variant_id', (select variant_id from fx),
        'quantity', 1,
        'unit_price_pesewas', (select shelf_price from fx)
      )
    )
  ) ->> 'replayed')::boolean,
  true,
  'replay after catalog drift returns replayed=true'
);

select is(
  (select count(*)::int from public.sales where id = 'd0d0d0d0-d0d0-40d0-80d0-d0d0d0d0d0d0'::uuid),
  1,
  'replay did not insert a second sale'
);

select is(
  (select count(*)::int from public.sale_items where sale_id = 'd0d0d0d0-d0d0-40d0-80d0-d0d0d0d0d0d0'::uuid),
  1,
  'replay did not insert a second sale_items row'
);

select is(
  (
    select count(*)::int
    from public.stock_movements
    where sale_id = 'd0d0d0d0-d0d0-40d0-80d0-d0d0d0d0d0d0'::uuid
  ),
  1,
  'replay did not insert a second stock movement'
);

select is(
  (
    select v.stock_qty
    from public.product_variants as v
    where v.id = (select variant_id from fx)
  ),
  0,
  'catalog drift update stands; replay did not re-apply stock'
);

select * from finish();
rollback;
