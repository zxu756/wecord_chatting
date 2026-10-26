-- Topics and circle posts 2.0 (roadmap B8), part 4 of 8: topics in Moments.
--
-- A topic page in Moments is the feed with a filter, never a public page:
--
--   * moments_feed gets one more argument, p_tag, from the definition that is
--     live (latest file: 202610260620_moments2_read.sql), patched in place
--     (pg_get_functiondef), so nothing else in it changes. With a tag the
--     feed keeps only posts that carry it, and every rule of the feed still
--     applies to them (a post must be visible to the caller through
--     moments_post_visible_to: friends, the audience, blocks, "only me";
--     friends whose Moments the caller hid stay hidden). The signature is
--     new, so the old five-argument function is dropped; calls without
--     p_tag behave as before.
--   * list_moment_hashtags(limit): the topics the caller's own and their
--     friends' recent posts (180 days) use, with the number of posts the
--     caller can see and the newest one. Only posts the caller may see are
--     counted, so a count never tells about a post that is hidden from them.
--   * hashtag_overview(tag): for the global search. How many Moments the
--     caller can see with the tag, and the circles the caller belongs to that
--     have posts with it (suspended circles left out).

do $$
declare
  def text;
  patched text;
  needle text;
begin
  def := pg_get_functiondef(
    'public.moments_feed(integer, timestamptz, uuid, uuid, uuid)'::regprocedure
  );
  if def not like '%p_tag%' then
    needle := 'and public.moments_post_visible_to(me, p)';
    if (length(def) - length(replace(def, needle, ''))) <> 2 * length(needle) then
      raise exception 'moments_feed changed shape (visibility); patch it by hand';
    end if;
    patched := replace(
      def,
      needle,
      E'and (p_tag is null or public.hashtag_clean(p_tag) = any (p.tags))\n        '
      || needle
    );
    needle := 'p_post_id uuid DEFAULT NULL::uuid)';
    if (length(patched) - length(replace(patched, needle, ''))) <> length(needle) then
      raise exception 'moments_feed changed shape (arguments); patch it by hand';
    end if;
    patched := replace(
      patched,
      needle,
      'p_post_id uuid DEFAULT NULL::uuid, p_tag text DEFAULT NULL::text)'
    );
    drop function public.moments_feed(integer, timestamptz, uuid, uuid, uuid);
    execute patched;
  end if;
end;
$$;

revoke execute on function public.moments_feed(integer, timestamptz, uuid, uuid, uuid, text)
  from public, anon;
grant execute on function public.moments_feed(integer, timestamptz, uuid, uuid, uuid, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- The topics friends use
-- ---------------------------------------------------------------------------

create or replace function public.list_moment_hashtags(p_limit integer default 20)
returns table (tag text, post_count integer, last_at timestamptz)
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
  select
    u.tag,
    count(*)::integer,
    max(p.created_at)
  from public.moments_posts p
  cross join lateral unnest(p.tags) as u(tag)
  where p.author_id = any (friend_ids)
    and p.created_at > now() - interval '180 days'
    and cardinality(p.tags) > 0
    and (
      p.author_id = me
      or not exists (
        select 1
        from public.moments_friend_prefs fp
        where fp.owner_id = me
          and fp.friend_id = p.author_id
          and fp.hide_theirs
      )
    )
    and public.moments_post_visible_to(me, p)
  group by u.tag
  order by count(*) desc, max(p.created_at) desc, u.tag
  limit greatest(1, least(coalesce(p_limit, 20), 50));
end;
$$;

revoke execute on function public.list_moment_hashtags(integer) from public, anon;
grant execute on function public.list_moment_hashtags(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Where a topic is used, for the search
-- ---------------------------------------------------------------------------

create or replace function public.hashtag_overview(p_tag text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  clean_tag text := public.hashtag_clean(p_tag);
  friend_ids uuid[];
  moments_count integer := 0;
  circles_json jsonb := '[]'::jsonb;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if clean_tag is null then
    return jsonb_build_object('tag', null, 'moments', 0, 'circles', '[]'::jsonb);
  end if;

  select coalesce(array_agg(
    case when f.user_low_id = me then f.user_high_id else f.user_low_id end
  ), '{}') || me
  into friend_ids
  from public.friendships f
  where me in (f.user_low_id, f.user_high_id);

  select count(*)::integer into moments_count
  from public.moments_posts p
  where p.author_id = any (friend_ids)
    and clean_tag = any (p.tags)
    and (
      p.author_id = me
      or not exists (
        select 1
        from public.moments_friend_prefs fp
        where fp.owner_id = me
          and fp.friend_id = p.author_id
          and fp.hide_theirs
      )
    )
    and public.moments_post_visible_to(me, p);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'circle_id', q.circle_id,
      'name', q.name,
      'avatar_url', q.avatar_url,
      'post_count', q.post_count
    )
    order by q.post_count desc, q.name
  ), '[]'::jsonb)
  into circles_json
  from (
    select
      c.id as circle_id,
      c.name,
      c.avatar_url,
      count(*)::integer as post_count
    from public.circle_members cm
    join public.circles c on c.id = cm.circle_id
    join public.circle_posts cp on cp.circle_id = c.id
    where cm.user_id = me
      and c.disabled_mode is distinct from 'suspend'
      and cp.deleted_at is null
      and clean_tag = any (cp.tags)
    group by c.id, c.name, c.avatar_url
    order by count(*) desc, c.name
    limit 10
  ) q;

  return jsonb_build_object(
    'tag', clean_tag,
    'moments', moments_count,
    'circles', circles_json
  );
end;
$$;

revoke execute on function public.hashtag_overview(text) from public, anon;
grant execute on function public.hashtag_overview(text) to authenticated;
