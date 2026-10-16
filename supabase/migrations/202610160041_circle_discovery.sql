-- Circle discovery: listing, previewing and joining public circles
-- (202610160040).
--
-- * presence_heartbeats: when each user last had the app open and visible
--   to others. Online and visible clients call touch_presence(true) about
--   every two minutes while they're tracked on the realtime presence
--   channel, and touch_presence(false) when they stop (Invisible, online
--   status hidden, signing out). Invisible or hidden users are never
--   counted, whatever the client says. Only counts leave the database:
--   discovery shows how many members of a public circle were seen in the
--   last five minutes. Clients cannot read the table.
-- * list_discoverable_circles(search_query, category_filter, sort_by,
--   page_size, page_offset): public circles for any signed-in user.
--   search_query matches the full-text document (websearch syntax,
--   'simple' configuration) or, for Chinese and partial words, a
--   case-insensitive substring of name, tags and description (pg_trgm
--   index). sort_by is 'popular' (members, online members and how recent
--   the last message is), 'new' (first listed) or 'relevance' (search
--   rank, then popular; the default with a query). page_size 1 to 50,
--   page_offset 0 to 2000. Rows carry only what the circle shows in
--   discovery, its member and online counts, the last activity time and
--   whether the caller is already a member.
-- * discoverable_circle_preview(circle_id): one public circle with its
--   rules (when onboarding is on), the names and kinds of the channels a
--   new member would see (@everyone's permissions and overwrites, at most
--   50), and whether the caller is a member or banned.
-- * join_public_circle(circle_id): joins a public circle as a member, like
--   accepting an invite. Banned users are refused (42501, also enforced by
--   circle_members_reject_banned); joining twice returns the circle.
--   Rate limited to 10 joins per user and hour (PB429), counted in
--   circle_public_joins. New members still accept the rules first when
--   onboarding is on, and AutoMod applies to what they send. Circles have
--   no member limit, so there is none to check.

create table if not exists public.presence_heartbeats (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  seen_at timestamptz not null default now()
);

create index if not exists presence_heartbeats_seen_idx
  on public.presence_heartbeats (seen_at desc);

alter table public.presence_heartbeats enable row level security;
revoke all on public.presence_heartbeats from anon, authenticated;

create or replace function public.touch_presence(is_online boolean default true)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  settings public.user_privacy_settings%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select s.* into settings
  from public.user_privacy_settings s
  where s.user_id = current_user_id;

  if not coalesce(is_online, false)
    or coalesce(settings.presence_status, 'online') = 'invisible'
    or not coalesce(settings.show_online_status, true)
  then
    delete from public.presence_heartbeats h where h.user_id = current_user_id;
    return;
  end if;

  insert into public.presence_heartbeats as h (user_id, seen_at)
  values (current_user_id, now())
  on conflict (user_id) do update
    set seen_at = excluded.seen_at
    -- Several tabs or devices: one write every 30 seconds is enough.
    where h.seen_at < now() - interval '30 seconds';
end;
$$;

