-- Whiteboard (roadmap D10), part 5 of 6: the whiteboard as a tab under a
-- chat header (D8) and its title in the AI guard (F7).
--
-- Group tab. The kind 'whiteboard' points at a board of THIS conversation
-- (target_type 'id', like a note). Added to the group tabs of
-- 202610280550_group_tabs_rpcs.sql by patching, in place from the live
-- definitions (so the featured posts tab of B8 and whatever else patched them
-- stays), the three functions that know the kinds of tab:
--   * conversation_tab_target_ok: a live board of this conversation;
--   * get_conversation_tabs: the board's own title, and the tab is available
--     while the board is not deleted;
--   * add_conversation_tab: a tab with no title takes the board's.
-- A tab goes when its board does.
--
-- AI guard. AI guard 2.0 (202610260210) checks the titles of notes, tasks and
-- events written by the people the guard watches. A whiteboard title is the
-- same thing: it is not a message, so nothing is hidden while the AI looks,
-- and what the AI flags goes to the circle's Review queue. Patched in place:
--   * guard_item_reviews accepts the item type 'whiteboard';
--   * guard_item_text knows a board (a deleted board has no text);
--   * guard_items_after_write learns the table whiteboards;
--   * an insert with a title and a change of the title start a check, with
--     the same limits as the other things.
-- (What is drawn on a board is not read by the guard.)
--
-- Each patch must find its anchor and change the text, or the migration stops
-- and says so (no silent no-op), and a second run changes nothing.

insert into public.conversation_tab_kinds (kind, target_type)
values ('whiteboard', 'id')
on conflict (kind) do nothing;

do $$
declare
  def text;
  patched text;
  needle text;
  constraint_def text;
