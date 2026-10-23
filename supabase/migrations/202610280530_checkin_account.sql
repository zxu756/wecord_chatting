-- Group check-in (roadmap D3), part 4 of 4: leaving WeCord and taking your
-- data.
--
-- * Deleting an account (profiles.deleted_at) erases what is only about that
--   person: their check-ins (the notes and the picture rows), their runs and
--   the reminders waiting for them. The files of their pictures go with the
--   rest of their uploads (delete-account removes what they own in storage).
--   A board they made stays in its chat, as a chain does, and its other
--   members keep their days. Same pattern as profiles_erase_events2
--   (202610270470); prepare_account_deletion is not rewritten.
-- * export_my_check_ins(user) is for the data-export Edge Function (service
--   role only, like export_my_events2). What the person did, and only that:
--     - check_ins: each day they checked in, in which check-in and chat (the
--       chat's name only while they are still in it), their note and the
--       picture's storage path (the function signs it);
--     - streaks: per check-in, the current run, the best run and the number
--       of days;
--     - boards_made: check-ins they made, with their settings (zone,
--       reminder time, last day, closed) but nobody else's check-ins.
--   Other people's notes, names and pictures are not included.

create or replace function public.erase_check_ins_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.check_in_entries where user_id = new.id;
  delete from public.check_in_streaks where user_id = new.id;
  delete from public.check_in_notices where user_id = new.id;
  return new;
end;
$$;

revoke execute on function public.erase_check_ins_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_erase_check_ins on public.profiles;
create trigger profiles_erase_check_ins
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_check_ins_of_deleted_account();

create or replace function public.export_my_check_ins(target_user_id uuid)
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
    'check_ins', coalesce((
      select jsonb_agg(row_json order by day desc, created_at desc)
      from (
        select
          jsonb_build_object(
            'check_in', b.title,
            'chat', case
              when cm.user_id is not null then coalesce(nullif(c.title, ''), c.type)
            end,
            'day', e.day,
            'note', e.note,
            'checked_in_at', e.created_at,
            'photo', case
              when e.photo_path is null then null
              else jsonb_build_object('bucket', 'chat-images', 'path', e.photo_path)
            end
          ) as row_json,
          e.day,
          e.created_at
        from public.check_in_entries e
        join public.check_in_boards b on b.id = e.board_id
        join public.conversations c on c.id = b.conversation_id
        left join public.conversation_members cm
          on cm.conversation_id = b.conversation_id and cm.user_id = target_user_id
        where e.user_id = target_user_id
        order by e.day desc, e.created_at desc
        limit 20000
      ) q
    ), '[]'::jsonb),
    'streaks', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'check_in', b.title,
          'current_streak', public.check_in_live_streak(
            s.current_streak, s.last_day, public.check_in_local_day(now(), b.time_zone)
          ),
          'best_streak', s.best_streak,
          'total_days', s.total_days,
          'last_day', s.last_day
        )
        order by s.last_day desc nulls last, b.id
      )
      from public.check_in_streaks s
      join public.check_in_boards b on b.id = s.board_id
      where s.user_id = target_user_id
    ), '[]'::jsonb),
    'boards_made', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'title', b.title,
          'description', b.description,
          'time_zone', b.time_zone,
          'reminder_minute', b.remind_minute,
          'last_day', b.ends_on,
          'closed', b.closed_at is not null,
          'created_at', b.created_at
        )
        order by b.created_at desc, b.id
      )
      from public.check_in_boards b
      where b.created_by = target_user_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_check_ins(uuid)
  from public, anon, authenticated;
grant execute on function public.export_my_check_ins(uuid) to service_role;
