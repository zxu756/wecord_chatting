-- Whiteboard (roadmap D10), part 2 of 6: versions.
--
-- A snapshot of a board is its live elements as they were: whiteboard_apply_ops
-- takes one before a new burst of work (the board was quiet for 10 minutes,
-- or has been worked on for 30 minutes without one), clearing a board and
-- restoring a version take one first, and anyone who can draw can take one by
-- hand with a name. Restoring is therefore never a one-way street: the state
-- before it is the newest version.
--
-- Only the newest 8 versions of a board are kept (a manual one outlives the
-- automatic ones), so a big board does not pile up copies of itself. A
-- version holds [{id, z, kind, data}] in drawing order, no pictures of its
-- own: a picture element points at a file of the whiteboard-files bucket,
-- which stays until the board is deleted.
--
-- The table is closed to clients; list_whiteboard_versions shows the rest of
-- the people what they can go back to.

create table if not exists public.whiteboard_versions (
  id uuid primary key default gen_random_uuid(),
  board_id uuid not null references public.whiteboards(id) on delete cascade,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  -- 'auto' | 'manual' | 'restore' (taken just before a restore or a clear)
  kind text not null default 'auto',
  label text,
  title text not null default '',
  element_count integer not null default 0,
  elements jsonb not null default '[]'::jsonb,
  constraint whiteboard_versions_kind check (kind in ('auto', 'manual', 'restore')),
  constraint whiteboard_versions_label_length check (label is null or char_length(label) <= 120),
  constraint whiteboard_versions_elements_array check (jsonb_typeof(elements) = 'array')
);

create index if not exists whiteboard_versions_board_idx
  on public.whiteboard_versions (board_id, created_at desc);

alter table public.whiteboard_versions enable row level security;
revoke all on public.whiteboard_versions from anon, authenticated;

-- Internal: stores a snapshot of the board's current state.
create or replace function public.snapshot_whiteboard(
  target_board_id uuid,
  by_user uuid,
  snapshot_label text,
  snapshot_kind text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  w public.whiteboards%rowtype;
  version_id uuid;
begin
  select * into w from public.whiteboards where id = target_board_id;
  if w.id is null then
    return null;
  end if;

  insert into public.whiteboard_versions (
    board_id, created_by, kind, label, title, element_count, elements
  )
  select
    w.id,
    by_user,
    snapshot_kind,
    snapshot_label,
    w.title,
    count(*),
    coalesce(
      jsonb_agg(
        jsonb_build_object('id', e.id, 'z', e.z, 'kind', e.kind, 'data', e.data)
        order by e.z, e.id
      ),
      '[]'::jsonb
    )
  from public.whiteboard_elements e
  where e.board_id = w.id and not e.deleted
  returning id into version_id;

  update public.whiteboards set last_snapshot_at = now() where id = w.id;

  -- Keep the newest 8; automatic snapshots are dropped first.
  delete from public.whiteboard_versions v
  where v.id in (
    select old.id
    from public.whiteboard_versions old
    where old.board_id = w.id
    order by (old.kind = 'auto') desc, old.created_at asc
    limit greatest(
      (select count(*) from public.whiteboard_versions c where c.board_id = w.id) - 8,
      0
    )
  );

  return version_id;
end;
$$;

revoke execute on function public.snapshot_whiteboard(uuid, uuid, text, text)
  from public, anon, authenticated;

-- A snapshot on demand, with an optional name.
create or replace function public.create_whiteboard_version(
  p_board_id uuid,
  p_label text default null
)
returns uuid
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
  if not public.can_current_user_edit_whiteboard(w.id) then
    raise exception 'You cannot edit this whiteboard' using errcode = '42501';
  end if;
  if char_length(coalesce(p_label, '')) > 120 then
    raise exception 'Name is too long' using errcode = '22023';
  end if;
  return public.snapshot_whiteboard(w.id, uid, nullif(btrim(p_label), ''), 'manual');
end;
$$;

create or replace function public.list_whiteboard_versions(p_board_id uuid)
returns table (
  id uuid,
  created_at timestamptz,
  created_by uuid,
  created_by_name text,
  kind text,
  label text,
  title text,
  element_count integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  if auth.uid() is null or not public.can_current_user_view_whiteboard(p_board_id) then
    raise exception 'Whiteboard not found' using errcode = 'P0002';
  end if;
  return query
  select
    v.id,
    v.created_at,
    v.created_by,
    coalesce(nullif(btrim(p.display_name), ''), p.username),
    v.kind,
    v.label,
    v.title,
    v.element_count
  from public.whiteboard_versions v
  left join public.profiles p on p.id = v.created_by
  where v.board_id = p_board_id
  order by v.created_at desc, v.id;
end;
$$;

-- One version with its elements, to look at before going back to it.
create or replace function public.get_whiteboard_version(p_version_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v public.whiteboard_versions%rowtype;
begin
  select * into v from public.whiteboard_versions where id = p_version_id;
  if auth.uid() is null or v.id is null
    or not public.can_current_user_view_whiteboard(v.board_id)
  then
    raise exception 'Version not found' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'id', v.id,
    'board_id', v.board_id,
    'created_at', v.created_at,
    'kind', v.kind,
    'label', v.label,
    'title', v.title,
    'elements', v.elements
  );
end;
$$;

revoke execute on function public.create_whiteboard_version(uuid, text) from public, anon;
revoke execute on function public.list_whiteboard_versions(uuid) from public, anon;
revoke execute on function public.get_whiteboard_version(uuid) from public, anon;
grant execute on function public.create_whiteboard_version(uuid, text) to authenticated;
grant execute on function public.list_whiteboard_versions(uuid) to authenticated;
grant execute on function public.get_whiteboard_version(uuid) to authenticated;
