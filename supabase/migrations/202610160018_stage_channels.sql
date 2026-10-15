-- Stage channels: a voice channel kind for talks, where a few speakers
-- talk and everyone else listens.
--
-- * circle_channels.kind takes 'stage' (the check constraint keeps every
--   kind it already allowed, so another migration adding its own kind
--   doesn't lose either), and create_circle_channel creates them.
-- * Stage moderators are members with both mute_members and move_members
--   in the channel (no new permission bit). They start a stage with a
--   topic (start_stage, which also changes the topic of a live one), end
--   it (end_stage), invite members to speak and move speakers back to the
--   audience. A stage whose channel stays empty for a minute ends by
--   itself.
-- * stage_instances: one row per live stage (channel, topic, who started
--   it, when). Viewers of the channel read it; realtime tells clients.
-- * voice_states gets stage_speaker, stage_invited and hand_raised_at.
--   Whoever joins a stage channel is in the audience: their LiveKit
--   token can subscribe but not publish (can_current_user_connect_voice
--   says kind 'stage' and whether they are a speaker). A rejoin within the
--   voice state's 60 seconds keeps the speaker's place.
-- * set_stage_hand_raised(channel, raised): an audience member asks to
--   speak (or stops asking). invite_stage_speaker(channel, user): a
--   moderator makes a member who raised their hand (or themselves) a
--   speaker at once, and invites anyone else, who accepts or declines
--   with respond_stage_invite(channel, accept). set_stage_audience(channel,
--   user): a speaker steps down, or a moderator (outranking them) moves
--   them down.
-- * voice_enforcement_state now covers stage channels and answers for the
--   caller themselves too: the livekit-token function's enforce request
--   then grants or revokes publishing as the database says, so a new
--   speaker can publish without reconnecting. It only ever makes the room
--   match the database, so asking for yourself grants nothing extra.
-- * Stage channels have no user limit; move_voice_member moves people into
--   a stage's audience. Audit: stage_start, stage_update, stage_end.

-- circle_channels.kind also takes 'stage', keeping every kind allowed now.
do $$
declare
  definition text;
  kinds text[];
begin
  select pg_get_constraintdef(c.oid)
  into definition
  from pg_constraint c
  where c.conrelid = 'public.circle_channels'::regclass
    and c.conname = 'circle_channels_kind_check';

  select coalesce(array_agg(distinct m[1]), array[]::text[])
  into kinds
  from regexp_matches(coalesce(definition, ''), '''([a-z_]+)''', 'g') as m;

  kinds := kinds || array['text', 'voice', 'forum', 'stage'];

  alter table public.circle_channels
    drop constraint if exists circle_channels_kind_check;
  execute format(
    'alter table public.circle_channels add constraint circle_channels_kind_check check (kind in (%s))',
    (select string_agg(quote_literal(k), ', ' order by k) from (select distinct unnest(kinds) as k) as distinct_kinds)
  );
end $$;

alter table public.voice_states
  add column if not exists stage_speaker boolean not null default false,
  add column if not exists stage_invited boolean not null default false,
  add column if not exists hand_raised_at timestamptz;

create table if not exists public.stage_instances (
  channel_id uuid primary key,
  circle_id uuid not null,
  topic text not null,
  started_by uuid references public.profiles(id) on delete set null,
  started_at timestamptz not null default now(),
  constraint stage_instances_topic_length check (
    char_length(btrim(topic)) between 1 and 120
  ),
  constraint stage_instances_channel_fkey
    foreign key (channel_id, circle_id)
    references public.circle_channels(id, circle_id)
    on delete cascade
);

create index if not exists stage_instances_circle_idx
  on public.stage_instances (circle_id);

-- Realtime matches DELETE events against the old row, so keep the circle
-- in it.
alter table public.stage_instances replica identity full;

alter table public.stage_instances enable row level security;

revoke insert, update, delete, truncate on public.stage_instances from anon;
revoke insert, update, delete, truncate on public.stage_instances from authenticated;

drop policy if exists stage_instances_select_viewer on public.stage_instances;
create policy stage_instances_select_viewer
  on public.stage_instances for select
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
      and tablename = 'stage_instances'
  ) then
    alter publication supabase_realtime add table public.stage_instances;
  end if;
