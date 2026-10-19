-- Support links (J4): a creator's "support me" pages on their profile, and a
-- circle's own support page. WeCord never touches the money; the link only
-- points to a page elsewhere.
--
--   profiles.links      up to 5 {url, label} entries
--   circles.support_url one URL
--
-- Only https links to a short list of known support platforms are accepted;
-- anything else is refused here (the app checks the same list, so it can
-- show a clear message and an icon, but the server does not trust it):
-- afdian.com, afdian.net, ifdian.net (爱发电), ko-fi.com, patreon.com,
-- buymeacoffee.com, liberapay.com, opencollective.com, paypal.me, fanbox.cc,
-- boosty.to and GitHub Sponsors (github.com/sponsors/...). A host matches the
-- domain itself or a subdomain of it ("www.patreon.com"), never a look-alike
-- ("patreon.com.example.net", "notpatreon.com"). No port, no user name in
-- the address, no spaces or quotes, at most 300 characters.
--
-- The app hides these links on iPhone (App Store guideline 3.1.1); the
-- server stores and returns them the same everywhere.
--
-- Like the birthday, the links are not granted as columns: they are read
-- through get_profile_extras (202610230650, which applies the profile
-- visibility rule) and get_my_profile_extras, and written through
-- set_my_links. A circle's link is read by its members
-- (get_circle_support_url) and written by those who manage the circle.

-- The normalized form of a support link, or null when it is not allowed.
create or replace function public.normalize_support_url(url text)
returns text
language plpgsql
immutable
as $$
declare
  cleaned text := btrim(coalesce(url, ''));
  parts text[];
  host text;
  tail text;
  allowed text[] := array[
    'afdian.com', 'afdian.net', 'ifdian.net', 'ko-fi.com', 'patreon.com',
    'buymeacoffee.com', 'liberapay.com', 'opencollective.com', 'paypal.me',
    'fanbox.cc', 'boosty.to'
  ];
  domain text;
begin
  if cleaned = '' or char_length(cleaned) > 300 then
    return null;
  end if;
  parts := regexp_match(
    cleaned,
    '^https://((?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,})(/[^\s<>"''\\]*)?$'
  );
  if parts is null then
    return null;
  end if;
  host := lower(parts[1]);
  tail := coalesce(parts[2], '');

  if host = 'github.com' then
    if tail !~* '^/sponsors/[A-Za-z0-9-]+' then
      return null;
    end if;
    return 'https://' || host || tail;
  end if;

  foreach domain in array allowed loop
    if host = domain or host like '%.' || domain then
      return 'https://' || host || tail;
    end if;
  end loop;
  return null;
end;
$$;

grant execute on function public.normalize_support_url(text) to authenticated;
revoke execute on function public.normalize_support_url(text) from public, anon;

alter table public.profiles
  add column if not exists links jsonb not null default '[]'::jsonb;

alter table public.profiles
  drop constraint if exists profiles_links_check;
alter table public.profiles
  add constraint profiles_links_check check (
    jsonb_typeof(links) = 'array' and jsonb_array_length(links) <= 5
  );

alter table public.circles
  add column if not exists support_url text;

alter table public.circles
  drop constraint if exists circles_support_url_check;
alter table public.circles
  add constraint circles_support_url_check check (
    support_url is null or char_length(support_url) <= 300
  );

-- Saves my links. [links] is a JSON array of {url, label}; an empty array
-- removes them. Every url must be an allowed support link; duplicates are
-- dropped; a label is at most 30 characters (blank: the app shows the site's
-- name). Returns what is stored.
create or replace function public.set_my_links(links jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  item jsonb;
  normalized text;
  label text;
  seen text[] := array[]::text[];
  stored jsonb := '[]'::jsonb;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if links is null or jsonb_typeof(links) <> 'array' then
    raise exception 'Links must be a list' using errcode = '22023';
  end if;
  if jsonb_array_length(links) > 5 then
    raise exception 'You can add up to 5 links' using errcode = '22023';
  end if;

  for item in select * from jsonb_array_elements(links) loop
    if jsonb_typeof(item) <> 'object' or jsonb_typeof(item -> 'url') <> 'string' then
      raise exception 'Each link needs a url' using errcode = '22023';
    end if;
    normalized := public.normalize_support_url(item ->> 'url');
    if normalized is null then
      raise exception 'That link is not a supported support page'
        using errcode = '22023';
    end if;
    if normalized = any (seen) then
      continue;
    end if;
    seen := seen || normalized;
    label := nullif(btrim(coalesce(item ->> 'label', '')), '');
    if label is not null and char_length(label) > 30 then
      raise exception 'A label is at most 30 characters' using errcode = '22023';
    end if;
    stored := stored || jsonb_build_array(
      jsonb_build_object('url', normalized, 'label', label)
    );
  end loop;

  update public.profiles p
  set links = stored
  where p.id = me and p.deleted_at is null;
  if not found then
    raise exception 'Profile not found' using errcode = '42501';
  end if;
  return stored;
end;
$$;

revoke execute on function public.set_my_links(jsonb) from public, anon;
grant execute on function public.set_my_links(jsonb) to authenticated;

-- Sets (or, with a blank url, removes) a circle's support page. Needs the
-- right to manage the circle.
create or replace function public.set_circle_support_url(
  target_circle_id uuid,
  url text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'You cannot change this circle' using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(url, '')), '') is null then
    normalized := null;
  else
    normalized := public.normalize_support_url(url);
    if normalized is null then
      raise exception 'That link is not a supported support page'
        using errcode = '22023';
    end if;
  end if;

  update public.circles c
  set support_url = normalized
  where c.id = target_circle_id;
  return normalized;
end;
$$;

revoke execute on function public.set_circle_support_url(uuid, text) from public, anon;
grant execute on function public.set_circle_support_url(uuid, text) to authenticated;

-- A circle's support page, for its members.
create or replace function public.get_circle_support_url(target_circle_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select c.support_url
  from public.circles c
  where c.id = target_circle_id
    and public.is_current_user_circle_member(c.id);
$$;

revoke execute on function public.get_circle_support_url(uuid) from public, anon;
grant execute on function public.get_circle_support_url(uuid) to authenticated;

-- get_my_profile_extras (202610230610) also returns my links.
create or replace function public.get_my_profile_extras()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'birthday', jsonb_build_object(
      'month', p.birthday_month,
      'day', p.birthday_day,
      'visibility', p.birthday_visibility,
      'reminders', p.birthday_reminders
    ),
    'status_visibility', p.status_visibility,
    'links', p.links
  )
  from public.profiles p
  where p.id = auth.uid();
$$;

revoke execute on function public.get_my_profile_extras() from public, anon;
grant execute on function public.get_my_profile_extras() to authenticated;

-- A deleted account keeps no links.
create or replace function public.clear_deleted_profile_links()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.deleted_at is not null then
    new.links := '[]'::jsonb;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_clear_deleted_links on public.profiles;
create trigger profiles_clear_deleted_links
  before update of deleted_at on public.profiles
  for each row execute function public.clear_deleted_profile_links();
