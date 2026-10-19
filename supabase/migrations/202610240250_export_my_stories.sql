-- "Download my data" (202610170053, 202610190023, 202610230130, 202610240660):
-- the Daily (B1, 202610240200-202610240240).
--
-- export_my_stories(user), for the data-export Edge Function (service role
-- only, like export_my_feedback). It reads only what the person made: the
-- dailies still up (a daily is gone 24 hours after it was posted), with the
-- audience as a word, how many people viewed it and the files (named by
-- bucket and path so the export can link or include them), their close
-- friends by name, and the reports they filed about dailies (the reason and
-- the outcome, nothing the team wrote about anyone else). The viewers
-- themselves are not listed: they are other people's activity.
-- Their replies to other people's dailies are ordinary chat messages and
-- are exported with the chats.
--
-- A new function: export_my_extras is not rewritten. Capped at 100 dailies
-- and 500 close friends.

create or replace function public.export_my_stories(target_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  stories_result jsonb;
  close_result jsonb;
  reports_result jsonb;
begin
  if target_user_id is null then
    raise exception 'A user is required' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', s.id,
      'media_kind', s.media_kind,
      'caption', s.caption,
      'audience', s.visibility,
      'created_at', s.created_at,
      'expires_at', s.expires_at,
      'width', s.width,
      'height', s.height,
      'duration_ms', s.duration_ms,
      'viewer_count', (
        select count(*) from public.story_views v where v.story_id = s.id
      ),
      'bucket', 'stories',
      'path', s.media_path,
      'poster_path', s.poster_path,
      'thumb_path', s.thumb_path
    )
    order by s.created_at desc, s.id
  ), '[]'::jsonb)
  into stories_result
  from (
    select *
    from public.stories ss
    where ss.author_id = target_user_id
    order by ss.created_at desc, ss.id desc
    limit 100
  ) s;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'user_id', cf.friend_id,
      'name', p.display_name,
      'username', p.username,
      'since', cf.created_at
    )
    order by cf.created_at, cf.friend_id
  ), '[]'::jsonb)
  into close_result
  from (
    select *
    from public.story_close_friends c
    where c.owner_id = target_user_id
    order by c.created_at, c.friend_id
    limit 500
  ) cf
  join public.profiles p on p.id = cf.friend_id and p.deleted_at is null;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'reason', r.reason,
      'details', r.details,
      'status', case r.status when 'actioned' then 'reviewed' else r.status end,
      'created_at', r.created_at,
      'handled_at', r.handled_at
    )
    order by r.created_at desc, r.id
  ), '[]'::jsonb)
  into reports_result
  from (
    select *
    from public.story_reports sr
    where sr.reporter_id = target_user_id
    order by sr.created_at desc, sr.id desc
    limit 200
  ) r;

  return jsonb_build_object(
    'stories', stories_result,
    'close_friends', close_result,
    'reports', reports_result
  );
end;
$$;

revoke execute on function public.export_my_stories(uuid) from public;
revoke execute on function public.export_my_stories(uuid) from anon;
revoke execute on function public.export_my_stories(uuid) from authenticated;
