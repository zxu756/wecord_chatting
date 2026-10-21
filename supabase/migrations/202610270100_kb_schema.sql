-- Circle knowledge base (roadmap D6), part 1 of 4: pages that belong to a
-- circle, and who may read and write them.
--
-- A knowledge base page is a note (public.notes) that belongs to a circle
-- instead of a conversation: it has circle_id and no conversation_id, and
-- sits in a tree through parent_id. Everything that already works for notes
-- works for a page: blocks and the merge rules (note_apply_ops), tables,
-- pictures, history and its restore, presence in the editor. Chat-only
-- features do not apply to a page and refuse it (a page has no conversation,
-- so sharing it into a chat, comments, publishing it on the web, pinning it
-- and "only managers can edit" all answer "Note not found" or are refused).
--
-- Who may do what (kb_user_access, asked by every policy and function):
--   * read: any member of the circle, unless the page, or a page above it,
--     is limited to some roles (view_role_ids): then only holders of one of
--     those roles, holders of an edit role of it, and managers;
--   * edit the words: managers (manage_channels, which the owner and
--     administrators have) and holders of a role in edit_role_ids of the page
--     or of a page above it; a timed-out member can only read (as for
--     messages, see 202610140004);
--   * create a top-level page, move, reorder, delete, and change who can see
--     or edit a page: managers. A person who may edit a page may also add
--     pages below it.
--   * rank: whoever limits a page records their own rank in the circle
--     (restrict_rank). Changing or lifting that limit, moving the page out of
--     it, or deleting it takes at least that rank (the owner outranks all),
--     like the role rules. The words of a page stay editable by every manager.
--   * a circle taken down by an admin (K1, Suspend) shows nothing and takes
--     no writes; one that is only delisted works as before.
-- Pages inherit the limits of the pages above them (a limited section hides
-- everything in it). At most 500 pages per circle, 5 levels deep, 100 below
-- one page.
--
-- Reading a page is recorded (circle_kb_reads) so the newcomer guide (C2) can
-- list pages as required reading (202610270120).
--
-- Existing functions are patched in place with pg_get_functiondef, so
-- nothing they gained since is lost: each patch must find its anchor and
-- change the text, or this migration stops and says so. can_current_user_*_note,
-- note_json and can_use_note_presence have a single earlier definition and
-- are rewritten from it (202610170060, 202610190050), the rest unchanged.

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------

alter table public.notes alter column conversation_id drop not null;

alter table public.notes
  add column if not exists circle_id uuid references public.circles(id) on delete cascade,
  add column if not exists parent_id uuid references public.notes(id) on delete set null,
  add column if not exists kb_position integer not null default 0,
  add column if not exists view_role_ids uuid[] not null default '{}'::uuid[],
  add column if not exists edit_role_ids uuid[] not null default '{}'::uuid[],
  add column if not exists restrict_rank integer not null default 0;

alter table public.notes drop constraint if exists notes_home;
alter table public.notes add constraint notes_home
  check ((conversation_id is null) <> (circle_id is null));

-- Only pages have a place in the tree, limits and a rank, and a page is never
-- pinned or locked to managers (those belong to chats).
alter table public.notes drop constraint if exists notes_kb_fields;
alter table public.notes add constraint notes_kb_fields check (
  circle_id is not null
  or (
    parent_id is null
    and kb_position = 0
    and cardinality(view_role_ids) = 0
    and cardinality(edit_role_ids) = 0
    and restrict_rank = 0
  )
);
alter table public.notes drop constraint if exists notes_kb_plain;
alter table public.notes add constraint notes_kb_plain check (
  circle_id is null or (not pinned and not managers_only)
);
alter table public.notes drop constraint if exists notes_kb_roles;
alter table public.notes add constraint notes_kb_roles check (
  cardinality(view_role_ids) <= 10
  and cardinality(edit_role_ids) <= 10
  and restrict_rank >= 0
);

create index if not exists notes_kb_tree_idx
  on public.notes (circle_id, parent_id, kb_position, created_at)
  where circle_id is not null and deleted_at is null;

-- Who has read which page (required reading, C2).
create table if not exists public.circle_kb_reads (
  user_id uuid not null,
  page_id uuid not null references public.notes(id) on delete cascade,
  circle_id uuid not null,
  read_at timestamptz not null default now(),
  primary key (user_id, page_id),
  constraint circle_kb_reads_member_fkey
    foreign key (circle_id, user_id)
    references public.circle_members(circle_id, user_id)
    on delete cascade
);

