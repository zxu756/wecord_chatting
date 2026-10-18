-- Moments video: one short video per post (60 seconds, 50 MB at most).
--
-- * moments_posts.video (jsonb, null for other posts), kind 'video':
--     {"path": "<author>/<post>-v.mp4|mov|webm", "poster": "<author>/<post>-0.jpg",
--      "thumb": "<author>/<post>-0-t.jpg", "w", "h", "duration_ms", "size", "mime"}
--   The poster frame is stored exactly like a photo (the same names, the same
--   storage rules), so a post has photos OR a video, never both, and not a
--   link with either. create_moment checks the names, the length (a second
--   of slack for rounding) and the size, and that both files are in storage.
-- * The private bucket "moments" takes videos too (mp4, mov, webm) up to
--   50 MB; pictures stay small because the app scales them before upload.
-- * Reading the video file is decided by moments_post_visible_to for its post,
--   the same select policy as photos (moments_can_read_object): friends in
--   the audience, minus "Don't let them see", the visible range and blocks;
--   unfriending cuts access at once because nothing is copied.
-- * moments_feed returns the video; delete_moment returns its files for the
--   app to remove; the notification thumbnail falls back to the poster.
--
-- Replaces the latest definitions of create_moment, delete_moment,
-- moments_feed (202610180042), list_moments_notifications (202610180042),
-- moments_can_read_object (202610180041) and the storage insert policy.

alter table public.moments_posts add column if not exists video jsonb;

alter table public.moments_posts drop constraint if exists moments_posts_kind;
alter table public.moments_posts add constraint moments_posts_kind
  check (kind in ('text', 'photos', 'link', 'video'));

alter table public.moments_posts drop constraint if exists moments_posts_shape;
alter table public.moments_posts add constraint moments_posts_shape check (
  (kind = 'text' and jsonb_array_length(photos) = 0 and link_url is null and video is null and btrim(body) <> '')
  or (kind = 'photos' and jsonb_array_length(photos) between 1 and 9 and link_url is null and video is null)
  or (kind = 'link' and link_url is not null and jsonb_array_length(photos) = 0 and video is null)
  or (kind = 'video' and video is not null and jsonb_array_length(photos) = 0 and link_url is null
      and jsonb_typeof(video) = 'object')
);

-- The audience columns stay unreadable; the video is as public as the photos.
revoke select on public.moments_posts from authenticated;
grant select (
  id, author_id, body, kind, photos, video, link_url, link_title, location,
  visibility, created_at
) on public.moments_posts to authenticated;

update storage.buckets
set file_size_limit = 52428800,
    allowed_mime_types = array[
      'image/jpeg', 'image/png', 'image/webp',
      'video/mp4', 'video/quicktime', 'video/webm'
    ]
where id = 'moments';

drop policy if exists moments_insert_owner on storage.objects;
create policy moments_insert_owner
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'moments'
    and (storage.foldername(name))[1] = auth.uid()::text
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/(cover-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-([0-8](-t)?\.jpg|v\.(mp4|mov|webm)))$'
  );

-- --------------------------------------------------------------- writing

