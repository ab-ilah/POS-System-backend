# Branch protection and repository security

Gabriel applies these settings in GitHub. The workflow files cannot enforce them.

## Flow: `staging` → `main`

Integration work merges into **`staging`**. That branch auto-deploys to **pos-staging** when migrations land. **Only Gabriel promotes** from `staging` to `main` (production path). Nobody else merges to `main`.

Typical sequence:

1. Open a pull request **into `staging`**. CI (`verify`, `rls`) must pass.
2. Merge the PR to `staging`. The deploy workflow migrates the staging Supabase project.
3. When staging is verified, Gabriel opens a promotion PR **`staging` → `main`** and merges it. A pull request is required for both `staging` and `main`; direct pushes to either branch are not allowed. Only Gabriel merges or promotes.
4. After merge to `main`, Gabriel runs the **manual** production database deploy. In GitHub Actions, open **Deploy database**, choose **Run workflow**, pick branch **`main`** in **Use workflow from**, set target **production**, and run. Production signup lock and prod migrations stay gated on the `production` environment.

Do not push directly to `staging` or `main`. Branch protection must block direct pushes to **`staging`**, because a push to `staging` deploys to pos-staging.

### Staging manual rerun

The **Deploy database** workflow can also be run manually for **staging** when a migrate needs a rerun (for example, after a transient failure). **Only Gabriel or repo admins** may do this. In **Use workflow from**, pick branch **`staging`**, set target **staging**, and run. This path is for reruns only; normal schema changes land via merge to `staging`. The job's `github.ref == 'refs/heads/staging'` guard skips deploy when the workflow is dispatched from any other ref.

## Branch rule for `staging`

Settings → Rules → Rulesets, or classic branch protection. Target `staging`.

- Require a pull request before merging.
- Require 1 approval (Gabriel or delegate per team policy).
- Require status checks: `verify` and `rls` from the CI workflow.
- Require branches to be up to date before merging.
- Do not allow force pushes.
- Do not allow deletions.
- Include administrators. Leave "allow administrators to bypass" off, and do not add a bypass list.

## Branch rule for `main`

Same protections as `staging`, applied to `main`:

- Require a pull request before merging.
- Require 1 approval. Gabriel is the reviewer for production promotion. Add a ruleset or code owner rule that names his GitHub login once confirmed.
- Require status checks: `verify` and `rls`.
- Require branches to be up to date before merging.
- Do not allow force pushes.
- Do not allow deletions.
- Include administrators. Leave "allow administrators to bypass" off, and do not add a bypass list.

Do not use `pull_request_target` workflows. CI does not read secrets, so a fork pull request has nothing to steal.

## Secret scanning

Settings → Code security and analysis:

- Enable Dependabot alerts and Dependabot security updates. `.github/dependabot.yml` already opens weekly update PRs for npm and GitHub Actions.
- Enable Secret scanning.
- Enable Push protection.

The CI secret scan is a second gate. It fails the pull request if the diff or the tree contains a `service_role` JWT, a key with the `sb_secret_` prefix, or any JWT whose payload role is not `anon`. It does not replace GitHub secret scanning.

## Environments

Settings → Environments.

### `staging`

No required reviewer. Secrets (names only; Gabriel pastes the values):

- `SUPABASE_ACCESS_TOKEN`
- `STAGING_DB_URL`

Used by the staging database push (on **`staging`** branch) and the staging keepalive.

Deployment branches: Selected branches, **`main`** and **`staging`**. `main` is needed so the staging keepalive can run from the default branch; migrations use `staging`.

### `production`

Required reviewer: Gabriel. This gates the manual production database push and the auth-config update that turns signup off.

Deployment branches: Selected branches, **`main` only**. The workflow also refuses the job unless `github.ref` is `refs/heads/main`. Set the environment rule as well, so a workflow edit cannot widen the gate by itself.

Secrets:

- `SUPABASE_ACCESS_TOKEN`
- `PROD_DB_URL` (also stored on `prod-ops` for backups and the daily ping; never on `staging`)

### `prod-ops`

No required reviewer. This environment exists so the daily production keepalive and the nightly backup do not wait for an approval. It must not be used for migrations.

Deployment branches: Selected branches, **`main` only**. The keepalive and backup jobs also require `github.ref == 'refs/heads/main'`. A manual run from another branch must not reach production.

Secrets, and nothing else:

- `PROD_DB_URL`
- `BACKUP_S3_ENDPOINT`
- `BACKUP_S3_BUCKET`
- `BACKUP_S3_REGION`
- `BACKUP_S3_ACCESS_KEY_ID`
- `BACKUP_S3_SECRET_ACCESS_KEY`
- `BACKUP_S3_FORCE_PATH_STYLE` (optional; set the secret to `true` only if the provider needs path-style URLs)
- `BACKUP_MIN_BYTES` (optional; the script defaults when this is empty)

Do not put `SUPABASE_ACCESS_TOKEN` here. Do not add Gabriel as a required reviewer. A reviewer on `prod-ops` would pause the Free project during a shop closure and would skip backups.

## Project refs

These are identifiers, not keys.

| Environment | Project ref | Region |
| --- | --- | --- |
| staging | `hnbvmxebzaocdttlteib` | eu-west-2 |
| production | `vasbjwzykqoebbtvqnjx` | eu-west-2 |
