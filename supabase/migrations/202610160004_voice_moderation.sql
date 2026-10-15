-- Voice moderation: server mute and deafen, disconnecting and moving
-- members between voice channels, and a user limit per voice channel.
--
-- * Three new permissions: mute_members (1 << 17), deafen_members
--   (1 << 18) and move_members (1 << 19). Roles that could time members
--   out get all three, so existing moderators keep moderating.
-- * circle_members.voice_server_mute / voice_server_deaf hold a member's
--   server mute and deafen, so leaving and rejoining voice keeps them;
--   voice_states.server_mute / server_deaf mirror them for whoever is
--   connected, so clients see the change through Realtime. A server-muted
--   (or deafened) member's LiveKit token cannot publish their microphone;
--   the livekit-token function also updates a connected participant's
--   permissions when asked by a moderator (enforce). Deafening also stops
--   them hearing others, which their client does.
-- * set_voice_server_mute / set_voice_server_deaf(circle, user, on): need
--   the permission and, for anyone but yourself, a higher rank than the
--   member (the owner can't be targeted by others).
-- * disconnect_voice_member(circle, user) and move_voice_member(circle,
--   user, channel): need move_members (and the same rank rule). Moving
--   needs the member and the mover to be able to connect to the
--   destination, and ignores its user limit. A disconnect leaves a
--   voice_disconnects row, so the member's client stops rather than
--   rejoining on its next heartbeat; joining again on purpose clears it.
-- * circle_channels.user_limit (0 = unlimited, 1–99), set with
--   set_voice_channel_user_limit and listed by
--   list_voice_channel_user_limits. join_voice_state and
--   can_current_user_connect_voice refuse a full channel unless the
--   caller has move_members.
-- * get_own_voice_state(): the caller's voice state (channel, its
--   conversation and name, server flags) and whether a moderator
--   disconnected them, for their client to follow moves and mutes.
-- * voice_enforcement_state(channel, user): asked by the livekit-token
--   function as a moderator, to make the LiveKit room match the database.
-- * Audit: member_voice_mute, member_voice_unmute, member_voice_deafen,
--   member_voice_undeafen, member_voice_disconnect, member_voice_move,
--   channel_user_limit_update.

-- Same as 202610140004_bans_and_timeouts, plus the voice moderation bits.
create or replace function public.circle_permission_bit(permission_name text)
returns bigint
language plpgsql
immutable
set search_path = public
as $$
begin
  return case permission_name
    when 'view_channel' then 1::bigint
    when 'send_messages' then 2::bigint
    when 'manage_messages' then 4::bigint
    when 'manage_channels' then 8::bigint
    when 'manage_roles' then 16::bigint
    when 'kick_members' then 32::bigint
    when 'create_invites' then 64::bigint
    when 'manage_nicknames' then 128::bigint
    when 'mention_everyone' then 256::bigint
    when 'manage_events' then 512::bigint
    when 'manage_emojis' then 1024::bigint
    when 'manage_webhooks' then 2048::bigint
    when 'view_audit_log' then 4096::bigint
    when 'connect_voice' then 8192::bigint
    when 'administrator' then 16384::bigint
    when 'ban_members' then 32768::bigint
    when 'moderate_members' then 65536::bigint
    when 'mute_members' then 131072::bigint
    when 'deafen_members' then 262144::bigint
    when 'move_members' then 524288::bigint
    else null
  end;
end;
$$;

create or replace function public.circle_all_permissions()
returns bigint
language sql
immutable
set search_path = public
as $$
  select 1048575::bigint;
$$;

alter table public.circle_roles
  drop constraint if exists circle_roles_permissions_range;

alter table public.circle_roles
  add constraint circle_roles_permissions_range check (
    permissions >= 0 and permissions <= 1048575
  );

update public.circle_roles
set permissions = permissions | 131072 | 262144 | 524288
where permissions & 65536 <> 0;

alter table public.circle_members
  add column if not exists voice_server_mute boolean not null default false,
  add column if not exists voice_server_deaf boolean not null default false;

alter table public.voice_states
  add column if not exists server_mute boolean not null default false,
  add column if not exists server_deaf boolean not null default false;

alter table public.circle_channels
  add column if not exists user_limit integer not null default 0;

alter table public.circle_channels
  drop constraint if exists circle_channels_user_limit_range;

