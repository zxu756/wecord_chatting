-- Daily (B1), part 4 of 6: reporting a daily (A1 extended to the Daily).
--
-- Dailies end after 24 hours, so a report keeps a copy (snapshot) of what
-- was reported: the caption, the kind, who posted it and when, and the file
-- names. The copy is only readable through the admin functions and is
-- cleared 90 days after the report was handled.
--
-- * report_story(story, reason, details, also_block): the reporter must be
--   able to see the daily, cannot report their own, has a limit of 20
--   reports a day, and can block the author in the same call. Reporting the
--   same daily again returns the first report. The reported person never
--   learns that a report exists.
-- * While a report is open the daily's files are not purged (the purge of
--   202610240240 leaves them for up to 30 days) and a platform admin can
--   read them (story_can_read_object, 202610240210), so the report can be
--   judged by looking at it.
-- * The platform side is the K1 console: admin_list_story_reports,
--   admin_get_story_report and admin_resolve_story_report have the shape of
--   the message report functions (202610220120). Actions: dismiss, delete
--   the daily, or note that the author was suspended through the console.
--   The audit log gets the action with the report as its target.

-- ---------------------------------------------------------------------------
-- Reporting
-- ---------------------------------------------------------------------------

create or replace function public.report_story(
  p_story_id uuid,
  p_reason text,
  p_details text default '',
  p_also_block boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  s public.stories%rowtype;
  author public.profiles%rowtype;
  existing_id uuid;
  created_id uuid;
  recent integer;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_reason is null
    or p_reason not in ('spam', 'harassment', 'impersonation', 'unsafe_content', 'other')
  then
    raise exception 'Unknown report reason' using errcode = '22023';
  end if;

  select * into s from public.stories where id = p_story_id;
  -- One answer for "no such daily" and "a daily you cannot see".
  if s.id is null or not public.story_visible_to(s, me) then
    raise exception 'Daily not found' using errcode = 'P0002';
  end if;
  if s.author_id = me then
    raise exception 'You cannot report your own daily' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('story_report:' || me::text, 0));

  select r.id into existing_id
  from public.story_reports r
  where r.reporter_id = me and r.story_id = s.id;

  if existing_id is null then
    select count(*)::integer into recent
    from public.story_reports r
    where r.reporter_id = me
      and r.created_at > now() - interval '24 hours';
    if recent >= 20 then
      raise exception 'You have sent too many reports today. Try again tomorrow.'
        using errcode = '54000';
    end if;

    select * into author from public.profiles where id = s.author_id;
    insert into public.story_reports (
      reporter_id, story_id, reported_user_id, reason, details, snapshot
    )
    values (
      me, s.id, s.author_id, p_reason,
      left(btrim(coalesce(p_details, '')), 1000),
      jsonb_build_object(
        'title', left(coalesce(nullif(s.caption, ''), 'Daily'), 80),
        'caption', s.caption,
        'media_kind', s.media_kind,
        'author_id', s.author_id,
        'author_username', author.username,
        'author_name', author.display_name,
        'visibility', s.visibility,
        'created_at', s.created_at,
        'expires_at', s.expires_at,
        'media_path', s.media_path,
        'poster_path', s.poster_path,
        'thumb_path', s.thumb_path
      )
    )
    returning id into created_id;
  else
    created_id := existing_id;
  end if;

  if coalesce(p_also_block, false) then
    perform public.block_user(s.author_id);
  end if;
  return created_id;
end;
$$;

revoke execute on function public.report_story(uuid, text, text, boolean) from public, anon;
grant execute on function public.report_story(uuid, text, text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Retention
-- ---------------------------------------------------------------------------

-- Clears the copies of reports handled more than 90 days ago. The report
-- (reason, outcome) stays. Called by the purge of 202610240240.
create or replace function public.purge_old_story_report_data()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  cleared integer;
begin
  update public.story_reports r
  set snapshot = null
  where r.handled_at < now() - interval '90 days'
    and r.snapshot is not null;
  get diagnostics cleared = row_count;
  return cleared;
end;
$$;

revoke execute on function public.purge_old_story_report_data()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The platform admins' side
-- ---------------------------------------------------------------------------

-- One report as the queue shows it (the shape of admin_report_row).
create or replace function public.admin_story_report_row(r public.story_reports)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', r.id,
    'kind', 'story',
    'status', case r.status when 'actioned' then 'reviewed' else r.status end,
    'reason', r.reason,
    'details', r.details,
    'created_at', r.created_at,
    'handled_at', r.handled_at,
    'handled_by_username', hb.username,
    'resolution', r.resolution,
    'title', coalesce(r.snapshot->>'title', ''),
    'subject_id', r.story_id,
    'responsible_user_id', r.reported_user_id,
    'reporter', jsonb_build_object(
      'id', r.reporter_id,
      'username', rep.username,
      'display_name', rep.display_name
    ),
    'repeat_count', (
      select count(*)
      from public.story_reports o
      where o.status = 'open'
        and o.story_id is not distinct from r.story_id
    )
  )
  from (select 1) one
  left join public.profiles rep on rep.id = r.reporter_id
  left join public.profiles hb on hb.id = r.handled_by;
