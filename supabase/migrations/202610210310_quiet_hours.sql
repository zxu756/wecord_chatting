-- Quiet hours: is a person in them, and who a push may still reach.
--
-- * quiet_window_contains(zone, days, start, end, at): the pure rule.
--     - The clock is the wall clock of the IANA zone at that moment, so
--       daylight saving time needs no special case: 23:00-07:00 is 23:00 to
--       07:00 on the clock the person sees, an hour longer or shorter on the
--       night the clocks change.
--     - days are the ISO weekdays on which a window STARTS. A window that
--       crosses midnight (start > end) continues into the next day, so its
--       after-midnight half is quiet when the PREVIOUS day is picked.
--     - start = end is an empty window.
--     - An unknown zone counts as UTC.
-- * notification_time_zone(user): the person's zone: the one their devices
--   reported in the settings, else the newest push subscription's, else UTC.
-- * in_quiet_hours(user, at): the rule applied to a person's settings.
-- * quiet_hours_recipients(subscriptions, message): for the push functions.
--   Of the given push subscriptions it answers those whose owner has quiet
--   hours on, with the window and whether this message breaks through
--   (a call, an @mention of the owner, a starred friend or an important
--   contact, as far as the owner allows). The functions decide at send time
--   whether the window is on and skip the push; the inbox and notifications
--   are written elsewhere and are not touched. claim_push_delivery and the
--   other claim functions stay as they are.
--
-- Quiet hours stack with the other reasons not to push (Do Not Disturb,
-- conversation and circle mutes): those are applied by the claim functions
-- before the push functions see a subscription at all.

create or replace function public.quiet_window_contains(
  zone text,
  days integer[],
  window_start time,
  window_end time,
  at timestamptz
)
returns boolean
language plpgsql
stable
set search_path = public
as $$
declare
  local_time timestamp;
  clock time;
  day integer;
  previous_day integer;
begin
  if window_start is null or window_end is null or at is null
    or window_start = window_end
    or coalesce(cardinality(days), 0) = 0
  then
    return false;
  end if;

  begin
    local_time := at at time zone coalesce(nullif(btrim(zone), ''), 'UTC');
  exception when others then
    local_time := at at time zone 'UTC';
  end;
  clock := local_time::time;
  day := extract(isodow from local_time)::integer;
  previous_day := case when day = 1 then 7 else day - 1 end;

  if window_start < window_end then
    return day = any(days) and clock >= window_start and clock < window_end;
  end if;
  return (clock >= window_start and day = any(days))
    or (clock < window_end and previous_day = any(days));
end;
$$;

revoke execute on function public.quiet_window_contains(text, integer[], time, time, timestamptz)
  from public, anon, authenticated;
grant execute on function public.quiet_window_contains(text, integer[], time, time, timestamptz)
  to service_role;

create or replace function public.notification_time_zone(target_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select s.timezone
      from public.user_notification_settings s
      where s.user_id = target_user_id
    ),
    (
      select p.time_zone
      from public.push_subscriptions p
      where p.user_id = target_user_id and p.time_zone is not null
      order by p.last_seen_at desc
      limit 1
    ),
    'UTC'
  );
$$;

revoke execute on function public.notification_time_zone(uuid) from public, anon, authenticated;
grant execute on function public.notification_time_zone(uuid) to service_role;

create or replace function public.in_quiet_hours(
  target_user_id uuid,
  at timestamptz default now()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select s.quiet_enabled
        and public.quiet_window_contains(
          public.notification_time_zone(s.user_id),
          s.quiet_days,
          s.quiet_start,
          s.quiet_end,
          at
        )
      from public.user_notification_settings s
      where s.user_id = target_user_id
    ),
    false
  );
$$;

revoke execute on function public.in_quiet_hours(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.in_quiet_hours(uuid, timestamptz) to service_role;

-- The subscriptions a push function may have to hold back during quiet hours,
-- one row per subscription whose owner has quiet hours on.
create or replace function public.quiet_hours_recipients(
  target_subscription_ids uuid[],
  target_message_id uuid default null
)
returns table (
  subscription_id uuid,
  user_id uuid,
  time_zone text,
  quiet_days integer[],
  quiet_start time,
  quiet_end time,
  breaks_through boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  message public.messages%rowtype;
begin
  if target_message_id is not null then
    select m.* into message from public.messages m where m.id = target_message_id;
  end if;

  return query
  select
    s.id,
    n.user_id,
    public.notification_time_zone(n.user_id),
    n.quiet_days,
    n.quiet_start,
    n.quiet_end,
    (
      message.id is not null
      and (
        (
          n.allow_calls
          and message.type = 'system'
          and message.attachment->>'kind' = 'call'
        )
        or (
          n.allow_mentions
          and exists (
            select 1
            from public.message_mentions mm
            where mm.message_id = message.id
              and mm.user_id = n.user_id
              and mm.kind = 'user'
          )
        )
        or (
          n.allow_starred
          and exists (
            select 1
            from public.friend_stars fs
            where fs.owner_id = n.user_id
              and fs.friend_id = message.sender_id
          )
        )
        or message.sender_id = any(n.vip_user_ids)
      )
    )
  from public.push_subscriptions s
  join public.user_notification_settings n on n.user_id = s.user_id
  where s.id = any(target_subscription_ids)
    and n.quiet_enabled;
end;
$$;

revoke execute on function public.quiet_hours_recipients(uuid[], uuid) from public, anon, authenticated;
grant execute on function public.quiet_hours_recipients(uuid[], uuid) to service_role;
