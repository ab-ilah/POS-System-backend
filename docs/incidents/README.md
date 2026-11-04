# Incidents

When a credential leaks, add `docs/incidents/YYYY-MM-DD-short-title.md` after the response in `docs/runbooks/key-rotation.md`.

Include:

- when it was noticed
- what leaked (the name of the credential, not the value)
- when it was rotated and when the old value was revoked
- what the Supabase and object-storage logs showed
- whether git history was purged

Do not paste secrets, connection strings, or the age private key.
