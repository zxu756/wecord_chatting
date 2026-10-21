-- Group space (roadmap B6), part 1 of 4: the tables, and keeping the files.
--
-- A group chat gets a place for what should outlive the scroll: albums for
-- pictures and videos (event photos, trips) and folders for files (notes,
-- handouts). An album or a folder holds
--
--   * a picture, video or file that was sent in the chat, kept by reference
--     (nothing is copied: the entry names the same Storage object the message
--     does), or
--   * a file uploaded straight to the space, stored in the same chat buckets
--     under <conversation id>/space/..., so the existing rules for who can
--     read and write there apply as they are (members read, people who may
--     send upload).
--
-- Rules fixed by the roadmap:
--   * group chats only (a direct chat has no admin to tidy up; channels have
--     their own tools);
--   * view-once media and anything in a chat with disappearing messages on
--     cannot be added, and while the timer is on nothing is added at all, so
--     a file cannot vanish from under an album;
--   * who sees it: whoever sees the chat; who adds: whoever may send there;
--     who removes: the person who added it, and the group's owner and admins.
--
-- The tables are closed to clients like the other newer features: the RPCs of
-- the next migrations are the only way in.
--
-- Keeping the files. Deleting (recalling) the message a picture came from
-- queues its file for removal (recalled_message_media). An entry in a group
-- space is a reason to keep that file, so a BEFORE INSERT trigger on that
-- queue drops the request while an album or folder still names the file. When
-- the last entry goes, the RPCs put the file in the queue themselves (as the
-- person who removed it), and the client then removes it through Storage as it
-- does for a deleted message. recall_message and the other functions that feed
-- the queue are not rewritten.

create table if not exists public.conversation_albums (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  name text not null,
  cover_item_id uuid,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint conversation_albums_name check (char_length(btrim(name)) between 1 and 40)
);
create unique index if not exists conversation_albums_name_unique
  on public.conversation_albums (conversation_id, lower(btrim(name)));
create index if not exists conversation_albums_conversation_idx
  on public.conversation_albums (conversation_id, updated_at desc);