alter table public.circle_channels
  add constraint circle_channels_user_limit_range check (
    user_limit between 0 and 99
  );

-- Members a moderator disconnected from voice, until they join again.
create table if not exists public.voice_disconnects (
  user_id uuid primary key,
  circle_id uuid not null,
  channel_id uuid,
  disconnected_by uuid references public.profiles(id) on delete set null,
  disconnected_at timestamptz not null default now(),
  constraint voice_disconnects_member_fkey
    foreign key (circle_id, user_id)
    references public.circle_members(circle_id, user_id)
    on delete cascade
);

alter table public.voice_disconnects enable row level security;

revoke all on public.voice_disconnects from anon;
revoke all on public.voice_disconnects from authenticated;

-- Whether the caller may use [permission_name] on [target_user_id]'s
-- voice: they need the permission, and a target other than themselves
-- must rank below them (never the owner).
create or replace function public.can_moderate_voice_member(
  target_circle_id uuid,
  target_user_id uuid,
  permission_name text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null
    or not public.current_user_has_circle_permission(
      target_circle_id,
      permission_name
    )
    or not exists (
      select 1
      from public.circle_members cm
      where cm.circle_id = target_circle_id
        and cm.user_id = target_user_id
    )
  then
    return false;
  end if;

  if target_user_id = current_user_id then
    return true;
  end if;

  if exists (
    select 1
    from public.circles c
    where c.id = target_circle_id
      and c.owner_id = target_user_id
  ) then
    return false;
  end if;

  return public.circle_member_rank(target_circle_id, target_user_id)
    < public.circle_member_rank(target_circle_id, current_user_id);
end;
$$;

-- Whether [channel] is full for the caller: its user limit counts
-- everyone else connected; move_members skips it, and so does already
-- being in it.
create or replace function public.voice_channel_is_full_for_current_user(
  target_channel_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
begin
  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel.id is null or coalesce(channel.user_limit, 0) <= 0 then
    return false;
  end if;

  if public.current_user_has_channel_permission(channel.id, 'move_members') then
    return false;
  end if;

  -- Already in it (moved there, or reconnecting).
  if exists (
    select 1
    from public.voice_states vs
    where vs.channel_id = channel.id
      and vs.user_id = auth.uid()
      and vs.last_seen_at > now() - public.voice_state_ttl()
  ) then
    return false;
  end if;

  return (
    select count(*)
    from public.voice_states vs
    where vs.channel_id = channel.id
      and vs.user_id <> auth.uid()
      and vs.last_seen_at > now() - public.voice_state_ttl()
  ) >= channel.user_limit;
end;
$$;

-- Same as 202610130028_voice_channels, plus the user limit, the member's
-- server mute and deafen, and clearing a moderator's disconnect.
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
  member public.circle_members%rowtype;
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

  -- Joins to one limited channel queue up, so two can't take the last
  -- place.
  if channel.user_limit > 0 then
    perform pg_advisory_xact_lock(
      hashtextextended('voice_channel:' || channel.id::text, 0)
    );
  end if;

  if public.voice_channel_is_full_for_current_user(channel.id) then
    raise exception 'This voice channel is full' using errcode = '53300';
  end if;

  select vs.*
  into previous
  from public.voice_states vs
  where vs.user_id = current_user_id
  for update;

  select cm.*
  into member
  from public.circle_members cm
  where cm.circle_id = channel.circle_id
    and cm.user_id = current_user_id;

  delete from public.voice_states vs where vs.user_id = current_user_id;
  delete from public.voice_disconnects vd where vd.user_id = current_user_id;

  insert into public.voice_states (
    channel_id,
    user_id,
    circle_id,
    joined_at,
    last_seen_at,
    server_mute,
    server_deaf
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
    now(),
    coalesce(member.voice_server_mute, false),
    coalesce(member.voice_server_deaf, false)
  );
end;
$$;

-- Same as 202610130028_voice_channels, plus server mute and deafen.
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
        'server_mute', vs.server_mute,
        'server_deaf', vs.server_deaf,
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

-- Same as 202610130028_voice_channels, plus whether the channel is full
-- for the caller and their server mute and deafen, which shape the token.
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
  member public.circle_members%rowtype;
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

  select cm.*
  into member
  from public.circle_members cm
  where cm.circle_id = channel.circle_id
    and cm.user_id = auth.uid();

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
    ),
    'full', public.voice_channel_is_full_for_current_user(channel.id),
    'server_mute', coalesce(member.voice_server_mute, false),
    'server_deaf', coalesce(member.voice_server_deaf, false)
  );
