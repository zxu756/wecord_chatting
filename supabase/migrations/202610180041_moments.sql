-- Moments: friends' posts (text, up to 9 photos or a link) with likes and
-- comments, and who may see what.
--
-- Everything is enforced here, not in the app:
--
-- Posts (moments_posts)
--   A post is text, photos or a link, with an optional place. visibility is
--     friends  every friend of the author
--     private  only the author
--     only     only the friends in audience_friend_ids and the friends in
--              the author's tags audience_tag_ids ("Only share with")
--     except   every friend but those ("Don't share with")
--   Tags are read live (friend_tags of the author), so a friend added to
--   "Family" later also sees the older posts shared with "Family", and a new
--   colleague added to "Work" does not see posts hidden from "Work".
--   Other rules, all in moments_post_visible_to:
--     * the viewer is a friend of the author and neither blocked the other
--       (unfriending, which blocking does, takes effect at once because
--       nothing is copied);
--     * "Don't let them see my Moments" (moments_friend_prefs.hide_mine)
--       hides all of the author's posts from that friend;
--     * the author's "Visible range" (moments_settings.visible_range: all,
--       six_months, one_month, three_days) hides older posts from everyone
--       but the author.
--   "Hide their Moments" (hide_theirs) is the viewer's choice and only
--   shapes the feed (moments_feed in 202610180042): the friend's own
--   Moments page still opens.
--   The table is readable except the audience columns (who a post was
--   hidden from is the author's secret); posts are created and deleted by
--   create_moment / delete_moment.
--
-- Likes and comments (moments_likes, moments_comments)
--   WeChat's rule: a like or comment is visible to a viewer only when the
--   viewer is a friend of (or is) the poster AND of (or is) whoever liked or
--   commented, and, for a reply, of (or is) the person replied to. The
--   person who liked or commented must also still be a friend of the
--   poster. moments_interaction_visible is that rule; the row level
--   security policies, the feed and the notifications all use it, so
--   strangers' reactions are never readable, whatever the app shows.
--   Liking and commenting needs the post to be visible. The author of a
--   comment deletes it, and so does the author of the post.
--
-- Photos (private bucket "moments")
--   <author id>/<post id>-<n>.jpg and the thumbnail <post id>-<n>-t.jpg
--   (n 0 to 8), and covers as <author id>/cover-<uuid>.jpg. Only the author
--   writes and deletes their folder. Reading a post's picture needs
--   moments_post_visible_to for that post; a cover is read by the author
--   and their friends (minus anyone they hide Moments from).
--
-- Notifications (moments_notifications)
--   Likes, comments and replies on my posts and comments, made by triggers
--   and listed (only while they are still visible to me) by
--   list_moments_notifications in 202610180042.

-- ---------------------------------------------------------------- tables

create table if not exists public.moments_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  cover_path text,
  visible_range text not null default 'all',
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint moments_settings_range check (
    visible_range in ('all', 'six_months', 'one_month', 'three_days')
  ),
  constraint moments_settings_cover check (
    cover_path is null
    or (
      cover_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/cover-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$'
      and split_part(cover_path, '/', 1) = user_id::text
    )
  )
);

create table if not exists public.moments_friend_prefs (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  -- "Don't let them see my Moments"
  hide_mine boolean not null default false,
  -- "Hide their Moments"
  hide_theirs boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (owner_id, friend_id),
  constraint moments_friend_prefs_not_self check (owner_id <> friend_id)
);

create index if not exists moments_friend_prefs_friend_idx
  on public.moments_friend_prefs (friend_id, owner_id);

