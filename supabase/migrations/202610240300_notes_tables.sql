-- Notes 2.0 (roadmap D5), part 1 of 5: tables in notes.
--
-- A table is a block of kind 'table' (note_blocks.kind). Its cells live in
-- props, with ids for rows and columns so that two people typing in
-- different cells never collide, whatever else changes around them (the
-- app merges a table cell by cell, see lib/features/notes/note_table.dart):
--
--   props = {
--     "header": true,                      -- the first row is a heading
--     "cols": ["c1", "c2", "c3"],          -- column ids, left to right
--     "rows": [                            -- top to bottom
--       {"id": "r1", "c": {"c1": "Name", "c2": "Day", "c3": "Where"}},
--       {"id": "r2", "c": {"c1": "Ada",  "c2": "Mon"}}   -- missing = empty
--     ]
--   }
--
-- Limits (note_table_props_valid): 1 to 12 columns, 1 to 200 rows, a cell of
-- at most 1000 characters, 60000 characters of props in all.
--
-- note_apply_ops is the only function that knew the list of block kinds and
-- the size limits, in a long condition of its own. It is rewritten here from
-- its only earlier definition (202610170060_notes) to ask the new
-- note_block_is_valid instead, so the rules live in one place and the
-- template function (202610240320) uses the very same check. Nothing else of
-- it changed.
--
-- The scrub triggers of 202610190013_security_deleted_content blank a deleted
-- note's and a deleted block's text; a table's text is in props, so they are
-- rewritten (from that file) to empty a table's props as well.

alter table public.note_blocks drop constraint if exists note_blocks_kind;
alter table public.note_blocks add constraint note_blocks_kind check (kind in (
  'paragraph', 'h1', 'h2', 'h3', 'bullet', 'numbered', 'todo', 'quote',
  'code', 'divider', 'image', 'table'
));

-- Whether [p_props] describes a usable table.
create or replace function public.note_table_props_valid(p_props jsonb)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  col jsonb;
  r jsonb;
  cell record;
  col_count integer;
