-- Daily digest (F3), part 3 of 5: the schedule and what the `ai` function does
-- with a digest. Everything here is for the service role only.
--
-- When (ai_digest_tick, every minute from pg_cron, like the assistant's
-- sweep 202610230410; run_later_dispatch is left alone):
--   * for each person with the digest on and at least one chat followed, it
--     reads the clock in THEIR zone (notification_time_zone, 202610210310:
--     what their devices reported, else UTC) and starts a digest when that
--     clock reaches their delivery time and today's (their date) has not run.
--     A person who missed it by more than six hours (an outage) waits for
--     tomorrow; there is no catch-up burst. Daylight saving needs no special
--     case because the clock is the zone's wall clock.
--   * the window is everything since the person's last digest, at most 24
--     hours.
--   * NO NEWS, NO MODEL: before anything is queued the database counts the
--     messages the person may see in the window (ai_digest_messages). When
--     there are none the day is recorded as skipped / no_news and the `ai`
--     function is never woken, so nothing is asked of the AI and nothing is
--     counted against the daily limit. The claim checks again.
--   * it wakes the `ai` function through pg_net (ai_guard_wake, the way the
--     AI guard and the assistant are woken), re-wakes lost wake-ups up to
--     three times, fails runs that never came back, and removes digests older
--     than two weeks.
--
-- What the model may read (ai_digest_messages, the one place that decides):
-- the messages of the chats the person follows, as THEY see them:
--   * only chats they still belong to and may read (a circle channel they lost
--     view permission on, or a suspended circle, is out), groups and circle
--     channels only;
--   * not where the circle or the group owner turned AI off
--     (conversation_ai_assistant_allowed), and nothing at all when the person
--     turned AI off (ai_digest_claim);
--   * never recalled or expired messages, never messages waiting for or
--     removed by the AI guard or an edit review (review_state), never
--     view-once pictures, never notices, never the person's own messages,
--     never a sender they blocked or who blocked them, never the assistant's
--     own replies, nothing without something to say (no text, file or poll).
-- It uses current_user_readable_conversation_ids() as the requester, by
-- setting the transaction's JWT claims to them, the way
-- ai_assistant_context does (202610230420).

