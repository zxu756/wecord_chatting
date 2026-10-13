-- Audit log, like Discord's: every management RPC of a circle records who
-- did what to which channel, category, role, member, invite, message,
-- thread or post, with the changed fields as {old, new} where it helps.
--
-- Entries are written only by write_circle_audit inside those RPCs (after
-- their checks, in the same transaction), never by clients. Members with
-- view_audit_log (the owner and administrators always) read them with
-- list_circle_audit_log, newest first, a page at a time. Calls that change
-- nothing (renaming to the same name, setting the same slowmode, pinning a
-- pinned message, ...) are not logged, and neither are members changing
-- their own nickname or archiving their own threads. target_label keeps
-- the target's name at the time, so entries still read well after the
-- target is renamed or deleted.
--
-- Actions, grouped by the prefix before the first underscore:
--   channel_create, channel_reorder, channel_permissions_update,
--   channel_privacy_update, channel_slowmode_update;
--   category_create, category_rename, category_delete;
--   role_create, role_update, role_delete, role_reorder;
--   member_add, member_roles_update, member_nickname_update, member_kick,
--   member_leave; circle_ownership_transfer;
--   invite_create, invite_revoke; message_pin, message_unpin;
--   thread_archive, thread_unarchive; post_delete.

create table if not exists public.circle_audit_log (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  target_type text not null,
  target_id uuid,
  target_label text,
  changes jsonb not null default '{}'::jsonb,
  -- clock_timestamp keeps entries of one transaction in order for paging.
  created_at timestamptz not null default clock_timestamp(),
  constraint circle_audit_log_action_format check (action ~ '^[a-z]+(_[a-z]+)+$'),
  constraint circle_audit_log_target_type_format check (target_type ~ '^[a-z]+$'),
  constraint circle_audit_log_changes_object check (jsonb_typeof(changes) = 'object')
);

create index if not exists circle_audit_log_circle_created_idx
  on public.circle_audit_log (circle_id, created_at desc);

alter table public.circle_audit_log enable row level security;

revoke insert, update, delete, truncate on public.circle_audit_log from anon;
revoke insert, update, delete, truncate on public.circle_audit_log from authenticated;

drop policy if exists circle_audit_log_select_viewer on public.circle_audit_log;
create policy circle_audit_log_select_viewer
  on public.circle_audit_log for select
  to authenticated
  using (public.current_user_has_circle_permission(circle_id, 'view_audit_log'));

-- Records one entry by the caller. Only management RPCs call this.
create or replace function public.write_circle_audit(
  target_circle_id uuid,
  audit_action text,
  audit_target_type text,
  audit_target_id uuid,
  audit_target_label text,
  audit_changes jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.circle_audit_log (
    circle_id,
    actor_id,
    action,
    target_type,
    target_id,
    target_label,
    changes
  )
  values (
    target_circle_id,
    auth.uid(),
    audit_action,
    audit_target_type,
    audit_target_id,
    audit_target_label,
    coalesce(audit_changes, '{}'::jsonb)
  );
end;
$$;

-- A user's name inside a circle: nickname, display name, then username.
create or replace function public.circle_member_label(
  target_circle_id uuid,
  target_user_id uuid
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(btrim(cm.nickname), ''),
    nullif(btrim(p.display_name), ''),
    p.username
  )
  from public.profiles p
  left join public.circle_members cm
    on cm.circle_id = target_circle_id
    and cm.user_id = p.id
  where p.id = target_user_id;
$$;

revoke execute on function public.write_circle_audit(uuid, text, text, uuid, text, jsonb) from public;
revoke execute on function public.write_circle_audit(uuid, text, text, uuid, text, jsonb) from anon;
revoke execute on function public.write_circle_audit(uuid, text, text, uuid, text, jsonb) from authenticated;
revoke execute on function public.circle_member_label(uuid, uuid) from public;
revoke execute on function public.circle_member_label(uuid, uuid) from anon;
revoke execute on function public.circle_member_label(uuid, uuid) from authenticated;

-- Same as 202610130012_circle_roles, plus an audit entry.
create or replace function public.create_circle_channel(
  target_circle_id uuid,
  channel_name text,
  target_category_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_name text := trim(coalesce(channel_name, ''));
  created_conversation_id uuid;
  created_channel_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_name) = 0 or char_length(trimmed_name) > 48 then
    raise exception 'Channel name must be between 1 and 48 characters'
      using errcode = '22023';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'manage_channels'
  ) then
    raise exception 'Only members who can manage channels can create channels'
      using errcode = '42501';
  end if;

  perform 1 from public.circles where id = target_circle_id for no key update;

  if target_category_id is not null and not exists (
    select 1
    from public.circle_channel_categories ccc
    where ccc.id = target_category_id
      and ccc.circle_id = target_circle_id
  ) then
    raise exception 'Category does not belong to this circle'
      using errcode = '22023';
  end if;

  insert into public.conversations (type, title)
  values ('channel', trimmed_name)
  returning id into created_conversation_id;

  insert into public.conversation_members (conversation_id, user_id, role)
  select created_conversation_id, cm.user_id, cm.role
  from public.circle_members cm
  where cm.circle_id = target_circle_id
  on conflict do nothing;

  insert into public.circle_channels (
    circle_id,
    conversation_id,
    name,
    position,
    category_id,
    created_by
  )
  values (
    target_circle_id,
    created_conversation_id,
    trimmed_name,
    coalesce((
      select max(position) + 1
      from public.circle_channels
      where circle_id = target_circle_id
    ), 0),
    target_category_id,
    current_user_id
  )
  returning id into created_channel_id;

  perform public.write_circle_audit(
    target_circle_id,
    'channel_create',
    'channel',
    created_channel_id,
    trimmed_name,
    jsonb_build_object(
      'name', trimmed_name,
      'category_id', target_category_id,
      'category_name', (
        select ccc.name
        from public.circle_channel_categories ccc
        where ccc.id = target_category_id
      )
    )
  );

  return created_channel_id;
end;
$$;

-- Same as 202610130012_circle_roles, plus an audit entry.
create or replace function public.create_channel_category(
  target_circle_id uuid,
  category_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_name text := trim(coalesce(category_name, ''));
  created_category_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_name) = 0 or char_length(trimmed_name) > 32 then
    raise exception 'Category name must be between 1 and 32 characters'
      using errcode = '22023';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'manage_channels'
  ) then
    raise exception 'Only members who can manage channels can manage categories'
      using errcode = '42501';
  end if;

  -- Serialises layout changes of one circle.
  perform 1 from public.circles where id = target_circle_id for no key update;

  insert into public.circle_channel_categories (circle_id, name, position)
  values (
    target_circle_id,
    trimmed_name,
    coalesce((
      select max(position) + 1
      from public.circle_channel_categories
      where circle_id = target_circle_id
    ), 0)
  )
  returning id into created_category_id;

  perform public.write_circle_audit(
    target_circle_id,
    'category_create',
    'category',
    created_category_id,
    trimmed_name,
    jsonb_build_object('name', trimmed_name)
  );

  return created_category_id;
end;
$$;

-- Same as 202610130012_circle_roles, plus an audit entry when the name changes.
create or replace function public.rename_channel_category(
  target_category_id uuid,
  category_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_name text := trim(coalesce(category_name, ''));
  target_circle_id uuid;
  old_name text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_name) = 0 or char_length(trimmed_name) > 32 then
    raise exception 'Category name must be between 1 and 32 characters'
      using errcode = '22023';
  end if;

  select ccc.circle_id, ccc.name into target_circle_id, old_name
  from public.circle_channel_categories ccc
  where ccc.id = target_category_id;

  if target_circle_id is null
    or not public.current_user_has_circle_permission(
      target_circle_id,
      'manage_channels'
    )
  then
    raise exception 'Only members who can manage channels can manage categories'
      using errcode = '42501';
  end if;

  update public.circle_channel_categories
  set name = trimmed_name
  where id = target_category_id;

  if old_name is distinct from trimmed_name then
    perform public.write_circle_audit(
      target_circle_id,
      'category_rename',
      'category',
      target_category_id,
      trimmed_name,
      jsonb_build_object(
        'name',
        jsonb_build_object('old', old_name, 'new', trimmed_name)
      )
    );
  end if;
