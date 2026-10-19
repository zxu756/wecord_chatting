-- Repeating scheduled messages (D4, part 2 of 2): working out the next send,
-- the guard, and writing the next send after one went out.
--
-- recurrence_next(kind, day, time, zone, after, until): the first send after
-- the instant [after], on the wall clock of the IANA [zone]. The rules:
--
--   * Wall clock. Each candidate is a local date and [time] in the zone,
--     turned into an instant with `at time zone`, so daylight saving needs no
--     special case: 9:00 is 9:00 on the clock the sender sees.
--   * A local time that does not exist (the hour skipped when the clocks go
--     forward: 02:30 on the night to summer time) is sent at the same moment
--     the clock would have shown it had the clock not jumped, which reads as
--     the time after the gap (03:30). A local time that happens twice (the
--     hour repeated when the clocks go back: 01:30) is sent once, at its
--     second occurrence (standard time). Postgres' own rule for `at time
--     zone`; it is tested for America/New_York and Europe/Berlin.
--   * daily: every local date. weekdays: Monday to Friday. weekly: the ISO
--     weekday [day]. monthly: the day [day] of the month; a month without
--     that day (the 31st of April, the 30th of February) sends on the LAST
--     DAY of that month instead (28th or 29th of February, 30th of April),
--     and the next month goes back to [day].
--   * [until] is the last local date a send may fall on, inclusive; null for
--     no end. After it, the result is null: the series is over.
--   * [after] decides "after": a candidate must be later than it, so a send
--     that went out 40 seconds late does not repeat the same day.
--   * An unknown zone counts as UTC.

create or replace function public.recurrence_next(
  p_kind text,
  p_day integer,
  p_time time,
  p_zone text,
  p_after timestamptz,
  p_until date default null
)
returns timestamptz
language plpgsql
stable
set search_path = public
as $$
declare
  zone text := coalesce(
    (select n.name from pg_timezone_names n where n.name = p_zone limit 1),
    'UTC'
  );
  start_date date := (p_after at time zone zone)::date;
  candidate_date date;
  candidate timestamptz;
  matches boolean;
  month_last integer;
  offset_days integer;
begin
  if p_kind not in ('daily', 'weekdays', 'weekly', 'monthly')
    or p_time is null or p_after is null
  then
    return null;
  end if;

  -- A month is at most 31 days and a week 7: a match is always within 62.
  for offset_days in 0..62 loop
    candidate_date := start_date + offset_days;
    matches := case p_kind
      when 'daily' then true
      when 'weekdays' then extract(isodow from candidate_date)::integer between 1 and 5
      when 'weekly' then extract(isodow from candidate_date)::integer = p_day
      else (
        select extract(day from candidate_date)::integer
          = least(
            p_day,
            extract(
              day from (date_trunc('month', candidate_date::timestamp) + interval '1 month - 1 day')
            )::integer
          )
      )
    end;
    if not coalesce(matches, false) then
      continue;
    end if;

    if p_until is not null and candidate_date > p_until then
      return null;
    end if;
    candidate := (candidate_date + p_time) at time zone zone;
    if candidate > p_after then
      return candidate;
    end if;
  end loop;
  return null;
end;
$$;

-- A pure rule over its arguments, nothing about anyone: the guard calls it as
-- the client, so signed-in people may call it too.
revoke execute on function public.recurrence_next(text, integer, time, text, timestamptz, date)
  from public, anon;
grant execute on function public.recurrence_next(text, integer, time, text, timestamptz, date)
  to authenticated, service_role;

-- The zone a client's repeating message falls back to when the app did not
-- report one: the caller's own notification zone (202610210310). The guard
-- runs as the client, and notification_time_zone is private to the server, so
-- this answers for the caller only; for anyone else it says UTC.
create or replace function public.schedule_fallback_time_zone(p_owner_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_owner_id is not null and p_owner_id = auth.uid()
      then public.notification_time_zone(p_owner_id)
    else 'UTC'
  end;
$$;

revoke execute on function public.schedule_fallback_time_zone(uuid) from public, anon;
grant execute on function public.schedule_fallback_time_zone(uuid) to authenticated;

-- 202610170010 with the repeat rule. What clients (the authenticated role)
-- may write: queue a message for a conversation they can send in, change its
-- text, time or repeat, or put a failed one back to pending. For a repeating
-- message the server works out the rest of the rule from the first send:
--
--   * the zone is the one the app reported (recurrence_tz), else the person's
--     notification zone (202610210310), else UTC;
--   * the time of day is that of the first send, in that zone, to the minute;
--   * weekly repeats on the weekday of the first send, monthly on its day of
--     the month;
--   * a "weekdays" message first set for a Saturday or Sunday goes out on the
--     Monday after;
--   * at most 20 repeating messages wait at once, and an end date may be at
--     most two years away.
-- The delivery functions run as their owner and are not held to this.
create or replace function public.scheduled_messages_guard()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  pending_count integer;
  repeating_count integer;
  zone text;
  local_start timestamp;
  moved timestamptz;
begin
  new.updated_at := now();

  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.status := 'pending';
    new.attempts := 0;
    new.last_error := null;
    new.sent_message_id := null;
    new.sent_at := null;
    new.push_claimed_at := null;
    new.recurrence_parent_id := null;
    new.body := btrim(new.body);

    select count(*)
    into pending_count
    from public.scheduled_messages s
    where s.owner_id = new.owner_id
      and s.status = 'pending';
    if pending_count >= 100 then
      raise exception 'Too many scheduled messages' using errcode = '53400';
    end if;
  else
    if new.owner_id is distinct from old.owner_id
      or new.conversation_id is distinct from old.conversation_id
      or new.sent_message_id is distinct from old.sent_message_id
      or new.sent_at is distinct from old.sent_at
      or new.push_claimed_at is distinct from old.push_claimed_at
      or new.recurrence_parent_id is distinct from old.recurrence_parent_id
    then
      raise exception 'Scheduled message fields are read only' using errcode = '42501';
    end if;
    if old.status = 'sent' then
      raise exception 'Scheduled message was already sent' using errcode = '22023';
    end if;
    -- Editing a message puts it (back) in the queue.
    new.status := 'pending';
    new.attempts := 0;
    new.last_error := null;
    new.body := btrim(new.body);
  end if;

  if new.recurrence is null then
    new.recurrence_day := null;
    new.recurrence_time := null;
    new.recurrence_tz := null;
    new.recurrence_until := null;
  else
    if new.recurrence not in ('daily', 'weekdays', 'weekly', 'monthly') then
      raise exception 'Unknown repeat' using errcode = '22023';
    end if;
    select count(*)
    into repeating_count
    from public.scheduled_messages s
    where s.owner_id = new.owner_id
      and s.status = 'pending'
      and s.recurrence is not null
      and s.id <> new.id;
    if repeating_count >= 20 then
      raise exception 'Too many repeating messages' using errcode = '53400';
    end if;

    zone := coalesce(
      (select n.name from pg_timezone_names n
        where n.name = nullif(btrim(new.recurrence_tz), '') limit 1),
      public.schedule_fallback_time_zone(new.owner_id),
      'UTC'
    );
    new.recurrence_tz := zone;
    local_start := new.send_at at time zone zone;
    new.recurrence_time := date_trunc('minute', local_start)::time;
    new.recurrence_day := case new.recurrence
      when 'weekly' then extract(isodow from local_start)::integer
      when 'monthly' then extract(day from local_start)::integer
      else null
    end;

    if new.recurrence_until is not null then
      if new.recurrence_until < local_start::date then
        raise exception 'The end is before the first send' using errcode = '22023';
      end if;
      if new.recurrence_until > (now() at time zone zone)::date + 730 then
        raise exception 'The end is too far away' using errcode = '22023';
      end if;
    end if;

    -- The first send of a weekdays message fits the rule too.
    if new.recurrence = 'weekdays'
      and extract(isodow from local_start)::integer > 5
    then
      moved := public.recurrence_next(
        'weekdays', null, new.recurrence_time, zone, new.send_at,
        new.recurrence_until
      );
      if moved is null then
        raise exception 'The end is before the first send' using errcode = '22023';
      end if;
      new.send_at := moved;
    end if;
  end if;

  if new.send_at < now() - interval '1 minute' then
    raise exception 'Scheduled time is in the past' using errcode = '22023';
  end if;
  if new.send_at > now() + interval '1 year' then
    raise exception 'Scheduled time is too far away' using errcode = '22023';
  end if;
  return new;
end;
$$;

-- After a repeating message went out (or failed for good), writes the next
-- one. The row stays 'sent' or 'failed' so the owner can see what happened;
-- the new row waits for its time.
--
--   * The next send is the first one on the rule after the later of the
--     message's own time and now: a send that was late does not make a
--     second one the same day, a "Send now" sent early skips the occurrence
--     it replaced, and an outage of several days does not send the missed
--     days one after another.
--   * No next send when the owner left the conversation, when the end date has
--     passed, or when the rule has no day left.
--   * A failed send still schedules the next one (a muted hour or a slow mode
--     is no reason to end a weekly report), unless the owner is gone from the
--     conversation.
--   * Exactly once: the unique index on recurrence_parent_id turns a second
--     try into nothing. A problem here never fails the send itself.
create or replace function public.scheduled_messages_spawn_next()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  next_at timestamptz;
begin
  begin
    if not exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = new.conversation_id
        and cm.user_id = new.owner_id
    ) then
      return new;
    end if;

    next_at := public.recurrence_next(
      new.recurrence,
      new.recurrence_day,
      new.recurrence_time,
      new.recurrence_tz,
      greatest(new.send_at, now()),
      new.recurrence_until
    );
    if next_at is null then
      return new;
    end if;

    insert into public.scheduled_messages (
      owner_id, conversation_id, body, mentions, send_at,
      recurrence, recurrence_day, recurrence_time, recurrence_tz,
      recurrence_until, recurrence_parent_id
    )
    values (
      new.owner_id, new.conversation_id, new.body, new.mentions, next_at,
      new.recurrence, new.recurrence_day, new.recurrence_time, new.recurrence_tz,
      new.recurrence_until, new.id
    )
    on conflict (recurrence_parent_id) where recurrence_parent_id is not null
    do nothing;
  exception when others then
    raise warning 'Could not schedule the next send after %: %', new.id, sqlerrm;
  end;
  return new;
end;
$$;

revoke execute on function public.scheduled_messages_spawn_next()
  from public, anon, authenticated;

drop trigger if exists scheduled_messages_spawn_next on public.scheduled_messages;
create trigger scheduled_messages_spawn_next
  after update of status on public.scheduled_messages
  for each row
  when (
    new.recurrence is not null
    and new.status in ('sent', 'failed')
    and old.status is distinct from new.status
  )
  execute function public.scheduled_messages_spawn_next();