begin
  if jsonb_typeof(p_props) <> 'object'
    or jsonb_typeof(p_props->'cols') is distinct from 'array'
    or jsonb_typeof(p_props->'rows') is distinct from 'array'
  then
    return false;
  end if;
  col_count := jsonb_array_length(p_props->'cols');
  if col_count < 1 or col_count > 12
    or jsonb_array_length(p_props->'rows') < 1
    or jsonb_array_length(p_props->'rows') > 200
  then
    return false;
  end if;
  for col in select * from jsonb_array_elements(p_props->'cols') loop
    if jsonb_typeof(col) <> 'string'
      or char_length(col #>> '{}') not between 1 and 16
    then
      return false;
    end if;
  end loop;
  for r in select * from jsonb_array_elements(p_props->'rows') loop
    if jsonb_typeof(r) <> 'object'
      or jsonb_typeof(r->'id') is distinct from 'string'
      or char_length(r->>'id') not between 1 and 16
      or jsonb_typeof(r->'c') is distinct from 'object'
    then
      return false;
    end if;
    for cell in select * from jsonb_each(r->'c') loop
      if jsonb_typeof(cell.value) <> 'string'
        or char_length(cell.value #>> '{}') > 1000
      then
        return false;
      end if;
    end loop;
  end loop;
  return true;
end;
$$;

-- The rules for one block, the same for every way a block gets in.
create or replace function public.note_block_is_valid(
  p_kind text,
  p_text text,
  p_marks jsonb,
  p_props jsonb,
  p_pos text
)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
begin
  if p_kind is null
    or p_kind not in ('paragraph', 'h1', 'h2', 'h3', 'bullet', 'numbered',
      'todo', 'quote', 'code', 'divider', 'image', 'table')
    or p_text is null
    or char_length(p_text) > 20000
    or p_marks is null
    or jsonb_typeof(p_marks) <> 'array'
    or jsonb_array_length(p_marks) > 1000
    or p_props is null
    or jsonb_typeof(p_props) <> 'object'
    or p_pos is null
    or p_pos !~ '^[0-9A-Za-z]{1,64}$'
  then
    return false;
  end if;
  if p_kind = 'table' then
    return length(p_props::text) <= 60000
      and public.note_table_props_valid(p_props);
  end if;
  return length(p_props::text) <= 4000;
end;
$$;

revoke execute on function public.note_table_props_valid(jsonb) from public, anon, authenticated;
revoke execute on function public.note_block_is_valid(text, text, jsonb, jsonb, text) from public, anon, authenticated;

-- Applies a batch of block changes, in order, as the current user.
--
-- Each op is one of
--   {"op": "put", "id": uuid, "base_rev": int | null, "pos": text,
--    "kind": text, "text": text, "marks": [...], "props": {...}}
--   {"op": "del", "id": uuid}
-- A put with base_rev null creates the block (or, when it exists already
-- with the very same content, is a repeat of an earlier send: answered ok).
-- A put with base_rev applies when the block is still at that revision.
-- Otherwise nothing is changed and the result is
--   {"id", "status": "conflict", "block": <current block>}
-- and the client merges and sends again. A delete always wins and is ok
-- for blocks that are already gone. Results come back in the order of the
-- ops: {"id", "status": "ok", "rev"} | "conflict" | "rejected" with
-- "reason".
--
-- (Rewritten in 202610240300 from 202610170060: blocks are checked by
-- note_block_is_valid, which also knows tables.)
--
-- A snapshot of the note is kept before the first change after a quiet
-- spell of 10 minutes (and every 30 minutes of continuous work), so the
-- history has a point to return to for every working session.
create or replace function public.note_apply_ops(
  p_note_id uuid,
  p_ops jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  n public.notes%rowtype;
  op jsonb;
  results jsonb := '[]'::jsonb;
  block_id uuid;
  b public.note_blocks%rowtype;
  base_rev integer;
  new_kind text;
  new_text text;
  new_marks jsonb;
  new_props jsonb;
  new_pos text;
  live_count integer;
  changed boolean := false;
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

  select * into n from public.notes where id = p_note_id and deleted_at is null for update;
  if n.id is null or not public.is_current_user_conversation_member(n.conversation_id) then
    raise exception 'Note not found' using errcode = 'P0002';
  end if;
  if not public.can_current_user_edit_note(n.id) then
    raise exception 'You cannot edit this note' using errcode = '42501';
  end if;

  -- A snapshot of the state before a new burst of work: the note changed
  -- since its last snapshot and was quiet for 10 minutes, or has been
  -- worked on for 30 minutes without one.
  if n.updated_at > coalesce(n.last_snapshot_at, n.created_at)
    and (
      n.updated_at < now() - interval '10 minutes'
      or coalesce(n.last_snapshot_at, n.created_at) < now() - interval '30 minutes'
    )
  then
    perform public.snapshot_note(n.id, uid, null, 'auto');
    n.last_snapshot_at := now();
  end if;

  select count(*) into live_count
  from public.note_blocks where note_id = n.id and not deleted;

  for op in select * from jsonb_array_elements(p_ops) loop
    begin
      block_id := (op->>'id')::uuid;
    exception when others then
      results := results || jsonb_build_object('status', 'rejected', 'reason', 'bad id');
      continue;
    end;

    if op->>'op' = 'del' then
      update public.note_blocks
      set deleted = true, rev = rev + 1, updated_by = uid, updated_at = now()
      where id = block_id and note_id = n.id and not deleted
      returning * into b;
      if b.id is not null then
        changed := true;
        live_count := live_count - 1;
        results := results || jsonb_build_object('id', block_id, 'status', 'ok', 'rev', b.rev);
      else
        results := results || jsonb_build_object('id', block_id, 'status', 'ok');
      end if;
      b := null;
      continue;
    end if;

    if op->>'op' is distinct from 'put' then
      results := results || jsonb_build_object('id', block_id, 'status', 'rejected', 'reason', 'bad op');
      continue;
    end if;

    new_kind := coalesce(op->>'kind', 'paragraph');
    new_text := coalesce(op->>'text', '');
    new_marks := coalesce(op->'marks', '[]'::jsonb);
    new_props := coalesce(op->'props', '{}'::jsonb);
    new_pos := op->>'pos';
    if not public.note_block_is_valid(new_kind, new_text, new_marks, new_props, new_pos) then
      results := results || jsonb_build_object('id', block_id, 'status', 'rejected', 'reason', 'invalid block');
      continue;
    end if;
    base_rev := nullif(op->>'base_rev', '')::integer;

    select * into b from public.note_blocks where id = block_id for update;

    if b.id is null then
      if base_rev is not null then
        -- Edited a block this note never had (or lost): create it anew.
        base_rev := null;
      end if;
      if live_count >= 5000 then
        results := results || jsonb_build_object('id', block_id, 'status', 'rejected', 'reason', 'too many blocks');
        continue;
      end if;
      insert into public.note_blocks (id, note_id, pos, kind, text, marks, props, updated_by)
      values (block_id, n.id, new_pos, new_kind, new_text, new_marks, new_props, uid)
      returning * into b;
      changed := true;
      live_count := live_count + 1;
      results := results || jsonb_build_object('id', block_id, 'status', 'ok', 'rev', b.rev);
      b := null;
      continue;
    end if;

    if b.note_id <> n.id then
      results := results || jsonb_build_object('id', block_id, 'status', 'rejected', 'reason', 'bad id');
      b := null;
      continue;
    end if;

    -- The very same content again: a repeated send.
    if b.pos = new_pos and b.kind = new_kind and b.text = new_text
      and b.marks = new_marks and b.props = new_props and not b.deleted
    then
      results := results || jsonb_build_object('id', block_id, 'status', 'ok', 'rev', b.rev);
      b := null;
      continue;
    end if;

    if b.deleted or base_rev is distinct from b.rev then
      results := results || jsonb_build_object(
        'id', block_id,
        'status', 'conflict',
        'block', public.note_block_json(b)
      );
      b := null;
      continue;
    end if;

    update public.note_blocks
    set pos = new_pos, kind = new_kind, text = new_text, marks = new_marks,
        props = new_props, rev = rev + 1, updated_by = uid, updated_at = now()
    where id = block_id
    returning * into b;
    changed := true;
    results := results || jsonb_build_object('id', block_id, 'status', 'ok', 'rev', b.rev);
    b := null;
  end loop;

  if changed then
    update public.notes set updated_at = now(), updated_by = uid where id = n.id;
  end if;

  -- Tombstones nobody can still be editing.
  delete from public.note_blocks
  where note_id = n.id and deleted and updated_at < now() - interval '30 days';

  return results;
end;
$$;

revoke execute on function public.note_apply_ops(uuid, jsonb) from public, anon;
grant execute on function public.note_apply_ops(uuid, jsonb) to authenticated;

-- Scrub triggers, from 202610190013_security_deleted_content, now emptying a
-- table's props (its cells) too. A picture's props stay: they hold the path
-- delete_note hands back for removal.
create or replace function public.scrub_deleted_note()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.deleted_at is null and new.deleted_at is not null then
    new.title := '';
    update public.note_blocks
    set text = '',
        marks = '[]'::jsonb,
        props = case when kind = 'table' then '{}'::jsonb else props end
    where note_id = new.id
      and (text <> '' or marks <> '[]'::jsonb
        or (kind = 'table' and props <> '{}'::jsonb));
    delete from public.note_versions where note_id = new.id;
  end if;
  return new;
end;
$$;

create or replace function public.scrub_deleted_note_block()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.deleted and not old.deleted then
    new.text := '';
    new.marks := '[]'::jsonb;
    if new.kind = 'table' then
      new.props := '{}'::jsonb;
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function public.scrub_deleted_note() from public, anon, authenticated;
revoke execute on function public.scrub_deleted_note_block() from public, anon, authenticated;
