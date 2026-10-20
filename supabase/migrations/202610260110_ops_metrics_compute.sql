-- Product statistics (K2), part 2 of 3: filling the tables, on a schedule of
-- their own. run_later_dispatch() is not touched.
--
-- * ops_tick() every 15 minutes: notes who was active in the last 20
--   minutes (sessions that registered, people the presence heartbeat saw,
--   people who sent a message: all indexed lookups), samples how many people
--   are in a voice channel (each sample counts 15 minutes) and recomputes
--   today's row.
-- * ops_daily_close() at 00:20 UTC: finishes yesterday (people who posted,
--   the storage total), works out retention for the days that are over,
--   and deletes what is old.
-- * ops_record_push() is called by the push functions with counts only.
--
-- A recomputed day never goes down: counts take the larger of the old and
-- the new value, because a source row may be deleted before the day closes
-- (a disappearing message, a story after 24 hours).
--
-- With pg_cron installed (hosted Supabase) the two jobs are scheduled;
-- without it (local development) they are plain functions.

-- Per key, the larger of two {"key": number} objects.
create or replace function public.ops_merge_max(a jsonb, b jsonb)
returns jsonb
language sql
immutable
as $$
  select coalesce(jsonb_object_agg(m.k, m.v), '{}'::jsonb)
  from (
    select x.k, max(x.v) as v
    from (
      select e.key as k, e.value::numeric as v
      from jsonb_each_text(coalesce(a, '{}'::jsonb)) e
      union all
      select e.key, e.value::numeric
      from jsonb_each_text(coalesce(b, '{}'::jsonb)) e
    ) x
    group by x.k
  ) m;
$$;

revoke execute on function public.ops_merge_max(jsonb, jsonb)
  from public, anon, authenticated;

-- Notes who was active lately. Indexed lookups only, so it is cheap to run
-- every 15 minutes.
create or replace function public.ops_record_activity(window_minutes integer default 20)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  since timestamptz := now() - make_interval(mins => least(greatest(coalesce(window_minutes, 20), 1), 1440));
  added integer := 0;
  step integer;
begin
  -- Sessions that registered (the app was opened): with their platform and
  -- version.
  insert into public.ops_active_days (day, user_key, platform, app_version)
  select
    (d.last_active_at at time zone 'utc')::date,
    public.ops_user_key(d.user_id),
    lower(left(d.platform, 20)),
    left(d.app_version, 32)
  from public.user_devices d
  where d.last_active_at > since
  on conflict do nothing;
  get diagnostics step = row_count;
  added := added + step;

  -- People the presence heartbeat saw.
  insert into public.ops_active_days (day, user_key)
  select (h.seen_at at time zone 'utc')::date, public.ops_user_key(h.user_id)
  from public.presence_heartbeats h
  where h.seen_at > since
  on conflict do nothing;
  get diagnostics step = row_count;
  added := added + step;

  -- People who sent a message.
  insert into public.ops_active_days (day, user_key)
  select distinct (m.created_at at time zone 'utc')::date, public.ops_user_key(m.sender_id)
  from public.messages m
  where m.created_at > since
  on conflict do nothing;
  get diagnostics step = row_count;
  added := added + step;

  return added;
end;
$$;

