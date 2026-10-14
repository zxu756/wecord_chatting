-- Voice and video calls in direct and group chats.
--
-- * direct_calls: at most one active call per conversation. Starting a call
--   posts a system message "X started a call."; when the last participant
--   leaves (or goes quiet for a minute) the call ends and that message
--   becomes "X started a call that lasted N minutes."
-- * direct_call_participants: who is in the call, with the same flags and
--   20 second heartbeat as voice_states. Someone is in at most one call,
--   and never in a call and a voice channel at once.
-- * The other members' apps ring while the call is less than 45 seconds old
--   and they have neither joined nor declined (direct_call_declines).
-- * The LiveKit room of a call is "call-<call id>"; livekit-token asks
--   can_current_user_join_direct_call before minting a token.

create table if not exists public.direct_calls (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  started_by uuid references public.profiles(id) on delete set null,
  system_message_id uuid references public.messages(id) on delete set null,
  created_at timestamptz not null default now(),
  ended_at timestamptz
);

create unique index if not exists direct_calls_one_active_idx
  on public.direct_calls (conversation_id)
  where ended_at is null;

create table if not exists public.direct_call_participants (
  call_id uuid not null references public.direct_calls(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  joined_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  self_mute boolean not null default false,
  self_deaf boolean not null default false,
  video boolean not null default false,
  screen boolean not null default false,
  primary key (call_id, user_id),
  constraint direct_call_participants_one_call unique (user_id)
);

create index if not exists direct_call_participants_conversation_idx
  on public.direct_call_participants (conversation_id);

create table if not exists public.direct_call_declines (
  call_id uuid not null references public.direct_calls(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (call_id, user_id)
);

alter table public.direct_calls enable row level security;
alter table public.direct_call_participants enable row level security;
alter table public.direct_call_declines enable row level security;

drop policy if exists direct_calls_select_member on public.direct_calls;
create policy direct_calls_select_member
  on public.direct_calls for select
  to authenticated
  using (public.is_current_user_conversation_member(conversation_id));

drop policy if exists direct_call_participants_select_member
  on public.direct_call_participants;
create policy direct_call_participants_select_member
  on public.direct_call_participants for select
  to authenticated
  using (public.is_current_user_conversation_member(conversation_id));

drop policy if exists direct_call_declines_select_own on public.direct_call_declines;
create policy direct_call_declines_select_own
  on public.direct_call_declines for select
  to authenticated
  using (user_id = auth.uid());

revoke insert, update, delete on public.direct_calls from anon, authenticated;
revoke insert, update, delete on public.direct_call_participants from anon, authenticated;
revoke insert, update, delete on public.direct_call_declines from anon, authenticated;

alter table public.direct_calls replica identity full;
alter table public.direct_call_participants replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'direct_calls'
  ) then
    alter publication supabase_realtime add table public.direct_calls;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'direct_call_participants'
  ) then
    alter publication supabase_realtime add table public.direct_call_participants;
  end if;
end;
$$;

-- "N minutes", "1 hour 5 minutes", or "a few seconds".
create or replace function public.format_call_length(length interval)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  total_minutes integer := floor(extract(epoch from length) / 60)::integer;
  hours integer := total_minutes / 60;
  minutes integer := total_minutes % 60;
  parts text[] := array[]::text[];
begin
  if total_minutes < 1 then
    return 'a few seconds';
  end if;
  if hours > 0 then
    parts := parts || (hours || case when hours = 1 then ' hour' else ' hours' end);
  end if;
  if minutes > 0 then
    parts := parts || (minutes || case when minutes = 1 then ' minute' else ' minutes' end);
  end if;
  return array_to_string(parts, ' ');
end;
$$;