end;
$$;

-- Same as 202610130012_circle_roles, plus an audit entry.
create or replace function public.delete_channel_category(target_category_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_circle_id uuid;
  category_name text;
  moved_channel_count integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select ccc.circle_id, ccc.name into target_circle_id, category_name
  from public.circle_channel_categories ccc
  where ccc.id = target_category_id;

  if target_circle_id is null
    or not public.current_user_has_circle_permission(
      target_circle_id,
      'manage_channels'
    )
  then
    raise exception 'Only members who can manage channels can manage categories'
      using errcode = '42501';
  end if;

  perform 1 from public.circles where id = target_circle_id for no key update;

  -- The foreign key would do this too; updating first keeps updated_at
  -- honest and notifies realtime listeners of circle_channels.
  update public.circle_channels
  set category_id = null,
      updated_at = now()
  where category_id = target_category_id;
  get diagnostics moved_channel_count = row_count;

  delete from public.circle_channel_categories
  where id = target_category_id;

  perform public.write_circle_audit(
    target_circle_id,
    'category_delete',
    'category',
    target_category_id,
    category_name,
    jsonb_build_object(
      'name', category_name,
      'channels_moved', moved_channel_count
    )
  );
end;
$$;

-- Same as 202610130014_channel_permission_overwrites, plus one audit entry listing what moved.
create or replace function public.reorder_circle_channels(
  target_circle_id uuid,
  layout jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  category_ids uuid[];
  channel_ids uuid[];
  channel_category_ids uuid[];
  visible_channel_ids uuid[];
  slots integer[];
  moved_categories jsonb;
  moved_channels jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'manage_channels'
  ) then
    raise exception 'Only members who can manage channels can reorder channels'
      using errcode = '42501';
  end if;

  if jsonb_typeof(layout) is distinct from 'object'
    or jsonb_typeof(layout -> 'categories') is distinct from 'array'
    or jsonb_typeof(layout -> 'channels') is distinct from 'array'
    or exists (
      select 1
      from jsonb_array_elements(layout -> 'categories') as item(value)
      where jsonb_typeof(item.value) <> 'string'
    )
    or exists (
      select 1
      from jsonb_array_elements(layout -> 'channels') as item(value)
      where jsonb_typeof(item.value) <> 'object'
        or jsonb_typeof(item.value -> 'id') is distinct from 'string'
        or coalesce(jsonb_typeof(item.value -> 'category_id'), 'null')
          not in ('string', 'null')
    )
  then
    raise exception 'Invalid channel layout' using errcode = '22023';
  end if;

  begin
    select coalesce(array_agg((item.value #>> '{}')::uuid order by item.ordinality), '{}')
    into category_ids
    from jsonb_array_elements(layout -> 'categories') with ordinality as item(value, ordinality);

    select
      coalesce(array_agg((item.value ->> 'id')::uuid order by item.ordinality), '{}'),
      coalesce(array_agg((item.value ->> 'category_id')::uuid order by item.ordinality), '{}')
    into channel_ids, channel_category_ids
    from jsonb_array_elements(layout -> 'channels') with ordinality as item(value, ordinality);
  exception
    when invalid_text_representation then
      raise exception 'Invalid channel layout' using errcode = '22023';
  end;

  -- Lock the circle so concurrent creates and reorders apply one at a time.
  perform 1 from public.circles where id = target_circle_id for no key update;

  if cardinality(category_ids) <> (
      select count(distinct category_id) from unnest(category_ids) as ids(category_id)
    )
    or (
      select count(*)
      from public.circle_channel_categories ccc
      where ccc.circle_id = target_circle_id
    ) <> cardinality(category_ids)
    or exists (
      select 1
      from unnest(category_ids) as ids(category_id)
      where not exists (
        select 1
        from public.circle_channel_categories ccc
        where ccc.id = ids.category_id
          and ccc.circle_id = target_circle_id
      )
    )
  then
    raise exception 'Layout must list every category of the circle once'
      using errcode = '22023';
  end if;

  select coalesce(array_agg(cc.id), '{}')
  into visible_channel_ids
  from public.circle_channels cc
  where cc.circle_id = target_circle_id
    and public.circle_channel_has_permission(cc.id, current_user_id, 'view_channel');

  if cardinality(channel_ids) <> (
      select count(distinct channel_id) from unnest(channel_ids) as ids(channel_id)
    )
    or cardinality(visible_channel_ids) <> cardinality(channel_ids)
    or exists (
      select 1
      from unnest(channel_ids) as ids(channel_id)
      where not (ids.channel_id = any(visible_channel_ids))
    )
  then
    raise exception 'Layout must list every channel of the circle once'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(channel_category_ids) as ids(category_id)
    where ids.category_id is not null
      and not (ids.category_id = any(category_ids))
  ) then
    raise exception 'Channels can only be placed in categories of the circle'
      using errcode = '22023';
  end if;

  -- Positions handed out in layout order: 0, 1, 2, ... when the caller sees
  -- every channel, otherwise the visible channels' current positions.
  if (
    select count(*)
    from public.circle_channels cc
    where cc.circle_id = target_circle_id
  ) = cardinality(visible_channel_ids) then
    select coalesce(array_agg(slot.position order by slot.position), '{}')
    into slots
    from generate_series(0, cardinality(channel_ids) - 1) as slot(position);
  else
    select coalesce(array_agg(cc.position order by cc.position, cc.created_at), '{}')
    into slots
    from public.circle_channels cc
    where cc.id = any(visible_channel_ids);
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', ccc.id,
        'name', ccc.name,
        'position', jsonb_build_object(
          'old', ccc.position,
          'new', ordered.ordinality - 1
        )
      )
      order by ordered.ordinality
    ),
    '[]'::jsonb
  )
  into moved_categories
  from unnest(category_ids) with ordinality as ordered(category_id, ordinality)
  join public.circle_channel_categories ccc on ccc.id = ordered.category_id
  where ccc.position is distinct from ordered.ordinality - 1;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', cc.id,
        'name', cc.name,
        'position', jsonb_build_object(
          'old', cc.position,
          'new', slots[ordered.ordinality]
        ),
        'category_id', jsonb_build_object(
          'old', cc.category_id,
          'new', ordered.category_id
        )
      )
      order by ordered.ordinality
    ),
    '[]'::jsonb
  )
  into moved_channels
  from unnest(channel_ids, channel_category_ids)
    with ordinality as ordered(channel_id, category_id, ordinality)
  join public.circle_channels cc on cc.id = ordered.channel_id
  where cc.position is distinct from slots[ordered.ordinality]
    or cc.category_id is distinct from ordered.category_id;

  update public.circle_channel_categories ccc
  set position = ordered.ordinality - 1
  from unnest(category_ids) with ordinality as ordered(category_id, ordinality)
  where ccc.id = ordered.category_id
    and ccc.position is distinct from ordered.ordinality - 1;

  update public.circle_channels cc
  set position = slots[ordered.ordinality],
      category_id = ordered.category_id,
      updated_at = now()
  from unnest(channel_ids, channel_category_ids)
    with ordinality as ordered(channel_id, category_id, ordinality)
  where cc.id = ordered.channel_id
    and (
      cc.position is distinct from slots[ordered.ordinality]
      or cc.category_id is distinct from ordered.category_id
    );

  if moved_categories <> '[]'::jsonb or moved_channels <> '[]'::jsonb then
    perform public.write_circle_audit(
      target_circle_id,
      'channel_reorder',
      'circle',
      target_circle_id,
      (select c.name from public.circles c where c.id = target_circle_id),
      jsonb_build_object(
        'categories', moved_categories,
        'channels', moved_channels
      )
    );
  end if;
