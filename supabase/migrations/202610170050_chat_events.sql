-- Events in group chats and direct messages (circles have their own, see
-- 202610130022_circle_events).
--
-- * chat_events: one row per event of a conversation (title, description,
--   place or link, start and optional end, which reminders to send, whether
--   it is pinned to the chat header, when it was cancelled). An event is
--   announced by a system message whose attachment is
--   {kind: 'event', event_id}; clients draw it as a card.
-- * chat_event_rsvps: Going / Maybe / Can't (declined), one per member.
-- * chat_event_reminders: one row per person per due reminder; this is the
--   inbox entry and what push is claimed from.
-- * Everything is written by the RPCs below (create/update/cancel_chat_event,
--   rsvp_chat_event, pin_chat_event); members read through RLS or
--   list/get_chat_event(s). Only group and direct conversations take events.
--
-- Reminders (15 minutes and/or 1 hour before, chosen when the event is made)
-- go to everyone who said Going or Maybe:
--
--   select public.chat_event_due_reminders();           -- inbox rows, idempotent
--   select * from public.claim_chat_event_reminder_pushes();  -- web push work
--
-- Both are meant for a scheduler (service role / postgres only). The first
-- is scheduled below when pg_cron is installed; the chat-event-reminders
-- Edge Function calls both and sends the pushes. docs/chat-events.md says
-- how to run them from the shared dispatcher.

create table if not exists public.chat_events (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null
    references public.conversations(id) on delete cascade,
  created_by uuid references public.profiles(id) on delete set null,
  title text not null,
  description text,
  location_text text,
  link_url text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  -- Minutes before the start to remind Going / Maybe members: 15 and/or 60.
  reminder_leads integer[] not null default array[15],
  message_id uuid references public.messages(id) on delete set null,
  pinned_at timestamptz,
  pinned_by uuid references public.profiles(id) on delete set null,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chat_events_title_length
    check (char_length(btrim(title)) between 1 and 100),
  constraint chat_events_description_length
    check (description is null or char_length(description) <= 2000),
  constraint chat_events_location_length
    check (location_text is null or char_length(location_text) <= 200),
  constraint chat_events_link_url
    check (
      link_url is null
      or (char_length(link_url) <= 500 and link_url ~* '^https?://[^\s]+$')
    ),
  constraint chat_events_ends_after_start
    check (ends_at is null or ends_at > starts_at),
  constraint chat_events_reminder_leads
    check (reminder_leads <@ array[15, 60])
);

create index if not exists chat_events_conversation_idx
  on public.chat_events (conversation_id, starts_at);

create index if not exists chat_events_upcoming_idx
  on public.chat_events (starts_at)
  where cancelled_at is null;

create table if not exists public.chat_event_rsvps (
  event_id uuid not null references public.chat_events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null check (status in ('going', 'maybe', 'declined')),
  -- Kept in the row so realtime can filter by conversation, also on delete.
  conversation_id uuid not null
    references public.conversations(id) on delete cascade,
  updated_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create index if not exists chat_event_rsvps_conversation_idx
  on public.chat_event_rsvps (conversation_id);

alter table public.chat_event_rsvps replica identity full;

create table if not exists public.chat_event_reminders (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.chat_events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  lead_minutes integer not null check (lead_minutes in (15, 60)),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  push_sent_at timestamptz,
  unique (event_id, user_id, lead_minutes)
);

create index if not exists chat_event_reminders_user_idx
  on public.chat_event_reminders (user_id, created_at desc);

create index if not exists chat_event_reminders_push_idx
  on public.chat_event_reminders (created_at)
  where push_sent_at is null;

alter table public.chat_events enable row level security;
alter table public.chat_event_rsvps enable row level security;
alter table public.chat_event_reminders enable row level security;

revoke all on public.chat_events from anon, authenticated;
revoke all on public.chat_event_rsvps from anon, authenticated;
revoke all on public.chat_event_reminders from anon, authenticated;
grant select on public.chat_events to authenticated;
grant select on public.chat_event_rsvps to authenticated;
grant select on public.chat_event_reminders to authenticated;

drop policy if exists chat_events_select_member on public.chat_events;
create policy chat_events_select_member
  on public.chat_events for select
  to authenticated
  using (
    conversation_id in (select public.current_user_readable_conversation_ids())
  );

drop policy if exists chat_event_rsvps_select_member on public.chat_event_rsvps;
create policy chat_event_rsvps_select_member
  on public.chat_event_rsvps for select
  to authenticated
  using (
    conversation_id in (select public.current_user_readable_conversation_ids())
  );

drop policy if exists chat_event_reminders_select_own on public.chat_event_reminders;
create policy chat_event_reminders_select_own
  on public.chat_event_reminders for select
  to authenticated
  using (user_id = auth.uid());

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'chat_events'
    ) then
      alter publication supabase_realtime add table public.chat_events;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'chat_event_rsvps'
    ) then
      alter publication supabase_realtime add table public.chat_event_rsvps;
    end if;
  end if;
