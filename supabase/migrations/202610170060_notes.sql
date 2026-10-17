-- Notes: shared documents that live in a conversation (a circle channel, a
-- group or a direct chat).
--
-- A note is a title, an emoji icon and an ordered list of BLOCKS (heading,
-- paragraph, list item, quote, code, divider, picture). Every block is a row
-- of note_blocks, so people editing at once only collide when they touch the
-- same block:
--
-- * pos is a fractional ordering key (base 62, "0-9A-Za-z", C collation):
--   a block inserted between two others gets a key between theirs without
--   renumbering anything. Equal keys (two people inserting at the same spot)
--   are broken by block id, so every client orders them the same way.
-- * rev is the block's revision. note_apply_ops takes the revision the
--   client based its change on; when the block moved on meanwhile the change
--   is NOT applied and the current block comes back, so the client can merge
--   (three-way, using the version it based its change on) and send again. No
--   change is dropped silently and nothing is overwritten blindly.
-- * Deleted blocks stay as tombstones (deleted = true), so an edit that
--   arrives late for a deleted block is noticed instead of resurrecting it.
-- * marks holds inline formatting as [[start, end, "b" | "i" | "s" | "c" |
--   "l:<url>" | "m:<user id>"], ...] over text (UTF-16 offsets, end
--   exclusive).
--
-- Who may do what (all enforced here, never by the client):
-- * view: anyone who can see the conversation (is_current_user_conversation_member,
--   which already asks view_channel for circle channels);
-- * edit: anyone who can send messages there (can_current_user_send_in_conversation),
--   and, when the note is "only managers can edit", holders of manage_messages
--   in the channel (or admins of a group) (can_current_user_moderate_messages);
-- * managers_only and pinned can only be changed by those managers; the
--   creator and managers can delete a note.
--
-- Tables are read-only for clients (row level security lets members read so
-- realtime can deliver changes); every write goes through the functions
-- below. Realtime streams notes and note_blocks per note.

create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  title text not null default '',
  icon text not null default E'\U0001F4DD',
  managers_only boolean not null default false,
  pinned boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- When the last automatic or manual snapshot was taken.
  last_snapshot_at timestamptz,
  deleted_at timestamptz,
  constraint notes_title_length check (char_length(title) <= 200),
  constraint notes_icon_length check (char_length(icon) between 1 and 16)
);

create index if not exists notes_conversation_idx
  on public.notes (conversation_id, updated_at desc)
  where deleted_at is null;

-- One pinned note (the banner) per conversation.
create unique index if not exists notes_one_pinned_idx
  on public.notes (conversation_id)
  where pinned and deleted_at is null;

create table if not exists public.note_blocks (
  id uuid primary key,
  note_id uuid not null references public.notes(id) on delete cascade,
  pos text not null collate "C",
  kind text not null default 'paragraph',
  text text not null default '',
  marks jsonb not null default '[]'::jsonb,
  props jsonb not null default '{}'::jsonb,
  rev integer not null default 1,
  deleted boolean not null default false,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint note_blocks_kind check (kind in (
    'paragraph', 'h1', 'h2', 'h3', 'bullet', 'numbered', 'todo', 'quote',
    'code', 'divider', 'image'
  )),
  constraint note_blocks_pos check (pos ~ '^[0-9A-Za-z]{1,64}$'),
  constraint note_blocks_text_length check (char_length(text) <= 20000),
  constraint note_blocks_marks_array check (
    jsonb_typeof(marks) = 'array' and jsonb_array_length(marks) <= 1000
  ),
  constraint note_blocks_props_object check (jsonb_typeof(props) = 'object')
);

create index if not exists note_blocks_order_idx
  on public.note_blocks (note_id, pos, id);

alter table public.notes enable row level security;
alter table public.note_blocks enable row level security;

revoke all on public.notes from anon, authenticated;
revoke all on public.note_blocks from anon, authenticated;
grant select on public.notes to authenticated;
grant select on public.note_blocks to authenticated;

drop policy if exists notes_select_member on public.notes;
create policy notes_select_member
  on public.notes for select
  to authenticated
  using (public.is_current_user_conversation_member(conversation_id));

