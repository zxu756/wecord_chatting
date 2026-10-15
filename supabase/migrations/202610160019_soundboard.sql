-- Soundboard: short sounds a circle uploads and members play into its
-- voice channels for everyone there to hear.
--
-- * circle_sounds: up to 24 sounds per circle, each an MP3, Ogg or WAV
--   clip of at most 5 seconds and 512 KB, with a name (1 to 32
--   characters, unique per circle) and an optional emoji. Members read
--   them; only the RPCs below write them.
-- * Storage: the private bucket circle-sounds holds the clips at
--   <circle_id>/<uuid>.<mp3|ogg|wav>, with the same policies as
--   circle-emojis: members read (signed URLs), members with manage_emojis
--   upload and delete. The bucket limits size and type; the client
--   measures the length (the server can't decode audio) and players stop
--   at 5 seconds whatever the file says.
-- * create_circle_sound (after the upload) and delete_circle_sound need
--   manage_emojis (no new permission: sounds are managed like emoji) and
--   are audited as sound_create / sound_delete. delete_circle_sound
--   returns the clip's path for the client to remove.
-- * play_soundboard_sound(channel, sound): the caller must be connected
--   to the voice channel (or speaking on the stage) with connect_voice,
--   not server muted or deafened, and the sound must be the channel's
--   circle's. One play per member every 2 seconds (errcode P0001, detail
--   soundboard_cooldown_ms=<ms>). It adds a soundboard_plays row, which
--   realtime delivers to everyone who can see the channel; each client
--   connected there plays the clip at their own soundboard volume. Plays
--   older than a minute are cleared as new ones come in.

create table if not exists public.circle_sounds (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  name text not null,
  emoji text,
  storage_path text not null unique,
  mime_type text not null,
  duration_ms integer not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint circle_sounds_name_length check (
    char_length(name) between 1 and 32 and name = btrim(name)
  ),
  constraint circle_sounds_emoji_length check (
    emoji is null or char_length(emoji) between 1 and 16
  ),
  constraint circle_sounds_mime_type_check
    check (mime_type in ('audio/mpeg', 'audio/ogg', 'audio/wav')),
  constraint circle_sounds_duration_range check (
    duration_ms between 1 and 5000
  ),
  constraint circle_sounds_name_unique unique (circle_id, name)
);

alter table public.circle_sounds enable row level security;

revoke insert, update, delete, truncate on public.circle_sounds from anon;
revoke insert, update, delete, truncate on public.circle_sounds from authenticated;

drop policy if exists circle_sounds_select_member on public.circle_sounds;
create policy circle_sounds_select_member
  on public.circle_sounds for select
  to authenticated
  using (public.is_current_user_circle_member(circle_id));

-- Soundboards refresh live, like custom emoji.
alter table public.circle_sounds replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'circle_sounds'
  ) then
    alter publication supabase_realtime add table public.circle_sounds;
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'circle-sounds',
  'circle-sounds',
  false,
  524288,
  array['audio/mpeg', 'audio/ogg', 'audio/wav']
)
on conflict (id) do update
set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- circle_emoji_object_circle_id reads the circle folder of any object.
drop policy if exists circle_sounds_storage_select_member on storage.objects;
create policy circle_sounds_storage_select_member
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'circle-sounds'
    and public.is_current_user_circle_member(
      public.circle_emoji_object_circle_id(name)
    )
  );

drop policy if exists circle_sounds_storage_insert_manager on storage.objects;
create policy circle_sounds_storage_insert_manager
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'circle-sounds'
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(mp3|ogg|wav)$'
    and public.current_user_has_circle_permission(
      public.circle_emoji_object_circle_id(name),
      'manage_emojis'
    )
  );

drop policy if exists circle_sounds_storage_delete_manager on storage.objects;
create policy circle_sounds_storage_delete_manager
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'circle-sounds'
    and public.current_user_has_circle_permission(
      public.circle_emoji_object_circle_id(name),
      'manage_emojis'
    )
  );

-- A sound as clients see it.
create or replace function public.circle_sound_payload(
  sound public.circle_sounds
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', sound.id,
    'circle_id', sound.circle_id,
    'name', sound.name,
    'emoji', sound.emoji,
    'storage_path', sound.storage_path,
    'mime_type', sound.mime_type,
    'duration_ms', sound.duration_ms,
    'created_by', sound.created_by,
    'created_at', sound.created_at
  );
$$;

