revoke execute on function public.are_users_blocked(uuid, uuid) from public;
revoke execute on function public.are_users_blocked(uuid, uuid) from anon;
revoke execute on function public.are_users_blocked(uuid, uuid) from authenticated;

create or replace function public.is_current_user_blocked_in_conversation(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.conversations c
    join public.conversation_members current_member
      on current_member.conversation_id = c.id
      and current_member.user_id = auth.uid()
    join public.conversation_members other_member
      on other_member.conversation_id = c.id
      and other_member.user_id <> auth.uid()
    where c.id = target_conversation_id
      and c.type = 'direct'
      and public.are_users_blocked(auth.uid(), other_member.user_id)
  );
$$;

drop policy if exists messages_insert_member on public.messages;

create policy messages_insert_member
  on public.messages for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and forwarded_from is null
    and public.is_current_user_conversation_member(conversation_id)
    and not public.is_current_user_blocked_in_conversation(conversation_id)
  );

create or replace function public.send_friend_request(target_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  created_request_id uuid;
  existing_request public.friend_requests%rowtype;
  target_policy text;
  low_user_id uuid;
  high_user_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if target_user_id is null or target_user_id = current_user_id then
    raise exception 'Cannot send a friend request to this user'
      using errcode = '22023';
  end if;

  if public.are_users_blocked(current_user_id, target_user_id) then
    raise exception 'Cannot send a friend request to this user'
      using errcode = '42501';
  end if;

  select coalesce(ups.friend_request_policy, 'everyone')
  into target_policy
  from public.profiles p
  left join public.user_privacy_settings ups on ups.user_id = p.id
  where p.id = target_user_id;

  if target_policy is null then
    raise exception 'Cannot send a friend request to this user'
      using errcode = '42501';
  end if;

  if target_policy = 'none' then
    raise exception 'This user is not accepting friend requests'
      using errcode = '42501';
  end if;

  if target_policy = 'friends_of_friends' and not exists (
    select 1
    from public.friendships requester_friendship
    join public.friendships target_friendship
      on (
        case
          when requester_friendship.user_low_id = current_user_id
            then requester_friendship.user_high_id
          else requester_friendship.user_low_id
        end
      ) = (
        case
          when target_friendship.user_low_id = target_user_id
            then target_friendship.user_high_id
          else target_friendship.user_low_id
        end
      )
    where current_user_id in (
      requester_friendship.user_low_id,
      requester_friendship.user_high_id
    )
      and target_user_id in (
        target_friendship.user_low_id,
        target_friendship.user_high_id
      )
  ) then
    raise exception 'This user only accepts friend requests through mutual friends'
      using errcode = '42501';
  end if;

  low_user_id = least(current_user_id, target_user_id);
  high_user_id = greatest(current_user_id, target_user_id);

  if exists (
    select 1
    from public.friendships
    where user_low_id = low_user_id
      and user_high_id = high_user_id
  ) then
    raise exception 'Users are already friends' using errcode = '22023';
  end if;

  select *
  into existing_request
  from public.friend_requests
  where requester_id = target_user_id
    and receiver_id = current_user_id
    and status = 'pending'
  limit 1;

  if existing_request.id is not null then
    raise exception 'This user has already sent you a friend request'
      using errcode = '22023';
  end if;

  insert into public.friend_requests (requester_id, receiver_id)
  values (current_user_id, target_user_id)
  on conflict (requester_id, receiver_id) do update
  set
    status = 'pending',
    updated_at = now()
  where public.friend_requests.status in ('rejected', 'cancelled')
  returning id into created_request_id;

  if created_request_id is null then
    raise exception 'Friend request already exists' using errcode = '23505';
  end if;

  return created_request_id;
end;
$$;

create or replace function public.send_text_message(
  target_conversation_id uuid,
  body text,
  reply_to_message_id uuid default null,
  reply_preview jsonb default null,
  mentions jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_body text := trim(coalesce(body, ''));
  created_message_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
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

  if exists (
    select 1
    from jsonb_array_elements(coalesce(mentions, '[]'::jsonb)) mention
    where (mention->>'user_id') is not null
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

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    reply_to_message_id,
    reply_preview,
    mentions
  )
  values (
    target_conversation_id,
    current_user_id,
    'text',
    trimmed_body,
    send_text_message.reply_to_message_id,
    send_text_message.reply_preview,
    coalesce(mentions, '[]'::jsonb)
  )
  returning id into created_message_id;

  insert into public.message_mentions (
    message_id,
    conversation_id,
    user_id,
    kind
  )
  select
    created_message_id,
    target_conversation_id,
    (mention->>'user_id')::uuid,
    coalesce(nullif(mention->>'kind', ''), 'user')
  from jsonb_array_elements(coalesce(mentions, '[]'::jsonb)) mention
  where (mention->>'user_id') is not null
  on conflict do nothing;

  return created_message_id;
end;
$$;

create or replace function public.forward_message(
  source_message_id uuid,
  target_conversation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  source_message public.messages%rowtype;
  source_sender_name text;
  created_message_id uuid;
begin
  select *
  into source_message
  from public.messages
  where id = source_message_id
    and recalled_at is null;

  if source_message.id is null
    or not public.is_current_user_conversation_member(source_message.conversation_id)
    or not public.is_current_user_conversation_member(target_conversation_id)
    or public.is_current_user_blocked_in_conversation(target_conversation_id)
  then
    raise exception 'Message cannot be forwarded' using errcode = '42501';
  end if;

  select display_name
  into source_sender_name
  from public.profiles
  where id = source_message.sender_id;

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    attachment,
    forwarded_from
  )
  values (
    target_conversation_id,
    auth.uid(),
    source_message.type,
    source_message.body,
    source_message.attachment,
    jsonb_build_object(
      'message_id', source_message.id,
      'sender_id', source_message.sender_id,
      'sender_name', source_sender_name,
      'type', source_message.type,
      'body', source_message.body,
      'source_attachment_bucket', source_message.attachment->>'bucket',
      'source_attachment_path', source_message.attachment->>'path'
    )
  )
  returning id into created_message_id;

  return created_message_id;
end;
$$;
