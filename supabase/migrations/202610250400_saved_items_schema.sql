-- Favorites 2.0 (roadmap B3), part 1 of 4: one place for everything a person
-- keeps, folders, tags, and the old saved messages moved in.
--
-- * saved_items: one row per thing the person keeps. kind says what:
--     message      a chat message (target_id, conversation_id)
--     moment       a Moment (target_id)
--     circle_post  a circle feed post (target_id, circle_id)
--     link         a web link the person pasted (url, title)
--     note         the person's own note, with a title and/or up to four
--                  pictures (title, body, images)
--     text         the person's own words with no title (body)
--   Anything written by somebody else is only a reference. The row never
--   copies its text, so what the person can see is decided every time by the
--   rules of the thing itself (messages: recall, expiry, AI guard, view-once;
--   Moments: friends, audience, blocks; posts: membership, take-down). When
--   they say no the entry reads "no longer visible" and can only be removed.
--   The only text stored is the person's own: title, body, note, tags, url.
-- * saved_folders: the person's folders (up to 50, one level, unique names).
-- * saved_messages stays, as a view of the message rows with the columns it
--   had, so older apps keep listing, marking done and removing. The rows were
--   moved here with the same ids; done_at (the old "mark done") is kept.
-- * search_vector is a 'simple' tsvector of the person's own text with every
--   CJK character as its own word (search_split_cjk, 202610160043).
--
-- Account deletion: prepare_account_deletion (202610160017) keeps the
-- profile, so the foreign keys never fire; a trigger on profiles.deleted_at
-- erases the person's folders and entries. The delete-account function
-- empties their folder of the saved-notes bucket (202610250420).
--
-- Tables are closed to clients except for reading and deleting one's own
-- rows; every write goes through the RPCs of the next migrations.

create table if not exists public.saved_folders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  constraint saved_folders_name_length
    check (char_length(btrim(name)) between 1 and 40)
);

create unique index if not exists saved_folders_user_name_key
  on public.saved_folders (user_id, lower(btrim(name)));

alter table public.saved_folders enable row level security;
revoke all on public.saved_folders from public, anon, authenticated;
grant select, delete on public.saved_folders to authenticated;

drop policy if exists saved_folders_select_own on public.saved_folders;
create policy saved_folders_select_own
  on public.saved_folders for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists saved_folders_delete_own on public.saved_folders;
create policy saved_folders_delete_own
  on public.saved_folders for delete
  to authenticated
  using (user_id = auth.uid());

create table if not exists public.saved_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null,
  -- The message, Moment or post. Not a foreign key: when it goes away the
  -- entry stays, as "no longer visible", until the person removes it.
  target_id uuid,
  conversation_id uuid references public.conversations(id) on delete cascade,
  circle_id uuid,
  folder_id uuid references public.saved_folders(id) on delete set null,
  tags text[] not null default '{}',
  -- The person's own remark on any entry.
  note text,
  -- The person's own words: a link's title, a note's title and text.
  title text,
  body text,
  url text,
  -- [{"path": "<user>/<entry>-0.jpg", "w": 1280, "h": 960}]
  images jsonb not null default '[]'::jsonb,
  done_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  search_vector tsvector not null default ''::tsvector,
  constraint saved_items_kind check (
    kind in ('message', 'moment', 'circle_post', 'link', 'note', 'text')
  ),
  constraint saved_items_shape check (
    (kind = 'message' and conversation_id is not null)
    or (kind in ('moment', 'circle_post') and target_id is not null)
    or (kind = 'link' and url is not null)
    or (kind = 'note' and (
      nullif(btrim(coalesce(title, '')), '') is not null
      or nullif(btrim(coalesce(body, '')), '') is not null
      or jsonb_array_length(images) > 0
    ))
    or (kind = 'text' and nullif(btrim(coalesce(body, '')), '') is not null)
  ),
  constraint saved_items_tags check (cardinality(tags) <= 10),
  constraint saved_items_note_length check (char_length(coalesce(note, '')) <= 1000),
  constraint saved_items_title_length check (char_length(coalesce(title, '')) <= 200),
  constraint saved_items_body_length check (char_length(coalesce(body, '')) <= 20000),
  constraint saved_items_url_length check (char_length(coalesce(url, '')) <= 2000),
  constraint saved_items_images check (
    jsonb_typeof(images) = 'array' and jsonb_array_length(images) <= 4
  )
);

