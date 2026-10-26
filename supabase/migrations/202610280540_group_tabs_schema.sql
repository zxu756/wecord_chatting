-- Group tabs (roadmap D8), part 1 of 3: the tables.
--
-- A group or a circle channel can pin its fixed entrances under the chat
-- header as a row of small tabs that scrolls sideways: a note, a task list, a
-- form, a check-in, a link, the circle's knowledge base, the events of the
-- chat, and, once B6 (group space) is merged, the group space. The row is
-- folded by default (the header keeps its 3 or 4 main actions, see the design
-- rule); the app shows it only while the conversation has at least one tab.
--
-- * conversation_tab_kinds: the kinds a tab may have and what each one points
--   at ('id': a row of this conversation, 'url': a web address, 'none': the
--   place itself). Another package adds a kind with one insert into this
--   table (group space: 'space' is already here and needs no target); the
--   client lists the kinds it can open and ignores the others.
-- * conversation_tabs: one row per tab. target is text so it can hold an id
--   or an address. title is up to 40 characters; the app shows the live title
--   of a note, list, form or check-in when the target still stands. Order is
--   `sort`. At most 12 tabs per conversation (add_conversation_tab).
-- * Clients only read (members of the conversation). Adding, renaming,
--   reordering and removing go through the functions of 202610280550, for
--   whoever may pin messages there (the owner and admins of a group, whoever
--   has manage_messages in a channel; can_current_user_pin_messages).
-- * A tab goes when its target does: a note or a list that is deleted, a form
--   or a check-in that is removed.
-- * Only groups and circle channels have tabs (not direct chats or threads).

create table if not exists public.conversation_tab_kinds (
  kind text primary key,
  target_type text not null,
  constraint conversation_tab_kinds_kind_format check (kind ~ '^[a-z][a-z_]{0,23}$'),
  constraint conversation_tab_kinds_target_type check (target_type in ('id', 'url', 'none'))
);

insert into public.conversation_tab_kinds (kind, target_type)
values
  ('note', 'id'),
  ('list', 'id'),
  ('form', 'id'),
  ('check_in', 'id'),
  ('link', 'url'),
  ('kb', 'none'),
  ('events', 'none'),
  ('space', 'none')
on conflict (kind) do nothing;

create table if not exists public.conversation_tabs (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  kind text not null references public.conversation_tab_kinds(kind),
  target text,
  title text not null,
  sort integer not null default 0,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint conversation_tabs_title_length check (char_length(title) between 1 and 40),
  constraint conversation_tabs_target_length check (target is null or char_length(target) <= 500)
);

create index if not exists conversation_tabs_conversation_idx
  on public.conversation_tabs (conversation_id, sort, created_at);
create unique index if not exists conversation_tabs_one_per_target_idx
  on public.conversation_tabs (conversation_id, kind, coalesce(target, ''));

alter table public.conversation_tab_kinds enable row level security;
alter table public.conversation_tabs enable row level security;

revoke all on public.conversation_tab_kinds from anon, authenticated;
revoke all on public.conversation_tabs from anon, authenticated;
grant select on public.conversation_tabs to authenticated;

drop policy if exists conversation_tabs_select on public.conversation_tabs;
create policy conversation_tabs_select on public.conversation_tabs
  for select to authenticated
  using (public.is_current_user_conversation_member(conversation_id));

-- A tab goes when what it points at goes.
create or replace function public.conversation_tabs_drop_target()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  tab_kind text := tg_argv[0];
begin
  delete from public.conversation_tabs t
  where t.kind = tab_kind and t.target = old.id::text;
  return null;
end;
$$;

revoke execute on function public.conversation_tabs_drop_target()
  from public, anon, authenticated;

drop trigger if exists conversation_tabs_note_gone on public.notes;
create trigger conversation_tabs_note_gone
  after update of deleted_at on public.notes
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.conversation_tabs_drop_target('note');

drop trigger if exists conversation_tabs_note_deleted on public.notes;
create trigger conversation_tabs_note_deleted
  after delete on public.notes
  for each row execute function public.conversation_tabs_drop_target('note');

drop trigger if exists conversation_tabs_list_gone on public.task_lists;
create trigger conversation_tabs_list_gone
  after update of deleted_at on public.task_lists
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.conversation_tabs_drop_target('list');

drop trigger if exists conversation_tabs_list_deleted on public.task_lists;
create trigger conversation_tabs_list_deleted
  after delete on public.task_lists
  for each row execute function public.conversation_tabs_drop_target('list');

drop trigger if exists conversation_tabs_form_deleted on public.forms;
create trigger conversation_tabs_form_deleted
  after delete on public.forms
  for each row execute function public.conversation_tabs_drop_target('form');

drop trigger if exists conversation_tabs_check_in_deleted on public.check_in_boards;
create trigger conversation_tabs_check_in_deleted
  after delete on public.check_in_boards
  for each row execute function public.conversation_tabs_drop_target('check_in');
