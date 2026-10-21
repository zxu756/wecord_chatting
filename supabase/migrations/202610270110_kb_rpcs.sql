-- Circle knowledge base (roadmap D6), part 2 of 4: what members and managers
-- call. The access rules and the columns are in 202610270100. Writing the
-- words of a page is the notes' own note_apply_ops; everything about the
-- tree is here.
--
-- Members
--   * kb_list_pages(circle): the pages the caller may read, flat; the app
--     builds the tree. Says which ones the caller may edit, which are
--     limited to some roles, which are required reading in the newcomer
--     guide and whether the caller has read them.
--   * kb_mark_read(page): records that the caller opened a page.
--   * kb_search(circle, text, limit): pages whose title or words contain the
--     text, among those the caller may read.
--   * kb_create_page(circle, parent, title, icon, id): a top-level page needs
--     manage_channels, a page below another one needs the right to edit that
--     one. Safe to send again with the same id.
-- Managers (manage_channels)
--   * kb_move_page(page, parent, before): moves a page and puts it before a
--     sibling (or last).
--   * kb_delete_page(page): deletes a page; the pages inside move up one
--     level. Returns the pictures to remove from storage.
--   * kb_get_page_access / kb_set_page_access: which roles may read and
--     which may edit a page. Whoever limits a page records their rank; a
--     lower rank cannot change, lift, move or delete it (errcode 42501).
-- Each tree change by a manager is audited (kb_page_create, kb_page_move,
-- kb_page_delete, kb_page_access); the page's title is left out of the entry
-- when the page is limited. A circle that an admin suspended refuses all of
-- it (42501); a suspended person likewise.

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

create or replace function public.kb_list_pages(p_circle_id uuid)
returns table (
  id uuid,
  parent_id uuid,
  title text,
  icon text,
  kb_position integer,
  created_at timestamptz,
  updated_at timestamptz,
  updated_by_name text,
  can_edit boolean,
  restricted boolean,
  required boolean,
  read boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  uid uuid := auth.uid();
  mgr boolean;
  my_roles uuid[];
  timed_out boolean;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.circle_members m
    where m.circle_id = p_circle_id and m.user_id = uid
  ) then
    raise exception 'Circle not found' using errcode = '42501';
  end if;
  if public.circle_is_suspended(p_circle_id) or public.is_user_suspended(uid) then
    return;
  end if;

  mgr := public.kb_is_manager(p_circle_id, uid);
  select coalesce(array_agg(mr.role_id), '{}'::uuid[]) into my_roles
  from public.circle_member_roles mr
  where mr.circle_id = p_circle_id and mr.user_id = uid;
  select coalesce(m.timed_out_until > now(), false) into timed_out
  from public.circle_members m
  where m.circle_id = p_circle_id and m.user_id = uid;

  return query
  with recursive tree as (
    select
      n.id as page_id,
      1 as depth,
      (
        mgr
        or cardinality(n.view_role_ids) = 0
        or n.view_role_ids && my_roles
        or n.edit_role_ids && my_roles
      ) as view_ok,
      (mgr or n.edit_role_ids && my_roles) as edit_ok
    from public.notes n
    where n.circle_id = p_circle_id
      and n.deleted_at is null
      and n.parent_id is null
    union all
    select
      c.id,
      t.depth + 1,
      t.view_ok and (
        mgr
        or cardinality(c.view_role_ids) = 0
        or c.view_role_ids && my_roles
        or c.edit_role_ids && my_roles
      ),
      t.edit_ok or (c.edit_role_ids && my_roles)
    from public.notes c
    join tree t on c.parent_id = t.page_id
    where c.circle_id = p_circle_id
      and c.deleted_at is null
      and t.depth < 6
  )
  select
    n.id,
    n.parent_id,
    n.title,
    n.icon,
    n.kb_position,
    n.created_at,
    n.updated_at,
    coalesce(nullif(btrim(p.display_name), ''), p.username),
    t.edit_ok and (mgr or not timed_out),
    cardinality(n.view_role_ids) > 0 or cardinality(n.edit_role_ids) > 0,
    exists (select 1 from public.circle_guide_tasks gt where gt.page_id = n.id),
    exists (
      select 1 from public.circle_kb_reads r
      where r.page_id = n.id and r.user_id = uid
    )
  from tree t
  join public.notes n on n.id = t.page_id
  left join public.profiles p on p.id = n.updated_by
  where t.view_ok
  order by n.parent_id nulls first, n.kb_position, n.created_at, n.id;
