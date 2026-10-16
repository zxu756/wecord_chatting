-- Sending messages again without doubling them.
--
-- Messages written while offline (or while a send keeps failing) wait in
-- the client's outbox and are sent again when the connection returns. A
-- send whose answer was lost may already have gone through, so each
-- message carries a client_id the client generates once, and the server
-- keeps one message per (sender, client_id).
--
-- * messages.client_id: the sender's id for the message, null for
--   messages sent without one (older clients, forwards, polls, bots).
-- * messages_sender_client_id_key: unique per sender (nulls do not
--   clash). A direct insert of a message already stored fails with
--   SQLSTATE 23505 on this constraint; the client then reads the stored
--   message's id.
-- * send_text_message takes client_id: when the current user already sent
--   a message with it, that message's id is returned and nothing new is
--   stored. Otherwise the same as 202610160020_automod.

alter table public.messages
  add column if not exists client_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'messages_sender_client_id_key'
      and conrelid = 'public.messages'::regclass
  ) then
    alter table public.messages
      add constraint messages_sender_client_id_key unique (sender_id, client_id);
  end if;
end;
$$;

drop function if exists public.send_text_message(uuid, text, uuid, jsonb, jsonb);

create or replace function public.send_text_message(
  target_conversation_id uuid,
  body text,
  reply_to_message_id uuid default null,
  reply_preview jsonb default null,
  mentions jsonb default '[]'::jsonb,
  client_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_body text := trim(coalesce(body, ''));
  visible_mentions jsonb;
  created_message_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  -- Sent before (the answer got lost): the same message again.
  if send_text_message.client_id is not null then
    select m.id
    into created_message_id
    from public.messages m
    where m.sender_id = current_user_id
      and m.client_id = send_text_message.client_id;
    if created_message_id is not null then
      return created_message_id;
    end if;
  end if;

  if char_length(trimmed_body) = 0 then
    raise exception 'Message body is required' using errcode = '22023';
  end if;

  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Cannot send messages in this conversation'
      using errcode = '42501';
  end if;

  if send_text_message.reply_to_message_id is not null and not exists (
    select 1
    from public.messages m
    where m.id = send_text_message.reply_to_message_id
      and m.conversation_id = target_conversation_id
  ) then
    raise exception 'Reply message does not belong to conversation'
      using errcode = '22023';
  end if;

  if jsonb_typeof(coalesce(mentions, '[]'::jsonb)) <> 'array' then
    raise exception 'mentions must be an array' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(mentions, '[]'::jsonb)) mention
    where coalesce(nullif(mention->>'kind', ''), 'user') in ('user', 'all')
      and (mention->>'user_id') is not null
      and not exists (
        select 1
        from public.conversation_members cm
        where cm.conversation_id = target_conversation_id
          and cm.user_id = (mention->>'user_id')::uuid
      )
  ) then
    raise exception 'mentioned users must be conversation members'
      using errcode = '42501';
  end if;

  visible_mentions := public.resolve_message_mentions(
    target_conversation_id,
    current_user_id,
    mentions
  );

  -- AutoMod (202610160020): a blocked message is dropped, not raised.
  perform set_config('wecord.automod_soft', 'on', true);

  begin
    insert into public.messages (
      conversation_id,
      sender_id,
      type,
      body,
      reply_to_message_id,
      reply_preview,
      mentions,
      client_id
    )
    values (
      target_conversation_id,
      current_user_id,
      'text',
      trimmed_body,
      send_text_message.reply_to_message_id,
      send_text_message.reply_preview,
      visible_mentions,
      send_text_message.client_id
    )
    returning id into created_message_id;
  exception when unique_violation then
    -- The same send, stored by a retry that raced this one.
    perform set_config('wecord.automod_soft', 'off', true);
    select m.id
    into created_message_id
    from public.messages m
    where m.sender_id = current_user_id
      and m.client_id = send_text_message.client_id;
    if created_message_id is null then
      raise;
    end if;
    return created_message_id;
  end;

  perform set_config('wecord.automod_soft', 'off', true);

  if created_message_id is null then
    return null;
  end if;

  perform public.record_message_mentions(
    created_message_id,
    target_conversation_id,
    current_user_id,
    mentions,
    visible_mentions
  );

  return created_message_id;
end;
$$;

revoke execute on function public.send_text_message(uuid, text, uuid, jsonb, jsonb, uuid) from public;
revoke execute on function public.send_text_message(uuid, text, uuid, jsonb, jsonb, uuid) from anon;
grant execute on function public.send_text_message(uuid, text, uuid, jsonb, jsonb, uuid) to authenticated;
