-- Moments 2.0 (roadmap B2), part 3 of 6: reading.
--
-- Each function below is the latest definition (all three are from
-- 202610190022_moments_video.sql) with the additions, nothing else changed:
--
-- * moments_feed: one more thing on every row and a different order on a
--   person's page.
--     - pinned_at, mentioned_me (the caller was reminded to read it) and
--       mentions (who the author reminded: filled for the author only, and
--       only with people who are still their friends);
--     - every comment carries its picture (`image`: path, w, h, alt);
--     - a person's page (p_author_id given) starts with that person's pinned
--       posts that the caller may see (at most 3, newest pin first), then the
--       rest by time; later pages (p_before_at given) leave the pinned ones
--       out, so nothing shows twice. The feed itself stays by time.
-- * list_moments_notifications: also the 'mention' kind (the reminder), and
--   has_image, whether the comment behind the notice is only a picture.
-- * moments_can_read_object: a comment's picture
--   (<commenter>/c-<comment id>.<ext>) can be read by the commenter and by
--   whoever may see that comment now (the post is visible to them and the
--   mutual-friends rule of moments_interaction_visible holds), so an
--   unfriended or blocked person is cut off at once.

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
  comments jsonb,
  pinned_at timestamptz,
  mentioned_me boolean,
  mentions jsonb
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
  author_page boolean := p_author_id is not null and p_post_id is null;
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
    -- The pinned posts: only on the first page of a person's page.
    (
      select p.*
      from public.moments_posts p
      where author_page
        and p_before_at is null
        and p.author_id = p_author_id
        and p.author_id = any (friend_ids)
        and p.pinned_at is not null
        and public.moments_post_visible_to(me, p)
      order by p.pinned_at desc, p.id desc
      limit 3
    )
    union all
    (
      select p.*
      from public.moments_posts p
      where p.author_id = any (friend_ids)
        and (p_post_id is null or p.id = p_post_id)
        and (p_author_id is null or p.author_id = p_author_id)
        and (not author_page or p.pinned_at is null)
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
    coalesce(cm.comments, '[]'::jsonb),
    page.pinned_at,
    me = any (page.mentioned_user_ids),
    coalesce(mn.mentions, '[]'::jsonb)
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
        jsonb_strip_nulls(jsonb_build_object(
          'id', c.id,
          'user_id', c.author_id,
          'name', coalesce(nullif(btrim(cca.alias), ''), cp.display_name),
          'avatar_url', cp.avatar_url,
          'body', c.body,
          'created_at', c.created_at,
          'reply_to_comment_id', c.reply_to_comment_id,
          'reply_to_user_id', c.reply_to_user_id,
          'reply_to_name', coalesce(nullif(btrim(rca.alias), ''), rp.display_name),
          'image', c.image
        ))
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
  left join lateral (
    -- Who the author reminded: the author sees it, nobody else.
    select jsonb_agg(
      jsonb_build_object(
        'user_id', u.id,
        'name', coalesce(nullif(btrim(mca.alias), ''), mp.display_name),
        'avatar_url', mp.avatar_url
      )
      order by u.ord
    ) as mentions
    from unnest(page.mentioned_user_ids) with ordinality as u(id, ord)
    join public.profiles mp on mp.id = u.id
    left join public.contact_aliases mca
      on mca.owner_id = me and mca.friend_id = u.id
    where page.author_id = me
      and public.moments_are_friends(me, u.id)
  ) mn on true
  order by
    (page.pinned_at is not null and author_page and p_before_at is null) desc,
    case
      when page.pinned_at is not null and author_page and p_before_at is null
      then page.pinned_at
    end desc,
    page.created_at desc,
    page.id desc;
end;
$$;

revoke execute on function public.moments_feed(integer, timestamptz, uuid, uuid, uuid) from public, anon;
grant execute on function public.moments_feed(integer, timestamptz, uuid, uuid, uuid) to authenticated;

-- ------------------------------------------------------- notifications

drop function if exists public.list_moments_notifications(integer);

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
  is_unread boolean,
  has_image boolean
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
    n.read_at is null,
    c.image is not null
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

revoke execute on function public.list_moments_notifications(integer) from public, anon;
grant execute on function public.list_moments_notifications(integer) to authenticated;

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
  comment_id uuid;
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
  -- A picture on a comment: it follows the comment.
  if file_name ~ ('^c-' || uuid_pattern || '\.(jpg|png|webp|gif)$') then
    comment_id := substring(file_name from '^c-(' || uuid_pattern || ')')::uuid;
    return exists (
      select 1
      from public.moments_comments c
      join public.moments_posts p on p.id = c.post_id
      where c.id = comment_id
        and c.author_id = owner_id
        and public.moments_post_visible_to(auth.uid(), p)
        and public.moments_interaction_visible(
          auth.uid(), p.author_id, c.author_id, c.reply_to_user_id
        )
    );
  end if;
  return false;
end;
$$;

revoke execute on function public.moments_can_read_object(text) from public, anon;
grant execute on function public.moments_can_read_object(text) to authenticated;
