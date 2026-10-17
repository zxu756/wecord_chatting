-- Chat wallpapers: the picture behind the messages. Personal, and it follows
-- the user to their other devices; changing it never changes what anyone
-- else sees.
--
-- * chat_wallpapers: one row per user for their default wallpaper
--   (conversation_id is null) and one per conversation they gave its own.
--   No row means "use the default" (for a conversation) or the plain paper
--   background (for the default). kind is 'none' (plain background, also a
--   way to opt one chat out of a default), 'preset' (a wallpaper drawn in
--   the app, named by preset_id) or 'photo' (photo_path in the private
--   wallpapers bucket, with the dim used in dark mode, an optional blur and
--   where the photo is positioned: focus_x/focus_y, -1 to 1). Owner-only
--   row level security: nobody reads or writes another person's rows.
-- * set_chat_wallpaper / clear_chat_wallpaper: the writes (one row per
--   scope, replaced in place). Both answer with the photo path the change
--   left unused, which the app removes from the bucket.
-- * Bucket wallpapers (private, 3 MB, JPEG/PNG/WebP): <user id>/<uuid>.<ext>.
--   Only the owner reads, writes and removes their folder. The app scales
--   photos down and compresses them before uploading.
-- * The table is in the Realtime publication so a change on one device shows
--   on the others.

create table if not exists public.chat_wallpapers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  conversation_id uuid references public.conversations(id) on delete cascade,
  kind text not null check (kind in ('none', 'preset', 'photo')),
  preset_id text,
  photo_path text,
  dim real not null default 0.4 check (dim >= 0 and dim <= 1),
  blur boolean not null default false,
  focus_x real not null default 0 check (focus_x >= -1 and focus_x <= 1),
  focus_y real not null default 0 check (focus_y >= -1 and focus_y <= 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chat_wallpapers_shape check (
    (kind = 'none' and preset_id is null and photo_path is null)
    or (
      kind = 'preset'
      and preset_id is not null
      and preset_id ~ '^[a-z0-9-]{1,40}$'
      and photo_path is null
    )
    or (
      kind = 'photo'
      and preset_id is null
      and photo_path is not null
      and photo_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'
      and split_part(photo_path, '/', 1) = user_id::text
    )
  )
);

create unique index if not exists chat_wallpapers_default_idx
  on public.chat_wallpapers (user_id)
  where conversation_id is null;

create unique index if not exists chat_wallpapers_conversation_idx
  on public.chat_wallpapers (user_id, conversation_id)
  where conversation_id is not null;

create index if not exists chat_wallpapers_conversation_lookup_idx
  on public.chat_wallpapers (conversation_id)
  where conversation_id is not null;

alter table public.chat_wallpapers enable row level security;

revoke all on public.chat_wallpapers from anon, authenticated;
grant select, insert, update, delete on public.chat_wallpapers to authenticated;

drop policy if exists chat_wallpapers_select_own on public.chat_wallpapers;
create policy chat_wallpapers_select_own
  on public.chat_wallpapers for select
  to authenticated
  using (user_id = auth.uid());

-- A wallpaper for a conversation needs a conversation the person can read.
drop policy if exists chat_wallpapers_insert_own on public.chat_wallpapers;
create policy chat_wallpapers_insert_own
  on public.chat_wallpapers for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and (
      conversation_id is null
      or conversation_id in (select public.current_user_readable_conversation_ids())
    )
  );

drop policy if exists chat_wallpapers_update_own on public.chat_wallpapers;
create policy chat_wallpapers_update_own
  on public.chat_wallpapers for update
  to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and (
      conversation_id is null
      or conversation_id in (select public.current_user_readable_conversation_ids())
    )
  );

drop policy if exists chat_wallpapers_delete_own on public.chat_wallpapers;
create policy chat_wallpapers_delete_own
  on public.chat_wallpapers for delete
  to authenticated
  using (user_id = auth.uid());

-- The row's owner, conversation and creation time never change.
create or replace function public.chat_wallpapers_before_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.user_id := old.user_id;
  new.conversation_id := old.conversation_id;
  new.created_at := old.created_at;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists chat_wallpapers_before_update on public.chat_wallpapers;
create trigger chat_wallpapers_before_update
  before update on public.chat_wallpapers
  for each row execute function public.chat_wallpapers_before_update();

