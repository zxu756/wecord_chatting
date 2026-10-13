-- Circle events, like Discord's scheduled events: a title, an optional
-- description, a place (a voice or text channel of the circle, or an
-- external place as text), a start and an optional end. Members mark
-- themselves interested and get a reminder shortly before the start.
--
-- * circle_events: visible to every circle member, except events in a
--   channel the member cannot see (view_channel, overwrites included).
--   Deleting the channel keeps the event without a channel. Whether an
--   event is upcoming, ongoing or over is computed on read: it is over
--   at ends_at, or circle_event_default_duration after starts_at when it
--   has no end. Nothing is posted when an event starts.
-- * circle_event_rsvps: who is interested. circle_id is kept on the row so
--   leaving or being kicked from the circle drops it, and so realtime can
--   filter by circle.
-- * create_circle_event (manage_events), update_circle_event and
--   cancel_circle_event (manage_events or the event's creator), audited as
--   event_create, event_update and event_cancel. Events cannot be created
--   or moved into the past (their end must be in the future).
-- * toggle_event_interest(event_id) returns the caller's new state.
-- * list_circle_events(circle_id, include_past): upcoming and ongoing
--   events by start time (with include_past also ended and cancelled
--   ones), each with its channel, creator, interested count and whether
--   the caller is interested. list_event_interested(event_id) lists the
--   interested members.
-- * list_my_upcoming_event_reminders(): the caller's interested, visible,
--   not cancelled events starting within 24 hours, with the circle's name
--   and the caller's notification settings for it, for local reminders.
-- Clients only read the tables; the RPCs write them.

create table if not exists public.circle_events (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  title text not null,
  description text,
  location_type text not null,
  channel_id uuid,
  location_text text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  cancelled_at timestamptz,
  constraint circle_events_title_length check (
    title = btrim(title) and char_length(title) between 1 and 100
  ),
  constraint circle_events_description_length check (
    description is null or char_length(description) between 1 and 2000
  ),
  constraint circle_events_location_type_check check (
    location_type in ('voice', 'text', 'external')
  ),
  constraint circle_events_location_text_length check (
    location_text is null
    or (
      location_text = btrim(location_text)
      and char_length(location_text) between 1 and 200
    )
  ),
  -- Channel events name their channel (until it is deleted); external
  -- events name their place instead.
  constraint circle_events_location_check check (
    case location_type
      when 'external' then channel_id is null and location_text is not null
      else location_text is null
    end
  ),
  constraint circle_events_ends_after_start check (
    ends_at is null or ends_at > starts_at
  ),
  constraint circle_events_channel_fkey
    foreign key (channel_id, circle_id)
    references public.circle_channels(id, circle_id)
    on delete set null (channel_id),
  constraint circle_events_id_circle_unique unique (id, circle_id)
);

create index if not exists circle_events_circle_starts_idx
  on public.circle_events (circle_id, starts_at);

create index if not exists circle_events_channel_idx
  on public.circle_events (channel_id)
  where channel_id is not null;

create table if not exists public.circle_event_rsvps (
  event_id uuid not null,
  circle_id uuid not null,
  user_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (event_id, user_id),
  constraint circle_event_rsvps_event_fkey
    foreign key (event_id, circle_id)
    references public.circle_events(id, circle_id)
    on delete cascade,
  constraint circle_event_rsvps_member_fkey
    foreign key (circle_id, user_id)
    references public.circle_members(circle_id, user_id)
    on delete cascade
);

create index if not exists circle_event_rsvps_user_idx
  on public.circle_event_rsvps (user_id, event_id);

create index if not exists circle_event_rsvps_member_idx
  on public.circle_event_rsvps (circle_id, user_id);

-- Realtime matches DELETE events against the old row, so keep the circle
-- in it.
alter table public.circle_events replica identity full;
alter table public.circle_event_rsvps replica identity full;

alter table public.circle_events enable row level security;
alter table public.circle_event_rsvps enable row level security;

revoke insert, update, delete, truncate on public.circle_events from anon;
revoke insert, update, delete, truncate on public.circle_events from authenticated;
revoke insert, update, delete, truncate on public.circle_event_rsvps from anon;
revoke insert, update, delete, truncate on public.circle_event_rsvps from authenticated;

drop policy if exists circle_events_select_viewer on public.circle_events;
create policy circle_events_select_viewer
  on public.circle_events for select
  to authenticated
  using (
    public.is_current_user_circle_member(circle_id)
    and (
      channel_id is null
      or public.current_user_has_channel_permission(channel_id, 'view_channel')
    )
  );

drop policy if exists circle_event_rsvps_select_viewer on public.circle_event_rsvps;
create policy circle_event_rsvps_select_viewer
  on public.circle_event_rsvps for select
  to authenticated
  using (
    public.is_current_user_circle_member(circle_id)
    and exists (
      select 1
      from public.circle_events e
      where e.id = event_id
        and (
          e.channel_id is null
          or public.current_user_has_channel_permission(
            e.channel_id,
            'view_channel'
          )
        )
    )
  );

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'circle_events'
  ) then
    alter publication supabase_realtime add table public.circle_events;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'circle_event_rsvps'
  ) then
    alter publication supabase_realtime add table public.circle_event_rsvps;
  end if;
