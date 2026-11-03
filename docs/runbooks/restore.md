# Restore a database backup

Owner: Gabriel. Practice this on a local stack or on wiped staging. Do not point a drill at production.

Backups are age-encrypted custom-format `pg_dump` files in the object-storage bucket. They are not GitHub Actions artifacts. The workflow never uploads those.

## Keys

- Decrypt with the private identity that matches `docs/backup/age.pub`.
- Gabriel keeps that private file on a trusted machine.
- Gabriel keeps a second copy offline, in a different place from the first (for example a sealed USB or a paper print).
- The public file in git cannot decrypt a backup. If the private key is lost, the backups cannot be read. If it leaks, follow `docs/runbooks/key-rotation.md` within 1 hour.
- Rotating the age recipient does not protect backups already encrypted to the old key. Anyone who has the old private key can still decrypt those objects until the bucket lifecycle deletes them (14 daily, 8 weekly). Keep the old private key until that window has passed, then destroy it. New dumps use only the recipient currently in `docs/backup/age.pub`.

## Download and decrypt

On a trusted machine, not in CI:

```bash
aws s3 cp "s3://BUCKET/daily/YYYY/MM/DD/pos-STAMP.dump.age" ./pos.dump.age \
  --endpoint-url "$BACKUP_S3_ENDPOINT"
age -d -i /path/to/pos-backup-identity.txt -o pos.dump pos.dump.age
```

Use the newest daily object, or the newest weekly object if the dailies are gone. Confirm the filename ends in `.age` before decrypting. Delete `pos.dump` when the drill is finished (`shred -u pos.dump` or remove it).

## Restore target

Pick one:

- Local: `npx supabase start` in a checkout of the commit that matches the backup era.
- Wiped staging: only after Gabriel has confirmed the URL is the staging session pooler. Never substitute `PROD_DB_URL` during a drill.

A full Supabase dump includes platform schemas (`auth`, `storage`, and others). Restoring every schema onto a running stack collides with objects the platform owns. Restore the `public` schema only.

The same command works on an empty database and on one that already has these tables. `--clean` drops each object before recreating it. `--if-exists` makes that drop a no-op when the object is not there yet, which is the empty-database case. `--no-owner` and `--no-privileges` skip roles that exist only on the source project.

```bash
pg_restore \
  --no-owner \
  --no-privileges \
  --schema=public \
  --clean \
  --if-exists \
  --exit-on-error \
  --dbname "$TARGET_URL" \
  pos.dump
```

`$TARGET_URL` is either the local stack (`postgresql://postgres:postgres@127.0.0.1:54322/postgres` after `npx supabase start`) or the staging session pooler after Gabriel has confirmed the URL. Never point this at production during a drill.

Use a fresh Supabase project when you do not want to wipe staging. Create it, run the migrations (`npx supabase db push`), then run the `pg_restore` command above. `--clean --if-exists` still applies: the migrated tables are dropped and replaced by the dump.

The `pg_restore` client must be at least the server major (the backup job uses the server's own major).

`npx supabase db reset` rebuilds from migrations and the local seed. It wipes whatever you just restored. Use it to prove the migrations and RLS suite, not as the step after a data restore.

## Verify

Record the numbers. Do not skip a check because the previous drill passed.

1. Row counts:

```sql
select 'profiles' as tbl, count(*) from public.profiles
union all select 'products', count(*) from public.products
union all select 'product_variants', count(*) from public.product_variants
union all select 'customers', count(*) from public.customers
union all select 'sales', count(*) from public.sales
union all select 'sale_items', count(*) from public.sale_items;
```

2. Migration version:

```sql
select version
from supabase_migrations.schema_migrations
order by version;
```

Compare that list with `supabase/migrations` at the commit you believe the backup came from.

3. RLS is still on:

```sql
select relname, relrowsecurity
from pg_class
where relnamespace = 'public'::regnamespace
  and relname in ('profiles', 'products', 'product_variants', 'customers', 'sales', 'sale_items');
```

Each `relrowsecurity` value must be true.

4. RLS suite. The suite expects the local seed users. A production dump will not have them. Run the suite on a separate, seeded database:

```bash
npx supabase db reset
npm run test:rls
```

That check proves the policies still match `shared/permissions.matrix.ts`. It does not prove the restored production rows. Say which database you used when you write the drill up.

## Write it down

Add `docs/restore-drills/YYYY-MM-DD.md` with:

- date
- who ran it
- duration
- object key that was restored
- target (local or staging)
- row counts
- migration versions
- RLS suite result, and whether it ran against seed data or the restored rows
- anything that failed
