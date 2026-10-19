-- Official notices (K6), part 2 of 3: publishing and taking back, and the one
-- optional push.
--
-- Roles (as 202610210130): owner and moderator publish and retract; support
-- only reads the list. Every change is in the audit log.
--
-- The push is held to a few rules so it cannot become noise:
--   * a notice asks for it when it is published (send_push), once; there is
--     no way to push a notice again;
--   * at most one notice with a push in any 24 hours, whoever sends it;
--   * it goes out through the scheduled-dispatch function like the other
--     background pushes: in the language of each device, held back in a
--     person's quiet hours and for Do Not Disturb, and dropped if it is more
--     than two hours old or has been taken back before it reaches a device;
--   * it carries the title and the start of the text, nothing else, and opens
--     Notifications.
-- claim_announcement_pushes gives out the devices a batch at a time (500 by
-- default), remembering where it stopped, and wakes the dispatcher again when
-- there are more.

-- Publishes a notice for everybody. [send_push] also asks for one push.
create or replace function public.admin_publish_announcement(
  title_en text,
  title_zh text,
  body_en text,
  body_zh text,
  send_push boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  t_en text := btrim(coalesce(title_en, ''));
  t_zh text := btrim(coalesce(title_zh, ''));
  b_en text := btrim(coalesce(body_en, ''));
  b_zh text := btrim(coalesce(body_zh, ''));
  pushing boolean := coalesce(send_push, false);
begin
  perform public.admin_require(array['owner', 'moderator']);

  if t_en = '' and t_zh = '' then
    raise exception 'A notice needs a title' using errcode = '22023';
  end if;
  if char_length(t_en) > 120 or char_length(t_zh) > 120
    or char_length(b_en) > 2000 or char_length(b_zh) > 2000
  then
    raise exception 'That notice is too long' using errcode = '22023';
  end if;
  if pushing and exists (
    select 1
    from public.announcements a
    where a.push
      and a.kind = 'announcement'
      and a.retracted_at is null
      and a.published_at > now() - interval '24 hours'
  ) then
    raise exception 'A push was already sent in the last 24 hours'
      using errcode = '53400';
  end if;

  insert into public.announcements (
    kind, title_en, title_zh, body_en, body_zh, push, created_by
  )
  values ('announcement', t_en, t_zh, b_en, b_zh, pushing, auth.uid())
  returning id into new_id;

  perform public.admin_write_audit(
    'publish_announcement',
    'announcement',
    new_id,
    null,
    jsonb_build_object(
      'title', coalesce(nullif(t_en, ''), t_zh),
      'push', pushing
    )
  );

  if pushing then
    perform public.wake_scheduled_dispatch();
  end if;
  return new_id;
end;
$$;

-- Takes a notice back: it disappears from every inbox, and a push that has
-- not gone out yet is cancelled.
create or replace function public.admin_retract_announcement(target_announcement_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  found_title text;
begin
  perform public.admin_require(array['owner', 'moderator']);

  update public.announcements a
  set retracted_at = now(),
      retracted_by = auth.uid(),
      push_done_at = case
        when a.push and a.push_done_at is null then now()
        else a.push_done_at
      end
  where a.id = target_announcement_id
    and a.retracted_at is null
  returning coalesce(nullif(a.title_en, ''), a.title_zh) into found_title;
  if not found then
    raise exception 'Notice not found or already taken back'
      using errcode = 'P0002';
  end if;

  perform public.admin_write_audit(
    'retract_announcement',
    'announcement',
    target_announcement_id,
    null,
    jsonb_build_object('title', found_title)
  );
end;
$$;

-- The notices for everybody, newest first, with how many people read or
-- dismissed each.
create or replace function public.admin_list_announcements(
  page_size integer default 30,
  before_published_at timestamptz default null
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

  select coalesce(jsonb_agg(e.entry order by e.published_at desc), '[]'::jsonb)
  into result
  from (
    select
      jsonb_build_object(
        'id', a.id,
        'title_en', a.title_en,
        'title_zh', a.title_zh,
        'body_en', a.body_en,
        'body_zh', a.body_zh,
        'push', a.push,
        'push_done', a.push_done_at is not null,
        'published_at', a.published_at,
        'retracted_at', a.retracted_at,
        'read_count', (
          select count(*) from public.announcement_states s
          where s.announcement_id = a.id and s.read_at is not null
        ),
        'dismissed_count', (
          select count(*) from public.announcement_states s
          where s.announcement_id = a.id and s.dismissed_at is not null
        )
      ) as entry,
      a.published_at
    from public.announcements a
    where a.kind = 'announcement'
      and (before_published_at is null or a.published_at < before_published_at)
    order by a.published_at desc
    limit page
  ) e;

  return result;
end;
$$;

-- The next batch of devices to push the oldest waiting notice to (service
-- role only: the scheduled-dispatch function). Per device: the title and the
-- start of the text in the device's language.
create or replace function public.claim_announcement_pushes(max_rows integer default 500)
returns table (
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth text,
  conversation_id uuid,
  circle_id uuid,
  title text,
  body text,
  tag text,
  url text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  a public.announcements;
  window_ids uuid[];
  batch integer := least(greatest(coalesce(max_rows, 500), 1), 2000);
  more boolean;
begin
  -- Too old to be news, or taken back: closed without a push.
  update public.announcements x
  set push_done_at = now()
  where x.push
    and x.push_done_at is null
    and (x.retracted_at is not null or x.published_at <= now() - interval '2 hours');

  select * into a
  from public.announcements x
  where x.push
    and x.push_done_at is null
    and x.kind = 'announcement'
    and x.retracted_at is null
  order by x.published_at
  limit 1
  for update skip locked;
  if not found then
    return;
  end if;

  -- The next devices after the one the last batch ended with. Devices that
  -- are skipped below (Do Not Disturb) still count, so the cursor moves on.
  select coalesce(array_agg(w.id order by w.id), '{}'::uuid[])
  into window_ids
  from (
    select s.id
    from public.push_subscriptions s
    where s.id > coalesce(a.push_cursor, '00000000-0000-0000-0000-000000000000'::uuid)
    order by s.id
    limit batch
  ) w;

  more := cardinality(window_ids) >= batch;
  update public.announcements x
  set push_cursor = coalesce(window_ids[cardinality(window_ids)], x.push_cursor),
      push_done_at = case when more then null else now() end
  where x.id = a.id;
  if more then
    perform public.wake_scheduled_dispatch();
  end if;

  return query
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    null::uuid,
    null::uuid,
    left(txt.t, 80),
    left(txt.b, 180),
    'announcement-' || a.id::text,
    '/#/notifications'
  from public.push_subscriptions s
  left join public.user_privacy_settings ups on ups.user_id = s.user_id
  cross join lateral (
    -- No angle brackets: a title must not pass for a time token.
    select
      replace(replace(
        case when s.language = 'zh'
          then coalesce(nullif(btrim(a.title_zh), ''), btrim(a.title_en))
          else coalesce(nullif(btrim(a.title_en), ''), btrim(a.title_zh))
        end, '<', ''), '>', '') as t,
      replace(replace(
        case when s.language = 'zh'
          then coalesce(nullif(btrim(a.body_zh), ''), btrim(a.body_en))
          else coalesce(nullif(btrim(a.body_en), ''), btrim(a.body_zh))
        end, '<', ''), '>', '') as b
  ) txt
  where s.id = any (window_ids)
    and coalesce(ups.presence_status, 'online') <> 'dnd';
end;
$$;

revoke execute on function public.admin_publish_announcement(text, text, text, text, boolean)
  from public, anon;
revoke execute on function public.admin_retract_announcement(uuid) from public, anon;
revoke execute on function public.admin_list_announcements(integer, timestamptz)
  from public, anon;
revoke execute on function public.claim_announcement_pushes(integer)
  from public, anon, authenticated;
grant execute on function public.admin_publish_announcement(text, text, text, text, boolean)
  to authenticated;
grant execute on function public.admin_retract_announcement(uuid) to authenticated;
grant execute on function public.admin_list_announcements(integer, timestamptz)
  to authenticated;
grant execute on function public.claim_announcement_pushes(integer) to service_role;
