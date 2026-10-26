-- Topics and circle posts 2.0 (roadmap B8), part 3 of 8: reading posts.
--
-- Three existing functions show a post. Each is patched in place from the
-- definition that is live (pg_get_functiondef), with one addition, so nothing
-- other packages put in them (profile visibility, the K1 take-down, saved
-- items' availability rules, report snapshots) is lost:
--
--   * get_circle_detail (latest file: 202610210120_circle_takedown.sql):
--     every post also carries title, tags, featured_at and can_feature_post
--     (the caller may feature posts: "manage messages"). The circle feed, the
--     grid, the tag filter and the "featured" filter all read these, so the
--     app needs no new call.
--   * list_saved_items (202610250410_saved_items_rpcs.sql): a kept circle post
--     also tells its title and tags in `extra` (post_title, post_tags), still
--     only when the post is visible to the person.
--   * report_snapshot (202610210110_admin_foundation.sql): a reported post's
--     snapshot has its title (the list label uses it when there is one), and
--     its tags.

do $$
declare
  def text;
  patched text;
  needle text;
begin
  -- get_circle_detail
  def := pg_get_functiondef('public.get_circle_detail(uuid)'::regprocedure);
  if def not like '%can_feature_post%' then
    needle := E'          ''body'', cp.body,\n          ''attachment'', cp.attachment,\n';
    if (length(def) - length(replace(def, needle, ''))) <> length(needle) then
      raise exception 'get_circle_detail changed shape; patch it by hand';
    end if;
    patched := replace(
      def,
      needle,
      E'          ''body'', cp.body,\n'
      || E'          ''title'', cp.title,\n'
      || E'          ''tags'', to_jsonb(cp.tags),\n'
      || E'          ''featured_at'', cp.featured_at,\n'
      || E'          ''can_feature_post'',\n'
      || E'          caller.permissions\n'
      || E'            & public.circle_permission_bit(''manage_messages'') <> 0,\n'
      || E'          ''attachment'', cp.attachment,\n'
    );
    if patched = def then
      raise exception 'get_circle_detail was not patched';
    end if;
    execute patched;
  end if;

  -- list_saved_items
  def := pg_get_functiondef('public.list_saved_items(integer)'::regprocedure);
  if def not like '%post_title%' then
    needle := E'      cp.attachment as cp_attachment,\n';
    if (length(def) - length(replace(def, needle, ''))) <> length(needle) then
      raise exception 'list_saved_items changed shape (picture); patch it by hand';
    end if;
    patched := replace(
      def,
      needle,
      needle || E'      cp.title as cp_title,\n      cp.tags as cp_tags,\n'
    );
    needle := E'        ''circle_name'', j.cr_name,\n';
    if (length(patched) - length(replace(patched, needle, ''))) <> length(needle) then
      raise exception 'list_saved_items changed shape (extra); patch it by hand';
    end if;
    patched := replace(
      patched,
      needle,
      needle
      || E'        ''post_title'', j.cp_title,\n'
      || E'        ''post_tags'', to_jsonb(j.cp_tags),\n'
    );
    execute patched;
  end if;

  -- report_snapshot
  def := pg_get_functiondef('public.report_snapshot(public.reports)'::regprocedure);
  if def not like '%post_title%' then
    needle := E'      ''title'', left(regexp_replace(p.body, ''\\s+'', '' '', ''g''), 80),\n';
    if (length(def) - length(replace(def, needle, ''))) <> length(needle) then
      raise exception 'report_snapshot changed shape; patch it by hand';
    end if;
    patched := replace(
      def,
      needle,
      E'      ''title'', coalesce(\n'
      || E'        nullif(p.title, ''''),\n'
      || E'        left(regexp_replace(p.body, ''\\s+'', '' '', ''g''), 80)\n'
      || E'      ),\n'
      || E'      ''post_title'', p.title,\n'
      || E'      ''post_tags'', to_jsonb(p.tags),\n'
    );
    execute patched;
  end if;
end;
$$;
