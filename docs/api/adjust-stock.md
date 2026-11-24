# `adjust_stock` RPC

Manual shelf corrections for owners and managers. `product_variants.stock_qty` cannot be updated directly over the API (column-level grants); stock changes go only through **`adjust_stock`** or **`commit_sale`**.

## Signature

```sql
create function public.adjust_stock(
  p_variant_id uuid,
  p_delta integer,
  p_reason text
) returns integer
language plpgsql
security definer
set search_path = ''
```

Returns the variant’s new `stock_qty` after the adjustment.

## Arguments

| Argument | Meaning |
| --- | --- |
| `p_variant_id` | `product_variants.id` to adjust. |
| `p_delta` | Signed integer change to `stock_qty` (non-zero). |
| `p_reason` | Non-empty explanation stored on the ledger row (trimmed, at most 500 characters). |

## Behaviour

1. **Staff gate** — Caller must be `authenticated` with `private.current_app_role()` in `owner` / `manager`. Cashiers, `anon`, and `service_role` are rejected (`42501`).
2. **Validation** — `p_delta <> 0`; trimmed `p_reason` must be non-empty and at most 500 characters; otherwise `P0004`.
3. **Lock and apply** — Locks the variant row `FOR UPDATE`. Unknown variant → `P0002`. Uses 64-bit arithmetic: if `stock_qty + p_delta < 0` → `PSTCK`; if the result would exceed PostgreSQL `integer` max (`2147483647`) → `22003`. No row is written on failure.
4. **Ledger** — Updates `product_variants.stock_qty` and appends one `stock_movements` row with `sale_id` / `sale_item_id` null, plus `reason`, `actor_id` (`auth.uid()`), and `qty_delta`.

`stock_movements` stays append-only: clients cannot `INSERT` / `UPDATE` / `DELETE`, and a database trigger rejects `UPDATE` / `DELETE` even for privileged roles. Sale rows still come from `commit_sale` only.

Owners and managers may still update catalogue columns on `product_variants` (`price_pesewas`, SKU, etc.) directly; only `stock_qty` is reserved for this RPC and `commit_sale`. `service_role` cannot `UPDATE` the `stock_qty` column directly either.

## Errors

| SQLSTATE | Meaning |
| --- | --- |
| `42501` | Caller is not an authenticated owner or manager. |
| `P0002` | Unknown `p_variant_id`. |
| `P0004` | Zero delta, empty reason, or reason longer than 500 characters. |
| `PSTCK` | Adjustment would drive `stock_qty` below zero. |
| `22003` | Adjustment would exceed maximum `stock_qty`. |