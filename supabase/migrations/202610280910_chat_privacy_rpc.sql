-- Advanced chat privacy (roadmap G6), part 2 of 4: switching it.
--
-- set_chat_restrict_sharing(chat, enabled) -> whether the chat is restricted
-- afterwards.
--
--   * direct chat: either person. It records or withdraws the caller's own
--     request; the chat stays restricted while the other person's request is
--     on (the answer says so, so the app can tell the caller).
--   * group: the owner and the admins; one switch for the group.
--   * not the note to self, not a circle channel, not a thread (a thread
--     follows its chat), not while the caller is blocked in the chat.
--
-- Every real change is announced to the chat with a system line, like the
-- disappearing messages timer: {kind: 'chat_privacy', enabled, restricted,
-- actor_id, actor_name}. Asking for what already is changes nothing and says
-- nothing.

create or replace function public.set_chat_restrict_sharing(
  target_conversation_id uuid,
  enabled boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  conversation public.conversations%rowtype;
  requests uuid[];
  now_restricted boolean;
  actor_name text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if enabled is null then
    raise exception 'Choose on or off' using errcode = '22023';
  end if;

  select c.*
  into conversation
  from public.conversations c
  where c.id = target_conversation_id
    and c.type in ('direct', 'group')
  for update;

  if conversation.id is null
    or not public.is_current_user_conversation_member(conversation.id)
  then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.note_to_self_conversations n
    where n.conversation_id = conversation.id
  ) then
    raise exception 'Your note to self cannot be restricted'
      using errcode = '22023';
  end if;

  if conversation.type = 'group' and not exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id = conversation.id
      and cm.user_id = current_user_id
      and cm.role in ('owner', 'admin')
  ) then
    raise exception 'Only the owner and admins can change advanced chat privacy'
      using errcode = '42501';
  end if;

  if public.is_current_user_blocked_in_conversation(conversation.id) then
    raise exception 'Cannot change this conversation' using errcode = '42501';
  end if;

  if conversation.type = 'direct' then
    requests := case
      when enabled then array(
        select distinct x
        from unnest(conversation.restrict_sharing_by || current_user_id) x
      )
      else array_remove(conversation.restrict_sharing_by, current_user_id)
    end;
    now_restricted := cardinality(requests) > 0;
  else
    requests := case
      when enabled then array[current_user_id]
      else '{}'::uuid[]
    end;
    now_restricted := enabled;
  end if;

  if requests is not distinct from conversation.restrict_sharing_by
    and now_restricted = conversation.restrict_sharing
  then
    return conversation.restrict_sharing;
  end if;

  update public.conversations c
  set restrict_sharing = now_restricted,
      restrict_sharing_by = requests
  where c.id = conversation.id;

  select nullif(btrim(p.display_name), '')
  into actor_name
  from public.profiles p
  where p.id = current_user_id;

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    attachment
  )
  values (
    conversation.id,
    current_user_id,
    'system',
    coalesce(actor_name, 'Someone') || case
      when enabled then ' turned on advanced chat privacy.'
      else ' turned off advanced chat privacy.'
    end,
    jsonb_build_object(
      'kind', 'chat_privacy',
      'enabled', enabled,
      'restricted', now_restricted,
      'actor_id', current_user_id,
      'actor_name', coalesce(actor_name, 'Someone')
    )
  );

  return now_restricted;
end;
$$;

revoke execute on function public.set_chat_restrict_sharing(uuid, boolean)
  from public, anon;
grant execute on function public.set_chat_restrict_sharing(uuid, boolean)
  to authenticated;
