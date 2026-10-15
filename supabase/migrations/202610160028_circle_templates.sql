-- Circle templates, like Discord's server templates: a saved layout that
-- anyone with its code can start a new circle from.
--
-- * circle_templates: at most one per circle, with a shareable code (10
--   lowercase letters and digits), a name (1 to 100 characters), an
--   optional description (up to 120) and a snapshot of the layout. Clients
--   cannot read the table; the RPCs below return what they may see.
-- * The snapshot (circle_template_snapshot) keeps the roles (name, colour,
--   permissions, hoist, order, and @everyone's permissions), the
--   categories, and the channels (name, kind, topic, slowmode, voice user
--   limit, category, order, role permission overwrites and forum tags). It
--   keeps no messages, members, member overwrites, emoji or invites.
-- * Managing templates needs manage_circle (202610160020):
--   create_circle_template,
--   get_circle_template (the circle's template or null),
--   sync_circle_template (re-snapshots the circle), and
--   delete_circle_template. Audited as template_create, template_sync and
--   template_delete.
-- * preview_circle_template(code): any signed-in user with the code sees
--   its name, description, source circle name and layout outline.
-- * create_circle_from_template(code, circle_name): creates a circle with
--   create_circle (so the caller owns it and gets whatever every new
--   circle gets), replaces its default channels with the template's
--   categories and channels, sets @everyone's permissions and creates the
--   roles. Unknown permission bits are dropped. Counts the use.

create table if not exists public.circle_templates (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  snapshot jsonb not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  usage_count integer not null default 0,
  constraint circle_templates_circle_unique unique (circle_id),
  constraint circle_templates_code_unique unique (code),
  constraint circle_templates_code_format check (code ~ '^[a-z0-9]{10}$'),
  constraint circle_templates_name_length check (
    name = btrim(name) and char_length(name) between 1 and 100
  ),
  constraint circle_templates_description_length check (
    description is null
    or (description = btrim(description) and char_length(description) between 1 and 120)
  ),
  constraint circle_templates_snapshot_object check (jsonb_typeof(snapshot) = 'object')
);

alter table public.circle_templates enable row level security;

revoke all on public.circle_templates from anon;
revoke all on public.circle_templates from authenticated;

create or replace function public.new_circle_template_code()
returns text
language sql
volatile
set search_path = public
as $$
  select string_agg(
    substr('abcdefghjkmnpqrstuvwxyz23456789', (get_byte(bytes, i) % 31) + 1, 1),
    ''
  )
  from (select extensions.gen_random_bytes(10) as bytes) random_bytes,
    generate_series(0, 9) as i;
$$;

-- The layout of a circle, as stored in a template.
create or replace function public.circle_template_snapshot(target_circle_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'version', 1,
    'roles', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'key', r.id,
          'name', r.name,
          'color', r.color,
          'permissions', r.permissions,
          'hoist', r.hoist,
          'position', r.position,
          'is_default', r.is_default
        )
        order by r.position
      )
      from public.circle_roles r
      where r.circle_id = target_circle_id
    ), '[]'::jsonb),
    'categories', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'key', ccc.id,
          'name', ccc.name,
          'position', ccc.position
        )
        order by ccc.position, ccc.created_at
      )
      from public.circle_channel_categories ccc
      where ccc.circle_id = target_circle_id
    ), '[]'::jsonb),
    'channels', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'name', cc.name,
          'kind', cc.kind,
          'topic', cc.topic,
          'slowmode_seconds', cc.slowmode_seconds,
          'user_limit', cc.user_limit,
          'position', cc.position,
          'category_key', cc.category_id,
          'overwrites', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'role_key', o.role_id,
                'allow', o.allow,
                'deny', o.deny
              )
              order by o.created_at
            )
            from public.circle_channel_overwrites o
            where o.channel_id = cc.id
              and o.role_id is not null
          ), '[]'::jsonb),
          'tags', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'name', ft.name,
                'emoji', ft.emoji,
                'position', ft.position
              )
              order by ft.position, ft.created_at
            )
            from public.forum_tags ft
            where ft.channel_id = cc.id
          ), '[]'::jsonb)
        )
        order by cc.position, cc.created_at
      )
      from public.circle_channels cc
      where cc.circle_id = target_circle_id
    ), '[]'::jsonb)
  );
