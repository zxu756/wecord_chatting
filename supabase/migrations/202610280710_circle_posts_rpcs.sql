-- Topics and circle posts 2.0 (roadmap B8), part 2 of 8: writing posts.
--
-- A circle post may now have a title (80 characters at most, one line) and
-- tags, and a moderator can mark a post as featured ("精华"):
--
--   * create_circle_post (the only definition before this one:
--     202605190003_community_discovery_v1.sql) is the same function with two
--     more optional arguments, post_title and post_tags, so an older app that
--     sends three arguments keeps working. Added: a member who is timed out
--     cannot post (the other ways of speaking are already refused for them).
--     The tags are the ones passed plus the ones written in the title or the
--     text (circle_posts_set_tags, 202610280700).
--   * update_circle_post: the author changes the title, the text and the tags
--     of their own post. The picture stays.
--   * set_circle_post_featured: a member with "manage messages" features or
--     un-features a post. Audited as post_feature / post_unfeature (the "post"
--     group of the audit log). Not while the circle is suspended (K1) and
--     nothing changes (nor is logged) when the post is already in that state.
--   * circle_posts_check_raid: while a raid lockdown (C6) is on, a member who
--     came in with the burst cannot post a link, in the text or the title,
--     the same rule messages have (messages_review_raid).

-- ---------------------------------------------------------------------------
-- Raid lockdown
-- ---------------------------------------------------------------------------

create or replace function public.circle_posts_check_raid()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- The usual case, nothing under lockdown anywhere, costs one index probe.
  if not exists (
    select 1 from public.circle_security s where s.lockdown_until > now()
  ) then
    return new;
  end if;

  if (coalesce(new.body, '') || ' ' || coalesce(new.title, '')) ~* '(https?://|www\.)'
    and public.circle_raid_newcomer(new.circle_id, new.author_id)
  then
    raise exception 'New members cannot post links while the circle is locked down'
      using errcode = '42501', detail = 'raid_newcomer_links';
  end if;
  return new;
end;
$$;

revoke execute on function public.circle_posts_check_raid()
  from public, anon, authenticated;

drop trigger if exists circle_posts_check_raid on public.circle_posts;
create trigger circle_posts_check_raid
  before insert or update of body, title on public.circle_posts
  for each row execute function public.circle_posts_check_raid();

-- ---------------------------------------------------------------------------
-- Writing
-- ---------------------------------------------------------------------------

-- A title as it is kept: one line, spaces folded, null when empty.
create or replace function public.circle_post_clean_title(p_title text)
returns text
language plpgsql
immutable
as $$
declare
  clean text := nullif(btrim(regexp_replace(coalesce(p_title, ''), '\s+', ' ', 'g')), '');
begin
  if clean is not null and char_length(clean) > 80 then
    raise exception 'The title can be 80 characters at most' using errcode = '22023';
  end if;
  return clean;
end;
$$;

revoke execute on function public.circle_post_clean_title(text) from public, anon;

-- Whether the caller is timed out in the circle.
create or replace function public.circle_member_is_timed_out(
  target_circle_id uuid,
  target_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = target_circle_id
      and cm.user_id = target_user_id
      and cm.timed_out_until > now()
  );
$$;

revoke execute on function public.circle_member_is_timed_out(uuid, uuid)
  from public, anon, authenticated;

drop function if exists public.create_circle_post(uuid, text, jsonb);

