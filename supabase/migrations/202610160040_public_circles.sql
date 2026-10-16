-- Public circles: a circle is private (invite only, the default) or public
-- (listed in discovery, anyone signed in can join; bans, onboarding rules
-- and AutoMod still apply, see 202610160041).
--
-- * circles.is_public, and what discovery shows about it:
--   discovery_description (up to 300 characters), discovery_category (one
--   of a fixed list), discovery_language (a short language code such as
--   'en' or 'zh-hant') and discovery_tags (up to 5, each 1 to 24
--   characters, lower case, no commas or '#'). discovery_listed_at is when
--   the circle was first made public ("New" in discovery); it stays when
--   the circle goes private and public again, so toggling doesn't bring a
--   circle back to the top. A public circle needs a category.
-- * Search: circles.discovery_search is a tsvector over the name, tags
--   (weight A) and description (weight B) with the 'simple' configuration
--   (no stemming: names and tags are in any language), with a GIN index.
--   Postgres full-text search doesn't segment Chinese (or Japanese), so
--   discovery also matches a substring of circle_discovery_text(...) with
--   ILIKE, served by a pg_trgm GIN index (pg_trgm in the extensions
--   schema, as Supabase installs it). Both indexes only cover public
--   circles.
-- * get_circle_discovery(circle_id): the settings, for members.
--   set_circle_discovery(circle_id, make_public, about, category, language,
--   tag_list): manage_circle (202610160020) in the circle; audited as
--   discovery_update with the old and new value of each changed field.

create extension if not exists pg_trgm with schema extensions;

alter table public.circles
  add column if not exists is_public boolean not null default false,
  add column if not exists discovery_description text,
  add column if not exists discovery_category text,
  add column if not exists discovery_language text,
  add column if not exists discovery_tags text[] not null default '{}',
  add column if not exists discovery_listed_at timestamptz;

alter table public.circles
  drop constraint if exists circles_discovery_description_length;
alter table public.circles
  add constraint circles_discovery_description_length check (
    discovery_description is null
    or (
      discovery_description = btrim(discovery_description)
      and char_length(discovery_description) between 1 and 300
    )
  );

alter table public.circles
  drop constraint if exists circles_discovery_category_known;
alter table public.circles
  add constraint circles_discovery_category_known check (
    discovery_category is null
    or discovery_category in (
      'gaming', 'music', 'education', 'science_tech', 'entertainment',
      'art', 'sports', 'travel_outdoors', 'food', 'local', 'other'
    )
  );

alter table public.circles
  drop constraint if exists circles_discovery_language_format;
alter table public.circles
  add constraint circles_discovery_language_format check (
    discovery_language is null
    or discovery_language ~ '^[a-z]{2,3}(-[a-z0-9]{2,8})?$'
  );

alter table public.circles
  drop constraint if exists circles_discovery_tags_count;
alter table public.circles
  add constraint circles_discovery_tags_count check (
    cardinality(discovery_tags) <= 5
  );

alter table public.circles
  drop constraint if exists circles_public_has_category;
alter table public.circles
  add constraint circles_public_has_category check (
    not is_public or discovery_category is not null
  );

-- The text discovery matches substrings of (lower case). Declared
-- immutable for the indexes: array_to_string of text[] is deterministic.
create or replace function public.circle_discovery_text(
  circle_name text,
  about text,
  tags text[]
)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  select lower(
    coalesce(circle_name, '')
    || ' ' || coalesce(array_to_string(tags, ' '), '')
    || ' ' || coalesce(about, '')
  );
$$;

create or replace function public.circle_discovery_document(
  circle_name text,
  about text,
  tags text[]
)
returns tsvector
language sql
immutable
parallel safe
set search_path = public
as $$
  select
    setweight(to_tsvector('simple'::regconfig, coalesce(circle_name, '')), 'A')
    || setweight(
      to_tsvector('simple'::regconfig, coalesce(array_to_string(tags, ' '), '')),
      'A'
    )
    || setweight(to_tsvector('simple'::regconfig, coalesce(about, '')), 'B');
$$;

alter table public.circles
  add column if not exists discovery_search tsvector
    generated always as (
      public.circle_discovery_document(
        name,
        discovery_description,
        discovery_tags
      )
    ) stored;

create index if not exists circles_discovery_search_idx
  on public.circles using gin (discovery_search)
  where is_public;

create index if not exists circles_discovery_trgm_idx
  on public.circles using gin (
    public.circle_discovery_text(name, discovery_description, discovery_tags)
    extensions.gin_trgm_ops
  )
  where is_public;

create index if not exists circles_discovery_listed_idx
  on public.circles (discovery_listed_at desc)
  where is_public;

create index if not exists circles_discovery_category_idx
  on public.circles (discovery_category)
  where is_public;

-- Tags as stored: trimmed, without a leading '#', lower case, no blanks
-- or repeats, in the order given.
create or replace function public.normalize_circle_discovery_tags(tag_list text[])
returns text[]
language plpgsql
immutable
set search_path = public
as $$
declare
  tag text;
  cleaned text;
  result text[] := '{}';
