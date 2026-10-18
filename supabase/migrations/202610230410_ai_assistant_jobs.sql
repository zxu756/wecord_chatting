-- The @WeCord AI assistant, part 2 of 3: noticing a mention and queueing it.
--
-- Nobody calls the assistant. A trigger on `messages` reads the text of every
-- new message, and when it @mentions the assistant it queues a row in
-- public.ai_jobs and wakes the `ai` function (action `assistant`) through
-- pg_net with the shared secret, the same way the AI guard is woken
-- (ai_guard_wake, 202610170090). So a client cannot skip, forge or repeat a
-- request, and the job exists the moment the message does.
--
-- What counts as a mention: the text "@WeCord AI" (also "@wecord_ai"), in any
-- case, as a word of its own (not inside an email address or a longer name),
-- optionally followed by a context range, "/20" or "/100":
--     @WeCord AI summarize the plan        -> this message and the one it replies to
--     @WeCord AI /20 what did we decide?   -> plus the last 20 messages
--     @WeCord AI /100 list the to-dos      -> plus the last 100 messages
-- The assistant is not a member of any chat, so a structured mention cannot
-- name it; the text is the mention. The app's "Ask WeCord AI" sheet writes
-- it for the person.
--
-- Only a message everybody can see counts:
--  * a message held by the AI guard (review_state 'checking' or 'held') is
--    ignored when it is sent, and queued if and when it is released (a
--    moderator's release or the guard's own), but not when the release
--    follows an edit and not when it is more than six hours old;
--  * recalled messages, bots, webhooks and non-text messages never queue;
--  * a message is queued once (message_id is unique), however often it is
--    released or edited;
--  * a person can queue at most 5 jobs a minute; the sixth is recorded as
--    skipped ('rate_limited') and nothing is asked of the AI.
--
-- public.ai_jobs is closed to the API except one read: the requester sees the
-- state of their own jobs (the app shows "WeCord AI is thinking" or why there
-- was no answer). Only the server writes it.
--
-- run_ai_assistant_sweep (every minute, pg_cron) wakes a job whose wake-up was
-- lost (up to three times), gives up on one that never finished, and removes
-- old finished jobs.

