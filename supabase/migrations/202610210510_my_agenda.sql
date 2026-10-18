-- My agenda: everything with a time that concerns the caller, across chats.
--
-- get_my_agenda(p_from, p_to) merges five sources into one list, soonest
-- first (at most 500 rows):
--
--   kind               source                                   starts_at
--   chat_event         chat_event_rsvps going / maybe           event start
--   circle_event       circle_event_rsvps (interested)          event start
--   task               task_item_assignees, open, with a due    due date
--   reminder           my message_reminders, not dismissed      remind_at
--   scheduled_message  my pending scheduled_messages            send_at
--
-- Each row: kind, title, starts_at, ends_at, all_day, conversation_id,
-- circle_id, target_id (the event, task, reminder or scheduled message),
-- parent_id (a task's list), place_name (the conversation or circle it
-- belongs to), subtitle (an event's place) and meta (small extras: my RSVP,
-- a task's priority, a reminder's message and type).
--
-- Every row goes through the rules that already hide things, so leaving a
-- group, a chat or a circle makes its items disappear:
--
--   * The conversation must be one the caller can read
--     (current_user_readable_conversation_ids: still a member, and for a
--     circle channel still allowed to view it). A direct chat with someone the
--     caller blocked, or who blocked the caller, is left out.
--   * Circle events use current_user_can_see_circle_event (circle member, and
--     the event's channel visible); cancelled events are left out, as are
--     deleted tasks and lists, and done tasks.
--   * A reminder's title is the message text only while the reader may still
--     read it: not recalled, not expired (expires_at), not held for review
--     (message_visible_to_current_user). Otherwise the reminder stays, with
--     no title, and the app says "Message unavailable".
--
-- The work is done by agenda_items_core, which asks auth.uid() for the person
-- the way the other helpers do. get_my_agenda is the door for signed-in
-- people. agenda_items_for_user is the door for the calendar-feed Edge
-- Function (service role only): it names the person for the length of one
-- transaction, so the feed follows exactly the same rules as the app.

create or replace function public.agenda_place_name(
  p_conversation_id uuid,
  p_user_id uuid
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when cc.id is not null then ci.name || ' · #' || cc.name
    when c.type = 'direct' then (
      select coalesce(nullif(btrim(ca.alias), ''), nullif(btrim(p.display_name), ''), p.username)
      from public.conversation_members cm
      join public.profiles p on p.id = cm.user_id
      left join public.contact_aliases ca
        on ca.owner_id = p_user_id and ca.friend_id = p.id
      where cm.conversation_id = c.id
        and cm.user_id <> p_user_id
      limit 1
    )
    else nullif(btrim(c.title), '')
  end
  from public.conversations c
  left join public.circle_channels cc on cc.conversation_id = c.id
  left join public.circles ci on ci.id = cc.circle_id
  where c.id = p_conversation_id;
$$;

revoke execute on function public.agenda_place_name(uuid, uuid) from public, anon, authenticated;

create or replace function public.agenda_items_core(
  p_from timestamptz,
  p_to timestamptz,
  p_kinds text[] default null
)
returns table (
  kind text,
  title text,
  starts_at timestamptz,
  ends_at timestamptz,
  all_day boolean,
  conversation_id uuid,
  circle_id uuid,
  target_id uuid,
  parent_id uuid,
  place_name text,
  subtitle text,
  meta jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_to <= p_from then
    raise exception 'Invalid range' using errcode = '22023';
  end if;
  if p_to - p_from > interval '400 days' then
    raise exception 'Range too long' using errcode = '22023';
  end if;

  return query
  with readable as (
    select r.id
    from public.current_user_readable_conversation_ids() as r(id)
    where not public.is_current_user_blocked_in_conversation(r.id)
  ),
  items as (
    -- Events of groups and direct chats I said going / maybe to.
    select
      'chat_event'::text as kind,
      e.title as title,
      e.starts_at as starts_at,
      e.ends_at as ends_at,
      false as all_day,
      e.conversation_id as conversation_id,
      null::uuid as circle_id,
      e.id as target_id,
      null::uuid as parent_id,
      nullif(btrim(coalesce(e.location_text, e.link_url, '')), '') as subtitle,
      jsonb_build_object('status', r.status) as meta
    from public.chat_event_rsvps r
    join public.chat_events e on e.id = r.event_id
    where (p_kinds is null or 'chat_event' = any (p_kinds))
      and r.user_id = uid
      and r.status in ('going', 'maybe')
      and e.cancelled_at is null
      and coalesce(e.ends_at, e.starts_at) >= p_from
      and e.starts_at < p_to
      and e.conversation_id in (select id from readable)

    union all

    -- Circle events I am interested in and may still see.
    select
      'circle_event',
      e.title,
      e.starts_at,
      e.ends_at,
      false,
      null::uuid,
      e.circle_id,
      e.id,
      null::uuid,
      nullif(btrim(coalesce(e.location_text, '')), ''),
      jsonb_build_object('status', 'interested')
    from public.circle_event_rsvps r
    join public.circle_events e
      on e.id = r.event_id and e.circle_id = r.circle_id
    where (p_kinds is null or 'circle_event' = any (p_kinds))
      and r.user_id = uid
      and e.cancelled_at is null
      and public.circle_event_ends_at(e.starts_at, e.ends_at) >= p_from
      and e.starts_at < p_to
      and public.current_user_can_see_circle_event(e)

    union all

    -- Tasks assigned to me that are open and have a due date.
    select
      'task',
      i.title,
      i.due_at,
      null::timestamptz,
      not i.due_has_time,
      l.conversation_id,
      null::uuid,
      i.id,
      i.list_id,
      null::text,
      jsonb_build_object('priority', i.priority)
    from public.task_item_assignees a
    join public.task_items i on i.id = a.item_id
    join public.task_lists l on l.id = i.list_id
    where (p_kinds is null or 'task' = any (p_kinds))
      and a.user_id = uid
      and i.deleted_at is null
      and i.completed_at is null
      and i.due_at is not null
      and i.due_at >= p_from
      and i.due_at < p_to
      and l.deleted_at is null
      and l.conversation_id in (select id from readable)

    union all

    -- My reminders about messages.
    select
      'reminder',
      case
        when m.id is not null
          and m.recalled_at is null
          and (m.expires_at is null or m.expires_at > now())
          and public.message_visible_to_current_user(
            m.review_state, m.sender_id, m.conversation_id
          )
        then left(btrim(coalesce(m.body, '')), 200)
      end,
      mr.remind_at,
      null::timestamptz,
      false,
      mr.conversation_id,
      null::uuid,
      mr.id,
      mr.message_id,
      null::text,
      jsonb_build_object(
        'message_type',
        case
          when m.id is not null
            and m.recalled_at is null
            and (m.expires_at is null or m.expires_at > now())
            and public.message_visible_to_current_user(
              m.review_state, m.sender_id, m.conversation_id
            )
          then m.type
        end,
        'fired', mr.remind_at <= now()
      )
    from public.message_reminders mr
    left join public.messages m on m.id = mr.message_id
    where (p_kinds is null or 'reminder' = any (p_kinds))
      and mr.user_id = uid
      and mr.dismissed_at is null
      and mr.remind_at >= p_from
      and mr.remind_at < p_to
      and mr.conversation_id in (select id from readable)

    union all

    -- My messages waiting to be sent.
    select
      'scheduled_message',
      left(btrim(s.body), 200),
      s.send_at,
      null::timestamptz,
      false,
      s.conversation_id,
      null::uuid,
      s.id,
      null::uuid,
      null::text,
      '{}'::jsonb
    from public.scheduled_messages s
    where (p_kinds is null or 'scheduled_message' = any (p_kinds))
      and s.owner_id = uid
      and s.status = 'pending'
      and s.send_at >= p_from
      and s.send_at < p_to
      and s.conversation_id in (select id from readable)
  )
  select
    items.kind,
    items.title,
    items.starts_at,
    items.ends_at,
    items.all_day,
    items.conversation_id,
    coalesce(
      items.circle_id,
      (
        select cc.circle_id
        from public.circle_channels cc
        where cc.conversation_id = items.conversation_id
      )
    ),
    items.target_id,
    items.parent_id,
    case
      when items.conversation_id is not null
        then public.agenda_place_name(items.conversation_id, uid)
      else (
        select ci.name from public.circles ci where ci.id = items.circle_id
      )
    end,
    items.subtitle,
    items.meta
  from items
  order by items.starts_at, items.kind, items.target_id
  limit 500;
end;
$$;

revoke execute on function public.agenda_items_core(timestamptz, timestamptz, text[])
  from public, anon, authenticated;

create or replace function public.get_my_agenda(
  p_from timestamptz,
  p_to timestamptz
)
returns table (
  kind text,
  title text,
  starts_at timestamptz,
  ends_at timestamptz,
  all_day boolean,
  conversation_id uuid,
  circle_id uuid,
  target_id uuid,
  parent_id uuid,
  place_name text,
  subtitle text,
  meta jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  return query select * from public.agenda_items_core(p_from, p_to, null);
end;
$$;

revoke execute on function public.get_my_agenda(timestamptz, timestamptz) from public, anon;
grant execute on function public.get_my_agenda(timestamptz, timestamptz) to authenticated;

-- The agenda of one person, for the calendar-feed Edge Function. Service
-- role only: it names the person, which the callers above cannot do.
create or replace function public.agenda_items_for_user(
  p_user_id uuid,
  p_from timestamptz,
  p_to timestamptz,
  p_kinds text[] default null
)
returns table (
  kind text,
  title text,
  starts_at timestamptz,
  ends_at timestamptz,
  all_day boolean,
  conversation_id uuid,
  circle_id uuid,
  target_id uuid,
  parent_id uuid,
  place_name text,
  subtitle text,
  meta jsonb
)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  previous text := current_setting('request.jwt.claim.sub', true);
begin
  if p_user_id is null then
    raise exception 'User required' using errcode = '22023';
  end if;
  -- Local to this transaction; put back before returning.
  perform set_config('request.jwt.claim.sub', p_user_id::text, true);
  return query select * from public.agenda_items_core(p_from, p_to, p_kinds);
  perform set_config('request.jwt.claim.sub', coalesce(previous, ''), true);
end;
$$;

revoke execute on function public.agenda_items_for_user(uuid, timestamptz, timestamptz, text[])
  from public, anon, authenticated;
grant execute on function public.agenda_items_for_user(uuid, timestamptz, timestamptz, text[])
  to service_role;
