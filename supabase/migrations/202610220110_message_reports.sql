-- Message reports (A1), part 1 of 2: report one message to the people who
-- run the place it was sent. Part 2 (202610220120) is the platform side.
--
-- * message_reports: a report of one message. `snapshot` is a copy of the
--   message as it was when it was reported (body, attachment metadata,
--   sender, time), so the report can be handled after the message is
--   recalled or has expired. View-once media is never copied, only a
--   placeholder, and attachment paths are not copied at all. `context` is up
--   to 5 messages before and after it, but only the ones the reporter could
--   see (the same rules as the messages select policy), and only when the
--   reporter agreed to "Include context".
-- * Who handles it: a report of a circle channel (circle_id is set) goes to
--   the circle's moderators, members with manage_messages. A report of a
--   direct chat or a group (circle_id is null) goes to the platform admins
--   (202610220120, the K1 console). Nobody else reads it, and the reported
--   person never sees that a report exists: they are left out of every list
--   and count, even when they moderate the circle themselves.
-- * Clients cannot read the table's content. A reporter reads their own
--   rows' plain columns (id, reason, status, ...), moderators and admins
--   read the same plain columns of the rows they handle; snapshot, context
--   and details are returned only by the security definer functions below.
-- * report_message(...) files a report: the reporter must be able to see the
--   message, cannot report their own message, has a daily limit, and can
--   block the sender in the same call.
-- * list_circle_message_reports(circle) and resolve_message_report(report,
--   action) are the moderators' side: dismiss, delete the message, time the
--   sender out or ban them. Deleting, timing out and banning go through
--   recall_message, timeout_circle_member and ban_circle_member, so their
--   own permission checks and audit entries apply; the circle audit log also
--   gets a report_resolve (or report_dismiss) entry.
-- * count_message_reviews (the badge of the circle's Review queue) now
--   counts open message reports too. Same as 202610170090 otherwise.
-- * purge_old_message_report_data() clears snapshot and context 90 days
--   after a report was handled. purge_old_client_errors(), which pg_cron
--   already runs once a day (202610190030), calls it, so no new cron job.

create table if not exists public.message_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  -- Set null when the message is purged (expired) or its chat is deleted.
  message_id uuid references public.messages(id) on delete set null,
  conversation_id uuid references public.conversations(id) on delete set null,
  circle_id uuid references public.circles(id) on delete cascade,
  -- The person who sent the message.
  reported_user_id uuid references public.profiles(id) on delete set null,
  reason text not null,
  details text not null default '',
  snapshot jsonb,
  context jsonb,
  status text not null default 'open',
  handled_by uuid references public.profiles(id) on delete set null,
  handled_at timestamptz,
  resolution text,
  created_at timestamptz not null default now(),
  constraint message_reports_reason_check check (
    reason in ('spam', 'harassment', 'impersonation', 'unsafe_content', 'other')
  ),
  constraint message_reports_status_check check (
    status in ('open', 'actioned', 'dismissed')
  ),
  constraint message_reports_details_length check (char_length(details) <= 1000),
  constraint message_reports_resolution_length check (
    resolution is null or char_length(resolution) between 1 and 40
  )
);

create unique index if not exists message_reports_once_per_reporter_idx
  on public.message_reports (reporter_id, message_id)
  where message_id is not null;
create index if not exists message_reports_reporter_created_idx
  on public.message_reports (reporter_id, created_at desc);
create index if not exists message_reports_circle_status_idx
  on public.message_reports (circle_id, status, created_at desc)
  where circle_id is not null;
create index if not exists message_reports_platform_status_idx
  on public.message_reports (status, created_at desc)
  where circle_id is null;
create index if not exists message_reports_handled_idx
  on public.message_reports (handled_at)
  where handled_at is not null and (snapshot is not null or context is not null);

alter table public.message_reports enable row level security;
revoke all on public.message_reports from public, anon, authenticated;
-- The plain columns only: snapshot, context, details and the reported
-- person are never readable through the table API.
grant select (
  id, reporter_id, message_id, conversation_id, circle_id, reason, status,
  created_at, handled_at
) on public.message_reports to authenticated;

