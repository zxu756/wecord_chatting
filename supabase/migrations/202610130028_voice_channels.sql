-- Voice channels, like Discord's: members connect to a LiveKit room named
-- after the channel id; this database only tracks who is in which channel.
--
-- * create_circle_channel accepts target_kind 'voice'. A voice channel keeps
--   a conversation like every channel, but it takes no messages (the send
--   trigger refuses them); clients show no chat for it.
-- * voice_states (channel_id, user_id, circle_id, joined_at, last_seen_at,
--   self_mute, self_deaf, video, screen): one row per connected member, and
--   a member is in at most one voice channel. Clients only read it (members
--   who can view the channel); RPCs write it. Leaving or being kicked from
--   the circle, or the channel being deleted, removes the row.
-- * Clients heartbeat every 20 seconds; a row without a heartbeat for 60
--   seconds is stale: list_voice_states skips (and deletes) it, and
--   join / update delete the caller's stale row.
-- * join_voice_state(channel_id): needs connect_voice in a voice channel;
--   replaces the caller's previous state (keeping joined_at when they
--   rejoin the same channel within the 60 seconds).
-- * update_voice_state(mute, deaf, video, screen): the caller's flags and
--   heartbeat. Returns false when the caller has no live state or lost
--   connect_voice (the row is then removed), so the client rejoins or
--   disconnects.
-- * leave_voice_state(), list_voice_states(circle_id) (with profile,
--   nickname and role colour).
-- * can_current_user_connect_voice(channel_id): what the livekit-token Edge
--   Function asks, as the caller, before signing a LiveKit token: the
--   channel's name and circle and the caller's display name, or null.

-- Same as 202610130020_forum_channels, but voice channels can be created too.
create or replace function public.create_circle_channel(
  target_circle_id uuid,
  channel_name text,
  target_category_id uuid default null,
  target_kind text default 'text'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_name text := trim(coalesce(channel_name, ''));
  channel_kind text := coalesce(target_kind, 'text');
  created_conversation_id uuid;
  created_channel_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_name) = 0 or char_length(trimmed_name) > 48 then
    raise exception 'Channel name must be between 1 and 48 characters'
      using errcode = '22023';
  end if;

  if channel_kind not in ('text', 'forum', 'voice') then
    raise exception 'Unsupported channel type' using errcode = '22023';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'manage_channels'
  ) then
    raise exception 'Only members who can manage channels can create channels'
      using errcode = '42501';
  end if;

  perform 1 from public.circles where id = target_circle_id for no key update;

  if target_category_id is not null and not exists (
    select 1
    from public.circle_channel_categories ccc
    where ccc.id = target_category_id
      and ccc.circle_id = target_circle_id
  ) then
    raise exception 'Category does not belong to this circle'
      using errcode = '22023';
  end if;

  insert into public.conversations (type, title)
  values ('channel', trimmed_name)
  returning id into created_conversation_id;

  insert into public.conversation_members (conversation_id, user_id, role)
  select created_conversation_id, cm.user_id, cm.role
  from public.circle_members cm
  where cm.circle_id = target_circle_id
  on conflict do nothing;

  insert into public.circle_channels (
    circle_id,
    conversation_id,
    name,
    position,
    category_id,
    created_by,
    kind
  )
  values (
    target_circle_id,
    created_conversation_id,
    trimmed_name,
    coalesce((
      select max(position) + 1
      from public.circle_channels
      where circle_id = target_circle_id
    ), 0),
    target_category_id,
    current_user_id,
    channel_kind
  )
  returning id into created_channel_id;

  perform public.write_circle_audit(
    target_circle_id,
    'channel_create',
    'channel',
    created_channel_id,
    trimmed_name,
    jsonb_build_object(
      'name', trimmed_name,
      'kind', channel_kind,
      'category_id', target_category_id,
      'category_name', (
        select ccc.name
        from public.circle_channel_categories ccc
        where ccc.id = target_category_id
      )
    )
  );

  return created_channel_id;
end;
$$;

-- Same as 202610130024_channel_webhooks, but a voice channel's
-- conversation takes no messages.
create or replace function public.check_channel_message_send()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
  last_sent_at timestamptz;
  remaining_seconds integer;
