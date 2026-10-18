-- Admin console (K1), part 2 of 3: what a circle take-down does. The
-- columns are in 202610210110; an admin sets them with admin_disable_circle
-- (202610210130).
--
-- Two modes, chosen per case:
--
-- * Delist (disabled_mode 'delist'): the circle is hidden from Discover
--   (list_discoverable_circles, discoverable_circle_preview) and takes no new
--   members. Existing members keep using it.
-- * Suspend (disabled_mode 'suspend'): the same, and nobody can enter or
--   read: members' reads of its messages, posts and files return nothing,
--   nobody can send, post or comment, and get_circle_detail returns null.
--   my_circle_takedowns() tells a member that their circle was suspended, so
--   the app shows "This circle was suspended". Members can still leave.
--
-- No new members, on every path, is one trigger on circle_members
-- (circle_members_reject_disabled): invite links, public join, member
-- invites and contact-card invites all end in an insert there, as do bots.
-- A trigger on circle_invites stops new invites (contact cards make theirs
-- with create_circle_invite), and admin_disable_circle revokes the ones that
-- exist, so an old card or link says it is invalid.
--
-- Reads in a suspended circle go through two small functions every policy
-- and RPC about chat already asks, so each gets one extra condition and
-- nothing else changes (the newest definition of each, from the file named
-- above it):
--   is_current_user_conversation_member    messages' insert policies, files in
--                                          Storage, realtime, calls
--   current_user_readable_conversation_ids messages, reactions, mentions,
--                                          pins and threads (select policies,
--                                          search)
-- plus restrictive select policies on posts, comments and likes, a guard in
-- get_circle_detail, and insert triggers on messages, posts and comments.
--
-- The same insert triggers refuse a suspended person's messages, posts and
-- comments, for the access token that is still valid after the ban.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public.circle_is_suspended(target_circle_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.circles c
    where c.id = target_circle_id
      and c.disabled_mode = 'suspend'
  );
$$;

create or replace function public.conversation_in_suspended_circle(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.circle_channels cc
    join public.circles c on c.id = cc.circle_id
    where c.disabled_mode = 'suspend'
      and cc.conversation_id = coalesce(
        (
          select ct.parent_conversation_id
          from public.conversation_threads ct
          where ct.conversation_id = target_conversation_id
        ),
        target_conversation_id
      )
  );
$$;

create or replace function public.circle_post_in_suspended_circle(
  target_post_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.circle_posts p
    join public.circles c on c.id = p.circle_id
    where p.id = target_post_id
      and c.disabled_mode = 'suspend'
  );
$$;

revoke execute on function public.circle_is_suspended(uuid)
  from public, anon, authenticated;
revoke execute on function public.conversation_in_suspended_circle(uuid)
  from public, anon, authenticated;
revoke execute on function public.circle_post_in_suspended_circle(uuid)
  from public, anon, authenticated;
-- The policies call them as the caller.
grant execute on function public.circle_is_suspended(uuid) to authenticated;
grant execute on function public.circle_post_in_suspended_circle(uuid)
  to authenticated;

-- The circles of the caller that an admin took down: {circle_id, mode}.
create or replace function public.my_circle_takedowns()
returns table (circle_id uuid, mode text)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.disabled_mode
  from public.circles c
  join public.circle_members m
    on m.circle_id = c.id
    and m.user_id = auth.uid()
  where c.disabled_at is not null;
$$;

revoke execute on function public.my_circle_takedowns() from public, anon;
grant execute on function public.my_circle_takedowns() to authenticated;

-- ---------------------------------------------------------------------------
-- No new members, no new invites
-- ---------------------------------------------------------------------------

create or replace function public.reject_disabled_circle_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.circles c
    where c.id = new.circle_id
      and c.disabled_at is not null
  ) then
    raise exception 'This circle is not accepting new members'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function public.reject_disabled_circle_member()
  from public, anon, authenticated;

drop trigger if exists circle_members_reject_disabled on public.circle_members;
create trigger circle_members_reject_disabled
  before insert on public.circle_members
  for each row execute function public.reject_disabled_circle_member();

create or replace function public.reject_disabled_circle_invite()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.circles c
    where c.id = new.circle_id
      and c.disabled_at is not null
  ) then
    raise exception 'This circle is not accepting new members'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function public.reject_disabled_circle_invite()
  from public, anon, authenticated;

