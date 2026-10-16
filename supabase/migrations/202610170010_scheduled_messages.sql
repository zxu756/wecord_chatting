-- Scheduled send: write a message now, have it sent later.
--
-- * scheduled_messages: the owner's queued text messages (RLS: owner only
--   for select, insert, update and delete). A trigger keeps clients to
--   what they may do: queue a message for a conversation they can send in,
--   change its text or time, or put a failed one back to pending. Sending,
--   failing and pruning belong to the functions below.
-- * deliver_scheduled_message sends one due message as its owner through
--   send_text_message (202610160047), so it goes through exactly the checks
--   of a normal send: membership, blocks, send_messages permission, bans and
--   timeouts, slowmode and AutoMod all run in the messages triggers. The
--   scheduled row's id is the message's client_id, so a retry after a crash
--   cannot send twice. Slowmode puts the message back for later (up to 5
--   times); any other refusal marks it failed with the reason, which the
--   owner sees in the conversation's Scheduled list.
-- * dispatch_due_scheduled_messages sends everything due; run_later_dispatch
--   is what the one-minute cron job calls: it dispatches, then (when
--   something still needs a push) pings the scheduled-dispatch Edge
--   Function through pg_net with the secret kept in Supabase Vault. The
--   Edge Function claims the pending pushes (claim_scheduled_message_pushes)
--   and pushes them the way the push function does for a message the
--   client just sent. Messages are delivered even when pg_net, the Vault
--   secrets or the Edge Function are missing; only the push then waits.
-- * send_scheduled_message_now sends the caller's queued message at once
--   ("Send now"); the client then asks the push function to push it.
-- * install_later_dispatch_schedule creates the cron job when pg_cron is
--   there. See the end of this file.

create table if not exists public.scheduled_messages (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  body text not null,
  mentions jsonb not null default '[]'::jsonb,
  send_at timestamptz not null,
  status text not null default 'pending',
  attempts integer not null default 0,
  last_error text,
  sent_message_id uuid references public.messages(id) on delete set null,
  sent_at timestamptz,
  push_claimed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scheduled_messages_status check (status in ('pending', 'sent', 'failed')),
  constraint scheduled_messages_body check (
    char_length(btrim(body)) > 0 and char_length(body) <= 4000
  ),
  constraint scheduled_messages_mentions_array check (jsonb_typeof(mentions) = 'array')
);

create index if not exists scheduled_messages_due_idx
  on public.scheduled_messages (send_at)
  where status = 'pending';

create index if not exists scheduled_messages_owner_idx
  on public.scheduled_messages (owner_id, conversation_id, send_at)
  where status in ('pending', 'failed');

create index if not exists scheduled_messages_push_idx
  on public.scheduled_messages (sent_at)
  where status = 'sent' and push_claimed_at is null;

alter table public.scheduled_messages enable row level security;

revoke all on public.scheduled_messages from anon;
grant select, insert, update, delete on public.scheduled_messages to authenticated;

drop policy if exists scheduled_messages_select_own on public.scheduled_messages;
create policy scheduled_messages_select_own
  on public.scheduled_messages for select
  to authenticated
  using (owner_id = auth.uid());

drop policy if exists scheduled_messages_insert_own on public.scheduled_messages;
create policy scheduled_messages_insert_own
  on public.scheduled_messages for insert
  to authenticated
  with check (
    owner_id = auth.uid()
    and public.can_current_user_send_in_conversation(conversation_id)
  );

drop policy if exists scheduled_messages_update_own on public.scheduled_messages;
create policy scheduled_messages_update_own
  on public.scheduled_messages for update
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists scheduled_messages_delete_own on public.scheduled_messages;
create policy scheduled_messages_delete_own
  on public.scheduled_messages for delete
  to authenticated
  using (owner_id = auth.uid());

