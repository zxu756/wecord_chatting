-- Screenshot alerts for view-once photos and videos (roadmap G7).
--
-- WHAT THIS IS, AND IS NOT. An iPhone tells an app when the person took a
-- screenshot (UIApplication.userDidTakeScreenshotNotification) and whether the
-- screen is being recorded or mirrored (UIScreen.isCaptured). The app reports
-- those while a view-once photo or video is open. That is all there is:
--
--   * it is an alert after the fact, not a lock: the screenshot already exists;
--   * it is the other person's phone telling us, so it can be skipped (an old
--     app, another device that takes the picture, a camera pointed at the
--     screen) or made up (a changed app). Nobody should treat it as proof;
--   * a Mac or a browser has no way to tell, so nothing is ever reported from
--     there. The app says so instead of showing a "protected" badge.
--
-- report_view_once_screenshot(message, event) records one report and writes a
-- system line into the chat so that both sides see it:
--
--   event 'screenshot'  "Ada took a screenshot of a view-once photo."
--   event 'recording'   "Ada's screen was being recorded while a view-once
--                        photo was open."
--
-- Rules:
--   * the caller opened that very message (message_view_once_opens) in the
--     last 30 minutes, did not send it, still belongs to the chat and is not
--     blocked in it;
--   * one report per person, message and event: the same person screenshotting
--     the same photo ten times says it once (the row stays the first time);
--   * the sender reads every report about their messages, everyone else only
--     their own; nobody writes the table directly.
--
-- The line is a system line (type 'system', kind 'screenshot'): it pushes
-- nobody, counts as no unread message and never expires, like the other
-- chat notices.

create table if not exists public.message_view_once_screenshots (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  event text not null check (event in ('screenshot', 'recording')),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, event)
);

create index if not exists message_view_once_screenshots_user_idx
  on public.message_view_once_screenshots (user_id, created_at desc);

alter table public.message_view_once_screenshots enable row level security;
revoke all on public.message_view_once_screenshots from anon, authenticated;
grant select on public.message_view_once_screenshots to authenticated;

drop policy if exists message_view_once_screenshots_select
  on public.message_view_once_screenshots;
create policy message_view_once_screenshots_select
  on public.message_view_once_screenshots for select
  to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.messages m
      where m.id = message_view_once_screenshots.message_id
        and m.sender_id = auth.uid()
    )
  );

-- Realtime matches DELETE events against the old row.
alter table public.message_view_once_screenshots replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message_view_once_screenshots'
  ) then
    alter publication supabase_realtime add table public.message_view_once_screenshots;
  end if;
end $$;

-- Records the report and tells the chat. Returns true when this report is
-- new (and the chat was told), false when the same report already existed.
create or replace function public.report_view_once_screenshot(
  target_message_id uuid,
  event_kind text default 'screenshot'
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target public.messages%rowtype;
  inserted integer;
  actor_name text;
  media text;
  line text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if event_kind is null or event_kind not in ('screenshot', 'recording') then
    raise exception 'Unknown report' using errcode = '22023';
  end if;

  select m.*
  into target
  from public.messages m
  where m.id = target_message_id
    and m.attachment->>'view_once' = 'true';

  if target.id is null
    or not public.is_current_user_conversation_member(target.conversation_id)
    or target.sender_id = current_user_id
    or target.recalled_at is not null
    or (target.expires_at is not null and target.expires_at <= now())
    or public.is_current_user_blocked_in_conversation(target.conversation_id)
  then
    raise exception 'view_once_unavailable' using errcode = '42501';
  end if;

  -- Only someone who opened it and still has it open can have taken a
  -- screenshot of it.
  if not exists (
    select 1
    from public.message_view_once_opens o
    where o.message_id = target.id
      and o.user_id = current_user_id
      and o.opened_at > now() - interval '30 minutes'
  ) then
    raise exception 'view_once_not_open' using errcode = '42501';
  end if;

  insert into public.message_view_once_screenshots (
    message_id, user_id, conversation_id, event
  )
  values (target.id, current_user_id, target.conversation_id, event_kind)
  on conflict do nothing;
  get diagnostics inserted = row_count;

  if inserted = 0 then
    return false;
  end if;

  select nullif(btrim(p.display_name), '')
  into actor_name
  from public.profiles p
  where p.id = current_user_id;

  media := case when target.type = 'image' then 'photo' else 'video' end;
  line := coalesce(actor_name, 'Someone') || case
    when event_kind = 'recording' and media = 'photo'
      then ' was recording the screen while a view-once photo was open.'
    when event_kind = 'recording'
      then ' was recording the screen while a view-once video was open.'
    when media = 'photo'
      then ' took a screenshot of a view-once photo.'
    else ' took a screenshot of a view-once video.'
  end;

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    attachment
  )
  values (
    target.conversation_id,
    current_user_id,
    'system',
    line,
    jsonb_build_object(
      'kind', 'screenshot',
      'event', event_kind,
      'media', media,
      'message_id', target.id,
      'actor_id', current_user_id,
      'actor_name', coalesce(actor_name, 'Someone')
    )
  );

  return true;
end;
$$;

revoke execute on function public.report_view_once_screenshot(uuid, text)
  from public, anon;
grant execute on function public.report_view_once_screenshot(uuid, text)
  to authenticated;