-- Notes who was active on [d] by what they made: messages, posts in circles,
-- moments and stories. A scan of one day, for the night close and the
-- backfill.
create or replace function public.ops_record_activity_day(d date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  day_start timestamptz := d::timestamp at time zone 'utc';
  day_end timestamptz := (d + 1)::timestamp at time zone 'utc';
  added integer := 0;
  step integer;
begin
  insert into public.ops_active_days (day, user_key)
  select distinct d, public.ops_user_key(m.sender_id)
  from public.messages m
  where m.created_at >= day_start and m.created_at < day_end
  on conflict do nothing;
  get diagnostics step = row_count;
  added := added + step;

  insert into public.ops_active_days (day, user_key)
  select distinct d, public.ops_user_key(p.author_id)
  from public.circle_posts p
  where p.created_at >= day_start and p.created_at < day_end
  on conflict do nothing;
  get diagnostics step = row_count;
  added := added + step;

  insert into public.ops_active_days (day, user_key)
  select distinct d, public.ops_user_key(p.author_id)
  from public.moments_posts p
  where p.created_at >= day_start and p.created_at < day_end
  on conflict do nothing;
  get diagnostics step = row_count;
  added := added + step;

  insert into public.ops_active_days (day, user_key)
  select distinct d, public.ops_user_key(s.author_id)
  from public.stories s
  where s.created_at >= day_start and s.created_at < day_end
  on conflict do nothing;
  get diagnostics step = row_count;
  added := added + step;

  return added;
end;
$$;

-- Works out (or refreshes) the row of [d] from what the database knows. The
-- voice minutes and the storage are not touched here (the tick and the close
-- write them).
create or replace function public.ops_compute_day(d date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  day_start timestamptz := d::timestamp at time zone 'utc';
  day_end timestamptz := (d + 1)::timestamp at time zone 'utc';
  active integer;
  signed_up integer;
  by_type jsonb;
  total_messages integer;
  features jsonb;
  ai_total integer;
  ai_people integer;
  p_sent integer;
  p_failed integer;
  p_gone integer;
  reports integer;
begin
  select count(distinct a.user_key) into active
  from public.ops_active_days a
  where a.day = d;

  select count(*) into signed_up
  from public.profiles p
  where p.created_at >= day_start and p.created_at < day_end;

  select
    coalesce(jsonb_object_agg(t.type, t.n), '{}'::jsonb),
    coalesce(sum(t.n), 0)
  into by_type, total_messages
  from (
    select m.type, count(*) as n
    from public.messages m
    where m.created_at >= day_start and m.created_at < day_end
    group by m.type
  ) t;

  features := jsonb_build_object(
    'circle_posts', (
      select count(*) from public.circle_posts p
      where p.created_at >= day_start and p.created_at < day_end
    ),
    'moments', (
      select count(*) from public.moments_posts p
      where p.created_at >= day_start and p.created_at < day_end
    ),
    'stories', (
      select count(*) from public.stories s
      where s.created_at >= day_start and s.created_at < day_end
    ),
    'notes', (
      select count(*) from public.notes n
      where n.created_at >= day_start and n.created_at < day_end
    ),
    'tasks', (
      select count(*) from public.task_items i
      where i.created_at >= day_start and i.created_at < day_end
    ),
    'chat_events', (
      select count(*) from public.chat_events e
      where e.created_at >= day_start and e.created_at < day_end
    )
  );

  select
    coalesce(sum(u.requests), 0),
    count(*) filter (where u.requests > 0)
  into ai_total, ai_people
  from public.ai_usage u
  where u.day = d;
  -- The AI guard's requests are charged to the circle.
  select ai_total + coalesce(sum(u.requests), 0) into ai_total
  from public.ai_circle_usage u
  where u.day = d;

  select
    coalesce(sum(s.sent), 0),
    coalesce(sum(s.failed), 0),
    coalesce(sum(s.gone), 0)
  into p_sent, p_failed, p_gone
  from public.ops_push_stats s
  where s.hour >= day_start and s.hour < day_end;

  select coalesce(sum(e.count), 0) into reports
  from public.client_errors e
  where e.created_at >= day_start and e.created_at < day_end;

  insert into public.ops_daily_metrics as m (
    day, active_users, new_users, messages_total, messages_by_type,
    feature_counts, ai_requests, ai_users, push_sent, push_failed, push_gone,
    error_reports
  )
  values (
    d, active, signed_up, total_messages, by_type, features, ai_total,
    ai_people, p_sent, p_failed, p_gone, reports
  )
  on conflict (day) do update
  set computed_at = now(),
      active_users = greatest(m.active_users, excluded.active_users),
      new_users = greatest(m.new_users, excluded.new_users),
      messages_total = greatest(m.messages_total, excluded.messages_total),
      messages_by_type = public.ops_merge_max(m.messages_by_type, excluded.messages_by_type),
      feature_counts = public.ops_merge_max(m.feature_counts, excluded.feature_counts),
      ai_requests = greatest(m.ai_requests, excluded.ai_requests),
      ai_users = greatest(m.ai_users, excluded.ai_users),
      push_sent = greatest(m.push_sent, excluded.push_sent),
      push_failed = greatest(m.push_failed, excluded.push_failed),
      push_gone = greatest(m.push_gone, excluded.push_gone),
      error_reports = greatest(m.error_reports, excluded.error_reports);
end;
$$;

-- How many of each finished day's new people were active 1, 7 and 30 days
-- later. A figure is written once, when that later day is over.
create or replace function public.ops_finalize_retention(today date)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.ops_daily_metrics m
  set d1_retained = (
    select count(*)::integer
    from public.profiles p
    where p.created_at >= m.day::timestamp at time zone 'utc'
      and p.created_at < (m.day + 1)::timestamp at time zone 'utc'
      and exists (
        select 1 from public.ops_active_days a
        where a.user_key = public.ops_user_key(p.id) and a.day = m.day + 1
      )
  )
  where m.d1_retained is null and m.day + 1 < today;

  update public.ops_daily_metrics m
  set d7_retained = (
    select count(*)::integer
    from public.profiles p
    where p.created_at >= m.day::timestamp at time zone 'utc'
      and p.created_at < (m.day + 1)::timestamp at time zone 'utc'
      and exists (
        select 1 from public.ops_active_days a
        where a.user_key = public.ops_user_key(p.id) and a.day = m.day + 7
      )
  )
  where m.d7_retained is null and m.day + 7 < today;

  update public.ops_daily_metrics m
  set d30_retained = (
    select count(*)::integer
    from public.profiles p
    where p.created_at >= m.day::timestamp at time zone 'utc'
      and p.created_at < (m.day + 1)::timestamp at time zone 'utc'
      and exists (
        select 1 from public.ops_active_days a
        where a.user_key = public.ops_user_key(p.id) and a.day = m.day + 30
      )
  )
  where m.d30_retained is null and m.day + 30 < today;
end;
$$;

-- Everything in the storage buckets, as the total of [d] (taken when the day
-- closes), and what was added since the day before. Quietly does nothing
-- where Storage is not installed.
create or replace function public.ops_snapshot_storage(d date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  total bigint;
  before_total bigint;
begin
  if to_regclass('storage.objects') is null then
    return;
  end if;
  begin
    execute $q$
      select coalesce(sum(
        case when (o.metadata->>'size') ~ '^[0-9]{1,15}$'
          then (o.metadata->>'size')::bigint else 0 end
      ), 0)
      from storage.objects o
    $q$ into total;
  exception when others then
    return;
  end;

  select m.storage_bytes into before_total
  from public.ops_daily_metrics m
  where m.day = d - 1;

  update public.ops_daily_metrics m
  set storage_bytes = total,
      storage_added = case when before_total is null then null else total - before_total end
  where m.day = d;
end;
$$;

-- Every 15 minutes.
create or replace function public.ops_tick()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  today date := (now() at time zone 'utc')::date;
  talking integer;
begin
  perform public.ops_record_activity(20);

  select count(*) into talking
  from public.voice_states v
  where v.last_seen_at > now() - interval '2 minutes';

  perform public.ops_compute_day(today);

  -- Each sample stands for the 15 minutes until the next one.
  update public.ops_daily_metrics m
  set voice_minutes = m.voice_minutes + talking * 15
  where m.day = today;
end;
$$;

-- At 00:20 UTC: finishes yesterday and tidies up.
create or replace function public.ops_daily_close()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  today date := (now() at time zone 'utc')::date;
  yesterday date := (now() at time zone 'utc')::date - 1;
begin
  perform public.ops_record_activity_day(yesterday);
  perform public.ops_compute_day(yesterday);
  perform public.ops_snapshot_storage(yesterday);
  perform public.ops_compute_day(today);
  perform public.ops_finalize_retention(today);

  delete from public.ops_active_days a where a.day < today - 45;
  delete from public.ops_push_stats s where s.hour < now() - interval '60 days';
  delete from public.ops_daily_metrics m where m.day < today - 400;
  -- (ops_error_groups comes with 202610260130.)
  delete from public.ops_error_groups g where g.last_seen_at < now() - interval '90 days';
end;
$$;

-- The push functions report how a round of pushes went: counts only.
create or replace function public.ops_record_push(
  sent_count integer,
  failed_count integer,
  gone_count integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  s integer := least(greatest(coalesce(sent_count, 0), 0), 1000000);
  f integer := least(greatest(coalesce(failed_count, 0), 0), 1000000);
  g integer := least(greatest(coalesce(gone_count, 0), 0), 1000000);
begin
  if s = 0 and f = 0 and g = 0 then
    return;
  end if;
  insert into public.ops_push_stats as p (hour, sent, failed, gone)
  values (date_trunc('hour', now()), s, f, g)
  on conflict (hour) do update
  set sent = p.sent + excluded.sent,
      failed = p.failed + excluded.failed,
      gone = p.gone + excluded.gone;
end;
$$;

revoke execute on function public.ops_record_activity(integer)
  from public, anon, authenticated;
revoke execute on function public.ops_record_activity_day(date)
  from public, anon, authenticated;
revoke execute on function public.ops_compute_day(date)
  from public, anon, authenticated;
revoke execute on function public.ops_finalize_retention(date)
  from public, anon, authenticated;
revoke execute on function public.ops_snapshot_storage(date)
  from public, anon, authenticated;
revoke execute on function public.ops_tick() from public, anon, authenticated;
revoke execute on function public.ops_daily_close() from public, anon, authenticated;
revoke execute on function public.ops_record_push(integer, integer, integer)
  from public, anon, authenticated;
grant execute on function public.ops_record_push(integer, integer, integer)
  to service_role;

-- The first days: what the database can still tell about the last 30 days.
do $$
declare
  today date := (now() at time zone 'utc')::date;
  d date;
begin
  for d in select g::date from generate_series(today - 30, today - 1, interval '1 day') g loop
    perform public.ops_record_activity_day(d);
    perform public.ops_compute_day(d);
  end loop;
  perform public.ops_record_activity(20);
  perform public.ops_compute_day(today);
  perform public.ops_finalize_retention(today);
end $$;

-- With pg_cron installed (hosted Supabase), run on a schedule of their own.
-- Without it (local development) nothing is scheduled.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'wecord-ops-tick',
      '*/15 * * * *',
      'select public.ops_tick()'
    );
    perform cron.schedule(
      'wecord-ops-daily-close',
      '20 0 * * *',
      'select public.ops_daily_close()'
    );
  end if;
end $$;
