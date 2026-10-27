-- Workflow automation (roadmap D9), part 3 of 5: what starts a workflow.
--
-- Five events write a row into workflow_runs (the queue); nothing else
-- happens in the transaction of the person who caused the event:
--
--   member_joined   AFTER INSERT on circle_members (every way into a circle
--                   ends there: invite, Discover, added by a friend, an
--                   approved request) and on conversation_members of a group.
--   reaction        AFTER INSERT on message_reactions, for the emoji the
--                   workflow names, once per message.
--   keyword         AFTER INSERT on messages, for text a person wrote that
--                   contains one of the words (not case sensitive).
--   form_submitted  AFTER INSERT on form_responses of the form the workflow
--                   names (never an anonymous form).
--   schedule        run_workflow_tick (part 4) at the due time.
--
-- Rules that keep this safe:
--   * Never raises: every trigger swallows its own errors, so a problem here
--     cannot stop anyone from joining, reacting, writing or answering.
--   * No loops: an event caused while a workflow runs (the setting
--     wecord.workflow_run is on) is ignored, and what a workflow writes is
--     marked auto_reply, which the keyword trigger skips.
--   * One run per event: (workflow, event key) is unique.
--   * Limits (workflow_limits): 200 runs a day for a workflow, 1000 for a
--     circle or group, 10 a day for one member in one workflow. Beyond that
--     events are dropped, and the log gets one "daily limit" line a day.
--   * Nothing for a suspended circle (K1), a deleted account or a bot.
--   * Held messages (AI guard review) and system, bot and webhook messages
--     do not start keyword workflows.
--
-- The messages a workflow sends carry auto_reply = true (the flag of the
-- away auto-reply, 202610280310), set by messages_aa_workflow_flag while a
-- run is going on. Clients still cannot set it.

-- ---------------------------------------------------------------- the queue