-- Whether the current user may write notes and lists in a conversation:
-- they can send messages there and nobody in a direct chat has blocked the
-- other.
create or replace function public.can_current_user_write_docs(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_current_user_send_in_conversation(target_conversation_id)
    and not public.is_current_user_blocked_in_conversation(target_conversation_id);
$$;

revoke execute on function public.can_current_user_write_docs(uuid) from public, anon;
grant execute on function public.can_current_user_write_docs(uuid) to authenticated;

-- Asked once per streamed row; the note lookup is by primary key.
create or replace function public.can_current_user_view_note(target_note_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.notes n
      where n.id = target_note_id
        and public.is_current_user_conversation_member(n.conversation_id)
    );
$$;

drop policy if exists note_blocks_select_member on public.note_blocks;
create policy note_blocks_select_member
  on public.note_blocks for select
  to authenticated
  using (public.can_current_user_view_note(note_id));

-- Whether the current user may change the note's blocks, title and icon.
create or replace function public.can_current_user_edit_note(target_note_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  n public.notes%rowtype;
begin
  if auth.uid() is null then
    return false;
  end if;
  select * into n from public.notes where id = target_note_id;
  if n.id is null or n.deleted_at is not null then
    return false;
  end if;
  if not public.can_current_user_write_docs(n.conversation_id) then
    return false;
  end if;
  if n.managers_only then
    return public.can_current_user_moderate_messages(n.conversation_id);
  end if;
  return true;
end;
$$;

-- Whether the current user manages notes in the note's conversation: pins
-- them, locks them to managers, deletes anyone's.
create or replace function public.can_current_user_manage_note(target_note_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  n public.notes%rowtype;
begin
  if auth.uid() is null then
    return false;
  end if;
  select * into n from public.notes where id = target_note_id;
  if n.id is null or n.deleted_at is not null then
    return false;
  end if;
  return public.can_current_user_moderate_messages(n.conversation_id);
end;
$$;

revoke execute on function public.can_current_user_view_note(uuid) from public, anon;
revoke execute on function public.can_current_user_edit_note(uuid) from public, anon;
revoke execute on function public.can_current_user_manage_note(uuid) from public, anon;
grant execute on function public.can_current_user_view_note(uuid) to authenticated;
grant execute on function public.can_current_user_edit_note(uuid) to authenticated;
grant execute on function public.can_current_user_manage_note(uuid) to authenticated;

-- JSON of a note row, with what the current user may do with it.
create or replace function public.note_json(n public.notes)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', n.id,
    'conversation_id', n.conversation_id,
    'title', n.title,
    'icon', n.icon,
    'managers_only', n.managers_only,
    'pinned', n.pinned,
    'created_by', n.created_by,
    'updated_by', n.updated_by,
    'created_at', n.created_at,
    'updated_at', n.updated_at,
    'can_edit', public.can_current_user_edit_note(n.id),
    'can_manage', public.can_current_user_manage_note(n.id)
  );
$$;

revoke execute on function public.note_json(public.notes) from public, anon, authenticated;

create or replace function public.note_block_json(b public.note_blocks)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select jsonb_build_object(
    'id', b.id,
    'note_id', b.note_id,
    'pos', b.pos,
    'kind', b.kind,
    'text', b.text,
    'marks', b.marks,
    'props', b.props,
    'rev', b.rev,
    'deleted', b.deleted,
    'updated_by', b.updated_by
  );
$$;

revoke execute on function public.note_block_json(public.note_blocks) from public, anon, authenticated;

-- Notes of a conversation, pinned first, then most recently edited.
create or replace function public.list_notes(p_conversation_id uuid)
returns table (
  id uuid,
  title text,
  icon text,
  managers_only boolean,
  pinned boolean,
  created_by uuid,
  updated_by uuid,
  updated_by_name text,
  updated_at timestamptz,
  preview text,
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
    n.id,
    n.title,
    n.icon,
    n.managers_only,
    n.pinned,
    n.created_by,
    n.updated_by,
    coalesce(nullif(btrim(p.display_name), ''), p.username),
    n.updated_at,
    coalesce((
      select left(regexp_replace(string_agg(b.text, ' ' order by b.pos, b.id), '\s+', ' ', 'g'), 140)
      from (
        select nb.text, nb.pos, nb.id
        from public.note_blocks nb
        where nb.note_id = n.id and not nb.deleted and nb.text <> ''
        order by nb.pos, nb.id
        limit 6
      ) b
    ), ''),
    public.can_current_user_edit_note(n.id)
  from public.notes n
  left join public.profiles p on p.id = n.updated_by
  where n.conversation_id = p_conversation_id
    and n.deleted_at is null
  order by n.pinned desc, n.updated_at desc, n.id;
end;
$$;

-- The pinned note of a conversation (for the banner), or nothing.
create or replace function public.get_pinned_note(p_conversation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  n public.notes%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.is_current_user_conversation_member(p_conversation_id) then
    return null;
  end if;
  select * into n
  from public.notes
  where conversation_id = p_conversation_id and pinned and deleted_at is null;
  if n.id is null then
    return null;
  end if;
  return public.note_json(n);
end;
$$;

-- A note with all its blocks, in order.
create or replace function public.get_note(p_note_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  n public.notes%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into n from public.notes where id = p_note_id and deleted_at is null;
  if n.id is null or not public.is_current_user_conversation_member(n.conversation_id) then
    raise exception 'Note not found' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'note', public.note_json(n),
    'blocks', coalesce((
      select jsonb_agg(public.note_block_json(b) order by b.pos, b.id)
      from public.note_blocks b
      where b.note_id = n.id and not b.deleted
    ), '[]'::jsonb)
  );
end;
$$;

-- Starts a note with one empty paragraph. [p_id] lets an offline client
-- create it with an id of its own and send it again safely.
create or replace function public.create_note(
  p_conversation_id uuid,
  p_title text default '',
  p_icon text default null,
  p_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  n public.notes%rowtype;
  new_id uuid := coalesce(p_id, gen_random_uuid());
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into n from public.notes where id = new_id;
  if n.id is not null then
    -- Sent before (the answer got lost).
    if n.created_by is distinct from uid
      or not public.is_current_user_conversation_member(n.conversation_id)
    then
      raise exception 'Note not found' using errcode = 'P0002';
    end if;
    return public.note_json(n);
  end if;

  if not public.can_current_user_write_docs(p_conversation_id) then
    raise exception 'You cannot create notes here' using errcode = '42501';
  end if;
  if (select count(*) from public.notes
      where conversation_id = p_conversation_id and deleted_at is null) >= 200
  then
    raise exception 'This conversation has too many notes' using errcode = '22023';
  end if;
  if char_length(coalesce(p_title, '')) > 200 then
    raise exception 'Title is too long' using errcode = '22023';
  end if;

  insert into public.notes (id, conversation_id, title, icon, created_by, updated_by)
  values (
    new_id,
    p_conversation_id,
    btrim(coalesce(p_title, '')),
    coalesce(nullif(btrim(p_icon), ''), E'\U0001F4DD'),
    uid,
    uid
  )
  returning * into n;

  insert into public.note_blocks (id, note_id, pos, kind, updated_by)
  values (gen_random_uuid(), n.id, 'V', 'paragraph', uid);

  return public.note_json(n);
end;
$$;

-- Changes a note's title, icon, "only managers can edit" or pin. [p_patch]
-- holds the keys to change. Title and icon need edit rights; the other two
-- need a manager.
create or replace function public.update_note_meta(
  p_note_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  n public.notes%rowtype;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_patch, '{}'::jsonb)) <> 'object' then
    raise exception 'Patch must be an object' using errcode = '22023';
  end if;

  select * into n from public.notes where id = p_note_id and deleted_at is null for update;
  if n.id is null or not public.is_current_user_conversation_member(n.conversation_id) then
    raise exception 'Note not found' using errcode = 'P0002';
  end if;

  if p_patch ? 'title' or p_patch ? 'icon' then
    if not public.can_current_user_edit_note(n.id) then
      raise exception 'You cannot edit this note' using errcode = '42501';
    end if;
    if p_patch ? 'title' then
      if char_length(coalesce(p_patch->>'title', '')) > 200 then
        raise exception 'Title is too long' using errcode = '22023';
      end if;
      n.title := btrim(coalesce(p_patch->>'title', ''));
    end if;
    if p_patch ? 'icon' then
      n.icon := coalesce(nullif(btrim(p_patch->>'icon'), ''), E'\U0001F4DD');
      if char_length(n.icon) > 16 then
        raise exception 'Icon is too long' using errcode = '22023';
      end if;
    end if;
  end if;

  if p_patch ? 'managers_only' or p_patch ? 'pinned' then
    if not public.can_current_user_manage_note(n.id) then
      raise exception 'Only managers can change this' using errcode = '42501';
    end if;
    if p_patch ? 'managers_only' then
      n.managers_only := coalesce((p_patch->>'managers_only')::boolean, false);
    end if;
    if p_patch ? 'pinned' then
      n.pinned := coalesce((p_patch->>'pinned')::boolean, false);
      if n.pinned then
        -- One banner per conversation: the new pin replaces the old.
        update public.notes
        set pinned = false
        where conversation_id = n.conversation_id
          and pinned
          and id <> n.id
          and deleted_at is null;
      end if;
    end if;
  end if;

  update public.notes
  set title = n.title,
      icon = n.icon,
      managers_only = n.managers_only,
      pinned = n.pinned,
      updated_by = uid,
      updated_at = now()
  where id = n.id
  returning * into n;

  return public.note_json(n);
end;
$$;

-- Deletes a note (the creator or a manager). Its pictures are listed so the
-- caller can remove them from storage; storage allows that once the note is
-- gone (see 202610170061_note_versions_files).
create or replace function public.delete_note(p_note_id uuid)
returns table (bucket_id text, object_path text)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  uid uuid := auth.uid();
  n public.notes%rowtype;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into n from public.notes where id = p_note_id and deleted_at is null for update;
  if n.id is null or not public.is_current_user_conversation_member(n.conversation_id) then
    raise exception 'Note not found' using errcode = 'P0002';
  end if;
  if n.created_by is distinct from uid
    and not public.can_current_user_manage_note(n.id)
  then
    raise exception 'Only the author or a manager can delete this note'
      using errcode = '42501';
  end if;

  update public.notes
  set deleted_at = now(), pinned = false, updated_by = uid, updated_at = now()
  where id = n.id;

  return query
  select distinct 'note-files'::text, b.props->>'path'
  from public.note_blocks b
  where b.note_id = n.id and b.kind = 'image' and b.props->>'path' is not null;
end;
$$;

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
    if new_kind not in ('paragraph', 'h1', 'h2', 'h3', 'bullet', 'numbered',
         'todo', 'quote', 'code', 'divider', 'image')
      or char_length(new_text) > 20000
      or jsonb_typeof(new_marks) <> 'array'
      or jsonb_array_length(new_marks) > 1000
      or jsonb_typeof(new_props) <> 'object'
      or new_pos is null
      or new_pos !~ '^[0-9A-Za-z]{1,64}$'
      or length(new_props::text) > 4000
    then
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

revoke execute on function public.list_notes(uuid) from public, anon;
revoke execute on function public.get_pinned_note(uuid) from public, anon;
revoke execute on function public.get_note(uuid) from public, anon;
revoke execute on function public.create_note(uuid, text, text, uuid) from public, anon;
revoke execute on function public.update_note_meta(uuid, jsonb) from public, anon;
revoke execute on function public.delete_note(uuid) from public, anon;
revoke execute on function public.note_apply_ops(uuid, jsonb) from public, anon;
grant execute on function public.list_notes(uuid) to authenticated;
grant execute on function public.get_pinned_note(uuid) to authenticated;
grant execute on function public.get_note(uuid) to authenticated;
grant execute on function public.create_note(uuid, text, text, uuid) to authenticated;
grant execute on function public.update_note_meta(uuid, jsonb) to authenticated;
grant execute on function public.delete_note(uuid) to authenticated;
grant execute on function public.note_apply_ops(uuid, jsonb) to authenticated;

-- Realtime: the blocks and the note itself (title, pin, lock).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notes'
    ) then
      alter publication supabase_realtime add table public.notes;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'note_blocks'
    ) then
      alter publication supabase_realtime add table public.note_blocks;
    end if;
  end if;
end;
$$;