-- Ends a call and rewrites its "started a call" message with the length.
create or replace function public.end_direct_call(target_call_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  call_row public.direct_calls%rowtype;
begin
  update public.direct_calls dc
  set ended_at = now()
  where dc.id = target_call_id
    and dc.ended_at is null
  returning dc.* into call_row;

  if call_row.id is null then
    return;
  end if;

  delete from public.direct_call_participants p where p.call_id = call_row.id;

  if call_row.system_message_id is not null then
    update public.messages m
    set body = coalesce(
      (
        select coalesce(nullif(btrim(p.display_name), ''), p.username)
        from public.profiles p
        where p.id = call_row.started_by
      ),
      'Someone'
    ) || ' started a call that lasted '
      || public.format_call_length(call_row.ended_at - call_row.created_at)
      || '.'
    where m.id = call_row.system_message_id;
  end if;
end;
$$;

-- Drops participants who stopped heartbeating and ends calls nobody is in.
create or replace function public.cleanup_direct_calls(target_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  stale_call uuid;
begin
  delete from public.direct_call_participants p
  where p.conversation_id = target_conversation_id
    and p.last_seen_at < now() - interval '60 seconds';

  for stale_call in
    select dc.id
    from public.direct_calls dc
    where dc.conversation_id = target_conversation_id
      and dc.ended_at is null
      and not exists (
        select 1
        from public.direct_call_participants p
        where p.call_id = dc.id
      )
  loop
    perform public.end_direct_call(stale_call);
  end loop;
end;
$$;

-- Whether the caller may call in a conversation: a member of a direct or
-- group chat that isn't blocked (or with a deleted account).
create or replace function public.can_current_user_call_in_conversation(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.conversations c
    where c.id = target_conversation_id
      and c.type in ('direct', 'group')
  )
    and public.is_current_user_conversation_member(target_conversation_id)
    and not public.is_current_user_blocked_in_conversation(target_conversation_id);
$$;

-- Puts the caller in a call: their other call and voice channel are left.
create or replace function public.add_direct_call_participant(
  target_call_id uuid,
  target_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  previous_call uuid;
begin
  select p.call_id
  into previous_call
  from public.direct_call_participants p
  where p.user_id = current_user_id
    and p.call_id <> target_call_id;

  if previous_call is not null then
    delete from public.direct_call_participants p
    where p.call_id = previous_call
      and p.user_id = current_user_id;
    if not exists (
      select 1 from public.direct_call_participants p where p.call_id = previous_call
    ) then
      perform public.end_direct_call(previous_call);
    end if;
  end if;

  delete from public.voice_states vs where vs.user_id = current_user_id;

  insert into public.direct_call_participants (
    call_id,
    user_id,
    conversation_id
  )
  values (target_call_id, current_user_id, target_conversation_id)
  on conflict (call_id, user_id) do update
  set last_seen_at = now();
end;
$$;

-- Joins the conversation's call, starting one (and ringing the others)
-- when there is none. Returns the call id.
create or replace function public.start_direct_call(target_conversation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  found_call uuid;
  caller_name text;
  notice_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.can_current_user_call_in_conversation(target_conversation_id) then
    raise exception 'You cannot call in this conversation' using errcode = '42501';
  end if;

  -- One call per conversation, even when two people press call at once.
  perform 1 from public.conversations c where c.id = target_conversation_id for update;

  perform public.cleanup_direct_calls(target_conversation_id);

  select dc.id
  into found_call
  from public.direct_calls dc
  where dc.conversation_id = target_conversation_id
    and dc.ended_at is null;

  if found_call is null then
    insert into public.direct_calls (conversation_id, started_by)
    values (target_conversation_id, current_user_id)
    returning id into found_call;

    select coalesce(nullif(btrim(p.display_name), ''), p.username)
    into caller_name
    from public.profiles p
    where p.id = current_user_id;

    insert into public.messages (conversation_id, sender_id, type, body, attachment)
    values (
      target_conversation_id,
      current_user_id,
      'system',
      coalesce(caller_name, 'Someone') || ' started a call.',
      jsonb_build_object('kind', 'call', 'call_id', found_call)
    )
    returning id into notice_id;

    update public.direct_calls dc
    set system_message_id = notice_id
    where dc.id = found_call;
  end if;

  perform public.add_direct_call_participant(found_call, target_conversation_id);
  return found_call;
end;
$$;

-- Rejoins a call still going (after a missed heartbeat). False once it
-- ended or the caller lost access.
create or replace function public.join_direct_call(target_call_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  call_conversation uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select dc.conversation_id
  into call_conversation
  from public.direct_calls dc
  where dc.id = target_call_id
    and dc.ended_at is null;

  if call_conversation is null
    or not public.can_current_user_call_in_conversation(call_conversation)
  then
    return false;
  end if;

  perform public.add_direct_call_participant(target_call_id, call_conversation);
  return true;
end;
$$;

-- The caller's heartbeat and flags. False when they are no longer in the
-- call (it ended, they went stale or lost access).
create or replace function public.update_direct_call_state(
  target_call_id uuid,
  target_self_mute boolean,
  target_self_deaf boolean,
  target_video boolean,
  target_screen boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  call_conversation uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select p.conversation_id
  into call_conversation
  from public.direct_call_participants p
  join public.direct_calls dc on dc.id = p.call_id and dc.ended_at is null
  where p.call_id = target_call_id
    and p.user_id = current_user_id
    and p.last_seen_at >= now() - interval '60 seconds';

  if call_conversation is null
    or not public.can_current_user_call_in_conversation(call_conversation)
  then
    delete from public.direct_call_participants p
    where p.call_id = target_call_id
      and p.user_id = current_user_id;
    return false;
  end if;

  update public.direct_call_participants p
  set
    last_seen_at = now(),
    self_mute = coalesce(target_self_mute, p.self_mute),
    self_deaf = coalesce(target_self_deaf, p.self_deaf),
    video = coalesce(target_video, p.video),
    screen = coalesce(target_screen, p.screen)
  where p.call_id = target_call_id
    and p.user_id = current_user_id;
  return true;
end;
$$;

create or replace function public.leave_direct_call(target_call_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  delete from public.direct_call_participants p
  where p.call_id = target_call_id
    and p.user_id = auth.uid();

  if not exists (
    select 1 from public.direct_call_participants p where p.call_id = target_call_id
  ) then
    perform public.end_direct_call(target_call_id);
  end if;
end;
$$;

-- Stops the call ringing for the caller.
create or replace function public.decline_direct_call(target_call_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.direct_calls dc
    where dc.id = target_call_id
      and public.is_current_user_conversation_member(dc.conversation_id)
  ) then
    raise exception 'Call not found' using errcode = 'P0002';
  end if;

  insert into public.direct_call_declines (call_id, user_id)
  values (target_call_id, auth.uid())
  on conflict do nothing;
end;
$$;

-- Calls going on in the caller's direct and group chats, with who is in
-- them and whether they ring for the caller.
create or replace function public.list_active_direct_calls()
returns table (
  call_id uuid,
  conversation_id uuid,
  started_by uuid,
  created_at timestamptz,
  ringing boolean,
  participants jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  active_conversation uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  for active_conversation in
    select distinct dc.conversation_id
    from public.direct_calls dc
    join public.conversation_members cm
      on cm.conversation_id = dc.conversation_id
      and cm.user_id = current_user_id
    where dc.ended_at is null
  loop
    perform public.cleanup_direct_calls(active_conversation);
  end loop;

  return query
  select
    dc.id,
    dc.conversation_id,
    dc.started_by,
    dc.created_at,
    (
      dc.created_at > now() - interval '45 seconds'
      and not exists (
        select 1
        from public.direct_call_participants mine
        where mine.call_id = dc.id
          and mine.user_id = current_user_id
      )
      and not exists (
        select 1
        from public.direct_call_declines d
        where d.call_id = dc.id
          and d.user_id = current_user_id
      )
      and not public.is_current_user_blocked_in_conversation(dc.conversation_id)
    ),
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'user_id', p.user_id,
          'username', pr.username,
          'display_name', pr.display_name,
          'avatar_url', pr.avatar_url,
          'self_mute', p.self_mute,
          'self_deaf', p.self_deaf,
          'video', p.video,
          'screen', p.screen,
          'joined_at', p.joined_at
        )
        order by p.joined_at
      )
      from public.direct_call_participants p
      join public.profiles pr on pr.id = p.user_id
      where p.call_id = dc.id
    ), '[]'::jsonb)
  from public.direct_calls dc
  join public.conversation_members cm
    on cm.conversation_id = dc.conversation_id
    and cm.user_id = current_user_id
  where dc.ended_at is null
  order by dc.created_at desc;
end;
$$;

-- For livekit-token: the call (still going) and the caller's display name,
-- or null when they may not join it.
create or replace function public.can_current_user_join_direct_call(
  target_call_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  call_conversation uuid;
begin
  select dc.conversation_id
  into call_conversation
  from public.direct_calls dc
  where dc.id = target_call_id
    and dc.ended_at is null;

  if call_conversation is null
    or not public.can_current_user_call_in_conversation(call_conversation)
  then
    return null;
  end if;

  return jsonb_build_object(
    'call_id', target_call_id,
    'display_name', (
      select coalesce(nullif(btrim(p.display_name), ''), p.username)
      from public.profiles p
      where p.id = auth.uid()
    )
  );
end;
$$;

-- Joining a voice channel leaves any call.
create or replace function public.leave_direct_call_on_voice_join()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  previous_call uuid;
begin
  delete from public.direct_call_participants p
  where p.user_id = new.user_id
  returning p.call_id into previous_call;

  if previous_call is not null and not exists (
    select 1 from public.direct_call_participants p where p.call_id = previous_call
  ) then
    perform public.end_direct_call(previous_call);
  end if;
  return new;
end;
$$;

drop trigger if exists voice_states_leave_direct_call on public.voice_states;
create trigger voice_states_leave_direct_call
  after insert on public.voice_states
  for each row execute function public.leave_direct_call_on_voice_join();

revoke execute on function public.format_call_length(interval) from public, anon;
revoke execute on function public.end_direct_call(uuid) from public, anon, authenticated;
revoke execute on function public.cleanup_direct_calls(uuid) from public, anon, authenticated;
revoke execute on function public.add_direct_call_participant(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.leave_direct_call_on_voice_join() from public;
revoke execute on function public.can_current_user_call_in_conversation(uuid) from public, anon;
grant execute on function public.can_current_user_call_in_conversation(uuid) to authenticated;

revoke execute on function public.start_direct_call(uuid) from public, anon;
revoke execute on function public.join_direct_call(uuid) from public, anon;
revoke execute on function public.update_direct_call_state(uuid, boolean, boolean, boolean, boolean) from public, anon;
revoke execute on function public.leave_direct_call(uuid) from public, anon;
revoke execute on function public.decline_direct_call(uuid) from public, anon;
revoke execute on function public.list_active_direct_calls() from public, anon;
revoke execute on function public.can_current_user_join_direct_call(uuid) from public, anon;
grant execute on function public.start_direct_call(uuid) to authenticated;
grant execute on function public.join_direct_call(uuid) to authenticated;
grant execute on function public.update_direct_call_state(uuid, boolean, boolean, boolean, boolean) to authenticated;
grant execute on function public.leave_direct_call(uuid) to authenticated;
grant execute on function public.decline_direct_call(uuid) to authenticated;
grant execute on function public.list_active_direct_calls() to authenticated;
grant execute on function public.can_current_user_join_direct_call(uuid) to authenticated;
