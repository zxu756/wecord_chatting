-- Daily (B1), part 2 of 6: who may see a daily, and the private bucket.
--
-- story_visible_to(s, viewer) is the one rule; everything else (the row
-- policy, the Storage read policy, the tray, the viewer and the reply)
-- asks it. It is the Moments rule (moments_post_visible_to, 202610180041)
-- with a clock on it:
--   * a daily past expires_at is seen by nobody, the author included;
--   * a deleted account's dailies are seen by nobody;
--   * the author sees their own;
--   * everyone else must be a friend of the author and neither blocked the
--     other (moments_are_friends; unfriending and blocking cut access at
--     once because nothing is copied);
--   * "Don't let them see my Moments" (moments_friend_prefs.hide_mine) hides
--     the author's dailies from that friend too;
--   * then the daily's own audience: friends, close friends, only me, only
--     share with / don't share with (friends and tags, read live).
-- It is internal; the app goes through story_can_view, which asks only about
-- the signed-in person.
--
-- Storage: the bucket "stories" is private, 20 MB a file. Only the author
-- writes and removes their folder; reading a file needs the daily it
-- belongs to to be visible (the same function), or, for a platform admin,
-- an open report about that daily (202610240230).

-- ------------------------------------------------------ close friends

-- Unfriending (blocking unfriends) takes the person off both close lists.
create or replace function public.forget_story_close_friend()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.story_close_friends
  where (owner_id = old.user_low_id and friend_id = old.user_high_id)
     or (owner_id = old.user_high_id and friend_id = old.user_low_id);
  return old;
end;
$$;

revoke execute on function public.forget_story_close_friend() from public, anon, authenticated;

drop trigger if exists friendships_forget_story_close_friend on public.friendships;
create trigger friendships_forget_story_close_friend
  after delete on public.friendships
  for each row execute function public.forget_story_close_friend();

-- --------------------------------------------------------- the rule

create or replace function public.story_visible_to(
  s public.stories,
  viewer uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  in_audience boolean;
begin
  if viewer is null or s.id is null then
    return false;
  end if;
  if s.expires_at <= now() then
    return false;
  end if;
  if exists (
    select 1
    from public.profiles p
    where p.id = s.author_id
      and p.deleted_at is not null
  ) then
    return false;
  end if;
  if s.author_id = viewer then
    return true;
  end if;
  if s.visibility = 'private' then
    return false;
  end if;
  if not public.moments_are_friends(viewer, s.author_id) then
    return false;
  end if;
  -- "Don't let them see my Moments"
  if exists (
    select 1
    from public.moments_friend_prefs fp
    where fp.owner_id = s.author_id
      and fp.friend_id = viewer
      and fp.hide_mine
  ) then
    return false;
  end if;

  if s.visibility = 'friends' then
    return true;
  end if;
  if s.visibility = 'close' then
    return exists (
      select 1
      from public.story_close_friends cf
      where cf.owner_id = s.author_id
        and cf.friend_id = viewer
    );
  end if;

  in_audience := viewer = any (s.audience_friend_ids)
    or exists (
      select 1
      from public.friend_tag_members m
      where m.owner_id = s.author_id
        and m.friend_id = viewer
        and m.tag_id = any (s.audience_tag_ids)
    );
  if s.visibility = 'only' then
    return in_audience;
  end if;
  -- except
  return not in_audience;
end;
$$;

-- The signed-in person may see the daily [target_story_id].
create or replace function public.story_can_view(target_story_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.stories s
    where s.id = target_story_id
      and public.story_visible_to(s, auth.uid())
  );
$$;

revoke execute on function public.story_visible_to(public.stories, uuid) from public, anon, authenticated;
revoke execute on function public.story_can_view(uuid) from public, anon;
grant execute on function public.story_can_view(uuid) to authenticated;

drop policy if exists stories_select_visible on public.stories;
create policy stories_select_visible
  on public.stories for select
  to authenticated
  using (public.story_can_view(id));

-- --------------------------------------------------------- the bucket

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'stories',
  'stories',
  false,
  20971520,
  array[
    'image/jpeg', 'image/png', 'image/webp',
    'video/mp4', 'video/quicktime', 'video/webm'
  ]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Whether the signed-in person may read the object [object_name] of the
-- stories bucket: <author id>/<story id>.jpg, <story id>-t.jpg or
-- <story id>-v.<ext>, while that daily is visible to them. A file with no
-- daily (not made yet, or already gone) is read by nobody.
create or replace function public.story_can_read_object(object_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uuid_pattern constant text := '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
  owner_text text := split_part(object_name, '/', 1);
  file_name text := split_part(object_name, '/', 2);
  owner_id uuid;
  story_id uuid;
  st public.stories%rowtype;
begin
  if auth.uid() is null or split_part(object_name, '/', 3) <> '' then
    return false;
  end if;
  if owner_text !~ ('^' || uuid_pattern || '$')
    or file_name !~ ('^' || uuid_pattern || '(-t\.jpg|\.jpg|-v\.(mp4|mov|webm))$')
  then
    return false;
  end if;
  owner_id := owner_text::uuid;
  story_id := substring(file_name from '^(' || uuid_pattern || ')')::uuid;

  select * into st
  from public.stories s
  where s.id = story_id
    and s.author_id = owner_id;
  if st.id is null then
    return false;
  end if;
  if public.story_visible_to(st, auth.uid()) then
    return true;
  end if;
  -- A platform admin reads a reported daily while the report is open.
  return public.is_app_admin()
    and exists (
      select 1
      from public.story_reports r
      where r.story_id = st.id
        and r.status = 'open'
    );
end;
$$;

revoke execute on function public.story_can_read_object(text) from public, anon;
grant execute on function public.story_can_read_object(text) to authenticated;

drop policy if exists stories_select_visible on storage.objects;
create policy stories_select_visible
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'stories'
    and public.story_can_read_object(name)
  );

drop policy if exists stories_insert_owner on storage.objects;
create policy stories_insert_owner
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'stories'
    and (storage.foldername(name))[1] = auth.uid()::text
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(-t\.jpg|\.jpg|-v\.(mp4|mov|webm))$'
  );

drop policy if exists stories_delete_owner on storage.objects;
create policy stories_delete_owner
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'stories'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
