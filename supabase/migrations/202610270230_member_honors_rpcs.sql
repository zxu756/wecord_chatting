-- Member titles and honors (roadmap C7), part 4 of 5: what the honors page
-- reads and the two switches.
--
--   * get_circle_honors(circle): one object for a member of the circle:
--       enabled       the circle has honors on
--       eligible      the circle has 5 or more people (below that nothing is
--                     worked out, as with the C3 dashboard)
--       participating the caller takes part
--       can_manage    the caller may switch honors on and off for the circle
--       mine          the caller's own streak, best streak, active days so
--                     far this week and the honors they earned. Only for the
--                     caller: nobody else's numbers are ever returned.
--       board         last week's board: the week and, only when 5 or more
--                     people are on it, each person's user_id and level.
--                     Levels, never day counts.
--     A suspended circle (K1) gives null.
--   * set_circle_honors_enabled(circle, on): manage_circle. Turning them off
--     deletes what was worked out, so nothing old shows if they come back.
--   * set_my_honors_participation(circle, on): any member, for themselves.
--     Staying out deletes their honors and streak.
--
-- A circle that was delisted or suspended takes no changes.

create or replace function public.get_circle_honors(target_circle_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  circle_row public.circles%rowtype;
  member_count integer;
  taking_part boolean;
  eligible boolean;
  this_monday date := date_trunc('week', public.insights_today()::timestamp)::date;
  mine jsonb;
  board jsonb;
  published boolean;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.is_current_user_circle_member(target_circle_id) then
    raise exception 'Only circle members can see honors' using errcode = '42501';
  end if;
  if public.circle_is_suspended(target_circle_id) then
    return null;
  end if;

  select * into circle_row from public.circles c where c.id = target_circle_id;
  if circle_row.id is null then
    return null;
  end if;

  select count(*)::integer into member_count
  from public.circle_members cm
  join public.profiles p on p.id = cm.user_id and not p.is_bot
  where cm.circle_id = target_circle_id;
  eligible := member_count >= 5;

  taking_part := not exists (
    select 1 from public.circle_honor_prefs hp
    where hp.circle_id = target_circle_id and hp.user_id = uid
  );

  if circle_row.honors_enabled and eligible and taking_part then
    select jsonb_build_object(
      'streak', coalesce(st.current_streak, 0),
      'best_streak', coalesce(st.best_streak, 0),
      'week_days', (
        select count(*)::integer
        from public.circle_member_daily d
        where d.circle_id = target_circle_id
          and d.user_id = uid
          and d.day between this_monday and public.insights_today()
      ),
      'honors', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'kind', h.kind,
            'level', h.level,
            'period_start', h.period_start
          )
          order by h.period_start desc, h.kind, h.level desc
        )
        from (
          select *
          from public.circle_member_honors x
          where x.circle_id = target_circle_id and x.user_id = uid
          order by x.period_start desc, x.kind, x.level desc
          limit 60
        ) h
      ), '[]'::jsonb)
    )
    into mine
    from (select 1) one
    left join public.circle_member_honor_stats st
      on st.circle_id = target_circle_id and st.user_id = uid;
  end if;

  published := public.honors_board_published(target_circle_id);
  board := jsonb_build_object(
    'week_start', public.honors_week_start(),
    'published', published,
    'entries', case when published then coalesce((
      select jsonb_agg(
        jsonb_build_object('user_id', h.user_id, 'level', h.level)
        order by h.level desc, h.user_id
      )
      from public.circle_member_honors h
      join public.circle_members cm
        on cm.circle_id = h.circle_id and cm.user_id = h.user_id
      where h.circle_id = target_circle_id
        and h.kind = 'weekly'
        and h.period_start = public.honors_week_start()
        and not exists (
          select 1 from public.circle_honor_prefs hp
          where hp.circle_id = h.circle_id and hp.user_id = h.user_id
        )
    ), '[]'::jsonb) else '[]'::jsonb end
  );

  return jsonb_build_object(
    'circle_id', target_circle_id,
    'enabled', circle_row.honors_enabled,
    'eligible', eligible,
    'participating', taking_part,
    'can_manage', public.current_user_has_circle_permission(
      target_circle_id, 'manage_circle'
    ),
    'mine', mine,
    'board', case
      when circle_row.honors_enabled and eligible then board
    end
  );
end;
$$;

revoke execute on function public.get_circle_honors(uuid) from public, anon;
grant execute on function public.get_circle_honors(uuid) to authenticated;

create or replace function public.set_circle_honors_enabled(
  target_circle_id uuid,
  honors_on boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  old_enabled boolean;
  circle_name text;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if honors_on is null then
    raise exception 'On or off is required' using errcode = '22023';
  end if;
  if public.is_user_suspended(uid) then
    raise exception 'Account suspended' using errcode = '42501';
  end if;
  if not public.current_user_has_circle_permission(
    target_circle_id, 'manage_circle'
  ) then
    raise exception 'Only members who manage the circle can change honors'
      using errcode = '42501';
  end if;
  perform public.assert_circle_up(target_circle_id);

  select c.honors_enabled, c.name into old_enabled, circle_name
  from public.circles c
  where c.id = target_circle_id
  for update;

  if old_enabled is null then
    raise exception 'Circle not found' using errcode = 'P0002';
  end if;
  if old_enabled = honors_on then
    return honors_on;
  end if;

  update public.circles set honors_enabled = honors_on
  where id = target_circle_id;

  if not honors_on then
    delete from public.circle_member_honors where circle_id = target_circle_id;
    delete from public.circle_member_honor_stats
    where circle_id = target_circle_id;
  end if;

  perform public.write_circle_audit(
    target_circle_id,
    'honors_update',
    'circle',
    target_circle_id,
    circle_name,
    jsonb_build_object(
      'enabled', jsonb_build_object('old', old_enabled, 'new', honors_on)
    )
  );
  return honors_on;
end;
$$;

revoke execute on function public.set_circle_honors_enabled(uuid, boolean)
  from public, anon;
grant execute on function public.set_circle_honors_enabled(uuid, boolean)
  to authenticated;

create or replace function public.set_my_honors_participation(
  target_circle_id uuid,
  take_part boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if take_part is null then
    raise exception 'On or off is required' using errcode = '22023';
  end if;
  if not public.is_current_user_circle_member(target_circle_id) then
    raise exception 'Only circle members can choose' using errcode = '42501';
  end if;
  perform public.assert_circle_up(target_circle_id);

  if take_part then
    delete from public.circle_honor_prefs
    where circle_id = target_circle_id and user_id = uid;
  else
    insert into public.circle_honor_prefs (circle_id, user_id)
    values (target_circle_id, uid)
    on conflict do nothing;
    delete from public.circle_member_honors
    where circle_id = target_circle_id and user_id = uid;
    delete from public.circle_member_honor_stats
    where circle_id = target_circle_id and user_id = uid;
  end if;
  return take_part;
end;
$$;

revoke execute on function public.set_my_honors_participation(uuid, boolean)
  from public, anon;
grant execute on function public.set_my_honors_participation(uuid, boolean)
  to authenticated;
