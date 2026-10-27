-- Whiteboard (roadmap D10), part 3 of 6: reading and changing boards.
--
-- * create_whiteboard(conversation, title, id): a new empty board. [id] lets
--   an offline client create it with an id of its own and send it again
--   safely. At most 20 boards per conversation.
-- * list_whiteboards(conversation): the boards of a conversation, the most
--   recently drawn on first.
-- * get_whiteboard(board): the board and all its live elements.
-- * whiteboard_apply_ops(board, ops): the only way elements change. Each op
--   is {op: 'put', id, kind, z, data, base_rev?, revive?} or {op: 'del', id}
--   and gets an answer in the same order:
--     ok        applied (with the new rev) or already the same;
--     conflict  the element moved on since base_rev: the current element
--               comes back and nothing is applied, the client merges and
--               sends again (no change is dropped silently, nothing is
--               overwritten blindly);
--     rejected  not valid, too much, or not allowed, with a reason.
--   A put for an element the board does not have creates it. A put for a
--   rubbed-out element is a conflict, except with revive = true and the
--   revision of its tombstone (what "undo" of a rub-out sends), which brings
--   it back. The kind of an element never changes.
-- * update_whiteboard_meta(board, patch): the title (anyone who can draw) and
--   "only managers can edit" (managers).
-- * clear_whiteboard(board): empties the board after taking a snapshot of it
--   (managers and the creator).
-- * restore_whiteboard_version(version): puts the board back to a version,
--   after taking a snapshot of how it is now (managers and the creator).
-- * delete_whiteboard(board): the creator or a manager. The board's elements
--   and versions go with it and the pictures it used are listed so the caller
--   can remove them from storage (the whiteboard-files policies allow that
--   once the board is gone, see 202610281430).
--
-- Limits: see 202610281400. A manager of a conversation can always clear,
-- restore and delete; the creator can too, so a lone creator is not locked
-- out of their own board by "only managers can edit".

