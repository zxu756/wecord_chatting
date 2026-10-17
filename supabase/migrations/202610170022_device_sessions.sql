-- Signed-in devices.
--
-- * user_devices records what a session is: a name, the platform and the
--   app version, keyed by the Supabase Auth session id (a claim of the
--   caller's token). The app calls register_device after signing in and
--   when it starts; the row goes when the session does (foreign key to
--   auth.sessions).
-- * list_my_sessions() lists the caller's own sessions from auth.sessions,
--   joined with that record, newest activity first, marking the one the
--   call came from. It returns no IP address and no location: working one
--   out would need a third-party service.
-- * Signing out the other devices uses Auth's own sign-out with scope
--   'others'. Signing out one device goes through the sessions Edge
--   Function, which checks the session is the caller's and then calls
--   delete_user_session, which only the service role may run.

create table if not exists public.user_devices (
  session_id uuid primary key references auth.sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_name text not null default '',
  platform text not null default '',
  app_version text not null default '',
  created_at timestamptz not null default now(),
  last_active_at timestamptz not null default now(),
  constraint user_devices_device_name_length check (char_length(device_name) <= 80),
  constraint user_devices_platform_length check (char_length(platform) <= 40),
  constraint user_devices_app_version_length check (char_length(app_version) <= 40)
);

create index if not exists user_devices_user_idx
  on public.user_devices (user_id, last_active_at desc);

alter table public.user_devices enable row level security;
revoke all on public.user_devices from anon, authenticated;
grant select on public.user_devices to authenticated;

drop policy if exists user_devices_select_own on public.user_devices;
create policy user_devices_select_own
  on public.user_devices for select
  to authenticated
  using (user_id = auth.uid());

-- Records (or refreshes) the device of the caller's current session.
create or replace function public.register_device(
  device_name text,
  platform text,
  app_version text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_session uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  begin
    current_session := nullif(auth.jwt()->>'session_id', '')::uuid;
  exception when others then
    current_session := null;
  end;

  if current_session is null or not exists (
    select 1
    from auth.sessions s
    where s.id = current_session
      and s.user_id = auth.uid()
  ) then
    return;
  end if;

  insert into public.user_devices as d (
    session_id, user_id, device_name, platform, app_version
  )
  values (
    current_session,
    auth.uid(),
    left(btrim(coalesce(register_device.device_name, '')), 80),
    left(btrim(coalesce(register_device.platform, '')), 40),
    left(btrim(coalesce(register_device.app_version, '')), 40)
  )
  on conflict (session_id) do update
  set
    device_name = excluded.device_name,
    platform = excluded.platform,
    app_version = excluded.app_version,
    last_active_at = now()
  where d.user_id = auth.uid();
end;
$$;

revoke execute on function public.register_device(text, text, text) from public, anon;
grant execute on function public.register_device(text, text, text) to authenticated;

-- The caller's own sessions.
create or replace function public.list_my_sessions()
returns table (
  session_id uuid,
  device_name text,
  platform text,
  app_version text,
  user_agent text,
  created_at timestamptz,
  last_active_at timestamptz,
  is_current boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_session uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  begin
    current_session := nullif(auth.jwt()->>'session_id', '')::uuid;
  exception when others then
    current_session := null;
  end;

  return query
  select
    s.id,
    coalesce(d.device_name, ''),
    coalesce(d.platform, ''),
    coalesce(d.app_version, ''),
    coalesce(s.user_agent, ''),
    s.created_at,
    greatest(
      coalesce(s.refreshed_at, s.updated_at, s.created_at),
      coalesce(d.last_active_at, s.created_at)
    ),
    s.id = current_session
  from auth.sessions s
  left join public.user_devices d on d.session_id = s.id
  where s.user_id = auth.uid()
    and (s.not_after is null or s.not_after > now())
  order by
    (s.id = current_session) desc,
    greatest(
      coalesce(s.refreshed_at, s.updated_at, s.created_at),
      coalesce(d.last_active_at, s.created_at)
    ) desc;
end;
$$;

revoke execute on function public.list_my_sessions() from public, anon;
grant execute on function public.list_my_sessions() to authenticated;

-- Ends one session of [owner]. For the sessions Edge Function (service
-- role) only, after it has checked that the session is the caller's.
create or replace function public.delete_user_session(
  target_session_id uuid,
  owner_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  removed integer;
begin
  delete from auth.sessions s
  where s.id = target_session_id
    and s.user_id = owner_id;
  get diagnostics removed = row_count;
  return removed > 0;
end;
$$;

revoke execute on function public.delete_user_session(uuid, uuid) from public, anon, authenticated;
grant execute on function public.delete_user_session(uuid, uuid) to service_role;
