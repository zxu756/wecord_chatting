-- Workflow automation (roadmap D9), part 2 of 5: what a manager can do.
--
-- * get_workflow_options(circle, conversation): what the editor offers in its
--   pickers: the circle's text channels, the roles a workflow may hand out
--   (workflow_role_grantable), and the forms of the scope.
-- * list_workflows(circle, conversation): {can_manage, limits, workflows}. Only
--   for people who can manage the scope (a circle's manage_circle, a group's
--   owner and admins): members do not see the automations.
-- * save_workflow(workflow): creates or changes one. The trigger and every
--   action are checked and cleaned here (unknown keys dropped, texts cleaned,
--   a channel, role or form must belong to the scope, a role must be one a
--   workflow may give, an action that needs "the member" needs a trigger
--   that has one). The person saving becomes the person the workflow runs
--   as. A circle's audit log gets workflow_create / workflow_update.
-- * set_workflow_enabled(id, enabled): pause or resume. Resuming makes the
--   caller the person it runs as and starts the failure count over; a
--   schedule starts again from now.
-- * delete_workflow(id).
-- * list_workflow_runs(id, limit, before): the run log, newest first.
--
-- Errors are short codes (workflow_name_invalid, workflow_limit_reached ...)
-- the app words in the person's language.

-- ------------------------------------------------------------- small helpers

