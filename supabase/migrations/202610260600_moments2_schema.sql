-- Moments 2.0 (roadmap B2), part 1 of 6: the columns, the rules about them
-- and the files.
--
-- What changes on the existing tables (nothing is rewritten, everything that
-- was there keeps working):
--
-- * moments_posts.mentioned_user_ids ("Remind who to read"): friends the
--   author asked to look at the post, at most 30. Only people who can see the
--   post are kept (create_moment, 202610260610, filters them), so a mention
--   never shows a post to someone the audience excludes. The column is not
--   readable through the API (like the audience columns); moments_feed shows
--   the names to the author only and tells a mentioned person that they were.
-- * moments_posts.pinned_at ("Pin"): when the author pinned the post; at most
--   3 pinned posts per author (set_moment_pinned). Not readable through the
--   API either: moments_feed returns it.
-- * Pictures of posts may carry a description (`alt`, L8): a trigger keeps it
--   text, trimmed and at most 1000 characters, so create_moment need not be
--   changed for it.
-- * moments_comments.image: one picture or sticker on a comment,
--   {path, w, h, alt}. The file lives in the commenter's own folder of the
--   private "moments" bucket as c-<comment id>.<jpg|png|webp|gif>; a trigger
--   checks the name belongs to this comment and its author and that the file
--   is uploaded. Reading the file follows the comment: whoever may see the
--   comment may read its picture (moments_can_read_object, 202610260620), so
--   unfriending or blocking cuts it off at once. A comment may now have no
--   words when it has a picture.
-- * moments_notifications.kind gains 'mention'.
-- * The bucket also takes GIF (an animated sticker).

alter table public.moments_posts
  add column if not exists mentioned_user_ids uuid[] not null default '{}',
  add column if not exists pinned_at timestamptz;

alter table public.moments_posts
  drop constraint if exists moments_posts_mentions;
alter table public.moments_posts
  add constraint moments_posts_mentions check (
    cardinality(mentioned_user_ids) <= 30
  );

create index if not exists moments_posts_pinned_idx
  on public.moments_posts (author_id, pinned_at desc)
  where pinned_at is not null;

create index if not exists moments_posts_mentioned_idx
  on public.moments_posts using gin (mentioned_user_ids);

-- ------------------------------------------------ picture descriptions

-- Each picture's `alt` stays text, trimmed, 1000 characters at most; a
-- description that is not text or is empty is dropped. (Other keys are left
-- as they are: create_moment already checks the file names.)
create or replace function public.moments_posts_clean_photos()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.photos is null or jsonb_typeof(new.photos) <> 'array' then
    return new;
  end if;
  new.photos := coalesce((
    select jsonb_agg(
      case
        when jsonb_typeof(e.value) <> 'object' then e.value
        when jsonb_typeof(e.value->'alt') = 'string'
          and btrim(e.value->>'alt') <> ''
        then jsonb_set(
          e.value, '{alt}', to_jsonb(left(btrim(e.value->>'alt'), 1000))
        )
        else e.value - 'alt'
      end
      order by e.ord
    )
    from jsonb_array_elements(new.photos) with ordinality as e(value, ord)
  ), '[]'::jsonb);
  return new;
end;
$$;

revoke execute on function public.moments_posts_clean_photos()
  from public, anon, authenticated;

drop trigger if exists moments_posts_clean_photos on public.moments_posts;
create trigger moments_posts_clean_photos
  before insert on public.moments_posts
  for each row execute function public.moments_posts_clean_photos();

-- ---------------------------------------------------- comment pictures

alter table public.moments_comments
  add column if not exists image jsonb;

-- Words, a picture or both (500 characters of words at most, as before).
alter table public.moments_comments
  drop constraint if exists moments_comments_body;
alter table public.moments_comments
  add constraint moments_comments_body check (
    char_length(btrim(body)) <= 500
    and (char_length(btrim(body)) >= 1 or image is not null)
  );

alter table public.moments_comments
  drop constraint if exists moments_comments_image_shape;
alter table public.moments_comments
  add constraint moments_comments_image_shape check (
    image is null
    or (jsonb_typeof(image) = 'object' and image ? 'path')
  );

-- The picture of a new comment: its file is the commenter's own, named after
-- this comment, and uploaded. Runs after moments_comments_before_insert
-- (triggers fire by name), which has already trimmed the words.
create or replace function public.moments_comments_image_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  image_path text;
  clean jsonb;
  width integer;
  height integer;
  description text;
begin
  if new.image is null or new.image = 'null'::jsonb then
    new.image := null;
    return new;
  end if;
  if jsonb_typeof(new.image) <> 'object' then
    raise exception 'The picture is malformed' using errcode = '22023';
  end if;
  image_path := new.image->>'path';
  if image_path is null
    or image_path !~ (
      '^' || new.author_id::text || '/c-' || new.id::text || '\.(jpg|png|webp|gif)$'
    )
  then
    raise exception 'That picture is not yours' using errcode = '22023';
  end if;
  if not exists (
    select 1
    from storage.objects o
    where o.bucket_id = 'moments' and o.name = image_path
  ) then
    raise exception 'The picture was not uploaded' using errcode = '22023';
  end if;
  width := case
    when jsonb_typeof(new.image->'w') = 'number'
    then greatest(0, least(4096, (new.image->>'w')::numeric::integer))
    else 0
  end;
  height := case
    when jsonb_typeof(new.image->'h') = 'number'
    then greatest(0, least(4096, (new.image->>'h')::numeric::integer))
    else 0
  end;
  description := case
    when jsonb_typeof(new.image->'alt') = 'string'
    then nullif(left(btrim(new.image->>'alt'), 1000), '')
  end;
  clean := jsonb_build_object('path', image_path, 'w', width, 'h', height);
  if description is not null then
    clean := clean || jsonb_build_object('alt', description);
  end if;
  new.image := clean;
  return new;
end;
$$;

revoke execute on function public.moments_comments_image_before_insert()
  from public, anon, authenticated;

drop trigger if exists moments_comments_image_before_insert on public.moments_comments;
create trigger moments_comments_image_before_insert
  before insert on public.moments_comments
  for each row execute function public.moments_comments_image_before_insert();

-- ------------------------------------------------------- notifications

alter table public.moments_notifications
  drop constraint if exists moments_notifications_kind;
alter table public.moments_notifications
  add constraint moments_notifications_kind check (
    kind in ('like', 'comment', 'reply', 'mention')
  );

-- One reminder per post and person.
create unique index if not exists moments_notifications_mention_once_idx
  on public.moments_notifications (user_id, post_id)
  where kind = 'mention';

-- ---------------------------------------------------------------- files

update storage.buckets
set allowed_mime_types = array[
      'image/jpeg', 'image/png', 'image/webp', 'image/gif',
      'video/mp4', 'video/quicktime', 'video/webm'
    ]
where id = 'moments';

-- 202610190022 plus c-<comment id>.<jpg|png|webp|gif>, a comment's picture.
drop policy if exists moments_insert_owner on storage.objects;
create policy moments_insert_owner
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'moments'
    and (storage.foldername(name))[1] = auth.uid()::text
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/(cover-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg|c-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp|gif)|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-([0-8](-t)?\.jpg|v\.(mp4|mov|webm)))$'
  );
