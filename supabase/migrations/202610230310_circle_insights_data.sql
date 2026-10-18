-- Circle insights (C3), part 2 of 3: the numbers, collected once a day.
--
-- Two tables hold them, both closed to clients (the RPC in 202610230320 is
-- the only way to read them):
--
--   * circle_daily_stats   one row per circle and UTC day: members at the end
--                          of the day, people who joined and left, how many
--                          members were active, channel messages, minutes in
--                          voice, the messages per UTC hour (for the weekday
--                          by hour map) and the busiest channels.
--   * circle_member_daily  whether a member was active that day, nothing
--                          else: no channel, no count, no content. It exists
--                          to count distinct active members over a range and
--                          for the "came back" ratio.
--
-- Active means: sent a message in one of the circle's channels, or spent time
-- in its voice channels. Bots and webhook posts are not members being
-- active; recalled and AI-guard-held or removed messages do not count.
--
-- Joins, leaves and voice time are counted as they happen by small triggers
-- (circle_members insert and delete, voice_states delete), because nothing
-- else remembers a person who joined and left on the same day. Everything
-- else is worked out once a day by aggregate_circle_insights(day), run by
-- pg_cron at 00:10 UTC for the day before (and for the two days before that,
-- which only repairs a missed run: the function is idempotent). It does not
-- touch the counted columns. Not run by run_later_dispatch: this is
-- statistics, not a push, so it needs no wake-up and the dispatcher keeps its
-- definition (202610190021).
--
-- Messages that disappearing-messages deleted before the aggregation ran are
-- not counted: the aggregation reads what is still there.
--
-- The column for people who left is left_members: LEFT is a reserved word.

create table if not exists public.circle_daily_stats (
  circle_id uuid not null references public.circles(id) on delete cascade,
  day date not null,
  members_total integer not null default 0,
  joined integer not null default 0,
  left_members integer not null default 0,
  active_members integer not null default 0,
  messages integer not null default 0,
  voice_minutes integer not null default 0,
  -- Messages per UTC hour of the day: hourly[1] is 00:00-00:59.
  hourly integer[] not null default array_fill(0, array[24]),
  -- [{channel_id, count}] for the busiest channels, most messages first.
  top_channels jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (circle_id, day),
  constraint circle_daily_stats_counts check (
    members_total >= 0 and joined >= 0 and left_members >= 0
    and active_members >= 0 and messages >= 0 and voice_minutes >= 0
  ),
  constraint circle_daily_stats_hourly check (cardinality(hourly) = 24),
  constraint circle_daily_stats_channels check (jsonb_typeof(top_channels) = 'array')
);

create table if not exists public.circle_member_daily (
  circle_id uuid not null references public.circles(id) on delete cascade,
  day date not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  primary key (circle_id, day, user_id)
);

create index if not exists circle_member_daily_user_idx
  on public.circle_member_daily (circle_id, user_id, day);

alter table public.circle_daily_stats enable row level security;
alter table public.circle_member_daily enable row level security;
revoke all on public.circle_daily_stats from public, anon, authenticated;
revoke all on public.circle_member_daily from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Counting as it happens
-- ---------------------------------------------------------------------------

-- The UTC day of now().
create or replace function public.insights_today()
returns date
language sql
stable
set search_path = public
as $$
  select (now() at time zone 'utc')::date;
$$;

create or replace function public.circle_members_count_join()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.profiles p where p.id = new.user_id and p.is_bot) then
    return null;
  end if;
  insert into public.circle_daily_stats (circle_id, day, joined)
  values (new.circle_id, public.insights_today(), 1)
  on conflict (circle_id, day) do update
  set joined = circle_daily_stats.joined + 1;
  return null;
end;
$$;

