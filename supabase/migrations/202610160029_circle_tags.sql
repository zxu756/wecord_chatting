-- Circle tags, like Discord's server tags: a circle defines a short tag
-- with a badge, and members may show one circle's tag next to their name.
--
-- * circles.tag: 2 to 4 characters without spaces or punctuation, and
--   circles.tag_badge, one of a small built-in set (leaf, star, flame,
--   heart, bolt, moon, crown, shield, gem, music). Both are set or both
--   are null (tags off).
-- * set_circle_tag(circle_id, tag, badge): manage_circle (202610160020)
--   in the circle; a null or blank
--   tag turns tags off, which also clears everyone's choice of it.
--   Audited as circle_tag_update. get_circle_tag(circle_id): members.
-- * profiles.display_circle_tag_id: the circle whose tag the user shows.
--   A trigger only accepts circles that have a tag and that the user is a
--   member of; leaving (or being kicked or banned from) the circle clears
--   it. set_display_circle_tag(circle_id or null) sets it for the caller;
--   list_tag_circles() lists the caller's circles that have a tag.
-- * list_profile_badges(user_ids): for up to 200 users, the tag each one
--   shows (tag, badge, circle id and name), for any signed-in user, since
--   showing a tag is public by choice.

alter table public.circles
  add column if not exists tag text,
  add column if not exists tag_badge text;

alter table public.circles
  drop constraint if exists circles_tag_format;
alter table public.circles
  add constraint circles_tag_format check (
    tag is null
    or (
      tag = btrim(tag)
      and char_length(tag) between 2 and 4
      and tag !~ '[[:space:][:punct:]]'
    )
  );

alter table public.circles
  drop constraint if exists circles_tag_badge_known;
alter table public.circles
  add constraint circles_tag_badge_known check (
    tag_badge is null
    or tag_badge in (
      'leaf', 'star', 'flame', 'heart', 'bolt',
      'moon', 'crown', 'shield', 'gem', 'music'
    )
  );

alter table public.circles
  drop constraint if exists circles_tag_with_badge;
alter table public.circles
  add constraint circles_tag_with_badge check ((tag is null) = (tag_badge is null));

alter table public.profiles
  add column if not exists display_circle_tag_id uuid
    references public.circles(id) on delete set null;

create index if not exists profiles_display_circle_tag_idx
  on public.profiles (display_circle_tag_id)
  where display_circle_tag_id is not null;

-- Only circles with a tag that the user belongs to.
create or replace function public.check_display_circle_tag()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.display_circle_tag_id is null then
    return new;
  end if;

  if tg_op = 'UPDATE'
    and new.display_circle_tag_id is not distinct from old.display_circle_tag_id
  then
    return new;
  end if;

  if not exists (
    select 1
    from public.circle_members cm
    join public.circles c on c.id = cm.circle_id
    where cm.circle_id = new.display_circle_tag_id
      and cm.user_id = new.id
      and c.tag is not null
  ) then
    raise exception 'Only the tag of a circle you are in can be shown'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke execute on function public.check_display_circle_tag() from public;
revoke execute on function public.check_display_circle_tag() from anon;
revoke execute on function public.check_display_circle_tag() from authenticated;

drop trigger if exists profiles_check_display_circle_tag on public.profiles;
create trigger profiles_check_display_circle_tag
  before insert or update of display_circle_tag_id on public.profiles
  for each row execute function public.check_display_circle_tag();

-- Leaving a circle stops showing its tag.
create or replace function public.clear_display_circle_tag_on_leave()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles p
  set display_circle_tag_id = null
  where p.id = old.user_id
    and p.display_circle_tag_id = old.circle_id;
  return old;
end;
$$;

revoke execute on function public.clear_display_circle_tag_on_leave() from public;
revoke execute on function public.clear_display_circle_tag_on_leave() from anon;
revoke execute on function public.clear_display_circle_tag_on_leave() from authenticated;

