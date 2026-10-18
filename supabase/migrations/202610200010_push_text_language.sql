-- Push notification text in the language of the device it lands on.
--
-- 202610170005_push_language.sql made claim_push_delivery write each push
-- in the subscription's language ('en' or 'zh'). The push kinds added since
-- built English only; this gives them the same two texts, chosen per
-- subscription:
--
--   * event reminders      "Starting now", "Starts in about 1 hour", ...
--   * task assignments     "Ada assigned you a task"
--   * task due reminders   "Task due soon" / "Task overdue"
--   * message reminders    "Reminder", "Ada: [Image]"
--   * Moments pushes       the fallback name "Someone"
--   * chat cards           a push of a live location, a chat history, a
--                          contact card, a note or a list names the card
--                          ("[名片] Ada") instead of its English body
--
-- card_body_zh is the one place that words the cards in Chinese, so the
-- functions below agree. Each function is its latest definition with only
-- the text changed.

-- A message that carries a card, worded in Chinese for a push. Other text
-- is returned as it is.
create or replace function public.card_body_zh(
  message_body text,
  message_attachment jsonb
)
returns text
language sql
immutable
set search_path = public
as $$
  select case message_attachment->>'kind'
    when 'live_location' then '[实时位置]'
    when 'chat_history' then
      '[聊天记录] ' || coalesce(message_attachment->>'title', '')
    when 'contact_card' then
      '[名片] ' || coalesce(message_attachment->>'name', '')
    when 'note' then
      coalesce(message_attachment->>'icon', '') || ' '
        || coalesce(nullif(btrim(message_attachment->>'title'), ''), '未命名笔记')
    when 'list' then
      coalesce(message_attachment->>'icon', '') || ' '
        || coalesce(nullif(btrim(message_attachment->>'title'), ''), '未命名列表')
    else message_body
  end;
$$;

revoke execute on function public.card_body_zh(text, jsonb) from public, anon, authenticated;
grant execute on function public.card_body_zh(text, jsonb) to service_role;

