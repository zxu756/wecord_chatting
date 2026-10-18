-- Status bubbles (B4): who can see my custom status.
--
-- A custom status (202610130010) is an emoji and a short text with an
-- optional expiry. It was visible to every signed-in user. Now its owner
-- chooses who sees it:
--
--   everyone  the way it always was (the default, so nothing changes for
--             anyone who does not choose)
--   friends   my friends
--   starred   the friends I starred (friend_stars; a star is the owner's
--             private note, the friend never learns of it)
--   self      only me
--
-- The rule lives in public.custom_status(profiles), the one function every
-- result that carries a status goes through (profile summary, circle
-- members, direct chat rows, the new bubble list). It is a security definer
-- function now: whoever asks gets null for a status they may not see, and
-- null for a status that expired. Nobody sees the status of a person who
-- blocked them. The raw status_emoji, status_text and status_expires_at
-- columns are no longer readable by clients at all (they would walk around
-- the rule); the app never read them directly.
--
-- custom_status is 202610130010_custom_status with one more branch (the
-- visibility check); its expiry rule is unchanged.

alter table public.profiles
  add column if not exists status_visibility text not null default 'everyone';

alter table public.profiles
  drop constraint if exists profiles_status_visibility_check;
alter table public.profiles
  add constraint profiles_status_visibility_check check (
    status_visibility in ('everyone', 'friends', 'starred', 'self')
  );

-- Whether the caller may see the status of [owner_id] whose choice is
-- [visibility]. Internal: custom_status() calls it.
create or replace function public.status_visible_to_caller(
  owner_id uuid,
  visibility text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  viewer uuid := auth.uid();
begin
  if viewer is null then
    return false;
  end if;
  if viewer = owner_id then
    return true;
  end if;

  -- Someone who blocked the viewer shows them nothing.
  if exists (
    select 1
    from public.blocks b
    where b.blocker_id = owner_id
      and b.blocked_id = viewer
  ) then
    return false;
  end if;

  if visibility = 'everyone' then
    return true;
  end if;
  if visibility = 'self' then
    return false;
  end if;

  if not exists (
    select 1
    from public.friendships f
    where f.user_low_id = least(viewer, owner_id)
      and f.user_high_id = greatest(viewer, owner_id)
  ) then
    return false;
  end if;
  if visibility = 'friends' then
    return true;
  end if;

  -- starred: the owner's own star on the viewer.
  return exists (
    select 1
    from public.friend_stars s
    where s.owner_id = status_visible_to_caller.owner_id
      and s.friend_id = viewer
  );
end;
$$;

revoke execute on function public.status_visible_to_caller(uuid, text)
  from public, anon, authenticated;

create or replace function public.custom_status(profile_row public.profiles)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case
    when profile_row.status_emoji is null and profile_row.status_text is null
      then null
    when profile_row.status_expires_at is not null
      and profile_row.status_expires_at <= now()
      then null
    when not public.status_visible_to_caller(
      profile_row.id,
      profile_row.status_visibility
    )
      then null
    else jsonb_build_object(
      'emoji', profile_row.status_emoji,
      'text', profile_row.status_text,
      'expires_at', profile_row.status_expires_at
    )
  end;
$$;

-- Clients read statuses only through custom_status(). The raw columns were
-- granted with the other chat columns in 202610170101.
revoke select (status_emoji, status_text, status_expires_at)
  on public.profiles from authenticated;

-- Saves who sees my status. Returns the stored choice.
create or replace function public.set_status_visibility(visibility text)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if visibility is null
    or visibility not in ('everyone', 'friends', 'starred', 'self')
  then
    raise exception 'Choose everyone, friends, starred friends or only me'
      using errcode = '22023';
  end if;

  update public.profiles p
  set status_visibility = set_status_visibility.visibility
  where p.id = auth.uid();
  if not found then
    raise exception 'Profile not found' using errcode = '42501';
  end if;
  return visibility;
end;
$$;

revoke execute on function public.set_status_visibility(text) from public, anon;
grant execute on function public.set_status_visibility(text) to authenticated;

-- The statuses of my friends that I may see right now, for the bubbles above
-- their avatars. A friend with no status, an expired one, one meant for
-- others (starred, self) or one who blocked me is not in the list: it is
-- exactly what custom_status() lets through. Bots and deleted accounts are
-- left out.
create or replace function public.list_friend_statuses()
returns table (
  user_id uuid,
  emoji text,
  status_text text,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    s.status ->> 'emoji',
    s.status ->> 'text',
    (s.status ->> 'expires_at')::timestamptz
  from public.friendships f
  join public.profiles p
    on p.id = case
      when f.user_low_id = auth.uid() then f.user_high_id
      else f.user_low_id
    end
  cross join lateral (select public.custom_status(p) as status) s
  where auth.uid() in (f.user_low_id, f.user_high_id)
    and not p.is_bot
    and p.deleted_at is null
    and s.status is not null;
$$;

revoke execute on function public.list_friend_statuses() from public, anon;
grant execute on function public.list_friend_statuses() to authenticated;

-- My own choice, for the status editor. (get_my_profile keeps its columns.)
create or replace function public.get_my_status_visibility()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select p.status_visibility from public.profiles p where p.id = auth.uid();
$$;

revoke execute on function public.get_my_status_visibility() from public, anon;
grant execute on function public.get_my_status_visibility() to authenticated;
