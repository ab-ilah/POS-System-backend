# Product images (Storage)

Catalog photos live in the private **`product-images`** bucket. Metadata on `public.products.image_path` stores the object path after upload.

## Path convention

```
products/<product_id>/<filename>
```

- `<product_id>` must match an existing `public.products.id`.
- Example: `products/10000000-0000-4000-8000-000000000001/hero.webp`.

Owners and managers set `products.image_path` to this path once the object is stored.

## Bucket settings

| Setting | Value |
| --- | --- |
| `public` | `false` (authenticated staff only) |
| `file_size_limit` | 2 097 152 bytes (2 MiB) |
| `allowed_mime_types` | `image/jpeg`, `image/png`, `image/webp` |

## Access (storage.objects RLS)

| Role | Select | Insert / update / delete |
| --- | --- | --- |
| Owner | Yes | Yes (valid `products/…` path only) |
| Manager | Yes | Yes (valid `products/…` path only) |
| Cashier | Yes | No |
| Anon | No | No |

Uploads that use the wrong prefix, a missing product id, a disallowed MIME type, or a file over the size limit are rejected.