-- What clients (the authenticated role) may write. The delivery functions
-- run as their owner and are not held to this.
create or replace function public.scheduled_messages_guard()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  pending_count integer;
begin
  new.updated_at := now();

  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.status := 'pending';
    new.attempts := 0;
    new.last_error := null;
    new.sent_message_id := null;
    new.sent_at := null;
    new.push_claimed_at := null;
    new.body := btrim(new.body);

    select count(*)
    into pending_count
    from public.scheduled_messages s
    where s.owner_id = new.owner_id
      and s.status = 'pending';
    if pending_count >= 100 then
      raise exception 'Too many scheduled messages' using errcode = '53400';
    end if;
  else
    if new.owner_id is distinct from old.owner_id
      or new.conversation_id is distinct from old.conversation_id
      or new.sent_message_id is distinct from old.sent_message_id
      or new.sent_at is distinct from old.sent_at
      or new.push_claimed_at is distinct from old.push_claimed_at
    then
      raise exception 'Scheduled message fields are read only' using errcode = '42501';
    end if;
    if old.status = 'sent' then
      raise exception 'Scheduled message was already sent' using errcode = '22023';
    end if;
    -- Editing a message puts it (back) in the queue.
    new.status := 'pending';
    new.attempts := 0;
    new.last_error := null;
    new.body := btrim(new.body);
  end if;

  if new.send_at < now() - interval '1 minute' then
    raise exception 'Scheduled time is in the past' using errcode = '22023';
  end if;
  if new.send_at > now() + interval '1 year' then
    raise exception 'Scheduled time is too far away' using errcode = '22023';
  end if;
  return new;
end;
$$;

drop trigger if exists scheduled_messages_guard on public.scheduled_messages;
create trigger scheduled_messages_guard
  before insert or update on public.scheduled_messages
  for each row execute function public.scheduled_messages_guard();

