-- Lists: task lists that live in a conversation (a circle channel, a group
-- or a direct chat).
--
-- * task_lists: a title, an emoji icon and the list's STATUSES, an ordered
--   array of {id, name, kind} where kind is 'todo', 'active' or 'done'. New
--   lists start with To do / In progress / Done and can use their own.
--   default_view ('list' or 'board') is how it opens.
-- * task_items: title, details, status (one of the list's status ids),
--   priority (0 none, 1 low, 2 medium, 3 high), due date (due_at, with
--   due_has_time false for "all day"), a fractional ordering key (pos) that
--   orders an item among the others of its status (board columns, grouped
--   lists), and the message it was made from (source_message_id).
-- * task_item_assignees: who the item is assigned to (up to 10 members).
--
-- Permissions mirror notes: whoever can see the conversation sees its lists;
-- whoever can send messages there creates, edits, moves and checks off
-- items; the author of a list or a manager (manage_messages, or a group
-- admin) deletes it. Tables are read-only to clients (so realtime can
-- stream them); all changes go through the functions below.
--
-- An item change is a PATCH: upsert_task_item only touches the fields it is
-- given, so two people changing different fields of an item (one moves it
-- to Done, another changes the due date) never undo each other; the same
-- field is last-writer-wins. Dragging an item to a column sets status and
-- pos in one call.

create table if not exists public.task_lists (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  title text not null default '',
  icon text not null default E'✅',
  statuses jsonb not null default
    '[{"id":"todo","name":"To do","kind":"todo"},{"id":"doing","name":"In progress","kind":"active"},{"id":"done","name":"Done","kind":"done"}]'::jsonb,
  default_view text not null default 'list',
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint task_lists_title_length check (char_length(title) <= 120),
  constraint task_lists_icon_length check (char_length(icon) between 1 and 16),
  constraint task_lists_view check (default_view in ('list', 'board'))
);

create index if not exists task_lists_conversation_idx
  on public.task_lists (conversation_id, created_at)
  where deleted_at is null;

create table if not exists public.task_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.task_lists(id) on delete cascade,
  title text not null,
  details text not null default '',
  status text not null,
  priority smallint not null default 0,
  due_at timestamptz,
  due_has_time boolean not null default false,
  pos text not null default 'V' collate "C",
  source_message_id uuid references public.messages(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  completed_by uuid references public.profiles(id) on delete set null,
  deleted_at timestamptz,
  constraint task_items_title_length check (char_length(btrim(title)) between 1 and 300),
  constraint task_items_details_length check (char_length(details) <= 5000),
  constraint task_items_priority check (priority between 0 and 3),
  constraint task_items_pos check (pos ~ '^[0-9A-Za-z]{1,64}$')
);

create index if not exists task_items_list_idx
  on public.task_items (list_id, status, pos, id)
  where deleted_at is null;
create index if not exists task_items_due_idx
  on public.task_items (due_at)
  where due_at is not null and completed_at is null and deleted_at is null;
create index if not exists task_items_source_message_idx
  on public.task_items (source_message_id)
  where source_message_id is not null;

create table if not exists public.task_item_assignees (
  item_id uuid not null references public.task_items(id) on delete cascade,
  -- The item's list, so realtime can filter on it.
  list_id uuid not null references public.task_lists(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  assigned_by uuid references public.profiles(id) on delete set null,
  assigned_at timestamptz not null default now(),
  primary key (item_id, user_id)
);

create index if not exists task_item_assignees_user_idx
  on public.task_item_assignees (user_id, item_id);

alter table public.task_lists enable row level security;
alter table public.task_items enable row level security;
alter table public.task_item_assignees enable row level security;

revoke all on public.task_lists from anon, authenticated;
revoke all on public.task_items from anon, authenticated;
revoke all on public.task_item_assignees from anon, authenticated;
grant select on public.task_lists to authenticated;
grant select on public.task_items to authenticated;
grant select on public.task_item_assignees to authenticated;

create or replace function public.can_current_user_view_task_list(target_list_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.task_lists l
      where l.id = target_list_id
        and public.is_current_user_conversation_member(l.conversation_id)
    );
$$;

create or replace function public.can_current_user_edit_task_list(target_list_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.task_lists l
      where l.id = target_list_id
        and l.deleted_at is null
        and public.can_current_user_write_docs(l.conversation_id)
    );
$$;

create or replace function public.can_current_user_manage_task_list(target_list_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.task_lists l
      where l.id = target_list_id
        and l.deleted_at is null
        and public.is_current_user_conversation_member(l.conversation_id)
        and (
          l.created_by = auth.uid()
          or public.can_current_user_moderate_messages(l.conversation_id)
        )
    );
$$;

drop policy if exists task_lists_select_member on public.task_lists;
create policy task_lists_select_member
  on public.task_lists for select
  to authenticated
  using (public.is_current_user_conversation_member(conversation_id));

drop policy if exists task_items_select_member on public.task_items;
create policy task_items_select_member
  on public.task_items for select
  to authenticated
  using (public.can_current_user_view_task_list(list_id));

drop policy if exists task_item_assignees_select_member on public.task_item_assignees;
create policy task_item_assignees_select_member
  on public.task_item_assignees for select
  to authenticated
  using (public.can_current_user_view_task_list(list_id));

revoke execute on function public.can_current_user_view_task_list(uuid) from public, anon;
revoke execute on function public.can_current_user_edit_task_list(uuid) from public, anon;
revoke execute on function public.can_current_user_manage_task_list(uuid) from public, anon;
grant execute on function public.can_current_user_view_task_list(uuid) to authenticated;
grant execute on function public.can_current_user_edit_task_list(uuid) to authenticated;
grant execute on function public.can_current_user_manage_task_list(uuid) to authenticated;

-- Whether [value] is a usable status array: 1 to 12 entries of
-- {id: [a-z0-9_-]{1,32}, name: 1-40 chars, kind: todo | active | done} with
-- distinct ids, and at least one 'todo' and one 'done'.
create or replace function public.valid_task_statuses(value jsonb)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  entry jsonb;
  ids text[] := array[]::text[];
  todo_count integer := 0;
  done_count integer := 0;
begin
  if value is null or jsonb_typeof(value) <> 'array'
    or jsonb_array_length(value) not between 1 and 12
  then
    return false;
  end if;
  for entry in select * from jsonb_array_elements(value) loop
    if jsonb_typeof(entry) <> 'object'
      or coalesce(entry->>'id', '') !~ '^[a-z0-9_-]{1,32}$'
      or char_length(btrim(coalesce(entry->>'name', ''))) not between 1 and 40
      or coalesce(entry->>'kind', '') not in ('todo', 'active', 'done')
      or (entry->>'id') = any (ids)
    then
      return false;
    end if;
    ids := ids || (entry->>'id');
    if entry->>'kind' = 'todo' then todo_count := todo_count + 1; end if;
    if entry->>'kind' = 'done' then done_count := done_count + 1; end if;
  end loop;
  return todo_count >= 1 and done_count >= 1;
end;
$$;

-- The kind ('todo' | 'active' | 'done') of status [status_id] in [statuses].
create or replace function public.task_status_kind(statuses jsonb, status_id text)
returns text
language sql
immutable
set search_path = public
as $$
  select e->>'kind'
  from jsonb_array_elements(statuses) e
  where e->>'id' = status_id
  limit 1;
$$;

create or replace function public.task_list_json(l public.task_lists)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', l.id,
    'conversation_id', l.conversation_id,
    'title', l.title,
    'icon', l.icon,
    'statuses', l.statuses,
    'default_view', l.default_view,
    'created_by', l.created_by,
    'created_at', l.created_at,
    'updated_at', l.updated_at,
    'can_edit', public.can_current_user_edit_task_list(l.id),
    'can_manage', public.can_current_user_manage_task_list(l.id)
  );
$$;

create or replace function public.task_item_json(i public.task_items)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', i.id,
    'list_id', i.list_id,
    'title', i.title,
    'details', i.details,
    'status', i.status,
    'priority', i.priority,
    'due_at', i.due_at,
    'due_has_time', i.due_has_time,
    'pos', i.pos,
    'source_message_id', i.source_message_id,
    'created_by', i.created_by,
    'created_at', i.created_at,
    'updated_at', i.updated_at,
    'completed_at', i.completed_at,
    'deleted', i.deleted_at is not null,
    'assignees', coalesce((
      select jsonb_agg(a.user_id order by a.assigned_at, a.user_id)
      from public.task_item_assignees a
      where a.item_id = i.id
    ), '[]'::jsonb)
  );
