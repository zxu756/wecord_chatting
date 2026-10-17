-- Notes, part two: version history, pictures, sharing into chat and search.
--
-- * note_versions keeps snapshots of a note (title, icon and every block).
--   note_apply_ops takes one automatically before a new burst of work (see
--   202610170060_notes); create_note_version takes one on demand. Only the
--   newest 100 are kept, automatic ones go first.
--   restore_note_version brings a snapshot back: blocks of the snapshot come
--   back with their own ids (so everyone's open editor simply sees them
--   change), blocks that are not in it are removed. The state before the
--   restore is snapshotted first, so a restore can itself be undone.
-- * Bucket note-files (private, pictures up to 10 MB) holds a note's pictures
--   under <note id>/…, like chat-files: whoever can see the note's
--   conversation can read them, whoever can edit the note can upload. They
--   are only removed once the note is deleted.
-- * share_note posts a note into its conversation (or a thread of it) as a
--   card: a text message whose body is "<icon> <title>" (so search, previews
--   and pushes just work) and whose attachment is
--   {kind: 'note', note_id, title, icon}.
-- * search_notes finds notes by title across the conversations the caller
--   can see, for the quick switcher.

create table if not exists public.note_versions (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null references public.notes(id) on delete cascade,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  -- 'auto' | 'manual' | 'restore'
  kind text not null default 'auto',
  label text,
  title text not null default '',
  icon text not null default E'\U0001F4DD',
  -- [{id, pos, kind, text, marks, props}] in document order.
  blocks jsonb not null default '[]'::jsonb,
  constraint note_versions_kind check (kind in ('auto', 'manual', 'restore')),
  constraint note_versions_label_length check (label is null or char_length(label) <= 120)
);

create index if not exists note_versions_note_idx
  on public.note_versions (note_id, created_at desc);

alter table public.note_versions enable row level security;
revoke all on public.note_versions from anon, authenticated;
-- Read through list_note_versions / get_note_version only.

-- Internal: stores a snapshot of the note's current state.
create or replace function public.snapshot_note(
  target_note_id uuid,
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
  n public.notes%rowtype;
  version_id uuid;
begin
  select * into n from public.notes where id = target_note_id;
  if n.id is null then
    return null;
  end if;

  insert into public.note_versions (note_id, created_by, kind, label, title, icon, blocks)
  values (
    n.id,
    by_user,
    snapshot_kind,
    snapshot_label,
    n.title,
    n.icon,
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', b.id, 'pos', b.pos, 'kind', b.kind, 'text', b.text,
          'marks', b.marks, 'props', b.props
        )
        order by b.pos, b.id
      )
      from public.note_blocks b
      where b.note_id = n.id and not b.deleted
    ), '[]'::jsonb)
  )
  returning id into version_id;

  update public.notes set last_snapshot_at = now() where id = n.id;

  -- Keep the newest 100; automatic snapshots are dropped first.
  delete from public.note_versions v
  where v.note_id = n.id
    and v.id in (
      select old.id
      from public.note_versions old
      where old.note_id = n.id
      order by (old.kind = 'auto') desc, old.created_at asc
      offset 0
      limit greatest(
        (select count(*) from public.note_versions c where c.note_id = n.id) - 100,
        0
      )
    );

  return version_id;
end;
$$;

revoke execute on function public.snapshot_note(uuid, uuid, text, text) from public, anon, authenticated;

-- A snapshot on demand, with an optional name.
create or replace function public.create_note_version(
  p_note_id uuid,
  p_label text default null
)
returns uuid
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
  select * into n from public.notes where id = p_note_id and deleted_at is null for update;
  if n.id is null or not public.is_current_user_conversation_member(n.conversation_id) then
    raise exception 'Note not found' using errcode = 'P0002';
  end if;
  if not public.can_current_user_edit_note(n.id) then
    raise exception 'You cannot edit this note' using errcode = '42501';
  end if;
  if char_length(coalesce(p_label, '')) > 120 then
    raise exception 'Name is too long' using errcode = '22023';
  end if;
  return public.snapshot_note(n.id, uid, nullif(btrim(p_label), ''), 'manual');
end;
$$;