$$;

revoke execute on function public.admin_story_report_row(public.story_reports)
  from public, anon, authenticated;

-- The queue of reports of dailies. [status_filter] is 'open', 'handled',
-- 'reviewed', 'dismissed' or 'all'; newest first, a page at a time.
create or replace function public.admin_list_story_reports(
  status_filter text default 'open',
  page_size integer default 30,
  before_created_at timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  page integer := least(greatest(coalesce(page_size, 30), 1), 100);
  result jsonb;
begin
  perform public.admin_require(array['owner', 'moderator', 'support']);

  if status_filter is not null
    and status_filter not in ('open', 'handled', 'reviewed', 'dismissed', 'all')
  then
    raise exception 'Unknown report status' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(page_row.entry order by page_row.created_at desc), '[]'::jsonb)
  into result
  from (
    select public.admin_story_report_row(r) as entry, r.created_at
    from public.story_reports r
    where r.reported_user_id is distinct from auth.uid()
      and (
        status_filter is null
        or status_filter = 'all'
        or (status_filter = 'handled' and r.status in ('actioned', 'dismissed'))
        or (status_filter = 'reviewed' and r.status = 'actioned')
        or r.status = status_filter
      )
      and (before_created_at is null or r.created_at < before_created_at)
    order by r.created_at desc
    limit page
  ) page_row;

  return result;
end;
$$;

