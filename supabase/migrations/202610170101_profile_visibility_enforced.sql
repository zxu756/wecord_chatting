-- "Who can see my profile" for every way of reading a profile.
--
-- 202610170024_profile_visibility.sql applied the setting
-- (user_privacy_settings.profile_visibility: everyone, friends_and_circles or
-- friends) in get_profile_summary only. The profile-only fields it covers,
-- bio, pronouns and banner, could still be read by anyone signed in:
--
--   * straight from public.profiles (its select policy is "any signed-in
--     user", and the columns were granted with the table),
--   * in the sender and member profiles the app embeds with messages and group
--     members (profiles(..., bio, ...)),
--   * in what circle details, forum posts and comments, pinned messages,
--     reactors, poll voters and circle events return about people,
--   * as the banner file itself: any signed-in user could list and read the
--     profile-banners bucket.
--
-- Now:
--
--   1. can_view_profile_details(target) is the one rule: the person
--      themselves, or anyone the setting lets in, unless the person blocked
--      them. get_profile_summary has the same rule inline and stays as it is.
--   2. Table privileges: SELECT on public.profiles is granted by column, and
--      bio, banner_url and pronouns are not among them. Names, usernames,
--      avatars, status, bot and deleted flags and timestamps are what chat
--      needs and stay readable. The three fields are read through
--      get_profile_summary (anyone, with the rule applied) and get_my_profile
--      (the caller's own, for the profile editor). Because a column list now
--      decides what `select *` may read, a column added to profiles later
--      needs its own grant select (column) ... to authenticated.
--   3. The functions that put other people's profiles into their results
--      return the bio through visible_profile_bio, which is empty for anyone
--      who may not see it. They are patched in place from their current
--      definition below, so this does not depend on which migration last
--      replaced them.
--   4. The banner files follow the same rule.
--
-- The bot API (bot_api_*) returns only id, username, name and the bot flag of
-- authors, and list_friends_with_aliases returns friends, who may see every
-- setting, so neither needs a change.
--
-- Deploy the app before this: an app from before reads bio in message and
-- member embeds, which is no longer allowed and fails until it is reloaded.

-- 1. The rule.
create or replace function public.can_view_profile_details(target_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  viewer uuid := auth.uid();
  setting text;
begin
  if viewer is null or target_user_id is null then
    return false;
  end if;
  if viewer = target_user_id then
    return true;
  end if;

  -- People who blocked the viewer show them nothing.
  if exists (
    select 1
    from public.blocks b
    where b.blocker_id = target_user_id
      and b.blocked_id = viewer
  ) then
    return false;
  end if;

  select ups.profile_visibility
  into setting
  from public.user_privacy_settings ups
  where ups.user_id = target_user_id;
  setting := coalesce(setting, 'everyone');

  if setting = 'everyone' then
    return true;
  end if;

  if exists (
    select 1
    from public.friendships f
    where f.user_low_id = least(viewer, target_user_id)
      and f.user_high_id = greatest(viewer, target_user_id)
  ) then
    return true;
  end if;

  return setting = 'friends_and_circles' and exists (
    select 1
    from public.circle_members mine
    join public.circle_members theirs
      on theirs.circle_id = mine.circle_id
      and theirs.user_id = target_user_id
    where mine.user_id = viewer
  );
end;
$$;

-- [bio] of [target_user_id] for the caller: the text where the caller may see
-- it, else an empty string.
create or replace function public.visible_profile_bio(
  target_user_id uuid,
  bio text
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when public.can_view_profile_details(target_user_id) then coalesce(bio, '')
    else ''
  end;
$$;

revoke execute on function public.can_view_profile_details(uuid) from public, anon;
grant execute on function public.can_view_profile_details(uuid) to authenticated;
revoke execute on function public.visible_profile_bio(uuid, text) from public, anon;
grant execute on function public.visible_profile_bio(uuid, text) to authenticated;

-- 2. Column privileges.
revoke select on public.profiles from anon, authenticated;
grant select (
  id,
  username,
  display_name,
  avatar_url,
  created_at,
  updated_at,
  status_emoji,
  status_text,
  status_expires_at,
  deleted_at,
  display_circle_tag_id,
  is_bot
) on public.profiles to authenticated;

-- The caller's own profile, all of it (the profile editor and settings).
create or replace function public.get_my_profile()
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  bio text,
  created_at timestamptz,
  updated_at timestamptz,
  banner_url text,
  pronouns text,
  custom_status jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.username,
    p.display_name,
    p.avatar_url,
    p.bio,
    p.created_at,
    p.updated_at,
    p.banner_url,
    p.pronouns,
    public.custom_status(p)
  from public.profiles p
  where p.id = auth.uid();
$$;

revoke execute on function public.get_my_profile() from public, anon;
grant execute on function public.get_my_profile() to authenticated;

-- 3. Functions that return other people's profiles. Each is rewritten from
-- its current definition: `'bio', x.bio` (a JSON field) and `x.bio,` on a
-- line of its own (a result column) become
-- public.visible_profile_bio(x.id, x.bio). A function that is missing is a
-- mistake in this list; one that has nothing to patch (already done) is left.
do $patch$
declare
  function_name text;
  target record;
  found_any boolean;
  original text;
  patched text;
begin
  foreach function_name in array array[
    'circle_event_profile',
    'forum_post_payload',
    'get_circle_detail',
    'list_message_reactors',
    'list_pinned_messages',
    'list_poll_voters'
  ] loop
    found_any := false;
    for target in
      select p.oid
      from pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname = function_name
    loop
      found_any := true;
      original := pg_get_functiondef(target.oid);
      patched := regexp_replace(
        original,
        E'(''bio'',\\s*)(\\w+)\\.bio\\M',
        E'\\1public.visible_profile_bio(\\2.id, \\2.bio)',
        'g'
      );
      patched := regexp_replace(
        patched,
        E'(\\n\\s*)(\\w+)\\.bio,(?=\\n)',
        E'\\1public.visible_profile_bio(\\2.id, \\2.bio) as bio,',
        'g'
      );
      if patched ~ E'''bio'',\\s*\\w+\\.bio\\M'
        or patched ~ E'\\n\\s*\\w+\\.bio,\\n'
      then
        raise exception 'Could not hide the bio in %', function_name;
      end if;
      if patched = original then
        if original !~ 'visible_profile_bio' then
          raise exception 'No bio to hide in %', function_name;
        end if;
      else
        execute patched;
      end if;
    end loop;
    if not found_any then
      raise exception 'Function % does not exist', function_name;
    end if;
  end loop;
end;
$patch$;

-- 4. Banner files: the owner, and whoever may see the profile.
drop policy if exists profile_banners_select_authenticated on storage.objects;
create policy profile_banners_select_authenticated
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'profile-banners'
    and case
      when (storage.foldername(name))[1]
        ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then public.can_view_profile_details(((storage.foldername(name))[1])::uuid)
      else false
    end
  );