begin
  if new.type = 'system' then
    return new;
  end if;

  if not public.user_has_conversation_channel_permission(
    new.conversation_id,
    new.sender_id,
    'send_messages'
  ) then
    raise exception 'You do not have permission to send messages in this channel'
      using errcode = '42501';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.conversation_id = new.conversation_id;

  -- A forum channel's own conversation takes no messages: they go into
  -- its posts (threads).
  if channel.kind = 'forum' then
    raise exception 'Messages in a forum channel go into its posts'
      using errcode = '42501';
  end if;

  -- Voice channels have no chat.
  if channel.kind = 'voice' then
    raise exception 'Voice channels have no chat'
      using errcode = '42501';
  end if;

  -- Webhook messages skip slowmode (they have their own rate limit).
  if channel.id is null
    or new.webhook_name is not null
    or channel.slowmode_seconds <= 0
    or public.circle_channel_has_permission(
      channel.id,
      new.sender_id,
      'manage_messages'
    )
  then
    return new;
  end if;

  -- One send per member and channel at a time, so two quick sends cannot
  -- both pass.
  perform pg_advisory_xact_lock(
    hashtextextended(new.conversation_id::text || ':' || new.sender_id::text, 0)
  );

  select max(m.created_at) into last_sent_at
  from public.messages m
  where m.conversation_id = new.conversation_id
    and m.sender_id = new.sender_id
    and m.type <> 'system'
    and m.webhook_name is null;

  if last_sent_at is not null
    and last_sent_at + make_interval(secs => channel.slowmode_seconds) > now()
  then
    remaining_seconds := greatest(
      1,
      ceil(
        extract(
          epoch from
            last_sent_at + make_interval(secs => channel.slowmode_seconds) - now()
        )
      )::integer
    );
    raise exception 'Slowmode is enabled. Try again in % seconds.', remaining_seconds
      using errcode = 'P0001',
        detail = format('slowmode_remaining_seconds=%s', remaining_seconds);
  end if;

  return new;
end;
$$;

create table if not exists public.voice_states (
  channel_id uuid not null,
  user_id uuid not null,
  circle_id uuid not null,
  joined_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  self_mute boolean not null default false,
  self_deaf boolean not null default false,
  video boolean not null default false,
  screen boolean not null default false,
  primary key (channel_id, user_id),
  constraint voice_states_one_channel unique (user_id),
  constraint voice_states_channel_fkey
    foreign key (channel_id, circle_id)
    references public.circle_channels(id, circle_id)
    on delete cascade,
  constraint voice_states_member_fkey
    foreign key (circle_id, user_id)
    references public.circle_members(circle_id, user_id)
    on delete cascade
);

create index if not exists voice_states_circle_idx
  on public.voice_states (circle_id, last_seen_at);

create index if not exists voice_states_member_idx
  on public.voice_states (circle_id, user_id);

-- Realtime matches DELETE events against the old row, so keep the circle
-- in it.
alter table public.voice_states replica identity full;

alter table public.voice_states enable row level security;

revoke insert, update, delete, truncate on public.voice_states from anon;
revoke insert, update, delete, truncate on public.voice_states from authenticated;

drop policy if exists voice_states_select_viewer on public.voice_states;
create policy voice_states_select_viewer
  on public.voice_states for select
  to authenticated
  using (
    public.is_current_user_circle_member(circle_id)
    and public.current_user_has_channel_permission(channel_id, 'view_channel')
  );

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'voice_states'
  ) then
    alter publication supabase_realtime add table public.voice_states;
  end if;
end $$;

-- How long a voice state lives without a heartbeat.
create or replace function public.voice_state_ttl()
returns interval
language sql
immutable
set search_path = public
as $$
  select interval '60 seconds';
$$;

