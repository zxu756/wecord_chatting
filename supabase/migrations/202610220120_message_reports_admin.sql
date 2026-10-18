-- Message reports (A1), part 2 of 2: the platform side. Reports of direct
-- chats and groups (message_reports.circle_id is null) go to the platform
-- admins of the K1 console (202610210110-0130); reports of circle channels
-- stay with the circle's moderators (202610220110) and are not visible here.
--
-- The functions follow the admin RPCs: security definer, admin_require() as
-- the first statement, every change written to admin_audit_log in the same
-- transaction. The rows come out in the shape of admin_list_reports and
-- admin_get_report, with kind 'message', so the console shows them with the
-- same list and detail screens; an actioned report is 'reviewed' there.
--
-- Roles: owner, moderator and support read and dismiss; deleting the message
-- and recording a suspension need owner or moderator. An admin who is the
-- reported person sees nothing of the report.
--
-- The suspension itself is done like for any report: the console calls the
-- `admin` Edge Function (suspend_user, which also bans the account in Auth),
-- then closes the report here with action 'suspend', which checks that the
-- person really is suspended.

-- Deletes a message for everyone as the platform: the same erasure as
-- recall_message (202610140007), for a caller who is not in the chat.
create or replace function public.admin_erase_message(target_message_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  target public.messages%rowtype;
  media_bucket text;
  media_path text;
begin
  select m.* into target
  from public.messages m
  where m.id = target_message_id
  for update;

  if target.id is null or target.type = 'system' or target.recalled_at is not null then
    return false;
  end if;

  media_bucket := target.attachment->>'bucket';
  media_path := target.attachment->>'path';
  if media_bucket is null
    or media_bucket not in ('chat-images', 'voice-messages', 'chat-files')
    or media_path is null
  then
    media_bucket := null;
    media_path := null;
  end if;

  update public.messages m
  set
    recalled_at = now(),
    recalled_by = auth.uid(),
    body = '',
    attachment = null,
    reply_preview = null,
    forwarded_from = null,
    mentions = '[]'::jsonb
  where m.id = target.id;

  delete from public.message_mentions mm where mm.message_id = target.id;
  delete from public.message_reactions r where r.message_id = target.id;
  delete from public.message_poll_votes v where v.message_id = target.id;
  delete from public.pinned_messages p where p.message_id = target.id;

  update public.messages m
  set reply_preview = m.reply_preview || jsonb_build_object('body', '')
  where m.reply_to_message_id = target.id
    and jsonb_typeof(m.reply_preview) = 'object';

  if media_path is not null then
    insert into public.recalled_message_media (
      bucket_id, object_path, message_id, deleted_by
    )
    values (media_bucket, media_path, target.id, auth.uid())
    on conflict on constraint recalled_message_media_pkey do update
    set
      message_id = excluded.message_id,
      deleted_by = excluded.deleted_by,
      created_at = now();
  end if;

  return true;
end;
$$;

revoke execute on function public.admin_erase_message(uuid)
  from public, anon, authenticated;

-- One message report as the queue shows it (the shape of admin_report_row).
create or replace function public.admin_message_report_row(r public.message_reports)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', r.id,
    'kind', 'message',
    'status', case r.status when 'actioned' then 'reviewed' else r.status end,
    'reason', r.reason,
    'details', r.details,
    'created_at', r.created_at,
    'handled_at', r.handled_at,
    'handled_by_username', hb.username,
    'resolution', r.resolution,
    'title', coalesce(r.snapshot->>'title', ''),
    'subject_id', r.message_id,
    'responsible_user_id', r.reported_user_id,
    'reporter', jsonb_build_object(
      'id', r.reporter_id,
      'username', rep.username,
      'display_name', rep.display_name
    ),
    'repeat_count', (
      select count(*)
      from public.message_reports o
      where o.status = 'open'
        and o.circle_id is null
        and o.message_id is not distinct from r.message_id
    )
  )
  from (select 1) one
  left join public.profiles rep on rep.id = r.reporter_id
  left join public.profiles hb on hb.id = r.handled_by;
$$;

revoke execute on function public.admin_message_report_row(public.message_reports)
  from public, anon, authenticated;