-- The messages a person's digest may cover. Volatile: it sets the claims.
create or replace function public.ai_digest_messages(
  p_user_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns table (
  conversation_id uuid,
  message_id uuid,
  sender_name text,
  type text,
  body text,
  attachment_name text,
  webhook_name text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  perform set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', p_user_id, 'role', 'authenticated')::text,
    true
  );

  return query
  with followed as (
    select s.conversation_id
    from public.ai_digest_subscriptions s
    join public.conversations c
      on c.id = s.conversation_id and c.type in ('group', 'channel')
    where s.user_id = p_user_id
      and exists (
        select 1
        from public.conversation_members cm
        where cm.conversation_id = s.conversation_id
          and cm.user_id = p_user_id
      )
      and s.conversation_id in (
        select r.id from public.current_user_readable_conversation_ids() r(id)
      )
      and public.conversation_ai_assistant_allowed(s.conversation_id)
  )
  select
    m.conversation_id,
    m.id,
    coalesce(nullif(btrim(p.display_name), ''), p.username, 'Someone'),
    m.type,
    coalesce(m.body, ''),
    m.attachment->>'name',
    m.webhook_name,
    m.created_at
  from public.messages m
  join followed f on f.conversation_id = m.conversation_id
  join public.profiles p on p.id = m.sender_id
  where m.created_at > p_from
    and m.created_at <= p_to
    and m.sender_id <> p_user_id
    and m.recalled_at is null
    and m.review_state is null
    and (m.expires_at is null or m.expires_at > now())
    and coalesce(m.attachment->>'view_once', '') <> 'true'
    and m.type <> 'system'
    and m.ai_reply is null
    and not public.are_users_blocked(m.sender_id, p_user_id)
    and (
      nullif(btrim(coalesce(m.body, '')), '') is not null
      or m.type in ('file', 'poll')
    );
end;
$$;

create or replace function public.ai_digest_news_count(
  p_user_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns integer
language sql
volatile
security definer
set search_path = public
as $$
  select count(*)::integer from public.ai_digest_messages(p_user_id, p_from, p_to);
$$;

-- ----------------------------------------------------------------- the tick

create or replace function public.ai_digest_tick()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  stale record;
  zone text;
  local_now timestamp;
  due timestamp;
  since timestamptz;
  news integer;
  new_id uuid;
  started integer := 0;
  prev_sub text := current_setting('request.jwt.claim.sub', true);
  prev_claims text := current_setting('request.jwt.claims', true);
begin
  -- A subscription whose owner is no longer a member goes away.
  delete from public.ai_digest_subscriptions s
  where not exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id = s.conversation_id and cm.user_id = s.user_id
  );

  for r in
    select st.user_id, st.deliver_at, st.language
    from public.ai_digest_settings st
    where st.enabled
      and exists (
        select 1 from public.ai_digest_subscriptions s where s.user_id = st.user_id
      )
    order by st.user_id
  loop
    zone := coalesce(public.notification_time_zone(r.user_id), 'UTC');
    begin
      local_now := now() at time zone zone;
    exception when others then
      local_now := now() at time zone 'UTC';
    end;
    due := local_now::date + r.deliver_at;

    continue when local_now < due or local_now >= due + interval '6 hours';
    continue when exists (
      select 1
      from public.ai_digests d
      where d.user_id = r.user_id and d.local_date = local_now::date
    );

    since := greatest(
      coalesce(
        (
          select max(d.window_end)
          from public.ai_digests d
          where d.user_id = r.user_id and d.status in ('done', 'skipped')
        ),
        now() - interval '24 hours'
      ),
      now() - interval '24 hours'
    );
    news := public.ai_digest_news_count(r.user_id, since, now());

    new_id := null;
    insert into public.ai_digests (
      user_id, local_date, window_start, window_end, language,
      status, reason, finished_at
    )
    values (
      r.user_id, local_now::date, since, now(), r.language,
      case when news > 0 then 'queued' else 'skipped' end,
      case when news > 0 then null else 'no_news' end,
      case when news > 0 then null else now() end
    )
    on conflict (user_id, local_date) do nothing
    returning id into new_id;

    if new_id is not null and news > 0 then
      started := started + 1;
      if not public.ai_guard_wake(
        'ai',
        jsonb_build_object('action', 'digest', 'digest_id', new_id)
      ) then
        update public.ai_digests
        set status = 'failed', reason = 'unavailable', finished_at = now()
        where id = new_id;
      end if;
    end if;
  end loop;

  -- Wake-ups that got lost.
  for stale in
    select d.id, d.wake_count
    from public.ai_digests d
    where d.status = 'queued'
      and d.woken_at < now() - interval '45 seconds'
    order by d.woken_at
    limit 100
  loop
    if stale.wake_count >= 3 then
      update public.ai_digests
      set status = 'failed', reason = 'timeout', finished_at = now()
      where id = stale.id and status = 'queued';
    else
      update public.ai_digests
      set wake_count = wake_count + 1, woken_at = now()
      where id = stale.id and status = 'queued';
      perform public.ai_guard_wake(
        'ai',
        jsonb_build_object('action', 'digest', 'digest_id', stale.id)
      );
    end if;
  end loop;

  -- Answers that never came back.
  update public.ai_digests
  set status = 'failed', reason = 'timeout', finished_at = now()
  where status = 'running'
    and started_at < now() - interval '4 minutes';

  delete from public.ai_digests
  where coalesce(finished_at, created_at) < now() - interval '14 days'
    and status <> 'queued'
    and status <> 'running';

  -- The visibility check above borrowed the claims of the people it served.
  perform set_config('request.jwt.claim.sub', coalesce(prev_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(prev_claims, ''), true);
  return started;
end;
$$;

-- ------------------------------------------------------------ for `ai`

-- Takes a queued digest (or one whose worker went quiet for 90 seconds, at
-- most three tries) and checks again every reason not to write it. When
-- there is one the digest is closed as 'skipped' with it and nothing is sent
-- to the model.
create or replace function public.ai_digest_claim(p_digest_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  d public.ai_digests%rowtype;
  why text;
begin
  update public.ai_digests
  set status = 'running', started_at = now(), attempts = attempts + 1
  where id = p_digest_id
    and (
      status = 'queued'
      or (status = 'running' and started_at < now() - interval '90 seconds' and attempts < 3)
    )
  returning * into d;

  if d.id is null then
    return null;
  end if;

  why := case
    when not coalesce(
      (select s.enabled from public.ai_digest_settings s where s.user_id = d.user_id),
      false
    ) then 'off'
    when exists (
      select 1
      from public.user_ai_settings s
      where s.user_id = d.user_id and s.ai_enabled = false
    ) then 'user_off'
    when not exists (
      select 1 from public.ai_digest_subscriptions s where s.user_id = d.user_id
    ) then 'no_subscriptions'
    when public.ai_digest_news_count(d.user_id, d.window_start, d.window_end) = 0
      then 'no_news'
    else null
  end;

  if why is not null then
    update public.ai_digests
    set status = 'skipped', reason = why, finished_at = now()
    where id = d.id;
    return jsonb_build_object('skipped', why);
  end if;

  return jsonb_build_object(
    'digest_id', d.id,
    'user_id', d.user_id,
    'language', d.language,
    'time_zone', public.notification_time_zone(d.user_id),
    'window_end', d.window_end
  );
end;
$$;

-- What the model may read for a running digest: the visible messages of each
-- followed chat (the latest 200 of each), oldest first, with how many there
-- were in all.
create or replace function public.ai_digest_context(p_digest_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  d public.ai_digests%rowtype;
  result jsonb;
begin
  select * into d from public.ai_digests where id = p_digest_id and status = 'running';
  if d.id is null then
    return null;
  end if;

  with msgs as (
    select * from public.ai_digest_messages(d.user_id, d.window_start, d.window_end)
  ),
  ranked as (
    select
      m.*,
      row_number() over (
        partition by m.conversation_id order by m.created_at desc, m.message_id desc
      ) as rn,
      count(*) over (partition by m.conversation_id) as total
    from msgs m
  ),
  per_chat as (
    select
      r.conversation_id,
      max(r.total) as total,
      jsonb_agg(
        jsonb_build_object(
          'id', r.message_id,
          'sender', r.sender_name,
          'type', r.type,
          'body', r.body,
          'attachment', case when r.attachment_name is not null
            then jsonb_build_object('name', r.attachment_name) end,
          'webhook_name', r.webhook_name,
          'created_at', r.created_at
        )
        order by r.created_at, r.message_id
      ) as messages
    from ranked r
    where r.rn <= 200
    group by r.conversation_id
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'conversation_id', pc.conversation_id,
      'title', coalesce(cc.name, c.title),
      'circle_name', ci.name,
      'total', pc.total,
      'messages', pc.messages
    )
    order by sub.created_at, pc.conversation_id
  ), '[]'::jsonb)
  into result
  from per_chat pc
  join public.conversations c on c.id = pc.conversation_id
  join public.ai_digest_subscriptions sub
    on sub.user_id = d.user_id and sub.conversation_id = pc.conversation_id
  left join public.circle_channels cc on cc.conversation_id = pc.conversation_id
  left join public.circles ci on ci.id = cc.circle_id;

  return jsonb_build_object('conversations', result);
end;
$$;

-- Hands in the card: [{conversation_id, summary, message_count}]. Only chats
-- the person follows; at most 10; each summary 1 to 2000 characters. False
-- when nothing usable was handed in (the digest is closed as failed).
create or replace function public.ai_digest_finish(p_digest_id uuid, p_items jsonb)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  d public.ai_digests%rowtype;
  clean jsonb;
begin
  select * into d from public.ai_digests where id = p_digest_id and status = 'running';
  if d.id is null then
    return false;
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'Items must be a list' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'conversation_id', x.conversation_id,
      'summary', x.summary,
      'message_count', x.message_count
    )
    order by x.position
  ), '[]'::jsonb)
  into clean
  from (
    select
      (e.item->>'conversation_id')::uuid as conversation_id,
      btrim(e.item->>'summary') as summary,
      greatest(0, least(100000, coalesce((e.item->>'message_count')::integer, 0)))
        as message_count,
      e.position
    from jsonb_array_elements(p_items) with ordinality e(item, position)
    where e.item->>'conversation_id' ~* '^[0-9a-f-]{36}$'
      and char_length(btrim(coalesce(e.item->>'summary', ''))) between 1 and 2000
    limit 10
  ) x
  where exists (
    select 1
    from public.ai_digest_subscriptions s
    where s.user_id = d.user_id and s.conversation_id = x.conversation_id
  );

  if jsonb_array_length(clean) = 0 then
    update public.ai_digests
    set status = 'failed', reason = 'error', finished_at = now()
    where id = d.id;
    return false;
  end if;

  update public.ai_digests
  set status = 'done', items = clean, reason = null, finished_at = now()
  where id = d.id;

  -- The push "your digest is ready" goes out within seconds.
  perform public.wake_scheduled_dispatch();
  return true;
