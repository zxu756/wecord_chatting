-- Circle insights (C3), part 3 of 3: what the dashboard reads.
--
-- get_circle_insights(circle, range_days, tz_offset_minutes) is for members
-- with manage_circle or view_audit_log (the owner and administrators have
-- every permission). Anyone else, a non-member and nobody signed in are
-- refused. It returns one object for the days from [range_days] ago up to
-- yesterday (the page asks for 7, 30 or 90; anything between 1 and 90 works):
--
--   small        true while the circle has fewer than 5 members
--   members_now  members today
--   series       per day: members, joined, left, active, messages, voice
--   totals       joined, left, active (distinct people), messages, voice
--   heatmap      messages by weekday (0 = Sunday .. 6 = Saturday) by hour,
--                shifted by tz_offset_minutes (rounded to whole hours)
--   channels     the busiest channels, with names
--   invites      the invite links that brought most people
--   inviters     the members who brought most people (links and friends)
--   retention    two ratios, or null when too few people to say
--
-- What keeps individuals out of it:
--
--   * Every count is -1 ("fewer than 5") when it is between 1 and 4, and 0
--     stays 0. While the circle has fewer than 5 members every count is -1:
--     with so few people any number is somebody. The page shows -1 as "<5".
--   * Retention is a ratio, and only given when 5 or more people stand
--     behind it: of those who joined in the range, the share still in the
--     circle; of those active the week before last, the share active last
--     week.
--   * Invite links are named by who made them and when, never by code: the
--     code is a way in, and view_audit_log is not a permission to use it.
--   * circle_member_daily is never returned, only counted.

-- A count for the page: -1 stands for "fewer than 5".
create or replace function public.insight_count(n bigint, hide boolean default false)
returns integer
language sql
immutable
set search_path = public
as $$
  select case
    when n is null then null
    when hide then -1
    when n between 1 and 4 then -1
    else n::integer
  end;
$$;

revoke execute on function public.insight_count(bigint, boolean) from public, anon, authenticated;

