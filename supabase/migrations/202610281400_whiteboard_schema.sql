-- Whiteboard (roadmap D10), part 1 of 6: the tables and who may do what.
--
-- A whiteboard is a shared canvas that lives in a conversation (a group, a
-- circle channel or a direct chat), next to its notes and lists. People draw
-- with a pen or a highlighter, put down shapes, sticky notes, text and
-- pictures, move them around and rub them out, all at the same time.
--
-- * whiteboards: one row per board (title, "only managers can edit", the
--   creator, a count and a size that the limits below read).
-- * whiteboard_elements: one row per thing on the board, like note_blocks are
--   one row per block of a note, so people only collide when they touch the
--   same element:
--     - z is a fractional ordering key (base 62, C collation, the very keys
--       of notes): what is drawn later gets a key after the others; "bring to
--       front" gets one after the last, "send to back" one before the first.
--     - rev is the element's revision. whiteboard_apply_ops takes the
--       revision a change was based on; when the element moved on meanwhile
--       the change is NOT applied and the current element comes back, so the
--       client can merge it (key by key, see
--       lib/features/whiteboard/whiteboard_merge.dart) and send it again.
--       A stroke is never edited after it is drawn, only moved, so strokes
--       merge by construction (they only ever get added or removed).
--     - deleted elements stay as tombstones (data emptied, rev kept), so an
--       edit that arrives late for a rubbed-out element is noticed rather
--       than bringing it back, and "undo" of a rub-out can revive it with the
--       revision it saw (see whiteboard_apply_ops).
--     - data holds what the kind needs, in board units (1 unit is one point
--       at 100% zoom; the board has no edge but stays within +-100000):
--         stroke  p: flat [x0, y0, x1, y1, ...] (up to 2000 points), pr: a
--                 pressure 0..100 per point (optional), c: ARGB color, sw:
--                 width, hl: highlighter, ox/oy: how far it was moved
--         shape   s: rect | ellipse | triangle | diamond | line | arrow,
--                 x, y, w, h (for a line or an arrow w and h can be
--                 negative: the end point is x + w, y + h), r: rotation in
--                 radians, c: line color, f: fill color, sw: line width
--         sticky  x, y, w, h, c: color, t: text (up to 1000 characters), r
--         text    x, y, w (box width, optional), t (up to 2000), fs: font
--                 size, c, a: align (l, c, r), r
--         image   x, y, w, h, r, path: a file of the whiteboard-files bucket
-- * Both tables are read-only for clients (row level security lets members
--   read so that Realtime can deliver the changes); everything is written by
--   the functions of the next files.
--
-- Limits, kept by the database (never only by the app):
--   * 3000 elements and 6 MB of element data per board;
--   * a stroke of up to 2000 points (40000 characters of data), any other
--     element up to 6000 characters;
--   * 20 boards per conversation, a title of up to 100 characters.
--
-- Who may do what:
--   * view: anyone who can see the conversation
--     (is_current_user_conversation_member, which already asks view_channel
--     for a circle channel and counts a suspended circle (K1) as no
--     membership);
--   * edit: anyone who can send messages there and is not blocked in a
--     direct chat (can_current_user_write_docs), and, when the board is
--     "only managers can edit", the holders of manage_messages in the channel
--     or the admins of a group (can_current_user_moderate_messages);
--   * manage (lock a board, clear it, restore a version): the same managers.
--     The creator can also rename, clear and delete their own board.

create table if not exists public.whiteboards (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  title text not null default '',
  managers_only boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- When the last automatic or manual snapshot was taken.
  last_snapshot_at timestamptz,
  -- Live elements and the characters of their data (the limits read these).
  element_count integer not null default 0,
  data_size integer not null default 0,
  deleted_at timestamptz,
  constraint whiteboards_title_length check (char_length(title) <= 100),
  constraint whiteboards_counts check (element_count >= 0 and data_size >= 0)
);

create index if not exists whiteboards_conversation_idx
  on public.whiteboards (conversation_id, updated_at desc)
  where deleted_at is null;

create table if not exists public.whiteboard_elements (
  id uuid primary key,
  board_id uuid not null references public.whiteboards(id) on delete cascade,
  z text not null collate "C",
  kind text not null,
  data jsonb not null default '{}'::jsonb,
  rev integer not null default 1,
  deleted boolean not null default false,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint whiteboard_elements_kind check (
    kind in ('stroke', 'shape', 'sticky', 'text', 'image')
  ),
  constraint whiteboard_elements_z check (z ~ '^[0-9A-Za-z]{1,64}$'),
  constraint whiteboard_elements_data_object check (jsonb_typeof(data) = 'object')
);

create index if not exists whiteboard_elements_board_idx
  on public.whiteboard_elements (board_id, z, id);

alter table public.whiteboards enable row level security;
alter table public.whiteboard_elements enable row level security;

revoke all on public.whiteboards from anon, authenticated;
revoke all on public.whiteboard_elements from anon, authenticated;
grant select on public.whiteboards to authenticated;
grant select on public.whiteboard_elements to authenticated;