create or replace function public.create_whiteboard(
  p_conversation_id uuid,
  p_title text default '',
  p_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  w public.whiteboards%rowtype;
  new_id uuid := coalesce(p_id, gen_random_uuid());
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into w from public.whiteboards where id = new_id;
  if w.id is not null then
    -- Sent before (the answer got lost).
    if w.created_by is distinct from uid
      or not public.is_current_user_conversation_member(w.conversation_id)
    then
      raise exception 'Whiteboard not found' using errcode = 'P0002';
    end if;
    return public.whiteboard_json(w);
  end if;

  if not public.is_current_user_conversation_member(p_conversation_id) then
    raise exception 'Conversation not found' using errcode = 'P0002';
  end if;
  if public.is_user_suspended(uid) then
    raise exception 'Account suspended' using errcode = '42501';
  end if;
  if not public.can_current_user_write_docs(p_conversation_id) then
    raise exception 'You cannot create whiteboards here' using errcode = '42501';
  end if;
  if (select count(*) from public.whiteboards
      where conversation_id = p_conversation_id and deleted_at is null) >= 20
  then
    raise exception 'whiteboard_limit' using errcode = '22023';
  end if;
  if char_length(coalesce(p_title, '')) > 100 then
    raise exception 'Title is too long' using errcode = '22023';
  end if;

  insert into public.whiteboards (id, conversation_id, title, created_by, updated_by)
  values (new_id, p_conversation_id, btrim(coalesce(p_title, '')), uid, uid)
  returning * into w;

  return public.whiteboard_json(w);
end;
$$;

create or replace function public.list_whiteboards(p_conversation_id uuid)
returns table (
  id uuid,
  title text,
  managers_only boolean,
  created_by uuid,
  updated_by uuid,
  updated_by_name text,
  updated_at timestamptz,
  element_count integer,
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
    w.id,
    w.title,
    w.managers_only,
    w.created_by,
    w.updated_by,
    coalesce(nullif(btrim(p.display_name), ''), p.username),
    w.updated_at,
    w.element_count,
    public.can_current_user_edit_whiteboard(w.id)
  from public.whiteboards w
  left join public.profiles p on p.id = w.updated_by
  where w.conversation_id = p_conversation_id
    and w.deleted_at is null
  order by w.updated_at desc, w.id;
end;
$$;

-- A board with all its live elements, in drawing order.
create or replace function public.get_whiteboard(p_board_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  w public.whiteboards%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into w from public.whiteboards where id = p_board_id and deleted_at is null;
  if w.id is null or not public.is_current_user_conversation_member(w.conversation_id) then
    raise exception 'Whiteboard not found' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'board', public.whiteboard_json(w),
    'elements', coalesce((
      select jsonb_agg(public.whiteboard_element_json(e) order by e.z, e.id)
      from public.whiteboard_elements e
      where e.board_id = w.id and not e.deleted
    ), '[]'::jsonb)
  );
end;
$$;

-- The one way elements change (see the head of this file).
create or replace function public.whiteboard_apply_ops(
  p_board_id uuid,
  p_ops jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  w public.whiteboards%rowtype;
  op jsonb;
  results jsonb := '[]'::jsonb;
  el_id uuid;
  e public.whiteboard_elements%rowtype;
  base_rev integer;
  new_kind text;
  new_z text;
  new_data jsonb;
  new_size integer;
  old_size integer;
  live_count integer;
  total_size integer;
  changed boolean := false;
  tombstones integer;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_ops) <> 'array' then
    raise exception 'ops must be an array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_ops) > 200 then
    raise exception 'Too many changes at once' using errcode = '22023';
  end if;

  select * into w from public.whiteboards where id = p_board_id and deleted_at is null for update;
  if w.id is null or not public.is_current_user_conversation_member(w.conversation_id) then
    raise exception 'Whiteboard not found' using errcode = 'P0002';
  end if;
  if not public.can_current_user_edit_whiteboard(w.id) then
    raise exception 'You cannot edit this whiteboard' using errcode = '42501';
  end if;

  -- A snapshot of the state before a new burst of work: the board changed
  -- since its last snapshot and was quiet for 10 minutes, or has been worked
  -- on for 30 minutes without one.
  if w.updated_at > coalesce(w.last_snapshot_at, w.created_at)
    and (
      w.updated_at < now() - interval '10 minutes'
      or coalesce(w.last_snapshot_at, w.created_at) < now() - interval '30 minutes'
    )
  then
    perform public.snapshot_whiteboard(w.id, uid, null, 'auto');
  end if;

  live_count := w.element_count;
  total_size := w.data_size;

  for op in select * from jsonb_array_elements(p_ops) loop
    begin
      el_id := (op->>'id')::uuid;
    exception when others then
      results := results || jsonb_build_object('status', 'rejected', 'reason', 'bad id');
      continue;
    end;

    if op->>'op' = 'del' then
      select * into e from public.whiteboard_elements
      where id = el_id and board_id = w.id for update;
      if e.id is not null and not e.deleted then
        old_size := length(e.data::text);
        update public.whiteboard_elements
        set deleted = true, data = '{}'::jsonb, rev = rev + 1,
            updated_by = uid, updated_at = now()
        where id = e.id
        returning * into e;
        changed := true;
        live_count := live_count - 1;
        total_size := total_size - old_size;
        results := results || jsonb_build_object('id', el_id, 'status', 'ok', 'rev', e.rev);
      else
        results := results || jsonb_build_object('id', el_id, 'status', 'ok');
      end if;
      e := null;
      continue;
    end if;

    if op->>'op' is distinct from 'put' then
      results := results || jsonb_build_object('id', el_id, 'status', 'rejected', 'reason', 'bad op');
      continue;
    end if;

    new_kind := op->>'kind';
    new_z := op->>'z';
    new_data := coalesce(op->'data', '{}'::jsonb);
    if not public.whiteboard_element_is_valid(new_kind, new_data, new_z) then
      results := results || jsonb_build_object('id', el_id, 'status', 'rejected', 'reason', 'invalid element');
      continue;
    end if;
    if new_kind = 'image' and (new_data->>'path') not like w.id::text || '/%' then
      results := results || jsonb_build_object('id', el_id, 'status', 'rejected', 'reason', 'bad picture');
      continue;
    end if;
    new_size := length(new_data::text);
    base_rev := nullif(op->>'base_rev', '')::integer;

    select * into e from public.whiteboard_elements where id = el_id for update;

    if e.id is null then
      if live_count >= 3000 then
        results := results || jsonb_build_object('id', el_id, 'status', 'rejected', 'reason', 'too many elements');
        continue;
      end if;
      if total_size + new_size > 6000000 then
        results := results || jsonb_build_object('id', el_id, 'status', 'rejected', 'reason', 'too much data');
        continue;
      end if;
      insert into public.whiteboard_elements (id, board_id, z, kind, data, updated_by)
      values (el_id, w.id, new_z, new_kind, new_data, uid)
      returning * into e;
      changed := true;
      live_count := live_count + 1;
      total_size := total_size + new_size;
      results := results || jsonb_build_object('id', el_id, 'status', 'ok', 'rev', e.rev);
      e := null;
      continue;
    end if;

    if e.board_id <> w.id then
      results := results || jsonb_build_object('id', el_id, 'status', 'rejected', 'reason', 'bad id');
      e := null;
      continue;
    end if;
    if e.kind <> new_kind then
      results := results || jsonb_build_object('id', el_id, 'status', 'rejected', 'reason', 'bad kind');
      e := null;
      continue;
    end if;

    -- The very same content again: a repeated send.
    if not e.deleted and e.z = new_z and e.data = new_data then
      results := results || jsonb_build_object('id', el_id, 'status', 'ok', 'rev', e.rev);
      e := null;
      continue;
    end if;

    if e.deleted then
      -- "Undo" of a rub-out: it saw the tombstone and asks for it back.
      if coalesce((op->>'revive')::boolean, false) and base_rev is not distinct from e.rev then
        if live_count >= 3000 then
          results := results || jsonb_build_object('id', el_id, 'status', 'rejected', 'reason', 'too many elements');
          e := null;
          continue;
        end if;
        if total_size + new_size > 6000000 then
          results := results || jsonb_build_object('id', el_id, 'status', 'rejected', 'reason', 'too much data');
          e := null;
          continue;
        end if;
        update public.whiteboard_elements
        set deleted = false, z = new_z, data = new_data, rev = rev + 1,
            updated_by = uid, updated_at = now()
        where id = el_id
        returning * into e;
        changed := true;
        live_count := live_count + 1;
        total_size := total_size + new_size;
        results := results || jsonb_build_object('id', el_id, 'status', 'ok', 'rev', e.rev);
      else
        results := results || jsonb_build_object(
          'id', el_id,
          'status', 'conflict',
          'element', public.whiteboard_element_json(e)
        );
      end if;
      e := null;
      continue;
    end if;

    if base_rev is distinct from e.rev then
      results := results || jsonb_build_object(
        'id', el_id,
        'status', 'conflict',
        'element', public.whiteboard_element_json(e)
      );
      e := null;
      continue;
    end if;

    old_size := length(e.data::text);
    if total_size - old_size + new_size > 6000000 then
      results := results || jsonb_build_object('id', el_id, 'status', 'rejected', 'reason', 'too much data');
      e := null;
      continue;
    end if;
    update public.whiteboard_elements
    set z = new_z, data = new_data, rev = rev + 1, updated_by = uid, updated_at = now()
    where id = el_id
    returning * into e;
    changed := true;
    total_size := total_size - old_size + new_size;
    results := results || jsonb_build_object('id', el_id, 'status', 'ok', 'rev', e.rev);
    e := null;
  end loop;

  if changed then
    update public.whiteboards
    set updated_at = now(),
        updated_by = uid,
        element_count = live_count,
        data_size = total_size
    where id = w.id;

    -- Tombstones nobody can still be editing: a month old, or beyond the
    -- newest 5000.
    delete from public.whiteboard_elements
    where board_id = w.id and deleted and updated_at < now() - interval '30 days';
    select count(*) into tombstones
    from public.whiteboard_elements where board_id = w.id and deleted;
    if tombstones > 5000 then
      delete from public.whiteboard_elements d
      where d.id in (
        select t.id from public.whiteboard_elements t
        where t.board_id = w.id and t.deleted
        order by t.updated_at asc, t.id
        limit tombstones - 5000
      );
    end if;
  end if;

  return results;
end;
$$;

-- Changes a board's title (anyone who can draw) or its "only managers can
-- edit" switch (a manager).
create or replace function public.update_whiteboard_meta(
  p_board_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  w public.whiteboards%rowtype;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_patch, '{}'::jsonb)) <> 'object' then
    raise exception 'Patch must be an object' using errcode = '22023';
  end if;

  select * into w from public.whiteboards where id = p_board_id and deleted_at is null for update;
  if w.id is null or not public.is_current_user_conversation_member(w.conversation_id) then
    raise exception 'Whiteboard not found' using errcode = 'P0002';
  end if;

  if p_patch ? 'title' then
    if not (
      public.can_current_user_edit_whiteboard(w.id) or w.created_by = uid
    ) then
      raise exception 'You cannot edit this whiteboard' using errcode = '42501';
    end if;
    if char_length(coalesce(p_patch->>'title', '')) > 100 then
      raise exception 'Title is too long' using errcode = '22023';
    end if;
    w.title := btrim(coalesce(p_patch->>'title', ''));
  end if;

  if p_patch ? 'managers_only' then
    if not public.can_current_user_manage_whiteboard(w.id) then
      raise exception 'Only managers can change this' using errcode = '42501';
    end if;
    w.managers_only := coalesce((p_patch->>'managers_only')::boolean, false);
  end if;

  update public.whiteboards
  set title = w.title,
      managers_only = w.managers_only,
      updated_by = uid,
      updated_at = now()
  where id = w.id
  returning * into w;

  return public.whiteboard_json(w);
end;
$$;

-- Empties the board (a snapshot first, so it can be brought back).
create or replace function public.clear_whiteboard(p_board_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  w public.whiteboards%rowtype;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into w from public.whiteboards where id = p_board_id and deleted_at is null for update;
  if w.id is null or not public.is_current_user_conversation_member(w.conversation_id) then
    raise exception 'Whiteboard not found' using errcode = 'P0002';
  end if;
  if w.created_by is distinct from uid
    and not public.can_current_user_manage_whiteboard(w.id)
  then
    raise exception 'Only the author or a manager can clear this whiteboard'
      using errcode = '42501';
  end if;

  perform public.snapshot_whiteboard(w.id, uid, null, 'restore');

  update public.whiteboard_elements
  set deleted = true, data = '{}'::jsonb, rev = rev + 1,
      updated_by = uid, updated_at = now()
  where board_id = w.id and not deleted;

  update public.whiteboards
  set element_count = 0, data_size = 0, updated_by = uid, updated_at = now()
  where id = w.id;
end;
$$;

-- Puts the board back to a version (a snapshot of how it is now first).
create or replace function public.restore_whiteboard_version(p_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  v public.whiteboard_versions%rowtype;
  w public.whiteboards%rowtype;
  item jsonb;
  kept uuid[] := '{}';
  item_id uuid;
  live integer := 0;
  total integer := 0;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into v from public.whiteboard_versions where id = p_version_id;
  if v.id is null then
    raise exception 'Version not found' using errcode = 'P0002';
  end if;
  select * into w from public.whiteboards where id = v.board_id and deleted_at is null for update;
  if w.id is null or not public.is_current_user_conversation_member(w.conversation_id) then
    raise exception 'Version not found' using errcode = 'P0002';
  end if;
  if w.created_by is distinct from uid
    and not public.can_current_user_manage_whiteboard(w.id)
  then
    raise exception 'Only the author or a manager can restore a version'
      using errcode = '42501';
  end if;

  perform public.snapshot_whiteboard(w.id, uid, null, 'restore');

  for item in select * from jsonb_array_elements(v.elements) loop
    item_id := (item->>'id')::uuid;
    if not public.whiteboard_element_is_valid(item->>'kind', item->'data', item->>'z') then
      continue;
    end if;
    -- An id of another board never gets in.
    if exists (
      select 1 from public.whiteboard_elements x
      where x.id = item_id and x.board_id <> w.id
    ) then
      continue;
    end if;
    insert into public.whiteboard_elements (id, board_id, z, kind, data, updated_by)
    values (item_id, w.id, item->>'z', item->>'kind', item->'data', uid)
    on conflict (id) do update
    set z = excluded.z,
        data = excluded.data,
        deleted = false,
        rev = public.whiteboard_elements.rev + 1,
        updated_by = uid,
        updated_at = now()
    where public.whiteboard_elements.kind = excluded.kind;
    kept := kept || item_id;
    live := live + 1;
    total := total + length((item->'data')::text);
  end loop;

  update public.whiteboard_elements
  set deleted = true, data = '{}'::jsonb, rev = rev + 1,
      updated_by = uid, updated_at = now()
  where board_id = w.id and not deleted and not (id = any(kept));

  update public.whiteboards
  set element_count = live, data_size = total, updated_by = uid, updated_at = now()
  where id = w.id
  returning * into w;

  return public.whiteboard_json(w);
end;
$$;

-- Deletes a board (the creator or a manager). Its pictures are listed so the
-- caller can remove them from storage.
create or replace function public.delete_whiteboard(p_board_id uuid)
returns table (bucket_id text, object_path text)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  uid uuid := auth.uid();
  w public.whiteboards%rowtype;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into w from public.whiteboards where id = p_board_id and deleted_at is null for update;
  if w.id is null or not public.is_current_user_conversation_member(w.conversation_id) then
    raise exception 'Whiteboard not found' using errcode = 'P0002';
  end if;
  if w.created_by is distinct from uid
    and not public.can_current_user_manage_whiteboard(w.id)
  then
    raise exception 'Only the author or a manager can delete this whiteboard'
      using errcode = '42501';
  end if;

  update public.whiteboards
  set deleted_at = now(), title = '', element_count = 0, data_size = 0,
      updated_by = uid, updated_at = now()
  where id = w.id;
  delete from public.whiteboard_elements where board_id = w.id;
  delete from public.whiteboard_versions where board_id = w.id;

  return query
  select 'whiteboard-files'::text, o.name
  from storage.objects o
  where o.bucket_id = 'whiteboard-files'
    and o.name like w.id::text || '/%';
end;
$$;

revoke execute on function public.create_whiteboard(uuid, text, uuid) from public, anon;
revoke execute on function public.list_whiteboards(uuid) from public, anon;
revoke execute on function public.get_whiteboard(uuid) from public, anon;
revoke execute on function public.whiteboard_apply_ops(uuid, jsonb) from public, anon;
revoke execute on function public.update_whiteboard_meta(uuid, jsonb) from public, anon;
revoke execute on function public.clear_whiteboard(uuid) from public, anon;
revoke execute on function public.restore_whiteboard_version(uuid) from public, anon;
revoke execute on function public.delete_whiteboard(uuid) from public, anon;
grant execute on function public.create_whiteboard(uuid, text, uuid) to authenticated;
grant execute on function public.list_whiteboards(uuid) to authenticated;
grant execute on function public.get_whiteboard(uuid) to authenticated;
grant execute on function public.whiteboard_apply_ops(uuid, jsonb) to authenticated;
grant execute on function public.update_whiteboard_meta(uuid, jsonb) to authenticated;
grant execute on function public.clear_whiteboard(uuid) to authenticated;
grant execute on function public.restore_whiteboard_version(uuid) to authenticated;
grant execute on function public.delete_whiteboard(uuid) to authenticated;