-- One report in full, in the shape of admin_get_message_report: the report
-- with its snapshot, the author as a person, other reports about the same
-- daily or author, and what admins did about the author before. `subject`
-- says whether the daily is still up (then the media can be opened).
create or replace function public.admin_get_story_report(target_report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  r public.story_reports%rowtype;
  subject jsonb;
  responsible jsonb;
  history jsonb;
  actions jsonb;
begin
  perform public.admin_require(array['owner', 'moderator', 'support']);

  select * into r
  from public.story_reports
  where id = target_report_id
    and reported_user_id is distinct from auth.uid();
  if r.id is null then
    raise exception 'Report not found' using errcode = 'P0002';
  end if;

  select jsonb_build_object(
    'type', 'story',
    'id', r.story_id,
    'deleted', s.id is null,
    'missing', s.id is null,
    'live', s.id is not null and s.expires_at > now(),
    'media_kind', s.media_kind,
    'media_path', s.media_path,
    'poster_path', s.poster_path,
    'thumb_path', s.thumb_path
  ) into subject
  from (select 1) one
  left join public.stories s on s.id = r.story_id;

  select jsonb_build_object(
    'id', p.id,
    'username', p.username,
    'display_name', p.display_name,
    'avatar_url', p.avatar_url,
    'created_at', p.created_at,
    'is_suspended', public.is_user_suspended(p.id),
    'suspended_until', sp.until,
    'suspension_reason', sp.reason,
    'is_admin', exists (select 1 from public.app_admins a where a.user_id = p.id),
    'reports_against', (
      select count(*) from public.reports o where o.target_user_id = p.id
    ) + (
      select count(*) from public.message_reports o where o.reported_user_id = p.id
    ) + (
      select count(*) from public.story_reports o where o.reported_user_id = p.id
    ),
    'open_reports_against', (
      select count(*) from public.reports o
      where o.target_user_id = p.id and o.status = 'open'
    ) + (
      select count(*) from public.message_reports o
      where o.reported_user_id = p.id and o.status = 'open'
    ) + (
      select count(*) from public.story_reports o
      where o.reported_user_id = p.id and o.status = 'open'
    )
  ) into responsible
  from public.profiles p
  left join public.app_user_suspensions sp
    on sp.user_id = p.id and (sp.until is null or sp.until > now())
  where p.id = r.reported_user_id;

  select coalesce(jsonb_agg(h.entry order by h.created_at desc), '[]'::jsonb)
  into history
  from (
    select jsonb_build_object(
      'id', o.id,
      'kind', 'story',
      'reason', o.reason,
      'status', case o.status when 'actioned' then 'reviewed' else o.status end,
      'resolution', o.resolution,
      'created_at', o.created_at
    ) as entry, o.created_at
    from public.story_reports o
    where o.id <> r.id
      and (
        (r.story_id is not null and o.story_id = r.story_id)
        or (r.reported_user_id is not null and o.reported_user_id = r.reported_user_id)
      )
    order by o.created_at desc
    limit 20
  ) h;

  select coalesce(jsonb_agg(a.entry order by a.created_at desc), '[]'::jsonb)
  into actions
  from (
    select jsonb_build_object(
      'id', l.id,
      'action', l.action,
      'actor_username', actor.username,
      'target_type', l.target_type,
      'created_at', l.created_at,
      'details', l.details
    ) as entry, l.created_at
    from public.admin_audit_log l
    left join public.profiles actor on actor.id = l.actor_id
    where l.action not in ('resolve_report', 'resolve_message_report', 'resolve_story_report')
      and l.target_type = 'user'
      and l.target_id = r.reported_user_id
    order by l.created_at desc
    limit 20
  ) a;

  return jsonb_build_object(
    'report', public.admin_story_report_row(r) || jsonb_build_object(
      'snapshot', coalesce(r.snapshot, '{}'::jsonb)
    ),
    'subject', subject,
    'responsible_user', responsible,
    'history', history,
    'actions', actions,
    'reporter_stats', (
      select jsonb_build_object(
        'total', (select count(*) from public.reports o where o.reporter_id = r.reporter_id)
          + (select count(*) from public.message_reports o where o.reporter_id = r.reporter_id)
          + (select count(*) from public.story_reports o where o.reporter_id = r.reporter_id),
        'dismissed', (
          select count(*) from public.reports o
          where o.reporter_id = r.reporter_id and o.status = 'dismissed'
        ) + (
          select count(*) from public.message_reports o
          where o.reporter_id = r.reporter_id and o.status = 'dismissed'
        ) + (
          select count(*) from public.story_reports o
          where o.reporter_id = r.reporter_id and o.status = 'dismissed'
        )
      )
    )
  );
end;
$$;

-- Closes a report of a daily. [action]:
--   'dismiss'       no violation;
--   'delete_story'  take the daily down now;
--   'suspend'       the author was suspended through the console (the
--                   `admin` function); refused while they are not.
-- Other open reports of the same daily are closed with it.
create or replace function public.admin_resolve_story_report(
  target_report_id uuid,
  action text,
  note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_role text;
  report public.story_reports%rowtype;
  new_status text;
  new_resolution text;
  removed boolean := false;
  clean_note text := left(btrim(coalesce(note, '')), 500);
begin
  caller_role := public.admin_require(array['owner', 'moderator', 'support']);

  if action is null or action not in ('dismiss', 'delete_story', 'suspend') then
    raise exception 'Unknown action' using errcode = '22023';
  end if;
  if action <> 'dismiss' and caller_role = 'support' then
    raise exception 'Admin access required' using errcode = '42501';
  end if;

  select r.* into report
  from public.story_reports r
  where r.id = target_report_id
    and r.reported_user_id is distinct from auth.uid()
  for update;
  if report.id is null then
    raise exception 'Report not found' using errcode = 'P0002';
  end if;
  if report.status <> 'open' then
    raise exception 'Report not found or already handled' using errcode = 'P0002';
  end if;

  if action = 'dismiss' then
    new_status := 'dismissed';
    new_resolution := 'no_violation';
  elsif action = 'delete_story' then
    new_status := 'actioned';
    new_resolution := 'story_deleted';
    if report.story_id is not null then
      delete from public.stories where id = report.story_id;
      removed := found;
    end if;
  else
    if report.reported_user_id is null
      or not public.is_user_suspended(report.reported_user_id)
    then
      raise exception 'Suspend the person first' using errcode = '22023';
    end if;
    new_status := 'actioned';
    new_resolution := 'user_suspended';
  end if;

  update public.story_reports r
  set status = new_status,
      resolution = new_resolution,
      handled_by = auth.uid(),
      handled_at = now()
  where r.status = 'open'
    and (
      r.id = report.id
      or (report.story_id is not null and r.story_id = report.story_id)
    );

  perform public.admin_write_audit(
    'resolve_story_report',
    'report',
    report.id,
    report.id,
    jsonb_build_object(
      'kind', 'story',
      'title', left(coalesce(report.snapshot->>'title', ''), 60),
      'action', action,
      'resolution', new_resolution,
      'removed', removed,
      'author_id', report.reported_user_id,
      'note', clean_note
    )
  );

  return jsonb_build_object(
    'id', report.id,
    'status', case new_status when 'actioned' then 'reviewed' else new_status end,
    'resolution', new_resolution
  );
end;
$$;

revoke execute on function public.admin_list_story_reports(text, integer, timestamptz)
  from public, anon;
revoke execute on function public.admin_get_story_report(uuid) from public, anon;
revoke execute on function public.admin_resolve_story_report(uuid, text, text)
  from public, anon;
grant execute on function public.admin_list_story_reports(text, integer, timestamptz)
  to authenticated;
grant execute on function public.admin_get_story_report(uuid) to authenticated;
grant execute on function public.admin_resolve_story_report(uuid, text, text)
  to authenticated;
