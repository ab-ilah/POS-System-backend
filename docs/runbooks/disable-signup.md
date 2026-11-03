# Turn off hosted signup

Local `supabase/config.toml` already has `enable_signup = false`. Hosted projects do not read that file until a deploy pushes the auth setting.

## What the deploy does

The Deploy database workflow, after a successful `supabase db push`, runs `npm run auth:disable-signup`. That sends:

```http
PATCH https://api.supabase.com/v1/projects/<ref>/config/auth
Authorization: Bearer $SUPABASE_ACCESS_TOKEN
Content-Type: application/json

{"disable_signup": true}
```

Staging ref: `hnbvmxebzaocdttlteib`, environment `staging`.
Production ref: `vasbjwzykqoebbtvqnjx`, environment `production`, and only from `main`.

The script refuses to continue unless the response has `disable_signup` set. It does not print the response body, because that payload can contain provider secrets.

This is not `supabase config push`. Pushing the whole local config would also copy local URLs and ports onto the hosted project.

## Manual fallback

If the workflow cannot run, Gabriel does it himself. Either is enough.

Dashboard: Authentication → Sign In / Providers → turn off "Allow new users to sign up". Save. Repeat on staging and on production.

Or, on a trusted machine, with a Supabase access token that is allowed to write auth config:

```bash
curl -fsS -X PATCH \
  "https://api.supabase.com/v1/projects/hnbvmxebzaocdttlteib/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"disable_signup": true}'
```

Run it again with `vasbjwzykqoebbtvqnjx` for production. Do not commit the token. Do not paste the JSON response into git or into a chat. Check the dashboard afterwards: new signups must be rejected.
