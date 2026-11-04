#!/usr/bin/env bash
# Fail when the running local database or its pg_dump is not the major in
# supabase/config.toml. CI and the restore drill both call this.

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

expected=$(awk -F= '/^[[:space:]]*major_version[[:space:]]*=/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' supabase/config.toml)
if [ -z "${expected}" ]; then
  echo "supabase/config.toml has no major_version" >&2
  exit 1
fi

container=${RESTORE_DB_CONTAINER:-}
if [ -z "$container" ]; then
  container=$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1 || true)
fi
if [ -z "$container" ]; then
  echo "local supabase database container is not running. Start it with: npx supabase start" >&2
  exit 1
fi

server_num=$(docker exec "$container" psql -U postgres -d postgres -tA -c "show server_version_num")
server_major=$((server_num / 10000))
dump_version=$(docker exec "$container" pg_dump --version)
dump_major=$(printf '%s\n' "$dump_version" | sed -n 's/.* \([0-9][0-9]*\)\..*/\1/p')

echo "config.toml major_version=${expected}; server ${server_num} (major ${server_major}); ${dump_version}"
if [ "$server_major" != "$expected" ] || [ "$dump_major" != "$expected" ]; then
  echo "Postgres major must match supabase/config.toml major_version (${expected})" >&2
  exit 1
fi