-- Members of circle_id seen in the last five minutes.
create or replace function public.circle_online_count(target_circle_id uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select count(*)
  from public.circle_members cm
  join public.presence_heartbeats h on h.user_id = cm.user_id
  where cm.circle_id = target_circle_id
    and h.seen_at > now() - interval '5 minutes';
$$;

-- The newest message in any of the circle's channels.
create or replace function public.circle_last_activity_at(target_circle_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  select max(latest.created_at)
  from public.circle_channels cc
  cross join lateral (
    select m.created_at
    from public.messages m
    where m.conversation_id = cc.conversation_id
    order by m.created_at desc
    limit 1
  ) latest
  where cc.circle_id = target_circle_id;
$$;

revoke execute on function public.circle_online_count(uuid) from public, anon, authenticated;
revoke execute on function public.circle_last_activity_at(uuid) from public, anon, authenticated;

create or replace function public.list_discoverable_circles(
  search_query text default null,
  category_filter text default null,
  sort_by text default null,
  page_size integer default 24,
  page_offset integer default 0
)
returns table (
  id uuid,
  name text,
  avatar_url text,
  description text,
  category text,
  language text,
  tags text[],
  member_count bigint,
  online_count bigint,
  listed_at timestamptz,
  last_activity_at timestamptz,
  is_member boolean,
  rank real
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  query_text text := nullif(btrim(left(coalesce(search_query, ''), 100)), '');
  pattern text;
  ts_query tsquery;
  wanted_category text := nullif(btrim(coalesce(category_filter, '')), '');
  sort_key text := coalesce(
    nullif(btrim(coalesce(sort_by, '')), ''),
    case when nullif(btrim(coalesce(search_query, '')), '') is null
      then 'popular' else 'relevance' end
  );
  size integer := least(greatest(coalesce(page_size, 24), 1), 50);
  skip integer := least(greatest(coalesce(page_offset, 0), 0), 2000);
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if sort_key not in ('popular', 'new', 'relevance') then
    raise exception 'Unknown sort' using errcode = '22023';
  end if;

  if query_text is not null then
    pattern := '%' || replace(replace(replace(lower(query_text), '\', '\\'), '%', '\%'), '_', '\_') || '%';
    ts_query := websearch_to_tsquery('simple'::regconfig, query_text);
  end if;

  return query
  with matches as (
    select
      c.id,
      c.name,
      c.avatar_url,
      c.discovery_description,
      c.discovery_category,
      c.discovery_language,
      c.discovery_tags,
      c.discovery_listed_at,
      case
        when query_text is null then 0::real
        else (
          case
            when ts_query is not null and numnode(ts_query) > 0
              then ts_rank(c.discovery_search, ts_query)
            else 0
          end
          + case when lower(c.name) = lower(query_text) then 1 else 0 end
          + case when lower(c.name) like pattern then 0.5 else 0 end
          + case when lower(query_text) = any(c.discovery_tags) then 0.4 else 0 end
          + 0.1
        )::real
      end as match_rank
    from public.circles c
    where c.is_public
      and (wanted_category is null or c.discovery_category = wanted_category)
      and (
        query_text is null
        or (
          ts_query is not null
          and numnode(ts_query) > 0
          and c.discovery_search @@ ts_query
        )
        or public.circle_discovery_text(
          c.name,
          c.discovery_description,
          c.discovery_tags
        ) like pattern
      )
  ),
  stats as (
    select
      m.*,
      (select count(*) from public.circle_members cm where cm.circle_id = m.id)
        as members,
      public.circle_online_count(m.id) as online,
      public.circle_last_activity_at(m.id) as activity,
      exists (
        select 1
        from public.circle_members cm
        where cm.circle_id = m.id
          and cm.user_id = current_user_id
      ) as joined
    from matches m
  ),
  scored as (
    select
      s.*,
      (
        ln(1 + s.members)
        + ln(1 + s.online)
        + case
          when s.activity is null then 0
          else 2 * exp(-greatest(extract(epoch from now() - s.activity), 0) / 259200.0)
        end
      ) as popularity
    from stats s
  )
  select
    s.id,
    s.name,
    s.avatar_url,
    s.discovery_description,
    s.discovery_category,
    s.discovery_language,
    s.discovery_tags,
    s.members,
    s.online,
    s.discovery_listed_at,
    s.activity,
    s.joined,
    s.match_rank
  from scored s
  order by
    case when sort_key = 'relevance' then s.match_rank end desc nulls last,
    case when sort_key = 'new' then s.discovery_listed_at end desc nulls last,
    s.popularity desc,
    s.members desc,
    s.id
  limit size
  offset skip;
end;
$$;

create or replace function public.discoverable_circle_preview(target_circle_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  circle public.circles%rowtype;
  onboarding public.circle_onboarding%rowtype;
  everyone_permissions bigint;
  channels jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select c.* into circle
  from public.circles c
  where c.id = target_circle_id
    and c.is_public;

  if circle.id is null then
    raise exception 'Circle not found' using errcode = 'P0002';
  end if;

  select o.* into onboarding
  from public.circle_onboarding o
  where o.circle_id = circle.id;

  select coalesce(bit_or(r.permissions), 0) into everyone_permissions
  from public.circle_roles r
  where r.circle_id = circle.id
    and r.is_default;

  -- Administrators see every channel, so a default role with it shows all.
  select coalesce(
    jsonb_agg(
      jsonb_build_object('name', visible.name, 'kind', visible.kind)
      order by visible.category_position nulls first, visible.position, visible.created_at
    ),
    '[]'::jsonb
  )
  into channels
  from (
    select
      cc.name,
      cc.kind,
      cc.position,
      cc.created_at,
      category.position as category_position
    from public.circle_channels cc
    left join public.circle_channel_categories category
      on category.id = cc.category_id
    left join lateral (
      select
        coalesce(bit_or(o.deny), 0) as deny,
        coalesce(bit_or(o.allow), 0) as allow
      from public.circle_channel_overwrites o
      join public.circle_roles r on r.id = o.role_id and r.is_default
      where o.channel_id = cc.id
    ) everyone on true
    where cc.circle_id = circle.id
      and (
        everyone_permissions & 16384 <> 0
        or ((everyone_permissions & ~everyone.deny) | everyone.allow) & 1 <> 0
      )
    order by category.position nulls first, cc.position, cc.created_at
    limit 50
  ) visible;

  return jsonb_build_object(
    'id', circle.id,
    'name', circle.name,
    'avatar_url', circle.avatar_url,
    'description', circle.discovery_description,
    'category', circle.discovery_category,
    'language', circle.discovery_language,
    'tags', to_jsonb(circle.discovery_tags),
    'listed_at', circle.discovery_listed_at,
    'member_count', (
      select count(*) from public.circle_members cm where cm.circle_id = circle.id
    ),
    'online_count', public.circle_online_count(circle.id),
    'last_activity_at', public.circle_last_activity_at(circle.id),
    'is_member', exists (
      select 1
      from public.circle_members cm
      where cm.circle_id = circle.id
        and cm.user_id = current_user_id
    ),
    'is_banned', exists (
      select 1
      from public.circle_bans b
      where b.circle_id = circle.id
        and b.user_id = current_user_id
    ),
    'rules_enabled', coalesce(onboarding.enabled, false),
    'rules', case
      when coalesce(onboarding.enabled, false) then to_jsonb(onboarding.rules)
      else '[]'::jsonb
    end,
    'channels', channels
  );
end;
$$;

create table if not exists public.circle_public_joins (
  user_id uuid not null references public.profiles(id) on delete cascade,
  circle_id uuid not null references public.circles(id) on delete cascade,
  joined_at timestamptz not null default now()
);

create index if not exists circle_public_joins_user_idx
  on public.circle_public_joins (user_id, joined_at desc);

alter table public.circle_public_joins enable row level security;
revoke all on public.circle_public_joins from anon, authenticated;

create or replace function public.join_public_circle(target_circle_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  circle public.circles%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select c.* into circle
  from public.circles c
  where c.id = target_circle_id
  for share;

  if circle.id is null or not circle.is_public then
    raise exception 'Circle not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = circle.id
      and cm.user_id = current_user_id
  ) then
    return circle.id;
  end if;

  if exists (
    select 1
    from public.circle_bans b
    where b.circle_id = circle.id
      and b.user_id = current_user_id
  ) then
    raise exception 'Banned from this circle' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('public-join:' || current_user_id::text, 0));

  delete from public.circle_public_joins j
  where j.user_id = current_user_id
    and j.joined_at < now() - interval '1 day';

  if (
    select count(*)
    from public.circle_public_joins j
    where j.user_id = current_user_id
      and j.joined_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception 'Too many circles joined. Try again later.'
      using errcode = 'PB429';
  end if;

  insert into public.circle_members (circle_id, user_id, role)
  values (circle.id, current_user_id, 'member')
  on conflict do nothing;

  insert into public.conversation_members (conversation_id, user_id, role)
  select cc.conversation_id, current_user_id, 'member'
  from public.circle_channels cc
  where cc.circle_id = circle.id
  on conflict do nothing;

  insert into public.circle_public_joins (user_id, circle_id)
  values (current_user_id, circle.id);

  return circle.id;
end;
$$;

revoke execute on function public.touch_presence(boolean) from public, anon;
revoke execute on function public.list_discoverable_circles(text, text, text, integer, integer)
  from public, anon;
revoke execute on function public.discoverable_circle_preview(uuid) from public, anon;
revoke execute on function public.join_public_circle(uuid) from public, anon;
grant execute on function public.touch_presence(boolean) to authenticated;
grant execute on function public.list_discoverable_circles(text, text, text, integer, integer)
  to authenticated;
grant execute on function public.discoverable_circle_preview(uuid) to authenticated;
grant execute on function public.join_public_circle(uuid) to authenticated;
