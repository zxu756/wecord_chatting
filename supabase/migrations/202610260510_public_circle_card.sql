-- Public circle web pages (C8), part 2 of 2: what the web page may read
-- without an account. The Cloudflare Worker (worker/src) draws
-- https://<site>/c/<slug> and https://<site>/invite/<code> from these two
-- functions, called with the anon key, and nothing else.
--
-- * get_public_circle_card(slug)
-- * get_public_invite_card(code)
--
-- Both answer one small JSON object. {"available": false} is the whole answer
-- when the page must say "unavailable", and it is the same answer for every
-- reason: no such slug or code, a private circle, a circle taken down
-- (delisted or suspended, K1), an invite that is revoked, expired, used up or
-- paused (raid protection, C6), a malformed value. Nothing tells those
-- apart, so the pages cannot be used to find out which circles or codes
-- exist. Only public circles are shown, even through a valid invite: an
-- invite to a private circle does not put its name on a link preview that a
-- chat app fetches without asking anyone.
--
-- When it is available the card has only what Explore already shows a
-- stranger and no more: name, description, category, language, tags, the
-- circle's picture when it is an https address, how people join ('open',
-- 'apply' or 'invite_only') and the size of the circle as a level, never the
-- count: fewer than 5 members is null (like the insights page, C3, "<5", so
-- no one can be picked out), otherwise the largest of 5, 10, 25, 50, 100,
-- 250, 500, 1000, 2500, 5000 or 10000 that the count reaches. No ids, no
-- member names, no channel names, no invite details beyond "valid".

create or replace function public.public_circle_member_level(member_total bigint)
returns integer
language sql
immutable
set search_path = public
as $$
  select case
    when member_total is null or member_total < 5 then null
    when member_total >= 10000 then 10000
    when member_total >= 5000 then 5000
    when member_total >= 2500 then 2500
    when member_total >= 1000 then 1000
    when member_total >= 500 then 500
    when member_total >= 250 then 250
    when member_total >= 100 then 100
    when member_total >= 50 then 50
    when member_total >= 25 then 25
    when member_total >= 10 then 10
    else 5
  end;
$$;

-- The card of a circle that is already known to be shown.
create or replace function public.public_circle_card_json(card_circle public.circles)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'available', true,
    'slug', card_circle.slug,
    'name', card_circle.name,
    'description', card_circle.discovery_description,
    'icon_url', case
      when card_circle.avatar_url ~ '^https://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]{1,255}$'
        then card_circle.avatar_url
      else null
    end,
    'category', card_circle.discovery_category,
    'language', card_circle.discovery_language,
    'tags', to_jsonb(card_circle.discovery_tags),
    'member_level', public.public_circle_member_level((
      select count(*)
      from public.circle_members cm
      where cm.circle_id = card_circle.id
    )),
    'join_mode', card_circle.join_mode
  );
$$;

create or replace function public.get_public_circle_card(card_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  wanted text := lower(btrim(coalesce(left(card_slug, 64), '')));
  found public.circles%rowtype;
begin
  if wanted !~ '^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$' then
    return jsonb_build_object('available', false);
  end if;

  select c.* into found
  from public.circles c
  where c.slug = wanted
    and c.is_public
    and c.disabled_at is null;

  if found.id is null then
    return jsonb_build_object('available', false);
  end if;

  return public.public_circle_card_json(found);
end;
$$;

create or replace function public.get_public_invite_card(invite_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  wanted text := lower(btrim(coalesce(left(invite_code, 64), '')));
  invite public.circle_invites%rowtype;
  found public.circles%rowtype;
begin
  if wanted !~ '^[a-z2-9]{10}$' then
    return jsonb_build_object('available', false);
  end if;

  select i.* into invite
  from public.circle_invites i
  where i.code = wanted;

  if invite.code is null
    or public.circle_invite_invalid_reason(invite) is not null
  then
    return jsonb_build_object('available', false);
  end if;

  select c.* into found
  from public.circles c
  where c.id = invite.circle_id
    and c.is_public
    and c.disabled_at is null;

  if found.id is null then
    return jsonb_build_object('available', false);
  end if;

  return public.public_circle_card_json(found);
end;
$$;

revoke execute on function public.public_circle_member_level(bigint) from public, anon, authenticated;
revoke execute on function public.public_circle_card_json(public.circles) from public, anon, authenticated;
revoke execute on function public.get_public_circle_card(text) from public;
revoke execute on function public.get_public_invite_card(text) from public;
grant execute on function public.get_public_circle_card(text) to anon, authenticated;
grant execute on function public.get_public_invite_card(text) to anon, authenticated;