end $$;

-- Whether the caller moderates the stage channel: mute_members and
-- move_members there.
create or replace function public.is_current_user_stage_moderator(
  target_channel_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
    and exists (
      select 1 from public.circle_channels cc
      where cc.id = target_channel_id
        and cc.kind = 'stage'
    )
    and public.current_user_has_channel_permission(target_channel_id, 'mute_members')
    and public.current_user_has_channel_permission(target_channel_id, 'move_members');
$$;

-- Same as 202610130028_voice_channels, but stage channels can be created
-- too.
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

  if channel_kind not in ('text', 'forum', 'voice', 'stage') then
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

-- Same as 202610160004_voice_moderation, but stage channels can be joined
-- too, and a rejoin within the TTL keeps the stage role.
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
  rejoining boolean;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cc.*
  into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel.id is null
    or channel.kind not in ('voice', 'stage')
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

  rejoining := previous.channel_id = channel.id
    and previous.last_seen_at > now() - public.voice_state_ttl();

  delete from public.voice_states vs where vs.user_id = current_user_id;
  delete from public.voice_disconnects vd where vd.user_id = current_user_id;

  insert into public.voice_states (
    channel_id,
    user_id,
    circle_id,
    joined_at,
    last_seen_at,
    server_mute,
    server_deaf,
    stage_speaker,
    stage_invited,
    hand_raised_at
  )
  values (
    channel.id,
    current_user_id,
    channel.circle_id,
    case when rejoining then previous.joined_at else now() end,
    now(),
    coalesce(member.voice_server_mute, false),
    coalesce(member.voice_server_deaf, false),
    channel.kind = 'stage' and rejoining and coalesce(previous.stage_speaker, false),
    channel.kind = 'stage' and rejoining and coalesce(previous.stage_invited, false),
    case
      when channel.kind = 'stage' and rejoining then previous.hand_raised_at
    end
  );
end;
$$;

-- Same as 202610160004_voice_moderation, plus the stage role and raised
-- hand.
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
        'stage_speaker', vs.stage_speaker,
        'stage_invited', vs.stage_invited,
        'hand_raised_at', vs.hand_raised_at,
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

-- Same as 202610160004_voice_moderation, but stage channels are accepted
-- and say whether the caller is one of the speakers, which decides
-- whether their token may publish.
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
    or channel.kind not in ('voice', 'stage')
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
    'server_deaf', coalesce(member.voice_server_deaf, false),
    'kind', channel.kind,
    'stage_speaker', channel.kind = 'stage' and exists (
      select 1
      from public.voice_states vs
      where vs.channel_id = channel.id
        and vs.user_id = auth.uid()
        and vs.stage_speaker
        and vs.last_seen_at > now() - public.voice_state_ttl()
    )
  );
end;
$$;

-- Same as 202610160004_voice_moderation, plus the channel's kind and the
-- caller's stage role.
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
        'channel_kind', cc.kind,
        'server_mute', vs.server_mute,
        'server_deaf', vs.server_deaf,
        'stage_speaker', vs.stage_speaker,
        'stage_invited', vs.stage_invited,
        'hand_raised_at', vs.hand_raised_at
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

-- Same as 202610160004_voice_moderation, but members can be moved into a
-- stage channel (as audience) too.
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
    or destination.kind not in ('voice', 'stage')
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
      joined_at = now(),
      stage_speaker = false,
      stage_invited = false,
      hand_raised_at = null
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

