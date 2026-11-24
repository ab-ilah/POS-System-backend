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
| `p_reason` | Non-empty explanation stored on the ledger row (trimmed). |

## Behaviour

1. **Staff gate** — Caller must be `authenticated` with `private.current_app_role()` in `owner` / `manager`. Cashiers, `anon`, and `service_role` are rejected (`42501`).
2. **Validation** — `p_delta <> 0` and trimmed `p_reason` non-empty; otherwise `P0004`.
3. **Lock and apply** — Locks the variant row `FOR UPDATE`. Unknown variant → `P0002`. If `stock_qty + p_delta < 0` → `PSTCK` and no row is written.
4. **Ledger** — Updates `product_variants.stock_qty` and appends one `stock_movements` row with `sale_id` / `sale_item_id` null, plus `reason`, `actor_id` (`auth.uid()`), and `qty_delta`.

`stock_movements` stays append-only: clients cannot `INSERT` / `UPDATE` / `DELETE`; sale rows still come from `commit_sale` only.

Owners and managers may still update catalogue columns on `product_variants` (`price_pesewas`, SKU, etc.) directly; only `stock_qty` is reserved for this RPC and `commit_sale`.

## Errors

| SQLSTATE | Meaning |
| --- | --- |
| `42501` | Caller is not an authenticated owner or manager. |
| `P0002` | Unknown `p_variant_id`. |
| `P0004` | Zero delta or empty reason. |
| `PSTCK` | Adjustment would drive `stock_qty` below zero. |