end;
$$;

-- Same as 202610130014_channel_permission_overwrites, plus an audit entry when the overwrite changes.
create or replace function public.set_channel_overwrite(
  target_channel_id uuid,
  target_role_id uuid,
  target_user_id uuid,
  allow_bits bigint,
  deny_bits bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_channel public.circle_channels%rowtype;
  existing public.circle_channel_overwrites%rowtype;
  stored public.circle_channel_overwrites%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if (target_role_id is null) = (target_user_id is null) then
    raise exception 'Set either a role or a member' using errcode = '22023';
  end if;

  if allow_bits is null
    or deny_bits is null
    or allow_bits < 0
    or deny_bits < 0
    or allow_bits & ~public.circle_channel_overwrite_permissions() <> 0
    or deny_bits & ~public.circle_channel_overwrite_permissions() <> 0
  then
    raise exception 'Unknown channel permissions' using errcode = '22023';
  end if;

  if allow_bits & deny_bits <> 0 then
    raise exception 'A permission cannot be both allowed and denied'
      using errcode = '22023';
  end if;

  select cc.* into target_channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if target_channel.id is null
    or not public.is_current_user_circle_member(target_channel.circle_id)
  then
    raise exception 'Channel not found or caller is not a member'
      using errcode = '42501';
  end if;

  -- Serialises permission changes of one circle.
  perform 1 from public.circles where id = target_channel.circle_id for no key update;

  select o.* into existing
  from public.circle_channel_overwrites o
  where o.channel_id = target_channel_id
    and (
      (target_role_id is not null and o.role_id = target_role_id)
      or (target_user_id is not null and o.user_id = target_user_id)
    );

  perform public.check_channel_overwrite_edit(
    target_channel,
    target_role_id,
    target_user_id,
    (allow_bits # coalesce(existing.allow, 0))
      | (deny_bits # coalesce(existing.deny, 0))
  );

  if coalesce(existing.allow, 0) <> allow_bits
    or coalesce(existing.deny, 0) <> deny_bits
  then
    perform public.write_circle_audit(
      target_channel.circle_id,
      'channel_permissions_update',
      'channel',
      target_channel.id,
      target_channel.name,
      jsonb_build_object(
        'role_id', target_role_id,
        'user_id', target_user_id,
        'target_name', coalesce(
          (select r.name from public.circle_roles r where r.id = target_role_id),
          public.circle_member_label(target_channel.circle_id, target_user_id)
        ),
        'allow', jsonb_build_object('old', coalesce(existing.allow, 0), 'new', allow_bits),
        'deny', jsonb_build_object('old', coalesce(existing.deny, 0), 'new', deny_bits)
      )
    );
  end if;

  if allow_bits = 0 and deny_bits = 0 then
    delete from public.circle_channel_overwrites o where o.id = existing.id;
    return null;
  end if;

  if existing.id is null then
    insert into public.circle_channel_overwrites (
      circle_id,
      channel_id,
      role_id,
      user_id,
      allow,
      deny
    )
    values (
      target_channel.circle_id,
      target_channel_id,
      target_role_id,
      target_user_id,
      allow_bits,
      deny_bits
    )
    returning * into stored;
  else
    update public.circle_channel_overwrites o
    set allow = allow_bits,
        deny = deny_bits
    where o.id = existing.id
    returning * into stored;
  end if;

  return jsonb_build_object(
    'id', stored.id,
    'channel_id', stored.channel_id,
    'role_id', stored.role_id,
    'user_id', stored.user_id,
    'allow', stored.allow,
    'deny', stored.deny
  );
end;
$$;

-- Same as 202610130014_channel_permission_overwrites, plus an audit entry when either switch changes.
create or replace function public.set_channel_privacy(
  target_channel_id uuid,
  private boolean,
  read_only boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  view_bit bigint := public.circle_permission_bit('view_channel');
  send_bit bigint := public.circle_permission_bit('send_messages');
  target_channel public.circle_channels%rowtype;
  default_role_id uuid;
  existing public.circle_channel_overwrites%rowtype;
  next_allow bigint;
  next_deny bigint;
  kept_bits bigint;
  missing_bits bigint;
  highest_role_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if private is null or read_only is null then
    raise exception 'Choose whether the channel is private and read-only'
      using errcode = '22023';
  end if;

  select cc.* into target_channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if target_channel.id is null
    or not public.is_current_user_circle_member(target_channel.circle_id)
  then
    raise exception 'Channel not found or caller is not a member'
      using errcode = '42501';
  end if;

  perform 1 from public.circles where id = target_channel.circle_id for no key update;

  select r.id into default_role_id
  from public.circle_roles r
  where r.circle_id = target_channel.circle_id
    and r.is_default;

  select o.* into existing
  from public.circle_channel_overwrites o
  where o.channel_id = target_channel_id
    and o.role_id = default_role_id;

  next_deny := coalesce(existing.deny, 0) & ~(view_bit | send_bit);
  next_allow := coalesce(existing.allow, 0);
  if private then
    next_deny := next_deny | view_bit;
    next_allow := next_allow & ~view_bit;
  end if;
  if read_only then
    next_deny := next_deny | send_bit;
    next_allow := next_allow & ~send_bit;
  end if;

  -- What the caller can do in the channel now, and should still do after.
  kept_bits := public.circle_channel_permissions(target_channel_id, current_user_id)
    & (view_bit | send_bit);

  perform public.check_channel_overwrite_edit(
    target_channel,
    default_role_id,
    null,
    (next_allow # coalesce(existing.allow, 0))
      | (next_deny # coalesce(existing.deny, 0))
  );

  if (coalesce(existing.deny, 0) & view_bit <> 0) is distinct from private
    or (coalesce(existing.deny, 0) & send_bit <> 0) is distinct from read_only
  then
    perform public.write_circle_audit(
      target_channel.circle_id,
      'channel_privacy_update',
      'channel',
      target_channel.id,
      target_channel.name,
      jsonb_build_object(
        'private', jsonb_build_object(
          'old', coalesce(existing.deny, 0) & view_bit <> 0,
          'new', private
        ),
        'read_only', jsonb_build_object(
          'old', coalesce(existing.deny, 0) & send_bit <> 0,
          'new', read_only
        )
      )
    );
  end if;

  if next_allow = 0 and next_deny = 0 then
    delete from public.circle_channel_overwrites o where o.id = existing.id;
  elsif existing.id is null then
    insert into public.circle_channel_overwrites (
      circle_id,
      channel_id,
      role_id,
      allow,
      deny
    )
    values (
      target_channel.circle_id,
      target_channel_id,
      default_role_id,
      next_allow,
      next_deny
    );
  else
    update public.circle_channel_overwrites o
    set allow = next_allow,
        deny = next_deny
    where o.id = existing.id;
  end if;

  -- Only bits this change denies count: losing view_channel also hides
  -- send_messages, which comes back with it.
  missing_bits := kept_bits
    & next_deny
    & ~public.circle_channel_permissions(target_channel_id, current_user_id);
  if missing_bits = 0 then
    return;
  end if;

  select mr.role_id into highest_role_id
  from public.circle_member_roles mr
  join public.circle_roles r on r.id = mr.role_id
  where mr.circle_id = target_channel.circle_id
    and mr.user_id = current_user_id
  order by r.position desc
  limit 1;

  if highest_role_id is not null then
    insert into public.circle_channel_overwrites (
      circle_id,
      channel_id,
      role_id,
      allow,
      deny
    )
    values (
      target_channel.circle_id,
      target_channel_id,
      highest_role_id,
      missing_bits,
      0
    )
    on conflict (channel_id, role_id) do update
    set allow = circle_channel_overwrites.allow | excluded.allow
    -- A deny on the role was set by someone ranked above the caller; the
    -- caller's own overwrite below handles that case instead.
    where circle_channel_overwrites.deny & excluded.allow = 0;

    missing_bits := kept_bits
      & next_deny
      & ~public.circle_channel_permissions(target_channel_id, current_user_id);
  end if;

  if missing_bits <> 0 then
    insert into public.circle_channel_overwrites (
      circle_id,
      channel_id,
      user_id,
      allow,
      deny
    )
    values (
      target_channel.circle_id,
      target_channel_id,
      current_user_id,
      missing_bits,
      0
    )
    on conflict (channel_id, user_id) do update
    set allow = circle_channel_overwrites.allow | excluded.allow,
        deny = circle_channel_overwrites.deny & ~excluded.allow;
  end if;
end;
$$;

-- Same as 202610130015_channel_slowmode, plus an audit entry when slowmode changes.
create or replace function public.set_channel_slowmode(
  target_channel_id uuid,
  seconds integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  channel_circle_id uuid;
  channel_name text;
  old_seconds integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if seconds is null or seconds < 0 or seconds > 21600 then
    raise exception 'Slowmode must be between 0 seconds and 6 hours'
      using errcode = '22023';
  end if;

  select cc.circle_id, cc.name, cc.slowmode_seconds
  into channel_circle_id, channel_name, old_seconds
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel_circle_id is null
    or not public.current_user_has_circle_permission(
      channel_circle_id,
      'manage_channels'
    )
    or not public.current_user_has_channel_permission(
      target_channel_id,
      'view_channel'
    )
  then
    raise exception 'Only members who can manage channels can change slowmode'
      using errcode = '42501';
  end if;

  update public.circle_channels cc
  set slowmode_seconds = seconds,
      updated_at = now()
  where cc.id = target_channel_id
    and cc.slowmode_seconds is distinct from seconds;

  if found then
    perform public.write_circle_audit(
      channel_circle_id,
      'channel_slowmode_update',
      'channel',
      target_channel_id,
      channel_name,
      jsonb_build_object(
        'slowmode_seconds',
        jsonb_build_object('old', old_seconds, 'new', seconds)
      )
    );
  end if;
end;
$$;

-- Same as 202610130012_circle_roles, plus an audit entry.
create or replace function public.create_circle_role(
  target_circle_id uuid,
  role_name text,
  role_color integer default null,
  role_permissions bigint default 0,
  role_hoist boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_name text;
  caller_permissions bigint;
  caller_rank integer;
  created_role_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(target_circle_id, 'manage_roles') then
    raise exception 'Only members who can manage roles can create roles'
      using errcode = '42501';
  end if;

  normalized_name := public.normalize_circle_role_name(role_name);
  perform public.validate_circle_role_fields(role_color, role_permissions);

  -- Serialises role changes of one circle.
  perform 1 from public.circles where id = target_circle_id for no key update;

  caller_permissions := public.circle_member_permissions(target_circle_id, current_user_id);
  caller_rank := public.circle_member_rank(target_circle_id, current_user_id);

  if role_permissions & ~caller_permissions <> 0 then
    raise exception 'Cannot grant permissions you do not have'
      using errcode = '42501';
  end if;

  -- The new role takes position 1 and every other role moves up one, so
  -- it lands below the caller as long as they hold any role.
  if caller_rank < 1 then
    raise exception 'Cannot create a role at or above your highest role'
      using errcode = '42501';
  end if;

  if (
    select count(*)
    from public.circle_roles r
    where r.circle_id = target_circle_id
  ) >= 100 then
    raise exception 'A circle can have at most 100 roles' using errcode = '22023';
  end if;

  update public.circle_roles
  set position = position + 1
  where circle_id = target_circle_id
    and not is_default;

  insert into public.circle_roles (
    circle_id,
    name,
    color,
    position,
    permissions,
    hoist
  )
  values (
    target_circle_id,
    normalized_name,
    role_color,
    1,
    role_permissions,
    coalesce(role_hoist, false)
  )
  returning id into created_role_id;

  perform public.write_circle_audit(
    target_circle_id,
    'role_create',
    'role',
    created_role_id,
    normalized_name,
    jsonb_build_object(
      'name', normalized_name,
      'color', role_color,
      'permissions', role_permissions,
      'hoist', coalesce(role_hoist, false)
    )
  );

  return created_role_id;
end;
$$;

-- Same as 202610130012_circle_roles, plus an audit entry with the changed fields.
create or replace function public.update_circle_role(
  target_role_id uuid,
  role_name text,
  role_color integer default null,
  role_permissions bigint default 0,
  role_hoist boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_role public.circle_roles%rowtype;
  normalized_name text;
  caller_permissions bigint;
  role_changes jsonb := '{}'::jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select r.* into target_role
  from public.circle_roles r
  where r.id = target_role_id;

  if target_role.id is null
    or not public.current_user_has_circle_permission(
      target_role.circle_id,
      'manage_roles'
    )
  then
    raise exception 'Role not found or caller cannot manage roles'
      using errcode = '42501';
  end if;

  perform public.validate_circle_role_fields(role_color, role_permissions);

  if target_role.is_default then
    if btrim(coalesce(role_name, '')) <> target_role.name then
      raise exception 'The default role cannot be renamed' using errcode = '22023';
    end if;
    if role_color is not null or coalesce(role_hoist, false) then
      raise exception 'The default role cannot be coloured or hoisted'
        using errcode = '22023';
    end if;
    normalized_name := target_role.name;
  else
    normalized_name := public.normalize_circle_role_name(role_name);
  end if;

  perform 1 from public.circles where id = target_role.circle_id for no key update;

  -- Re-read under the lock: a concurrent reorder may have moved it.
  select r.* into target_role
  from public.circle_roles r
  where r.id = target_role_id;

  if target_role.position
    >= public.circle_member_rank(target_role.circle_id, current_user_id)
  then
    raise exception 'Cannot edit a role at or above your highest role'
      using errcode = '42501';
  end if;

  caller_permissions := public.circle_member_permissions(
    target_role.circle_id,
    current_user_id
  );
  if (role_permissions # target_role.permissions) & ~caller_permissions <> 0 then
    raise exception 'Cannot change permissions you do not have'
      using errcode = '42501';
  end if;

  update public.circle_roles
  set name = normalized_name,
      color = role_color,
      permissions = role_permissions,
      hoist = coalesce(role_hoist, false)
  where id = target_role_id;

  perform public.sync_circle_admin_roles(target_role.circle_id);

  -- Only the fields that changed, each as {old, new}.
  if target_role.name is distinct from normalized_name then
    role_changes := role_changes || jsonb_build_object(
      'name', jsonb_build_object('old', target_role.name, 'new', normalized_name)
    );
  end if;
  if target_role.color is distinct from role_color then
    role_changes := role_changes || jsonb_build_object(
      'color', jsonb_build_object('old', target_role.color, 'new', role_color)
    );
  end if;
  if target_role.permissions is distinct from role_permissions then
    role_changes := role_changes || jsonb_build_object(
      'permissions',
      jsonb_build_object('old', target_role.permissions, 'new', role_permissions)
    );
  end if;
  if target_role.hoist is distinct from coalesce(role_hoist, false) then
    role_changes := role_changes || jsonb_build_object(
      'hoist',
      jsonb_build_object('old', target_role.hoist, 'new', coalesce(role_hoist, false))
    );
  end if;

  if role_changes <> '{}'::jsonb then
    perform public.write_circle_audit(
      target_role.circle_id,
      'role_update',
      'role',
      target_role_id,
      normalized_name,
      role_changes
    );
  end if;
end;
$$;

-- Same as 202610130012_circle_roles, plus an audit entry.
create or replace function public.delete_circle_role(target_role_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_role public.circle_roles%rowtype;
  role_member_count integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select r.* into target_role
  from public.circle_roles r
  where r.id = target_role_id;

  if target_role.id is null
    or not public.current_user_has_circle_permission(
      target_role.circle_id,
      'manage_roles'
    )
  then
    raise exception 'Role not found or caller cannot manage roles'
      using errcode = '42501';
  end if;

  if target_role.is_default then
    raise exception 'The default role cannot be deleted' using errcode = '22023';
  end if;

  perform 1 from public.circles where id = target_role.circle_id for no key update;

  select r.* into target_role
  from public.circle_roles r
  where r.id = target_role_id;

  if target_role.position
    >= public.circle_member_rank(target_role.circle_id, current_user_id)
  then
    raise exception 'Cannot delete a role at or above your highest role'
      using errcode = '42501';
  end if;

  select count(*)::integer into role_member_count
  from public.circle_member_roles mr
  where mr.role_id = target_role_id;

  delete from public.circle_roles where id = target_role_id;

  perform public.sync_circle_admin_roles(target_role.circle_id);

  perform public.write_circle_audit(
    target_role.circle_id,
    'role_delete',
    'role',
    target_role_id,
    target_role.name,
    jsonb_build_object(
      'name', target_role.name,
      'color', target_role.color,
      'permissions', target_role.permissions,
      'hoist', target_role.hoist,
      'member_count', role_member_count
    )
  );
end;
$$;

-- Same as 202610130012_circle_roles, plus one audit entry listing the moved roles.
create or replace function public.reorder_circle_roles(
  target_circle_id uuid,
  role_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  caller_rank integer;
  moved_roles jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(target_circle_id, 'manage_roles') then
    raise exception 'Only members who can manage roles can reorder roles'
      using errcode = '42501';
  end if;

  perform 1 from public.circles where id = target_circle_id for no key update;

  if role_ids is null
    or exists (select 1 from unnest(role_ids) as ids(role_id) where ids.role_id is null)
    or cardinality(role_ids) <> (
      select count(distinct role_id) from unnest(role_ids) as ids(role_id)
    )
    or cardinality(role_ids) <> (
      select count(*)
      from public.circle_roles r
      where r.circle_id = target_circle_id
        and not r.is_default
    )
    or exists (
      select 1
      from unnest(role_ids) as ids(role_id)
      where not exists (
        select 1
        from public.circle_roles r
        where r.id = ids.role_id
          and r.circle_id = target_circle_id
          and not r.is_default
      )
    )
  then
    raise exception 'Order must list every role of the circle once'
      using errcode = '22023';
  end if;

  caller_rank := public.circle_member_rank(target_circle_id, current_user_id);

  if exists (
    select 1
    from (
      select ordered.role_id, positions.position as next_position
      from unnest(role_ids) with ordinality as ordered(role_id, ordinality)
      join (
        select
          r.position,
          row_number() over (order by r.position desc) as ordinality
        from public.circle_roles r
        where r.circle_id = target_circle_id
          and not r.is_default
      ) positions on positions.ordinality = ordered.ordinality
    ) next_order
    join public.circle_roles r on r.id = next_order.role_id
    where (r.position >= caller_rank or next_order.next_position >= caller_rank)
      and r.position <> next_order.next_position
  ) then
    raise exception 'Cannot move roles at or above your highest role'
      using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'name', r.name,
        'position', jsonb_build_object('old', r.position, 'new', next_order.next_position)
      )
      order by next_order.next_position desc
    ),
    '[]'::jsonb
  )
  into moved_roles
  from (
    select ordered.role_id, positions.position as next_position
    from unnest(role_ids) with ordinality as ordered(role_id, ordinality)
    join (
      select
        r.position,
        row_number() over (order by r.position desc) as ordinality
      from public.circle_roles r
      where r.circle_id = target_circle_id
        and not r.is_default
    ) positions on positions.ordinality = ordered.ordinality
  ) next_order
  join public.circle_roles r on r.id = next_order.role_id
  where r.position <> next_order.next_position;

  -- One statement: the deferrable unique constraint is checked at its end.
  update public.circle_roles r
  set position = next_order.next_position
  from (
    select ordered.role_id, positions.position as next_position
    from unnest(role_ids) with ordinality as ordered(role_id, ordinality)
    join (
      select
        r.position,
        row_number() over (order by r.position desc) as ordinality
      from public.circle_roles r
      where r.circle_id = target_circle_id
        and not r.is_default
    ) positions on positions.ordinality = ordered.ordinality
  ) next_order
  where r.id = next_order.role_id
    and r.position <> next_order.next_position;

  if moved_roles <> '[]'::jsonb then
    perform public.write_circle_audit(
      target_circle_id,
      'role_reorder',
      'circle',
      target_circle_id,
      (select c.name from public.circles c where c.id = target_circle_id),
      jsonb_build_object('roles', moved_roles)
    );
  end if;
end;
$$;

-- Same as 202610130012_circle_roles, plus an audit entry with the added and removed roles.
create or replace function public.set_member_roles(
  target_circle_id uuid,
  target_user_id uuid,
  role_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  next_role_ids uuid[] := coalesce(role_ids, array[]::uuid[]);
  caller_rank integer;
  added_roles jsonb;
  removed_roles jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(target_circle_id, 'manage_roles') then
    raise exception 'Only members who can manage roles can assign roles'
      using errcode = '42501';
  end if;

  perform 1 from public.circles where id = target_circle_id for no key update;

  if not exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = target_circle_id
      and cm.user_id = target_user_id
  ) then
    raise exception 'Circle member not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from public.circles c
    where c.id = target_circle_id
      and c.owner_id = target_user_id
      and c.owner_id <> current_user_id
  ) then
    raise exception 'Only the owner can change the owner''s roles'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from unnest(next_role_ids) as ids(role_id)
    where ids.role_id is null
      or not exists (
        select 1
        from public.circle_roles r
        where r.id = ids.role_id
          and r.circle_id = target_circle_id
          and not r.is_default
      )
  ) then
    raise exception 'Roles must be assignable roles of the circle'
      using errcode = '22023';
  end if;

  caller_rank := public.circle_member_rank(target_circle_id, current_user_id);

  if exists (
    select 1
    from public.circle_roles r
    where r.circle_id = target_circle_id
      and r.position >= caller_rank
      and (
        (r.id = any(next_role_ids)) <> exists (
          select 1
          from public.circle_member_roles mr
          where mr.circle_id = target_circle_id
            and mr.user_id = target_user_id
            and mr.role_id = r.id
        )
      )
  ) then
    raise exception 'Cannot assign or remove roles at or above your highest role'
      using errcode = '42501';
  end if;

  select
    coalesce(
      jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name) order by r.position desc)
        filter (where r.id = any(next_role_ids) and mr.role_id is null),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name) order by r.position desc)
        filter (where not (r.id = any(next_role_ids)) and mr.role_id is not null),
      '[]'::jsonb
    )
  into added_roles, removed_roles
  from public.circle_roles r
  left join public.circle_member_roles mr
    on mr.role_id = r.id
    and mr.circle_id = target_circle_id
    and mr.user_id = target_user_id
  where r.circle_id = target_circle_id
    and not r.is_default;

  delete from public.circle_member_roles mr
  where mr.circle_id = target_circle_id
    and mr.user_id = target_user_id
    and not (mr.role_id = any(next_role_ids));

  insert into public.circle_member_roles (circle_id, user_id, role_id)
  select distinct target_circle_id, target_user_id, ids.role_id
  from unnest(next_role_ids) as ids(role_id)
  on conflict do nothing;

  perform public.sync_circle_admin_roles(target_circle_id);

  if added_roles <> '[]'::jsonb or removed_roles <> '[]'::jsonb then
    perform public.write_circle_audit(
      target_circle_id,
      'member_roles_update',
      'member',
      target_user_id,
      public.circle_member_label(target_circle_id, target_user_id),
      jsonb_build_object('added', added_roles, 'removed', removed_roles)
    );
  end if;
end;
$$;

-- Same as 202610130012_circle_roles, plus an audit entry when someone else's nickname changes.
create or replace function public.set_circle_nickname(
  target_circle_id uuid,
  target_user_id uuid,
  nickname text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_nickname text := nullif(btrim(coalesce(nickname, '')), '');
  target_exists boolean;
  old_nickname text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if normalized_nickname is not null
    and char_length(normalized_nickname) > 32
  then
    raise exception 'Nickname must be 1 to 32 characters'
      using errcode = '22023';
  end if;

  if not public.is_current_user_circle_member(target_circle_id) then
    raise exception 'Only circle members can set nicknames'
      using errcode = '42501';
  end if;

  select true, cm.nickname
  into target_exists, old_nickname
  from public.circle_members cm
  where cm.circle_id = target_circle_id
    and cm.user_id = target_user_id
  for update;

  if target_exists is null then
    raise exception 'Circle member not found' using errcode = 'P0002';
  end if;

  if target_user_id <> current_user_id then
    if not public.current_user_has_circle_permission(
      target_circle_id,
      'manage_nicknames'
    ) then
      raise exception 'Only members who can manage nicknames can change other nicknames'
        using errcode = '42501';
    end if;

    if public.circle_member_rank(target_circle_id, target_user_id)
      >= public.circle_member_rank(target_circle_id, current_user_id)
    then
      raise exception 'Cannot change the nickname of a member ranked at or above you'
        using errcode = '42501';
    end if;
  end if;

  update public.circle_members cm
  set nickname = normalized_nickname
  where cm.circle_id = target_circle_id
    and cm.user_id = target_user_id;

  -- Members renaming themselves are not logged.
  if target_user_id <> current_user_id
    and old_nickname is distinct from normalized_nickname
  then
    perform public.write_circle_audit(
      target_circle_id,
      'member_nickname_update',
      'member',
      target_user_id,
      (
        select coalesce(nullif(btrim(p.display_name), ''), p.username)
        from public.profiles p
        where p.id = target_user_id
      ),
      jsonb_build_object(
        'nickname',
        jsonb_build_object('old', old_nickname, 'new', normalized_nickname)
      )
    );
  end if;

  return normalized_nickname;
end;
$$;

-- Same as 202610130013_kick_circle_member, plus an audit entry.
create or replace function public.kick_circle_member(
  target_circle_id uuid,
  target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  kicked_label text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'kick_members'
  ) then
    raise exception 'Only members who can kick members can kick members'
      using errcode = '42501';
  end if;

  -- Serialises with role changes, so the rank check below holds.
  perform 1 from public.circles where id = target_circle_id for no key update;

  if target_user_id = current_user_id then
    raise exception 'Leave the circle instead of kicking yourself'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = target_circle_id
      and cm.user_id = target_user_id
  ) then
    raise exception 'Circle member not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from public.circles c
    where c.id = target_circle_id
      and c.owner_id = target_user_id
  ) then
    raise exception 'The circle owner cannot be kicked' using errcode = '42501';
  end if;

  if public.circle_member_rank(target_circle_id, target_user_id)
    >= public.circle_member_rank(target_circle_id, current_user_id)
  then
    raise exception 'Cannot kick a member ranked at or above you'
      using errcode = '42501';
  end if;

  kicked_label := public.circle_member_label(target_circle_id, target_user_id);

  -- Threads first: the leave trigger on conversation_members would remove
  -- these too, but the kick should not depend on it.
  delete from public.conversation_members cm
  using public.conversation_threads ct
  join public.circle_channels cc on cc.conversation_id = ct.parent_conversation_id
  where cc.circle_id = target_circle_id
    and cm.conversation_id = ct.conversation_id
    and cm.user_id = target_user_id;

  delete from public.conversation_members cm
  using public.circle_channels cc
  where cc.circle_id = target_circle_id
    and cm.conversation_id = cc.conversation_id
    and cm.user_id = target_user_id;

  delete from public.circle_members cm
  where cm.circle_id = target_circle_id
    and cm.user_id = target_user_id;

  perform public.write_circle_audit(
    target_circle_id,
    'member_kick',
    'member',
    target_user_id,
    kicked_label,
    '{}'::jsonb
  );
end;
$$;

-- Same as 202610130017_leave_circle, plus an audit entry by the member who left.
create or replace function public.leave_circle(target_circle_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  leaving_label text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  -- Serialises with ownership transfers, so the owner check below holds.
  perform 1 from public.circles where id = target_circle_id for no key update;

  if not public.is_current_user_circle_member(target_circle_id) then
    raise exception 'Circle not found or caller is not a member'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.circles c
    where c.id = target_circle_id
      and c.owner_id = current_user_id
  ) then
    raise exception 'Transfer ownership before leaving the circle'
      using errcode = '42501';
  end if;

  leaving_label := public.circle_member_label(target_circle_id, current_user_id);

  delete from public.conversation_members cm
  using public.conversation_threads ct
  join public.circle_channels cc on cc.conversation_id = ct.parent_conversation_id
  where cc.circle_id = target_circle_id
    and cm.conversation_id = ct.conversation_id
    and cm.user_id = current_user_id;

  delete from public.conversation_members cm
  using public.circle_channels cc
  where cc.circle_id = target_circle_id
    and cm.conversation_id = cc.conversation_id
    and cm.user_id = current_user_id;

  delete from public.circle_members cm
  where cm.circle_id = target_circle_id
    and cm.user_id = current_user_id;

  perform public.write_circle_audit(
    target_circle_id,
    'member_leave',
    'member',
    current_user_id,
    leaving_label,
    '{}'::jsonb
  );
end;
$$;

-- Same as 202610130017_leave_circle, plus an audit entry.
create or replace function public.transfer_circle_ownership(
  target_circle_id uuid,
  new_owner_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  current_owner_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select c.owner_id into current_owner_id
  from public.circles c
  where c.id = target_circle_id
  for update;

  if current_owner_id is null or current_owner_id <> current_user_id then
    raise exception 'Only the circle owner can transfer ownership'
      using errcode = '42501';
  end if;

  if new_owner_id is null or new_owner_id = current_user_id then
    raise exception 'Choose another member to own the circle'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = target_circle_id
      and cm.user_id = new_owner_id
  ) then
    raise exception 'Circle member not found' using errcode = 'P0002';
  end if;

  update public.circles c
  set owner_id = new_owner_id
  where c.id = target_circle_id;

  update public.circle_members cm
  set role = case when cm.user_id = new_owner_id then 'owner' else 'member' end
  where cm.circle_id = target_circle_id
    and cm.user_id in (current_user_id, new_owner_id);

  delete from public.circle_member_roles mr
  where mr.circle_id = target_circle_id
    and mr.user_id = current_user_id;

  update public.conversation_members cm
  set role = case when cm.user_id = new_owner_id then 'owner' else 'member' end
  from public.circle_channels cc
  where cc.circle_id = target_circle_id
    and cm.conversation_id = cc.conversation_id
    and cm.user_id in (current_user_id, new_owner_id)
    and cm.role is distinct from
      case when cm.user_id = new_owner_id then 'owner' else 'member' end;

  perform public.write_circle_audit(
    target_circle_id,
    'circle_ownership_transfer',
    'member',
    new_owner_id,
    public.circle_member_label(target_circle_id, new_owner_id),
    jsonb_build_object(
      'owner_id', jsonb_build_object('old', current_user_id, 'new', new_owner_id),
      'previous_owner_name', public.circle_member_label(target_circle_id, current_user_id)
    )
  );
end;
$$;

-- Same as 202610130012_circle_roles, plus an audit entry.
create or replace function public.create_circle_invite(
  target_circle_id uuid,
  expires_in_hours integer default null,
  max_uses integer default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  created_code text;
  attempt integer := 0;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'create_invites'
  ) then
    raise exception 'Only members who can create invites can create invites'
      using errcode = '42501';
  end if;

  if expires_in_hours is not null
    and (expires_in_hours < 1 or expires_in_hours > 8760)
  then
    raise exception 'Invite expiry must be between 1 hour and 1 year'
      using errcode = '22023';
  end if;

  if create_circle_invite.max_uses is not null
    and (create_circle_invite.max_uses < 1 or create_circle_invite.max_uses > 1000)
  then
    raise exception 'Invite max uses must be between 1 and 1000'
      using errcode = '22023';
  end if;

  loop
    attempt := attempt + 1;
    begin
      insert into public.circle_invites (
        code,
        circle_id,
        created_by,
        expires_at,
        max_uses
      )
      values (
        public.generate_circle_invite_code(),
        target_circle_id,
        current_user_id,
        case
          when expires_in_hours is null then null
          else now() + make_interval(hours => expires_in_hours)
        end,
        create_circle_invite.max_uses
      )
      returning code into created_code;
      exit;
    exception
      when unique_violation then
        if attempt >= 5 then
          raise;
        end if;
    end;
  end loop;

  perform public.write_circle_audit(
    target_circle_id,
    'invite_create',
    'invite',
    null,
    created_code,
    (
      select jsonb_build_object(
        'code', ci.code,
        'expires_at', ci.expires_at,
        'max_uses', ci.max_uses
      )
      from public.circle_invites ci
      where ci.code = created_code
    )
  );

  return created_code;
end;
$$;

-- Same as 202610130012_circle_roles, plus an audit entry when the invite was still active.
create or replace function public.revoke_circle_invite(invite_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_invite public.circle_invites%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select *
  into target_invite
  from public.circle_invites
  where code = lower(trim(coalesce(invite_code, '')))
  for update;

  if target_invite.code is null
    or not (
      public.current_user_has_circle_permission(
        target_invite.circle_id,
        'manage_channels'
      )
      or (
        target_invite.created_by = current_user_id
        and public.current_user_has_circle_permission(
          target_invite.circle_id,
          'create_invites'
        )
      )
    )
  then
    raise exception 'Invite not found or caller cannot revoke invites'
      using errcode = '42501';
  end if;

  update public.circle_invites
  set revoked_at = now()
  where code = target_invite.code
    and revoked_at is null;

  if found then
    perform public.write_circle_audit(
      target_invite.circle_id,
      'invite_revoke',
      'invite',
      null,
      target_invite.code,
      jsonb_build_object('code', target_invite.code, 'created_by', target_invite.created_by)
    );
  end if;
end;
$$;

-- Same as 202610130012_circle_roles, plus one audit entry naming the added members.
create or replace function public.invite_circle_members(
  target_circle_id uuid,
  member_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  added_members jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'create_invites'
  ) then
    raise exception 'Only members who can create invites can invite members'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from unnest(coalesce(member_ids, array[]::uuid[])) as candidate(member_id)
    where candidate.member_id is null
      or candidate.member_id = current_user_id
      or not exists (
        select 1
        from public.profiles p
        where p.id = candidate.member_id
      )
      or not exists (
        select 1
        from public.friendships f
        where f.user_low_id = least(current_user_id, candidate.member_id)
          and f.user_high_id = greatest(current_user_id, candidate.member_id)
      )
      or public.are_users_blocked(current_user_id, candidate.member_id)
  ) then
    raise exception 'Invalid circle invite members' using errcode = '42501';
  end if;

  if exists (
    select 1
    from unnest(coalesce(member_ids, array[]::uuid[])) as candidate(member_id)
    join public.circle_members cm
      on cm.circle_id = target_circle_id
      and cm.user_id = candidate.member_id
  ) then
    raise exception 'User is already a circle member' using errcode = '23505';
  end if;

  with invited as (
    select distinct member_id
    from unnest(coalesce(member_ids, array[]::uuid[])) as candidate(member_id)
    where member_id is not null
      and member_id <> current_user_id
  ),
  allowed as (
    select invited.member_id
    from invited
    where exists (
      select 1
      from public.friendships f
      where f.user_low_id = least(current_user_id, invited.member_id)
        and f.user_high_id = greatest(current_user_id, invited.member_id)
    )
      and not public.are_users_blocked(current_user_id, invited.member_id)
  ),
  inserted as (
    insert into public.circle_members (circle_id, user_id, role)
    select target_circle_id, allowed.member_id, 'member'
    from allowed
    on conflict do nothing
    returning user_id
  ),
  joined_channels as (
    insert into public.conversation_members (conversation_id, user_id, role)
    select cc.conversation_id, inserted.user_id, 'member'
    from inserted
    cross join public.circle_channels cc
    where cc.circle_id = target_circle_id
    on conflict do nothing
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'name', coalesce(nullif(btrim(p.display_name), ''), p.username)
      )
      order by p.display_name
    ),
    '[]'::jsonb
  )
  into added_members
  from inserted
  join public.profiles p on p.id = inserted.user_id;

  if added_members <> '[]'::jsonb then
    perform public.write_circle_audit(
      target_circle_id,
      'member_add',
      'member',
      case
        when jsonb_array_length(added_members) = 1
          then (added_members -> 0 ->> 'id')::uuid
      end,
      (
        select string_agg(member.value ->> 'name', ', ' order by member.ordinality)
        from jsonb_array_elements(added_members) with ordinality as member(value, ordinality)
      ),
      jsonb_build_object('members', added_members)
    );
  end if;
