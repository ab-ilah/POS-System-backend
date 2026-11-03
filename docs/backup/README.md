# Database backups

The Backup database workflow dumps production with `pg_dump` in custom format, encrypts it with `age` to the recipient in `docs/backup/age.pub`, deletes the plaintext on the runner, and uploads only the `.age` object.

Nothing is stored as a GitHub Actions artifact, and nothing is committed.

## What Gabriel still has to supply

- A real age public key in `docs/backup/age.pub`. The file shipped here is a placeholder. Backups fail until it is replaced. Generate the identity on a trusted machine:

```bash
age-keygen -o pos-backup-identity.txt
age-keygen -y pos-backup-identity.txt
```

Commit the printed `age1...` line only. Keep `pos-backup-identity.txt`, and keep a second offline copy. See `docs/runbooks/restore.md`.

- The object-storage secrets on the `production` environment. The provider is not chosen yet. The same variables work for Cloudflare R2 or Backblaze B2:

| Secret | Meaning |
| --- | --- |
| `BACKUP_S3_ENDPOINT` | R2 `https://<accountid>.r2.cloudflarestorage.com` or B2 `https://s3.<region>.backblazeb2.com` |
| `BACKUP_S3_BUCKET` | Bucket name |
| `BACKUP_S3_REGION` | R2 uses `auto`. B2 uses the bucket region, such as `eu-central-003`. |
| `BACKUP_S3_ACCESS_KEY_ID` | Write-only credential if the provider can scope it that way |
| `BACKUP_S3_SECRET_ACCESS_KEY` | Matching secret |
| `BACKUP_S3_FORCE_PATH_STYLE` | Optional. Set to `true` when the provider requires path-style addressing |
| `BACKUP_MIN_BYTES` | Optional. Dumps smaller than this fail. Default is 8192 bytes |
| `PROD_DB_URL` | Session pooler URI, port 5432. Not the transaction pooler |

`PROD_DB_URL` stays on the `production` environment only.

## Layout in the bucket

- `daily/YYYY/MM/DD/pos-YYYYMMDDTHHMMSSZ.dump.age` every night
- `weekly/YYYY-Www/pos-YYYYMMDDTHHMMSSZ.dump.age` as well, on Sundays

## Retention

Keep 14 daily objects and 8 weekly objects. The workflow does not delete old objects. Set a lifecycle rule on the bucket so a failed runner cannot be the only thing standing between you and a full disk.

Cloudflare R2 (S3 API `PutBucketLifecycleConfiguration`, or the R2 dashboard):

- Prefix `daily/`: expire after 14 days
- Prefix `weekly/`: expire after 8 weeks

Backblaze B2 (bucket lifecycle settings):

- `daily/`: keep only the last 14 days
- `weekly/`: keep only the last 8 weeks

Apply the rule before the first successful backup, or the bucket will keep every object until someone notices.

## When a backup fails

The job fails if the age key is still the placeholder, if `pg_dump` fails, if the archive is under the size floor or is not a custom-format dump (`PGDMP` header), if encryption fails, or if the upload or the follow-up `head-object` fails. A failure leaves no plaintext on the runner (the script deletes it on the way out) and does not publish an artifact. Fix the cause and re-run the workflow with `workflow_dispatch` from `main`.
