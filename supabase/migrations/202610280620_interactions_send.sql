-- Interactive components and interaction callbacks (roadmap I1), part 2 of 6:
-- what a bot sends and changes.
--
-- * bot_send_text (internal): sends a bot's text message with components in
--   one write. send_text_message (202610160047) is called as it is, so
--   permissions, timeouts, slowmode, AutoMod on the text, the push and the
--   search entry all work the same as for any member; the components ride in
--   on the setting wecord.message_components that messages_guard_components
--   (part 1) reads for the insert.
-- * bot_text_blocked / bot_components_automod (internal): AutoMod reads the
--   texts of the components (and of a private reply) like the message. A blocking rule refuses quietly (the caller
--   returns null / false, like a blocked message).
-- * bot_api_send_message_with_components: bot_api_send_message plus
--   components. bot_api_send_message is left as it was.
-- * bot_api_edit_message: a bot changes the text and/or the components of its
--   own message (components: null or [] removes them). The text goes through
--   the same triggers as anyone's edit (history, AutoMod, the circle's edit
--   time limit, the AI guard's lock); changing only the components touches
--   none of them.
-- Writes count against the bot's 60 per minute (count_bot_write).

create or replace function public.bot_text_blocked(
  target_conversation_id uuid,
  sender_user_id uuid,
  message_text text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  verdict jsonb;
begin
  if coalesce(message_text, '') = '' then
    return false;
  end if;
  verdict := public.circle_automod_verdict(
    target_conversation_id,
    sender_user_id,
    message_text,
    '[]'::jsonb,
    false
  );
  return verdict is not null and coalesce((verdict->>'block')::boolean, false);
end;
$$;

create or replace function public.bot_components_automod(
  target_conversation_id uuid,
  sender_user_id uuid,
  message_components jsonb
)
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.bot_text_blocked(
    target_conversation_id,
    sender_user_id,
    public.message_components_text(message_components)
  );
$$;

revoke execute on function public.bot_text_blocked(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function public.bot_components_automod(uuid, uuid, jsonb) from public, anon, authenticated;

-- Sends [content] as the bot (auth.uid() must already be the bot, see
-- act_as_bot) with [message_components] (already normalized, or null).
-- Returns the message's id, or null when AutoMod refused it quietly.
create or replace function public.bot_send_text(
  target_conversation_id uuid,
  content text,
  reply_message_id uuid,
  reply_preview jsonb,
  message_components jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  created_id uuid;
begin
  if message_components is not null then
    perform set_config('wecord.message_components', message_components::text, true);
  end if;
  begin
    created_id := public.send_text_message(
      target_conversation_id,
      content,
      reply_message_id,
      reply_preview,
      '[]'::jsonb
    );
  exception when others then
    perform set_config('wecord.message_components', '', true);
    raise;
  end;
  perform set_config('wecord.message_components', '', true);
  return created_id;
end;
$$;

revoke execute on function public.bot_send_text(uuid, text, uuid, jsonb, jsonb) from public, anon, authenticated;

create or replace function public.bot_api_send_message_with_components(
  bot_token text,
  target_channel_id uuid,
  content text,
  reply_to_message_id uuid default null,
  message_components jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  channel public.circle_channels%rowtype := public.bot_visible_channel(bot, target_channel_id);
  trimmed_content text := btrim(coalesce(content, ''));
  cleaned jsonb := public.normalize_message_components(message_components);
  reply public.messages%rowtype;
  preview jsonb;
begin
  if char_length(trimmed_content) not between 1 and 2000 then
    raise exception 'Content must be 1 to 2000 characters' using errcode = '22023';
  end if;

  if reply_to_message_id is not null then
    select m.* into reply
    from public.messages m
    where m.id = bot_api_send_message_with_components.reply_to_message_id
      and m.conversation_id = channel.conversation_id;

    if reply.id is null then
      raise exception 'Reply message not found in this channel' using errcode = '22023';
    end if;

    preview := jsonb_build_object(
      'message_id', reply.id,
      'sender_name', coalesce(
        reply.webhook_name,
        public.circle_member_label(bot.circle_id, reply.sender_id)
      ),
      'body', case when reply.recalled_at is null then left(reply.body, 200) else '' end,
      'type', reply.type
    );
  end if;

  perform public.count_bot_write(bot);

  -- AutoMod reads the texts of the buttons like the message itself.
  if cleaned is not null
    and public.bot_components_automod(channel.conversation_id, bot.user_id, cleaned)
  then
    return null;
  end if;

  perform public.act_as_bot(bot);

  return public.bot_send_text(
    channel.conversation_id,
    trimmed_content,
    reply.id,
    preview,
    cleaned
  );
end;
$$;

revoke execute on function public.bot_api_send_message_with_components(text, uuid, text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.bot_api_send_message_with_components(text, uuid, text, uuid, jsonb) to service_role;

-- Changes the bot's own message. A null [new_content] leaves the text;
-- [change_components] says the components are to be replaced (null
-- [new_components] then removes them).
-- Returns false when AutoMod refused the change quietly.
create or replace function public.bot_edit_own_message(
  bot public.circle_bots,
  target_message_id uuid,
  new_content text,
  change_components boolean,
  new_components jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  message public.messages%rowtype;
  trimmed_content text := btrim(coalesce(new_content, ''));
  cleaned jsonb := case
    when change_components then public.normalize_message_components(new_components)
    else null
  end;
begin
  if new_content is not null and char_length(trimmed_content) not between 1 and 2000 then
    raise exception 'Content must be 1 to 2000 characters' using errcode = '22023';
  end if;
  if new_content is null and not change_components then
    raise exception 'Nothing to change' using errcode = '22023';
  end if;

  select m.* into message
  from public.messages m
  where m.id = target_message_id
  for update;

  if message.id is null
    or message.sender_id <> bot.user_id
    or message.recalled_at is not null
    or message.type <> 'text'
    or not exists (
      select 1
      from public.circle_channels cc
      where cc.id = public.conversation_circle_channel_id(message.conversation_id)
        and cc.circle_id = bot.circle_id
    )
    or not public.user_has_conversation_channel_permission(
      message.conversation_id,
      bot.user_id,
      'view_channel'
    )
  then
    raise exception 'Message not found' using errcode = 'P0002';
  end if;

  if cleaned is not null
    and public.bot_components_automod(message.conversation_id, bot.user_id, cleaned)
  then
    return false;
  end if;

  begin
    update public.messages m
    set
      body = case
        when new_content is not null then trimmed_content
        else m.body
      end,
      edited_at = case
        when new_content is not null and trimmed_content is distinct from m.body then now()
        else m.edited_at
      end,
      components = case
        when change_components then cleaned
        else m.components
      end
    where m.id = message.id;
  exception when sqlstate 'P0001' then
    -- AutoMod blocked the new text (the edit trigger raises).
    if sqlerrm like 'AutoMod blocked%' then
      return false;
    end if;
    raise;
  end;

  return true;
end;
$$;

revoke execute on function public.bot_edit_own_message(public.circle_bots, uuid, text, boolean, jsonb) from public, anon, authenticated;

create or replace function public.bot_api_edit_message(
  bot_token text,
  target_message_id uuid,
  new_content text default null,
  change_components boolean default false,
  new_components jsonb default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
begin
  perform public.count_bot_write(bot);
  perform public.act_as_bot(bot);
  return public.bot_edit_own_message(
    bot,
    target_message_id,
    new_content,
    change_components,
    new_components
  );
end;
$$;

revoke execute on function public.bot_api_edit_message(text, uuid, text, boolean, jsonb) from public, anon, authenticated;
grant execute on function public.bot_api_edit_message(text, uuid, text, boolean, jsonb) to service_role;
