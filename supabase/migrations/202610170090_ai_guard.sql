-- AI guard for new members: an opt-in check of the first messages a new
-- member sends in a circle, before the others see them.
--
-- Part 1 of 2 (202610170091_ai_guard_hidden.sql hides held messages from
-- everything that reads messages for other people).
--
-- * circle_ai_guard: one row per circle that configured the guard (managers
--   only, through get_circle_ai_guard / set_circle_ai_guard, audited as
--   guard_update). Off unless enabled; works only while the circle's AI
--   switch (circles.ai_enabled, 202610170031) is on. Who counts as new: the
--   member joined less than 1, 3 or 7 days ago, or has fewer than N visible
--   messages in the circle. The action is "hold" (a flagged message stays
--   hidden until a moderator decides) or "flag" (a flagged message is
--   released with a flag for the moderators).
-- * messages.review_state: null (everyone sees the message), 'checking'
--   (waiting for the AI), 'held' (the AI flagged it; hidden) or 'removed'
--   (a moderator removed a held message; stays hidden). A hidden message is
--   visible to its author and to members who moderate the channel
--   (manage_messages); 202610170091 changes the select policy and every
--   function that reads messages for other people. The server alone sets
--   it: a BEFORE INSERT trigger (so every way of sending is covered,
--   including scheduled sends) decides, and a client cannot send a value.
-- * The check is woken by the database, not by the client. An AFTER INSERT
--   trigger records the message in message_reviews and posts to the `ai`
--   Edge Function through pg_net ({action: 'guard', message_id}) with the
--   shared secret in Supabase Vault (wecord_functions_url,
--   wecord_dispatch_secret: the same ones scheduled-dispatch uses). So it
--   starts the moment the message is stored, needs no cron delay, and a
--   client that never calls anything cannot skip it. The function claims
--   the message (ai_guard_claim), counts the request against the circle
--   (ai_consume_circle_request, not the member), classifies the text and
--   answers with finish_message_review, which releases or holds it.
-- * Fail open: when pg_net / Vault / the function cannot be reached, the AI
--   is not set up, the circle's daily limit is reached, the provider fails
--   or times out, the message is released and recorded as 'not_checked'
--   with the reason. Whatever happens, run_ai_guard_sweep (every minute,
--   pg_cron) releases checks older than a minute as 'not_checked'. AutoMod
--   keeps working on its own: its triggers run first and may still block
--   the message.
-- * Releasing makes the message normal: review_state goes back to null, its
--   time moves to now when it waited more than a few seconds (so it lands
--   at the end of the chat and counts as unread for those who read on), the
--   conversation's and thread's latest message are updated, and the push
--   is queued (message_reviews.push_pending). scheduled-dispatch claims it
--   with claim_released_message_pushes and pushes through
--   claim_push_delivery, so nobody is notified while it is held.
-- * Moderators decide in the circle's Review queue: list_message_reviews,
--   count_message_reviews and decide_message_review ('approve' or
--   'remove'), audited as guard_approve / guard_remove. The AI's own holds
--   and flags are audited as guard_hold / guard_flag without an actor.
-- * ai_circle_usage counts the guard's AI requests per circle and day
--   (the `ai` function's AI_GUARD_DAILY_LIMIT_PER_CIRCLE).

-- ---------------------------------------------------------------- settings

create table if not exists public.circle_ai_guard (
  circle_id uuid primary key references public.circles(id) on delete cascade,
  enabled boolean not null default false,
  new_rule text not null default 'joined_days',
  joined_days integer not null default 3,
  message_count integer not null default 10,
  action text not null default 'hold',
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint circle_ai_guard_rule check (new_rule in ('joined_days', 'message_count')),
  constraint circle_ai_guard_days check (joined_days in (1, 3, 7)),
  constraint circle_ai_guard_messages check (message_count between 1 and 200),
  constraint circle_ai_guard_action check (action in ('hold', 'flag'))
);

alter table public.circle_ai_guard enable row level security;
revoke all on public.circle_ai_guard from anon, authenticated;

alter table public.messages
  add column if not exists review_state text;

alter table public.messages
  drop constraint if exists messages_review_state_check;
alter table public.messages
  add constraint messages_review_state_check
  check (review_state in ('checking', 'held', 'removed'));

create index if not exists messages_review_state_idx
  on public.messages (created_at)
  where review_state is not null;

create table if not exists public.message_reviews (
  message_id uuid primary key references public.messages(id) on delete cascade,
  circle_id uuid not null references public.circles(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  mode text not null,
  -- checking: waiting for the AI. held / flagged: the AI flagged it and a
  -- moderator has yet to decide (held is hidden, flagged is visible).
  -- released: allowed, or not checked. approved / removed: a moderator's
  -- decision.
  state text not null default 'checking',
  verdict text,
  reason text,
  unchecked_reason text,
  created_at timestamptz not null default now(),
  check_started_at timestamptz,
  checked_at timestamptz,
  released_at timestamptz,
  decided_at timestamptz,
  decided_by uuid references public.profiles(id) on delete set null,
  push_pending boolean not null default false,
  constraint message_reviews_mode check (mode in ('hold', 'flag')),
  constraint message_reviews_state check (
    state in ('checking', 'held', 'flagged', 'released', 'approved', 'removed')
  ),
  constraint message_reviews_verdict check (
    verdict is null
    or verdict in ('allow', 'spam', 'scam', 'harassment', 'sexual', 'other', 'not_checked')
  ),
  constraint message_reviews_unchecked check (
    unchecked_reason is null
    or unchecked_reason in ('not_configured', 'ai_off', 'limit', 'error', 'timeout', 'unavailable')
  )
);

create index if not exists message_reviews_queue_idx
  on public.message_reviews (circle_id, created_at desc)
  where state in ('held', 'flagged');
create index if not exists message_reviews_checking_idx
  on public.message_reviews (created_at)
  where state = 'checking';
create index if not exists message_reviews_push_idx
  on public.message_reviews (released_at)
  where push_pending;

alter table public.message_reviews enable row level security;
revoke all on public.message_reviews from anon, authenticated;
grant select on public.message_reviews to authenticated;

-- Moderators of the channel see the review rows (so the queue and its badge
-- can follow them in realtime); the AI's reason is not for the author.
drop policy if exists message_reviews_select_moderator on public.message_reviews;
create policy message_reviews_select_moderator
  on public.message_reviews for select
  to authenticated
  using (
    state in ('held', 'flagged')
    and public.can_current_user_moderate_messages(conversation_id)
  );

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'message_reviews'
    )
  then
    alter publication supabase_realtime add table public.message_reviews;
  end if;
end $$;

create table if not exists public.ai_circle_usage (
  circle_id uuid not null references public.circles(id) on delete cascade,
  day date not null default ((now() at time zone 'utc')::date),
  requests integer not null default 0 check (requests >= 0),
  updated_at timestamptz not null default now(),
  primary key (circle_id, day)
);

alter table public.ai_circle_usage enable row level security;
revoke all on public.ai_circle_usage from anon, authenticated;

-- Whether the current user sees a message that may be under review: its
-- author and the members who moderate its channel see it, nobody else.
create or replace function public.message_visible_to_current_user(
  message_review_state text,
  message_sender_id uuid,
  message_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select message_review_state is null
    or message_sender_id = auth.uid()
    or public.can_current_user_moderate_messages(message_conversation_id);
$$;

revoke execute on function public.message_visible_to_current_user(text, uuid, uuid) from public, anon;
grant execute on function public.message_visible_to_current_user(text, uuid, uuid) to authenticated;

-- The guard of a circle as the settings screen reads it. Managers only.
create or replace function public.get_circle_ai_guard(target_circle_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  guard public.circle_ai_guard%rowtype;
  circle_ai boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'Only members who manage the circle can see the AI guard'
      using errcode = '42501';
  end if;

  select c.ai_enabled into circle_ai from public.circles c where c.id = target_circle_id;
  if circle_ai is null then
    raise exception 'Circle not found' using errcode = 'P0002';
  end if;

  select g.* into guard from public.circle_ai_guard g where g.circle_id = target_circle_id;
  if guard.circle_id is null then
    guard.enabled := false;
    guard.new_rule := 'joined_days';
    guard.joined_days := 3;
    guard.message_count := 10;
    guard.action := 'hold';
  end if;

  return jsonb_build_object(
    'enabled', guard.enabled,
    'new_rule', guard.new_rule,
    'joined_days', guard.joined_days,
    'message_count', guard.message_count,
    'action', guard.action,
    'circle_ai_enabled', circle_ai
  );
end;
$$;

create or replace function public.set_circle_ai_guard(
  target_circle_id uuid,
  guard_enabled boolean,
  guard_new_rule text,
  guard_joined_days integer,
  guard_message_count integer,
  guard_action text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  old_guard jsonb;
  new_guard jsonb;
  circle_name text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'Only members who manage the circle can change the AI guard'
      using errcode = '42501';
  end if;
  if guard_enabled is null
    or guard_new_rule is null
    or guard_new_rule not in ('joined_days', 'message_count')
    or guard_joined_days is null
    or guard_joined_days not in (1, 3, 7)
    or guard_message_count is null
    or guard_message_count not between 1 and 200
    or guard_action is null
    or guard_action not in ('hold', 'flag')
  then
    raise exception 'Choose valid AI guard settings' using errcode = '22023';
  end if;

  select c.name into circle_name from public.circles c where c.id = target_circle_id for update;
  if circle_name is null then
    raise exception 'Circle not found' using errcode = 'P0002';
  end if;

  old_guard := public.get_circle_ai_guard(target_circle_id) - 'circle_ai_enabled';

  insert into public.circle_ai_guard as g (
    circle_id, enabled, new_rule, joined_days, message_count, action, updated_by, updated_at
  )
  values (
    target_circle_id, guard_enabled, guard_new_rule, guard_joined_days,
    guard_message_count, guard_action, auth.uid(), now()
  )
  on conflict (circle_id) do update
  set enabled = excluded.enabled,
    new_rule = excluded.new_rule,
    joined_days = excluded.joined_days,
    message_count = excluded.message_count,
    action = excluded.action,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at;

  new_guard := public.get_circle_ai_guard(target_circle_id);

  if old_guard is distinct from (new_guard - 'circle_ai_enabled') then
    perform public.write_circle_audit(
      target_circle_id,
      'guard_update',
      'circle',
      target_circle_id,
      circle_name,
      (
        select coalesce(jsonb_object_agg(
          n.key,
          jsonb_build_object('old', old_guard -> n.key, 'new', n.value)
        ), '{}'::jsonb)
        from jsonb_each(new_guard - 'circle_ai_enabled') n
        where old_guard -> n.key is distinct from n.value
      )
    );
  end if;

  return new_guard;
end;
$$;

revoke execute on function public.get_circle_ai_guard(uuid) from public, anon;
revoke execute on function public.set_circle_ai_guard(uuid, boolean, text, integer, integer, text) from public, anon;
grant execute on function public.get_circle_ai_guard(uuid) to authenticated;
grant execute on function public.set_circle_ai_guard(uuid, boolean, text, integer, integer, text) to authenticated;

-- ------------------------------------------------------------------- waking

-- Posts to one of the project's Edge Functions through pg_net with the
-- shared secret kept in Vault. False when pg_net, the Vault secrets or the
-- call are not there, so the caller can fail open.
create or replace function public.ai_guard_wake(function_name text, payload jsonb)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  functions_url text;
  dispatch_secret text;
begin
  select d.decrypted_secret into functions_url
  from vault.decrypted_secrets d
  where d.name = 'wecord_functions_url';
  select d.decrypted_secret into dispatch_secret
  from vault.decrypted_secrets d
  where d.name = 'wecord_dispatch_secret';

  if functions_url is null or dispatch_secret is null then
    return false;
  end if;

  perform net.http_post(
    url := rtrim(functions_url, '/') || '/' || function_name,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || dispatch_secret
    ),
    body := coalesce(payload, '{}'::jsonb),
    timeout_milliseconds := 10000
  );
  return true;
exception when others then
  return false;
end;
$$;

revoke execute on function public.ai_guard_wake(text, jsonb) from public, anon, authenticated;
grant execute on function public.ai_guard_wake(text, jsonb) to service_role;

-- ---------------------------------------------------------------- the check

-- BEFORE INSERT on messages, after AutoMod (triggers fire in name order, so
-- a message AutoMod drops never gets here). Decides whether the message
-- waits for the AI. Nothing a client sends for review_state counts.
create or replace function public.messages_review_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  channel_circle_id uuid;
  guard public.circle_ai_guard%rowtype;
  joined_at timestamptz;
  is_new boolean;
begin
  new.review_state := null;

  -- Only text can be read; the rest has nothing to classify.
  if new.type <> 'text'
    or btrim(coalesce(new.body, '')) = ''
    or new.webhook_id is not null
    or new.webhook_name is not null
  then
    return new;
  end if;

  -- Someone posing as another sender is refused by the insert policy.
  if auth.uid() is not null and new.sender_id is distinct from auth.uid() then
    return new;
  end if;

  select cc.circle_id
  into channel_circle_id
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(new.conversation_id);
  if channel_circle_id is null then
    return new;
  end if;

  select g.* into guard
  from public.circle_ai_guard g
  where g.circle_id = channel_circle_id and g.enabled;
  if guard.circle_id is null then
    return new;
  end if;

  -- The guard works only while the circle allows AI.
  if not exists (
    select 1 from public.circles c where c.id = channel_circle_id and c.ai_enabled
  ) then
    return new;
  end if;

  select cm.created_at into joined_at
  from public.circle_members cm
  where cm.circle_id = channel_circle_id and cm.user_id = new.sender_id;
  if joined_at is null then
    return new;
  end if;

  -- Bots, moderators, managers and the owner are never held.
  if exists (select 1 from public.profiles p where p.id = new.sender_id and p.is_bot)
    or public.circle_member_has_permission(channel_circle_id, new.sender_id, 'manage_messages')
    or public.circle_member_has_permission(channel_circle_id, new.sender_id, 'manage_circle')
  then
    return new;
  end if;

  if guard.new_rule = 'joined_days' then
    is_new := joined_at > now() - make_interval(days => guard.joined_days);
  else
    -- Messages that are visible and not deleted count; held, removed and
    -- deleted ones do not make a member trusted.
    is_new := (
      select count(*)
      from (
        select 1
        from public.messages m
        where m.sender_id = new.sender_id
          and m.recalled_at is null
          and m.review_state is null
          and m.conversation_id in (
            select cc.conversation_id
            from public.circle_channels cc
            where cc.circle_id = channel_circle_id
            union all
            select ct.conversation_id
            from public.conversation_threads ct
            join public.circle_channels cc
              on cc.conversation_id = ct.parent_conversation_id
            where cc.circle_id = channel_circle_id
          )
        limit guard.message_count
      ) counted
    ) < guard.message_count;
  end if;

  if is_new then
    new.review_state := 'checking';
  end if;
  return new;
end;
$$;

-- AFTER INSERT: records the check and wakes the `ai` function. Without a
-- way to wake it the message is released at once, not checked.
create or replace function public.messages_review_open()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  channel_circle_id uuid;
  guard_mode text;
begin
  select cc.circle_id
  into channel_circle_id
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(new.conversation_id);

  select g.action into guard_mode
  from public.circle_ai_guard g
  where g.circle_id = channel_circle_id;

  insert into public.message_reviews (
    message_id, circle_id, conversation_id, sender_id, mode
  )
  values (
    new.id, channel_circle_id, new.conversation_id, new.sender_id,
    coalesce(guard_mode, 'hold')
  );

  if not public.ai_guard_wake(
    'ai',
    jsonb_build_object('action', 'guard', 'message_id', new.id)
  ) then
    perform public.finish_message_review(new.id, 'not_checked', null, 'unavailable');
  end if;
  return null;
end;
$$;

-- BEFORE UPDATE OF body: a message cannot be edited into something the AI
-- has not seen while it waits for the check or for a moderator.
create or replace function public.messages_review_lock_edit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.review_state in ('checking', 'held')
    and new.body is distinct from old.body
    and new.recalled_at is null
    and new.review_state is not distinct from old.review_state
  then
    raise exception 'This message is waiting for review and cannot be edited'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function public.messages_review_guard() from public, anon, authenticated;
revoke execute on function public.messages_review_open() from public, anon, authenticated;
revoke execute on function public.messages_review_lock_edit() from public, anon, authenticated;

drop trigger if exists messages_review_guard on public.messages;
create trigger messages_review_guard
  before insert on public.messages
  for each row execute function public.messages_review_guard();

drop trigger if exists messages_review_open on public.messages;
create trigger messages_review_open
  after insert on public.messages
  for each row
  when (new.review_state = 'checking')
  execute function public.messages_review_open();

drop trigger if exists messages_review_lock_edit on public.messages;
create trigger messages_review_lock_edit
  before update of body on public.messages
  for each row execute function public.messages_review_lock_edit();

-- Claims a message for the `ai` function: its circle, text and whether the
-- circle still allows AI. Nothing when it is not waiting any more, or
-- another call claimed it in the last 45 seconds.
create or replace function public.ai_guard_claim(p_message_id uuid)
returns table (circle_id uuid, body text, ai_enabled boolean)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with claimed as (
    update public.message_reviews r
    set check_started_at = now()
    where r.message_id = p_message_id
      and r.state = 'checking'
      and (r.check_started_at is null or r.check_started_at < now() - interval '45 seconds')
    returning r.message_id, r.circle_id
  )
  select c.circle_id, m.body, ci.ai_enabled
  from claimed c
  join public.messages m on m.id = c.message_id
  join public.circles ci on ci.id = c.circle_id;
end;
$$;

-- The guard's AI requests, per circle and UTC day, with the limit given by
-- the caller (the AI_GUARD_DAILY_LIMIT_PER_CIRCLE secret).
create or replace function public.ai_consume_circle_request(
  p_circle_id uuid,
  p_limit integer
)
returns table (allowed boolean, used integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  today date := (now() at time zone 'utc')::date;
  new_count integer;
begin
  if p_circle_id is null or p_limit is null or p_limit < 1 then
    raise exception 'A circle and a positive limit are required' using errcode = '22023';
  end if;

  delete from public.ai_circle_usage u
  where u.circle_id = p_circle_id and u.day < today - 30;

  insert into public.ai_circle_usage as u (circle_id, day, requests)
  values (p_circle_id, today, 0)
  on conflict (circle_id, day) do nothing;

  update public.ai_circle_usage u
  set requests = u.requests + 1, updated_at = now()
  where u.circle_id = p_circle_id and u.day = today and u.requests < p_limit
  returning u.requests into new_count;

  if new_count is not null then
    return query select true, new_count;
  else
    return query
      select false, u.requests
      from public.ai_circle_usage u
      where u.circle_id = p_circle_id and u.day = today;
  end if;
end;
$$;

create or replace function public.ai_refund_circle_request(p_circle_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.ai_circle_usage u
  set requests = greatest(u.requests - 1, 0), updated_at = now()
  where u.circle_id = p_circle_id and u.day = (now() at time zone 'utc')::date;
$$;

-- Makes a held message normal: visible to everyone, at the end of the chat
-- when it waited, and the conversation's latest message again. Internal.
create or replace function public.ai_guard_release_message(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  msg public.messages%rowtype;
begin
  update public.messages m
  set
    review_state = null,
    created_at = case
      when clock_timestamp() - m.created_at > interval '3 seconds'
        then clock_timestamp()
      else m.created_at
    end
  where m.id = p_message_id
    and m.review_state in ('checking', 'held')
  returning m.* into msg;

  if msg.id is null then
    return;
  end if;

  update public.conversations c
  set
    last_message_id = msg.id,
    last_message_at = msg.created_at,
    updated_at = now()
  where c.id = msg.conversation_id
    and (c.last_message_at is null or c.last_message_at <= msg.created_at);

  update public.conversation_threads ct
  set last_message_at = msg.created_at, archived_at = null
  where ct.conversation_id = msg.conversation_id
    and (ct.last_message_at is null or ct.last_message_at <= msg.created_at);
end;
$$;

-- The AI's answer (or its absence) for a message that waits for it.
-- p_verdict is allow, one of the categories, or not_checked (with the
-- reason in p_unchecked_reason). Returns the review's new state, or null
-- when nothing was waiting.
create or replace function public.finish_message_review(
  p_message_id uuid,
  p_verdict text,
  p_reason text default null,
  p_unchecked_reason text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  review public.message_reviews%rowtype;
  new_state text;
  flagged boolean;
  clean_reason text := nullif(left(btrim(coalesce(p_reason, '')), 240), '');
  channel public.circle_channels%rowtype;
begin
  if p_verdict is null
    or p_verdict not in ('allow', 'spam', 'scam', 'harassment', 'sexual', 'other', 'not_checked')
  then
    raise exception 'Unknown verdict' using errcode = '22023';
  end if;

  select r.* into review
  from public.message_reviews r
  where r.message_id = p_message_id and r.state = 'checking'
  for update;
  if review.message_id is null then
    return null;
  end if;

  flagged := p_verdict not in ('allow', 'not_checked');

  if flagged and review.mode = 'hold' then
    update public.messages m set review_state = 'held' where m.id = p_message_id;
    new_state := 'held';
  else
    perform public.ai_guard_release_message(p_message_id);
    new_state := case when flagged then 'flagged' else 'released' end;
  end if;

  update public.message_reviews r
  set
    state = new_state,
    verdict = p_verdict,
    reason = case when flagged then clean_reason end,
    unchecked_reason = case
      when p_verdict = 'not_checked' then coalesce(p_unchecked_reason, 'error')
    end,
    checked_at = now(),
    released_at = case when new_state in ('released', 'flagged') then now() end,
    push_pending = new_state in ('released', 'flagged')
  where r.message_id = p_message_id;

  if flagged then
    select cc.* into channel
    from public.circle_channels cc
    where cc.id = public.conversation_circle_channel_id(review.conversation_id);

    insert into public.circle_audit_log (
      circle_id, actor_id, action, target_type, target_id, target_label, changes
    )
    values (
      review.circle_id,
      null,
      case when new_state = 'held' then 'guard_hold' else 'guard_flag' end,
      'message',
      p_message_id,
      public.circle_member_label(review.circle_id, review.sender_id),
      jsonb_strip_nulls(jsonb_build_object(
        'verdict', p_verdict,
        'reason', clean_reason,
        'author_id', review.sender_id,
        'channel_id', channel.id,
        'channel_name', channel.name
      ))
    );
  end if;

  if new_state in ('released', 'flagged') then
    -- Push it now; the sweep tries again when this call is lost.
    perform public.ai_guard_wake('scheduled-dispatch', '{}'::jsonb);
  end if;

  return new_state;
end;
$$;

-- Released messages that still need their push, for scheduled-dispatch
-- (the message and its sender, like claim_scheduled_message_pushes).
create or replace function public.claim_released_message_pushes()
returns table (message_id uuid, sender_id uuid)
language sql
security definer
set search_path = public
as $$
  update public.message_reviews r
  set push_pending = false
  where r.push_pending
    and r.released_at > now() - interval '1 hour'
  returning r.message_id, r.sender_id;
$$;

-- Every minute: gives up on checks that never came back (released, not
-- checked) and wakes the pusher for releases whose wake-up was lost.
create or replace function public.run_ai_guard_sweep()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  stale uuid;
begin
  for stale in
    select r.message_id
    from public.message_reviews r
    where r.state = 'checking'
      and r.created_at < now() - interval '60 seconds'
    order by r.created_at
    limit 200
  loop
    perform public.finish_message_review(stale, 'not_checked', null, 'timeout');
  end loop;

  update public.message_reviews r
  set push_pending = false
  where r.push_pending and r.released_at <= now() - interval '1 hour';

  if exists (
    select 1
    from public.message_reviews r
    where r.push_pending
      and r.released_at <= now() - interval '20 seconds'
  ) then
    perform public.ai_guard_wake('scheduled-dispatch', '{}'::jsonb);
  end if;
end;
$$;

revoke execute on function public.ai_guard_claim(uuid) from public, anon, authenticated;
revoke execute on function public.ai_consume_circle_request(uuid, integer) from public, anon, authenticated;
revoke execute on function public.ai_refund_circle_request(uuid) from public, anon, authenticated;
revoke execute on function public.ai_guard_release_message(uuid) from public, anon, authenticated;
revoke execute on function public.finish_message_review(uuid, text, text, text) from public, anon, authenticated;
revoke execute on function public.claim_released_message_pushes() from public, anon, authenticated;
revoke execute on function public.run_ai_guard_sweep() from public, anon, authenticated;
grant execute on function public.ai_guard_claim(uuid) to service_role;
grant execute on function public.ai_consume_circle_request(uuid, integer) to service_role;
grant execute on function public.ai_refund_circle_request(uuid) to service_role;
grant execute on function public.finish_message_review(uuid, text, text, text) to service_role;
grant execute on function public.claim_released_message_pushes() to service_role;
grant execute on function public.run_ai_guard_sweep() to service_role;

-- ---------------------------------------------------------- the review queue

-- The held and flagged messages of a circle that the caller moderates,
-- newest first.
create or replace function public.list_message_reviews(
  target_circle_id uuid,
  max_results integer default 50
)
returns table (
  message_id uuid,
  conversation_id uuid,
  channel_id uuid,
  channel_name text,
  sender_id uuid,
  sender_name text,
  sender_avatar_url text,
  body text,
  state text,
  verdict text,
  reason text,
  sent_at timestamptz,
  checked_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  return query
  select
    r.message_id,
    r.conversation_id,
    cc.id,
    cc.name,
    r.sender_id,
    public.circle_member_label(r.circle_id, r.sender_id),
    coalesce(cm.avatar_url, p.avatar_url),
    m.body,
    r.state,
    r.verdict,
    r.reason,
    m.created_at,
    r.checked_at
  from public.message_reviews r
  join public.messages m on m.id = r.message_id
  join public.profiles p on p.id = r.sender_id
  left join public.circle_members cm
    on cm.circle_id = r.circle_id and cm.user_id = r.sender_id
  left join public.circle_channels cc
    on cc.id = public.conversation_circle_channel_id(r.conversation_id)
  where r.circle_id = target_circle_id
    and r.state in ('held', 'flagged')
    and m.recalled_at is null
    and public.can_current_user_moderate_messages(r.conversation_id)
  order by m.created_at desc, r.message_id desc
  limit least(greatest(coalesce(max_results, 50), 1), 100);
end;
$$;

-- How many are waiting, for the badge (counts up to 99).
create or replace function public.count_message_reviews(target_circle_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return 0;
  end if;
  return (
    select count(*)::integer
    from (
      select 1
      from public.message_reviews r
      join public.messages m on m.id = r.message_id
      where r.circle_id = target_circle_id
        and r.state in ('held', 'flagged')
        and m.recalled_at is null
        and public.can_current_user_moderate_messages(r.conversation_id)
      limit 99
    ) waiting
  );
end;
$$;

-- A moderator's decision on a held or flagged message. 'approve' releases a
-- held message (a flagged one is already visible and is just closed);
-- 'remove' deletes it, like a moderator deleting any message.
create or replace function public.decide_message_review(
  target_message_id uuid,
  decision text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  review public.message_reviews%rowtype;
  msg public.messages%rowtype;
  channel public.circle_channels%rowtype;
  new_state text;
  releasing boolean;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if decision is null or decision not in ('approve', 'remove') then
    raise exception 'Choose approve or remove' using errcode = '22023';
  end if;

  select r.* into review
  from public.message_reviews r
  where r.message_id = target_message_id
    and r.state in ('held', 'flagged')
  for update;
  if review.message_id is null then
    raise exception 'This message was already reviewed' using errcode = 'P0002';
  end if;

  if not public.can_current_user_moderate_messages(review.conversation_id) then
    raise exception 'Only moderators can review messages' using errcode = '42501';
  end if;

  select m.* into msg from public.messages m where m.id = target_message_id for update;

  -- Approving a held message that is still there lets everyone see it.
  releasing := decision = 'approve'
    and msg.recalled_at is null
    and msg.review_state is not distinct from 'held';

  if decision = 'approve' then
    new_state := 'approved';
    if releasing then
      perform public.ai_guard_release_message(target_message_id);
    end if;
  else
    new_state := 'removed';
    if msg.recalled_at is null then
      -- Like recall_message: the content goes. A message nobody saw stays
      -- hidden; one that was already visible shows as deleted.
      update public.messages m
      set
        recalled_at = now(),
        recalled_by = current_user_id,
        body = '',
        attachment = null,
        reply_preview = null,
        forwarded_from = null,
        mentions = '[]'::jsonb,
        review_state = case when m.review_state is not null then 'removed' end
      where m.id = target_message_id;

      delete from public.message_mentions mm where mm.message_id = target_message_id;
      delete from public.message_reactions rx where rx.message_id = target_message_id;
      delete from public.pinned_messages pm where pm.message_id = target_message_id;
      update public.messages m
      set reply_preview = m.reply_preview || jsonb_build_object('body', '')
      where m.reply_to_message_id = target_message_id
        and jsonb_typeof(m.reply_preview) = 'object';
    end if;
  end if;

  update public.message_reviews r
  set
    state = new_state,
    decided_at = now(),
    decided_by = current_user_id,
    released_at = case when releasing then now() else r.released_at end,
    -- A flagged message was released (and queued for its push) already.
    push_pending = case
      when decision = 'remove' then false
      else r.push_pending or releasing
    end
  where r.message_id = target_message_id;

  select cc.* into channel
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(review.conversation_id);

  perform public.write_circle_audit(
    review.circle_id,
    case when decision = 'approve' then 'guard_approve' else 'guard_remove' end,
    'message',
    target_message_id,
    public.circle_member_label(review.circle_id, review.sender_id),
    jsonb_strip_nulls(jsonb_build_object(
      'verdict', review.verdict,
      'reason', review.reason,
      'author_id', review.sender_id,
      'channel_id', channel.id,
      'channel_name', channel.name,
      'was', review.state
    ))
  );

  if releasing then
    perform public.ai_guard_wake('scheduled-dispatch', '{}'::jsonb);
  end if;

  return new_state;
end;
$$;

revoke execute on function public.list_message_reviews(uuid, integer) from public, anon;
revoke execute on function public.count_message_reviews(uuid) from public, anon;
revoke execute on function public.decide_message_review(uuid, text) from public, anon;
grant execute on function public.list_message_reviews(uuid, integer) to authenticated;
grant execute on function public.count_message_reviews(uuid) to authenticated;
grant execute on function public.decide_message_review(uuid, text) to authenticated;

-- ----------------------------------------------------------------- schedule

-- Creates (or replaces) the one-minute sweep when pg_cron is available. Run
-- `select public.install_ai_guard_schedule();` again after enabling pg_cron
-- in the dashboard if this migration found it missing.
create or replace function public.install_ai_guard_schedule()
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
    'wecord-ai-guard-sweep',
    '* * * * *',
    'select public.run_ai_guard_sweep()'
  );
  return 'scheduled';
end;
$$;

revoke execute on function public.install_ai_guard_schedule() from public, anon, authenticated;
grant execute on function public.install_ai_guard_schedule() to service_role;

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
  raise notice 'AI guard sweep: %', public.install_ai_guard_schedule();
exception when others then
  raise notice 'Could not schedule the AI guard sweep: %', sqlerrm;
end;
$$;
