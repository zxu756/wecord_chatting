-- Public circle web pages (C8), part 1 of 2: a circle's short name.
--
-- circles.slug is the part after /c/ in https://<site>/c/<slug>, the page the
-- Cloudflare Worker draws for a public circle (worker/src, part 2:
-- 202610260510). A slug is 3 to 32 characters: lower-case letters, digits and
-- single hyphens, starting and ending with a letter or digit. It is unique
-- across WeCord, and a handful of words that are routes of the site or the
-- app are reserved. A circle can have a slug while it is private or taken
-- down; the page only ever shows a public circle that is not taken down
-- (K1), and answers the same "unavailable" for every other case.
--
-- * set_circle_slug(circle, slug): manage_circle in the circle. A null or
--   empty slug clears it. Audited as slug_update. A circle may change its
--   slug 10 times an hour (PB429), so a short name cannot be swapped around
--   to hold several at once. 23505 when the slug is taken, 22023 when it is
--   not a valid or is a reserved name.
-- * get_circle_slug(circle): the slug, for the members who manage the circle.
-- * resolve_circle_slug(slug): for a signed-in person opening /c/<slug> in
--   the app: the circle id and whether they are in it, only for a public
--   circle that is not taken down, or one they belong to. Anything else is
--   null, so it says nothing about private circles.

alter table public.circles
  add column if not exists slug text;

create or replace function public.circle_slug_is_reserved(candidate text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select candidate = any (array[
    'about', 'admin', 'api', 'app', 'assets', 'auth', 'c', 'call', 'circle',
    'circles', 'discover', 'explore', 'g', 'help', 'home', 'icons', 'invite',
    'legal', 'login', 'logout', 'n', 'new', 'null', 'official', 'privacy',
    'search', 'settings', 'signin', 'signup', 'staff', 'support', 'terms',
    'u', 'undefined', 'wecord'
  ]);
$$;

alter table public.circles
  drop constraint if exists circles_slug_format;
alter table public.circles
  add constraint circles_slug_format check (
    slug is null
    or (
      slug ~ '^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$'
      and slug !~ '--'
      and not public.circle_slug_is_reserved(slug)
    )
  );

create unique index if not exists circles_slug_key
  on public.circles (slug)
  where slug is not null;

create or replace function public.set_circle_slug(
  target_circle_id uuid,
  new_slug text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  circle public.circles%rowtype;
  wanted text := nullif(lower(btrim(coalesce(new_slug, ''))), '');
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'Only members who manage the circle can change its short name'
      using errcode = '42501';
  end if;

  if wanted is not null then
    if wanted !~ '^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$' or wanted ~ '--' then
      raise exception 'A short name is 3 to 32 letters, digits and hyphens'
        using errcode = '22023';
    end if;
    if public.circle_slug_is_reserved(wanted) then
      raise exception 'That short name is reserved' using errcode = '22023';
    end if;
  end if;

  select c.* into circle
  from public.circles c
  where c.id = target_circle_id
  for update;

  if circle.id is null then
    raise exception 'Circle not found' using errcode = 'P0002';
  end if;

  if circle.slug is not distinct from wanted then
    return jsonb_build_object('slug', circle.slug);
  end if;

  if (
    select count(*)
    from public.circle_audit_log a
    where a.circle_id = circle.id
      and a.action = 'slug_update'
      and a.created_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception 'Too many short name changes. Try again later.'
      using errcode = 'PB429';
  end if;

  if wanted is not null and exists (
    select 1 from public.circles o where o.slug = wanted and o.id <> circle.id
  ) then
    raise exception 'That short name is taken' using errcode = '23505';
  end if;

  begin
    update public.circles c set slug = wanted where c.id = circle.id;
  exception when unique_violation then
    raise exception 'That short name is taken' using errcode = '23505';
  end;

  perform public.write_circle_audit(
    circle.id,
    'slug_update',
    'circle',
    circle.id,
    circle.name,
    jsonb_build_object(
      'slug', jsonb_build_object('old', circle.slug, 'new', wanted)
    )
  );

  return jsonb_build_object('slug', wanted);
end;
$$;

create or replace function public.get_circle_slug(target_circle_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'Only members who manage the circle can see its short name'
      using errcode = '42501';
  end if;

  return jsonb_build_object(
    'slug', (select c.slug from public.circles c where c.id = target_circle_id)
  );
end;
$$;

create or replace function public.resolve_circle_slug(circle_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  wanted text := lower(btrim(coalesce(circle_slug, '')));
  found public.circles%rowtype;
  member boolean;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if wanted !~ '^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$' then
    return null;
  end if;

  select c.* into found from public.circles c where c.slug = wanted;
  if found.id is null then
    return null;
  end if;

  member := exists (
    select 1 from public.circle_members cm
    where cm.circle_id = found.id and cm.user_id = current_user_id
  );

  -- A circle that is private or taken down says nothing to people outside it.
  if not member and (not found.is_public or found.disabled_at is not null) then
    return null;
  end if;

  return jsonb_build_object('circle_id', found.id, 'is_member', member);
end;
$$;

-- circle_slug_is_reserved stays executable: the circles_slug_format check runs
-- it for whoever updates a circle.
revoke execute on function public.set_circle_slug(uuid, text) from public, anon;
revoke execute on function public.get_circle_slug(uuid) from public, anon;
revoke execute on function public.resolve_circle_slug(text) from public, anon;
grant execute on function public.set_circle_slug(uuid, text) to authenticated;
grant execute on function public.get_circle_slug(uuid) to authenticated;
grant execute on function public.resolve_circle_slug(text) to authenticated;
