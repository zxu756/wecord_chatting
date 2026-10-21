-- Events 2.0 (roadmap C10), part 4 of 7: repeating events, and the sweep that
-- keeps the waiting lists moving.
--
-- A series is made one occurrence at a time. Once an occurrence has started,
-- events2_spawn_next makes the next one (events2_next_start, 202610270400:
-- the same wall-clock time in the zone of the device that made the event,
-- whatever daylight saving does, counted from the series anchor so a month
-- shorter than the anchor's day does not move later months):
--
--   * it copies the title, place, link, description, reminders, cover,
--     questions, capacity and repeat of the occurrence that just started, so
--     edits carry forward;
--   * a chat event announces itself in the chat like a new event (a system
--     message from the organiser) and the organiser is Going; if the
--     organiser left the chat or deleted their account the series ends;
--   * a pinned event passes its pin on;
--   * people have to sign up again for each occurrence;
--   * after an outage it does not make the occurrences it missed: it makes
--     the first one after now;
--   * an organiser an admin suspended, or a circle an admin suspended (K1),
--     pauses the series until it is lifted.
--
-- events2_sweep runs the above and moves people up the waiting lists (for
-- seats freed by someone leaving the chat), and tidies old pushes and codes. It is
-- scheduled with a job of its own, every 5 minutes: run_later_dispatch (the
-- every-minute dispatcher) is not touched.

create or replace function public.events2_spawn_next(
  as_of timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  made integer := 0;
  chat_src public.chat_events%rowtype;
  circle_src public.circle_events%rowtype;
  new_chat public.chat_events%rowtype;
  next_start timestamptz;
  next_end timestamptz;
  creator_answers jsonb;
  actor_name text;
  announcement_id uuid;
begin
  for chat_src in
    select e.*
    from public.chat_events e
    where e.recurrence is not null
      and e.next_spawned_at is null
      and e.starts_at <= as_of
    order by e.starts_at
    limit 200
    for update skip locked
  loop
    if chat_src.created_by is null
      or not exists (
        select 1 from public.conversation_members cm
        where cm.conversation_id = chat_src.conversation_id
          and cm.user_id = chat_src.created_by
      )
      or exists (
        select 1 from public.profiles p
        where p.id = chat_src.created_by and p.deleted_at is not null
      )
    then
      -- Nobody left to run it: the series ends here.
      update public.chat_events set recurrence = null where id = chat_src.id;
      continue;
    end if;
    if public.is_user_suspended(chat_src.created_by) then
      continue;
    end if;

    next_start := public.events2_next_start(
      chat_src.recurrence, chat_src.recurrence_anchor, chat_src.recurrence_tz,
      greatest(chat_src.starts_at, as_of)
    );
    if next_start is null then
      update public.chat_events set recurrence = null where id = chat_src.id;
      continue;
    end if;
    next_end := case
      when chat_src.ends_at is null then null
      else next_start + (chat_src.ends_at - chat_src.starts_at)
    end;

    if exists (
      select 1 from public.chat_events x
      where x.series_id = chat_src.series_id and x.starts_at = next_start
    ) then
      update public.chat_events set next_spawned_at = as_of where id = chat_src.id;
      continue;
    end if;

    insert into public.chat_events (
      conversation_id, created_by, title, description, location_text, link_url,
      starts_at, ends_at, reminder_leads, pinned_at, pinned_by,
      recurrence, recurrence_tz, recurrence_anchor, series_id,
      cover_path, questions, capacity
    )
    values (
      chat_src.conversation_id, chat_src.created_by, chat_src.title,
      chat_src.description, chat_src.location_text, chat_src.link_url,
      next_start, next_end, chat_src.reminder_leads,
      chat_src.pinned_at, chat_src.pinned_by,
      chat_src.recurrence, chat_src.recurrence_tz, chat_src.recurrence_anchor,
      chat_src.series_id, chat_src.cover_path, chat_src.questions, chat_src.capacity
    )
    returning * into new_chat;

    select r.answers into creator_answers
    from public.chat_event_rsvps r
    where r.event_id = chat_src.id and r.user_id = chat_src.created_by;
    insert into public.chat_event_rsvps (
      event_id, user_id, status, conversation_id, answers
    )
    values (
      new_chat.id, chat_src.created_by, 'going', chat_src.conversation_id,
      coalesce(creator_answers, '{}'::jsonb)
    );

    select nullif(btrim(p.display_name), '') into actor_name
    from public.profiles p where p.id = chat_src.created_by;

    insert into public.messages (conversation_id, sender_id, type, body, attachment)
    values (
      chat_src.conversation_id,
      chat_src.created_by,
      'system',
      coalesce(actor_name, 'Someone') || ' created an event: ' || chat_src.title,
      jsonb_build_object('kind', 'event', 'event_id', new_chat.id)
    )
    returning id into announcement_id;

    update public.chat_events
    set message_id = announcement_id
    where id = new_chat.id;

    -- The pin moves to the new occurrence.
    update public.chat_events
    set pinned_at = null, pinned_by = null, next_spawned_at = as_of
    where id = chat_src.id;

    made := made + 1;
  end loop;

  for circle_src in
    select e.*
    from public.circle_events e
    where e.recurrence is not null
      and e.next_spawned_at is null
      and e.starts_at <= as_of
    order by e.starts_at
    limit 200
    for update skip locked
  loop
    if public.circle_is_suspended(circle_src.circle_id) then
      continue;
    end if;

    next_start := public.events2_next_start(
      circle_src.recurrence, circle_src.recurrence_anchor, circle_src.recurrence_tz,
      greatest(circle_src.starts_at, as_of)
    );
    if next_start is null then
      update public.circle_events set recurrence = null where id = circle_src.id;
      continue;
    end if;
    next_end := case
      when circle_src.ends_at is null then null
      else next_start + (circle_src.ends_at - circle_src.starts_at)
    end;

    if exists (
      select 1 from public.circle_events x
      where x.series_id = circle_src.series_id and x.starts_at = next_start
    ) then
      update public.circle_events set next_spawned_at = as_of where id = circle_src.id;
      continue;
    end if;

    insert into public.circle_events (
      circle_id, title, description, location_type, channel_id, location_text,
      starts_at, ends_at, created_by,
      recurrence, recurrence_tz, recurrence_anchor, series_id,
      cover_path, questions, capacity
    )
    values (
      circle_src.circle_id, circle_src.title, circle_src.description,
      circle_src.location_type, circle_src.channel_id, circle_src.location_text,
      next_start, next_end, circle_src.created_by,
      circle_src.recurrence, circle_src.recurrence_tz, circle_src.recurrence_anchor,
      circle_src.series_id, circle_src.cover_path, circle_src.questions,
      circle_src.capacity
    );

    update public.circle_events
    set next_spawned_at = as_of
    where id = circle_src.id;

    made := made + 1;
  end loop;

  return made;
end;
$$;

create or replace function public.events2_sweep()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  spawned integer;
  promoted integer := 0;
  target record;
begin
  spawned := public.events2_spawn_next(now());

  -- Seats freed by people who left a chat. (A seat freed by an answer is
  -- handed on at once, in rsvp_chat_event.)
  for target in
    select distinct 'chat'::text as kind, w.chat_event_id as event_id
    from public.event_waitlist w
    where w.chat_event_id is not null
    union all
    select distinct 'circle', w.circle_event_id
    from public.event_waitlist w
    where w.circle_event_id is not null
  loop
    promoted := promoted + public.events2_promote(target.kind, target.event_id);
  end loop;

  -- Pushes nobody claimed in two days, and codes that ran out a day ago.
  delete from public.event_notices n where n.created_at < now() - interval '2 days';
  delete from public.event_check_in_codes c
  where c.expires_at < now() - interval '1 day' or c.revoked_at < now() - interval '1 day';

  return jsonb_build_object('spawned', spawned, 'promoted', promoted);
end;
$$;

revoke execute on function public.events2_spawn_next(timestamptz)
  from public, anon, authenticated;
revoke execute on function public.events2_sweep() from public, anon, authenticated;
grant execute on function public.events2_spawn_next(timestamptz) to service_role;
grant execute on function public.events2_sweep() to service_role;

-- With pg_cron installed (hosted Supabase) the sweep runs on a job of its
-- own; without it (local development) these stay plain functions.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'wecord-events2-sweep';
    perform cron.schedule(
      'wecord-events2-sweep',
      '*/5 * * * *',
      'select public.events2_sweep()'
    );
  end if;
exception when others then
  -- No permission to schedule (a restored or local database): the sweep can
  -- still be run by hand.
  null;
end $$;
