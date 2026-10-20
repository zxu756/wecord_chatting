-- Monitoring and alerts (K3), part 1 of 4: the tables.
--
-- WeCord watches itself with its own data and nothing else: no third-party
-- monitoring and no data leaving Supabase. A job of its own (202610260150)
-- looks at the cron job history, the replies of the wake-up calls, the push
-- outcomes, the error reports and the AI usage every 5 minutes.
--
-- * ops_checks: the latest result of each check (ok, warn, fail, unknown),
--   with a few numbers and when it was last looked at and last changed. The
--   admin console shows them, and shows a warning when the newest one is old
--   (the checks run from pg_cron, so if cron stops this is how it shows).
-- * ops_alerts: something that went wrong. There is at most one open alert
--   per check key. A 'state' alert (the push failure rate is high) closes by
--   itself when the check has been fine twice in a row; an 'event' alert (a
--   new kind of error) closes by itself after a day. Platform admins
--   acknowledge or close them from the console. The texts are written in
--   English and Chinese and hold numbers and names of jobs, never a person
--   or a message.
-- * announcements.ops_alert_id and the notice kind 'ops_alert': an alert
--   also reaches each owner and moderator as an official card in
--   Notifications (a notice for one person, like a feedback reply), taken
--   back by itself when the alert closes.
--
-- The tables are closed to every client role (row level security on, no
-- policy, no grant).

create table if not exists public.ops_checks (
  key text primary key check (key ~ '^[a-z][a-z0-9_]{0,59}$'),
  status text not null check (status in ('ok', 'warn', 'fail', 'unknown')),
  detail jsonb not null default '{}'::jsonb,
  checked_at timestamptz not null default now(),
  changed_at timestamptz not null default now(),
  ok_streak integer not null default 0 check (ok_streak >= 0)
);

alter table public.ops_checks enable row level security;
revoke all on public.ops_checks from public, anon, authenticated;

create table if not exists public.ops_alerts (
  id uuid primary key default gen_random_uuid(),
  check_key text not null check (char_length(check_key) between 1 and 80),
  kind text not null default 'state' check (kind in ('state', 'event')),
  severity text not null check (severity in ('warn', 'fail')),
  title_en text not null default '',
  title_zh text not null default '',
  body_en text not null default '',
  body_zh text not null default '',
  detail jsonb not null default '{}'::jsonb,
  opened_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  acknowledged_by uuid references public.profiles(id) on delete set null,
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id) on delete set null,
  -- 'auto' when the check recovered or the day passed, 'manual' when an
  -- admin closed it.
  resolution text check (resolution in ('auto', 'manual')),
  -- Whether the push for it has been given out (once).
  push_claimed_at timestamptz,
  reopen_count integer not null default 0 check (reopen_count >= 0),
  constraint ops_alerts_text_lengths check (
    char_length(title_en) <= 120 and char_length(title_zh) <= 120
    and char_length(body_en) <= 600 and char_length(body_zh) <= 600
  ),
  constraint ops_alerts_resolution_pair check (
    (resolved_at is null) = (resolution is null)
  )
);

-- One open alert per check.
create unique index if not exists ops_alerts_one_open_idx
  on public.ops_alerts (check_key)
  where resolved_at is null;
create index if not exists ops_alerts_opened_idx
  on public.ops_alerts (opened_at desc);
create index if not exists ops_alerts_resolved_idx
  on public.ops_alerts (check_key, resolved_at desc)
  where resolved_at is not null;
create index if not exists ops_alerts_push_idx
  on public.ops_alerts (opened_at)
  where push_claimed_at is null and resolved_at is null;

alter table public.ops_alerts enable row level security;
revoke all on public.ops_alerts from public, anon, authenticated;

-- The official card of an alert.
alter table public.announcements
  add column if not exists ops_alert_id uuid
    references public.ops_alerts(id) on delete cascade;

create index if not exists announcements_ops_alert_idx
  on public.announcements (ops_alert_id)
  where ops_alert_id is not null;

alter table public.announcements
  drop constraint if exists announcements_kind_check;
alter table public.announcements
  add constraint announcements_kind_check
  check (kind in ('announcement', 'feedback_reply', 'ops_alert'));

alter table public.announcements
  drop constraint if exists announcements_audience_matches_kind;
alter table public.announcements
  add constraint announcements_audience_matches_kind check (
    (kind in ('feedback_reply', 'ops_alert')) = (audience_user_id is not null)
  );
