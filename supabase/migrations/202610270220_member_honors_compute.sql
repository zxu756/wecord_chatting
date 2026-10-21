-- Member titles and honors (roadmap C7), part 3 of 5: working honors out.
--
-- run_circle_honors() reads circle_member_daily (C3: whether a member was
-- active on a day, nothing else) and writes two things for the people who
-- take part, in circles that have honors on and 5 or more people:
--
--   * circle_member_honor_stats: the running streak (consecutive UTC days of
--     activity ending today or yesterday, looked at over the 120 days C3
--     keeps) and the longest run seen.
--   * circle_member_honors: a streak milestone (7, 30, 100 days) the first
--     time the streak gets there, and for each of the last two completed
--     weeks (Monday to Sunday, UTC) the level of that week: 7 active days
--     is level 3, 5 or 6 is level 2, 3 or 4 is level 1.
--
-- Days, not messages: a person who writes 200 messages in a day gets the
-- same day as one who writes one. Activity is what C3 counts: a message in
-- one of the circle's channels, or time in its voice channels.
--
-- Idempotent: running it twice in a day writes the same rows, so a missed
-- night is repaired by the next. Everything about a person who left, opted
-- out, or whose circle turned honors off is removed. Old weekly rows are
-- kept for 400 days.
--
-- Its own pg_cron job at 00:40 UTC, half an hour after the C3 run
-- (aggregate_circle_insights at 00:10) has put yesterday into
-- circle_member_daily. It is statistics, not a push, so it needs no
-- wake-up; run_later_dispatch is not touched.

create or replace function public.run_circle_honors()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  today date := public.insights_today();
  week_back integer;
  week_first date;
  people integer;
begin
  -- Who takes part: people (not bots, not deleted accounts) who did not
  -- opt out, in circles that have honors on, are not taken down, and have 5
  -- or more people.
  create temp table if not exists pg_temp.honor_people (
    circle_id uuid,
    user_id uuid
  ) on commit drop;
  truncate pg_temp.honor_people;

  insert into pg_temp.honor_people
  select cm.circle_id, cm.user_id
  from public.circles c
  join public.circle_members cm on cm.circle_id = c.id
  join public.profiles p
    on p.id = cm.user_id and not p.is_bot and p.deleted_at is null
  where c.honors_enabled
    and c.disabled_at is null
    and (
      select count(*)
      from public.circle_members x
      join public.profiles xp on xp.id = x.user_id and not xp.is_bot
      where x.circle_id = c.id
    ) >= 5
    and not exists (
      select 1 from public.circle_honor_prefs hp
      where hp.circle_id = cm.circle_id and hp.user_id = cm.user_id
    );
  get diagnostics people = row_count;

  -- The streaks.
  create temp table if not exists pg_temp.honor_streaks (
    circle_id uuid,
    user_id uuid,
    current_streak integer,
    best_streak integer,
    current_first_day date
  ) on commit drop;
  truncate pg_temp.honor_streaks;

  insert into pg_temp.honor_streaks
  with days as (
    select
      d.circle_id,
      d.user_id,
      d.day,
      d.day - (
        row_number() over (
          partition by d.circle_id, d.user_id order by d.day
        )
      )::integer as grp
    from public.circle_member_daily d
    join pg_temp.honor_people hp
      on hp.circle_id = d.circle_id and hp.user_id = d.user_id
    where d.day between today - 119 and today
  ),
  runs as (
    select
      circle_id,
      user_id,
      min(day) as first_day,
      max(day) as last_day,
      count(*)::integer as len
    from days
    group by circle_id, user_id, grp
  )
  select
    hp.circle_id,
    hp.user_id,
    coalesce(cur.len, 0),
    coalesce(best.len, 0),
    cur.first_day
  from pg_temp.honor_people hp
  left join runs cur
    on cur.circle_id = hp.circle_id
    and cur.user_id = hp.user_id
    and cur.last_day >= today - 1
  left join lateral (
    select max(r.len) as len
    from runs r
    where r.circle_id = hp.circle_id and r.user_id = hp.user_id
  ) best on true;

  insert into public.circle_member_honor_stats as s (
    circle_id, user_id, current_streak, best_streak, updated_day
  )
  select
    st.circle_id,
    st.user_id,
    st.current_streak,
    greatest(st.best_streak, st.current_streak),
    today
  from pg_temp.honor_streaks st
  on conflict (circle_id, user_id) do update
  set current_streak = excluded.current_streak,
      best_streak = greatest(s.best_streak, excluded.best_streak),
      updated_day = excluded.updated_day;

  delete from public.circle_member_honor_stats s
  where not exists (
    select 1 from pg_temp.honor_people hp
    where hp.circle_id = s.circle_id and hp.user_id = s.user_id
  );

  -- Streak milestones, once each; the day it was reached is the day the run
  -- got that long.
  insert into public.circle_member_honors (
    circle_id, user_id, kind, level, period_start
  )
  select
    st.circle_id,
    st.user_id,
    'streak',
    m.level,
    st.current_first_day + (m.level - 1)
  from pg_temp.honor_streaks st
  join (values (7), (30), (100)) m(level)
    on st.current_streak >= m.level
  on conflict (circle_id, user_id, level) where kind = 'streak' do nothing;

  -- The last two completed weeks.
  for week_back in 0..1 loop
    week_first := public.honors_week_start() - 7 * week_back;

    create temp table if not exists pg_temp.honor_week (
      circle_id uuid,
      user_id uuid,
      level integer
    ) on commit drop;
    truncate pg_temp.honor_week;

    insert into pg_temp.honor_week
    select
      w.circle_id,
      w.user_id,
      case when w.n = 7 then 3 when w.n >= 5 then 2 else 1 end
    from (
      select d.circle_id, d.user_id, count(*)::integer as n
      from public.circle_member_daily d
      join pg_temp.honor_people hp
        on hp.circle_id = d.circle_id and hp.user_id = d.user_id
      where d.day between week_first and week_first + 6
      group by d.circle_id, d.user_id
    ) w
    where w.n >= 3;

    insert into public.circle_member_honors as h (
      circle_id, user_id, kind, level, period_start
    )
    select hw.circle_id, hw.user_id, 'weekly', hw.level, week_first
    from pg_temp.honor_week hw
    on conflict (circle_id, user_id, period_start) where kind = 'weekly'
    do update set level = excluded.level;

    delete from public.circle_member_honors h
    where h.kind = 'weekly'
      and h.period_start = week_first
      and not exists (
        select 1 from pg_temp.honor_week hw
        where hw.circle_id = h.circle_id and hw.user_id = h.user_id
      );
  end loop;

  -- Honors of people who no longer take part (they opted out, or the circle
  -- turned honors off or shrank) are not kept.
  delete from public.circle_member_honors h
  where not exists (
    select 1 from pg_temp.honor_people hp
    where hp.circle_id = h.circle_id and hp.user_id = h.user_id
  );

  delete from public.circle_member_honors
  where kind = 'weekly' and period_start < today - 400;

  return people;
end;
$$;

revoke execute on function public.run_circle_honors()
  from public, anon, authenticated;
grant execute on function public.run_circle_honors() to service_role;

-- With pg_cron installed (hosted Supabase), run at 00:40 UTC. Without it
-- (local development) nothing is scheduled and this stays a plain function.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'wecord-circle-honors';
    perform cron.schedule(
      'wecord-circle-honors',
      '40 0 * * *',
      'select public.run_circle_honors()'
    );
  end if;
exception when others then
  raise notice 'Could not schedule circle honors with pg_cron: %', sqlerrm;
end $$;
