-- Topics (#话题) and circle posts 2.0 (roadmap B8), part 1 of 8: the tags.
--
-- A topic is a word after a hash sign: #读书, #travel. Nothing here makes a
-- public topic page. A topic is only a way to filter what the person can
-- already see:
--   * Moments: the tags of a post are read from its text when it is written.
--     Counting and filtering by a tag only ever look at posts the caller may
--     see (moments_post_visible_to), so a tag collects the caller's own posts
--     and their friends' posts that were shared with them, and nothing else.
--   * Circle posts: a tag collects the posts of one circle for its members.
--
-- Reading a tag out of text is done here and in the app
-- (lib/features/hashtags/hashtag_text.dart) with the same rules, kept equal by
-- the shared cases in test/fixtures/hashtag_cases.json:
--   * it starts with # (or the full-width ＃) that is not glued to a letter,
--     digit, underscore, / & = ? or another hash (so C#, a#b and web
--     addresses like https://x.com/#top are not tags);
--   * 1 to 30 characters of letters, digits, underscores and CJK text. Spaces,
--     punctuation (ASCII and CJK), @ and # end it. A word that is longer than
--     30 characters is not a tag, and a tag of digits only (#1) is not one;
--   * lower-cased, at most 10 per post, the first ones when there are more.
--
-- This part:
--   * hashtag_chars / hashtag_clean / hashtag_clean_list / hashtags_from_text;
--   * moments_posts.tags (set by a trigger from the body, so create_moment is
--     not rewritten) and circle_posts.title, tags, featured_at, featured_by;
--   * the existing posts are given their tags.

-- ---------------------------------------------------------------------------
-- Reading and cleaning tags
-- ---------------------------------------------------------------------------

-- The characters a tag may be made of, as a regular expression bracket: not
-- white space (including no-break and ideographic spaces and zero-width
-- characters), not # or ＃ or @, not ASCII punctuation except the underscore,
-- not the usual CJK punctuation.
create or replace function public.hashtag_chars()
returns text
language sql
immutable
as $$
  select '[^\s#＃@ ​-‏ - 　﻿!-/:-@[-^`{-~，。！？、；：“”‘’（）【】《》〈〉「」『』…·～￥]'
$$;

revoke execute on function public.hashtag_chars() from public, anon;

-- One tag cleaned up: no leading hash, lower case, or null when it is not a
-- valid tag.
create or replace function public.hashtag_clean(p_tag text)
returns text
language plpgsql
immutable
as $$
declare
  tag text := lower(btrim(coalesce(p_tag, '')));
begin
  tag := regexp_replace(tag, '^[#＃]+', '');
  if tag !~ ('^' || public.hashtag_chars() || '{1,30}$') then
    return null;
  end if;
  if tag ~ '^[0-9]+$' then
    return null;
  end if;
  return tag;
end;
$$;

revoke execute on function public.hashtag_clean(text) from public, anon;

-- A list of tags cleaned: invalid ones dropped, repeats folded, the first
-- ones kept (10 at most, or p_limit).
create or replace function public.hashtag_clean_list(
  p_tags text[],
  p_limit integer default 10
)
returns text[]
language plpgsql
immutable
as $$
declare
  result text[] := '{}';
  raw text;
  tag text;
begin
  if p_tags is null then
    return result;
  end if;
  foreach raw in array p_tags loop
    tag := public.hashtag_clean(raw);
    if tag is not null and not (tag = any (result)) then
      result := result || tag;
      exit when cardinality(result) >= greatest(coalesce(p_limit, 10), 1);
    end if;
  end loop;
  return result;
end;
$$;

revoke execute on function public.hashtag_clean_list(text[], integer) from public, anon;

-- The tags written in a text, in order, without repeats.
create or replace function public.hashtags_from_text(p_text text)
returns text[]
language plpgsql
immutable
as $$
declare
  found text[] := '{}';
  chars text := public.hashtag_chars();
  m text[];
  tag text;
begin
  if p_text is null or (position('#' in p_text) = 0 and position('＃' in p_text) = 0) then
    return found;
  end if;
  for m in
    select regexp_matches(
      p_text,
      '(?<![A-Za-z0-9_/&=?#＃])[#＃](' || chars || '{1,30})(?!' || chars || ')',
      'g'
    )
  loop
    tag := public.hashtag_clean(m[1]);
    if tag is not null and not (tag = any (found)) then
      found := found || tag;
      exit when cardinality(found) >= 10;
    end if;
  end loop;
  return found;
end;
$$;

revoke execute on function public.hashtags_from_text(text) from public, anon;

-- ---------------------------------------------------------------------------
-- Moments
-- ---------------------------------------------------------------------------

alter table public.moments_posts
  add column if not exists tags text[] not null default '{}';

alter table public.moments_posts
  drop constraint if exists moments_posts_tags;
alter table public.moments_posts
  add constraint moments_posts_tags check (cardinality(tags) <= 10);

create index if not exists moments_posts_tags_idx
  on public.moments_posts using gin (tags);

-- The tags come from the text, whoever wrote the row (create_moment stays as
-- it is). The text of a Moment cannot be edited; the update is for safety.
create or replace function public.moments_posts_set_tags()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.tags := public.hashtags_from_text(new.body);
  return new;
end;
$$;

revoke execute on function public.moments_posts_set_tags() from public, anon, authenticated;

drop trigger if exists moments_posts_set_tags on public.moments_posts;
create trigger moments_posts_set_tags
  before insert or update of body on public.moments_posts
  for each row execute function public.moments_posts_set_tags();

update public.moments_posts p
set tags = public.hashtags_from_text(p.body)
where p.body ~ '[#＃]'
  and p.tags is distinct from public.hashtags_from_text(p.body);

-- ---------------------------------------------------------------------------
-- Circle posts
-- ---------------------------------------------------------------------------

alter table public.circle_posts
  add column if not exists title text,
  add column if not exists tags text[] not null default '{}',
  add column if not exists featured_at timestamptz,
  add column if not exists featured_by uuid references public.profiles(id) on delete set null;

alter table public.circle_posts
  drop constraint if exists circle_posts_title_length;
alter table public.circle_posts
  add constraint circle_posts_title_length check (
    title is null
    or (
      title = btrim(title)
      and char_length(title) between 1 and 80
      and title !~ '[\r\n\t]'
    )
  );

alter table public.circle_posts
  drop constraint if exists circle_posts_tags;
alter table public.circle_posts
  add constraint circle_posts_tags check (cardinality(tags) <= 10);

create index if not exists circle_posts_tags_idx
  on public.circle_posts using gin (tags)
  where deleted_at is null;

create index if not exists circle_posts_featured_idx
  on public.circle_posts (circle_id, featured_at desc)
  where featured_at is not null and deleted_at is null;

-- The tags of a post: the ones the author picked plus the ones written in the
-- title or the text, cleaned (10 at most). Featuring always carries a time.
create or replace function public.circle_posts_set_tags()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.title := nullif(btrim(regexp_replace(coalesce(new.title, ''), '\s+', ' ', 'g')), '');
  new.tags := public.hashtag_clean_list(
    coalesce(new.tags, '{}')
      || public.hashtags_from_text(new.title)
      || public.hashtags_from_text(new.body)
  );
  if new.featured_at is null then
    new.featured_by := null;
  end if;
  return new;
end;
$$;

revoke execute on function public.circle_posts_set_tags() from public, anon, authenticated;

drop trigger if exists circle_posts_set_tags on public.circle_posts;
create trigger circle_posts_set_tags
  before insert or update of title, body, tags, featured_at on public.circle_posts
  for each row execute function public.circle_posts_set_tags();

update public.circle_posts p
set tags = public.hashtags_from_text(p.body)
where p.body ~ '[#＃]';
