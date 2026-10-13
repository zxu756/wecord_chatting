-- Moderators delete others' messages, like Discord's Manage Messages.
--
-- * recall_message(message_id) still deletes the caller's own messages
--   (webhook messages count as their creator's), and now also lets
--   moderators delete anyone's: members with manage_messages in a circle
--   channel (and its threads), or the owner and admins of a group (and its
--   threads). Direct chats have no moderators. System notices cannot be
--   deleted by anyone; deleting a deleted message changes nothing.
-- * messages.recalled_by records who deleted a message, so clients show
--   "Message deleted by a moderator" when it is not the sender. Clients
--   cannot insert messages with it set.
-- * A moderator deleting someone else's message in a circle channel or its
--   threads is audited as message_delete (target: the message, labelled
--   with its author; changes: the channel and author, never the text).
-- * can_current_user_moderate_messages(conversation_id) tells clients
--   whether to offer "Delete message" on others' messages.

alter table public.messages
  add column if not exists recalled_by uuid
    references public.profiles(id) on delete set null;

-- Same as 202610130024_channel_webhooks, but clients cannot mark a message
-- as deleted by someone.
drop policy if exists messages_insert_member on public.messages;

create policy messages_insert_member
  on public.messages for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and type <> 'system'
    and type <> 'poll'
    and forwarded_from is null
    and webhook_id is null
    and webhook_name is null
    and webhook_avatar_url is null
    and recalled_by is null
    and public.is_current_user_conversation_member(conversation_id)
    and not public.is_current_user_blocked_in_conversation(conversation_id)
  );

-- Whether the caller may delete others' messages in a conversation:
-- manage_messages in circle channels and their threads, the owner or an
-- admin in groups and group threads, nobody in direct chats.
create or replace function public.can_current_user_moderate_messages(
  target_conversation_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  channel_id uuid := public.conversation_circle_channel_id(target_conversation_id);
  group_conversation_id uuid;
begin
  if auth.uid() is null
    or not public.is_current_user_conversation_member(target_conversation_id)
  then
    return false;
  end if;

  if channel_id is not null then
    return public.current_user_has_channel_permission(
      channel_id,
      'manage_messages'
    );
  end if;

  select c.id
  into group_conversation_id
  from public.conversations c
  where c.type = 'group'
    and c.id = coalesce(
      (
        select ct.parent_conversation_id
        from public.conversation_threads ct
        where ct.conversation_id = target_conversation_id
      ),
      target_conversation_id
    );

  return group_conversation_id is not null
    and exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = group_conversation_id
        and cm.user_id = auth.uid()
        and cm.role in ('owner', 'admin')
    );
end;
$$;

-- Same as 202605180004_recall_messages, but moderators may delete others'
-- messages (audited in circle channels), system notices cannot be deleted
-- and recalled_by records who deleted the message.
create or replace function public.recall_message(
  target_message_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target public.messages%rowtype;
  is_own boolean;
  channel public.circle_channels%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select m.*
  into target
  from public.messages m
  where m.id = target_message_id
  for update;

  if target.id is null
    or target.type = 'system'
    or not public.is_current_user_conversation_member(target.conversation_id)
  then
    raise exception 'Message not found or cannot be deleted'
      using errcode = '42501';
  end if;

  -- Webhook messages are sent as their creator, who may delete them.
  is_own := coalesce(target.sender_id = current_user_id, false);

  if not is_own
    and not public.can_current_user_moderate_messages(target.conversation_id)
  then
    raise exception 'Message not found or cannot be deleted'
      using errcode = '42501';
  end if;

  if target.recalled_at is not null then
    return;
  end if;

  update public.messages m
  set
    recalled_at = now(),
    recalled_by = current_user_id
  where m.id = target.id;

  if is_own then
    return;
  end if;

  select cc.*
  into channel
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(target.conversation_id);

  if channel.id is not null then
    perform public.write_circle_audit(
      channel.circle_id,
      'message_delete',
      'message',
      target.id,
      coalesce(
        target.webhook_name,
        public.circle_member_label(channel.circle_id, target.sender_id)
      ),
      jsonb_strip_nulls(jsonb_build_object(
        'channel_id', channel.id,
        'channel_name', channel.name,
        'author_id', case when target.webhook_name is null then target.sender_id end,
        'webhook_id', target.webhook_id
      ))
    );
  end if;
end;
$$;

revoke execute on function public.can_current_user_moderate_messages(uuid) from public;
revoke execute on function public.can_current_user_moderate_messages(uuid) from anon;
revoke execute on function public.recall_message(uuid) from public;
revoke execute on function public.recall_message(uuid) from anon;

grant execute on function public.can_current_user_moderate_messages(uuid) to authenticated;
grant execute on function public.recall_message(uuid) to authenticated;