$$;

revoke execute on function public.valid_task_statuses(jsonb) from public, anon;
revoke execute on function public.task_status_kind(jsonb, text) from public, anon;
revoke execute on function public.task_list_json(public.task_lists) from public, anon, authenticated;
revoke execute on function public.task_item_json(public.task_items) from public, anon, authenticated;
grant execute on function public.valid_task_statuses(jsonb) to authenticated;
grant execute on function public.task_status_kind(jsonb, text) to authenticated;

-- Lists of a conversation with their counts: open and done items, the
-- caller's open items and overdue ones.
create or replace function public.list_task_lists(p_conversation_id uuid)
returns table (
  id uuid,
  title text,
  icon text,
  default_view text,
  created_by uuid,
  updated_at timestamptz,
  open_count integer,
  done_count integer,
  mine_count integer,
  overdue_count integer,
  can_edit boolean
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
  select
    l.id,
    l.title,
    l.icon,
    l.default_view,
    l.created_by,
    l.updated_at,
    (count(i.id) filter (where i.completed_at is null))::integer,
    (count(i.id) filter (where i.completed_at is not null))::integer,
    (count(i.id) filter (
      where i.completed_at is null
        and exists (
          select 1 from public.task_item_assignees a
          where a.item_id = i.id and a.user_id = auth.uid()
        )
    ))::integer,
    (count(i.id) filter (where i.completed_at is null and i.due_at < now()))::integer,
    public.can_current_user_edit_task_list(l.id)
  from public.task_lists l
  left join public.task_items i on i.list_id = l.id and i.deleted_at is null
  where l.conversation_id = p_conversation_id
    and l.deleted_at is null
  group by l.id
  order by l.created_at, l.id;
end;
$$;

-- A list with all its items.
create or replace function public.get_task_list(p_list_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  l public.task_lists%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into l from public.task_lists where id = p_list_id and deleted_at is null;
  if l.id is null or not public.is_current_user_conversation_member(l.conversation_id) then
    raise exception 'List not found' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'list', public.task_list_json(l),
    'items', coalesce((
      select jsonb_agg(public.task_item_json(i) order by i.pos, i.created_at, i.id)
      from public.task_items i
      where i.list_id = l.id and i.deleted_at is null
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.create_task_list(
  p_conversation_id uuid,
  p_title text default '',
  p_icon text default null,
  p_id uuid default null,
  p_statuses jsonb default null,
  p_default_view text default 'list'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  l public.task_lists%rowtype;
  new_id uuid := coalesce(p_id, gen_random_uuid());
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into l from public.task_lists where id = new_id;
  if l.id is not null then
    if l.created_by is distinct from uid
      or not public.is_current_user_conversation_member(l.conversation_id)
    then
      raise exception 'List not found' using errcode = 'P0002';
    end if;
    return public.task_list_json(l);
  end if;

  if not public.can_current_user_write_docs(p_conversation_id) then
    raise exception 'You cannot create lists here' using errcode = '42501';
  end if;
  if (select count(*) from public.task_lists
      where conversation_id = p_conversation_id and deleted_at is null) >= 50
  then
    raise exception 'This conversation has too many lists' using errcode = '22023';
  end if;
  if char_length(coalesce(p_title, '')) > 120 then
    raise exception 'Title is too long' using errcode = '22023';
  end if;
  if p_statuses is not null and not public.valid_task_statuses(p_statuses) then
    raise exception 'Invalid statuses' using errcode = '22023';
  end if;
  if coalesce(p_default_view, 'list') not in ('list', 'board') then
    raise exception 'Invalid view' using errcode = '22023';
  end if;

  insert into public.task_lists (id, conversation_id, title, icon, statuses, default_view, created_by)
  values (
    new_id,
    p_conversation_id,
    btrim(coalesce(p_title, '')),
    coalesce(nullif(btrim(p_icon), ''), E'✅'),
    coalesce(
      p_statuses,
      '[{"id":"todo","name":"To do","kind":"todo"},{"id":"doing","name":"In progress","kind":"active"},{"id":"done","name":"Done","kind":"done"}]'::jsonb
    ),
    coalesce(p_default_view, 'list'),
    uid
  )
  returning * into l;

  return public.task_list_json(l);
end;
$$;

-- Changes a list's title, icon, statuses or default view; [p_patch] holds
-- the keys to change. Removing a status moves its items to [fallback] (the
-- first status of the same kind, else the first one) - the client says
-- where in "status_moves": {"removed id": "new id"}.
create or replace function public.update_task_list(
  p_list_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  l public.task_lists%rowtype;
  new_statuses jsonb;
  moves jsonb := coalesce(p_patch->'status_moves', '{}'::jsonb);
  entry record;
  target_kind text;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_patch, '{}'::jsonb)) <> 'object' then
    raise exception 'Patch must be an object' using errcode = '22023';
  end if;
  select * into l from public.task_lists where id = p_list_id and deleted_at is null for update;
  if l.id is null or not public.is_current_user_conversation_member(l.conversation_id) then
    raise exception 'List not found' using errcode = 'P0002';
  end if;
  if not public.can_current_user_edit_task_list(l.id) then
    raise exception 'You cannot edit this list' using errcode = '42501';
  end if;

  if p_patch ? 'title' then
    if char_length(coalesce(p_patch->>'title', '')) > 120 then
      raise exception 'Title is too long' using errcode = '22023';
    end if;
    l.title := btrim(coalesce(p_patch->>'title', ''));
  end if;
  if p_patch ? 'icon' then
    l.icon := coalesce(nullif(btrim(p_patch->>'icon'), ''), E'✅');
    if char_length(l.icon) > 16 then
      raise exception 'Icon is too long' using errcode = '22023';
    end if;
  end if;
  if p_patch ? 'default_view' then
    if coalesce(p_patch->>'default_view', '') not in ('list', 'board') then
      raise exception 'Invalid view' using errcode = '22023';
    end if;
    l.default_view := p_patch->>'default_view';
  end if;
  if p_patch ? 'statuses' then
    new_statuses := p_patch->'statuses';
    if not public.valid_task_statuses(new_statuses) then
      raise exception 'Invalid statuses' using errcode = '22023';
    end if;
    -- Items in a status that goes away move to the one the caller named
    -- (it must exist), or to the first status of the same kind.
    for entry in
      select e->>'id' as id, e->>'kind' as kind
      from jsonb_array_elements(l.statuses) e
      where not exists (
        select 1 from jsonb_array_elements(new_statuses) n where n->>'id' = e->>'id'
      )
    loop
      target_kind := moves->>entry.id;
      if target_kind is null or not exists (
        select 1 from jsonb_array_elements(new_statuses) n where n->>'id' = target_kind
      ) then
        select n->>'id' into target_kind
        from jsonb_array_elements(new_statuses) n
        where n->>'kind' = entry.kind
        limit 1;
      end if;
      if target_kind is null then
        select new_statuses->0->>'id' into target_kind;
      end if;
      update public.task_items i
      set status = target_kind,
          updated_by = uid,
          updated_at = now(),
          completed_at = case
            when public.task_status_kind(new_statuses, target_kind) = 'done'
              then coalesce(i.completed_at, now())
            else null
          end,
          completed_by = case
            when public.task_status_kind(new_statuses, target_kind) = 'done'
              then coalesce(i.completed_by, uid)
            else null
          end
      where i.list_id = l.id and i.status = entry.id;
    end loop;
    l.statuses := new_statuses;
  end if;

  update public.task_lists
  set title = l.title, icon = l.icon, statuses = l.statuses,
      default_view = l.default_view, updated_at = now()
  where id = l.id
  returning * into l;

  return public.task_list_json(l);
end;
$$;

create or replace function public.delete_task_list(p_list_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.can_current_user_manage_task_list(p_list_id) then
    raise exception 'Only the author or a manager can delete this list'
      using errcode = '42501';
  end if;
  update public.task_lists set deleted_at = now(), updated_at = now() where id = p_list_id;
  update public.task_items set deleted_at = coalesce(deleted_at, now()) where list_id = p_list_id;
end;
$$;

-- Creates or changes one item. [p_item] holds the item's id and the fields
-- to set (see the header): title, details, status, priority, due_at (null
-- clears it), due_has_time, pos, assignees (an array of user ids that
-- replaces the assignees), source_message_id. Returns the item.
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
  new_item_id uuid;
  existing boolean;
  new_status text;
  assignee uuid;
  wanted uuid[];
  kind_after text;
  kind_before text;
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
    i.pos := 'V';
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
        updated_by = uid, updated_at = now()
    where id = i.id
    returning * into i;
  else
    insert into public.task_items (
      id, list_id, title, details, status, priority, due_at, due_has_time, pos,
      source_message_id, created_by, completed_at, completed_by, updated_by
    )
    values (
      i.id, i.list_id, i.title, i.details, i.status, i.priority, i.due_at,
      i.due_has_time, i.pos, i.source_message_id, uid, i.completed_at,
      i.completed_by, uid
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

-- Checks an item off (or back on): the list's first 'done' status, or its
-- first 'todo' status. For the check box in chat.
create or replace function public.set_task_item_done(
  p_item_id uuid,
  p_done boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  l public.task_lists%rowtype;
  i public.task_items%rowtype;
  target text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into i from public.task_items where id = p_item_id and deleted_at is null;
  if i.id is null then
    raise exception 'Item not found' using errcode = 'P0002';
  end if;
  select * into l from public.task_lists where id = i.list_id and deleted_at is null;
  if l.id is null or not public.is_current_user_conversation_member(l.conversation_id) then
    raise exception 'Item not found' using errcode = 'P0002';
  end if;
  select e->>'id' into target
  from jsonb_array_elements(l.statuses) e
  where e->>'kind' = case when coalesce(p_done, true) then 'done' else 'todo' end
  limit 1;
  return public.upsert_task_item(l.id, jsonb_build_object('id', i.id, 'status', target));
end;
$$;

create or replace function public.delete_task_item(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  i public.task_items%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into i from public.task_items where id = p_item_id and deleted_at is null for update;
  if i.id is null then
    return;
  end if;
  if not public.can_current_user_edit_task_list(i.list_id) then
    raise exception 'You cannot edit this list' using errcode = '42501';
  end if;
  update public.task_items
  set deleted_at = now(), updated_by = auth.uid(), updated_at = now()
  where id = i.id;
  update public.task_lists set updated_at = now() where id = i.list_id;
end;
$$;

revoke execute on function public.list_task_lists(uuid) from public, anon;
revoke execute on function public.get_task_list(uuid) from public, anon;
revoke execute on function public.create_task_list(uuid, text, text, uuid, jsonb, text) from public, anon;
revoke execute on function public.update_task_list(uuid, jsonb) from public, anon;
revoke execute on function public.delete_task_list(uuid) from public, anon;
revoke execute on function public.upsert_task_item(uuid, jsonb) from public, anon;
revoke execute on function public.set_task_item_done(uuid, boolean) from public, anon;
revoke execute on function public.delete_task_item(uuid) from public, anon;
grant execute on function public.list_task_lists(uuid) to authenticated;
grant execute on function public.get_task_list(uuid) to authenticated;
grant execute on function public.create_task_list(uuid, text, text, uuid, jsonb, text) to authenticated;
grant execute on function public.update_task_list(uuid, jsonb) to authenticated;
grant execute on function public.delete_task_list(uuid) to authenticated;
grant execute on function public.upsert_task_item(uuid, jsonb) to authenticated;
grant execute on function public.set_task_item_done(uuid, boolean) to authenticated;
grant execute on function public.delete_task_item(uuid) to authenticated;

-- Realtime: lists, items and who they are assigned to.
do $$
declare
  table_name text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach table_name in array array['task_lists', 'task_items', 'task_item_assignees'] loop
      if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = table_name
      ) then
        execute format('alter publication supabase_realtime add table public.%I', table_name);
      end if;
    end loop;
  end if;
end;
$$;