create table if not exists public.ai_jobs (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'assistant' check (kind in ('assistant')),
  message_id uuid not null unique references public.messages(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  requester_id uuid not null references public.profiles(id) on delete cascade,
  -- How many recent messages the requester let the assistant read besides the
  -- message itself and the one it replies to.
  context_count smallint not null default 0 check (context_count in (0, 20, 100)),
  status text not null default 'queued'
    check (status in ('queued', 'running', 'done', 'skipped', 'failed', 'limited')),
  -- Why a job was skipped, failed or limited: message_gone, stale, not_member,
  -- circle_off, group_off, user_off, rate_limited, unavailable, timeout,
  -- not_configured, provider, limit.
  reason text,
  attempts integer not null default 0,
  wake_count integer not null default 1,
  woken_at timestamptz not null default now(),
  reply_message_id uuid references public.messages(id) on delete set null,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz
);

create index if not exists ai_jobs_open_idx
  on public.ai_jobs (created_at)
  where status in ('queued', 'running');
create index if not exists ai_jobs_requester_idx
  on public.ai_jobs (requester_id, created_at desc);

alter table public.ai_jobs enable row level security;
revoke all on public.ai_jobs from anon, authenticated;
grant select (id, message_id, conversation_id, status, reason, created_at, finished_at)
  on public.ai_jobs to authenticated;

drop policy if exists ai_jobs_select_requester on public.ai_jobs;
create policy ai_jobs_select_requester
  on public.ai_jobs for select
  to authenticated
  using (requester_id = auth.uid());

-- The context range of a text that mentions the assistant: 0 (this message
-- and its reply target), 20 or 100; null when it does not mention it.
create or replace function public.ai_assistant_mention(message_body text)
returns smallint
language sql
immutable
as $$
  select case
    when m is null then null
    else coalesce(m[2]::smallint, 0::smallint)
  end
  from (
    select regexp_match(
      coalesce(message_body, ''),
      '(?:^|[^A-Za-z0-9_])@wecord[ _]?ai(?![A-Za-z0-9_])(\s+/(20|100)(?![A-Za-z0-9_]))?',
      'i'
    ) as m
  ) found;
$$;

-- Queues the assistant's answer to [message], or records why not. Internal.
create or replace function public.ai_assistant_enqueue(
  target_message_id uuid,
  target_conversation_id uuid,
  target_requester_id uuid,
  range_count smallint
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  job_id uuid;
  recent integer;
begin
  select count(*) into recent
  from public.ai_jobs j
  where j.requester_id = target_requester_id
    and j.created_at > now() - interval '1 minute';

  if recent >= 5 then
    insert into public.ai_jobs (
      message_id, conversation_id, requester_id, context_count,
      status, reason, finished_at
    )
    values (
      target_message_id, target_conversation_id, target_requester_id, range_count,
      'skipped', 'rate_limited', now()
    )
    on conflict (message_id) do nothing;
    return null;
  end if;

  insert into public.ai_jobs (
    message_id, conversation_id, requester_id, context_count
  )
  values (
    target_message_id, target_conversation_id, target_requester_id, range_count
  )
  on conflict (message_id) do nothing
  returning id into job_id;

  if job_id is null then
    return null;
  end if;

  if not public.ai_guard_wake(
    'ai',
    jsonb_build_object('action', 'assistant', 'job_id', job_id)
  ) then
    -- No pg_net or Vault secrets: nothing will ever answer this.
    update public.ai_jobs
    set status = 'failed', reason = 'unavailable', finished_at = now()
    where id = job_id;
    return null;
  end if;
  return job_id;
end;
$$;

revoke execute on function public.ai_assistant_enqueue(uuid, uuid, uuid, smallint)
  from public, anon, authenticated;

-- AFTER INSERT: a new message that mentions the assistant.
create or replace function public.messages_ai_assistant_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  range_count smallint;
begin
  if new.type <> 'text'
    or new.review_state is not null
    or new.recalled_at is not null
    or new.webhook_id is not null
    or new.webhook_name is not null
  then
    return new;
  end if;

  range_count := public.ai_assistant_mention(new.body);
  if range_count is null then
    return new;
  end if;

  if exists (select 1 from public.profiles p where p.id = new.sender_id and p.is_bot) then
    return new;
  end if;

  perform public.ai_assistant_enqueue(
    new.id, new.conversation_id, new.sender_id, range_count
  );
  return new;
end;
$$;

-- AFTER UPDATE of review_state: a message the AI guard held is released.
create or replace function public.messages_ai_assistant_release()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  range_count smallint;
begin
  if new.type <> 'text'
    or new.recalled_at is not null
    or new.webhook_id is not null
    or new.webhook_name is not null
    or new.created_at < now() - interval '6 hours'
  then
    return new;
  end if;

  range_count := public.ai_assistant_mention(new.body);
  if range_count is null then
    return new;
  end if;

  if exists (select 1 from public.profiles p where p.id = new.sender_id and p.is_bot) then
    return new;
  end if;

  -- A release that follows an edit is not a new message.
  if coalesce(
    (select r.after_edit from public.message_reviews r where r.message_id = new.id),
    false
  ) then
    return new;
  end if;

  perform public.ai_assistant_enqueue(
    new.id, new.conversation_id, new.sender_id, range_count
  );
  return new;
end;
$$;

revoke execute on function public.messages_ai_assistant_insert() from public, anon, authenticated;
revoke execute on function public.messages_ai_assistant_release() from public, anon, authenticated;

drop trigger if exists messages_ai_assistant_insert on public.messages;
create trigger messages_ai_assistant_insert
  after insert on public.messages
  for each row
  when (
    new.type = 'text'
    and new.review_state is null
    and new.body ~* '@wecord[ _]?ai'
  )
  execute function public.messages_ai_assistant_insert();

drop trigger if exists messages_ai_assistant_release on public.messages;
create trigger messages_ai_assistant_release
  after update of review_state on public.messages
  for each row
  when (
    old.review_state is not null
    and new.review_state is null
    and new.type = 'text'
    and new.body ~* '@wecord[ _]?ai'
  )
  execute function public.messages_ai_assistant_release();

-- ------------------------------------------------------------------- sweep

create or replace function public.run_ai_assistant_sweep()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  stale record;
begin
  -- Wake-ups that got lost.
  for stale in
    select j.id, j.wake_count
    from public.ai_jobs j
    where j.status = 'queued'
      and j.woken_at < now() - interval '45 seconds'
    order by j.woken_at
    limit 100
  loop
    if stale.wake_count >= 3 then
      update public.ai_jobs
      set status = 'failed', reason = 'timeout', finished_at = now()
      where id = stale.id and status = 'queued';
    else
      update public.ai_jobs
      set wake_count = wake_count + 1, woken_at = now()
      where id = stale.id and status = 'queued';
      perform public.ai_guard_wake(
        'ai',
        jsonb_build_object('action', 'assistant', 'job_id', stale.id)
      );
    end if;
  end loop;

  -- Answers that never came back.
  update public.ai_jobs
  set status = 'failed', reason = 'timeout', finished_at = now()
  where status = 'running'
    and started_at < now() - interval '3 minutes';

  delete from public.ai_jobs
  where status in ('done', 'skipped', 'failed', 'limited')
    and finished_at < now() - interval '14 days';
end;
$$;

revoke execute on function public.run_ai_assistant_sweep() from public, anon, authenticated;
grant execute on function public.run_ai_assistant_sweep() to service_role;

create or replace function public.install_ai_assistant_schedule()
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
    'wecord-ai-assistant-sweep',
    '* * * * *',
    'select public.run_ai_assistant_sweep()'
  );
  return 'scheduled';
end;
$$;

revoke execute on function public.install_ai_assistant_schedule() from public, anon, authenticated;
grant execute on function public.install_ai_assistant_schedule() to service_role;

do $$
begin
  raise notice 'AI assistant sweep: %', public.install_ai_assistant_schedule();
exception when others then
  raise notice 'Could not schedule the AI assistant sweep: %', sqlerrm;
end;
$$;
