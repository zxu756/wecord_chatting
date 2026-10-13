-- Custom circle roles with permission bits, replacing the owner / admin
-- checks of earlier migrations.
--
-- * Every circle has exactly one default role, '@everyone' (is_default,
--   position 0), that every member holds implicitly. It cannot be renamed,
--   deleted, coloured or hoisted; only its permissions change.
-- * Other roles have unique positions >= 1; a higher position ranks higher.
--   A member's rank is the highest position among their assigned roles (0
--   with none); the circle owner (circles.owner_id) outranks everyone.
-- * A member's permissions are the OR of the default role and their
--   assigned roles. The owner and holders of `administrator` have every
--   permission. Non-members have none.
-- * Like Discord, members with manage_roles may only create, edit, delete,
--   reorder and assign roles strictly below their own rank, may not grant
--   (or take away) permissions they lack themselves, and nobody but the
--   owner may change the owner's roles.
--
-- circle_members.role keeps 'owner' / 'admin' / 'member' for display and
-- for older clients, but no longer authorizes anything. 'owner' stays tied
-- to circles.owner_id. 'admin' is kept in sync by the role RPCs: a
-- non-owner member is 'admin' while they are assigned a role carrying a
-- moderation permission (administrator, manage_roles, manage_channels,
-- manage_messages, kick_members or manage_nicknames), otherwise 'member'.
--
-- Existing circles get '@everyone' with view_channel, send_messages,
-- create_invites and connect_voice, plus a hoisted 'Admin' role (every
-- moderation permission except manage_roles and administrator) assigned to
-- their current admins.
--
-- Invites: creating one needs create_invites. Listing and revoking your own
-- invites needs create_invites too; seeing and revoking everyone's needs
-- manage_channels (there is no separate "manage circle" permission).

-- Permission names map to bits once, here. Mirrored in
-- lib/shared/models/circle_role.dart.
create or replace function public.circle_permission_bit(permission_name text)
returns bigint
language plpgsql
immutable
set search_path = public
as $$
begin
  return case permission_name
    when 'view_channel' then 1::bigint
    when 'send_messages' then 2::bigint
    when 'manage_messages' then 4::bigint
    when 'manage_channels' then 8::bigint
    when 'manage_roles' then 16::bigint
    when 'kick_members' then 32::bigint
    when 'create_invites' then 64::bigint
    when 'manage_nicknames' then 128::bigint
    when 'mention_everyone' then 256::bigint
    when 'manage_events' then 512::bigint
    when 'manage_emojis' then 1024::bigint
    when 'manage_webhooks' then 2048::bigint
    when 'view_audit_log' then 4096::bigint
    when 'connect_voice' then 8192::bigint
    when 'administrator' then 16384::bigint
    else null
  end;
end;
$$;

-- Unknown names fail loudly instead of silently denying.
create or replace function public.circle_permission_bits(permission_names text[])
returns bigint
language plpgsql
immutable
set search_path = public
as $$
declare
  result bigint := 0;
  permission_name text;
  bit bigint;
begin
  foreach permission_name in array coalesce(permission_names, array[]::text[]) loop
    bit := public.circle_permission_bit(permission_name);
    if bit is null then
      raise exception 'Unknown circle permission %', permission_name
        using errcode = '22023';
    end if;
    result := result | bit;
  end loop;
  return result;
end;
$$;

create or replace function public.circle_all_permissions()
returns bigint
language sql
immutable
set search_path = public
as $$
  select 32767::bigint;
$$;

create or replace function public.circle_default_role_permissions()
returns bigint
language sql
immutable
set search_path = public
as $$
  select public.circle_permission_bits(array[
    'view_channel',
    'send_messages',
    'create_invites',
    'connect_voice'
  ]);
$$;

