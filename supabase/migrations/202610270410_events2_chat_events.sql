-- Events 2.0 (roadmap C10), part 2 of 7: the events of group and direct chats.
--
-- Rewritten from their only definition (202610170050_chat_events.sql; no
-- later migration redefines any of them), so nothing of anyone else's is
-- lost:
--
--   chat_event_check_conversation   plus: a suspended account (K1) writes nothing
--   chat_event_json                 plus: cover, repeat, questions, capacity,
--                                   waiting list, my answers, check-ins
--   create_chat_event               plus event_options jsonb
--   update_chat_event               plus event_options jsonb
--   cancel_chat_event               plus cancel_series
--   rsvp_chat_event                 plus answers, capacity and the waiting list
--
-- event_options is {recurrence: 'weekly'|'biweekly'|'monthly'|null, timezone,
-- cover_path, questions: [...], capacity}. On a new event a missing key means
-- none. On an update a missing key keeps what the event has and a JSON null
-- clears it (events2_merge_options, 202610270400). Old clients that send none
-- of it keep working.
--
-- Signing up: a Going answer takes a seat while there are any; with the event
-- full the person goes to the waiting list instead (my_waitlisted in the
-- payload) and moves up in order when a seat frees: the person changes their
-- answer, the capacity grows, or the sweep finds someone left the chat. Maybe
-- and Can't never take a seat. Required questions must be answered to say
-- Going. Nobody can join an event that is over or cancelled.

create or replace function public.chat_event_check_conversation(
  target_conversation_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if public.is_user_suspended(auth.uid()) then
    raise exception 'Account suspended' using errcode = '42501';
  end if;

  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.conversations c
    where c.id = target_conversation_id
      and c.type in ('direct', 'group')
  ) then
    raise exception 'Only group chats and direct messages have events'
      using errcode = '22023';
  end if;

  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Cannot post in this conversation' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.chat_event_json(event_row public.chat_events)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', event_row.id,
    'conversation_id', event_row.conversation_id,
    'title', event_row.title,
    'description', event_row.description,
    'location_text', event_row.location_text,
    'link_url', event_row.link_url,
    'starts_at', event_row.starts_at,
    'ends_at', event_row.ends_at,
    'reminder_leads', to_jsonb(event_row.reminder_leads),
    'message_id', event_row.message_id,
    'pinned_at', event_row.pinned_at,
    'cancelled_at', event_row.cancelled_at,
    'created_by', event_row.created_by,
    'created_at', event_row.created_at,
    'creator', (
      select jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'display_name', p.display_name,
        'avatar_url', p.avatar_url
      )
      from public.profiles p
      where p.id = event_row.created_by
    ),
    'going_count', (
      select count(*)
      from public.chat_event_rsvps r
      join public.conversation_members cm
        on cm.conversation_id = event_row.conversation_id
       and cm.user_id = r.user_id
      where r.event_id = event_row.id and r.status = 'going'
    ),
    'maybe_count', (
      select count(*)
      from public.chat_event_rsvps r
      join public.conversation_members cm
        on cm.conversation_id = event_row.conversation_id
       and cm.user_id = r.user_id
      where r.event_id = event_row.id and r.status = 'maybe'
    ),
    'declined_count', (
      select count(*)
      from public.chat_event_rsvps r
      join public.conversation_members cm
        on cm.conversation_id = event_row.conversation_id
       and cm.user_id = r.user_id
      where r.event_id = event_row.id and r.status = 'declined'
    ),
    'my_status', (
      select r.status
      from public.chat_event_rsvps r
      where r.event_id = event_row.id and r.user_id = auth.uid()
    ),
    'attendees', coalesce((
      select jsonb_agg(attendee order by attendee_rank, attendee_at)
      from (
        select
          jsonb_build_object(
            'id', p.id,
            'username', p.username,
            'display_name', p.display_name,
            'avatar_url', p.avatar_url,
            'status', r.status
          ) as attendee,
          case r.status when 'going' then 0 else 1 end as attendee_rank,
          r.updated_at as attendee_at
        from public.chat_event_rsvps r
        join public.conversation_members cm
          on cm.conversation_id = event_row.conversation_id
         and cm.user_id = r.user_id
        join public.profiles p on p.id = r.user_id
        where r.event_id = event_row.id
          and r.status in ('going', 'maybe')
        order by attendee_rank, attendee_at
        limit 12
      ) attendees
    ), '[]'::jsonb),
    'can_manage', public.can_manage_chat_event(event_row, auth.uid()),
    -- Events 2.0 (202610270410)
    'cover_path', event_row.cover_path,
    'recurrence', event_row.recurrence,
    'recurrence_tz', event_row.recurrence_tz,
    'series_id', event_row.series_id,
    'questions', event_row.questions,
    'capacity', event_row.capacity,
    'waitlist_count', (
      select count(*)
      from public.event_waitlist w
      join public.conversation_members cm
        on cm.conversation_id = event_row.conversation_id
       and cm.user_id = w.user_id
      where w.chat_event_id = event_row.id
    ),
    'my_waitlisted', exists (
      select 1 from public.event_waitlist w
      where w.chat_event_id = event_row.id and w.user_id = auth.uid()
    ),
    'my_answers', coalesce(
      (
        select r.answers from public.chat_event_rsvps r
        where r.event_id = event_row.id and r.user_id = auth.uid()
      ),
      (
        select w.answers from public.event_waitlist w
        where w.chat_event_id = event_row.id and w.user_id = auth.uid()
      ),
      '{}'::jsonb
    ),
    'checked_in_count', (
      select count(*)
      from public.event_check_ins ci
      join public.conversation_members cm
        on cm.conversation_id = event_row.conversation_id
       and cm.user_id = ci.user_id
      where ci.chat_event_id = event_row.id
    ),
    'my_checked_in', exists (
      select 1 from public.event_check_ins ci
      where ci.chat_event_id = event_row.id and ci.user_id = auth.uid()
    ),
    'photo_count', (
      select count(*) from public.event_photos ph
      where ph.chat_event_id = event_row.id
    )
  );
