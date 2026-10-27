-- Workflow automation (roadmap D9), part 4 of 5: doing the work.
--
-- * run_workflow_tick(): the one call of the job. In this order it
--     1. queues the schedule workflows that are due (a run that is more than
--        two hours late is logged as "missed" instead of running late), and
--        sets their next time with recurrence_next (D4);
--     2. runs up to 40 queued runs, oldest first (workflow_execute);
--     3. once an hour trims the log (30 days) and the push queue;
--     4. wakes scheduled-dispatch when messages wait for their push.
-- * workflow_execute(run): checks, then does the actions one by one AS THE
--   CREATOR (the request.jwt.claims of the transaction say so while it runs
--   and are put back after), so every rule the creator is under applies:
--       - a run is skipped when the workflow was paused, the circle is
--         suspended (K1), or the run waited more than a day;
--       - the creator must still be allowed to manage the scope
--         (workflow_user_can_manage), else the workflow pauses itself with
--         creator_lost_permission and the run is skipped;
--       - send_message / send_dm go through send_text_message: membership,
--         channel permissions, blocking, timeouts, slowmode, AutoMod, the AI
--         guard, locked threads and the disappearing-message timer apply. A
--         direct message needs the creator and the member to be friends
--         (get_or_create_direct_conversation) and not blocked: otherwise the
--         action is skipped, never forced;
--       - add_role goes through set_member_roles: it needs manage_roles and
--         a rank above the role, and the role must still be one a workflow
--         may give (workflow_role_grantable);
--       - create_task from a message only for a plain text message that is
--         not under review, not recalled, not in a chat with disappearing
--         messages and not in a chat with private-chat limits (G6); it goes
--         through create_task_from_message / upsert_task_item;
--       - send_form copies the form (title, questions, settings) into the
--         channel through create_form, with a new deadline if asked.
--     An action that is refused on purpose (not friends, blocked, left the
--     circle, has the role, AutoMod, G6 ...) is "skipped"; an action that
--     raises is "failed" and stops the rest. Five failed runs in a row pause
--     the workflow (failures).
-- * claim_workflow_message_pushes(): the messages a workflow sent that were
--   not pushed yet; scheduled-dispatch claims them once and asks
--   claim_push_delivery as for a scheduled message.
-- * A job of its own, wecord-workflows-tick, every minute. run_later_dispatch
--   is not touched.

-- ------------------------------------------------------------------ helpers

-- The chat an action works in, or null.
create or replace function public.workflow_target_conversation(
  w public.workflows,
  a jsonb,
  r public.workflow_runs
)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  wanted uuid;
  home uuid;
begin
  if w.conversation_id is not null then
    return w.conversation_id;
  end if;
  wanted := public.workflow_uuid(a -> 'channel_id');
  if wanted is not null then
    return (
      select cc.conversation_id
      from public.circle_channels cc
      where cc.id = wanted and cc.circle_id = w.circle_id
    );
  end if;
  -- "Where it happened": only for a reaction or a keyword, and only inside
  -- this circle.
  home := public.workflow_uuid(r.subject -> 'conversation_id');
  if home is not null and public.check_in_circle_of(home) = w.circle_id then
    return home;
  end if;
  return null;
end;
$$;

-- A text with {member}, {place} and {date} filled in.
create or replace function public.workflow_fill(
  template text,
  w public.workflows,
  r public.workflow_runs
)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  place text;
  zone text := coalesce(nullif(w.trigger_config ->> 'zone', ''), 'UTC');
  member text;
begin
  if w.circle_id is not null then
    select c.name into place from public.circles c where c.id = w.circle_id;
  else
    select coalesce(nullif(btrim(c.title), ''), '') into place
    from public.conversations c where c.id = w.conversation_id;
  end if;
  member := coalesce(public.workflow_user_label(w.circle_id, r.actor_id), '');
  return left(
    replace(
      replace(
        replace(template, '{place}', coalesce(place, '')),
        '{date}',
        to_char(now() at time zone zone, 'YYYY-MM-DD')
      ),
      '{member}',
      member
    ),
    2000
  );
end;
$$;

revoke execute on function public.workflow_target_conversation(public.workflows, jsonb, public.workflow_runs)
  from public, anon, authenticated;
revoke execute on function public.workflow_fill(text, public.workflows, public.workflow_runs)
  from public, anon, authenticated;