create table if not exists public.circle_roles (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  name text not null,
  color integer,
  position integer not null default 0,
  permissions bigint not null default 0,
  hoist boolean not null default false,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  constraint circle_roles_name_length check (
    name = btrim(name) and char_length(name) between 1 and 32
  ),
  constraint circle_roles_color_range check (
    color is null or color between 0 and 16777215
  ),
  constraint circle_roles_permissions_range check (
    permissions >= 0 and permissions <= 32767
  ),
  constraint circle_roles_position_check check (
    (is_default and position = 0) or (not is_default and position >= 1)
  ),
  constraint circle_roles_default_plain check (
    not is_default or (color is null and not hoist)
  ),
  constraint circle_roles_id_circle_unique unique (id, circle_id),
  -- Deferrable so a reorder can swap positions in one statement.
  constraint circle_roles_circle_position_unique unique (circle_id, position)
    deferrable initially immediate
);

create unique index if not exists circle_roles_one_default_idx
  on public.circle_roles (circle_id)
  where is_default;

create table if not exists public.circle_member_roles (
  circle_id uuid not null,
  user_id uuid not null,
  role_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (circle_id, user_id, role_id),
  constraint circle_member_roles_member_fkey
    foreign key (circle_id, user_id)
    references public.circle_members(circle_id, user_id)
    on delete cascade,
  constraint circle_member_roles_role_fkey
    foreign key (role_id, circle_id)
    references public.circle_roles(id, circle_id)
    on delete cascade
);

create index if not exists circle_member_roles_role_idx
  on public.circle_member_roles (role_id);

-- Realtime matches DELETE events against the old row, so keep circle_id in
-- it to let an open circle filter role removals.
alter table public.circle_roles replica identity full;
alter table public.circle_member_roles replica identity full;

alter table public.circle_roles enable row level security;
alter table public.circle_member_roles enable row level security;

drop policy if exists circle_roles_select_member on public.circle_roles;
create policy circle_roles_select_member
  on public.circle_roles for select
  to authenticated
  using (public.is_current_user_circle_member(circle_id));

drop policy if exists circle_member_roles_select_member on public.circle_member_roles;
create policy circle_member_roles_select_member
  on public.circle_member_roles for select
  to authenticated
  using (public.is_current_user_circle_member(circle_id));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'circle_roles'
  ) then
    alter publication supabase_realtime add table public.circle_roles;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'circle_member_roles'
  ) then
    alter publication supabase_realtime add table public.circle_member_roles;
  end if;
end $$;

-- Backfill: a default role for every circle, and an 'Admin' role for the
-- current admins of circles that have any.
insert into public.circle_roles (circle_id, name, position, permissions, is_default)
select c.id, '@everyone', 0, public.circle_default_role_permissions(), true
from public.circles c
where not exists (
  select 1
  from public.circle_roles r
  where r.circle_id = c.id
    and r.is_default
);

insert into public.circle_roles (circle_id, name, color, position, permissions, hoist)
select
  c.id,
  'Admin',
  15105570, -- #E67E22
  1,
  public.circle_permission_bits(array[
    'manage_messages',
    'manage_channels',
    'kick_members',
    'create_invites',
    'manage_nicknames',
    'mention_everyone',
    'manage_events',
    'manage_emojis',
    'manage_webhooks',
    'view_audit_log',
    'view_channel',
    'send_messages',
    'connect_voice'
  ]),
  true
from public.circles c
where exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = c.id
      and cm.role = 'admin'
  )
  and not exists (
    select 1
    from public.circle_roles r
    where r.circle_id = c.id
      and not r.is_default
  );

insert into public.circle_member_roles (circle_id, user_id, role_id)
select cm.circle_id, cm.user_id, r.id
from public.circle_members cm
join public.circle_roles r
  on r.circle_id = cm.circle_id
  and r.name = 'Admin'
  and r.position = 1
  and not r.is_default
where cm.role = 'admin'
on conflict do nothing;

