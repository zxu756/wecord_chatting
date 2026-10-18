-- Birthdays (B5), part 2 of 2: the reminder at 9 in the morning.
--
-- On a friend's birthday, at 9:00 in the recipient's own time (and through
-- the evening, 20:59, for a device that was off), the recipient's devices
-- get a push: "It is Ada's birthday today" / "今天是 Ada 的生日". The same
-- friends are listed as cards in Notifications (list_birthdays_today,
-- 202610230610), which the app asks for with its own calendar date.
--
-- The tick is the existing one: pg_cron runs run_later_dispatch() every
-- minute, which wakes the scheduled-dispatch Edge Function when something
-- waits (birthday_pushes_waiting() here), and the function calls
-- claim_birthday_pushes() with the service role. No new cron job.
--
-- Whose "9 o'clock": each push subscription remembers the time zone of its
-- device (202610170100). A recipient is "awake" when one of their devices is
-- between 9:00 and 20:59 in its zone; the birthday is compared with that
-- device's calendar date. A subscription without a usable zone counts as UTC.
-- Each recipient is told once per friend per year (birthday_reminder_log).
--
-- Who is NOT told:
--   * a friend who chose "only me" for their birthday (birthday_visibility),
--     who deleted the account, or a bot;
--   * the recipient who turned birthday reminders off (profiles
--     .birthday_reminders), or is in Do Not Disturb (the quiet-hours filter
--     of scheduled-dispatch also applies);
--   * anyone who blocked, or was blocked by, the friend (a block ends the
--     friendship anyway);
--   * the birthday person themselves.
-- The text is in the language of each subscription ('en' or 'zh'); it has no
-- time in it, so there is nothing to write in a time zone. Names are the
-- recipient's aliases, cleaned of angle brackets so a name cannot pass for a
-- time token.
--
-- run_later_dispatch is 202610190021_moments_push.sql (the latest
-- definition of the four) with one more reason to wake the function.

create table if not exists public.birthday_reminder_log (
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  year integer not null,
  created_at timestamptz not null default now(),
  primary key (recipient_id, friend_id, year)
);

alter table public.birthday_reminder_log enable row level security;
revoke all on public.birthday_reminder_log from public, anon, authenticated;

-- The wall clock of a time zone name. An unknown name is UTC.
create or replace function public.local_time_in_zone(zone text)
returns timestamp
language plpgsql
stable
as $$
begin
  return (now() at time zone coalesce(nullif(btrim(zone), ''), 'UTC'))::timestamp;
exception when others then
  return (now() at time zone 'UTC')::timestamp;
end;
$$;

revoke execute on function public.local_time_in_zone(text)
  from public, anon, authenticated;

-- The reminders that are due now: one row per recipient and friend that has
-- not been told this year. Internal (the claim and the dispatcher use it).
create or replace function public.birthday_due_reminders()
returns table (
  recipient_id uuid,
  friend_id uuid,
  local_year integer
)
language sql
stable
security definer
set search_path = public
as $$
  with zones as (
    select z.zone, public.local_time_in_zone(z.zone) as local_now
    from (
      select distinct coalesce(s.time_zone, 'UTC') as zone
      from public.push_subscriptions s
    ) z
  ),
  dates as (
    select distinct zn.local_now::date as day from zones zn
  ),
  awake as (
    select distinct s.user_id, zn.local_now::date as day
    from public.push_subscriptions s
    join zones zn on zn.zone = coalesce(s.time_zone, 'UTC')
    where extract(hour from zn.local_now) between 9 and 20
  )
  select distinct
    a.user_id,
    p.id,
    extract(year from a.day)::integer
  from dates d
  join public.profiles p
    on p.birthday_month is not null
    and p.birthday_visibility = 'friends'
    and p.deleted_at is null
    and not p.is_bot
    and public.birthday_falls_on(p.birthday_month, p.birthday_day, d.day)
  join public.friendships f
    on p.id in (f.user_low_id, f.user_high_id)
  join awake a
    on a.day = d.day
    and a.user_id = case
      when f.user_low_id = p.id then f.user_high_id
      else f.user_low_id
    end
  join public.profiles me
    on me.id = a.user_id
    and me.birthday_reminders
    and me.deleted_at is null
  where not exists (
      select 1
      from public.blocks b
      where (b.blocker_id = a.user_id and b.blocked_id = p.id)
        or (b.blocker_id = p.id and b.blocked_id = a.user_id)
    )
    and not exists (
      select 1
      from public.birthday_reminder_log l
      where l.recipient_id = a.user_id
        and l.friend_id = p.id
        and l.year = extract(year from a.day)::integer
    )
    and coalesce(
      (
        select ups.presence_status
        from public.user_privacy_settings ups
        where ups.user_id = a.user_id
      ),
      'online'
    ) <> 'dnd';
$$;

revoke execute on function public.birthday_due_reminders()
  from public, anon, authenticated;
