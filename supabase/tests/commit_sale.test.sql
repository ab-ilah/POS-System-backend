begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp;

select plan(37);

create or replace function pg_temp.commit_sale_pstck_detail(
  p_idempotency_key uuid,
  p_store_id uuid,
  p_lines jsonb
) returns text
language plpgsql
as $$
declare
  _detail text;
begin
  perform public.commit_sale(p_idempotency_key, p_store_id, p_lines);
  return null;
exception
  when others then
    if sqlstate <> 'PSTCK' then
      raise;
    end if;
    get stacked diagnostics _detail = pg_exception_detail;
    return _detail;
end;
$$;

create temporary table commit_fixture as
select
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid as store_id,
  (select id from auth.users where email = 'cashier@example.com') as cashier_id,
  (
    select id
    from public.product_variants
  where stock_qty >= 5
    order by sku
    limit 1
  ) as stocked_variant_id,
  (
    select price_pesewas
    from public.product_variants
    where stock_qty >= 5
    order by sku
    limit 1
  ) as shelf_price,
  (
    select stock_qty
    from public.product_variants
    where stock_qty >= 5
    order by sku
    limit 1
  ) as stock_before,
  (
    select id
    from public.product_variants
    where stock_qty = 0
    limit 1
  ) as zero_stock_variant_id,
  (
    select id
    from public.product_variants
    where stock_qty >= 3
    order by sku
    offset 1
    limit 1
  ) as second_variant_id,
  (
    select price_pesewas
    from public.product_variants
    where stock_qty >= 3
    order by sku
    offset 1
    limit 1
  ) as second_shelf_price;

grant select on table commit_fixture to authenticated;

select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', cashier_id, 'role', 'authenticated')::text from commit_fixture),
  true
);
select set_config(
  'request.jwt.claim.sub',
  (select cashier_id::text from commit_fixture),
  true
);
set local role authenticated;

select lives_ok(
  $$
    select public.commit_sale(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
      (select store_id from commit_fixture),
      jsonb_build_array(
        jsonb_build_object(
          'id', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          'variant_id', (select stocked_variant_id from commit_fixture),
          'quantity', 2,
          'unit_price_pesewas', (select shelf_price from commit_fixture)
        )
      )
    )
  $$,
  'happy path commits a sale'
);

select is(
  (select status from public.sales where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid),
  'completed',
  'cashier commit leaves the sale completed'
);

select throws_ok(
  $$
    insert into public.sale_items (
      sale_id, variant_id, product_name, size_name, colour_name,
      qty, unit_price_pesewas, line_total_pesewas
    )
  values (
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
      (select stocked_variant_id from commit_fixture),
      'Late', 'M', 'Black', 1,
      (select shelf_price from commit_fixture),
      (select shelf_price from commit_fixture)
    )
  $$,
  '42501',
  'cannot change lines on a finished sale',
  'a completed sale rejects a new sale_item'
);

reset role;

insert into public.stores (id, name)
values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbc'::uuid, 'Second shop');

select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', cashier_id, 'role', 'authenticated')::text from commit_fixture),
  true
);
select set_config(
  'request.jwt.claim.sub',
  (select cashier_id::text from commit_fixture),
  true
);
set local role authenticated;

select throws_ok(
  $$
    select public.commit_sale(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbc'::uuid,
      jsonb_build_array(
        jsonb_build_object(
          'id', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          'variant_id', (select stocked_variant_id from commit_fixture),
          'quantity', 2,
          'unit_price_pesewas', (select shelf_price from commit_fixture)
        )
      )
    )
  $$,
  'P0004',
  'idempotency_key_conflict',
  'mismatched store on replay is rejected'
);

select throws_ok(
  $$
    select public.commit_sale(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
      (select store_id from commit_fixture),
      jsonb_build_array(
        jsonb_build_object(
          'id', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          'variant_id', (select stocked_variant_id from commit_fixture),
          'quantity', 3,
          'unit_price_pesewas', (select shelf_price from commit_fixture)
        )
      )
    )
  $$,
  'P0004',
  'idempotency_key_conflict',
  'mismatched line quantity on replay is rejected'
);

