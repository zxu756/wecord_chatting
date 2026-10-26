-- Group check-in (roadmap D3), part 3 of 4: the daily reminder.
--
-- A board can ask for a reminder at a time of day (remind_minute, minutes
-- after midnight in the board's zone, set when the board is made).
-- check_in_sweep() runs every 5 minutes on a pg_cron job of its own
-- ('wecord-check-in-sweep'; run_later_dispatch, the every-minute dispatcher,
-- is not touched) and, once per board per local day:
--
--   * looks at boards that are open, whose card still stands, whose circle an
--     admin has not suspended (K1) and whose local time has reached the
--     reminder time but not by more than 3 hours (after an outage it does
--     not wake people at night for something stale);
--   * writes one check_in_notices row for each person who can see the
--     conversation, is no bot, no deleted or suspended account, and has not
--     checked in today;
--   * wakes scheduled-dispatch (wake_scheduled_dispatch, 202610210430) so the
--     push goes out at once.
--   It also tidies notices nobody claimed in two days.
--
-- claim_check_in_pushes() is what scheduled-dispatch claims: one row per
-- device, worded in the device's language ('en' or 'zh'). The chat's id comes
-- with the row, so a chat the person locked is told without its words (G2),
-- quiet hours and Do Not Disturb hold it back (A4) like any other push, and
-- nothing is sent to someone who muted the chat (or whose circle level for
-- the channel is none or muted), who left, or for a board that is closed or
-- whose card was removed. A notice more than 30 minutes old by the time the
-- function gets to it is closed without a push. The words say how long the
-- run is when it would break today ("don't lose your 7 day streak").

create or replace function public.check_in_sweep()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.check_in_boards%rowtype;
  local_now timestamp;
  local_day date;
  minute_of_day integer;
  made integer;
  total_boards integer := 0;
  total_notices integer := 0;
begin
  for b in
    select x.*
    from public.check_in_boards x
    where x.remind_minute is not null
      and x.closed_at is null
    order by x.id
    limit 2000
    for update skip locked
  loop
    begin
      local_now := now() at time zone b.time_zone;
    exception when others then
      continue;
    end;
    local_day := local_now::date;
    minute_of_day := extract(hour from local_now)::integer * 60
      + extract(minute from local_now)::integer;

    if b.last_reminded_on is not distinct from local_day then
      continue;
    end if;
    if minute_of_day < b.remind_minute or minute_of_day > b.remind_minute + 180 then
      continue;
    end if;
    if b.ends_on is not null and local_day > b.ends_on then
      continue;
    end if;
    if b.message_id is null
      or not exists (
        select 1 from public.messages m
        where m.id = b.message_id
          and m.recalled_at is null
          and (m.expires_at is null or m.expires_at > now())
          and m.review_state is null
      )
      or public.conversation_in_suspended_circle(b.conversation_id)
    then
      -- Nothing to remind about today; try again tomorrow.
      update public.check_in_boards set last_reminded_on = local_day where id = b.id;
      continue;
    end if;

    insert into public.check_in_notices (board_id, user_id, day)
    select b.id, cm.user_id, local_day
    from public.conversation_members cm
    join public.profiles p on p.id = cm.user_id
    where cm.conversation_id = b.conversation_id
      and not coalesce(p.is_bot, false)
      and p.deleted_at is null
      and not public.is_user_suspended(cm.user_id)
      and public.form_user_can_view(b.conversation_id, cm.user_id)
      and not exists (
        select 1 from public.check_in_entries e
        where e.board_id = b.id and e.user_id = cm.user_id and e.day = local_day
      )
    on conflict (board_id, user_id, day) do nothing;
    get diagnostics made = row_count;

    update public.check_in_boards set last_reminded_on = local_day where id = b.id;
    total_boards := total_boards + 1;
    total_notices := total_notices + made;
  end loop;

  delete from public.check_in_notices n where n.created_at < now() - interval '2 days';

  if total_notices > 0 then
    perform public.wake_scheduled_dispatch();
  end if;

  return jsonb_build_object('boards', total_boards, 'notices', total_notices);
end;
$$;

revoke execute on function public.check_in_sweep() from public, anon, authenticated;
grant execute on function public.check_in_sweep() to service_role;

create or replace function public.claim_check_in_pushes()
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
  -- Too old to be worth a push now.
  update public.check_in_notices n
  set push_claimed_at = now()
  where n.push_claimed_at is null
    and n.created_at <= now() - interval '30 minutes';

  return query
  with claimed as (
    update public.check_in_notices n
    set push_claimed_at = now()
    where n.push_claimed_at is null
    returning n.*
  ),
  named as (
    select
      c.id as notice_id,
      c.user_id,
      b.conversation_id as notice_conversation_id,
      ch.circle_id as notice_circle_id,
      btrim(replace(replace(b.title, '<', ''), '>', '')) as board_title,
      public.check_in_live_streak(
        s.current_streak, s.last_day, c.day
      ) as run
    from claimed c
    join public.check_in_boards b on b.id = c.board_id
    join public.conversation_members cm
      on cm.conversation_id = b.conversation_id and cm.user_id = c.user_id
    left join public.circle_channels ch on ch.conversation_id = b.conversation_id
    left join public.circles ci on ci.id = ch.circle_id
    left join public.circle_notification_settings ns
      on ns.circle_id = ch.circle_id and ns.user_id = c.user_id
    left join public.check_in_streaks s
      on s.board_id = b.id and s.user_id = c.user_id
    where b.closed_at is null
      and (b.ends_on is null or b.ends_on >= c.day)
      and (cm.muted_until is null or cm.muted_until < now())
      and (ci.id is null or ci.disabled_mode is distinct from 'suspend')
      and (
        ch.id is null
        or (
          coalesce(ns.level, 'all') <> 'none'
          and (ns.muted_until is null or ns.muted_until < now())
        )
      )
      and not exists (
        select 1 from public.check_in_entries e
        where e.board_id = b.id and e.user_id = c.user_id and e.day = c.day
      )
      and exists (
        select 1 from public.messages m
        where m.id = b.message_id
          and m.recalled_at is null
          and (m.expires_at is null or m.expires_at > now())
          and m.review_state is null
      )
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    d.notice_conversation_id,
    d.notice_circle_id,
    case
      when s.language = 'zh' then '今天还没打卡'
      else 'Time to check in'
    end,
    case
      when s.language = 'zh' then
        case
          when d.run >= 2 then
            '「' || d.board_title || '」今天还没打卡，已连续 ' || d.run
              || ' 天，别断了。'
          else '「' || d.board_title || '」今天还没打卡，点开打卡。'
        end
      else
        case
          when d.run >= 2 then
            'You have not checked in to "' || d.board_title || '" today. '
              || 'Keep your ' || d.run || ' day streak going.'
          else 'You have not checked in to "' || d.board_title || '" today.'
        end
    end,
    'check-in-' || d.notice_id::text,
    '/#/chats/' || d.notice_conversation_id::text
  from named d
  join public.push_subscriptions s on s.user_id = d.user_id;
end;
$$;

revoke execute on function public.claim_check_in_pushes()
  from public, anon, authenticated;
grant execute on function public.claim_check_in_pushes() to service_role;

-- With pg_cron installed (hosted Supabase) the sweep runs on a job of its
-- own; without it (local development) it stays a plain function.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'wecord-check-in-sweep';
    perform cron.schedule(
      'wecord-check-in-sweep',
      '*/5 * * * *',
      'select public.check_in_sweep()'
    );
  end if;
exception when others then
  -- No permission to schedule (a restored or local database): the sweep can
  -- still be run by hand.
  null;
end $$;