-- Effective permissions of a user in a circle; 0 for non-members.
create or replace function public.circle_member_permissions(
  target_circle_id uuid,
  target_user_id uuid
)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select case
        when c.owner_id = cm.user_id then public.circle_all_permissions()
        when granted.permissions
          & public.circle_permission_bit('administrator') <> 0
          then public.circle_all_permissions()
        else granted.permissions
      end
      from public.circle_members cm
      join public.circles c on c.id = cm.circle_id
      cross join lateral (
        select coalesce(bit_or(r.permissions), 0)::bigint as permissions
        from public.circle_roles r
        where r.circle_id = cm.circle_id
          and (
            r.is_default
            or exists (
              select 1
              from public.circle_member_roles mr
              where mr.circle_id = cm.circle_id
                and mr.user_id = cm.user_id
                and mr.role_id = r.id
            )
          )
      ) granted
      where cm.circle_id = target_circle_id
        and cm.user_id = target_user_id
    ),
    0
  );
$$;

-- Never null: false for non-members, raises for unknown permission names.
create or replace function public.circle_member_has_permission(
  target_circle_id uuid,
  target_user_id uuid,
  permission_name text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.circle_member_permissions(target_circle_id, target_user_id)
    & public.circle_permission_bits(array[permission_name]) <> 0;
$$;

-- Where a user stands in the role hierarchy: the owner outranks everyone,
-- members rank at their highest assigned role (0 with none), non-members
-- at -1.
create or replace function public.circle_member_rank(
  target_circle_id uuid,
  target_user_id uuid
)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select case
        when c.owner_id = cm.user_id then 2147483647
        else coalesce((
          select max(r.position)
          from public.circle_member_roles mr
          join public.circle_roles r on r.id = mr.role_id
          where mr.circle_id = cm.circle_id
            and mr.user_id = cm.user_id
        ), 0)
      end
      from public.circle_members cm
      join public.circles c on c.id = cm.circle_id
      where cm.circle_id = target_circle_id
        and cm.user_id = target_user_id
    ),
    -1
  );
$$;

create or replace function public.current_user_has_circle_permission(
  target_circle_id uuid,
  permission_name text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.circle_member_has_permission(
    target_circle_id,
    auth.uid(),
    permission_name
  );
$$;

-- Keeps circle_members.role = 'admin' for display (see the header).
create or replace function public.sync_circle_admin_roles(target_circle_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.circle_members cm
  set role = flagged.next_role
  from (
    select
      member.user_id,
      case
        when exists (
          select 1
          from public.circle_member_roles mr
          join public.circle_roles r on r.id = mr.role_id
          where mr.circle_id = member.circle_id
            and mr.user_id = member.user_id
            and r.permissions & public.circle_permission_bits(array[
              'administrator',
              'manage_roles',
              'manage_channels',
              'manage_messages',
              'kick_members',
              'manage_nicknames'
            ]) <> 0
        ) then 'admin'
        else 'member'
      end as next_role
    from public.circle_members member
    join public.circles c on c.id = member.circle_id
    where member.circle_id = target_circle_id
      and member.user_id <> c.owner_id
      and member.role <> 'owner'
  ) flagged
  where cm.circle_id = target_circle_id
    and cm.user_id = flagged.user_id
    and cm.role is distinct from flagged.next_role;
$$;

revoke execute on function public.circle_member_permissions(uuid, uuid) from public;
revoke execute on function public.circle_member_permissions(uuid, uuid) from anon;
revoke execute on function public.circle_member_permissions(uuid, uuid) from authenticated;
revoke execute on function public.circle_member_has_permission(uuid, uuid, text) from public;
revoke execute on function public.circle_member_has_permission(uuid, uuid, text) from anon;
revoke execute on function public.circle_member_has_permission(uuid, uuid, text) from authenticated;
revoke execute on function public.circle_member_rank(uuid, uuid) from public;
revoke execute on function public.circle_member_rank(uuid, uuid) from anon;
revoke execute on function public.circle_member_rank(uuid, uuid) from authenticated;
revoke execute on function public.sync_circle_admin_roles(uuid) from public;
revoke execute on function public.sync_circle_admin_roles(uuid) from anon;
revoke execute on function public.sync_circle_admin_roles(uuid) from authenticated;
revoke execute on function public.current_user_has_circle_permission(uuid, text) from public;
revoke execute on function public.current_user_has_circle_permission(uuid, text) from anon;

-- Same as 202605190003_community_discovery_v1, plus the default role.
create or replace function public.create_circle(
  circle_name text,
  member_ids uuid[] default array[]::uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_name text := trim(coalesce(circle_name, ''));
  created_circle_id uuid;
  created_conversation_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_name) = 0 or char_length(trimmed_name) > 80 then
    raise exception 'Circle name must be between 1 and 80 characters'
      using errcode = '22023';
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

  insert into public.circles (name, owner_id)
  values (trimmed_name, current_user_id)
  returning id into created_circle_id;

  insert into public.circle_roles (circle_id, name, position, permissions, is_default)
  values (
    created_circle_id,
    '@everyone',
    0,
    public.circle_default_role_permissions(),
    true
  );

  insert into public.circle_members (circle_id, user_id, role)
  values (created_circle_id, current_user_id, 'owner');

  insert into public.circle_members (circle_id, user_id, role)
  select created_circle_id, invited.member_id, 'member'
  from (
    select distinct member_id
    from unnest(coalesce(member_ids, array[]::uuid[])) as candidate(member_id)
    where member_id is not null
      and member_id <> current_user_id
  ) invited
  where exists (
    select 1
    from public.friendships f
    where f.user_low_id = least(current_user_id, invited.member_id)
      and f.user_high_id = greatest(current_user_id, invited.member_id)
  )
    and not public.are_users_blocked(current_user_id, invited.member_id)
  on conflict do nothing;

  insert into public.conversations (type, title)
  values ('channel', 'general')
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
    created_by
  )
  values (
    created_circle_id,
    created_conversation_id,
    'general',
    0,
    current_user_id
  );

  return created_circle_id;
end;
$$;

-- Same as 202610130007_channel_categories, but needs manage_channels.
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

  return created_channel_id;
end;
$$;

-- Same as 202610130007_channel_categories, but needs manage_channels.
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

  return created_category_id;
end;
$$;

-- Same as 202610130007_channel_categories, but needs manage_channels.
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
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_name) = 0 or char_length(trimmed_name) > 32 then
    raise exception 'Category name must be between 1 and 32 characters'
      using errcode = '22023';
  end if;

  select ccc.circle_id into target_circle_id
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
end;
$$;

