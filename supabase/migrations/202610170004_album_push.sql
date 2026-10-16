-- An album is one push: "Ada sent 3 photos".
--
-- Each picture, video or file of an album is a message of its own, and
-- the sender's app asks for a push once the album is stored (see
-- 202610170001_media_albums). claim_push_delivery now
-- * sends one push for the whole album: when a message of the album was
--   already pushed (its push_deliveries row exists) the others are
--   skipped, so a retried or late item does not ring again;
-- * says what the album holds, "sent 3 photos", "sent 2 photos, 1 video"
--   or "sent 4 files", counting the album's messages that are not deleted.
--   An album of one message reads as a single picture, video or file.
--
-- Same as 202610160032_push_delivery_recipients otherwise.
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
  push_title text;
  push_body text;
  album_images integer := 0;
  album_videos integer := 0;
  album_files integer := 0;
  album_parts text[] := array[]::text[];
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
  sender_name := coalesce(sender_name, 'Someone');

  push_title := case
    when channel.id is not null then
      sender_name || ' (#' || channel.name || ', ' || coalesce(circle_name, 'circle') || ')'
    when conv.type = 'group' then
      sender_name || ' (' || coalesce(nullif(btrim(conv.title), ''), 'group') || ')'
    else sender_name
  end;

  if album_images + album_videos + album_files >= 2 then
    if album_images > 0 then
      album_parts := album_parts || format(
        case when album_images = 1 then '%s photo' else '%s photos' end,
        album_images
      );
    end if;
    if album_videos > 0 then
      album_parts := album_parts || format(
        case when album_videos = 1 then '%s video' else '%s videos' end,
        album_videos
      );
    end if;
    if album_files > 0 then
      album_parts := album_parts || format(
        case when album_files = 1 then '%s file' else '%s files' end,
        album_files
      );
    end if;
    push_body := 'sent ' || array_to_string(album_parts, ', ');
  else
    push_body := case message.type
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
  end if;

  return query
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    message.conversation_id,
    channel.circle_id,
    push_title,
    push_body
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
