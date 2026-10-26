-- Away auto-reply (roadmap A8, part 2 of 4): "I'm away" answered for you.
--
-- Where it lives: the settings are columns of user_notification_settings (the
-- A4 table; owner only), written through set_away_reply():
--     away_enabled           the switch
--     away_message           what is said (at most 500 characters)
--     away_until             when it turns itself off (null: until switched
--                            off by hand)
--     away_in_quiet_hours    also answer while the person's quiet hours (A4)
--                            are on, even with the switch off
--
-- Who is answered, and when (messages_zz_away_reply, an AFTER INSERT trigger
-- on messages that runs after the other triggers so the reply is the chat's
-- last message):
--   * only in a direct chat of two people, and only a message a person wrote:
--     not a system notice, not a webhook or bot message, not one under AI
--     review or recalled, and never an auto-reply (so two people who both have
--     the reply on cannot answer each other forever);
--   * the sender must be a friend of the away person, not blocked either way,
--     not a bot and not a deleted account; the away person must not be
--     deleted either;
--   * at most once per person in 24 hours (away_reply_log), and at most 300
--     auto-replies a day in all for one away person;
--   * never in groups, circle channels or threads, and never in a note to
--     self (one member).
-- The reply is an ordinary text message from the away person with
-- messages.auto_reply = true (the app labels it "Auto-reply"). It is never
-- silent, even when the message it answers was sent silently, so it rings like
-- any message. Clients cannot set or change auto_reply; only this trigger can.
--
-- Push: claim_away_reply_pushes() hands the scheduled-dispatch Edge Function
-- the replies it has not pushed, the same way scheduled messages are, and the
-- function then asks claim_push_delivery as for any message (so mutes, Do Not
-- Disturb, blocks, locked chats and the push language apply unchanged). The
-- trigger wakes the function; a minute-by-minute pg_cron job of its own wakes
-- it again when something is still waiting, and trims the log after three
-- days. run_later_dispatch() is not touched.

-- ------------------------------------------------------------- settings

alter table public.user_notification_settings
  add column if not exists away_enabled boolean not null default false,
  add column if not exists away_message text,
  add column if not exists away_until timestamptz,
  add column if not exists away_in_quiet_hours boolean not null default false;

alter table public.user_notification_settings
  drop constraint if exists user_notification_settings_away_message_check;
alter table public.user_notification_settings
  add constraint user_notification_settings_away_message_check
  check (
    away_message is null
    or char_length(btrim(away_message)) between 1 and 500
  );

-- ------------------------------------------------------ the auto-reply flag

alter table public.messages
  add column if not exists auto_reply boolean not null default false;

-- Only the trigger below makes an auto-reply: a signed-in client cannot claim
-- its own message is one, and the flag does not change after.
create or replace function public.messages_guard_auto_reply()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.auto_reply and current_user in ('authenticated', 'anon') then
      raise exception 'Auto-replies are made by the server'
        using errcode = '42501';
    end if;
  else
    new.auto_reply := old.auto_reply;
  end if;
  return new;
end;
$$;

revoke execute on function public.messages_guard_auto_reply()
  from public, anon, authenticated;

drop trigger if exists messages_guard_auto_reply on public.messages;
create trigger messages_guard_auto_reply
  before insert on public.messages
  for each row execute function public.messages_guard_auto_reply();

drop trigger if exists messages_auto_reply_unchanged on public.messages;
create trigger messages_auto_reply_unchanged
  before update of auto_reply on public.messages
  for each row execute function public.messages_guard_auto_reply();

-- ------------------------------------------------------------ the log

create table if not exists public.away_reply_log (
  id uuid primary key default gen_random_uuid(),
  away_user_id uuid not null references public.profiles(id) on delete cascade,
  to_user_id uuid not null references public.profiles(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  message_id uuid references public.messages(id) on delete set null,
  replied_at timestamptz not null default now(),
  push_claimed_at timestamptz
);

create index if not exists away_reply_log_pair_idx
  on public.away_reply_log (away_user_id, to_user_id, replied_at desc);
create index if not exists away_reply_log_unpushed_idx
  on public.away_reply_log (replied_at)
  where push_claimed_at is null and message_id is not null;

-- Server only: nobody reads or writes it from a client.
alter table public.away_reply_log enable row level security;
revoke all on public.away_reply_log from anon, authenticated;

-- ------------------------------------------------------------- the rule

-- Whether [target_user_id]'s auto-reply is on at [at]: the switch with its
-- end time, or quiet hours when the person asked for those. A blank message
-- never counts.
create or replace function public.away_reply_active(
  target_user_id uuid,
  at timestamptz default now()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select nullif(btrim(coalesce(s.away_message, '')), '') is not null
        and (
          (s.away_enabled and (s.away_until is null or s.away_until > at))
          or (
            s.away_in_quiet_hours
            and public.in_quiet_hours(s.user_id, at)
          )
        )
      from public.user_notification_settings s
      where s.user_id = target_user_id
    ),
    false
  );
