# Branch protection and repository security

Gabriel applies these settings in GitHub. The workflow files cannot enforce them.

## Branch rule for `main`

Settings → Rules → Rulesets, or Settings → Branches → Add classic branch protection rule. Target `main`.

- Require a pull request before merging.
- Require 1 approval. Gabriel is the reviewer. GitHub's classic rule counts any person with write access, so also add a ruleset or code owner rule that names his GitHub login once he confirms it. Do not put a guessed login in this repo.
- Require status checks to pass before merging. After the first CI run on this repo, require both jobs from the CI workflow: `verify` and `rls`.
- Require branches to be up to date before merging.
- Do not allow force pushes.
- Do not allow deletions.
- Include administrators. Leave "allow administrators to bypass" off, and do not add a bypass list.
- Do not use `pull_request_target` workflows. CI does not read secrets, so a fork pull request has nothing to steal.

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

Used by the staging database push and the staging keepalive.

### `production`

Required reviewer: Gabriel. This is what gates the manual production database push.

Secrets:

- `SUPABASE_ACCESS_TOKEN`
- `PROD_DB_URL` (this value must not also be stored on `staging`)
- `BACKUP_S3_ENDPOINT`
- `BACKUP_S3_BUCKET`
- `BACKUP_S3_REGION`
- `BACKUP_S3_ACCESS_KEY_ID`
- `BACKUP_S3_SECRET_ACCESS_KEY`
- `BACKUP_S3_FORCE_PATH_STYLE` (optional; set the secret to `true` only if the provider needs path-style URLs)
- `BACKUP_MIN_BYTES` (optional; the script defaults when this is empty)

GitHub attaches required reviewers to the environment, not to a single workflow. The same reviewer rule also holds the nightly backup and the production keepalive until someone approves the run. A run that sits pending does not ping the database and does not upload a backup. Free projects pause after about a week without traffic, so a keepalive waiting on a click during a shop closure misses the point.

Gabriel should keep the required reviewer on production, and approve the scheduled backup and keepalive runs (or adjust the environment rule if GitHub later supports a per-workflow exception). Do not copy `PROD_DB_URL` into an unprotected environment to dodge the review.

## Project refs

These are identifiers, not keys.

| Environment | Project ref | Region |
| --- | --- | --- |
| staging | `hnbvmxebzaocdttlteib` | eu-west-2 |
| production | `vasbjwzykqoebbtvqnjx` | eu-west-2 |
