-- Interactive components and interaction callbacks (roadmap I1), part 4 of 6:
-- what the bot gets and how it answers.
--
-- * bot_interaction_payload(row): one interaction as the bot sees it, the same
--   for a poll and for a callback. Commands keep their old keys (command,
--   options); every item now also says "type" ("command" or "component"). A
--   component item names the message (message_id: the message the person
--   pressed on, also for a private reply), the component (id, type, label),
--   what was chosen or typed (values) and whether the press was on a private
--   reply (ephemeral).
-- * bot_api_poll_interactions: the latest definition is 202610160030; the same
--   function with component presses added. Presses that went to the bot's
--   callback are not handed out again unless the delivery failed for good
--   (delivery_state 'failed'), so a bot with a callback is not told twice.
-- * bot_api_respond: one answer per interaction, within the 15 minutes it
--   stands. For a slash command it is the old answer
--   (a message with "Ann used /ping" above it, components allowed). For a press:
--     message    a message in the channel (shows who pressed what),
--     ephemeral  a private reply only the person who pressed sees,
--     update     changes the message pressed on (text and/or components), or
--                the private reply it was pressed on,
--     ack        nothing visible, the press is marked answered.
--   bot_api_respond_interaction (202610160030) stays for old callers, but for
--   a press it refuses and says to use the new function.

