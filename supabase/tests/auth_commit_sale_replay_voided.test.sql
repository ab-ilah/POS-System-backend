begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(4);

create temporary table fx as
select
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid as store_id,
  (select id from auth.users where email = 'cashier@example.com') as cashier_id,
  (select id from auth.users where email = 'owner@example.com') as owner_id,
  (
    select id
    from public.product_variants
    where stock_qty >= 2
    order by sku
    limit 1
  ) as variant_id,
  (
    select price_pesewas
    from public.product_variants
    where stock_qty >= 2
    order by sku
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
      'e0e0e0e0-e0e0-40e0-80e0-e0e0e0e0e0e0'::uuid,
      (select store_id from fx),
      jsonb_build_array(
        jsonb_build_object(
          'id', 'e1e1e1e1-e1e1-41e1-81e1-e1e1e1e1e1e1',
          'variant_id', (select variant_id from fx),
          'quantity', 1,
          'unit_price_pesewas', (select shelf_price from fx)
        )
      )
    )
  $$,
  'commit_sale completes an open sale'
);

reset role;

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

update public.sales as s
set status = 'voided',
    void_reason = 'pgTAP owner void for replay'
where s.id = 'e0e0e0e0-e0e0-40e0-80e0-e0e0e0e0e0e0'::uuid;

reset role;

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
  public.commit_sale(
    'e0e0e0e0-e0e0-40e0-80e0-e0e0e0e0e0e0'::uuid,
    (select store_id from fx),
    jsonb_build_array(
      jsonb_build_object(
        'id', 'e1e1e1e1-e1e1-41e1-81e1-e1e1e1e1e1e1',
        'variant_id', (select variant_id from fx),
        'quantity', 1,
        'unit_price_pesewas', (select shelf_price from fx)
      )
    )
  ) ->> 'status',
  'voided',
  'replay returns status voided'
);

select is(
  (public.commit_sale(
    'e0e0e0e0-e0e0-40e0-80e0-e0e0e0e0e0e0'::uuid,
    (select store_id from fx),
    jsonb_build_array(
      jsonb_build_object(
        'id', 'e1e1e1e1-e1e1-41e1-81e1-e1e1e1e1e1e1',
        'variant_id', (select variant_id from fx),
        'quantity', 1,
        'unit_price_pesewas', (select shelf_price from fx)
      )
    )
  ) ->> 'replayed')::boolean,
  true,
  'replay after void still returns replayed=true'
);

select * from finish();
rollback;
