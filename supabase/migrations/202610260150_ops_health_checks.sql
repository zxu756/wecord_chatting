-- Monitoring and alerts (K3), part 2 of 4: the alert engine and the checks.
-- run_later_dispatch() is not touched: the checks run from a job of their
-- own, ops_health_check(), every 5 minutes.
--
-- What is looked at (all of it is WeCord's own data in this Supabase project):
--
--   cron_dispatch   the every-minute dispatcher (wecord-later-dispatch) has a
--                   successful run in the cron history. warn after 4 minutes
--                   without one, fail after 10.
--   cron_failures   failed runs of any cron job in the last 30 minutes. warn
--                   at 2 for one job, fail at 5.
--   edge_wakes      the answers to the wake-up calls this database sends to
--                   Edge Functions (pg_net's response table): the share of
--                   errors and time-outs in the last 15 minutes, with at
--                   least 5 calls. warn at a quarter, fail at a half.
--   push_failures   ops_push_stats: pushes that failed (not the dead
--                   subscriptions, which are normal) in the last hour, with
--                   at least 20 attempts. warn at a quarter, fail at a half.
--   error_spike     error reports in the last hour against the hourly
--                   average of the 24 hours before. warn at 4 times and at
--                   least 30, fail at 10 times and at least 100.
--   ai_quota        the AI limits (ops_settings ai_user_daily_limit, 50, and
--                   ai_guard_circle_limit, 500, as in the ai function). fail
--                   when a circle's guard has used up its day, warn when one
--                   is at 90% or five people hit their own limit.
--   version_health  per app version (at least 10 people in the last day, ops
--                   setting version_health_min_users): the share of people
--                   with a crash. warn at 5%, fail at 10%.
--   new_errors      an error group that was never seen before and has at
--                   least 3 reports (event alerts, one per group, up to
--                   three at a time and then one for the rest).
--   heartbeat       written on every run; the console warns when it is old,
--                   which is how a stopped cron shows (the checks run from
--                   cron too).
--
-- A check that cannot look (pg_cron or pg_net missing, as in local
-- development) is 'unknown' and raises nothing.
--
-- Alerts: ops_raise_alert opens one alert per check key (or updates the open
-- one, or reopens one that closed less than an hour ago without saying
-- anything again). A new alert is also written as an official card for each
-- owner and moderator (announcements kind 'ops_alert') and, when it is a
-- 'fail', wakes the dispatcher for its push (202610260170). A state alert
-- closes by itself when its check has been ok twice in a row; an event alert
-- closes after 24 hours. Closing an alert takes its cards back.

create or replace function public.ops_set_check(
  p_key text,
  p_status text,
  p_detail jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  streak integer;
begin
  insert into public.ops_checks as c (key, status, detail, checked_at, changed_at, ok_streak)
  values (
    p_key,
    p_status,
    coalesce(p_detail, '{}'::jsonb),
    now(),
    now(),
    case when p_status = 'ok' then 1 else 0 end
  )
  on conflict (key) do update
  set detail = excluded.detail,
      checked_at = now(),
      changed_at = case when c.status = excluded.status then c.changed_at else now() end,
      ok_streak = case when excluded.status = 'ok' then c.ok_streak + 1 else 0 end,
      status = excluded.status
  returning c.ok_streak into streak;
  return streak;
end;
$$;

-- Closes the open alert of [p_key] and takes its cards back.
create or replace function public.ops_close_alert(
  p_key text,
  p_by uuid,
  p_how text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  closed integer;
begin
  with done as (
    update public.ops_alerts a
    set resolved_at = now(),
        resolved_by = p_by,
        resolution = p_how,
        updated_at = now()
    where a.check_key = p_key and a.resolved_at is null
    returning a.id
  ), cards as (
    update public.announcements n
    set retracted_at = now()
    from done
    where n.ops_alert_id = done.id and n.retracted_at is null
    returning n.id
  )
  select count(*) into closed from done;
  return closed;
end;
$$;

-- Opens, updates or reopens the alert of [p_key]. Returns its id.
create or replace function public.ops_raise_alert(
  p_key text,
  p_kind text,
  p_severity text,
  t_en text,
  t_zh text,
  b_en text,
  b_zh text,
  p_detail jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  existing public.ops_alerts;
  alert_id uuid;
  title_en_v text := left(coalesce(t_en, ''), 120);
  title_zh_v text := left(coalesce(t_zh, ''), 120);
  body_en_v text := left(coalesce(b_en, ''), 600);
  body_zh_v text := left(coalesce(b_zh, ''), 600);
begin
  select * into existing
  from public.ops_alerts a
  where a.check_key = p_key and a.resolved_at is null
  for update;

  if found then
    update public.ops_alerts a
    set severity = case when p_severity = 'fail' then 'fail' else a.severity end,
        -- A warning that turns into a failure may be pushed.
        push_claimed_at = case
          when p_severity = 'fail' and a.severity = 'warn' then null
          else a.push_claimed_at
        end,
        title_en = title_en_v,
        title_zh = title_zh_v,
        body_en = body_en_v,
        body_zh = body_zh_v,
        detail = coalesce(p_detail, '{}'::jsonb),
        updated_at = now()
    where a.id = existing.id;
    update public.announcements n
    set title_en = title_en_v, title_zh = title_zh_v,
        body_en = body_en_v, body_zh = body_zh_v
    where n.ops_alert_id = existing.id and n.retracted_at is null;
    if p_severity = 'fail' and existing.severity = 'warn' then
      perform public.wake_scheduled_dispatch();
    end if;
    return existing.id;
  end if;

  -- One that closed a moment ago and is back: the same alert, quietly.
  select * into existing
  from public.ops_alerts a
  where a.check_key = p_key
    and a.kind = 'state'
    and a.resolved_at > now() - interval '1 hour'
  order by a.resolved_at desc
  limit 1
  for update;
  if found then
    update public.ops_alerts a
    set resolved_at = null,
        resolved_by = null,
        resolution = null,
        reopen_count = a.reopen_count + 1,
        severity = p_severity,
        title_en = title_en_v,
        title_zh = title_zh_v,
        body_en = body_en_v,
        body_zh = body_zh_v,
        detail = coalesce(p_detail, '{}'::jsonb),
        updated_at = now()
    where a.id = existing.id;
    update public.announcements n
    set retracted_at = null,
        title_en = title_en_v, title_zh = title_zh_v,
        body_en = body_en_v, body_zh = body_zh_v
    where n.ops_alert_id = existing.id;
    return existing.id;
  end if;

  insert into public.ops_alerts (
    check_key, kind, severity, title_en, title_zh, body_en, body_zh, detail
  )
  values (
    p_key,
    case when p_kind = 'event' then 'event' else 'state' end,
    case when p_severity = 'fail' then 'fail' else 'warn' end,
    title_en_v, title_zh_v, body_en_v, body_zh_v,
    coalesce(p_detail, '{}'::jsonb)
  )
  returning id into alert_id;

  insert into public.announcements (
    kind, title_en, title_zh, body_en, body_zh, audience_user_id, ops_alert_id
  )
  select
    'ops_alert', title_en_v, title_zh_v, body_en_v, body_zh_v, a.user_id, alert_id
  from public.app_admins a
  where a.role in ('owner', 'moderator');

  if p_severity = 'fail' then
    perform public.wake_scheduled_dispatch();
  end if;
  return alert_id;
end;
$$;

-- Records a check's result and raises or closes its alert.
create or replace function public.ops_apply_check(
  p_key text,
  p_status text,
  t_en text,
  t_zh text,
  b_en text,
  b_zh text,
  p_detail jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  streak integer;
begin
  streak := public.ops_set_check(p_key, p_status, p_detail);
  if p_status in ('warn', 'fail') then
    perform public.ops_raise_alert(p_key, 'state', p_status, t_en, t_zh, b_en, b_zh, p_detail);
  elsif p_status = 'ok' and streak >= 2 then
    perform public.ops_close_alert(p_key, null, 'auto');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- The checks
-- ---------------------------------------------------------------------------

create or replace function public.ops_check_cron()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  has_job boolean;
  last_ok timestamptz;
  minutes integer;
  status text := 'ok';
  jobs jsonb;
  worst integer;
  total integer;
  failure_status text := 'ok';
  names text;
begin
  if to_regclass('cron.job_run_details') is null or to_regclass('cron.job') is null then
    perform public.ops_set_check('cron_dispatch', 'unknown', '{"reason": "pg_cron is not installed"}');
    perform public.ops_set_check('cron_failures', 'unknown', '{"reason": "pg_cron is not installed"}');
    return;
  end if;

  execute $q$select exists (select 1 from cron.job j where j.jobname = 'wecord-later-dispatch')$q$
    into has_job;
  if not has_job then
    perform public.ops_set_check('cron_dispatch', 'unknown', '{"reason": "the dispatcher is not scheduled"}');
  else
    execute $q$
      select max(d.end_time)
      from cron.job_run_details d
      join cron.job j on j.jobid = d.jobid
      where j.jobname = 'wecord-later-dispatch' and d.status = 'succeeded'
    $q$ into last_ok;
    if last_ok is null then
      minutes := null;
      status := 'fail';
    else
      minutes := floor(extract(epoch from (now() - last_ok)) / 60)::integer;
      status := case
        when minutes >= 10 then 'fail'
        when minutes >= 4 then 'warn'
        else 'ok'
      end;
    end if;
    perform public.ops_apply_check(
      'cron_dispatch',
      status,
      'Scheduled tasks have stopped',
      '定时任务停了',
      case when minutes is null
        then 'The every-minute dispatcher (wecord-later-dispatch) has no successful run on record. Scheduled messages, reminders and pushes are not going out.'
        else format('The every-minute dispatcher (wecord-later-dispatch) has not finished a run for %s minutes. Scheduled messages, reminders and pushes may not be going out.', minutes)
      end,
      case when minutes is null
        then '每分钟的调度任务（wecord-later-dispatch）没有成功运行的记录，定时消息、提醒和推送发不出去。'
        else format('每分钟的调度任务（wecord-later-dispatch）已有 %s 分钟没有成功运行，定时消息、提醒和推送可能发不出去。', minutes)
      end,
      jsonb_build_object('minutes_since_success', minutes)
    );
  end if;

  execute $q$
    select
      coalesce(jsonb_agg(jsonb_build_object('job', x.name, 'failed', x.n) order by x.n desc), '[]'::jsonb),
      coalesce(max(x.n), 0)::integer,
      coalesce(sum(x.n), 0)::integer
    from (
      select coalesce(j.jobname, d.jobid::text) as name, count(*) as n
      from cron.job_run_details d
      left join cron.job j on j.jobid = d.jobid
      where d.status = 'failed' and d.start_time > now() - interval '30 minutes'
      group by 1
    ) x
  $q$ into jobs, worst, total;
  failure_status := case
    when worst >= 5 then 'fail'
    when worst >= 2 then 'warn'
    else 'ok'
  end;
  select string_agg(format('%s (%s)', e->>'job', e->>'failed'), ', ')
  into names
  from (select e from jsonb_array_elements(jobs) e limit 5) t;
  perform public.ops_apply_check(
    'cron_failures',
    failure_status,
    'Scheduled jobs are failing',
    '定时任务在报错',
    format('In the last 30 minutes these jobs failed: %s. Look at cron.job_run_details for the message.', coalesce(names, '-')),
    format('最近 30 分钟内这些任务运行失败：%s。错误信息见 cron.job_run_details。', coalesce(names, '-')),
    jsonb_build_object('failed_runs', total, 'jobs', jobs)
  );
end;
$$;

create or replace function public.ops_check_wakes()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  total integer;
  bad integer;
  status text;
  share integer;
begin
  if to_regclass('net._http_response') is null then
    perform public.ops_set_check('edge_wakes', 'unknown', '{"reason": "pg_net is not installed"}');
    return;
  end if;
  execute $q$
    select
      count(*)::integer,
      count(*) filter (
        where r.timed_out is true
          or r.error_msg is not null
          or r.status_code is null
          or r.status_code >= 400
      )::integer
    from net._http_response r
    where r.created > now() - interval '15 minutes'
  $q$ into total, bad;
  share := case when total = 0 then 0 else round(100.0 * bad / total)::integer end;
  status := case
    when total < 5 then 'ok'
    when bad * 2 >= total then 'fail'
    when bad * 4 >= total then 'warn'
    else 'ok'
  end;
  perform public.ops_apply_check(
    'edge_wakes',
    status,
    'Edge Functions are not answering',
    '边缘函数没有正常响应',
    format('%s of the last %s wake-up calls to Edge Functions failed (%s%%) in 15 minutes. Check the function logs and the DISPATCH_SECRET.', bad, total, share),
    format('最近 15 分钟内对边缘函数的 %s 次唤醒调用中有 %s 次失败（%s%%）。请检查函数日志和 DISPATCH_SECRET。', total, bad, share),
    jsonb_build_object('calls', total, 'failed', bad)
  );
end;
$$;

create or replace function public.ops_check_push()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  sent_n integer;
  failed_n integer;
  attempts integer;
  status text;
  share integer;
begin
  select coalesce(sum(s.sent), 0), coalesce(sum(s.failed), 0)
  into sent_n, failed_n
  from public.ops_push_stats s
  where s.hour > date_trunc('hour', now()) - interval '1 hour';
  attempts := sent_n + failed_n;
  share := case when attempts = 0 then 0 else round(100.0 * failed_n / attempts)::integer end;
  status := case
    when attempts < 20 then 'ok'
    when failed_n * 2 >= attempts then 'fail'
    when failed_n * 4 >= attempts then 'warn'
    else 'ok'
  end;
  perform public.ops_apply_check(
    'push_failures',
    status,
    'Many pushes are failing',
    '大量推送失败',
    format('%s of %s pushes failed (%s%%) in the last hour or so. Check the VAPID keys and the push service.', failed_n, attempts, share),
    format('最近约一小时内 %s 条推送中有 %s 条失败（%s%%）。请检查 VAPID 密钥和推送服务。', attempts, failed_n, share),
    jsonb_build_object('attempts', attempts, 'failed', failed_n)
  );
end;
$$;

create or replace function public.ops_check_error_spike()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  recent integer;
  before_total integer;
  baseline numeric;
  status text;
begin
  select count(*)::integer into recent
  from public.client_errors e
  where e.created_at > now() - interval '1 hour';
  select count(*)::integer into before_total
  from public.client_errors e
  where e.created_at > now() - interval '25 hours'
    and e.created_at <= now() - interval '1 hour';
  baseline := before_total / 24.0;
  status := case
    when recent >= greatest(100, 10 * baseline) then 'fail'
    when recent >= greatest(30, 4 * baseline) then 'warn'
    else 'ok'
  end;
  perform public.ops_apply_check(
    'error_spike',
    status,
    'Error reports are spiking',
    '错误报告激增',
    format('%s error reports in the last hour, against about %s an hour over the day before.', recent, round(baseline, 1)),
    format('最近一小时收到 %s 条错误报告，前一天平均每小时约 %s 条。', recent, round(baseline, 1)),
    jsonb_build_object('last_hour', recent, 'hourly_average', round(baseline, 1))
  );
end;
$$;

create or replace function public.ops_check_ai()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  today date := (now() at time zone 'utc')::date;
  user_cap integer := greatest(public.ops_setting_int('ai_user_daily_limit', 50), 1);
  circle_cap integer := greatest(public.ops_setting_int('ai_guard_circle_limit', 500), 1);
  users_at_cap integer;
  circles_at_cap integer;
  circles_near integer;
  status text;
begin
  select count(*)::integer into users_at_cap
  from public.ai_usage u
  where u.day = today and u.requests >= user_cap;
  select
    count(*) filter (where u.requests >= circle_cap)::integer,
    count(*) filter (where u.requests * 10 >= circle_cap * 9)::integer
  into circles_at_cap, circles_near
  from public.ai_circle_usage u
  where u.day = today;
  status := case
    when circles_at_cap >= 1 then 'fail'
    when circles_near >= 1 or users_at_cap >= 5 then 'warn'
    else 'ok'
  end;
  perform public.ops_apply_check(
    'ai_quota',
    status,
    case when status = 'fail' then 'AI limit reached' else 'AI use is near its limit' end,
    case when status = 'fail' then 'AI 额度用完了' else 'AI 用量接近上限' end,
    format('Today %s circle(s) used up the AI guard''s daily limit (%s), %s are near it, and %s people reached their own limit (%s).', circles_at_cap, circle_cap, circles_near, users_at_cap, user_cap),
    format('今天有 %s 个圈子用完了 AI 守护的每日额度（%s），%s 个接近上限，%s 人用完了自己的每日额度（%s）。', circles_at_cap, circle_cap, circles_near, users_at_cap, user_cap),
    jsonb_build_object(
      'circles_at_limit', circles_at_cap,
      'circles_near_limit', circles_near,
      'people_at_limit', users_at_cap
    )
  );
end;
$$;

create or replace function public.ops_check_versions()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  today date := (now() at time zone 'utc')::date;
  min_users integer := greatest(public.ops_setting_int('version_health_min_users', 10), 1);
  worst record;
  status text := 'ok';
  share integer;
begin
  select v.app_version, v.platform, v.active_users, coalesce(c.crash_users, 0) as crash_users
  into worst
  from (
    select a.app_version, a.platform, count(distinct a.user_key)::integer as active_users
    from public.ops_active_days a
    where a.day >= today - 1 and a.app_version <> ''
    group by a.app_version, a.platform
    having count(distinct a.user_key) >= min_users
  ) v
  left join (
    select e.app_version, lower(e.platform) as platform, count(distinct e.user_id)::integer as crash_users
    from public.client_errors e
    where e.created_at > now() - interval '24 hours'
      and e.kind in ('flutter_error', 'platform_error', 'zone_error')
    group by e.app_version, lower(e.platform)
  ) c on c.app_version = v.app_version and c.platform = v.platform
  order by coalesce(c.crash_users, 0)::numeric / v.active_users desc
  limit 1;

  if worst.app_version is null then
    perform public.ops_set_check('version_health', 'ok', '{"reason": "no version has enough people yet"}');
    perform public.ops_close_alert('version_health', null, 'auto');
    return;
  end if;
  share := round(100.0 * worst.crash_users / worst.active_users)::integer;
  status := case
    when worst.crash_users * 10 >= worst.active_users then 'fail'
    when worst.crash_users * 20 >= worst.active_users then 'warn'
    else 'ok'
  end;
  perform public.ops_apply_check(
    'version_health',
    status,
    format('Version %s is crashing', worst.app_version),
    format('版本 %s 在崩溃', worst.app_version),
    format('%s of %s people on %s (%s) hit a crash in the last day (%s%%).', worst.crash_users, worst.active_users, worst.app_version, worst.platform, share),
    format('%s（%s）上的 %s 位用户中有 %s 位在最近一天遇到崩溃（%s%%）。', worst.app_version, worst.platform, worst.active_users, worst.crash_users, share),
    jsonb_build_object(
      'app_version', worst.app_version,
      'platform', worst.platform,
      'active_users', worst.active_users,
      'crash_users', worst.crash_users
    )
  );
end;
$$;

create or replace function public.ops_check_new_errors()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  fresh public.ops_error_groups;
  listed integer := 0;
  total integer;
begin
  -- A group that stayed small for a day is not news any more.
  update public.ops_error_groups g
  set alerted_at = now()
  where g.alerted_at is null
    and g.reports < 3
    and g.first_seen_at < now() - interval '24 hours';

  select count(*)::integer into total
  from public.ops_error_groups g
  where g.alerted_at is null and g.reports >= 3;

  for fresh in
    select * from public.ops_error_groups g
    where g.alerted_at is null and g.reports >= 3
    order by g.first_seen_at
  loop
    if listed < 3 then
      perform public.ops_raise_alert(
        'new_error_' || fresh.group_key,
        'event',
        'warn',
        'New kind of error: ' || fresh.kind,
        '出现新的错误类型：' || fresh.kind,
        format('%s. First seen in version %s, %s reports so far.', fresh.label, coalesce(nullif(fresh.first_version, ''), '?'), fresh.reports),
        format('%s。首次出现在版本 %s，目前已有 %s 条报告。', fresh.label, coalesce(nullif(fresh.first_version, ''), '?'), fresh.reports),
        jsonb_build_object('group_key', fresh.group_key, 'kind', fresh.kind, 'reports', fresh.reports)
      );
    end if;
    listed := listed + 1;
    update public.ops_error_groups g set alerted_at = now() where g.group_key = fresh.group_key;
  end loop;

  if listed > 3 then
    perform public.ops_raise_alert(
      'new_error_many',
      'event',
      'warn',
      format('%s more new kinds of error', listed - 3),
      format('另有 %s 种新的错误类型', listed - 3),
      format('%s new error groups showed up together with the ones above. See the error list in the console.', listed - 3),
      format('另有 %s 个新的错误分组同时出现，详见后台的错误列表。', listed - 3),
      jsonb_build_object('groups', listed - 3)
    );
  end if;

  perform public.ops_set_check('new_errors', 'ok', jsonb_build_object('new_groups', listed));
end;
$$;

-- Every 5 minutes.
create or replace function public.ops_health_check()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  step record;
begin
  for step in
    select * from (values
      ('cron', 'ops_check_cron'),
      ('edge_wakes', 'ops_check_wakes'),
      ('push_failures', 'ops_check_push'),
      ('error_spike', 'ops_check_error_spike'),
      ('ai_quota', 'ops_check_ai'),
      ('version_health', 'ops_check_versions'),
      ('new_errors', 'ops_check_new_errors')
    ) as s(check_key, fn)
  loop
    begin
      execute format('select public.%I()', step.fn);
    exception when others then
      -- One check failing must not stop the others.
      perform public.ops_set_check(
        step.check_key,
        'unknown',
        jsonb_build_object('error', sqlstate)
      );
    end;
  end loop;

  -- An event is news for a day.
  perform public.ops_close_alert(a.check_key, null, 'auto')
  from public.ops_alerts a
  where a.kind = 'event'
    and a.resolved_at is null
    and a.opened_at < now() - interval '24 hours';

  -- The checks ran: the console reads this to tell a stopped cron.
  perform public.ops_set_check('heartbeat', 'ok', '{}'::jsonb);

  delete from public.ops_alerts a
  where a.resolved_at < now() - interval '90 days';
end;
$$;

revoke execute on function public.ops_set_check(text, text, jsonb)
  from public, anon, authenticated;
revoke execute on function public.ops_close_alert(text, uuid, text)
  from public, anon, authenticated;
revoke execute on function public.ops_raise_alert(text, text, text, text, text, text, text, jsonb)
  from public, anon, authenticated;
revoke execute on function public.ops_apply_check(text, text, text, text, text, text, jsonb)
  from public, anon, authenticated;
revoke execute on function public.ops_check_cron() from public, anon, authenticated;
revoke execute on function public.ops_check_wakes() from public, anon, authenticated;
revoke execute on function public.ops_check_push() from public, anon, authenticated;
revoke execute on function public.ops_check_error_spike() from public, anon, authenticated;
revoke execute on function public.ops_check_ai() from public, anon, authenticated;
revoke execute on function public.ops_check_versions() from public, anon, authenticated;
revoke execute on function public.ops_check_new_errors() from public, anon, authenticated;
revoke execute on function public.ops_health_check() from public, anon, authenticated;

-- With pg_cron installed (hosted Supabase), run every 5 minutes. Without it
-- (local development) nothing is scheduled.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'wecord-ops-health-check',
      '*/5 * * * *',
      'select public.ops_health_check()'
    );
  end if;
end $$;