create index if not exists circle_kb_reads_page_idx
  on public.circle_kb_reads (page_id);

alter table public.circle_kb_reads enable row level security;
revoke all on public.circle_kb_reads from public, anon, authenticated;

-- A page the guide asks new members to read (202610270120 fills it in).
alter table public.circle_guide_tasks
  add column if not exists page_id uuid references public.notes(id) on delete cascade;

alter table public.circle_guide_tasks drop constraint if exists circle_guide_tasks_action_check;
alter table public.circle_guide_tasks add constraint circle_guide_tasks_action_check check (
  action in ('read_rules', 'visit_channel', 'send_message', 'set_avatar', 'read_page')
);
alter table public.circle_guide_tasks drop constraint if exists circle_guide_tasks_page_check;
alter table public.circle_guide_tasks add constraint circle_guide_tasks_page_check check (
  (action = 'read_page') = (page_id is not null)
);

-- ---------------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------------

-- Whether [p_user] manages the knowledge base of a circle (manage_channels,
-- which the owner and administrators hold), in a circle that works.
create or replace function public.kb_is_manager(p_circle_id uuid, p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_user is not null
    and not public.circle_is_suspended(p_circle_id)
    and not public.is_user_suspended(p_user)
    and public.circle_member_permissions(p_circle_id, p_user)
      & public.circle_permission_bit('manage_channels') <> 0;
$$;

-- What [p_user] may do with a page: 0 nothing, 1 read, 2 read and edit. The
-- page's own deleted_at is not looked at (a deleted page's change is still
-- streamed to the people who could see it, and the functions that act on a
-- page look at it themselves).
create or replace function public.kb_user_access(p_note_id uuid, p_user uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  cur public.notes%rowtype;
  home uuid;
  mem public.circle_members%rowtype;
  perms bigint;
  roles uuid[];
  can_edit boolean := false;
  depth integer := 0;
begin
  if p_user is null then
    return 0;
  end if;
  select * into cur from public.notes where id = p_note_id;
  if cur.id is null or cur.circle_id is null then
    return 0;
  end if;
  home := cur.circle_id;
  if public.circle_is_suspended(home) or public.is_user_suspended(p_user) then
    return 0;
  end if;
  select * into mem
  from public.circle_members m
  where m.circle_id = home and m.user_id = p_user;
  if mem.user_id is null then
    return 0;
  end if;

  perms := public.circle_member_permissions(home, p_user);
  if perms & public.circle_permission_bit('manage_channels') <> 0 then
    return 2;
  end if;

  select coalesce(array_agg(mr.role_id), '{}'::uuid[]) into roles
  from public.circle_member_roles mr
  where mr.circle_id = home and mr.user_id = p_user;

  while cur.id is not null and depth < 8 loop
    if cardinality(cur.view_role_ids) > 0
      and not (cur.view_role_ids && roles)
      and not (cur.edit_role_ids && roles)
    then
      return 0;
    end if;
    if cur.edit_role_ids && roles then
      can_edit := true;
    end if;
    exit when cur.parent_id is null;
    select * into cur from public.notes p
    where p.id = cur.parent_id and p.circle_id = home;
    depth := depth + 1;
  end loop;

  -- A timed-out member can only read.
  if can_edit and coalesce(mem.timed_out_until > now(), false) then
    can_edit := false;
  end if;
  return case when can_edit then 2 else 1 end;
end;
$$;

-- The highest rank that limited this page or a page above it (0: no limit).
create or replace function public.kb_lock_rank(p_note_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  cur public.notes%rowtype;
  found_rank integer := 0;
  depth integer := 0;
begin
  select * into cur from public.notes where id = p_note_id;
  while cur.id is not null and depth < 8 loop
    found_rank := greatest(found_rank, cur.restrict_rank);
    exit when cur.parent_id is null;
    select * into cur from public.notes p where p.id = cur.parent_id;
    depth := depth + 1;
  end loop;
  return found_rank;
end;
$$;

revoke execute on function public.kb_is_manager(uuid, uuid) from public, anon;
revoke execute on function public.kb_user_access(uuid, uuid) from public, anon;
revoke execute on function public.kb_lock_rank(uuid) from public, anon, authenticated;
-- The policies and the editor's checks call them as the caller.
grant execute on function public.kb_is_manager(uuid, uuid) to authenticated;
grant execute on function public.kb_user_access(uuid, uuid) to authenticated;

-- Where a page sits is checked whatever writes it: the parent is a page of the
-- same circle, never the page itself or one of its own descendants, and the
-- tree stays within its limits.
create or replace function public.kb_check_page_tree()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cur uuid := new.parent_id;
  depth integer := 1;
  below integer := 0;
begin
  if new.circle_id is null then
    return new;
  end if;
  if new.parent_id is not null then
    if new.parent_id = new.id then
      raise exception 'A page cannot be inside itself' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.notes p
      where p.id = new.parent_id and p.circle_id = new.circle_id
    ) then
      raise exception 'Parent page not found' using errcode = '22023';
    end if;
    while cur is not null loop
      depth := depth + 1;
      if cur = new.id or depth > 12 then
        raise exception 'A page cannot be inside itself' using errcode = '22023';
      end if;
      select p.parent_id into cur from public.notes p where p.id = cur;
    end loop;
  end if;
  if tg_op = 'UPDATE' then
    with recursive sub as (
      select c.id, 1 as lvl from public.notes c
      where c.parent_id = new.id and c.deleted_at is null
      union all
      select c.id, s.lvl + 1 from public.notes c
      join sub s on c.parent_id = s.id
      where c.deleted_at is null and s.lvl < 8
    )
    select coalesce(max(lvl), 0) into below from sub;
  end if;
  if depth + below > 5 then
    raise exception 'Pages can be nested 5 levels deep' using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke execute on function public.kb_check_page_tree() from public, anon, authenticated;

drop trigger if exists notes_kb_check_tree on public.notes;
create trigger notes_kb_check_tree
  before insert or update of parent_id, circle_id on public.notes
  for each row
  when (new.circle_id is not null)
  execute function public.kb_check_page_tree();

-- A deleted page leaves the newcomer guide.
create or replace function public.kb_forget_deleted_page()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.circle_guide_tasks t where t.page_id = new.id;
  return new;
end;
$$;

revoke execute on function public.kb_forget_deleted_page() from public, anon, authenticated;

drop trigger if exists notes_kb_forget_deleted on public.notes;
create trigger notes_kb_forget_deleted
  after update of deleted_at on public.notes
  for each row
  when (old.deleted_at is null and new.deleted_at is not null and new.circle_id is not null)
  execute function public.kb_forget_deleted_page();

-- ---------------------------------------------------------------------------
-- The note checks, now knowing pages
-- ---------------------------------------------------------------------------

-- Same as 202610170060_notes, plus the pages of a circle.
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
        and (
          (
            n.conversation_id is not null
            and public.is_current_user_conversation_member(n.conversation_id)
          )
          or (
            n.circle_id is not null
            and public.kb_user_access(n.id, auth.uid()) >= 1
          )
        )
    );