end $$;

-- Who may change, cancel or pin an event: its creator, the owner and admins
-- of a group, either person in a direct chat.
create or replace function public.can_manage_chat_event(
  event_row public.chat_events,
  user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select event_row.created_by is not distinct from user_id
    or exists (
      select 1
      from public.conversations c
      join public.conversation_members cm
        on cm.conversation_id = c.id and cm.user_id = can_manage_chat_event.user_id
      where c.id = event_row.conversation_id
        and (
          c.type = 'direct'
          or (c.type = 'group' and cm.role in ('owner', 'admin'))
        )
    );
$$;

-- An event as the client reads it, for the current user.
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
    'can_manage', public.can_manage_chat_event(event_row, auth.uid())
  );
$$;

-- Checks shared by the writers: the caller is signed in, belongs to the
-- conversation and it takes events.
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

-- Trims and validates event fields shared by create and update.
create or replace function public.normalize_chat_event_leads(leads integer[])
returns integer[]
language sql
immutable
set search_path = public
as $$
  select coalesce(
    (
      select array_agg(distinct lead order by lead)
      from unnest(coalesce(leads, array[15])) as lead
      where lead in (15, 60)
    ),
    array[]::integer[]
  );
$$;

create or replace function public.create_chat_event(
  target_conversation_id uuid,
  event_title text,
  event_starts_at timestamptz,
  event_ends_at timestamptz default null,
  event_description text default null,
  event_location text default null,
  event_link text default null,
  event_reminder_leads integer[] default array[15],
  pin_event boolean default false
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
    pinned_by
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
    case when coalesce(pin_event, false) then current_user_id end
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
  event_reminder_leads integer[] default array[15]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  trimmed_title text := btrim(coalesce(event_title, ''));
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

  update public.chat_events
  set
    title = trimmed_title,
    description = nullif(btrim(coalesce(event_description, '')), ''),
    location_text = nullif(btrim(coalesce(event_location, '')), ''),
    link_url = nullif(btrim(coalesce(event_link, '')), ''),
    starts_at = event_starts_at,
    ends_at = event_ends_at,
    reminder_leads = public.normalize_chat_event_leads(event_reminder_leads),
    updated_at = now()
  where id = current_event.id
  returning * into current_event;

  -- A moved event reminds again.
  delete from public.chat_event_reminders r
  where r.event_id = current_event.id;

  return public.chat_event_json(current_event);
end;
$$;

create or replace function public.cancel_chat_event(target_event_id uuid)
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

  return public.chat_event_json(current_event);
end;
$$;

-- Sets the caller's answer; null clears it.
create or replace function public.rsvp_chat_event(
  target_event_id uuid,
  rsvp_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  current_event public.chat_events%rowtype;
begin
  select e.* into current_event
  from public.chat_events e
  where e.id = target_event_id;

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

  if rsvp_status is null then
    delete from public.chat_event_rsvps r
    where r.event_id = current_event.id and r.user_id = current_user_id;
  else
    insert into public.chat_event_rsvps (
      event_id, user_id, status, conversation_id
    )
    values (
      current_event.id, current_user_id, rsvp_status, current_event.conversation_id
    )
    on conflict (event_id, user_id) do update
    set status = excluded.status, updated_at = now();
  end if;

  return public.chat_event_json(current_event);
end;
$$;

-- Pins an event to the chat header (one at a time per conversation).
create or replace function public.pin_chat_event(
  target_event_id uuid,
  pinned boolean
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
    raise exception 'Cannot pin this event' using errcode = '42501';
  end if;
  if coalesce(pinned, false) and current_event.cancelled_at is not null then
    raise exception 'This event was cancelled' using errcode = '22023';
  end if;

  if coalesce(pinned, false) then
    update public.chat_events
    set pinned_at = null, pinned_by = null
    where conversation_id = current_event.conversation_id
      and pinned_at is not null
      and id <> current_event.id;
  end if;

  update public.chat_events
  set
    pinned_at = case when coalesce(pinned, false) then now() end,
    pinned_by = case when coalesce(pinned, false) then auth.uid() end
  where id = current_event.id
  returning * into current_event;

  return public.chat_event_json(current_event);
end;
$$;

create or replace function public.get_chat_event(target_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_event public.chat_events%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select e.* into current_event
  from public.chat_events e
  where e.id = target_event_id;

  if current_event.id is null
    or not public.is_current_user_conversation_member(current_event.conversation_id)
  then
    return null;
  end if;

  return public.chat_event_json(current_event);
end;
$$;

-- A conversation's events, soonest first: upcoming and running ones, and on
-- request the past ones too (cancelled events only then).
create or replace function public.list_chat_events(
  target_conversation_id uuid,
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

  if not public.is_current_user_conversation_member(target_conversation_id) then
    return;
  end if;

  return query
  select public.chat_event_json(e)
  from public.chat_events e
  where e.conversation_id = target_conversation_id
    and (
      coalesce(include_past, false)
      or (
        e.cancelled_at is null
        and coalesce(e.ends_at, e.starts_at + interval '2 hours') > now()
      )
    )
  order by e.starts_at, e.created_at
  limit 100;
end;
$$;

-- Reminders ----------------------------------------------------------------

-- Writes the reminders that are due now: one per event and person who said
-- Going or Maybe and still belongs to the chat, for the most imminent
-- reminder whose time has come (someone answering 10 minutes before gets
-- the 15-minute one, not both). Safe to run as often as you like; returns
-- how many were new. Run it every minute from a scheduler.
create or replace function public.chat_event_due_reminders(
  as_of timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  created_count integer;
begin
  with due as (
    select
      e.id as event_id,
      r.user_id,
      min(leads.lead_minutes) as lead_minutes
    from public.chat_events e
    cross join lateral unnest(e.reminder_leads) as leads(lead_minutes)
    join public.chat_event_rsvps r
      on r.event_id = e.id and r.status in ('going', 'maybe')
    join public.conversation_members cm
      on cm.conversation_id = e.conversation_id and cm.user_id = r.user_id
    where e.cancelled_at is null
      and as_of < e.starts_at
      and as_of >= e.starts_at - make_interval(mins => leads.lead_minutes)
    group by e.id, r.user_id
  )
  insert into public.chat_event_reminders (event_id, user_id, lead_minutes)
  select due.event_id, due.user_id, due.lead_minutes
  from due
  on conflict (event_id, user_id, lead_minutes) do nothing;

  get diagnostics created_count = row_count;
  return created_count;
end;
$$;

-- Hands out the web pushes for reminders not pushed yet (and no older than
-- half an hour), once: each reminder is marked as it is returned. One row
-- per device; people muting the chat or without a subscription get none.
create or replace function public.claim_chat_event_reminder_pushes(
  max_reminders integer default 200
)
returns table (
  reminder_id uuid,
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth text,
  conversation_id uuid,
  event_id uuid,
  title text,
  body text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with claimed as (
    update public.chat_event_reminders r
    set push_sent_at = now()
    where r.id in (
      select p.id
      from public.chat_event_reminders p
      where p.push_sent_at is null
        and p.created_at > now() - interval '30 minutes'
      order by p.created_at
      limit greatest(1, least(coalesce(max_reminders, 200), 1000))
      for update skip locked
    )
    returning r.id, r.event_id, r.user_id, r.lead_minutes
  )
  select
    claimed.id,
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    e.conversation_id,
    e.id,
    e.title,
    case
      when e.starts_at <= now() then 'Starting now'
      when claimed.lead_minutes >= 60 then 'Starts in about 1 hour'
      else 'Starts in ' || greatest(1, ceil(extract(epoch from (e.starts_at - now())) / 60)::integer) || ' minutes'
    end
  from claimed
  join public.chat_events e on e.id = claimed.event_id
  join public.conversation_members cm
    on cm.conversation_id = e.conversation_id and cm.user_id = claimed.user_id
  join public.push_subscriptions s on s.user_id = claimed.user_id
  where e.cancelled_at is null
    and (cm.muted_until is null or cm.muted_until < now());
end;
$$;

-- The caller's reminders from the last two days for the inbox, newest first.
create or replace function public.list_chat_event_reminders(
  max_reminders integer default 20
)
returns table (
  reminder_id uuid,
  event_id uuid,
  conversation_id uuid,
  title text,
  starts_at timestamptz,
  lead_minutes integer,
  created_at timestamptz,
  is_unread boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id,
    e.id,
    e.conversation_id,
    e.title,
    e.starts_at,
    r.lead_minutes,
    r.created_at,
    r.read_at is null
  from public.chat_event_reminders r
  join public.chat_events e on e.id = r.event_id
  where r.user_id = auth.uid()
    and r.created_at > now() - interval '2 days'
    and e.cancelled_at is null
    and e.conversation_id in (select public.current_user_readable_conversation_ids())
  order by r.created_at desc
  limit greatest(1, least(coalesce(max_reminders, 20), 100));
$$;

create or replace function public.mark_chat_event_reminders_read(
  reminder_ids uuid[] default null
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.chat_event_reminders r
  set read_at = now()
  where r.user_id = auth.uid()
    and r.read_at is null
    and (reminder_ids is null or r.id = any(reminder_ids));
$$;

-- Old reminders are only history.
create or replace function public.purge_old_chat_event_reminders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  removed integer;
begin
  delete from public.chat_event_reminders r
  where r.created_at < now() - interval '14 days';
  get diagnostics removed = row_count;
  return removed;
end;
$$;

-- Grants: members call the RPCs; the scheduler functions are for the
-- service role and postgres only.
revoke execute on function public.can_manage_chat_event(public.chat_events, uuid) from public, anon, authenticated;
revoke execute on function public.chat_event_json(public.chat_events) from public, anon, authenticated;
revoke execute on function public.chat_event_check_conversation(uuid) from public, anon, authenticated;
revoke execute on function public.normalize_chat_event_leads(integer[]) from public, anon, authenticated;

revoke execute on function public.create_chat_event(uuid, text, timestamptz, timestamptz, text, text, text, integer[], boolean) from public, anon;
revoke execute on function public.update_chat_event(uuid, text, timestamptz, timestamptz, text, text, text, integer[]) from public, anon;
revoke execute on function public.cancel_chat_event(uuid) from public, anon;
revoke execute on function public.rsvp_chat_event(uuid, text) from public, anon;
revoke execute on function public.pin_chat_event(uuid, boolean) from public, anon;
revoke execute on function public.get_chat_event(uuid) from public, anon;
revoke execute on function public.list_chat_events(uuid, boolean) from public, anon;
revoke execute on function public.list_chat_event_reminders(integer) from public, anon;
revoke execute on function public.mark_chat_event_reminders_read(uuid[]) from public, anon;

grant execute on function public.create_chat_event(uuid, text, timestamptz, timestamptz, text, text, text, integer[], boolean) to authenticated;
grant execute on function public.update_chat_event(uuid, text, timestamptz, timestamptz, text, text, text, integer[]) to authenticated;
grant execute on function public.cancel_chat_event(uuid) to authenticated;
grant execute on function public.rsvp_chat_event(uuid, text) to authenticated;
grant execute on function public.pin_chat_event(uuid, boolean) to authenticated;
grant execute on function public.get_chat_event(uuid) to authenticated;
grant execute on function public.list_chat_events(uuid, boolean) to authenticated;
grant execute on function public.list_chat_event_reminders(integer) to authenticated;
grant execute on function public.mark_chat_event_reminders_read(uuid[]) to authenticated;

revoke execute on function public.chat_event_due_reminders(timestamptz) from public, anon, authenticated;
revoke execute on function public.claim_chat_event_reminder_pushes(integer) from public, anon, authenticated;
revoke execute on function public.purge_old_chat_event_reminders() from public, anon, authenticated;

-- With pg_cron installed (hosted Supabase), write due reminders every
-- minute and tidy up daily. Without it (local development) nothing is
-- scheduled and these stay plain functions.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'chat-event-due-reminders',
      '* * * * *',
      'select public.chat_event_due_reminders()'
    );
    perform cron.schedule(
      'chat-event-reminders-purge',
      '17 4 * * *',
      'select public.purge_old_chat_event_reminders()'
    );
  end if;
end $$;