select results_eq(
  $$
    select (public.commit_sale(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
      (select store_id from commit_fixture),
      jsonb_build_array(
        jsonb_build_object(
          'id', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          'variant_id', (select stocked_variant_id from commit_fixture),
          'quantity', 2,
          'unit_price_pesewas', (select shelf_price from commit_fixture)
        )
      )
    ) ->> 'replayed')::boolean
  $$,
  $$ values (true) $$,
  'replay returns replayed true'
);

select is(
  (select status from public.sales where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid),
  'completed',
  'replay returns an already completed sale'
);

select is(
  (select count(*)::int from public.sales where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid),
  1,
  'replay did not insert a second sale header'
);

select is(
  (select count(*)::int from public.sale_items where sale_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid),
  1,
  'replay did not insert a second line'
);

select is(
  (
    select count(*)::int
    from public.stock_movements
    where sale_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid
  ),
  1,
  'replay did not insert a second stock movement'
);

select is(
  (
    select stock_qty
    from public.product_variants
    where id = (select stocked_variant_id from commit_fixture)
  ),
  (select stock_before - 2 from commit_fixture),
  'replay did not change stock again'
);

select throws_ok(
  $$
    select public.commit_sale(
      '2a2a2a2a-2a2a-42a2-82a2-2a2a2a2a2a2a'::uuid,
      (select store_id from commit_fixture),
      jsonb_build_array(
        jsonb_build_object(
          'id', '2b2b2b2b-2b2b-42b2-82b2-2b2b2b2b2b2b',
          'variant_id', (
            select id from public.product_variants where stock_qty = 6 order by sku limit 1
          ),
          'quantity', 4,
          'unit_price_pesewas', (
            select price_pesewas from public.product_variants where stock_qty = 6 order by sku limit 1
          )
        ),
        jsonb_build_object(
          'id', '2c2c2c2c-2c2c-42c2-82c2-2c2c2c2c2c2c',
          'variant_id', (
            select id from public.product_variants where stock_qty = 6 order by sku limit 1
          ),
          'quantity', 3,
          'unit_price_pesewas', (
            select price_pesewas from public.product_variants where stock_qty = 6 order by sku limit 1
          )
        )
      )
    )
  $$,
  'PSTCK',
  'insufficient stock',
  'repeated variant lines aggregate qty before stock check'
);

select throws_ok(
  $$
    select public.commit_sale(
      '3a3a3a3a-3a3a-43a3-83a3-3a3a3a3a3a3a'::uuid,
      (select store_id from commit_fixture),
      jsonb_build_array(
        jsonb_build_object(
          'id', '3b3b3b3b-3b3b-43b3-83b3-3b3b3b3b3b3b',
          'variant_id', (select stocked_variant_id from commit_fixture),
          'quantity', 1,
          'unit_price_pesewas', (select shelf_price from commit_fixture)
        ),
        jsonb_build_object(
          'id', '3b3b3b3b-3b3b-43b3-83b3-3b3b3b3b3b3b',
          'variant_id', (select stocked_variant_id from commit_fixture),
          'quantity', 1,
          'unit_price_pesewas', (select shelf_price from commit_fixture)
        )
      )
    )
  $$,
  'P0005',
  'duplicate sale line id',
  'first commit rejects duplicate line ids in the payload'
);

select lives_ok(
  $$
    select public.commit_sale(
      '3d3d3d3d-3d3d-43d3-83d3-3d3d3d3d3d3d'::uuid,
      (select store_id from commit_fixture),
      jsonb_build_array(
        jsonb_build_object(
          'id', '3e3e3e3e-3e3e-43e3-83e3-3e3e3e3e3e3e',
          'variant_id', (select stocked_variant_id from commit_fixture),
          'quantity', 1,
          'unit_price_pesewas', (select shelf_price from commit_fixture)
        ),
        jsonb_build_object(
          'id', '3f3f3f3f-3f3f-43f3-83f3-3f3f3f3f3f3f',
          'variant_id', (select second_variant_id from commit_fixture),
          'quantity', 1,
          'unit_price_pesewas', (select second_shelf_price from commit_fixture)
        )
      )
    )
  $$,
  'two-line commit succeeds'
);

