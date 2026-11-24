-- POS-07: product-images storage bucket and RLS on storage.objects.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'product-images',
  'product-images',
  false,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do nothing;

comment on column public.products.image_path is
  'Object path in the product-images bucket, e.g. products/<product_id>/hero.webp. Set by owner/manager after upload.';

create or replace function private.product_images_path_ok(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    split_part(object_name, '/', 1) = 'products'
    and split_part(object_name, '/', 2) <> ''
    and exists (
      select 1
      from public.products as p
      where p.id::text = split_part(object_name, '/', 2)
    );
$$;

revoke all on function private.product_images_path_ok(text) from public, anon, authenticated, service_role;
grant execute on function private.product_images_path_ok(text) to authenticated;

create policy product_images_select
on storage.objects
for select
to authenticated
using (
  bucket_id = 'product-images'
  and (select private.current_app_role()) in (
    'owner'::public.app_role,
    'manager'::public.app_role,
    'cashier'::public.app_role
  )
);

create policy product_images_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and (select private.current_app_role()) in (
    'owner'::public.app_role,
    'manager'::public.app_role
  )
  and (select private.product_images_path_ok(name))
);

create policy product_images_update
on storage.objects
for update
to authenticated
using (
  bucket_id = 'product-images'
  and (select private.current_app_role()) in (
    'owner'::public.app_role,
    'manager'::public.app_role
  )
  and (select private.product_images_path_ok(name))
)
with check (
  bucket_id = 'product-images'
  and (select private.current_app_role()) in (
    'owner'::public.app_role,
    'manager'::public.app_role
  )
  and (select private.product_images_path_ok(name))
);

create policy product_images_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'product-images'
  and (select private.current_app_role()) in (
    'owner'::public.app_role,
    'manager'::public.app_role
  )
  and (select private.product_images_path_ok(name))
);