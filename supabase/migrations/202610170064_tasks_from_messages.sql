-- Tasks and chat: making a task from a message, task and list cards, and
-- the tasks a conversation made from its messages.
--
-- * create_task_from_message: the message menu's "Create task". The item
--   keeps source_message_id, so the task links back to the message and the
--   message can show its task. The conversation's first list is used (one
--   called "Tasks" is made when there is none) unless a list is named.
-- * share_task_item / share_task_list: a card in the chat, like a shared
--   note: a text message whose body is "<icon> <title>" and whose attachment
--   is {kind: 'task', item_id, list_id, title} or {kind: 'list', list_id,
--   title, icon}. The card shows the live state; its check box calls
--   set_task_item_done.
-- * list_message_tasks: the items of a conversation made from messages
--   (newest 500), so messages can show "Task: ..." with a check box.

create or replace function public.create_task_from_message(
  p_message_id uuid,
  p_list_id uuid default null,
  p_title text default null,
  p_item_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  m public.messages%rowtype;
  target_list uuid := p_list_id;
  item_title text;
  existing public.task_items%rowtype;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into m from public.messages where id = p_message_id;
  if m.id is null or not public.is_current_user_conversation_member(m.conversation_id) then
    raise exception 'Message not found' using errcode = 'P0002';
  end if;
  if m.recalled_at is not null or m.type = 'system' then
    raise exception 'This message cannot become a task' using errcode = '22023';
  end if;
  if not public.can_current_user_write_docs(m.conversation_id) then
    raise exception 'You cannot create tasks here' using errcode = '42501';
  end if;

  -- Sent before (the answer got lost).
  if p_item_id is not null then
    select * into existing from public.task_items where id = p_item_id;
    if existing.id is not null then
      return public.task_item_json(existing);
    end if;
  end if;

  if target_list is null then
    select l.id into target_list
    from public.task_lists l
    where l.conversation_id = m.conversation_id and l.deleted_at is null
    order by l.created_at, l.id
    limit 1;
    if target_list is null then
      target_list := (
        public.create_task_list(m.conversation_id, 'Tasks', null)->>'id'
      )::uuid;
    end if;
  elsif not exists (
    select 1 from public.task_lists l
    where l.id = target_list and l.conversation_id = m.conversation_id and l.deleted_at is null
  ) then
    raise exception 'List not found' using errcode = 'P0002';
  end if;

  item_title := nullif(btrim(coalesce(p_title, '')), '');
  if item_title is null then
    item_title := nullif(btrim(split_part(btrim(m.body), E'\n', 1)), '');
  end if;
  if item_title is null then
    item_title := case m.type
      when 'image' then 'Picture'
      when 'voice' then 'Voice message'
      when 'file' then coalesce(nullif(m.attachment->>'name', ''), 'File')
      when 'poll' then coalesce(nullif(m.attachment->>'question', ''), 'Poll')
      else 'Task from a message'
    end;
  end if;
  item_title := left(item_title, 300);

  return public.upsert_task_item(
    target_list,
    jsonb_build_object(
      'id', coalesce(p_item_id, gen_random_uuid()),
      'title', item_title,
      'source_message_id', m.id
    )
  );
end;
$$;

create or replace function public.share_task_item(
  p_item_id uuid,
  p_conversation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  i public.task_items%rowtype;
  l public.task_lists%rowtype;
  message_id uuid;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into i from public.task_items where id = p_item_id and deleted_at is null;
  select * into l from public.task_lists where id = i.list_id and deleted_at is null;
  if i.id is null or l.id is null
    or not public.is_current_user_conversation_member(l.conversation_id)
  then
    raise exception 'Task not found' using errcode = 'P0002';
  end if;
  if p_conversation_id is distinct from l.conversation_id and not exists (
    select 1
    from public.conversation_threads t
    where t.conversation_id = p_conversation_id
      and t.parent_conversation_id = l.conversation_id
  ) then
    raise exception 'A task can only be shared where it lives' using errcode = '22023';
  end if;
  if not public.can_current_user_write_docs(p_conversation_id)
    or public.is_current_user_blocked_in_conversation(p_conversation_id)
  then
    raise exception 'You cannot send messages here' using errcode = '42501';
  end if;

  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (
    p_conversation_id,
    uid,
    'text',
    E'☑ ' || left(i.title, 300),
    jsonb_build_object(
      'kind', 'task',
      'item_id', i.id,
      'list_id', l.id,
      'title', left(i.title, 300)
    )
  )
  returning id into message_id;
  return message_id;
end;
$$;

create or replace function public.share_task_list(
  p_list_id uuid,
  p_conversation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  l public.task_lists%rowtype;
  message_id uuid;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into l from public.task_lists where id = p_list_id and deleted_at is null;
  if l.id is null or not public.is_current_user_conversation_member(l.conversation_id) then
    raise exception 'List not found' using errcode = 'P0002';
  end if;
  if p_conversation_id is distinct from l.conversation_id and not exists (
    select 1
    from public.conversation_threads t
    where t.conversation_id = p_conversation_id
      and t.parent_conversation_id = l.conversation_id
  ) then
    raise exception 'A list can only be shared where it lives' using errcode = '22023';
  end if;
  if not public.can_current_user_write_docs(p_conversation_id)
    or public.is_current_user_blocked_in_conversation(p_conversation_id)
  then
    raise exception 'You cannot send messages here' using errcode = '42501';
  end if;

  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (
    p_conversation_id,
    uid,
    'text',
    l.icon || ' ' || coalesce(nullif(btrim(l.title), ''), 'Untitled list'),
    jsonb_build_object(
      'kind', 'list',
      'list_id', l.id,
      'title', l.title,
      'icon', l.icon
    )
  )
  returning id into message_id;
  return message_id;
end;
$$;

create or replace function public.list_message_tasks(p_conversation_id uuid)
returns table (
  message_id uuid,
  item_id uuid,
  list_id uuid,
  title text,
  is_done boolean
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
  if not public.is_current_user_conversation_member(p_conversation_id) then
    raise exception 'Conversation not found' using errcode = '42501';
  end if;
  return query
  select i.source_message_id, i.id, i.list_id, i.title, i.completed_at is not null
  from public.task_items i
  join public.task_lists l on l.id = i.list_id and l.deleted_at is null
  where l.conversation_id = p_conversation_id
    and i.deleted_at is null
    and i.source_message_id is not null
  order by i.created_at desc, i.id
  limit 500;
end;
$$;

revoke execute on function public.create_task_from_message(uuid, uuid, text, uuid) from public, anon;
revoke execute on function public.share_task_item(uuid, uuid) from public, anon;
revoke execute on function public.share_task_list(uuid, uuid) from public, anon;
revoke execute on function public.list_message_tasks(uuid) from public, anon;
grant execute on function public.create_task_from_message(uuid, uuid, text, uuid) to authenticated;
grant execute on function public.share_task_item(uuid, uuid) to authenticated;
grant execute on function public.share_task_list(uuid, uuid) to authenticated;
grant execute on function public.list_message_tasks(uuid) to authenticated;

-- One task with its list, for the card in the chat.
create or replace function public.get_task_item(p_item_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  i public.task_items%rowtype;
  l public.task_lists%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into i from public.task_items where id = p_item_id and deleted_at is null;
  select * into l from public.task_lists where id = i.list_id and deleted_at is null;
  if i.id is null or l.id is null
    or not public.is_current_user_conversation_member(l.conversation_id)
  then
    raise exception 'Task not found' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'list', public.task_list_json(l),
    'items', jsonb_build_array(public.task_item_json(i))
  );
end;
$$;

revoke execute on function public.get_task_item(uuid) from public, anon;
grant execute on function public.get_task_item(uuid) to authenticated;