select throws_ok(
  $$
    select public.commit_sale(
      '3d3d3d3d-3d3d-43d3-83d3-3d3d3d3d3d3d'::uuid,
      (select store_id from commit_fixture),
      jsonb_build_array(
        jsonb_build_object(
          'id', '3e3e3e3e-3e3e-43e3-83e3-3e3e3e3e3e3e',
          'variant_id', (select stocked_variant_id from commit_fixture),
          'quantity', 1,
          'unit_price_pesewas', (select shelf_price from commit_fixture)
        ),
        jsonb_build_object(
          'id', '3e3e3e3e-3e3e-43e3-83e3-3e3e3e3e3e3e',
          'variant_id', (select second_variant_id from commit_fixture),
          'quantity', 1,
          'unit_price_pesewas', (select second_shelf_price from commit_fixture)
        )
      )
    )
  $$,
  'P0005',
  'duplicate sale line id',
  'replay with duplicate line id is rejected before multiset match'
);

select throws_ok(
  $$
    select public.commit_sale(
      '3d3d3d3d-3d3d-43d3-83d3-3d3d3d3d3d3d'::uuid,
      (select store_id from commit_fixture),
      jsonb_build_array(
        jsonb_build_object(
          'id', '3e3e3e3e-3e3e-43e3-83e3-3e3e3e3e3e3e',
          'variant_id', (select stocked_variant_id from commit_fixture),
          'quantity', 1,
          'unit_price_pesewas', (select shelf_price from commit_fixture)
        )
      )
    )
  $$,
  'P0004',
  'idempotency_key_conflict',
  'missing line on replay is rejected via multiset compare'
);

select throws_ok(
  $$
    select public.commit_sale(
      '3d3d3d3d-3d3d-43d3-83d3-3d3d3d3d3d3d'::uuid,
      (select store_id from commit_fixture),
      jsonb_build_array(
        jsonb_build_object(
          'id', '40000000-0000-4000-8000-000000000001'::uuid,
          'variant_id', (select stocked_variant_id from commit_fixture),
          'quantity', 1,
          'unit_price_pesewas', (select shelf_price from commit_fixture)
        ),
        jsonb_build_object(
          'id', '40000000-0000-4000-8000-000000000002'::uuid,
          'variant_id', (select second_variant_id from commit_fixture),
          'quantity', 1,
          'unit_price_pesewas', (select second_shelf_price from commit_fixture)
        )
      )
    )
  $$,
  'P0004',
  'idempotency_key_conflict',
  'replay with same tuples but different line ids is rejected'
);

select results_eq(
  $$
    select (public.commit_sale(
      '3d3d3d3d-3d3d-43d3-83d3-3d3d3d3d3d3d'::uuid,
      (select store_id from commit_fixture),
      jsonb_build_array(
        jsonb_build_object(
          'id', '3f3f3f3f-3f3f-43f3-83f3-3f3f3f3f3f3f',
          'variant_id', (select second_variant_id from commit_fixture),
          'quantity', 1,
          'unit_price_pesewas', (select second_shelf_price from commit_fixture)
        ),
        jsonb_build_object(
          'id', '3e3e3e3e-3e3e-43e3-83e3-3e3e3e3e3e3e',
          'variant_id', (select stocked_variant_id from commit_fixture),
          'quantity', 1,
          'unit_price_pesewas', (select shelf_price from commit_fixture)
        )
      )
    ) ->> 'replayed')::boolean
  $$,
  $$ values (true) $$,
  'reordered lines with the same multiset replay ok'
);

reset role;

select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', id, 'role', 'authenticated')::text
   from auth.users where email = 'manager@example.com'),
  true
);
set local role authenticated;

select throws_ok(
  $$
    select public.commit_sale(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
      (select store_id from commit_fixture),
      jsonb_build_array(
        jsonb_build_object(
          'id', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          'variant_id', (select stocked_variant_id from commit_fixture),
          'quantity', 2,
          'unit_price_pesewas', (select shelf_price from commit_fixture)
        )
      )
    )
  $$,
  'P0004',
  'idempotency_key_conflict',
  'other staff cannot replay someone else''s sale'
);

select throws_ok(
  $$
    select public.commit_sale(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
      '00000000-0000-4000-8000-000000000000'::uuid,
      '[]'::jsonb
    )
  $$,
  'P0004',
  'a sale needs at least one line',
  'existing id with junk payload matches a fresh id (no oracle)'
);

