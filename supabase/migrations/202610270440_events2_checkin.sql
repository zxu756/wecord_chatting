-- Events 2.0 (roadmap C10), part 5 of 7: checking in, and the organiser's
-- view of who signed up.
--
-- * events2_event_scope(kind, event, mode): the one place that decides who may
--   touch an event, used by everything below and by the photos (next
--   migration). kind is 'chat' or 'circle'. mode:
--     'read'    anyone who can see the event;
--     'member'  a write by an attendee: for a chat event the chat's own rules
--               (member, not blocked, not suspended); for a circle event a
--               member who can see it, in a circle that is not suspended (K1);
--     'manage'  an organiser: for a chat event its creator, a group's owner or
--               an admin (can_manage_chat_event); for a circle event its
--               creator or manage_events, in a circle that is not taken down.
--   Everything else is refused with 42501.
-- * create_event_check_in_code(kind, event): an organiser makes a code to show
--   as a QR. It works from 2 hours before the start until 3 hours after the
--   end; making another one cancels the one before. Only a hash is stored, so
--   the code is shown once, to the organiser who made it.
-- * check_in_event(code): an attendee scans it. Anyone who can see the event
--   can check in (walk-ins included) unless they are on the waiting list.
--   Checking in twice is the same as once.
-- * set_event_check_in(kind, event, user, checked_in): an organiser ticks a
--   person on or off by hand.
-- * list_event_registrations(kind, event): for organisers. Everyone signed up
--   with their answers and whether they checked in, the waiting list in
--   order, and people who came without signing up.