end $$;

-- How long an event without an end time lasts.
create or replace function public.circle_event_default_duration()
returns interval
language sql
immutable
set search_path = public
as $$
  select interval '2 hours';
$$;

-- When an event is over.
create or replace function public.circle_event_ends_at(
  event_starts_at timestamptz,
  event_ends_at timestamptz
)
returns timestamptz
language sql
immutable
set search_path = public
as $$
  select coalesce(
    event_ends_at,
    event_starts_at + public.circle_event_default_duration()
  );
$$;

-- Whether the caller can see an event: a member of its circle who can see
-- its channel, if it has one.
create or replace function public.current_user_can_see_circle_event(
  event_row public.circle_events
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select event_row.id is not null
    and public.is_current_user_circle_member(event_row.circle_id)
    and (
      event_row.channel_id is null
      or public.current_user_has_channel_permission(
        event_row.channel_id,
        'view_channel'
      )
    );
$$;

-- A profile as the client reads it, with the member's circle nickname.
create or replace function public.circle_event_profile(
  target_circle_id uuid,
  target_user_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', p.id,
    'username', p.username,
    'display_name', p.display_name,
    'avatar_url', p.avatar_url,
    'bio', p.bio,
    'created_at', p.created_at,
    'updated_at', p.updated_at,
    'nickname', cm.nickname
  )
  from public.profiles p
  left join public.circle_members cm
    on cm.circle_id = target_circle_id
    and cm.user_id = p.id
  where p.id = target_user_id;
$$;

-- An event as the client reads it.
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
      )
  )
  from (select 1) as single_row
  left join public.circle_channels channel on channel.id = event_row.channel_id;
$$;

-- Normalizes and checks an event's fields for create_circle_event and
-- update_circle_event; returns them as a circle_events row (id, creator
-- and timestamps unset).
create or replace function public.normalize_circle_event(
  target_circle_id uuid,
  event_title text,
  event_description text,
  event_location_type text,
  event_channel_id uuid,
  event_location_text text,
  event_starts_at timestamptz,
  event_ends_at timestamptz
)
returns public.circle_events
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  normalized public.circle_events%rowtype;
  channel public.circle_channels%rowtype;
begin
  normalized.circle_id := target_circle_id;
  normalized.title := nullif(
    regexp_replace(btrim(coalesce(event_title, '')), '\s+', ' ', 'g'),
    ''
  );
  normalized.description := nullif(btrim(coalesce(event_description, '')), '');
  normalized.location_type := event_location_type;
  normalized.starts_at := event_starts_at;
  normalized.ends_at := event_ends_at;

  if normalized.title is null or char_length(normalized.title) > 100 then
    raise exception 'Event title must be between 1 and 100 characters'
      using errcode = '22023';
  end if;

  if char_length(normalized.description) > 2000 then
    raise exception 'Event description must be at most 2000 characters'
      using errcode = '22023';
  end if;

  if event_starts_at is null then
    raise exception 'Event start is required' using errcode = '22023';
  end if;

  if event_ends_at is not null and event_ends_at <= event_starts_at then
    raise exception 'Event must end after it starts' using errcode = '22023';
  end if;

  if public.circle_event_ends_at(event_starts_at, event_ends_at) <= now() then
    raise exception 'Event must not be over already' using errcode = '22023';
  end if;

  if event_location_type is null
    or event_location_type not in ('voice', 'text', 'external')
  then
    raise exception 'Event location must be voice, text or external'
      using errcode = '22023';
  end if;

  if event_location_type = 'external' then
    normalized.channel_id := null;
    normalized.location_text := nullif(btrim(coalesce(event_location_text, '')), '');
    if normalized.location_text is null
      or char_length(normalized.location_text) > 200
    then
      raise exception 'Event location must be between 1 and 200 characters'
        using errcode = '22023';
    end if;
  else
    normalized.location_text := null;
    if event_channel_id is not null then
      select cc.* into channel
      from public.circle_channels cc
      where cc.id = event_channel_id
        and cc.circle_id = target_circle_id;
    end if;

    if channel.id is null
      or not public.current_user_has_channel_permission(channel.id, 'view_channel')
    then
      raise exception 'Event channel not found or caller cannot see it'
        using errcode = '22023';
    end if;

    if channel.kind is distinct from event_location_type then
      raise exception 'Event channel must be a % channel', event_location_type
        using errcode = '22023';
    end if;

    normalized.channel_id := channel.id;
  end if;

  return normalized;