select throws_ok(
  $$
    select public.commit_sale(
      gen_random_uuid(),
      '00000000-0000-4000-8000-000000000000'::uuid,
      '[]'::jsonb
    )
  $$,
  'P0004',
  'a sale needs at least one line',
  'unknown id gives the identical empty-lines error'
);

select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', cashier_id, 'role', 'authenticated')::text from commit_fixture),
  true
);
set local role authenticated;

select throws_ok(
  $$
    insert into public.stock_movements (
      sale_id,
      sale_item_id,
      variant_id,
      qty_delta
    )
    values (
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc'::uuid,
      (select stocked_variant_id from commit_fixture),
      -1
    )
  $$,
  '42501',
  NULL,
  'authenticated cannot insert stock_movements directly'
);

select throws_ok(
  $$
    select public.commit_sale(
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd'::uuid,
      (select store_id from commit_fixture),
      jsonb_build_array(
        jsonb_build_object(
          'id', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          'variant_id', (select zero_stock_variant_id from commit_fixture),
          'quantity', 1,
          'unit_price_pesewas', (
            select price_pesewas
            from public.product_variants
            where id = (select zero_stock_variant_id from commit_fixture)
          )
        )
      )
    )
  $$,
  'PSTCK',
  'insufficient stock',
  'insufficient stock rejects the sale'
);

select is(
  (select count(*)::int from public.sales where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'::uuid),
  0,
  'insufficient stock left no sale header'
);

select is(
  pg_temp.commit_sale_pstck_detail(
    'd1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d1d1'::uuid,
    (select store_id from commit_fixture),
    jsonb_build_array(
      jsonb_build_object(
        'id', 'd2d2d2d2-d2d2-42d2-82d2-d2d2d2d2d2d2',
        'variant_id', (select zero_stock_variant_id from commit_fixture),
        'quantity', 1,
        'unit_price_pesewas', (
          select price_pesewas
          from public.product_variants
          where id = (select zero_stock_variant_id from commit_fixture)
        )
      )
    )
  ),
  'variant_id=' || (select zero_stock_variant_id::text from commit_fixture),
  'PSTCK detail names the out-of-stock variant'
);

reset role;

insert into public.sales (
  id,
  receipt_no,
  store_id,
  customer_id,
  cashier_id,
  status,
  subtotal_pesewas,
  total_pesewas,
  tendered_pesewas,
  change_pesewas,
  credit_applied_pesewas
) values (
  'c1c1c1c1-c1c1-41c1-81c1-c1c1c1c1c1c1'::uuid,
  'OPEN-RLS-PROBE',
  (select store_id from commit_fixture),
  null,
  (select cashier_id from commit_fixture),
  'open',
  1000,
  1000,
  1000,
  0,
  0
);

select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', cashier_id, 'role', 'authenticated')::text from commit_fixture),
  true
);
select set_config(
  'request.jwt.claim.sub',
  (select cashier_id::text from commit_fixture),
  true
);
set local role authenticated;

create or replace function pg_temp.cashier_try_complete_open_sale() returns integer
language plpgsql
as $$
declare
  rows_updated integer;
begin
  update public.sales
  set status = 'completed'
  where id = 'c1c1c1c1-c1c1-41c1-81c1-c1c1c1c1c1c1'::uuid;
  get diagnostics rows_updated = row_count;
  return rows_updated;
end;
$$;

select is(
  pg_temp.cashier_try_complete_open_sale(),
  0,
  'cashier cannot complete a sale with a direct update'
);

select is(
  (select status from public.sales where id = 'c1c1c1c1-c1c1-41c1-81c1-c1c1c1c1c1c1'::uuid),
  'open',
  'direct update attempt left the sale open'
);

select throws_ok(
  $$
    select public.commit_sale(
      'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid,
      (select store_id from commit_fixture),
      jsonb_build_array(
        jsonb_build_object(
          'id', '11111111-1111-4111-8111-111111111112',
          'variant_id', (select stocked_variant_id from commit_fixture),
          'quantity', 1,
          'unit_price_pesewas', (select shelf_price + 1 from commit_fixture)
        )
      )
    )
  $$,
  'P0003',
  'unit price does not match shelf price',
  'price mismatch is rejected'
);