create or replace function public.create_circle_post(
  target_circle_id uuid,
  body text,
  attachment jsonb default null,
  post_title text default null,
  post_tags text[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_body text := trim(coalesce(body, ''));
  clean_title text;
  created_post_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.is_current_user_circle_member(target_circle_id) then
    raise exception 'Circle not found or caller is not a member'
      using errcode = '42501';
  end if;

  if public.circle_member_is_timed_out(target_circle_id, current_user_id) then
    raise exception 'You are timed out in this circle' using errcode = '42501';
  end if;

  clean_title := public.circle_post_clean_title(post_title);

  if char_length(trimmed_body) = 0 and attachment is null then
    raise exception 'Post body or attachment is required' using errcode = '22023';
  end if;

  insert into public.circle_posts (circle_id, author_id, body, attachment, title, tags)
  values (
    target_circle_id,
    current_user_id,
    trimmed_body,
    attachment,
    clean_title,
    public.hashtag_clean_list(post_tags)
  )
  returning id into created_post_id;

  return created_post_id;
end;
$$;

revoke execute on function public.create_circle_post(uuid, text, jsonb, text, text[])
  from public, anon;
grant execute on function public.create_circle_post(uuid, text, jsonb, text, text[])
  to authenticated;

create or replace function public.update_circle_post(
  target_post_id uuid,
  post_title text default null,
  body text default '',
  post_tags text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_post public.circle_posts%rowtype;
  trimmed_body text := trim(coalesce(body, ''));
  clean_title text;
  clean_tags text[];
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into target_post
  from public.circle_posts p
  where p.id = target_post_id
    and p.deleted_at is null
  for update;

  if target_post.id is null
    or target_post.author_id <> current_user_id
    or not public.is_current_user_circle_member(target_post.circle_id)
    or public.circle_is_suspended(target_post.circle_id)
  then
    raise exception 'Post not found or caller cannot edit it' using errcode = '42501';
  end if;

  if public.circle_member_is_timed_out(target_post.circle_id, current_user_id) then
    raise exception 'You are timed out in this circle' using errcode = '42501';
  end if;

  clean_title := public.circle_post_clean_title(post_title);
  clean_tags := public.hashtag_clean_list(post_tags);

  if char_length(trimmed_body) = 0 and target_post.attachment is null then
    raise exception 'Post body or attachment is required' using errcode = '22023';
  end if;

  update public.circle_posts p
  set title = clean_title,
    body = trimmed_body,
    tags = clean_tags
  where p.id = target_post_id
    and (
      p.title is distinct from clean_title
      or p.body is distinct from trimmed_body
      or p.tags is distinct from public.hashtag_clean_list(
        clean_tags
          || public.hashtags_from_text(clean_title)
          || public.hashtags_from_text(trimmed_body)
      )
    );
end;
$$;

revoke execute on function public.update_circle_post(uuid, text, text, text[])
  from public, anon;
grant execute on function public.update_circle_post(uuid, text, text, text[])
  to authenticated;

create or replace function public.set_circle_post_featured(
  target_post_id uuid,
  featured boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_post public.circle_posts%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into target_post
  from public.circle_posts p
  where p.id = target_post_id
    and p.deleted_at is null
  for update;

  if target_post.id is null
    or not public.is_current_user_circle_member(target_post.circle_id)
  then
    raise exception 'Post not found or caller is not a circle member'
      using errcode = '42501';
  end if;

  if public.circle_is_suspended(target_post.circle_id) then
    raise exception 'This circle is suspended' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(target_post.circle_id, 'manage_messages') then
    raise exception 'Only moderators can feature posts' using errcode = '42501';
  end if;

  if (target_post.featured_at is not null) = coalesce(featured, false) then
    return coalesce(featured, false);
  end if;

  update public.circle_posts p
  set featured_at = case when coalesce(featured, false) then now() end,
    featured_by = case when coalesce(featured, false) then current_user_id end
  where p.id = target_post_id;

  perform public.write_circle_audit(
    target_post.circle_id,
    case when coalesce(featured, false) then 'post_feature' else 'post_unfeature' end,
    'post',
    target_post.id,
    public.circle_member_label(target_post.circle_id, target_post.author_id),
    jsonb_strip_nulls(jsonb_build_object(
      'author_id', target_post.author_id,
      'title', target_post.title,
      'excerpt', left(target_post.body, 100)
    ))
  );
  return coalesce(featured, false);
end;
$$;

revoke execute on function public.set_circle_post_featured(uuid, boolean)
  from public, anon;
grant execute on function public.set_circle_post_featured(uuid, boolean)
  to authenticated;