end;
$$;

-- Same as 202610130002_pinned_messages, plus an audit entry for circle channels and their threads.
create or replace function public.pin_message(target_message_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_conversation_id uuid;
  target_message_type text;
  active_pin_count integer;
  actor_name text;
  pinned_channel public.circle_channels%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select m.conversation_id, m.type
  into target_conversation_id, target_message_type
  from public.messages m
  where m.id = target_message_id
    and m.recalled_at is null;

  if target_conversation_id is null
    or not public.is_current_user_conversation_member(target_conversation_id)
    or not public.can_current_user_pin_messages(target_conversation_id)
  then
    raise exception 'Message not found or caller cannot pin messages'
      using errcode = '42501';
  end if;

  if target_message_type = 'system' then
    raise exception 'System messages cannot be pinned' using errcode = '22023';
  end if;

  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Message cannot be pinned' using errcode = '42501';
  end if;

  -- Serialize pins per conversation so the limit holds under concurrency.
  perform 1
  from public.conversations c
  where c.id = target_conversation_id
  for update;

  if exists (
    select 1
    from public.pinned_messages pm
    where pm.message_id = target_message_id
  ) then
    return false;
  end if;

  select count(*)::integer
  into active_pin_count
  from public.pinned_messages pm
  join public.messages m on m.id = pm.message_id
  where pm.conversation_id = target_conversation_id
    and m.recalled_at is null;

  if active_pin_count >= 50 then
    raise exception 'A conversation can have at most 50 pinned messages'
      using errcode = '54000';
  end if;

  insert into public.pinned_messages (
    conversation_id,
    message_id,
    pinned_by
  )
  values (
    target_conversation_id,
    target_message_id,
    current_user_id
  );

  select nullif(btrim(p.display_name), '')
  into actor_name
  from public.profiles p
  where p.id = current_user_id;

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    attachment
  )
  values (
    target_conversation_id,
    current_user_id,
    'system',
    coalesce(actor_name, 'Someone') || ' pinned a message.',
    jsonb_build_object('kind', 'pin', 'message_id', target_message_id)
  );

  select cc.* into pinned_channel
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(target_conversation_id);

  if pinned_channel.id is not null then
    perform public.write_circle_audit(
      pinned_channel.circle_id,
      'message_pin',
      'message',
      target_message_id,
      pinned_channel.name,
      jsonb_build_object(
        'channel_id', pinned_channel.id,
        'channel_name', pinned_channel.name,
        'conversation_id', target_conversation_id,
        'author_id', (
          select m.sender_id from public.messages m where m.id = target_message_id
        )
      )
    );
  end if;

  return true;