$$;

-- The old signatures go: a call by name with the new optional argument would
-- otherwise match both.
drop function if exists public.create_chat_event(
  uuid, text, timestamptz, timestamptz, text, text, text, integer[], boolean
);
drop function if exists public.update_chat_event(
  uuid, text, timestamptz, timestamptz, text, text, text, integer[]
);
drop function if exists public.cancel_chat_event(uuid);
drop function if exists public.rsvp_chat_event(uuid, text);

create or replace function public.create_chat_event(
  target_conversation_id uuid,
  event_title text,
  event_starts_at timestamptz,
  event_ends_at timestamptz default null,
  event_description text default null,
  event_location text default null,
  event_link text default null,
  event_reminder_leads integer[] default array[15],
  pin_event boolean default false,
  event_options jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_title text := btrim(coalesce(event_title, ''));
  new_event public.chat_events%rowtype;
  actor_name text;
  announcement_id uuid;
  options jsonb;
begin
  perform public.chat_event_check_conversation(target_conversation_id);

  if char_length(trimmed_title) not between 1 and 100 then
    raise exception 'Event title must be 1 to 100 characters'
      using errcode = '22023';
  end if;
  if event_starts_at is null or event_starts_at < now() - interval '5 minutes' then
    raise exception 'Event must start in the future' using errcode = '22023';
  end if;
  if event_ends_at is not null and event_ends_at <= event_starts_at then
    raise exception 'Event must end after it starts' using errcode = '22023';
  end if;

  options := public.events2_merge_options(
    target_conversation_id, event_options, null, null, null, '[]'::jsonb, null
  );

  if coalesce(pin_event, false) then
    update public.chat_events
    set pinned_at = null, pinned_by = null
    where conversation_id = target_conversation_id
      and pinned_at is not null;
  end if;

  insert into public.chat_events (
    conversation_id,
    created_by,
    title,
    description,
    location_text,
    link_url,
    starts_at,
    ends_at,
    reminder_leads,
    pinned_at,
    pinned_by,
    recurrence,
    recurrence_tz,
    recurrence_anchor,
    series_id,
    cover_path,
    questions,
    capacity
  )
  values (
    target_conversation_id,
    current_user_id,
    trimmed_title,
    nullif(btrim(coalesce(event_description, '')), ''),
    nullif(btrim(coalesce(event_location, '')), ''),
    nullif(btrim(coalesce(event_link, '')), ''),
    event_starts_at,
    event_ends_at,
    public.normalize_chat_event_leads(event_reminder_leads),
    case when coalesce(pin_event, false) then now() end,
    case when coalesce(pin_event, false) then current_user_id end,
    options ->> 'recurrence',
    options ->> 'recurrence_tz',
    case when options ->> 'recurrence' is not null then event_starts_at end,
    case when options ->> 'recurrence' is not null then gen_random_uuid() end,
    options ->> 'cover_path',
    options -> 'questions',
    (options ->> 'capacity')::integer
  )
  returning * into new_event;

  insert into public.chat_event_rsvps (
    event_id, user_id, status, conversation_id
  )
  values (new_event.id, current_user_id, 'going', target_conversation_id);

  select nullif(btrim(p.display_name), '')
  into actor_name
  from public.profiles p
  where p.id = current_user_id;

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    attachment
  )
  values (
    target_conversation_id,
    current_user_id,
    'system',
    coalesce(actor_name, 'Someone') || ' created an event: ' || trimmed_title,
    jsonb_build_object('kind', 'event', 'event_id', new_event.id)
  )
  returning id into announcement_id;

  update public.chat_events
  set message_id = announcement_id
  where id = new_event.id
  returning * into new_event;

  return public.chat_event_json(new_event);