-- Same as 202610130007_channel_categories, but needs manage_channels.
create or replace function public.delete_channel_category(target_category_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_circle_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select ccc.circle_id into target_circle_id
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

  delete from public.circle_channel_categories
  where id = target_category_id;
end;
$$;

-- Same as 202610130007_channel_categories, but needs manage_channels.
-- layout = {"categories": [category ids in order],
--           "channels": [{"id": channel id, "category_id": id or null}, ...]}
-- Every category and channel of the circle must appear exactly once.
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

  if cardinality(channel_ids) <> (
      select count(distinct channel_id) from unnest(channel_ids) as ids(channel_id)
    )
    or (
      select count(*)
      from public.circle_channels cc
      where cc.circle_id = target_circle_id
    ) <> cardinality(channel_ids)
    or exists (
      select 1
      from unnest(channel_ids) as ids(channel_id)
      where not exists (
        select 1
        from public.circle_channels cc
        where cc.id = ids.channel_id
          and cc.circle_id = target_circle_id
      )
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

  update public.circle_channel_categories ccc
  set position = ordered.ordinality - 1
  from unnest(category_ids) with ordinality as ordered(category_id, ordinality)
  where ccc.id = ordered.category_id
    and ccc.position is distinct from ordered.ordinality - 1;

  update public.circle_channels cc
  set position = ordered.ordinality - 1,
      category_id = ordered.category_id,
      updated_at = now()
  from unnest(channel_ids, channel_category_ids)
    with ordinality as ordered(channel_id, category_id, ordinality)
  where cc.id = ordered.channel_id
    and (
      cc.position is distinct from ordered.ordinality - 1
      or cc.category_id is distinct from ordered.category_id
    );
end;
$$;

-- Same as 202610130008_fix_circle_role_checks, but needs create_invites.
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
  )
  insert into public.conversation_members (conversation_id, user_id, role)
  select cc.conversation_id, inserted.user_id, 'member'
  from inserted
  cross join public.circle_channels cc
  where cc.circle_id = target_circle_id
  on conflict do nothing;
end;
$$;

-- Invite rows: managers (manage_channels) see every invite of the circle,
-- members who may create invites see their own.
drop policy if exists circle_invites_select_manager on public.circle_invites;
create policy circle_invites_select_manager
  on public.circle_invites for select
  to authenticated
  using (
    public.current_user_has_circle_permission(circle_id, 'manage_channels')
    or (
      created_by = auth.uid()
      and public.current_user_has_circle_permission(circle_id, 'create_invites')
    )
  );

-- Same as 202610130003_circle_invites, but needs create_invites.
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
      return created_code;
    exception
      when unique_violation then
        if attempt >= 5 then
          raise;
        end if;
    end;
  end loop;
end;
$$;

-- Same as 202610130003_circle_invites: active invites only. Members with
-- manage_channels see all of them, members with create_invites their own.
create or replace function public.list_circle_invites(target_circle_id uuid)
returns table (
  code text,
  circle_id uuid,
  created_by uuid,
  created_by_name text,
  created_at timestamptz,
  expires_at timestamptz,
  max_uses integer,
  use_count integer
)
language sql
stable
security definer
set search_path = public
as $$
  select
    ci.code,
    ci.circle_id,
    ci.created_by,
    creator.display_name as created_by_name,
    ci.created_at,
    ci.expires_at,
    ci.max_uses,
    ci.use_count
  from public.circle_invites ci
  left join public.profiles creator on creator.id = ci.created_by
  where auth.uid() is not null
    and ci.circle_id = target_circle_id
    and (
      public.current_user_has_circle_permission(target_circle_id, 'manage_channels')
      or (
        ci.created_by = auth.uid()
        and public.current_user_has_circle_permission(
          target_circle_id,
          'create_invites'
        )
      )
    )
    and public.circle_invite_invalid_reason(ci) is null
  order by ci.created_at desc, ci.code;
$$;

-- Same as 202610130003_circle_invites: your own invites need
-- create_invites, everyone else's manage_channels.
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
end;
$$;

-- Same as 202610130004_circle_nicknames: members may always set their own
-- nickname. Changing someone else's needs manage_nicknames and a higher
-- rank than theirs (so only the owner may rename the owner). A null or
-- blank nickname clears it. Returns the stored nickname.
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

  select true
  into target_exists
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

  return normalized_nickname;
end;
$$;

-- Same as 202610130008_fix_circle_role_checks, but deleting someone
-- else's post needs manage_messages.
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
end;
$$;

-- Same as 202610130011_message_threads, but pinning in a circle channel
-- needs manage_messages.
create or replace function public.can_current_user_pin_messages(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select case c.type
        when 'direct' then public.is_current_user_conversation_member(c.id)
        when 'group' then exists (
          select 1
          from public.conversation_members cm
          where cm.conversation_id = c.id
            and cm.user_id = auth.uid()
            and cm.role = 'owner'
        )
        when 'channel' then public.is_current_user_conversation_member(c.id)
          and exists (
            select 1
            from public.circle_channels ch
            where ch.conversation_id = c.id
              and public.current_user_has_circle_permission(
                ch.circle_id,
                'manage_messages'
              )
          )
        when 'thread' then public.is_current_user_conversation_member(c.id)
          and public.can_current_user_pin_messages(ct.parent_conversation_id)
        else false
      end
      from public.conversations c
      left join public.conversation_threads ct on ct.conversation_id = c.id
      where c.id = target_conversation_id
    ),
    false
  );