begin
  foreach tag in array coalesce(tag_list, '{}'::text[]) loop
    cleaned := lower(btrim(regexp_replace(coalesce(tag, ''), '^\s*#+', '')));
    if cleaned = '' then
      continue;
    end if;
    if char_length(cleaned) > 24 or cleaned ~ '[,#]' then
      raise exception 'A tag is up to 24 characters without commas or #'
        using errcode = '22023';
    end if;
    if not cleaned = any(result) then
      result := result || cleaned;
    end if;
  end loop;
  if cardinality(result) > 5 then
    raise exception 'At most 5 tags' using errcode = '22023';
  end if;
  return result;
end;
$$;

create or replace function public.circle_discovery_payload(circle public.circles)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'is_public', circle.is_public,
    'description', circle.discovery_description,
    'category', circle.discovery_category,
    'language', circle.discovery_language,
    'tags', to_jsonb(circle.discovery_tags),
    'listed_at', circle.discovery_listed_at
  );
$$;

revoke execute on function public.circle_discovery_payload(public.circles)
  from public, anon, authenticated;
revoke execute on function public.normalize_circle_discovery_tags(text[])
  from public, anon;

create or replace function public.get_circle_discovery(target_circle_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  circle public.circles%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.is_current_user_circle_member(target_circle_id) then
    raise exception 'Circle not found or caller is not a member'
      using errcode = '42501';
  end if;

  select c.* into circle from public.circles c where c.id = target_circle_id;
  return public.circle_discovery_payload(circle);
end;
$$;

create or replace function public.set_circle_discovery(
  target_circle_id uuid,
  make_public boolean,
  about text default null,
  category text default null,
  language text default null,
  tag_list text[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  circle public.circles%rowtype;
  new_description text := nullif(btrim(coalesce(about, '')), '');
  new_category text := nullif(btrim(coalesce(category, '')), '');
  new_language text := nullif(lower(btrim(coalesce(language, ''))), '');
  new_tags text[];
  new_public boolean := coalesce(make_public, false);
  changes jsonb := '{}'::jsonb;
  updated public.circles%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'Only members who manage the circle can change discovery'
      using errcode = '42501';
  end if;

  if new_description is not null and char_length(new_description) > 300 then
    raise exception 'A description is up to 300 characters'
      using errcode = '22023';
  end if;

  if new_category is not null and new_category not in (
    'gaming', 'music', 'education', 'science_tech', 'entertainment',
    'art', 'sports', 'travel_outdoors', 'food', 'local', 'other'
  ) then
    raise exception 'Unknown category' using errcode = '22023';
  end if;

  if new_public and new_category is null then
    raise exception 'A public circle needs a category' using errcode = '22023';
  end if;

  if new_language is not null
    and new_language !~ '^[a-z]{2,3}(-[a-z0-9]{2,8})?$'
  then
    raise exception 'Unknown language' using errcode = '22023';
  end if;

  new_tags := public.normalize_circle_discovery_tags(tag_list);

  select c.* into circle
  from public.circles c
  where c.id = target_circle_id
  for update;

  if circle.is_public is distinct from new_public then
    changes := changes || jsonb_build_object(
      'is_public', jsonb_build_object('old', circle.is_public, 'new', new_public)
    );
  end if;
  if circle.discovery_description is distinct from new_description then
    changes := changes || jsonb_build_object(
      'description',
      jsonb_build_object('old', circle.discovery_description, 'new', new_description)
    );
  end if;
  if circle.discovery_category is distinct from new_category then
    changes := changes || jsonb_build_object(
      'category',
      jsonb_build_object('old', circle.discovery_category, 'new', new_category)
    );
  end if;
  if circle.discovery_language is distinct from new_language then
    changes := changes || jsonb_build_object(
      'language',
      jsonb_build_object('old', circle.discovery_language, 'new', new_language)
    );
  end if;
  if circle.discovery_tags is distinct from new_tags then
    changes := changes || jsonb_build_object(
      'tags',
      jsonb_build_object('old', to_jsonb(circle.discovery_tags), 'new', to_jsonb(new_tags))
    );
  end if;

  if changes = '{}'::jsonb then
    return public.circle_discovery_payload(circle);
  end if;

  update public.circles c
  set
    is_public = new_public,
    discovery_description = new_description,
    discovery_category = new_category,
    discovery_language = new_language,
    discovery_tags = new_tags,
    discovery_listed_at = case
      when new_public then coalesce(c.discovery_listed_at, now())
      else c.discovery_listed_at
    end
  where c.id = circle.id
  returning c.* into updated;

  perform public.write_circle_audit(
    circle.id,
    'discovery_update',
    'circle',
    circle.id,
    circle.name,
    changes
  );

  return public.circle_discovery_payload(updated);
end;
$$;

revoke execute on function public.get_circle_discovery(uuid) from public, anon;
revoke execute on function public.set_circle_discovery(uuid, boolean, text, text, text, text[])
  from public, anon;
grant execute on function public.get_circle_discovery(uuid) to authenticated;
grant execute on function public.set_circle_discovery(uuid, boolean, text, text, text, text[])
  to authenticated;
