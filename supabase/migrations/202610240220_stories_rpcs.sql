-- Daily (B1), part 3 of 6: posting, watching, "who viewed", replying.
--
-- Every function is security definer, checks the caller, and asks
-- story_visible_to (202610240210) for what a person may see.
--
--   create_story            posts a daily whose files the app has uploaded
--                           (the same id again changes nothing)
--   delete_story            removes one of the caller's own
--   stories_tray            who has dailies for me: my own first, then
--                           friends with something new, then the rest
--   list_author_stories     one person's dailies I may see, oldest first
--   mark_story_viewed       I opened a daily (never the author's own)
--   list_story_viewers      who viewed and reacted: the author only
--   react_to_story          a quick emoji (null takes it back)
--   send_story_reply        a reply = a private chat message with a
--                           story_ref attachment. Chat rules apply: friends
--                           only, not blocked, a conversation the caller may
--                           write in.
--   get_story_ref           what the reply card shows (thumbnail, kind) while
--                           the daily is still visible to the caller
--   list_close_friends / set_close_friends
--                           the author's close friends list

-- ------------------------------------------------------------ posting

create or replace function public.create_story(
  p_id uuid,
  p_kind text,
  p_ext text default 'mp4',
  p_caption text default '',
  p_visibility text default 'friends',
  p_friend_ids uuid[] default '{}',
  p_tag_ids uuid[] default '{}',
  p_width integer default 0,
  p_height integer default 0,
  p_duration_ms integer default null,
  p_size bigint default 0
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  prefix text;
  media text;
  poster text;
  thumb text;
  friend_ids uuid[];
  tag_ids uuid[];
  stored_size bigint;
  video_size bigint;
  mime_type text;
  live integer;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_id is null then
    raise exception 'A daily needs an id' using errcode = '22023';
  end if;
  if exists (select 1 from public.stories where id = p_id) then
    if exists (select 1 from public.stories where id = p_id and author_id = me) then
      return p_id;
    end if;
    raise exception 'That daily id is taken' using errcode = '23505';
  end if;
  if p_kind is null or p_kind not in ('photo', 'video') then
    raise exception 'A daily is a photo or a video' using errcode = '22023';
  end if;
  if p_visibility is null
    or p_visibility not in ('friends', 'close', 'private', 'only', 'except')
  then
    raise exception 'Unknown audience' using errcode = '22023';
  end if;

  -- Counted one person at a time.
  perform pg_advisory_xact_lock(hashtextextended('story_create:' || me::text, 0));
  select count(*)::integer into live
  from public.stories s
  where s.author_id = me and s.expires_at > now();
  if live >= 50 then
    raise exception 'You have 50 dailies up. Wait for one to end or delete one.'
      using errcode = '54000';
  end if;

  prefix := me::text || '/' || p_id::text;
  thumb := prefix || '-t.jpg';
  if p_kind = 'photo' then
    media := prefix || '.jpg';
    poster := null;
    mime_type := 'image/jpeg';
  else
    if p_ext is null or p_ext not in ('mp4', 'mov', 'webm') then
      raise exception 'Videos are MP4, MOV or WebM' using errcode = '22023';
    end if;
    media := prefix || '-v.' || p_ext;
    poster := prefix || '.jpg';
    mime_type := case p_ext
      when 'mp4' then 'video/mp4'
      when 'mov' then 'video/quicktime'
      else 'video/webm'
    end;
    -- 15 seconds, and a second of slack for rounding.
    if p_duration_ms is null or p_duration_ms < 1 or p_duration_ms > 16000 then
      raise exception 'A video can be at most 15 seconds' using errcode = '22023';
    end if;
  end if;

  -- The files are in storage by now, and within the limit.
  if not exists (
    select 1 from storage.objects o where o.bucket_id = 'stories' and o.name = thumb
  ) then
    raise exception 'The thumbnail was not uploaded' using errcode = '22023';
  end if;
  select (o.metadata->>'size')::bigint into stored_size
  from storage.objects o
  where o.bucket_id = 'stories' and o.name = media;
  if not found then
    raise exception 'The picture or video was not uploaded' using errcode = '22023';
  end if;
  if p_kind = 'video' and not exists (
    select 1 from storage.objects o where o.bucket_id = 'stories' and o.name = poster
  ) then
    raise exception 'The video has no poster picture' using errcode = '22023';
  end if;
  video_size := coalesce(stored_size, p_size, 0);
  if video_size > 20971520 then
    raise exception 'A daily can be at most 20 MB' using errcode = '22023';
  end if;

  -- Only friends can be chosen, only the author's own tags.
  select coalesce(array_agg(distinct f.id), '{}') into friend_ids
  from unnest(coalesce(p_friend_ids, '{}')) as f(id)
  where public.moments_are_friends(me, f.id);
  select coalesce(array_agg(t.id), '{}') into tag_ids
  from public.friend_tags t
  where t.owner_id = me
    and t.id = any (coalesce(p_tag_ids, '{}'));
  if p_visibility in ('friends', 'close', 'private') then
    friend_ids := '{}';
    tag_ids := '{}';
  end if;
  if p_visibility in ('only', 'except')
    and cardinality(friend_ids) = 0
    and cardinality(tag_ids) = 0
  then
    raise exception 'Choose at least one friend or tag' using errcode = '22023';
  end if;
  if p_visibility = 'close' and not exists (
    select 1 from public.story_close_friends cf where cf.owner_id = me
  ) then
    raise exception 'Add close friends first' using errcode = '22023';
  end if;

  insert into public.stories (
    id, author_id, media_kind, media_path, poster_path, thumb_path, width,
    height, duration_ms, size, mime, caption, visibility,
    audience_friend_ids, audience_tag_ids
  )
  values (
    p_id, me, p_kind, media, poster, thumb,
    greatest(coalesce(p_width, 0), 0), greatest(coalesce(p_height, 0), 0),
    case when p_kind = 'video' then p_duration_ms end,
    video_size, mime_type,
    left(btrim(coalesce(p_caption, '')), 200),
    p_visibility, friend_ids, tag_ids
  );
  return p_id;
end;
$$;

create or replace function public.delete_story(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  -- The files are queued for removal by the trigger of 202610240240.
  delete from public.stories where id = p_id and author_id = me;
end;
$$;

-- ----------------------------------------------------------- watching

-- Who has dailies I may see, with how many are new to me. My own row comes
-- first (when I have any), then friends with something new, newest first.
-- Friends whose Moments I chose to hide are left out.
create or replace function public.stories_tray()
returns table (
  author_id uuid,
  display_name text,
  avatar_url text,
  is_me boolean,
  story_count integer,
  unseen_count integer,
  latest_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  return query
  select
    s.author_id,
    p.display_name,
    p.avatar_url,
    (s.author_id = me) as is_me,
    count(*)::integer as story_count,
    (count(*) filter (
      where s.author_id <> me
        and not exists (
          select 1 from public.story_views v
          where v.story_id = s.id and v.viewer_id = me
        )
    ))::integer as unseen_count,
    max(s.created_at) as latest_at
  from public.stories s
  join public.profiles p on p.id = s.author_id
  where s.expires_at > now()
    -- Only friends can have a daily for me: narrow it down before the rule.
    and (
      s.author_id = me
      or exists (
        select 1
        from public.friendships f
        where f.user_low_id = least(me, s.author_id)
          and f.user_high_id = greatest(me, s.author_id)
      )
    )
    and public.story_visible_to(s, me)
    and (
      s.author_id = me
      or not exists (
        select 1
        from public.moments_friend_prefs fp
        where fp.owner_id = me
          and fp.friend_id = s.author_id
          and fp.hide_theirs
      )
    )
  group by s.author_id, p.display_name, p.avatar_url
  order by
    (s.author_id = me) desc,
    (count(*) filter (
      where s.author_id <> me
        and not exists (
          select 1 from public.story_views v
          where v.story_id = s.id and v.viewer_id = me
        )
    ) > 0) desc,
    max(s.created_at) desc
  limit 100;
end;
$$;

-- One person's dailies I may see, oldest first. The author also gets the
-- number of viewers and reactions; everybody else gets zeros.
create or replace function public.list_author_stories(p_author_id uuid)
returns table (
  id uuid,
  author_id uuid,
  media_kind text,
  media_path text,
  poster_path text,
  thumb_path text,
  width integer,
  height integer,
  duration_ms integer,
  size bigint,
  mime text,
  caption text,
  visibility text,
  created_at timestamptz,
  expires_at timestamptz,
  viewed boolean,
  my_reaction text,
  view_count integer,
  reaction_count integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  return query
  select
    s.id, s.author_id, s.media_kind, s.media_path, s.poster_path,
    s.thumb_path, s.width, s.height, s.duration_ms, s.size, s.mime,
    s.caption, s.visibility, s.created_at, s.expires_at,
    (s.author_id = me or exists (
      select 1 from public.story_views v
      where v.story_id = s.id and v.viewer_id = me
    )) as viewed,
    (select r.emoji from public.story_reactions r
      where r.story_id = s.id and r.user_id = me) as my_reaction,
    case when s.author_id = me then (
      select count(*)::integer from public.story_views v
      join public.profiles vp on vp.id = v.viewer_id and vp.deleted_at is null
      where v.story_id = s.id
        and public.moments_are_friends(s.author_id, v.viewer_id)
    ) else 0 end as view_count,
    case when s.author_id = me then (
      select count(*)::integer from public.story_reactions r
      join public.profiles rp on rp.id = r.user_id and rp.deleted_at is null
      where r.story_id = s.id
        and public.moments_are_friends(s.author_id, r.user_id)
    ) else 0 end as reaction_count
  from public.stories s
  where s.author_id = p_author_id
    and public.story_visible_to(s, me)
  order by s.created_at, s.id;
end;
$$;

create or replace function public.mark_story_viewed(p_story_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  s public.stories%rowtype;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into s from public.stories where id = p_story_id;
  if s.id is null or s.author_id = me or not public.story_visible_to(s, me) then
    return;
  end if;
  insert into public.story_views (story_id, viewer_id)
  values (s.id, me)
  on conflict (story_id, viewer_id) do nothing;
end;
$$;

-- Who viewed one of my dailies, and with what emoji, latest first. The
-- author only. People who have since been unfriended or blocked, or whose
-- account is gone, are left out.
create or replace function public.list_story_viewers(p_story_id uuid)
returns table (
  viewer_id uuid,
  display_name text,
  avatar_url text,
  viewed_at timestamptz,
  emoji text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  s public.stories%rowtype;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into s from public.stories where id = p_story_id;
  if s.id is null or s.author_id <> me or s.expires_at <= now() then
    raise exception 'Daily not found' using errcode = 'P0002';
  end if;
  return query
  select v.viewer_id, p.display_name, p.avatar_url, v.viewed_at, r.emoji
  from public.story_views v
  join public.profiles p on p.id = v.viewer_id and p.deleted_at is null
  left join public.story_reactions r
    on r.story_id = v.story_id and r.user_id = v.viewer_id
  where v.story_id = s.id
    and public.moments_are_friends(me, v.viewer_id)
  order by v.viewed_at desc, v.viewer_id
  limit 500;
end;
$$;

-- A quick emoji on a daily I may see (one per person; null or empty takes it
-- back). Never on my own.
create or replace function public.react_to_story(
  p_story_id uuid,
  p_emoji text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  s public.stories%rowtype;
  clean text := btrim(coalesce(p_emoji, ''));
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into s from public.stories where id = p_story_id;
  if s.id is null or not public.story_visible_to(s, me) then
    raise exception 'Daily not found' using errcode = 'P0002';
  end if;
  if s.author_id = me then
    raise exception 'You cannot react to your own daily' using errcode = '22023';
  end if;
  if clean = '' then
    delete from public.story_reactions where story_id = s.id and user_id = me;
    return;
  end if;
  if char_length(clean) > 16 then
    raise exception 'That is not an emoji' using errcode = '22023';
  end if;
  insert into public.story_reactions (story_id, user_id, emoji)
  values (s.id, me, clean)
  on conflict (story_id, user_id) do update
  set emoji = excluded.emoji, created_at = now();
  -- Reacting counts as having seen it.
  insert into public.story_views (story_id, viewer_id)
  values (s.id, me)
  on conflict (story_id, viewer_id) do nothing;
end;
$$;

-- --------------------------------------------------------- replying

-- Replies to a daily: an ordinary text message in the private chat with the
-- author, carrying {kind: story_ref, story_id, owner_id, media_kind}. The
-- chat's own rules decide whether it can be sent: get_or_create_direct_
-- conversation needs friends who have not blocked each other, and the
-- caller must be allowed to write in it. [p_client_id] makes a retry of the
-- same send return the same message.
create or replace function public.send_story_reply(
  p_story_id uuid,
  p_body text,
  p_client_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  s public.stories%rowtype;
  conversation uuid;
  trimmed text := btrim(coalesce(p_body, ''));
  created_message_id uuid;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if p_client_id is not null then
    select m.id into created_message_id
    from public.messages m
    where m.sender_id = me and m.client_id = p_client_id;
    if created_message_id is not null then
      return created_message_id;
    end if;
  end if;

  if char_length(trimmed) = 0 or char_length(trimmed) > 2000 then
    raise exception 'Write a reply' using errcode = '22023';
  end if;

  select * into s from public.stories where id = p_story_id;
  if s.id is null or not public.story_visible_to(s, me) then
    raise exception 'Daily not found' using errcode = 'P0002';
  end if;
  if s.author_id = me then
    raise exception 'You cannot reply to your own daily' using errcode = '22023';
  end if;

  conversation := public.get_or_create_direct_conversation(s.author_id);
  if not public.is_current_user_conversation_member(conversation)
    or not public.can_current_user_send_in_conversation(conversation)
    or public.is_current_user_blocked_in_conversation(conversation)
  then
    raise exception 'Cannot send messages in this conversation'
      using errcode = '42501';
  end if;

  insert into public.messages (
    conversation_id, sender_id, type, body, attachment, client_id
  )
  values (
    conversation, me, 'text', trimmed,
    jsonb_build_object(
      'kind', 'story_ref',
      'story_id', s.id,
      'owner_id', s.author_id,
      'media_kind', s.media_kind
    ),
    p_client_id
  )
  returning id into created_message_id;
  return created_message_id;
end;
$$;

-- What the reply card shows: the daily's kind and thumbnail path while it is
-- still visible to the caller; no row once it has ended or been taken back.
create or replace function public.get_story_ref(p_story_id uuid)
returns table (
  story_id uuid,
  author_id uuid,
  media_kind text,
  thumb_path text,
  expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  return query
  select s.id, s.author_id, s.media_kind, s.thumb_path, s.expires_at
  from public.stories s
  where s.id = p_story_id
    and public.story_visible_to(s, me);
end;
$$;

-- ------------------------------------------------------ close friends

create or replace function public.list_close_friends()
returns table (friend_id uuid)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  return query
  select cf.friend_id
  from public.story_close_friends cf
  where cf.owner_id = me
    and public.moments_are_friends(me, cf.friend_id)
  order by cf.created_at, cf.friend_id;
end;
$$;

-- Replaces my close friends with [p_friend_ids] (friends only, 500 at most).
create or replace function public.set_close_friends(p_friend_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  wanted uuid[];
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select coalesce(array_agg(distinct f.id), '{}') into wanted
  from unnest(coalesce(p_friend_ids, '{}')) as f(id)
  where public.moments_are_friends(me, f.id);
  if cardinality(wanted) > 500 then
    raise exception 'At most 500 close friends' using errcode = '22023';
  end if;
  delete from public.story_close_friends cf
  where cf.owner_id = me and not (cf.friend_id = any (wanted));
  insert into public.story_close_friends (owner_id, friend_id)
  select me, w.id from unnest(wanted) as w(id)
  on conflict (owner_id, friend_id) do nothing;
end;
$$;

revoke execute on function public.create_story(uuid, text, text, text, text, uuid[], uuid[], integer, integer, integer, bigint) from public, anon;
revoke execute on function public.delete_story(uuid) from public, anon;
revoke execute on function public.stories_tray() from public, anon;
revoke execute on function public.list_author_stories(uuid) from public, anon;
revoke execute on function public.mark_story_viewed(uuid) from public, anon;
revoke execute on function public.list_story_viewers(uuid) from public, anon;
revoke execute on function public.react_to_story(uuid, text) from public, anon;
revoke execute on function public.send_story_reply(uuid, text, uuid) from public, anon;
revoke execute on function public.get_story_ref(uuid) from public, anon;
revoke execute on function public.list_close_friends() from public, anon;
revoke execute on function public.set_close_friends(uuid[]) from public, anon;
grant execute on function public.create_story(uuid, text, text, text, text, uuid[], uuid[], integer, integer, integer, bigint) to authenticated;
grant execute on function public.delete_story(uuid) to authenticated;
grant execute on function public.stories_tray() to authenticated;
grant execute on function public.list_author_stories(uuid) to authenticated;
grant execute on function public.mark_story_viewed(uuid) to authenticated;
grant execute on function public.list_story_viewers(uuid) to authenticated;
grant execute on function public.react_to_story(uuid, text) to authenticated;
grant execute on function public.send_story_reply(uuid, text, uuid) to authenticated;
grant execute on function public.get_story_ref(uuid) to authenticated;
grant execute on function public.list_close_friends() to authenticated;
grant execute on function public.set_close_friends(uuid[]) to authenticated;
