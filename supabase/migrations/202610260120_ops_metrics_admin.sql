-- Product statistics (K2), part 3 of 3: what the admin console's Stats tab
-- reads. Only platform admins (any role) can call it; it returns counts and
-- nothing about a person.
--
-- admin_ops_metrics(range_days) answers one object:
--   * days: one entry per UTC day of the range (7 to 120 days, 30 by
--     default), oldest first, with the counts of ops_daily_metrics. A
--     retention figure is null until that later day is over.
--   * summary: people active in the last 7 and 30 days (distinct people, so
--     not a sum of days) and today's active people so far.
--   * versions: per app version and platform, the people active in the last
--     7 days and how many of them hit a crash (flutter, platform and zone
--     errors reported by signed-in people), newest version first. A report
--     from somebody signed out counts in crash_reports only.

create or replace function public.admin_ops_metrics(range_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  span integer := least(greatest(coalesce(range_days, 30), 7), 120);
  today date := (now() at time zone 'utc')::date;
  result jsonb;
begin
  perform public.admin_require(array['owner', 'moderator', 'support']);

  select jsonb_build_object(
    'generated_at', now(),
    'days', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'day', m.day,
          'active_users', m.active_users,
          'new_users', m.new_users,
          'd1_retained', m.d1_retained,
          'd7_retained', m.d7_retained,
          'd30_retained', m.d30_retained,
          'messages_total', m.messages_total,
          'messages_by_type', m.messages_by_type,
          'feature_counts', m.feature_counts,
          'voice_minutes', m.voice_minutes,
          'ai_requests', m.ai_requests,
          'ai_users', m.ai_users,
          'push_sent', m.push_sent,
          'push_failed', m.push_failed,
          'push_gone', m.push_gone,
          'error_reports', m.error_reports,
          'storage_bytes', m.storage_bytes,
          'storage_added', m.storage_added
        )
        order by m.day
      )
      from public.ops_daily_metrics m
      where m.day > today - span
    ), '[]'::jsonb),
    'summary', jsonb_build_object(
      'wau', (
        select count(distinct a.user_key) from public.ops_active_days a
        where a.day > today - 7
      ),
      'mau', (
        select count(distinct a.user_key) from public.ops_active_days a
        where a.day > today - 30
      )
    ),
    'versions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'app_version', v.app_version,
          'platform', v.platform,
          'active_users', v.active_users,
          'crash_users', coalesce(c.crash_users, 0),
          'crash_reports', coalesce(c.crash_reports, 0)
        )
        order by v.app_version desc, v.platform
      )
      from (
        select a.app_version, a.platform, count(distinct a.user_key)::integer as active_users
        from public.ops_active_days a
        where a.day > today - 7 and a.app_version <> ''
        group by a.app_version, a.platform
      ) v
      left join (
        select
          e.app_version,
          lower(e.platform) as platform,
          count(distinct e.user_id)::integer as crash_users,
          count(*)::integer as crash_reports
        from public.client_errors e
        where e.created_at >= (today - 6)::timestamp at time zone 'utc'
          and e.kind in ('flutter_error', 'platform_error', 'zone_error')
        group by e.app_version, lower(e.platform)
      ) c on c.app_version = v.app_version and c.platform = v.platform
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$$;

revoke execute on function public.admin_ops_metrics(integer) from public, anon;
grant execute on function public.admin_ops_metrics(integer) to authenticated;
