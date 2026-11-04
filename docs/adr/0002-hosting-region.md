# ADR 0002: Host Supabase in eu-west-2

Status: Accepted for the projects that already exist. Gabriel still needs to confirm the Ghana data-protection points with a lawyer before go-live. This note is not legal advice.

## Context

The shop is in Ghana. Supabase has no Africa region. The projects are already on the Free plan in London:

- staging ref `hnbvmxebzaocdttlteib`
- production ref `vasbjwzykqoebbtvqnjx`

Both are in `eu-west-2`.

## Decision

Stay on `eu-west-2`.

London is a shorter round trip from Accra than a US region, and the UK is a familiar hosting jurisdiction for a small shop that cannot wait for an African Supabase region. Moving later is a project migration, not a config change, so the region is fixed unless latency or the legal review says otherwise.

## Ghana Data Protection Act, 2012 (Act 843)

Flagged for Gabriel to confirm with legal advice before customer data is stored for real:

- The shop may need to register with the Data Protection Commission as a data controller.
- Customers should be told that their personal data is stored outside Ghana, in the UK (`eu-west-2`).
- Collect less. This schema stores staff profiles, customer name and phone, the amount owed, and sales lines. It does not store card numbers, and it must not grow a column for them. Card payments, if they are added later, belong at a payment processor.
- Cross-border transfer rules under Act 843 need a qualified reading for UK hosting. Do not treat this ADR as that reading.

## Consequences

- Connection strings used from GitHub Actions must be the IPv4 session pooler. That is an operations detail, documented in the README, not a reason to change region.
- The frontend must not embed a service-role or secret key. Region choice does not change that.
