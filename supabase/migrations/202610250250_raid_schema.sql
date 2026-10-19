-- Raid protection (C6), part 6 of 9: the data, and pausing a circle's
-- invites.
--
-- A circle can be "locked down" for a while, by itself (a burst of people
-- joining, see 202610250260) or by a moderator. A lockdown does three things
-- and never removes a member:
--
--   * invites are paused: no invite link or contact card works, no new invite
--     is made, and members cannot add friends (circle_security
--     .invites_paused_until);
--   * an open circle becomes an "apply" circle (C1), so Discover and every
--     other join path make a request that a moderator approves. The mode the
--     circle had is remembered (lockdown_prev_mode) and put back when the
--     lockdown ends, unless somebody changed the mode meanwhile, in which
--     case their choice stands. A circle that already reviews who joins
--     (apply) or is invite-only is left as it is;
--   * the people who joined during the burst cannot post links until it ends
--     (202610250270), and the AI guard, when the circle uses it, checks
--     their messages (it treats them as new members whatever its rule says).
--
-- Pausing invites on its own (the circle menu's "Safety actions") uses only
-- the first part.
--
-- This file: circle_security (one row per circle that has settings or a
-- state; defaults apply without a row), circle_raid_events (the log that
-- the moderators' push reads), the "paused" check on every invite path, and
-- a small index. Nothing in here rewrites a function except two patches of
-- the newest definitions:
--
--   * circle_invite_invalid_reason (202610130003): one more reason, 'paused'.
--     accept_circle_invite, the invite preview and the contact card all ask
--     it, so a paused circle's links read as unusable everywhere.
--   * invite_circle_members (202610220610): a call at the top, patched into
--     the text of the live definition with pg_get_functiondef, so the
--     C1 / C4 rules in it are untouched.
-- A BEFORE INSERT trigger on circle_invites stops new invites (the K1 take
-- down has the same trigger).

create table if not exists public.circle_security (
  circle_id uuid primary key references public.circles(id) on delete cascade,
  -- Automatic protection: on by default, with the threshold below. Counted
  -- over ten minutes: people who joined or asked to join.
  raid_enabled boolean not null default true,
  raid_threshold integer not null default 20
    check (raid_threshold between 3 and 500),
  -- How long an automatic lockdown lasts.
  raid_lock_hours smallint not null default 1
    check (raid_lock_hours in (1, 24)),
  invites_paused_until timestamptz,
  lockdown_until timestamptz,
  lockdown_started_at timestamptz,
  -- People who joined at or after this moment are the burst's newcomers.
  lockdown_window_from timestamptz,
  -- The join mode before the lockdown made the circle "apply"; null when it
  -- did not change it (or somebody took over).
  lockdown_prev_mode text
    check (lockdown_prev_mode is null
      or lockdown_prev_mode in ('open', 'apply', 'invite_only')),
  lockdown_source text check (lockdown_source is null or lockdown_source in ('auto', 'manual')),
  lockdown_joins integer,
  lockdown_new_accounts integer,
  -- The counting of a burst starts here after a lockdown ended, so the same
  -- people are not counted again.
  raid_counted_from timestamptz,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.circle_security enable row level security;
revoke all on public.circle_security from public, anon, authenticated;

create table if not exists public.circle_raid_events (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  kind text not null check (kind in ('lockdown', 'release')),
  source text not null check (source in ('auto', 'manual', 'expired')),
  joins integer,
  new_accounts integer,
  actor_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  -- Only an automatic lockdown is pushed to the moderators; handed to
  -- scheduled-dispatch once.
  push_claimed_at timestamptz
);

create index if not exists circle_raid_events_circle_idx
  on public.circle_raid_events (circle_id, created_at desc);

create index if not exists circle_raid_events_unpushed_idx
  on public.circle_raid_events (created_at)
  where push_claimed_at is null and kind = 'lockdown' and source = 'auto';

alter table public.circle_raid_events enable row level security;
revoke all on public.circle_raid_events from public, anon, authenticated;

-- Counting recent joiners walks the circle's newest members.
create index if not exists circle_members_recent_idx
  on public.circle_members (circle_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Paused invites
-- ---------------------------------------------------------------------------

create or replace function public.circle_invites_paused(target_circle_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.circle_security s
    where s.circle_id = target_circle_id
      and s.invites_paused_until > now()
  );
$$;

revoke execute on function public.circle_invites_paused(uuid)
  from public, anon, authenticated;

create or replace function public.assert_circle_invites_open(target_circle_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if public.circle_invites_paused(target_circle_id) then
    raise exception 'Invites to this circle are paused' using
      errcode = '42501', detail = 'invites_paused';
  end if;
end;
$$;

revoke execute on function public.assert_circle_invites_open(uuid)
  from public, anon, authenticated;

-- 202610130003 plus 'paused'.
create or replace function public.circle_invite_invalid_reason(
  invite_row public.circle_invites
)
returns text
language sql
stable
set search_path = public
as $$
  select case
    when invite_row.revoked_at is not null then 'revoked'
    when invite_row.expires_at is not null
      and invite_row.expires_at <= now() then 'expired'
    when invite_row.max_uses is not null
      and invite_row.use_count >= invite_row.max_uses then 'exhausted'
    when public.circle_invites_paused(invite_row.circle_id) then 'paused'
    else null
  end;
$$;

revoke execute on function public.circle_invite_invalid_reason(public.circle_invites)
  from public, anon, authenticated;

-- No new invites while they are paused.
create or replace function public.reject_paused_circle_invite()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_circle_invites_open(new.circle_id);
  return new;
end;
$$;

revoke execute on function public.reject_paused_circle_invite()
  from public, anon, authenticated;

drop trigger if exists circle_invites_reject_paused on public.circle_invites;
create trigger circle_invites_reject_paused
  before insert on public.circle_invites
  for each row execute function public.reject_paused_circle_invite();

-- invite_circle_members: the newest definition (202610220610), with a call
-- that refuses while invites are paused, placed after its permission check.
do $$
declare
  def text;
  patched text;
begin
  def := pg_get_functiondef('public.invite_circle_members(uuid, uuid[])'::regprocedure);
  if def like '%assert_circle_invites_open%' then
    return;
  end if;
  patched := regexp_replace(
    def,
    E'\n  if exists \\(',
    E'\n  perform public.assert_circle_invites_open(target_circle_id);\n\n  if exists (');
  if patched = def or patched not like '%assert_circle_invites_open%' then
    raise exception 'invite_circle_members changed shape; patch it by hand';
  end if;
  execute patched;
end;
$$;
