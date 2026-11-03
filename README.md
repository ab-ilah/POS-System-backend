# POS-System-backend

Backend for a clothing-store point of sale in Ghana. This repository is the database, row level security, seed data, and operations. The React app lives in [ab-ilah/POS-system-](https://github.com/ab-ilah/POS-system-) and is out of scope here.

Amounts are whole pesewas. 100 pesewas is 1 cedi. Shelf prices already include tax. There is no fractional column and no card-number column.

## Projects

Both projects are on the Supabase Free plan in `eu-west-2`. Refs are not keys.

| Environment | Ref | API URL |
| --- | --- | --- |
| staging | `hnbvmxebzaocdttlteib` | `https://hnbvmxebzaocdttlteib.supabase.co` |
| production | `vasbjwzykqoebbtvqnjx` | `https://vasbjwzykqoebbtvqnjx.supabase.co` |

Why London, and what Act 843 still needs from a lawyer: `docs/adr/0002-hosting-region.md`.

## Local development

Requirements: Docker, Node.js 22, and a checkout of this repo. The Supabase CLI is installed from `package.json` (`supabase` 3.0.0). You do not need hosted credentials to run the local stack.

```bash
npm ci
npx supabase start
npx supabase db reset
npm test
npm run test:rls
```

`supabase start` then `supabase db reset` applies `supabase/migrations` and `supabase/seed.sql`. The local database URL is the public demo URL:

`postgresql://postgres:postgres@127.0.0.1:54322/postgres`

Seed staff (local database fixtures, one per role):

| Email | Role |
| --- | --- |
| `owner@example.com` | owner |
| `manager@example.com` | manager |
| `cashier@example.com` | cashier |
| `spare.cashier@example.com` | cashier, deleted by the RLS suite and rolled back |

The seed inserts `auth.users` (with `raw_app_meta_data.role`) and `profiles`. It does not insert `auth.identities`, because that table is owned by `supabase_admin` and the seed role cannot write it. The RLS suite does not log in through GoTrue. It sets the user id on the database session. `encrypted_password` is still `local-dev-only` so a later auth-admin step can attach an identity without inventing a new password. Do not treat these rows as hosted accounts.

Do not load this seed on staging or production. The deploy workflow does not pass `--include-seed`.

Regenerate the seed after editing `supabase/seed/*.ts`:

```bash
npm run seed:generate
```

`npm test` fails if `supabase/seed.sql` drifts from the generator.

Other checks:

```bash
npm run typecheck
npm run lint
npm run secrets:scan
deno check supabase/functions/health/index.ts
```

The health edge function returns `{ "ok": true }` and reads no tables. `verify_jwt` is off only for that function. A function that reads the database must not copy that setting. The service-role key is never a client key: it belongs in Edge Function secrets or another server-side store, not in this repo and not in the React bundle.

## Roles

The frontend imports `shared/permissions.matrix.ts` directly. That file has no imports of its own. It exports `PERMISSIONS_MATRIX` (each row is `{ role, table, operation, decision }`, and `decision` is `allow` or `deny`), `ROLES`, and the types `Role`, `TableName`, `Operation`, `Decision`, and `PermissionRow`. Row scope that a boolean cannot express is in `PERMISSION_SCOPE_NOTES` and in the SQL policies: a user with no role sees nothing, a cashier sees only their own profile, a line can be added only to that staff member's own sale, a sale update can only void it, and only the owner can change `credit_balance_pesewas`. CI checks every matrix row. A mismatch fails the `rls` job.

The role itself lives in `auth.users.raw_app_meta_data.role` (`app_metadata` on the token after refresh). RLS reads that column, not `user_metadata`. Signup creates a profile and does not assign a role. An owner or manager assigns one with `public.assign_staff_role`. The first owner is a one-off server-side update: `docs/runbooks/bootstrap-owner.md`.

### How the frontend should consume the matrix

Publish this file as a dependency-free package, recommended name `@pos/permissions`, and pin that version in `ab-ilah/POS-system-`. Import `PERMISSIONS_MATRIX` and read `row.decision`. A permission change then shows up as a version bump the frontend can review. Copying the file by hand will drift from these RLS tests. Until the package is published, a copied file plus the backend git SHA in the frontend PR is only a bridge. This shape change means any pin or copy taken from the first scaffold commit has to be re-synced after merge.

## Layout

| Path | Purpose |
| --- | --- |
| `supabase/config.toml` | Local stack. Public signup is off. `private` is not an API schema. |
| `supabase/migrations` | Schema and RLS |
| `supabase/seed/*.ts` | Seed source. Generates `supabase/seed.sql` |
| `supabase/functions/health` | Deno health function |
| `shared/permissions.matrix.ts` | Role matrix |
| `tests/` | Unit tests and the RLS suite |
| `scripts/` | Secret scan, keepalive, backup |
| `docs/` | Protection, rotation, restore, backups, ADR |

## Secrets Gabriel adds

Commit no values. CI (`ci.yml`) references no secrets, so a fork pull request has none to read. Do not switch that workflow to `pull_request_target`.

Connection strings are the **session pooler** URI (host `*.pooler.supabase.com`, port **5432**, user `postgres.<project-ref>`). GitHub-hosted runners are IPv4-only. The Free-plan direct host is often IPv6-only, and the transaction pooler on port 6543 cannot dump or migrate. Percent-encode the password.

### Environment `staging`

| Secret | Used by |
| --- | --- |
| `SUPABASE_ACCESS_TOKEN` | Deploy database |
| `STAGING_DB_URL` | Deploy database, Keepalive |

### Environment `production`

Required reviewer: Gabriel. Manual production migrations and the signup lock only. The job runs only from `main`.

| Secret | Used by |
| --- | --- |
| `SUPABASE_ACCESS_TOKEN` | Deploy database, including the auth config call that sets `disable_signup` |
| `PROD_DB_URL` | Deploy database. The same value is also on `prod-ops`. Do not copy it into `staging`. |

### Environment `prod-ops`

No required reviewer. Daily production keepalive and the nightly backup. Do not put the access token here, and do not use this environment for migrations.

| Secret | Used by |
| --- | --- |
| `PROD_DB_URL` | Keepalive, Backup database |
| `BACKUP_S3_ENDPOINT` | Backup database |
| `BACKUP_S3_BUCKET` | Backup database |
| `BACKUP_S3_REGION` | Backup database. `auto` for Cloudflare R2. |
| `BACKUP_S3_ACCESS_KEY_ID` | Backup database. Write-only if the provider allows it. |
| `BACKUP_S3_SECRET_ACCESS_KEY` | Backup database |
| `BACKUP_S3_FORCE_PATH_STYLE` | Optional. `true` when the provider wants path-style URLs. |
| `BACKUP_MIN_BYTES` | Optional. Refuse dumps smaller than this. Default 8192. |

The backup host is not chosen yet. The same variables work for Cloudflare R2 or Backblaze B2. Retention (14 daily, 8 weekly) is a bucket lifecycle rule, documented in `docs/backup/README.md`. The age public key in `docs/backup/age.pub` is a placeholder until Gabriel replaces it. Backups fail on purpose until then.

Service-role and `sb_secret_` keys are not in this list. They do not belong in CI.

## Operations

| Workflow | When |
| --- | --- |
| `CI` | Pull requests and pushes to `main`. Install, typecheck, lint, unit tests, secret scan, `supabase start`, `supabase db reset`, RLS suite. |
| `Deploy database` | Push to `main` migrates staging and turns signup off. Production is manual, from `main` only, and waits on the production environment. |
| `Keepalive` | Every day at 06:15 UTC. Reads `products`, `customers`, and `sales`. Production uses `prod-ops`. |
| `Backup database` | 02:00 UTC, `main` only, `prod-ops`. |

Hosted signup is turned off by the deploy workflow (`docs/runbooks/disable-signup.md`). The manual dashboard step in that runbook is the fallback if the workflow cannot run.

Runbooks:

- `docs/branch-protection.md`
- `docs/runbooks/bootstrap-owner.md`
- `docs/runbooks/disable-signup.md`
- `docs/runbooks/key-rotation.md`
- `docs/runbooks/restore.md`
- `docs/backup/README.md`
