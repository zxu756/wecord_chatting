-- Performance: one conversation's summary without the whole list.
--
-- The chat screen needs the summary of the conversation it shows (title,
-- type, whether the person may send, slow mode, thread state, ...) and got it
-- by running list_conversation_summaries, the server's heaviest query, over
-- every conversation and keeping one row. get_conversation_summary returns
-- the same row for one conversation: the very same query, as of the latest
-- list_conversation_summaries (202610190011_security_hidden_messages.sql),
-- narrowed to the conversation at each step so only its rows are read.
-- Nothing comes back for a conversation the person is not in, cannot view, or
-- has hidden (with no newer message), exactly as the list leaves them out.
-- When list_conversation_summaries changes, change this with it: the
-- behaviour test compares the two for every conversation.

CREATE OR REPLACE FUNCTION public.get_conversation_summary(target_conversation_id uuid)
 RETURNS TABLE(id uuid, type text, title text, avatar_url text, announcement text, announcement_updated_at timestamp with time zone, announcement_updated_by uuid, last_message_body text, last_message_sender_id uuid, last_message_at timestamp with time zone, last_message_type text, last_message_webhook_name text, last_message_attachment_kind text, last_message_album jsonb, unread_count bigint, pinned_at timestamp with time zone, muted_until timestamp with time zone, is_muted boolean, is_marked_unread boolean, member_count bigint, mentioned_user_ids uuid[], circle_id uuid, circle_notification_level text, circle_muted_until timestamp with time zone, direct_user_id uuid, direct_custom_status jsonb, parent_conversation_id uuid, parent_title text, thread_id uuid, thread_archived_at timestamp with time zone, thread_last_activity_at timestamp with time zone, can_send_messages boolean, slowmode_seconds integer, is_note_to_self boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      and cm.conversation_id = target_conversation_id
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
  -- Messages from others (and webhooks) after the read marker, an album
  -- counted once. Worked out per conversation on its own, so the summary
  -- query below needs no GROUP BY over all its columns.
  unread_counts as (
    select
      rm.conversation_id,
      count(unread_messages.id)
        - count(unread_messages.attachment_group_id)
        + count(distinct unread_messages.attachment_group_id) as unread_count
    from read_markers rm
    join public.messages unread_messages
      on unread_messages.conversation_id = rm.conversation_id
      and unread_messages.review_state is null
      and (unread_messages.expires_at is null or unread_messages.expires_at > now())
      -- A pat is only a line in the chat, never unread.
      and not (
        unread_messages.type = 'system'
        and unread_messages.attachment->>'kind' = 'pat'
      )
      and (
        unread_messages.sender_id <> auth.uid()
        or unread_messages.webhook_name is not null
      )
      and (
        rm.last_read_at is null
        or unread_messages.created_at > rm.last_read_at
      )
    group by rm.conversation_id
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
      and cm.conversation_id = target_conversation_id
  ),
  member_counts as (
    select cm.conversation_id, count(*) as member_count
    from public.conversation_members cm
    where cm.conversation_id = target_conversation_id
    group by cm.conversation_id
  ),
  last_message_mentions as (
    select mm.message_id, array_agg(distinct mm.user_id) as mentioned_user_ids
    from public.message_mentions mm
    where mm.message_id = (
      select lc.last_message_id
      from public.conversations lc
      where lc.id = target_conversation_id
    )
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
    last_message.webhook_name as last_message_webhook_name,
    case
      when last_message.recalled_at is not null then null
      when last_message.type <> 'file' then null
      when last_message.attachment->>'kind' = 'video'
        or last_message.attachment->>'mime_type' like 'video/%' then 'video'
      else 'file'
    end as last_message_attachment_kind,
    case
      when album.total >= 2 then album.counts
      else null
    end as last_message_album,
    greatest(
      coalesce(uc.unread_count, 0),
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
    end as slowmode_seconds,
    nts.conversation_id is not null as is_note_to_self
  from public.conversations c
  join current_memberships cm on cm.conversation_id = c.id
  left join read_markers rm on rm.conversation_id = c.id
  left join direct_profiles dp on dp.conversation_id = c.id and c.type = 'direct'
  left join member_counts mc on mc.conversation_id = c.id
  left join public.messages last_message
    on last_message.id = c.last_message_id
    -- An expired message is gone even before the purge deletes it, and one
    -- waiting for review is not the chat's latest message for anyone else.
    and (last_message.expires_at is null or last_message.expires_at > now())
    and public.message_visible_to_current_user(last_message.review_state, last_message.sender_id, last_message.conversation_id)
  left join last_message_mentions lmm on lmm.message_id = last_message.id
  -- The rest of the latest message's album, if it is in one.
  left join lateral (
    select
      count(*) as total,
      jsonb_build_object(
        'images', count(*) filter (where album_message.type = 'image'),
        'videos', count(*) filter (
          where album_message.type = 'file'
            and coalesce(
              album_message.attachment->>'kind' = 'video'
                or album_message.attachment->>'mime_type' like 'video/%',
              false
            )
        ),
        'files', count(*) filter (
          where album_message.type = 'file'
            and not coalesce(
              album_message.attachment->>'kind' = 'video'
                or album_message.attachment->>'mime_type' like 'video/%',
              false
            )
        )
      ) as counts
    from public.messages album_message
    where album_message.conversation_id = c.id
      and album_message.sender_id = last_message.sender_id
      and album_message.attachment_group_id = last_message.attachment_group_id
      and album_message.recalled_at is null
  ) album
    on last_message.attachment_group_id is not null
    and last_message.recalled_at is null
  left join public.conversation_threads ct on ct.conversation_id = c.id
  left join public.conversations parent_conversation
    on parent_conversation.id = ct.parent_conversation_id
  left join public.circle_channels cc
    on cc.conversation_id = coalesce(ct.parent_conversation_id, c.id)
  left join public.circle_notification_settings cns
    on cns.circle_id = cc.circle_id
    and cns.user_id = auth.uid()
  left join unread_counts uc on uc.conversation_id = c.id
  left join public.note_to_self_conversations nts
    on nts.conversation_id = c.id
    and nts.user_id = auth.uid()
  where c.id = target_conversation_id
    and (
      cm.hidden_at is null
      or c.last_message_at > cm.hidden_at
    );
$function$;

revoke execute on function public.get_conversation_summary(uuid) from public, anon;
grant execute on function public.get_conversation_summary(uuid) to authenticated;