$$;

-- Same as 202610130011_message_threads, but managing threads of a circle
-- channel needs manage_messages.
create or replace function public.can_current_user_manage_thread(
  target_thread_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select public.is_current_user_conversation_member(ct.parent_conversation_id)
        and (
          ct.created_by = auth.uid()
          or case parent.type
            when 'channel' then exists (
              select 1
              from public.circle_channels cc
              where cc.conversation_id = parent.id
                and public.current_user_has_circle_permission(
                  cc.circle_id,
                  'manage_messages'
                )
            )
            when 'group' then exists (
              select 1
              from public.conversation_members cm
              where cm.conversation_id = parent.id
                and cm.user_id = auth.uid()
                and cm.role in ('owner', 'admin')
            )
            else false
          end
        )
      from public.conversation_threads ct
      join public.conversations parent on parent.id = ct.parent_conversation_id
      where ct.id = target_thread_id
    ),
    false
  );
$$;

-- The colour of a user's highest coloured role in the circle of a channel
-- conversation (or of a thread under one), or null. Like
-- circle_channel_nickname, only the circle's own members can see it.
create or replace function public.circle_channel_role_color(
  target_conversation_id uuid,
  target_user_id uuid
)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select (
    select r.color
    from public.circle_member_roles mr
    join public.circle_roles r on r.id = mr.role_id
    where mr.circle_id = cc.circle_id
      and mr.user_id = target_user_id
      and r.color is not null
    order by r.position desc
    limit 1
  )
  from public.circle_channels cc
  where cc.conversation_id = coalesce(
      (
        select ct.parent_conversation_id
        from public.conversation_threads ct
        where ct.conversation_id = target_conversation_id
      ),
      target_conversation_id
    )
    and public.is_current_user_circle_member(cc.circle_id);
