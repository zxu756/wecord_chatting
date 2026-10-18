-- Admin console (K1), part 3 of 3: the admin RPCs. Tables are in
-- 202610210110, what a take-down does in 202610210120.
--
-- Every function is security definer and starts with admin_require(roles),
-- which raises 42501 for anybody who is not an admin of one of those roles,
-- so the grant to `authenticated` gives a normal user nothing. Roles:
--   owner, moderator  everything below
--   support           reads reports and the audit log, and closes reports
--                     (admin_resolve_report); no sanctions
-- Every change is written to admin_audit_log in the same transaction.
--
-- None of them reads chat: reports are read through the snapshot taken when
-- they were filed (202610210110), plus counts and non-content facts about
-- the people and circles involved.
--
-- Banning (the Auth user) is done by the admin Edge Function, which calls
-- admin_suspend_user as the admin and then bans the account with the
-- service role; this file only holds the database half.

-- Closes an open report as part of another action (internal). Does nothing
-- when [target_report_id] is null; raises when it is not an open report.
create or replace function public.admin_close_report(
  target_report_id uuid,
  new_status text,
  new_resolution text,
  note text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  closed integer;
begin
  if target_report_id is null then
    return;
  end if;
  update public.reports r
  set status = new_status,
      resolution = new_resolution,
      handled_by = auth.uid(),
      handled_at = now()
  where r.id = target_report_id
    and r.status = 'open';
  get diagnostics closed = row_count;
  if closed = 0 then
    raise exception 'Report not found or already handled'
      using errcode = 'P0002';
  end if;
  perform public.admin_write_audit(
    'resolve_report',
    'report',
    target_report_id,
    target_report_id,
    jsonb_build_object(
      'status', new_status,
      'resolution', new_resolution,
      'note', left(coalesce(note, ''), 500)
    )
  );
end;
$$;

revoke execute on function public.admin_close_report(uuid, text, text, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Reports
-- ---------------------------------------------------------------------------

-- One report as the queue shows it.
create or replace function public.admin_report_row(r public.reports)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', r.id,
    'kind', public.report_kind(r),
    'status', r.status,
    'reason', r.reason,
    'details', r.details,
    'created_at', r.created_at,
    'handled_at', r.handled_at,
    'handled_by_username', hb.username,
    'resolution', r.resolution,
    'title', coalesce(r.snapshot->>'title', ''),
    'subject_id', case public.report_kind(r)
      when 'post' then r.target_post_id
      when 'circle' then r.target_circle_id
      else r.target_user_id
    end,
    'responsible_user_id', r.target_user_id,
    'reporter', jsonb_build_object(
      'id', r.reporter_id,
      'username', rep.username,
      'display_name', rep.display_name
    ),
    'repeat_count', (
      select count(*)
      from public.reports o
      where o.status = 'open'
        and public.report_kind(o) = public.report_kind(r)
        and (
          case public.report_kind(o)
            when 'post' then o.target_post_id
            when 'circle' then o.target_circle_id
            else o.target_user_id
          end
        ) is not distinct from (
          case public.report_kind(r)
            when 'post' then r.target_post_id
            when 'circle' then r.target_circle_id
            else r.target_user_id
          end
        )
    )
  )
  from (select 1) one
  left join public.profiles rep on rep.id = r.reporter_id
  left join public.profiles hb on hb.id = r.handled_by;
$$;

revoke execute on function public.admin_report_row(public.reports)
  from public, anon, authenticated;

-- The queue: kind_filter 'user' | 'circle' | 'post' (| 'message' once A1
-- lands) or null for all; status_filter 'open', 'handled' (reviewed or
-- dismissed), 'reviewed', 'dismissed' or 'all'. Newest first, a page at a
-- time: pass the last created_at as before_created_at for the next page.
create or replace function public.admin_list_reports(
  kind_filter text default null,
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

  if kind_filter is not null
    and kind_filter not in ('user', 'circle', 'post', 'message')
  then
    raise exception 'Unknown report kind' using errcode = '22023';
  end if;
  if status_filter is not null
    and status_filter not in ('open', 'handled', 'reviewed', 'dismissed', 'all')
  then
    raise exception 'Unknown report status' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(page_row.entry order by page_row.created_at desc), '[]'::jsonb)
  into result
  from (
    select public.admin_report_row(r) as entry, r.created_at
    from public.reports r
    where (kind_filter is null or public.report_kind(r) = kind_filter)
      and (
        status_filter is null
        or status_filter = 'all'
        or (status_filter = 'handled' and r.status in ('reviewed', 'dismissed'))
        or r.status = status_filter
      )
      and (before_created_at is null or r.created_at < before_created_at)
    order by r.created_at desc
    limit page
  ) page_row;

  return result;
end;
$$;

-- One report with everything the admin needs to decide: the report and its
-- snapshot, the person or circle it is about, who answers for it, earlier
-- reports about the same subject, and what admins did about it before.
create or replace function public.admin_get_report(target_report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  r public.reports%rowtype;
  kind text;
  subject jsonb;
  responsible jsonb;
  history jsonb;
  actions jsonb;
  subject_id uuid;
begin
  perform public.admin_require(array['owner', 'moderator', 'support']);

  select * into r from public.reports where id = target_report_id;
  if r.id is null then
    raise exception 'Report not found' using errcode = 'P0002';
  end if;
  kind := public.report_kind(r);
  subject_id := case kind
    when 'post' then r.target_post_id
    when 'circle' then r.target_circle_id
    else r.target_user_id
  end;

  -- Live, non-content facts about the subject.
  if kind = 'circle' then
    select jsonb_build_object(
      'type', 'circle',
      'id', c.id,
      'name', c.name,
      'owner_id', c.owner_id,
      'owner_username', o.username,
      'member_count', (select count(*) from public.circle_members m where m.circle_id = c.id),
      'is_public', c.is_public,
      'created_at', c.created_at,
      'disabled_mode', c.disabled_mode,
      'disabled_at', c.disabled_at
    ) into subject
    from public.circles c
    left join public.profiles o on o.id = c.owner_id
    where c.id = r.target_circle_id;
  elsif kind = 'post' then
    select jsonb_build_object(
      'type', 'post',
      'id', p.id,
      'deleted', p.deleted_at is not null,
      'circle_id', p.circle_id,
      'circle_name', c.name,
      'circle_disabled_mode', c.disabled_mode,
      'created_at', p.created_at
    ) into subject
    from public.circle_posts p
    left join public.circles c on c.id = p.circle_id
    where p.id = r.target_post_id;
  end if;
  subject := coalesce(subject, jsonb_build_object('type', kind, 'missing', true));

  -- The person who answers for it: the reported person, a circle's owner or
  -- a post's author.
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
    ),
    'open_reports_against', (
      select count(*) from public.reports o
      where o.target_user_id = p.id and o.status = 'open'
    )
  ) into responsible
  from public.profiles p
  left join public.app_user_suspensions s
    on s.user_id = p.id and (s.until is null or s.until > now())
  where p.id = r.target_user_id;

  -- Earlier and later reports about the same subject.
  select coalesce(jsonb_agg(h.entry order by h.created_at desc), '[]'::jsonb)
  into history
  from (
    select jsonb_build_object(
      'id', o.id,
      'kind', public.report_kind(o),
      'reason', o.reason,
      'status', o.status,
      'resolution', o.resolution,
      'created_at', o.created_at
    ) as entry, o.created_at
    from public.reports o
    where o.id <> r.id
      and (
        (kind = 'post' and o.target_post_id = r.target_post_id)
        or (kind = 'circle' and o.target_circle_id = r.target_circle_id)
        or (kind = 'user' and o.target_user_id = r.target_user_id)
      )
    order by o.created_at desc
    limit 20
  ) h;

  -- What admins already did about the subject or the responsible person.
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
      and (
        (l.target_type = 'user' and l.target_id = r.target_user_id)
        or (l.target_type = 'circle' and l.target_id = r.target_circle_id)
        or (l.target_type = 'circle_post' and l.target_id = r.target_post_id)
      )
    order by l.created_at desc
    limit 20
  ) a;

  return jsonb_build_object(
    'report', public.admin_report_row(r) || jsonb_build_object('snapshot', coalesce(r.snapshot, '{}'::jsonb)),
    'subject', subject,
    'responsible_user', responsible,
    'history', history,
    'actions', actions,
    'reporter_stats', (
      select jsonb_build_object(
        'total', count(*),
        'dismissed', count(*) filter (where o.status = 'dismissed')
      )
      from public.reports o
      where o.reporter_id = r.reporter_id
    )
  );