drop trigger if exists circle_invites_reject_disabled on public.circle_invites;
create trigger circle_invites_reject_disabled
  before insert on public.circle_invites
  for each row execute function public.reject_disabled_circle_invite();

-- ---------------------------------------------------------------------------
-- Nothing is sent, posted or commented in a suspended circle, or by a
-- suspended person
-- ---------------------------------------------------------------------------

create or replace function public.reject_takedown_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- System notices ("X left") are written by RPCs, whoever caused them.
  if new.type = 'system' then
    return new;
  end if;
  if new.sender_id is not null and public.is_user_suspended(new.sender_id) then
    raise exception 'Account suspended' using errcode = '42501';
  end if;
  if exists (select 1 from public.circles c where c.disabled_mode = 'suspend')
    and public.conversation_in_suspended_circle(new.conversation_id)
  then
    raise exception 'This circle was suspended' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function public.reject_takedown_message()
  from public, anon, authenticated;

drop trigger if exists messages_reject_takedown on public.messages;
create trigger messages_reject_takedown
  before insert on public.messages
  for each row execute function public.reject_takedown_message();

create or replace function public.reject_takedown_post()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_user_suspended(new.author_id) then
    raise exception 'Account suspended' using errcode = '42501';
  end if;
  if public.circle_is_suspended(new.circle_id) then
    raise exception 'This circle was suspended' using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function public.reject_takedown_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_user_suspended(new.author_id) then
    raise exception 'Account suspended' using errcode = '42501';
  end if;
  if public.circle_post_in_suspended_circle(new.post_id) then
    raise exception 'This circle was suspended' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function public.reject_takedown_post()
  from public, anon, authenticated;
revoke execute on function public.reject_takedown_comment()
  from public, anon, authenticated;

drop trigger if exists circle_posts_reject_takedown on public.circle_posts;
create trigger circle_posts_reject_takedown
  before insert on public.circle_posts
  for each row execute function public.reject_takedown_post();

drop trigger if exists circle_post_comments_reject_takedown
  on public.circle_post_comments;
create trigger circle_post_comments_reject_takedown
  before insert on public.circle_post_comments
  for each row execute function public.reject_takedown_comment();

-- ---------------------------------------------------------------------------
-- Suspend: nothing is readable
-- ---------------------------------------------------------------------------

-- Restrictive policies are ANDed with the policies that exist, so the
-- member policies stay as they are.
drop policy if exists circle_posts_takedown_select on public.circle_posts;
create policy circle_posts_takedown_select
  on public.circle_posts as restrictive for select
  to authenticated
  using (not public.circle_is_suspended(circle_id));

drop policy if exists circle_post_comments_takedown_select
  on public.circle_post_comments;
create policy circle_post_comments_takedown_select
  on public.circle_post_comments as restrictive for select
  to authenticated
  using (not public.circle_post_in_suspended_circle(post_id));

drop policy if exists circle_post_likes_takedown_select
  on public.circle_post_likes;
create policy circle_post_likes_takedown_select
  on public.circle_post_likes as restrictive for select
  to authenticated
  using (not public.circle_post_in_suspended_circle(post_id));

-- The pictures of posts (bucket chat-media, folder = circle id; the other
-- chat buckets ask is_current_user_conversation_member, patched below).
drop policy if exists chat_media_takedown_select on storage.objects;
create policy chat_media_takedown_select
  on storage.objects as restrictive for select
  to authenticated
  using (
    case
      when bucket_id = 'chat-media'
        then not public.circle_is_suspended(((storage.foldername(name))[1])::uuid)
      else true
    end
  );

-- Same as 202610130014_channel_permission_overwrites, plus the take-down.
create or replace function public.is_current_user_conversation_member(
  check_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = check_conversation_id
        and cm.user_id = auth.uid()
    )
    and coalesce(
      (
        select case
          -- Taken down by an admin (Suspend): nobody is a member.
          when suspended.disabled_mode = 'suspend' then false
          when not exists (
              select 1
              from public.circle_channel_overwrites o
              where o.channel_id = cc.id
            )
            and exists (
              select 1
              from public.circle_roles r
              where r.circle_id = cc.circle_id
                and r.is_default
                and r.permissions & 1 <> 0
            )
            then true
          -- view_channel
          else public.circle_channel_permissions(cc.id, auth.uid()) & 1 <> 0
        end
        from public.circle_channels cc
        join public.circles suspended on suspended.id = cc.circle_id
        where cc.conversation_id = coalesce(
          (
            select ct.parent_conversation_id
            from public.conversation_threads ct
            where ct.conversation_id = check_conversation_id
          ),
          check_conversation_id
        )
      ),
      true
    );
