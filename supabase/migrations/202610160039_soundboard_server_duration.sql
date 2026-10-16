-- The soundboard's 5-second limit, enforced on the server.
--
-- Clients measured a clip's length themselves and create_circle_sound
-- trusted it. Now clips go through the sound-upload Edge Function, which
-- reads the length from the file (MP3 frames, Ogg Opus or Vorbis packets,
-- PCM WAV data; other formats are refused), refuses anything over 5.2
-- seconds, stores the clip with the service role and calls
-- create_circle_sound as the caller with the measured length (at most
-- 5000 ms).
--
-- * Clients can no longer upload into the circle-sounds bucket: its
--   insert policy is dropped. Members still read clips, and managers
--   still delete them.
-- * create_circle_sound only registers clips without a Storage owner,
--   that is ones the service role stored, so a clip a client uploaded
--   before this migration can't be registered with a made-up length.

drop policy if exists circle_sounds_storage_insert_manager on storage.objects;

-- Same as 202610160019_soundboard, but only for clips the service role
-- stored.
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

  -- Only clips the sound-upload function stored (with the service role,
  -- so without an owner) and measured; never one a client uploaded itself.
  if stored_object.owner is not null or stored_object.owner_id is not null then
    raise exception 'Upload sounds through the app' using errcode = '22023';
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

revoke execute on function public.create_circle_sound(uuid, text, text, text, text, integer) from public;
revoke execute on function public.create_circle_sound(uuid, text, text, text, text, integer) from anon;
grant execute on function public.create_circle_sound(uuid, text, text, text, text, integer) to authenticated;