end;
$$;

create or replace function public.update_chat_event(
  target_event_id uuid,
  event_title text,
  event_starts_at timestamptz,
  event_ends_at timestamptz default null,
  event_description text default null,
  event_location text default null,
  event_link text default null,
  event_reminder_leads integer[] default array[15],
  event_options jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  trimmed_title text := btrim(coalesce(event_title, ''));
  current_event public.chat_events%rowtype;
  options jsonb;
  old_capacity integer;
begin
  select e.* into current_event
  from public.chat_events e
  where e.id = target_event_id
  for update;

  if current_event.id is null then
    raise exception 'Event not found' using errcode = '42501';
  end if;
  perform public.chat_event_check_conversation(current_event.conversation_id);

  if not public.can_manage_chat_event(current_event, auth.uid()) then
    raise exception 'Cannot change this event' using errcode = '42501';
  end if;
  if current_event.cancelled_at is not null then
    raise exception 'This event was cancelled' using errcode = '22023';
  end if;
  if char_length(trimmed_title) not between 1 and 100 then
    raise exception 'Event title must be 1 to 100 characters'
      using errcode = '22023';
  end if;
  if event_starts_at is null then
    raise exception 'Event needs a start' using errcode = '22023';
  end if;
  if event_ends_at is not null and event_ends_at <= event_starts_at then
    raise exception 'Event must end after it starts' using errcode = '22023';
  end if;

  old_capacity := current_event.capacity;
  options := public.events2_merge_options(
    current_event.conversation_id,
    event_options,
    current_event.recurrence,
    current_event.recurrence_tz,
    current_event.cover_path,
    current_event.questions,
    current_event.capacity
  );

  update public.chat_events
  set
    title = trimmed_title,
    description = nullif(btrim(coalesce(event_description, '')), ''),
    location_text = nullif(btrim(coalesce(event_location, '')), ''),
    link_url = nullif(btrim(coalesce(event_link, '')), ''),
    starts_at = event_starts_at,
    ends_at = event_ends_at,
    reminder_leads = public.normalize_chat_event_leads(event_reminder_leads),
    recurrence = options ->> 'recurrence',
    recurrence_tz = options ->> 'recurrence_tz',
    -- A series that moves its start (or begins now) counts from the new start.
    recurrence_anchor = case
      when options ->> 'recurrence' is null then null
      when current_event.recurrence_anchor is null
        or event_starts_at is distinct from current_event.starts_at
        or options ->> 'recurrence' is distinct from current_event.recurrence
        or options ->> 'recurrence_tz' is distinct from current_event.recurrence_tz
      then event_starts_at
      else current_event.recurrence_anchor
    end,
    series_id = case
      when options ->> 'recurrence' is null then current_event.series_id
      else coalesce(current_event.series_id, gen_random_uuid())
    end,
    cover_path = options ->> 'cover_path',
    questions = options -> 'questions',
    capacity = (options ->> 'capacity')::integer,
    updated_at = now()
  where id = current_event.id
  returning * into current_event;

  -- A moved event reminds again.
  delete from public.chat_event_reminders r
  where r.event_id = current_event.id;

  -- More seats let people off the waiting list.
  if current_event.capacity is distinct from old_capacity then
    perform public.events2_promote('chat', current_event.id);
  end if;

  return public.chat_event_json(current_event);
end;
$$;

-- Cancels this event. With [cancel_series] the whole series ends: later
-- occurrences already made are cancelled too and no more are made.
create or replace function public.cancel_chat_event(
  target_event_id uuid,
  cancel_series boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_event public.chat_events%rowtype;
begin
  select e.* into current_event
  from public.chat_events e
  where e.id = target_event_id
  for update;

  if current_event.id is null then
    raise exception 'Event not found' using errcode = '42501';
  end if;
  perform public.chat_event_check_conversation(current_event.conversation_id);

  if not public.can_manage_chat_event(current_event, auth.uid()) then
    raise exception 'Cannot cancel this event' using errcode = '42501';
  end if;

  update public.chat_events
  set
    cancelled_at = coalesce(cancelled_at, now()),
    pinned_at = null,
    pinned_by = null,
    updated_at = now()
  where id = current_event.id
  returning * into current_event;

  if coalesce(cancel_series, false) and current_event.series_id is not null then
    update public.chat_events
    set recurrence = null
    where series_id = current_event.series_id and recurrence is not null;

    update public.chat_events
    set cancelled_at = coalesce(cancelled_at, now()),
      pinned_at = null,
      pinned_by = null,
      updated_at = now()
    where series_id = current_event.series_id
      and starts_at > now()
      and cancelled_at is null;

    select e.* into current_event
    from public.chat_events e
    where e.id = current_event.id;
  end if;

  return public.chat_event_json(current_event);
end;
$$;

-- Sets the caller's answer; null clears it. [rsvp_answers] are the answers to
-- the event's questions ({question id: text}); with none given, the ones the
-- person gave before are kept.
create or replace function public.rsvp_chat_event(
  target_event_id uuid,
  rsvp_status text,
  rsvp_answers jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  current_event public.chat_events%rowtype;
  previous_status text;
  previous_answers jsonb;
  clean_answers jsonb;
begin
  select e.* into current_event
  from public.chat_events e
  where e.id = target_event_id
  for update;

  if current_event.id is null then
    raise exception 'Event not found' using errcode = '42501';
  end if;
  perform public.chat_event_check_conversation(current_event.conversation_id);

  if rsvp_status is not null and rsvp_status not in ('going', 'maybe', 'declined') then
    raise exception 'Unknown answer' using errcode = '22023';
  end if;
  if current_event.cancelled_at is not null then
    raise exception 'This event was cancelled' using errcode = '22023';
  end if;

  select r.status, r.answers into previous_status, previous_answers
  from public.chat_event_rsvps r
  where r.event_id = current_event.id and r.user_id = current_user_id;

  if rsvp_status is not null and rsvp_status <> 'declined'
    and coalesce(current_event.ends_at, current_event.starts_at + interval '2 hours') <= now()
  then
    raise exception 'This event is over' using errcode = '22023';
  end if;

  if rsvp_status is null then
    delete from public.chat_event_rsvps r
    where r.event_id = current_event.id and r.user_id = current_user_id;
    delete from public.event_waitlist w
    where w.chat_event_id = current_event.id and w.user_id = current_user_id;
  elsif rsvp_status = 'going' then
    clean_answers := public.events2_clean_answers(
      current_event.questions,
      coalesce(rsvp_answers, previous_answers, (
        select w.answers from public.event_waitlist w
        where w.chat_event_id = current_event.id and w.user_id = current_user_id
      )),
      true
    );

    if previous_status = 'going' then
      update public.chat_event_rsvps r
      set answers = clean_answers, updated_at = now()
      where r.event_id = current_event.id and r.user_id = current_user_id;
    elsif current_event.capacity is null
      or public.events2_seats_taken('chat', current_event.id) < current_event.capacity
    then
      insert into public.chat_event_rsvps (
        event_id, user_id, status, conversation_id, answers
      )
      values (
        current_event.id, current_user_id, 'going',
        current_event.conversation_id, clean_answers
      )
      on conflict (event_id, user_id) do update
      set status = 'going', answers = excluded.answers, updated_at = now();
      delete from public.event_waitlist w
      where w.chat_event_id = current_event.id and w.user_id = current_user_id;
    else
      -- Full: wait in line (a Maybe stays as it was).
      insert into public.event_waitlist (chat_event_id, user_id, answers)
      values (current_event.id, current_user_id, clean_answers)
      on conflict (chat_event_id, user_id) where chat_event_id is not null
      do update set answers = excluded.answers;
    end if;
  else
    insert into public.chat_event_rsvps (
      event_id, user_id, status, conversation_id, answers
    )
    values (
      current_event.id, current_user_id, rsvp_status,
      current_event.conversation_id,
      public.events2_clean_answers(
        current_event.questions, coalesce(rsvp_answers, previous_answers), false
      )
    )
    on conflict (event_id, user_id) do update
    set status = excluded.status, answers = excluded.answers, updated_at = now();
    delete from public.event_waitlist w
    where w.chat_event_id = current_event.id and w.user_id = current_user_id;
  end if;

  -- A seat that opened goes to the next in line.
  if previous_status = 'going' and rsvp_status is distinct from 'going' then
    perform public.events2_promote('chat', current_event.id);
  end if;

  return public.chat_event_json(current_event);
end;
$$;

revoke execute on function public.chat_event_check_conversation(uuid)
  from public, anon, authenticated;
revoke execute on function public.chat_event_json(public.chat_events)
  from public, anon, authenticated;
revoke execute on function public.create_chat_event(
  uuid, text, timestamptz, timestamptz, text, text, text, integer[], boolean, jsonb
) from public, anon;
revoke execute on function public.update_chat_event(
  uuid, text, timestamptz, timestamptz, text, text, text, integer[], jsonb
) from public, anon;
revoke execute on function public.cancel_chat_event(uuid, boolean) from public, anon;
revoke execute on function public.rsvp_chat_event(uuid, text, jsonb) from public, anon;

grant execute on function public.create_chat_event(
  uuid, text, timestamptz, timestamptz, text, text, text, integer[], boolean, jsonb
) to authenticated;
grant execute on function public.update_chat_event(
  uuid, text, timestamptz, timestamptz, text, text, text, integer[], jsonb
) to authenticated;
grant execute on function public.cancel_chat_event(uuid, boolean) to authenticated;
grant execute on function public.rsvp_chat_event(uuid, text, jsonb) to authenticated;
