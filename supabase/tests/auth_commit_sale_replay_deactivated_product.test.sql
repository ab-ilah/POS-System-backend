begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(2);

create temporary table fx as
select
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid as store_id,
  (select id from auth.users where email = 'cashier@example.com') as cashier_id,
  (
    select pv.id
    from public.product_variants as pv
    inner join public.products as p on p.id = pv.product_id and p.active = true
    where pv.stock_qty >= 2
    order by pv.sku
    limit 1
  ) as variant_id,
  (
    select p.id
    from public.product_variants as pv
    inner join public.products as p on p.id = pv.product_id and p.active = true
    where pv.stock_qty >= 2
    order by pv.sku
    limit 1
  ) as product_id,
  (
    select pv.price_pesewas
    from public.product_variants as pv
  where pv.stock_qty >= 2
    order by pv.sku
    limit 1
  ) as shelf_price;

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
      'b8b8b8b8-b8b8-48b8-88b8-b8b8b8b8b8b8'::uuid,
      (select store_id from fx),
      jsonb_build_array(
        jsonb_build_object(
          'id', 'b9b9b9b9-b9b9-49b9-89b9-b9b9b9b9b9b9',
          'variant_id', (select variant_id from fx),
          'quantity', 1,
          'unit_price_pesewas', (select shelf_price from fx)
        )
      )
    )
  $$,
  'initial commit succeeds'
);

reset role;

update public.products as p
set active = false
where p.id = (select product_id from fx);

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
    'b8b8b8b8-b8b8-48b8-88b8-b8b8b8b8b8b8'::uuid,
    (select store_id from fx),
    jsonb_build_array(
      jsonb_build_object(
        'id', 'b9b9b9b9-b9b9-49b9-89b9-b9b9b9b9b9b9',
        'variant_id', (select variant_id from fx),
        'quantity', 1,
        'unit_price_pesewas', (select shelf_price from fx)
      )
    )
  ) ->> 'replayed')::boolean,
  true,
  'replay succeeds after product deactivated'
);

select * from finish();
rollback;
