-- Group space (roadmap B6), part 3 of 4: folders.
--
-- * list_group_folders(chat): the folders with how many files each holds and
--   how many sit at the top, in one answer.
-- * create / rename / delete a folder. Anyone who may send in the chat can make
--   a folder; the person who made it and the group's owner and admins can
--   rename or delete it. Deleting a folder deletes the files in it (the app
--   says how many first).
-- * list_folder_files(chat, folder): a folder's files, or the top level when
--   the folder is null; newest first, up to 500.
-- * add_folder_files_from_messages(chat, folder, messages): pictures, videos
--   and files sent in the chat. The same refusals as albums: not view-once, not
--   deleted, not waiting for review, not set to expire, not forwarded from
--   another chat.
-- * add_folder_upload(chat, folder, ...): a file uploaded to <chat>/space/...
--   first (any kind of file, up to the bucket's 50 MB).
-- * move_folder_file / rename_folder_file / remove_folder_file: the person who
--   added the file and the group's owner and admins.
--
-- A group's folders and albums together refer to at most 2 GiB (the app also
-- shows what a group uses); 50 folders; 500 files in a folder or at the top.

create or replace function public.list_group_folders(p_conversation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  is_admin boolean;
begin
  is_admin := public.group_space_access(p_conversation_id, 'read');

  return jsonb_build_object(
    'folders', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', f.id,
          'name', f.name,
          'file_count', (
            select count(*) from public.folder_files ff
            where ff.folder_id = f.id
              and (ff.added_by is null or not public.are_users_blocked(current_user_id, ff.added_by))
          ),
          'created_by', f.created_by,
          'creator_name', (
            select coalesce(nullif(btrim(p.display_name), ''), p.username)
            from public.profiles p where p.id = f.created_by
          ),
          'can_manage', f.created_by is not distinct from current_user_id or is_admin,
          'created_at', f.created_at
        )
        order by lower(f.name), f.id
      )
      from public.conversation_folders f
      where f.conversation_id = p_conversation_id
    ), '[]'::jsonb),
    'root_count', (
      select count(*) from public.folder_files ff
      where ff.conversation_id = p_conversation_id and ff.folder_id is null
        and (ff.added_by is null or not public.are_users_blocked(current_user_id, ff.added_by))
    )
  );
end;
$$;

create or replace function public.create_group_folder(
  p_conversation_id uuid,
  p_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  clean text := public.group_space_clean_name(p_name);
  new_row public.conversation_folders%rowtype;
begin
  perform public.group_space_access(p_conversation_id, 'add');
  if clean is null or char_length(clean) > 40 then
    raise exception 'A name needs 1 to 40 characters' using errcode = '22023';
  end if;
  if (select count(*) from public.conversation_folders f
      where f.conversation_id = p_conversation_id) >= 50
  then
    raise exception 'A group can have up to 50 folders' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.conversation_folders f
    where f.conversation_id = p_conversation_id and lower(btrim(f.name)) = lower(clean)
  ) then
    raise exception 'This group already has a folder with that name' using errcode = '22023';
  end if;

  insert into public.conversation_folders (conversation_id, name, created_by)
  values (p_conversation_id, clean, current_user_id)
  returning * into new_row;

  return jsonb_build_object(
    'id', new_row.id,
    'name', new_row.name,
    'file_count', 0,
    'created_by', new_row.created_by,
    'can_manage', true,
    'created_at', new_row.created_at
  );
end;
$$;

create or replace function public.group_space_folder_for_change(
  p_folder_id uuid,
  p_mode text
)
returns public.conversation_folders
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  folder public.conversation_folders%rowtype;
  is_admin boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select f.* into folder from public.conversation_folders f where f.id = p_folder_id;
  if folder.id is null then
    raise exception 'Group folder not found' using errcode = '42501';
  end if;
  is_admin := public.group_space_access(folder.conversation_id, p_mode);
  if folder.created_by is distinct from auth.uid() and not is_admin then
    raise exception 'Only the person who made it or a group admin can do this'
      using errcode = '42501';
  end if;
  return folder;
end;
$$;

revoke execute on function public.group_space_folder_for_change(uuid, text)
  from public, anon, authenticated;