create or replace function public.circle_members_count_leave()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- The circle itself going away takes its members with it.
  if not exists (select 1 from public.circles c where c.id = old.circle_id) then
    return null;
  end if;
  if exists (select 1 from public.profiles p where p.id = old.user_id and p.is_bot) then
    return null;
  end if;
  insert into public.circle_daily_stats (circle_id, day, left_members)
  values (old.circle_id, public.insights_today(), 1)
  on conflict (circle_id, day) do update
  set left_members = circle_daily_stats.left_members + 1;
  return null;
end;
$$;

-- Time in voice is added when the person leaves the channel (a session that
-- crosses midnight counts for the day it ended), at most 12 hours per
-- session so a connection nobody closed does not distort the day.
create or replace function public.voice_states_count_time()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  minutes integer;
begin
  if not exists (select 1 from public.circles c where c.id = old.circle_id) then
    return null;
  end if;
  minutes := least(
    greatest(floor(extract(epoch from (now() - old.joined_at)) / 60), 0),
    720
  )::integer;

  insert into public.circle_daily_stats (circle_id, day, voice_minutes)
  values (old.circle_id, public.insights_today(), minutes)
  on conflict (circle_id, day) do update
  set voice_minutes = circle_daily_stats.voice_minutes + minutes;

  if not exists (select 1 from public.profiles p where p.id = old.user_id and p.is_bot) then
    insert into public.circle_member_daily (circle_id, day, user_id)
    values (old.circle_id, public.insights_today(), old.user_id)
    on conflict do nothing;
  end if;
  return null;
end;
$$;

revoke execute on function public.insights_today() from public, anon, authenticated;
revoke execute on function public.circle_members_count_join() from public, anon, authenticated;
revoke execute on function public.circle_members_count_leave() from public, anon, authenticated;
revoke execute on function public.voice_states_count_time() from public, anon, authenticated;

drop trigger if exists circle_members_count_join on public.circle_members;
create trigger circle_members_count_join
  after insert on public.circle_members
  for each row execute function public.circle_members_count_join();

drop trigger if exists circle_members_count_leave on public.circle_members;
create trigger circle_members_count_leave
  after delete on public.circle_members
  for each row execute function public.circle_members_count_leave();

drop trigger if exists voice_states_count_time on public.voice_states;
create trigger voice_states_count_time
  after delete on public.voice_states
  for each row execute function public.voice_states_count_time();

-- ---------------------------------------------------------------------------
-- The daily aggregation
-- ---------------------------------------------------------------------------

