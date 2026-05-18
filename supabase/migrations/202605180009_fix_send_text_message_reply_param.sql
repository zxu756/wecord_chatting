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
    reply_preview,
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
