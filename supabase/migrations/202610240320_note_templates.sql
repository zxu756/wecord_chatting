-- Notes 2.0 (roadmap D5), part 3 of 5: note templates.
--
-- A template is the start of a note: an icon, a title and a list of blocks.
-- The built-in ones (meeting notes, weekly report, trip plan, ...) live in
-- the app, in the language of the person using it; this migration holds the
-- personal ones, which only their owner can see or use.
--
-- * save_note_template turns a note the caller can read into a template.
--   Pictures are left out (their files belong to the note they were added
--   to) and so are mentions of people, which mean nothing in a template.
--   At most 30 each.
-- * create_note_from_blocks starts a note in a conversation with a list of
--   blocks, for built-in and personal templates alike. The blocks are
--   checked with note_block_is_valid (the very check note_apply_ops makes);
--   ids and positions are made here, so a template can never overwrite or
--   take over somebody's block. [p_id] makes it safe to send again.
-- * Templates go with the account that owns them.

create table if not exists public.note_templates (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  icon text not null default E'\U0001F4DD',
  title text not null default '',
  blocks jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  constraint note_templates_name_length check (char_length(name) between 1 and 80),
  constraint note_templates_icon_length check (char_length(icon) between 1 and 16),
  constraint note_templates_title_length check (char_length(title) <= 200),
  constraint note_templates_blocks_array check (
    jsonb_typeof(blocks) = 'array' and jsonb_array_length(blocks) <= 200
  )
);

create index if not exists note_templates_owner_idx
  on public.note_templates (owner_id, created_at desc);

alter table public.note_templates enable row level security;
revoke all on public.note_templates from anon, authenticated;
-- Read and written through the functions below only.

-- The ordering key of the [i]th block (from 0) of a new note: "G" and two
-- digits of 1 to 61, so it never ends in 0 and has room before and after.
create or replace function public.note_template_pos(i integer)
returns text
language sql
immutable
set search_path = public
as $$
  select 'G'
    || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (i / 61) + 1, 1)
    || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (i % 61) + 2, 1);
$$;

revoke execute on function public.note_template_pos(integer) from public, anon, authenticated;

-- [marks] without the mentions of people.
create or replace function public.note_marks_without_mentions(marks jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select coalesce(
    jsonb_agg(m) filter (where not (m->>2 like 'm:%')),
    '[]'::jsonb
  )
  from jsonb_array_elements(
    case when jsonb_typeof(marks) = 'array' then marks else '[]'::jsonb end
  ) m;
$$;

revoke execute on function public.note_marks_without_mentions(jsonb) from public, anon, authenticated;

-- The caller's templates, newest first (without their blocks).
create or replace function public.list_note_templates()
returns setof jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  return query
  select jsonb_build_object(
    'id', t.id,
    'name', t.name,
    'icon', t.icon,
    'title', t.title,
    'block_count', jsonb_array_length(t.blocks),
    'created_at', t.created_at
  )
  from public.note_templates t
  where t.owner_id = auth.uid()
  order by t.created_at desc, t.id;
end;
$$;

create or replace function public.get_note_template(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  t public.note_templates%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into t from public.note_templates where id = p_id and owner_id = auth.uid();
  if t.id is null then
    raise exception 'Template not found' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'id', t.id,
    'name', t.name,
    'icon', t.icon,
    'title', t.title,
    'blocks', t.blocks
  );
end;
$$;

-- Makes a template of a note the caller can read.
create or replace function public.save_note_template(
  p_note_id uuid,
  p_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  n public.notes%rowtype;
  t public.note_templates%rowtype;
  template_name text := btrim(coalesce(p_name, ''));
  picked jsonb;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into n from public.notes where id = p_note_id and deleted_at is null;
  if n.id is null or not public.is_current_user_conversation_member(n.conversation_id) then
    raise exception 'Note not found' using errcode = 'P0002';
  end if;
  if char_length(template_name) not between 1 and 80 then
    raise exception 'A template name has 1 to 80 characters' using errcode = '22023';
  end if;
  if (select count(*) from public.note_templates where owner_id = uid) >= 30 then
    raise exception 'You have too many templates' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'kind', b.kind,
      'text', b.text,
      'marks', public.note_marks_without_mentions(b.marks),
      'props', b.props
    )
    order by b.pos, b.id
  ), '[]'::jsonb)
  into picked
  from (
    select *
    from public.note_blocks nb
    where nb.note_id = n.id and not nb.deleted and nb.kind <> 'image'
    order by nb.pos, nb.id
    limit 200
  ) b;

  insert into public.note_templates (owner_id, name, icon, title, blocks)
  values (uid, template_name, n.icon, n.title, picked)
  returning * into t;

  return jsonb_build_object(
    'id', t.id,
    'name', t.name,
    'icon', t.icon,
    'title', t.title,
    'block_count', jsonb_array_length(t.blocks),
    'created_at', t.created_at
  );
