-- Interactive components and interaction callbacks (roadmap I1), part 3 of 6:
-- pressing a component, and reading a bot's private replies.
--
-- * submit_interaction(message_id, component_id, values): a member presses a
--   button or picks from a list (a form's answers come in values too). Only
--   someone who can read the message as it is now may: a member of the chat
--   with view_channel (current_user_readable_conversation_ids, which also
--   closes a circle that K1 suspended), the message not deleted, expired or
--   waiting for the AI guard, the account not suspended (K1), no block with
--   the bot, the bot still in its circle and able to see the channel. The
--   answer is checked against what the bot defined: the component exists and
--   is not disabled, a list gets between min_values and max_values of its own
--   option values, a form gets only its own fields within their lengths. A
--   wrong id looks the same as a message that cannot be seen (P0002), so the
--   function says nothing about messages the caller cannot read.
--   Limits: 30 presses per person and minute, one per component and second
--   (BT429), and a bot with 200 unanswered presses takes no more.
--   The press is a bot_interactions row of kind 'component' for the bot to
--   poll or to get on its callback (parts 4 and 5).
-- * interaction_status(id): the person who pressed learns whether the bot has
--   answered (the app waits a few seconds, then says the bot did not answer).
-- * list_my_ephemeral_messages(conversation): the private replies of bots to
--   the caller. dismiss_ephemeral_message(id) removes one.

-- The component [component_id] of a list of components, or null.
create or replace function public.find_message_component(
  message_components jsonb,
  component_id text
)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select c.value
  from jsonb_array_elements(coalesce(message_components, '[]'::jsonb)) r,
    jsonb_array_elements(r.value) c
  where c.value->>'id' = component_id
  limit 1;
$$;

revoke execute on function public.find_message_component(jsonb, text) from public, anon, authenticated;

-- Checks what a person sent for a component against its definition and
-- returns it in the shape the bot gets: a list gives an array of option
-- values, a form an object of field id -> text, a plain button null.
create or replace function public.check_component_values(
  component jsonb,
  submitted jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  chosen text[];
  picked jsonb;
  option_values text[];
  value text;
  field jsonb;
  fields_in jsonb;
  field_value text;
  out_values jsonb := '{}'::jsonb;
  seen_fields text[] := '{}';
  key text;
  forbidden text;
begin
  if component->>'type' = 'select' then
    if submitted is null or jsonb_typeof(submitted) <> 'array' then
      raise exception 'Choose from the list' using errcode = '22023';
    end if;
    chosen := '{}';
    for picked in select v from jsonb_array_elements(submitted) v loop
      if jsonb_typeof(picked) <> 'string' then
        raise exception 'Choices are option values' using errcode = '22023';
      end if;
      value := picked #>> '{}';
      if value = any (chosen) then
        raise exception 'The same option twice' using errcode = '22023';
      end if;
      chosen := chosen || value;
    end loop;
    select array_agg(o.value->>'value')
    into option_values
    from jsonb_array_elements(component->'options') o;
    if coalesce(array_length(chosen, 1), 0) < (component->>'min_values')::integer
      or coalesce(array_length(chosen, 1), 0) > (component->>'max_values')::integer
    then
      raise exception 'Choose % to % options',
        component->>'min_values', component->>'max_values'
        using errcode = '22023';
    end if;
    foreach value in array chosen loop
      if not (value = any (option_values)) then
        raise exception 'That option is not in the list' using errcode = '22023';
      end if;
    end loop;
    return to_jsonb(chosen);
  end if;

  if component ? 'modal' then
    fields_in := component#>'{modal,fields}';
    if submitted is null or jsonb_typeof(submitted) <> 'object' then
      raise exception 'Fill in the form' using errcode = '22023';
    end if;
    for key in select k from jsonb_object_keys(submitted) k loop
      if not exists (
        select 1 from jsonb_array_elements(fields_in) f where f.value->>'id' = key
      ) then
        raise exception 'That field is not in the form' using errcode = '22023';
      end if;
    end loop;
    for field in select f from jsonb_array_elements(fields_in) f loop
      if jsonb_typeof(submitted->(field->>'id')) not in ('string', 'null')
        and submitted ? (field->>'id')
      then
        raise exception 'Form answers are text' using errcode = '22023';
      end if;
      field_value := btrim(coalesce(submitted->>(field->>'id'), ''));
      if (field->>'required')::boolean and field_value = '' then
        raise exception 'Fill in every required field' using errcode = '22023';
      end if;
      if char_length(field_value) > (field->>'max_length')::integer then
        raise exception 'An answer is too long' using errcode = '22023';
      end if;
      -- No control characters but new lines in a long answer.
      forbidden := case
        when field->>'style' = 'paragraph' then '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]'
        else '[[:cntrl:]]'
      end;
      if field_value ~ forbidden then
        raise exception 'An answer has characters that are not allowed' using errcode = '22023';
      end if;
      out_values := out_values || jsonb_build_object(field->>'id', field_value);
    end loop;
    return out_values;
  end if;

  if submitted is not null
    and jsonb_typeof(submitted) not in ('null')
    and not (jsonb_typeof(submitted) = 'array' and jsonb_array_length(submitted) = 0)
    and not (jsonb_typeof(submitted) = 'object' and submitted = '{}'::jsonb)
  then
    raise exception 'A button takes no values' using errcode = '22023';
  end if;
  return null;
end;
$$;

revoke execute on function public.check_component_values(jsonb, jsonb) from public, anon, authenticated;

create or replace function public.submit_interaction(
  target_message_id uuid,
  target_component_id text,
  submitted_values jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  message public.messages%rowtype;
  ephemeral public.bot_ephemeral_messages%rowtype;
  conversation uuid;
  root_message uuid;
  defined jsonb;
  bot public.circle_bots%rowtype;
  channel_id uuid;
  component jsonb;
  checked jsonb;
  label text;
  created public.bot_interactions%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if public.is_user_suspended(current_user_id) then
    raise exception 'Your account is suspended' using errcode = '42501';
  end if;

  select m.* into message
  from public.messages m
  where m.id = target_message_id;

  if message.id is not null then
    -- Only what the caller could read in the chat right now.
    if message.conversation_id not in (select public.current_user_readable_conversation_ids())
      or message.recalled_at is not null
      or (message.expires_at is not null and message.expires_at <= now())
      or message.review_state is not null
    then
      raise exception 'Message not found' using errcode = 'P0002';
    end if;
    conversation := message.conversation_id;
    root_message := message.id;
    defined := message.components;
    select b.* into bot from public.circle_bots b where b.user_id = message.sender_id;
  else
    select e.* into ephemeral
    from public.bot_ephemeral_messages e
    where e.id = target_message_id
      and e.user_id = current_user_id
      and e.expires_at > now();
    if ephemeral.id is null
      or ephemeral.conversation_id not in (select public.current_user_readable_conversation_ids())
    then
      raise exception 'Message not found' using errcode = 'P0002';
    end if;
    conversation := ephemeral.conversation_id;
    root_message := ephemeral.message_id;
    defined := ephemeral.components;
    select b.* into bot from public.circle_bots b where b.id = ephemeral.bot_id;
  end if;

  channel_id := public.conversation_circle_channel_id(conversation);

  if bot.id is null
    or defined is null
    or channel_id is null
    or not exists (
      select 1
      from public.circle_members cm
      where cm.circle_id = bot.circle_id
        and cm.user_id = bot.user_id
    )
    or not exists (
      select 1 from public.circle_channels cc
      where cc.id = channel_id and cc.circle_id = bot.circle_id
    )
    or not public.circle_channel_has_permission(channel_id, bot.user_id, 'view_channel')
  then
    raise exception 'Message not found' using errcode = 'P0002';
  end if;

  if public.are_users_blocked(current_user_id, bot.user_id) then
    raise exception 'You cannot use this bot' using errcode = '42501';
  end if;

  component := public.find_message_component(defined, target_component_id);
  if component is null then
    raise exception 'Component not found' using errcode = 'P0002';
  end if;
  if component->>'type' = 'link' then
    raise exception 'A link opens in the browser' using errcode = '22023';
  end if;
  if coalesce((component->>'disabled')::boolean, false) then
    raise exception 'This component is turned off' using errcode = '22023';
  end if;

  checked := public.check_component_values(component, submitted_values);

  -- Limits: per person, per component and per bot.
  if (
    select count(*)
    from public.bot_interactions bi
    where bi.user_id = current_user_id
      and bi.kind = 'component'
      and bi.created_at > now() - interval '1 minute'
  ) >= 30 then
    raise exception 'Too many presses, wait a moment' using errcode = 'BT429';
  end if;
  if exists (
    select 1
    from public.bot_interactions bi
    where bi.user_id = current_user_id
      and bi.kind = 'component'
      and bi.component_id = target_component_id
      and bi.message_id is not distinct from root_message
      and bi.created_at > now() - interval '1 second'
  ) then
    raise exception 'Too fast, wait a moment' using errcode = 'BT429';
  end if;
  if (
    select count(*)
    from public.bot_interactions bi
    where bi.bot_id = bot.id
      and bi.kind = 'component'
      and bi.responded_at is null
      and bi.expires_at > now()
  ) >= 200 then
    raise exception 'This bot is busy, try again later' using errcode = 'BT429';
  end if;

  label := coalesce(
    nullif(component->>'label', ''),
    nullif(component->>'placeholder', ''),
    (
      select o.value->>'label'
      from jsonb_array_elements(coalesce(component->'options', '[]'::jsonb)) o
      where checked is not null
        and jsonb_typeof(checked) = 'array'
        and o.value->>'value' = checked->>0
      limit 1
    ),
    target_component_id
  );

  insert into public.bot_interactions (
    kind,
    bot_id,
    circle_id,
    channel_id,
    conversation_id,
    user_id,
    message_id,
    ephemeral_id,
    component_id,
    component_type,
    component_label,
    submitted
  )
  values (
    'component',
    bot.id,
    bot.circle_id,
    channel_id,
    conversation,
    current_user_id,
    root_message,
    ephemeral.id,
    target_component_id,
    case
      when component->>'type' = 'select' then 'select'
      when component ? 'modal' then 'modal'
      else 'button'
    end,
    left(label, 100),
    checked
  )
  returning * into created;

  return jsonb_build_object(
    'interaction_id', created.id,
    'bot_name', bot.name,
    'expires_at', created.expires_at,
    'by_callback', created.delivery_state = 'queued'
  );
end;
$$;

revoke execute on function public.submit_interaction(uuid, text, jsonb) from public, anon;
grant execute on function public.submit_interaction(uuid, text, jsonb) to authenticated;

-- Whether the bot has answered a press of the caller: pending, answered or
-- expired (the bot did not answer in time).
create or replace function public.interaction_status(target_interaction_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  status_row public.bot_interactions%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select bi.* into status_row
  from public.bot_interactions bi
  where bi.id = target_interaction_id
    and bi.user_id = auth.uid();

  if status_row.id is null then
    raise exception 'Interaction not found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'status', case
      when status_row.responded_at is not null then 'answered'
      when status_row.expires_at <= now() then 'expired'
      else 'pending'
    end,
    'response_kind', status_row.response_kind
  );
end;
$$;


revoke execute on function public.interaction_status(uuid) from public, anon;
grant execute on function public.interaction_status(uuid) to authenticated;

-- The bots' private replies to the caller in a chat, oldest first.
create or replace function public.list_my_ephemeral_messages(
  target_conversation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if target_conversation_id not in (select public.current_user_readable_conversation_ids()) then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', e.id,
        'message_id', e.message_id,
        'bot_name', b.name,
        'body', e.body,
        'components', e.components,
        'created_at', e.created_at,
        'expires_at', e.expires_at
      )
      order by e.created_at, e.id
    )
    from public.bot_ephemeral_messages e
    join public.circle_bots b on b.id = e.bot_id
    where e.user_id = auth.uid()
      and e.conversation_id = target_conversation_id
      and e.expires_at > now()
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.list_my_ephemeral_messages(uuid) from public, anon;
grant execute on function public.list_my_ephemeral_messages(uuid) to authenticated;

create or replace function public.dismiss_ephemeral_message(target_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  delete from public.bot_ephemeral_messages e
  where e.id = target_id
    and e.user_id = auth.uid();
end;
$$;

revoke execute on function public.dismiss_ephemeral_message(uuid) from public, anon;
grant execute on function public.dismiss_ephemeral_message(uuid) to authenticated;
