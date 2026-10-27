-- Event subscriptions, a bot's outgoing webhook (roadmap I2), part 1 of 4:
-- the tables, the rule for what a bot may be told about, and the settings.
--
-- A bot that has a server can ask to be TOLD when something happens, instead
-- of asking over and over. The managers of the bot's circle (manage_circle)
-- give it one https address and the kinds of event they want:
--
--   message.created      a new message in a chat the bot is in
--   message.mentioned    a message that mentions the bot
--   message.updated      a message was edited
--   message.deleted      a message was deleted
--   reaction.added       someone reacted to a message
--   member.joined        someone joined the circle, or the group
--   member.left          someone left or was removed
--   interaction.created  a slash command, a press or a form (only when the bot
--                        has no callback address: a callback gets them)
--
-- Sending is the same machinery as the interaction callbacks (I1,
-- 202610280650): the same address check (bot_callback_url_problem here, the
-- DNS check before every send in supabase/functions/_shared/ssrf.ts), the same
-- HMAC-SHA256 signature, 5 second timeout, no redirects, retries with backoff
-- and a pause after 20 deliveries lost in a row. The function that sends is
-- bot-events (part 2 queues, the function sends).
--
-- What a bot may be told (the rule of this whole feature):
--
--   * Only what the bot itself could read through the bot API: a chat it is a
--     member of, in its own circle with view_channel there, or a group or a
--     direct chat it was put in (bot_conversation_access). A circle that an
--     admin suspended tells nothing. A bot with its token revoked, or whose
--     subscription is off, is told nothing.
--   * Never what the person who set it up could not set up: the subscription
--     belongs to a member who manages the circle (manage_circle); if that
--     member stops managing it, the subscription is paused.
--   * Never a message nobody can read yet (the AI guard's review_state) or any
--     more (deleted, disappeared).
--   * Never anything from someone who blocked the bot.
--   * Never the words of a restricted chat (G6, conversation_restricts_sharing),
--     of a chat a member locked (G2), of a disappearing message or a view-once
--     picture: the event still comes, saying what happened and where, with the
--     reason the text was kept back (content_withheld).
--   * People are {id, username, name, is_bot}: what anyone signed in can read
--     of a profile. Never a bio, status, birthday, presence, e-mail or a
--     picture's address. Files are named, never linked.
--
-- Limits: at most 300 events a minute and 1000 waiting per bot (the rest are
-- counted as dropped), a body of at most 16 KB, deliveries removed after 7
-- days.
--
-- This part also adds what the bot API 2.0 (I3) needs from circle_bots: a
-- description and the two switches that let people talk to the bot in direct
-- chats and groups.

alter table public.circle_bots
  add column if not exists description text not null default '',
  add column if not exists allow_direct boolean not null default false,
  add column if not exists allow_groups boolean not null default false;

alter table public.circle_bots
  drop constraint if exists circle_bots_description_length;
alter table public.circle_bots
  add constraint circle_bots_description_length check (
    description = btrim(description)
    and char_length(description) <= 200
    and description !~ '[[:cntrl:]]'
  );

create or replace function public.bot_event_types()
returns text[]
language sql
immutable
set search_path = public
as $$
  select array[
    'message.created',
    'message.mentioned',
    'message.updated',
    'message.deleted',
    'reaction.added',
    'member.joined',
    'member.left',
    'interaction.created'
  ]::text[];
$$;

revoke execute on function public.bot_event_types() from public, anon, authenticated;
grant execute on function public.bot_event_types() to service_role;

create table if not exists public.bot_event_subscriptions (
  bot_id uuid primary key references public.circle_bots(id) on delete cascade,
  url text not null,
  secret text not null,
  events text[] not null,
  enabled boolean not null default true,
  -- The member who set it; it works only while they manage the circle.
  owner_id uuid references public.profiles(id) on delete set null,
  consecutive_failures integer not null default 0,
  last_status integer,
  last_error text,
  last_success_at timestamptz,
  last_failure_at timestamptz,
  window_start timestamptz,
  window_count integer not null default 0,
  dropped_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint bot_event_subscriptions_url_length check (char_length(url) <= 500),
  constraint bot_event_subscriptions_secret_format check (secret ~ '^[0-9a-f]{64}$'),
  constraint bot_event_subscriptions_events_known check (
    events <@ public.bot_event_types()
    and cardinality(events) between 1 and 8
  )
);

alter table public.bot_event_subscriptions enable row level security;
revoke all on public.bot_event_subscriptions from public, anon, authenticated;

create table if not exists public.bot_event_deliveries (
  id uuid primary key default gen_random_uuid(),
  bot_id uuid not null references public.circle_bots(id) on delete cascade,
  event text not null,
  -- Where it happened, checked again before sending.
  conversation_id uuid,
  -- The person the event is about, so deleting an account removes it.
  actor_id uuid,
  payload jsonb not null,
  state text not null default 'queued',
  attempts integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  last_status integer,
  last_error text,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  constraint bot_event_deliveries_state check (
    state in ('queued', 'sending', 'delivered', 'failed', 'dropped')
  ),
  constraint bot_event_deliveries_event check (
    event = 'ping' or event = any (public.bot_event_types())
  ),
  constraint bot_event_deliveries_payload_size check (octet_length(payload::text) <= 14336)
);

create index if not exists bot_event_deliveries_due_idx
  on public.bot_event_deliveries (next_attempt_at)
  where state in ('queued', 'sending');
create index if not exists bot_event_deliveries_bot_idx
  on public.bot_event_deliveries (bot_id, created_at desc);
create index if not exists bot_event_deliveries_actor_idx
  on public.bot_event_deliveries (actor_id)
  where actor_id is not null;
create index if not exists bot_event_deliveries_created_idx
  on public.bot_event_deliveries (created_at);

alter table public.bot_event_deliveries enable row level security;
revoke all on public.bot_event_deliveries from public, anon, authenticated;

-- ---------------------------------------------------------------- the rule

-- Whether the bot is, right now, somewhere it may read: a member of the
-- conversation and
--   * a circle channel (or a thread of one): the channel is in the bot's own
--     circle, the bot can view it, and the circle is not suspended;
--   * a group: the bot is allowed in groups (circle_bots.allow_groups);
--   * a direct chat: the bot is open to direct chats (allow_direct) and
--     nobody blocked anybody.
-- It needs a working token and a place in its own circle. Used for every event
-- and, in 202610281130, for every read of a chat.
create or replace function public.bot_conversation_access(
  bot public.circle_bots,
  target_conversation_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  channel_id uuid;
  channel_circle uuid;
  chat_type text;
  base_id uuid;
  peer uuid;
begin
  if bot.id is null or target_conversation_id is null or bot.token_hash is null then
    return false;
  end if;

  if not exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id = target_conversation_id
      and cm.user_id = bot.user_id
  ) then
    return false;
  end if;

  -- Gone from its own circle: its token no longer works either.
  if not exists (
    select 1
    from public.circle_members m
    where m.circle_id = bot.circle_id
      and m.user_id = bot.user_id
  ) then
    return false;
  end if;

  channel_id := public.conversation_circle_channel_id(target_conversation_id);
  if channel_id is not null then
    select cc.circle_id into channel_circle
    from public.circle_channels cc
    where cc.id = channel_id;

    return channel_circle = bot.circle_id
      and not public.conversation_in_suspended_circle(target_conversation_id)
      and public.circle_channel_has_permission(channel_id, bot.user_id, 'view_channel');
  end if;

  -- A thread follows the chat it belongs to.
  base_id := coalesce((
    select ct.parent_conversation_id
    from public.conversation_threads ct
    where ct.conversation_id = target_conversation_id
  ), target_conversation_id);

  select c.type into chat_type
  from public.conversations c
  where c.id = base_id;

  if chat_type = 'group' then
    return coalesce((
      select b.allow_groups from public.circle_bots b where b.id = bot.id
    ), false);
  end if;

  if chat_type = 'direct' then
    if not coalesce((
      select b.allow_direct from public.circle_bots b where b.id = bot.id
    ), false) then
      return false;
    end if;
    select cm.user_id into peer
    from public.conversation_members cm
    where cm.conversation_id = base_id
      and cm.user_id <> bot.user_id
    limit 1;
    return peer is not null and not public.are_users_blocked(bot.user_id, peer);
  end if;

  return false;
end;
$$;

revoke execute on function public.bot_conversation_access(public.circle_bots, uuid)
  from public, anon, authenticated;
grant execute on function public.bot_conversation_access(public.circle_bots, uuid)
  to service_role;

-- ---------------------------------------------------------------- settings

create or replace function public.bot_event_subscription_state(target_bot_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select jsonb_build_object(
      'url', s.url,
      'events', to_jsonb(s.events),
      'enabled', s.enabled,
      'consecutive_failures', s.consecutive_failures,
      'last_status', s.last_status,
      'last_error', s.last_error,
      'last_success_at', s.last_success_at,
      'last_failure_at', s.last_failure_at,
      'dropped_count', s.dropped_count
    )
    from public.bot_event_subscriptions s
    where s.bot_id = target_bot_id
  ), jsonb_build_object('url', null, 'enabled', false, 'events', '[]'::jsonb));