drop trigger if exists circle_members_clear_display_tag on public.circle_members;
create trigger circle_members_clear_display_tag
  after delete on public.circle_members
  for each row execute function public.clear_display_circle_tag_on_leave();

create or replace function public.set_circle_tag(
  target_circle_id uuid,
  circle_tag text,
  badge text default 'star'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  circle public.circles%rowtype;
  trimmed_tag text := nullif(btrim(coalesce(circle_tag, '')), '');
  new_badge text := case
    when trimmed_tag is null then null
    else coalesce(nullif(btrim(coalesce(badge, '')), ''), 'star')
  end;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'Only members who manage the circle can change the tag'
      using errcode = '42501';
  end if;

  if trimmed_tag is not null and (
    char_length(trimmed_tag) not between 2 and 4
    or trimmed_tag ~ '[[:space:][:punct:]]'
  ) then
    raise exception 'A tag is 2 to 4 letters or digits' using errcode = '22023';
  end if;

  if new_badge is not null and new_badge not in (
    'leaf', 'star', 'flame', 'heart', 'bolt',
    'moon', 'crown', 'shield', 'gem', 'music'
  ) then
    raise exception 'Unknown badge' using errcode = '22023';
  end if;

  select c.* into circle
  from public.circles c
  where c.id = target_circle_id
  for update;

  if circle.tag is not distinct from trimmed_tag
    and circle.tag_badge is not distinct from new_badge
  then
    return jsonb_build_object('tag', circle.tag, 'badge', circle.tag_badge);
  end if;

  update public.circles c
  set tag = trimmed_tag, tag_badge = new_badge
  where c.id = circle.id;

  if trimmed_tag is null then
    update public.profiles p
    set display_circle_tag_id = null
    where p.display_circle_tag_id = circle.id;
  end if;

  perform public.write_circle_audit(
    circle.id,
    'circle_tag_update',
    'circle',
    circle.id,
    circle.name,
    jsonb_build_object(
      'tag', jsonb_build_object('old', circle.tag, 'new', trimmed_tag),
      'badge', jsonb_build_object('old', circle.tag_badge, 'new', new_badge)
    )
  );

  return jsonb_build_object('tag', trimmed_tag, 'badge', new_badge);
end;
$$;

create or replace function public.get_circle_tag(target_circle_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object('tag', c.tag, 'badge', c.tag_badge)
  from public.circles c
  where c.id = target_circle_id
    and public.is_current_user_circle_member(c.id);
$$;

create or replace function public.list_tag_circles()
returns table (
  circle_id uuid,
  circle_name text,
  avatar_url text,
  tag text,
  badge text,
  is_selected boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    c.name,
    c.avatar_url,
    c.tag,
    c.tag_badge,
    p.display_circle_tag_id is not distinct from c.id
  from public.circle_members cm
  join public.circles c on c.id = cm.circle_id
  join public.profiles p on p.id = cm.user_id
  where cm.user_id = auth.uid()
    and c.tag is not null
  order by c.name, c.id;
$$;

create or replace function public.set_display_circle_tag(target_circle_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.profiles p
  set display_circle_tag_id = target_circle_id
  where p.id = auth.uid();
end;
$$;

create or replace function public.list_profile_badges(user_ids uuid[])
returns table (
  user_id uuid,
  tag text,
  badge text,
  circle_id uuid,
  circle_name text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if coalesce(cardinality(user_ids), 0) > 200 then
    raise exception 'At most 200 users at a time' using errcode = '54000';
  end if;

  return query
  select p.id, c.tag, c.tag_badge, c.id, c.name
  from public.profiles p
  left join public.circles c
    on c.id = p.display_circle_tag_id
    and c.tag is not null
  where p.id = any(user_ids);
end;
$$;

grant execute on function public.set_circle_tag(uuid, text, text) to authenticated;
grant execute on function public.get_circle_tag(uuid) to authenticated;
grant execute on function public.list_tag_circles() to authenticated;
grant execute on function public.set_display_circle_tag(uuid) to authenticated;
grant execute on function public.list_profile_badges(uuid[]) to authenticated;