drop policy if exists message_reports_select_reporter on public.message_reports;
create policy message_reports_select_reporter
  on public.message_reports for select
  to authenticated
  using (reporter_id = auth.uid());

drop policy if exists message_reports_select_handler on public.message_reports;
create policy message_reports_select_handler
  on public.message_reports for select
  to authenticated
  using (
    reported_user_id is distinct from auth.uid()
    and (
      (circle_id is not null
        and public.current_user_has_circle_permission(circle_id, 'manage_messages'))
      or (circle_id is null and public.is_app_admin())
    )
  );

-- ---------------------------------------------------------------------------
-- What goes into a snapshot
-- ---------------------------------------------------------------------------

-- Attachment metadata that is safe to keep: kind, name, type and size, never
-- a storage path, a link or a position. View-once media is a placeholder.
create or replace function public.report_attachment_meta(attachment jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select case
    when attachment is null or jsonb_typeof(attachment) <> 'object' then null
    when attachment->>'view_once' = 'true'
      then jsonb_build_object('kind', 'view_once', 'view_once', true)
    else coalesce(
      (
        select jsonb_object_agg(e.key, e.value)
        from jsonb_each(attachment) e
        where e.key in (
            'kind', 'name', 'mime_type', 'size', 'width', 'height',
            'duration', 'duration_ms', 'title'
          )
          and jsonb_typeof(e.value) in ('string', 'number', 'boolean')
      ),
      '{}'::jsonb
    )
  end;
$$;

revoke execute on function public.report_attachment_meta(jsonb)
  from public, anon, authenticated;

-- Whether the caller sees [m] the way the messages select policy lets them
-- (202610170091): readable conversation, not expired, not held by the AI
-- guard for somebody else. A recalled message has no content left to report.
create or replace function public.report_can_see_message(m public.messages)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select m.id is not null
    and m.recalled_at is null
    and (m.expires_at is null or m.expires_at > now())
    and m.conversation_id in (select public.current_user_readable_conversation_ids())
    and public.message_visible_to_current_user(
      m.review_state, m.sender_id, m.conversation_id
    );
$$;

revoke execute on function public.report_can_see_message(public.messages)
  from public, anon, authenticated;

-- A copy of [m] as it is now.
create or replace function public.report_message_snapshot(m public.messages)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'kind', 'message',
    'title', left(
      regexp_replace(
        coalesce(
          nullif(btrim(m.body), ''),
          case when m.attachment->>'view_once' = 'true' then 'View-once media'
            else coalesce(m.attachment->>'name', m.type) end
        ),
        '\s+', ' ', 'g'
      ),
      80
    ),
    'message_id', m.id,
    'type', m.type,
    'body', m.body,
    'attachment', public.report_attachment_meta(m.attachment),
    'created_at', m.created_at,
    'edited_at', m.edited_at,
    'forwarded', m.forwarded_from is not null,
    'sender_id', m.sender_id,
    'sender_username', s.username,
    'sender_display_name', s.display_name,
    'webhook_name', m.webhook_name,
    'conversation_id', m.conversation_id,
    'conversation_type', c.type,
    'conversation_title', c.title,
    'circle_id', cc.circle_id,
    'circle_name', ci.name,
    'channel_name', cc.name
  )
  from (select 1) one
  left join public.profiles s on s.id = m.sender_id
  left join public.conversations c on c.id = m.conversation_id
  left join public.circle_channels cc
    on cc.id = public.conversation_circle_channel_id(m.conversation_id)
  left join public.circles ci on ci.id = cc.circle_id;
$$;

revoke execute on function public.report_message_snapshot(public.messages)
  from public, anon, authenticated;