-- Registers a clip the caller uploaded to <circle_id>/<uuid>.<ext> as a
-- sound. Raises 22023 for invalid input, 23505 when the name is taken and
-- 54000 when the circle has no room left.
create or replace function public.create_circle_sound(
  target_circle_id uuid,
  sound_name text,
  sound_emoji text,
  storage_path text,
  mime_type text,
  duration_ms integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_name text := btrim(coalesce(sound_name, ''));
  trimmed_emoji text := nullif(btrim(coalesce(sound_emoji, '')), '');
  object_path text := coalesce(storage_path, '');
  stored_object storage.objects%rowtype;
  violated_constraint text;
  created public.circle_sounds%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'manage_emojis'
  ) then
    raise exception 'Circle not found or caller cannot manage its sounds'
      using errcode = '42501';
  end if;

  if char_length(trimmed_name) not between 1 and 32 then
    raise exception 'Names are 1 to 32 characters' using errcode = '22023';
  end if;

  if trimmed_emoji is not null and char_length(trimmed_emoji) > 16 then
    raise exception 'Use a single emoji' using errcode = '22023';
  end if;

  if mime_type is null
    or mime_type not in ('audio/mpeg', 'audio/ogg', 'audio/wav')
  then
    raise exception 'Sounds must be MP3, Ogg or WAV' using errcode = '22023';
  end if;

  if duration_ms is null or duration_ms not between 1 and 5000 then
    raise exception 'Sounds can be at most 5 seconds long'
      using errcode = '22023';
  end if;

  if public.circle_emoji_object_circle_id(object_path) is distinct from target_circle_id
    or object_path !~ '^[0-9a-f-]{36}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(mp3|ogg|wav)$'
  then
    raise exception 'The sound must be uploaded to the circle''s folder'
      using errcode = '22023';
  end if;

  select o.*
  into stored_object
  from storage.objects o
  where o.bucket_id = 'circle-sounds'
    and o.name = object_path;

  if stored_object.id is null then
    raise exception 'The sound was not uploaded' using errcode = '22023';
  end if;

  if coalesce((stored_object.metadata->>'size')::bigint, 0) > 524288
    or coalesce(stored_object.metadata->>'mimetype', mime_type) <> mime_type
  then
    raise exception 'Sounds must be MP3, Ogg or WAV of at most 512 KB'
      using errcode = '22023';
  end if;

  -- One upload per circle at a time, so the limit holds.
  perform 1
  from public.circles c
  where c.id = target_circle_id
  for update;

  if (
    select count(*)
    from public.circle_sounds s
    where s.circle_id = target_circle_id
  ) >= 24 then
    raise exception 'This circle has no room for more sounds'
      using errcode = '54000';
  end if;

  begin
    insert into public.circle_sounds (
      circle_id,
      name,
      emoji,
      storage_path,
      mime_type,
      duration_ms,
      created_by
    )
    values (
      target_circle_id,
      trimmed_name,
      trimmed_emoji,
      object_path,
      mime_type,
      duration_ms,
      current_user_id
    )
    returning * into created;
  exception
    when unique_violation then
      get stacked diagnostics violated_constraint = constraint_name;
      if violated_constraint = 'circle_sounds_name_unique' then
        raise exception 'That name is already taken' using errcode = '23505';
      end if;
      raise exception 'That sound is already in use' using errcode = '22023';
  end;

  perform public.write_circle_audit(
    target_circle_id,
    'sound_create',
    'sound',
    created.id,
    created.name,
    jsonb_build_object('emoji', created.emoji)
  );

  return public.circle_sound_payload(created);
end;
$$;