$$;

revoke execute on function public.away_reply_active(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.away_reply_active(uuid, timestamptz)
  to service_role;

-- Switches the auto-reply on or off and sets what it says. Returns what is
-- stored. While it is off the message is kept for next time.
create or replace function public.set_away_reply(
  enabled boolean,
  message text,
  until_at timestamptz default null,
  during_quiet_hours boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  clean text := nullif(btrim(coalesce(message, '')), '');
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if clean is not null and char_length(clean) > 500 then
    raise exception 'The away message is too long' using errcode = '22023';
  end if;
  if (coalesce(enabled, false) or coalesce(during_quiet_hours, false))
    and clean is null
  then
    raise exception 'Write the away message first' using errcode = '22023';
  end if;
  if coalesce(enabled, false) and until_at is not null and until_at <= now()
  then
    raise exception 'The end time is already past' using errcode = '22023';
  end if;

  insert into public.user_notification_settings as s (
    user_id, away_enabled, away_message, away_until, away_in_quiet_hours
  )
  values (
    me,
    coalesce(enabled, false),
    clean,
    case when coalesce(enabled, false) then until_at end,
    coalesce(during_quiet_hours, false)
  )
  on conflict (user_id) do update
  set away_enabled = excluded.away_enabled,
      away_message = excluded.away_message,
      away_until = excluded.away_until,
      away_in_quiet_hours = excluded.away_in_quiet_hours;

  return jsonb_build_object(
    'enabled', coalesce(enabled, false),
    'message', clean,
    'until', case when coalesce(enabled, false) then until_at end,
    'during_quiet_hours', coalesce(during_quiet_hours, false)
  );
end;
$$;

revoke execute on function public.set_away_reply(boolean, text, timestamptz, boolean)
  from public, anon;
grant execute on function public.set_away_reply(boolean, text, timestamptz, boolean)
  to authenticated;

-- ------------------------------------------------------------ the trigger

create or replace function public.messages_send_away_reply()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  conversation_kind text;
  member_ids uuid[];
  away_id uuid;
  reply_text text;
  sender_is_bot boolean;
  sender_gone timestamptz;
  away_gone timestamptz;
  reply_id uuid;
  was_silent text;
begin
  if new.auto_reply
    or new.type = 'system'
    or new.sender_id is null
    or new.webhook_id is not null
    or new.recalled_at is not null
    or new.review_state is not null
  then
    return new;
  end if;

  select c.type into conversation_kind
  from public.conversations c
  where c.id = new.conversation_id;
  if conversation_kind is distinct from 'direct' then
    return new;
  end if;

  select array_agg(cm.user_id) into member_ids
  from public.conversation_members cm
  where cm.conversation_id = new.conversation_id;
  if coalesce(cardinality(member_ids), 0) <> 2
    or not (new.sender_id = any(member_ids))
  then
    return new;
  end if;
  away_id := (
    select m from unnest(member_ids) m where m <> new.sender_id limit 1
  );

  -- Cheap exit: nearly everyone has no auto-reply.
  if not public.away_reply_active(away_id, now()) then
    return new;
  end if;

  select p.is_bot, p.deleted_at into sender_is_bot, sender_gone
  from public.profiles p
  where p.id = new.sender_id;
  select p.deleted_at into away_gone
  from public.profiles p
  where p.id = away_id;
  if coalesce(sender_is_bot, true)
    or sender_gone is not null
    or away_gone is not null
  then
    return new;
  end if;

  -- Friends only, and nobody who is blocked either way.
  if not exists (
    select 1
    from public.friendships f
    where f.user_low_id = least(new.sender_id, away_id)
      and f.user_high_id = greatest(new.sender_id, away_id)
  ) or public.are_users_blocked(new.sender_id, away_id) then
    return new;
  end if;

  -- One reply per person in 24 hours, and a ceiling for the away person.
  perform pg_advisory_xact_lock(
    hashtextextended('away-reply:' || away_id::text || ':' || new.sender_id::text, 0)
  );
  if exists (
    select 1
    from public.away_reply_log l
    where l.away_user_id = away_id
      and l.to_user_id = new.sender_id
      and l.replied_at > now() - interval '24 hours'
  ) then
    return new;
  end if;
  if (
    select count(*)
    from public.away_reply_log l
    where l.away_user_id = away_id
      and l.replied_at > now() - interval '24 hours'
  ) >= 300 then
    return new;
  end if;

  select s.away_message into reply_text
  from public.user_notification_settings s
  where s.user_id = away_id;

  -- A message sent silently must not make its answer silent.
  was_silent := current_setting('wecord.send_silent', true);
  perform set_config('wecord.send_silent', 'off', true);

  insert into public.messages (
    conversation_id, sender_id, type, body, auto_reply, created_at
  )
  values (
    new.conversation_id,
    away_id,
    'text',
    reply_text,
    true,
    greatest(clock_timestamp(), new.created_at + interval '1 millisecond')
  )
  returning id into reply_id;

  perform set_config('wecord.send_silent', coalesce(was_silent, 'off'), true);

  if reply_id is null then
    return new;
  end if;

  insert into public.away_reply_log (
    away_user_id, to_user_id, conversation_id, message_id
  )
  values (away_id, new.sender_id, new.conversation_id, reply_id);

  perform public.wake_scheduled_dispatch();
  return new;
end;
$$;

revoke execute on function public.messages_send_away_reply()
  from public, anon, authenticated;

-- Named to sort after the triggers that update the chat's last message, so the
-- auto-reply is the last message.
drop trigger if exists messages_zz_away_reply on public.messages;
create trigger messages_zz_away_reply
  after insert on public.messages
  for each row
  when (not new.auto_reply and new.type <> 'system')
  execute function public.messages_send_away_reply();

-- --------------------------------------------------------------- the push

-- Replies that still need their push: marked claimed here, so each is pushed
-- at most once. The Edge Function then asks claim_push_delivery.
create or replace function public.claim_away_reply_pushes()
returns table (message_id uuid, sender_id uuid)
language sql
security definer
set search_path = public
as $$
  update public.away_reply_log l
  set push_claimed_at = now()
  where l.push_claimed_at is null
    and l.message_id is not null
    and l.replied_at > now() - interval '15 minutes'
  returning l.message_id, l.away_user_id;
$$;

revoke execute on function public.claim_away_reply_pushes()
  from public, anon, authenticated;
grant execute on function public.claim_away_reply_pushes() to service_role;

-- The cron job's one call: wake the dispatcher while a reply waits for its
-- push, and forget log rows older than three days (the 24 hour rule needs
-- only the last day).
create or replace function public.wake_away_reply_dispatch()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.away_reply_log l
  where l.replied_at < now() - interval '3 days';

  if exists (
    select 1
    from public.away_reply_log l
    where l.push_claimed_at is null
      and l.message_id is not null
      and l.replied_at > now() - interval '15 minutes'
  ) then
    perform public.wake_scheduled_dispatch();
  end if;
end;
$$;

revoke execute on function public.wake_away_reply_dispatch()
  from public, anon, authenticated;
grant execute on function public.wake_away_reply_dispatch() to service_role;

create or replace function public.install_away_reply_schedule()
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return 'pg_cron is not enabled';
  end if;
  perform cron.unschedule(jobid)
  from cron.job
  where jobname = 'wecord-away-reply-push';
  perform cron.schedule(
    'wecord-away-reply-push',
    '* * * * *',
    'select public.wake_away_reply_dispatch()'
  );
  return 'scheduled';
end;
$$;

revoke execute on function public.install_away_reply_schedule()
  from public, anon, authenticated;
grant execute on function public.install_away_reply_schedule() to service_role;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    begin
      create extension if not exists pg_cron;
    exception when others then
      raise notice 'Could not enable pg_cron: %', sqlerrm;
    end;
  end if;
  perform public.install_away_reply_schedule();
exception when others then
  raise notice 'Could not schedule the away reply job: %', sqlerrm;
end;
$$;