create or replace function public.list_note_versions(p_note_id uuid)
returns table (
  id uuid,
  created_at timestamptz,
  created_by uuid,
  created_by_name text,
  kind text,
  label text,
  title text,
  block_count integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  if auth.uid() is null or not public.can_current_user_view_note(p_note_id) then
    raise exception 'Note not found' using errcode = 'P0002';
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
    jsonb_array_length(v.blocks)
  from public.note_versions v
  left join public.profiles p on p.id = v.created_by
  where v.note_id = p_note_id
  order by v.created_at desc, v.id;
end;
$$;

create or replace function public.get_note_version(p_version_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v public.note_versions%rowtype;
begin
  select * into v from public.note_versions where id = p_version_id;
  if auth.uid() is null or v.id is null
    or not public.can_current_user_view_note(v.note_id)
  then
    raise exception 'Version not found' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'id', v.id,
    'note_id', v.note_id,
    'created_at', v.created_at,
    'kind', v.kind,
    'label', v.label,
    'title', v.title,
    'icon', v.icon,
    'blocks', v.blocks
  );
end;
$$;

create or replace function public.restore_note_version(p_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  v public.note_versions%rowtype;
  n public.notes%rowtype;
  blk jsonb;
  kept uuid[] := array[]::uuid[];
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into v from public.note_versions where id = p_version_id;
  if v.id is null then
    raise exception 'Version not found' using errcode = 'P0002';
  end if;
  select * into n from public.notes where id = v.note_id and deleted_at is null for update;
  if n.id is null or not public.is_current_user_conversation_member(n.conversation_id) then
    raise exception 'Note not found' using errcode = 'P0002';
  end if;
  if not public.can_current_user_edit_note(n.id) then
    raise exception 'You cannot edit this note' using errcode = '42501';
  end if;

  perform public.snapshot_note(n.id, uid, null, 'restore');

  for blk in select * from jsonb_array_elements(v.blocks) loop
    kept := kept || (blk->>'id')::uuid;
    insert into public.note_blocks (id, note_id, pos, kind, text, marks, props, updated_by)
    values (
      (blk->>'id')::uuid, n.id, blk->>'pos', blk->>'kind', coalesce(blk->>'text', ''),
      coalesce(blk->'marks', '[]'::jsonb), coalesce(blk->'props', '{}'::jsonb), uid
    )
    on conflict (id) do update
    set pos = excluded.pos,
        kind = excluded.kind,
        text = excluded.text,
        marks = excluded.marks,
        props = excluded.props,
        deleted = false,
        rev = public.note_blocks.rev + 1,
        updated_by = uid,
        updated_at = now()
    where public.note_blocks.note_id = n.id;
  end loop;

  update public.note_blocks
  set deleted = true, rev = rev + 1, updated_by = uid, updated_at = now()
  where note_id = n.id and not deleted and not (id = any (kept));

  -- An empty snapshot still leaves one block to type into.
  if not exists (select 1 from public.note_blocks where note_id = n.id and not deleted) then
    insert into public.note_blocks (id, note_id, pos, kind, updated_by)
    values (gen_random_uuid(), n.id, 'V', 'paragraph', uid);
  end if;

  update public.notes
  set title = v.title, icon = v.icon, updated_by = uid, updated_at = now(),
      last_snapshot_at = now()
  where id = n.id
  returning * into n;

  return public.note_json(n);
end;
$$;

-- Same as 202610170060_notes, plus pictures kept in old versions.
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
  select distinct 'note-files'::text, found.path
  from (
    select b.props->>'path' as path
    from public.note_blocks b
    where b.note_id = n.id and b.kind = 'image'
    union all
    select blk->'props'->>'path'
    from public.note_versions v
    cross join lateral jsonb_array_elements(v.blocks) blk
    where v.note_id = n.id and blk->>'kind' = 'image'
  ) found
  where found.path is not null;
end;
$$;

revoke execute on function public.create_note_version(uuid, text) from public, anon;
revoke execute on function public.list_note_versions(uuid) from public, anon;
revoke execute on function public.get_note_version(uuid) from public, anon;
revoke execute on function public.restore_note_version(uuid) from public, anon;
revoke execute on function public.delete_note(uuid) from public, anon;
grant execute on function public.create_note_version(uuid, text) to authenticated;
grant execute on function public.list_note_versions(uuid) to authenticated;
grant execute on function public.get_note_version(uuid) to authenticated;
grant execute on function public.restore_note_version(uuid) to authenticated;
grant execute on function public.delete_note(uuid) to authenticated;

-- Pictures ---------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'note-files', 'note-files', false, 10485760,
  array['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- The note a storage path belongs to (<note id>/<file>), or null.
create or replace function public.note_file_note_id(object_name text)
returns uuid
language sql
immutable
set search_path = public
as $$
  select case
    when object_name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/[^/]+$'
      then split_part(object_name, '/', 1)::uuid
  end;
$$;

-- Whether the current user may remove a note's pictures: the note is
-- deleted and they are its author or manage the conversation.
create or replace function public.can_current_user_delete_note_files(target_note_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  n public.notes%rowtype;
begin
  if auth.uid() is null or target_note_id is null then
    return false;
  end if;
  select * into n from public.notes where id = target_note_id;
  return n.id is not null
    and n.deleted_at is not null
    and public.is_current_user_conversation_member(n.conversation_id)
    and (
      n.created_by = auth.uid()
      or public.can_current_user_moderate_messages(n.conversation_id)
    );
end;
$$;

revoke execute on function public.note_file_note_id(text) from public, anon;
revoke execute on function public.can_current_user_delete_note_files(uuid) from public, anon;
grant execute on function public.note_file_note_id(text) to authenticated;
grant execute on function public.can_current_user_delete_note_files(uuid) to authenticated;

drop policy if exists note_files_select_member on storage.objects;
create policy note_files_select_member
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'note-files'
    and public.note_file_note_id(name) is not null
    and public.can_current_user_view_note(public.note_file_note_id(name))
  );

drop policy if exists note_files_insert_editor on storage.objects;
create policy note_files_insert_editor
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'note-files'
    and public.note_file_note_id(name) is not null
    and public.can_current_user_edit_note(public.note_file_note_id(name))
  );

drop policy if exists note_files_delete_deleted_note on storage.objects;
create policy note_files_delete_deleted_note
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'note-files'
    and public.can_current_user_delete_note_files(public.note_file_note_id(name))
  );

-- Sharing and search -------------------------------------------------------

-- Posts the note as a card into [p_conversation_id]: the note's own
-- conversation or a thread of it.
create or replace function public.share_note(
  p_note_id uuid,
  p_conversation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  n public.notes%rowtype;
  label text;
  message_id uuid;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into n from public.notes where id = p_note_id and deleted_at is null;
  if n.id is null or not public.is_current_user_conversation_member(n.conversation_id) then
    raise exception 'Note not found' using errcode = 'P0002';
  end if;
  if p_conversation_id is distinct from n.conversation_id and not exists (
    select 1
    from public.conversation_threads t
    where t.conversation_id = p_conversation_id
      and t.parent_conversation_id = n.conversation_id
  ) then
    raise exception 'A note can only be shared where it lives' using errcode = '22023';
  end if;
  if not public.can_current_user_send_in_conversation(p_conversation_id) then
    raise exception 'You cannot send messages here' using errcode = '42501';
  end if;
  if public.is_current_user_blocked_in_conversation(p_conversation_id) then
    raise exception 'Cannot send messages in this conversation' using errcode = '42501';
  end if;

  label := n.icon || ' ' || coalesce(nullif(btrim(n.title), ''), 'Untitled note');

  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (
    p_conversation_id,
    uid,
    'text',
    label,
    jsonb_build_object(
      'kind', 'note',
      'note_id', n.id,
      'title', n.title,
      'icon', n.icon
    )
  )
  returning id into message_id;

  return message_id;
end;
$$;

-- Notes whose title contains [p_query], newest first, in conversations the
-- caller can see. Blank query: the most recently edited ones.
create or replace function public.search_notes(
  p_query text,
  p_limit integer default 20
)
returns table (
  id uuid,
  conversation_id uuid,
  title text,
  icon text,
  updated_at timestamptz,
  conversation_type text,
  conversation_title text,
  circle_id uuid,
  circle_name text
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  pattern text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  pattern := '%' || replace(replace(replace(lower(btrim(coalesce(p_query, ''))), '\', '\\'), '%', '\%'), '_', '\_') || '%';

  return query
  select
    n.id,
    n.conversation_id,
    n.title,
    n.icon,
    n.updated_at,
    c.type,
    c.title,
    cc.circle_id,
    ci.name
  from public.notes n
  join public.conversation_members cm
    on cm.conversation_id = n.conversation_id and cm.user_id = auth.uid()
  join public.conversations c on c.id = n.conversation_id
  left join public.circle_channels cc on cc.conversation_id = n.conversation_id
  left join public.circles ci on ci.id = cc.circle_id
  where n.deleted_at is null
    and lower(n.title) like pattern escape '\'
    and public.is_current_user_conversation_member(n.conversation_id)
  order by n.updated_at desc, n.id
  limit greatest(1, least(coalesce(p_limit, 20), 50));
end;
$$;

revoke execute on function public.share_note(uuid, uuid) from public, anon;
revoke execute on function public.search_notes(text, integer) from public, anon;
grant execute on function public.share_note(uuid, uuid) to authenticated;
grant execute on function public.search_notes(text, integer) to authenticated;