$$;

-- Same as 202610130016_channel_permission_fixes, plus the take-down.
create or replace function public.current_user_readable_conversation_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select cm.conversation_id
  from public.conversation_members cm
  left join public.conversation_threads ct
    on ct.conversation_id = cm.conversation_id
  left join public.circle_channels cc
    on cc.conversation_id = coalesce(ct.parent_conversation_id, cm.conversation_id)
  where cm.user_id = auth.uid()
    and case
      when cc.id is null then true
      -- Taken down by an admin (Suspend): nothing is readable.
      when exists (
          select 1
          from public.circles suspended
          where suspended.id = cc.circle_id
            and suspended.disabled_mode = 'suspend'
        )
        then false
      when not exists (
          select 1
          from public.circle_channel_overwrites o
          where o.channel_id = cc.id
        )
        and exists (
          select 1
          from public.circle_roles r
          where r.circle_id = cc.circle_id
            and r.is_default
            and r.permissions & 1 <> 0
        )
        then true
      -- view_channel
      else public.circle_channel_permissions(cc.id, auth.uid()) & 1 <> 0
    end;
$$;

-- Same as 202610140004_bans_and_timeouts, plus the take-down.
create or replace function public.get_circle_detail(target_circle_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'circle',
    jsonb_build_object(
      'id', c.id,
      'name', c.name,
      'avatar_url', c.avatar_url,
      'owner_id', c.owner_id,
      'created_at', c.created_at,
      'updated_at', c.updated_at,
      'current_user_role', current_member.role,
      'current_user_permissions', caller.permissions
    ),
    'roles',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', r.id,
          'name', r.name,
          'color', r.color,
          'position', r.position,
          'permissions', r.permissions,
          'hoist', r.hoist,
          'is_default', r.is_default,
          'member_count', case
            when r.is_default then (
              select count(*)
              from public.circle_members cm
              where cm.circle_id = c.id
            )
            else (
              select count(*)
              from public.circle_member_roles mr
              where mr.role_id = r.id
            )
          end
        )
        order by r.position desc
      )
      from public.circle_roles r
      where r.circle_id = c.id
    ), '[]'::jsonb),
    'members',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'role', cm.role,
          'nickname', cm.nickname,
          'is_current_user', cm.user_id = auth.uid(),
          'timed_out_until', case
            when cm.timed_out_until > now() then cm.timed_out_until
          end,
          'created_at', cm.created_at,
          'role_ids', coalesce((
            select jsonb_agg(r.id order by r.position desc)
            from public.circle_member_roles mr
            join public.circle_roles r on r.id = mr.role_id
            where mr.circle_id = cm.circle_id
              and mr.user_id = cm.user_id
          ), '[]'::jsonb),
          'profile',
          jsonb_build_object(
            'id', p.id,
            'username', p.username,
            'display_name', p.display_name,
            'avatar_url', p.avatar_url,
            'bio', p.bio,
            'created_at', p.created_at,
            'updated_at', p.updated_at,
            'custom_status', public.custom_status(p)
          )
        )
        order by
          case cm.role when 'owner' then 0 when 'admin' then 1 else 2 end,
          coalesce(cm.nickname, p.display_name)
      )
      from public.circle_members cm
      join public.profiles p on p.id = cm.user_id
      where cm.circle_id = c.id
    ), '[]'::jsonb),
    'channels',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', cc.id,
          'circle_id', cc.circle_id,
          'conversation_id', cc.conversation_id,
          'name', cc.name,
          'position', cc.position,
          'category_id', cc.category_id,
          'created_by', cc.created_by,
          'current_user_permissions', channel_access.permissions,
          'is_private', coalesce(
            everyone_overwrite.deny
              & public.circle_permission_bit('view_channel') <> 0,
            false
          ),
          'is_read_only', coalesce(
            everyone_overwrite.deny
              & public.circle_permission_bit('send_messages') <> 0,
            false
          ),
          'slowmode_seconds', cc.slowmode_seconds,
          'topic', cc.topic,
          'kind', cc.kind,
          'tags', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', ft.id,
                'channel_id', ft.channel_id,
                'name', ft.name,
                'emoji', ft.emoji,
                'position', ft.position
              )
              order by ft.position, ft.created_at
            )
            from public.forum_tags ft
            where ft.channel_id = cc.id
          ), '[]'::jsonb)
        )
        order by cc.position, cc.created_at
      )
      from public.circle_channels cc
      cross join lateral (
        select public.circle_channel_permissions(cc.id, auth.uid()) as permissions
      ) channel_access
      left join lateral (
        select o.deny
        from public.circle_channel_overwrites o
        join public.circle_roles r on r.id = o.role_id
        where o.channel_id = cc.id
          and r.is_default
      ) everyone_overwrite on true
      where cc.circle_id = c.id
        and channel_access.permissions
          & public.circle_permission_bit('view_channel') <> 0
    ), '[]'::jsonb),
    'categories',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', ccc.id,
          'circle_id', ccc.circle_id,
          'name', ccc.name,
          'position', ccc.position,
          'created_at', ccc.created_at
        )
        order by ccc.position, ccc.created_at
      )
      from public.circle_channel_categories ccc
      where ccc.circle_id = c.id
    ), '[]'::jsonb),
    'posts',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', cp.id,
          'circle_id', cp.circle_id,
          'author_id', cp.author_id,
          'author',
          jsonb_build_object(
            'id', author.id,
            'username', author.username,
            'display_name', author.display_name,
            'avatar_url', author.avatar_url,
            'bio', author.bio,
            'created_at', author.created_at,
            'updated_at', author.updated_at
          ),
          'body', cp.body,
          'attachment', cp.attachment,
          'created_at', cp.created_at,
          'updated_at', cp.updated_at,
          'is_own_post', cp.author_id = auth.uid(),
          'can_manage_post',
          cp.author_id = auth.uid()
            or caller.permissions
              & public.circle_permission_bit('manage_messages') <> 0,
          'like_count', (
            select count(*)
            from public.circle_post_likes cpl
            where cpl.post_id = cp.id
          ),
          'comment_count', (
            select count(*)
            from public.circle_post_comments cpc
            where cpc.post_id = cp.id
          ),
          'liked_by_current_user', exists (
            select 1
            from public.circle_post_likes cpl
            where cpl.post_id = cp.id
              and cpl.user_id = auth.uid()
          ),
          'comments',
          coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', cpc.id,
                'post_id', cpc.post_id,
                'author_id', cpc.author_id,
                'body', cpc.body,
                'created_at', cpc.created_at,
                'updated_at', cpc.updated_at,
                'is_own_comment', cpc.author_id = auth.uid(),
                'author',
                jsonb_build_object(
                  'id', comment_author.id,
                  'username', comment_author.username,
                  'display_name', comment_author.display_name,
                  'avatar_url', comment_author.avatar_url,
                  'bio', comment_author.bio,
                  'created_at', comment_author.created_at,
                  'updated_at', comment_author.updated_at
                )
              )
              order by cpc.created_at
            )
            from public.circle_post_comments cpc
            join public.profiles comment_author on comment_author.id = cpc.author_id
            where cpc.post_id = cp.id
              and cpc.deleted_at is null
          ), '[]'::jsonb)
        )
        order by cp.created_at desc
      )
      from public.circle_posts cp
      join public.profiles author on author.id = cp.author_id
      where cp.circle_id = c.id
        and cp.deleted_at is null
    ), '[]'::jsonb)
  )
  from public.circles c
  join public.circle_members current_member
    on current_member.circle_id = c.id
    and current_member.user_id = auth.uid()
  cross join lateral (
    select public.circle_member_permissions(c.id, auth.uid()) as permissions
  ) caller
  where c.id = target_circle_id
    -- Taken down by an admin (Suspend): nothing to show (null, as for a
    -- circle the caller is not in); my_circle_takedowns says why.
    and c.disabled_mode is distinct from 'suspend';
$$;

-- ---------------------------------------------------------------------------
-- Delist: hidden from Discover, closed to new members
-- ---------------------------------------------------------------------------

-- Same as 202610160041_circle_discovery, plus the take-down.
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
      and c.disabled_at is null
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
    and c.is_public
    and c.disabled_at is null;

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

-- A friendlier refusal than the trigger's, for a circle that is down.
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

  if circle.disabled_at is not null then
    raise exception 'This circle is not accepting new members'
      using errcode = '42501';
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
