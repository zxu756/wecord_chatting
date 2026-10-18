-- Security audit (2026-10-19): deleting a note or a task really removes what
-- it said.
--
-- Notes, note blocks, task lists and task items are deleted softly (a
-- deleted_at or deleted flag), so that a late edit is noticed and Realtime
-- can tell the other screens. But the rows kept their content, and the
-- tables are readable by every member of the conversation: someone who
-- deleted a note (or a task, or a block) to take back something they wrote
-- left the text where anyone could still read it through the REST API,
-- through get_note_version / list_note_versions (the version history of a
-- deleted note), and for 30 days (tombstones) in note_blocks.
--
-- The rows stay, as tombstones, but the moment they are deleted:
--   * a note loses its title, its blocks lose their text and marks (props
--     stay: they hold the picture paths delete_note hands back for removal)
--     and its version history is deleted;
--   * a deleted block loses its text and marks;
--   * a deleted task item loses its title (a placeholder, the column cannot
--     be empty) and details; a deleted list loses its title.

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
    set text = '', marks = '[]'::jsonb
    where note_id = new.id and (text <> '' or marks <> '[]'::jsonb);
    delete from public.note_versions where note_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists notes_scrub_deleted on public.notes;
create trigger notes_scrub_deleted
  before update of deleted_at on public.notes
  for each row execute function public.scrub_deleted_note();

create or replace function public.scrub_deleted_note_block()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.deleted and not old.deleted then
    new.text := '';
    new.marks := '[]'::jsonb;
  end if;
  return new;
end;
$$;

drop trigger if exists note_blocks_scrub_deleted on public.note_blocks;
create trigger note_blocks_scrub_deleted
  before update of deleted on public.note_blocks
  for each row execute function public.scrub_deleted_note_block();

create or replace function public.scrub_deleted_task_item()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.deleted_at is null and new.deleted_at is not null then
    new.title := '[deleted]';
    new.details := '';
  end if;
  return new;
end;
$$;

drop trigger if exists task_items_scrub_deleted on public.task_items;
create trigger task_items_scrub_deleted
  before update of deleted_at on public.task_items
  for each row execute function public.scrub_deleted_task_item();

create or replace function public.scrub_deleted_task_list()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.deleted_at is null and new.deleted_at is not null then
    new.title := '';
  end if;
  return new;
end;
$$;

drop trigger if exists task_lists_scrub_deleted on public.task_lists;
create trigger task_lists_scrub_deleted
  before update of deleted_at on public.task_lists
  for each row execute function public.scrub_deleted_task_list();

revoke execute on function public.scrub_deleted_note() from public, anon, authenticated;
revoke execute on function public.scrub_deleted_note_block() from public, anon, authenticated;
revoke execute on function public.scrub_deleted_task_item() from public, anon, authenticated;
revoke execute on function public.scrub_deleted_task_list() from public, anon, authenticated;

-- What was deleted before this migration is scrubbed now.
update public.note_blocks b
set text = '', marks = '[]'::jsonb
where (b.text <> '' or b.marks <> '[]'::jsonb)
  and (b.deleted or exists (
    select 1 from public.notes n where n.id = b.note_id and n.deleted_at is not null
  ));
update public.notes set title = '' where deleted_at is not null and title <> '';
delete from public.note_versions v
using public.notes n
where n.id = v.note_id and n.deleted_at is not null;
update public.task_items set title = '[deleted]', details = ''
where deleted_at is not null and (title <> '[deleted]' or details <> '');
update public.task_lists set title = '' where deleted_at is not null and title <> '';
