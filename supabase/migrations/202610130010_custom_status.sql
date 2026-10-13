-- Custom statuses: an optional emoji and short text under a user's name,
-- with an optional expiry. Both blank means no status. Clients only ever see
-- statuses through public.custom_status(profiles), which returns null once a
-- status has expired, so a stale status never reaches the UI.
alter table public.profiles
  add column if not exists status_emoji text,
  add column if not exists status_text text,
  add column if not exists status_expires_at timestamptz;

alter table public.profiles
  drop constraint if exists profiles_status_emoji_length;
alter table public.profiles
  add constraint profiles_status_emoji_length check (
    status_emoji is null
    or (
      status_emoji = btrim(status_emoji)
      and char_length(status_emoji) between 1 and 32
    )
  );

alter table public.profiles
  drop constraint if exists profiles_status_text_length;
alter table public.profiles
  add constraint profiles_status_text_length check (
    status_text is null
    or (
      status_text = btrim(status_text)
      and char_length(status_text) between 1 and 64
    )
  );

-- PostgREST computed field: `profiles?select=*,custom_status` returns
-- {emoji, text, expires_at}, or null without a status or once it expired.
create or replace function public.custom_status(profile_row public.profiles)
returns jsonb
language sql
stable
set search_path = public
as $$
  select case
    when profile_row.status_emoji is null and profile_row.status_text is null
      then null
    when profile_row.status_expires_at is not null
      and profile_row.status_expires_at <= now()
      then null
    else jsonb_build_object(
      'emoji', profile_row.status_emoji,
      'text', profile_row.status_text,
      'expires_at', profile_row.status_expires_at
    )
  end;
$$;

-- Sets the current user's status. Blank emoji and text clear it (and its
-- expiry); a null expires_at keeps it until changed. Returns the stored
-- status, as custom_status() reports it.
create or replace function public.set_custom_status(
  emoji text,
  text text,
  expires_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_emoji text := nullif(btrim(coalesce(set_custom_status.emoji, '')), '');
  normalized_text text := nullif(btrim(coalesce(set_custom_status.text, '')), '');
  normalized_expires_at timestamptz := set_custom_status.expires_at;
  updated_profile public.profiles%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if normalized_emoji is not null and char_length(normalized_emoji) > 32 then
    raise exception 'Status emoji must be at most 32 characters'
      using errcode = '22023';
  end if;

  if normalized_text is not null and char_length(normalized_text) > 64 then
    raise exception 'Status text must be at most 64 characters'
      using errcode = '22023';
  end if;

  if normalized_emoji is null and normalized_text is null then
    normalized_expires_at := null;
  elsif normalized_expires_at is not null and normalized_expires_at <= now() then
    raise exception 'Status expiry must be in the future'
      using errcode = '22023';
  end if;

  update public.profiles p
  set
    status_emoji = normalized_emoji,
    status_text = normalized_text,
    status_expires_at = normalized_expires_at
  where p.id = current_user_id
  returning p.* into updated_profile;

  if updated_profile.id is null then
    raise exception 'Profile not found' using errcode = '42501';
  end if;

  return public.custom_status(updated_profile);
end;
$$;

-- Same as 202610130007_channel_categories, plus each member's custom status.
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
      'current_user_role', current_member.role
    ),
    'members',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'role', cm.role,
          'nickname', cm.nickname,
          'is_current_user', cm.user_id = auth.uid(),
          'created_at', cm.created_at,
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
          'created_by', cc.created_by
        )
        order by cc.position, cc.created_at
      )
      from public.circle_channels cc
      where cc.circle_id = c.id
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
          cp.author_id = auth.uid() or current_member.role in ('owner', 'admin'),
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
  where c.id = target_circle_id;
$$;

-- Same as 202605190001_identity_safety_v4, plus the custom status (hidden,
-- like the bio, from users the profile owner blocked).
drop function if exists public.get_profile_summary(uuid);

