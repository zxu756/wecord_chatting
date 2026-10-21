-- Member titles and honors (roadmap C7), part 1 of 5: the tables.
--
-- Two separate things share one display slot next to a member's name:
--
--   * A title: up to 10 characters a moderator gives a member for one circle
--     ("Founder", "Photo editor"). It is a plain column on circle_members
--     (title, title_set_at), written only by set_circle_member_title
--     (202610270210). The circle's members see it, as they see a nickname.
--   * Honors: what the nightly run (202610270220) works out from
--     circle_member_daily, the C3 table that only says "this person was
--     active on this day". Honors count DAYS, never messages, so there is
--     nothing to win by posting more:
--       - weekly   last week's active days: 7 = level 3, 5-6 = level 2,
--                  3-4 = level 1, fewer than 3 = none
--       - streak   consecutive active days up to now: milestones 7, 30, 100
--     Stored in circle_member_honors (what was earned) and
--     circle_member_honor_stats (the running streak).
--
-- Privacy, because the C3 dashboard deliberately hides small numbers and
-- never shows who was active:
--
--   * Honors are computed only for a circle with 5 or more people, and only
--     while the circle has them switched on (circles.honors_enabled, off for
--     the whole circle by someone with manage_circle).
--   * A member can stay out (circle_honor_prefs, opted_out): nothing is
--     computed for them and what exists is deleted.
--   * Other members see the conclusion only (a level, a milestone), never a
--     day count or a date; the weekly board is published only when 5 or more
--     people are on it. The person themself sees their own numbers.
--   * All of it is closed to clients; the RPCs of 202610270210 and
--     202610270230 are the only way in.

alter table public.circles
  add column if not exists honors_enabled boolean not null default true;

alter table public.circle_members
  add column if not exists title text,
  add column if not exists title_set_at timestamptz;

alter table public.circle_members
  drop constraint if exists circle_members_title_check;
alter table public.circle_members
  add constraint circle_members_title_check check (
    title is null
    or (char_length(title) between 1 and 10 and title = btrim(title))
  );

-- Who stays out of honors in a circle. Only the people who stay out have a
-- row, so a missing row means "takes part".
create table if not exists public.circle_honor_prefs (
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  opted_out_at timestamptz not null default now(),
  primary key (circle_id, user_id)
);

-- What was earned. A week's honor is rewritten while the week is repaired
-- (kind 'weekly', period_start = the Monday, level 1 to 3); a streak
-- milestone is awarded once (kind 'streak', level 7, 30 or 100,
-- period_start = the day it was reached).
create table if not exists public.circle_member_honors (
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null,
  level integer not null,
  period_start date not null,
  awarded_at timestamptz not null default now(),
  constraint circle_member_honors_kind check (kind in ('weekly', 'streak')),
  constraint circle_member_honors_level check (
    (kind = 'weekly' and level between 1 and 3)
    or (kind = 'streak' and level in (7, 30, 100))
  )
);

create unique index if not exists circle_member_honors_weekly_key
  on public.circle_member_honors (circle_id, user_id, period_start)
  where kind = 'weekly';
create unique index if not exists circle_member_honors_streak_key
  on public.circle_member_honors (circle_id, user_id, level)
  where kind = 'streak';
create index if not exists circle_member_honors_week_idx
  on public.circle_member_honors (circle_id, period_start)
  where kind = 'weekly';

-- The running streak, as of the last nightly run. Streak days are UTC days
-- like the rest of the dashboard; the longest run is kept up to the 120 days
-- circle_member_daily remembers.
create table if not exists public.circle_member_honor_stats (
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  current_streak integer not null default 0,
  best_streak integer not null default 0,
  updated_day date not null,
  primary key (circle_id, user_id),
  constraint circle_member_honor_stats_counts check (
    current_streak >= 0 and best_streak >= current_streak
  )
);

-- A title given to somebody else, waiting for its push (claimed once).
create table if not exists public.circle_title_notices (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  created_at timestamptz not null default now(),
  push_claimed_at timestamptz
);

create index if not exists circle_title_notices_unclaimed_idx
  on public.circle_title_notices (created_at)
  where push_claimed_at is null;

alter table public.circle_honor_prefs enable row level security;
alter table public.circle_member_honors enable row level security;
alter table public.circle_member_honor_stats enable row level security;
alter table public.circle_title_notices enable row level security;
revoke all on public.circle_honor_prefs from public, anon, authenticated;
revoke all on public.circle_member_honors from public, anon, authenticated;
revoke all on public.circle_member_honor_stats from public, anon, authenticated;
revoke all on public.circle_title_notices from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Leaving, and leaving WeCord
-- ---------------------------------------------------------------------------

-- Somebody who leaves or is removed takes their honors and their wait for a
-- title push with them. (The title itself is a column of the row that goes.)
create or replace function public.honors_forget_left_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.circle_member_honors
  where circle_id = old.circle_id and user_id = old.user_id;
  delete from public.circle_member_honor_stats
  where circle_id = old.circle_id and user_id = old.user_id;
  delete from public.circle_honor_prefs
  where circle_id = old.circle_id and user_id = old.user_id;
  delete from public.circle_title_notices
  where circle_id = old.circle_id and user_id = old.user_id;
  return null;
end;
$$;

revoke execute on function public.honors_forget_left_member()
  from public, anon, authenticated;

drop trigger if exists circle_members_forget_honors on public.circle_members;
create trigger circle_members_forget_honors
  after delete on public.circle_members
  for each row execute function public.honors_forget_left_member();

-- Deleting an account (profiles.deleted_at) erases everything about the
-- person here: honors, streak, the choice to stay out, waiting pushes, and
-- the titles they were given. Same pattern as profiles_erase_kb
-- (202610270130); prepare_account_deletion is not rewritten.
create or replace function public.erase_honors_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.circle_member_honors where user_id = new.id;
  delete from public.circle_member_honor_stats where user_id = new.id;
  delete from public.circle_honor_prefs where user_id = new.id;
  delete from public.circle_title_notices where user_id = new.id;
  update public.circle_members
  set title = null, title_set_at = null
  where user_id = new.id and title is not null;
  return new;
end;
$$;

revoke execute on function public.erase_honors_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_erase_honors on public.profiles;
create trigger profiles_erase_honors
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_honors_of_deleted_account();
