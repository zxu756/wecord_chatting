-- Task lists 2.0 (D7), part 3: triggers.
--
-- * Finishing a repeating task makes the next one. A trigger, not the app,
--   so it happens however the task was finished (the check box, a card in
--   the chat, a board drag, a patch that was queued offline). The new task
--   copies the old one (title, notes, priority, fields, people, subtasks as
--   open again), lands in the list's first 'todo' status and is due on the
--   first date of the rule after now (and after the old date), so a task
--   finished weeks late does not make a pile of overdue copies. People are
--   not notified of the copy as an assignment; the usual due reminders
--   cover it. A task makes its next one once (next_item_id).
-- * Deleting a task deletes its subtasks; a deleted task forgets its fields
--   and repeat rule.
-- * Closing an account removes the person from the person fields of tasks.
--   Their tasks and what they wrote stay as the rest of the list.

create or replace function public.spawn_next_recurring_task()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  l public.task_lists%rowtype;
  next_id uuid := gen_random_uuid();
  next_due timestamptz;
  zone text;
  candidate text;
  rule jsonb := new.recurrence;
  todo_status text;
  local_day integer;
  child record;
begin
  select * into l from public.task_lists where id = new.list_id and deleted_at is null;
  if l.id is null then
    return new;
  end if;
  -- Only the first finish counts.
  update public.task_items set next_item_id = next_id
  where id = new.id and next_item_id is null;
  if not found then
    return new;
  end if;
  if (select count(*) from public.task_items
      where list_id = l.id and deleted_at is null) >= 2000 then
    return new;
  end if;

  select e->>'id' into todo_status
  from jsonb_array_elements(l.statuses) e
  where e->>'kind' = 'todo'
  limit 1;
  if todo_status is null then
    return new;
  end if;

  -- The local day: the rule's own zone, else the zone of the person who
  -- finished it when it has the rule's offset on that date, else the offset.
  zone := nullif(rule->>'tz', '');
  if zone is not null and not exists (select 1 from pg_timezone_names where name = zone) then
    zone := null;
  end if;
  if zone is null then
    candidate := public.notification_time_zone(coalesce(new.completed_by, new.created_by));
    if candidate is not null and exists (select 1 from pg_timezone_names where name = candidate) then
      if rule->>'tz_offset' is null
        or round(extract(epoch from (
          (new.due_at at time zone candidate) - (new.due_at at time zone 'UTC')
        )) / 60) = (rule->>'tz_offset')::numeric
      then
        zone := candidate;
      end if;
    end if;
  end if;

  if rule->>'freq' = 'monthly' and rule->>'anchor_day' is null then
    if zone is not null then
      local_day := extract(day from (new.due_at at time zone zone))::integer;
    else
      local_day := extract(day from (
        (new.due_at at time zone 'UTC') + make_interval(mins => coalesce((rule->>'tz_offset')::integer, 0))
      ))::integer;
    end if;
    rule := rule || jsonb_build_object('anchor_day', local_day);
  end if;

  next_due := public.task_next_due(
    new.due_at,
    new.due_has_time,
    rule,
    greatest(now(), new.due_at),
    zone
  );
  if next_due is null then
    return new;
  end if;

  insert into public.task_items (
    id, list_id, title, details, status, priority, due_at, due_has_time, pos,
    created_by, updated_by, custom, recurrence
  )
  values (
    next_id, new.list_id, new.title, new.details, todo_status, new.priority,
    next_due, new.due_has_time, new.pos, new.created_by,
    coalesce(new.completed_by, new.created_by), new.custom, rule
  );

  -- Assigned again, without telling anyone it happened.
  insert into public.task_item_assignees (item_id, list_id, user_id, assigned_by)
  select next_id, a.list_id, a.user_id, null
  from public.task_item_assignees a
  where a.item_id = new.id
  on conflict do nothing;

  -- The steps start over.
  for child in
    select * from public.task_items c
    where c.parent_id = new.id and c.deleted_at is null
    order by c.pos, c.id
  loop
    insert into public.task_items (
      list_id, title, details, status, priority, due_at, due_has_time, pos,
      created_by, updated_by, custom, parent_id
    )
    values (
      child.list_id, child.title, child.details, todo_status, child.priority,
      case when child.due_at is null then null
           else child.due_at + (next_due - new.due_at) end,
      child.due_has_time and child.due_at is not null, child.pos,
      child.created_by, coalesce(new.completed_by, new.created_by),
      child.custom, next_id
    );
  end loop;

  update public.task_lists set updated_at = now() where id = l.id;
  return new;
end;
$$;

revoke execute on function public.spawn_next_recurring_task() from public, anon, authenticated;

drop trigger if exists task_items_spawn_next_insert on public.task_items;
create trigger task_items_spawn_next_insert
  after insert on public.task_items
  for each row
  when (
    new.recurrence is not null and new.completed_at is not null
    and new.deleted_at is null and new.parent_id is null
    and new.due_at is not null and new.next_item_id is null
  )
  execute function public.spawn_next_recurring_task();

drop trigger if exists task_items_spawn_next_update on public.task_items;
create trigger task_items_spawn_next_update
  after update of completed_at on public.task_items
  for each row
  when (
    new.recurrence is not null and new.completed_at is not null
    and old.completed_at is null
    and new.deleted_at is null and new.parent_id is null
    and new.due_at is not null and new.next_item_id is null
  )
  execute function public.spawn_next_recurring_task();

-- A deleted task takes its subtasks along and forgets its fields and rule.
create or replace function public.task_item_deleted_cleanup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.custom := '{}'::jsonb;
  new.recurrence := null;
  return new;
end;
$$;

create or replace function public.task_item_deleted_subtasks()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.task_items
  set deleted_at = coalesce(deleted_at, now()),
      updated_by = new.updated_by,
      updated_at = now()
  where parent_id = new.id and deleted_at is null;
  return new;
end;
$$;

revoke execute on function public.task_item_deleted_cleanup() from public, anon, authenticated;
revoke execute on function public.task_item_deleted_subtasks() from public, anon, authenticated;

drop trigger if exists task_items_deleted_cleanup on public.task_items;
create trigger task_items_deleted_cleanup
  before update of deleted_at on public.task_items
  for each row
  when (new.deleted_at is not null and old.deleted_at is null)
  execute function public.task_item_deleted_cleanup();

drop trigger if exists task_items_deleted_subtasks on public.task_items;
create trigger task_items_deleted_subtasks
  after update of deleted_at on public.task_items
  for each row
  when (new.deleted_at is not null and old.deleted_at is null)
  execute function public.task_item_deleted_subtasks();

-- Closing an account: the person leaves the person fields.
create or replace function public.erase_task_fields_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.task_items i
  set custom = coalesce((
    select jsonb_object_agg(e.key, e.value)
    from jsonb_each(i.custom) e
    where not (jsonb_typeof(e.value) = 'string' and e.value #>> '{}' = new.id::text)
  ), '{}'::jsonb)
  where i.list_id in (
    select tl.id from public.task_lists tl
    where tl.field_defs @> '[{"type": "person"}]'::jsonb
  )
    and i.custom::text like '%' || new.id::text || '%';
  return new;
end;
$$;

revoke execute on function public.erase_task_fields_of_deleted_account() from public, anon, authenticated;

drop trigger if exists profiles_erase_task_fields on public.profiles;
create trigger profiles_erase_task_fields
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_task_fields_of_deleted_account();
