#!/usr/bin/env bash
# Nightly custom-format dump, age-encrypted, uploaded to S3-compatible storage.
# Plaintext is deleted before the script exits. Only the .age object is uploaded.
# Secrets come from the environment, never from argv.

set -euo pipefail

required=(
  PROD_DB_URL
  BACKUP_S3_ENDPOINT
  BACKUP_S3_BUCKET
  BACKUP_S3_REGION
  BACKUP_S3_ACCESS_KEY_ID
  BACKUP_S3_SECRET_ACCESS_KEY
)

for name in "${required[@]}"; do
  if [ -z "${!name:-}" ]; then
    echo "missing required env: ${name}" >&2
    exit 1
  fi
done

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
pub_key="${repo_root}/docs/backup/age.pub"
recipient=$(mktemp)
trap 'rm -f "$recipient"' EXIT

grep -vE '^[[:space:]]*#' "$pub_key" | grep -vE '^[[:space:]]*$' > "$recipient" || true
if grep -q 'PLACEHOLDER' "$recipient" || ! grep -q '^age1' "$recipient"; then
  echo "docs/backup/age.pub is still a placeholder. Gabriel must commit a real age public key." >&2
  exit 1
fi

workdir=$(mktemp -d)
plaintext="${workdir}/pos.dump"
encrypted="${workdir}/pos.dump.age"

wipe() {
  if [ -f "$plaintext" ]; then
    if command -v shred >/dev/null 2>&1; then
      shred -u "$plaintext" || rm -f "$plaintext"
    else
      rm -f "$plaintext"
    fi
  fi
  rm -rf "$workdir"
  rm -f "$recipient"
}
trap wipe EXIT

major=$(node --input-type=module <<'NODE'
import postgres from "postgres";

const url = process.env.PROD_DB_URL;
if (!url) {
  console.error("PROD_DB_URL is not set");
  process.exit(1);
}
const sql = postgres(url, {
  max: 1,
  prepare: false,
  ssl: "require",
  connect_timeout: 20,
});
try {
  const rows = await sql`select current_setting('server_version') as version`;
  const version = String(rows[0]?.version ?? "");
  const serverMajor = version.split(".")[0] ?? "";
  if (!/^[0-9]+$/.test(serverMajor)) {
    console.error("could not read the Postgres server major version");
    process.exit(1);
  }
  process.stdout.write(serverMajor);
} catch (error) {
  const message = error instanceof Error ? error.message : "unknown error";
  if (message.includes("://") || message.toLowerCase().includes("password")) {
    console.error("could not read the server version (connection error redacted)");
  } else {
    console.error(`could not read the server version: ${message}`);
  }
  process.exit(1);
} finally {
  await sql.end({ timeout: 5 });
}
NODE
)

echo "dumping with postgres:${major}"
docker run --rm --network host \
  -e PROD_DB_URL \
  -v "${workdir}:/out" \
  --entrypoint bash \
  "postgres:${major}" \
  -c 'pg_dump --format=custom --no-owner --no-privileges --file=/out/pos.dump --dbname="$PROD_DB_URL"'

if [ ! -s "$plaintext" ]; then
  echo "pg_dump did not produce a file" >&2
  exit 1
fi

min_bytes="${BACKUP_MIN_BYTES:-8192}"
actual_bytes=$(wc -c < "$plaintext" | tr -d ' ')
if [ "$actual_bytes" -lt "$min_bytes" ]; then
  echo "dump is ${actual_bytes} bytes, below BACKUP_MIN_BYTES=${min_bytes}" >&2
  exit 1
fi

magic=$(head -c 5 "$plaintext" || true)
if [ "$magic" != "PGDMP" ]; then
  echo "dump is not a pg_dump custom-format archive" >&2
  exit 1
fi

age --recipients-file "$recipient" --output "$encrypted" "$plaintext"
wipe_plaintext_only() {
  if [ -f "$plaintext" ]; then
    shred -u "$plaintext" 2>/dev/null || rm -f "$plaintext"
  fi
}
wipe_plaintext_only

if [ ! -s "$encrypted" ] || [[ "$encrypted" != *.age ]]; then
  echo "refusing to upload because the encrypted file is missing or not an .age file" >&2
  exit 1
fi

export AWS_ACCESS_KEY_ID="$BACKUP_S3_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$BACKUP_S3_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="$BACKUP_S3_REGION"
export AWS_REQUEST_CHECKSUM_CALCULATION="${AWS_REQUEST_CHECKSUM_CALCULATION:-when_required}"
export AWS_RESPONSE_CHECKSUM_VALIDATION="${AWS_RESPONSE_CHECKSUM_VALIDATION:-when_required}"

aws_cli() {
  if [ "${BACKUP_S3_FORCE_PATH_STYLE:-}" = "true" ]; then
    aws --endpoint-url "$BACKUP_S3_ENDPOINT" --force-path-style "$@"
  else
    aws --endpoint-url "$BACKUP_S3_ENDPOINT" "$@"
  fi
}

stamp=$(date -u +%Y%m%dT%H%M%SZ)
day_path=$(date -u +%Y/%m/%d)
week=$(date -u +%G-W%V)
daily_key="daily/${day_path}/pos-${stamp}.dump.age"

aws_cli s3 cp "$encrypted" "s3://${BACKUP_S3_BUCKET}/${daily_key}" --only-show-errors
aws_cli s3api head-object --bucket "$BACKUP_S3_BUCKET" --key "$daily_key" >/dev/null

if [ "$(date -u +%u)" = "7" ]; then
  weekly_key="weekly/${week}/pos-${stamp}.dump.age"
  aws_cli s3 cp "$encrypted" "s3://${BACKUP_S3_BUCKET}/${weekly_key}" --only-show-errors
  aws_cli s3api head-object --bucket "$BACKUP_S3_BUCKET" --key "$weekly_key" >/dev/null
  echo "uploaded ${daily_key} and ${weekly_key}"
else
  echo "uploaded ${daily_key}"
fi
