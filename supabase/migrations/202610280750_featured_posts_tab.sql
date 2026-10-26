-- Topics and circle posts 2.0 (roadmap B8), part 6 of 8: the featured posts
-- as a tab under a circle channel's header (D8).
--
-- The kind 'featured_posts' has no target and opens the circle's featured
-- posts ("精华"). Like the knowledge base it needs a circle channel (a group
-- chat has no circle). Added to the group tabs of
-- 202610280550_group_tabs_rpcs.sql by patching the two functions that know
-- the knowledge base kind, in place from the live definitions:
--   * conversation_tab_target_ok: a kind that needs a circle channel;
--   * get_conversation_tabs: the tab is listed as available only where there
--     is a circle (and the circle is not suspended, K1).

insert into public.conversation_tab_kinds (kind, target_type)
values ('featured_posts', 'none')
on conflict (kind) do nothing;

do $$
declare
  def text;
  patched text;
  needle text;
begin
  def := pg_get_functiondef(
    'public.conversation_tab_target_ok(uuid, text, text)'::regprocedure
  );
  if def not like '%featured_posts%' then
    needle := E'    if p_kind = ''kb'' then\n';
    if (length(def) - length(replace(def, needle, ''))) <> length(needle) then
      raise exception 'conversation_tab_target_ok changed shape; patch it by hand';
    end if;
    patched := replace(
      def,
      needle,
      E'    if p_kind in (''kb'', ''featured_posts'') then\n'
    );
    execute patched;
  end if;

  def := pg_get_functiondef(
    'public.get_conversation_tabs(uuid, boolean)'::regprocedure
  );
  if def not like '%featured_posts%' then
    needle := E'              when ''kb'' then home_circle is not null\n';
    if (length(def) - length(replace(def, needle, ''))) <> length(needle) then
      raise exception 'get_conversation_tabs changed shape; patch it by hand';
    end if;
    patched := replace(
      def,
      needle,
      E'              when ''kb'' then home_circle is not null\n'
      || E'              when ''featured_posts'' then\n'
      || E'                home_circle is not null\n'
      || E'                and not public.circle_is_suspended(home_circle)\n'
    );
    execute patched;
  end if;
end;
$$;
