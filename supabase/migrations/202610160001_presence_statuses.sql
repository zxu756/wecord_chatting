-- Presence statuses: Online, Idle, Do Not Disturb and Invisible.
--
-- * user_privacy_settings.presence_status is the status the user picked,
--   remembered across devices. Only its owner reads it (the table's RLS);
--   everyone else learns Online, Idle or Do Not Disturb from the app-wide
--   realtime presence channel, which Invisible users never join visibly.
-- * Do Not Disturb silences pushes: claim_push_delivery leaves those
--   recipients out. The app silences its own local notifications.
-- * set_show_online_status saves the existing show_online_status switch,
--   which hides the user like Invisible does.

alter table public.user_privacy_settings
  add column if not exists presence_status text not null default 'online';

alter table public.user_privacy_settings
  drop constraint if exists user_privacy_settings_presence_status_check;
alter table public.user_privacy_settings
  add constraint user_privacy_settings_presence_status_check check (
    presence_status in ('online', 'idle', 'dnd', 'invisible')
  );

-- Saves the caller's status. Returns it.
create or replace function public.set_presence_status(new_status text)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if new_status is null
    or new_status not in ('online', 'idle', 'dnd', 'invisible')
  then
    raise exception 'Unknown status' using errcode = '22023';
  end if;

  insert into public.user_privacy_settings (user_id, presence_status)
  values (auth.uid(), new_status)
  on conflict (user_id) do update
  set presence_status = excluded.presence_status;

  return new_status;
end;
$$;

-- Saves whether others see the caller online. Returns it.
create or replace function public.set_show_online_status(show boolean)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if show is null then
    raise exception 'A value is required' using errcode = '22023';
  end if;

  insert into public.user_privacy_settings (user_id, show_online_status)
  values (auth.uid(), show)
  on conflict (user_id) do update
  set show_online_status = excluded.show_online_status;

  return show;
end;
$$;

-- Same as 202610140008_push_notifications, except that recipients in
-- Do Not Disturb are left out.
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
    and public.conversation_member_can_view(message.conversation_id, cm.user_id)
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

revoke execute on function public.set_presence_status(text) from public, anon;
revoke execute on function public.set_show_online_status(boolean) from public, anon;
grant execute on function public.set_presence_status(text) to authenticated;
grant execute on function public.set_show_online_status(boolean) to authenticated;

revoke execute on function public.claim_push_delivery(uuid, uuid) from public, anon, authenticated;
grant execute on function public.claim_push_delivery(uuid, uuid) to service_role;
