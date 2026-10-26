-- Topics and circle posts 2.0 (roadmap B8), part 5 of 8: the AI guard reads
-- the titles of circle posts.
--
-- AI guard 2.0 (F7, 202610260210_guard2_items.sql) already checks the titles
-- of events, notes and tasks written by the people the guard watches (new
-- members, and the ones who came in during a raid lockdown). A circle post is
-- the same kind of thing: it is not a message, so nothing is hidden while the
-- AI looks, and what the AI flags goes to the circle's review queue as a
-- card. The post's title and text are what the AI reads (the title alone
-- stands for the post in the queue; a post without a title shows its first
-- words).
--
-- Everything is done on the machinery that exists, patched in place from the
-- live definitions (so the knowledge base pages of D6 and the event questions
-- of the events package stay):
--   * guard_item_reviews accepts the item type 'circle_post';
--   * guard_item_text knows a post (a deleted post has no text, so its card
--     disappears);
--   * guard_items_after_write learns the table circle_posts;
--   * an insert and a change of the title or the text start a check, with the
--     same limits as the other things (one check a minute for a post, ten in
--     ten minutes for a person).

do $$
declare
  def text;
  patched text;
  needle text;
  constraint_def text;
begin
  -- The item types the table accepts.
  select pg_get_constraintdef(c.oid)
  into constraint_def
  from pg_constraint c
  where c.conrelid = 'public.guard_item_reviews'::regclass
    and c.conname = 'guard_item_reviews_type';
  if constraint_def is null then
    raise exception 'guard_item_reviews_type does not exist';
  end if;
  if constraint_def not like '%circle_post%' then
    needle := '''task_item''::text]';
    if position(needle in constraint_def) = 0 then
      raise exception 'guard_item_reviews_type changed shape; patch it by hand';
    end if;
    alter table public.guard_item_reviews drop constraint guard_item_reviews_type;
    execute format(
      'alter table public.guard_item_reviews add constraint guard_item_reviews_type %s',
      replace(constraint_def, needle, '''task_item''::text, ''circle_post''::text]')
    );
  end if;

  -- The text of a post.
  def := pg_get_functiondef('public.guard_item_text(text, uuid)'::regprocedure);
  if def not like '%circle_post%' then
    needle := E'      where t.id = p_item_id and t.deleted_at is null;\n  end if;\n';
    if (length(def) - length(replace(def, needle, ''))) <> length(needle) then
      raise exception 'guard_item_text changed shape; patch it by hand';
    end if;
    patched := replace(
      def,
      needle,
      E'      where t.id = p_item_id and t.deleted_at is null;\n'
      || E'  elsif p_item_type = ''circle_post'' then\n'
      || E'    return query\n'
      || E'      select\n'
      || E'        coalesce(cp.title, left(cp.body, 60)),\n'
      || E'        case when cp.title is null then ''''::text else cp.body end\n'
      || E'      from public.circle_posts cp\n'
      || E'      where cp.id = p_item_id and cp.deleted_at is null;\n'
      || E'  end if;\n'
    );
    execute patched;
  end if;

  -- Which circle a post belongs to.
  def := pg_get_functiondef('public.guard_items_after_write()'::regprocedure);
  if def not like '%circle_posts%' then
    needle := E'    item_type := ''circle_event'';\n    channel_circle := (row_data ->> ''circle_id'')::uuid;\n  else\n';
    if (length(def) - length(replace(def, needle, ''))) <> length(needle) then
      raise exception 'guard_items_after_write changed shape; patch it by hand';
    end if;
    patched := replace(
      def,
      needle,
      E'    item_type := ''circle_event'';\n    channel_circle := (row_data ->> ''circle_id'')::uuid;\n'
      || E'  elsif tg_table_name = ''circle_posts'' then\n'
      || E'    item_type := ''circle_post'';\n'
      || E'    channel_circle := (row_data ->> ''circle_id'')::uuid;\n'
      || E'  else\n'
    );
    execute patched;
  end if;
end;
$$;

drop trigger if exists guard_items_circle_posts_ins on public.circle_posts;
create trigger guard_items_circle_posts_ins
  after insert on public.circle_posts
  for each row execute function public.guard_items_after_write();

drop trigger if exists guard_items_circle_posts_upd on public.circle_posts;
create trigger guard_items_circle_posts_upd
  after update of title, body on public.circle_posts
  for each row
  when (
    old.title is distinct from new.title
    or old.body is distinct from new.body
  )
  execute function public.guard_items_after_write();