drop function if exists public.create_moment(uuid, text, jsonb, text, text, text, text, uuid[], uuid[]);

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
  p_video jsonb default null
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
  -- same names and storage rules as a photo), at most 60 seconds (one second
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
    if video_duration < 1 or video_duration > 61000 then
      raise exception 'A video can be at most 60 seconds' using errcode = '22023';
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
  return p_id;
end;
$$;

create or replace function public.delete_moment(p_id uuid)
returns table (object_path text)
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
  select * into post from public.moments_posts where id = p_id and author_id = me;
  if post.id is null then
    return;
  end if;
  delete from public.moments_posts where id = p_id;
  return query
  select path.value
  from jsonb_array_elements(post.photos) as photo(value),
    lateral (values (photo.value->>'path'), (photo.value->>'thumb')) as path(value)
  where path.value is not null
  union
  select path.value
  from (values (post.video->>'path'), (post.video->>'poster'), (post.video->>'thumb')) as path(value)
  where path.value is not null;
end;
$$;

-- ------------------------------------------------------------- reading

drop function if exists public.moments_feed(integer, timestamptz, uuid, uuid, uuid);

create or replace function public.moments_feed(
  p_limit integer default 20,
  p_before_at timestamptz default null,
  p_before_id uuid default null,
  p_author_id uuid default null,
  p_post_id uuid default null
)
returns table (
  id uuid,
  author_id uuid,
  author_name text,
  author_avatar_url text,
  body text,
  kind text,
  photos jsonb,
  video jsonb,
  link_url text,
  link_title text,
  location text,
  visibility text,
  created_at timestamptz,
  like_count integer,
  liked_by_me boolean,
  likes jsonb,
  comment_count integer,
  comments jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  me uuid := auth.uid();
  friend_ids uuid[];
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select coalesce(array_agg(
    case when f.user_low_id = me then f.user_high_id else f.user_low_id end
  ), '{}') || me
  into friend_ids
  from public.friendships f
  where me in (f.user_low_id, f.user_high_id);

  return query
  with page as (
    select p.*
    from public.moments_posts p
    where p.author_id = any (friend_ids)
      and (p_post_id is null or p.id = p_post_id)
      and (p_author_id is null or p.author_id = p_author_id)
      and (
        p_before_at is null
        or (p.created_at, p.id) < (
          p_before_at,
          coalesce(p_before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)
        )
      )
      and (
        p_author_id is not null
        or p_post_id is not null
        or p.author_id = me
        or not exists (
          select 1
          from public.moments_friend_prefs fp
          where fp.owner_id = me
            and fp.friend_id = p.author_id
            and fp.hide_theirs
        )
      )
      and public.moments_post_visible_to(me, p)
    order by p.created_at desc, p.id desc
    limit greatest(1, least(coalesce(p_limit, 20), 50))
  )
  select
    page.id,
    page.author_id,
    coalesce(nullif(btrim(ca.alias), ''), pr.display_name),
    pr.avatar_url,
    page.body,
    page.kind,
    page.photos,
    page.video,
    page.link_url,
    page.link_title,
    page.location,
    page.visibility,
    page.created_at,
    coalesce(lk.like_count, 0),
    coalesce(lk.liked_by_me, false),
    coalesce(lk.likes, '[]'::jsonb),
    coalesce(cm.comment_count, 0),
    coalesce(cm.comments, '[]'::jsonb)
  from page
  join public.profiles pr on pr.id = page.author_id
  left join public.contact_aliases ca
    on ca.owner_id = me and ca.friend_id = page.author_id
  left join lateral (
    select
      count(*)::integer as like_count,
      bool_or(l.user_id = me) as liked_by_me,
      jsonb_agg(
        jsonb_build_object(
          'user_id', l.user_id,
          'name', coalesce(nullif(btrim(lca.alias), ''), lp.display_name),
          'avatar_url', lp.avatar_url
        )
        order by l.created_at, l.user_id
      ) as likes
    from public.moments_likes l
    join public.profiles lp on lp.id = l.user_id
    left join public.contact_aliases lca
      on lca.owner_id = me and lca.friend_id = l.user_id
    where l.post_id = page.id
      and public.moments_interaction_visible(me, page.author_id, l.user_id, null)
  ) lk on true
  left join lateral (
    select
      count(*)::integer as comment_count,
      jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'user_id', c.author_id,
          'name', coalesce(nullif(btrim(cca.alias), ''), cp.display_name),
          'avatar_url', cp.avatar_url,
          'body', c.body,
          'created_at', c.created_at,
          'reply_to_comment_id', c.reply_to_comment_id,
          'reply_to_user_id', c.reply_to_user_id,
          'reply_to_name', coalesce(nullif(btrim(rca.alias), ''), rp.display_name)
        )
        order by c.created_at, c.id
      ) as comments
    from public.moments_comments c
    join public.profiles cp on cp.id = c.author_id
    left join public.contact_aliases cca
      on cca.owner_id = me and cca.friend_id = c.author_id
    left join public.profiles rp on rp.id = c.reply_to_user_id
    left join public.contact_aliases rca
      on rca.owner_id = me and rca.friend_id = c.reply_to_user_id
    where c.post_id = page.id
      and public.moments_interaction_visible(
        me, page.author_id, c.author_id, c.reply_to_user_id
      )
  ) cm on true
  order by page.created_at desc, page.id desc;
