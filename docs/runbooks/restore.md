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
  --endpoint-url "$BACKUP_S3_ENDPOINT" \
  --force-path-style
age -d -i /path/to/pos-backup-identity.txt -o pos.dump pos.dump.age
```

Use the newest daily object, or the newest weekly object if the dailies are gone. Confirm the filename ends in `.age` before decrypting. Delete `pos.dump` when the drill is finished (`shred -u pos.dump` or remove it).

## Restore target

Pick one:

- Local: `npx supabase start` in a checkout of the commit that matches the backup era.
- Wiped staging: only after Gabriel has confirmed the URL is the staging session pooler. Never substitute `PROD_DB_URL` during a drill.

A full Supabase dump includes platform schemas (`auth`, `storage`, and others). Do not restore those onto a running stack. Dump the application schemas together:

```bash
pg_dump -Fc --schema=public --schema=private --dbname "$SOURCE_URL" --file=pos.dump
```

`private` holds the triggers. Restoring `public` alone leaves those triggers pointing at functions that are not there.

There are two restores. Do not ask pg_restore to drop existing objects first. On a database that already has the schema, that drop tries to remove `public.app_role` and can fail halfway, leaving `public` empty.

Run `pg_restore` as `supabase_admin` (or another role that can disable triggers). Pass `--disable-triggers` so historical lines on completed sales can load. The finished-sale trigger is still there afterwards. Pass `--single-transaction` so a failed restore rolls back instead of stopping in the middle.

The local database and the `pg_dump` inside that container must both be the major in `supabase/config.toml` (`major_version = 17`). `scripts/assert-postgres-major.sh` checks that, and CI plus `scripts/restore-drill.sh` run it. A Postgres 16 server or client does not match this project.

**Empty application schema.** The Supabase project is up, `auth` exists, and `public` does not yet contain these tables (a new local stack before `db reset`, or after you have dropped `private`, the application tables, and `public.app_role`).

Create the auth users before the restore. `profiles.id` references `auth.users`, and this dump does not include `auth`. For every profile id in the dump, insert an `auth.users` row with that same id. A placeholder email is enough when the original auth row is not in the dump. Token columns must be empty strings, not null.

```bash
pg_restore --data-only --table=profiles --file=profiles.sql pos.dump
```

Use each id from that file:

```sql
insert into auth.users (
  instance_id, id, aud, role, email,
  raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at,
  confirmation_token, recovery_token,
  email_change, email_change_token_new, email_change_token_current,
  phone_change, phone_change_token, reauthentication_token
) values (
  '00000000-0000-0000-0000-000000000000',
  '<profile-id>',
  'authenticated',
  'authenticated',
  '<profile-id>@restore.invalid',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  now(), now(),
  '', '', '', '', '', '', '', ''
);
```

Then load schema and data, including `private` and the enum:

```bash
pg_restore -l pos.dump | grep -v -E 'SCHEMA - public |COMMENT - SCHEMA public ' > restore.list
pg_restore \
  --no-owner \
  --disable-triggers \
  --single-transaction \
  --exit-on-error \
  --use-list=restore.list \
  --dbname "$TARGET_URL" \
  pos.dump
```

The list drops `CREATE SCHEMA public` because that schema already exists. `private` is created by the dump. The signup trigger is attached to `auth.users`, so it is not inside this dump. Recreate it after the restore:

```sql
create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_user();
```

**Already migrated.** Migrations have been applied and the application tables are empty. Do not drop the enum. Load rows only:

```bash
pg_restore \
  --data-only \
  --schema=public \
  --no-owner \
  --disable-triggers \
  --single-transaction \
  --exit-on-error \
  --dbname "$TARGET_URL" \
  pos.dump
```

`$TARGET_URL` is the local stack (`postgresql://postgres:postgres@127.0.0.1:54322/postgres` after `npx supabase start`) or the staging session pooler after Gabriel has confirmed the URL. Never point this at production during a drill.

`scripts/restore-drill.sh` runs both paths against the local stack. CI runs it after `supabase db reset`.

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
union all select 'sale_lines', count(*) from public.sale_lines;
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
  and relname in ('profiles', 'products', 'product_variants', 'customers', 'sales', 'sale_lines');
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
