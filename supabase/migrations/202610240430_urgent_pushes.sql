-- Urgent and "please confirm" pushes (A7, part 4 of 4).
--
-- Both are claimed by the scheduled-dispatch Edge Function (service role),
-- like the pushes of reminders and join requests: send_message_urgent and the
-- reminder functions wake it at once, and run_later_dispatch
-- (202610240460) wakes it while a second push is due. The claim marks the
-- rows, so a push is sent once however many times the function wakes up.
-- claim_push_delivery (7 versions) and the other claim functions are not
-- touched.
--
-- claim_urgent_pushes()
--   * First push: right after the message was made urgent (rows of the last
--     15 minutes; older rows nobody pushed are closed without a push, so an
--     outage does not end in a burst).
--   * Second push: a person who has not confirmed 10 minutes after the first
--     push gets it once more (never a third time), worded as "not confirmed
--     yet"; rows older than an hour after the first push are closed.
--   * Breaks through: the Do Not Disturb status, the muted conversation, the
--     circle notification level. The function does not hold urgent pushes back
--     for quiet hours either (index.ts of scheduled-dispatch).
--   * Still keeps: blocks (either way), people who turned urgent messages off
--     for the sender, people who left the conversation or can no longer see
--     the channel, a taken-down circle, a message that was deleted, expired or
--     is waiting for review, and a confirmation made in between. The text is
--     written for each device's language ('en' or 'zh'). It carries no time,
--     so no time zone is involved; the message itself is shown in the chat.
--
-- claim_announcement_ack_pushes()
--   * One row of announcement_ack_reminders for each member asked. Pushed once
--     (rows of the last 15 minutes). The normal push rules apply: Do Not
--     Disturb, mute, and quiet hours (applied by the function).
--   * Skipped if the member confirmed or left, the announcement no longer asks
--     for a confirmation, or either person blocked the other.