$$;

revoke execute on function public.bot_event_subscription_state(uuid)
  from public, anon, authenticated;

-- The subscription of a bot as its managers see it (never the secret).
create or replace function public.get_bot_event_subscription(target_bot_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.circle_bot_for_management(target_bot_id);
begin
  return public.bot_event_subscription_state(bot.id);
end;
$$;

-- The kinds of event, cleaned: known names only, no repeats, at least one.
create or replace function public.bot_event_names_clean(event_names text[])
returns text[]
language plpgsql
immutable
set search_path = public
as $$
declare
  cleaned text[];
begin
  select coalesce(array_agg(distinct btrim(n)), array[]::text[])
  into cleaned
  from unnest(coalesce(event_names, array[]::text[])) as n;

  if cardinality(cleaned) = 0 then
    raise exception 'Choose at least one kind of event' using errcode = '22023';
  end if;
  if not (cleaned <@ public.bot_event_types()) then
    raise exception 'Unknown kind of event' using errcode = '22023';
  end if;
  return cleaned;
end;
$$;

revoke execute on function public.bot_event_names_clean(text[])
  from public, anon, authenticated;

-- Sets the address and the kinds of event. The first time (or after clearing)
-- a secret is made and returned once; changing the address or the kinds keeps
-- the secret and returns none. Saving turns a paused subscription back on.
create or replace function public.set_bot_event_subscription(
  target_bot_id uuid,
  event_url text,
  event_names text[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.circle_bot_for_management(target_bot_id);
  problem text := public.bot_callback_url_problem(event_url);
  cleaned text[] := public.bot_event_names_clean(event_names);
  new_secret text;
  existing_secret text;
begin
  if problem is not null then
    raise exception '%', problem using errcode = '22023';
  end if;

  if bot.token_hash is null then
    raise exception 'Make a new token for the bot first' using errcode = '22023';
  end if;

  select s.secret into existing_secret
  from public.bot_event_subscriptions s
  where s.bot_id = bot.id;

  if existing_secret is null then
    new_secret := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.bot_event_subscriptions (bot_id, url, secret, events, owner_id)
    values (bot.id, event_url, new_secret, cleaned, auth.uid());
  else
    update public.bot_event_subscriptions s
    set
      url = event_url,
      events = cleaned,
      enabled = true,
      owner_id = auth.uid(),
      consecutive_failures = 0,
      last_error = null,
      updated_at = now()
    where s.bot_id = bot.id;
  end if;

  perform public.write_circle_audit(
    bot.circle_id,
    'bot_events_set',
    'bot',
    bot.id,
    bot.name,
    jsonb_build_object(
      'host', substring(event_url from '^https://([^/?#:]+)'),
      'events', to_jsonb(cleaned)
    )
  );

  return public.bot_event_subscription_state(bot.id)
    || case when new_secret is not null then jsonb_build_object('secret', new_secret) else '{}'::jsonb end;
end;
$$;

create or replace function public.rotate_bot_event_secret(target_bot_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.circle_bot_for_management(target_bot_id);
  new_secret text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  update public.bot_event_subscriptions s
  set secret = new_secret, updated_at = now()
  where s.bot_id = bot.id;

  if not found then
    raise exception 'This bot has no event subscription' using errcode = 'P0002';
  end if;

  perform public.write_circle_audit(
    bot.circle_id, 'bot_events_rotate', 'bot', bot.id, bot.name, '{}'::jsonb
  );

  return public.bot_event_subscription_state(bot.id)
    || jsonb_build_object('secret', new_secret);
end;
$$;

-- Turns the subscription off and forgets it; what waited is dropped.
create or replace function public.clear_bot_event_subscription(target_bot_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.circle_bot_for_management(target_bot_id);
begin
  delete from public.bot_event_subscriptions s where s.bot_id = bot.id;

  if found then
    update public.bot_event_deliveries d
    set state = 'dropped', last_error = coalesce(d.last_error, 'subscription_removed')
    where d.bot_id = bot.id
      and d.state in ('queued', 'sending');

    perform public.write_circle_audit(
      bot.circle_id, 'bot_events_clear', 'bot', bot.id, bot.name, '{}'::jsonb
    );
  end if;
end;
$$;

revoke execute on function public.get_bot_event_subscription(uuid) from public, anon;
revoke execute on function public.set_bot_event_subscription(uuid, text, text[]) from public, anon;
revoke execute on function public.rotate_bot_event_secret(uuid) from public, anon;
revoke execute on function public.clear_bot_event_subscription(uuid) from public, anon;
grant execute on function public.get_bot_event_subscription(uuid) to authenticated;
grant execute on function public.set_bot_event_subscription(uuid, text, text[]) to authenticated;
grant execute on function public.rotate_bot_event_secret(uuid) to authenticated;
grant execute on function public.clear_bot_event_subscription(uuid) to authenticated;