create or replace function public.events2_event_scope(
  p_kind text,
  p_event_id uuid,
  p_mode text
)
returns table (
  kind text,
  event_id uuid,
  scope_id uuid,
  title text,
  starts_at timestamptz,
  effective_ends_at timestamptz,
  cancelled_at timestamptz,
  capacity integer,
  questions jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  chat_row public.chat_events%rowtype;
  circle_row public.circle_events%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_mode not in ('read', 'member', 'manage') then
    raise exception 'Unknown mode' using errcode = '22023';
  end if;

  if p_kind = 'chat' then
    select e.* into chat_row from public.chat_events e where e.id = p_event_id;
    if chat_row.id is null
      or not public.is_current_user_conversation_member(chat_row.conversation_id)
    then
      raise exception 'Event not found' using errcode = '42501';
    end if;
    if p_mode <> 'read' then
      perform public.chat_event_check_conversation(chat_row.conversation_id);
    end if;
    if p_mode = 'manage' and not public.can_manage_chat_event(chat_row, auth.uid()) then
      raise exception 'Cannot manage this event' using errcode = '42501';
    end if;
    return query select
      'chat'::text, chat_row.id, chat_row.conversation_id, chat_row.title,
      chat_row.starts_at,
      coalesce(chat_row.ends_at, chat_row.starts_at + interval '2 hours'),
      chat_row.cancelled_at, chat_row.capacity, chat_row.questions;
  elsif p_kind = 'circle' then
    select e.* into circle_row from public.circle_events e where e.id = p_event_id;
    if not coalesce(public.current_user_can_see_circle_event(circle_row), false) then
      raise exception 'Event not found' using errcode = '42501';
    end if;
    if p_mode = 'manage' then
      if not (
        circle_row.created_by is not distinct from auth.uid()
        or public.current_user_has_circle_permission(circle_row.circle_id, 'manage_events')
      ) then
        raise exception 'Cannot manage this event' using errcode = '42501';
      end if;
      perform public.events2_assert_circle_open(circle_row.circle_id, true);
    elsif p_mode = 'member' then
      perform public.events2_assert_circle_open(circle_row.circle_id, false);
    end if;
    return query select
      'circle'::text, circle_row.id, circle_row.circle_id, circle_row.title,
      circle_row.starts_at,
      public.circle_event_ends_at(circle_row.starts_at, circle_row.ends_at),
      circle_row.cancelled_at, circle_row.capacity, circle_row.questions;
  else
    raise exception 'An event is a chat event or a circle event' using errcode = '22023';
  end if;
end;
$$;

revoke execute on function public.events2_event_scope(text, uuid, text)
  from public, anon, authenticated;

create or replace function public.create_event_check_in_code(
  p_kind text,
  p_event_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  scope record;
  new_code text;
  expires timestamptz;
begin
  select * into scope from public.events2_event_scope(p_kind, p_event_id, 'manage');
  if scope.cancelled_at is not null then
    raise exception 'This event was cancelled' using errcode = '22023';
  end if;
  expires := scope.effective_ends_at + interval '3 hours';
  if expires <= now() then
    raise exception 'This event is over' using errcode = '22023';
  end if;

  update public.event_check_in_codes c
  set revoked_at = now()
  where c.revoked_at is null
    and (
      (p_kind = 'chat' and c.chat_event_id = p_event_id)
      or (p_kind = 'circle' and c.circle_event_id = p_event_id)
    );

  new_code := public.generate_call_link_code();
  insert into public.event_check_in_codes (
    chat_event_id, circle_event_id, code_hash, created_by, expires_at
  )
  values (
    case when p_kind = 'chat' then p_event_id end,
    case when p_kind = 'circle' then p_event_id end,
    encode(sha256(convert_to(new_code, 'UTF8')), 'hex'),
    auth.uid(),
    expires
  );

  return jsonb_build_object(
    'code', new_code,
    'expires_at', expires,
    'path', '/checkin/' || new_code
  );
end;
$$;

create or replace function public.check_in_event(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  code_row public.event_check_in_codes%rowtype;
  kind_value text;
  event_value uuid;
  scope record;
  inserted boolean;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_code is null or p_code !~ '^[a-z0-9]{12}$' then
    raise exception 'This check-in code is not valid' using errcode = '22023';
  end if;

  select c.* into code_row
  from public.event_check_in_codes c
  where c.code_hash = encode(sha256(convert_to(p_code, 'UTF8')), 'hex');
  if code_row.id is null or code_row.revoked_at is not null or code_row.expires_at <= now() then
    raise exception 'This check-in code is not valid' using errcode = '22023';
  end if;

  kind_value := case when code_row.chat_event_id is not null then 'chat' else 'circle' end;
  event_value := coalesce(code_row.chat_event_id, code_row.circle_event_id);

  select * into scope from public.events2_event_scope(kind_value, event_value, 'member');
  if scope.cancelled_at is not null then
    raise exception 'This event was cancelled' using errcode = '22023';
  end if;
  if now() < scope.starts_at - interval '2 hours' then
    raise exception 'Check-in has not opened yet' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.event_waitlist w
    where w.user_id = current_user_id
      and (
        (kind_value = 'chat' and w.chat_event_id = event_value)
        or (kind_value = 'circle' and w.circle_event_id = event_value)
      )
  ) then
    raise exception 'You are on the waiting list' using errcode = '22023';
  end if;

  insert into public.event_check_ins (chat_event_id, circle_event_id, user_id)
  values (
    case when kind_value = 'chat' then event_value end,
    case when kind_value = 'circle' then event_value end,
    current_user_id
  )
  on conflict do nothing;
  inserted := found;

  return jsonb_build_object(
    'kind', kind_value,
    'event_id', event_value,
    'scope_id', scope.scope_id,
    'title', scope.title,
    'starts_at', scope.starts_at,
    'already', not inserted
  );
end;
$$;

create or replace function public.set_event_check_in(
  p_kind text,
  p_event_id uuid,
  p_user_id uuid,
  p_checked_in boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  scope record;
begin
  select * into scope from public.events2_event_scope(p_kind, p_event_id, 'manage');

  -- Only people who belong to the chat or the circle.
  if p_kind = 'chat' and not exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = scope.scope_id and cm.user_id = p_user_id
  ) then
    raise exception 'Not a member' using errcode = '22023';
  end if;
  if p_kind = 'circle' and not exists (
    select 1 from public.circle_members cm
    where cm.circle_id = scope.scope_id and cm.user_id = p_user_id
  ) then
    raise exception 'Not a member' using errcode = '22023';
  end if;

  if coalesce(p_checked_in, false) then
    insert into public.event_check_ins (chat_event_id, circle_event_id, user_id)
    values (
      case when p_kind = 'chat' then p_event_id end,
      case when p_kind = 'circle' then p_event_id end,
      p_user_id
    )
    on conflict do nothing;
  else
    delete from public.event_check_ins ci
    where ci.user_id = p_user_id
      and (
        (p_kind = 'chat' and ci.chat_event_id = p_event_id)
        or (p_kind = 'circle' and ci.circle_event_id = p_event_id)
      );
  end if;
end;
$$;

create or replace function public.list_event_registrations(
  p_kind text,
  p_event_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  scope record;
  signed_up jsonb;
  waiting jsonb;
  walk_ins jsonb;
begin
  select * into scope from public.events2_event_scope(p_kind, p_event_id, 'manage');

  if p_kind = 'chat' then
    select coalesce(jsonb_agg(row_json order by sort_key, sign_up_at), '[]'::jsonb)
    into signed_up
    from (
      select
        jsonb_build_object(
          'user_id', p.id,
          'display_name', p.display_name,
          'username', p.username,
          'avatar_url', p.avatar_url,
          'status', r.status,
          'answers', r.answers,
          'signed_up_at', r.updated_at,
          'checked_in_at', ci.checked_in_at
        ) as row_json,
        case r.status when 'going' then 0 when 'maybe' then 1 else 2 end as sort_key,
        r.updated_at as sign_up_at
      from public.chat_event_rsvps r
      join public.conversation_members cm
        on cm.conversation_id = scope.scope_id and cm.user_id = r.user_id
      join public.profiles p on p.id = r.user_id
      left join public.event_check_ins ci
        on ci.chat_event_id = r.event_id and ci.user_id = r.user_id
      where r.event_id = p_event_id
    ) q;

    select coalesce(jsonb_agg(row_json order by joined_at, wid), '[]'::jsonb)
    into waiting
    from (
      select
        jsonb_build_object(
          'user_id', p.id,
          'display_name', p.display_name,
          'username', p.username,
          'avatar_url', p.avatar_url,
          'answers', w.answers,
          'joined_at', w.created_at
        ) as row_json,
        w.created_at as joined_at,
        w.id as wid
      from public.event_waitlist w
      join public.conversation_members cm
        on cm.conversation_id = scope.scope_id and cm.user_id = w.user_id
      join public.profiles p on p.id = w.user_id
      where w.chat_event_id = p_event_id
    ) q;

    select coalesce(jsonb_agg(row_json order by checked), '[]'::jsonb)
    into walk_ins
    from (
      select
        jsonb_build_object(
          'user_id', p.id,
          'display_name', p.display_name,
          'username', p.username,
          'avatar_url', p.avatar_url,
          'checked_in_at', ci.checked_in_at
        ) as row_json,
        ci.checked_in_at as checked
      from public.event_check_ins ci
      join public.conversation_members cm
        on cm.conversation_id = scope.scope_id and cm.user_id = ci.user_id
      join public.profiles p on p.id = ci.user_id
      where ci.chat_event_id = p_event_id
        and not exists (
          select 1 from public.chat_event_rsvps r
          where r.event_id = ci.chat_event_id and r.user_id = ci.user_id
        )
    ) q;
  else
    select coalesce(jsonb_agg(row_json order by sign_up_at), '[]'::jsonb)
    into signed_up
    from (
      select
        jsonb_build_object(
          'user_id', p.id,
          'display_name', coalesce(public.circle_member_label(scope.scope_id, p.id), p.display_name),
          'username', p.username,
          'avatar_url', p.avatar_url,
          'status', 'going',
          'answers', r.answers,
          'signed_up_at', r.created_at,
          'checked_in_at', ci.checked_in_at
        ) as row_json,
        r.created_at as sign_up_at
      from public.circle_event_rsvps r
      join public.profiles p on p.id = r.user_id
      left join public.event_check_ins ci
        on ci.circle_event_id = r.event_id and ci.user_id = r.user_id
      where r.event_id = p_event_id
    ) q;

    select coalesce(jsonb_agg(row_json order by joined_at, wid), '[]'::jsonb)
    into waiting
    from (
      select
        jsonb_build_object(
          'user_id', p.id,
          'display_name', coalesce(public.circle_member_label(scope.scope_id, p.id), p.display_name),
          'username', p.username,
          'avatar_url', p.avatar_url,
          'answers', w.answers,
          'joined_at', w.created_at
        ) as row_json,
        w.created_at as joined_at,
        w.id as wid
      from public.event_waitlist w
      join public.profiles p on p.id = w.user_id
      where w.circle_event_id = p_event_id
    ) q;

    select coalesce(jsonb_agg(row_json order by checked), '[]'::jsonb)
    into walk_ins
    from (
      select
        jsonb_build_object(
          'user_id', p.id,
          'display_name', coalesce(public.circle_member_label(scope.scope_id, p.id), p.display_name),
          'username', p.username,
          'avatar_url', p.avatar_url,
          'checked_in_at', ci.checked_in_at
        ) as row_json,
        ci.checked_in_at as checked
      from public.event_check_ins ci
      join public.circle_members cm
        on cm.circle_id = scope.scope_id and cm.user_id = ci.user_id
      join public.profiles p on p.id = ci.user_id
      where ci.circle_event_id = p_event_id
        and not exists (
          select 1 from public.circle_event_rsvps r
          where r.event_id = ci.circle_event_id and r.user_id = ci.user_id
        )
    ) q;
  end if;

  return jsonb_build_object(
    'questions', scope.questions,
    'capacity', scope.capacity,
    'registrations', signed_up,
    'waitlist', waiting,
    'walk_ins', walk_ins
  );
end;
$$;

revoke execute on function public.create_event_check_in_code(text, uuid) from public, anon;
revoke execute on function public.check_in_event(text) from public, anon;
revoke execute on function public.set_event_check_in(text, uuid, uuid, boolean) from public, anon;
revoke execute on function public.list_event_registrations(text, uuid) from public, anon;
grant execute on function public.create_event_check_in_code(text, uuid) to authenticated;
grant execute on function public.check_in_event(text) to authenticated;
grant execute on function public.set_event_check_in(text, uuid, uuid, boolean) to authenticated;
grant execute on function public.list_event_registrations(text, uuid) to authenticated;
