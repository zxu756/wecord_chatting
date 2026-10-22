-- Group check-in (roadmap D3), part 1 of 4: the tables.
--
-- A check-in is the chain (接龙, 202610180060) with one line a DAY instead of
-- one line in all: a study group or a fitness group says "done today" once a
-- day, and the card in the chat shows "Today 18/30 · you are on a 7 day
-- streak". It uses the same pieces as a chain and a form (D1, 202610230100):
--
-- * check_in_boards: one row per check-in. The card in the chat is an
--   ordinary text message whose body is "✅ <title>" (so search, previews and
--   pushes just work) and whose attachment is {kind: 'check_in',
--   check_in_id, title}; the chat renders it as the live card. A board lives
--   in a group or a circle channel (and not in a direct chat or a thread), as
--   a chain does (chain_conversation_allowed). It is closed when closed_at is
--   set or its last day (ends_on) has passed.
-- * "A day" is a day of the zone the creator's device was in when the board
--   was made (time_zone, an IANA name; bad names count as UTC), so a group
--   spread over several zones agrees on when the day turns over.
-- * check_in_entries: one row per person per day (day = the board's local
--   date). Checking in again the same day edits the note and the picture;
--   undoing removes the row. The note is up to 200 characters and a picture
--   is a file of chat-images under <conversation id>/check-ins/<board id>/.
-- * check_in_streaks: how long the run is that ends on a person's last day,
--   the best run and the number of days, kept by a trigger on the entries
--   (the "daily aggregate" is the entry itself, so the number on the card is
--   never behind). A run is alive while its last day is today or yesterday;
--   readers go through check_in_live_streak.
-- * check_in_notices: "you have not checked in today" pushes waiting to be
--   claimed (202610280520). One per person per board per day.
-- * Nothing is written by clients directly: submit_check_in and the other
--   functions of 202610280510 check membership, whether the person may send
--   there, blocking, the AI guard for the note and the closed state.
-- * A board follows its card, as a chain does (202610190012): while the card
--   waits for the AI guard, after it is deleted or when it expired, nobody
--   can read the board or its entries (chain_card_visible).
-- * Live updates: every change to an entry touches the board's row
--   (updated_at), and the table is in the supabase_realtime publication, so a
--   card re-reads get_check_in when it changes: no message per check-in.
-- * In a circle channel a check-in counts as a day of activity for C3/C7
--   (circle_member_daily), so the member honors streak (202610270220) sees it
--   (submit_check_in, 202610280510).

create table if not exists public.check_in_boards (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  message_id uuid references public.messages(id) on delete set null,
  created_by uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text not null default '',
  time_zone text not null default 'UTC',
  -- Minutes after local midnight at which the daily reminder goes, or null.
  remind_minute integer,
  -- The last day the board takes check-ins (local date), or null.
  ends_on date,
  -- The local day the reminder last went out, so it goes once a day.
  last_reminded_on date,
  closed_at timestamptz,
  closed_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint check_in_boards_title_length check (char_length(title) between 1 and 120),
  constraint check_in_boards_description_length check (char_length(description) <= 1000),
  constraint check_in_boards_zone_length check (char_length(time_zone) between 1 and 64),
  constraint check_in_boards_remind_range check (
    remind_minute is null or remind_minute between 0 and 1439
  )
);

create index if not exists check_in_boards_conversation_idx
  on public.check_in_boards (conversation_id, created_at desc);
create index if not exists check_in_boards_remind_idx
  on public.check_in_boards (remind_minute)
  where remind_minute is not null and closed_at is null;