end;
$$;

-- The caller's voice state, for their client to follow moves, server
-- mutes and disconnects.
create or replace function public.get_own_voice_state()
returns jsonb
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

  return jsonb_build_object(
    'state', (
      select jsonb_build_object(
        'channel_id', vs.channel_id,
        'circle_id', vs.circle_id,
        'conversation_id', cc.conversation_id,
        'channel_name', cc.name,
        'server_mute', vs.server_mute,
        'server_deaf', vs.server_deaf
      )
      from public.voice_states vs
      join public.circle_channels cc on cc.id = vs.channel_id
      where vs.user_id = current_user_id
        and vs.last_seen_at > now() - public.voice_state_ttl()
    ),
    'disconnected', exists (
      select 1
      from public.voice_disconnects vd
      where vd.user_id = current_user_id
    )
  );
end;
$$;

create or replace function public.set_voice_server_mute(
  target_circle_id uuid,
  target_user_id uuid,
  muted boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  was_muted boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.can_moderate_voice_member(
    target_circle_id,
    target_user_id,
    'mute_members'
  ) then
    raise exception 'You cannot server mute this member' using errcode = '42501';
  end if;

  select cm.voice_server_mute into was_muted
  from public.circle_members cm
  where cm.circle_id = target_circle_id
    and cm.user_id = target_user_id
  for update;

  if was_muted is not distinct from coalesce(muted, false) then
    return;
  end if;

  update public.circle_members cm
  set voice_server_mute = coalesce(muted, false)
  where cm.circle_id = target_circle_id
    and cm.user_id = target_user_id;

  update public.voice_states vs
  set server_mute = coalesce(muted, false)
  where vs.circle_id = target_circle_id
    and vs.user_id = target_user_id;

  perform public.write_circle_audit(
    target_circle_id,
    case when muted then 'member_voice_mute' else 'member_voice_unmute' end,
    'member',
    target_user_id,
    public.circle_member_label(target_circle_id, target_user_id),
    '{}'::jsonb
  );
end;
$$;

create or replace function public.set_voice_server_deaf(
  target_circle_id uuid,
  target_user_id uuid,
  deafened boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  was_deafened boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.can_moderate_voice_member(
    target_circle_id,
    target_user_id,
    'deafen_members'
  ) then
    raise exception 'You cannot server deafen this member'
      using errcode = '42501';
  end if;

  select cm.voice_server_deaf into was_deafened
  from public.circle_members cm
  where cm.circle_id = target_circle_id
    and cm.user_id = target_user_id
  for update;

  if was_deafened is not distinct from coalesce(deafened, false) then
    return;
  end if;

  update public.circle_members cm
  set voice_server_deaf = coalesce(deafened, false)
  where cm.circle_id = target_circle_id
    and cm.user_id = target_user_id;

  update public.voice_states vs
  set server_deaf = coalesce(deafened, false)
  where vs.circle_id = target_circle_id
    and vs.user_id = target_user_id;

  perform public.write_circle_audit(
    target_circle_id,
    case
      when deafened then 'member_voice_deafen'
      else 'member_voice_undeafen'
    end,
    'member',
    target_user_id,
    public.circle_member_label(target_circle_id, target_user_id),
    '{}'::jsonb
  );
end;
$$;

-- Removes the member from the circle's voice channels. Returns the channel
-- they were in, for the client to have the LiveKit room follow.
create or replace function public.disconnect_voice_member(
  target_circle_id uuid,
  target_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  state public.voice_states%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.can_moderate_voice_member(
    target_circle_id,
    target_user_id,
    'move_members'
  ) then
    raise exception 'You cannot disconnect this member' using errcode = '42501';
  end if;

  delete from public.voice_states vs
  where vs.circle_id = target_circle_id
    and vs.user_id = target_user_id
  returning vs.* into state;

  if state.channel_id is null then
    return null;
  end if;

  insert into public.voice_disconnects (
    user_id,
    circle_id,
    channel_id,
    disconnected_by,
    disconnected_at
  )
  values (
    target_user_id,
    target_circle_id,
    state.channel_id,
    auth.uid(),
    now()
  )
  on conflict (user_id) do update
  set circle_id = excluded.circle_id,
      channel_id = excluded.channel_id,
      disconnected_by = excluded.disconnected_by,
      disconnected_at = excluded.disconnected_at;

  perform public.write_circle_audit(
    target_circle_id,
    'member_voice_disconnect',
    'member',
    target_user_id,
    public.circle_member_label(target_circle_id, target_user_id),
    jsonb_build_object(
      'channel_id', state.channel_id,
      'channel_name', (
        select cc.name from public.circle_channels cc
        where cc.id = state.channel_id
      )
    )
  );

  return state.channel_id;
end;
$$;

-- Moves a connected member to another voice channel of the circle, past
-- its user limit. Returns the channel they were in.
create or replace function public.move_voice_member(
  target_circle_id uuid,
  target_user_id uuid,
  target_channel_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  state public.voice_states%rowtype;
  destination public.circle_channels%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.can_moderate_voice_member(
    target_circle_id,
    target_user_id,
    'move_members'
  ) then
    raise exception 'You cannot move this member' using errcode = '42501';
  end if;

  select cc.* into destination
  from public.circle_channels cc
  where cc.id = target_channel_id
    and cc.circle_id = target_circle_id;

  if destination.id is null
    or destination.kind <> 'voice'
    or not public.current_user_has_channel_permission(
      destination.id,
      'connect_voice'
    )
    or public.circle_channel_permissions(destination.id, target_user_id)
      & public.circle_permission_bit('connect_voice') = 0
  then
    raise exception 'They cannot be moved to that channel'
      using errcode = '42501';
  end if;

  select vs.* into state
  from public.voice_states vs
  where vs.circle_id = target_circle_id
    and vs.user_id = target_user_id
    and vs.last_seen_at > now() - public.voice_state_ttl()
  for update;

  if state.channel_id is null then
    raise exception 'They are not in a voice channel' using errcode = 'P0002';
  end if;

  if state.channel_id = destination.id then
    return state.channel_id;
  end if;

  update public.voice_states vs
  set channel_id = destination.id,
      joined_at = now()
  where vs.user_id = target_user_id;

  perform public.write_circle_audit(
    target_circle_id,
    'member_voice_move',
    'member',
    target_user_id,
    public.circle_member_label(target_circle_id, target_user_id),
    jsonb_build_object(
      'from_channel_id', state.channel_id,
      'from_channel_name', (
        select cc.name from public.circle_channels cc
        where cc.id = state.channel_id
      ),
      'channel_id', destination.id,
      'channel_name', destination.name
    )
  );

  return state.channel_id;
end;
$$;

-- What a voice channel's LiveKit room should allow [target_user_id]:
-- asked by the livekit-token function for a moderator. Null unless the
-- caller can mute, deafen or move members of the channel's circle.
create or replace function public.voice_enforcement_state(
  target_channel_id uuid,
  target_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
  state public.voice_states%rowtype;
begin
  if auth.uid() is null then
    return null;
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id
    and cc.kind = 'voice';

  if channel.id is null
    or not (
      public.current_user_has_circle_permission(channel.circle_id, 'mute_members')
      or public.current_user_has_circle_permission(channel.circle_id, 'deafen_members')
      or public.current_user_has_circle_permission(channel.circle_id, 'move_members')
    )
  then
    return null;
  end if;

  select vs.* into state
  from public.voice_states vs
  where vs.channel_id = channel.id
    and vs.user_id = target_user_id
    and vs.last_seen_at > now() - public.voice_state_ttl();

  return jsonb_build_object(
    'channel_id', channel.id,
    'user_id', target_user_id,
    'in_channel', state.user_id is not null,
    'server_mute', coalesce(state.server_mute, false),
    'server_deaf', coalesce(state.server_deaf, false)
  );
end;
$$;

create or replace function public.set_voice_channel_user_limit(
  target_channel_id uuid,
  user_limit integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  channel public.circle_channels%rowtype;
  new_limit integer := coalesce(user_limit, 0);
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if new_limit < 0 or new_limit > 99 then
    raise exception 'User limit must be between 0 and 99'
      using errcode = '22023';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel.id is null
    or not public.current_user_has_circle_permission(
      channel.circle_id,
      'manage_channels'
    )
    or not public.current_user_has_channel_permission(
      channel.id,
      'view_channel'
    )
  then
    raise exception 'Only members who can manage channels can change the user limit'
      using errcode = '42501';
  end if;

  if channel.kind <> 'voice' then
    raise exception 'Only voice channels have a user limit'
      using errcode = '22023';
  end if;

  update public.circle_channels cc
  set user_limit = new_limit,
      updated_at = now()
  where cc.id = channel.id
    and cc.user_limit is distinct from new_limit;

  if found then
    perform public.write_circle_audit(
      channel.circle_id,
      'channel_user_limit_update',
      'channel',
      channel.id,
      channel.name,
      jsonb_build_object(
        'user_limit',
        jsonb_build_object('old', channel.user_limit, 'new', new_limit)
      )
    );
  end if;
end;
$$;

-- {channel id: user limit} for the circle's limited voice channels the
-- caller can see.
create or replace function public.list_voice_channel_user_limits(
  target_circle_id uuid
)
returns jsonb
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
    raise exception 'Circle not found' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_object_agg(cc.id::text, cc.user_limit)
    from public.circle_channels cc
    where cc.circle_id = target_circle_id
      and cc.kind = 'voice'
      and cc.user_limit > 0
      and public.current_user_has_channel_permission(cc.id, 'view_channel')
  ), '{}'::jsonb);
end;
$$;

revoke execute on function public.can_moderate_voice_member(uuid, uuid, text) from public;
revoke execute on function public.can_moderate_voice_member(uuid, uuid, text) from anon;
revoke execute on function public.can_moderate_voice_member(uuid, uuid, text) from authenticated;
revoke execute on function public.voice_channel_is_full_for_current_user(uuid) from public;
revoke execute on function public.voice_channel_is_full_for_current_user(uuid) from anon;
revoke execute on function public.voice_channel_is_full_for_current_user(uuid) from authenticated;

revoke execute on function public.join_voice_state(uuid) from public;
revoke execute on function public.join_voice_state(uuid) from anon;
revoke execute on function public.list_voice_states(uuid) from public;
revoke execute on function public.list_voice_states(uuid) from anon;
revoke execute on function public.can_current_user_connect_voice(uuid) from public;
revoke execute on function public.can_current_user_connect_voice(uuid) from anon;
revoke execute on function public.get_own_voice_state() from public;
revoke execute on function public.get_own_voice_state() from anon;
revoke execute on function public.set_voice_server_mute(uuid, uuid, boolean) from public;
revoke execute on function public.set_voice_server_mute(uuid, uuid, boolean) from anon;
revoke execute on function public.set_voice_server_deaf(uuid, uuid, boolean) from public;
revoke execute on function public.set_voice_server_deaf(uuid, uuid, boolean) from anon;
revoke execute on function public.disconnect_voice_member(uuid, uuid) from public;
revoke execute on function public.disconnect_voice_member(uuid, uuid) from anon;
revoke execute on function public.move_voice_member(uuid, uuid, uuid) from public;
revoke execute on function public.move_voice_member(uuid, uuid, uuid) from anon;
revoke execute on function public.voice_enforcement_state(uuid, uuid) from public;
revoke execute on function public.voice_enforcement_state(uuid, uuid) from anon;
revoke execute on function public.set_voice_channel_user_limit(uuid, integer) from public;
revoke execute on function public.set_voice_channel_user_limit(uuid, integer) from anon;
revoke execute on function public.list_voice_channel_user_limits(uuid) from public;
revoke execute on function public.list_voice_channel_user_limits(uuid) from anon;

grant execute on function public.join_voice_state(uuid) to authenticated;
grant execute on function public.list_voice_states(uuid) to authenticated;
grant execute on function public.can_current_user_connect_voice(uuid) to authenticated;
grant execute on function public.get_own_voice_state() to authenticated;
grant execute on function public.set_voice_server_mute(uuid, uuid, boolean) to authenticated;
grant execute on function public.set_voice_server_deaf(uuid, uuid, boolean) to authenticated;
grant execute on function public.disconnect_voice_member(uuid, uuid) to authenticated;
grant execute on function public.move_voice_member(uuid, uuid, uuid) to authenticated;
grant execute on function public.voice_enforcement_state(uuid, uuid) to authenticated;
grant execute on function public.set_voice_channel_user_limit(uuid, integer) to authenticated;
grant execute on function public.list_voice_channel_user_limits(uuid) to authenticated;
