-- "Remind me": a message comes back to its reader at a time they chose.
--
-- * message_reminders: one row per reminder (RLS: owner only for select and
--   delete). Rows are written through the functions below, which check the
--   caller can see the message. The message may go away later (the id is
--   cleared); the reminder then reads "Message unavailable".
-- * A reminder is "fired" when remind_at has passed, whether or not any job
--   ran: list_my_reminders works that out when it is read, so the inbox item
--   needs neither cron nor the app to have been open. It stays until the
--   reader dismisses it.
-- * claim_local_reminders: the open app asks for reminders that came due and
--   shows a local notification for each, once (those more than an hour old
--   are marked without one).
-- * claim_reminder_pushes: for the scheduled-dispatch Edge Function (service
--   role): reminders that came due in the last 15 minutes and were not
--   pushed yet, claimed once, with the push subscriptions to send them to:
--   title "Reminder", body "{sender}: {text}". Nothing goes to someone in
--   Do Not Disturb or who can no longer see the conversation.
-- * run_later_dispatch (202610170010) also wakes the Edge Function when a
--   reminder push is waiting.

create table if not exists public.message_reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  message_id uuid references public.messages(id) on delete set null,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  remind_at timestamptz not null,
  created_at timestamptz not null default now(),
  local_notified_at timestamptz,
  push_claimed_at timestamptz,
  dismissed_at timestamptz
);

create index if not exists message_reminders_user_idx
  on public.message_reminders (user_id, remind_at)
  where dismissed_at is null;

create index if not exists message_reminders_push_idx
  on public.message_reminders (remind_at)
  where push_claimed_at is null and dismissed_at is null;

alter table public.message_reminders enable row level security;

revoke all on public.message_reminders from anon, authenticated;
grant select, delete on public.message_reminders to authenticated;

drop policy if exists message_reminders_select_own on public.message_reminders;
create policy message_reminders_select_own
  on public.message_reminders for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists message_reminders_delete_own on public.message_reminders;
create policy message_reminders_delete_own
  on public.message_reminders for delete
  to authenticated
  using (user_id = auth.uid());

