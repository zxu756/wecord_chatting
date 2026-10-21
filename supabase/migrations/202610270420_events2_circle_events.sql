-- Events 2.0 (roadmap C10), part 3 of 7: the events of circles.
--
-- Rewritten from their only definition (202610130022_circle_events.sql; no
-- later migration redefines any of them). circle_event_profile, which
-- 202610170101 patched to hide a bio the viewer may not see, is NOT touched
-- here: the payload still calls it.
--
--   circle_event_payload   plus: cover, repeat, questions, capacity, waiting
--                          list, my answers, check-ins, photos
--   create_circle_event    plus event_options jsonb, and K1: nothing in a
--                          circle an admin took down, nothing by a suspended
--                          account
--   update_circle_event    the same; the audit entry names a changed capacity,
--                          repeat or set of questions
--   cancel_circle_event    plus cancel_series
--   toggle_event_interest  signing up or leaving, as before, but through the
--                          same capacity and questions as register_circle_event
--
-- New:
--   register_circle_event(event, answers)  sign up with answers to the
--                          event's questions (the interest of before, plus
--                          answers); a full event puts the person on the
--                          waiting list
--   unregister_circle_event(event)         leave the event (or its waiting
--                          list); the next in line moves up
--
-- event_options works as for chat events (202610270410). The permission to
-- make and change events is what it was: manage_events, or being the event's
-- creator for changes. A circle an admin delisted or suspended takes no change
-- from its organisers; a suspended one takes no sign-up either (K1).

create or replace function public.circle_event_payload(
  event_row public.circle_events
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', event_row.id,
    'circle_id', event_row.circle_id,
    'title', event_row.title,
    'description', event_row.description,
    'location_type', event_row.location_type,
    'channel_id', event_row.channel_id,
    'channel_name', channel.name,
    'channel_conversation_id', channel.conversation_id,
    'location_text', event_row.location_text,
    'starts_at', event_row.starts_at,
    'ends_at', event_row.ends_at,
    'created_by', event_row.created_by,
    'created_at', event_row.created_at,
    'updated_at', event_row.updated_at,
    'cancelled_at', event_row.cancelled_at,
    'creator', case
      when event_row.created_by is null then null
      else public.circle_event_profile(event_row.circle_id, event_row.created_by)
    end,
    'interested_count', (
      select count(*)
      from public.circle_event_rsvps r
      where r.event_id = event_row.id
    ),
    'interested_by_me', exists (
      select 1
      from public.circle_event_rsvps r
      where r.event_id = event_row.id
        and r.user_id = auth.uid()
    ),
    'can_manage',
      event_row.created_by is not distinct from auth.uid()
      or public.current_user_has_circle_permission(
        event_row.circle_id,
        'manage_events'
      ),
    -- Events 2.0 (202610270420)
    'cover_path', event_row.cover_path,
    'recurrence', event_row.recurrence,
    'recurrence_tz', event_row.recurrence_tz,
    'series_id', event_row.series_id,
    'questions', event_row.questions,
    'capacity', event_row.capacity,
    'waitlist_count', (
      select count(*)
      from public.event_waitlist w
      where w.circle_event_id = event_row.id
    ),
    'my_waitlisted', exists (
      select 1 from public.event_waitlist w
      where w.circle_event_id = event_row.id and w.user_id = auth.uid()
    ),
    'my_answers', coalesce(
      (
        select r.answers from public.circle_event_rsvps r
        where r.event_id = event_row.id and r.user_id = auth.uid()
      ),
      (
        select w.answers from public.event_waitlist w
        where w.circle_event_id = event_row.id and w.user_id = auth.uid()
      ),
      '{}'::jsonb
    ),
    'checked_in_count', (
      select count(*) from public.event_check_ins ci
      where ci.circle_event_id = event_row.id
    ),
    'my_checked_in', exists (
      select 1 from public.event_check_ins ci
      where ci.circle_event_id = event_row.id and ci.user_id = auth.uid()
    ),
    'photo_count', (
      select count(*) from public.event_photos ph
      where ph.circle_event_id = event_row.id
    )
  )
  from (select 1) as single_row
  left join public.circle_channels channel on channel.id = event_row.channel_id;
$$;

drop function if exists public.create_circle_event(
  uuid, text, text, text, uuid, text, timestamptz, timestamptz
);
drop function if exists public.update_circle_event(
  uuid, text, text, text, uuid, text, timestamptz, timestamptz
);
drop function if exists public.cancel_circle_event(uuid);