-- A text for a message or a task: trimmed, 1 to [max_length] characters, new
-- lines allowed, no other control characters and nothing that reorders or
-- hides text.
create or replace function public.workflow_clean_text(
  raw jsonb,
  max_length integer,
  required boolean default true
)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  cleaned text;
begin
  if raw is null or jsonb_typeof(raw) = 'null' then
    cleaned := '';
  elsif jsonb_typeof(raw) <> 'string' then
    raise exception 'workflow_text_invalid' using errcode = '22023';
  else
    cleaned := btrim(raw #>> '{}');
  end if;
  if cleaned = '' then
    if required then
      raise exception 'workflow_text_invalid' using errcode = '22023';
    end if;
    return null;
  end if;
  if char_length(cleaned) > max_length
    or cleaned ~ '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f​-‏‪-‮⁠-⁤⁦-⁩﻿]'
  then
    raise exception 'workflow_text_invalid' using errcode = '22023';
  end if;
  return cleaned;
end;
$$;

-- The uuid in a json value, or null.
create or replace function public.workflow_uuid(raw jsonb)
returns uuid
language plpgsql
immutable
set search_path = public
as $$
begin
  if raw is null or jsonb_typeof(raw) <> 'string' then
    return null;
  end if;
  return (raw #>> '{}')::uuid;
exception when others then
  return null;
end;
$$;

-- A name of a person for a log or a message: their name in the circle, or
-- their display name.
create or replace function public.workflow_user_label(
  p_circle_id uuid,
  p_user_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  label text;
begin
  if p_user_id is null then
    return null;
  end if;
  if p_circle_id is not null then
    label := public.circle_member_label(p_circle_id, p_user_id);
    if nullif(btrim(coalesce(label, '')), '') is not null then
      return label;
    end if;
  end if;
  select coalesce(nullif(btrim(p.display_name), ''), p.username)
  into label
  from public.profiles p
  where p.id = p_user_id;
  return label;
end;
$$;

revoke execute on function public.workflow_clean_text(jsonb, integer, boolean) from public, anon, authenticated;
revoke execute on function public.workflow_uuid(jsonb) from public, anon, authenticated;
revoke execute on function public.workflow_user_label(uuid, uuid) from public, anon, authenticated;

-- A channel of the circle a workflow may post in or listen to.
create or replace function public.workflow_channel_ok(p_channel_id uuid, p_circle_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.circle_channels cc
    where cc.id = p_channel_id
      and cc.circle_id = p_circle_id
      and cc.kind in ('text', 'announcement')
  );
$$;

-- A form of the scope (the group's chat, or a channel of the circle).
create or replace function public.workflow_form_in_scope(
  p_form_id uuid,
  p_circle_id uuid,
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.forms f
    where f.id = p_form_id
      and (
        (p_conversation_id is not null and f.conversation_id = p_conversation_id)
        or (
          p_circle_id is not null
          and exists (
            select 1
            from public.circle_channels cc
            where cc.circle_id = p_circle_id
              and cc.conversation_id = f.conversation_id
          )
        )
      )
  );
$$;

revoke execute on function public.workflow_channel_ok(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.workflow_form_in_scope(uuid, uuid, uuid) from public, anon, authenticated;

-- ------------------------------------------------------------- the trigger

create or replace function public.workflow_normalize_trigger(
  p_kind text,
  p_config jsonb,
  p_circle_id uuid,
  p_conversation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  src jsonb := coalesce(p_config, '{}'::jsonb);
  channel uuid;
  emoji text;
  words jsonb := '[]'::jsonb;
  word text;
  seen text[] := '{}';
  form_id uuid;
  recurrence text;
  day_of integer;
  at_time text;
  zone text;
  until_date date;
  out jsonb := '{}'::jsonb;
begin
  if jsonb_typeof(src) <> 'object' then
    raise exception 'workflow_trigger_invalid' using errcode = '22023';
  end if;

  if p_kind = 'member_joined' then
    return '{}'::jsonb;

  elsif p_kind in ('reaction', 'keyword') then
    if src ? 'channel_id' and jsonb_typeof(src -> 'channel_id') <> 'null' then
      channel := public.workflow_uuid(src -> 'channel_id');
      if p_circle_id is null
        or channel is null
        or not public.workflow_channel_ok(channel, p_circle_id)
      then
        raise exception 'workflow_channel_invalid' using errcode = '22023';
      end if;
      out := jsonb_build_object('channel_id', channel);
    end if;

    if p_kind = 'reaction' then
      emoji := btrim(coalesce(src ->> 'emoji', ''));
      if char_length(emoji) not between 1 and 64 then
        raise exception 'workflow_trigger_invalid' using errcode = '22023';
      end if;
      return out || jsonb_build_object('emoji', emoji);
    end if;

    if jsonb_typeof(src -> 'words') is distinct from 'array'
      or jsonb_array_length(src -> 'words') not between 1 and 10
    then
      raise exception 'workflow_trigger_invalid' using errcode = '22023';
    end if;
    for word in select value #>> '{}' from jsonb_array_elements(src -> 'words') loop
      word := lower(btrim(coalesce(word, '')));
      if char_length(word) not between 1 and 40
        or word ~ '[\x01-\x1f\x7f​-‏‪-‮⁠-⁤⁦-⁩﻿]'
      then
        raise exception 'workflow_trigger_invalid' using errcode = '22023';
      end if;
      if not (word = any(seen)) then
        seen := seen || word;
        words := words || to_jsonb(word);
      end if;
    end loop;
    return out || jsonb_build_object('words', words);

  elsif p_kind = 'schedule' then
    recurrence := coalesce(src ->> 'recurrence', '');
    if recurrence not in ('daily', 'weekdays', 'weekly', 'monthly') then
      raise exception 'workflow_trigger_invalid' using errcode = '22023';
    end if;
    at_time := coalesce(src ->> 'time', '');
    if at_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
      raise exception 'workflow_trigger_invalid' using errcode = '22023';
    end if;
    zone := coalesce(
      (select n.name from pg_timezone_names n where n.name = btrim(coalesce(src ->> 'zone', '')) limit 1),
      'UTC'
    );
    out := jsonb_build_object('recurrence', recurrence, 'time', at_time, 'zone', zone);

    if recurrence = 'weekly' then
      begin
        day_of := (src ->> 'day')::integer;
      exception when others then
        day_of := null;
      end;
      if day_of is null or day_of not between 1 and 7 then
        raise exception 'workflow_trigger_invalid' using errcode = '22023';
      end if;
      out := out || jsonb_build_object('day', day_of);
    elsif recurrence = 'monthly' then
      begin
        day_of := (src ->> 'day')::integer;
      exception when others then
        day_of := null;
      end;
      if day_of is null or day_of not between 1 and 31 then
        raise exception 'workflow_trigger_invalid' using errcode = '22023';
      end if;
      out := out || jsonb_build_object('day', day_of);
    end if;

    if nullif(src ->> 'until', '') is not null then
      begin
        until_date := (src ->> 'until')::date;
      exception when others then
        raise exception 'workflow_trigger_invalid' using errcode = '22023';
      end;
      if until_date < (now() at time zone zone)::date
        or until_date > (now() at time zone zone)::date + 730
      then
        raise exception 'workflow_trigger_invalid' using errcode = '22023';
      end if;
      out := out || jsonb_build_object('until', until_date);
    end if;
    return out;

  elsif p_kind = 'form_submitted' then
    form_id := public.workflow_uuid(src -> 'form_id');
    if form_id is null
      or not public.workflow_form_in_scope(form_id, p_circle_id, p_conversation_id)
    then
      raise exception 'workflow_form_invalid' using errcode = '22023';
    end if;
    -- Answers of an anonymous form stay anonymous: no workflow listens.
    if exists (
      select 1 from public.forms f
      where f.id = form_id and coalesce((f.settings ->> 'anonymous')::boolean, false)
    ) then
      raise exception 'workflow_form_anonymous' using errcode = '22023';
    end if;
    return jsonb_build_object('form_id', form_id);
  end if;

  raise exception 'workflow_trigger_invalid' using errcode = '22023';
end;
$$;

revoke execute on function public.workflow_normalize_trigger(text, jsonb, uuid, uuid)
  from public, anon, authenticated;

-- ------------------------------------------------------------- the actions

create or replace function public.workflow_normalize_actions(
  p_actions jsonb,
  p_trigger_kind text,
  p_circle_id uuid,
  p_conversation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  item jsonb;
  kind text;
  out jsonb := '[]'::jsonb;
  clean jsonb;
  channel uuid;
  role_id uuid;
  form_id uuid;
  text_value text;
  title_value text;
  days integer;
  has_actor boolean := p_trigger_kind <> 'schedule';
  has_message boolean := p_trigger_kind in ('reaction', 'keyword');
  from_message boolean;
begin
  if jsonb_typeof(p_actions) is distinct from 'array'
    or jsonb_array_length(p_actions) not between 1 and 5
  then
    raise exception 'workflow_actions_invalid' using errcode = '22023';
  end if;

  for item in select value from jsonb_array_elements(p_actions) loop
    if jsonb_typeof(item) <> 'object' then
      raise exception 'workflow_action_invalid' using errcode = '22023';
    end if;
    kind := coalesce(item ->> 'type', '');
    clean := jsonb_build_object('type', kind);

    -- The channel an action works in. A group has only its chat; a circle
    -- needs a channel, except that a reaction or a keyword may say "where it
    -- happened".
    if kind in ('send_message', 'create_task', 'send_form') then
      channel := null;
      if p_circle_id is not null then
        if item ? 'channel_id' and jsonb_typeof(item -> 'channel_id') <> 'null' then
          channel := public.workflow_uuid(item -> 'channel_id');
          if channel is null or not public.workflow_channel_ok(channel, p_circle_id) then
            raise exception 'workflow_channel_invalid' using errcode = '22023';
          end if;
        elsif not has_message then
          raise exception 'workflow_channel_invalid' using errcode = '22023';
        end if;
      end if;
    end if;

    if kind = 'send_message' then
      text_value := public.workflow_clean_text(item -> 'text', 500);
      if text_value like '%{member}%' and not has_actor then
        raise exception 'workflow_needs_member' using errcode = '22023';
      end if;
      clean := clean || jsonb_build_object('text', text_value);
      if channel is not null then
        clean := clean || jsonb_build_object('channel_id', channel);
      end if;

    elsif kind = 'send_dm' then
      if not has_actor then
        raise exception 'workflow_needs_member' using errcode = '22023';
      end if;
      clean := clean || jsonb_build_object(
        'text', public.workflow_clean_text(item -> 'text', 500)
      );

    elsif kind = 'add_role' then
      if p_circle_id is null then
        raise exception 'workflow_role_invalid' using errcode = '22023';
      end if;
      if not has_actor then
        raise exception 'workflow_needs_member' using errcode = '22023';
      end if;
      role_id := public.workflow_uuid(item -> 'role_id');
      if role_id is null or not public.workflow_role_grantable(role_id, p_circle_id) then
        raise exception 'workflow_role_invalid' using errcode = '22023';
      end if;
      clean := clean || jsonb_build_object('role_id', role_id);

    elsif kind = 'create_task' then
      from_message := coalesce((item ->> 'from_message')::boolean, false);
      if from_message and not has_message then
        raise exception 'workflow_needs_message' using errcode = '22023';
      end if;
      title_value := public.workflow_clean_text(item -> 'title', 200, not from_message);
      if title_value like '%{member}%' and not has_actor then
        raise exception 'workflow_needs_member' using errcode = '22023';
      end if;
      clean := clean || jsonb_build_object('from_message', from_message);
      if title_value is not null then
        clean := clean || jsonb_build_object('title', title_value);
      end if;
      -- A task made from a message lives in the message's own chat.
      if channel is not null and not from_message then
        clean := clean || jsonb_build_object('channel_id', channel);
      end if;

    elsif kind = 'send_form' then
      form_id := public.workflow_uuid(item -> 'form_id');
      if form_id is null
        or not public.workflow_form_in_scope(form_id, p_circle_id, p_conversation_id)
      then
        raise exception 'workflow_form_invalid' using errcode = '22023';
      end if;
      clean := clean || jsonb_build_object(
        'form_id', form_id,
        'date_in_title', coalesce((item ->> 'date_in_title')::boolean, true)
      );
      if nullif(item ->> 'deadline_days', '') is not null then
        begin
          days := (item ->> 'deadline_days')::integer;
        exception when others then
          days := null;
        end;
        if days is null or days not between 1 and 60 then
          raise exception 'workflow_action_invalid' using errcode = '22023';
        end if;
        clean := clean || jsonb_build_object('deadline_days', days);
      end if;
      if channel is not null then
        clean := clean || jsonb_build_object('channel_id', channel);
      end if;

    else
      raise exception 'workflow_action_invalid' using errcode = '22023';
    end if;

    out := out || jsonb_build_array(clean);
  end loop;
  return out;
end;
$$;

revoke execute on function public.workflow_normalize_actions(jsonb, text, uuid, uuid)
  from public, anon, authenticated;

-- ------------------------------------------------------------- json shapes

create or replace function public.workflow_json(w public.workflows)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', w.id,
    'circle_id', w.circle_id,
    'conversation_id', w.conversation_id,
    'name', w.name,
    'trigger', jsonb_build_object('kind', w.trigger_kind, 'config', w.trigger_config),
    'actions', w.actions,
    'enabled', w.enabled,
    'paused_reason', w.paused_reason,
    'created_by', case
      when w.created_by is null then null
      else jsonb_build_object(
        'id', w.created_by,
        'name', public.workflow_user_label(w.circle_id, w.created_by)
      )
    end,
    'created_by_me', w.created_by is not distinct from auth.uid(),
    'next_run_at', w.next_run_at,
    'last_run_at', w.last_run_at,
    'runs_today', (
      select count(*)
      from public.workflow_runs r
      where r.workflow_id = w.id
        and r.created_at > now() - interval '24 hours'
        and r.skip_reason is distinct from 'daily_limit'
    ),
    'last_status', (
      select r.status
      from public.workflow_runs r
      where r.workflow_id = w.id and r.status not in ('queued', 'running')
      order by r.created_at desc, r.id desc
      limit 1
    ),
    'created_at', w.created_at,
    'updated_at', w.updated_at
  );
$$;

revoke execute on function public.workflow_json(public.workflows)
  from public, anon, authenticated;

-- The scope of a call: exactly one of a circle and a group chat, and the
-- caller has to manage it.
create or replace function public.workflow_assert_manager(
  p_circle_id uuid,
  p_conversation_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if (p_circle_id is not null)::integer + (p_conversation_id is not null)::integer <> 1 then
    raise exception 'workflow_scope_invalid' using errcode = '22023';
  end if;
  if not public.workflow_user_can_manage(p_circle_id, p_conversation_id, auth.uid()) then
    raise exception 'workflow_not_allowed' using errcode = '42501';
  end if;
end;
$$;

revoke execute on function public.workflow_assert_manager(uuid, uuid)
  from public, anon, authenticated;

-- ------------------------------------------------------------------ options

create or replace function public.get_workflow_options(
  p_circle_id uuid default null,
  p_conversation_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.workflow_assert_manager(p_circle_id, p_conversation_id);

  return jsonb_build_object(
    'channels', case when p_circle_id is null then '[]'::jsonb else coalesce((
      select jsonb_agg(
        jsonb_build_object('id', cc.id, 'name', cc.name, 'kind', cc.kind)
        order by cc.position, cc.name, cc.id
      )
      from public.circle_channels cc
      where cc.circle_id = p_circle_id and cc.kind in ('text', 'announcement')
    ), '[]'::jsonb) end,
    'roles', case when p_circle_id is null then '[]'::jsonb else coalesce((
      select jsonb_agg(
        jsonb_build_object('id', r.id, 'name', r.name, 'color', r.color)
        order by r.position desc, r.id
      )
      from public.circle_roles r
      where r.circle_id = p_circle_id
        and public.workflow_role_grantable(r.id, p_circle_id)
    ), '[]'::jsonb) end,
    'forms', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', f.id,
          'title', f.title,
          'anonymous', coalesce((f.settings ->> 'anonymous')::boolean, false)
        )
        order by f.created_at desc, f.id
      )
      from (
        select f2.*
        from public.forms f2
        where public.workflow_form_in_scope(f2.id, p_circle_id, p_conversation_id)
        order by f2.created_at desc, f2.id
        limit 50
      ) f
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.get_workflow_options(uuid, uuid) from public, anon;
grant execute on function public.get_workflow_options(uuid, uuid) to authenticated;

-- ------------------------------------------------------------------- list

create or replace function public.list_workflows(
  p_circle_id uuid default null,
  p_conversation_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.workflow_assert_manager(p_circle_id, p_conversation_id);

  return jsonb_build_object(
    'can_manage', true,
    'limits', public.workflow_limits(),
    'workflows', coalesce((
      select jsonb_agg(public.workflow_json(w) order by w.created_at, w.id)
      from public.workflows w
      where (p_circle_id is not null and w.circle_id = p_circle_id)
         or (p_conversation_id is not null and w.conversation_id = p_conversation_id)
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.list_workflows(uuid, uuid) from public, anon;
grant execute on function public.list_workflows(uuid, uuid) to authenticated;

-- ------------------------------------------------------------------- save

-- p_workflow: {id?, circle_id | conversation_id, name, trigger: {kind,
-- config}, actions: [...], enabled?}. Answers the workflow.
create or replace function public.save_workflow(p_workflow jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  limits jsonb := public.workflow_limits();
  existing public.workflows%rowtype;
  wanted_id uuid;
  scope_circle uuid;
  scope_conversation uuid;
  clean_name text;
  v_kind text;
  v_config jsonb;
  actions_clean jsonb;
  next_at timestamptz;
  saved public.workflows%rowtype;
  turn_on boolean;
  max_allowed integer;
  made integer;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_workflow) is distinct from 'object' then
    raise exception 'workflow_scope_invalid' using errcode = '22023';
  end if;

  wanted_id := public.workflow_uuid(p_workflow -> 'id');
  if wanted_id is not null then
    select * into existing from public.workflows where id = wanted_id for update;
    if existing.id is null then
      raise exception 'workflow_not_found' using errcode = 'P0002';
    end if;
    scope_circle := existing.circle_id;
    scope_conversation := existing.conversation_id;
  else
    scope_circle := public.workflow_uuid(p_workflow -> 'circle_id');
    scope_conversation := public.workflow_uuid(p_workflow -> 'conversation_id');
  end if;
  perform public.workflow_assert_manager(scope_circle, scope_conversation);

  clean_name := public.workflow_clean_text(p_workflow -> 'name', 60);
  if clean_name ~ E'\n' then
    raise exception 'workflow_name_invalid' using errcode = '22023';
  end if;

  v_kind := coalesce(p_workflow #>> '{trigger,kind}', '');
  v_config := public.workflow_normalize_trigger(
    v_kind,
    p_workflow #> '{trigger,config}',
    scope_circle,
    scope_conversation
  );
  actions_clean := public.workflow_normalize_actions(
    p_workflow -> 'actions',
    v_kind,
    scope_circle,
    scope_conversation
  );

  if existing.id is null then
    max_allowed := case
      when scope_circle is not null then (limits ->> 'max_per_circle')::integer
      else (limits ->> 'max_per_group')::integer
    end;
    select count(*) into made
    from public.workflows w
    where (scope_circle is not null and w.circle_id = scope_circle)
       or (scope_conversation is not null and w.conversation_id = scope_conversation);
    if made >= max_allowed then
      raise exception 'workflow_limit_reached' using errcode = '22023';
    end if;
  end if;

  turn_on := case
    when existing.id is null then coalesce((p_workflow ->> 'enabled')::boolean, true)
    else existing.enabled
  end;

  if v_kind = 'schedule' and turn_on then
    next_at := public.recurrence_next(
      v_config ->> 'recurrence',
      nullif(v_config ->> 'day', '')::integer,
      (v_config ->> 'time')::time,
      v_config ->> 'zone',
      now(),
      nullif(v_config ->> 'until', '')::date
    );
    if next_at is null then
      raise exception 'workflow_trigger_invalid' using errcode = '22023';
    end if;
  end if;

  if existing.id is null then
    insert into public.workflows (
      circle_id, conversation_id, name, trigger_kind, trigger_config, actions,
      enabled, paused_reason, paused_at, created_by, next_run_at
    )
    values (
      scope_circle, scope_conversation, clean_name, v_kind, v_config,
      actions_clean, turn_on,
      case when turn_on then null else 'manual' end,
      case when turn_on then null else now() end,
      uid, next_at
    )
    returning * into saved;
  else
    -- Whoever changes a workflow is the person its actions run as from now on.
    update public.workflows w
    set name = clean_name,
        trigger_kind = v_kind,
        trigger_config = v_config,
        actions = actions_clean,
        created_by = uid,
        next_run_at = case
          when v_kind = 'schedule' and w.enabled then next_at
          else null
        end,
        fail_streak = 0,
        updated_at = now()
    where w.id = existing.id
    returning * into saved;
  end if;

  if scope_circle is not null then
    perform public.write_circle_audit(
      scope_circle,
      case when existing.id is null then 'workflow_create' else 'workflow_update' end,
      'workflow',
      saved.id,
      saved.name,
      jsonb_build_object(
        'trigger', v_kind,
        'actions', (select jsonb_agg(a ->> 'type') from jsonb_array_elements(actions_clean) a)
      )
    );
  end if;

  return public.workflow_json(saved);
end;
$$;

revoke execute on function public.save_workflow(jsonb) from public, anon;
grant execute on function public.save_workflow(jsonb) to authenticated;

-- ---------------------------------------------------------- pause / resume

create or replace function public.set_workflow_enabled(
  p_workflow_id uuid,
  p_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  w public.workflows%rowtype;
  config jsonb;
  next_at timestamptz;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into w from public.workflows where id = p_workflow_id for update;
  if w.id is null then
    raise exception 'workflow_not_found' using errcode = 'P0002';
  end if;
  perform public.workflow_assert_manager(w.circle_id, w.conversation_id);

  if coalesce(p_enabled, false) then
    config := w.trigger_config;
    if w.trigger_kind = 'schedule' then
      next_at := public.recurrence_next(
        config ->> 'recurrence',
        nullif(config ->> 'day', '')::integer,
        (config ->> 'time')::time,
        config ->> 'zone',
        now(),
        nullif(config ->> 'until', '')::date
      );
      if next_at is null then
        raise exception 'workflow_finished' using errcode = '22023';
      end if;
    end if;
    update public.workflows
    set enabled = true,
        paused_reason = null,
        paused_at = null,
        fail_streak = 0,
        created_by = uid,
        next_run_at = next_at,
        updated_at = now()
    where id = w.id
    returning * into w;
  else
    update public.workflows
    set enabled = false,
        paused_reason = 'manual',
        paused_at = now(),
        next_run_at = null,
        updated_at = now()
    where id = w.id
    returning * into w;
  end if;

  if w.circle_id is not null then
    perform public.write_circle_audit(
      w.circle_id,
      case when w.enabled then 'workflow_resume' else 'workflow_pause' end,
      'workflow',
      w.id,
      w.name,
      '{}'::jsonb
    );
  end if;
  return public.workflow_json(w);
end;
$$;

revoke execute on function public.set_workflow_enabled(uuid, boolean) from public, anon;
grant execute on function public.set_workflow_enabled(uuid, boolean) to authenticated;

-- ------------------------------------------------------------------ delete

create or replace function public.delete_workflow(p_workflow_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  w public.workflows%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into w from public.workflows where id = p_workflow_id for update;
  if w.id is null then
    raise exception 'workflow_not_found' using errcode = 'P0002';
  end if;
  perform public.workflow_assert_manager(w.circle_id, w.conversation_id);

  delete from public.workflows where id = w.id;

  if w.circle_id is not null then
    perform public.write_circle_audit(
      w.circle_id, 'workflow_delete', 'workflow', w.id, w.name, '{}'::jsonb
    );
  end if;
end;
$$;

revoke execute on function public.delete_workflow(uuid) from public, anon;
grant execute on function public.delete_workflow(uuid) to authenticated;

-- ----------------------------------------------------------------- the log

create or replace function public.list_workflow_runs(
  p_workflow_id uuid,
  p_limit integer default 30,
  p_before timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  w public.workflows%rowtype;
  row_limit integer := least(greatest(coalesce(p_limit, 30), 1), 100);
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into w from public.workflows where id = p_workflow_id;
  if w.id is null then
    raise exception 'workflow_not_found' using errcode = 'P0002';
  end if;
  perform public.workflow_assert_manager(w.circle_id, w.conversation_id);

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'status', r.status,
        'skip_reason', r.skip_reason,
        'actor', case
          when r.actor_id is null then null
          else jsonb_build_object(
            'id', r.actor_id,
            'name', public.workflow_user_label(w.circle_id, r.actor_id)
          )
        end,
        'results', r.results,
        'error', r.error,
        'created_at', r.created_at,
        'finished_at', r.finished_at
      )
      order by r.created_at desc, r.id desc
    )
    from (
      select r2.*
      from public.workflow_runs r2
      where r2.workflow_id = w.id
        and (p_before is null or r2.created_at < p_before)
      order by r2.created_at desc, r2.id desc
      limit row_limit
    ) r
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.list_workflow_runs(uuid, integer, timestamptz) from public, anon;
grant execute on function public.list_workflow_runs(uuid, integer, timestamptz) to authenticated;