$$;

revoke execute on function public.circle_channel_role_color(uuid, uuid) from public;
revoke execute on function public.circle_channel_role_color(uuid, uuid) from anon;
revoke execute on function public.circle_channel_role_color(uuid, uuid) from authenticated;

-- PostgREST computed field: `messages?select=*,sender_role_color`.
create or replace function public.sender_role_color(message_row public.messages)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select public.circle_channel_role_color(
    message_row.conversation_id,
    message_row.sender_id
  );
$$;

-- Same as 202610130010_custom_status, plus the circle's roles (highest
-- first, with member counts), each member's assigned role ids and the
-- current user's effective permissions. Posts are manageable by their
-- author and by members with manage_messages.
create or replace function public.get_circle_detail(target_circle_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'circle',
    jsonb_build_object(
      'id', c.id,
      'name', c.name,
      'avatar_url', c.avatar_url,
      'owner_id', c.owner_id,
      'created_at', c.created_at,
      'updated_at', c.updated_at,
      'current_user_role', current_member.role,
      'current_user_permissions', caller.permissions
    ),
    'roles',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', r.id,
          'name', r.name,
          'color', r.color,
          'position', r.position,
          'permissions', r.permissions,
          'hoist', r.hoist,
          'is_default', r.is_default,
          'member_count', case
            when r.is_default then (
              select count(*)
              from public.circle_members cm
              where cm.circle_id = c.id
            )
            else (
              select count(*)
              from public.circle_member_roles mr
              where mr.role_id = r.id
            )
          end
        )
        order by r.position desc
      )
      from public.circle_roles r
      where r.circle_id = c.id
    ), '[]'::jsonb),
    'members',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'role', cm.role,
          'nickname', cm.nickname,
          'is_current_user', cm.user_id = auth.uid(),
          'created_at', cm.created_at,
          'role_ids', coalesce((
            select jsonb_agg(r.id order by r.position desc)
            from public.circle_member_roles mr
            join public.circle_roles r on r.id = mr.role_id
            where mr.circle_id = cm.circle_id
              and mr.user_id = cm.user_id
          ), '[]'::jsonb),
          'profile',
          jsonb_build_object(
            'id', p.id,
            'username', p.username,
            'display_name', p.display_name,
            'avatar_url', p.avatar_url,
            'bio', p.bio,
            'created_at', p.created_at,
            'updated_at', p.updated_at,
            'custom_status', public.custom_status(p)
          )
        )
        order by
          case cm.role when 'owner' then 0 when 'admin' then 1 else 2 end,
          coalesce(cm.nickname, p.display_name)
      )
      from public.circle_members cm
      join public.profiles p on p.id = cm.user_id
      where cm.circle_id = c.id
    ), '[]'::jsonb),
    'channels',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', cc.id,
          'circle_id', cc.circle_id,
          'conversation_id', cc.conversation_id,
          'name', cc.name,
          'position', cc.position,
          'category_id', cc.category_id,
          'created_by', cc.created_by
        )
        order by cc.position, cc.created_at
      )
      from public.circle_channels cc
      where cc.circle_id = c.id
    ), '[]'::jsonb),
    'categories',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', ccc.id,
          'circle_id', ccc.circle_id,
          'name', ccc.name,
          'position', ccc.position,
          'created_at', ccc.created_at
        )
        order by ccc.position, ccc.created_at
      )
      from public.circle_channel_categories ccc
      where ccc.circle_id = c.id
    ), '[]'::jsonb),
    'posts',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', cp.id,
          'circle_id', cp.circle_id,
          'author_id', cp.author_id,
          'author',
          jsonb_build_object(
            'id', author.id,
            'username', author.username,
            'display_name', author.display_name,
            'avatar_url', author.avatar_url,
            'bio', author.bio,
            'created_at', author.created_at,
            'updated_at', author.updated_at
          ),
          'body', cp.body,
          'attachment', cp.attachment,
          'created_at', cp.created_at,
          'updated_at', cp.updated_at,
          'is_own_post', cp.author_id = auth.uid(),
          'can_manage_post',
          cp.author_id = auth.uid()
            or caller.permissions
              & public.circle_permission_bit('manage_messages') <> 0,
          'like_count', (
            select count(*)
            from public.circle_post_likes cpl
            where cpl.post_id = cp.id
          ),
          'comment_count', (
            select count(*)
            from public.circle_post_comments cpc
            where cpc.post_id = cp.id
          ),
          'liked_by_current_user', exists (
            select 1
            from public.circle_post_likes cpl
            where cpl.post_id = cp.id
              and cpl.user_id = auth.uid()
          ),
          'comments',
          coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', cpc.id,
                'post_id', cpc.post_id,
                'author_id', cpc.author_id,
                'body', cpc.body,
                'created_at', cpc.created_at,
                'updated_at', cpc.updated_at,
                'is_own_comment', cpc.author_id = auth.uid(),
                'author',
                jsonb_build_object(
                  'id', comment_author.id,
                  'username', comment_author.username,
                  'display_name', comment_author.display_name,
                  'avatar_url', comment_author.avatar_url,
                  'bio', comment_author.bio,
                  'created_at', comment_author.created_at,
                  'updated_at', comment_author.updated_at
                )
              )
              order by cpc.created_at
            )
            from public.circle_post_comments cpc
            join public.profiles comment_author on comment_author.id = cpc.author_id
            where cpc.post_id = cp.id
              and cpc.deleted_at is null
          ), '[]'::jsonb)
        )
        order by cp.created_at desc
      )
      from public.circle_posts cp
      join public.profiles author on author.id = cp.author_id
      where cp.circle_id = c.id
        and cp.deleted_at is null
    ), '[]'::jsonb)
  )
  from public.circles c
  join public.circle_members current_member
    on current_member.circle_id = c.id
    and current_member.user_id = auth.uid()
  cross join lateral (
    select public.circle_member_permissions(c.id, auth.uid()) as permissions
  ) caller
  where c.id = target_circle_id;