$$;

-- What managers and code holders see of a template.
create or replace function public.circle_template_payload(
  template public.circle_templates,
  include_snapshot boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', template.id,
    'circle_id', template.circle_id,
    'circle_name', c.name,
    'code', template.code,
    'name', template.name,
    'description', template.description,
    'created_by', template.created_by,
    'creator_name', case
      when template.created_by is null then null
      else public.circle_member_label(template.circle_id, template.created_by)
    end,
    'created_at', template.created_at,
    'updated_at', template.updated_at,
    'usage_count', template.usage_count,
    'role_count', (
      select count(*)
      from jsonb_array_elements(template.snapshot->'roles') role
      where not coalesce((role->>'is_default')::boolean, false)
    ),
    'category_count', jsonb_array_length(template.snapshot->'categories'),
    'channel_count', jsonb_array_length(template.snapshot->'channels')
  )
  || case
    when include_snapshot then jsonb_build_object(
      'categories', template.snapshot->'categories',
      'channels', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'name', channel->>'name',
            'kind', channel->>'kind',
            'category_key', channel->>'category_key'
          )
          order by ordinality
        ), '[]'::jsonb)
        from jsonb_array_elements(template.snapshot->'channels')
          with ordinality as channels(channel, ordinality)
      ),
      'roles', (
        select coalesce(jsonb_agg(
          jsonb_build_object('name', role->>'name', 'color', role->'color')
          order by (role->>'position')::integer desc
        ), '[]'::jsonb)
        from jsonb_array_elements(template.snapshot->'roles') role
        where not coalesce((role->>'is_default')::boolean, false)
      )
    )
    else '{}'::jsonb
  end
  from public.circles c
  where c.id = template.circle_id;
$$;

revoke execute on function public.new_circle_template_code() from public;
revoke execute on function public.new_circle_template_code() from anon;
revoke execute on function public.new_circle_template_code() from authenticated;
revoke execute on function public.circle_template_snapshot(uuid) from public;
revoke execute on function public.circle_template_snapshot(uuid) from anon;
revoke execute on function public.circle_template_snapshot(uuid) from authenticated;
revoke execute on function public.circle_template_payload(public.circle_templates, boolean) from public;
revoke execute on function public.circle_template_payload(public.circle_templates, boolean) from anon;
revoke execute on function public.circle_template_payload(public.circle_templates, boolean) from authenticated;

-- The template, when the caller may manage it; raises otherwise.
create or replace function public.circle_template_for_management(target_template_id uuid)
returns public.circle_templates
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  template public.circle_templates%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select t.* into template
  from public.circle_templates t
  where t.id = target_template_id;

  if template.id is null
    or not public.current_user_has_circle_permission(template.circle_id, 'manage_circle')
  then
    raise exception 'Template not found or caller cannot manage it'
      using errcode = '42501';
  end if;

  return template;
end;
$$;

revoke execute on function public.circle_template_for_management(uuid) from public;
revoke execute on function public.circle_template_for_management(uuid) from anon;
revoke execute on function public.circle_template_for_management(uuid) from authenticated;

