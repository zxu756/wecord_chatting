-- Chat folders: the person's own way to sort the chat list ("Work", "Family",
-- "Unread", a folded group chats row).
--
-- A folder stores RULES only. The chat list is already on the device, so the
-- app filters it there; nothing here reads conversations, messages or
-- members, and a folder never changes what anybody else sees.
--
-- * include_types: which kinds of chat the folder takes by itself
--   (direct / group / channel). Empty means "no chat by its kind".
-- * include_ids: chats that are always in the folder, whatever the filters
--   below say. exclude_ids: chats that are never in it. The ids are not
--   foreign keys (an array cannot be); the app ignores ids of chats the
--   person no longer has.
-- * only_unread / exclude_muted / only_muted: filters on the chats taken by
--   kind. A folder cannot ask for muted chats and no muted chats at once.
-- * folded: the folder's chats leave the main list and show as one row
--   ("Folded group chats"). At most one folder per person is folded.
-- * sort_key: the order of the folders (1, 2, 3 ...); reorder_chat_folders
--   sets it for a whole list at once.
--
-- Owner-only row level security, at most 20 folders per person (a trigger
-- counts them under a lock, so two devices cannot both add the 21st), and
-- the table is in the Realtime publication so a change on one device shows
-- on the others.

create table if not exists public.chat_folders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  icon text not null default 'folder',
  sort_key integer not null default 0,
  include_types text[] not null default '{}',
  include_ids uuid[] not null default '{}',
  exclude_ids uuid[] not null default '{}',
  only_unread boolean not null default false,
  exclude_muted boolean not null default false,
  only_muted boolean not null default false,
  folded boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chat_folders_name_length check (char_length(btrim(name)) between 1 and 30),
  constraint chat_folders_icon_shape check (icon ~ '^[a-z0-9_]{1,30}$'),
  constraint chat_folders_types check (
    include_types <@ array['direct', 'group', 'channel']::text[]
  ),
  constraint chat_folders_id_counts check (
    cardinality(include_ids) <= 500 and cardinality(exclude_ids) <= 500
  ),
  constraint chat_folders_muted_filters check (not (exclude_muted and only_muted))
);

create index if not exists chat_folders_user_order_idx
  on public.chat_folders (user_id, sort_key, created_at);

-- One folded folder per person.
create unique index if not exists chat_folders_one_folded_idx
  on public.chat_folders (user_id)
  where folded;

alter table public.chat_folders enable row level security;

revoke all on public.chat_folders from anon, authenticated;
grant select, insert, update, delete on public.chat_folders to authenticated;

drop policy if exists chat_folders_select_own on public.chat_folders;
create policy chat_folders_select_own
  on public.chat_folders for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists chat_folders_insert_own on public.chat_folders;
create policy chat_folders_insert_own
  on public.chat_folders for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists chat_folders_update_own on public.chat_folders;
create policy chat_folders_update_own
  on public.chat_folders for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists chat_folders_delete_own on public.chat_folders;
create policy chat_folders_delete_own
  on public.chat_folders for delete
  to authenticated
  using (user_id = (select auth.uid()));

-- At most 20 folders per person. The lock makes two inserts of the same
-- person take turns, so the count each one sees is the real one.
create or replace function public.chat_folders_before_insert()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('chat_folders:' || new.user_id::text, 0));
  if (
    select count(*) from public.chat_folders where user_id = new.user_id
  ) >= 20 then
    raise exception 'You can have at most 20 chat folders'
      using errcode = '23514', constraint = 'chat_folders_limit';
  end if;
  return new;
end;
$$;

drop trigger if exists chat_folders_before_insert on public.chat_folders;
create trigger chat_folders_before_insert
  before insert on public.chat_folders
  for each row execute function public.chat_folders_before_insert();

-- The owner and the creation time never change.
create or replace function public.chat_folders_before_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.user_id := old.user_id;
  new.created_at := old.created_at;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists chat_folders_before_update on public.chat_folders;
create trigger chat_folders_before_update
  before update on public.chat_folders
  for each row execute function public.chat_folders_before_update();

-- Puts the caller's folders in the order of [folder_ids] (first = top).
-- Folders that are not the caller's, or not listed, are left alone; row
-- level security keeps other people's rows out of reach anyway.
create or replace function public.reorder_chat_folders(folder_ids uuid[])
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Sign in to arrange chat folders' using errcode = '28000';
  end if;
  update public.chat_folders as folder
  set sort_key = ordered.position
  from unnest(folder_ids) with ordinality as ordered(id, position)
  where folder.id = ordered.id
    and folder.user_id = me;
end;
$$;

revoke execute on function public.chat_folders_before_insert() from public, anon, authenticated;
revoke execute on function public.chat_folders_before_update() from public, anon, authenticated;
revoke execute on function public.reorder_chat_folders(uuid[]) from public, anon;
grant execute on function public.reorder_chat_folders(uuid[]) to authenticated;

-- Changes show up on the person's other devices.
alter table public.chat_folders replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'chat_folders'
  ) then
    alter publication supabase_realtime add table public.chat_folders;
  end if;
end $$;
