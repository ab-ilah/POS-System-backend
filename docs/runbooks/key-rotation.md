# Key rotation

Owner: Gabriel.

Cadence: every 90 days, and immediately after any leak. Record the date of each routine rotation in a new file under `docs/key-rotations/`. Record a leak in `docs/incidents/`.

## What is in scope

- `SUPABASE_ACCESS_TOKEN` (Supabase account access token)
- Database passwords inside `STAGING_DB_URL` and `PROD_DB_URL`
- `BACKUP_S3_ACCESS_KEY_ID` and `BACKUP_S3_SECRET_ACCESS_KEY`
- The age backup identity (the private key that matches `docs/backup/age.pub`)
- Supabase `service_role` JWTs and `sb_secret_` keys, which live in the Supabase dashboard and in Edge Function secrets, never in this repo
- Publishable or anon keys, when the dashboard rotation replaces them

## Scheduled rotation

1. Make a new credential before deleting the old one, so a running job is not stranded.
2. Supabase account token: Dashboard → Account → Access Tokens. Create a new token, update `SUPABASE_ACCESS_TOKEN` on both the `staging` and `production` environments, revoke the old token.
3. Database password: Dashboard → Project Settings → Database. Reset the password, rebuild the session-pooler URI, and update `STAGING_DB_URL` or `PROD_DB_URL` in the matching environment only. Use the session pooler (port 5432 on `*.pooler.supabase.com`, user `postgres.<project-ref>`). GitHub-hosted runners are IPv4-only. The direct host on the Free plan is often IPv6-only, and the transaction pooler (port 6543) cannot run `pg_dump` or migrations.
4. Object-storage keys: create a new key that can write the backup bucket and nothing else, update the `BACKUP_S3_*` secrets, confirm the next backup (or a manual `workflow_dispatch` of Backup database) uploads an `.age` object, then delete the old key.
5. Age key: generate a new identity on a trusted machine, commit only the new public recipient in `docs/backup/age.pub`, keep two offline copies of the new private key, and keep the previous private key until every backup encrypted to the old recipient has expired (14 daily, 8 weekly).
6. Service-role and secret API keys: rotate them in the Supabase dashboard. Put the new value only in Edge Function secrets or another server-side store. Do not put it in GitHub Actions for this repo's CI, and do not put it anywhere a browser bundle can see.
7. Write `docs/key-rotations/YYYY-MM-DD.md` with the date, which credentials moved, and who did it. Do not paste the new values.

## Leak response

Do this within 1 hour of discovering a leak. Finish rotation before the write-up.

1. Rotate the leaked credential using the steps above. A leaked database URL means reset that project's database password. A leaked service-role or `sb_secret_` key means revoke it in the dashboard immediately.
2. Revoke the old credential after the new one is in place. Confirm the old value no longer authenticates.
3. Check logs. Supabase Dashboard → Logs for the affected project (API, Postgres, Auth). For object storage, check that provider's access logs for the backup bucket. Note anything unexpected (unknown IPs, dumps, schema changes).
4. If the value was committed, purge it from git history (`git filter-repo` or the GitHub secret-scanning remediation flow) and tell anyone with a clone to delete it. History purge is not a substitute for rotation. Assume the value was copied.
5. Record the incident in `docs/incidents/YYYY-MM-DD-short-title.md`: when it was noticed, what leaked, when rotation and revocation finished, what the logs showed, and the history-purge result. Do not include the secret itself.