end;
$$;

create or replace function public.delete_note_template(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  delete from public.note_templates where id = p_id and owner_id = auth.uid();
end;
$$;

-- Starts a note in [p_conversation_id] with [p_blocks], a list of
-- {kind, text, marks, props}. Same rights as create_note.
create or replace function public.create_note_from_blocks(
  p_conversation_id uuid,
  p_title text,
  p_icon text,
  p_blocks jsonb,
  p_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  made jsonb;
  new_id uuid := coalesce(p_id, gen_random_uuid());
  already boolean;
  blk jsonb;
  i integer := 0;
  b_kind text;
  b_text text;
  b_marks jsonb;
  b_props jsonb;
  b_pos text;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_blocks is null or jsonb_typeof(p_blocks) <> 'array'
    or jsonb_array_length(p_blocks) > 200
  then
    raise exception 'Blocks must be a list of at most 200' using errcode = '22023';
  end if;

  select exists (select 1 from public.notes where id = new_id) into already;
  -- create_note answers a repeat of an earlier send with the note itself.
  made := public.create_note(p_conversation_id, p_title, p_icon, new_id);
  if already or jsonb_array_length(p_blocks) = 0 then
    return made;
  end if;

  -- The note was just made: replace its empty first block.
  delete from public.note_blocks where note_id = new_id;
  for blk in select * from jsonb_array_elements(p_blocks) loop
    b_kind := coalesce(blk->>'kind', 'paragraph');
    b_text := coalesce(blk->>'text', '');
    b_marks := public.note_marks_without_mentions(coalesce(blk->'marks', '[]'::jsonb));
    b_props := coalesce(blk->'props', '{}'::jsonb);
    b_pos := public.note_template_pos(i);
    if jsonb_typeof(blk) <> 'object'
      or b_kind = 'image'
      or not public.note_block_is_valid(b_kind, b_text, b_marks, b_props, b_pos)
    then
      raise exception 'A block of the template is not valid' using errcode = '22023';
    end if;
    insert into public.note_blocks (id, note_id, pos, kind, text, marks, props, updated_by)
    values (gen_random_uuid(), new_id, b_pos, b_kind, b_text, b_marks, b_props, uid);
    i := i + 1;
  end loop;
  return made;
end;
$$;

revoke execute on function public.list_note_templates() from public, anon;
revoke execute on function public.get_note_template(uuid) from public, anon;
revoke execute on function public.save_note_template(uuid, text) from public, anon;
revoke execute on function public.delete_note_template(uuid) from public, anon;
revoke execute on function public.create_note_from_blocks(uuid, text, text, jsonb, uuid) from public, anon;
grant execute on function public.list_note_templates() to authenticated;
grant execute on function public.get_note_template(uuid) to authenticated;
grant execute on function public.save_note_template(uuid, text) to authenticated;
grant execute on function public.delete_note_template(uuid) to authenticated;
grant execute on function public.create_note_from_blocks(uuid, text, text, jsonb, uuid) to authenticated;
