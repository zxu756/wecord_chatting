-- Moments 2.0 (roadmap B2), part 2 of 6: posting and pinning.
--
-- * create_moment (latest before this: 202610190022_moments_video.sql), the
--   same function with two changes:
--     - a video can be 3 minutes (a second of slack for rounding, so 181000
--       ms), no longer 1; the 50 MB limit stays (longer needs L4 and a plan);
--     - [p_mentioned_ids] ("Remind who to read"): the people to remind. Only
--       the author's friends who can see this very post are kept
--       (moments_post_visible_to for the post as stored, so "Only me", a
--       list that leaves them out, "Don't let them see my Moments", the
--       visible range and blocks all count), at most 30 asked for. Each kept
--       person gets one 'mention' notification (the Moments section of the
--       inbox and, through claim_moments_pushes, a push) and a live signal.
--       Posting the same id again changes nothing and reminds nobody twice.
--   Everything else is copied from the earlier definition: file names, the
--   video checks, links, audience clean-up.
-- * set_moment_pinned: the author pins or unpins their own post; three pinned
--   posts at most.

drop function if exists public.create_moment(uuid, text, jsonb, text, text, text, text, uuid[], uuid[], jsonb);

create or replace function public.create_moment(
  p_id uuid,
  p_body text default '',
  p_photos jsonb default '[]'::jsonb,
  p_link_url text default null,
  p_link_title text default null,
  p_location text default null,
  p_visibility text default 'friends',
  p_friend_ids uuid[] default '{}',
  p_tag_ids uuid[] default '{}',
  p_video jsonb default null,
  p_mentioned_ids uuid[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  body_text text := btrim(coalesce(p_body, ''));
  post_kind text;
  photo jsonb;
  photo_count integer;
  friend_ids uuid[];
  tag_ids uuid[];
  prefix text;
  index_value integer := 0;
  video_value jsonb;
  video_ext text;
  video_duration integer;
  video_size bigint;
  stored_size bigint;
  asked uuid[];
  kept uuid[];
  stored public.moments_posts%rowtype;
  reminded uuid;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_id is null then
    raise exception 'A post needs an id' using errcode = '22023';
  end if;
  if exists (select 1 from public.moments_posts where id = p_id) then
    if exists (select 1 from public.moments_posts where id = p_id and author_id = me) then
      return p_id;
    end if;
    raise exception 'That post id is taken' using errcode = '23505';
  end if;
  if p_visibility not in ('friends', 'private', 'only', 'except') then
    raise exception 'Unknown visibility' using errcode = '22023';
  end if;

  select coalesce(array_agg(distinct m.id), '{}') into asked
  from unnest(coalesce(p_mentioned_ids, '{}')) as m(id)
  where m.id is not null and m.id <> me;
  if cardinality(asked) > 30 then
    raise exception 'You can remind at most 30 people' using errcode = '22023';
  end if;

  p_photos := coalesce(p_photos, '[]'::jsonb);
  if jsonb_typeof(p_photos) <> 'array' then
    raise exception 'Photos must be a list' using errcode = '22023';
  end if;
  photo_count := jsonb_array_length(p_photos);
  if photo_count > 9 then
    raise exception 'At most 9 photos' using errcode = '22023';
  end if;
  prefix := me::text || '/' || p_id::text || '-';
  for photo in select value from jsonb_array_elements(p_photos) loop
    if jsonb_typeof(photo) <> 'object'
      or photo->>'path' is distinct from (prefix || index_value::text || '.jpg')
      or photo->>'thumb' is distinct from (prefix || index_value::text || '-t.jpg')
    then
      raise exception 'Photo % is not one of yours', index_value + 1 using errcode = '22023';
    end if;
    index_value := index_value + 1;
  end loop;

  -- One short video instead of photos: the file <author>/<post>-v.<ext>, its
  -- poster frame as the post's picture 0 (<post>-0.jpg and -0-t.jpg, the
  -- same names and storage rules as a photo), at most 3 minutes (one second
  -- of slack for rounding) and 50 MB. Both files are in storage by now.
  if p_video is not null and p_video <> 'null'::jsonb then
    if jsonb_typeof(p_video) <> 'object' then
      raise exception 'The video is malformed' using errcode = '22023';
    end if;
    if photo_count > 0 then
      raise exception 'A post has photos or a video, not both' using errcode = '22023';
    end if;
    video_ext := substring(p_video->>'path' from '\.(mp4|mov|webm)$');
    if video_ext is null
      or p_video->>'path' is distinct from (prefix || 'v.' || video_ext)
      or p_video->>'poster' is distinct from (prefix || '0.jpg')
      or p_video->>'thumb' is distinct from (prefix || '0-t.jpg')
    then
      raise exception 'That video is not one of yours' using errcode = '22023';
    end if;
    if jsonb_typeof(p_video->'duration_ms') is distinct from 'number'
      or jsonb_typeof(p_video->'size') is distinct from 'number'
    then
      raise exception 'The video needs a length and a size' using errcode = '22023';
    end if;
    video_duration := (p_video->>'duration_ms')::numeric::integer;
    video_size := (p_video->>'size')::numeric::bigint;
    if video_duration < 1 or video_duration > 181000 then
      raise exception 'A video can be at most 3 minutes' using errcode = '22023';
    end if;
    if video_size < 1 or video_size > 52428800 then
      raise exception 'A video can be at most 50 MB' using errcode = '22023';
    end if;
    select (o.metadata->>'size')::bigint into stored_size
    from storage.objects o
    where o.bucket_id = 'moments' and o.name = p_video->>'path';
    if not found then
      raise exception 'The video was not uploaded' using errcode = '22023';
    end if;
    if stored_size is not null and stored_size > 52428800 then
      raise exception 'A video can be at most 50 MB' using errcode = '22023';
    end if;
    if not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'moments' and o.name = p_video->>'poster'
    ) then
      raise exception 'The video has no poster picture' using errcode = '22023';
    end if;
    video_value := jsonb_build_object(
      'path', p_video->>'path',
      'poster', p_video->>'poster',
      'thumb', p_video->>'thumb',
      'w', coalesce((p_video->>'w')::numeric::integer, 0),
      'h', coalesce((p_video->>'h')::numeric::integer, 0),
      'duration_ms', video_duration,
      'size', coalesce(stored_size, video_size),
      'mime', case video_ext
        when 'mp4' then 'video/mp4'
        when 'mov' then 'video/quicktime'
        else 'video/webm'
      end
    );
  end if;

  p_link_url := nullif(btrim(coalesce(p_link_url, '')), '');
  if p_link_url is not null and p_link_url !~* '^https?://[^\s]+$' then
    raise exception 'Links must start with http:// or https://' using errcode = '22023';
  end if;
  if photo_count > 0 and p_link_url is not null then
    raise exception 'A post has photos or a link, not both' using errcode = '22023';
  end if;
  if video_value is not null and p_link_url is not null then
    raise exception 'A post has a video or a link, not both' using errcode = '22023';
  end if;
  post_kind := case
    when video_value is not null then 'video'
    when photo_count > 0 then 'photos'
    when p_link_url is not null then 'link'
    else 'text'
  end;
  if post_kind = 'text' and body_text = '' then
    raise exception 'Write something or add photos' using errcode = '22023';
  end if;

  -- Only friends can be chosen, only the author's own tags.
  select coalesce(array_agg(distinct f.id), '{}') into friend_ids
  from unnest(coalesce(p_friend_ids, '{}')) as f(id)
  where public.moments_are_friends(me, f.id);
  select coalesce(array_agg(t.id), '{}') into tag_ids
  from public.friend_tags t
  where t.owner_id = me
    and t.id = any (coalesce(p_tag_ids, '{}'));
  if p_visibility in ('friends', 'private') then
    friend_ids := '{}';
    tag_ids := '{}';
  end if;

  insert into public.moments_posts (
    id, author_id, body, kind, photos, video, link_url, link_title, location,
    visibility, audience_friend_ids, audience_tag_ids
  )
  values (
    p_id, me, body_text, post_kind, p_photos, video_value, p_link_url,
    left(nullif(btrim(coalesce(p_link_title, '')), ''), 200),
    left(nullif(btrim(coalesce(p_location, '')), ''), 80),
    p_visibility, friend_ids, tag_ids
  );

  -- Remind who to read: only friends who can see this post as it is stored.
  if cardinality(asked) > 0 then
    select * into stored from public.moments_posts where id = p_id;
    select coalesce(array_agg(a.id order by a.id), '{}') into kept
    from unnest(asked) as a(id)
    where public.moments_are_friends(me, a.id)
      and public.moments_post_visible_to(a.id, stored);
    if cardinality(kept) > 0 then
      update public.moments_posts
      set mentioned_user_ids = kept
      where id = p_id;
      for reminded in select unnest(kept) loop
        insert into public.moments_notifications (
          user_id, kind, post_id, actor_id, snippet
        )
        values (reminded, 'mention', p_id, me, left(body_text, 200))
        on conflict (user_id, post_id) where kind = 'mention' do nothing;
        perform public.moments_signal(reminded, 'reaction', p_id);
      end loop;
    end if;
  end if;
  return p_id;