create or replace function public.bot_interaction_payload(
  interaction public.bot_interactions
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select
    jsonb_build_object(
      'id', interaction.id,
      'type', interaction.kind,
      'channel_id', interaction.channel_id,
      'user', jsonb_build_object(
        'id', interaction.user_id,
        'username', p.username,
        'name', public.circle_member_label(interaction.circle_id, interaction.user_id)
      ),
      'created_at', interaction.created_at,
      'expires_at', interaction.expires_at
    )
    || case
      when interaction.kind = 'command' then jsonb_build_object(
        'command', interaction.command_name,
        'options', interaction.options
      )
      else jsonb_build_object(
        'message_id', interaction.message_id,
        'ephemeral', interaction.ephemeral_id is not null,
        'component', jsonb_build_object(
          'id', interaction.component_id,
          'type', interaction.component_type,
          'label', interaction.component_label
        ),
        'values', interaction.submitted
      )
    end
  from public.profiles p
  where p.id = interaction.user_id;
$$;

revoke execute on function public.bot_interaction_payload(public.bot_interactions) from public, anon, authenticated;

-- Hands out unanswered interactions (again 30 seconds after a poll).
create or replace function public.bot_api_poll_interactions(
  bot_token text,
  max_count integer default 25
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  result jsonb;
begin
  with picked as (
    select bi.id
    from public.bot_interactions bi
    where bi.bot_id = bot.id
      and bi.responded_at is null
      and bi.expires_at > now()
      and bi.delivery_state in ('none', 'failed')
      and (bi.claimed_at is null or bi.claimed_at < now() - interval '30 seconds')
    order by bi.created_at
    limit least(greatest(coalesce(max_count, 25), 1), 100)
    for update skip locked
  ),
  claimed as (
    update public.bot_interactions bi
    set claimed_at = now()
    from picked
    where bi.id = picked.id
    returning bi.*
  )
  select coalesce(jsonb_agg(
    public.bot_interaction_payload(c)
    order by c.created_at
  ), '[]'::jsonb)
  into result
  from claimed c;

  return result;
end;
$$;

-- The old answer function: commands only.
create or replace function public.bot_api_respond_interaction(
  bot_token text,
  target_interaction_id uuid,
  content text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  pending public.bot_interactions%rowtype;
  trimmed_content text := btrim(coalesce(content, ''));
  created_message_id uuid;
begin
  select bi.* into pending
  from public.bot_interactions bi
  where bi.id = target_interaction_id
    and bi.bot_id = bot.id
  for update;

  if pending.id is null or pending.expires_at <= now() then
    raise exception 'Interaction not found or expired' using errcode = 'P0002';
  end if;

  if pending.kind <> 'command' then
    raise exception 'Answer a press on a component with the new answer function'
      using errcode = '22023';
  end if;

  if pending.responded_at is not null then
    raise exception 'Interaction already answered' using errcode = '23505';
  end if;

  if char_length(trimmed_content) not between 1 and 2000 then
    raise exception 'Content must be 1 to 2000 characters' using errcode = '22023';
  end if;

  perform public.count_bot_write(bot);
  perform public.act_as_bot(bot);

  created_message_id := public.send_text_message(
    pending.conversation_id,
    trimmed_content,
    null,
    null,
    '[]'::jsonb
  );

  -- AutoMod refused it quietly (202610160020): the interaction stays open.
  if created_message_id is null then
    return null;
  end if;

  update public.messages m
  set interaction = jsonb_build_object(
    'interaction_id', pending.id,
    'command', pending.command_name,
    'user_id', pending.user_id,
    'user_name', public.circle_member_label(pending.circle_id, pending.user_id)
  )
  where m.id = created_message_id;

  update public.bot_interactions bi
  set responded_at = now(), response_message_id = created_message_id, response_kind = 'message'
  where bi.id = pending.id;

  return created_message_id;
end;
$$;

-- Answers an interaction once. [response] is {type?, content?, components?}:
-- type is message (the default), ephemeral, update or ack. Returns the id of
-- the message made (message), of the private reply (ephemeral) or of the
-- message or private reply changed (update); null for ack, and also when
-- AutoMod refused quietly (the interaction then stays open).
create or replace function public.bot_api_respond(
  bot_token text,
  target_interaction_id uuid,
  response jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  pending public.bot_interactions%rowtype;
  response_type text;
  has_content boolean;
  has_components boolean;
  trimmed_content text;
  cleaned jsonb;
  result_id uuid;
  target_ephemeral public.bot_ephemeral_messages%rowtype;
begin
  if response is null or jsonb_typeof(response) <> 'object' then
    raise exception 'The answer must be an object' using errcode = '22023';
  end if;

  response_type := coalesce(response->>'type', 'message');
  if response_type not in ('message', 'ephemeral', 'update', 'ack') then
    raise exception 'type is message, ephemeral, update or ack' using errcode = '22023';
  end if;

  has_content := response ? 'content' and jsonb_typeof(response->'content') <> 'null';
  has_components := response ? 'components';
  if has_content and jsonb_typeof(response->'content') <> 'string' then
    raise exception 'content must be text' using errcode = '22023';
  end if;
  trimmed_content := btrim(coalesce(response->>'content', ''));
  cleaned := case
    when has_components then public.normalize_message_components(response->'components')
    else null
  end;

  select bi.* into pending
  from public.bot_interactions bi
  where bi.id = target_interaction_id
    and bi.bot_id = bot.id
  for update;

  if pending.id is null or pending.expires_at <= now() then
    raise exception 'Interaction not found or expired' using errcode = 'P0002';
  end if;
  if pending.responded_at is not null then
    raise exception 'Interaction already answered' using errcode = '23505';
  end if;

  if pending.kind = 'command' and response_type <> 'message' then
    raise exception 'A slash command is answered with a message' using errcode = '22023';
  end if;

  if response_type in ('message', 'ephemeral')
    and char_length(trimmed_content) not between 1 and 2000
  then
    raise exception 'Content must be 1 to 2000 characters' using errcode = '22023';
  end if;
  if response_type = 'ack' and (has_content or has_components) then
    raise exception 'An ack has no content' using errcode = '22023';
  end if;

  perform public.count_bot_write(bot);

  if cleaned is not null
    and public.bot_components_automod(pending.conversation_id, bot.user_id, cleaned)
  then
    return null;
  end if;

  perform public.act_as_bot(bot);

  if response_type = 'message' then
    result_id := public.bot_send_text(
      pending.conversation_id,
      trimmed_content,
      null,
      null,
      cleaned
    );
    -- AutoMod refused it quietly: the interaction stays open.
    if result_id is null then
      return null;
    end if;
    update public.messages m
    set interaction = case
      when pending.kind = 'command' then jsonb_build_object(
        'interaction_id', pending.id,
        'command', pending.command_name,
        'user_id', pending.user_id,
        'user_name', public.circle_member_label(pending.circle_id, pending.user_id)
      )
      else jsonb_build_object(
        'interaction_id', pending.id,
        'command', '',
        'component_label', pending.component_label,
        'user_id', pending.user_id,
        'user_name', public.circle_member_label(pending.circle_id, pending.user_id)
      )
    end
    where m.id = result_id;
  elsif response_type = 'ephemeral' then
    if public.bot_text_blocked(pending.conversation_id, bot.user_id, trimmed_content) then
      return null;
    end if;
    insert into public.bot_ephemeral_messages (
      bot_id, conversation_id, message_id, user_id, interaction_id, body, components
    )
    values (
      bot.id, pending.conversation_id, pending.message_id, pending.user_id,
      pending.id, trimmed_content, cleaned
    )
    returning id into result_id;
  elsif response_type = 'update' then
    if not has_content and not has_components then
      raise exception 'An update changes the content or the components' using errcode = '22023';
    end if;
    if pending.ephemeral_id is not null then
      select e.* into target_ephemeral
      from public.bot_ephemeral_messages e
      where e.id = pending.ephemeral_id
      for update;
      if target_ephemeral.id is null then
        raise exception 'The private reply is gone' using errcode = 'P0002';
      end if;
      if has_content and char_length(trimmed_content) not between 1 and 2000 then
        raise exception 'Content must be 1 to 2000 characters' using errcode = '22023';
      end if;
      if has_content
        and public.bot_text_blocked(pending.conversation_id, bot.user_id, trimmed_content)
      then
        return null;
      end if;
      update public.bot_ephemeral_messages e
      set
        body = case when has_content then trimmed_content else e.body end,
        components = case when has_components then cleaned else e.components end
      where e.id = target_ephemeral.id;
      result_id := target_ephemeral.id;
    else
      if not public.bot_edit_own_message(
        bot,
        pending.message_id,
        case when has_content then trimmed_content end,
        has_components,
        cleaned
      ) then
        return null;
      end if;
      result_id := pending.message_id;
    end if;
  end if;

  update public.bot_interactions bi
  set
    responded_at = now(),
    response_message_id = case when response_type = 'message' then result_id end,
    response_kind = response_type
  where bi.id = pending.id;

  return result_id;
end;
$$;

revoke execute on function public.bot_api_respond(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.bot_api_respond(text, uuid, jsonb) to service_role;
