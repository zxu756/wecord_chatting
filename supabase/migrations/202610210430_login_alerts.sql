-- New-login alerts.
--
-- When a session registers its device for the first time (user_devices, the
-- row register_device writes), and the user already has another registered
-- device, a login_alerts row is written:
--
--   * Notifications → Security shows a card "New sign-in: {device}, {time}"
--     with "It was me" and "Not me". "Not me" signs that session out through
--     the sessions Edge Function (the Devices sign-out path) and points the
--     user to changing their password. No address and no location, as in
--     Devices.
--   * The user's other devices get a web push (claim_security_alert_pushes,
--     claimed by the scheduled-dispatch function), worded in each
--     subscription's language, with the time in its time zone.
--
-- The very first login raises nothing (no other device). A token refresh
-- keeps its session, so it is no new device. register_device on a session
-- that is already recorded only updates the row.

create table if not exists public.login_alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  -- The session that signed in. No foreign key: the alert outlives it when
  -- "Not me" ends the session.
  session_id uuid not null,
  device_name text not null default '',
  platform text not null default '',
  created_at timestamptz not null default now(),
  push_claimed_at timestamptz,
  resolved_at timestamptz,
  resolution text check (resolution in ('dismissed', 'revoked')),
  constraint login_alerts_resolution_pair check (
    (resolved_at is null) = (resolution is null)
  )
);

create index if not exists login_alerts_user_idx
  on public.login_alerts (user_id, created_at desc);

alter table public.login_alerts enable row level security;
revoke all on public.login_alerts from anon, authenticated;
grant select on public.login_alerts to authenticated;

drop policy if exists login_alerts_select_own on public.login_alerts;
create policy login_alerts_select_own
  on public.login_alerts for select
  to authenticated
  using (user_id = auth.uid());

-- Wakes the scheduled-dispatch function (as run_later_dispatch does, with
-- the same Vault secrets) so a push goes out within seconds, not at the next
-- minute. Quietly does nothing where Vault or pg_net is missing.
create or replace function public.wake_scheduled_dispatch()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  functions_url text;
  dispatch_secret text;
begin
  select d.decrypted_secret
  into functions_url
  from vault.decrypted_secrets d
  where d.name = 'wecord_functions_url';
  select d.decrypted_secret
  into dispatch_secret
  from vault.decrypted_secrets d
  where d.name = 'wecord_dispatch_secret';

  if functions_url is null or dispatch_secret is null then
    return;
  end if;

  perform net.http_post(
    url := rtrim(functions_url, '/') || '/scheduled-dispatch',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || dispatch_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 5000
  );
exception when others then
  null;
end;
$$;

revoke execute on function public.wake_scheduled_dispatch() from public, anon, authenticated;
grant execute on function public.wake_scheduled_dispatch() to service_role;

-- A newly recorded device: alert the user when they had another.
create or replace function public.user_devices_login_alert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.user_devices d
    where d.user_id = new.user_id
      and d.session_id <> new.session_id
  ) then
    return new;
  end if;

  insert into public.login_alerts (user_id, session_id, device_name, platform)
  values (new.user_id, new.session_id, new.device_name, new.platform);

  perform public.wake_scheduled_dispatch();
  return new;
end;
$$;

revoke execute on function public.user_devices_login_alert() from public, anon, authenticated;

drop trigger if exists user_devices_login_alert on public.user_devices;
create trigger user_devices_login_alert
  after insert on public.user_devices
  for each row execute function public.user_devices_login_alert();

-- The caller's alerts of the last 30 days, newest first, for the
-- Notifications Security card.
create or replace function public.list_my_login_alerts()
returns table (
  id uuid,
  session_id uuid,
  device_name text,
  platform text,
  created_at timestamptz,
  resolved_at timestamptz,
  resolution text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  return query
  select a.id, a.session_id, a.device_name, a.platform, a.created_at,
         a.resolved_at, a.resolution
  from public.login_alerts a
  where a.user_id = auth.uid()
    and a.created_at > now() - interval '30 days'
  order by a.created_at desc
  limit 50;
end;
$$;

revoke execute on function public.list_my_login_alerts() from public, anon;
grant execute on function public.list_my_login_alerts() to authenticated;

-- Closes an alert of the caller's: 'dismissed' ("It was me") or 'revoked'
-- ("Not me", after the app signed that session out). Closed once.
create or replace function public.resolve_login_alert(
  alert_id uuid,
  outcome text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if outcome is null or outcome not in ('dismissed', 'revoked') then
    raise exception 'Unknown outcome' using errcode = '22023';
  end if;

  update public.login_alerts a
  set resolved_at = now(), resolution = outcome
  where a.id = alert_id
    and a.user_id = auth.uid()
    and a.resolved_at is null;

  if not found and not exists (
    select 1 from public.login_alerts a
    where a.id = alert_id and a.user_id = auth.uid()
  ) then
    raise exception 'Alert not found' using errcode = '42501';
  end if;
end;
$$;

revoke execute on function public.resolve_login_alert(uuid, text) from public, anon;
grant execute on function public.resolve_login_alert(uuid, text) to authenticated;

-- Pushes for alerts nobody has pushed yet, to the subscriptions that
-- existed when the login happened (the new device's own browser subscribes
-- later), claimed once. For the scheduled-dispatch function (service role).
-- The title and body are in the subscription's language; the time is a
-- time token the function writes in the subscription's time zone. Do Not
-- Disturb does not hold a security alert back.
create or replace function public.claim_security_alert_pushes()
returns table (
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth text,
  conversation_id uuid,
  circle_id uuid,
  title text,
  body text,
  tag text,
  url text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  -- Too old to be news, or already dealt with: closed without a push.
  update public.login_alerts a
  set push_claimed_at = now()
  where a.push_claimed_at is null
    and (a.created_at <= now() - interval '15 minutes'
         or a.resolved_at is not null);

  return query
  with claimed as (
    update public.login_alerts a
    set push_claimed_at = now()
    where a.push_claimed_at is null
    returning a.*
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    null::uuid,
    null::uuid,
    case when s.language = 'zh' then
      '你的账号在新设备上登录'
    else
      'New sign-in to your account'
    end,
    case when s.language = 'zh' then
      coalesce(nullif(device.label, ''), '未知设备')
        || '，<t:' || floor(extract(epoch from c.created_at))::bigint || ':f>。不是你？打开 WeCord 的通知页处理。'
    else
      coalesce(nullif(device.label, ''), 'An unknown device')
        || ', <t:' || floor(extract(epoch from c.created_at))::bigint || ':f>. Not you? Open Notifications in WeCord.'
    end,
    'security-' || c.id::text,
    '/#/notifications'
  from claimed c
  cross join lateral (
    -- No angle brackets: the name must not pass for a time token.
    select btrim(replace(replace(
      case
        when btrim(c.device_name) <> '' and btrim(c.platform) <> ''
          and position(lower(btrim(c.platform)) in lower(c.device_name)) = 0
          then btrim(c.device_name) || ' (' || btrim(c.platform) || ')'
        when btrim(c.device_name) <> '' then btrim(c.device_name)
        else btrim(c.platform)
      end,
      '<', ''), '>', '')) as label
  ) device
  join public.push_subscriptions s
    on s.user_id = c.user_id
    and s.created_at <= c.created_at;
end;
$$;

revoke execute on function public.claim_security_alert_pushes() from public, anon, authenticated;
grant execute on function public.claim_security_alert_pushes() to service_role;
