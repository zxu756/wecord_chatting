-- Who has read a message in a group (A6, part 2 of 3).
--
-- get_message_read_status(target_message_id): for the SENDER of a message in a
-- group of up to 200 members, who has read it, who has not, and who it
-- cannot tell.
--
--   * A member has read the message when the message their last_read points
--     to is as new as it or newer (created_at >=). The data is
--     conversation_members.last_read_message_id; nothing new is stored.
--   * "unknown": the member turned read receipts off
--     (user_privacy_settings.send_read_receipts, 202610220300).
--   * The caller must have receipts on too: with them off the call fails with
--     the message read_receipts_off, as they see nobody else's receipts.
--   * Blocking: someone the sender blocked, or who blocked the sender, is not
--     in the list. Neither is anyone who joined after the message was sent.
--   * Not available (22023) for: direct chats (they show "Read"), circle
--     channels, threads, groups of more than 200 members, the note to self,
--     system notices, webhook posts, deleted, expired or still-under-review
--     messages.
--   * Only the sender may ask (42501); a non-member gets "not found".
--
-- The list is read when someone opens it; nothing pushes a live count.
--
-- message_read_status_rows is the one place that applies these rules, for
-- this function and for remind_unread (202610220320).

create or replace function public.message_read_status_rows(
  target_message_id uuid,
  caller_id uuid
)
returns table (
  user_id uuid,
  status text
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  message public.messages%rowtype;
  conversation_type text;
  member_total integer;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select m.* into message
  from public.messages m
  where m.id = target_message_id;

  if message.id is null or not exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id = message.conversation_id
      and cm.user_id = caller_id
  ) then
    raise exception 'Message not found' using errcode = 'P0002';
  end if;

  if message.sender_id is distinct from caller_id then
    raise exception 'Only the sender can see who read a message'
      using errcode = '42501';
  end if;

  select c.type into conversation_type
  from public.conversations c
  where c.id = message.conversation_id;

  if conversation_type is distinct from 'group'
    or exists (
      select 1
      from public.note_to_self_conversations n
      where n.conversation_id = message.conversation_id
    )
    or message.recalled_at is not null
    or message.type = 'system'
    or message.webhook_id is not null
    or message.review_state is not null
    or (message.expires_at is not null and message.expires_at <= now())
  then
    raise exception 'Read status is not available for this message'
      using errcode = '22023';
  end if;

  select count(*) into member_total
  from public.conversation_members cm
  where cm.conversation_id = message.conversation_id;
  if member_total > 200 then
    raise exception 'Read status is only available in groups of up to 200 members'
      using errcode = '22023';
  end if;

  if not public.read_receipts_enabled(caller_id) then
    raise exception 'read_receipts_off';
  end if;

  return query
  select
    cm.user_id,
    case
      when not public.read_receipts_enabled(cm.user_id) then 'unknown'
      when read_message.created_at is not null
        and read_message.created_at >= message.created_at then 'read'
      else 'unread'
    end
  from public.conversation_members cm
  left join public.messages read_message
    on read_message.id = cm.last_read_message_id
  where cm.conversation_id = message.conversation_id
    and cm.user_id <> caller_id
    and cm.joined_at <= message.created_at
    and not public.are_users_blocked(caller_id, cm.user_id);
end;
$$;

revoke execute on function public.message_read_status_rows(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.message_read_status_rows(uuid, uuid)
  to service_role;

create or replace function public.get_message_read_status(target_message_id uuid)
returns table (
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  status text
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  return query
  select
    r.user_id,
    p.username,
    coalesce(nullif(btrim(ca.alias), ''), p.display_name),
    p.avatar_url,
    r.status
  from public.message_read_status_rows(target_message_id, auth.uid()) r
  join public.profiles p on p.id = r.user_id
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid()
    and ca.friend_id = r.user_id
  order by
    case r.status when 'read' then 0 when 'unread' then 1 else 2 end,
    lower(coalesce(nullif(btrim(ca.alias), ''), p.display_name)),
    r.user_id;
end;
$$;

revoke execute on function public.get_message_read_status(uuid) from public, anon;
grant execute on function public.get_message_read_status(uuid) to authenticated;