end;
$$;

-- Closes a report without any other action (or after the admin did
-- something the report does not know about). [new_status] is 'reviewed' or
-- 'dismissed'; [resolution] says what was decided.
create or replace function public.admin_resolve_report(
  target_report_id uuid,
  new_status text,
  resolution text,
  note text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.admin_require(array['owner', 'moderator', 'support']);
  if new_status is null or new_status not in ('reviewed', 'dismissed') then
    raise exception 'Unknown report status' using errcode = '22023';
  end if;
  if resolution is null or resolution not in (
    'no_violation', 'duplicate', 'content_removed', 'user_suspended',
    'circle_delisted', 'circle_suspended', 'other'
  ) then
    raise exception 'Unknown resolution' using errcode = '22023';
  end if;
  perform public.admin_close_report(target_report_id, new_status, resolution, note);
end;
$$;

-- ---------------------------------------------------------------------------
-- People
-- ---------------------------------------------------------------------------

-- The database half of a suspension: the row that the insert triggers
-- check (202610210120). [until] null is for good. The admin Edge Function
-- calls this as the admin and then bans the Auth user.
create or replace function public.admin_suspend_user(
  target_user_id uuid,
  until timestamptz default null,
  reason text default '',
  report_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_reason text := left(btrim(coalesce(reason, '')), 500);
  target public.profiles%rowtype;
begin
  perform public.admin_require(array['owner', 'moderator']);

  if clean_reason = '' then
    raise exception 'A reason is required' using errcode = '22023';
  end if;
  if until is not null and until <= now() then
    raise exception 'The end of a suspension must be in the future'
      using errcode = '22023';
  end if;
  if target_user_id = auth.uid() then
    raise exception 'You cannot suspend yourself' using errcode = '42501';
  end if;
  if exists (select 1 from public.app_admins a where a.user_id = target_user_id) then
    raise exception 'Admins cannot be suspended' using errcode = '42501';
  end if;

  select * into target from public.profiles where id = target_user_id;
  if target.id is null then
    raise exception 'User not found' using errcode = 'P0002';
  end if;

  insert into public.app_user_suspensions as s (user_id, until, reason, created_by)
  values (target_user_id, until, clean_reason, auth.uid())
  on conflict (user_id) do update
    set until = excluded.until,
        reason = excluded.reason,
        created_by = excluded.created_by,
        created_at = now();

  perform public.admin_write_audit(
    'suspend_user', 'user', target_user_id, report_id,
    jsonb_build_object(
      'title', '@' || target.username,
      'until', until,
      'reason', clean_reason
    )
  );
  perform public.admin_close_report(report_id, 'reviewed', 'user_suspended', clean_reason);

  return jsonb_build_object('user_id', target_user_id, 'until', until);
end;
$$;

create or replace function public.admin_unsuspend_user(
  target_user_id uuid,
  reason text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target public.profiles%rowtype;
  removed integer;
begin
  perform public.admin_require(array['owner', 'moderator']);

  select * into target from public.profiles where id = target_user_id;
  if target.id is null then
    raise exception 'User not found' using errcode = 'P0002';
  end if;

  delete from public.app_user_suspensions s where s.user_id = target_user_id;
  get diagnostics removed = row_count;
  -- Lifting a suspension that is not there still goes through: the Auth ban
  -- may be (idempotent), and the audit log says what was asked.
  perform public.admin_write_audit(
    'unsuspend_user', 'user', target_user_id, null,
    jsonb_build_object(
      'title', '@' || target.username,
      'had_suspension', removed > 0,
      'reason', left(btrim(coalesce(reason, '')), 500)
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Circles and posts
-- ---------------------------------------------------------------------------

-- Takes a circle down. [mode] is 'delist' (hidden from Discover, no new
-- members, members keep using it) or 'suspend' (nobody can enter or read).
-- Invites that exist are revoked. Calling it again changes the mode.
create or replace function public.admin_disable_circle(
  target_circle_id uuid,
  mode text,
  reason text default '',
  report_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_reason text := left(btrim(coalesce(reason, '')), 500);
  circle public.circles%rowtype;
  previous_mode text;
begin
  perform public.admin_require(array['owner', 'moderator']);

  if mode is null or mode not in ('delist', 'suspend') then
    raise exception 'Unknown take-down mode' using errcode = '22023';
  end if;
  if clean_reason = '' then
    raise exception 'A reason is required' using errcode = '22023';
  end if;

  select * into circle from public.circles where id = target_circle_id for update;
  if circle.id is null then
    raise exception 'Circle not found' using errcode = 'P0002';
  end if;
  previous_mode := circle.disabled_mode;

  update public.circles c
  set disabled_at = coalesce(c.disabled_at, now()),
      disabled_mode = mode,
      disabled_reason = clean_reason
  where c.id = target_circle_id;

  update public.circle_invites i
  set revoked_at = now()
  where i.circle_id = target_circle_id
    and i.revoked_at is null;

  perform public.admin_write_audit(
    'disable_circle', 'circle', target_circle_id, report_id,
    jsonb_build_object(
      'title', circle.name,
      'mode', mode,
      'previous_mode', previous_mode,
      'reason', clean_reason
    )
  );
  perform public.admin_close_report(
    report_id,
    'reviewed',
    case mode when 'suspend' then 'circle_suspended' else 'circle_delisted' end,
    clean_reason
  );
end;
$$;

create or replace function public.admin_enable_circle(
  target_circle_id uuid,
  reason text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  circle public.circles%rowtype;
begin
  perform public.admin_require(array['owner', 'moderator']);

  select * into circle from public.circles where id = target_circle_id for update;
  if circle.id is null then
    raise exception 'Circle not found' using errcode = 'P0002';
  end if;

  update public.circles c
  set disabled_at = null,
      disabled_mode = null,
      disabled_reason = null
  where c.id = target_circle_id;

  perform public.admin_write_audit(
    'enable_circle', 'circle', target_circle_id, null,
    jsonb_build_object(
      'title', circle.name,
      'previous_mode', circle.disabled_mode,
      'reason', left(btrim(coalesce(reason, '')), 500)
    )
  );
end;
$$;

-- Removes a circle post (soft delete, as the author's delete does).
create or replace function public.admin_delete_circle_post(
  target_post_id uuid,
  reason text default '',
  report_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_reason text := left(btrim(coalesce(reason, '')), 500);
  post public.circle_posts%rowtype;
begin
  perform public.admin_require(array['owner', 'moderator']);

  if clean_reason = '' then
    raise exception 'A reason is required' using errcode = '22023';
  end if;

  select * into post from public.circle_posts p
  where p.id = target_post_id and p.deleted_at is null
  for update;
  if post.id is null then
    raise exception 'Post not found' using errcode = 'P0002';
  end if;

  update public.circle_posts p
  set deleted_at = now()
  where p.id = target_post_id;

  perform public.admin_write_audit(
    'delete_circle_post', 'circle_post', target_post_id, report_id,
    jsonb_build_object(
      'title', left(regexp_replace(post.body, '\s+', ' ', 'g'), 60),
      'circle_id', post.circle_id,
      'author_id', post.author_id,
      'reason', clean_reason
    )
  );
  perform public.admin_close_report(report_id, 'reviewed', 'content_removed', clean_reason);
end;
$$;

-- ---------------------------------------------------------------------------
-- Audit log
-- ---------------------------------------------------------------------------

-- Newest first, a page at a time (before_created_at is the last entry's
-- created_at). [target_type_filter] and [target_id_filter] narrow it to one
-- subject.
create or replace function public.admin_list_audit_log(
  page_size integer default 50,
  before_created_at timestamptz default null,
  target_type_filter text default null,
  target_id_filter uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  page integer := least(greatest(coalesce(page_size, 50), 1), 200);
  result jsonb;
begin
  perform public.admin_require(array['owner', 'moderator', 'support']);

  select coalesce(jsonb_agg(e.entry order by e.created_at desc), '[]'::jsonb)
  into result
  from (
    select jsonb_build_object(
      'id', l.id,
      'action', l.action,
      'actor_id', l.actor_id,
      'actor_username', actor.username,
      'actor_role', l.actor_role,
      'target_type', l.target_type,
      'target_id', l.target_id,
      'report_id', l.report_id,
      'details', l.details,
      'created_at', l.created_at
    ) as entry, l.created_at
    from public.admin_audit_log l
    left join public.profiles actor on actor.id = l.actor_id
    where (before_created_at is null or l.created_at < before_created_at)
      and (target_type_filter is null or l.target_type = target_type_filter)
      and (target_id_filter is null or l.target_id = target_id_filter)
    order by l.created_at desc
    limit page
  ) e;

  return result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

revoke execute on function public.admin_list_reports(text, text, integer, timestamptz)
  from public, anon;
revoke execute on function public.admin_get_report(uuid) from public, anon;
revoke execute on function public.admin_resolve_report(uuid, text, text, text)
  from public, anon;
revoke execute on function public.admin_suspend_user(uuid, timestamptz, text, uuid)
  from public, anon;
revoke execute on function public.admin_unsuspend_user(uuid, text) from public, anon;
revoke execute on function public.admin_disable_circle(uuid, text, text, uuid)
  from public, anon;
revoke execute on function public.admin_enable_circle(uuid, text) from public, anon;
revoke execute on function public.admin_delete_circle_post(uuid, text, uuid)
  from public, anon;
revoke execute on function public.admin_list_audit_log(integer, timestamptz, text, uuid)
  from public, anon;

grant execute on function public.admin_list_reports(text, text, integer, timestamptz)
  to authenticated;
grant execute on function public.admin_get_report(uuid) to authenticated;
grant execute on function public.admin_resolve_report(uuid, text, text, text)
  to authenticated;
grant execute on function public.admin_suspend_user(uuid, timestamptz, text, uuid)
  to authenticated;
grant execute on function public.admin_unsuspend_user(uuid, text) to authenticated;
grant execute on function public.admin_disable_circle(uuid, text, text, uuid)
  to authenticated;
grant execute on function public.admin_enable_circle(uuid, text) to authenticated;
grant execute on function public.admin_delete_circle_post(uuid, text, uuid)
  to authenticated;
grant execute on function public.admin_list_audit_log(integer, timestamptz, text, uuid)
  to authenticated;