-- Works out [target_day] (UTC) for every circle and returns how many circles
-- it wrote. Idempotent: running it again for the same day rewrites the same
-- row. Leaves joined, left_members and voice_minutes to the triggers above,
-- except that a day with no row yet gets joined from the members' join dates
-- (days before this migration, or a quiet day).
create or replace function public.aggregate_circle_insights(target_day date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  day_start timestamptz := target_day::timestamp at time zone 'UTC';
  day_end timestamptz := (target_day + 1)::timestamp at time zone 'UTC';
  written integer;
begin
  if target_day is null then
    raise exception 'A day is required' using errcode = '22023';
  end if;

  -- Who spoke, where, and when: people only, in a temporary table so the
  -- rest reads it more than once.
  create temp table if not exists pg_temp.insight_messages (
    circle_id uuid,
    channel_id uuid,
    sender_id uuid,
    hour_of_day integer
  ) on commit drop;
  truncate pg_temp.insight_messages;

  insert into pg_temp.insight_messages
  select
    cc.circle_id,
    cc.id,
    m.sender_id,
    extract(hour from m.created_at at time zone 'UTC')::integer
  from public.messages m
  join public.circle_channels cc on cc.conversation_id = m.conversation_id
  join public.profiles p on p.id = m.sender_id and not p.is_bot
  where m.created_at >= day_start
    and m.created_at < day_end
    and m.recalled_at is null
    and m.webhook_id is null
    and m.review_state is distinct from 'held'
    and m.review_state is distinct from 'removed';

  insert into public.circle_member_daily (circle_id, day, user_id)
  select distinct im.circle_id, target_day, im.sender_id
  from pg_temp.insight_messages im
  on conflict do nothing;

  insert into public.circle_daily_stats as s (
    circle_id, day, members_total, joined, active_members, messages,
    hourly, top_channels, updated_at
  )
  select
    c.id,
    target_day,
    coalesce(members.total, 0),
    coalesce(members.joined, 0),
    coalesce(active.total, 0),
    coalesce(msgs.total, 0),
    coalesce(hours.counts, array_fill(0, array[24])),
    coalesce(channels.top, '[]'::jsonb),
    now()
  from public.circles c
  left join lateral (
    select
      count(*)::integer as total,
      count(*) filter (where cm.created_at >= day_start)::integer as joined
    from public.circle_members cm
    join public.profiles p on p.id = cm.user_id and not p.is_bot
    where cm.circle_id = c.id
      and cm.created_at < day_end
  ) members on true
  left join lateral (
    select count(*)::integer as total
    from public.circle_member_daily d
    where d.circle_id = c.id and d.day = target_day
  ) active on true
  left join lateral (
    select count(*)::integer as total
    from pg_temp.insight_messages im
    where im.circle_id = c.id
  ) msgs on true
  left join lateral (
    select array_agg(coalesce(h.n, 0) order by g.hour) as counts
    from generate_series(0, 23) g(hour)
    left join (
      select im.hour_of_day, count(*)::integer as n
      from pg_temp.insight_messages im
      where im.circle_id = c.id
      group by im.hour_of_day
    ) h on h.hour_of_day = g.hour
  ) hours on true
  left join lateral (
    select jsonb_agg(
      jsonb_build_object('channel_id', t.channel_id, 'count', t.n)
      order by t.n desc, t.channel_id
    ) as top
    from (
      select im.channel_id, count(*)::integer as n
      from pg_temp.insight_messages im
      where im.circle_id = c.id
      group by im.channel_id
      order by n desc, im.channel_id
      limit 10
    ) t
  ) channels on true
  on conflict (circle_id, day) do update
  set members_total = excluded.members_total,
      active_members = (
        select count(*)::integer
        from public.circle_member_daily d
        where d.circle_id = s.circle_id and d.day = s.day
      ),
      messages = excluded.messages,
      hourly = excluded.hourly,
      top_channels = excluded.top_channels,
      updated_at = now();
  get diagnostics written = row_count;

  return written;
end;
$$;

-- The nightly run: yesterday, and a repair of the two days before it. Also
-- tidies up: daily rows are kept for 400 days, who-was-active for 120.
create or replace function public.run_circle_insights()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  today date := public.insights_today();
  written integer := 0;
  back integer;
begin
  for back in reverse 3..1 loop
    written := written + public.aggregate_circle_insights(today - back);
  end loop;

  delete from public.circle_daily_stats where day < today - 400;
  delete from public.circle_member_daily where day < today - 120;
  return written;
end;
$$;

revoke execute on function public.aggregate_circle_insights(date)
  from public, anon, authenticated;
revoke execute on function public.run_circle_insights()
  from public, anon, authenticated;
grant execute on function public.aggregate_circle_insights(date) to service_role;
grant execute on function public.run_circle_insights() to service_role;

-- With pg_cron installed (hosted Supabase), run at 00:10 UTC. Without it
-- (local development) nothing is scheduled and this stays a plain function.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'wecord-circle-insights';
    perform cron.schedule(
      'wecord-circle-insights',
      '10 0 * * *',
      'select public.run_circle_insights()'
    );
  end if;
exception when others then
  raise notice 'Could not schedule circle insights with pg_cron: %', sqlerrm;
end $$;

-- The last 30 days, from what is there: messages, who spoke, members by join
-- date. Joins and leaves before today are not known, so joins come from the
-- members' join dates and leaves stay 0.
do $$
declare
  back integer;
begin
  for back in reverse 30..1 loop
    perform public.aggregate_circle_insights(public.insights_today() - back);
  end loop;
end $$;
