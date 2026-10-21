-- Group space (roadmap B6), part 2 of 4: albums.
--
-- * get_group_space(chat): what the space of this chat allows the caller
--   (supported only for group chats; enabled is false while disappearing
--   messages are on; can_add; is_admin; the two counts).
-- * list_group_albums(chat): the albums, newest activity first, each with its
--   count and a cover; plus one album for every event of the chat that has
--   pictures (kind 'event': the pictures people added from the event, C10, so
--   they are found here after the event too). Pictures of somebody who blocked
--   the caller or whom the caller blocked are left out of the counts and lists.
-- * create / rename / set the cover of / delete an album. Anyone who may send
--   in the chat can make an album; the person who made it and the group's
--   owner and admins can change or delete it.
-- * list_album_items(album): newest first, up to 500.
-- * add_album_items_from_messages(album, messages): pictures and videos that
--   were sent in the chat. Not the ones sent view-once, not ones that are
--   deleted, waiting for review, set to expire, or that came from another chat
--   by forwarding (their file lives in that chat's folder). A group message
--   that is one of an album of pictures is added picture by picture: the app
--   sends all the ids.
-- * add_album_upload(album, ...): a file uploaded to <chat>/space/... first.
-- * remove_album_item(item) / set_album_item_alt(item, alt): the person who
--   added it and the group's owner and admins.
-- * list_group_event_album(chat, event): the pictures of one event.
--
-- Calls that remove something answer with the files to remove from Storage
-- (see 202610280200); the app deletes them right after.

create or replace function public.get_group_space(p_conversation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  conversation record;
  is_admin boolean;
  can_add boolean;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select c.type, c.disappear_after_seconds
  into conversation
  from public.conversations c
  where c.id = p_conversation_id;
  if conversation.type is null
    or not public.is_current_user_conversation_member(p_conversation_id)
  then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;
  if conversation.type <> 'group' then
    return jsonb_build_object('supported', false);
  end if;

  is_admin := public.group_space_access(p_conversation_id, 'read');
  can_add := not public.is_user_suspended(current_user_id)
    and public.can_current_user_send_in_conversation(p_conversation_id);

  return jsonb_build_object(
    'supported', true,
    'enabled', conversation.disappear_after_seconds is null,
    'can_add', can_add and conversation.disappear_after_seconds is null,
    'can_tidy', can_add,
    'is_admin', is_admin,
    'album_count', (select count(*) from public.conversation_albums a
                    where a.conversation_id = p_conversation_id),
    'folder_count', (select count(*) from public.conversation_folders f
                     where f.conversation_id = p_conversation_id)
  );
end;
$$;

create or replace function public.list_group_albums(p_conversation_id uuid)
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

  return query
  select row_json
  from (
    select
      jsonb_build_object(
        'kind', 'album',
        'id', a.id,
        'name', a.name,
        'item_count', coalesce(counts.n, 0),
        'cover', case when cover.path is null then null
                 else jsonb_build_object('bucket', cover.bucket, 'path', cover.path) end,
        'created_by', a.created_by,
        'creator_name', coalesce(nullif(btrim(p.display_name), ''), p.username),
        'can_manage', a.created_by is not distinct from current_user_id or is_admin,
        'updated_at', a.updated_at
      ) as row_json,
      a.updated_at as sort_at
    from public.conversation_albums a
    left join public.profiles p on p.id = a.created_by
    left join lateral (
      select count(*) as n
      from public.album_items i
      where i.album_id = a.id
        and (i.added_by is null or not public.are_users_blocked(current_user_id, i.added_by))
    ) counts on true
    left join lateral (
      select i.bucket, i.path
      from public.album_items i
      where i.album_id = a.id
        and (i.added_by is null or not public.are_users_blocked(current_user_id, i.added_by))
      order by (i.id = a.cover_item_id) desc, (i.kind = 'image') desc, i.created_at desc
      limit 1
    ) cover on true
    where a.conversation_id = p_conversation_id

    union all

    select
      jsonb_build_object(
        'kind', 'event',
        'id', e.id,
        'name', e.title,
        'item_count', photos.n,
        'cover', jsonb_build_object('bucket', photos.bucket, 'path', photos.path),
        'created_by', null,
        'creator_name', null,
        'can_manage', false,
        'starts_at', e.starts_at,
        'updated_at', e.starts_at
      ),
      e.starts_at
    from public.chat_events e
    join lateral (
      select count(*) over () as n, ph.bucket, ph.path
      from public.event_photos ph
      where ph.chat_event_id = e.id
        and not public.are_users_blocked(current_user_id, ph.user_id)
      order by ph.created_at desc, ph.id
      limit 1
    ) photos on true
    where e.conversation_id = p_conversation_id
  ) all_albums
  order by sort_at desc, row_json->>'id';
end;
$$;

create or replace function public.create_group_album(
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
  new_row public.conversation_albums%rowtype;
begin
  perform public.group_space_access(p_conversation_id, 'add');
  if clean is null or char_length(clean) > 40 then
    raise exception 'A name needs 1 to 40 characters' using errcode = '22023';
  end if;
  if (select count(*) from public.conversation_albums a
      where a.conversation_id = p_conversation_id) >= 50
  then
    raise exception 'A group can have up to 50 albums' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.conversation_albums a
    where a.conversation_id = p_conversation_id and lower(btrim(a.name)) = lower(clean)
  ) then
    raise exception 'This group already has an album with that name' using errcode = '22023';
  end if;

  insert into public.conversation_albums (conversation_id, name, created_by)
  values (p_conversation_id, clean, current_user_id)
  returning * into new_row;

  return jsonb_build_object(
    'kind', 'album',
    'id', new_row.id,
    'name', new_row.name,
    'item_count', 0,
    'cover', null,
    'created_by', new_row.created_by,
    'can_manage', true,
    'updated_at', new_row.updated_at
  );
end;
$$;

-- The album, after checking that the caller may change it: whoever made it, or
-- an owner or admin of the group.
create or replace function public.group_space_album_for_change(
  p_album_id uuid,
  p_mode text
)
returns public.conversation_albums
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  album public.conversation_albums%rowtype;
  is_admin boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select a.* into album from public.conversation_albums a where a.id = p_album_id;
  if album.id is null then
    raise exception 'Album not found' using errcode = '42501';
  end if;
  is_admin := public.group_space_access(album.conversation_id, p_mode);
  if album.created_by is distinct from auth.uid() and not is_admin then
    raise exception 'Only the person who made it or a group admin can do this'
      using errcode = '42501';
  end if;
  return album;
end;
$$;

revoke execute on function public.group_space_album_for_change(uuid, text)
  from public, anon, authenticated;

create or replace function public.rename_group_album(
  p_album_id uuid,
  p_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  album public.conversation_albums%rowtype;
  clean text := public.group_space_clean_name(p_name);
begin
  album := public.group_space_album_for_change(p_album_id, 'add');
  if clean is null or char_length(clean) > 40 then
    raise exception 'A name needs 1 to 40 characters' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.conversation_albums a
    where a.conversation_id = album.conversation_id
      and a.id <> album.id
      and lower(btrim(a.name)) = lower(clean)
  ) then
    raise exception 'This group already has an album with that name' using errcode = '22023';
  end if;
  update public.conversation_albums set name = clean, updated_at = now()
  where id = album.id;
end;
$$;

create or replace function public.set_group_album_cover(
  p_album_id uuid,
  p_item_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  album public.conversation_albums%rowtype;
begin
  album := public.group_space_album_for_change(p_album_id, 'tidy');
  if p_item_id is not null and not exists (
    select 1 from public.album_items i
    where i.id = p_item_id and i.album_id = album.id and i.kind = 'image'
  ) then
    raise exception 'The cover must be a picture of the album' using errcode = '22023';
  end if;
  update public.conversation_albums set cover_item_id = p_item_id where id = album.id;
end;
$$;

create or replace function public.delete_group_album(p_album_id uuid)
returns table (bucket_id text, object_path text)
language plpgsql
security definer
set search_path = public
as $$
declare
  album public.conversation_albums%rowtype;
  buckets text[];
  paths text[];
begin
  album := public.group_space_album_for_change(p_album_id, 'tidy');
  select coalesce(array_agg(i.bucket), '{}'), coalesce(array_agg(i.path), '{}')
  into buckets, paths
  from public.album_items i
  where i.album_id = album.id;

  delete from public.conversation_albums where id = album.id;

  return query select * from public.group_space_release_files(buckets, paths);
end;
$$;

create or replace function public.group_space_item_json(
  item public.album_items,
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
    'id', item.id,
    'album_id', item.album_id,
    'bucket', item.bucket,
    'path', item.path,
    'kind', item.kind,
    'name', item.name,
    'mime_type', item.mime_type,
    'size', item.size,
    'width', item.width,
    'height', item.height,
    'alt', item.alt,
    'blurhash', item.blurhash,
    'added_by', item.added_by,
    'adder_name', (
      select coalesce(nullif(btrim(p.display_name), ''), p.username)
      from public.profiles p where p.id = item.added_by
    ),
    'created_at', item.created_at,
    'from_chat', item.source_message_id is not null,
    'message_id', item.source_message_id,
    'mine', item.added_by is not distinct from viewer,
    'can_delete', item.added_by is not distinct from viewer or is_admin
  ));
$$;

revoke execute on function public.group_space_item_json(public.album_items, uuid, boolean)
  from public, anon, authenticated;

create or replace function public.list_album_items(p_album_id uuid)
returns setof jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  album public.conversation_albums%rowtype;
  is_admin boolean;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select a.* into album from public.conversation_albums a where a.id = p_album_id;
  if album.id is null then
    raise exception 'Album not found' using errcode = '42501';
  end if;
  is_admin := public.group_space_access(album.conversation_id, 'read');

  return query
  select public.group_space_item_json(i, current_user_id, is_admin)
  from public.album_items i
  where i.album_id = album.id
    and (i.added_by is null or not public.are_users_blocked(current_user_id, i.added_by))
  order by i.created_at desc, i.id
  limit 500;
end;
$$;

create or replace function public.add_album_items_from_messages(
  p_album_id uuid,
  p_message_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  album public.conversation_albums%rowtype;
  message record;
  kind_value text;
  added integer := 0;
  skipped integer := 0;
  inserted integer;
  size_value bigint;
  width_value integer;
  height_value integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select a.* into album from public.conversation_albums a where a.id = p_album_id;
  if album.id is null then
    raise exception 'Album not found' using errcode = '42501';
  end if;
  perform public.group_space_access(album.conversation_id, 'add');

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
      and m.conversation_id = album.conversation_id
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
        and message.attachment->>'kind' = 'video'
        and message.attachment->>'bucket' = 'chat-files'
      then
        kind_value := 'video';
      end if;
    end if;
    -- A forwarded picture keeps the file of the chat it came from.
    if kind_value is null
      or coalesce(message.attachment->>'path', '') not like album.conversation_id::text || '/%'
      or message.attachment->>'path' ~ '\.\.'
    then
      skipped := skipped + 1;
      continue;
    end if;

    if (select count(*) from public.album_items i where i.album_id = album.id) >= 500 then
      raise exception 'An album holds up to 500 pictures and videos' using errcode = '22023';
    end if;
    size_value := case when message.attachment->>'size' ~ '^\d{1,10}$'
      then (message.attachment->>'size')::bigint else 0 end;
    width_value := case when message.attachment->>'width' ~ '^\d{1,6}$'
      then (message.attachment->>'width')::integer end;
    height_value := case when message.attachment->>'height' ~ '^\d{1,6}$'
      then (message.attachment->>'height')::integer end;
    if public.group_space_bytes(album.conversation_id) + size_value > 2147483648 then
      raise exception 'The group space is full' using errcode = '22023';
    end if;

    insert into public.album_items (
      album_id, conversation_id, source_message_id, bucket, path, kind, name,
      mime_type, size, width, height, alt, blurhash, added_by
    )
    values (
      album.id,
      album.conversation_id,
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
      width_value,
      height_value,
      left(nullif(btrim(coalesce(message.attachment->>'alt', '')), ''), 1000),
      left(nullif(btrim(coalesce(message.attachment->>'blurhash', '')), ''), 100),
      current_user_id
    )
    on conflict (album_id, bucket, path) do nothing;
    get diagnostics inserted = row_count;
    added := added + inserted;
    skipped := skipped + (1 - inserted);
  end loop;

  if added > 0 then
    update public.conversation_albums set updated_at = now() where id = album.id;
  end if;
  return jsonb_build_object('added', added, 'skipped', skipped);
end;
$$;

create or replace function public.add_album_upload(
  p_album_id uuid,
  p_bucket text,
  p_path text,
  p_name text,
  p_mime_type text,
  p_size bigint,
  p_width integer default null,
  p_height integer default null,
  p_alt text default null,
  p_blurhash text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  album public.conversation_albums%rowtype;
  kind_value text;
  stored_size bigint;
  clean_name text := left(public.group_space_clean_name(p_name), 200);
  mime text := left(lower(coalesce(p_mime_type, '')), 100);
  new_row public.album_items%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select a.* into album from public.conversation_albums a where a.id = p_album_id;
  if album.id is null then
    raise exception 'Album not found' using errcode = '42501';
  end if;
  perform public.group_space_access(album.conversation_id, 'add');

  if p_bucket = 'chat-images' then
    kind_value := 'image';
  elsif p_bucket = 'chat-files' and mime like 'video/%' then
    kind_value := 'video';
  else
    raise exception 'Only pictures and videos can go in an album' using errcode = '22023';
  end if;
  if p_path is null
    or char_length(p_path) not between 3 and 300
    or p_path ~ '\.\.'
    or p_path !~ ('^' || album.conversation_id::text || '/space/[^/]+$')
  then
    raise exception 'The file must be in the group space folder' using errcode = '22023';
  end if;
  select coalesce((o.metadata->>'size')::bigint, p_size, 0)
  into stored_size
  from storage.objects o
  where o.bucket_id = p_bucket and o.name = p_path;
  if not found then
    raise exception 'Upload the file first' using errcode = '22023';
  end if;
  if (select count(*) from public.album_items i where i.album_id = album.id) >= 500 then
    raise exception 'An album holds up to 500 pictures and videos' using errcode = '22023';
  end if;
  if public.group_space_bytes(album.conversation_id) + stored_size > 2147483648 then
    raise exception 'The group space is full' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.album_items i
    where i.album_id = album.id and i.bucket = p_bucket and i.path = p_path
  ) then
    raise exception 'That file is already in the album' using errcode = '22023';
  end if;

  insert into public.album_items (
    album_id, conversation_id, bucket, path, kind, name, mime_type, size,
    width, height, alt, blurhash, added_by
  )
  values (
    album.id, album.conversation_id, p_bucket, p_path, kind_value,
    coalesce(clean_name, (regexp_match(p_path, '[^/]+$'))[1]),
    mime, greatest(stored_size, 0),
    case when p_width between 1 and 999999 then p_width end,
    case when p_height between 1 and 999999 then p_height end,
    left(nullif(btrim(coalesce(p_alt, '')), ''), 1000),
    left(nullif(btrim(coalesce(p_blurhash, '')), ''), 100),
    current_user_id
  )
  returning * into new_row;

  update public.conversation_albums set updated_at = now() where id = album.id;
  return public.group_space_item_json(new_row, current_user_id, false);
end;
$$;

create or replace function public.remove_album_item(p_item_id uuid)
returns table (bucket_id text, object_path text)
language plpgsql
security definer
set search_path = public
as $$
declare
  item public.album_items%rowtype;
  is_admin boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select i.* into item from public.album_items i where i.id = p_item_id;
  if item.id is null then
    raise exception 'Item not found' using errcode = '42501';
  end if;
  is_admin := public.group_space_access(item.conversation_id, 'tidy');
  if item.added_by is distinct from auth.uid() and not is_admin then
    raise exception 'Only the person who made it or a group admin can do this'
      using errcode = '42501';
  end if;

  delete from public.album_items where id = item.id;
  update public.conversation_albums set updated_at = now() where id = item.album_id;

  return query
  select * from public.group_space_release_files(array[item.bucket], array[item.path]);
end;
$$;

create or replace function public.set_album_item_alt(
  p_item_id uuid,
  p_alt text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  item public.album_items%rowtype;
  is_admin boolean;
  clean text := left(nullif(btrim(coalesce(p_alt, '')), ''), 1000);
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select i.* into item from public.album_items i where i.id = p_item_id;
  if item.id is null then
    raise exception 'Item not found' using errcode = '42501';
  end if;
  is_admin := public.group_space_access(item.conversation_id, 'tidy');
  if item.added_by is distinct from auth.uid() and not is_admin then
    raise exception 'Only the person who made it or a group admin can do this'
      using errcode = '42501';
  end if;
  if item.kind <> 'image' then
    raise exception 'Only pictures have a description' using errcode = '22023';
  end if;
  update public.album_items set alt = clean where id = item.id;
end;
$$;

-- The pictures of one event of the chat (what the event's own page shows).
create or replace function public.list_group_event_album(
  p_conversation_id uuid,
  p_event_id uuid
)
returns setof jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  event_row public.chat_events%rowtype;
begin
  perform public.group_space_access(p_conversation_id, 'read');
  select e.* into event_row
  from public.chat_events e
  where e.id = p_event_id and e.conversation_id = p_conversation_id;
  if event_row.id is null then
    raise exception 'Event not found' using errcode = '42501';
  end if;
  return query
  select jsonb_strip_nulls(jsonb_build_object(
    'id', ph.id,
    'bucket', ph.bucket,
    'path', ph.path,
    'kind', 'image',
    'name', (regexp_match(ph.path, '[^/]+$'))[1],
    'added_by', ph.user_id,
    'adder_name', coalesce(nullif(btrim(p.display_name), ''), p.username),
    'created_at', ph.created_at,
    'mine', ph.user_id = current_user_id,
    'can_delete', ph.user_id = current_user_id
      or public.can_manage_chat_event(event_row, current_user_id)
  ))
  from public.event_photos ph
  join public.profiles p on p.id = ph.user_id
  where ph.chat_event_id = event_row.id
    and not public.are_users_blocked(current_user_id, ph.user_id)
  order by ph.created_at desc, ph.id
  limit 300;
end;
$$;

revoke execute on function public.get_group_space(uuid) from public, anon;
revoke execute on function public.list_group_albums(uuid) from public, anon;
revoke execute on function public.create_group_album(uuid, text) from public, anon;
revoke execute on function public.rename_group_album(uuid, text) from public, anon;
revoke execute on function public.set_group_album_cover(uuid, uuid) from public, anon;
revoke execute on function public.delete_group_album(uuid) from public, anon;
revoke execute on function public.list_album_items(uuid) from public, anon;
revoke execute on function public.add_album_items_from_messages(uuid, uuid[]) from public, anon;
revoke execute on function public.add_album_upload(
  uuid, text, text, text, text, bigint, integer, integer, text, text
) from public, anon;
revoke execute on function public.remove_album_item(uuid) from public, anon;
revoke execute on function public.set_album_item_alt(uuid, text) from public, anon;
revoke execute on function public.list_group_event_album(uuid, uuid) from public, anon;

grant execute on function public.get_group_space(uuid) to authenticated;
grant execute on function public.list_group_albums(uuid) to authenticated;
grant execute on function public.create_group_album(uuid, text) to authenticated;
grant execute on function public.rename_group_album(uuid, text) to authenticated;
grant execute on function public.set_group_album_cover(uuid, uuid) to authenticated;
grant execute on function public.delete_group_album(uuid) to authenticated;
grant execute on function public.list_album_items(uuid) to authenticated;
grant execute on function public.add_album_items_from_messages(uuid, uuid[]) to authenticated;
grant execute on function public.add_album_upload(
  uuid, text, text, text, text, bigint, integer, integer, text, text
) to authenticated;
grant execute on function public.remove_album_item(uuid) to authenticated;
grant execute on function public.set_album_item_alt(uuid, text) to authenticated;
grant execute on function public.list_group_event_album(uuid, uuid) to authenticated;
