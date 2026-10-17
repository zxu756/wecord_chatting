-- Push subscriptions remember the time zone of the device.
--
-- Messages can hold time tokens (<t:1760000000:F>) that every reader sees in
-- their own zone. The Edge Functions that send Web Push (push,
-- scheduled-dispatch, chat-event-reminders) write the tokens out in the
-- subscriber's zone and language, so they need the zone: the IANA name the
-- browser reports ('Asia/Shanghai'), sent by the app with the subscription
-- and again each time it starts. Null means unknown, and the functions then
-- show UTC and say so.
--
-- register_push_subscription is 202610170005_push_language.sql with one more
-- argument. The five argument version goes: the new one takes the same call
-- (the zone is optional), and keeping both would make that call ambiguous.

alter table public.push_subscriptions
  add column if not exists time_zone text;

alter table public.push_subscriptions
  drop constraint if exists push_subscriptions_time_zone_check;
-- The shape of an IANA name only. Whether the runtime knows it is checked
-- where it is used, so a new zone never blocks a subscription.
alter table public.push_subscriptions
  add constraint push_subscriptions_time_zone_check
  check (time_zone is null or time_zone ~ '^[A-Za-z0-9_+./-]{1,64}$');

drop function if exists public.register_push_subscription(text, text, text, text, text);

create or replace function public.register_push_subscription(
  target_endpoint text,
  target_p256dh text,
  target_auth text,
  target_user_agent text default null,
  target_language text default 'en',
  target_time_zone text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  zone text := nullif(btrim(target_time_zone), '');
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  -- A malformed name is dropped, not an error: a push without the right
  -- time zone is better than no subscription.
  if zone is not null and zone !~ '^[A-Za-z0-9_+./-]{1,64}$' then
    zone := null;
  end if;

  insert into public.push_subscriptions (
    user_id,
    endpoint,
    p256dh,
    auth,
    user_agent,
    language,
    time_zone
  )
  values (
    auth.uid(),
    target_endpoint,
    target_p256dh,
    target_auth,
    left(target_user_agent, 300),
    case when target_language = 'zh' then 'zh' else 'en' end,
    zone
  )
  on conflict (endpoint) do update
  set
    user_id = excluded.user_id,
    p256dh = excluded.p256dh,
    auth = excluded.auth,
    user_agent = excluded.user_agent,
    language = excluded.language,
    -- An older app that sends no zone doesn't wipe the one stored.
    time_zone = coalesce(excluded.time_zone, public.push_subscriptions.time_zone),
    last_seen_at = now();
end;
$$;

revoke execute on function public.register_push_subscription(text, text, text, text, text, text) from public, anon;
grant execute on function public.register_push_subscription(text, text, text, text, text, text) to authenticated;