-- claim_push_delivery (202610170091): cards worded in Chinese for zh devices.
create or replace function public.claim_push_delivery(
  target_message_id uuid,
  caller_id uuid
)
returns table (
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth text,
  conversation_id uuid,
  circle_id uuid,
  title text,
  body text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  message public.messages%rowtype;
  conv public.conversations%rowtype;
  channel public.circle_channels%rowtype;
  circle_name text;
  sender_name text;
  title_en text;
  title_zh text;
  body_en text;
  body_zh text;
  album_images integer := 0;
  album_videos integer := 0;
  album_files integer := 0;
  album_parts_en text[] := array[]::text[];
  album_parts_zh text[] := array[]::text[];
begin
  select m.*
  into message
  from public.messages m
  where m.id = target_message_id;

  if message.id is null
    or message.sender_id is distinct from caller_id
    or message.recalled_at is not null
    -- Waiting for review: pushed when it is released (claim_released_message_pushes).
    or message.review_state is not null
    or message.webhook_id is not null
    or (message.type = 'system' and message.attachment->>'kind' is distinct from 'call')
  then
    return;
  end if;

  if message.attachment_group_id is not null then
    -- Two items of an album claiming at once must not both pass.
    perform pg_advisory_xact_lock(
      hashtextextended('push-album:' || message.attachment_group_id::text, 0)
    );

    if exists (
      select 1
      from public.messages sibling
      join public.push_deliveries delivery on delivery.message_id = sibling.id
      where sibling.conversation_id = message.conversation_id
        and sibling.sender_id = message.sender_id
        and sibling.attachment_group_id = message.attachment_group_id
        and sibling.id <> message.id
    ) then
      return;
    end if;

    select
      count(*) filter (where sibling.type = 'image'),
      count(*) filter (
        where sibling.type = 'file'
          and coalesce(
            sibling.attachment->>'kind' = 'video'
              or sibling.attachment->>'mime_type' like 'video/%',
            false
          )
      ),
      count(*) filter (
        where sibling.type = 'file'
          and not coalesce(
            sibling.attachment->>'kind' = 'video'
              or sibling.attachment->>'mime_type' like 'video/%',
            false
          )
      )
    into album_images, album_videos, album_files
    from public.messages sibling
    where sibling.conversation_id = message.conversation_id
      and sibling.sender_id = message.sender_id
      and sibling.attachment_group_id = message.attachment_group_id
      and sibling.recalled_at is null;
  end if;

  insert into public.push_deliveries (message_id)
  values (message.id)
  on conflict do nothing;
  if not found then
    return;
  end if;

  select c.* into conv from public.conversations c where c.id = message.conversation_id;

  select cc.*
  into channel
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(message.conversation_id);

  if channel.id is not null then
    select ci.name into circle_name from public.circles ci where ci.id = channel.circle_id;
  end if;

  select coalesce(
    nullif(btrim(public.sender_nickname(message)), ''),
    nullif(btrim(p.display_name), ''),
    p.username
  )
  into sender_name
  from public.profiles p
  where p.id = message.sender_id;

  title_en := case
    when channel.id is not null then
      coalesce(sender_name, 'Someone')
        || ' (#' || channel.name || ', ' || coalesce(circle_name, 'circle') || ')'
    when conv.type = 'group' then
      coalesce(sender_name, 'Someone')
        || ' (' || coalesce(nullif(btrim(conv.title), ''), 'group') || ')'
    else coalesce(sender_name, 'Someone')
  end;
  title_zh := case
    when channel.id is not null then
      coalesce(sender_name, '某人')
        || ' (#' || channel.name || ', ' || coalesce(circle_name, '圈子') || ')'
    when conv.type = 'group' then
      coalesce(sender_name, '某人')
        || ' (' || coalesce(nullif(btrim(conv.title), ''), '群聊') || ')'
    else coalesce(sender_name, '某人')
  end;

  if album_images + album_videos + album_files >= 2 then
    if album_images > 0 then
      album_parts_en := album_parts_en || format(
        case when album_images = 1 then '%s photo' else '%s photos' end,
        album_images
      );
      album_parts_zh := album_parts_zh || format('%s 张照片', album_images);
    end if;
    if album_videos > 0 then
      album_parts_en := album_parts_en || format(
        case when album_videos = 1 then '%s video' else '%s videos' end,
        album_videos
      );
      album_parts_zh := album_parts_zh || format('%s 个视频', album_videos);
    end if;
    if album_files > 0 then
      album_parts_en := album_parts_en || format(
        case when album_files = 1 then '%s file' else '%s files' end,
        album_files
      );
      album_parts_zh := album_parts_zh || format('%s 个文件', album_files);
    end if;
    body_en := 'sent ' || array_to_string(album_parts_en, ', ');
    body_zh := '发来 ' || array_to_string(album_parts_zh, '、');
  else
    body_en := case message.type
      when 'text' then left(regexp_replace(message.body, '\s+', ' ', 'g'), 160)
      when 'image' then '[Image]'
      when 'voice' then '[Voice message]'
      when 'file' then
        case when message.attachment->>'kind' = 'video' then '[Video]' else '[File]' end
      when 'poll' then '[Poll]'
      when 'sticker' then '[Sticker]'
      when 'system' then message.body
      else '[Message]'
    end;
    body_zh := case message.type
      when 'text' then public.card_body_zh(body_en, message.attachment)
      when 'image' then '[图片]'
      when 'voice' then '[语音消息]'
      when 'file' then
        case when message.attachment->>'kind' = 'video' then '[视频]' else '[文件]' end
      when 'poll' then '[投票]'
      when 'sticker' then '[贴纸]'
      -- Only "X started a call." notices get here.
      when 'system' then coalesce(sender_name, '某人') || ' 发起了通话'
      else '[消息]'
    end;
  end if;

  return query
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    message.conversation_id,
    channel.circle_id,
    case when s.language = 'zh' then title_zh else title_en end,
    case when s.language = 'zh' then body_zh else body_en end
  from public.conversation_members cm
  join public.push_subscriptions s on s.user_id = cm.user_id
  left join public.circle_notification_settings ns
    on ns.circle_id = channel.circle_id
    and ns.user_id = cm.user_id
  left join public.user_privacy_settings ups on ups.user_id = cm.user_id
  where cm.conversation_id = message.conversation_id
    and cm.user_id <> message.sender_id
    and (cm.muted_until is null or cm.muted_until < now())
    and coalesce(ups.presence_status, 'online') <> 'dnd'
    and not public.are_users_blocked(message.sender_id, cm.user_id)
    and public.user_has_conversation_channel_permission(
      message.conversation_id,
      cm.user_id,
      'view_channel'
    )
    and (
      channel.id is null
      or ns.user_id is null
      or (
        (ns.muted_until is null or ns.muted_until < now())
        and (
          ns.level = 'all'
          or (
            ns.level = 'mentions'
            and exists (
              select 1
              from public.message_mentions mm
              where mm.message_id = message.id
                and mm.user_id = cm.user_id
            )
          )
        )
      )
    );
end;
$$;

-- claim_chat_event_reminder_pushes (202610170050): the "starts in" line per language.
create or replace function public.claim_chat_event_reminder_pushes(
  max_reminders integer default 200
)
returns table (
  reminder_id uuid,
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth text,
  conversation_id uuid,
  event_id uuid,
  title text,
  body text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with claimed as (
    update public.chat_event_reminders r
    set push_sent_at = now()
    where r.id in (
      select p.id
      from public.chat_event_reminders p
      where p.push_sent_at is null
        and p.created_at > now() - interval '30 minutes'
      order by p.created_at
      limit greatest(1, least(coalesce(max_reminders, 200), 1000))
      for update skip locked
    )
    returning r.id, r.event_id, r.user_id, r.lead_minutes
  )
  select
    claimed.id,
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    e.conversation_id,
    e.id,
    e.title,
    case
      when s.language = 'zh' then
        case
          when e.starts_at <= now() then '现在开始'
          when claimed.lead_minutes >= 60 then '约 1 小时后开始'
          else greatest(1, ceil(extract(epoch from (e.starts_at - now())) / 60)::integer) || ' 分钟后开始'
        end
      when e.starts_at <= now() then 'Starting now'
      when claimed.lead_minutes >= 60 then 'Starts in about 1 hour'
      else 'Starts in ' || greatest(1, ceil(extract(epoch from (e.starts_at - now())) / 60)::integer) || ' minutes'
    end
  from claimed
  join public.chat_events e on e.id = claimed.event_id
  join public.conversation_members cm
    on cm.conversation_id = e.conversation_id and cm.user_id = claimed.user_id
  join public.push_subscriptions s on s.user_id = claimed.user_id
  where e.cancelled_at is null
    and (cm.muted_until is null or cm.muted_until < now());
end;
$$;

-- claim_task_assignment_push (202610170063)
create or replace function public.claim_task_assignment_push(
  target_item_id uuid,
  caller_id uuid
)
returns table (
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth text,
  conversation_id uuid,
  circle_id uuid,
  title text,
  body text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  actor_name text;
begin
  select coalesce(nullif(btrim(p.display_name), ''), p.username, 'Someone')
  into actor_name
  from public.profiles p
  where p.id = caller_id;

  return query
  with claimed as (
    update public.task_notifications n
    set pushed_at = now()
    where n.item_id = target_item_id
      and n.kind = 'assigned'
      and n.actor_id = caller_id
      and n.pushed_at is null
      and n.created_at > now() - interval '10 minutes'
    returning n.*
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    c.conversation_id,
    cc.circle_id,
    case when s.language = 'zh' then
      coalesce(actor_name, '某人') || ' 给你分配了一个任务'
    else
      coalesce(actor_name, 'Someone') || ' assigned you a task'
    end,
    c.title
  from claimed c
  join public.push_subscriptions s on s.user_id = c.user_id
  left join public.circle_channels cc
    on cc.id = public.conversation_circle_channel_id(c.conversation_id)
  left join public.circle_notification_settings ns
    on ns.circle_id = cc.circle_id and ns.user_id = c.user_id
  left join public.user_privacy_settings ups on ups.user_id = c.user_id
  where coalesce(ups.presence_status, 'online') <> 'dnd'
    and public.user_has_conversation_channel_permission(
      c.conversation_id, c.user_id, 'view_channel'
    )
    and (
      ns.user_id is null
      or (
        (ns.muted_until is null or ns.muted_until < now())
        and ns.level <> 'none'
      )
    );
end;
$$;

-- due_list_item_reminders (202610170063)
create or replace function public.due_list_item_reminders()
returns table (
  notification_id uuid,
  user_id uuid,
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth text,
  conversation_id uuid,
  circle_id uuid,
  title text,
  body text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  return query
  with candidates as (
    select
      i.id as item_id,
      i.list_id,
      l.conversation_id,
      i.title,
      i.due_at,
      case when i.due_at < now() then 'overdue' else 'due_soon' end as kind,
      coalesce(a.user_id, i.created_by) as person
    from public.task_items i
    join public.task_lists l on l.id = i.list_id and l.deleted_at is null
    left join public.task_item_assignees a on a.item_id = i.id
    where i.deleted_at is null
      and i.completed_at is null
      and i.due_at is not null
      and i.due_at > now() - interval '2 days'
      and i.due_at <= now() + case
        when i.due_has_time then interval '1 hour'
        else interval '12 hours'
      end
  ),
  inserted as (
    -- The push is claimed with the notification (pushed_at), so a second
    -- run never sends it again.
    insert into public.task_notifications (
      user_id, kind, item_id, list_id, conversation_id, title, due_at, pushed_at
    )
    select c.person, c.kind, c.item_id, c.list_id, c.conversation_id,
           left(c.title, 300), c.due_at, now()
    from candidates c
    where c.person is not null
      and exists (
        select 1 from public.conversation_members cm
        where cm.conversation_id = c.conversation_id and cm.user_id = c.person
      )
      and public.user_has_conversation_channel_permission(
        c.conversation_id, c.person, 'view_channel'
      )
    on conflict (user_id, item_id, kind, due_at)
      where kind in ('due_soon', 'overdue')
      do nothing
    returning *
  )
  select
    c.id,
    c.user_id,
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    c.conversation_id,
    cc.circle_id,
    case
      when s.language = 'zh' then
        case c.kind when 'overdue' then '任务已逾期' else '任务即将到期' end
      else
        case c.kind when 'overdue' then 'Task overdue' else 'Task due soon' end
    end,
    c.title
  from inserted c
  join public.push_subscriptions s on s.user_id = c.user_id
  left join public.circle_channels cc
    on cc.id = public.conversation_circle_channel_id(c.conversation_id)
  left join public.circle_notification_settings ns
    on ns.circle_id = cc.circle_id and ns.user_id = c.user_id
  left join public.user_privacy_settings ups on ups.user_id = c.user_id
  where coalesce(ups.presence_status, 'online') <> 'dnd'
    and (
      ns.user_id is null
      or (
        (ns.muted_until is null or ns.muted_until < now())
        and ns.level <> 'none'
      )
    );
end;
$$;

-- claim_reminder_pushes (202610170011)
create or replace function public.claim_reminder_pushes()
returns table (
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth text,
  conversation_id uuid,
  circle_id uuid,
  title text,
  body text,
  tag text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with due as (
    update public.message_reminders r
    set push_claimed_at = now()
    where r.push_claimed_at is null
      and r.dismissed_at is null
      and r.remind_at <= now()
      and r.remind_at > now() - interval '15 minutes'
    returning r.id, r.user_id, r.message_id, r.conversation_id
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    due.conversation_id,
    channel.circle_id,
    case when s.language = 'zh' then '提醒' else 'Reminder' end,
    (
      coalesce(
        m.webhook_name,
        nullif(btrim(public.sender_nickname(m)), ''),
        nullif(btrim(p.display_name), ''),
        p.username,
        case when s.language = 'zh' then '某人' else 'Someone' end
      )
      || ': '
      || case m.type
        when 'text' then left(
          regexp_replace(
            case when s.language = 'zh'
              then public.card_body_zh(m.body, m.attachment)
              else m.body
            end,
            '\s+', ' ', 'g'
          ),
          160
        )
        when 'image' then case when s.language = 'zh' then '[图片]' else '[Image]' end
        when 'voice' then case when s.language = 'zh' then '[语音消息]' else '[Voice message]' end
        when 'file' then
          case
            when m.attachment->>'kind' = 'video' then
              case when s.language = 'zh' then '[视频]' else '[Video]' end
            else case when s.language = 'zh' then '[文件]' else '[File]' end
          end
        when 'poll' then case when s.language = 'zh' then '[投票]' else '[Poll]' end
        when 'sticker' then case when s.language = 'zh' then '[贴纸]' else '[Sticker]' end
        else case when s.language = 'zh' then '[消息]' else '[Message]' end
      end
    ),
    'reminder-' || due.id::text
  from due
  join public.messages m on m.id = due.message_id and m.recalled_at is null
  join public.profiles p on p.id = m.sender_id
  join public.push_subscriptions s on s.user_id = due.user_id
  left join public.user_privacy_settings ups on ups.user_id = due.user_id
  left join public.circle_channels channel
    on channel.id = public.conversation_circle_channel_id(due.conversation_id)
  where coalesce(ups.presence_status, 'online') <> 'dnd'
    and exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = due.conversation_id
        and cm.user_id = due.user_id
    )
    and public.user_has_conversation_channel_permission(
      due.conversation_id,
      due.user_id,
      'view_channel'
    );
end;
$$;

-- claim_moments_pushes (202610190021)
create or replace function public.claim_moments_pushes(
  caller_id uuid default null,
  target_post_id uuid default null
)
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
  -- Too old to be news: closed without a push.
  update public.moments_notifications n
  set pushed_at = now()
  where n.pushed_at is null
    and n.created_at <= now() - interval '10 minutes';

  return query
  with claimed as (
    update public.moments_notifications n
    set pushed_at = now()
    where n.pushed_at is null
      and n.created_at > now() - interval '10 minutes'
      and (caller_id is null or n.actor_id = caller_id)
      and (target_post_id is null or n.post_id = target_post_id)
    returning n.*
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    null::uuid,
    null::uuid,
    case when s.language = 'zh' then
      actor.name || case c.kind
        when 'like' then ' 赞了你的朋友圈'
        when 'comment' then ' 评论了你的朋友圈'
        else ' 回复了你的评论'
      end
    else
      actor.name || case c.kind
        when 'like' then ' liked your Moment'
        when 'comment' then ' commented on your Moment'
        else ' replied to your comment'
      end
    end,
    case
      when c.kind <> 'like' and btrim(c.snippet) <> '' then left(c.snippet, 200)
      when nullif(btrim(p.body), '') is not null then left(btrim(p.body), 80)
      when s.language = 'zh' then case p.kind
        when 'photos' then '[图片]'
        when 'video' then '[视频]'
        when 'link' then coalesce(p.link_title, p.link_url, '[链接]')
        else ''
      end
      else case p.kind
        when 'photos' then '[Photo]'
        when 'video' then '[Video]'
        when 'link' then coalesce(p.link_title, p.link_url, '[Link]')
        else ''
      end
    end,
    'moments-' || c.post_id::text,
    '/#/moments/' || c.post_id::text
  from claimed c
  join public.moments_posts p on p.id = c.post_id
  left join public.moments_comments mc on mc.id = c.comment_id
  join public.push_subscriptions s on s.user_id = c.user_id
  join lateral (
    select coalesce(
      nullif(btrim(ca.alias), ''),
      nullif(btrim(pr.display_name), ''),
      pr.username,
      case when s.language = 'zh' then '某人' else 'Someone' end
    ) as name
    from public.profiles pr
    left join public.contact_aliases ca
      on ca.owner_id = c.user_id and ca.friend_id = pr.id
    where pr.id = c.actor_id
  ) actor on true
  left join public.user_privacy_settings ups on ups.user_id = c.user_id
  left join public.moments_settings ms on ms.user_id = c.user_id
  where coalesce(ups.presence_status, 'online') <> 'dnd'
    and coalesce(ms.push_enabled, true)
    -- Still visible to the recipient, by the rules of the inbox.
    and public.moments_post_visible_to(c.user_id, p)
    and public.moments_interaction_visible(
      c.user_id, p.author_id, c.actor_id, mc.reply_to_user_id
    );
end;
$$;
