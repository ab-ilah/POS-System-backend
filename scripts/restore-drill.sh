#!/usr/bin/env bash
# Dump the seeded local database, encrypt and decrypt it, then restore both ways:
# data-only onto the already-migrated schema, and a full public+private restore
# onto an empty application schema. Auth stays in place; this does not touch hosted projects.

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

container=${RESTORE_DB_CONTAINER:-}
if [ -z "$container" ]; then
  container=$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1 || true)
fi
if [ -z "$container" ]; then
  echo "local supabase database container is not running. Start it with: npx supabase start" >&2
  exit 1
fi
export RESTORE_DB_CONTAINER="$container"
bash "$root/scripts/assert-postgres-major.sh"
if ! command -v age >/dev/null 2>&1 || ! command -v age-keygen >/dev/null 2>&1; then
  echo "age and age-keygen must be installed" >&2
  exit 1
fi

workdir=$(mktemp -d)
cleanup() {
  rm -rf "$workdir"
  docker exec "$container" rm -f /tmp/pos-restore.dump /tmp/pos-restore.list >/dev/null 2>&1 || true
}
trap cleanup EXIT

psql_exec() {
  docker exec -i "$container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"
}

psql_admin() {
  docker exec -i "$container" psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 "$@"
}

counts() {
  psql_exec -tA -c "select
    (select count(*) from public.profiles)::text || ' ' ||
    (select count(*) from public.products)::text || ' ' ||
    (select count(*) from public.product_variants)::text || ' ' ||
    (select count(*) from public.customers)::text || ' ' ||
    (select count(*) from public.sales)::text || ' ' ||
    (select count(*) from public.sale_items)::text || ' ' ||
    (select count(*) from public.stores)::text || ' ' ||
    (select count(*) from public.stock_movements)::text"
}

assert_counts() {
  local actual
  actual=$(counts)
  if [ "$actual" != "$1" ]; then
    echo "row counts differ: expected [$1] got [$actual]" >&2
    exit 1
  fi
}

assert_behavior() {
  psql_exec <<'SQL'
begin;
insert into auth.users (
  instance_id, id, aud, role, email,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current, phone_change, phone_change_token, reauthentication_token
) values (
  '00000000-0000-0000-0000-000000000000',
  '77777777-7777-4777-8777-777777777777',
  'authenticated',
  'authenticated',
  'restore-drill@example.com',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"full_name":"Restore Drill"}'::jsonb,
  now(), now(),
  '', '', '', '', '', '', '', ''
);
do $$
begin
  if (select count(*) from public.profiles where id = '77777777-7777-4777-8777-777777777777') <> 1 then
    raise exception 'new auth user did not get a profile';
  end if;
  if (select raw_app_meta_data ->> 'role' from auth.users where id = '77777777-7777-4777-8777-777777777777') is not null then
    raise exception 'new auth user was assigned a role';
  end if;
end $$;
rollback;
SQL

  psql_exec <<'SQL'
begin;
select set_config(
  'request.jwt.claims',
  (select json_build_object('sub', id, 'role', 'authenticated')::text from auth.users where email = 'cashier@example.com'),
  true
);
select set_config(
  'request.jwt.claim.sub',
  (select id::text from auth.users where email = 'cashier@example.com'),
  true
);
set local role authenticated;
do $$
declare
  visible integer;
begin
  select count(*) into visible from public.products;
  if visible < 1 then
    raise exception 'cashier cannot read products after restore';
  end if;
end $$;
rollback;
SQL

  if psql_exec <<'SQL'
insert into public.sale_items (
  sale_id, variant_id, product_name, size_name, colour_name,
  qty, unit_price_pesewas, line_total_pesewas
)
select sale.id, variant.id, 'Drill', 'M', 'Black', 1, 1000, 1000
from public.sales as sale
cross join lateral (select id from public.product_variants limit 1) as variant
where sale.status = 'completed'
limit 1;
SQL
  then
    echo "a finished sale accepted a new line after restore" >&2
    exit 1
  fi
}

echo "dumping public and private"
docker exec "$container" pg_dump -U postgres -d postgres -Fc --schema=public --schema=private > "$workdir/pos.dump"
if [ "$(head -c 5 "$workdir/pos.dump")" != "PGDMP" ]; then
  echo "dump is not a custom-format archive" >&2
  exit 1
fi

age-keygen -o "$workdir/identity.txt" >/dev/null
age-keygen -y "$workdir/identity.txt" > "$workdir/recipient.txt"
age -R "$workdir/recipient.txt" -o "$workdir/pos.dump.age" "$workdir/pos.dump"
rm -f "$workdir/pos.dump"
age -d -i "$workdir/identity.txt" -o "$workdir/pos.dump" "$workdir/pos.dump.age"
if [ "$(head -c 5 "$workdir/pos.dump")" != "PGDMP" ]; then
  echo "decrypted dump is not a custom-format archive" >&2
  exit 1
fi

expected=$(counts)
echo "seeded counts: $expected"
docker cp "$workdir/pos.dump" "$container:/tmp/pos-restore.dump"

echo "data-only restore onto the migrated schema"
psql_admin -c "truncate table public.stock_movements, public.sale_items, public.sales, public.stores, public.customers, public.product_variants, public.products, public.profiles;"
docker exec "$container" pg_restore -U supabase_admin -d postgres \
  --data-only \
  --schema=public \
  --no-owner \
  --disable-triggers \
  --single-transaction \
  --exit-on-error \
  /tmp/pos-restore.dump
assert_counts "$expected"
assert_behavior
echo "migrated data-only restore ok"

echo "full restore onto an empty application schema"
psql_admin <<'SQL'
drop schema if exists private cascade;
drop table if exists
  public.stock_movements,
  public.sale_items,
  public.sales,
  public.stores,
  public.customers,
  public.product_variants,
  public.products,
  public.profiles
cascade;
drop function if exists public.commit_sale(uuid, uuid, jsonb) cascade;
drop function if exists private.commit_sale_assert_lines_payload(jsonb) cascade;
drop function if exists private.commit_sale_payload_matches(uuid, uuid, jsonb) cascade;
drop function if exists private.stock_qty_apply_for_commit(uuid, integer) cascade;
drop function if exists public.assign_staff_role(uuid, public.app_role);
drop function if exists public.my_role();
drop function if exists private.target_is_owner(uuid);
drop function if exists private.bootstrap_first_owner(text);
drop table if exists private.bootstrap_state;
drop function if exists public.consume_staff_invite_slot(uuid);
drop table if exists private.staff_invite_buckets;
drop function if exists private.consume_staff_invite_slot(uuid);
drop function if exists private.set_commit_sale_completing();
drop function if exists private.clear_commit_sale_completing();
drop table if exists private.sale_completion_tokens;
drop type if exists public.app_role cascade;
SQL
docker exec "$container" pg_restore -l /tmp/pos-restore.dump > "$workdir/toc.list"
grep -v -E 'SCHEMA - public |COMMENT - SCHEMA public ' "$workdir/toc.list" > "$workdir/toc.filtered"
docker cp "$workdir/toc.filtered" "$container:/tmp/pos-restore.list"
docker exec "$container" pg_restore -U supabase_admin -d postgres \
  --no-owner \
  --disable-triggers \
  --single-transaction \
  --exit-on-error \
  --use-list=/tmp/pos-restore.list \
  /tmp/pos-restore.dump
psql_exec <<'SQL'
do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'on_auth_user_created') then
    create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function private.handle_new_user();
  end if;
end $$;
SQL
assert_counts "$expected"
assert_behavior
echo "empty-schema full restore ok"
