-- Feedback and help (K7), part 2 of 4: what platform admins do with feedback.
--
-- All three roles read and answer (support is the role for exactly this);
-- every answer and every close is in the audit log, which names the person
-- ("@username"), not what they wrote.
--
-- A reply is an official notice (K6, 202610240620) of kind feedback_reply for
-- the one person who wrote the feedback: it shows in their Notifications as a
-- "WeCord team" card, in the language of their app, and nobody else sees it.
-- It has no push. The admin writes it once; it is stored for both languages.
-- The screenshots are read by the admin's app through a signed link, with the
-- storage policy of 202610240640 (platform admins read the bucket).

-- A page of feedback, newest first.
create or replace function public.admin_list_feedback(
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
  if status_filter is not null and status_filter not in ('open', 'closed', 'all') then
    raise exception 'Unknown status' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(e.entry order by e.created_at desc), '[]'::jsonb)
  into result
  from (
    select
      jsonb_build_object(
        'id', f.id,
        'user_id', f.user_id,
        'username', p.username,
        'display_name', p.display_name,
        'message', f.message,
        'app_version', f.app_version,
        'platform', f.platform,
        'has_screenshot', f.screenshot_path is not null,
        'status', f.status,
        'replied_at', f.replied_at,
        'created_at', f.created_at
      ) as entry,
      f.created_at
    from public.user_feedback f
    left join public.profiles p on p.id = f.user_id
    where (status_filter is null or status_filter = 'all' or f.status = status_filter)
      and (before_created_at is null or f.created_at < before_created_at)
    order by f.created_at desc
    limit page
  ) e;

  return result;
end;
$$;

-- One piece of feedback with the replies it got.
create or replace function public.admin_get_feedback(target_feedback_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  perform public.admin_require(array['owner', 'moderator', 'support']);

  select jsonb_build_object(
    'id', f.id,
    'user_id', f.user_id,
    'username', p.username,
    'display_name', p.display_name,
    'message', f.message,
    'app_version', f.app_version,
    'platform', f.platform,
    'screenshot_path', f.screenshot_path,
    'status', f.status,
    'replied_at', f.replied_at,
    'created_at', f.created_at,
    'replies', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', a.id,
          'body', coalesce(nullif(a.body_en, ''), a.body_zh),
          'published_at', a.published_at,
          'retracted_at', a.retracted_at
        )
        order by a.published_at
      )
      from public.announcements a
      where a.feedback_id = f.id
    ), '[]'::jsonb)
  )
  into result
  from public.user_feedback f
  left join public.profiles p on p.id = f.user_id
  where f.id = target_feedback_id;

  if result is null then
    raise exception 'Feedback not found' using errcode = 'P0002';
  end if;
  return result;
end;
$$;

-- Answers feedback with a notice for the person who wrote it, and closes it
-- when [close_after] says so.
create or replace function public.admin_reply_feedback(
  target_feedback_id uuid,
  reply_text text,
  close_after boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  text_clean text := btrim(coalesce(reply_text, ''));
  owner_id uuid;
  owner_name text;
  reply_id uuid;
begin
  perform public.admin_require(array['owner', 'moderator', 'support']);

  if text_clean = '' then
    raise exception 'Write a reply first' using errcode = '22023';
  end if;
  if char_length(text_clean) > 1500 then
    raise exception 'That reply is too long' using errcode = '22023';
  end if;

  select f.user_id, p.username
  into owner_id, owner_name
  from public.user_feedback f
  left join public.profiles p on p.id = f.user_id
  where f.id = target_feedback_id
  for update of f;
  if owner_id is null then
    raise exception 'Feedback not found' using errcode = 'P0002';
  end if;

  insert into public.announcements (
    kind, title_en, title_zh, body_en, body_zh,
    audience_user_id, feedback_id, created_by
  )
  values (
    'feedback_reply',
    'Reply to your feedback',
    '对你反馈的回复',
    text_clean,
    text_clean,
    owner_id,
    target_feedback_id,
    auth.uid()
  )
  returning id into reply_id;

  update public.user_feedback f
  set replied_at = now(),
      status = case when coalesce(close_after, true) then 'closed' else f.status end,
      closed_at = case
        when coalesce(close_after, true) and f.status = 'open' then now()
        else f.closed_at
      end,
      closed_by = case
        when coalesce(close_after, true) and f.status = 'open' then auth.uid()
        else f.closed_by
      end
  where f.id = target_feedback_id;

  perform public.admin_write_audit(
    'reply_feedback',
    'feedback',
    target_feedback_id,
    null,
    jsonb_build_object('title', '@' || coalesce(owner_name, ''))
  );
  return reply_id;
end;
$$;

-- Closes feedback, or opens it again.
create or replace function public.admin_close_feedback(
  target_feedback_id uuid,
  closed boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_name text;
  changed integer;
begin
  perform public.admin_require(array['owner', 'moderator', 'support']);

  update public.user_feedback f
  set status = case when coalesce(closed, true) then 'closed' else 'open' end,
      closed_at = case when coalesce(closed, true) then now() else null end,
      closed_by = case when coalesce(closed, true) then auth.uid() else null end
  where f.id = target_feedback_id
  returning (select p.username from public.profiles p where p.id = f.user_id)
  into owner_name;
  get diagnostics changed = row_count;
  if changed = 0 then
    raise exception 'Feedback not found' using errcode = 'P0002';
  end if;

  perform public.admin_write_audit(
    case when coalesce(closed, true) then 'close_feedback' else 'reopen_feedback' end,
    'feedback',
    target_feedback_id,
    null,
    jsonb_build_object('title', '@' || coalesce(owner_name, ''))
  );
end;
$$;

revoke execute on function public.admin_list_feedback(text, integer, timestamptz)
  from public, anon;
revoke execute on function public.admin_get_feedback(uuid) from public, anon;
revoke execute on function public.admin_reply_feedback(uuid, text, boolean)
  from public, anon;
revoke execute on function public.admin_close_feedback(uuid, boolean) from public, anon;
grant execute on function public.admin_list_feedback(text, integer, timestamptz)
  to authenticated;
grant execute on function public.admin_get_feedback(uuid) to authenticated;
grant execute on function public.admin_reply_feedback(uuid, text, boolean)
  to authenticated;
grant execute on function public.admin_close_feedback(uuid, boolean) to authenticated;
