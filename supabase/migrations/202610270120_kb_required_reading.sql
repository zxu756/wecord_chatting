-- Circle knowledge base (roadmap D6), part 3 of 4: a page as required
-- reading in the newcomer guide (onboarding 2.0, C2).
--
-- The guide's task list gets a fifth kind, 'read_page' ("Read a page"), that
-- points at a knowledge base page (circle_guide_tasks.page_id, and the table
-- checks of 202610270100). Like "read the rules" it ticks itself off: it is
-- done when the member has opened the page (circle_kb_reads, recorded by
-- kb_mark_read). A member who cannot read the page does not see the task, as
-- with a channel they cannot see; a deleted page takes its tasks with it (a
-- trigger of 202610270100).
--
-- The three guide functions are patched in place from their newest
-- definitions (all in 202610230210_onboarding_guide_rpcs) so nothing they
-- gained since is lost; each patch must find its anchor and change the text,
-- or the migration stops and says so:
--   get_circle_guide         shows the task with its page, and whether it is
--                            read;
--   get_circle_guide_config  returns page_id and page_title for the editor;
--   set_circle_guide_tasks   accepts action 'read_page' with a page_id the
--                            caller can read, a page of this circle.
-- complete_guide_task is as it was: it already refuses every kind but a
-- visit ("This task completes itself").

-- Replaces [anchor] with [replacement] in [def]; the anchor must be there.
-- (A temporary helper: it lives in this session only.)
create or replace function pg_temp.kb_swap(
  def text,
  anchor text,
  replacement text,
  label text
)
returns text
language plpgsql
as $$
declare
  patched text := replace(def, anchor, replacement);
begin
  if position(anchor in def) = 0 or patched = def then
    raise exception '% changed shape; patch it by hand', label;
  end if;
  return patched;
end;
$$;

do $$
declare
  def text;
  patched text;
begin
  -- ----------------------------------------------------------- get_circle_guide
  def := pg_get_functiondef('public.get_circle_guide(uuid)'::regprocedure);
  if def not like '%circle_kb_reads%' then
    patched := def;
    patched := pg_temp.kb_swap(
      patched,
      E'          when ''set_avatar'' then coalesce(has_avatar, false)\n',
      E'          when ''set_avatar'' then coalesce(has_avatar, false)\n          when ''read_page'' then exists (\n            select 1\n            from public.circle_kb_reads kr\n            where kr.page_id = t.page_id\n              and kr.user_id = current_user_id\n          )\n',
      'get_circle_guide'
    );
    patched := pg_temp.kb_swap(
      patched,
      E'        ''channel_name'', cc.name,\n',
      E'        ''channel_name'', cc.name,\n        ''page_id'', t.page_id,\n        ''page_title'', kp.title,\n',
      'get_circle_guide'
    );
    patched := pg_temp.kb_swap(
      patched,
      E'  left join public.circle_channels cc on cc.id = t.channel_id\n  where t.circle_id = target_circle_id\n    and (\n      t.channel_id is null\n      or public.circle_channel_permissions(t.channel_id, current_user_id) & 1 <> 0\n    );',
      E'  left join public.circle_channels cc on cc.id = t.channel_id\n  left join public.notes kp on kp.id = t.page_id\n  where t.circle_id = target_circle_id\n    and (\n      t.channel_id is null\n      or public.circle_channel_permissions(t.channel_id, current_user_id) & 1 <> 0\n    )\n    -- A page the member cannot read is left out, like a channel they cannot see.\n    and (\n      t.page_id is null\n      or (\n        kp.deleted_at is null\n        and public.kb_user_access(t.page_id, current_user_id) >= 1\n      )\n    );',
      'get_circle_guide'
    );
    execute patched;
  end if;

  -- ---------------------------------------------------- get_circle_guide_config
  def := pg_get_functiondef('public.get_circle_guide_config(uuid)'::regprocedure);
  if def not like '%page_title%' then
    patched := pg_temp.kb_swap(
      def,
      E'            ''action'', t.action,\n            ''channel_id'', t.channel_id\n          )',
      E'            ''action'', t.action,\n            ''channel_id'', t.channel_id,\n            ''page_id'', t.page_id,\n            ''page_title'', (\n              select kp.title from public.notes kp\n              where kp.id = t.page_id and kp.deleted_at is null\n            )\n          )',
      'get_circle_guide_config'
    );
    execute patched;
  end if;

  -- ----------------------------------------------------- set_circle_guide_tasks
  def := pg_get_functiondef('public.set_circle_guide_tasks(uuid, jsonb)'::regprocedure);
  if def not like '%v_page_id%' then
    patched := def;
    patched := pg_temp.kb_swap(
      patched,
      E'  v_channel_id uuid;\n  kept_tasks uuid[] := ''{}'';',
      E'  v_channel_id uuid;\n  v_page_id uuid;\n  kept_tasks uuid[] := ''{}'';',
      'set_circle_guide_tasks'
    );
    patched := pg_temp.kb_swap(
      patched,
      E'    v_channel_id := nullif(task_item ->> ''channel_id'', '''')::uuid;\n',
      E'    v_channel_id := nullif(task_item ->> ''channel_id'', '''')::uuid;\n    v_page_id := nullif(task_item ->> ''page_id'', '''')::uuid;\n',
      'set_circle_guide_tasks'
    );
    patched := pg_temp.kb_swap(
      patched,
      E'v_action not in (''read_rules'', ''visit_channel'', ''send_message'', ''set_avatar'')',
      E'v_action not in (''read_rules'', ''visit_channel'', ''send_message'', ''set_avatar'', ''read_page'')',
      'set_circle_guide_tasks'
    );
    patched := pg_temp.kb_swap(
      patched,
      E'    if v_action in (''read_rules'', ''set_avatar'') then\n      v_channel_id := null;\n    end if;\n',
      E'    if v_action in (''read_rules'', ''set_avatar'') then\n      v_channel_id := null;\n    end if;\n    if v_action <> ''read_page'' then\n      v_page_id := null;\n    else\n      v_channel_id := null;\n      if v_page_id is null\n        or not exists (\n          select 1 from public.notes kp\n          where kp.id = v_page_id\n            and kp.circle_id = target_circle_id\n            and kp.deleted_at is null\n        )\n        or public.kb_user_access(v_page_id, current_user_id) < 1\n      then\n        raise exception ''Pick a page to read'' using errcode = ''22023'';\n      end if;\n    end if;\n',
      'set_circle_guide_tasks'
    );
    patched := pg_temp.kb_swap(
      patched,
      E'      set position = task_index, title = v_title, action = v_action,\n        channel_id = v_channel_id\n',
      E'      set position = task_index, title = v_title, action = v_action,\n        channel_id = v_channel_id, page_id = v_page_id\n',
      'set_circle_guide_tasks'
    );
    patched := pg_temp.kb_swap(
      patched,
      E'        action,\n        channel_id\n      )\n      values (target_circle_id, task_index, v_title, v_action, v_channel_id)',
      E'        action,\n        channel_id,\n        page_id\n      )\n      values (target_circle_id, task_index, v_title, v_action, v_channel_id, v_page_id)',
      'set_circle_guide_tasks'
    );
    execute patched;
  end if;
end;
$$;
