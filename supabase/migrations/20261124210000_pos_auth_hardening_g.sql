-- POS-AUTH-01g: sole owner, invite slot from JWT, staff role guards.

-- ---------- sole owner: assign_staff_role + write_staff_role ----------

create or replace function private.write_staff_role(target uuid, new_role public.app_role)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller public.app_role;
  existing public.app_role;
begin
  if pg_catalog.current_setting('role', true) is distinct from 'authenticated'
     or coalesce((select auth.jwt() ->> 'role'), '') is distinct from 'authenticated' then
    raise exception 'only an owner or manager can assign a staff role'
      using errcode = '42501';
  end if;
  caller := private.app_role_of((select auth.uid()));
  if caller is null or caller not in ('owner'::public.app_role, 'manager'::public.app_role) then
    raise exception 'only an owner or manager can assign a staff role'
      using errcode = '42501';
  end if;
  if new_role = 'owner'::public.app_role then
    raise exception 'the owner role cannot be assigned here'
      using errcode = '42501';
  end if;
  existing := private.app_role_of(target);
  if existing = 'owner'::public.app_role then
    raise exception 'the owner cannot be reassigned'
      using errcode = '42501';
  end if;
  if caller = 'manager'::public.app_role and existing = 'owner'::public.app_role then
    raise exception 'a manager cannot change the owner'
      using errcode = '42501';
  end if;
  if caller = 'manager'::public.app_role and new_role = 'owner'::public.app_role then
    raise exception 'a manager cannot assign the owner role'
      using errcode = '42501';
  end if;
  update auth.users
  set raw_app_meta_data =
    case
      when raw_app_meta_data is null then pg_catalog.jsonb_build_object('role', new_role)
      else raw_app_meta_data || pg_catalog.jsonb_build_object('role', new_role)
    end
  where id = target;
  if not found then
    raise exception 'no such staff user'
      using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.assign_staff_role(target uuid, new_role public.app_role)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  caller public.app_role;
begin
  if current_user is distinct from 'authenticated'
     or coalesce((select auth.jwt() ->> 'role'), '') is distinct from 'authenticated' then
    raise exception 'only an owner or manager can assign a staff role'
      using errcode = '42501';
  end if;
  caller := private.current_app_role();
  if caller is null or caller not in ('owner'::public.app_role, 'manager'::public.app_role) then
    raise exception 'only an owner or manager can assign a staff role'
      using errcode = '42501';
  end if;
  if new_role = 'owner'::public.app_role then
    raise exception 'the owner role cannot be assigned here'
      using errcode = '42501';
  end if;
  if private.target_is_owner(target) then
    raise exception 'the owner cannot be reassigned'
      using errcode = '42501';
  end if;
  if caller = 'manager'::public.app_role and private.target_is_owner(target) then
    raise exception 'a manager cannot change the owner'
      using errcode = '42501';
  end if;
  if caller = 'manager'::public.app_role and new_role = 'owner'::public.app_role then
    raise exception 'a manager cannot assign the owner role'
      using errcode = '42501';
  end if;
  perform private.write_staff_role(target, new_role);
end;
$$;

-- ---------- sole owner: profile removal ----------

drop policy if exists profiles_delete on public.profiles;

create policy profiles_delete
on public.profiles
for delete
to authenticated
using (
  (select private.current_app_role()) = 'owner'
  and coalesce((select private.target_is_owner(id)), false) = false
);

-- ---------- consume_staff_invite_slot: caller from JWT (auth.uid) ----------

drop function if exists public.consume_staff_invite_slot(uuid);
drop function if exists private.consume_staff_invite_slot(uuid);

create or replace function private.consume_staff_invite_slot()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  bucket timestamptz := date_trunc('hour', pg_catalog.now());
  cnt integer;
  v_caller_id uuid := auth.uid();
  caller_role text;
begin
  if coalesce((select auth.jwt() ->> 'role'), '') is distinct from 'authenticated' then
    raise exception 'invite rate limit requires an authenticated caller'
      using errcode = '42501';
  end if;
  if v_caller_id is null then
    raise exception 'invite rate limit requires an authenticated caller'
      using errcode = '42501';
  end if;

  select u.raw_app_meta_data ->> 'role'
  into caller_role
  from auth.users as u
  where u.id = v_caller_id;

  if caller_role is null or caller_role not in ('owner', 'manager') then
    raise exception 'invite rate limit requires owner or manager caller'
      using errcode = '42501';
  end if;

  insert into private.staff_invite_buckets as b (caller_id, bucket_start, invite_count)
  values (v_caller_id, bucket, 1)
  on conflict (caller_id, bucket_start) do update
  set invite_count = b.invite_count + 1
  returning invite_count into cnt;
  if cnt > 10 then
    raise exception 'invite rate limit exceeded'
      using errcode = 'P0004';
  end if;
end;
$$;

create or replace function public.consume_staff_invite_slot()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.consume_staff_invite_slot();
end;
$$;

revoke all on function private.consume_staff_invite_slot() from public, anon, authenticated, service_role;
grant execute on function private.consume_staff_invite_slot() to postgres;

revoke all on function public.consume_staff_invite_slot() from public, anon, service_role;
grant execute on function public.consume_staff_invite_slot() to authenticated;