create or replace function public.rename_group_folder(
  p_folder_id uuid,
  p_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  folder public.conversation_folders%rowtype;
  clean text := public.group_space_clean_name(p_name);
begin
  folder := public.group_space_folder_for_change(p_folder_id, 'add');
  if clean is null or char_length(clean) > 40 then
    raise exception 'A name needs 1 to 40 characters' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.conversation_folders f
    where f.conversation_id = folder.conversation_id
      and f.id <> folder.id
      and lower(btrim(f.name)) = lower(clean)
  ) then
    raise exception 'This group already has a folder with that name' using errcode = '22023';
  end if;
  update public.conversation_folders set name = clean where id = folder.id;
end;
$$;

create or replace function public.delete_group_folder(p_folder_id uuid)
returns table (bucket_id text, object_path text)
language plpgsql
security definer
set search_path = public
as $$
declare
  folder public.conversation_folders%rowtype;
  buckets text[];
  paths text[];
begin
  folder := public.group_space_folder_for_change(p_folder_id, 'tidy');
  select coalesce(array_agg(f.bucket), '{}'), coalesce(array_agg(f.path), '{}')
  into buckets, paths
  from public.folder_files f
  where f.folder_id = folder.id;

  delete from public.conversation_folders where id = folder.id;

  return query select * from public.group_space_release_files(buckets, paths);
end;
$$;

create or replace function public.group_space_file_json(
  file public.folder_files,
  viewer uuid,
  is_admin boolean
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', file.id,
    'folder_id', file.folder_id,
    'bucket', file.bucket,
    'path', file.path,
    'kind', file.kind,
    'name', file.name,
    'mime_type', file.mime_type,
    'size', file.size,
    'alt', file.alt,
    'added_by', file.added_by,
    'adder_name', (
      select coalesce(nullif(btrim(p.display_name), ''), p.username)
      from public.profiles p where p.id = file.added_by
    ),
    'created_at', file.created_at,
    'from_chat', file.source_message_id is not null,
    'message_id', file.source_message_id,
    'mine', file.added_by is not distinct from viewer,
    'can_delete', file.added_by is not distinct from viewer or is_admin
  ));
$$;

revoke execute on function public.group_space_file_json(public.folder_files, uuid, boolean)
  from public, anon, authenticated;

create or replace function public.list_folder_files(
  p_conversation_id uuid,
  p_folder_id uuid
)
returns setof jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  is_admin boolean;
begin
  is_admin := public.group_space_access(p_conversation_id, 'read');
  if p_folder_id is not null and not exists (
    select 1 from public.conversation_folders f
    where f.id = p_folder_id and f.conversation_id = p_conversation_id
  ) then
    raise exception 'Group folder not found' using errcode = '42501';
  end if;

  return query
  select public.group_space_file_json(ff, current_user_id, is_admin)
  from public.folder_files ff
  where ff.conversation_id = p_conversation_id
    and ff.folder_id is not distinct from p_folder_id
    and (ff.added_by is null or not public.are_users_blocked(current_user_id, ff.added_by))
  order by ff.created_at desc, ff.id
  limit 500;
end;
$$;