-- A message, Moment or post is kept once.
create unique index if not exists saved_items_user_target_key
  on public.saved_items (user_id, kind, target_id)
  where target_id is not null and kind in ('message', 'moment', 'circle_post');

create unique index if not exists saved_items_user_link_key
  on public.saved_items (user_id, url)
  where kind = 'link';

create index if not exists saved_items_user_idx
  on public.saved_items (user_id, created_at desc);

create index if not exists saved_items_folder_idx
  on public.saved_items (folder_id)
  where folder_id is not null;

create index if not exists saved_items_search_idx
  on public.saved_items using gin (search_vector);

-- ------------------------------------------------------------- the rows

-- Tags as the person typed them, tidied: no "#", spaces folded, at most 24
-- characters, no empty or repeated ones (case aside), at most ten.
create or replace function public.normalize_saved_tags(raw text[])
returns text[]
language sql
immutable
set search_path = public
as $$
  select coalesce(array_agg(t.tag order by t.position), '{}'::text[])
  from (
    select c.tag, c.position
    from (
      select distinct on (lower(x.tag)) x.tag, x.position
      from (
        select
          btrim(left(
            regexp_replace(btrim(regexp_replace(u.tag, '^\s*#+', '')), '\s+', ' ', 'g'),
            24
          )) as tag,
          u.position
        from unnest(coalesce(raw, '{}'::text[])) with ordinality as u(tag, position)
      ) x
      where x.tag <> ''
      order by lower(x.tag), x.position
    ) c
    order by c.position
    limit 10
  ) t;
$$;

-- The text of the person's own that search looks through.
create or replace function public.saved_items_search_text(item public.saved_items)
returns text
language sql
immutable
set search_path = public
as $$
  select lower(concat_ws(
    ' ',
    item.title,
    item.body,
    item.note,
    item.url,
    array_to_string(item.tags, ' ')
  ));
$$;

create or replace function public.saved_items_before_write()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.tags := public.normalize_saved_tags(new.tags);
  new.title := nullif(btrim(coalesce(new.title, '')), '');
  new.note := nullif(btrim(coalesce(new.note, '')), '');
  new.search_vector := to_tsvector(
    'simple',
    public.search_split_cjk(public.saved_items_search_text(new))
  );
  if tg_op = 'UPDATE' then
    new.updated_at := now();
  end if;
  return new;
end;
$$;

revoke execute on function public.saved_items_before_write() from public, anon, authenticated;

drop trigger if exists saved_items_before_write on public.saved_items;
create trigger saved_items_before_write
  before insert or update on public.saved_items
  for each row execute function public.saved_items_before_write();

alter table public.saved_items enable row level security;
revoke all on public.saved_items from public, anon, authenticated;
grant select, delete on public.saved_items to authenticated;

drop policy if exists saved_items_select_own on public.saved_items;
create policy saved_items_select_own
  on public.saved_items for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists saved_items_delete_own on public.saved_items;
create policy saved_items_delete_own
  on public.saved_items for delete
  to authenticated
  using (user_id = auth.uid());

-- ------------------------------------------- the old saved messages move

do $$
begin
  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'saved_messages'
      and c.relkind = 'r'
  ) then
    insert into public.saved_items (
      id, user_id, kind, target_id, conversation_id, done_at, created_at,
      updated_at
    )
    select
      s.id, s.user_id, 'message', s.message_id, s.conversation_id, s.done_at,
      s.created_at, s.created_at
    from public.saved_messages s
    on conflict (id) do nothing;
    drop table public.saved_messages;
  end if;
end;
$$;

-- What older apps read and delete: the message rows, as they were. Reads
-- and deletes run as the caller, so the row policy above still decides.
create or replace view public.saved_messages
with (security_invoker = true)
as
  select
    i.id,
    i.user_id,
    i.target_id as message_id,
    i.conversation_id,
    i.created_at,
    i.done_at
  from public.saved_items i
  where i.kind = 'message';

revoke all on public.saved_messages from public, anon, authenticated;
grant select, delete on public.saved_messages to authenticated;

-- ------------------------------------------------------ account deletion

create or replace function public.erase_favorites_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.saved_items where user_id = new.id;
  delete from public.saved_folders where user_id = new.id;
  return new;
end;
$$;

revoke execute on function public.erase_favorites_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_erase_favorites on public.profiles;
create trigger profiles_erase_favorites
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_favorites_of_deleted_account();