-- Puts a message a workflow sent in line for its push.
create or replace function public.workflow_queue_push(p_message_id uuid, p_sender_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.workflow_push_queue (message_id, sender_id)
  values (p_message_id, p_sender_id);
$$;

revoke execute on function public.workflow_queue_push(uuid, uuid)
  from public, anon, authenticated;

-- A person is still in the workflow's circle or group.
create or replace function public.workflow_still_member(
  w public.workflows,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when w.circle_id is not null then exists (
      select 1 from public.circle_members cm
      where cm.circle_id = w.circle_id and cm.user_id = p_user_id
    )
    else exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id = w.conversation_id and cm.user_id = p_user_id
    )
  end;
$$;

revoke execute on function public.workflow_still_member(public.workflows, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------- one action

-- Does action number [idx] of [w] for run [r], as whoever the transaction
-- says is signed in (workflow_execute made that the creator). Answers
-- {action, status: ok|skipped, detail}; a failure is raised.
create or replace function public.workflow_do_action(
  w public.workflows,
  r public.workflow_runs,
  a jsonb,
  idx integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  kind text := a ->> 'type';
  step_id uuid := md5(r.id::text || ':' || idx::text)::uuid;
  conv uuid;
  message_id uuid;
  body text;
  actor uuid := r.actor_id;
  role_id uuid;
  current_roles uuid[];
  src public.messages%rowtype;
  list_id uuid;
  form_src public.forms%rowtype;
  form_settings jsonb;
  form_title text;
  created jsonb;
  days integer;
begin
  if kind = 'send_message' then
    conv := public.workflow_target_conversation(w, a, r);
    if conv is null then
      return jsonb_build_object('action', kind, 'status', 'skipped', 'detail', 'no_channel');
    end if;
    body := public.workflow_fill(a ->> 'text', w, r);
    message_id := public.send_text_message(conv, body, null, null, '[]'::jsonb, step_id);
    if message_id is null then
      return jsonb_build_object('action', kind, 'status', 'skipped', 'detail', 'automod');
    end if;
    perform public.workflow_queue_push(message_id, uid);
    return jsonb_build_object('action', kind, 'status', 'ok');

  elsif kind = 'send_dm' then
    if actor is null or actor = uid then
      return jsonb_build_object('action', kind, 'status', 'skipped', 'detail', 'no_member');
    end if;
    if exists (
      select 1 from public.profiles p
      where p.id = actor and (p.deleted_at is not null or p.is_bot)
    ) or not public.workflow_still_member(w, actor) then
      return jsonb_build_object('action', kind, 'status', 'skipped', 'detail', 'left');
    end if;
    if public.are_users_blocked(uid, actor) then
      return jsonb_build_object('action', kind, 'status', 'skipped', 'detail', 'blocked');
    end if;
    if not exists (
      select 1 from public.friendships f
      where f.user_low_id = least(uid, actor) and f.user_high_id = greatest(uid, actor)
    ) then
      return jsonb_build_object('action', kind, 'status', 'skipped', 'detail', 'not_friends');
    end if;
    conv := public.get_or_create_direct_conversation(actor);
    body := public.workflow_fill(a ->> 'text', w, r);
    message_id := public.send_text_message(conv, body, null, null, '[]'::jsonb, step_id);
    if message_id is null then
      return jsonb_build_object('action', kind, 'status', 'skipped', 'detail', 'automod');
    end if;
    perform public.workflow_queue_push(message_id, uid);
    return jsonb_build_object('action', kind, 'status', 'ok');

  elsif kind = 'add_role' then
    role_id := public.workflow_uuid(a -> 'role_id');
    if w.circle_id is null or actor is null then
      return jsonb_build_object('action', kind, 'status', 'skipped', 'detail', 'no_member');
    end if;
    if not public.workflow_still_member(w, actor) then
      return jsonb_build_object('action', kind, 'status', 'skipped', 'detail', 'left');
    end if;
    -- The role may have been given powers since the workflow was saved.
    if not public.workflow_role_grantable(role_id, w.circle_id) then
      return jsonb_build_object('action', kind, 'status', 'skipped', 'detail', 'role_not_allowed');
    end if;
    select coalesce(array_agg(mr.role_id), array[]::uuid[]) into current_roles
    from public.circle_member_roles mr
    where mr.circle_id = w.circle_id and mr.user_id = actor;
    if role_id = any(current_roles) then
      return jsonb_build_object('action', kind, 'status', 'skipped', 'detail', 'has_role');
    end if;
    perform public.set_member_roles(w.circle_id, actor, current_roles || role_id);
    perform public.write_circle_audit(
      w.circle_id,
      'workflow_role_add',
      'member',
      actor,
      public.circle_member_label(w.circle_id, actor),
      jsonb_build_object(
        'workflow', w.name,
        'role', (select cr.name from public.circle_roles cr where cr.id = role_id)
      )
    );
    return jsonb_build_object('action', kind, 'status', 'ok');

  elsif kind = 'create_task' then
    if coalesce((a ->> 'from_message')::boolean, false) then
      select * into src
      from public.messages m
      where m.id = public.workflow_uuid(r.subject -> 'message_id');
      if src.id is null
        or src.type <> 'text'
        or src.recalled_at is not null
        or src.review_state is not null
        or src.expires_at is not null
        or src.auto_reply
      then
        return jsonb_build_object('action', kind, 'status', 'skipped', 'detail', 'message_gone');
      end if;
      -- Private chats and disappearing messages: what is said there does not
      -- leave the message (G6, disappearing messages).
      if public.conversation_restricts_sharing(src.conversation_id) then
        return jsonb_build_object('action', kind, 'status', 'skipped', 'detail', 'chat_restricted');
      end if;
      if exists (
        select 1 from public.conversations c
        where c.id = src.conversation_id and c.disappear_after_seconds is not null
      ) then
        return jsonb_build_object('action', kind, 'status', 'skipped', 'detail', 'disappearing');
      end if;
      -- The message has to be in this workflow's scope.
      if not (
        (w.conversation_id is not null and src.conversation_id = w.conversation_id)
        or (w.circle_id is not null and public.check_in_circle_of(src.conversation_id) = w.circle_id)
      ) then
        return jsonb_build_object('action', kind, 'status', 'skipped', 'detail', 'message_gone');
      end if;
      perform public.create_task_from_message(
        src.id,
        null,
        case
          when a ->> 'title' is null then null
          else left(public.workflow_fill(a ->> 'title', w, r), 300)
        end,
        step_id
      );
      return jsonb_build_object('action', kind, 'status', 'ok');
    end if;

    conv := public.workflow_target_conversation(w, a, r);
    if conv is null then
      return jsonb_build_object('action', kind, 'status', 'skipped', 'detail', 'no_channel');
    end if;
    select l.id into list_id
    from public.task_lists l
    where l.conversation_id = conv and l.deleted_at is null
    order by l.created_at, l.id
    limit 1;
    if list_id is null then
      list_id := (public.create_task_list(conv, 'Tasks', null) ->> 'id')::uuid;
    end if;
    perform public.upsert_task_item(
      list_id,
      jsonb_build_object(
        'id', step_id,
        'title', left(public.workflow_fill(a ->> 'title', w, r), 300)
      )
    );
    return jsonb_build_object('action', kind, 'status', 'ok');

  elsif kind = 'send_form' then
    conv := public.workflow_target_conversation(w, a, r);
    if conv is null then
      return jsonb_build_object('action', kind, 'status', 'skipped', 'detail', 'no_channel');
    end if;
    select * into form_src from public.forms f where f.id = public.workflow_uuid(a -> 'form_id');
    if form_src.id is null
      or not public.workflow_form_in_scope(form_src.id, w.circle_id, w.conversation_id)
    then
      return jsonb_build_object('action', kind, 'status', 'skipped', 'detail', 'form_gone');
    end if;
    form_settings := coalesce(form_src.settings, '{}'::jsonb) - 'deadline';
    if nullif(a ->> 'deadline_days', '') is not null then
      days := (a ->> 'deadline_days')::integer;
      form_settings := form_settings || jsonb_build_object(
        'deadline',
        to_char(
          (now() + make_interval(days => days)) at time zone 'utc',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
        )
      );
    end if;
    form_title := left(form_src.title, 100);
    if coalesce((a ->> 'date_in_title')::boolean, true) then
      form_title := form_title || ' · '
        || to_char(now() at time zone coalesce(nullif(w.trigger_config ->> 'zone', ''), 'UTC'), 'YYYY-MM-DD');
    end if;
    created := public.create_form(
      conv, form_title, form_src.description, form_src.fields, form_settings
    );
    perform public.workflow_queue_push((created ->> 'message_id')::uuid, uid);
    return jsonb_build_object('action', kind, 'status', 'ok');
  end if;

  return jsonb_build_object('action', coalesce(kind, ''), 'status', 'skipped', 'detail', 'unknown_action');
end;
$$;

revoke execute on function public.workflow_do_action(public.workflows, public.workflow_runs, jsonb, integer)
  from public, anon, authenticated;

-- ---------------------------------------------------------------- one run

-- Closes a run that was not carried out.
create or replace function public.workflow_finish_skipped(p_run_id uuid, p_reason text)
returns void
language sql
security definer
set search_path = public
as $$
  update public.workflow_runs
  set status = 'skipped',
      skip_reason = p_reason,
      finished_at = now()
  where id = p_run_id;
$$;

revoke execute on function public.workflow_finish_skipped(uuid, text)
  from public, anon, authenticated;

create or replace function public.workflow_execute(p_run_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.workflow_runs%rowtype;
  w public.workflows%rowtype;
  prev_sub text := current_setting('request.jwt.claim.sub', true);
  prev_claims text := current_setting('request.jwt.claims', true);
  prev_run text := current_setting('wecord.workflow_run', true);
  item jsonb;
  step jsonb;
  step_results jsonb := '[]'::jsonb;
  failure text;
  i integer := 0;
begin
  select * into r from public.workflow_runs where id = p_run_id for update skip locked;
  if r.id is null or r.status <> 'queued' then
    return;
  end if;
  select * into w from public.workflows where id = r.workflow_id;
  if w.id is null then
    return;
  end if;

  if r.created_at < now() - interval '1 day' then
    perform public.workflow_finish_skipped(r.id, 'expired');
    return;
  end if;
  if not w.enabled then
    perform public.workflow_finish_skipped(r.id, 'paused');
    return;
  end if;
  if w.circle_id is not null and public.circle_is_suspended(w.circle_id) then
    perform public.workflow_finish_skipped(r.id, 'circle_suspended');
    return;
  end if;
  if not public.workflow_user_can_manage(w.circle_id, w.conversation_id, w.created_by) then
    update public.workflows
    set enabled = false,
        paused_reason = case when created_by is null then 'creator_gone' else 'creator_lost_permission' end,
        paused_at = now(),
        next_run_at = null,
        updated_at = now()
    where id = w.id and enabled;
    perform public.workflow_finish_skipped(r.id, 'creator_lost_permission');
    return;
  end if;
  -- A form workflow dies quietly with an anonymous form.
  if w.trigger_kind = 'form_submitted' and exists (
    select 1 from public.forms f
    where f.id = public.workflow_uuid(w.trigger_config -> 'form_id')
      and coalesce((f.settings ->> 'anonymous')::boolean, false)
  ) then
    perform public.workflow_finish_skipped(r.id, 'paused');
    return;
  end if;

  update public.workflow_runs set status = 'running', started_at = now() where id = r.id;

  begin
    -- From here on the creator is the signed-in person, and a workflow's own
    -- writes start no workflow.
    perform set_config('request.jwt.claim.sub', w.created_by::text, true);
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object('sub', w.created_by, 'role', 'authenticated')::text,
      true
    );
    perform set_config('wecord.workflow_run', 'on', true);

    for item in select value from jsonb_array_elements(w.actions) loop
      begin
        step := public.workflow_do_action(w, r, item, i);
      exception when others then
        failure := left(sqlerrm, 160);
        step := jsonb_build_object(
          'action', coalesce(item ->> 'type', ''),
          'status', 'failed',
          'detail', failure
        );
      end;
      step_results := step_results || jsonb_build_array(step);
      exit when failure is not null;
      i := i + 1;
    end loop;
  exception when others then
    failure := coalesce(failure, left(sqlerrm, 160));
  end;

  perform set_config('request.jwt.claim.sub', coalesce(prev_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(prev_claims, ''), true);
  perform set_config('wecord.workflow_run', coalesce(prev_run, ''), true);

  update public.workflow_runs
  set status = case when failure is null then 'succeeded' else 'failed' end,
      results = step_results,
      error = failure,
      finished_at = now()
  where id = r.id;

  update public.workflows
  set last_run_at = now(),
      fail_streak = case when failure is null then 0 else fail_streak + 1 end,
      enabled = case when failure is not null and fail_streak + 1 >= 5 then false else enabled end,
      paused_reason = case
        when failure is not null and fail_streak + 1 >= 5 then 'failures'
        else paused_reason
      end,
      paused_at = case
        when failure is not null and fail_streak + 1 >= 5 then now()
        else paused_at
      end,
      next_run_at = case
        when failure is not null and fail_streak + 1 >= 5 then null
        else next_run_at
      end
  where id = w.id;
end;
$$;

revoke execute on function public.workflow_execute(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- the tick

create or replace function public.run_workflow_tick(max_runs integer default 40)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  w public.workflows%rowtype;
  r record;
  next_at timestamptz;
  config jsonb;
  done integer := 0;
begin
  -- 1. Schedules that are due.
  for w in
    select * from public.workflows x
    where x.enabled and x.trigger_kind = 'schedule' and x.next_run_at <= now()
    order by x.next_run_at
    limit 50
    for update skip locked
  loop
    config := w.trigger_config;
    if now() - w.next_run_at <= interval '2 hours' then
      perform public.workflow_enqueue(
        w.id,
        'sched:' || extract(epoch from w.next_run_at)::bigint::text,
        null,
        '{}'::jsonb
      );
    else
      insert into public.workflow_runs (workflow_id, event_key, status, skip_reason, finished_at)
      values (
        w.id,
        'sched:' || extract(epoch from w.next_run_at)::bigint::text,
        'skipped',
        'missed',
        now()
      )
      on conflict (workflow_id, event_key) do nothing;
    end if;

    next_at := public.recurrence_next(
      config ->> 'recurrence',
      nullif(config ->> 'day', '')::integer,
      (config ->> 'time')::time,
      config ->> 'zone',
      now(),
      nullif(config ->> 'until', '')::date
    );
    if next_at is null then
      update public.workflows
      set enabled = false, paused_reason = 'finished', paused_at = now(),
          next_run_at = null, updated_at = now()
      where id = w.id;
    else
      update public.workflows set next_run_at = next_at where id = w.id;
    end if;
  end loop;

  -- 2. Queued runs, oldest first.
  for r in
    select q.id from public.workflow_runs q
    where q.status = 'queued'
    order by q.created_at
    limit greatest(coalesce(max_runs, 40), 1)
    for update skip locked
  loop
    perform public.workflow_execute(r.id);
    done := done + 1;
  end loop;

  -- 3. Housekeeping, once an hour.
  if extract(minute from now())::integer = 7 then
    delete from public.workflow_runs
    where created_at < now() - interval '30 days' and status <> 'queued';
    delete from public.workflow_push_queue
    where created_at < now() - interval '1 day';
  end if;

  -- 4. Messages waiting for their push.
  if exists (
    select 1 from public.workflow_push_queue q
    where q.claimed_at is null and q.created_at > now() - interval '15 minutes'
  ) then
    perform public.wake_scheduled_dispatch();
  end if;

  return done;
end;
$$;

revoke execute on function public.run_workflow_tick(integer) from public, anon, authenticated;
grant execute on function public.run_workflow_tick(integer) to service_role;

-- --------------------------------------------------------------- the push

create or replace function public.claim_workflow_message_pushes()
returns table (message_id uuid, sender_id uuid)
language sql
security definer
set search_path = public
as $$
  update public.workflow_push_queue q
  set claimed_at = now()
  where q.claimed_at is null
    and q.created_at > now() - interval '15 minutes'
  returning q.message_id, q.sender_id;
$$;

revoke execute on function public.claim_workflow_message_pushes()
  from public, anon, authenticated;
grant execute on function public.claim_workflow_message_pushes() to service_role;

-- ---------------------------------------------------------------- the job

create or replace function public.install_workflows_schedule()
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return 'pg_cron is not enabled';
  end if;
  perform cron.unschedule(jobid)
  from cron.job
  where jobname = 'wecord-workflows-tick';
  perform cron.schedule(
    'wecord-workflows-tick',
    '* * * * *',
    'select public.run_workflow_tick()'
  );
  return 'scheduled';
end;
$$;

revoke execute on function public.install_workflows_schedule()
  from public, anon, authenticated;
grant execute on function public.install_workflows_schedule() to service_role;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    begin
      create extension if not exists pg_cron;
    exception when others then
      raise notice 'Could not enable pg_cron: %', sqlerrm;
    end;
  end if;
  perform public.install_workflows_schedule();
exception when others then
  raise notice 'Could not schedule the workflows job: %', sqlerrm;
end;
$$;