drop policy if exists whiteboards_select_member on public.whiteboards;
create policy whiteboards_select_member
  on public.whiteboards for select
  to authenticated
  using (public.is_current_user_conversation_member(conversation_id));

-- Asked once per streamed row; the board lookup is by primary key.
create or replace function public.can_current_user_view_whiteboard(
  target_board_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.whiteboards w
      where w.id = target_board_id
        and public.is_current_user_conversation_member(w.conversation_id)
    );
$$;

drop policy if exists whiteboard_elements_select_member on public.whiteboard_elements;
create policy whiteboard_elements_select_member
  on public.whiteboard_elements for select
  to authenticated
  using (public.can_current_user_view_whiteboard(board_id));

-- Whether the current user may draw on the board.
create or replace function public.can_current_user_edit_whiteboard(
  target_board_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  w public.whiteboards%rowtype;
begin
  if auth.uid() is null then
    return false;
  end if;
  select * into w from public.whiteboards where id = target_board_id;
  if w.id is null or w.deleted_at is not null then
    return false;
  end if;
  if public.is_user_suspended(auth.uid()) then
    return false;
  end if;
  if not public.is_current_user_conversation_member(w.conversation_id)
    or not public.can_current_user_write_docs(w.conversation_id)
  then
    return false;
  end if;
  if w.managers_only then
    return public.can_current_user_moderate_messages(w.conversation_id);
  end if;
  return true;
end;
$$;

-- Whether the current user manages whiteboards in the board's conversation:
-- locks them to managers, clears them, restores older versions, deletes
-- anyone's.
create or replace function public.can_current_user_manage_whiteboard(
  target_board_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  w public.whiteboards%rowtype;
begin
  if auth.uid() is null then
    return false;
  end if;
  select * into w from public.whiteboards where id = target_board_id;
  if w.id is null or w.deleted_at is not null then
    return false;
  end if;
  return public.is_current_user_conversation_member(w.conversation_id)
    and public.can_current_user_moderate_messages(w.conversation_id);
end;
$$;

revoke execute on function public.can_current_user_view_whiteboard(uuid) from public, anon;
revoke execute on function public.can_current_user_edit_whiteboard(uuid) from public, anon;
revoke execute on function public.can_current_user_manage_whiteboard(uuid) from public, anon;
grant execute on function public.can_current_user_view_whiteboard(uuid) to authenticated;
grant execute on function public.can_current_user_edit_whiteboard(uuid) to authenticated;
grant execute on function public.can_current_user_manage_whiteboard(uuid) to authenticated;

-- ------------------------------------------------------------- validation

-- Whether [p_value] is a JSON number inside [low, high].
create or replace function public.whiteboard_number_ok(
  p_value jsonb,
  p_low numeric,
  p_high numeric
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select case
    when jsonb_typeof(p_value) = 'number'
      then (p_value #>> '{}')::numeric between p_low and p_high
    else false
  end;
$$;

-- The rules for one element, the same for every way an element gets in
-- (whiteboard_apply_ops, restoring a version).
create or replace function public.whiteboard_element_is_valid(
  p_kind text,
  p_data jsonb,
  p_z text
)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  key text;
  points integer;
  size_limit integer;
begin
  if p_kind is null
    or p_kind not in ('stroke', 'shape', 'sticky', 'text', 'image')
    or p_data is null
    or jsonb_typeof(p_data) <> 'object'
    or p_z is null
    or p_z !~ '^[0-9A-Za-z]{1,64}$'
  then
    return false;
  end if;

  -- Only the keys the kinds use.
  if (p_data - array[
    'x', 'y', 'w', 'h', 'r', 'c', 'f', 'sw', 's', 't', 'fs', 'p', 'pr',
    'hl', 'ox', 'oy', 'path', 'a'
  ]) <> '{}'::jsonb then
    return false;
  end if;

  size_limit := case p_kind when 'stroke' then 40000 else 6000 end;
  if length(p_data::text) > size_limit then
    return false;
  end if;

  -- Coordinates, sizes and the like.
  for key in select unnest(array['x', 'y', 'w', 'h', 'ox', 'oy']) loop
    if p_data ? key and not public.whiteboard_number_ok(p_data -> key, -100000, 100000) then
      return false;
    end if;
  end loop;
  if p_data ? 'r' and not public.whiteboard_number_ok(p_data -> 'r', -100, 100) then
    return false;
  end if;
  if p_data ? 'sw' and not public.whiteboard_number_ok(p_data -> 'sw', 0.5, 200) then
    return false;
  end if;
  if p_data ? 'fs' and not public.whiteboard_number_ok(p_data -> 'fs', 4, 400) then
    return false;
  end if;
  for key in select unnest(array['c', 'f']) loop
    if p_data ? key and not public.whiteboard_number_ok(p_data -> key, 0, 4294967295) then
      return false;
    end if;
  end loop;
  if p_data ? 'hl' and jsonb_typeof(p_data -> 'hl') <> 'boolean' then
    return false;
  end if;
  if p_data ? 'a' and (p_data ->> 'a') not in ('l', 'c', 'r') then
    return false;
  end if;

  if p_kind = 'stroke' then
    if jsonb_typeof(p_data -> 'p') is distinct from 'array' then
      return false;
    end if;
    points := jsonb_array_length(p_data -> 'p');
    if points < 2 or points > 4000 or points % 2 <> 0 then
      return false;
    end if;
    if jsonb_path_exists(
      p_data -> 'p',
      '$[*] ? (@.type() != "number" || @ < -100000 || @ > 100000)'
    ) then
      return false;
    end if;
    if p_data ? 'pr' then
      if jsonb_typeof(p_data -> 'pr') <> 'array'
        or jsonb_array_length(p_data -> 'pr') <> points / 2
        or jsonb_path_exists(
          p_data -> 'pr',
          '$[*] ? (@.type() != "number" || @ < 0 || @ > 100)'
        )
      then
        return false;
      end if;
    end if;
    return true;
  end if;

  if p_data ? 'p' or p_data ? 'pr' then
    return false;
  end if;

  if p_kind = 'shape' then
    return coalesce((p_data ->> 's') in ('rect', 'ellipse', 'triangle', 'diamond', 'line', 'arrow')
      and public.whiteboard_number_ok(p_data -> 'x', -100000, 100000)
      and public.whiteboard_number_ok(p_data -> 'y', -100000, 100000)
      and public.whiteboard_number_ok(p_data -> 'w', -100000, 100000)
      and public.whiteboard_number_ok(p_data -> 'h', -100000, 100000), false);
  end if;

  if p_kind = 'sticky' then
    return public.whiteboard_number_ok(p_data -> 'x', -100000, 100000)
      and public.whiteboard_number_ok(p_data -> 'y', -100000, 100000)
      and public.whiteboard_number_ok(p_data -> 'w', 20, 100000)
      and public.whiteboard_number_ok(p_data -> 'h', 20, 100000)
      and (not (p_data ? 't') or (
        jsonb_typeof(p_data -> 't') = 'string'
        and char_length(p_data ->> 't') <= 1000
      ));
  end if;

  if p_kind = 'text' then
    return public.whiteboard_number_ok(p_data -> 'x', -100000, 100000)
      and public.whiteboard_number_ok(p_data -> 'y', -100000, 100000)
      and coalesce(jsonb_typeof(p_data -> 't') = 'string'
        and char_length(p_data ->> 't') <= 2000, false)
      and (not (p_data ? 'w') or public.whiteboard_number_ok(p_data -> 'w', 10, 100000));
  end if;

  -- image
  return public.whiteboard_number_ok(p_data -> 'x', -100000, 100000)
    and public.whiteboard_number_ok(p_data -> 'y', -100000, 100000)
    and public.whiteboard_number_ok(p_data -> 'w', 4, 100000)
    and public.whiteboard_number_ok(p_data -> 'h', 4, 100000)
    and coalesce(jsonb_typeof(p_data -> 'path') = 'string'
      and (p_data ->> 'path') ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/[^/]{1,120}$', false);
end;
$$;

revoke execute on function public.whiteboard_number_ok(jsonb, numeric, numeric)
  from public, anon, authenticated;
revoke execute on function public.whiteboard_element_is_valid(text, jsonb, text)
  from public, anon, authenticated;

-- ------------------------------------------------------------------ JSON

create or replace function public.whiteboard_json(w public.whiteboards)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', w.id,
    'conversation_id', w.conversation_id,
    'title', w.title,
    'managers_only', w.managers_only,
    'created_by', w.created_by,
    'updated_by', w.updated_by,
    'created_at', w.created_at,
    'updated_at', w.updated_at,
    'element_count', w.element_count,
    'can_edit', public.can_current_user_edit_whiteboard(w.id),
    'can_manage', public.can_current_user_manage_whiteboard(w.id)
      or (w.created_by is not null and w.created_by = auth.uid())
  );
$$;

create or replace function public.whiteboard_element_json(e public.whiteboard_elements)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select jsonb_build_object(
    'id', e.id,
    'board_id', e.board_id,
    'z', e.z,
    'kind', e.kind,
    'data', e.data,
    'rev', e.rev,
    'deleted', e.deleted,
    'updated_by', e.updated_by
  );
$$;

revoke execute on function public.whiteboard_json(public.whiteboards)
  from public, anon, authenticated;
revoke execute on function public.whiteboard_element_json(public.whiteboard_elements)
  from public, anon, authenticated;

-- Realtime: the elements and the board itself (title, lock, deletion).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'whiteboards'
    ) then
      alter publication supabase_realtime add table public.whiteboards;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'whiteboard_elements'
    ) then
      alter publication supabase_realtime add table public.whiteboard_elements;
    end if;
  end if;
end;
$$;