end;
$$;

create or replace function public.list_moments_notifications(p_limit integer default 50)
returns table (
  id uuid,
  kind text,
  post_id uuid,
  comment_id uuid,
  actor_id uuid,
  actor_name text,
  actor_avatar_url text,
  snippet text,
  post_excerpt text,
  post_thumb text,
  created_at timestamptz,
  is_unread boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  return query
  select
    n.id,
    n.kind,
    n.post_id,
    n.comment_id,
    n.actor_id,
    coalesce(nullif(btrim(ca.alias), ''), pr.display_name),
    pr.avatar_url,
    n.snippet,
    left(p.body, 120),
    coalesce(p.photos->0->>'thumb', p.video->>'thumb'),
    n.created_at,
    n.read_at is null
  from public.moments_notifications n
  join public.moments_posts p on p.id = n.post_id
  join public.profiles pr on pr.id = n.actor_id
  left join public.contact_aliases ca
    on ca.owner_id = me and ca.friend_id = n.actor_id
  left join public.moments_comments c on c.id = n.comment_id
  where n.user_id = me
    and n.created_at > now() - interval '60 days'
    and public.moments_post_visible_to(me, p)
    and public.moments_interaction_visible(
      me, p.author_id, n.actor_id, c.reply_to_user_id
    )
  order by n.created_at desc, n.id desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
end;
$$;

-- ---------------------------------------------------------------- files

create or replace function public.moments_can_read_object(object_name text)
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
  post_id uuid;
begin
  if auth.uid() is null or split_part(object_name, '/', 3) <> '' then
    return false;
  end if;
  if owner_text !~ ('^' || uuid_pattern || '$') then
    return false;
  end if;
  owner_id := owner_text::uuid;
  if owner_id = auth.uid() then
    return true;
  end if;
  if file_name ~ ('^cover-' || uuid_pattern || '\.jpg$') then
    return public.moments_can_view_profile(owner_id);
  end if;
  if file_name ~ ('^' || uuid_pattern || '(-[0-8](-t)?\.jpg|-v\.(mp4|mov|webm))$') then
    post_id := substring(file_name from '^(' || uuid_pattern || ')')::uuid;
    return exists (
      select 1
      from public.moments_posts p
      where p.id = post_id
        and p.author_id = owner_id
        and public.moments_post_visible_to(auth.uid(), p)
    );
  end if;
  return false;
end;
$$;


revoke execute on function public.create_moment(uuid, text, jsonb, text, text, text, text, uuid[], uuid[], jsonb) from public, anon;
grant execute on function public.create_moment(uuid, text, jsonb, text, text, text, text, uuid[], uuid[], jsonb) to authenticated;
revoke execute on function public.delete_moment(uuid) from public, anon;
grant execute on function public.delete_moment(uuid) to authenticated;
revoke execute on function public.moments_feed(integer, timestamptz, uuid, uuid, uuid) from public, anon;
grant execute on function public.moments_feed(integer, timestamptz, uuid, uuid, uuid) to authenticated;
revoke execute on function public.list_moments_notifications(integer) from public, anon;
grant execute on function public.list_moments_notifications(integer) to authenticated;
revoke execute on function public.moments_can_read_object(text) from public, anon;
grant execute on function public.moments_can_read_object(text) to authenticated;
