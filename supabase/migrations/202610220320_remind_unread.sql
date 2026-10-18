-- "Remind unread" (A6, part 3 of 3): nudge the members who have not read a
-- message yet, once per message.
--
-- remind_unread(target_message_id), for the sender of a message in a group of
-- up to 200 members (the rules of get_message_read_status, 202610220310; they
-- run through message_read_status_rows):
--
--   * It reminds the members whose status is "unread". "Unknown" (receipts
--     off) and blocked people are left alone: reminding only the ones who
--     have not read would tell the sender what the app promised to hide.
--   * Once per message: message_read_reminders has one row per message. A
--     second call fails with already_reminded; a call with nobody to remind
--     fails with nobody_to_remind and uses nothing up.
--   * At most 30 reminders per sender per day (rate_limited, 53400).
--   * Each reminded member gets a read_reminder_notices row: the "Reminder"
--     card in their notifications (list_read_reminder_notices). The card
--     goes away when they read the message or dismiss it.
--   * The push goes out through the push Edge Function:
--     {read_reminder_message_id} -> claim_read_reminder_pushes, which claims
--     the notices once, words the text for each device's language, and
--     leaves out Do Not Disturb, blocked people and people who left. Quiet
--     hours (202610210310) are applied by the function after the claim, as
--     for every push. The notification text carries the message's time as a
--     time token, shown in each device's time zone.
--
-- The notice rows are only reachable through the functions below (no table
-- grant). They follow the message, the conversation and the account.

