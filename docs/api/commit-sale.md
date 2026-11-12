# `commit_sale` RPC

Implements the frontend contract in [ab-ilah/POS-system-](https://github.com/ab-ilah/POS-system-) (`src/types/database.ts`, `docs/commit-sale.md`).

## Signature

```sql
create function public.commit_sale(
  p_idempotency_key uuid,
  p_store_id uuid,
  p_lines jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
```

## Return value

```json
{ "sale_id": "<uuid>", "replayed": false, "status": "completed" }
```

On idempotency replay with the same store and lines and the same cashier (`sales.cashier_id = auth.uid()`), `replayed` is `true`, `status` reflects the stored sale (`completed`, `voided`, etc.), and the function performs no writes. Replay is resolved before catalog/stock/price checks so a prior commit still replays after stock or shelf drift. A second call with the same key but a different store, line payload, or cashier raises `P0004` / `idempotency_key_conflict`. Validation (non-empty lines, store, and line shape) runs before any idempotency lookup, so some errors do not reveal whether an id is already taken.

## Arguments

| Argument | Meaning |
| --- | --- |
| `p_idempotency_key` | Client-generated sale id (becomes `sales.id`). |
| `p_store_id` | Store for the receipt. |
| `p_lines` | JSON array of `{ "id", "variant_id", "quantity", "unit_price_pesewas" }`. Line ids must be unique. Quantities and prices are integers (tax-inclusive pesewas). |

## Behaviour

1. **Staff only** — `auth.role()` and JWT `role` must be `authenticated`, with `app_metadata.role` in `owner` / `manager` / `cashier`. `anon` and `service_role` are rejected (`42501`). The function runs as **SECURITY DEFINER** and enforces the same rules RLS would (store exists, active catalog variant, `cashier_id = auth.uid()`).
2. **Idempotency** — Transaction-scoped advisory lock on the key. An existing `sales` row with the same store and `sale_items` snapshot returns the replay payload with no extra lines, stock moves, or stock changes. A payload mismatch raises `P0004`.
3. **One transaction** — Insert `open` sale, `sale_items`, `stock_movements`, decrement `product_variants.stock_qty` (via `private.stock_qty_apply_for_commit`), then set `completed`. Any failure rolls back everything.
4. **Stock** — Variants are locked `FOR UPDATE` in a deterministic `variant_id` order. Required quantities are summed per `variant_id` across all lines before the stock check. Sales that would drive stock below zero raise `PSTCK` / `insufficient stock`.
5. **Pricing** — Each line’s `unit_price_pesewas` must match the current shelf `price_pesewas`. Header `total_pesewas` is computed as `sum(quantity * unit_price_pesewas)`; tendered equals total with zero change and no credit on commit.
6. **Triggers** — Inserts lines on an `open` sale, then completes through the existing sale update rules.

## Schema notes

- Line rows stay in **`sale_items`** (`qty` column). The RPC JSON field is `quantity`; it maps to `sale_items.qty`. The frontend (PR #6) already targets `sale_items`, so this migration does **not** rename the table.
- **`stores`** and **`stock_movements`** (`sale_item_id` FK) were added. Re-sync `shared/permissions.matrix.ts` in the frontend after merge.

## Errors

| SQLSTATE | Message |
| --- | --- |
| `42501` | Caller is not authenticated staff. |
| `PSTCK` | Insufficient stock. `details` is `variant_id=<uuid>` for the variant that failed the pre-check. |
| `P0002` | Unknown store or variant. |
| `P0003` | Unit price does not match shelf price. |
| `P0004` | Invalid or empty lines payload; or `idempotency_key_conflict` when the key exists for another cashier or with a different store/lines payload. |
| `P0005` | Duplicate line id in one call. |