create or replace function public.join_voice_state(
  target_channel_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  channel public.circle_channels%rowtype;
  previous public.voice_states%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cc.*
  into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel.id is null
    or channel.kind <> 'voice'
    or not public.current_user_has_channel_permission(
      channel.id,
      'connect_voice'
    )
  then
    raise exception 'You cannot connect to this voice channel'
      using errcode = '42501';
  end if;

  -- One join per member at a time.
  perform pg_advisory_xact_lock(
    hashtextextended('voice_state:' || current_user_id::text, 0)
  );

  select vs.*
  into previous
  from public.voice_states vs
  where vs.user_id = current_user_id
  for update;

  delete from public.voice_states vs where vs.user_id = current_user_id;

  insert into public.voice_states (
    channel_id,
    user_id,
    circle_id,
    joined_at,
    last_seen_at
  )
  values (
    channel.id,
    current_user_id,
    channel.circle_id,
    case
      when previous.channel_id = channel.id
        and previous.last_seen_at > now() - public.voice_state_ttl()
      then previous.joined_at
      else now()
    end,
    now()
  );
end;
$$;

create or replace function public.update_voice_state(
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
  state public.voice_states%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  delete from public.voice_states vs
  where vs.user_id = current_user_id
    and vs.last_seen_at <= now() - public.voice_state_ttl();

  select vs.*
  into state
  from public.voice_states vs
  where vs.user_id = current_user_id
  for update;

  if state.channel_id is null then
    return false;
  end if;

  if not public.current_user_has_channel_permission(
    state.channel_id,
    'connect_voice'
  ) then
    delete from public.voice_states vs where vs.user_id = current_user_id;
    return false;
  end if;

  update public.voice_states vs
  set
    last_seen_at = now(),
    self_mute = coalesce(target_self_mute, false),
    self_deaf = coalesce(target_self_deaf, false),
    video = coalesce(target_video, false),
    screen = coalesce(target_screen, false)
  where vs.user_id = current_user_id;

  return true;
end;
$$;

create or replace function public.leave_voice_state()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  delete from public.voice_states vs where vs.user_id = auth.uid();
end;
$$;

-- Who is connected to the circle's voice channels the caller can see.
create or replace function public.list_voice_states(
  target_circle_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.is_current_user_circle_member(target_circle_id) then
    raise exception 'Circle not found' using errcode = '42501';
  end if;

  -- Members who stopped sending heartbeats left.
  delete from public.voice_states vs
  where vs.circle_id = target_circle_id
    and vs.last_seen_at <= now() - public.voice_state_ttl();

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'channel_id', vs.channel_id,
        'circle_id', vs.circle_id,
        'user_id', vs.user_id,
        'joined_at', vs.joined_at,
        'last_seen_at', vs.last_seen_at,
        'self_mute', vs.self_mute,
        'self_deaf', vs.self_deaf,
        'video', vs.video,
        'screen', vs.screen,
        'profile', jsonb_build_object(
          'id', p.id,
          'username', p.username,
          'display_name', p.display_name,
          'avatar_url', p.avatar_url
        ),
        'nickname', cm.nickname,
        'role_color', (
          select r.color
          from public.circle_member_roles mr
          join public.circle_roles r on r.id = mr.role_id
          where mr.circle_id = vs.circle_id
            and mr.user_id = vs.user_id
            and r.color is not null
          order by r.position desc
          limit 1
        )
      )
      order by vs.joined_at, vs.user_id
    )
    from public.voice_states vs
    join public.profiles p on p.id = vs.user_id
    join public.circle_members cm
      on cm.circle_id = vs.circle_id
      and cm.user_id = vs.user_id
    where vs.circle_id = target_circle_id
      and vs.last_seen_at > now() - public.voice_state_ttl()
      and public.current_user_has_channel_permission(
        vs.channel_id,
        'view_channel'
      )
  ), '[]'::jsonb);
end;
$$;

-- Asked by the livekit-token Edge Function as the caller: null unless they
-- may connect to the voice channel.
create or replace function public.can_current_user_connect_voice(
  target_channel_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
begin
  if auth.uid() is null then
    return null;
  end if;

  select cc.*
  into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel.id is null
    or channel.kind <> 'voice'
    or not public.current_user_has_channel_permission(
      channel.id,
      'connect_voice'
    )
  then
    return null;
  end if;

  return jsonb_build_object(
    'channel_id', channel.id,
    'channel_name', channel.name,
    'circle_id', channel.circle_id,
    'display_name', (
      select coalesce(
        nullif(trim(cm.nickname), ''),
        nullif(trim(p.display_name), ''),
        p.username
      )
      from public.profiles p
      left join public.circle_members cm
        on cm.circle_id = channel.circle_id
        and cm.user_id = p.id
      where p.id = auth.uid()
    )
  );
end;
$$;


revoke execute on function public.check_channel_message_send() from public;
revoke execute on function public.check_channel_message_send() from anon;
revoke execute on function public.check_channel_message_send() from authenticated;

revoke execute on function public.join_voice_state(uuid) from public;
revoke execute on function public.join_voice_state(uuid) from anon;
revoke execute on function public.update_voice_state(boolean, boolean, boolean, boolean) from public;
revoke execute on function public.update_voice_state(boolean, boolean, boolean, boolean) from anon;
revoke execute on function public.leave_voice_state() from public;
revoke execute on function public.leave_voice_state() from anon;
revoke execute on function public.list_voice_states(uuid) from public;
revoke execute on function public.list_voice_states(uuid) from anon;
revoke execute on function public.can_current_user_connect_voice(uuid) from public;
revoke execute on function public.can_current_user_connect_voice(uuid) from anon;

grant execute on function public.create_circle_channel(uuid, text, uuid, text) to authenticated;
grant execute on function public.join_voice_state(uuid) to authenticated;
grant execute on function public.update_voice_state(boolean, boolean, boolean, boolean) to authenticated;
grant execute on function public.leave_voice_state() to authenticated;
grant execute on function public.list_voice_states(uuid) to authenticated;
grant execute on function public.can_current_user_connect_voice(uuid) to authenticated;