create or replace function public.create_circle_template(
  target_circle_id uuid,
  template_name text,
  template_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  trimmed_name text := btrim(coalesce(template_name, ''));
  trimmed_description text := nullif(btrim(coalesce(template_description, '')), '');
  created public.circle_templates%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'Only members who manage the circle can create templates'
      using errcode = '42501';
  end if;

  if char_length(trimmed_name) not between 1 and 100 then
    raise exception 'Template name must be 1 to 100 characters'
      using errcode = '22023';
  end if;

  if trimmed_description is not null and char_length(trimmed_description) > 120 then
    raise exception 'Template description must be at most 120 characters'
      using errcode = '22023';
  end if;

  if exists (
    select 1 from public.circle_templates t where t.circle_id = target_circle_id
  ) then
    raise exception 'This circle already has a template' using errcode = '23505';
  end if;

  insert into public.circle_templates (
    circle_id,
    code,
    name,
    description,
    snapshot,
    created_by
  )
  values (
    target_circle_id,
    public.new_circle_template_code(),
    trimmed_name,
    trimmed_description,
    public.circle_template_snapshot(target_circle_id),
    auth.uid()
  )
  returning * into created;

  perform public.write_circle_audit(
    target_circle_id,
    'template_create',
    'template',
    created.id,
    created.name,
    '{}'::jsonb
  );

  return public.circle_template_payload(created);
end;
$$;

create or replace function public.get_circle_template(target_circle_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  template public.circle_templates%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'Only members who manage the circle can see templates'
      using errcode = '42501';
  end if;

  select t.* into template
  from public.circle_templates t
  where t.circle_id = target_circle_id;

  if template.id is null then
    return null;
  end if;

  return public.circle_template_payload(template);
end;
$$;

-- Re-snapshots the circle; name and description may change at the same
-- time (null keeps them).
create or replace function public.sync_circle_template(
  target_template_id uuid,
  template_name text default null,
  template_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  template public.circle_templates%rowtype :=
    public.circle_template_for_management(target_template_id);
  trimmed_name text := coalesce(nullif(btrim(coalesce(template_name, '')), ''), template.name);
  trimmed_description text := case
    when template_description is null then template.description
    else nullif(btrim(template_description), '')
  end;
  synced public.circle_templates%rowtype;
begin
  if char_length(trimmed_name) > 100 then
    raise exception 'Template name must be 1 to 100 characters'
      using errcode = '22023';
  end if;

  if trimmed_description is not null and char_length(trimmed_description) > 120 then
    raise exception 'Template description must be at most 120 characters'
      using errcode = '22023';
  end if;

  update public.circle_templates t
  set
    snapshot = public.circle_template_snapshot(template.circle_id),
    name = trimmed_name,
    description = trimmed_description,
    updated_at = now()
  where t.id = template.id
  returning * into synced;

  perform public.write_circle_audit(
    template.circle_id,
    'template_sync',
    'template',
    template.id,
    synced.name,
    '{}'::jsonb
  );

  return public.circle_template_payload(synced);
end;
$$;

create or replace function public.delete_circle_template(target_template_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  template public.circle_templates%rowtype :=
    public.circle_template_for_management(target_template_id);
begin
  delete from public.circle_templates t where t.id = template.id;

  perform public.write_circle_audit(
    template.circle_id,
    'template_delete',
    'template',
    template.id,
    template.name,
    '{}'::jsonb
  );
end;
$$;

create or replace function public.preview_circle_template(template_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  template public.circle_templates%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select t.* into template
  from public.circle_templates t
  where t.code = lower(btrim(coalesce(template_code, '')));

  if template.id is null then
    raise exception 'Template not found' using errcode = 'P0002';
  end if;

  return public.circle_template_payload(template, true);
end;
$$;

create or replace function public.create_circle_from_template(
  template_code text,
  circle_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  template public.circle_templates%rowtype;
  created_circle_id uuid;
  role_ids jsonb := '{}'::jsonb;
  category_ids jsonb := '{}'::jsonb;
  item jsonb;
  overwrite jsonb;
  tag jsonb;
  created_id uuid;
  created_conversation_id uuid;
  next_position integer;
  kind_value text;
  overwrite_bits bigint := public.circle_channel_overwrite_permissions();
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select t.* into template
  from public.circle_templates t
  where t.code = lower(btrim(coalesce(template_code, '')))
  for update;

  if template.id is null then
    raise exception 'Template not found' using errcode = 'P0002';
  end if;

  created_circle_id := public.create_circle(circle_name, array[]::uuid[]);

  -- The template replaces the default channels.
  delete from public.conversations c
  using public.circle_channels cc
  where cc.circle_id = created_circle_id
    and c.id = cc.conversation_id;
  delete from public.circle_channel_categories ccc
  where ccc.circle_id = created_circle_id;

  -- Roles: @everyone's permissions, then the others in their order.
  next_position := 1;
  for item in
    select role
    from jsonb_array_elements(template.snapshot->'roles') role
    order by coalesce((role->>'position')::integer, 0)
  loop
    if coalesce((item->>'is_default')::boolean, false) then
      update public.circle_roles r
      set permissions = coalesce((item->>'permissions')::bigint, 0)
        & public.circle_all_permissions()
      where r.circle_id = created_circle_id
        and r.is_default
      returning r.id into created_id;
    else
      insert into public.circle_roles (
        circle_id,
        name,
        color,
        position,
        permissions,
        hoist
      )
      values (
        created_circle_id,
        btrim(left(btrim(coalesce(item->>'name', 'Role')), 32)),
        case
          when (item->>'color') ~ '^[0-9]+$'
            and (item->>'color')::bigint between 0 and 16777215
            then (item->>'color')::integer
        end,
        next_position,
        coalesce((item->>'permissions')::bigint, 0) & public.circle_all_permissions(),
        coalesce((item->>'hoist')::boolean, false)
      )
      returning id into created_id;
      next_position := next_position + 1;
    end if;

    if item->>'key' is not null then
      role_ids := role_ids || jsonb_build_object(item->>'key', created_id);
    end if;
  end loop;

  for item in
    select category
    from jsonb_array_elements(template.snapshot->'categories') category
  loop
    insert into public.circle_channel_categories (circle_id, name, position)
    values (
      created_circle_id,
      left(btrim(coalesce(item->>'name', 'Category')), 32),
      coalesce((item->>'position')::integer, 0)
    )
    returning id into created_id;

    if item->>'key' is not null then
      category_ids := category_ids || jsonb_build_object(item->>'key', created_id);
    end if;
  end loop;

  for item in
    select channel
    from jsonb_array_elements(template.snapshot->'channels') channel
  loop
    kind_value := coalesce(item->>'kind', 'text');

    insert into public.conversations (type, title)
    values ('channel', left(btrim(coalesce(item->>'name', 'channel')), 48))
    returning id into created_conversation_id;

    insert into public.conversation_members (conversation_id, user_id, role)
    select created_conversation_id, cm.user_id, cm.role
    from public.circle_members cm
    where cm.circle_id = created_circle_id
    on conflict do nothing;

    insert into public.circle_channels (
      circle_id,
      conversation_id,
      name,
      position,
      category_id,
      created_by,
      kind,
      topic,
      slowmode_seconds,
      user_limit
    )
    values (
      created_circle_id,
      created_conversation_id,
      left(btrim(coalesce(item->>'name', 'channel')), 48),
      coalesce((item->>'position')::integer, 0),
      (category_ids->>(item->>'category_key'))::uuid,
      current_user_id,
      kind_value,
      nullif(item->>'topic', ''),
      least(greatest(coalesce((item->>'slowmode_seconds')::integer, 0), 0), 21600),
      least(greatest(coalesce((item->>'user_limit')::integer, 0), 0), 99)
    )
    returning id into created_id;

    for overwrite in
      select value from jsonb_array_elements(coalesce(item->'overwrites', '[]'::jsonb))
    loop
      if role_ids ? (overwrite->>'role_key') then
        insert into public.circle_channel_overwrites (
          circle_id,
          channel_id,
          role_id,
          allow,
          deny
        )
        values (
          created_circle_id,
          created_id,
          (role_ids->>(overwrite->>'role_key'))::uuid,
          coalesce((overwrite->>'allow')::bigint, 0) & overwrite_bits,
          coalesce((overwrite->>'deny')::bigint, 0) & overwrite_bits
            & ~(coalesce((overwrite->>'allow')::bigint, 0) & overwrite_bits)
        )
        on conflict do nothing;
      end if;
    end loop;

    if kind_value = 'forum' then
      for tag in
        select value from jsonb_array_elements(coalesce(item->'tags', '[]'::jsonb))
      loop
        insert into public.forum_tags (circle_id, channel_id, name, emoji, position)
        values (
          created_circle_id,
          created_id,
          btrim(left(btrim(coalesce(tag->>'name', 'tag')), 20)),
          nullif(tag->>'emoji', ''),
          coalesce((tag->>'position')::integer, 0)
        )
        on conflict do nothing;
      end loop;
    end if;
  end loop;

  update public.circle_templates t
  set usage_count = t.usage_count + 1
  where t.id = template.id;

  return created_circle_id;
end;
$$;

grant execute on function public.create_circle_template(uuid, text, text) to authenticated;
grant execute on function public.get_circle_template(uuid) to authenticated;
grant execute on function public.sync_circle_template(uuid, text, text) to authenticated;
grant execute on function public.delete_circle_template(uuid) to authenticated;
grant execute on function public.preview_circle_template(text) to authenticated;
grant execute on function public.create_circle_from_template(text, text) to authenticated;
