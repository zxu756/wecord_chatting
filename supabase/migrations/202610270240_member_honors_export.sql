-- Member titles and honors (roadmap C7), part 5 of 5: taking your data.
--
-- export_my_honors(user) is for the data-export Edge Function (service role
-- only, like export_my_knowledge): the titles circles gave me, my honors and
-- streaks, and the circles where I stay out of honors. Only my own: no one
-- else's titles, honors or numbers. Deleting an account already erases all of
-- it (profiles_erase_honors, 202610270200).

create or replace function public.export_my_honors(target_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if target_user_id is null then
    raise exception 'A user is required' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'titles', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'circle_id', cm.circle_id,
          'circle_name', c.name,
          'title', cm.title,
          'given_at', cm.title_set_at
        )
        order by cm.title_set_at desc nulls last, cm.circle_id
      )
      from public.circle_members cm
      join public.circles c on c.id = cm.circle_id
      where cm.user_id = target_user_id and cm.title is not null
    ), '[]'::jsonb),
    'honors', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'circle_id', h.circle_id,
          'circle_name', c.name,
          'kind', h.kind,
          'level', h.level,
          'period_start', h.period_start,
          'awarded_at', h.awarded_at
        )
        order by h.period_start desc, h.circle_id, h.kind, h.level desc
      )
      from public.circle_member_honors h
      join public.circles c on c.id = h.circle_id
      where h.user_id = target_user_id
    ), '[]'::jsonb),
    'streaks', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'circle_id', s.circle_id,
          'circle_name', c.name,
          'current_streak', s.current_streak,
          'best_streak', s.best_streak,
          'as_of', s.updated_day
        )
        order by s.circle_id
      )
      from public.circle_member_honor_stats s
      join public.circles c on c.id = s.circle_id
      where s.user_id = target_user_id
    ), '[]'::jsonb),
    'opted_out', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'circle_id', hp.circle_id,
          'circle_name', c.name,
          'since', hp.opted_out_at
        )
        order by hp.opted_out_at desc, hp.circle_id
      )
      from public.circle_honor_prefs hp
      join public.circles c on c.id = hp.circle_id
      where hp.user_id = target_user_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_honors(uuid)
  from public, anon, authenticated;
grant execute on function public.export_my_honors(uuid) to service_role;