$$;

-- Role names: trimmed, 1 to 32 characters, and not the default role's.
create or replace function public.normalize_circle_role_name(role_name text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  normalized text := regexp_replace(btrim(coalesce(role_name, '')), '\s+', ' ', 'g');
begin
  if char_length(normalized) = 0 or char_length(normalized) > 32 then
    raise exception 'Role name must be between 1 and 32 characters'
      using errcode = '22023';
  end if;
  if lower(normalized) = '@everyone' then
    raise exception 'Role name is reserved' using errcode = '22023';
  end if;
  return normalized;
end;
$$;

create or replace function public.validate_circle_role_fields(
  role_color integer,
  role_permissions bigint
)
returns void
language plpgsql
immutable
set search_path = public
as $$
begin
  if role_color is not null and (role_color < 0 or role_color > 16777215) then
    raise exception 'Role color must be an RGB value' using errcode = '22023';
  end if;
  if role_permissions is null
    or role_permissions < 0
    or role_permissions & ~public.circle_all_permissions() <> 0
  then
    raise exception 'Unknown role permissions' using errcode = '22023';
  end if;
end;
$$;

revoke execute on function public.normalize_circle_role_name(text) from public;
revoke execute on function public.normalize_circle_role_name(text) from anon;
revoke execute on function public.normalize_circle_role_name(text) from authenticated;
revoke execute on function public.validate_circle_role_fields(integer, bigint) from public;
revoke execute on function public.validate_circle_role_fields(integer, bigint) from anon;
revoke execute on function public.validate_circle_role_fields(integer, bigint) from authenticated;

-- New roles start just above @everyone, like Discord, so a manager can
-- always edit what they just created. Returns the new role id.
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

  return created_role_id;
end;
$$;

-- Edits a role below the caller. The default role keeps its name, has no
-- colour and is never hoisted. Non-owners may only flip permission bits
-- they hold themselves.
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
end;
$$;

-- Deletes a role below the caller; its members simply lose it.
create or replace function public.delete_circle_role(target_role_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_role public.circle_roles%rowtype;
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

  delete from public.circle_roles where id = target_role_id;

  perform public.sync_circle_admin_roles(target_role.circle_id);
end;
$$;

-- role_ids lists every role of the circle except @everyone, highest first
-- (as the roles page shows them). The circle's existing positions are
-- handed out in that order, so roles at or above a non-owner caller must
-- keep the position they have.
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
end;
$$;

-- Replaces the roles assigned to a member (role_ids excludes @everyone,
-- which everyone holds). Every role added or removed must be below the
-- caller, and only the owner may change the owner's roles.
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

  delete from public.circle_member_roles mr
  where mr.circle_id = target_circle_id
    and mr.user_id = target_user_id
    and not (mr.role_id = any(next_role_ids));

  insert into public.circle_member_roles (circle_id, user_id, role_id)
  select distinct target_circle_id, target_user_id, ids.role_id
  from unnest(next_role_ids) as ids(role_id)
  on conflict do nothing;

  perform public.sync_circle_admin_roles(target_circle_id);
end;
$$;

grant execute on function public.current_user_has_circle_permission(uuid, text) to authenticated;
grant execute on function public.create_circle(text, uuid[]) to authenticated;
grant execute on function public.create_circle_channel(uuid, text, uuid) to authenticated;
grant execute on function public.create_channel_category(uuid, text) to authenticated;
grant execute on function public.rename_channel_category(uuid, text) to authenticated;
grant execute on function public.delete_channel_category(uuid) to authenticated;
grant execute on function public.reorder_circle_channels(uuid, jsonb) to authenticated;
grant execute on function public.invite_circle_members(uuid, uuid[]) to authenticated;
grant execute on function public.create_circle_invite(uuid, integer, integer) to authenticated;
grant execute on function public.list_circle_invites(uuid) to authenticated;
grant execute on function public.revoke_circle_invite(text) to authenticated;
grant execute on function public.set_circle_nickname(uuid, uuid, text) to authenticated;
grant execute on function public.delete_circle_post(uuid) to authenticated;
grant execute on function public.can_current_user_pin_messages(uuid) to authenticated;
grant execute on function public.can_current_user_manage_thread(uuid) to authenticated;
grant execute on function public.sender_role_color(public.messages) to authenticated;
grant execute on function public.get_circle_detail(uuid) to authenticated;
grant execute on function public.create_circle_role(uuid, text, integer, bigint, boolean) to authenticated;
grant execute on function public.update_circle_role(uuid, text, integer, bigint, boolean) to authenticated;
grant execute on function public.delete_circle_role(uuid) to authenticated;
grant execute on function public.reorder_circle_roles(uuid, uuid[]) to authenticated;
grant execute on function public.set_member_roles(uuid, uuid, uuid[]) to authenticated;
