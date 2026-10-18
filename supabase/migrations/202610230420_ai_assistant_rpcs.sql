-- The @WeCord AI assistant, part 3 of 3: what the `ai` function does with a
-- queued job. Every function here is for the service role only; the `ai`
-- function calls them after the database woke it (202610230410).
--
-- * ai_assistant_claim(job): takes a queued job (or one whose worker went
--   quiet for 90 seconds, at most three tries) and checks, in the database, all
--   the reasons not to answer. When there is one the job is closed as
--   'skipped' with that reason and nothing is sent to the AI:
--     message_gone  the message was recalled, expired or is under review
--     stale         the message is more than six hours old
--     not_member    the requester left the chat
--     circle_off    the circle turned AI features off (circles.ai_enabled)
--     group_off     the group owner turned WeCord AI off
--     user_off      the requester turned AI off in Settings (user_ai_settings)
--   The daily limit is counted by the function (ai_consume_request) next.
-- * ai_assistant_context(job): what the model may read, as the REQUESTER sees
--   it, never more: the asking message, the message it replies to, and the
--   last 0, 20 or 100 messages before it (the range the requester chose).
--   The requester must still be able to read the conversation; recalled,
--   expired and AI-guard-held messages are never included (even for a
--   moderator, who could see held ones); view-once pictures are left empty;
--   attachments reduce to a file name. It also lists the conversation's
--   members (id and names), which the model's to-do assignees are limited to.
-- * ai_assistant_reply(job, body, kind, items): posts the answer as the
--   assistant, as a reply to the asking message, marks it with messages.ai_reply
--   and closes the job as done. The message goes through the same insert
--   triggers as any message (AutoMod of the circle included); the assistant
--   being a bot, the AI guard never holds it.
-- * ai_assistant_finish(job, status, reason): closes a running job as
--   'skipped', 'failed' or 'limited'.
-- * ai_assistant_requester_zone(job): the requester's time zone for dates.

create or replace function public.ai_assistant_close(
  target_job_id uuid,
  new_status text,
  new_reason text
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.ai_jobs
  set status = new_status, reason = new_reason, finished_at = now()
  where id = target_job_id and status in ('queued', 'running');
$$;

revoke execute on function public.ai_assistant_close(uuid, text, text)
  from public, anon, authenticated;

create or replace function public.ai_assistant_claim(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  j public.ai_jobs%rowtype;
  m public.messages%rowtype;
  why text;
  requester_name text;
begin
  update public.ai_jobs
  set status = 'running', started_at = now(), attempts = attempts + 1
  where id = p_job_id
    and (
      status = 'queued'
      or (status = 'running' and started_at < now() - interval '90 seconds' and attempts < 3)
    )
  returning * into j;

  if j.id is null then
    return null;
  end if;

  select * into m from public.messages where id = j.message_id;

  why := case
    when m.id is null
      or m.recalled_at is not null
      or m.review_state is not null
      or (m.expires_at is not null and m.expires_at <= now())
      then 'message_gone'
    when m.created_at < now() - interval '6 hours'
      then 'stale'
    when not exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = j.conversation_id and cm.user_id = j.requester_id
    ) then 'not_member'
    when not coalesce((
      select c.ai_enabled
      from public.circle_channels cc
      join public.circles c on c.id = cc.circle_id
      where cc.conversation_id = coalesce(
        (select ct.parent_conversation_id
         from public.conversation_threads ct
         where ct.conversation_id = j.conversation_id),
        j.conversation_id
      )
      limit 1
    ), true) then 'circle_off'
    when not public.conversation_ai_assistant_allowed(j.conversation_id)
      then 'group_off'
    when exists (
      select 1
      from public.user_ai_settings s
      where s.user_id = j.requester_id and s.ai_enabled = false
    ) then 'user_off'
    else null
  end;

  if why is not null then
    perform public.ai_assistant_close(j.id, 'skipped', why);
    return jsonb_build_object('skipped', why);
  end if;

  select coalesce(nullif(btrim(p.display_name), ''), p.username, 'Someone')
  into requester_name
  from public.profiles p
  where p.id = j.requester_id;

  return jsonb_build_object(
    'job_id', j.id,
    'requester_id', j.requester_id,
    'requester_name', coalesce(requester_name, 'Someone'),
    'conversation_id', j.conversation_id,
    'message_id', j.message_id,
    'body', m.body,
    'reply_to_message_id', m.reply_to_message_id,
    'context_count', j.context_count,
    'time_zone', public.notification_time_zone(j.requester_id)
  );
end;
$$;

create or replace function public.ai_assistant_context(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  j public.ai_jobs%rowtype;
  trig public.messages%rowtype;
  replied jsonb := null;
  recent jsonb := '[]'::jsonb;
  members jsonb;
begin
  select * into j from public.ai_jobs where id = p_job_id and status = 'running';
  if j.id is null then
    return null;
  end if;

  -- From here on the visibility functions see the requester.
  perform set_config('request.jwt.claim.sub', j.requester_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', j.requester_id, 'role', 'authenticated')::text,
    true
  );

  if not exists (
    select 1
    from public.current_user_readable_conversation_ids() r(id)
    where r.id = j.conversation_id
  ) then
    return null;
  end if;

  select * into trig
  from public.messages m
  where m.id = j.message_id and m.conversation_id = j.conversation_id;
  if trig.id is null then
    return null;
  end if;

  if trig.reply_to_message_id is not null then
    select jsonb_build_object(
      'id', m.id,
      'sender_id', m.sender_id,
      'sender', coalesce(nullif(btrim(p.display_name), ''), p.username, 'Someone'),
      'type', m.type,
      'body', case when m.attachment->>'view_once' = 'true' then '' else coalesce(m.body, '') end,
      'attachment', case when m.attachment ? 'name'
        then jsonb_build_object('name', m.attachment->>'name') end,
      'webhook_name', m.webhook_name,
      'created_at', m.created_at
    )
    into replied
    from public.messages m
    join public.profiles p on p.id = m.sender_id
    where m.id = trig.reply_to_message_id
      and m.conversation_id = j.conversation_id
      and m.recalled_at is null
      and m.review_state is null
      and (m.expires_at is null or m.expires_at > now());
  end if;

  if j.context_count > 0 then
    select coalesce(jsonb_agg(q.item order by q.created_at, q.id), '[]'::jsonb)
    into recent
    from (
      select
        m.id,
        m.created_at,
        jsonb_build_object(
          'id', m.id,
          'sender_id', m.sender_id,
          'sender', coalesce(nullif(btrim(p.display_name), ''), p.username, 'Someone'),
          'type', m.type,
          'body', case when m.attachment->>'view_once' = 'true' then '' else coalesce(m.body, '') end,
          'attachment', case when m.attachment ? 'name'
            then jsonb_build_object('name', m.attachment->>'name') end,
          'webhook_name', m.webhook_name,
          'created_at', m.created_at
        ) as item
      from public.messages m
      join public.profiles p on p.id = m.sender_id
      where m.conversation_id = j.conversation_id
        and m.id <> trig.id
        and (m.created_at, m.id) < (trig.created_at, trig.id)
        and m.recalled_at is null
        and m.review_state is null
        and (m.expires_at is null or m.expires_at > now())
      order by m.created_at desc, m.id desc
      limit j.context_count
    ) q;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', cm.user_id,
    'name', coalesce(nullif(btrim(p.display_name), ''), p.username, 'Someone'),
    'username', p.username
  ) order by cm.joined_at), '[]'::jsonb)
  into members
  from (
    select x.user_id, x.joined_at
    from public.conversation_members x
    where x.conversation_id = j.conversation_id
    order by x.joined_at
    limit 200
  ) cm
  join public.profiles p on p.id = cm.user_id
  where not p.is_bot;

  return jsonb_build_object(
    'trigger', jsonb_build_object(
      'id', trig.id,
      'sender', (
        select coalesce(nullif(btrim(p.display_name), ''), p.username, 'Someone')
        from public.profiles p where p.id = trig.sender_id
      ),
      'body', coalesce(trig.body, '')
    ),
    'replied', replied,
    'recent', recent,
    'members', members
  );