-- Sets the wallpaper for [target_conversation_id] (null: the default).
-- Returns the photo path the previous wallpaper used when this change left
-- it unused, so the app can remove it from the bucket.
create or replace function public.set_chat_wallpaper(
  target_conversation_id uuid,
  wallpaper_kind text,
  wallpaper_preset_id text default null,
  wallpaper_photo_path text default null,
  wallpaper_dim real default 0.4,
  wallpaper_blur boolean default false,
  wallpaper_focus_x real default 0,
  wallpaper_focus_y real default 0
)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  me uuid := auth.uid();
  previous_path text;
begin
  if me is null then
    raise exception 'Sign in to change the wallpaper' using errcode = '28000';
  end if;

  if target_conversation_id is null then
    select photo_path into previous_path
    from public.chat_wallpapers
    where user_id = me and conversation_id is null;
  else
    select photo_path into previous_path
    from public.chat_wallpapers
    where user_id = me and conversation_id = target_conversation_id;
  end if;

  if target_conversation_id is null then
    insert into public.chat_wallpapers (
      user_id, conversation_id, kind, preset_id, photo_path, dim, blur, focus_x, focus_y
    )
    values (
      me, null, wallpaper_kind, wallpaper_preset_id, wallpaper_photo_path,
      coalesce(wallpaper_dim, 0.4), coalesce(wallpaper_blur, false),
      coalesce(wallpaper_focus_x, 0), coalesce(wallpaper_focus_y, 0)
    )
    on conflict (user_id) where conversation_id is null
    do update set
      kind = excluded.kind,
      preset_id = excluded.preset_id,
      photo_path = excluded.photo_path,
      dim = excluded.dim,
      blur = excluded.blur,
      focus_x = excluded.focus_x,
      focus_y = excluded.focus_y;
  else
    insert into public.chat_wallpapers (
      user_id, conversation_id, kind, preset_id, photo_path, dim, blur, focus_x, focus_y
    )
    values (
      me, target_conversation_id, wallpaper_kind, wallpaper_preset_id,
      wallpaper_photo_path, coalesce(wallpaper_dim, 0.4),
      coalesce(wallpaper_blur, false), coalesce(wallpaper_focus_x, 0),
      coalesce(wallpaper_focus_y, 0)
    )
    on conflict (user_id, conversation_id) where conversation_id is not null
    do update set
      kind = excluded.kind,
      preset_id = excluded.preset_id,
      photo_path = excluded.photo_path,
      dim = excluded.dim,
      blur = excluded.blur,
      focus_x = excluded.focus_x,
      focus_y = excluded.focus_y;
  end if;

  if previous_path is not null and previous_path is distinct from wallpaper_photo_path then
    return previous_path;
  end if;
  return null;
end;
$$;

-- Removes the wallpaper of [target_conversation_id] (null: the default), so
-- the conversation follows the default again. Returns the photo path that
-- is no longer used.
create or replace function public.clear_chat_wallpaper(target_conversation_id uuid)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  me uuid := auth.uid();
  removed_path text;
begin
  if me is null then
    raise exception 'Sign in to change the wallpaper' using errcode = '28000';
  end if;

  if target_conversation_id is null then
    delete from public.chat_wallpapers
    where user_id = me and conversation_id is null
    returning photo_path into removed_path;
  else
    delete from public.chat_wallpapers
    where user_id = me and conversation_id = target_conversation_id
    returning photo_path into removed_path;
  end if;
  return removed_path;
end;
$$;

revoke execute on function public.set_chat_wallpaper(uuid, text, text, text, real, boolean, real, real) from public, anon;
revoke execute on function public.clear_chat_wallpaper(uuid) from public, anon;
grant execute on function public.set_chat_wallpaper(uuid, text, text, text, real, boolean, real, real) to authenticated;
grant execute on function public.clear_chat_wallpaper(uuid) to authenticated;

-- Changes show up on the person's other devices.
alter table public.chat_wallpapers replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'chat_wallpapers'
  ) then
    alter publication supabase_realtime add table public.chat_wallpapers;
  end if;
end $$;

-- ------------------------------------------------------------------ photos

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'wallpapers',
  'wallpapers',
  false,
  3145728,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists wallpapers_select_owner on storage.objects;
create policy wallpapers_select_owner
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'wallpapers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists wallpapers_insert_owner on storage.objects;
create policy wallpapers_insert_owner
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'wallpapers'
    and (storage.foldername(name))[1] = auth.uid()::text
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'
  );

drop policy if exists wallpapers_update_owner on storage.objects;
create policy wallpapers_update_owner
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'wallpapers'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'wallpapers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists wallpapers_delete_owner on storage.objects;
create policy wallpapers_delete_owner
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'wallpapers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