create or replace function public.claim_urgent_pushes()
returns table (
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth text,
  conversation_id uuid,
  circle_id uuid,
  title text,
  body text,
  tag text,
  url text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  -- Too late to be news: closed without a push.
  update public.message_urgent_targets t
  set push_claimed_at = now(), repush_claimed_at = now()
  where t.acked_at is null
    and t.push_claimed_at is null
    and t.created_at <= now() - interval '15 minutes';
  update public.message_urgent_targets t
  set repush_claimed_at = now()
  where t.acked_at is null
    and t.repush_claimed_at is null
    and t.push_claimed_at is not null
    and t.push_claimed_at <= now() - interval '1 hour';

  return query
  with first_push as (
    update public.message_urgent_targets t
    set push_claimed_at = now()
    where t.acked_at is null
      and t.push_claimed_at is null
      and t.created_at > now() - interval '15 minutes'
    returning t.urgent_id, t.message_id, t.user_id
  ), second_push as (
    update public.message_urgent_targets t
    set repush_claimed_at = now()
    where t.acked_at is null
      and t.repush_claimed_at is null
      and t.push_claimed_at is not null
      and t.push_claimed_at <= now() - interval '10 minutes'
    returning t.urgent_id, t.message_id, t.user_id
  ), claimed as (
    select f.urgent_id, f.message_id, f.user_id, false as again from first_push f
    union all
    select s.urgent_id, s.message_id, s.user_id, true from second_push s
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    m.conversation_id,
    ch.circle_id,
    case when s.language = 'zh' then
      case when c.again then '加急消息未确认：' else '' end
        || coalesce(sender.name, '某人')
        || case when c.again then '' else ' 加急了一条消息' end
        || case
          when ch.id is not null then
            ' (#' || ch.name || ', ' || coalesce(circle.name, '圈子') || ')'
          when conv.type = 'group' then
            ' (' || coalesce(nullif(btrim(conv.title), ''), '群聊') || ')'
          else ''
        end
    else
      case when c.again then 'Urgent, not confirmed yet: ' else '' end
        || coalesce(sender.name, 'Someone')
        || case when c.again then '' else ' marked a message urgent' end
        || case
          when ch.id is not null then
            ' (#' || ch.name || ', ' || coalesce(circle.name, 'circle') || ')'
          when conv.type = 'group' then
            ' (' || coalesce(nullif(btrim(conv.title), ''), 'group') || ')'
          else ''
        end
    end,
    case when s.language = 'zh' then
      case m.type
        when 'text' then public.card_body_zh(
          left(regexp_replace(m.body, '\s+', ' ', 'g'), 160), m.attachment
        )
        when 'image' then '[图片]'
        when 'voice' then '[语音消息]'
        when 'file' then
          case when m.attachment->>'kind' = 'video' then '[视频]' else '[文件]' end
        when 'poll' then '[投票]'
        when 'sticker' then '[贴纸]'
        else '[消息]'
      end
    else
      case m.type
        when 'text' then left(regexp_replace(m.body, '\s+', ' ', 'g'), 160)
        when 'image' then '[Image]'
        when 'voice' then '[Voice message]'
        when 'file' then
          case when m.attachment->>'kind' = 'video' then '[Video]' else '[File]' end
        when 'poll' then '[Poll]'
        when 'sticker' then '[Sticker]'
        else '[Message]'
      end
    end,
    'urgent-' || m.id::text,
    null::text
  from claimed c
  join public.message_urgents u on u.id = c.urgent_id
  join public.messages m on m.id = c.message_id
  join public.conversations conv on conv.id = m.conversation_id
  join public.push_subscriptions s on s.user_id = c.user_id
  join lateral (
    select coalesce(
      nullif(btrim(public.sender_nickname(m)), ''),
      nullif(btrim(pr.display_name), ''),
      pr.username
    ) as name
    from public.profiles pr
    where pr.id = u.sender_id
  ) sender on true
  left join public.circle_channels ch
    on ch.id = public.conversation_circle_channel_id(m.conversation_id)
  left join public.circles circle on circle.id = ch.circle_id
  where m.recalled_at is null
    and m.review_state is null
    and (m.expires_at is null or m.expires_at > now())
    and exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id = m.conversation_id and cm.user_id = c.user_id
    )
    and public.user_has_conversation_channel_permission(
      m.conversation_id, c.user_id, 'view_channel'
    )
    and not public.conversation_in_suspended_circle(m.conversation_id)
    and not public.are_users_blocked(u.sender_id, c.user_id)
    and not exists (
      select 1 from public.urgent_sender_mutes mute
      where mute.user_id = c.user_id and mute.sender_id = u.sender_id
    );
end;
$$;

revoke execute on function public.claim_urgent_pushes()
  from public, anon, authenticated;
grant execute on function public.claim_urgent_pushes() to service_role;

create or replace function public.claim_announcement_ack_pushes()
returns table (
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth text,
  conversation_id uuid,
  circle_id uuid,
  title text,
  body text,
  tag text,
  url text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  update public.announcement_ack_reminders r
  set pushed_at = now()
  where r.pushed_at is null
    and r.created_at <= now() - interval '15 minutes';

  return query
  with claimed as (
    update public.announcement_ack_reminders r
    set pushed_at = now()
    where r.pushed_at is null
      and r.created_at > now() - interval '15 minutes'
    returning r.conversation_id, r.user_id, r.sender_id
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    conv.id,
    null::uuid,
    case when s.language = 'zh' then
      '请确认群公告 (' || coalesce(nullif(btrim(conv.title), ''), '群聊') || ')'
    else
      'Please confirm the announcement ('
        || coalesce(nullif(btrim(conv.title), ''), 'group') || ')'
    end,
    left(regexp_replace(btrim(conv.announcement), '\s+', ' ', 'g'), 160),
    'announcement-' || conv.id::text,
    null::text
  from claimed c
  join public.conversations conv on conv.id = c.conversation_id
  join public.conversation_members cm
    on cm.conversation_id = c.conversation_id and cm.user_id = c.user_id
  join public.push_subscriptions s on s.user_id = c.user_id
  left join public.user_privacy_settings ups on ups.user_id = c.user_id
  where conv.announcement_requires_ack
    and (cm.muted_until is null or cm.muted_until < now())
    and coalesce(ups.presence_status, 'online') <> 'dnd'
    and not exists (
      select 1 from public.announcement_acks a
      where a.conversation_id = c.conversation_id and a.user_id = c.user_id
    )
    and not public.are_users_blocked(c.sender_id, c.user_id);
end;
$$;

revoke execute on function public.claim_announcement_ack_pushes()
  from public, anon, authenticated;
grant execute on function public.claim_announcement_ack_pushes() to service_role;