create or replace function public.create_circle_event(
  target_circle_id uuid,
  event_title text,
  event_description text,
  event_location_type text,
  event_channel_id uuid,
  event_location_text text,
  event_starts_at timestamptz,
  event_ends_at timestamptz default null,
  event_options jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  normalized public.circle_events%rowtype;
  created public.circle_events%rowtype;
  options jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.is_current_user_circle_member(target_circle_id)
    or not public.current_user_has_circle_permission(
      target_circle_id,
      'manage_events'
    )
  then
    raise exception 'Circle not found or caller cannot manage events'
      using errcode = '42501';
  end if;
  perform public.events2_assert_circle_open(target_circle_id, true);

  normalized := public.normalize_circle_event(
    target_circle_id,
    event_title,
    event_description,
    event_location_type,
    event_channel_id,
    event_location_text,
    event_starts_at,
    event_ends_at
  );
  options := public.events2_merge_options(
    target_circle_id, event_options, null, null, null, '[]'::jsonb, null
  );

  insert into public.circle_events (
    circle_id,
    title,
    description,
    location_type,
    channel_id,
    location_text,
    starts_at,
    ends_at,
    created_by,
    recurrence,
    recurrence_tz,
    recurrence_anchor,
    series_id,
    cover_path,
    questions,
    capacity
  )
  values (
    target_circle_id,
    normalized.title,
    normalized.description,
    normalized.location_type,
    normalized.channel_id,
    normalized.location_text,
    normalized.starts_at,
    normalized.ends_at,
    current_user_id,
    options ->> 'recurrence',
    options ->> 'recurrence_tz',
    case when options ->> 'recurrence' is not null then normalized.starts_at end,
    case when options ->> 'recurrence' is not null then gen_random_uuid() end,
    options ->> 'cover_path',
    options -> 'questions',
    (options ->> 'capacity')::integer
  )
  returning * into created;

  perform public.write_circle_audit(
    target_circle_id,
    'event_create',
    'event',
    created.id,
    created.title,
    jsonb_strip_nulls(jsonb_build_object(
      'starts_at', created.starts_at,
      'ends_at', created.ends_at,
      'location', public.circle_event_location_label(created),
      'recurrence', created.recurrence,
      'capacity', created.capacity
    ))
  );

  return public.circle_event_payload(created);
end;
$$;

create or replace function public.update_circle_event(
  target_event_id uuid,
  event_title text,
  event_description text,
  event_location_type text,
  event_channel_id uuid,
  event_location_text text,
  event_starts_at timestamptz,
  event_ends_at timestamptz default null,
  event_options jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  existing public.circle_events%rowtype;
  normalized public.circle_events%rowtype;
  updated public.circle_events%rowtype;
  options jsonb;
  changes jsonb := '{}'::jsonb;
  old_location text;
  new_location text;
begin
  existing := public.circle_event_for_management(target_event_id);
  perform public.events2_assert_circle_open(existing.circle_id, true);

  if existing.cancelled_at is not null then
    raise exception 'Cancelled events cannot be changed'
      using errcode = '22023';
  end if;

  normalized := public.normalize_circle_event(
    existing.circle_id,
    event_title,
    event_description,
    event_location_type,
    event_channel_id,
    event_location_text,
    event_starts_at,
    event_ends_at
  );
  options := public.events2_merge_options(
    existing.circle_id,
    event_options,
    existing.recurrence,
    existing.recurrence_tz,
    existing.cover_path,
    existing.questions,
    existing.capacity
  );

  if normalized.title is not distinct from existing.title
    and normalized.description is not distinct from existing.description
    and normalized.location_type is not distinct from existing.location_type
    and normalized.channel_id is not distinct from existing.channel_id
    and normalized.location_text is not distinct from existing.location_text
    and normalized.starts_at is not distinct from existing.starts_at
    and normalized.ends_at is not distinct from existing.ends_at
    and options ->> 'recurrence' is not distinct from existing.recurrence
    and options ->> 'recurrence_tz' is not distinct from existing.recurrence_tz
    and options ->> 'cover_path' is not distinct from existing.cover_path
    and options -> 'questions' is not distinct from existing.questions
    and (options ->> 'capacity')::integer is not distinct from existing.capacity
  then
    return public.circle_event_payload(existing);
  end if;

  update public.circle_events e
  set
    title = normalized.title,
    description = normalized.description,
    location_type = normalized.location_type,
    channel_id = normalized.channel_id,
    location_text = normalized.location_text,
    starts_at = normalized.starts_at,
    ends_at = normalized.ends_at,
    recurrence = options ->> 'recurrence',
    recurrence_tz = options ->> 'recurrence_tz',
    recurrence_anchor = case
      when options ->> 'recurrence' is null then null
      when existing.recurrence_anchor is null
        or normalized.starts_at is distinct from existing.starts_at
        or options ->> 'recurrence' is distinct from existing.recurrence
        or options ->> 'recurrence_tz' is distinct from existing.recurrence_tz
      then normalized.starts_at
      else existing.recurrence_anchor
    end,
    series_id = case
      when options ->> 'recurrence' is null then existing.series_id
      else coalesce(existing.series_id, gen_random_uuid())
    end,
    cover_path = options ->> 'cover_path',
    questions = options -> 'questions',
    capacity = (options ->> 'capacity')::integer,
    updated_at = now()
  where e.id = existing.id
  returning * into updated;

  if updated.title is distinct from existing.title then
    changes := changes || jsonb_build_object(
      'title', jsonb_build_object('old', existing.title, 'new', updated.title)
    );
  end if;
  if updated.description is distinct from existing.description then
    changes := changes || jsonb_build_object(
      'description', jsonb_build_object(
        'old', existing.description,
        'new', updated.description
      )
    );
  end if;
  if updated.starts_at is distinct from existing.starts_at then
    changes := changes || jsonb_build_object(
      'starts_at', jsonb_build_object(
        'old', existing.starts_at,
        'new', updated.starts_at
      )
    );
  end if;
  if updated.ends_at is distinct from existing.ends_at then
    changes := changes || jsonb_build_object(
      'ends_at', jsonb_build_object('old', existing.ends_at, 'new', updated.ends_at)
    );
  end if;
  old_location := public.circle_event_location_label(existing);
  new_location := public.circle_event_location_label(updated);
  if old_location is distinct from new_location then
    changes := changes || jsonb_build_object(
      'location', jsonb_build_object('old', old_location, 'new', new_location)
    );
  end if;
  if updated.recurrence is distinct from existing.recurrence then
    changes := changes || jsonb_build_object(
      'recurrence', jsonb_build_object('old', existing.recurrence, 'new', updated.recurrence)
    );
  end if;
  if updated.capacity is distinct from existing.capacity then
    changes := changes || jsonb_build_object(
      'capacity', jsonb_build_object('old', existing.capacity, 'new', updated.capacity)
    );
  end if;
  if updated.questions is distinct from existing.questions then
    changes := changes || jsonb_build_object(
      'questions', jsonb_build_object(
        'old', jsonb_array_length(existing.questions),
        'new', jsonb_array_length(updated.questions)
      )
    );
  end if;

  perform public.write_circle_audit(
    updated.circle_id,
    'event_update',
    'event',
    updated.id,
    updated.title,
    changes
  );

  -- More seats let people off the waiting list.
  if updated.capacity is distinct from existing.capacity then
    perform public.events2_promote('circle', updated.id);
  end if;

  return public.circle_event_payload(updated);
end;
$$;

-- Cancels this event. With [cancel_series] the whole series ends: later
-- occurrences already made are cancelled too and no more are made.
create or replace function public.cancel_circle_event(
  target_event_id uuid,
  cancel_series boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  existing public.circle_events%rowtype;
  cancelled public.circle_events%rowtype;
begin
  existing := public.circle_event_for_management(target_event_id);
  perform public.events2_assert_circle_open(existing.circle_id, true);

  if existing.cancelled_at is not null and not (
    coalesce(cancel_series, false) and existing.recurrence is not null
  ) then
    return public.circle_event_payload(existing);
  end if;

  update public.circle_events e
  set cancelled_at = coalesce(e.cancelled_at, now()), updated_at = now()
  where e.id = existing.id
  returning * into cancelled;

  if coalesce(cancel_series, false) and cancelled.series_id is not null then
    update public.circle_events
    set recurrence = null
    where series_id = cancelled.series_id and recurrence is not null;

    update public.circle_events
    set cancelled_at = now(), updated_at = now()
    where series_id = cancelled.series_id
      and starts_at > now()
      and cancelled_at is null;

    select e.* into cancelled from public.circle_events e where e.id = cancelled.id;
  end if;

  perform public.write_circle_audit(
    cancelled.circle_id,
    'event_cancel',
    'event',
    cancelled.id,
    cancelled.title,
    jsonb_strip_nulls(jsonb_build_object(
      'starts_at', cancelled.starts_at,
      'series', case when coalesce(cancel_series, false) then true end
    ))
  );

  return public.circle_event_payload(cancelled);
end;
$$;

-- Signs the caller up, with answers to the event's questions; the interest
-- of before, plus answers. With the event full the caller joins the waiting
-- list. Signing up again changes the answers.
create or replace function public.register_circle_event(
  target_event_id uuid,
  event_answers jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  event_row public.circle_events%rowtype;
  existing_answers jsonb;
  clean_answers jsonb;
  has_seat boolean;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select e.* into event_row
  from public.circle_events e
  where e.id = target_event_id
  for update;

  if not coalesce(public.current_user_can_see_circle_event(event_row), false) then
    raise exception 'Event not found' using errcode = '42501';
  end if;
  perform public.events2_assert_circle_open(event_row.circle_id, false);

  if event_row.cancelled_at is not null
    or public.circle_event_ends_at(event_row.starts_at, event_row.ends_at) <= now()
  then
    raise exception 'Event is cancelled or over' using errcode = '22023';
  end if;

  select r.answers into existing_answers
  from public.circle_event_rsvps r
  where r.event_id = event_row.id and r.user_id = current_user_id;
  has_seat := found;

  clean_answers := public.events2_clean_answers(
    event_row.questions,
    coalesce(event_answers, existing_answers, (
      select w.answers from public.event_waitlist w
      where w.circle_event_id = event_row.id and w.user_id = current_user_id
    )),
    true
  );

  if has_seat then
    update public.circle_event_rsvps r
    set answers = clean_answers
    where r.event_id = event_row.id and r.user_id = current_user_id;
  elsif event_row.capacity is null
    or public.events2_seats_taken('circle', event_row.id) < event_row.capacity
  then
    insert into public.circle_event_rsvps (event_id, circle_id, user_id, answers)
    values (event_row.id, event_row.circle_id, current_user_id, clean_answers)
    on conflict (event_id, user_id) do update set answers = excluded.answers;
    delete from public.event_waitlist w
    where w.circle_event_id = event_row.id and w.user_id = current_user_id;
  else
    insert into public.event_waitlist (circle_event_id, circle_id, user_id, answers)
    values (event_row.id, event_row.circle_id, current_user_id, clean_answers)
    on conflict (circle_event_id, user_id) where circle_event_id is not null
    do update set answers = excluded.answers;
  end if;

  return public.circle_event_payload(event_row);
end;
$$;

-- Takes the caller off the event (or its waiting list). The next in line
-- moves up. Allowed whatever the state of the circle.
create or replace function public.unregister_circle_event(target_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  event_row public.circle_events%rowtype;
  had_seat boolean;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select e.* into event_row
  from public.circle_events e
  where e.id = target_event_id
  for update;

  if not coalesce(public.current_user_can_see_circle_event(event_row), false) then
    raise exception 'Event not found' using errcode = '42501';
  end if;

  delete from public.circle_event_rsvps r
  where r.event_id = event_row.id and r.user_id = current_user_id;
  had_seat := found;
  delete from public.event_waitlist w
  where w.circle_event_id = event_row.id and w.user_id = current_user_id;

  if had_seat then
    perform public.events2_promote('circle', event_row.id);
  end if;

  return public.circle_event_payload(event_row);
end;
$$;

-- Marks the caller interested in an event, or not any more. Returns the new
-- state (on the waiting list counts as signed up). Cancelled or finished
-- events take no new interest.
create or replace function public.toggle_event_interest(target_event_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  event_row public.circle_events%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select e.* into event_row
  from public.circle_events e
  where e.id = target_event_id;

  if not coalesce(public.current_user_can_see_circle_event(event_row), false) then
    raise exception 'Event not found' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.circle_event_rsvps r
    where r.event_id = event_row.id and r.user_id = current_user_id
  ) or exists (
    select 1 from public.event_waitlist w
    where w.circle_event_id = event_row.id and w.user_id = current_user_id
  ) then
    perform public.unregister_circle_event(event_row.id);
    return false;
  end if;

  perform public.register_circle_event(event_row.id, null);
  return true;
end;
$$;

revoke execute on function public.circle_event_payload(public.circle_events)
  from public, anon, authenticated;
revoke execute on function public.create_circle_event(
  uuid, text, text, text, uuid, text, timestamptz, timestamptz, jsonb
) from public, anon;
revoke execute on function public.update_circle_event(
  uuid, text, text, text, uuid, text, timestamptz, timestamptz, jsonb
) from public, anon;
revoke execute on function public.cancel_circle_event(uuid, boolean) from public, anon;
revoke execute on function public.register_circle_event(uuid, jsonb) from public, anon;
revoke execute on function public.unregister_circle_event(uuid) from public, anon;
revoke execute on function public.toggle_event_interest(uuid) from public, anon;

grant execute on function public.create_circle_event(
  uuid, text, text, text, uuid, text, timestamptz, timestamptz, jsonb
) to authenticated;
grant execute on function public.update_circle_event(
  uuid, text, text, text, uuid, text, timestamptz, timestamptz, jsonb
) to authenticated;
grant execute on function public.cancel_circle_event(uuid, boolean) to authenticated;
grant execute on function public.register_circle_event(uuid, jsonb) to authenticated;
grant execute on function public.unregister_circle_event(uuid) to authenticated;
grant execute on function public.toggle_event_interest(uuid) to authenticated;