-- Deletes a sound. Returns its clip's path, which the client removes from
-- Storage.
create or replace function public.delete_circle_sound(target_sound_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  sound public.circle_sounds%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select s.* into sound
  from public.circle_sounds s
  where s.id = target_sound_id;

  if sound.id is null
    or not public.current_user_has_circle_permission(
      sound.circle_id,
      'manage_emojis'
    )
  then
    raise exception 'Sound not found or caller cannot manage it'
      using errcode = '42501';
  end if;

  delete from public.circle_sounds s where s.id = sound.id;

  perform public.write_circle_audit(
    sound.circle_id,
    'sound_delete',
    'sound',
    sound.id,
    sound.name,
    '{}'::jsonb
  );

  return sound.storage_path;
end;
$$;

create or replace function public.list_circle_sounds(target_circle_id uuid)
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
  select public.circle_sound_payload(s)
  from public.circle_sounds s
  where s.circle_id = target_circle_id
  order by s.created_at, s.id;
end;
$$;

-- Sounds played in voice channels, delivered to clients by realtime.
create table if not exists public.soundboard_plays (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null,
  circle_id uuid not null,
  sound_id uuid not null references public.circle_sounds(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  played_at timestamptz not null default now(),
  constraint soundboard_plays_channel_fkey
    foreign key (channel_id, circle_id)
    references public.circle_channels(id, circle_id)
    on delete cascade
);

create index if not exists soundboard_plays_user_idx
  on public.soundboard_plays (user_id, played_at desc);

create index if not exists soundboard_plays_played_at_idx
  on public.soundboard_plays (played_at);

alter table public.soundboard_plays enable row level security;

revoke insert, update, delete, truncate on public.soundboard_plays from anon;
revoke insert, update, delete, truncate on public.soundboard_plays from authenticated;

drop policy if exists soundboard_plays_select_viewer on public.soundboard_plays;
create policy soundboard_plays_select_viewer
  on public.soundboard_plays for select
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
      and tablename = 'soundboard_plays'
  ) then
    alter publication supabase_realtime add table public.soundboard_plays;
  end if;
end $$;

-- How long a member waits between soundboard plays.
create or replace function public.soundboard_cooldown()
returns interval
language sql
immutable
set search_path = public
as $$
  select interval '2 seconds';
$$;

-- Plays [target_sound_id] in [target_channel_id] for everyone there.
create or replace function public.play_soundboard_sound(
  target_channel_id uuid,
  target_sound_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  state public.voice_states%rowtype;
  channel public.circle_channels%rowtype;
  sound public.circle_sounds%rowtype;
  last_played_at timestamptz;
  remaining_ms integer;
  play_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id
    and cc.kind in ('voice', 'stage');

  select vs.* into state
  from public.voice_states vs
  where vs.channel_id = target_channel_id
    and vs.user_id = current_user_id
    and vs.last_seen_at > now() - public.voice_state_ttl();

  if channel.id is null
    or state.user_id is null
    or not public.current_user_has_channel_permission(
      channel.id,
      'connect_voice'
    )
    or state.server_mute
    or state.server_deaf
    or (channel.kind = 'stage' and not state.stage_speaker)
  then
    raise exception 'You cannot use the soundboard here'
      using errcode = '42501';
  end if;

  select s.* into sound
  from public.circle_sounds s
  where s.id = target_sound_id
    and s.circle_id = channel.circle_id;

  if sound.id is null then
    raise exception 'Sound not found' using errcode = 'P0002';
  end if;

  -- One play per member at a time, so two quick plays cannot both pass.
  perform pg_advisory_xact_lock(
    hashtextextended('soundboard:' || current_user_id::text, 0)
  );

  select max(p.played_at) into last_played_at
  from public.soundboard_plays p
  where p.user_id = current_user_id;

  if last_played_at is not null
    and last_played_at + public.soundboard_cooldown() > now()
  then
    remaining_ms := greatest(
      1,
      ceil(
        extract(
          epoch from last_played_at + public.soundboard_cooldown() - now()
        ) * 1000
      )::integer
    );
    raise exception 'Wait a moment before playing another sound'
      using errcode = 'P0001',
        detail = format('soundboard_cooldown_ms=%s', remaining_ms);
  end if;

  delete from public.soundboard_plays p
  where p.played_at < now() - interval '1 minute';

  insert into public.soundboard_plays (channel_id, circle_id, sound_id, user_id)
  values (channel.id, channel.circle_id, sound.id, current_user_id)
  returning id into play_id;

  return play_id;
end;
$$;

revoke execute on function public.circle_sound_payload(public.circle_sounds) from public;
revoke execute on function public.circle_sound_payload(public.circle_sounds) from anon;
revoke execute on function public.circle_sound_payload(public.circle_sounds) from authenticated;

revoke execute on function public.create_circle_sound(uuid, text, text, text, text, integer) from public;
revoke execute on function public.create_circle_sound(uuid, text, text, text, text, integer) from anon;
revoke execute on function public.delete_circle_sound(uuid) from public;
revoke execute on function public.delete_circle_sound(uuid) from anon;
revoke execute on function public.list_circle_sounds(uuid) from public;
revoke execute on function public.list_circle_sounds(uuid) from anon;
revoke execute on function public.play_soundboard_sound(uuid, uuid) from public;
revoke execute on function public.play_soundboard_sound(uuid, uuid) from anon;

grant execute on function public.create_circle_sound(uuid, text, text, text, text, integer) to authenticated;
grant execute on function public.delete_circle_sound(uuid) to authenticated;
grant execute on function public.list_circle_sounds(uuid) to authenticated;
grant execute on function public.play_soundboard_sound(uuid, uuid) to authenticated;