end;
$$;

create or replace function public.ai_assistant_reply(
  p_job_id uuid,
  p_body text,
  p_kind text,
  p_items jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  j public.ai_jobs%rowtype;
  trig public.messages%rowtype;
  assistant uuid := public.ai_assistant_user_id();
  requester_name text;
  trimmed text := btrim(coalesce(p_body, ''));
  reply_id uuid;
begin
  select * into j from public.ai_jobs where id = p_job_id and status = 'running';
  if j.id is null then
    return null;
  end if;
  if assistant is null then
    raise exception 'The assistant account does not exist yet' using errcode = '22023';
  end if;
  if p_kind is null or p_kind not in ('answer', 'summary', 'translation', 'rewrite', 'todos') then
    raise exception 'Unknown kind of answer' using errcode = '22023';
  end if;
  if char_length(trimmed) not between 1 and 4000 then
    raise exception 'The answer must be 1 to 4000 characters' using errcode = '22023';
  end if;
  if p_items is not null and (
    jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 20
  ) then
    raise exception 'Items must be a list of up to 20' using errcode = '22023';
  end if;

  select * into trig from public.messages where id = j.message_id;
  if trig.id is null or trig.recalled_at is not null then
    perform public.ai_assistant_close(j.id, 'skipped', 'message_gone');
    return null;
  end if;

  select coalesce(nullif(btrim(p.display_name), ''), p.username, 'Someone')
  into requester_name
  from public.profiles p where p.id = j.requester_id;

  insert into public.messages (
    conversation_id, sender_id, type, body, reply_to_message_id, reply_preview, ai_reply
  )
  values (
    j.conversation_id,
    assistant,
    'text',
    trimmed,
    trig.id,
    jsonb_build_object(
      'message_id', trig.id,
      'sender_name', coalesce(requester_name, 'Someone'),
      'body', left(coalesce(trig.body, ''), 200),
      'type', trig.type
    ),
    jsonb_strip_nulls(jsonb_build_object(
      'requester_id', j.requester_id,
      'requester_name', coalesce(requester_name, 'Someone'),
      'kind', p_kind,
      'items', case when p_kind = 'todos' then p_items end
    ))
  )
  returning id into reply_id;

  update public.ai_jobs
  set status = 'done', reply_message_id = reply_id, finished_at = now()
  where id = j.id;
  return reply_id;
end;
$$;

create or replace function public.ai_assistant_finish(
  p_job_id uuid,
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
  update public.ai_jobs
  set status = p_status, reason = left(p_reason, 40), finished_at = now()
  where id = p_job_id and status = 'running';
end;
$$;

revoke execute on function public.ai_assistant_claim(uuid) from public, anon, authenticated;
revoke execute on function public.ai_assistant_context(uuid) from public, anon, authenticated;
revoke execute on function public.ai_assistant_reply(uuid, text, text, jsonb) from public, anon, authenticated;
revoke execute on function public.ai_assistant_finish(uuid, text, text) from public, anon, authenticated;
grant execute on function public.ai_assistant_claim(uuid) to service_role;
grant execute on function public.ai_assistant_context(uuid) to service_role;
grant execute on function public.ai_assistant_reply(uuid, text, text, jsonb) to service_role;
grant execute on function public.ai_assistant_finish(uuid, text, text) to service_role;
