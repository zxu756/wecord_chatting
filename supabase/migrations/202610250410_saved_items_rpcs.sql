-- Favorites 2.0 (roadmap B3), part 2 of 4: keeping, organizing, listing and
-- searching. Every function checks who is asking.
--
-- Keeping
--   save_message(message)          the 202610190011 rule (not recalled, not
--                                  expired, not held by the AI guard, in a
--                                  conversation the caller can read) plus:
--                                  a view-once message is never kept. Writes
--                                  saved_items now; the signature is the same.
--   save_item(kind, target)        a Moment the caller may see right now, or a
--                                  post in a circle the caller is a member of
--                                  (not deleted, circle not suspended).
--   save_link(url, title, ...)     an http(s) link, once per address.
--   create_saved_note(...)         the person's own note or text.
--   At most 1000 entries per person (the old limit for messages).
-- Organizing
--   update_saved_item(id, patch)   folder, tags, remark; title, text and
--                                  pictures of the person's own notes.
--                                  Returns the picture files taken off the
--                                  entry, for the app to remove from Storage.
--   set_saved_message_done(id, d)  "mark done", for any kind.
--   create_saved_folder / rename_saved_folder   (deleting a folder is a plain
--                                  delete; its entries stay, without one).
--   rename_saved_tag(old, new)     renames a tag on all entries; a blank new
--                                  name removes it.
-- Reading
--   list_saved_items(limit)        everything, newest first. Runs as the
--                                  caller, so messages, Moments and posts
--                                  keep their own row policies; what is gone
--                                  or no longer visible comes back with
--                                  available = false and none of its text.
--   list_saved_messages(limit)     the message rows only, as before, for
--                                  older apps.
--   search_saved_items(query)      ids matching every word: through the
--                                  entry's own text (full text, plus
--                                  substrings) or through the text of what
--                                  it points to, read live and only while
--                                  visible. Nothing of other people's text is
--                                  stored for search.

-- ------------------------------------------------------------ helpers

create or replace function public.assert_saved_room(owner uuid)
returns void
language plpgsql
stable
set search_path = public
as $$
begin
  if (select count(*) from public.saved_items s where s.user_id = owner) >= 1000 then
    raise exception 'Too many saved items' using errcode = '53400';
  end if;
end;
$$;

revoke execute on function public.assert_saved_room(uuid) from public, anon, authenticated;

-- The folder [folder] is one of [owner]'s (null is "no folder").
create or replace function public.assert_saved_folder(owner uuid, folder uuid)
returns void
language plpgsql
stable
set search_path = public
as $$
begin
  if folder is not null and not exists (
    select 1 from public.saved_folders f
    where f.id = folder and f.user_id = owner
  ) then
    raise exception 'Folder not found' using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function public.assert_saved_folder(uuid, uuid) from public, anon, authenticated;

-- The pictures of a note: at most four, each in the person's own folder of
-- the saved-notes bucket and named for the entry. Returns them tidied.
create or replace function public.check_saved_note_images(
  owner uuid,
  entry uuid,
  images jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  image jsonb;
  tidy jsonb := '[]'::jsonb;
  path text;
begin
  if images is null or jsonb_typeof(images) <> 'array' then
    raise exception 'Pictures must be a list' using errcode = '22023';
  end if;
  if jsonb_array_length(images) > 4 then
    raise exception 'At most 4 pictures' using errcode = '22023';
  end if;
  for image in select value from jsonb_array_elements(images) loop
    path := image->>'path';
    if jsonb_typeof(image) <> 'object'
      or path is null
      or path !~ ('^' || owner::text || '/' || entry::text || '-[0-3]\.jpg$')
    then
      raise exception 'Invalid picture' using errcode = '22023';
    end if;
    tidy := tidy || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'path', path,
      'w', case when (image->>'w') ~ '^\d{1,5}$' then (image->>'w')::integer end,
      'h', case when (image->>'h') ~ '^\d{1,5}$' then (image->>'h')::integer end
    )));
  end loop;
  return tidy;
