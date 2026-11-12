-- Restrict the commit_sale completion bypass to postgres executing the definer UPDATE.
-- service_role must not complete sales even with a forged authenticated JWT claim.

create or replace function private.enforce_sale_update()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.status = 'voided' then
    raise exception 'a voided sale is frozen'
      using errcode = '42501';
  end if;
  if not (
    private.session_is_trusted_db()
    or (
      current_user in ('postgres', 'supabase_admin')
      and (select auth.role()) = 'authenticated'
      and coalesce((select auth.jwt() ->> 'role'), '') = 'authenticated'
      and private.session_staff_app_role() in (
        'owner'::public.app_role,
        'manager'::public.app_role,
        'cashier'::public.app_role
      )
      and old.status = 'open'
      and new.status = 'completed'
      and new.void_reason is null
      and new.voided_at is null
    )
    or (
      current_user = 'authenticated'
      and coalesce((select auth.jwt() ->> 'role'), '') = 'authenticated'
      and private.current_app_role() in ('owner'::public.app_role, 'manager'::public.app_role)
    )
  ) then
    raise exception 'only an owner or manager can update a sale'
      using errcode = '42501';
  end if;
  if new.receipt_no is distinct from old.receipt_no
     or new.customer_id is distinct from old.customer_id
     or new.cashier_id is distinct from old.cashier_id
     or new.subtotal_pesewas is distinct from old.subtotal_pesewas
     or new.total_pesewas is distinct from old.total_pesewas
     or new.tendered_pesewas is distinct from old.tendered_pesewas
     or new.change_pesewas is distinct from old.change_pesewas
     or new.credit_applied_pesewas is distinct from old.credit_applied_pesewas
     or new.sold_at is distinct from old.sold_at
     or new.created_at is distinct from old.created_at
  then
    raise exception 'sale amounts and identity columns are immutable'
      using errcode = '42501';
  end if;
  if new.status is distinct from old.status
     and not (
       old.status = 'open'
       and new.status = 'completed'
       and new.void_reason is null
       and new.voided_at is null
     )
     and new.status <> 'voided' then
    raise exception 'a sale can only be completed from open, or voided'
      using errcode = '42501';
  end if;
  if new.status = 'voided' and (new.void_reason is null or length(btrim(new.void_reason)) = 0) then
    raise exception 'voiding a sale requires a reason'
      using errcode = '42501';
  end if;
  if new.status = 'voided' and old.status is distinct from 'voided' and new.voided_at is null then
    new.voided_at := pg_catalog.now();
  end if;
  return new;
end;
$$;
