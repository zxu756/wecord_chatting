-- Two-step recovery codes and passkeys (roadmap G4), part 3 of 4: the
-- security record, the pushes and the export.
--
-- * list_my_security_events / resolve_security_event: what Notifications ->
--   Security and Settings -> Security log show: the account's events of the
--   last 30 days, each closed once with "It was me" (confirmed) or "Not me"
--   (denied).
-- * claim_account_security_pushes: one push per device for each new event,
--   worded in the device's language, with the time in its time zone (a time
--   token the scheduled-dispatch function turns into the zone), claimed once.
--   Do Not Disturb does not hold a security alert back. A separate function
--   from claim_security_alert_pushes (new-login alerts, 202610210430), which
--   is not rewritten.
-- * export_my_account_security: for the data-export function (service role):
--   the record, how many codes are left and the passkeys' names and dates.
--   Never a code, a hash, a salt or a key.

create or replace function public.list_my_security_events()
returns table (
  id uuid,
  kind text,
  detail jsonb,
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
  select e.id, e.kind, e.detail, e.created_at, e.resolved_at, e.resolution
  from public.account_security_events e
  where e.user_id = auth.uid()
    and e.created_at > now() - interval '30 days'
  order by e.created_at desc
  limit 50;
end;
$$;

revoke execute on function public.list_my_security_events() from public, anon;
grant execute on function public.list_my_security_events() to authenticated;

create or replace function public.resolve_security_event(
  event_id uuid,
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

  if outcome is null or outcome not in ('confirmed', 'denied') then
    raise exception 'Unknown outcome' using errcode = '22023';
  end if;

  update public.account_security_events e
  set resolved_at = now(), resolution = outcome
  where e.id = event_id
    and e.user_id = auth.uid()
    and e.resolved_at is null;

  if not found and not exists (
    select 1 from public.account_security_events e
    where e.id = event_id and e.user_id = auth.uid()
  ) then
    raise exception 'Event not found' using errcode = '42501';
  end if;
end;
$$;

revoke execute on function public.resolve_security_event(uuid, text) from public, anon;
grant execute on function public.resolve_security_event(uuid, text) to authenticated;

create or replace function public.claim_account_security_pushes()
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
  update public.account_security_events e
  set push_claimed_at = now()
  where e.push_claimed_at is null
    and (e.created_at <= now() - interval '15 minutes'
         or e.resolved_at is not null);

  return query
  with claimed as (
    update public.account_security_events e
    set push_claimed_at = now()
    where e.push_claimed_at is null
    returning e.*
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    null::uuid,
    null::uuid,
    case when s.language = 'zh' then
      case c.kind
        when 'recovery_codes_generated' then '两步验证恢复码已重新生成'
        when 'recovery_code_used' then '有人用恢复码通过了两步验证'
        when 'recovery_locked' then '恢复码输错次数过多'
        when 'passkey_added' then '你的账号新增了通行密钥'
        else '你的账号删除了一个通行密钥'
      end
    else
      case c.kind
        when 'recovery_codes_generated' then 'New two-step recovery codes were made'
        when 'recovery_code_used' then 'A recovery code was used to sign in'
        when 'recovery_locked' then 'Too many wrong recovery codes'
        when 'passkey_added' then 'A passkey was added to your account'
        else 'A passkey was removed from your account'
      end
    end,
    case when s.language = 'zh' then
      case c.kind
        when 'recovery_codes_generated' then
          '<t:' || floor(extract(epoch from c.created_at))::bigint || ':f>，旧的恢复码已全部作废。不是你？打开 WeCord 的通知页处理。'
        when 'recovery_code_used' then
          '<t:' || floor(extract(epoch from c.created_at))::bigint || ':f>，两步验证已被关闭。不是你？马上修改密码，打开 WeCord 的通知页处理。'
        when 'recovery_locked' then
          '<t:' || floor(extract(epoch from c.created_at))::bigint || ':f>，恢复码已暂时锁定 30 分钟。不是你？请修改密码。'
        when 'passkey_added' then
          coalesce(nullif(item.label, ''), '一个通行密钥')
            || '，<t:' || floor(extract(epoch from c.created_at))::bigint || ':f>。不是你？打开 WeCord 的通知页处理。'
        else
          coalesce(nullif(item.label, ''), '一个通行密钥')
            || '，<t:' || floor(extract(epoch from c.created_at))::bigint || ':f>。不是你？打开 WeCord 的通知页处理。'
      end
    else
      case c.kind
        when 'recovery_codes_generated' then
          '<t:' || floor(extract(epoch from c.created_at))::bigint || ':f>. Your old codes no longer work. Not you? Open Notifications in WeCord.'
        when 'recovery_code_used' then
          '<t:' || floor(extract(epoch from c.created_at))::bigint || ':f>. Two-step verification was turned off. Not you? Change your password now and open Notifications in WeCord.'
        when 'recovery_locked' then
          '<t:' || floor(extract(epoch from c.created_at))::bigint || ':f>. Recovery is locked for 30 minutes. Not you? Change your password.'
        when 'passkey_added' then
          coalesce(nullif(item.label, ''), 'A passkey')
            || ', <t:' || floor(extract(epoch from c.created_at))::bigint || ':f>. Not you? Open Notifications in WeCord.'
        else
          coalesce(nullif(item.label, ''), 'A passkey')
            || ', <t:' || floor(extract(epoch from c.created_at))::bigint || ':f>. Not you? Open Notifications in WeCord.'
      end
    end,
    'account-security-' || c.id::text,
    '/#/notifications'
  from claimed c
  cross join lateral (
    -- No angle brackets: a passkey's name must not pass for a time token.
    select btrim(replace(replace(coalesce(c.detail ->> 'name', ''), '<', ''), '>', '')) as label
  ) item
  join public.push_subscriptions s
    on s.user_id = c.user_id
    and s.created_at <= c.created_at;
end;
$$;

revoke execute on function public.claim_account_security_pushes()
  from public, anon, authenticated;
grant execute on function public.claim_account_security_pushes() to service_role;

create or replace function public.export_my_account_security(target_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  passkeys jsonb := '[]'::jsonb;
begin
  if target_user_id is null then
    raise exception 'A user is required' using errcode = '22023';
  end if;

  -- Supabase Auth keeps the passkeys; names and dates only. Where the table
  -- is missing or not readable, there are none to list.
  begin
    execute $q$
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'name', nullif(btrim(w.friendly_name), ''),
          'added_at', w.created_at,
          'last_used_at', w.last_used_at
        )
        order by w.created_at
      ), '[]'::jsonb)
      from auth.webauthn_credentials w
      where w.user_id = $1
    $q$ into passkeys using target_user_id;
  exception when others then
    passkeys := '[]'::jsonb;
  end;

  return jsonb_build_object(
    'events', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'kind', e.kind,
          'detail', e.detail,
          'at', e.created_at,
          'answer', e.resolution,
          'answered_at', e.resolved_at
        )
        order by e.created_at desc
      )
      from public.account_security_events e
      where e.user_id = target_user_id
    ), '[]'::jsonb),
    'recovery_codes', (
      select jsonb_build_object(
        'remaining', count(*) filter (where c.used_at is null),
        'made_at', min(c.created_at)
      )
      from public.mfa_recovery_codes c
      where c.user_id = target_user_id
    ),
    'passkeys', passkeys
  );
end;
$$;

revoke execute on function public.export_my_account_security(uuid)
  from public, anon, authenticated;
grant execute on function public.export_my_account_security(uuid) to service_role;