grant execute on function public.birthday_due_reminders() to service_role;

-- Whether run_later_dispatch should wake the function for birthdays.
create or replace function public.birthday_pushes_waiting()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.birthday_due_reminders());
$$;

revoke execute on function public.birthday_pushes_waiting()
  from public, anon, authenticated;
grant execute on function public.birthday_pushes_waiting() to service_role;

-- Claims the birthday pushes to send. Service role only. Each (recipient,
-- friend, year) is claimed once, so a second wake-up cannot ring twice.
create or replace function public.claim_birthday_pushes()
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
  -- Last year's notes are of no use any more.
  delete from public.birthday_reminder_log l
  where l.created_at < now() - interval '2 years';

  return query
  with claimed as (
    insert into public.birthday_reminder_log (recipient_id, friend_id, year)
    select d.recipient_id, d.friend_id, d.local_year
    from public.birthday_due_reminders() d
    on conflict do nothing
    returning recipient_id, friend_id, year
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    null::uuid,
    null::uuid,
    case when s.language = 'zh' then
      '🎂 今天是 ' || label.name || ' 的生日'
    else
      '🎂 It''s ' || label.name || '''s birthday today'
    end,
    case when s.language = 'zh' then
      '打开 WeCord，送上一句生日祝福。'
    else
      'Open WeCord and send a birthday wish.'
    end,
    'birthday-' || c.friend_id::text || '-' || c.year::text,
    '/#/notifications'
  from claimed c
  join public.push_subscriptions s on s.user_id = c.recipient_id
  cross join lateral (
    select left(btrim(replace(replace(coalesce(
      nullif(btrim(ca.alias), ''),
      nullif(btrim(pr.display_name), ''),
      pr.username,
      'A friend'
    ), '<', ''), '>', '')), 60) as name
    from public.profiles pr
    left join public.contact_aliases ca
      on ca.owner_id = c.recipient_id and ca.friend_id = pr.id
    where pr.id = c.friend_id
  ) label;
end;
$$;

revoke execute on function public.claim_birthday_pushes()
  from public, anon, authenticated;
grant execute on function public.claim_birthday_pushes() to service_role;

-- 202610190021 with one more reason to wake scheduled-dispatch: a friend's
-- birthday whose reminder nobody has sent yet.
create or replace function public.run_later_dispatch()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  pushes_waiting boolean;
  functions_url text;
  dispatch_secret text;
begin
  perform public.dispatch_due_scheduled_messages();
  perform public.chat_event_due_reminders();

  -- Dismissed reminders go after a month.
  delete from public.message_reminders r
  where r.dismissed_at < now() - interval '30 days';

  select exists (
    select 1
    from public.scheduled_messages s
    where s.status = 'sent'
      and s.push_claimed_at is null
      and s.sent_at > now() - interval '15 minutes'
  ) or exists (
    select 1
    from public.message_reminders r
    where r.push_claimed_at is null
      and r.dismissed_at is null
      and r.remind_at <= now()
      and r.remind_at > now() - interval '15 minutes'
  ) or exists (
    select 1
    from public.chat_event_reminders r
    where r.push_sent_at is null
      and r.created_at > now() - interval '30 minutes'
  ) or exists (
    -- The same items due_list_item_reminders() looks at, for a member who
    -- has no notice of this kind for this due date yet.
    select 1
    from public.task_items i
    join public.task_lists l on l.id = i.list_id and l.deleted_at is null
    left join public.task_item_assignees a on a.item_id = i.id
    join public.conversation_members cm
      on cm.conversation_id = l.conversation_id
      and cm.user_id = coalesce(a.user_id, i.created_by)
    where i.deleted_at is null
      and i.completed_at is null
      and i.due_at is not null
      and i.due_at > now() - interval '2 days'
      and i.due_at <= now() + case
        when i.due_has_time then interval '1 hour'
        else interval '12 hours'
      end
      and not exists (
        select 1
        from public.task_notifications n
        where n.user_id = cm.user_id
          and n.item_id = i.id
          and n.due_at = i.due_at
          and n.kind = case when i.due_at < now() then 'overdue' else 'due_soon' end
      )
  ) or exists (
    select 1
    from public.recalled_message_media r
    where r.expired
  ) or exists (
    -- A like, comment or reply on a Moment whose push nobody has claimed
    -- (claim_moments_pushes).
    select 1
    from public.moments_notifications mn
    where mn.pushed_at is null
      and mn.created_at > now() - interval '10 minutes'
  ) or public.birthday_pushes_waiting()
  into pushes_waiting;

  if not pushes_waiting then
    return;
  end if;

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
    -- No Vault or pg_net here: the work is done, only the push waits.
    null;
  end;
end;
$$;

revoke execute on function public.run_later_dispatch() from public, anon, authenticated;
grant execute on function public.run_later_dispatch() to service_role;
