-- Daily (B1), part 1 of 6: the tables.
--
-- A "daily" is a photo or a short video that disappears after 24 hours
-- (Instagram Stories, WhatsApp Status). The product name is "Daily"; the
-- tables say stories. Moments (202610180041) stay the long-lived feed.
--
-- * stories: one daily. The media is in the private bucket "stories"
--   (202610240210), named <author id>/<story id>.jpg (the photo, or the
--   video's poster frame), <story id>-t.jpg (the thumbnail) and, for a
--   video, <story id>-v.mp4|mov|webm. Videos are 15 seconds and 20 MB at most.
--   expires_at is created_at + 24 hours; after it nobody (the author
--   included) can see the daily, and the purge (202610240240) removes the
--   row and the files.
--   The audience is the Moments model: visibility is
--     friends  every friend of the author
--     close    the author's close friends (story_close_friends)
--     private  only the author
--     only     the friends in audience_friend_ids and in the author's tags
--     except   every friend but those
--   The audience columns are not readable through the table (who a daily was
--   hidden from is the author's secret), like moments_posts.
-- * story_views: who opened which daily. Only the author may see it, through
--   list_story_viewers (202610240220); the table itself is closed.
-- * story_reactions: one quick emoji per viewer and daily, seen by the author
--   in the same list.
-- * story_close_friends: the author's close friends, a list of friends.
--   Unfriending or blocking removes the person (a trigger in 202610240210).
-- * story_media_cleanup: the files of dailies that are gone, queued for the
--   expire-stories Edge Function to remove from Storage (202610240240).
--
-- Nothing here is readable through the API except the daily rows a person
-- may see (story_can_view, 202610240210).

-- ---------------------------------------------------------------- tables

create table if not exists public.story_close_friends (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, friend_id),
  constraint story_close_friends_not_self check (owner_id <> friend_id)
);

create index if not exists story_close_friends_friend_idx
  on public.story_close_friends (friend_id, owner_id);

create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  media_kind text not null,
  -- The photo, or the video file.
  media_path text not null,
  -- A video's poster frame (the full-size picture); null for a photo.
  poster_path text,
  thumb_path text not null,
  width integer not null default 0,
  height integer not null default 0,
  duration_ms integer,
  size bigint not null default 0,
  mime text not null default 'image/jpeg',
  caption text not null default '',
  visibility text not null default 'friends',
  audience_friend_ids uuid[] not null default '{}',
  audience_tag_ids uuid[] not null default '{}',
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  constraint stories_media_kind check (media_kind in ('photo', 'video')),
  constraint stories_caption_length check (char_length(caption) <= 200),
  constraint stories_visibility check (
    visibility in ('friends', 'close', 'private', 'only', 'except')
  ),
  constraint stories_audience check (
    cardinality(audience_friend_ids) <= 200 and cardinality(audience_tag_ids) <= 50
  ),
  constraint stories_shape check (
    (media_kind = 'photo' and poster_path is null and duration_ms is null)
    or (media_kind = 'video' and poster_path is not null and duration_ms between 1 and 16000)
  ),
  constraint stories_size check (size between 0 and 20971520)
);

create index if not exists stories_author_idx
  on public.stories (author_id, created_at, id);
create index if not exists stories_expires_idx on public.stories (expires_at);

create table if not exists public.story_views (
  story_id uuid not null references public.stories(id) on delete cascade,
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (story_id, viewer_id)
);

create index if not exists story_views_viewer_idx
  on public.story_views (viewer_id, story_id);

create table if not exists public.story_reactions (
  story_id uuid not null references public.stories(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  primary key (story_id, user_id),
  constraint story_reactions_emoji check (char_length(emoji) between 1 and 16)
);

-- Files of dailies that are gone, waiting for Storage to drop them.
create table if not exists public.story_media_cleanup (
  bucket_id text not null default 'stories',
  object_path text not null,
  created_at timestamptz not null default now(),
  primary key (bucket_id, object_path)
);

create index if not exists story_media_cleanup_created_idx
  on public.story_media_cleanup (created_at);

-- A report of a daily (A1 for the Daily; the handling is in 202610240230).
-- story_id is set null when the daily is purged; the copy of what was
-- reported stays in snapshot until 90 days after the report was handled.
create table if not exists public.story_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  story_id uuid references public.stories(id) on delete set null,
  -- The author of the daily.
  reported_user_id uuid references public.profiles(id) on delete set null,
  reason text not null,
  details text not null default '',
  snapshot jsonb,
  status text not null default 'open',
  handled_by uuid references public.profiles(id) on delete set null,
  handled_at timestamptz,
  resolution text,
  created_at timestamptz not null default now(),
  constraint story_reports_reason_check check (
    reason in ('spam', 'harassment', 'impersonation', 'unsafe_content', 'other')
  ),
  constraint story_reports_status_check check (
    status in ('open', 'actioned', 'dismissed')
  ),
  constraint story_reports_details_length check (char_length(details) <= 1000),
  constraint story_reports_resolution_length check (
    resolution is null or char_length(resolution) between 1 and 40
  )
);

create unique index if not exists story_reports_once_per_reporter_idx
  on public.story_reports (reporter_id, story_id)
  where story_id is not null;
create index if not exists story_reports_reporter_created_idx
  on public.story_reports (reporter_id, created_at desc);
create index if not exists story_reports_status_idx
  on public.story_reports (status, created_at desc);
create index if not exists story_reports_story_idx
  on public.story_reports (story_id)
  where story_id is not null;

-- ---------------------------------------------- row level security, grants

alter table public.story_close_friends enable row level security;
alter table public.stories enable row level security;
alter table public.story_views enable row level security;
alter table public.story_reactions enable row level security;
alter table public.story_media_cleanup enable row level security;
alter table public.story_reports enable row level security;

revoke all on public.story_close_friends from public, anon, authenticated;
revoke all on public.stories from public, anon, authenticated;
revoke all on public.story_views from public, anon, authenticated;
revoke all on public.story_reactions from public, anon, authenticated;
revoke all on public.story_media_cleanup from public, anon, authenticated;
-- Reports are filed and read through functions only.
revoke all on public.story_reports from public, anon, authenticated;

-- A person reads their own close friends; the functions change them.
grant select on public.story_close_friends to authenticated;
-- The audience (who a daily is shared with or hidden from) is not readable.
grant select (
  id, author_id, media_kind, media_path, poster_path, thumb_path, width,
  height, duration_ms, size, mime, caption, visibility, created_at, expires_at
) on public.stories to authenticated;

drop policy if exists story_close_friends_select_own on public.story_close_friends;
create policy story_close_friends_select_own
  on public.story_close_friends for select
  to authenticated
  using (owner_id = auth.uid());
