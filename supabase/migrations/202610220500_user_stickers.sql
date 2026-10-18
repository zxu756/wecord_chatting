-- Personal stickers (A11), part 1 of 2: each person's own sticker library.
--
-- * user_stickers: one row per saved sticker (path, size, whether it moves,
--   and where it sits in the person's list). Owner only: RLS lets a person
--   read, add, reorder and delete their own rows and nobody else's. At most
--   300 per person (a trigger refuses the 301st with 54000).
-- * Storage: the private bucket user-stickers keeps the images at
--   <owner id>/<uuid>.<png|gif|webp>. Only the owner can read, write or
--   delete the objects of their own folder. The bucket limits a file to 1 MB
--   (the ceiling for an animated sticker) and to PNG, GIF and WebP. Nobody
--   else can read the library, not even a person the sticker was sent to:
--   sending (202610220510) copies the file into the chat's own folder in
--   chat-images, so the recipients read the copy and never the original.
-- * A row is only accepted for an object that exists in the owner's folder,
--   so a row cannot point at somebody else's file.
-- * reorder_user_stickers(ids) rewrites the order of the caller's list.
--
-- The cap is a trigger and not a policy so that the error is the same for the
-- app and for SQL. Deleting a row leaves the image to the client to remove,
-- the way circle emoji do; nothing points at an orphan.

create table if not exists public.user_stickers (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  path text not null unique,
  width integer not null check (width between 1 and 4096),
  height integer not null check (height between 1 and 4096),
  animated boolean not null default false,
  -- Ascending order; new stickers default to the front of the list.
  sort_key bigint not null
    default (-(extract(epoch from clock_timestamp()) * 1000000)::bigint),
  created_at timestamptz not null default now(),
  constraint user_stickers_path_format check (
    path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|gif|webp)$'
  ),
  -- Only formats that can move may be marked as animated.
  constraint user_stickers_animated_format check (
    not animated or path ~ '\.(gif|webp)$'
  )
);

create index if not exists user_stickers_owner_order_idx
  on public.user_stickers (owner_id, sort_key, created_at);

alter table public.user_stickers enable row level security;

revoke all on public.user_stickers from anon;
revoke all on public.user_stickers from authenticated;
grant select, insert, delete on public.user_stickers to authenticated;
-- Only the order may change.
grant update (sort_key) on public.user_stickers to authenticated;

drop policy if exists user_stickers_select_owner on public.user_stickers;
create policy user_stickers_select_owner
  on public.user_stickers for select
  to authenticated
  using (owner_id = auth.uid());

drop policy if exists user_stickers_insert_owner on public.user_stickers;
create policy user_stickers_insert_owner
  on public.user_stickers for insert
  to authenticated
  with check (owner_id = auth.uid());

drop policy if exists user_stickers_update_owner on public.user_stickers;
create policy user_stickers_update_owner
  on public.user_stickers for update
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists user_stickers_delete_owner on public.user_stickers;
create policy user_stickers_delete_owner
  on public.user_stickers for delete
  to authenticated
  using (owner_id = auth.uid());

-- The 300 limit, and "the file is there and is the owner's".
create or replace function public.user_stickers_check_insert()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  stored_size bigint;
begin
  if split_part(new.path, '/', 1) <> new.owner_id::text then
    raise exception 'A sticker file must be in its owner''s folder'
      using errcode = '42501';
  end if;

  select (o.metadata->>'size')::bigint
  into stored_size
  from storage.objects o
  where o.bucket_id = 'user-stickers'
    and o.name = new.path;

  if not found then
    raise exception 'Upload the image first' using errcode = '22023';
  end if;

  if new.animated and coalesce(stored_size, 0) > 1048576 then
    raise exception 'Animated stickers can be at most 1 MB'
      using errcode = '22023';
  end if;

  -- One person adding at a time, so two requests cannot both pass the count.
  perform pg_advisory_xact_lock(hashtextextended('user_stickers:' || new.owner_id::text, 0));

  if (
    select count(*) from public.user_stickers s where s.owner_id = new.owner_id
  ) >= 300 then
    raise exception 'You can keep at most 300 stickers'
      using errcode = '54000';
  end if;

  return new;
end;
$$;

revoke execute on function public.user_stickers_check_insert() from public, anon, authenticated;

drop trigger if exists user_stickers_check_insert on public.user_stickers;
create trigger user_stickers_check_insert
  before insert on public.user_stickers
  for each row execute function public.user_stickers_check_insert();

-- Puts the caller's stickers in the order of [sticker_ids]; ones the list
-- leaves out keep their relative order after it. Others' ids are ignored.
create or replace function public.reorder_user_stickers(sticker_ids uuid[])
returns void
language plpgsql
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.user_stickers s
  set sort_key = ordered.position
  from (
    select
      s2.id,
      row_number() over (
        order by coalesce(listed.ord, 1000000), s2.sort_key, s2.created_at
      ) as position
    from public.user_stickers s2
    left join (
      select i.id, min(i.ord) as ord
      from unnest(sticker_ids) with ordinality as i(id, ord)
      group by i.id
    ) listed on listed.id = s2.id
    where s2.owner_id = current_user_id
  ) ordered
  where s.id = ordered.id
    and s.owner_id = current_user_id;
end;
$$;

revoke execute on function public.reorder_user_stickers(uuid[]) from public, anon;
grant execute on function public.reorder_user_stickers(uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- Storage: the private bucket user-stickers, owner only.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'user-stickers',
  'user-stickers',
  false,
  1048576,
  array['image/png', 'image/gif', 'image/webp']
)
on conflict (id) do update
set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists user_stickers_storage_select_owner on storage.objects;
create policy user_stickers_storage_select_owner
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'user-stickers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists user_stickers_storage_insert_owner on storage.objects;
create policy user_stickers_storage_insert_owner
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'user-stickers'
    and (storage.foldername(name))[1] = auth.uid()::text
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|gif|webp)$'
  );

drop policy if exists user_stickers_storage_delete_owner on storage.objects;
create policy user_stickers_storage_delete_owner
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'user-stickers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