end;
$$;

-- The event the caller may change: they see it and either created it or
-- have manage_events. Only for the RPCs below.
create or replace function public.circle_event_for_management(
  target_event_id uuid
)
returns public.circle_events
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  event_row public.circle_events%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select e.* into event_row
  from public.circle_events e
  where e.id = target_event_id;

  if not coalesce(public.current_user_can_see_circle_event(event_row), false)
    or not (
      event_row.created_by is not distinct from auth.uid()
      or public.current_user_has_circle_permission(
        event_row.circle_id,
        'manage_events'
      )
    )
  then
    raise exception 'Event not found or caller cannot manage it'
      using errcode = '42501';
  end if;

  return event_row;
end;
$$;

-- What an audit entry says about an event's place.
create or replace function public.circle_event_location_label(
  event_row public.circle_events
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when event_row.location_type = 'external' then event_row.location_text
    else coalesce(
      '#' || (
        select cc.name
        from public.circle_channels cc
        where cc.id = event_row.channel_id
      ),
      'deleted channel'
    )
  end;
$$;

revoke execute on function public.current_user_can_see_circle_event(public.circle_events) from public;
revoke execute on function public.current_user_can_see_circle_event(public.circle_events) from anon;
revoke execute on function public.current_user_can_see_circle_event(public.circle_events) from authenticated;
revoke execute on function public.circle_event_profile(uuid, uuid) from public;
revoke execute on function public.circle_event_profile(uuid, uuid) from anon;
revoke execute on function public.circle_event_profile(uuid, uuid) from authenticated;
revoke execute on function public.circle_event_payload(public.circle_events) from public;
revoke execute on function public.circle_event_payload(public.circle_events) from anon;
revoke execute on function public.circle_event_payload(public.circle_events) from authenticated;
revoke execute on function public.normalize_circle_event(uuid, text, text, text, uuid, text, timestamptz, timestamptz) from public;
revoke execute on function public.normalize_circle_event(uuid, text, text, text, uuid, text, timestamptz, timestamptz) from anon;
revoke execute on function public.normalize_circle_event(uuid, text, text, text, uuid, text, timestamptz, timestamptz) from authenticated;
revoke execute on function public.circle_event_for_management(uuid) from public;
revoke execute on function public.circle_event_for_management(uuid) from anon;
revoke execute on function public.circle_event_for_management(uuid) from authenticated;
revoke execute on function public.circle_event_location_label(public.circle_events) from public;
revoke execute on function public.circle_event_location_label(public.circle_events) from anon;
revoke execute on function public.circle_event_location_label(public.circle_events) from authenticated;

create or replace function public.create_circle_event(
  target_circle_id uuid,
  event_title text,
  event_description text,
  event_location_type text,
  event_channel_id uuid,
  event_location_text text,
  event_starts_at timestamptz,
  event_ends_at timestamptz default null
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

  insert into public.circle_events (
    circle_id,
    title,
    description,
    location_type,
    channel_id,
    location_text,
    starts_at,
    ends_at,
    created_by
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
    current_user_id
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
      'location', public.circle_event_location_label(created)
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
  event_ends_at timestamptz default null
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
  changes jsonb := '{}'::jsonb;
  old_location text;
  new_location text;
begin
  existing := public.circle_event_for_management(target_event_id);

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

  if normalized.title is not distinct from existing.title
    and normalized.description is not distinct from existing.description
    and normalized.location_type is not distinct from existing.location_type
    and normalized.channel_id is not distinct from existing.channel_id
    and normalized.location_text is not distinct from existing.location_text
    and normalized.starts_at is not distinct from existing.starts_at
    and normalized.ends_at is not distinct from existing.ends_at
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

  perform public.write_circle_audit(
    updated.circle_id,
    'event_update',
    'event',
    updated.id,
    updated.title,
    changes
  );

  return public.circle_event_payload(updated);
end;
$$;

create or replace function public.cancel_circle_event(target_event_id uuid)
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

  if existing.cancelled_at is not null then
    return public.circle_event_payload(existing);
  end if;

  update public.circle_events e
  set cancelled_at = now(), updated_at = now()
  where e.id = existing.id
  returning * into cancelled;

  perform public.write_circle_audit(
    cancelled.circle_id,
    'event_cancel',
    'event',
    cancelled.id,
    cancelled.title,
    jsonb_build_object('starts_at', cancelled.starts_at)
  );

  return public.circle_event_payload(cancelled);
end;
$$;

-- Marks the caller interested in an event, or not any more. Returns the
-- new state. Cancelled or finished events take no new interest.
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

  delete from public.circle_event_rsvps r
  where r.event_id = event_row.id
    and r.user_id = current_user_id;
  if found then
    return false;
  end if;

  if event_row.cancelled_at is not null
    or public.circle_event_ends_at(event_row.starts_at, event_row.ends_at) <= now()
  then
    raise exception 'Event is cancelled or over' using errcode = '22023';
  end if;

  insert into public.circle_event_rsvps (event_id, circle_id, user_id)
  values (event_row.id, event_row.circle_id, current_user_id)
  on conflict do nothing;
  return true;
end;
$$;

create or replace function public.list_circle_events(
  target_circle_id uuid,
  include_past boolean default false
)
returns setof jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.is_current_user_circle_member(target_circle_id) then
    raise exception 'Circle not found or caller is not a member'
      using errcode = '42501';
  end if;

  return query
  select public.circle_event_payload(e)
  from public.circle_events e
  where e.circle_id = target_circle_id
    and public.current_user_can_see_circle_event(e)
    and (
      coalesce(include_past, false)
      or (
        e.cancelled_at is null
        and public.circle_event_ends_at(e.starts_at, e.ends_at) > now()
      )
    )
  order by e.starts_at, e.id;
end;
$$;

create or replace function public.list_event_interested(target_event_id uuid)
returns setof jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  event_row public.circle_events%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select e.* into event_row
  from public.circle_events e
  where e.id = target_event_id;

  if not coalesce(public.current_user_can_see_circle_event(event_row), false) then
    raise exception 'Event not found' using errcode = '42501';
  end if;

  return query
  select public.circle_event_profile(event_row.circle_id, r.user_id)
  from public.circle_event_rsvps r
  where r.event_id = event_row.id
  order by r.created_at, r.user_id;
end;
$$;

create or replace function public.list_my_upcoming_event_reminders()
returns setof jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  return query
  select jsonb_build_object(
    'event_id', e.id,
    'circle_id', e.circle_id,
    'circle_name', c.name,
    'title', e.title,
    'starts_at', e.starts_at,
    'location_type', e.location_type,
    'location', public.circle_event_location_label(e),
    'notification_level', coalesce(ns.level, 'all'),
    'muted_until', ns.muted_until
  )
  from public.circle_event_rsvps r
  join public.circle_events e on e.id = r.event_id
  join public.circles c on c.id = e.circle_id
  left join public.circle_notification_settings ns
    on ns.circle_id = e.circle_id
    and ns.user_id = current_user_id
  where r.user_id = current_user_id
    and e.cancelled_at is null
    and e.starts_at > now()
    and e.starts_at <= now() + interval '24 hours'
    and public.current_user_can_see_circle_event(e)
  order by e.starts_at, e.id;
end;
$$;

revoke execute on function public.create_circle_event(uuid, text, text, text, uuid, text, timestamptz, timestamptz) from public;
revoke execute on function public.create_circle_event(uuid, text, text, text, uuid, text, timestamptz, timestamptz) from anon;
revoke execute on function public.update_circle_event(uuid, text, text, text, uuid, text, timestamptz, timestamptz) from public;
revoke execute on function public.update_circle_event(uuid, text, text, text, uuid, text, timestamptz, timestamptz) from anon;
revoke execute on function public.cancel_circle_event(uuid) from public;
revoke execute on function public.cancel_circle_event(uuid) from anon;
revoke execute on function public.toggle_event_interest(uuid) from public;
revoke execute on function public.toggle_event_interest(uuid) from anon;
revoke execute on function public.list_circle_events(uuid, boolean) from public;
revoke execute on function public.list_circle_events(uuid, boolean) from anon;
revoke execute on function public.list_event_interested(uuid) from public;
revoke execute on function public.list_event_interested(uuid) from anon;
revoke execute on function public.list_my_upcoming_event_reminders() from public;
revoke execute on function public.list_my_upcoming_event_reminders() from anon;

grant select on public.circle_events to authenticated;
grant select on public.circle_event_rsvps to authenticated;
grant execute on function public.create_circle_event(uuid, text, text, text, uuid, text, timestamptz, timestamptz) to authenticated;
grant execute on function public.update_circle_event(uuid, text, text, text, uuid, text, timestamptz, timestamptz) to authenticated;
grant execute on function public.cancel_circle_event(uuid) to authenticated;
grant execute on function public.toggle_event_interest(uuid) to authenticated;
grant execute on function public.list_circle_events(uuid, boolean) to authenticated;
grant execute on function public.list_event_interested(uuid) to authenticated;
grant execute on function public.list_my_upcoming_event_reminders() to authenticated;
