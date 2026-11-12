-- POS-AUTH-01f: sales/sale_items DML grants, invite caller gate, case-insensitive email.

-- ---------- (a) sales / sale_items: no client-side DML ----------

revoke insert, update, delete on table public.sales from service_role;
revoke insert, update, delete on table public.sale_items from service_role;

revoke insert, update, delete on table public.sale_items from authenticated;

revoke insert, delete on table public.sales from authenticated;

-- Column-level void/update grant for owner and manager (init_pos) must remain.

-- ---------- bootstrap email normalization (Auth enforces unique emails) ----------

create or replace function private.bootstrap_first_owner(p_email text)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  target uuid;
  normalized text := lower(trim(p_email));
begin
  if session_user not in ('postgres', 'supabase_admin')
     or current_user <> session_user then
    raise exception 'bootstrap is SQL-editor only'
      using errcode = '42501';
  end if;
  perform 1 from private.bootstrap_state where id for update;
  if (select owner_bootstrapped_at from private.bootstrap_state) is not null
     or exists (
       select 1 from auth.users as u
       where u.raw_app_meta_data ->> 'role' = 'owner'
     ) then
    raise exception 'owner already bootstrapped'
      using errcode = '42501';
  end if;
  select u.id
  into strict target
  from auth.users as u
  where lower(trim(u.email)) = normalized;
  update auth.users as u
  set raw_app_meta_data = coalesce(u.raw_app_meta_data, '{}'::jsonb) || '{"role":"owner"}'::jsonb
  where u.id = target;
  update private.bootstrap_state
  set owner_bootstrapped_at = pg_catalog.now();
  return target;
end;
$$;

-- ---------- (c) invite rate limit: service_role + owner/manager caller only ----------

create or replace function private.consume_staff_invite_slot(p_caller uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  bucket timestamptz := date_trunc('hour', pg_catalog.now());
  cnt integer;
  caller_role text;
begin
  if coalesce((select auth.jwt() ->> 'role'), '') is distinct from 'service_role' then
    raise exception 'invite rate limit is service only'
      using errcode = '42501';
  end if;

  select u.raw_app_meta_data ->> 'role'
  into caller_role
  from auth.users as u
  where u.id = p_caller;

  if caller_role is null or caller_role not in ('owner', 'manager') then
    raise exception 'invite rate limit requires owner or manager caller'
      using errcode = '42501';
  end if;

  insert into private.staff_invite_buckets as b (caller_id, bucket_start, invite_count)
  values (p_caller, bucket, 1)
  on conflict (caller_id, bucket_start) do update
  set invite_count = b.invite_count + 1
  returning invite_count into cnt;
  if cnt > 10 then
    raise exception 'invite rate limit exceeded'
      using errcode = 'P0004';
  end if;
end;
$$;