create table if not exists public.moments_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null default '',
  kind text not null default 'text',
  -- [{"path": "<author>/<post>-0.jpg", "thumb": "<author>/<post>-0-t.jpg", "w": 1280, "h": 960}]
  photos jsonb not null default '[]'::jsonb,
  link_url text,
  link_title text,
  location text,
  visibility text not null default 'friends',
  audience_friend_ids uuid[] not null default '{}',
  audience_tag_ids uuid[] not null default '{}',
  created_at timestamptz not null default now(),
  constraint moments_posts_body_length check (char_length(body) <= 2000),
  constraint moments_posts_kind check (kind in ('text', 'photos', 'link')),
  constraint moments_posts_photos check (
    jsonb_typeof(photos) = 'array' and jsonb_array_length(photos) <= 9
  ),
  constraint moments_posts_link check (
    (link_url is null or char_length(link_url) <= 2000)
    and (link_title is null or char_length(link_title) <= 200)
  ),
  constraint moments_posts_location check (
    location is null or char_length(location) <= 80
  ),
  constraint moments_posts_visibility check (
    visibility in ('friends', 'private', 'only', 'except')
  ),
  constraint moments_posts_audience check (
    cardinality(audience_friend_ids) <= 200 and cardinality(audience_tag_ids) <= 50
  ),
  constraint moments_posts_shape check (
    (kind = 'text' and jsonb_array_length(photos) = 0 and link_url is null and btrim(body) <> '')
    or (kind = 'photos' and jsonb_array_length(photos) between 1 and 9 and link_url is null)
    or (kind = 'link' and link_url is not null and jsonb_array_length(photos) = 0)
  )
);

create index if not exists moments_posts_author_idx
  on public.moments_posts (author_id, created_at desc, id desc);
create index if not exists moments_posts_created_idx
  on public.moments_posts (created_at desc, id desc);

create table if not exists public.moments_likes (
  post_id uuid not null references public.moments_posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index if not exists moments_likes_user_idx on public.moments_likes (user_id);

create table if not exists public.moments_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.moments_posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  reply_to_comment_id uuid references public.moments_comments(id) on delete set null,
  reply_to_user_id uuid references public.profiles(id) on delete set null,
  body text not null,
  created_at timestamptz not null default now(),
  constraint moments_comments_body check (char_length(btrim(body)) between 1 and 500)
);

create index if not exists moments_comments_post_idx
  on public.moments_comments (post_id, created_at, id);
create index if not exists moments_comments_author_idx
  on public.moments_comments (author_id);

create table if not exists public.moments_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null,
  post_id uuid not null references public.moments_posts(id) on delete cascade,
  comment_id uuid references public.moments_comments(id) on delete cascade,
  actor_id uuid not null references public.profiles(id) on delete cascade,
  snippet text not null default '',
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint moments_notifications_kind check (kind in ('like', 'comment', 'reply'))
);

create index if not exists moments_notifications_user_idx
  on public.moments_notifications (user_id, created_at desc);
create unique index if not exists moments_notifications_like_once_idx
  on public.moments_notifications (user_id, post_id, actor_id)
  where kind = 'like';

-- ------------------------------------------------------------ the rules

