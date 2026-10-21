-- Events 2.0 (roadmap C10), part 7b of 7: deleting an account, and taking your
-- data.
--
-- * Deleting an account (profiles.deleted_at) erases what Events 2.0 holds of
--   the person: their answers to the questions of events they signed up to,
--   their place on waiting lists, their check-ins, the pictures they added
--   (the files go with the rest of their uploads), the check-in codes they
--   made and the pushes waiting for them. Same pattern as profiles_erase_honors
--   (202610270200): prepare_account_deletion is not rewritten. Events they made
--   stay, as before, with no creator; a repeating series of theirs ends at its
--   next turn (events2_spawn_next sees the deleted account).
-- * export_my_events2(user) is for the data-export Edge Function (service role
--   only, like export_my_honors). What the person did, and only that:
--     - signed_up: events they signed up to (chat and circle) while they can
--       still see them, with when, their answers, whether they checked in and
--       the seat or the waiting list;
--     - waiting: events they wait for a seat in;
--     - check_ins: where they checked in and when;
--     - photos: pictures they added (a storage path the function signs);
--     - events_made: events they made, with their settings (repeat, capacity,
--       questions, cover) but never anybody's answers.
--   Other people's answers, names and pictures are not included.

create or replace function public.erase_events2_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.chat_event_rsvps set answers = '{}'::jsonb
  where user_id = new.id and answers <> '{}'::jsonb;
  update public.circle_event_rsvps set answers = '{}'::jsonb
  where user_id = new.id and answers <> '{}'::jsonb;
  delete from public.event_waitlist where user_id = new.id;
  delete from public.event_check_ins where user_id = new.id;
  delete from public.event_photos where user_id = new.id;
  delete from public.event_check_in_codes where created_by = new.id;
  delete from public.event_notices where user_id = new.id;
  return new;
end;
$$;

revoke execute on function public.erase_events2_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_erase_events2 on public.profiles;
create trigger profiles_erase_events2
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_events2_of_deleted_account();

create or replace function public.export_my_events2(target_user_id uuid)
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
    'signed_up', coalesce((
      select jsonb_agg(row_json order by starts_at desc)
      from (
        select
          jsonb_build_object(
            'kind', 'chat',
            'title', e.title,
            'starts_at', e.starts_at,
            'cancelled', e.cancelled_at is not null,
            'answer', r.status,
            'signed_up_at', r.updated_at,
            'answers', r.answers,
            'checked_in_at', ci.checked_in_at,
            'questions', e.questions
          ) as row_json,
          e.starts_at
        from public.chat_event_rsvps r
        join public.chat_events e on e.id = r.event_id
        join public.conversation_members cm
          on cm.conversation_id = e.conversation_id and cm.user_id = target_user_id
        left join public.event_check_ins ci
          on ci.chat_event_id = e.id and ci.user_id = target_user_id
        where r.user_id = target_user_id
        union all
        select
          jsonb_build_object(
            'kind', 'circle',
            'circle_name', c.name,
            'title', e.title,
            'starts_at', e.starts_at,
            'cancelled', e.cancelled_at is not null,
            'answer', 'going',
            'signed_up_at', r.created_at,
            'answers', r.answers,
            'checked_in_at', ci.checked_in_at,
            'questions', e.questions
          ),
          e.starts_at
        from public.circle_event_rsvps r
        join public.circle_events e on e.id = r.event_id
        join public.circles c on c.id = e.circle_id
        left join public.event_check_ins ci
          on ci.circle_event_id = e.id and ci.user_id = target_user_id
        where r.user_id = target_user_id
      ) q
    ), '[]'::jsonb),
    'waiting', coalesce((
      select jsonb_agg(row_json order by joined_at desc)
      from (
        select
          jsonb_build_object(
            'kind', case when w.chat_event_id is not null then 'chat' else 'circle' end,
            'title', coalesce(ce.title, ke.title),
            'starts_at', coalesce(ce.starts_at, ke.starts_at),
            'joined_at', w.created_at,
            'answers', w.answers
          ) as row_json,
          w.created_at as joined_at
        from public.event_waitlist w
        left join public.chat_events ce on ce.id = w.chat_event_id
        left join public.circle_events ke on ke.id = w.circle_event_id
        where w.user_id = target_user_id
      ) q
    ), '[]'::jsonb),
    'check_ins', coalesce((
      select jsonb_agg(row_json order by checked_in_at desc)
      from (
        select
          jsonb_build_object(
            'kind', case when ci.chat_event_id is not null then 'chat' else 'circle' end,
            'title', coalesce(ce.title, ke.title),
            'starts_at', coalesce(ce.starts_at, ke.starts_at),
            'checked_in_at', ci.checked_in_at
          ) as row_json,
          ci.checked_in_at
        from public.event_check_ins ci
        left join public.chat_events ce on ce.id = ci.chat_event_id
        left join public.circle_events ke on ke.id = ci.circle_event_id
        where ci.user_id = target_user_id
      ) q
    ), '[]'::jsonb),
    'photos', coalesce((
      select jsonb_agg(row_json order by created_at desc)
      from (
        select
          jsonb_build_object(
            'kind', case when ph.chat_event_id is not null then 'chat' else 'circle' end,
            'title', coalesce(ce.title, ke.title),
            'bucket', ph.bucket,
            'path', ph.path,
            'added_at', ph.created_at
          ) as row_json,
          ph.created_at
        from public.event_photos ph
        left join public.chat_events ce on ce.id = ph.chat_event_id
        left join public.circle_events ke on ke.id = ph.circle_event_id
        where ph.user_id = target_user_id
      ) q
    ), '[]'::jsonb),
    'events_made', coalesce((
      select jsonb_agg(row_json order by starts_at desc)
      from (
        select
          jsonb_build_object(
            'kind', 'chat',
            'title', e.title,
            'starts_at', e.starts_at,
            'repeats', e.recurrence,
            'time_zone', e.recurrence_tz,
            'capacity', e.capacity,
            'questions', e.questions,
            'cover', case when e.cover_path is null then null else
              jsonb_build_object('bucket', 'chat-images', 'path', e.cover_path) end
          ) as row_json,
          e.starts_at
        from public.chat_events e
        where e.created_by = target_user_id
        union all
        select
          jsonb_build_object(
            'kind', 'circle',
            'circle_name', c.name,
            'title', e.title,
            'starts_at', e.starts_at,
            'repeats', e.recurrence,
            'time_zone', e.recurrence_tz,
            'capacity', e.capacity,
            'questions', e.questions,
            'cover', case when e.cover_path is null then null else
              jsonb_build_object('bucket', 'chat-media', 'path', e.cover_path) end
          ),
          e.starts_at
        from public.circle_events e
        join public.circles c on c.id = e.circle_id
        where e.created_by = target_user_id
      ) q
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_events2(uuid)
  from public, anon, authenticated;
grant execute on function public.export_my_events2(uuid) to service_role;
