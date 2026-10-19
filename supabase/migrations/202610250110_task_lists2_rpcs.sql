-- Task lists 2.0 (D7), part 2: the functions the app calls.
--
-- * set_task_list_fields(list, fields): sets the list's own fields. The
--   values items hold for a field that went away, changed type or lost an
--   option are dropped. Anyone who can edit the list may do it (as for its
--   statuses).
-- * upsert_task_item: based on 202610170062_task_lists.sql (its only
--   definition); everything it did is kept. New in the item patch:
--     custom      {field id: value}, merged field by field; null removes a
--                 value; values that do not fit the list's fields are
--                 ignored (a field may have gone while a patch was queued)
--     parent_id   makes the item a subtask of a task of the same list, or
--                 (null) a task again. One level; at most 50 per task.
--     recurrence  the repeat rule, or null. Needs a due date and a task that
--                 is not a subtask; otherwise it is dropped.

create or replace function public.set_task_list_fields(
  p_list_id uuid,
  p_field_defs jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  l public.task_lists%rowtype;
  cleaned jsonb;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.valid_task_field_defs(p_field_defs) then
    raise exception 'Invalid fields' using errcode = '22023';
  end if;
  select * into l from public.task_lists where id = p_list_id and deleted_at is null for update;
  if l.id is null or not public.is_current_user_conversation_member(l.conversation_id) then
    raise exception 'List not found' using errcode = 'P0002';
  end if;
  if not public.can_current_user_edit_task_list(l.id) then
    raise exception 'You cannot edit this list' using errcode = '42501';
  end if;

  cleaned := public.normalize_task_field_defs(p_field_defs);
  update public.task_lists
  set field_defs = cleaned, updated_at = now()
  where id = l.id
  returning * into l;

  -- Values that no longer fit go; the rest is left alone.
  update public.task_items i
  set custom = public.task_clean_custom(cleaned, i.custom)
  where i.list_id = l.id
    and i.custom <> '{}'::jsonb
    and i.custom is distinct from public.task_clean_custom(cleaned, i.custom);

  return public.task_list_json(l);
end;
$$;

create or replace function public.upsert_task_item(
  p_list_id uuid,
  p_item jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  l public.task_lists%rowtype;
  i public.task_items%rowtype;
  parent public.task_items%rowtype;
  new_item_id uuid;
  new_parent uuid;
  existing boolean;
  new_status text;
  assignee uuid;
  wanted uuid[];
  kind_after text;
  kind_before text;
  entry record;
  field_def jsonb;
  coerced jsonb;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_item) <> 'object' then
    raise exception 'Item must be an object' using errcode = '22023';
  end if;

  select * into l from public.task_lists where id = p_list_id and deleted_at is null for share;
  if l.id is null or not public.is_current_user_conversation_member(l.conversation_id) then
    raise exception 'List not found' using errcode = 'P0002';
  end if;
  if not public.can_current_user_edit_task_list(l.id) then
    raise exception 'You cannot edit this list' using errcode = '42501';
  end if;

  begin
    new_item_id := coalesce((p_item->>'id')::uuid, gen_random_uuid());
  exception when others then
    raise exception 'Invalid item id' using errcode = '22023';
  end;

  select * into i from public.task_items where id = new_item_id for update;
  existing := i.id is not null;
  if existing and i.list_id <> l.id then
    -- Moving between lists of the same conversation.
    if not exists (
      select 1 from public.task_lists o
      where o.id = i.list_id and o.conversation_id = l.conversation_id
    ) then
      raise exception 'Item not found' using errcode = 'P0002';
    end if;
    -- Subtasks stay with their task.
    if i.parent_id is not null or exists (
      select 1 from public.task_items c
      where c.parent_id = i.id and c.deleted_at is null
    ) then
      raise exception 'A task with subtasks, or a subtask, stays in its list'
        using errcode = '22023';
    end if;
    i.custom := public.task_clean_custom(l.field_defs, i.custom);
  end if;
  if existing and i.deleted_at is not null then
    raise exception 'Item was deleted' using errcode = 'P0002';
  end if;

  if not existing then
    if char_length(btrim(coalesce(p_item->>'title', ''))) = 0 then
      raise exception 'Title is required' using errcode = '22023';
    end if;
    if (select count(*) from public.task_items
        where list_id = l.id and deleted_at is null) >= 2000
    then
      raise exception 'This list is full' using errcode = '22023';
    end if;
    i.id := new_item_id;
    i.list_id := l.id;
    i.title := '';
    i.details := '';
    i.status := l.statuses->0->>'id';
    i.priority := 0;
    i.due_has_time := false;
    i.pos := 'V';
    i.custom := '{}'::jsonb;
    i.created_by := uid;
    i.created_at := now();
  end if;

  kind_before := public.task_status_kind(l.statuses, i.status);

  if p_item ? 'title' then
    if char_length(btrim(coalesce(p_item->>'title', ''))) not between 1 and 300 then
      raise exception 'Title must be 1 to 300 characters' using errcode = '22023';
    end if;
    i.title := btrim(p_item->>'title');
  end if;
  if p_item ? 'details' then
    if char_length(coalesce(p_item->>'details', '')) > 5000 then
      raise exception 'Notes are too long' using errcode = '22023';
    end if;
    i.details := coalesce(p_item->>'details', '');
  end if;
  if p_item ? 'status' then
    new_status := p_item->>'status';
    if public.task_status_kind(l.statuses, new_status) is null then
      raise exception 'Unknown status' using errcode = '22023';
    end if;
    i.status := new_status;
  end if;
  if p_item ? 'priority' then
    if coalesce((p_item->>'priority')::integer, 0) not between 0 and 3 then
      raise exception 'Invalid priority' using errcode = '22023';
    end if;
    i.priority := coalesce((p_item->>'priority')::integer, 0);
  end if;
  if p_item ? 'due_at' then
    i.due_at := nullif(p_item->>'due_at', '')::timestamptz;
  end if;
  if p_item ? 'due_has_time' then
    i.due_has_time := coalesce((p_item->>'due_has_time')::boolean, false);
  end if;
  if i.due_at is null then
    i.due_has_time := false;
  end if;
  if p_item ? 'pos' then
    if coalesce(p_item->>'pos', '') !~ '^[0-9A-Za-z]{1,64}$' then
      raise exception 'Invalid position' using errcode = '22023';
    end if;
    i.pos := p_item->>'pos';
  end if;
  if p_item ? 'source_message_id' and not existing then
    i.source_message_id := nullif(p_item->>'source_message_id', '')::uuid;
    if i.source_message_id is not null and not exists (
      select 1 from public.messages m
      where m.id = i.source_message_id and m.conversation_id = l.conversation_id
    ) then
      raise exception 'Message does not belong to this conversation' using errcode = '22023';
    end if;
  end if;

  -- The list's own fields: merged key by key, so two people filling in
  -- different fields never undo each other.
  if p_item ? 'custom' then
    if jsonb_typeof(p_item->'custom') <> 'object' then
      raise exception 'Fields must be an object' using errcode = '22023';
    end if;
    for entry in select e.key, e.value from jsonb_each(p_item->'custom') e loop
      field_def := null;
      select d into field_def
      from jsonb_array_elements(l.field_defs) d
      where d->>'id' = entry.key;
      if field_def is null then
        continue;
      end if;
      if jsonb_typeof(entry.value) = 'null' then
        i.custom := i.custom - entry.key;
        continue;
      end if;
      coerced := public.coerce_task_field_value(field_def, entry.value);
      if coerced is null then
        continue;
      end if;
      if field_def->>'type' = 'person' and not exists (
        select 1 from public.conversation_members cm
        where cm.conversation_id = l.conversation_id
          and cm.user_id = (coerced #>> '{}')::uuid
      ) then
        continue;
      end if;
      i.custom := i.custom || jsonb_build_object(entry.key, coerced);
    end loop;
  end if;

  -- Subtasks: one level, in the same list.
  if p_item ? 'parent_id' then
    begin
      new_parent := nullif(p_item->>'parent_id', '')::uuid;
    exception when others then
      raise exception 'Invalid parent' using errcode = '22023';
    end;
    if new_parent is not null then
      if new_parent = i.id then
        raise exception 'A task cannot be its own subtask' using errcode = '22023';
      end if;
      select * into parent from public.task_items
      where id = new_parent and list_id = l.id and deleted_at is null;
      if parent.id is null then
        raise exception 'Task not found' using errcode = 'P0002';
      end if;
      if parent.parent_id is not null then
        raise exception 'Subtasks cannot have subtasks' using errcode = '22023';
      end if;
      if existing and exists (
        select 1 from public.task_items c
        where c.parent_id = i.id and c.deleted_at is null
      ) then
        raise exception 'A task with subtasks cannot become a subtask' using errcode = '22023';
      end if;
      if i.parent_id is distinct from new_parent and (
        select count(*) from public.task_items c
        where c.parent_id = new_parent and c.deleted_at is null and c.id <> i.id
      ) >= 50 then
        raise exception 'This task has too many subtasks' using errcode = '22023';
      end if;
    end if;
    i.parent_id := new_parent;
  end if;

  if p_item ? 'recurrence' then
    if p_item->'recurrence' is null or jsonb_typeof(p_item->'recurrence') = 'null' then
      i.recurrence := null;
    else
      i.recurrence := public.normalize_task_recurrence(p_item->'recurrence');
    end if;
  end if;
  -- A repeat needs a date to count from, and belongs to a task, not a
  -- subtask.
  if i.due_at is null or i.parent_id is not null then
    i.recurrence := null;
  end if;

  kind_after := public.task_status_kind(l.statuses, i.status);
  if kind_after = 'done' and (not existing or i.completed_at is null) then
    i.completed_at := now();
    i.completed_by := uid;
  elsif kind_after <> 'done' then
    i.completed_at := null;
    i.completed_by := null;
  end if;

  if existing then
    update public.task_items
    set list_id = l.id, title = i.title, details = i.details, status = i.status,
        priority = i.priority, due_at = i.due_at, due_has_time = i.due_has_time,
        pos = i.pos, completed_at = i.completed_at, completed_by = i.completed_by,
        custom = i.custom, parent_id = i.parent_id, recurrence = i.recurrence,
        updated_by = uid, updated_at = now()
    where id = i.id
    returning * into i;
  else
    insert into public.task_items (
      id, list_id, title, details, status, priority, due_at, due_has_time, pos,
      source_message_id, created_by, completed_at, completed_by, updated_by,
      custom, parent_id, recurrence
    )
    values (
      i.id, i.list_id, i.title, i.details, i.status, i.priority, i.due_at,
      i.due_has_time, i.pos, i.source_message_id, uid, i.completed_at,
      i.completed_by, uid, i.custom, i.parent_id, i.recurrence
    )
    returning * into i;
  end if;

  if p_item ? 'assignees' then
    if jsonb_typeof(p_item->'assignees') <> 'array'
      or jsonb_array_length(p_item->'assignees') > 10
    then
      raise exception 'Assignees must be a list of up to 10 people' using errcode = '22023';
    end if;
    select coalesce(array_agg(distinct x::uuid), array[]::uuid[])
    into wanted
    from jsonb_array_elements_text(p_item->'assignees') x;

    foreach assignee in array wanted loop
      if not exists (
        select 1 from public.conversation_members cm
        where cm.conversation_id = l.conversation_id and cm.user_id = assignee
      ) or not public.user_has_conversation_channel_permission(
        l.conversation_id, assignee, 'view_channel'
      ) then
        raise exception 'Only people in this conversation can be assigned'
          using errcode = '22023';
      end if;
    end loop;

    delete from public.task_item_assignees a
    where a.item_id = i.id and not (a.user_id = any (wanted));
    insert into public.task_item_assignees (item_id, list_id, user_id, assigned_by)
    select i.id, i.list_id, w, uid from unnest(wanted) w
    on conflict do nothing;
  end if;
  update public.task_item_assignees
  set list_id = i.list_id
  where item_id = i.id and list_id <> i.list_id;

  update public.task_lists set updated_at = now() where id = l.id;
  return public.task_item_json(i);
end;
$$;

revoke execute on function public.set_task_list_fields(uuid, jsonb) from public, anon;
grant execute on function public.set_task_list_fields(uuid, jsonb) to authenticated;
revoke execute on function public.upsert_task_item(uuid, jsonb) from public, anon;
grant execute on function public.upsert_task_item(uuid, jsonb) to authenticated;
