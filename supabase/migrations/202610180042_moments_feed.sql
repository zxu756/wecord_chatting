-- Moments: reading. One function builds the feed (and a friend's page, and
-- a single post), so the app makes one request per page.
--
-- * moments_feed(p_limit, p_before_at, p_before_id, p_author_id, p_post_id):
--   the posts the caller may see, newest first, with keyset pagination
--   (pass the last row's created_at and id as p_before_at / p_before_id).
--   Each row carries the author's name (the caller's alias for them wins),
--   the likes and comments the caller may see (WeChat's rule: see
--   moments_interaction_visible in 202610180041) with their counts, and
--   whether the caller liked it. Without p_author_id it is the feed: the
--   caller's own posts and their friends', minus friends whose Moments they
--   hid ("Hide their Moments"). With p_author_id it is that person's page,
--   which hiding does not close. With p_post_id it is that one post.
-- * moments_unseen_summary / mark_moments_seen: the badge on the Moments
--   entry, how many new posts from friends since the caller last opened
--   Moments, and the newest poster's avatar.
-- * get_moments_profile: a person's cover for their Moments page.
-- * list_moments_notifications / mark_moments_notifications_read: the
--   Moments section of the inbox.
-- * list_moments_friend_prefs: Settings -> Moments, the friends the caller
--   chose to hide from or to hide.
--
-- All of them run as the function owner and apply the rules themselves,
-- starting from auth.uid().

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

-- New posts from friends since the caller last opened Moments.
create or replace function public.moments_unseen_summary()
returns table (
  new_count integer,
  latest_author_id uuid,
  latest_author_name text,
  latest_author_avatar_url text,
  latest_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  me uuid := auth.uid();
  seen_at timestamptz;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select ms.last_seen_at into seen_at
  from public.moments_settings ms
  where ms.user_id = me;
  -- Nobody opened Moments yet: what is a day old is not "new".
  seen_at := coalesce(seen_at, now() - interval '1 day');

  return query
  with fresh as (
    select p.id, p.author_id, p.created_at
    from public.moments_posts p
    where p.author_id <> me
      and p.created_at > seen_at
      and p.created_at > now() - interval '30 days'
      and exists (
        select 1
        from public.friendships f
        where f.user_low_id = least(me, p.author_id)
          and f.user_high_id = greatest(me, p.author_id)
      )
      and not exists (
        select 1
        from public.moments_friend_prefs fp
        where fp.owner_id = me
          and fp.friend_id = p.author_id
          and fp.hide_theirs
      )
      and public.moments_post_visible_to(me, p)
  ), newest as (
    select fresh.author_id, fresh.created_at
    from fresh
    order by fresh.created_at desc, fresh.id desc
    limit 1
  )
  select
    (select count(*)::integer from fresh),
    newest.author_id,
    coalesce(nullif(btrim(ca.alias), ''), pr.display_name),
    pr.avatar_url,
    newest.created_at
  from newest
  join public.profiles pr on pr.id = newest.author_id
  left join public.contact_aliases ca
    on ca.owner_id = me and ca.friend_id = newest.author_id;
end;
$$;

create or replace function public.mark_moments_seen()
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
  insert into public.moments_settings (user_id, last_seen_at)
  values (me, now())
  on conflict (user_id) do update set last_seen_at = now();
end;
$$;

-- The cover and name on a person's Moments page. cover_path is null unless
-- the caller may see it.
create or replace function public.get_moments_profile(p_user_id uuid)
returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
  cover_path text,
  is_friend boolean
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
    pr.id,
    coalesce(nullif(btrim(ca.alias), ''), pr.display_name),
    pr.avatar_url,
    case when public.moments_can_view_profile(pr.id) then ms.cover_path end,
    public.moments_can_view_profile(pr.id)
  from public.profiles pr
  left join public.moments_settings ms on ms.user_id = pr.id
  left join public.contact_aliases ca
    on ca.owner_id = me and ca.friend_id = pr.id
  where pr.id = p_user_id
    and (pr.id = me or public.moments_are_friends(me, pr.id));
end;
$$;

-- Likes, comments and replies on the caller's posts and comments that they
-- can still see (the post is visible and the reaction passes the mutual
-- friends rule now, so unfriending or blocking takes them away).
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
    p.photos->0->>'thumb',
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

-- Marks the listed notifications read (null: all of them).
create or replace function public.mark_moments_notifications_read(p_ids uuid[] default null)
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
  update public.moments_notifications n
  set read_at = now()
  where n.user_id = me
    and n.read_at is null
    and (p_ids is null or n.id = any (p_ids));
end;
$$;

-- The friends the caller hides Moments from, or whose Moments they hide.
create or replace function public.list_moments_friend_prefs()
returns table (
  friend_id uuid,
  display_name text,
  avatar_url text,
  hide_mine boolean,
  hide_theirs boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    fp.friend_id,
    coalesce(nullif(btrim(ca.alias), ''), pr.display_name),
    pr.avatar_url,
    fp.hide_mine,
    fp.hide_theirs
  from public.moments_friend_prefs fp
  join public.profiles pr on pr.id = fp.friend_id
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid() and ca.friend_id = fp.friend_id
  where fp.owner_id = auth.uid()
    and public.moments_are_friends(auth.uid(), fp.friend_id)
  order by coalesce(nullif(btrim(ca.alias), ''), pr.display_name), fp.friend_id;
$$;

revoke execute on function public.moments_feed(integer, timestamptz, uuid, uuid, uuid) from public, anon;
revoke execute on function public.moments_unseen_summary() from public, anon;
revoke execute on function public.mark_moments_seen() from public, anon;
revoke execute on function public.get_moments_profile(uuid) from public, anon;
revoke execute on function public.list_moments_notifications(integer) from public, anon;
revoke execute on function public.mark_moments_notifications_read(uuid[]) from public, anon;
revoke execute on function public.list_moments_friend_prefs() from public, anon;
grant execute on function public.moments_feed(integer, timestamptz, uuid, uuid, uuid) to authenticated;
grant execute on function public.moments_unseen_summary() to authenticated;
grant execute on function public.mark_moments_seen() to authenticated;
grant execute on function public.get_moments_profile(uuid) to authenticated;
grant execute on function public.list_moments_notifications(integer) to authenticated;
grant execute on function public.mark_moments_notifications_read(uuid[]) to authenticated;
grant execute on function public.list_moments_friend_prefs() to authenticated;