create or replace function public.get_circle_insights(
  target_circle_id uuid,
  range_days integer default 30,
  tz_offset_minutes integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  today date := public.insights_today();
  span integer := least(greatest(coalesce(range_days, 30), 1), 90);
  first_day date;
  last_day date;
  range_start timestamptz;
  shift integer := least(greatest(round(coalesce(tz_offset_minutes, 0) / 60.0), -14), 14);
  members_now integer;
  small boolean;
  joined_total bigint;
  kept_total bigint;
  prior_base bigint;
  prior_back bigint;
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not (
    public.current_user_has_circle_permission(target_circle_id, 'manage_circle')
    or public.current_user_has_circle_permission(target_circle_id, 'view_audit_log')
  ) then
    raise exception 'Only members who manage the circle or view its audit log can see insights'
      using errcode = '42501';
  end if;

  first_day := today - span;
  last_day := today - 1;
  range_start := first_day::timestamp at time zone 'UTC';

  select count(*)::integer into members_now
  from public.circle_members cm
  join public.profiles p on p.id = cm.user_id and not p.is_bot
  where cm.circle_id = target_circle_id;
  small := members_now < 5;

  -- Retention: of the people who joined in the range, who is still here.
  select coalesce(sum(s.joined), 0) into joined_total
  from public.circle_daily_stats s
  where s.circle_id = target_circle_id
    and s.day between first_day and last_day;

  select count(*) into kept_total
  from public.circle_members cm
  join public.profiles p on p.id = cm.user_id and not p.is_bot
  where cm.circle_id = target_circle_id
    and cm.created_at >= range_start
    and cm.created_at < today::timestamp at time zone 'UTC';

  -- Retention: of those active between 14 and 8 days ago, who is still a
  -- member and was active in the last 7 days.
  select
    count(*),
    count(*) filter (
      where exists (
        select 1
        from public.circle_member_daily b
        where b.circle_id = a.circle_id
          and b.user_id = a.user_id
          and b.day between today - 7 and today - 1
      )
    )
  into prior_base, prior_back
  from (
    select distinct d.circle_id, d.user_id
    from public.circle_member_daily d
    join public.circle_members cm
      on cm.circle_id = d.circle_id and cm.user_id = d.user_id
    where d.circle_id = target_circle_id
      and d.day between today - 14 and today - 8
  ) a;

  select jsonb_build_object(
    'circle_id', target_circle_id,
    'range_days', span,
    'from', first_day,
    'to', last_day,
    'small', small,
    'members_now', public.insight_count(members_now, false),

    'series', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'day', d.day,
          'members', public.insight_count(coalesce(s.members_total, 0), small),
          'joined', public.insight_count(coalesce(s.joined, 0), small),
          'left', public.insight_count(coalesce(s.left_members, 0), small),
          'active', public.insight_count(coalesce(s.active_members, 0), small),
          'messages', public.insight_count(coalesce(s.messages, 0), small),
          'voice_minutes', public.insight_count(coalesce(s.voice_minutes, 0), small)
        )
        order by d.day
      )
      from (
        select g.day::date as day
        from generate_series(
          first_day::timestamp, last_day::timestamp, interval '1 day'
        ) g(day)
      ) d
      left join public.circle_daily_stats s
        on s.circle_id = target_circle_id and s.day = d.day
    ), '[]'::jsonb),

    'totals', (
      select jsonb_build_object(
        'joined', public.insight_count(coalesce(sum(s.joined), 0), small),
        'left', public.insight_count(coalesce(sum(s.left_members), 0), small),
        'messages', public.insight_count(coalesce(sum(s.messages), 0), small),
        'voice_minutes', public.insight_count(coalesce(sum(s.voice_minutes), 0), small),
        'active', public.insight_count((
          select count(distinct d.user_id)
          from public.circle_member_daily d
          where d.circle_id = target_circle_id
            and d.day between first_day and last_day
        ), small)
      )
      from public.circle_daily_stats s
      where s.circle_id = target_circle_id
        and s.day between first_day and last_day
    ),

    'heatmap', (
      select jsonb_build_object(
        'weekday_start', 0,
        'rows', coalesce(jsonb_agg(row_cells order by weekday), '[]'::jsonb)
      )
      from (
        select
          w.weekday,
          (
            select jsonb_agg(
              public.insight_count(coalesce(c.n, 0), small)
              order by h.hour
            )
            from generate_series(0, 23) h(hour)
            left join (
              select
                extract(dow from cell.ts)::integer as weekday,
                extract(hour from cell.ts)::integer as hour,
                sum(cell.n) as n
              from (
                select
                  s.day::timestamp + make_interval(hours => g.hour + shift) as ts,
                  s.hourly[g.hour + 1] as n
                from public.circle_daily_stats s
                cross join generate_series(0, 23) g(hour)
                where s.circle_id = target_circle_id
                  and s.day between first_day and last_day
              ) cell
              group by 1, 2
            ) c on c.weekday = w.weekday and c.hour = h.hour
          ) as row_cells
        from generate_series(0, 6) w(weekday)
      ) grid
    ),

    'channels', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'channel_id', ranked.channel_id,
          'name', ranked.name,
          'messages', public.insight_count(ranked.n, small)
        )
        order by ranked.n desc, ranked.name
      )
      from (
        select cc.id as channel_id, cc.name, sum(t.n) as n
        from (
          select
            (e.value ->> 'channel_id')::uuid as channel_id,
            (e.value ->> 'count')::integer as n
          from public.circle_daily_stats s
          cross join lateral jsonb_array_elements(s.top_channels) e(value)
          where s.circle_id = target_circle_id
            and s.day between first_day and last_day
        ) t
        join public.circle_channels cc
          on cc.id = t.channel_id and cc.circle_id = target_circle_id
        group by cc.id, cc.name
        order by sum(t.n) desc, cc.name
        limit 10
      ) ranked
    ), '[]'::jsonb),

    'invites', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'created_by_name', ranked.creator_name,
          'created_at', ranked.created_at,
          'revoked', ranked.revoked,
          'brought', public.insight_count(ranked.brought, small),
          'remaining', public.insight_count(ranked.remaining, small)
        )
        order by ranked.brought desc, ranked.created_at desc
      )
      from (
        select
          ci.created_at,
          ci.revoked_at is not null as revoked,
          case when ci.created_by is null then null
            else public.circle_member_label(target_circle_id, ci.created_by)
          end as creator_name,
          count(*) as brought,
          count(*) filter (
            where exists (
              select 1 from public.circle_members cm
              where cm.circle_id = j.circle_id
                and cm.user_id = j.user_id
                and cm.created_at = j.joined_at
            )
          ) as remaining
        from public.circle_invite_joins j
        join public.circle_invites ci on ci.code = j.invite_code
        where j.circle_id = target_circle_id
          and j.invite_code is not null
          and j.joined_at >= range_start
        group by ci.code, ci.created_at, ci.revoked_at, ci.created_by
        order by count(*) desc, ci.created_at desc
        limit 10
      ) ranked
    ), '[]'::jsonb),

    'inviters', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'name', ranked.name,
          'brought', public.insight_count(ranked.brought, small),
          'remaining', public.insight_count(ranked.remaining, small)
        )
        order by ranked.brought desc, ranked.name
      )
      from (
        select
          public.circle_member_label(target_circle_id, j.invited_by) as name,
          count(*) as brought,
          count(*) filter (
            where exists (
              select 1 from public.circle_members cm
              where cm.circle_id = j.circle_id
                and cm.user_id = j.user_id
                and cm.created_at = j.joined_at
            )
          ) as remaining
        from public.circle_invite_joins j
        where j.circle_id = target_circle_id
          and j.invited_by is not null
          and j.joined_at >= range_start
        group by j.invited_by
        order by count(*) desc
        limit 10
      ) ranked
    ), '[]'::jsonb),

    'retention', jsonb_build_object(
      'joined_kept', case
        when small or joined_total < 5 then null
        else round(least(kept_total::numeric / joined_total, 1), 2)
      end,
      'active_returning', case
        when small or prior_base < 5 then null
        else round(prior_back::numeric / prior_base, 2)
      end
    )
  ) into result;

  return result;
end;
$$;

revoke execute on function public.get_circle_insights(uuid, integer, integer)
  from public, anon;
grant execute on function public.get_circle_insights(uuid, integer, integer)
  to authenticated;