create or replace function public.workflow_enqueue(
  p_workflow_id uuid,
  p_event_key text,
  p_actor_id uuid,
  p_subject jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  w public.workflows%rowtype;
  limits jsonb := public.workflow_limits();
  today_key text := 'limit:' || to_char(now() at time zone 'utc', 'YYYY-MM-DD');
begin
  -- A workflow's own actions never start another workflow.
  if current_setting('wecord.workflow_run', true) = 'on' then
    return;
  end if;

  select * into w from public.workflows where id = p_workflow_id and enabled;
  if w.id is null then
    return;
  end if;
  if w.circle_id is not null and public.circle_is_suspended(w.circle_id) then
    return;
  end if;
  if p_actor_id is not null and exists (
    select 1 from public.profiles p
    where p.id = p_actor_id and (p.deleted_at is not null or p.is_bot)
  ) then
    return;
  end if;

  if (
    select count(*)
    from public.workflow_runs r
    where r.workflow_id = w.id
      and r.created_at > now() - interval '24 hours'
      and r.skip_reason is distinct from 'daily_limit'
  ) >= (limits ->> 'max_runs_per_day')::integer
  or (
    select count(*)
    from public.workflow_runs r
    join public.workflows w2 on w2.id = r.workflow_id
    where r.created_at > now() - interval '24 hours'
      and r.skip_reason is distinct from 'daily_limit'
      and (
        (w.circle_id is not null and w2.circle_id = w.circle_id)
        or (w.conversation_id is not null and w2.conversation_id = w.conversation_id)
      )
  ) >= (limits ->> 'max_scope_runs_per_day')::integer
  then
    insert into public.workflow_runs (
      workflow_id, event_key, status, skip_reason, finished_at
    )
    values (w.id, today_key, 'skipped', 'daily_limit', now())
    on conflict (workflow_id, event_key) do nothing;
    return;
  end if;

  -- One member cannot use up a workflow's day alone.
  if p_actor_id is not null and (
    select count(*)
    from public.workflow_runs r
    where r.workflow_id = w.id
      and r.actor_id = p_actor_id
      and r.created_at > now() - interval '24 hours'
  ) >= (limits ->> 'max_member_runs_per_day')::integer
  then
    return;
  end if;

  insert into public.workflow_runs (workflow_id, event_key, actor_id, subject)
  values (w.id, left(p_event_key, 200), p_actor_id, coalesce(p_subject, '{}'::jsonb))
  on conflict (workflow_id, event_key) do nothing;
exception when others then
  -- The event that called this must not fail because a workflow could not
  -- be queued.
  null;
end;
$$;

revoke execute on function public.workflow_enqueue(uuid, text, uuid, jsonb)
  from public, anon, authenticated;

-- ------------------------------------------------------------ a circle join

create or replace function public.workflows_on_circle_join()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  w record;
begin
  if new.role = 'owner' then
    return new;
  end if;
  for w in
    select wf.id
    from public.workflows wf
    where wf.circle_id = new.circle_id
      and wf.trigger_kind = 'member_joined'
      and wf.enabled
  loop
    perform public.workflow_enqueue(
      w.id,
      'join:' || new.user_id::text || ':'
        || (extract(epoch from new.created_at) * 1000)::bigint::text,
      new.user_id,
      '{}'::jsonb
    );
  end loop;
  return new;
exception when others then
  return new;
end;
$$;

revoke execute on function public.workflows_on_circle_join()
  from public, anon, authenticated;

drop trigger if exists circle_members_workflows on public.circle_members;
create trigger circle_members_workflows
  after insert on public.circle_members
  for each row execute function public.workflows_on_circle_join();

-- ------------------------------------------------------------ a group join

create or replace function public.workflows_on_group_join()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  w record;
begin
  for w in
    select wf.id
    from public.workflows wf
    where wf.conversation_id = new.conversation_id
      and wf.trigger_kind = 'member_joined'
      and wf.enabled
  loop
    perform public.workflow_enqueue(
      w.id,
      'join:' || new.user_id::text || ':'
        || (extract(epoch from new.joined_at) * 1000)::bigint::text,
      new.user_id,
      '{}'::jsonb
    );
  end loop;
  return new;
exception when others then
  return new;
end;
$$;

revoke execute on function public.workflows_on_group_join()
  from public, anon, authenticated;

drop trigger if exists conversation_members_workflows on public.conversation_members;
create trigger conversation_members_workflows
  after insert on public.conversation_members
  for each row execute function public.workflows_on_group_join();

-- --------------------------------------------------------------- a reaction

create or replace function public.workflows_on_reaction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  w record;
  home_circle uuid;
  home_channel uuid;
begin
  if not exists (
    select 1 from public.workflows wf
    where wf.enabled and wf.trigger_kind = 'reaction'
      and wf.trigger_config ->> 'emoji' = new.emoji
  ) then
    return new;
  end if;

  home_channel := public.conversation_circle_channel_id(new.conversation_id);
  home_circle := public.check_in_circle_of(new.conversation_id);

  for w in
    select wf.id
    from public.workflows wf
    where wf.enabled
      and wf.trigger_kind = 'reaction'
      and wf.trigger_config ->> 'emoji' = new.emoji
      and (
        wf.conversation_id = new.conversation_id
        or (wf.circle_id is not null and wf.circle_id = home_circle)
      )
      and (
        wf.trigger_config ->> 'channel_id' is null
        or wf.trigger_config ->> 'channel_id' = home_channel::text
      )
  loop
    perform public.workflow_enqueue(
      w.id,
      'react:' || new.message_id::text,
      new.user_id,
      jsonb_build_object(
        'message_id', new.message_id,
        'conversation_id', new.conversation_id,
        'channel_id', home_channel
      )
    );
  end loop;
  return new;
exception when others then
  return new;
end;
$$;

revoke execute on function public.workflows_on_reaction()
  from public, anon, authenticated;

drop trigger if exists message_reactions_workflows on public.message_reactions;
create trigger message_reactions_workflows
  after insert on public.message_reactions
  for each row execute function public.workflows_on_reaction();

-- ----------------------------------------------------------------- keywords

create or replace function public.workflows_on_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  w record;
  home_circle uuid;
  home_channel uuid;
  lowered text;
begin
  -- The cheap exit: nearly every database has no keyword workflow at all.
  if not exists (
    select 1 from public.workflows wf
    where wf.enabled and wf.trigger_kind = 'keyword'
  ) then
    return new;
  end if;

  lowered := lower(new.body);
  home_channel := public.conversation_circle_channel_id(new.conversation_id);
  home_circle := public.check_in_circle_of(new.conversation_id);

  for w in
    select wf.id, wf.trigger_config
    from public.workflows wf
    where wf.enabled
      and wf.trigger_kind = 'keyword'
      and (
        wf.conversation_id = new.conversation_id
        or (wf.circle_id is not null and wf.circle_id = home_circle)
      )
      and (
        wf.trigger_config ->> 'channel_id' is null
        or wf.trigger_config ->> 'channel_id' = home_channel::text
      )
  loop
    if exists (
      select 1
      from jsonb_array_elements_text(w.trigger_config -> 'words') k(word)
      where position(k.word in lowered) > 0
    ) then
      perform public.workflow_enqueue(
        w.id,
        'kw:' || new.id::text,
        new.sender_id,
        jsonb_build_object(
          'message_id', new.id,
          'conversation_id', new.conversation_id,
          'channel_id', home_channel
        )
      );
    end if;
  end loop;
  return new;
exception when others then
  return new;
end;
$$;

revoke execute on function public.workflows_on_message()
  from public, anon, authenticated;

drop trigger if exists messages_zz_workflows on public.messages;
create trigger messages_zz_workflows
  after insert on public.messages
  for each row
  when (
    new.type = 'text'
    and not new.auto_reply
    and new.review_state is null
    and new.webhook_id is null
    and new.recalled_at is null
  )
  execute function public.workflows_on_message();

-- ------------------------------------------------------------- a form answer

create or replace function public.workflows_on_form_response()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  w record;
begin
  if exists (
    select 1 from public.forms f
    where f.id = new.form_id
      and coalesce((f.settings ->> 'anonymous')::boolean, false)
  ) then
    return new;
  end if;
  for w in
    select wf.id
    from public.workflows wf
    where wf.enabled
      and wf.trigger_kind = 'form_submitted'
      and wf.trigger_config ->> 'form_id' = new.form_id::text
  loop
    perform public.workflow_enqueue(
      w.id,
      'form:' || new.id::text,
      new.user_id,
      jsonb_build_object('form_id', new.form_id, 'response_id', new.id)
    );
  end loop;
  return new;
exception when others then
  return new;
end;
$$;

revoke execute on function public.workflows_on_form_response()
  from public, anon, authenticated;

drop trigger if exists form_responses_workflows on public.form_responses;
create trigger form_responses_workflows
  after insert on public.form_responses
  for each row execute function public.workflows_on_form_response();

-- ------------------------------------------------------ the auto-reply label

-- While a workflow runs, what it writes is marked auto_reply. Named to sort
-- before messages_guard_auto_reply (202610280310), which refuses the flag
-- from a client's own role: a workflow runs inside security definer
-- functions, as the function owner, so it passes.
create or replace function public.messages_flag_workflow()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.auto_reply := true;
  return new;
end;
$$;

revoke execute on function public.messages_flag_workflow()
  from public, anon, authenticated;

drop trigger if exists messages_aa_workflow_flag on public.messages;
create trigger messages_aa_workflow_flag
  before insert on public.messages
  for each row
  when (current_setting('wecord.workflow_run', true) = 'on')
  execute function public.messages_flag_workflow();