end;
$$;

create or replace function public.kb_mark_read(p_page_id uuid)
returns void
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
  select * into n from public.notes where id = p_page_id and deleted_at is null;
  if n.id is null or n.circle_id is null or public.kb_user_access(n.id, uid) < 1 then
    raise exception 'Page not found' using errcode = 'P0002';
  end if;
  insert into public.circle_kb_reads (user_id, page_id, circle_id)
  values (uid, n.id, n.circle_id)
  on conflict (user_id, page_id) do nothing;
end;
$$;

create or replace function public.kb_search(
  p_circle_id uuid,
  p_query text,
  p_limit integer default 20
)
returns table (
  id uuid,
  parent_id uuid,
  title text,
  icon text,
  snippet text,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  pattern text;
  q text := lower(btrim(coalesce(p_query, '')));
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if char_length(q) < 2 then
    return;
  end if;
  pattern := '%' || replace(replace(replace(left(q, 80), '\', '\\'), '%', '\%'), '_', '\_') || '%';

  return query
  select
    n.id,
    n.parent_id,
    n.title,
    n.icon,
    coalesce((
      select left(regexp_replace(b.text, '\s+', ' ', 'g'), 160)
      from public.note_blocks b
      where b.note_id = n.id
        and not b.deleted
        and lower(b.text) like pattern escape '\'
      order by b.pos, b.id
      limit 1
    ), ''),
    n.updated_at
  from public.kb_list_pages(p_circle_id) v
  join public.notes n on n.id = v.id
  where lower(n.title) like pattern escape '\'
    or exists (
      select 1 from public.note_blocks b
      where b.note_id = n.id
        and not b.deleted
        and lower(b.text) like pattern escape '\'
    )
  order by (lower(n.title) like pattern escape '\') desc, n.updated_at desc, n.id
  limit greatest(1, least(coalesce(p_limit, 20), 50));
end;
$$;

-- ---------------------------------------------------------------------------
-- Writing the tree
-- ---------------------------------------------------------------------------

-- A short label of a page for the audit log: its title, unless it is limited
-- (the people who read the log may not be allowed to read the page).
create or replace function public.kb_audit_label(p_note_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when public.kb_lock_rank(n.id) > 0
      or cardinality(n.view_role_ids) > 0
      or cardinality(n.edit_role_ids) > 0 then null
    else left(nullif(btrim(n.title), ''), 120)
  end
  from public.notes n
  where n.id = p_note_id;
$$;

revoke execute on function public.kb_audit_label(uuid) from public, anon, authenticated;

create or replace function public.kb_create_page(
  p_circle_id uuid,
  p_parent_id uuid default null,
  p_title text default '',
  p_icon text default null,
  p_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  new_id uuid := coalesce(p_id, gen_random_uuid());
  n public.notes%rowtype;
  parent public.notes%rowtype;
  next_position integer;
  sibling_count integer;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into n from public.notes where id = new_id;
  if n.id is not null then
    -- Sent before (the answer got lost).
    if n.created_by is distinct from uid
      or n.circle_id is distinct from p_circle_id
      or public.kb_user_access(n.id, uid) < 1
    then
      raise exception 'Page not found' using errcode = 'P0002';
    end if;
    return public.note_json(n);
  end if;

  if not exists (
    select 1 from public.circle_members m
    where m.circle_id = p_circle_id and m.user_id = uid
  ) then
    raise exception 'Circle not found' using errcode = '42501';
  end if;
  if public.circle_is_suspended(p_circle_id) then
    raise exception 'This circle was suspended' using errcode = '42501';
  end if;
  if public.is_user_suspended(uid) then
    raise exception 'Account suspended' using errcode = '42501';
  end if;

  perform 1 from public.circles where id = p_circle_id for no key update;

  if p_parent_id is null then
    if not public.kb_is_manager(p_circle_id, uid) then
      raise exception 'Only people who manage channels can add a top-level page'
        using errcode = '42501';
    end if;
  else
    select * into parent from public.notes
    where id = p_parent_id and circle_id = p_circle_id and deleted_at is null
    for update;
    if parent.id is null then
      raise exception 'Page not found' using errcode = 'P0002';
    end if;
    if public.kb_user_access(parent.id, uid) < 2 then
      raise exception 'You cannot add pages here' using errcode = '42501';
    end if;
  end if;

  if char_length(coalesce(p_title, '')) > 200 then
    raise exception 'Title is too long' using errcode = '22023';
  end if;
  if char_length(coalesce(p_icon, '')) > 16 then
    raise exception 'Icon is too long' using errcode = '22023';
  end if;
  if (select count(*) from public.notes
      where circle_id = p_circle_id and deleted_at is null) >= 500
  then
    raise exception 'This circle has too many pages' using errcode = '22023';
  end if;
  select coalesce(max(s.kb_position), 0), count(*)
  into next_position, sibling_count
  from public.notes s
  where s.circle_id = p_circle_id
    and s.parent_id is not distinct from p_parent_id
    and s.deleted_at is null;
  if sibling_count >= 100 then
    raise exception 'There are too many pages here' using errcode = '22023';
  end if;

  insert into public.notes (
    id, circle_id, parent_id, kb_position, title, icon, created_by, updated_by
  )
  values (
    new_id,
    p_circle_id,
    p_parent_id,
    next_position + 1,
    btrim(coalesce(p_title, '')),
    coalesce(nullif(btrim(p_icon), ''), E'\U0001F4C4'),
    uid,
    uid
  )
  returning * into n;

  insert into public.note_blocks (id, note_id, pos, kind, updated_by)
  values (gen_random_uuid(), n.id, 'V', 'paragraph', uid);

  perform public.write_circle_audit(
    p_circle_id,
    'kb_page_create',
    'page',
    n.id,
    public.kb_audit_label(n.id),
    jsonb_build_object('parent_id', p_parent_id)
  );

  return public.note_json(n);
end;
$$;

create or replace function public.kb_move_page(
  p_page_id uuid,
  p_parent_id uuid default null,
  p_before_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  n public.notes%rowtype;
  old_parent uuid;
  siblings uuid[];
  at_index integer;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into n from public.notes
  where id = p_page_id and circle_id is not null and deleted_at is null
  for update;
  if n.id is null or public.kb_user_access(n.id, uid) < 1 then
    raise exception 'Page not found' using errcode = 'P0002';
  end if;
  if not public.kb_is_manager(n.circle_id, uid) then
    raise exception 'Only people who manage channels can move pages'
      using errcode = '42501';
  end if;
  if public.kb_lock_rank(n.id) > public.circle_member_rank(n.circle_id, uid) then
    raise exception 'A higher role limited this page' using errcode = '42501';
  end if;
  if p_parent_id is not null and not exists (
    select 1 from public.notes p
    where p.id = p_parent_id and p.circle_id = n.circle_id and p.deleted_at is null
  ) then
    raise exception 'Page not found' using errcode = 'P0002';
  end if;

  old_parent := n.parent_id;
  siblings := array(
    select s.id from public.notes s
    where s.circle_id = n.circle_id
      and s.parent_id is not distinct from p_parent_id
      and s.deleted_at is null
      and s.id <> n.id
    order by s.kb_position, s.created_at, s.id
  );
  if p_parent_id is distinct from old_parent and cardinality(siblings) >= 100 then
    raise exception 'There are too many pages there' using errcode = '22023';
  end if;
  if p_before_id is not null then
    at_index := array_position(siblings, p_before_id);
    if at_index is null then
      raise exception 'Page not found' using errcode = 'P0002';
    end if;
    siblings := siblings[1:at_index - 1] || n.id || siblings[at_index:];
  else
    siblings := siblings || n.id;
  end if;

  if p_parent_id is distinct from old_parent then
    update public.notes set parent_id = p_parent_id where id = n.id;
  end if;
  update public.notes t
  set kb_position = x.ord
  from unnest(siblings) with ordinality as x(page_id, ord)
  where t.id = x.page_id
    and t.kb_position is distinct from x.ord;

  if p_parent_id is distinct from old_parent then
    perform public.write_circle_audit(
      n.circle_id,
      'kb_page_move',
      'page',
      n.id,
      public.kb_audit_label(n.id),
      jsonb_build_object('from_parent_id', old_parent, 'to_parent_id', p_parent_id)
    );
  end if;

  select * into n from public.notes where id = n.id;
  return public.note_json(n);
end;
$$;

-- Deletes a page. The pages inside it move up one level, after the pages
-- that are already there. Its pictures are listed so the caller can remove
-- them from storage (storage allows that once the page is gone).
create or replace function public.kb_delete_page(p_page_id uuid)
returns table (bucket_id text, object_path text)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  uid uuid := auth.uid();
  n public.notes%rowtype;
  label text;
  base integer;
  inside integer;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into n from public.notes
  where id = p_page_id and circle_id is not null and deleted_at is null
  for update;
  if n.id is null or public.kb_user_access(n.id, uid) < 1 then
    raise exception 'Page not found' using errcode = 'P0002';
  end if;
  if not public.kb_is_manager(n.circle_id, uid) then
    raise exception 'Only people who manage channels can delete pages'
      using errcode = '42501';
  end if;
  if public.kb_lock_rank(n.id) > public.circle_member_rank(n.circle_id, uid) then
    raise exception 'A higher role limited this page' using errcode = '42501';
  end if;

  select coalesce(max(s.kb_position), 0), count(*)
  into base, inside
  from public.notes s
  where s.circle_id = n.circle_id
    and s.parent_id is not distinct from n.parent_id
    and s.deleted_at is null
    and s.id <> n.id;
  if inside + (
    select count(*) from public.notes c
    where c.parent_id = n.id and c.deleted_at is null
  ) > 100 then
    raise exception 'There would be too many pages at that level'
      using errcode = '22023';
  end if;

  label := public.kb_audit_label(n.id);

  update public.notes c
  set parent_id = n.parent_id,
      kb_position = base + r.rn
  from (
    select k.id, row_number() over (order by k.kb_position, k.created_at, k.id) as rn
    from public.notes k
    where k.parent_id = n.id and k.deleted_at is null
  ) r
  where c.id = r.id;

  update public.notes
  set deleted_at = now(), parent_id = null, updated_by = uid, updated_at = now()
  where id = n.id;

  perform public.write_circle_audit(
    n.circle_id, 'kb_page_delete', 'page', n.id, label, '{}'::jsonb
  );

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

-- ---------------------------------------------------------------------------
-- Who can read and edit a page
-- ---------------------------------------------------------------------------

-- The limits of a page and the roles to choose from, for managers.
create or replace function public.kb_get_page_access(p_page_id uuid)
returns jsonb
language plpgsql
stable
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
  select * into n from public.notes
  where id = p_page_id and circle_id is not null and deleted_at is null;
  if n.id is null or public.kb_user_access(n.id, uid) < 1 then
    raise exception 'Page not found' using errcode = 'P0002';
  end if;
  if not public.kb_is_manager(n.circle_id, uid) then
    raise exception 'Only people who manage channels can see this'
      using errcode = '42501';
  end if;
  return jsonb_build_object(
    'view_role_ids', to_jsonb(n.view_role_ids),
    'edit_role_ids', to_jsonb(n.edit_role_ids),
    -- A higher role limited this page (or one above it): the caller can
    -- look but not change.
    'locked', public.kb_lock_rank(n.id) > public.circle_member_rank(n.circle_id, uid),
    'roles', coalesce((
      select jsonb_agg(
        jsonb_build_object('id', r.id, 'name', r.name, 'color', r.color)
        order by r.position desc
      )
      from public.circle_roles r
      where r.circle_id = n.circle_id and not r.is_default
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.kb_set_page_access(
  p_page_id uuid,
  p_view_role_ids uuid[],
  p_edit_role_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  n public.notes%rowtype;
  caller_rank integer;
  view_ids uuid[] := array(select distinct x from unnest(coalesce(p_view_role_ids, '{}'::uuid[])) x);
  edit_ids uuid[] := array(select distinct x from unnest(coalesce(p_edit_role_ids, '{}'::uuid[])) x);
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into n from public.notes
  where id = p_page_id and circle_id is not null and deleted_at is null
  for update;
  if n.id is null or public.kb_user_access(n.id, uid) < 1 then
    raise exception 'Page not found' using errcode = 'P0002';
  end if;
  if not public.kb_is_manager(n.circle_id, uid) then
    raise exception 'Only people who manage channels can change this'
      using errcode = '42501';
  end if;
  caller_rank := public.circle_member_rank(n.circle_id, uid);
  if public.kb_lock_rank(n.id) > caller_rank then
    raise exception 'A higher role limited this page' using errcode = '42501';
  end if;
  if cardinality(view_ids) > 10 or cardinality(edit_ids) > 10 then
    raise exception 'Up to 10 roles' using errcode = '22023';
  end if;
  if exists (
    select 1 from unnest(view_ids || edit_ids) x
    where not exists (
      select 1 from public.circle_roles r
      where r.id = x and r.circle_id = n.circle_id and not r.is_default
    )
  ) then
    raise exception 'Role not found' using errcode = '22023';
  end if;

  update public.notes
  set view_role_ids = view_ids,
      edit_role_ids = edit_ids,
      restrict_rank = case
        when cardinality(view_ids) = 0 and cardinality(edit_ids) = 0 then 0
        else caller_rank
      end
  where id = n.id
  returning * into n;

  perform public.write_circle_audit(
    n.circle_id,
    'kb_page_access',
    'page',
    n.id,
    public.kb_audit_label(n.id),
    jsonb_build_object(
      'view_roles', cardinality(view_ids),
      'edit_roles', cardinality(edit_ids)
    )
  );

  return public.note_json(n);
end;
$$;

revoke execute on function public.kb_list_pages(uuid) from public, anon;
revoke execute on function public.kb_mark_read(uuid) from public, anon;
revoke execute on function public.kb_search(uuid, text, integer) from public, anon;
revoke execute on function public.kb_create_page(uuid, uuid, text, text, uuid) from public, anon;
revoke execute on function public.kb_move_page(uuid, uuid, uuid) from public, anon;
revoke execute on function public.kb_delete_page(uuid) from public, anon;
revoke execute on function public.kb_get_page_access(uuid) from public, anon;
revoke execute on function public.kb_set_page_access(uuid, uuid[], uuid[]) from public, anon;
grant execute on function public.kb_list_pages(uuid) to authenticated;
grant execute on function public.kb_mark_read(uuid) to authenticated;
grant execute on function public.kb_search(uuid, text, integer) to authenticated;
grant execute on function public.kb_create_page(uuid, uuid, text, text, uuid) to authenticated;
grant execute on function public.kb_move_page(uuid, uuid, uuid) to authenticated;
grant execute on function public.kb_delete_page(uuid) to authenticated;
grant execute on function public.kb_get_page_access(uuid) to authenticated;
grant execute on function public.kb_set_page_access(uuid, uuid[], uuid[]) to authenticated;