-- Sends one pending scheduled message as its owner. Returns the sent
-- message's id, or null when it was not sent (not pending, put back for
-- later, or failed).
create or replace function public.deliver_scheduled_message(p_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  scheduled public.scheduled_messages%rowtype;
  sent_id uuid;
  previous_sub text := coalesce(current_setting('request.jwt.claim.sub', true), '');
  previous_claims text := coalesce(current_setting('request.jwt.claims', true), '');
  error_text text;
  error_detail text;
  error_state text;
  wait_seconds integer;
  notice jsonb;
begin
  select s.*
  into scheduled
  from public.scheduled_messages s
  where s.id = p_id
    and s.status = 'pending'
  for update skip locked;

  if not found then
    return null;
  end if;

  -- Send as the owner: auth.uid() reads these.
  perform set_config('request.jwt.claim.sub', scheduled.owner_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', scheduled.owner_id, 'role', 'authenticated')::text,
    true
  );

  begin
    sent_id := public.send_text_message(
      scheduled.conversation_id,
      scheduled.body,
      null,
      null,
      scheduled.mentions,
      scheduled.id
    );

    if sent_id is not null then
      update public.scheduled_messages s
      set status = 'sent',
          sent_message_id = sent_id,
          sent_at = now(),
          last_error = null
      where s.id = scheduled.id;
    else
      -- AutoMod dropped it and left a note of why.
      delete from public.circle_automod_notices n
      where n.user_id = scheduled.owner_id
        and n.conversation_id = scheduled.conversation_id
      returning jsonb_build_object('rule_name', n.rule_name, 'reason', n.reason)
      into notice;

      update public.scheduled_messages s
      set status = 'failed',
          attempts = s.attempts + 1,
          last_error = 'automod:' || coalesce(notice->>'reason', notice->>'rule_name', '')
      where s.id = scheduled.id;
    end if;
  exception when others then
    get stacked diagnostics
      error_text = message_text,
      error_detail = pg_exception_detail,
      error_state = returned_sqlstate;

    wait_seconds := substring(coalesce(error_detail, '') from 'slowmode_remaining_seconds=(\d+)')::integer;
    if error_state = 'P0001' and wait_seconds is not null and scheduled.attempts < 5 then
      update public.scheduled_messages s
      set send_at = now() + make_interval(secs => wait_seconds + 5),
          attempts = s.attempts + 1,
          last_error = null
      where s.id = scheduled.id;
    else
      update public.scheduled_messages s
      set status = 'failed',
          attempts = s.attempts + 1,
          last_error = left(coalesce(error_text, 'error'), 300)
      where s.id = scheduled.id;
    end if;
    sent_id := null;
  end;

  perform set_config('request.jwt.claim.sub', previous_sub, true);
  perform set_config('request.jwt.claims', previous_claims, true);
  return sent_id;
end;
$$;

revoke execute on function public.deliver_scheduled_message(uuid) from public, anon, authenticated;
grant execute on function public.deliver_scheduled_message(uuid) to service_role;

-- "Send now" for the caller's own queued (or failed) message.
create or replace function public.send_scheduled_message_now(p_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  scheduled public.scheduled_messages%rowtype;
  sent_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select s.*
  into scheduled
  from public.scheduled_messages s
  where s.id = p_id
    and s.owner_id = auth.uid();
  if not found then
    raise exception 'Scheduled message not found' using errcode = 'P0002';
  end if;
  if scheduled.status = 'sent' then
    return scheduled.sent_message_id;
  end if;

  update public.scheduled_messages s
  set status = 'pending', attempts = 0, last_error = null
  where s.id = p_id;

  sent_id := public.deliver_scheduled_message(p_id);
  if sent_id is null then
    select s.* into scheduled from public.scheduled_messages s where s.id = p_id;
    -- Slowmode and the like: tell the caller why, as a normal send would.
    raise exception '%', coalesce(scheduled.last_error, 'Could not send message')
      using errcode = 'P0001';
  end if;
  return sent_id;
end;
$$;

revoke execute on function public.send_scheduled_message_now(uuid) from public, anon;
grant execute on function public.send_scheduled_message_now(uuid) to authenticated;

-- Sends everything that is due. Returns how many went out.
create or replace function public.dispatch_due_scheduled_messages(p_limit integer default 200)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  due record;
  delivered integer := 0;
begin
  for due in
    select s.id
    from public.scheduled_messages s
    where s.status = 'pending'
      and s.send_at <= now()
    order by s.send_at
    limit greatest(1, least(coalesce(p_limit, 200), 1000))
    for update skip locked
  loop
    if public.deliver_scheduled_message(due.id) is not null then
      delivered := delivered + 1;
    end if;
  end loop;

  -- Sent and failed entries stay a while so the owner can see them.
  delete from public.scheduled_messages s
  where (s.status = 'sent' and s.sent_at < now() - interval '3 days')
     or (s.status = 'failed' and s.updated_at < now() - interval '30 days');

  return delivered;
end;
$$;

revoke execute on function public.dispatch_due_scheduled_messages(integer) from public, anon, authenticated;
grant execute on function public.dispatch_due_scheduled_messages(integer) to service_role;

-- Scheduled messages that went out and still need their push: marked
-- claimed here, so each is pushed at most once. The Edge Function then
-- asks claim_push_delivery (which checks the sender) as for any message.
create or replace function public.claim_scheduled_message_pushes()
returns table (message_id uuid, sender_id uuid)
language sql
security definer
set search_path = public
as $$
  update public.scheduled_messages s
  set push_claimed_at = now()
  where s.status = 'sent'
    and s.push_claimed_at is null
    and s.sent_message_id is not null
    and s.sent_at > now() - interval '15 minutes'
  returning s.sent_message_id, s.owner_id;
$$;

revoke execute on function public.claim_scheduled_message_pushes() from public, anon, authenticated;
grant execute on function public.claim_scheduled_message_pushes() to service_role;

-- The cron job's one call, every minute: deliver what is due, then wake the
-- scheduled-dispatch Edge Function when pushes are waiting. The function
-- URL and the shared secret come from Supabase Vault:
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1', 'wecord_functions_url');
--   select vault.create_secret('<random string>', 'wecord_dispatch_secret');
-- (the same string is the Edge Function's DISPATCH_SECRET).
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

  select exists (
    select 1
    from public.scheduled_messages s
    where s.status = 'sent'
      and s.push_claimed_at is null
      and s.sent_at > now() - interval '15 minutes'
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

-- Creates (or replaces) the one-minute cron job when pg_cron is available.
-- Run `select public.install_later_dispatch_schedule();` again after
-- enabling pg_cron (and pg_net) in the dashboard if this migration found
-- them missing.
create or replace function public.install_later_dispatch_schedule()
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return 'pg_cron is not enabled';
  end if;
  perform cron.schedule(
    'wecord-later-dispatch',
    '* * * * *',
    'select public.run_later_dispatch()'
  );
  return 'scheduled';
end;
$$;

revoke execute on function public.install_later_dispatch_schedule() from public, anon, authenticated;
grant execute on function public.install_later_dispatch_schedule() to service_role;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    begin
      create extension if not exists pg_cron;
    exception when others then
      raise notice 'Could not enable pg_cron: %', sqlerrm;
    end;
  end if;
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    begin
      create extension if not exists pg_net;
    exception when others then
      raise notice 'Could not enable pg_net: %', sqlerrm;
    end;
  end if;
  raise notice 'Later dispatch schedule: %', public.install_later_dispatch_schedule();
exception when others then
  raise notice 'Could not schedule the later dispatch: %', sqlerrm;
end;
$$;