-- Up to 5 messages before and 5 after [m] that the caller can see.
create or replace function public.report_message_context(m public.messages)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', x.id,
        'sender_id', x.sender_id,
        'sender_name', coalesce(nullif(btrim(p.display_name), ''), p.username),
        'type', x.type,
        'body', x.body,
        'attachment', public.report_attachment_meta(x.attachment),
        'created_at', x.created_at,
        'position', x.rel
      )
      order by x.created_at, x.id
    ),
    '[]'::jsonb
  )
  from (
    (
      select b.*, 'before'::text as rel
      from public.messages b
      where b.conversation_id = m.conversation_id
        and (b.created_at, b.id) < (m.created_at, m.id)
        and public.report_can_see_message(b)
      order by b.created_at desc, b.id desc
      limit 5
    )
    union all
    (
      select a.*, 'after'::text as rel
      from public.messages a
      where a.conversation_id = m.conversation_id
        and (a.created_at, a.id) > (m.created_at, m.id)
        and public.report_can_see_message(a)
      order by a.created_at asc, a.id asc
      limit 5
    )
  ) x
  left join public.profiles p on p.id = x.sender_id;
$$;

revoke execute on function public.report_message_context(public.messages)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Reporting
-- ---------------------------------------------------------------------------

-- Reports a message. Returns the report's id; reporting the same message
-- again returns the first report. At most 20 new reports per person in 24
-- hours (54000). [also_block] blocks the sender too.
create or replace function public.report_message(
  target_message_id uuid,
  report_reason text,
  report_details text default '',
  include_context boolean default true,
  also_block boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  msg public.messages%rowtype;
  channel public.circle_channels%rowtype;
  existing_id uuid;
  created_id uuid;
  recent integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if report_reason is null
    or report_reason not in (
      'spam', 'harassment', 'impersonation', 'unsafe_content', 'other'
    )
  then
    raise exception 'Unknown report reason' using errcode = '22023';
  end if;

  select m.* into msg
  from public.messages m
  where m.id = target_message_id;

  -- One answer for "no such message" and "a message you cannot see".
  if msg.id is null or not public.report_can_see_message(msg) then
    raise exception 'Message not found' using errcode = 'P0002';
  end if;

  if msg.type = 'system' then
    raise exception 'This message cannot be reported' using errcode = '22023';
  end if;

  if msg.sender_id = current_user_id then
    raise exception 'You cannot report your own message' using errcode = '22023';
  end if;

  -- Reports of one person are counted one at a time.
  perform pg_advisory_xact_lock(hashtextextended('message_report:' || current_user_id::text, 0));

  select r.id into existing_id
  from public.message_reports r
  where r.reporter_id = current_user_id
    and r.message_id = msg.id;

  if existing_id is null then
    select count(*)::integer into recent
    from public.message_reports r
    where r.reporter_id = current_user_id
      and r.created_at > now() - interval '24 hours';
    if recent >= 20 then
      raise exception 'You have sent too many reports today. Try again tomorrow.'
        using errcode = '54000';
    end if;

    select cc.* into channel
    from public.circle_channels cc
    where cc.id = public.conversation_circle_channel_id(msg.conversation_id);

    insert into public.message_reports (
      reporter_id, message_id, conversation_id, circle_id, reported_user_id,
      reason, details, snapshot, context
    )
    values (
      current_user_id,
      msg.id,
      msg.conversation_id,
      channel.circle_id,
      msg.sender_id,
      report_reason,
      left(btrim(coalesce(report_details, '')), 1000),
      public.report_message_snapshot(msg),
      case when coalesce(include_context, false)
        then public.report_message_context(msg) end
    )
    returning id into created_id;
  else
    created_id := existing_id;
  end if;

  if coalesce(also_block, false) then
    perform public.block_user(msg.sender_id);
  end if;

  return created_id;
end;
$$;

revoke execute on function public.report_message(uuid, text, text, boolean, boolean)
  from public, anon;
grant execute on function public.report_message(uuid, text, text, boolean, boolean)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Moderators
-- ---------------------------------------------------------------------------

-- The reports of a circle's messages for its moderators (manage_messages),
-- newest first. [status_filter] is 'open' (default), 'handled' or 'all'.
-- Reports about the caller's own messages are left out.
create or replace function public.list_circle_message_reports(
  target_circle_id uuid,
  status_filter text default 'open',
  max_results integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.current_user_has_circle_permission(target_circle_id, 'manage_messages') then
    raise exception 'Only members who manage messages can see reports'
      using errcode = '42501';
  end if;
  if status_filter is null or status_filter not in ('open', 'handled', 'all') then
    raise exception 'Unknown report status' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(page.entry order by page.created_at desc), '[]'::jsonb)
  into result
  from (
    select
      jsonb_build_object(
        'id', r.id,
        'status', r.status,
        'reason', r.reason,
        'details', r.details,
        'created_at', r.created_at,
        'handled_at', r.handled_at,
        'resolution', r.resolution,
        'message_id', r.message_id,
        'message_available', coalesce((
          select m.recalled_at is null
          from public.messages m
          where m.id = r.message_id
        ), false),
        'reporter', jsonb_build_object(
          'id', r.reporter_id,
          'name', public.circle_member_label(r.circle_id, r.reporter_id)
        ),
        'reported_user', jsonb_build_object(
          'id', r.reported_user_id,
          'name', public.circle_member_label(r.circle_id, r.reported_user_id),
          'avatar_url', ru.avatar_url
        ),
        'snapshot', r.snapshot,
        'context', r.context,
        'repeat_count', (
          select count(*)
          from public.message_reports o
          where o.circle_id = r.circle_id
            and o.status = 'open'
            and o.message_id is not distinct from r.message_id
        )
      ) as entry,
      r.created_at
    from public.message_reports r
    left join public.profiles ru on ru.id = r.reported_user_id
    where r.circle_id = target_circle_id
      and r.reported_user_id is distinct from auth.uid()
      and (
        status_filter = 'all'
        or (status_filter = 'open' and r.status = 'open')
        or (status_filter = 'handled' and r.status <> 'open')
      )
    order by r.created_at desc
    limit least(greatest(coalesce(max_results, 100), 1), 200)
  ) page;

  return result;
end;
$$;

-- Handles a circle's message report. [action]:
--   'dismiss'         close it, nothing was wrong;
--   'delete_message'  delete the message for everyone (recall_message);
--   'timeout'         time the sender out for [duration_seconds] (default
--                     1 hour, at most 28 days; timeout_circle_member);
--   'ban'             ban the sender from the circle (ban_circle_member).
-- The called functions check their own permissions (moderate_members,
-- ban_members, manage_messages in the channel), so a moderator who may not
-- do that gets 42501 and the report stays open.
create or replace function public.resolve_message_report(
  target_report_id uuid,
  action text,
  duration_seconds integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  report public.message_reports%rowtype;
  new_status text;
  new_resolution text;
  label text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if action is null or action not in ('dismiss', 'delete_message', 'timeout', 'ban') then
    raise exception 'Unknown action' using errcode = '22023';
  end if;

  select r.* into report
  from public.message_reports r
  where r.id = target_report_id
  for update;

  -- Platform reports (no circle) are handled in the admin console.
  if report.id is null
    or report.circle_id is null
    or report.reported_user_id is not distinct from current_user_id
    or not public.current_user_has_circle_permission(report.circle_id, 'manage_messages')
  then
    raise exception 'Report not found' using errcode = 'P0002';
  end if;
  if report.status <> 'open' then
    raise exception 'Report already handled' using errcode = 'P0002';
  end if;

  label := coalesce(
    public.circle_member_label(report.circle_id, report.reported_user_id),
    ''
  );

  if action = 'dismiss' then
    new_status := 'dismissed';
    new_resolution := 'dismissed';
  elsif action = 'delete_message' then
    new_status := 'actioned';
    new_resolution := 'message_deleted';
    -- Already gone (expired, or deleted by someone) counts as done.
    if exists (
      select 1 from public.messages m
      where m.id = report.message_id and m.recalled_at is null
    ) then
      perform * from public.recall_message(report.message_id);
    end if;
  elsif action = 'timeout' then
    new_status := 'actioned';
    new_resolution := 'user_timed_out';
    if report.reported_user_id is null then
      raise exception 'The sender no longer exists' using errcode = 'P0002';
    end if;
    perform public.timeout_circle_member(
      report.circle_id,
      report.reported_user_id,
      coalesce(duration_seconds, 3600)
    );
  else
    new_status := 'actioned';
    new_resolution := 'user_banned';
    if report.reported_user_id is null then
      raise exception 'The sender no longer exists' using errcode = 'P0002';
    end if;
    perform * from public.ban_circle_member(
      report.circle_id,
      report.reported_user_id,
      'Reported message',
      0
    );
  end if;

  update public.message_reports r
  set status = new_status,
      resolution = new_resolution,
      handled_by = current_user_id,
      handled_at = now()
  where r.id = report.id;

  -- Other open reports of the same message are settled with it.
  update public.message_reports r
  set status = new_status,
      resolution = new_resolution,
      handled_by = current_user_id,
      handled_at = now()
  where r.circle_id = report.circle_id
    and r.status = 'open'
    and r.id <> report.id
    and r.message_id is not null
    and r.message_id = report.message_id;

  perform public.write_circle_audit(
    report.circle_id,
    case when action = 'dismiss' then 'report_dismiss' else 'report_resolve' end,
    'message',
    report.message_id,
    label,
    jsonb_build_object(
      'report_id', report.id,
      'action', action,
      'reason', report.reason
    )
  );

  return jsonb_build_object(
    'id', report.id,
    'status', new_status,
    'resolution', new_resolution
  );
end;
$$;

revoke execute on function public.list_circle_message_reports(uuid, text, integer)
  from public, anon;
revoke execute on function public.resolve_message_report(uuid, text, integer)
  from public, anon;
grant execute on function public.list_circle_message_reports(uuid, text, integer)
  to authenticated;
grant execute on function public.resolve_message_report(uuid, text, integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- The Review badge
-- ---------------------------------------------------------------------------

-- Same as 202610170090_ai_guard, plus the open message reports of the circle
-- (for moderators who manage messages, not counting reports about
-- themselves). Still counts up to 99.
create or replace function public.count_message_reviews(target_circle_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  reviews integer;
  reports integer;
begin
  if auth.uid() is null then
    return 0;
  end if;
  select count(*)::integer
  into reviews
  from (
    select 1
    from public.message_reviews r
    join public.messages m on m.id = r.message_id
    where r.circle_id = target_circle_id
      and r.state in ('held', 'flagged')
      and m.recalled_at is null
      and public.can_current_user_moderate_messages(r.conversation_id)
    limit 99
  ) waiting;

  select count(*)::integer
  into reports
  from (
    select 1
    from public.message_reports r
    where r.circle_id = target_circle_id
      and r.status = 'open'
      and r.reported_user_id is distinct from auth.uid()
      and public.current_user_has_circle_permission(r.circle_id, 'manage_messages')
    limit 99
  ) waiting;

  return least(reviews + reports, 99);
end;
$$;

-- ---------------------------------------------------------------------------
-- Retention
-- ---------------------------------------------------------------------------

-- Clears the copies of messages from reports handled more than 90 days ago.
-- The report itself (reason, outcome) stays.
create or replace function public.purge_old_message_report_data()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  cleared integer;
begin
  update public.message_reports r
  set snapshot = null,
      context = null
  where r.handled_at < now() - interval '90 days'
    and (r.snapshot is not null or r.context is not null);
  get diagnostics cleared = row_count;
  return cleared;
end;
$$;

revoke execute on function public.purge_old_message_report_data()
  from public, anon, authenticated;

-- Same as 202610190030_client_errors, plus the message report copies. This is
-- the job pg_cron runs once a day ('client-errors-purge').
create or replace function public.purge_old_client_errors()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  removed integer;
begin
  delete from public.client_errors
  where created_at < now() - interval '30 days';
  get diagnostics removed = row_count;
  delete from public.client_error_rate
  where window_start < now() - interval '1 day';
  perform public.purge_old_message_report_data();
  return removed;
end;
$$;

revoke execute on function public.purge_old_client_errors()
  from public, anon, authenticated;