create or replace function public.add_folder_files_from_messages(
  p_conversation_id uuid,
  p_folder_id uuid,
  p_message_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  message record;
  kind_value text;
  added integer := 0;
  skipped integer := 0;
  inserted integer;
  size_value bigint;
begin
  perform public.group_space_access(p_conversation_id, 'add');
  if p_folder_id is not null and not exists (
    select 1 from public.conversation_folders f
    where f.id = p_folder_id and f.conversation_id = p_conversation_id
  ) then
    raise exception 'Group folder not found' using errcode = '42501';
  end if;

  if p_message_ids is null or cardinality(p_message_ids) = 0 then
    return jsonb_build_object('added', 0, 'skipped', 0);
  end if;
  if cardinality(p_message_ids) > 50 then
    raise exception 'Choose up to 50 items at a time' using errcode = '22023';
  end if;

  for message in
    select m.*
    from public.messages m
    where m.id = any (p_message_ids)
      and m.conversation_id = p_conversation_id
    order by m.created_at, m.id
  loop
    kind_value := null;
    if message.recalled_at is null
      and message.expires_at is null
      and message.review_state is null
      and message.attachment is not null
      and jsonb_typeof(message.attachment) = 'object'
      and coalesce(message.attachment->>'view_once', 'false') <> 'true'
    then
      if message.type = 'image'
        and message.attachment->>'kind' = 'image'
        and message.attachment->>'bucket' = 'chat-images'
      then
        kind_value := 'image';
      elsif message.type = 'file'
        and message.attachment->>'bucket' = 'chat-files'
      then
        kind_value := case when message.attachment->>'kind' = 'video' then 'video' else 'file' end;
      end if;
    end if;
    if kind_value is null
      or coalesce(message.attachment->>'path', '') not like p_conversation_id::text || '/%'
      or message.attachment->>'path' ~ '\.\.'
    then
      skipped := skipped + 1;
      continue;
    end if;

    if (select count(*) from public.folder_files ff
        where ff.conversation_id = p_conversation_id
          and ff.folder_id is not distinct from p_folder_id) >= 500
    then
      raise exception 'A folder holds up to 500 files' using errcode = '22023';
    end if;
    size_value := case when message.attachment->>'size' ~ '^\d{1,10}$'
      then (message.attachment->>'size')::bigint else 0 end;
    if public.group_space_bytes(p_conversation_id) + size_value > 2147483648 then
      raise exception 'The group space is full' using errcode = '22023';
    end if;

    insert into public.folder_files (
      conversation_id, folder_id, source_message_id, bucket, path, kind, name,
      mime_type, size, alt, added_by
    )
    values (
      p_conversation_id,
      p_folder_id,
      message.id,
      message.attachment->>'bucket',
      message.attachment->>'path',
      kind_value,
      left(coalesce(
        nullif(btrim(message.attachment->>'name'), ''),
        (regexp_match(message.attachment->>'path', '[^/]+$'))[1],
        'file'
      ), 200),
      left(coalesce(message.attachment->>'mime_type', ''), 100),
      size_value,
      left(nullif(btrim(coalesce(message.attachment->>'alt', '')), ''), 1000),
      current_user_id
    )
    on conflict (
      conversation_id,
      coalesce(folder_id, '00000000-0000-0000-0000-000000000000'::uuid),
      bucket,
      path
    ) do nothing;
    get diagnostics inserted = row_count;
    added := added + inserted;
    skipped := skipped + (1 - inserted);
  end loop;

  return jsonb_build_object('added', added, 'skipped', skipped);
end;
$$;

create or replace function public.add_folder_upload(
  p_conversation_id uuid,
  p_folder_id uuid,
  p_bucket text,
  p_path text,
  p_name text,
  p_mime_type text,
  p_size bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  clean_name text := left(public.group_space_clean_name(p_name), 200);
  mime text := left(lower(coalesce(p_mime_type, '')), 100);
  kind_value text;
  stored_size bigint;
  new_row public.folder_files%rowtype;
begin
  perform public.group_space_access(p_conversation_id, 'add');
  if p_folder_id is not null and not exists (
    select 1 from public.conversation_folders f
    where f.id = p_folder_id and f.conversation_id = p_conversation_id
  ) then
    raise exception 'Group folder not found' using errcode = '42501';
  end if;
  if clean_name is null then
    raise exception 'A file needs a name' using errcode = '22023';
  end if;
  if p_bucket not in ('chat-files', 'chat-images') then
    raise exception 'The file must be in the group space folder' using errcode = '22023';
  end if;
  if p_path is null
    or char_length(p_path) not between 3 and 300
    or p_path ~ '\.\.'
    or p_path !~ ('^' || p_conversation_id::text || '/space/[^/]+$')
  then
    raise exception 'The file must be in the group space folder' using errcode = '22023';
  end if;
  kind_value := case
    when p_bucket = 'chat-images' then 'image'
    when mime like 'video/%' then 'video'
    when mime like 'image/%' and mime <> 'image/svg+xml' then 'image'
    else 'file'
  end;
  select coalesce((o.metadata->>'size')::bigint, p_size, 0)
  into stored_size
  from storage.objects o
  where o.bucket_id = p_bucket and o.name = p_path;
  if not found then
    raise exception 'Upload the file first' using errcode = '22023';
  end if;
  if (select count(*) from public.folder_files ff
      where ff.conversation_id = p_conversation_id
        and ff.folder_id is not distinct from p_folder_id) >= 500
  then
    raise exception 'A folder holds up to 500 files' using errcode = '22023';
  end if;
  if public.group_space_bytes(p_conversation_id) + stored_size > 2147483648 then
    raise exception 'The group space is full' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.folder_files ff
    where ff.conversation_id = p_conversation_id
      and ff.folder_id is not distinct from p_folder_id
      and ff.bucket = p_bucket and ff.path = p_path
  ) then
    raise exception 'That file is already in the folder' using errcode = '22023';
  end if;

  insert into public.folder_files (
    conversation_id, folder_id, bucket, path, kind, name, mime_type, size, added_by
  )
  values (
    p_conversation_id, p_folder_id, p_bucket, p_path, kind_value, clean_name,
    mime, greatest(stored_size, 0), current_user_id
  )
  returning * into new_row;

  return public.group_space_file_json(new_row, current_user_id, false);
end;
$$;

create or replace function public.group_space_file_for_change(p_file_id uuid)
returns public.folder_files
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  file public.folder_files%rowtype;
  is_admin boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select ff.* into file from public.folder_files ff where ff.id = p_file_id;
  if file.id is null then
    raise exception 'File not found' using errcode = '42501';
  end if;
  is_admin := public.group_space_access(file.conversation_id, 'tidy');
  if file.added_by is distinct from auth.uid() and not is_admin then
    raise exception 'Only the person who made it or a group admin can do this'
      using errcode = '42501';
  end if;
  return file;
end;
$$;

revoke execute on function public.group_space_file_for_change(uuid)
  from public, anon, authenticated;

create or replace function public.move_folder_file(
  p_file_id uuid,
  p_folder_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  file public.folder_files%rowtype;
begin
  file := public.group_space_file_for_change(p_file_id);
  if p_folder_id is not null and not exists (
    select 1 from public.conversation_folders f
    where f.id = p_folder_id and f.conversation_id = file.conversation_id
  ) then
    raise exception 'Group folder not found' using errcode = '42501';
  end if;
  if file.folder_id is not distinct from p_folder_id then
    return;
  end if;
  if exists (
    select 1 from public.folder_files ff
    where ff.conversation_id = file.conversation_id
      and ff.folder_id is not distinct from p_folder_id
      and ff.bucket = file.bucket and ff.path = file.path
  ) then
    raise exception 'That file is already in the folder' using errcode = '22023';
  end if;
  if (select count(*) from public.folder_files ff
      where ff.conversation_id = file.conversation_id
        and ff.folder_id is not distinct from p_folder_id) >= 500
  then
    raise exception 'A folder holds up to 500 files' using errcode = '22023';
  end if;
  update public.folder_files set folder_id = p_folder_id where id = file.id;
end;
$$;

create or replace function public.rename_folder_file(
  p_file_id uuid,
  p_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  file public.folder_files%rowtype;
  clean text := left(public.group_space_clean_name(p_name), 200);
begin
  file := public.group_space_file_for_change(p_file_id);
  if clean is null then
    raise exception 'A file needs a name' using errcode = '22023';
  end if;
  update public.folder_files set name = clean where id = file.id;
end;
$$;

create or replace function public.remove_folder_file(p_file_id uuid)
returns table (bucket_id text, object_path text)
language plpgsql
security definer
set search_path = public
as $$
declare
  file public.folder_files%rowtype;
begin
  file := public.group_space_file_for_change(p_file_id);
  delete from public.folder_files where id = file.id;
  return query
  select * from public.group_space_release_files(array[file.bucket], array[file.path]);
end;
$$;

revoke execute on function public.list_group_folders(uuid) from public, anon;
revoke execute on function public.create_group_folder(uuid, text) from public, anon;
revoke execute on function public.rename_group_folder(uuid, text) from public, anon;
revoke execute on function public.delete_group_folder(uuid) from public, anon;
revoke execute on function public.list_folder_files(uuid, uuid) from public, anon;
revoke execute on function public.add_folder_files_from_messages(uuid, uuid, uuid[]) from public, anon;
revoke execute on function public.add_folder_upload(uuid, uuid, text, text, text, text, bigint)
  from public, anon;
revoke execute on function public.move_folder_file(uuid, uuid) from public, anon;
revoke execute on function public.rename_folder_file(uuid, text) from public, anon;
revoke execute on function public.remove_folder_file(uuid) from public, anon;

grant execute on function public.list_group_folders(uuid) to authenticated;
grant execute on function public.create_group_folder(uuid, text) to authenticated;
grant execute on function public.rename_group_folder(uuid, text) to authenticated;
grant execute on function public.delete_group_folder(uuid) to authenticated;
grant execute on function public.list_folder_files(uuid, uuid) to authenticated;
grant execute on function public.add_folder_files_from_messages(uuid, uuid, uuid[]) to authenticated;
grant execute on function public.add_folder_upload(uuid, uuid, text, text, text, text, bigint)
  to authenticated;
grant execute on function public.move_folder_file(uuid, uuid) to authenticated;
grant execute on function public.rename_folder_file(uuid, text) to authenticated;
grant execute on function public.remove_folder_file(uuid) to authenticated;
