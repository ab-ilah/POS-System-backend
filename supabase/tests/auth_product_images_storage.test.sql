begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public, pg_temp, storage;

select plan(9);

create temporary table fx as
select
  (select id from auth.users where email = 'owner@example.com') as owner_id,
  (select id from auth.users where email = 'manager@example.com') as manager_id,
  (select id from auth.users where email = 'cashier@example.com') as cashier_id,
  '10000000-0000-4000-8000-000000000001'::uuid as product_id;

grant select on fx to authenticated;

insert into storage.objects (
  id,
  bucket_id,
  name,
  owner,
  metadata
)
select
  'a1000000-0000-4000-8000-0000000000a1'::uuid,
  'product-images',
  'products/' || product_id::text || '/pgtap-fixture.webp',
  owner_id,
  '{}'::jsonb
from fx;

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
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$
    insert into storage.objects (
      id, bucket_id, name, owner, metadata
    )
    select
      gen_random_uuid(),
      'product-images',
      'products/' || product_id::text || '/cashier-upload.webp',
      cashier_id,
      '{}'::jsonb
    from fx
  $$,
  '42501',
  null,
  'cashier cannot insert product images'
);

select isnt_empty(
  $$
    select id from storage.objects where bucket_id = 'product-images'
  $$,
  'cashier can select product images'
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
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select lives_ok(
  $$
    insert into storage.objects (
      id, bucket_id, name, owner, metadata
    )
    select
      gen_random_uuid(),
      'product-images',
      'products/' || product_id::text || '/manager-upload.webp',
      manager_id,
      '{}'::jsonb
    from fx
  $$,
  'manager can insert product images'
);

select isnt_empty(
  $$
    select id from storage.objects where bucket_id = 'product-images'
  $$,
  'manager can select product images'
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
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select lives_ok(
  $$
    insert into storage.objects (
      id, bucket_id, name, owner, metadata
    )
    select
      gen_random_uuid(),
      'product-images',
      'products/' || product_id::text || '/owner-upload.webp',
      owner_id,
      '{}'::jsonb
    from fx
  $$,
  'owner can insert product images'
);

set local role anon;

select is_empty(
  $$
    select id from storage.objects where bucket_id = 'product-images'
  $$,
  'anon cannot select product images'
);

reset role;

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
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$
    insert into storage.objects (
      id, bucket_id, name, owner, metadata
    )
    select
      gen_random_uuid(),
      'product-images',
      'catalog/' || product_id::text || '/bad-prefix.webp',
      manager_id,
      '{}'::jsonb
    from fx
  $$,
  '42501',
  null,
  'wrong path prefix is denied'
);

select throws_ok(
  $$
    insert into storage.objects (
      id, bucket_id, name, owner, metadata
    )
    select
      gen_random_uuid(),
      'product-images',
      'products/00000000-0000-4000-8000-000000009999/unknown-product.webp',
      manager_id,
      '{}'::jsonb
    from fx
  $$,
  '42501',
  null,
  'unknown product_id in path is denied'
);

select lives_ok(
  $$
    update public.products as p
    set image_path = 'products/' || f.product_id::text || '/manager-upload.webp'
    from fx as f
    where p.id = f.product_id
  $$,
  'manager can update products.image_path'
);

select * from finish();

rollback;