create table if not exists public.album_items (
  id uuid primary key default gen_random_uuid(),
  album_id uuid not null references public.conversation_albums(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  source_message_id uuid references public.messages(id) on delete set null,
  bucket text not null,
  path text not null,
  kind text not null,
  name text not null,
  mime_type text not null default '',
  size bigint not null default 0,
  width integer,
  height integer,
  -- What the picture shows, for people who cannot see it (roadmap L8).
  alt text,
  blurhash text,
  added_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint album_items_kind check (kind in ('image', 'video')),
  constraint album_items_bucket check (
    (kind = 'image' and bucket = 'chat-images')
    or (kind = 'video' and bucket = 'chat-files')
  ),
  constraint album_items_path check (
    char_length(path) between 3 and 300
    and path !~ '\.\.'
    and path like conversation_id::text || '/%'
  ),
  constraint album_items_name check (char_length(name) between 1 and 200),
  constraint album_items_size check (size between 0 and 104857600),
  constraint album_items_alt check (alt is null or char_length(alt) between 1 and 1000)
);
create unique index if not exists album_items_album_file_unique
  on public.album_items (album_id, bucket, path);
create index if not exists album_items_album_idx
  on public.album_items (album_id, created_at desc);
create index if not exists album_items_conversation_idx
  on public.album_items (conversation_id);
create index if not exists album_items_file_idx
  on public.album_items (bucket, path);
create index if not exists album_items_added_by_idx
  on public.album_items (added_by);

alter table public.conversation_albums
  drop constraint if exists conversation_albums_cover_fk;
alter table public.conversation_albums
  add constraint conversation_albums_cover_fk
  foreign key (cover_item_id) references public.album_items(id) on delete set null;

create table if not exists public.conversation_folders (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  name text not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint conversation_folders_name check (char_length(btrim(name)) between 1 and 40)
);
create unique index if not exists conversation_folders_name_unique
  on public.conversation_folders (conversation_id, lower(btrim(name)));

-- folder_id null: the file sits at the top of the group's files.
create table if not exists public.folder_files (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  folder_id uuid references public.conversation_folders(id) on delete cascade,
  source_message_id uuid references public.messages(id) on delete set null,
  bucket text not null,
  path text not null,
  kind text not null,
  name text not null,
  mime_type text not null default '',
  size bigint not null default 0,
  alt text,
  added_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint folder_files_kind check (kind in ('image', 'video', 'file')),
  constraint folder_files_bucket check (
    bucket = 'chat-files' or (bucket = 'chat-images' and kind = 'image')
  ),
  constraint folder_files_path check (
    char_length(path) between 3 and 300
    and path !~ '\.\.'
    and path like conversation_id::text || '/%'
  ),
  constraint folder_files_name check (char_length(btrim(name)) between 1 and 200),
  constraint folder_files_size check (size between 0 and 104857600),
  constraint folder_files_alt check (alt is null or char_length(alt) between 1 and 1000)
);
create unique index if not exists folder_files_place_unique
  on public.folder_files (
    conversation_id,
    coalesce(folder_id, '00000000-0000-0000-0000-000000000000'::uuid),
    bucket,
    path
  );
create index if not exists folder_files_folder_idx
  on public.folder_files (conversation_id, folder_id, created_at desc);
create index if not exists folder_files_file_idx
  on public.folder_files (bucket, path);
create index if not exists folder_files_added_by_idx
  on public.folder_files (added_by);

alter table public.conversation_albums enable row level security;
alter table public.album_items enable row level security;
alter table public.conversation_folders enable row level security;
alter table public.folder_files enable row level security;
revoke all on public.conversation_albums from public, anon, authenticated;
revoke all on public.album_items from public, anon, authenticated;
revoke all on public.conversation_folders from public, anon, authenticated;
revoke all on public.folder_files from public, anon, authenticated;

-- ---------------------------------------------------------------- helpers

-- Whether an album or a folder still names the file.
create or replace function public.group_space_file_in_use(
  p_bucket text,
  p_path text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.album_items i where i.bucket = p_bucket and i.path = p_path
  ) or exists (
    select 1 from public.folder_files f where f.bucket = p_bucket and f.path = p_path
  );
$$;

revoke execute on function public.group_space_file_in_use(text, text)
  from public, anon, authenticated;

-- A deleted message's file stays while the group space keeps it.
create or replace function public.recalled_media_keep_space_files()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.group_space_file_in_use(new.bucket_id, new.object_path) then
    return null;
  end if;
  return new;
end;
$$;

revoke execute on function public.recalled_media_keep_space_files()
  from public, anon, authenticated;

drop trigger if exists recalled_media_keep_space_files on public.recalled_message_media;
create trigger recalled_media_keep_space_files
  before insert on public.recalled_message_media
  for each row execute function public.recalled_media_keep_space_files();

-- The one place that decides who may touch a group's space.
--   'read'  a member of the group chat;
--   'tidy'  also not suspended and allowed to send there (renaming, removing);
--   'add'   also with disappearing messages off.
-- Returns whether the caller is an owner or admin of the group. Refused with
-- 42501 (not allowed) or 22023 (not possible here).
create or replace function public.group_space_access(
  p_conversation_id uuid,
  p_mode text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  conversation record;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_mode not in ('read', 'tidy', 'add') then
    raise exception 'Unknown mode' using errcode = '22023';
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
    raise exception 'Only group chats have a group space' using errcode = '22023';
  end if;

  if p_mode in ('tidy', 'add') then
    if public.is_user_suspended(current_user_id) then
      raise exception 'Account suspended' using errcode = '42501';
    end if;
    if not public.can_current_user_send_in_conversation(p_conversation_id) then
      raise exception 'You cannot add to this group chat' using errcode = '42501';
    end if;
  end if;
  if p_mode = 'add' and conversation.disappear_after_seconds is not null then
    raise exception 'The group space is off while disappearing messages are on'
      using errcode = '22023';
  end if;

  return exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id = p_conversation_id
      and cm.user_id = current_user_id
      and cm.role in ('owner', 'admin')
  );
end;
$$;

revoke execute on function public.group_space_access(uuid, text)
  from public, anon, authenticated;

-- How many bytes the group space refers to, so one group cannot fill Storage.
create or replace function public.group_space_bytes(p_conversation_id uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select sum(i.size) from public.album_items i
                   where i.conversation_id = p_conversation_id), 0)
       + coalesce((select sum(f.size) from public.folder_files f
                   where f.conversation_id = p_conversation_id), 0);
$$;

revoke execute on function public.group_space_bytes(uuid)
  from public, anon, authenticated;

-- Puts the files nobody names any more in the queue the client removes them
-- from (as the caller), and answers which they are. A file a message, an
-- event, another album or another folder still names stays.
create or replace function public.group_space_release_files(
  p_buckets text[],
  p_paths text[]
)
returns table (bucket_id text, object_path text)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  candidate record;
begin
  for candidate in
    select distinct f.b, f.p
    from unnest(p_buckets, p_paths) as f(b, p)
  loop
    if public.group_space_file_in_use(candidate.b, candidate.p)
      or exists (
        select 1 from public.messages m
        where m.attachment->>'path' = candidate.p
          and m.attachment->>'bucket' = candidate.b
      )
      or exists (
        select 1 from public.event_photos ph
        where ph.bucket = candidate.b and ph.path = candidate.p
      )
    then
      continue;
    end if;

    insert into public.recalled_message_media as r (bucket_id, object_path, message_id, deleted_by)
    values (candidate.b, candidate.p, null, current_user_id)
    on conflict on constraint recalled_message_media_pkey do update
    set deleted_by = excluded.deleted_by, created_at = now();

    bucket_id := candidate.b;
    object_path := candidate.p;
    return next;
  end loop;
end;
$$;

revoke execute on function public.group_space_release_files(text[], text[])
  from public, anon, authenticated;

-- A name as people write it: trimmed, inner runs of spaces kept as typed.
create or replace function public.group_space_clean_name(p_name text)
returns text
language sql
immutable
set search_path = public
as $$
  select nullif(btrim(coalesce(p_name, '')), '');
$$;

revoke execute on function public.group_space_clean_name(text)
  from public, anon, authenticated;
