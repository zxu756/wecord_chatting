-- Product statistics (K2), part 1 of 3: the tables. Part 2 (202610260110)
-- fills them, part 3 (202610260120) lets platform admins read them.
--
-- Nothing here is measured on the device: there is no client tracking. The
-- numbers come from what the database already knows, are aggregated on the
-- server, and keep no content and no list of people:
--
-- * ops_daily_metrics: one row per UTC day with counts only (active people,
--   sign-ups, retained sign-ups, messages by type, how much each feature was
--   used, voice minutes, AI requests, push outcome, storage). Never a user
--   id, a conversation id or a text.
-- * ops_active_days: who was active on a day, only to count distinct people
--   and to work out retention. The person is a salted hash (ops_user_key),
--   never the user id, the rows are kept for 45 days, and nobody can read
--   the table through the API: only the aggregate functions look at it. The
--   platform and app version of the session are kept with the hash, to tell
--   how many people use each version (K5 version health, read live over the
--   last 7 days).
-- * ops_push_stats: per hour, how many web pushes went out, failed or found
--   a dead subscription (counts only; the push functions report them).
-- * ops_settings: the salt of the hash and the limits the health checks use.
--
-- Every table is closed to every client role (row level security on, no
-- policy, no grant).

create table if not exists public.ops_settings (
  key text primary key check (key ~ '^[a-z][a-z0-9_]{0,59}$'),
  value jsonb not null default 'null'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.ops_settings enable row level security;
revoke all on public.ops_settings from public, anon, authenticated;

-- The salt of ops_user_key: made once, here, and never shown to anybody.
insert into public.ops_settings (key, value)
values (
  'activity_salt',
  to_jsonb(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
)
on conflict (key) do nothing;

-- An integer setting, or [fallback] when it is not set (or not a number).
create or replace function public.ops_setting_int(setting_key text, fallback integer)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select case
        when jsonb_typeof(s.value) = 'number' then (s.value #>> '{}')::numeric::integer
      end
      from public.ops_settings s
      where s.key = setting_key
    ),
    fallback
  );
$$;

revoke execute on function public.ops_setting_int(text, integer)
  from public, anon, authenticated;

-- The de-identified key of a person: a salted hash, 32 hex characters. Not
-- reversible without the salt, which lives only in ops_settings.
create or replace function public.ops_user_key(uid uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select substr(
    encode(
      sha256(
        convert_to(
          coalesce(
            (select s.value #>> '{}' from public.ops_settings s where s.key = 'activity_salt'),
            ''
          ) || ':' || uid::text,
          'UTF8'
        )
      ),
      'hex'
    ),
    1,
    32
  );
$$;

revoke execute on function public.ops_user_key(uuid)
  from public, anon, authenticated;

create table if not exists public.ops_active_days (
  day date not null,
  user_key text not null check (user_key ~ '^[0-9a-f]{32}$'),
  -- The session's platform and app version in lower case; '' when the
  -- activity does not say (a message sent, a post).
  platform text not null default '',
  app_version text not null default '',
  primary key (day, user_key, platform, app_version)
);

create index if not exists ops_active_days_key_idx
  on public.ops_active_days (user_key, day);

alter table public.ops_active_days enable row level security;
revoke all on public.ops_active_days from public, anon, authenticated;

create table if not exists public.ops_daily_metrics (
  day date primary key,
  computed_at timestamptz not null default now(),
  -- People active that day (opened the app, sent something, posted).
  active_users integer not null default 0 check (active_users >= 0),
  new_users integer not null default 0 check (new_users >= 0),
  -- How many of that day's new people were active 1, 7 and 30 days later;
  -- null until that day has passed.
  d1_retained integer check (d1_retained >= 0),
  d7_retained integer check (d7_retained >= 0),
  d30_retained integer check (d30_retained >= 0),
  messages_total integer not null default 0 check (messages_total >= 0),
  -- {"text": 120, "image": 8, ...}
  messages_by_type jsonb not null default '{}'::jsonb,
  -- {"circle_posts": 3, "moments": 5, "stories": 2, "notes": 1, "tasks": 4,
  --  "chat_events": 1}
  feature_counts jsonb not null default '{}'::jsonb,
  -- Minutes people spent in circle voice channels, sampled every 15 minutes.
  voice_minutes integer not null default 0 check (voice_minutes >= 0),
  ai_requests integer not null default 0 check (ai_requests >= 0),
  ai_users integer not null default 0 check (ai_users >= 0),
  push_sent integer not null default 0 check (push_sent >= 0),
  push_failed integer not null default 0 check (push_failed >= 0),
  push_gone integer not null default 0 check (push_gone >= 0),
  error_reports integer not null default 0 check (error_reports >= 0),
  -- Everything in the storage buckets at the end of the day, and what was
  -- added since the day before (null when there is no day before).
  storage_bytes bigint check (storage_bytes >= 0),
  storage_added bigint
);

alter table public.ops_daily_metrics enable row level security;
revoke all on public.ops_daily_metrics from public, anon, authenticated;

create table if not exists public.ops_push_stats (
  hour timestamptz primary key,
  sent integer not null default 0 check (sent >= 0),
  failed integer not null default 0 check (failed >= 0),
  gone integer not null default 0 check (gone >= 0)
);

alter table public.ops_push_stats enable row level security;
revoke all on public.ops_push_stats from public, anon, authenticated;

-- The daily scans of messages go by day, so they need this index (the
-- existing ones start with the conversation).
create index if not exists messages_created_at_idx
  on public.messages (created_at);