end;
$$;

-- Closes a running digest without a card.
create or replace function public.ai_digest_close(
  p_digest_id uuid,
  p_status text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_status not in ('skipped', 'failed', 'limited') then
    raise exception 'Unknown status' using errcode = '22023';
  end if;
  update public.ai_digests
  set status = p_status, reason = left(p_reason, 40), finished_at = now()
  where id = p_digest_id and status = 'running';
end;
$$;

revoke execute on function public.ai_digest_messages(uuid, timestamptz, timestamptz) from public, anon, authenticated;
revoke execute on function public.ai_digest_news_count(uuid, timestamptz, timestamptz) from public, anon, authenticated;
revoke execute on function public.ai_digest_tick() from public, anon, authenticated;
revoke execute on function public.ai_digest_claim(uuid) from public, anon, authenticated;
revoke execute on function public.ai_digest_context(uuid) from public, anon, authenticated;
revoke execute on function public.ai_digest_finish(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.ai_digest_close(uuid, text, text) from public, anon, authenticated;
grant execute on function public.ai_digest_messages(uuid, timestamptz, timestamptz) to service_role;
grant execute on function public.ai_digest_news_count(uuid, timestamptz, timestamptz) to service_role;
grant execute on function public.ai_digest_tick() to service_role;
grant execute on function public.ai_digest_claim(uuid) to service_role;
grant execute on function public.ai_digest_context(uuid) to service_role;
grant execute on function public.ai_digest_finish(uuid, jsonb) to service_role;
grant execute on function public.ai_digest_close(uuid, text, text) to service_role;

-- ---------------------------------------------------------------- schedule

create or replace function public.install_ai_digest_schedule()
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return 'pg_cron is not enabled';
  end if;
  perform cron.schedule(
    'wecord-ai-digest-tick',
    '* * * * *',
    'select public.ai_digest_tick()'
  );
  return 'scheduled';
end;
$$;

revoke execute on function public.install_ai_digest_schedule() from public, anon, authenticated;
grant execute on function public.install_ai_digest_schedule() to service_role;

do $$
begin
  raise notice 'AI digest tick: %', public.install_ai_digest_schedule();
exception when others then
  raise notice 'Could not schedule the AI digest tick: %', sqlerrm;
end;
$$;