create or replace function public.get_profile_summary(target_user_id uuid)
returns table (
  id uuid,
  username text,
  display_name text,
  alias text,
  avatar_url text,
  bio text,
  relationship_status text,
  incoming_request_id uuid,
  outgoing_request_id uuid,
  is_blocked_by_me boolean,
  has_blocked_me boolean,
  custom_status jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  with friendship as (
    select 1
    from public.friendships f
    where f.user_low_id = least(auth.uid(), target_user_id)
      and f.user_high_id = greatest(auth.uid(), target_user_id)
  ),
  incoming_request as (
    select fr.id
    from public.friend_requests fr
    where fr.requester_id = target_user_id
      and fr.receiver_id = auth.uid()
      and fr.status = 'pending'
    order by fr.created_at desc
    limit 1
  ),
  outgoing_request as (
    select fr.id
    from public.friend_requests fr
    where fr.requester_id = auth.uid()
      and fr.receiver_id = target_user_id
      and fr.status = 'pending'
    order by fr.created_at desc
    limit 1
  ),
  block_state as (
    select
      exists (
        select 1
        from public.blocks b
        where b.blocker_id = auth.uid()
          and b.blocked_id = target_user_id
      ) as is_blocked_by_me,
      exists (
        select 1
        from public.blocks b
        where b.blocker_id = target_user_id
          and b.blocked_id = auth.uid()
      ) as has_blocked_me
  )
  select
    p.id,
    p.username,
    p.display_name,
    ca.alias,
    p.avatar_url,
    case when bs.has_blocked_me then '' else p.bio end as bio,
    case
      when p.id = auth.uid() then 'self'
      when bs.is_blocked_by_me then 'blocked'
      when bs.has_blocked_me then 'blocked_by_them'
      when exists (select 1 from friendship) then 'friend'
      when exists (select 1 from incoming_request) then 'incoming_request'
      when exists (select 1 from outgoing_request) then 'outgoing_request'
      else 'none'
    end as relationship_status,
    (select id from incoming_request) as incoming_request_id,
    (select id from outgoing_request) as outgoing_request_id,
    bs.is_blocked_by_me,
    bs.has_blocked_me,
    case
      when bs.has_blocked_me then null
      else public.custom_status(p)
    end as custom_status
  from public.profiles p
  cross join block_state bs
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid()
    and ca.friend_id = p.id
  where p.id = target_user_id
    and auth.uid() is not null;
$$;

-- Same as 202610130005_circle_notification_settings, plus the other member
-- of a direct conversation and their custom status (null when they blocked
-- the current user), for the direct chat header.
drop function if exists public.list_conversation_summaries();

create or replace function public.list_conversation_summaries()
returns table (
  id uuid,
  type text,
  title text,
  avatar_url text,
  announcement text,
  announcement_updated_at timestamptz,
  announcement_updated_by uuid,
  last_message_body text,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_type text,
  unread_count bigint,
  pinned_at timestamptz,
  muted_until timestamptz,
  is_muted boolean,
  is_marked_unread boolean,
  member_count bigint,
  mentioned_user_ids uuid[],
  circle_id uuid,
  circle_notification_level text,
  circle_muted_until timestamptz,
  direct_user_id uuid,
  direct_custom_status jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  with current_memberships as (
    select
      cm.conversation_id,
      cm.last_read_message_id,
      cm.pinned_at,
      cm.muted_until,
      cm.hidden_at,
      cm.manual_unread_at
    from public.conversation_members cm
    where cm.user_id = auth.uid()
  ),
  read_markers as (
    select cm.conversation_id, rm.created_at as last_read_at
    from current_memberships cm
    left join public.messages rm on rm.id = cm.last_read_message_id
  ),
  direct_profiles as (
    select
      cm.conversation_id,
      p.id as user_id,
      coalesce(ca.alias, p.display_name) as display_name,
      p.avatar_url,
      case
        when exists (
          select 1
          from public.blocks b
          where b.blocker_id = p.id
            and b.blocked_id = auth.uid()
        ) then null
        else public.custom_status(p)
      end as custom_status
    from public.conversation_members cm
    join public.profiles p on p.id = cm.user_id
    left join public.contact_aliases ca
      on ca.owner_id = auth.uid()
      and ca.friend_id = p.id
    where cm.user_id <> auth.uid()
  ),
  member_counts as (
    select cm.conversation_id, count(*) as member_count
    from public.conversation_members cm
    group by cm.conversation_id
  ),
  last_message_mentions as (
    select mm.message_id, array_agg(distinct mm.user_id) as mentioned_user_ids
    from public.message_mentions mm
    group by mm.message_id
  )
  select
    c.id,
    c.type,
    coalesce(c.title, dp.display_name) as title,
    coalesce(c.avatar_url, dp.avatar_url) as avatar_url,
    c.announcement,
    c.announcement_updated_at,
    c.announcement_updated_by,
    case
      when last_message.recalled_at is not null then 'Message deleted'
      when last_message.type = 'image' then '[Image]'
      else last_message.body
    end as last_message_body,
    last_message.sender_id as last_message_sender_id,
    c.last_message_at,
    last_message.type as last_message_type,
    greatest(
      count(unread_messages.id),
      case when cm.manual_unread_at is null then 0 else 1 end::bigint
    ) as unread_count,
    cm.pinned_at,
    cm.muted_until,
    cm.muted_until is not null and cm.muted_until > now() as is_muted,
    cm.manual_unread_at is not null as is_marked_unread,
    coalesce(mc.member_count, 0) as member_count,
    coalesce(lmm.mentioned_user_ids, array[]::uuid[]) as mentioned_user_ids,
    cc.circle_id,
    case
      when cc.circle_id is null then null
      else coalesce(cns.level, 'all')
    end as circle_notification_level,
    cns.muted_until as circle_muted_until,
    dp.user_id as direct_user_id,
    dp.custom_status as direct_custom_status
  from public.conversations c
  join current_memberships cm on cm.conversation_id = c.id
  left join read_markers rm on rm.conversation_id = c.id
  left join direct_profiles dp on dp.conversation_id = c.id and c.type = 'direct'
  left join member_counts mc on mc.conversation_id = c.id
  left join public.messages last_message on last_message.id = c.last_message_id
  left join last_message_mentions lmm on lmm.message_id = last_message.id
  left join public.circle_channels cc on cc.conversation_id = c.id
  left join public.circle_notification_settings cns
    on cns.circle_id = cc.circle_id
    and cns.user_id = auth.uid()
  left join public.messages unread_messages
    on unread_messages.conversation_id = c.id
    and unread_messages.sender_id <> auth.uid()
    and (
      rm.last_read_at is null
      or unread_messages.created_at > rm.last_read_at
    )
  where cm.hidden_at is null
    or c.last_message_at > cm.hidden_at
  group by
    c.id,
    c.type,
    c.title,
    c.avatar_url,
    c.announcement,
    c.announcement_updated_at,
    c.announcement_updated_by,
    dp.user_id,
    dp.display_name,
    dp.avatar_url,
    dp.custom_status,
    last_message.body,
    last_message.sender_id,
    last_message.recalled_at,
    last_message.type,
    c.last_message_at,
    c.updated_at,
    cm.pinned_at,
    cm.muted_until,
    cm.manual_unread_at,
    mc.member_count,
    lmm.mentioned_user_ids,
    cc.circle_id,
    cns.level,
    cns.muted_until
  order by
    cm.pinned_at desc nulls last,
    c.last_message_at desc nulls last,
    c.updated_at desc;
$$;

grant execute on function public.custom_status(public.profiles) to authenticated;
grant execute on function public.set_custom_status(text, text, timestamptz) to authenticated;
grant execute on function public.get_circle_detail(uuid) to authenticated;
grant execute on function public.get_profile_summary(uuid) to authenticated;
grant execute on function public.list_conversation_summaries() to authenticated;