create table if not exists public.check_in_entries (
  id uuid primary key default gen_random_uuid(),
  board_id uuid not null references public.check_in_boards(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  day date not null,
  note text not null default '',
  photo_path text,
  photo_mime text,
  -- clock_timestamp, not now(): two check-ins in one transaction keep their
  -- order.
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint check_in_entries_note_length check (char_length(note) <= 200),
  constraint check_in_entries_photo_mime_length check (
    photo_mime is null or char_length(photo_mime) <= 100
  ),
  constraint check_in_entries_one_per_day unique (board_id, user_id, day)
);

create index if not exists check_in_entries_day_idx
  on public.check_in_entries (board_id, day, created_at, id);
create index if not exists check_in_entries_user_idx
  on public.check_in_entries (user_id, board_id, day);

create table if not exists public.check_in_streaks (
  board_id uuid not null references public.check_in_boards(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  -- The length of the run that ends on last_day.
  current_streak integer not null default 0,
  best_streak integer not null default 0,
  total_days integer not null default 0,
  last_day date,
  updated_at timestamptz not null default now(),
  primary key (board_id, user_id)
);

create index if not exists check_in_streaks_leaders_idx
  on public.check_in_streaks (board_id, last_day desc, current_streak desc);

create table if not exists public.check_in_notices (
  id uuid primary key default gen_random_uuid(),
  board_id uuid not null references public.check_in_boards(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  day date not null,
  created_at timestamptz not null default now(),
  push_claimed_at timestamptz,
  constraint check_in_notices_one_per_day unique (board_id, user_id, day)
);

create index if not exists check_in_notices_unclaimed_idx
  on public.check_in_notices (created_at)
  where push_claimed_at is null;

alter table public.check_in_boards enable row level security;
alter table public.check_in_entries enable row level security;
alter table public.check_in_streaks enable row level security;
alter table public.check_in_notices enable row level security;

revoke all on public.check_in_boards from anon, authenticated;
revoke all on public.check_in_entries from anon, authenticated;
revoke all on public.check_in_streaks from anon, authenticated;
revoke all on public.check_in_notices from anon, authenticated;
grant select on public.check_in_boards to authenticated;
grant select on public.check_in_entries to authenticated;

-- Whether the card message of a board can be read by the caller (the rule of
-- chain_card_visible, 202610190012, which it asks).
create or replace function public.check_in_card_visible(card_message_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.chain_card_visible(card_message_id);
$$;

revoke execute on function public.check_in_card_visible(uuid) from public, anon;
grant execute on function public.check_in_card_visible(uuid) to authenticated;

drop policy if exists check_in_boards_select on public.check_in_boards;
create policy check_in_boards_select on public.check_in_boards
  for select to authenticated
  using (
    public.is_current_user_conversation_member(conversation_id)
    and public.check_in_card_visible(message_id)
  );

drop policy if exists check_in_entries_select on public.check_in_entries;
create policy check_in_entries_select on public.check_in_entries
  for select to authenticated
  using (
    exists (
      select 1
      from public.check_in_boards b
      where b.id = check_in_entries.board_id
        and public.is_current_user_conversation_member(b.conversation_id)
        and public.check_in_card_visible(b.message_id)
    )
  );

-- The local date of [ts] in zone [zone] (UTC when the zone is unknown).
create or replace function public.check_in_local_day(ts timestamptz, zone text)
returns date
language plpgsql
stable
set search_path = public
as $$
begin
  return (ts at time zone coalesce(nullif(zone, ''), 'UTC'))::date;
exception when others then
  return (ts at time zone 'UTC')::date;
end;
$$;

-- A zone name PostgreSQL knows, or 'UTC'.
create or replace function public.check_in_clean_zone(zone text)
returns text
language sql
stable
set search_path = public
as $$
  select coalesce(
    (select n.name from pg_catalog.pg_timezone_names n where n.name = btrim(zone) limit 1),
    'UTC'
  );
$$;

-- The board's "today" and whether it no longer takes check-ins.
create or replace function public.check_in_today(board public.check_in_boards)
returns date
language sql
stable
set search_path = public
as $$
  select public.check_in_local_day(now(), board.time_zone);
$$;

create or replace function public.check_in_is_closed(board public.check_in_boards)
returns boolean
language sql
stable
set search_path = public
as $$
  select board.closed_at is not null
    or (
      board.ends_on is not null
      and public.check_in_local_day(now(), board.time_zone) > board.ends_on
    );
$$;

-- A run is alive while its last day is today or yesterday.
create or replace function public.check_in_live_streak(
  run integer,
  last_day date,
  today date
)
returns integer
language sql
immutable
as $$
  select case
    when last_day is not null and last_day >= today - 1 then coalesce(run, 0)
    else 0
  end;
$$;

revoke execute on function public.check_in_local_day(timestamptz, text) from public, anon;
revoke execute on function public.check_in_clean_zone(text) from public, anon;
revoke execute on function public.check_in_today(public.check_in_boards) from public, anon;
revoke execute on function public.check_in_is_closed(public.check_in_boards) from public, anon;
revoke execute on function public.check_in_live_streak(integer, date, date) from public, anon;
grant execute on function public.check_in_local_day(timestamptz, text) to authenticated;
grant execute on function public.check_in_clean_zone(text) to authenticated;
grant execute on function public.check_in_today(public.check_in_boards) to authenticated;
grant execute on function public.check_in_is_closed(public.check_in_boards) to authenticated;
grant execute on function public.check_in_live_streak(integer, date, date) to authenticated;

-- Works the run of one person out of their entries (gaps and islands over the
-- days) and keeps it in check_in_streaks. No entries: no row.
create or replace function public.check_in_refresh_streak(
  p_board_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  best integer;
  total integer;
  latest date;
  run integer;
begin
  if not exists (select 1 from public.check_in_boards b where b.id = p_board_id) then
    return;
  end if;

  with days as (
    select
      e.day,
      e.day - (row_number() over (order by e.day))::integer as grp
    from public.check_in_entries e
    where e.board_id = p_board_id and e.user_id = p_user_id
  ),
  runs as (
    select max(day) as last_day, count(*)::integer as len
    from days
    group by grp
  )
  select
    coalesce(max(len), 0),
    coalesce(sum(len), 0),
    max(last_day),
    (select r.len from runs r order by r.last_day desc limit 1)
  into best, total, latest, run
  from runs;

  if total = 0 then
    delete from public.check_in_streaks s
    where s.board_id = p_board_id and s.user_id = p_user_id;
    return;
  end if;

  insert into public.check_in_streaks as s (
    board_id, user_id, current_streak, best_streak, total_days, last_day, updated_at
  )
  values (p_board_id, p_user_id, run, best, total, latest, now())
  on conflict (board_id, user_id) do update
  set current_streak = excluded.current_streak,
      best_streak = greatest(s.best_streak, excluded.best_streak),
      total_days = excluded.total_days,
      last_day = excluded.last_day,
      updated_at = now();
end;
$$;

-- Every change of an entry keeps the streak and touches the board, which is
-- what Realtime sends.
create or replace function public.check_in_entries_after_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_board uuid := coalesce(new.board_id, old.board_id);
  target_user uuid := coalesce(new.user_id, old.user_id);
begin
  perform public.check_in_refresh_streak(target_board, target_user);
  update public.check_in_boards b
  set updated_at = clock_timestamp()
  where b.id = target_board;
  return null;
end;
$$;

drop trigger if exists check_in_entries_after on public.check_in_entries;
create trigger check_in_entries_after
  after insert or update or delete on public.check_in_entries
  for each row execute function public.check_in_entries_after_change();

revoke execute on function public.check_in_refresh_streak(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function public.check_in_entries_after_change()
  from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'check_in_boards'
    )
  then
    alter publication supabase_realtime add table public.check_in_boards;
  end if;
end;
$$;