end;
$$;

revoke execute on function public.create_moment(uuid, text, jsonb, text, text, text, text, uuid[], uuid[], jsonb, uuid[]) from public, anon;
grant execute on function public.create_moment(uuid, text, jsonb, text, text, text, text, uuid[], uuid[], jsonb, uuid[]) to authenticated;

-- Pins or unpins the caller's own post. Three pinned posts at most (54000).
-- Pinning one that is already pinned changes nothing.
create or replace function public.set_moment_pinned(
  p_id uuid,
  p_pinned boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  post public.moments_posts%rowtype;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  -- One person pinning at a time, so two requests cannot both take the
  -- third place.
  perform pg_advisory_xact_lock(hashtextextended('moments-pin:' || me::text, 0));
  select * into post
  from public.moments_posts
  where id = p_id and author_id = me;
  if post.id is null then
    raise exception 'Moment not found' using errcode = 'P0002';
  end if;
  if coalesce(p_pinned, false) then
    if post.pinned_at is not null then
      return;
    end if;
    if (
      select count(*) from public.moments_posts
      where author_id = me and pinned_at is not null
    ) >= 3 then
      raise exception 'You can pin at most 3 Moments' using errcode = '54000';
    end if;
    update public.moments_posts set pinned_at = now() where id = p_id;
  else
    update public.moments_posts set pinned_at = null where id = p_id;
  end if;
end;
$$;

revoke execute on function public.set_moment_pinned(uuid, boolean) from public, anon;
grant execute on function public.set_moment_pinned(uuid, boolean) to authenticated;