end;
$$;

-- Same as 202610130002_pinned_messages, plus an audit entry for circle channels and their threads.
create or replace function public.unpin_message(target_message_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_conversation_id uuid;
  unpinned boolean;
  pinned_channel public.circle_channels%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select m.conversation_id
  into target_conversation_id
  from public.messages m
  where m.id = target_message_id;

  if target_conversation_id is null
    or not public.is_current_user_conversation_member(target_conversation_id)
    or not public.can_current_user_pin_messages(target_conversation_id)
  then
    raise exception 'Message not found or caller cannot unpin messages'
      using errcode = '42501';
  end if;

  delete from public.pinned_messages pm
  where pm.message_id = target_message_id
    and pm.conversation_id = target_conversation_id;
  unpinned := found;

  if unpinned then
    select cc.* into pinned_channel
    from public.circle_channels cc
    where cc.id = public.conversation_circle_channel_id(target_conversation_id);

    if pinned_channel.id is not null then
      perform public.write_circle_audit(
        pinned_channel.circle_id,
        'message_unpin',
        'message',
        target_message_id,
        pinned_channel.name,
        jsonb_build_object(
          'channel_id', pinned_channel.id,
          'channel_name', pinned_channel.name,
          'conversation_id', target_conversation_id,
          'author_id', (
            select m.sender_id from public.messages m where m.id = target_message_id
          )
        )
      );
    end if;
  end if;

  return unpinned;
end;
$$;

-- Same as 202610130011_message_threads, plus an audit entry when a manager archives or restores a channel thread.
create or replace function public.set_thread_archived(
  target_thread_id uuid,
  archived boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_thread public.conversation_threads%rowtype;
  previous_thread public.conversation_threads%rowtype;
  thread_channel public.circle_channels%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.can_current_user_manage_thread(target_thread_id) then
    raise exception 'Only the thread creator or a manager can archive it'
      using errcode = '42501';
  end if;

  select ct.* into previous_thread
  from public.conversation_threads ct
  where ct.id = target_thread_id;

  update public.conversation_threads ct
  set archived_at = case
    when set_thread_archived.archived then coalesce(ct.archived_at, now())
    else null
  end
  where ct.id = target_thread_id
  returning * into updated_thread;

  -- Logged when a manager (not the thread's creator) archives or restores
  -- a thread of a circle channel.
  if previous_thread.created_by is distinct from auth.uid()
    and (previous_thread.archived_at is null) <> (updated_thread.archived_at is null)
  then
    select cc.* into thread_channel
    from public.circle_channels cc
    where cc.conversation_id = updated_thread.parent_conversation_id;

    if thread_channel.id is not null then
      perform public.write_circle_audit(
        thread_channel.circle_id,
        case
          when updated_thread.archived_at is null then 'thread_unarchive'
          else 'thread_archive'
        end,
        'thread',
        updated_thread.id,
        updated_thread.title,
        jsonb_build_object(
          'channel_id', thread_channel.id,
          'channel_name', thread_channel.name,
          'created_by', updated_thread.created_by
        )
      );
    end if;
  end if;

  return public.thread_payload(updated_thread);
end;
$$;

-- Same as 202610130012_circle_roles, plus an audit entry when deleting someone else's post.
create or replace function public.delete_circle_post(target_post_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_post public.circle_posts%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into target_post
  from public.circle_posts
  where id = target_post_id
    and deleted_at is null;

  if target_post.id is null then
    raise exception 'Post not found' using errcode = '42501';
  end if;

  if target_post.author_id <> current_user_id
    and not public.current_user_has_circle_permission(
      target_post.circle_id,
      'manage_messages'
    )
  then
    raise exception 'Caller cannot delete this post' using errcode = '42501';
  end if;

  update public.circle_posts
  set deleted_at = now()
  where id = target_post_id;

  if target_post.author_id <> current_user_id then
    perform public.write_circle_audit(
      target_post.circle_id,
      'post_delete',
      'post',
      target_post.id,
      public.circle_member_label(target_post.circle_id, target_post.author_id),
      jsonb_build_object(
        'author_id', target_post.author_id,
        'excerpt', left(target_post.body, 100)
      )
    );
  end if;
end;
$$;
-- A page of the circle's audit log, newest first: entries before [before]
-- (all when null), at most [limit_count] (1 to 100), optionally only one
-- action or one group of actions ('role' matches role_create, ...). Each
-- entry names its actor with their circle nickname, if any.
create or replace function public.list_circle_audit_log(
  target_circle_id uuid,
  before timestamptz default null,
  limit_count integer default 50,
  action_filter text default null
)
returns table (
  id uuid,
  circle_id uuid,
  action text,
  target_type text,
  target_id uuid,
  target_label text,
  changes jsonb,
  created_at timestamptz,
  actor jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'view_audit_log'
  ) then
    raise exception 'Only members who can view the audit log can read it'
      using errcode = '42501';
  end if;

  return query
  select
    a.id,
    a.circle_id,
    a.action,
    a.target_type,
    a.target_id,
    a.target_label,
    a.changes,
    a.created_at,
    case
      when p.id is null then null
      else jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'display_name', p.display_name,
        'avatar_url', p.avatar_url,
        'nickname', cm.nickname
      )
    end
  from public.circle_audit_log a
  left join public.profiles p on p.id = a.actor_id
  left join public.circle_members cm
    on cm.circle_id = a.circle_id
    and cm.user_id = a.actor_id
  where a.circle_id = target_circle_id
    and (
      list_circle_audit_log.before is null
      or a.created_at < list_circle_audit_log.before
    )
    and (
      list_circle_audit_log.action_filter is null
      or a.action = list_circle_audit_log.action_filter
      or split_part(a.action, '_', 1) = list_circle_audit_log.action_filter
    )
  order by a.created_at desc, a.id desc
  limit greatest(1, least(coalesce(list_circle_audit_log.limit_count, 50), 100));
end;
$$;

revoke execute on function public.list_circle_audit_log(uuid, timestamptz, integer, text) from public;
revoke execute on function public.list_circle_audit_log(uuid, timestamptz, integer, text) from anon;

grant select on public.circle_audit_log to authenticated;
grant execute on function public.list_circle_audit_log(uuid, timestamptz, integer, text) to authenticated;
grant execute on function public.create_circle_channel(uuid, text, uuid) to authenticated;
grant execute on function public.create_channel_category(uuid, text) to authenticated;
grant execute on function public.rename_channel_category(uuid, text) to authenticated;
grant execute on function public.delete_channel_category(uuid) to authenticated;
grant execute on function public.reorder_circle_channels(uuid, jsonb) to authenticated;
grant execute on function public.set_channel_overwrite(uuid, uuid, uuid, bigint, bigint) to authenticated;
grant execute on function public.set_channel_privacy(uuid, boolean, boolean) to authenticated;
grant execute on function public.set_channel_slowmode(uuid, integer) to authenticated;
grant execute on function public.create_circle_role(uuid, text, integer, bigint, boolean) to authenticated;
grant execute on function public.update_circle_role(uuid, text, integer, bigint, boolean) to authenticated;
grant execute on function public.delete_circle_role(uuid) to authenticated;
grant execute on function public.reorder_circle_roles(uuid, uuid[]) to authenticated;
grant execute on function public.set_member_roles(uuid, uuid, uuid[]) to authenticated;
grant execute on function public.set_circle_nickname(uuid, uuid, text) to authenticated;
grant execute on function public.kick_circle_member(uuid, uuid) to authenticated;
grant execute on function public.leave_circle(uuid) to authenticated;
grant execute on function public.transfer_circle_ownership(uuid, uuid) to authenticated;
grant execute on function public.create_circle_invite(uuid, integer, integer) to authenticated;
grant execute on function public.revoke_circle_invite(text) to authenticated;
grant execute on function public.invite_circle_members(uuid, uuid[]) to authenticated;
grant execute on function public.pin_message(uuid) to authenticated;
grant execute on function public.unpin_message(uuid) to authenticated;
grant execute on function public.set_thread_archived(uuid, boolean) to authenticated;
grant execute on function public.delete_circle_post(uuid) to authenticated;
