# First owner and later staff

Signup is off. A new auth user gets a profile and no role, so row level security allows nothing until someone assigns `auth.users.raw_app_meta_data.role`. The client never sends that value. `user_metadata` is ignored.

Do this from the Supabase SQL editor or another server-side session. Do not put the service-role key in the React app, and do not run it from a browser.

## Bootstrap the first owner

Gabriel creates the auth user in the dashboard (Authentication → Users → Add user) or with the Auth admin API using the service-role key on a trusted machine. The trigger inserts a profile and does not set a role.

Then, in the SQL editor for that project:

```sql
update auth.users
set raw_app_meta_data =
  coalesce(raw_app_meta_data, '{}'::jsonb)
  || jsonb_build_object('role', 'owner')
where email = 'owner@example.com';
```

Replace the email with the real owner address. Confirm:

```sql
select email, raw_app_meta_data ->> 'role' as role
from auth.users
where email = 'owner@example.com';
```

The role must be `owner`. Ask the owner to sign in again so their token picks up `app_metadata`. Row level security reads the table, so the new role applies on the next request even before that refresh. The Data API JWT stays stale until refresh, which matters for anything that trusts the token claim instead of the table.

## Invite the rest of the staff

1. Create the auth user the same server-side way. They can sign in and still see no rows.
2. The owner or a manager assigns the role. From a session signed in as that owner or manager:

```sql
select public.assign_staff_role('<user-uuid>'::uuid, 'cashier');
```

`cashier` or `manager` are the other values. A manager cannot assign `owner` and cannot change the existing owner. The function writes `raw_app_meta_data.role` and nothing else.

There is no public signup path for this. See `docs/runbooks/disable-signup.md`.
