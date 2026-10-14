-- Web push notifications.
--
-- * push_subscriptions: a browser's Web Push endpoint and keys per user,
--   written only through register_push_subscription /
--   unregister_push_subscription.
-- * The sender's app asks the push-notify Edge Function to deliver a new
--   message. The function (service role) calls claim_push_delivery, which
--   records the message in push_deliveries so it is pushed at most once and
--   returns who to notify: members who can see the conversation, other than
--   the sender, not blocked by or blocking them, not muted, and, in circles,
--   following their notification level (all, mentions only, none).
-- * Calls ring through push too: "X started a call." system messages are
--   delivered; other system notices are not.

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  constraint push_subscriptions_endpoint_https check (endpoint ~ '^https://'),
  constraint push_subscriptions_key_lengths check (
    char_length(p256dh) between 40 and 200
    and char_length(auth) between 10 and 100
    and char_length(endpoint) <= 2048
  )
);

create index if not exists push_subscriptions_user_idx
  on public.push_subscriptions (user_id);

alter table public.push_subscriptions enable row level security;

drop policy if exists push_subscriptions_select_own on public.push_subscriptions;
create policy push_subscriptions_select_own
  on public.push_subscriptions for select
  to authenticated
  using (user_id = auth.uid());

revoke insert, update, delete on public.push_subscriptions from anon, authenticated;

create table if not exists public.push_deliveries (
  message_id uuid primary key references public.messages(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.push_deliveries enable row level security;
revoke all on public.push_deliveries from anon, authenticated;

-- Saves this browser's subscription for the caller; an endpoint moves to
-- whoever signed in on that browser last.
create or replace function public.register_push_subscription(
  target_endpoint text,
  target_p256dh text,
  target_auth text,
  target_user_agent text default null
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
    user_agent
  )
  values (
    auth.uid(),
    target_endpoint,
    target_p256dh,
    target_auth,
    left(target_user_agent, 300)
  )
  on conflict (endpoint) do update
  set
    user_id = excluded.user_id,
    p256dh = excluded.p256dh,
    auth = excluded.auth,
    user_agent = excluded.user_agent,
    last_seen_at = now();
end;
$$;

create or replace function public.unregister_push_subscription(target_endpoint text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  delete from public.push_subscriptions s
  where s.endpoint = target_endpoint
    and s.user_id = auth.uid();
end;
$$;

-- For push-notify (service role only). Claims [target_message_id] for
-- delivery and returns one row per subscription to notify, with the text
-- to show; nothing when the message was already pushed, isn't pushable or
-- [caller_id] didn't send it.
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
  where cm.conversation_id = message.conversation_id
    and cm.user_id <> message.sender_id
    and (cm.muted_until is null or cm.muted_until < now())
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

-- For push-notify (service role only): drops subscriptions the push
-- service says are gone.
create or replace function public.remove_push_subscriptions(target_ids uuid[])
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.push_subscriptions s where s.id = any(target_ids);
$$;

revoke execute on function public.register_push_subscription(text, text, text, text) from public, anon;
revoke execute on function public.unregister_push_subscription(text) from public, anon;
grant execute on function public.register_push_subscription(text, text, text, text) to authenticated;
grant execute on function public.unregister_push_subscription(text) to authenticated;

revoke execute on function public.claim_push_delivery(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.remove_push_subscriptions(uuid[]) from public, anon, authenticated;
grant execute on function public.claim_push_delivery(uuid, uuid) to service_role;
grant execute on function public.remove_push_subscriptions(uuid[]) to service_role;
