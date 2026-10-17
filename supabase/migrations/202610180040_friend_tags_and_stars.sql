-- Friend tags and starred friends.
--
-- Both are the owner's private notes about their friends, like contact
-- aliases: nobody else can read or write them, and the friend never learns
-- about either.
--
-- * friend_tags: a named group of friends ("Family", "Work"). Names are
--   unique per owner (ignoring case and surrounding spaces), 1 to 30
--   characters.
-- * friend_tag_members: which friends are in which tag. owner_id repeats the
--   tag's owner so the row level security checks stay a plain comparison. A
--   friend can only be put in a tag while they are a friend.
-- * friend_stars: starred friends, listed first and under a "Starred" header.
--
-- Unfriending (or blocking, which removes the friendship) removes the
-- friend from the owner's tags and stars, so nothing stale is left behind
-- that a later friendship could pick up again.
--
-- Moments (202610180041) uses tags as audiences for "Only share with" and
-- "Don't share with".

create table if not exists public.friend_tags (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint friend_tags_name_length check (char_length(btrim(name)) between 1 and 30)
);

create unique index if not exists friend_tags_owner_name_idx
  on public.friend_tags (owner_id, lower(btrim(name)));

create table if not exists public.friend_tag_members (
  tag_id uuid not null references public.friend_tags(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (tag_id, friend_id),
  constraint friend_tag_members_not_self check (owner_id <> friend_id)
);

create index if not exists friend_tag_members_owner_friend_idx
  on public.friend_tag_members (owner_id, friend_id);

create table if not exists public.friend_stars (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, friend_id),
  constraint friend_stars_not_self check (owner_id <> friend_id)
);

alter table public.friend_tags enable row level security;
alter table public.friend_tag_members enable row level security;
alter table public.friend_stars enable row level security;

revoke all on public.friend_tags from anon, authenticated;
revoke all on public.friend_tag_members from anon, authenticated;
revoke all on public.friend_stars from anon, authenticated;
grant select, insert, update, delete on public.friend_tags to authenticated;
grant select, insert, delete on public.friend_tag_members to authenticated;
grant select, insert, delete on public.friend_stars to authenticated;

-- A tag is its owner's.
drop policy if exists friend_tags_select_own on public.friend_tags;
create policy friend_tags_select_own
  on public.friend_tags for select
  to authenticated
  using (owner_id = auth.uid());

drop policy if exists friend_tags_insert_own on public.friend_tags;
create policy friend_tags_insert_own
  on public.friend_tags for insert
  to authenticated
  with check (owner_id = auth.uid());

drop policy if exists friend_tags_update_own on public.friend_tags;
create policy friend_tags_update_own
  on public.friend_tags for update
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists friend_tags_delete_own on public.friend_tags;
create policy friend_tags_delete_own
  on public.friend_tags for delete
  to authenticated
  using (owner_id = auth.uid());

-- Members: only of the owner's own tags, and only friends.
drop policy if exists friend_tag_members_select_own on public.friend_tag_members;
create policy friend_tag_members_select_own
  on public.friend_tag_members for select
  to authenticated
  using (owner_id = auth.uid());

drop policy if exists friend_tag_members_insert_own on public.friend_tag_members;
create policy friend_tag_members_insert_own
  on public.friend_tag_members for insert
  to authenticated
  with check (
    owner_id = auth.uid()
    and exists (
      select 1
      from public.friend_tags t
      where t.id = tag_id
        and t.owner_id = auth.uid()
    )
    and exists (
      select 1
      from public.friendships f
      where f.user_low_id = least(auth.uid(), friend_id)
        and f.user_high_id = greatest(auth.uid(), friend_id)
    )
  );

drop policy if exists friend_tag_members_delete_own on public.friend_tag_members;
create policy friend_tag_members_delete_own
  on public.friend_tag_members for delete
  to authenticated
  using (owner_id = auth.uid());

drop policy if exists friend_stars_select_own on public.friend_stars;
create policy friend_stars_select_own
  on public.friend_stars for select
  to authenticated
  using (owner_id = auth.uid());

drop policy if exists friend_stars_insert_own on public.friend_stars;
create policy friend_stars_insert_own
  on public.friend_stars for insert
  to authenticated
  with check (
    owner_id = auth.uid()
    and exists (
      select 1
      from public.friendships f
      where f.user_low_id = least(auth.uid(), friend_id)
        and f.user_high_id = greatest(auth.uid(), friend_id)
    )
  );

drop policy if exists friend_stars_delete_own on public.friend_stars;
create policy friend_stars_delete_own
  on public.friend_stars for delete
  to authenticated
  using (owner_id = auth.uid());

-- A tag's owner never changes, and its name is kept tidy.
create or replace function public.friend_tags_before_write()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.name := btrim(new.name);
  if tg_op = 'UPDATE' then
    new.owner_id := old.owner_id;
    new.created_at := old.created_at;
    new.updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists friend_tags_before_write on public.friend_tags;
create trigger friend_tags_before_write
  before insert or update on public.friend_tags
  for each row execute function public.friend_tags_before_write();

-- A tag holds friends of its owner only: the member row must carry the
-- tag's owner (the policy checks the caller; this keeps the copy honest).
create or replace function public.friend_tag_members_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  tag_owner uuid;
begin
  select owner_id into tag_owner from public.friend_tags where id = new.tag_id;
  if tag_owner is null or tag_owner <> new.owner_id then
    raise exception 'That tag belongs to someone else' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function public.friend_tag_members_before_insert() from public, anon, authenticated;

drop trigger if exists friend_tag_members_before_insert on public.friend_tag_members;
create trigger friend_tag_members_before_insert
  before insert on public.friend_tag_members
  for each row execute function public.friend_tag_members_before_insert();

-- Unfriending and blocking take the friend out of the owner's tags and stars,
-- on both sides.
create or replace function public.forget_friend_tags_and_stars()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.friend_tag_members
  where (owner_id = old.user_low_id and friend_id = old.user_high_id)
     or (owner_id = old.user_high_id and friend_id = old.user_low_id);
  delete from public.friend_stars
  where (owner_id = old.user_low_id and friend_id = old.user_high_id)
     or (owner_id = old.user_high_id and friend_id = old.user_low_id);
  return old;
end;
$$;

revoke execute on function public.forget_friend_tags_and_stars() from public, anon, authenticated;

drop trigger if exists friendships_forget_tags_and_stars on public.friendships;
create trigger friendships_forget_tags_and_stars
  after delete on public.friendships
  for each row execute function public.forget_friend_tags_and_stars();
