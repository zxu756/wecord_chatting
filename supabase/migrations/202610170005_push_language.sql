-- Push notifications in the language of the app they land in.
--
-- Each push subscription (a browser, signed in as one user) now stores the
-- app language of that device, 'en' or 'zh', sent by the app when it saves
-- the subscription (register_push_subscription) and again whenever the
-- language setting changes. claim_push_delivery writes each row's title and
-- body in that language: "[图片]", "发来 3 张照片", "Ada 发起了通话" for
-- Chinese devices, the same English text as before for the rest.
--
-- claim_push_delivery is 202610170004_album_push.sql with the text built
-- twice and chosen per subscription.

alter table public.push_subscriptions
  add column if not exists language text not null default 'en';

alter table public.push_subscriptions
  drop constraint if exists push_subscriptions_language_check;
alter table public.push_subscriptions
  add constraint push_subscriptions_language_check
  check (language in ('en', 'zh'));

-- The old four argument version goes: the new one takes the same call
-- (language is optional), and keeping both would make that call ambiguous.
drop function if exists public.register_push_subscription(text, text, text, text);

create or replace function public.register_push_subscription(
  target_endpoint text,
  target_p256dh text,
  target_auth text,
  target_user_agent text default null,
  target_language text default 'en'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  insert into public.push_subscriptions (
    user_id,
    endpoint,
    p256dh,
    auth,
    user_agent,
    language
  )
  values (
    auth.uid(),
    target_endpoint,
    target_p256dh,
    target_auth,
    left(target_user_agent, 300),
    case when target_language = 'zh' then 'zh' else 'en' end
  )
  on conflict (endpoint) do update
  set
    user_id = excluded.user_id,
    p256dh = excluded.p256dh,
    auth = excluded.auth,
    user_agent = excluded.user_agent,
    language = excluded.language,
    last_seen_at = now();
end;
$$;

revoke execute on function public.register_push_subscription(text, text, text, text, text) from public, anon;
grant execute on function public.register_push_subscription(text, text, text, text, text) to authenticated;

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
      when 'text' then body_en
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

revoke execute on function public.claim_push_delivery(uuid, uuid) from public, anon, authenticated;
grant execute on function public.claim_push_delivery(uuid, uuid) to service_role;
