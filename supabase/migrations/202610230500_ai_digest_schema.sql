-- Daily digest (roadmap F3), part 1 of 5: what a person follows, when they
-- want it, and the digests themselves.
--
-- A person picks up to 10 groups and circle channels and a time of day. Every
-- day at that time, on THEIR clock, the database checks whether anything new
-- was said in those chats that they may see; if so the `ai` function (action
-- `digest`) summarises it into one card in Notifications and a push says it is
-- ready. When nothing is new the model is not asked at all (202610230520).
--
-- * public.ai_digest_settings: one row per person who set the digest up.
--     enabled      the master switch (Settings -> AI -> Daily digest)
--     deliver_at   the wall-clock time in the person's own time zone. The zone
--                  is not stored here: it is notification_time_zone() (the one
--                  their devices report, 202610210310), so a trip or a new
--                  phone moves the digest with them.
--     language     'en' or 'zh': what the summaries are written in (the app's
--                  language when it saved the setting)
-- * public.ai_digest_subscriptions: (person, chat) pairs, the chats they
--   follow. At most 10 per person, enforced by a trigger so no client, RPC or
--   script can exceed it; only groups and circle channels can be followed
--   (never a private chat, a note to self or a thread). Leaving a chat ends
--   the subscription (trigger on conversation_members); deleting the account
--   or the chat deletes the rows (foreign keys).
-- * public.ai_digests: one row per person per local day. It records the run
--   (queued, running, done, skipped, failed, limited and why) and, once done,
--   the card: [{conversation_id, summary, message_count}]. The unique
--   (user_id, local_date) is what makes a digest happen at most once a day.
--
-- Clients read their own settings and subscriptions and nothing else directly;
-- everything is written through the functions of the next files. The digests
-- are read through list_my_ai_digests, which re-checks visibility.

create table if not exists public.ai_digest_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  enabled boolean not null default true,
  deliver_at time not null default '08:00',
  language text not null default 'en' check (language in ('en', 'zh')),
  updated_at timestamptz not null default now()
);

alter table public.ai_digest_settings enable row level security;
revoke all on public.ai_digest_settings from anon, authenticated;
grant select on public.ai_digest_settings to authenticated;

drop policy if exists ai_digest_settings_select on public.ai_digest_settings;
create policy ai_digest_settings_select
  on public.ai_digest_settings for select
  to authenticated
  using (user_id = auth.uid());

create table if not exists public.ai_digest_subscriptions (
  user_id uuid not null references public.profiles(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, conversation_id)
);

create index if not exists ai_digest_subscriptions_conversation_idx
  on public.ai_digest_subscriptions (conversation_id);

alter table public.ai_digest_subscriptions enable row level security;
revoke all on public.ai_digest_subscriptions from anon, authenticated;
grant select on public.ai_digest_subscriptions to authenticated;

drop policy if exists ai_digest_subscriptions_select on public.ai_digest_subscriptions;
create policy ai_digest_subscriptions_select
  on public.ai_digest_subscriptions for select
  to authenticated
  using (user_id = auth.uid());

-- How many chats one person can follow.
create or replace function public.ai_digest_max_subscriptions()
returns integer
language sql
immutable
as $$
  select 10;
$$;

-- The limit and the kinds of chat, for every writer (the RPC, the service
-- role, a script). Two inserts racing for the last place take the same lock.
create or replace function public.ai_digest_subscriptions_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  perform pg_advisory_xact_lock(
    hashtextextended('ai_digest_subscriptions:' || new.user_id::text, 0)
  );

  -- Following a chat that is already followed changes nothing (the insert
  -- that follows will find the row and do nothing).
  if exists (
    select 1
    from public.ai_digest_subscriptions s
    where s.user_id = new.user_id and s.conversation_id = new.conversation_id
  ) then
    return new;
  end if;

  if not exists (
    select 1
    from public.conversations c
    where c.id = new.conversation_id
      and c.type in ('group', 'channel')
  ) then
    raise exception 'Only groups and circle channels can be followed'
      using errcode = '22023';
  end if;

  if (
    select count(*)
    from public.ai_digest_subscriptions s
    where s.user_id = new.user_id
  ) >= public.ai_digest_max_subscriptions() then
    raise exception 'digest_limit: you can follow at most % chats',
      public.ai_digest_max_subscriptions()
      using errcode = '54000';
  end if;
  return new;
end;
$$;

revoke execute on function public.ai_digest_subscriptions_guard() from public, anon, authenticated;

drop trigger if exists ai_digest_subscriptions_guard on public.ai_digest_subscriptions;
create trigger ai_digest_subscriptions_guard
  before insert on public.ai_digest_subscriptions
  for each row execute function public.ai_digest_subscriptions_guard();

-- Leaving a chat (or being removed from it) ends the subscription.
create or replace function public.ai_digest_drop_subscription_on_leave()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.ai_digest_subscriptions s
  where s.user_id = old.user_id and s.conversation_id = old.conversation_id;
  return old;
end;
$$;

revoke execute on function public.ai_digest_drop_subscription_on_leave()
  from public, anon, authenticated;

drop trigger if exists conversation_members_drop_digest_subscription on public.conversation_members;
create trigger conversation_members_drop_digest_subscription
  after delete on public.conversation_members
  for each row execute function public.ai_digest_drop_subscription_on_leave();

create table if not exists public.ai_digests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  -- The day on the person's clock when it ran.
  local_date date not null,
  -- The messages it covers: sent after window_start, up to window_end.
  window_start timestamptz not null,
  window_end timestamptz not null,
  language text not null default 'en' check (language in ('en', 'zh')),
  status text not null default 'queued'
    check (status in ('queued', 'running', 'done', 'skipped', 'failed', 'limited')),
  -- Why it was skipped, failed or limited: no_news, off, user_off,
  -- no_subscriptions, limit, not_configured, timeout, provider, error.
  reason text,
  -- [{conversation_id, summary, message_count}] once done.
  items jsonb not null default '[]'::jsonb,
  attempts integer not null default 0,
  wake_count integer not null default 1,
  woken_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  read_at timestamptz,
  push_claimed_at timestamptz,
  constraint ai_digests_one_a_day unique (user_id, local_date),
  constraint ai_digests_items_array check (jsonb_typeof(items) = 'array')
);

create index if not exists ai_digests_open_idx
  on public.ai_digests (woken_at)
  where status in ('queued', 'running');
create index if not exists ai_digests_user_idx
  on public.ai_digests (user_id, local_date desc);
create index if not exists ai_digests_unpushed_idx
  on public.ai_digests (finished_at)
  where status = 'done' and push_claimed_at is null;

-- Nobody reads the table directly: the digests come through
-- list_my_ai_digests, which drops what the person may no longer see.
alter table public.ai_digests enable row level security;
revoke all on public.ai_digests from anon, authenticated;