-- Same as 202610160004_voice_moderation, but stage channels are covered
-- (with whether the member is a speaker), and members may ask about
-- themselves: the answer only makes the room match the database.
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
    and cc.kind in ('voice', 'stage');

  if channel.id is null
    or not (
      (
        target_user_id = auth.uid()
        and public.is_current_user_circle_member(channel.circle_id)
      )
      or public.current_user_has_circle_permission(channel.circle_id, 'mute_members')
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
    'server_deaf', coalesce(state.server_deaf, false),
    'stage', channel.kind = 'stage',
    'stage_speaker', coalesce(state.stage_speaker, false)
  );
end;
$$;

-- The circle's live stages the caller can see, by channel id. Stages whose
-- channel has been empty for a minute end here.
create or replace function public.list_stage_instances(
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

  delete from public.stage_instances si
  where si.circle_id = target_circle_id
    and si.started_at <= now() - public.voice_state_ttl()
    and not exists (
      select 1
      from public.voice_states vs
      where vs.channel_id = si.channel_id
        and vs.last_seen_at > now() - public.voice_state_ttl()
    );

  return coalesce((
    select jsonb_object_agg(
      si.channel_id::text,
      jsonb_build_object(
        'channel_id', si.channel_id,
        'circle_id', si.circle_id,
        'topic', si.topic,
        'started_by', si.started_by,
        'started_at', si.started_at
      )
    )
    from public.stage_instances si
    where si.circle_id = target_circle_id
      and public.current_user_has_channel_permission(si.channel_id, 'view_channel')
  ), '{}'::jsonb);
end;
$$;

-- Starts a stage in [target_channel_id] with [stage_topic], or changes the
-- topic of the live one. The moderator becomes a speaker when connected.
create or replace function public.start_stage(
  target_channel_id uuid,
  stage_topic text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
  live public.stage_instances%rowtype;
  trimmed_topic text := btrim(coalesce(stage_topic, ''));
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.is_current_user_stage_moderator(target_channel_id) then
    raise exception 'Only stage moderators can start a stage'
      using errcode = '42501';
  end if;

  if char_length(trimmed_topic) not between 1 and 120 then
    raise exception 'The topic must be between 1 and 120 characters'
      using errcode = '22023';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  select si.* into live
  from public.stage_instances si
  where si.channel_id = channel.id
  for update;

  if live.channel_id is not null then
    if live.topic = trimmed_topic then
      return;
    end if;
    update public.stage_instances si
    set topic = trimmed_topic
    where si.channel_id = channel.id;

    perform public.write_circle_audit(
      channel.circle_id,
      'stage_update',
      'channel',
      channel.id,
      channel.name,
      jsonb_build_object(
        'topic',
        jsonb_build_object('old', live.topic, 'new', trimmed_topic)
      )
    );
    return;
  end if;

  insert into public.stage_instances (
    channel_id,
    circle_id,
    topic,
    started_by,
    started_at
  )
  values (channel.id, channel.circle_id, trimmed_topic, auth.uid(), now());

  update public.voice_states vs
  set stage_speaker = true,
      stage_invited = false,
      hand_raised_at = null
  where vs.channel_id = channel.id
    and vs.user_id = auth.uid();

  perform public.write_circle_audit(
    channel.circle_id,
    'stage_start',
    'channel',
    channel.id,
    channel.name,
    jsonb_build_object('topic', trimmed_topic)
  );
end;
$$;

-- Ends the live stage: everyone goes back to the audience. Returns who was
-- speaking, for the client to have the room follow.
create or replace function public.end_stage(target_channel_id uuid)
returns uuid[]
language plpgsql
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
  ended public.stage_instances%rowtype;
  speakers uuid[];
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.is_current_user_stage_moderator(target_channel_id) then
    raise exception 'Only stage moderators can end a stage'
      using errcode = '42501';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  delete from public.stage_instances si
  where si.channel_id = channel.id
  returning si.* into ended;

  select coalesce(array_agg(vs.user_id), array[]::uuid[])
  into speakers
  from public.voice_states vs
  where vs.channel_id = channel.id
    and vs.stage_speaker;

  update public.voice_states vs
  set stage_speaker = false,
      stage_invited = false,
      hand_raised_at = null
  where vs.channel_id = channel.id
    and (vs.stage_speaker or vs.stage_invited or vs.hand_raised_at is not null);

  if ended.channel_id is not null then
    perform public.write_circle_audit(
      channel.circle_id,
      'stage_end',
      'channel',
      channel.id,
      channel.name,
      jsonb_build_object('topic', ended.topic)
    );
  end if;

  return speakers;
end;
$$;

-- The caller's live voice state in the stage channel, locked; raises when
-- they are not in it.
create or replace function public.stage_state_for_update(
  target_channel_id uuid,
  target_user_id uuid
)
returns public.voice_states
language plpgsql
security definer
set search_path = public
as $$
declare
  state public.voice_states%rowtype;
begin
  select vs.* into state
  from public.voice_states vs
  join public.circle_channels cc on cc.id = vs.channel_id
  where vs.channel_id = target_channel_id
    and vs.user_id = target_user_id
    and cc.kind = 'stage'
    and vs.last_seen_at > now() - public.voice_state_ttl()
  for update of vs;

  if state.user_id is null then
    raise exception 'They are not on this stage' using errcode = 'P0002';
  end if;

  return state;
end;
$$;

-- Asks to speak (or stops asking) while a stage is live.
create or replace function public.set_stage_hand_raised(
  target_channel_id uuid,
  raised boolean
)
returns void
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

  state := public.stage_state_for_update(target_channel_id, auth.uid());

  if coalesce(raised, false) then
    if state.stage_speaker then
      return;
    end if;
    if not exists (
      select 1 from public.stage_instances si
      where si.channel_id = target_channel_id
    ) then
      raise exception 'No stage is live here' using errcode = '55000';
    end if;
    update public.voice_states vs
    set hand_raised_at = coalesce(vs.hand_raised_at, now())
    where vs.user_id = auth.uid();
  else
    update public.voice_states vs
    set hand_raised_at = null
    where vs.user_id = auth.uid();
  end if;
end;
$$;

-- A moderator invites [target_user_id] to speak. Members who raised their
-- hand, and the moderator themselves, become speakers at once (true);
-- anyone else is invited and accepts or declines (false).
create or replace function public.invite_stage_speaker(
  target_channel_id uuid,
  target_user_id uuid
)
returns boolean
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

  if not public.is_current_user_stage_moderator(target_channel_id) then
    raise exception 'Only stage moderators can invite speakers'
      using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.stage_instances si
    where si.channel_id = target_channel_id
  ) then
    raise exception 'No stage is live here' using errcode = '55000';
  end if;

  state := public.stage_state_for_update(target_channel_id, target_user_id);

  if state.stage_speaker then
    return true;
  end if;

  if target_user_id = auth.uid() or state.hand_raised_at is not null then
    update public.voice_states vs
    set stage_speaker = true,
        stage_invited = false,
        hand_raised_at = null
    where vs.user_id = target_user_id;
    return true;
  end if;

  update public.voice_states vs
  set stage_invited = true
  where vs.user_id = target_user_id;
  return false;
end;
$$;

-- Accepts (becoming a speaker) or declines an invitation to speak.
create or replace function public.respond_stage_invite(
  target_channel_id uuid,
  accept boolean
)
returns boolean
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

  state := public.stage_state_for_update(target_channel_id, auth.uid());

  if not state.stage_invited then
    return state.stage_speaker;
  end if;

  update public.voice_states vs
  set stage_speaker = coalesce(accept, false),
      stage_invited = false,
      hand_raised_at = null
  where vs.user_id = auth.uid();

  return coalesce(accept, false);
end;
$$;

-- Moves a speaker back to the audience: themselves, or anyone a moderator
-- outranks.
create or replace function public.set_stage_audience(
  target_channel_id uuid,
  target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if target_user_id <> auth.uid()
    and not (
      public.is_current_user_stage_moderator(target_channel_id)
      and public.can_moderate_voice_member(
        channel.circle_id,
        target_user_id,
        'move_members'
      )
    )
  then
    raise exception 'You cannot move this speaker to the audience'
      using errcode = '42501';
  end if;

  perform public.stage_state_for_update(target_channel_id, target_user_id);

  update public.voice_states vs
  set stage_speaker = false,
      stage_invited = false,
      hand_raised_at = null
  where vs.user_id = target_user_id;
end;
$$;

revoke execute on function public.is_current_user_stage_moderator(uuid) from public;
revoke execute on function public.is_current_user_stage_moderator(uuid) from anon;
revoke execute on function public.is_current_user_stage_moderator(uuid) from authenticated;
revoke execute on function public.stage_state_for_update(uuid, uuid) from public;
revoke execute on function public.stage_state_for_update(uuid, uuid) from anon;
revoke execute on function public.stage_state_for_update(uuid, uuid) from authenticated;

revoke execute on function public.join_voice_state(uuid) from public;
revoke execute on function public.join_voice_state(uuid) from anon;
revoke execute on function public.list_voice_states(uuid) from public;
revoke execute on function public.list_voice_states(uuid) from anon;
revoke execute on function public.can_current_user_connect_voice(uuid) from public;
revoke execute on function public.can_current_user_connect_voice(uuid) from anon;
revoke execute on function public.get_own_voice_state() from public;
revoke execute on function public.get_own_voice_state() from anon;
revoke execute on function public.move_voice_member(uuid, uuid, uuid) from public;
revoke execute on function public.move_voice_member(uuid, uuid, uuid) from anon;
revoke execute on function public.voice_enforcement_state(uuid, uuid) from public;
revoke execute on function public.voice_enforcement_state(uuid, uuid) from anon;
revoke execute on function public.list_stage_instances(uuid) from public;
revoke execute on function public.list_stage_instances(uuid) from anon;
revoke execute on function public.start_stage(uuid, text) from public;
revoke execute on function public.start_stage(uuid, text) from anon;
revoke execute on function public.end_stage(uuid) from public;
revoke execute on function public.end_stage(uuid) from anon;
revoke execute on function public.set_stage_hand_raised(uuid, boolean) from public;
revoke execute on function public.set_stage_hand_raised(uuid, boolean) from anon;
revoke execute on function public.invite_stage_speaker(uuid, uuid) from public;
revoke execute on function public.invite_stage_speaker(uuid, uuid) from anon;
revoke execute on function public.respond_stage_invite(uuid, boolean) from public;
revoke execute on function public.respond_stage_invite(uuid, boolean) from anon;
revoke execute on function public.set_stage_audience(uuid, uuid) from public;
revoke execute on function public.set_stage_audience(uuid, uuid) from anon;

grant execute on function public.create_circle_channel(uuid, text, uuid, text) to authenticated;
grant execute on function public.join_voice_state(uuid) to authenticated;
grant execute on function public.list_voice_states(uuid) to authenticated;
grant execute on function public.can_current_user_connect_voice(uuid) to authenticated;
grant execute on function public.get_own_voice_state() to authenticated;
grant execute on function public.move_voice_member(uuid, uuid, uuid) to authenticated;
grant execute on function public.voice_enforcement_state(uuid, uuid) to authenticated;
grant execute on function public.list_stage_instances(uuid) to authenticated;
grant execute on function public.start_stage(uuid, text) to authenticated;
grant execute on function public.end_stage(uuid) to authenticated;
grant execute on function public.set_stage_hand_raised(uuid, boolean) to authenticated;
grant execute on function public.invite_stage_speaker(uuid, uuid) to authenticated;
grant execute on function public.respond_stage_invite(uuid, boolean) to authenticated;
grant execute on function public.set_stage_audience(uuid, uuid) to authenticated;