-- Sets (or moves) the caller's reminder about a message.
create or replace function public.set_message_reminder(
  p_message_id uuid,
  p_remind_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_conversation_id uuid;
  reminder_id uuid;
  open_count integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_remind_at is null
    or p_remind_at < now() - interval '1 minute'
    or p_remind_at > now() + interval '1 year'
  then
    raise exception 'Reminder time must be in the next year' using errcode = '22023';
  end if;

  select m.conversation_id
  into target_conversation_id
  from public.messages m
  where m.id = p_message_id
    and m.recalled_at is null
    and m.conversation_id in (select public.current_user_readable_conversation_ids());
  if target_conversation_id is null then
    raise exception 'Message not found' using errcode = 'P0002';
  end if;

  -- One open reminder per message: setting it again moves it.
  delete from public.message_reminders r
  where r.user_id = current_user_id
    and r.message_id = p_message_id
    and r.dismissed_at is null;

  select count(*)
  into open_count
  from public.message_reminders r
  where r.user_id = current_user_id
    and r.dismissed_at is null
    and r.remind_at > now();
  if open_count >= 200 then
    raise exception 'Too many reminders' using errcode = '53400';
  end if;

  insert into public.message_reminders (user_id, message_id, conversation_id, remind_at)
  values (current_user_id, p_message_id, target_conversation_id, p_remind_at)
  returning id into reminder_id;

  return reminder_id;
end;
$$;

revoke execute on function public.set_message_reminder(uuid, timestamptz) from public, anon;
grant execute on function public.set_message_reminder(uuid, timestamptz) to authenticated;

-- Dismisses a reminder (a fired one from the inbox, or an upcoming one).
create or replace function public.dismiss_message_reminder(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  update public.message_reminders r
  set dismissed_at = now()
  where r.id = p_id
    and r.user_id = auth.uid();
end;
$$;

revoke execute on function public.dismiss_message_reminder(uuid) from public, anon;
grant execute on function public.dismiss_message_reminder(uuid) to authenticated;

-- The caller's open reminders, upcoming and fired, soonest first, with the
-- message as the caller may see it (security invoker: messages and profiles
-- keep their own policies, so a message the caller can no longer read
-- comes back unavailable).
create or replace function public.list_my_reminders(p_limit integer default 100)
returns table (
  reminder_id uuid,
  message_id uuid,
  conversation_id uuid,
  remind_at timestamptz,
  fired boolean,
  sender_id uuid,
  sender_display_name text,
  sender_avatar_url text,
  webhook_name text,
  body text,
  type text,
  message_created_at timestamptz,
  available boolean
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    r.id,
    r.message_id,
    r.conversation_id,
    r.remind_at,
    r.remind_at <= now(),
    case when m.recalled_at is null then m.sender_id end,
    case when m.recalled_at is null then p.display_name end,
    case when m.recalled_at is null then p.avatar_url end,
    case when m.recalled_at is null then m.webhook_name end,
    case when m.recalled_at is null then m.body end,
    case when m.recalled_at is null then m.type end,
    case when m.recalled_at is null then m.created_at end,
    m.id is not null and m.recalled_at is null
  from public.message_reminders r
  left join public.messages m on m.id = r.message_id
  left join public.profiles p on p.id = m.sender_id
  where r.user_id = auth.uid()
    and r.dismissed_at is null
  order by r.remind_at, r.id
  limit greatest(1, least(coalesce(p_limit, 100), 200));
$$;

revoke execute on function public.list_my_reminders(integer) from public, anon;
grant execute on function public.list_my_reminders(integer) to authenticated;

-- Reminders that came due for the caller and were not shown by an open app
-- yet. Marks them shown; the older ones (more than an hour late) only
-- marked.
create or replace function public.claim_local_reminders()
returns table (
  reminder_id uuid,
  conversation_id uuid,
  message_id uuid,
  remind_at timestamptz,
  sender_name text,
  body text,
  type text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  return query
  with due as (
    update public.message_reminders r
    set local_notified_at = now()
    where r.user_id = auth.uid()
      and r.remind_at <= now()
      and r.local_notified_at is null
      and r.dismissed_at is null
    returning r.id, r.conversation_id, r.message_id, r.remind_at
  )
  select
    due.id,
    due.conversation_id,
    due.message_id,
    due.remind_at,
    coalesce(
      m.webhook_name,
      nullif(btrim(public.sender_nickname(m)), ''),
      nullif(btrim(p.display_name), ''),
      p.username
    ),
    m.body,
    m.type
  from due
  join public.messages m on m.id = due.message_id
  join public.profiles p on p.id = m.sender_id
  where due.remind_at > now() - interval '1 hour'
    and m.recalled_at is null
    and due.conversation_id in (select public.current_user_readable_conversation_ids())
  order by due.remind_at;
end;
$$;

revoke execute on function public.claim_local_reminders() from public, anon;
grant execute on function public.claim_local_reminders() to authenticated;

-- Reminder pushes for the scheduled-dispatch Edge Function.
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
    'Reminder'::text,
    (
      coalesce(
        m.webhook_name,
        nullif(btrim(public.sender_nickname(m)), ''),
        nullif(btrim(p.display_name), ''),
        p.username,
        'Someone'
      )
      || ': '
      || case m.type
        when 'text' then left(regexp_replace(m.body, '\s+', ' ', 'g'), 160)
        when 'image' then '[Image]'
        when 'voice' then '[Voice message]'
        when 'file' then
          case when m.attachment->>'kind' = 'video' then '[Video]' else '[File]' end
        when 'poll' then '[Poll]'
        when 'sticker' then '[Sticker]'
        else '[Message]'
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

revoke execute on function public.claim_reminder_pushes() from public, anon, authenticated;
grant execute on function public.claim_reminder_pushes() to service_role;

-- Same as 202610170010_scheduled_messages, and it also wakes the Edge
-- Function for reminder pushes.
create or replace function public.run_later_dispatch()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  pushes_waiting boolean;
  functions_url text;
  dispatch_secret text;
begin
  perform public.dispatch_due_scheduled_messages();

  -- Dismissed reminders go after a month.
  delete from public.message_reminders r
  where r.dismissed_at < now() - interval '30 days';

  select exists (
    select 1
    from public.scheduled_messages s
    where s.status = 'sent'
      and s.push_claimed_at is null
      and s.sent_at > now() - interval '15 minutes'
  ) or exists (
    select 1
    from public.message_reminders r
    where r.push_claimed_at is null
      and r.dismissed_at is null
      and r.remind_at <= now()
      and r.remind_at > now() - interval '15 minutes'
  )
  into pushes_waiting;

  if not pushes_waiting then
    return;
  end if;

  begin
    select d.decrypted_secret
    into functions_url
    from vault.decrypted_secrets d
    where d.name = 'wecord_functions_url';
    select d.decrypted_secret
    into dispatch_secret
    from vault.decrypted_secrets d
    where d.name = 'wecord_dispatch_secret';

    if functions_url is null or dispatch_secret is null then
      return;
    end if;

    perform net.http_post(
      url := rtrim(functions_url, '/') || '/scheduled-dispatch',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || dispatch_secret
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 5000
    );
  exception when others then
    -- No Vault or pg_net here: the messages are sent, only the push waits.
    null;
  end;
end;
$$;

revoke execute on function public.run_later_dispatch() from public, anon, authenticated;
grant execute on function public.run_later_dispatch() to service_role;