$$;

-- Same as 202610170060_notes, plus the pages of a circle.
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
  if n.circle_id is not null then
    return public.kb_user_access(n.id, auth.uid()) >= 2;
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

-- Same as 202610170060_notes, plus the pages of a circle.
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
  if n.circle_id is not null then
    return public.kb_is_manager(n.circle_id, auth.uid());
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

drop policy if exists notes_select_member on public.notes;
create policy notes_select_member
  on public.notes for select
  to authenticated
  using (
    (
      conversation_id is not null
      and public.is_current_user_conversation_member(conversation_id)
    )
    or (
      circle_id is not null
      and public.kb_user_access(id, auth.uid()) >= 1
    )
  );

-- Same as 202610170060_notes, plus what a page carries. The keys of a chat
-- note are as they were.
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
  ) || case
    when n.circle_id is null then '{}'::jsonb
    else jsonb_build_object(
      'circle_id', n.circle_id,
      'parent_id', n.parent_id,
      'restricted', cardinality(n.view_role_ids) > 0 or cardinality(n.edit_role_ids) > 0
    )
  end;
$$;

revoke execute on function public.note_json(public.notes) from public, anon, authenticated;

-- Same as 202610190050_realtime_private, plus the pages of a circle (they
-- have no conversation to be blocked in).
create or replace function public.can_use_note_presence(target_note_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select target_note_id is not null
    and auth.uid() is not null
    and public.can_current_user_view_note(target_note_id)
    and exists (
      select 1
      from public.notes n
      where n.id = target_note_id
        and n.deleted_at is null
        and (
          n.circle_id is not null
          or not public.is_current_user_blocked_in_conversation(n.conversation_id)
        )
    );
$$;

revoke execute on function public.can_use_note_presence(uuid) from public, anon;
grant execute on function public.can_use_note_presence(uuid) to authenticated;

-- Same as 202610170061_note_versions_files, plus the pages of a circle: the
-- pictures of a deleted page are removed by its author or a manager.
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
  if n.id is null or n.deleted_at is null then
    return false;
  end if;
  if n.circle_id is not null then
    return public.kb_user_access(n.id, auth.uid()) >= 1
      and (
        n.created_by = auth.uid()
        or public.kb_is_manager(n.circle_id, auth.uid())
      );
  end if;
  return public.is_current_user_conversation_member(n.conversation_id)
    and (
      n.created_by = auth.uid()
      or public.can_current_user_moderate_messages(n.conversation_id)
    );
end;
$$;

revoke execute on function public.can_current_user_delete_note_files(uuid) from public, anon;
grant execute on function public.can_current_user_delete_note_files(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- In-place patches
-- ---------------------------------------------------------------------------

do $$
declare
  fn text;
  def text;
  patched text;
  guard text := 'public.is_current_user_conversation_member(n.conversation_id)';
  swap text := 'public.can_current_user_view_note(n.id)';
begin
  -- The note functions that open a note ask who may see it; a page is seen
  -- by who can_current_user_view_note says (for a chat note that is the very
  -- same question). Their newest definitions: get_note (202610170060),
  -- update_note_meta (202610170060), note_apply_ops (202610240300),
  -- create_note_version and restore_note_version (202610170061).
  foreach fn in array array[
    'public.get_note(uuid)',
    'public.update_note_meta(uuid, jsonb)',
    'public.note_apply_ops(uuid, jsonb)',
    'public.create_note_version(uuid, text)',
    'public.restore_note_version(uuid)'
  ] loop
    def := pg_get_functiondef(fn::regprocedure);
    if position(guard in def) = 0 then
      if position(swap in def) > 0 then
        continue;
      end if;
      raise exception '% changed shape; patch it by hand', fn;
    end if;
    patched := replace(def, guard, swap);
    if patched = def or position(guard in patched) > 0 then
      raise exception '% changed shape; patch it by hand', fn;
    end if;
    execute patched;
  end loop;

  -- A page has no pin and no "managers only" (the table forbids it too).
  def := pg_get_functiondef('public.update_note_meta(uuid, jsonb)'::regprocedure);
  if def not like '%Not available for knowledge base pages%' then
    patched := replace(
      def,
      E'  if p_patch ? ''title'' or p_patch ? ''icon'' then\n',
      E'  if n.circle_id is not null\n    and (p_patch ? ''managers_only'' or p_patch ? ''pinned'')\n  then\n    raise exception ''Not available for knowledge base pages'' using errcode = ''22023'';\n  end if;\n\n  if p_patch ? ''title'' or p_patch ? ''icon'' then\n'
    );
    if patched = def or patched not like '%Not available for knowledge base pages%' then
      raise exception 'update_note_meta changed shape; patch it by hand';
    end if;
    execute patched;
  end if;

  -- The AI guard (202610260210) also checks the title of a page, which has
  -- no conversation: the circle comes from the page itself.
  def := pg_get_functiondef('public.guard_items_after_write()'::regprocedure);
  if def not like '%knowledge base%' then
    patched := replace(
      def,
      E'    if conv is null then\n      return null;\n    end if;\n    select cc.circle_id into channel_circle\n    from public.circle_channels cc\n    where cc.id = public.conversation_circle_channel_id(conv);\n',
      E'    if conv is null and tg_table_name = ''notes'' then\n      -- A knowledge base page: it belongs to the circle itself.\n      channel_circle := (row_data ->> ''circle_id'')::uuid;\n    else\n      if conv is null then\n        return null;\n      end if;\n      select cc.circle_id into channel_circle\n      from public.circle_channels cc\n      where cc.id = public.conversation_circle_channel_id(conv);\n    end if;\n'
    );
    if patched = def or patched not like '%knowledge base%' then
      raise exception 'guard_items_after_write changed shape; patch it by hand';
    end if;
    execute patched;
  end if;
end;
$$;