select throws_ok(
  $$
    select public.commit_sale(
      '1b1b1b1b-1b1b-41b1-81b1-1b1b1b1b1b1b'::uuid,
      '00000000-0000-4000-8000-000000009999'::uuid,
      jsonb_build_array(
        jsonb_build_object(
          'id', '1c1c1c1c-1c1c-41c1-81c1-1c1c1c1c1c1c',
          'variant_id', (select stocked_variant_id from commit_fixture),
          'quantity', 1,
          'unit_price_pesewas', (select shelf_price from commit_fixture)
        )
      )
    )
  $$,
  'P0002',
  'no such store',
  'wrong store id is rejected'
);

with updated as (
  update public.product_variants as v
  set stock_qty = v.stock_qty - 1
  where v.id = (select stocked_variant_id from commit_fixture)
  returning v.id
)
select is((select count(*)::int from updated), 0, 'cashier cannot update stock_qty directly');

select set_config('private.commit_sale_active', '1', true);

select throws_ok(
  $$
    select private.stock_qty_apply_for_commit(
      (select stocked_variant_id from commit_fixture),
      -1
    )
  $$,
  '42501',
  NULL,
  'direct call to stock helper is denied even with the old GUC set'
);

select throws_ok(
  $$
    select public.commit_sale(
      '12121212-1212-4212-8212-121212121212'::uuid,
      (select store_id from commit_fixture),
      jsonb_build_array(
        jsonb_build_object(
          'id', '13131313-1313-4313-8313-131313131313',
          'variant_id', (select stocked_variant_id from commit_fixture),
          'quantity', 1,
          'unit_price_pesewas', (select shelf_price from commit_fixture)
        ),
        jsonb_build_object(
          'id', '14141414-1414-4414-8414-141414141414',
          'variant_id', '00000000-0000-4000-8000-000000000099'::uuid,
          'quantity', 1,
          'unit_price_pesewas', 1
        )
      )
    )
  $$,
  'P0002',
  'no such variant',
  'mid-transaction failure rolls back partial work'
);

select is(
  (select count(*)::int from public.sales where id = '12121212-1212-4212-8212-121212121212'::uuid),
  0,
  'rolled back sale header after variant failure'
);

reset role;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current, phone_change, phone_change_token, reauthentication_token
)
values (
  '00000000-0000-0000-0000-000000000000',
  '18181818-1818-4818-8818-181818181818',
  'authenticated',
  'authenticated',
  'no-role@example.com',
  extensions.crypt('local-dev-only', extensions.gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"full_name":"No Role"}'::jsonb,
  now(), now(),
  '', '', '', '', '', '', '', ''
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', '18181818-1818-4818-8818-181818181818', 'role', 'authenticated')::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '18181818-1818-4818-8818-181818181818',
  true
);
set local role authenticated;

select throws_ok(
  $$ select public.commit_sale(
    '19191919-1919-4919-8919-191919191919'::uuid,
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
    jsonb_build_array(
      jsonb_build_object(
        'id', '1a1a1a1a-1a1a-4a1a-8a1a-1a1a1a1a1a1a',
        'variant_id', (select stocked_variant_id from commit_fixture),
        'quantity', 1,
        'unit_price_pesewas', (select shelf_price from commit_fixture)
      )
    )
  ) $$,
  '42501',
  'only staff can commit a sale',
  'a user with no app role cannot commit'
);

set local role anon;

select throws_ok(
  $$ select public.commit_sale(
    '15151515-1515-4515-8515-151515151515'::uuid,
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
    '[]'::jsonb
  ) $$,
  '42501',
  NULL,
  'anon cannot commit a sale'
);

set local role authenticated;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', (select cashier_id::text from commit_fixture), 'role', 'service_role')::text,
  true
);
set local role service_role;

select skip(
  1,
  'concurrent replay needs a second DB session (dblink); unique_violation path is covered above'
);

select throws_ok(
  $$
    select public.commit_sale(
      '16161616-1616-4616-8616-161616161616'::uuid,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
      jsonb_build_array(
        jsonb_build_object(
          'id', '17171717-1717-4717-8717-171717171717',
          'variant_id', (select stocked_variant_id from commit_fixture),
          'quantity', 1,
          'unit_price_pesewas', (select shelf_price from commit_fixture)
        )
      )
    )
  $$,
  '42501',
  NULL,
  'service_role cannot commit even with an owner subject'
);

select * from finish();

rollback;
