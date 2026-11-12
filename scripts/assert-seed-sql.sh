#!/usr/bin/env bash
# Apply supabase/seed.sql on a migrated DB without seed and assert historical sales completed.
set -euo pipefail

DATABASE_URL="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"

npx supabase db reset --no-seed --yes

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/seed.sql

completed_count="$(
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -tAc "
    select count(*)::text
    from public.sales
    where id in (
      '40000000-0000-4000-8000-000000000001'::uuid,
      '40000000-0000-4000-8000-000000000002'::uuid,
      '40000000-0000-4000-8000-000000000003'::uuid,
      '40000000-0000-4000-8000-000000000004'::uuid
    )
      and status = 'completed'
  "
)"

if [[ "$completed_count" != "4" ]]; then
  echo "::error::expected 4 seeded historical sales completed, got ${completed_count}"
  exit 1
fi

token_count="$(
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -tAc "
    select count(*)::text from private.sale_completion_tokens
  "
)"

if [[ "$token_count" != "0" ]]; then
  echo "::error::expected no sale_completion_tokens after seed, got ${token_count}"
  exit 1
fi

echo "seed.sql completed historical sales and left no completion tokens"