-- The queue of direct-chat and group message reports. [status_filter] is
-- 'open', 'handled', 'reviewed', 'dismissed' or 'all'; newest first, a page
-- at a time (pass the last created_at as before_created_at).
create or replace function public.admin_list_message_reports(
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
    select public.admin_message_report_row(r) as entry, r.created_at
    from public.message_reports r
    where r.circle_id is null
      and r.reported_user_id is distinct from auth.uid()
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

-- One message report in full, in the shape of admin_get_report: the report
-- with its snapshot (and the context the reporter agreed to share), the
-- sender as a person, other reports about the same message or sender, and
-- what admins did about the sender before.
create or replace function public.admin_get_message_report(target_report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  r public.message_reports%rowtype;
  subject jsonb;
  responsible jsonb;
  history jsonb;
  actions jsonb;
begin
  perform public.admin_require(array['owner', 'moderator', 'support']);

  select * into r
  from public.message_reports
  where id = target_report_id
    and circle_id is null
    and reported_user_id is distinct from auth.uid();
  if r.id is null then
    raise exception 'Report not found' using errcode = 'P0002';
  end if;

  select jsonb_build_object(
    'type', 'message',
    'id', r.message_id,
    'deleted', coalesce(m.recalled_at is not null, true),
    'missing', m.id is null
  ) into subject
  from (select 1) one
  left join public.messages m on m.id = r.message_id;

  select jsonb_build_object(
    'id', p.id,
    'username', p.username,
    'display_name', p.display_name,
    'avatar_url', p.avatar_url,
    'created_at', p.created_at,
    'is_suspended', public.is_user_suspended(p.id),
    'suspended_until', s.until,
    'suspension_reason', s.reason,
    'is_admin', exists (select 1 from public.app_admins a where a.user_id = p.id),
    'reports_against', (
      select count(*) from public.reports o where o.target_user_id = p.id
    ) + (
      select count(*) from public.message_reports o where o.reported_user_id = p.id
    ),
    'open_reports_against', (
      select count(*) from public.reports o
      where o.target_user_id = p.id and o.status = 'open'
    ) + (
      select count(*) from public.message_reports o
      where o.reported_user_id = p.id and o.status = 'open'
    )
  ) into responsible
  from public.profiles p
  left join public.app_user_suspensions s
    on s.user_id = p.id and (s.until is null or s.until > now())
  where p.id = r.reported_user_id;

  select coalesce(jsonb_agg(h.entry order by h.created_at desc), '[]'::jsonb)
  into history
  from (
    select jsonb_build_object(
      'id', o.id,
      'kind', 'message',
      'reason', o.reason,
      'status', case o.status when 'actioned' then 'reviewed' else o.status end,
      'resolution', o.resolution,
      'created_at', o.created_at
    ) as entry, o.created_at
    from public.message_reports o
    where o.id <> r.id
      and o.circle_id is null
      and (
        (r.message_id is not null and o.message_id = r.message_id)
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
    where l.action <> 'resolve_report'
      and l.action <> 'resolve_message_report'
      and (
        (l.target_type = 'user' and l.target_id = r.reported_user_id)
        or (l.target_type = 'message' and l.target_id = r.message_id)
      )
    order by l.created_at desc
    limit 20
  ) a;

  return jsonb_build_object(
    'report', public.admin_message_report_row(r) || jsonb_build_object(
      'snapshot',
      case when r.snapshot is null then '{}'::jsonb
        else r.snapshot
          || jsonb_build_object('context', coalesce(r.context, '[]'::jsonb))
      end
    ),
    'subject', subject,
    'responsible_user', responsible,
    'history', history,
    'actions', actions,
    'reporter_stats', (
      select jsonb_build_object(
        'total', (select count(*) from public.reports o where o.reporter_id = r.reporter_id)
          + (select count(*) from public.message_reports o where o.reporter_id = r.reporter_id),
        'dismissed', (
          select count(*) from public.reports o
          where o.reporter_id = r.reporter_id and o.status = 'dismissed'
        ) + (
          select count(*) from public.message_reports o
          where o.reporter_id = r.reporter_id and o.status = 'dismissed'
        )
      )
    )
  );
end;
$$;

-- Closes a direct-chat or group message report. [action]:
--   'dismiss'         no violation;
--   'delete_message'  delete the message for everyone;
--   'suspend'         the sender was suspended through the console (the
--                     `admin` function); refused while they are not.
-- Other open reports of the same message are closed with it.
create or replace function public.admin_resolve_message_report(
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
  report public.message_reports%rowtype;
  new_status text;
  new_resolution text;
  erased boolean := false;
  clean_note text := left(btrim(coalesce(note, '')), 500);
begin
  caller_role := public.admin_require(array['owner', 'moderator', 'support']);

  if action is null or action not in ('dismiss', 'delete_message', 'suspend') then
    raise exception 'Unknown action' using errcode = '22023';
  end if;
  if action <> 'dismiss' and caller_role = 'support' then
    raise exception 'Admin access required' using errcode = '42501';
  end if;

  select r.* into report
  from public.message_reports r
  where r.id = target_report_id
    and r.circle_id is null
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
  elsif action = 'delete_message' then
    new_status := 'actioned';
    new_resolution := 'message_deleted';
    if report.message_id is not null then
      erased := public.admin_erase_message(report.message_id);
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

  update public.message_reports r
  set status = new_status,
      resolution = new_resolution,
      handled_by = auth.uid(),
      handled_at = now()
  where r.circle_id is null
    and r.status = 'open'
    and (
      r.id = report.id
      or (report.message_id is not null and r.message_id = report.message_id)
    );

  perform public.admin_write_audit(
    'resolve_message_report',
    'message',
    report.message_id,
    report.id,
    jsonb_build_object(
      'title', left(coalesce(report.snapshot->>'title', ''), 60),
      'action', action,
      'resolution', new_resolution,
      'erased', erased,
      'sender_id', report.reported_user_id,
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

revoke execute on function public.admin_list_message_reports(text, integer, timestamptz)
  from public, anon;
revoke execute on function public.admin_get_message_report(uuid) from public, anon;
revoke execute on function public.admin_resolve_message_report(uuid, text, text)
  from public, anon;

grant execute on function public.admin_list_message_reports(text, integer, timestamptz)
  to authenticated;
grant execute on function public.admin_get_message_report(uuid) to authenticated;
grant execute on function public.admin_resolve_message_report(uuid, text, text)
  to authenticated;
