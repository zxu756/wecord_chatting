-- Slowmode, like Discord's: a circle channel can make members wait
-- slowmode_seconds (0 = off, at most 6 hours) between their messages.
-- Members with manage_messages in the channel are exempt, threads have no
-- slowmode of their own, and system notices never count.
--
-- The check lives in the send trigger of 202610130014, so every send path
-- (direct inserts, send_text_message, forward_message, ...) is covered. It
-- fails with SQLSTATE P0001, a message saying how many seconds are left
-- and detail 'slowmode_remaining_seconds=<n>' for clients.
alter table public.circle_channels
  add column if not exists slowmode_seconds integer not null default 0;

alter table public.circle_channels
  drop constraint if exists circle_channels_slowmode_range;
alter table public.circle_channels
  add constraint circle_channels_slowmode_range
  check (slowmode_seconds between 0 and 21600);

-- The sender's latest message in a conversation.
create index if not exists messages_conversation_sender_created_idx
  on public.messages (conversation_id, sender_id, created_at desc);

-- Same as 202610130014_channel_permission_overwrites, plus slowmode in
-- circle channels (not their threads).
create or replace function public.check_channel_message_send()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
  last_sent_at timestamptz;
  remaining_seconds integer;
begin
  if new.type = 'system' then
    return new;
  end if;

  if not public.user_has_conversation_channel_permission(
    new.conversation_id,
    new.sender_id,
    'send_messages'
  ) then
    raise exception 'You do not have permission to send messages in this channel'
      using errcode = '42501';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.conversation_id = new.conversation_id;

  if channel.id is null
    or channel.slowmode_seconds <= 0
    or public.circle_channel_has_permission(
      channel.id,
      new.sender_id,
      'manage_messages'
    )
  then
    return new;
  end if;

  -- One send per member and channel at a time, so two quick sends cannot
  -- both pass.
  perform pg_advisory_xact_lock(
    hashtextextended(new.conversation_id::text || ':' || new.sender_id::text, 0)
  );

  select max(m.created_at) into last_sent_at
  from public.messages m
  where m.conversation_id = new.conversation_id
    and m.sender_id = new.sender_id
    and m.type <> 'system';

  if last_sent_at is not null
    and last_sent_at + make_interval(secs => channel.slowmode_seconds) > now()
  then
    remaining_seconds := greatest(
      1,
      ceil(
        extract(
          epoch from
            last_sent_at + make_interval(secs => channel.slowmode_seconds) - now()
        )
      )::integer
    );
    raise exception 'Slowmode is enabled. Try again in % seconds.', remaining_seconds
      using errcode = 'P0001',
        detail = format('slowmode_remaining_seconds=%s', remaining_seconds);
  end if;

  return new;
end;
$$;

revoke execute on function public.check_channel_message_send() from public;
revoke execute on function public.check_channel_message_send() from anon;
revoke execute on function public.check_channel_message_send() from authenticated;

-- Sets a channel's slowmode; needs manage_channels and access to the
-- channel. 0 turns it off.
create or replace function public.set_channel_slowmode(
  target_channel_id uuid,
  seconds integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  channel_circle_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if seconds is null or seconds < 0 or seconds > 21600 then
    raise exception 'Slowmode must be between 0 seconds and 6 hours'
      using errcode = '22023';
  end if;

  select cc.circle_id into channel_circle_id
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel_circle_id is null
    or not public.current_user_has_circle_permission(
      channel_circle_id,
      'manage_channels'
    )
    or not public.current_user_has_channel_permission(
      target_channel_id,
      'view_channel'
    )
  then
    raise exception 'Only members who can manage channels can change slowmode'
      using errcode = '42501';
  end if;

  update public.circle_channels cc
  set slowmode_seconds = seconds,
      updated_at = now()
  where cc.id = target_channel_id
    and cc.slowmode_seconds is distinct from seconds;
end;
$$;

-- Same as 202610130014_channel_permission_overwrites, plus each channel's
-- slowmode.
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
          'slowmode_seconds', cc.slowmode_seconds
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
  where c.id = target_circle_id;
$$;

-- Same as 202610130014_channel_permission_overwrites, plus the slowmode
-- that applies to the caller: the channel's, unless they have
-- manage_messages there; always 0 outside circle channels and in threads.
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
  direct_custom_status jsonb,
  parent_conversation_id uuid,
  parent_title text,
  thread_id uuid,
  thread_archived_at timestamptz,
  thread_last_activity_at timestamptz,
  can_send_messages boolean,
  slowmode_seconds integer
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
      and public.user_has_conversation_channel_permission(
        cm.conversation_id,
        auth.uid(),
        'view_channel'
      )
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
    dp.custom_status as direct_custom_status,
    ct.parent_conversation_id,
    parent_conversation.title as parent_title,
    ct.id as thread_id,
    ct.archived_at as thread_archived_at,
    coalesce(ct.last_message_at, ct.created_at) as thread_last_activity_at,
    cc.id is null
      or public.circle_channel_has_permission(
        cc.id,
        auth.uid(),
        'send_messages'
      ) as can_send_messages,
    case
      when ct.id is null
        and cc.slowmode_seconds > 0
        and not public.circle_channel_has_permission(
          cc.id,
          auth.uid(),
          'manage_messages'
        )
        then cc.slowmode_seconds
      else 0
    end as slowmode_seconds
  from public.conversations c
  join current_memberships cm on cm.conversation_id = c.id
  left join read_markers rm on rm.conversation_id = c.id
  left join direct_profiles dp on dp.conversation_id = c.id and c.type = 'direct'
  left join member_counts mc on mc.conversation_id = c.id
  left join public.messages last_message on last_message.id = c.last_message_id
  left join last_message_mentions lmm on lmm.message_id = last_message.id
  left join public.conversation_threads ct on ct.conversation_id = c.id
  left join public.conversations parent_conversation
    on parent_conversation.id = ct.parent_conversation_id
  left join public.circle_channels cc
    on cc.conversation_id = coalesce(ct.parent_conversation_id, c.id)
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
    cc.id,
    cc.circle_id,
    cc.slowmode_seconds,
    cns.level,
    cns.muted_until,
    ct.id,
    ct.parent_conversation_id,
    ct.archived_at,
    ct.last_message_at,
    ct.created_at,
    parent_conversation.title
  order by
    cm.pinned_at desc nulls last,
    c.last_message_at desc nulls last,
    c.updated_at desc;
$$;

grant execute on function public.set_channel_slowmode(uuid, integer) to authenticated;
grant execute on function public.get_circle_detail(uuid) to authenticated;
grant execute on function public.list_conversation_summaries() to authenticated;