-- Friends, and neither blocked the other. Internal: no direct use by the app.
create or replace function public.moments_are_friends(user_a uuid, user_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select user_a is not null
    and user_b is not null
    and user_a <> user_b
    and exists (
      select 1
      from public.friendships f
      where f.user_low_id = least(user_a, user_b)
        and f.user_high_id = greatest(user_a, user_b)
    )
    and not exists (
      select 1
      from public.blocks b
      where (b.blocker_id = user_a and b.blocked_id = user_b)
         or (b.blocker_id = user_b and b.blocked_id = user_a)
    );
$$;

-- Whether [viewer] may see the post [p]. Internal: callers that run as the
-- signed-in person go through moments_can_view, so nobody can ask it about
-- somebody else.
create or replace function public.moments_post_visible_to(
  viewer uuid,
  p public.moments_posts
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  range_setting text;
  in_audience boolean;
begin
  if viewer is null or p.id is null then
    return false;
  end if;
  if p.author_id = viewer then
    return true;
  end if;
  if p.visibility = 'private' then
    return false;
  end if;
  if not public.moments_are_friends(viewer, p.author_id) then
    return false;
  end if;
  -- "Don't let them see my Moments"
  if exists (
    select 1
    from public.moments_friend_prefs fp
    where fp.owner_id = p.author_id
      and fp.friend_id = viewer
      and fp.hide_mine
  ) then
    return false;
  end if;
  -- The author's visible range
  select ms.visible_range into range_setting
  from public.moments_settings ms
  where ms.user_id = p.author_id;
  if (range_setting = 'six_months' and p.created_at < now() - interval '6 months')
    or (range_setting = 'one_month' and p.created_at < now() - interval '1 month')
    or (range_setting = 'three_days' and p.created_at < now() - interval '3 days')
  then
    return false;
  end if;

  if p.visibility = 'friends' then
    return true;
  end if;

  in_audience := viewer = any (p.audience_friend_ids)
    or exists (
      select 1
      from public.friend_tag_members m
      where m.owner_id = p.author_id
        and m.friend_id = viewer
        and m.tag_id = any (p.audience_tag_ids)
    );
  if p.visibility = 'only' then
    return in_audience;
  end if;
  -- except
  return not in_audience;
end;
$$;

-- The viewer may see the post [target_post_id].
create or replace function public.moments_can_view(target_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.moments_posts p
    where p.id = target_post_id
      and public.moments_post_visible_to(auth.uid(), p)
  );
$$;

-- The WeChat rule for a like or comment by [actor] on a post by [poster],
-- replying to [replied_to] (null: not a reply), seen by [viewer].
create or replace function public.moments_interaction_visible(
  viewer uuid,
  poster uuid,
  actor uuid,
  replied_to uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select viewer is not null
    and (viewer = actor or public.moments_are_friends(viewer, actor))
    and (viewer = poster or public.moments_are_friends(viewer, poster))
    and (actor = poster or public.moments_are_friends(actor, poster))
    and (
      replied_to is null
      or viewer = replied_to
      or public.moments_are_friends(viewer, replied_to)
    );
$$;

-- The signed-in person may see a like or comment by [actor] on [target_post_id].
create or replace function public.moments_can_see_interaction(
  target_post_id uuid,
  actor uuid,
  replied_to uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.moments_posts p
    where p.id = target_post_id
      and public.moments_post_visible_to(auth.uid(), p)
      and public.moments_interaction_visible(auth.uid(), p.author_id, actor, replied_to)
  );
$$;

-- The signed-in person may see the Moments cover and page of [owner]: it is
-- them, or a friend who has not been hidden from.
create or replace function public.moments_can_view_profile(owner uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
    and (
      owner = auth.uid()
      or (
        public.moments_are_friends(auth.uid(), owner)
        and not exists (
          select 1
          from public.moments_friend_prefs fp
          where fp.owner_id = owner
            and fp.friend_id = auth.uid()
            and fp.hide_mine
        )
      )
    );
$$;

revoke execute on function public.moments_are_friends(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.moments_post_visible_to(uuid, public.moments_posts) from public, anon, authenticated;
revoke execute on function public.moments_interaction_visible(uuid, uuid, uuid, uuid) from public, anon, authenticated;
revoke execute on function public.moments_can_view(uuid) from public, anon;
revoke execute on function public.moments_can_see_interaction(uuid, uuid, uuid) from public, anon;
revoke execute on function public.moments_can_view_profile(uuid) from public, anon;
grant execute on function public.moments_can_view(uuid) to authenticated;
grant execute on function public.moments_can_see_interaction(uuid, uuid, uuid) to authenticated;
grant execute on function public.moments_can_view_profile(uuid) to authenticated;

-- --------------------------------------------- row level security, grants

alter table public.moments_settings enable row level security;
alter table public.moments_friend_prefs enable row level security;
alter table public.moments_posts enable row level security;
alter table public.moments_likes enable row level security;
alter table public.moments_comments enable row level security;
alter table public.moments_notifications enable row level security;

revoke all on public.moments_settings from anon, authenticated;
revoke all on public.moments_friend_prefs from anon, authenticated;
revoke all on public.moments_posts from anon, authenticated;
revoke all on public.moments_likes from anon, authenticated;
revoke all on public.moments_comments from anon, authenticated;
revoke all on public.moments_notifications from anon, authenticated;

grant select on public.moments_settings to authenticated;
grant select on public.moments_friend_prefs to authenticated;
-- The audience (who a post is shared with or hidden from) is not readable.
grant select (
  id, author_id, body, kind, photos, link_url, link_title, location,
  visibility, created_at
) on public.moments_posts to authenticated;
grant select, insert, delete on public.moments_likes to authenticated;
grant select, insert, delete on public.moments_comments to authenticated;
-- Notifications are read and marked through functions only.

drop policy if exists moments_settings_select_own on public.moments_settings;
create policy moments_settings_select_own
  on public.moments_settings for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists moments_friend_prefs_select_own on public.moments_friend_prefs;
create policy moments_friend_prefs_select_own
  on public.moments_friend_prefs for select
  to authenticated
  using (owner_id = auth.uid());

drop policy if exists moments_posts_select_visible on public.moments_posts;
create policy moments_posts_select_visible
  on public.moments_posts for select
  to authenticated
  using (public.moments_can_view(id));

drop policy if exists moments_likes_select_visible on public.moments_likes;
create policy moments_likes_select_visible
  on public.moments_likes for select
  to authenticated
  using (public.moments_can_see_interaction(post_id, user_id, null));

drop policy if exists moments_likes_insert_own on public.moments_likes;
create policy moments_likes_insert_own
  on public.moments_likes for insert
  to authenticated
  with check (user_id = auth.uid() and public.moments_can_view(post_id));

drop policy if exists moments_likes_delete_own on public.moments_likes;
create policy moments_likes_delete_own
  on public.moments_likes for delete
  to authenticated
  using (user_id = auth.uid());

drop policy if exists moments_comments_select_visible on public.moments_comments;
create policy moments_comments_select_visible
  on public.moments_comments for select
  to authenticated
  using (public.moments_can_see_interaction(post_id, author_id, reply_to_user_id));

drop policy if exists moments_comments_insert_own on public.moments_comments;
create policy moments_comments_insert_own
  on public.moments_comments for insert
  to authenticated
  with check (author_id = auth.uid() and public.moments_can_view(post_id));

-- Your own comment, or any comment on your own post.
drop policy if exists moments_comments_delete_own_or_poster on public.moments_comments;
create policy moments_comments_delete_own_or_poster
  on public.moments_comments for delete
  to authenticated
  using (
    author_id = auth.uid()
    or exists (
      select 1
      from public.moments_posts p
      where p.id = post_id
        and p.author_id = auth.uid()
    )
  );

-- A reply points at a comment of the same post, which the replier can see;
-- the person replied to is that comment's author.
create or replace function public.moments_comments_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  parent public.moments_comments%rowtype;
  poster uuid;
begin
  new.body := btrim(new.body);
  if new.reply_to_comment_id is null then
    new.reply_to_user_id := null;
    return new;
  end if;
  select * into parent from public.moments_comments where id = new.reply_to_comment_id;
  if parent.id is null or parent.post_id <> new.post_id then
    raise exception 'That comment is not on this post' using errcode = '22023';
  end if;
  select author_id into poster from public.moments_posts where id = new.post_id;
  if not public.moments_interaction_visible(
    new.author_id, poster, parent.author_id, parent.reply_to_user_id
  ) then
    raise exception 'That comment is not on this post' using errcode = '22023';
  end if;
  new.reply_to_user_id := parent.author_id;
  return new;
end;
$$;

revoke execute on function public.moments_comments_before_insert() from public, anon, authenticated;

drop trigger if exists moments_comments_before_insert on public.moments_comments;
create trigger moments_comments_before_insert
  before insert on public.moments_comments
  for each row execute function public.moments_comments_before_insert();

-- ------------------------------------------------------- notifications

create or replace function public.moments_notify_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  poster uuid;
begin
  select author_id into poster from public.moments_posts where id = new.post_id;
  if poster is null or poster = new.user_id then
    return new;
  end if;
  if not public.moments_interaction_visible(poster, poster, new.user_id, null) then
    return new;
  end if;
  insert into public.moments_notifications (user_id, kind, post_id, actor_id)
  values (poster, 'like', new.post_id, new.user_id)
  on conflict (user_id, post_id, actor_id) where kind = 'like' do nothing;
  return new;
end;
$$;

create or replace function public.moments_unnotify_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.moments_notifications
  where kind = 'like'
    and post_id = old.post_id
    and actor_id = old.user_id;
  return old;
end;
$$;

create or replace function public.moments_notify_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  post public.moments_posts%rowtype;
begin
  select * into post from public.moments_posts where id = new.post_id;
  if post.id is null then
    return new;
  end if;
  -- The person replied to hears of the reply...
  if new.reply_to_user_id is not null
    and new.reply_to_user_id <> new.author_id
    and public.moments_post_visible_to(new.reply_to_user_id, post)
    and public.moments_interaction_visible(
      new.reply_to_user_id, post.author_id, new.author_id, new.reply_to_user_id
    )
  then
    insert into public.moments_notifications (
      user_id, kind, post_id, comment_id, actor_id, snippet
    )
    values (
      new.reply_to_user_id, 'reply', new.post_id, new.id, new.author_id,
      left(new.body, 200)
    );
  end if;
  -- ...and the poster of every comment on their post (one notice each).
  if post.author_id <> new.author_id
    and post.author_id is distinct from new.reply_to_user_id
    and public.moments_interaction_visible(
      post.author_id, post.author_id, new.author_id, new.reply_to_user_id
    )
  then
    insert into public.moments_notifications (
      user_id, kind, post_id, comment_id, actor_id, snippet
    )
    values (
      post.author_id, 'comment', new.post_id, new.id, new.author_id,
      left(new.body, 200)
    );
  end if;
  return new;
end;
$$;

revoke execute on function public.moments_notify_like() from public, anon, authenticated;
revoke execute on function public.moments_unnotify_like() from public, anon, authenticated;
revoke execute on function public.moments_notify_comment() from public, anon, authenticated;

drop trigger if exists moments_likes_notify on public.moments_likes;
create trigger moments_likes_notify
  after insert on public.moments_likes
  for each row execute function public.moments_notify_like();

drop trigger if exists moments_likes_unnotify on public.moments_likes;
create trigger moments_likes_unnotify
  after delete on public.moments_likes
  for each row execute function public.moments_unnotify_like();

drop trigger if exists moments_comments_notify on public.moments_comments;
create trigger moments_comments_notify
  after insert on public.moments_comments
  for each row execute function public.moments_notify_comment();

-- Unfriending and blocking remove the per-friend choices on both sides.
create or replace function public.forget_moments_friend_prefs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.moments_friend_prefs
  where (owner_id = old.user_low_id and friend_id = old.user_high_id)
     or (owner_id = old.user_high_id and friend_id = old.user_low_id);
  return old;
end;
$$;

revoke execute on function public.forget_moments_friend_prefs() from public, anon, authenticated;

drop trigger if exists friendships_forget_moments_prefs on public.friendships;
create trigger friendships_forget_moments_prefs
  after delete on public.friendships
  for each row execute function public.forget_moments_friend_prefs();

-- ------------------------------------------------------------- writing

-- Posts a moment. [p_id] is chosen by the app (its photos are uploaded to
-- <author>/<p_id>-<n>.jpg first); posting the same id again changes
-- nothing. Returns the id.
create or replace function public.create_moment(
  p_id uuid,
  p_body text default '',
  p_photos jsonb default '[]'::jsonb,
  p_link_url text default null,
  p_link_title text default null,
  p_location text default null,
  p_visibility text default 'friends',
  p_friend_ids uuid[] default '{}',
  p_tag_ids uuid[] default '{}'
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

  p_link_url := nullif(btrim(coalesce(p_link_url, '')), '');
  if p_link_url is not null and p_link_url !~* '^https?://[^\s]+$' then
    raise exception 'Links must start with http:// or https://' using errcode = '22023';
  end if;
  if photo_count > 0 and p_link_url is not null then
    raise exception 'A post has photos or a link, not both' using errcode = '22023';
  end if;
  post_kind := case
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
    id, author_id, body, kind, photos, link_url, link_title, location,
    visibility, audience_friend_ids, audience_tag_ids
  )
  values (
    p_id, me, body_text, post_kind, p_photos, p_link_url,
    left(nullif(btrim(coalesce(p_link_title, '')), ''), 200),
    left(nullif(btrim(coalesce(p_location, '')), ''), 80),
    p_visibility, friend_ids, tag_ids
  );
  return p_id;
end;
$$;

-- Deletes a post of the caller's and returns its picture files for the
-- app to remove from storage.
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
  where path.value is not null;
end;
$$;

-- The caller's cover and visible range. Each argument left null stays as it
-- is; [p_clear_cover] removes the cover. Returns the cover file this change
-- left unused, for the app to remove.
create or replace function public.set_moments_settings(
  p_visible_range text default null,
  p_cover_path text default null,
  p_clear_cover boolean default false
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  previous_cover text;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_visible_range is not null
    and p_visible_range not in ('all', 'six_months', 'one_month', 'three_days')
  then
    raise exception 'Unknown range' using errcode = '22023';
  end if;
  insert into public.moments_settings (user_id) values (me)
  on conflict (user_id) do nothing;
  select cover_path into previous_cover from public.moments_settings where user_id = me;
  update public.moments_settings
  set visible_range = coalesce(p_visible_range, visible_range),
      cover_path = case
        when p_clear_cover then null
        else coalesce(p_cover_path, cover_path)
      end,
      updated_at = now()
  where user_id = me;
  if previous_cover is not null
    and previous_cover is distinct from (
      select cover_path from public.moments_settings where user_id = me
    )
  then
    return previous_cover;
  end if;
  return null;
end;
$$;

-- "Don't let them see my Moments" and "Hide their Moments" for one friend.
-- Null leaves a switch as it is; both off removes the row.
create or replace function public.set_moments_friend_pref(
  p_friend_id uuid,
  p_hide_mine boolean default null,
  p_hide_theirs boolean default null
)
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
  if not public.moments_are_friends(me, p_friend_id) then
    raise exception 'Only friends can be chosen' using errcode = '22023';
  end if;
  insert into public.moments_friend_prefs (owner_id, friend_id, hide_mine, hide_theirs)
  values (me, p_friend_id, coalesce(p_hide_mine, false), coalesce(p_hide_theirs, false))
  on conflict (owner_id, friend_id) do update
  set hide_mine = coalesce(p_hide_mine, moments_friend_prefs.hide_mine),
      hide_theirs = coalesce(p_hide_theirs, moments_friend_prefs.hide_theirs),
      updated_at = now();
  delete from public.moments_friend_prefs
  where owner_id = me and friend_id = p_friend_id and not hide_mine and not hide_theirs;
end;
$$;

revoke execute on function public.create_moment(uuid, text, jsonb, text, text, text, text, uuid[], uuid[]) from public, anon;
revoke execute on function public.delete_moment(uuid) from public, anon;
revoke execute on function public.set_moments_settings(text, text, boolean) from public, anon;
revoke execute on function public.set_moments_friend_pref(uuid, boolean, boolean) from public, anon;
grant execute on function public.create_moment(uuid, text, jsonb, text, text, text, text, uuid[], uuid[]) to authenticated;
grant execute on function public.delete_moment(uuid) to authenticated;
grant execute on function public.set_moments_settings(text, text, boolean) to authenticated;
grant execute on function public.set_moments_friend_pref(uuid, boolean, boolean) to authenticated;

-- ------------------------------------------------------------- pictures

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'moments',
  'moments',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Whether the signed-in person may read the object [object_name] of the
-- moments bucket: their own files, the pictures of posts they may see, and
-- the covers of friends who have not hidden their Moments from them.
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
  if file_name ~ ('^' || uuid_pattern || '-[0-8](-t)?\.jpg$') then
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

revoke execute on function public.moments_can_read_object(text) from public, anon;
grant execute on function public.moments_can_read_object(text) to authenticated;

drop policy if exists moments_select_visible on storage.objects;
create policy moments_select_visible
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'moments'
    and public.moments_can_read_object(name)
  );

drop policy if exists moments_insert_owner on storage.objects;
create policy moments_insert_owner
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'moments'
    and (storage.foldername(name))[1] = auth.uid()::text
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/(cover-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-[0-8](-t)?)\.jpg$'
  );

drop policy if exists moments_delete_owner on storage.objects;
create policy moments_delete_owner
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'moments'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