begin
  -- A live board of this conversation.
  def := pg_get_functiondef(
    'public.conversation_tab_target_ok(uuid, text, text)'::regprocedure
  );
  if def not like '%whiteboards%' then
    needle := E'    when ''check_in'' then exists (\n      select 1 from public.check_in_boards b\n      where b.id = target_id and b.conversation_id = p_conversation_id\n    )\n';
    if (length(def) - length(replace(def, needle, ''))) <> length(needle) then
      raise exception 'conversation_tab_target_ok changed shape; patch it by hand';
    end if;
    patched := replace(
      def,
      needle,
      needle
      || E'    when ''whiteboard'' then exists (\n'
      || E'      select 1 from public.whiteboards wb\n'
      || E'      where wb.id = target_id\n'
      || E'        and wb.conversation_id = p_conversation_id\n'
      || E'        and wb.deleted_at is null\n'
      || E'    )\n'
    );
    execute patched;
  end if;

  -- Listing: the live title, and whether the board is still there.
  def := pg_get_functiondef(
    'public.get_conversation_tabs(uuid, boolean)'::regprocedure
  );
  if def not like '%whiteboards%' then
    needle := E'                when ''check_in'' then b.title\n              end), ''''),';
    if (length(def) - length(replace(def, needle, ''))) <> length(needle) then
      raise exception 'get_conversation_tabs (title) changed shape; patch it by hand';
    end if;
    patched := replace(
      def,
      needle,
      E'                when ''check_in'' then b.title\n'
      || E'                when ''whiteboard'' then wb.title\n'
      || E'              end), ''''),'
    );

    needle := E'              when ''check_in'' then b.id is not null and public.check_in_card_visible(b.message_id)\n';
    if (length(patched) - length(replace(patched, needle, ''))) <> length(needle) then
      raise exception 'get_conversation_tabs (available) changed shape; patch it by hand';
    end if;
    patched := replace(
      patched,
      needle,
      needle
      || E'              when ''whiteboard'' then wb.id is not null and wb.deleted_at is null\n'
    );

    needle := E'          left join public.check_in_boards b\n            on t.kind = ''check_in'' and b.id::text = t.target\n            and b.conversation_id = t.conversation_id\n';
    if (length(patched) - length(replace(patched, needle, ''))) <> length(needle) then
      raise exception 'get_conversation_tabs (join) changed shape; patch it by hand';
    end if;
    patched := replace(
      patched,
      needle,
      needle
      || E'          left join public.whiteboards wb\n'
      || E'            on t.kind = ''whiteboard'' and wb.id::text = t.target\n'
      || E'            and wb.conversation_id = t.conversation_id\n'
    );
    execute patched;
  end if;

  -- A tab with no title takes the board's.
  def := pg_get_functiondef(
    'public.add_conversation_tab(uuid, text, text, text)'::regprocedure
  );
  if def not like '%whiteboards%' then
    needle := E'      when ''check_in'' then (select b.title from public.check_in_boards b where b.id = clean_target::uuid)\n';
    if (length(def) - length(replace(def, needle, ''))) <> length(needle) then
      raise exception 'add_conversation_tab changed shape; patch it by hand';
    end if;
    patched := replace(
      def,
      needle,
      needle
      || E'      when ''whiteboard'' then (select nullif(btrim(wb.title), '''') from public.whiteboards wb where wb.id = clean_target::uuid)\n'
    );
    execute patched;
  end if;

  -- The AI guard: the item types the table accepts.
  select pg_get_constraintdef(c.oid)
  into constraint_def
  from pg_constraint c
  where c.conrelid = 'public.guard_item_reviews'::regclass
    and c.conname = 'guard_item_reviews_type';
  if constraint_def is null then
    raise exception 'guard_item_reviews_type does not exist';
  end if;
  if constraint_def not like '%whiteboard%' then
    if (length(constraint_def) - length(replace(constraint_def, '::text])', ''))) <> length('::text])') then
      raise exception 'guard_item_reviews_type changed shape; patch it by hand';
    end if;
    alter table public.guard_item_reviews drop constraint guard_item_reviews_type;
    execute format(
      'alter table public.guard_item_reviews add constraint guard_item_reviews_type %s',
      replace(constraint_def, '::text])', '::text, ''whiteboard''::text])')
    );
  end if;

  -- The text of a board.
  def := pg_get_functiondef('public.guard_item_text(text, uuid)'::regprocedure);
  if def not like '%whiteboards%' then
    needle := E'      where cp.id = p_item_id and cp.deleted_at is null;\n';
    if (length(def) - length(replace(def, needle, ''))) <> length(needle) then
      raise exception 'guard_item_text changed shape; patch it by hand';
    end if;
    patched := replace(
      def,
      needle,
      needle
      || E'  elsif p_item_type = ''whiteboard'' then\n'
      || E'    return query\n'
      || E'      select wb.title, ''''::text\n'
      || E'      from public.whiteboards wb\n'
      || E'      where wb.id = p_item_id and wb.deleted_at is null;\n'
    );
    execute patched;
  end if;

  -- Which circle a board belongs to: through its conversation, like a note.
  def := pg_get_functiondef('public.guard_items_after_write()'::regprocedure);
  if def not like '%whiteboards%' then
    needle := E'    elsif tg_table_name = ''task_lists'' then\n';
    if (length(def) - length(replace(def, needle, ''))) <> length(needle) then
      raise exception 'guard_items_after_write changed shape; patch it by hand';
    end if;
    patched := replace(
      def,
      needle,
      E'    elsif tg_table_name = ''whiteboards'' then\n'
      || E'      item_type := ''whiteboard'';\n'
      || E'      conv := (row_data ->> ''conversation_id'')::uuid;\n'
      || needle
    );
    execute patched;
  end if;
end;
$$;

drop trigger if exists guard_items_whiteboards_ins on public.whiteboards;
create trigger guard_items_whiteboards_ins
  after insert on public.whiteboards
  for each row
  when (btrim(new.title) <> '')
  execute function public.guard_items_after_write();

drop trigger if exists guard_items_whiteboards_upd on public.whiteboards;
create trigger guard_items_whiteboards_upd
  after update of title on public.whiteboards
  for each row
  when (old.title is distinct from new.title and new.deleted_at is null)
  execute function public.guard_items_after_write();

-- A tab goes when its board does (conversation_tabs_drop_target is the
-- trigger function of the other kinds, 202610280540).
drop trigger if exists conversation_tabs_whiteboard_gone on public.whiteboards;
create trigger conversation_tabs_whiteboard_gone
  after update of deleted_at on public.whiteboards
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.conversation_tabs_drop_target('whiteboard');

drop trigger if exists conversation_tabs_whiteboard_deleted on public.whiteboards;
create trigger conversation_tabs_whiteboard_deleted
  after delete on public.whiteboards
  for each row execute function public.conversation_tabs_drop_target('whiteboard');