create table if not exists public.message_read_reminders (
  message_id uuid primary key references public.messages(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_count integer not null check (recipient_count > 0),
  created_at timestamptz not null default now()
);

create index if not exists message_read_reminders_sender_idx
  on public.message_read_reminders (sender_id, created_at);

alter table public.message_read_reminders enable row level security;
revoke all on public.message_read_reminders from anon, authenticated;
grant select on public.message_read_reminders to authenticated;

-- The sender can see that they reminded (and so that it is used up).
drop policy if exists message_read_reminders_select_sender
  on public.message_read_reminders;
create policy message_read_reminders_select_sender
  on public.message_read_reminders for select
  to authenticated
  using (sender_id = auth.uid());

create table if not exists public.read_reminder_notices (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  pushed_at timestamptz,
  read_at timestamptz,
  unique (message_id, recipient_id)
);

create index if not exists read_reminder_notices_recipient_idx
  on public.read_reminder_notices (recipient_id, created_at desc)
  where read_at is null;

alter table public.read_reminder_notices enable row level security;
revoke all on public.read_reminder_notices from anon, authenticated;

create or replace function public.remind_unread(target_message_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  current_user_id uuid := auth.uid();
  message public.messages%rowtype;
  unread_ids uuid[];
  reminded_today integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  -- Serialises two taps on the same message.
  perform pg_advisory_xact_lock(
    hashtextextended('remind-unread:' || target_message_id::text, 0)
  );

  -- The same checks as the list (sender only, group of up to 200, receipts
  -- on, ...); they raise when the message is not eligible.
  select coalesce(array_agg(r.user_id), array[]::uuid[])
  into unread_ids
  from public.message_read_status_rows(target_message_id, current_user_id) r
  where r.status = 'unread';

  if exists (
    select 1
    from public.message_read_reminders mr
    where mr.message_id = target_message_id
  ) then
    raise exception 'already_reminded';
  end if;

  if cardinality(unread_ids) = 0 then
    raise exception 'nobody_to_remind';
  end if;

  select count(*) into reminded_today
  from public.message_read_reminders mr
  where mr.sender_id = current_user_id
    and mr.created_at > now() - interval '1 day';
  if reminded_today >= 30 then
    raise exception 'rate_limited' using errcode = '53400';
  end if;

  select m.* into message
  from public.messages m
  where m.id = target_message_id;

  insert into public.message_read_reminders (message_id, sender_id, recipient_count)
  values (target_message_id, current_user_id, cardinality(unread_ids));

  insert into public.read_reminder_notices (
    message_id, conversation_id, sender_id, recipient_id
  )
  select target_message_id, message.conversation_id, current_user_id, u
  from unnest(unread_ids) as u;

  return cardinality(unread_ids);
end;
$$;

revoke execute on function public.remind_unread(uuid) from public, anon;
grant execute on function public.remind_unread(uuid) to authenticated;

-- The caller's "Reminder" cards: not dismissed, for messages they can still
-- see and have not read.
create or replace function public.list_read_reminder_notices(p_limit integer default 50)
returns table (
  notice_id uuid,
  message_id uuid,
  conversation_id uuid,
  sender_id uuid,
  sender_display_name text,
  sender_avatar_url text,
  body text,
  type text,
  message_created_at timestamptz,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    n.id,
    n.message_id,
    n.conversation_id,
    n.sender_id,
    coalesce(nullif(btrim(ca.alias), ''), p.display_name),
    p.avatar_url,
    left(btrim(coalesce(m.body, '')), 200),
    m.type,
    m.created_at,
    n.created_at
  from public.read_reminder_notices n
  join public.messages m on m.id = n.message_id
  join public.profiles p on p.id = n.sender_id
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid() and ca.friend_id = n.sender_id
  where n.recipient_id = auth.uid()
    and auth.uid() is not null
    and n.read_at is null
    and n.created_at > now() - interval '30 days'
    and m.recalled_at is null
    and (m.expires_at is null or m.expires_at > now())
    and public.message_visible_to_current_user(
      m.review_state, m.sender_id, m.conversation_id
    )
    and exists (
      select 1
      from public.conversation_members me
      where me.conversation_id = n.conversation_id
        and me.user_id = auth.uid()
    )
    and not public.are_users_blocked(auth.uid(), n.sender_id)
    -- Reading the message answers the reminder.
    and not exists (
      select 1
      from public.conversation_members me
      join public.messages read_message on read_message.id = me.last_read_message_id
      where me.conversation_id = n.conversation_id
        and me.user_id = auth.uid()
        and read_message.created_at >= m.created_at
    )
  order by n.created_at desc, n.id
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

revoke execute on function public.list_read_reminder_notices(integer) from public, anon;
grant execute on function public.list_read_reminder_notices(integer) to authenticated;

-- Dismisses cards (all of the caller's when no ids are given).
create or replace function public.mark_read_reminder_notices_read(p_ids uuid[] default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  update public.read_reminder_notices n
  set read_at = now()
  where n.recipient_id = auth.uid()
    and n.read_at is null
    and (p_ids is null or n.id = any (p_ids));
end;
$$;

revoke execute on function public.mark_read_reminder_notices_read(uuid[]) from public, anon;
grant execute on function public.mark_read_reminder_notices_read(uuid[]) to authenticated;

-- For the push Edge Function (service role): the devices to push a reminder
-- to, once. The caller must be the one who reminded; notices older than 10
-- minutes are not pushed any more. Each device gets the text in its language
-- ('en' or 'zh'); the message's time is a time token, which the function
-- writes for the device's time zone.
create or replace function public.claim_read_reminder_pushes(
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
#variable_conflict use_column
declare
  message public.messages%rowtype;
  group_title text;
  sender_name text;
  preview_en text;
  preview_zh text;
  sent_at text;
begin
  select m.* into message
  from public.messages m
  where m.id = target_message_id;

  if message.id is null
    or message.sender_id is distinct from caller_id
    or message.recalled_at is not null
    or message.review_state is not null
  then
    return;
  end if;

  select nullif(btrim(c.title), '') into group_title
  from public.conversations c
  where c.id = message.conversation_id;

  select coalesce(nullif(btrim(p.display_name), ''), p.username)
  into sender_name
  from public.profiles p
  where p.id = message.sender_id;

  preview_en := case message.type
    when 'text' then left(regexp_replace(message.body, '\s+', ' ', 'g'), 120)
    when 'image' then '[Image]'
    when 'voice' then '[Voice message]'
    when 'file' then
      case when message.attachment->>'kind' = 'video' then '[Video]' else '[File]' end
    when 'poll' then '[Poll]'
    when 'sticker' then '[Sticker]'
    else '[Message]'
  end;
  preview_zh := case message.type
    when 'text' then public.card_body_zh(
      left(regexp_replace(message.body, '\s+', ' ', 'g'), 120),
      message.attachment
    )
    when 'image' then '[图片]'
    when 'voice' then '[语音消息]'
    when 'file' then
      case when message.attachment->>'kind' = 'video' then '[视频]' else '[文件]' end
    when 'poll' then '[投票]'
    when 'sticker' then '[贴纸]'
    else '[消息]'
  end;
  sent_at := '<t:' || floor(extract(epoch from message.created_at))::bigint::text || ':t>';

  return query
  with claimed as (
    update public.read_reminder_notices n
    set pushed_at = now()
    where n.message_id = target_message_id
      and n.sender_id = caller_id
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
    null::uuid,
    case when s.language = 'zh' then
      '提醒：' || coalesce(sender_name, '某人')
        || ' (' || coalesce(group_title, '群聊') || ')'
    else
      'Reminder: ' || coalesce(sender_name, 'Someone')
        || ' (' || coalesce(group_title, 'group') || ')'
    end,
    case when s.language = 'zh' then
      '发送于 ' || sent_at || ' · ' || preview_zh
    else
      'Sent ' || sent_at || ' · ' || preview_en
    end
  from claimed c
  join public.push_subscriptions s on s.user_id = c.recipient_id
  left join public.user_privacy_settings ups on ups.user_id = c.recipient_id
  where coalesce(ups.presence_status, 'online') <> 'dnd'
    and not public.are_users_blocked(c.sender_id, c.recipient_id)
    and exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = c.conversation_id
        and cm.user_id = c.recipient_id
    );
end;
$$;

revoke execute on function public.claim_read_reminder_pushes(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.claim_read_reminder_pushes(uuid, uuid)
  to service_role;