end;
$$;

revoke execute on function public.check_saved_note_images(uuid, uuid, jsonb)
  from public, anon, authenticated;

-- --------------------------------------------------------------- keeping

-- Keeps a message the caller can see. Keeping it again changes nothing.
create or replace function public.save_message(p_message_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_conversation_id uuid;
  saved_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select m.conversation_id
  into target_conversation_id
  from public.messages m
  where m.id = p_message_id
    and m.recalled_at is null
    and (m.expires_at is null or m.expires_at > now())
    and coalesce(m.attachment->>'view_once', '') <> 'true'
    and public.message_visible_to_current_user(m.review_state, m.sender_id, m.conversation_id)
    and m.conversation_id in (select public.current_user_readable_conversation_ids());
  if target_conversation_id is null then
    raise exception 'Message not found' using errcode = 'P0002';
  end if;

  select s.id into saved_id
  from public.saved_items s
  where s.user_id = current_user_id
    and s.kind = 'message'
    and s.target_id = p_message_id;
  if saved_id is not null then
    return saved_id;
  end if;

  perform public.assert_saved_room(current_user_id);

  insert into public.saved_items (user_id, kind, target_id, conversation_id)
  values (current_user_id, 'message', p_message_id, target_conversation_id)
  on conflict do nothing
  returning id into saved_id;

  if saved_id is null then
    select s.id into saved_id
    from public.saved_items s
    where s.user_id = current_user_id
      and s.kind = 'message'
      and s.target_id = p_message_id;
  end if;
  return saved_id;
end;
$$;

revoke execute on function public.save_message(uuid) from public, anon;
grant execute on function public.save_message(uuid) to authenticated;

-- Keeps a Moment or a circle post the caller can see.
create or replace function public.save_item(p_kind text, p_target_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_circle uuid;
  saved_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_kind = 'message' then
    return public.save_message(p_target_id);
  end if;
  if p_kind is null or p_kind not in ('moment', 'circle_post') or p_target_id is null then
    raise exception 'Cannot keep this' using errcode = '22023';
  end if;

  if p_kind = 'moment' then
    if not exists (
      select 1
      from public.moments_posts p
      where p.id = p_target_id
        and public.moments_post_visible_to(current_user_id, p)
    ) then
      raise exception 'Moment not found' using errcode = 'P0002';
    end if;
  else
    select cp.circle_id into target_circle
    from public.circle_posts cp
    where cp.id = p_target_id
      and cp.deleted_at is null
      and public.is_current_user_circle_member(cp.circle_id)
      and not public.circle_is_suspended(cp.circle_id);
    if target_circle is null then
      raise exception 'Post not found' using errcode = 'P0002';
    end if;
  end if;

  select s.id into saved_id
  from public.saved_items s
  where s.user_id = current_user_id
    and s.kind = p_kind
    and s.target_id = p_target_id;
  if saved_id is not null then
    return saved_id;
  end if;

  perform public.assert_saved_room(current_user_id);

  insert into public.saved_items (user_id, kind, target_id, circle_id)
  values (current_user_id, p_kind, p_target_id, target_circle)
  on conflict do nothing
  returning id into saved_id;

  if saved_id is null then
    select s.id into saved_id
    from public.saved_items s
    where s.user_id = current_user_id
      and s.kind = p_kind
      and s.target_id = p_target_id;
  end if;
  return saved_id;
end;
$$;

revoke execute on function public.save_item(text, uuid) from public, anon;
grant execute on function public.save_item(text, uuid) to authenticated;

-- Keeps a web link. The same address is kept once (its entry is returned).
create or replace function public.save_link(
  p_url text,
  p_title text default null,
  p_folder_id uuid default null,
  p_tags text[] default '{}',
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  clean_url text := btrim(coalesce(p_url, ''));
  saved_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if char_length(clean_url) > 2000 or clean_url !~* '^https?://[^[:space:]]+$' then
    raise exception 'Enter a web link' using errcode = '22023';
  end if;
  perform public.assert_saved_folder(current_user_id, p_folder_id);

  select s.id into saved_id
  from public.saved_items s
  where s.user_id = current_user_id and s.kind = 'link' and s.url = clean_url;
  if saved_id is not null then
    return saved_id;
  end if;

  perform public.assert_saved_room(current_user_id);

  insert into public.saved_items (user_id, kind, url, title, folder_id, tags, note)
  values (
    current_user_id, 'link', clean_url, left(btrim(coalesce(p_title, '')), 200),
    p_folder_id, coalesce(p_tags, '{}'::text[]), left(coalesce(p_note, ''), 1000)
  )
  returning id into saved_id;
  return saved_id;
end;
$$;

revoke execute on function public.save_link(text, text, uuid, text[], text) from public, anon;
grant execute on function public.save_link(text, text, uuid, text[], text) to authenticated;

-- Keeps the person's own note: a title and/or text and/or up to four
-- pictures. Without a title and pictures it is plain text. [p_id] is chosen
-- by the app so the pictures it uploaded first can be named for the entry.
create or replace function public.create_saved_note(
  p_id uuid default null,
  p_title text default null,
  p_body text default null,
  p_images jsonb default '[]'::jsonb,
  p_folder_id uuid default null,
  p_tags text[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  entry uuid := coalesce(p_id, gen_random_uuid());
  clean_title text := nullif(btrim(coalesce(p_title, '')), '');
  clean_body text := nullif(btrim(coalesce(p_body, '')), '');
  tidy_images jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if char_length(coalesce(clean_title, '')) > 200
    or char_length(coalesce(clean_body, '')) > 20000
  then
    raise exception 'That is too long' using errcode = '22023';
  end if;
  tidy_images := public.check_saved_note_images(
    current_user_id, entry, coalesce(p_images, '[]'::jsonb)
  );
  if clean_title is null and clean_body is null and jsonb_array_length(tidy_images) = 0 then
    raise exception 'Write something first' using errcode = '22023';
  end if;
  perform public.assert_saved_folder(current_user_id, p_folder_id);
  perform public.assert_saved_room(current_user_id);

  insert into public.saved_items (
    id, user_id, kind, title, body, images, folder_id, tags
  )
  values (
    entry,
    current_user_id,
    case
      when clean_title is null and jsonb_array_length(tidy_images) = 0 then 'text'
      else 'note'
    end,
    clean_title,
    clean_body,
    tidy_images,
    p_folder_id,
    coalesce(p_tags, '{}'::text[])
  );
  return entry;
end;
$$;

revoke execute on function public.create_saved_note(uuid, text, text, jsonb, uuid, text[])
  from public, anon;
grant execute on function public.create_saved_note(uuid, text, text, jsonb, uuid, text[])
  to authenticated;

-- ------------------------------------------------------------ organizing

-- Changes an entry of the caller's. The patch holds only what changes:
--   folder_id (null: no folder), tags, note (the remark),
--   title and body (notes and text; a link's title), images (notes).
create or replace function public.update_saved_item(p_id uuid, p_patch jsonb)
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  item public.saved_items%rowtype;
  new_folder uuid;
  new_images jsonb;
  removed text[];
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'Nothing to change' using errcode = '22023';
  end if;
  select * into item
  from public.saved_items s
  where s.id = p_id and s.user_id = current_user_id
  for update;
  if item.id is null then
    raise exception 'Saved item not found' using errcode = 'P0002';
  end if;

  if p_patch ? 'folder_id' then
    new_folder := nullif(p_patch->>'folder_id', '')::uuid;
    perform public.assert_saved_folder(current_user_id, new_folder);
    item.folder_id := new_folder;
  end if;
  if p_patch ? 'tags' then
    if jsonb_typeof(p_patch->'tags') <> 'array' then
      raise exception 'Tags must be a list' using errcode = '22023';
    end if;
    item.tags := array(select jsonb_array_elements_text(p_patch->'tags'));
  end if;
  if p_patch ? 'note' then
    item.note := left(coalesce(p_patch->>'note', ''), 1000);
  end if;
  if p_patch ? 'title' then
    if item.kind not in ('note', 'link') then
      raise exception 'This entry has no title' using errcode = '22023';
    end if;
    item.title := left(btrim(coalesce(p_patch->>'title', '')), 200);
  end if;
  if p_patch ? 'body' then
    if item.kind not in ('note', 'text') then
      raise exception 'This entry has no text of its own' using errcode = '22023';
    end if;
    if char_length(coalesce(p_patch->>'body', '')) > 20000 then
      raise exception 'That is too long' using errcode = '22023';
    end if;
    item.body := nullif(btrim(coalesce(p_patch->>'body', '')), '');
  end if;
  if p_patch ? 'images' then
    if item.kind <> 'note' then
      raise exception 'This entry has no pictures' using errcode = '22023';
    end if;
    new_images := public.check_saved_note_images(
      current_user_id, item.id, p_patch->'images'
    );
    select coalesce(array_agg(old_image->>'path'), '{}'::text[])
    into removed
    from jsonb_array_elements(item.images) old_image
    where not exists (
      select 1
      from jsonb_array_elements(new_images) kept
      where kept->>'path' = old_image->>'path'
    );
    item.images := new_images;
  end if;

  update public.saved_items s
  set folder_id = item.folder_id,
      tags = item.tags,
      note = item.note,
      title = item.title,
      body = item.body,
      images = item.images
  where s.id = item.id;

  return coalesce(removed, '{}'::text[]);
end;
$$;

revoke execute on function public.update_saved_item(uuid, jsonb) from public, anon;
grant execute on function public.update_saved_item(uuid, jsonb) to authenticated;

-- Marks an entry done, or active again (any kind).
create or replace function public.set_saved_message_done(p_id uuid, p_done boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  update public.saved_items s
  set done_at = case when coalesce(p_done, true) then coalesce(s.done_at, now()) else null end
  where s.id = p_id
    and s.user_id = auth.uid();
end;
$$;

revoke execute on function public.set_saved_message_done(uuid, boolean) from public, anon;
grant execute on function public.set_saved_message_done(uuid, boolean) to authenticated;

create or replace function public.create_saved_folder(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  clean_name text := btrim(coalesce(p_name, ''));
  folder_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if char_length(clean_name) not between 1 and 40 then
    raise exception 'A folder name is 1 to 40 characters' using errcode = '22023';
  end if;
  select f.id into folder_id
  from public.saved_folders f
  where f.user_id = current_user_id and lower(btrim(f.name)) = lower(clean_name);
  if folder_id is not null then
    return folder_id;
  end if;
  if (select count(*) from public.saved_folders f where f.user_id = current_user_id) >= 50 then
    raise exception 'Too many folders' using errcode = '53400';
  end if;
  insert into public.saved_folders (user_id, name)
  values (current_user_id, clean_name)
  returning id into folder_id;
  return folder_id;
end;
$$;

revoke execute on function public.create_saved_folder(text) from public, anon;
grant execute on function public.create_saved_folder(text) to authenticated;

create or replace function public.rename_saved_folder(p_id uuid, p_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  clean_name text := btrim(coalesce(p_name, ''));
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if char_length(clean_name) not between 1 and 40 then
    raise exception 'A folder name is 1 to 40 characters' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.saved_folders f
    where f.user_id = current_user_id
      and f.id <> p_id
      and lower(btrim(f.name)) = lower(clean_name)
  ) then
    raise exception 'A folder with that name exists' using errcode = '23505';
  end if;
  update public.saved_folders f
  set name = clean_name
  where f.id = p_id and f.user_id = current_user_id;
  if not found then
    raise exception 'Folder not found' using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function public.rename_saved_folder(uuid, text) from public, anon;
grant execute on function public.rename_saved_folder(uuid, text) to authenticated;

-- Renames a tag on every entry of the caller's (a blank new name removes it).
-- Returns how many entries changed.
create or replace function public.rename_saved_tag(p_old text, p_new text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  old_tag text := lower(btrim(regexp_replace(coalesce(p_old, ''), '^\s*#+', '')));
  new_tag text := btrim(regexp_replace(coalesce(p_new, ''), '^\s*#+', ''));
  changed integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if old_tag = '' then
    raise exception 'Choose a tag' using errcode = '22023';
  end if;
  if char_length(new_tag) > 24 then
    raise exception 'A tag is up to 24 characters' using errcode = '22023';
  end if;
  update public.saved_items s
  set tags = array(
    select case when lower(t) = old_tag then new_tag else t end
    from unnest(s.tags) with ordinality as u(t, position)
    order by u.position
  )
  where s.user_id = current_user_id
    and exists (select 1 from unnest(s.tags) t where lower(t) = old_tag);
  get diagnostics changed = row_count;
  return changed;
end;
$$;

revoke execute on function public.rename_saved_tag(text, text) from public, anon;
grant execute on function public.rename_saved_tag(text, text) to authenticated;

-- --------------------------------------------------------------- reading

create or replace function public.list_saved_items(p_limit integer default 1000)
returns table (
  saved_id uuid,
  kind text,
  target_id uuid,
  conversation_id uuid,
  circle_id uuid,
  folder_id uuid,
  tags text[],
  note text,
  title text,
  body text,
  url text,
  images jsonb,
  saved_at timestamptz,
  done_at timestamptz,
  available boolean,
  sender_id uuid,
  sender_display_name text,
  sender_avatar_url text,
  webhook_name text,
  content_body text,
  content_type text,
  content_created_at timestamptz,
  extra jsonb
)
language sql
stable
security invoker
set search_path = public
as $$
  with joined as (
    select
      s.*,
      m.id as m_id,
      (
        m.id is not null
        and m.recalled_at is null
        and coalesce(m.attachment->>'view_once', '') <> 'true'
      ) as m_ok,
      m.sender_id as m_sender,
      m.webhook_name as m_webhook,
      m.body as m_body,
      m.type as m_type,
      m.created_at as m_created,
      mp.id as mp_id,
      mp.author_id as mp_author,
      mp.body as mp_body,
      mp.kind as mp_kind,
      mp.photos as mp_photos,
      mp.video as mp_video,
      mp.link_url as mp_link_url,
      mp.link_title as mp_link_title,
      mp.created_at as mp_created,
      cp.id as cp_id,
      cp.author_id as cp_author,
      cp.body as cp_body,
      cp.attachment as cp_attachment,
      cp.created_at as cp_created,
      cr.name as cr_name
    from public.saved_items s
    left join public.messages m
      on s.kind = 'message' and m.id = s.target_id
    left join public.moments_posts mp
      on s.kind = 'moment' and mp.id = s.target_id
    left join public.circle_posts cp
      on s.kind = 'circle_post' and cp.id = s.target_id and cp.deleted_at is null
    left join public.circles cr
      on cr.id = cp.circle_id
    where s.user_id = auth.uid()
  ), shown as (
    select
      j.*,
      case j.kind
        when 'message' then j.m_ok
        when 'moment' then j.mp_id is not null
        when 'circle_post' then j.cp_id is not null
        else true
      end as is_available
    from joined j
  )
  select
    j.id,
    j.kind,
    j.target_id,
    j.conversation_id,
    j.circle_id,
    j.folder_id,
    j.tags,
    j.note,
    j.title,
    j.body,
    j.url,
    j.images,
    j.created_at,
    j.done_at,
    j.is_available,
    case when j.is_available then coalesce(j.m_sender, j.mp_author, j.cp_author) end,
    case when j.is_available then p.display_name end,
    case when j.is_available then p.avatar_url end,
    case when j.is_available then j.m_webhook end,
    case when j.is_available then coalesce(j.m_body, j.mp_body, j.cp_body) end,
    case when j.is_available then j.m_type end,
    case when j.is_available then coalesce(j.m_created, j.mp_created, j.cp_created) end,
    case
      when not j.is_available then '{}'::jsonb
      when j.kind = 'moment' then jsonb_strip_nulls(jsonb_build_object(
        'moment_kind', j.mp_kind,
        'photo_count', jsonb_array_length(j.mp_photos),
        'thumb', coalesce(j.mp_photos->0->>'thumb', j.mp_video->>'thumb'),
        'link_url', j.mp_link_url,
        'link_title', j.mp_link_title
      ))
      when j.kind = 'circle_post' then jsonb_strip_nulls(jsonb_build_object(
        'circle_name', j.cr_name,
        'attachment_kind', j.cp_attachment->>'kind',
        'attachment_name', j.cp_attachment->>'name'
      ))
      else '{}'::jsonb
    end
  from shown j
  left join public.profiles p
    on p.id = coalesce(j.m_sender, j.mp_author, j.cp_author)
  order by j.created_at desc, j.id
  limit greatest(1, least(coalesce(p_limit, 1000), 1000));
$$;

revoke execute on function public.list_saved_items(integer) from public, anon;
grant execute on function public.list_saved_items(integer) to authenticated;

-- The message entries, in the shape older apps expect.
create or replace function public.list_saved_messages(p_limit integer default 500)
returns table (
  saved_id uuid,
  message_id uuid,
  conversation_id uuid,
  saved_at timestamptz,
  done_at timestamptz,
  sender_id uuid,
  sender_display_name text,
  sender_avatar_url text,
  webhook_name text,
  body text,
  type text,
  message_created_at timestamptz,
  available boolean
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    l.saved_id,
    l.target_id,
    l.conversation_id,
    l.saved_at,
    l.done_at,
    l.sender_id,
    l.sender_display_name,
    l.sender_avatar_url,
    l.webhook_name,
    l.content_body,
    l.content_type,
    l.content_created_at,
    l.available
  from public.list_saved_items(1000) l
  where l.kind = 'message'
  order by l.saved_at desc, l.saved_id
  limit greatest(1, least(coalesce(p_limit, 500), 1000));
$$;

revoke execute on function public.list_saved_messages(integer) from public, anon;
grant execute on function public.list_saved_messages(integer) to authenticated;

-- The ids of the entries that match every word of [p_query] (up to eight
-- words, any case). A word matches the entry's own text (title, text, remark,
-- link, tags) as a whole word or run of CJK characters through the full-text
-- vector, or anywhere inside it; or the text of what it points to, read now
-- and only while the caller may see it.
create or replace function public.search_saved_items(p_query text)
returns table (saved_id uuid)
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  terms text[];
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  terms := array(
    select lower(btrim(t))
    from regexp_split_to_table(left(coalesce(p_query, ''), 200), '\s+') t
    where btrim(t) <> ''
    limit 8
  );
  if cardinality(terms) = 0 then
    return;
  end if;
  return query
  select l.saved_id
  from public.list_saved_items(1000) l
  join public.saved_items si on si.id = l.saved_id
  where not exists (
    select 1
    from unnest(terms) term
    where not (
      si.search_vector @@ phraseto_tsquery('simple', public.search_split_cjk(term))
      or position(term in public.saved_items_search_text(si)) > 0
      or position(term in lower(concat_ws(
        ' ',
        l.content_body,
        l.sender_display_name,
        l.webhook_name,
        l.extra->>'circle_name',
        l.extra->>'link_title',
        l.extra->>'attachment_name'
      ))) > 0
    )
  )
  order by l.saved_at desc, l.saved_id;
end;
$$;

revoke execute on function public.search_saved_items(text) from public, anon;
grant execute on function public.search_saved_items(text) to authenticated;
