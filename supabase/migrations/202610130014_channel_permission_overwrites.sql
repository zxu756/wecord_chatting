-- Channel permission overwrites, like Discord's.
--
-- A channel may carry one overwrite per role (including @everyone) and one
-- per member, each with `allow` and `deny` bits. A member's permissions in a
-- channel start from their circle permissions (circle_member_permissions);
-- the owner and holders of `administrator` keep every permission and skip
-- overwrites. Then, in order:
--   1. the @everyone overwrite: deny, then allow;
--   2. the overwrites of the member's roles, combined: the OR of their
--      denies is removed, then the OR of their allows is added;
--   3. the member's own overwrite: deny, then allow.
-- Without view_channel in the end a member has no permissions in the
-- channel at all. Only channel-level bits can be overwritten: view_channel,
-- send_messages, manage_messages, create_invites, mention_everyone and
-- connect_voice. Threads use the permissions of their parent channel.
--
-- Enforcement:
-- * view_channel: is_current_user_conversation_member, which every message
--   policy, storage policy and message-reading RPC already asks, now also
--   requires view_channel for circle channels and their threads. The
--   channel list (get_circle_detail, circle_channels), chat list
--   (list_conversation_summaries, which also feeds notifications), circle
--   unread counts and discovery search skip channels the caller cannot see.
-- * send_messages: a trigger on messages refuses every non-system message in
--   a channel (or a thread of one) whose sender lacks send_messages there,
--   whichever path inserted it (direct insert, send_text_message,
--   forward_message, ...). Starting a thread needs it too. Reactions only
--   need view_channel.
--
-- Editing overwrites needs manage_roles and follows the role hierarchy:
-- only roles ranked below the caller (the owner outranks everyone), only
-- members ranked below the caller or the caller themselves, and only bits
-- the caller holds in that channel.

create or replace function public.circle_channel_overwrite_permissions()
returns bigint
language sql
immutable
set search_path = public
as $$
  select public.circle_permission_bits(array[
    'view_channel',
    'send_messages',
    'manage_messages',
    'create_invites',
    'mention_everyone',
    'connect_voice'
  ]);
$$;

alter table public.circle_channels
  drop constraint if exists circle_channels_id_circle_unique;
alter table public.circle_channels
  add constraint circle_channels_id_circle_unique unique (id, circle_id);

create table if not exists public.circle_channel_overwrites (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null,
  channel_id uuid not null,
  role_id uuid,
  user_id uuid,
  allow bigint not null default 0,
  deny bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint circle_channel_overwrites_one_target check (
    (role_id is null) <> (user_id is null)
  ),
  constraint circle_channel_overwrites_bits check (
    allow >= 0
    and deny >= 0
    and allow & ~public.circle_channel_overwrite_permissions() = 0
    and deny & ~public.circle_channel_overwrite_permissions() = 0
    and allow & deny = 0
  ),
  constraint circle_channel_overwrites_channel_fkey
    foreign key (channel_id, circle_id)
    references public.circle_channels(id, circle_id)
    on delete cascade,
  constraint circle_channel_overwrites_role_fkey
    foreign key (role_id, circle_id)
    references public.circle_roles(id, circle_id)
    on delete cascade,
  constraint circle_channel_overwrites_member_fkey
    foreign key (circle_id, user_id)
    references public.circle_members(circle_id, user_id)
    on delete cascade,
  constraint circle_channel_overwrites_channel_role_unique
    unique (channel_id, role_id),
  constraint circle_channel_overwrites_channel_user_unique
    unique (channel_id, user_id)
);

create index if not exists circle_channel_overwrites_role_idx
  on public.circle_channel_overwrites (role_id)
  where role_id is not null;

create index if not exists circle_channel_overwrites_member_idx
  on public.circle_channel_overwrites (circle_id, user_id)
  where user_id is not null;

drop trigger if exists circle_channel_overwrites_set_updated_at
  on public.circle_channel_overwrites;
create trigger circle_channel_overwrites_set_updated_at
  before update on public.circle_channel_overwrites
  for each row execute function public.set_updated_at();

-- Realtime matches DELETE events against the old row, so keep circle_id in
-- it to let an open circle filter overwrite removals.
alter table public.circle_channel_overwrites replica identity full;

alter table public.circle_channel_overwrites enable row level security;

-- Every member of the circle sees the overwrites (they name role and member
-- ids only), so losing access to a channel reaches open clients through
-- realtime.
drop policy if exists circle_channel_overwrites_select_member
  on public.circle_channel_overwrites;
create policy circle_channel_overwrites_select_member
  on public.circle_channel_overwrites for select
  to authenticated
  using (public.is_current_user_circle_member(circle_id));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'circle_channel_overwrites'
  ) then
    alter publication supabase_realtime add table public.circle_channel_overwrites;
  end if;
end $$;

-- These helpers run once per row in the messages policies, so they are
-- plpgsql (which caches query plans; nested SQL functions are re-planned on
-- every call) and use literal bits rather than circle_permission_bit().

-- A user's effective permissions in a channel (see the header); 0 for
-- non-members, for unknown channels and without view_channel. Base
-- permissions are computed as in circle_member_permissions.
create or replace function public.circle_channel_permissions(
  target_channel_id uuid,
  target_user_id uuid
)
returns bigint
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  channel_circle_id uuid;
  is_owner boolean;
  permissions bigint;
  everyone_deny bigint;
  everyone_allow bigint;
  roles_deny bigint;
  roles_allow bigint;
  member_deny bigint;
  member_allow bigint;
begin
  select cc.circle_id, c.owner_id = target_user_id
  into channel_circle_id, is_owner
  from public.circle_channels cc
  join public.circles c on c.id = cc.circle_id
  join public.circle_members cm
    on cm.circle_id = cc.circle_id
    and cm.user_id = target_user_id
  where cc.id = target_channel_id;

  if channel_circle_id is null then
    return 0;
  end if;

  if is_owner then
    return public.circle_all_permissions();
  end if;

  select coalesce(bit_or(r.permissions), 0)
  into permissions
  from public.circle_roles r
  where r.circle_id = channel_circle_id
    and (
      r.is_default
      or exists (
        select 1
        from public.circle_member_roles mr
        where mr.circle_id = channel_circle_id
          and mr.user_id = target_user_id
          and mr.role_id = r.id
      )
    );

  -- Administrators have everything, overwrites or not.
  if permissions & 16384 <> 0 then
    return public.circle_all_permissions();
  end if;

  -- The default role is never assigned, so role overwrites joined through
  -- circle_member_roles never include @everyone's.
  select
    coalesce(bit_or(o.deny) filter (where r.is_default), 0),
    coalesce(bit_or(o.allow) filter (where r.is_default), 0),
    coalesce(bit_or(o.deny) filter (where mr.role_id is not null), 0),
    coalesce(bit_or(o.allow) filter (where mr.role_id is not null), 0),
    coalesce(bit_or(o.deny) filter (where o.user_id = target_user_id), 0),
    coalesce(bit_or(o.allow) filter (where o.user_id = target_user_id), 0)
  into
    everyone_deny,
    everyone_allow,
    roles_deny,
    roles_allow,
    member_deny,
    member_allow
  from public.circle_channel_overwrites o
  left join public.circle_roles r on r.id = o.role_id
  left join public.circle_member_roles mr
    on mr.role_id = o.role_id
    and mr.circle_id = channel_circle_id
    and mr.user_id = target_user_id
  where o.channel_id = target_channel_id;

  permissions := (permissions & ~everyone_deny) | everyone_allow;
  permissions := (permissions & ~roles_deny) | roles_allow;
  permissions := (permissions & ~member_deny) | member_allow;

  -- view_channel
  if permissions & 1 = 0 then
    return 0;
  end if;

  return permissions;
end;
$$;

-- Never null: false for non-members, raises for unknown permission names.
create or replace function public.circle_channel_has_permission(
  target_channel_id uuid,
  target_user_id uuid,
  permission_name text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return public.circle_channel_permissions(target_channel_id, target_user_id)
    & public.circle_permission_bits(array[permission_name]) <> 0;
end;
$$;

-- The circle channel a conversation belongs to: itself for a channel, the
-- parent channel for a thread of one, otherwise null.
create or replace function public.conversation_circle_channel_id(
  target_conversation_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  found_channel_id uuid;
begin
  select cc.id
  into found_channel_id
  from public.circle_channels cc
  where cc.conversation_id = coalesce(
    (
      select ct.parent_conversation_id
      from public.conversation_threads ct
      where ct.conversation_id = target_conversation_id
    ),
    target_conversation_id
  );

  return found_channel_id;
end;
$$;

-- Whether a user holds a channel permission in a conversation. Always true
-- for conversations outside circle channels (direct chats, groups and their
-- threads), which have no channel permissions. Channels without overwrites
-- take a shortcut when @everyone grants the permission.
create or replace function public.user_has_conversation_channel_permission(
  target_conversation_id uuid,
  target_user_id uuid,
  permission_name text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  permission_bit bigint := public.circle_permission_bits(array[permission_name]);
  found_channel_id uuid;
  channel_circle_id uuid;
begin
  select cc.id, cc.circle_id
  into found_channel_id, channel_circle_id
  from public.circle_channels cc
  where cc.conversation_id = coalesce(
    (
      select ct.parent_conversation_id
      from public.conversation_threads ct
      where ct.conversation_id = target_conversation_id
    ),
    target_conversation_id
  );

  if found_channel_id is null then
    return true;
  end if;

  if not exists (
      select 1
      from public.circle_channel_overwrites o
      where o.channel_id = found_channel_id
    )
    and exists (
      select 1
      from public.circle_roles r
      where r.circle_id = channel_circle_id
        and r.is_default
        and r.permissions & (permission_bit | 1) = (permission_bit | 1)
    )
    and exists (
      select 1
      from public.circle_members cm
      where cm.circle_id = channel_circle_id
        and cm.user_id = target_user_id
    )
  then
    return true;
  end if;

  return public.circle_channel_permissions(found_channel_id, target_user_id)
    & permission_bit <> 0;
end;
$$;

create or replace function public.current_user_channel_permissions(
  target_channel_id uuid
)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select public.circle_channel_permissions(target_channel_id, auth.uid());
$$;

create or replace function public.current_user_has_channel_permission(
  target_channel_id uuid,
  permission_name text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.circle_channel_has_permission(
    target_channel_id,
    auth.uid(),
    permission_name
  );
$$;

revoke execute on function public.circle_channel_permissions(uuid, uuid) from public;
revoke execute on function public.circle_channel_permissions(uuid, uuid) from anon;
revoke execute on function public.circle_channel_permissions(uuid, uuid) from authenticated;
revoke execute on function public.circle_channel_has_permission(uuid, uuid, text) from public;
revoke execute on function public.circle_channel_has_permission(uuid, uuid, text) from anon;
revoke execute on function public.circle_channel_has_permission(uuid, uuid, text) from authenticated;
revoke execute on function public.conversation_circle_channel_id(uuid) from public;
revoke execute on function public.conversation_circle_channel_id(uuid) from anon;
revoke execute on function public.conversation_circle_channel_id(uuid) from authenticated;
revoke execute on function public.user_has_conversation_channel_permission(uuid, uuid, text) from public;
revoke execute on function public.user_has_conversation_channel_permission(uuid, uuid, text) from anon;
revoke execute on function public.user_has_conversation_channel_permission(uuid, uuid, text) from authenticated;
revoke execute on function public.current_user_channel_permissions(uuid) from public;
revoke execute on function public.current_user_channel_permissions(uuid) from anon;
revoke execute on function public.current_user_has_channel_permission(uuid, text) from public;
revoke execute on function public.current_user_has_channel_permission(uuid, text) from anon;

-- Same as 202605180001_private_chat, but circle channels and their threads
-- also need view_channel. Every policy and RPC that reads messages,
-- reactions, mentions, pins, threads, read markers or chat media goes
-- through this, once per row, so the common case (a channel without
-- overwrites whose @everyone can view it) is answered inline and only other
-- channels compute the member's permissions.
create or replace function public.is_current_user_conversation_member(
  check_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = check_conversation_id
        and cm.user_id = auth.uid()
    )
    and coalesce(
      (
        select case
          when not exists (
              select 1
              from public.circle_channel_overwrites o
              where o.channel_id = cc.id
            )
            and exists (
              select 1
              from public.circle_roles r
              where r.circle_id = cc.circle_id
                and r.is_default
                and r.permissions & 1 <> 0
            )
            then true
          -- view_channel
          else public.circle_channel_permissions(cc.id, auth.uid()) & 1 <> 0
        end
        from public.circle_channels cc
        where cc.conversation_id = coalesce(
          (
            select ct.parent_conversation_id
            from public.conversation_threads ct
            where ct.conversation_id = check_conversation_id
          ),
          check_conversation_id
        )
      ),
      true
    );
$$;

-- Channels the caller cannot see are hidden from direct reads too.
drop policy if exists circle_channels_select_member on public.circle_channels;
create policy circle_channels_select_member
  on public.circle_channels for select
  to authenticated
  using (
    public.is_current_user_circle_member(circle_id)
    and public.current_user_has_channel_permission(id, 'view_channel')
  );

-- Every message insert, whatever the path: circle channels and their
-- threads need send_messages. System notices ("X pinned a message") are
-- written by RPCs that check their own permission.
create or replace function public.check_channel_message_send()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.type <> 'system'
    and not public.user_has_conversation_channel_permission(
      new.conversation_id,
      new.sender_id,
      'send_messages'
    )
  then
    raise exception 'You do not have permission to send messages in this channel'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke execute on function public.check_channel_message_send() from public;
revoke execute on function public.check_channel_message_send() from anon;
revoke execute on function public.check_channel_message_send() from authenticated;

drop trigger if exists messages_check_channel_send on public.messages;
create trigger messages_check_channel_send
  before insert on public.messages
  for each row execute function public.check_channel_message_send();

-- Same as 202610130011_message_threads, but starting a thread in a circle
-- channel needs send_messages there.
create or replace function public.create_thread(
  parent_conversation_id uuid,
  root_message_id uuid default null,
  title text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  parent_type text;
  root_message public.messages%rowtype;
  existing_thread public.conversation_threads%rowtype;
  created_thread public.conversation_threads%rowtype;
  created_conversation_id uuid;
  normalized_title text := nullif(
    regexp_replace(btrim(coalesce(create_thread.title, '')), '\s+', ' ', 'g'),
    ''
  );
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select c.type
  into parent_type
  from public.conversations c
  where c.id = create_thread.parent_conversation_id;

  if parent_type is null
    or not public.is_current_user_conversation_member(
      create_thread.parent_conversation_id
    )
  then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  if parent_type not in ('channel', 'group') then
    raise exception 'Threads can only start in channels and groups'
      using errcode = '22023';
  end if;

  if not public.user_has_conversation_channel_permission(
    create_thread.parent_conversation_id,
    current_user_id,
    'send_messages'
  ) then
    raise exception 'You do not have permission to send messages in this channel'
      using errcode = '42501';
  end if;

  if create_thread.root_message_id is not null then
    -- Lock the root so concurrent calls agree on a single thread.
    select m.*
    into root_message
    from public.messages m
    where m.id = create_thread.root_message_id
      and m.conversation_id = create_thread.parent_conversation_id
    for update;

    if root_message.id is null then
      raise exception 'Root message not found in this conversation'
        using errcode = '22023';
    end if;

    select ct.*
    into existing_thread
    from public.conversation_threads ct
    where ct.root_message_id = root_message.id;

    if existing_thread.id is not null then
      return public.thread_payload(existing_thread);
    end if;

    if root_message.recalled_at is not null or root_message.type = 'system' then
      raise exception 'Threads cannot start from this message'
        using errcode = '22023';
    end if;

    normalized_title := coalesce(
      normalized_title,
      nullif(
        left(regexp_replace(btrim(root_message.body), '\s+', ' ', 'g'), 40),
        ''
      ),
      case root_message.type
        when 'image' then 'Image'
        when 'voice' then 'Voice message'
        else 'Thread'
      end
    );
  end if;

  if normalized_title is null then
    raise exception 'Thread title is required' using errcode = '22023';
  end if;

  if char_length(normalized_title) > 100 then
    raise exception 'Thread title must be at most 100 characters'
      using errcode = '22023';
  end if;

  insert into public.conversations (type, title)
  values ('thread', normalized_title)
  returning id into created_conversation_id;

  insert into public.conversation_members (conversation_id, user_id, role)
  select created_conversation_id, cm.user_id, 'member'
  from public.conversation_members cm
  where cm.conversation_id = create_thread.parent_conversation_id
  on conflict do nothing;

  insert into public.conversation_threads (
    parent_conversation_id,
    root_message_id,
    conversation_id,
    title,
    created_by
  )
  values (
    create_thread.parent_conversation_id,
    create_thread.root_message_id,
    created_conversation_id,
    normalized_title,
    current_user_id
  )
  returning * into created_thread;

  return public.thread_payload(created_thread);
end;
$$;

-- Validates an overwrite edit by the caller and returns the caller's
-- channel permissions. Raises unless the caller has manage_roles, can see
-- the channel, outranks the target (or is the target member) and only
-- changes bits they hold in the channel.
create or replace function public.check_channel_overwrite_edit(
  target_channel public.circle_channels,
  target_role_id uuid,
  target_user_id uuid,
  changed_bits bigint
)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  caller_permissions bigint;
  caller_rank integer;
  target_role public.circle_roles%rowtype;
begin
  if not public.circle_member_has_permission(
      target_channel.circle_id,
      current_user_id,
      'manage_roles'
    )
    or not public.circle_channel_has_permission(
      target_channel.id,
      current_user_id,
      'view_channel'
    )
  then
    raise exception 'Only members who can manage roles can edit channel permissions'
      using errcode = '42501';
  end if;

  caller_rank := public.circle_member_rank(target_channel.circle_id, current_user_id);

  if target_role_id is not null then
    select r.* into target_role
    from public.circle_roles r
    where r.id = target_role_id
      and r.circle_id = target_channel.circle_id;

    if target_role.id is null then
      raise exception 'Role not found in this circle' using errcode = '22023';
    end if;

    if target_role.position >= caller_rank then
      raise exception 'Cannot edit permissions of a role at or above your highest role'
        using errcode = '42501';
    end if;
  else
    if not exists (
      select 1
      from public.circle_members cm
      where cm.circle_id = target_channel.circle_id
        and cm.user_id = target_user_id
    ) then
      raise exception 'Circle member not found' using errcode = 'P0002';
    end if;

    if target_user_id <> current_user_id
      and public.circle_member_rank(target_channel.circle_id, target_user_id)
        >= caller_rank
    then
      raise exception 'Cannot edit permissions of a member at or above your highest role'
        using errcode = '42501';
    end if;
  end if;

  caller_permissions := public.circle_channel_permissions(
    target_channel.id,
    current_user_id
  );

  if changed_bits & ~caller_permissions <> 0 then
    raise exception 'Cannot change permissions you do not have'
      using errcode = '42501';
  end if;
end;
$$;

revoke execute on function public.check_channel_overwrite_edit(public.circle_channels, uuid, uuid, bigint) from public;
revoke execute on function public.check_channel_overwrite_edit(public.circle_channels, uuid, uuid, bigint) from anon;
revoke execute on function public.check_channel_overwrite_edit(public.circle_channels, uuid, uuid, bigint) from authenticated;

-- Writes the overwrite of a role or a member (exactly one of the two) in a
-- channel; allow = deny = 0 removes it. Bits outside the channel-level
-- permissions, negative masks and bits both allowed and denied are refused.
-- Returns the stored overwrite, or null when removed.
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

-- A channel's overwrites, for members who can edit them: role overwrites
-- from the highest role down to @everyone, then member overwrites.
create or replace function public.list_channel_overwrites(target_channel_id uuid)
returns table (
  id uuid,
  channel_id uuid,
  role_id uuid,
  user_id uuid,
  allow bigint,
  deny bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  channel_circle_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cc.circle_id into channel_circle_id
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel_circle_id is null
    or not public.current_user_has_circle_permission(channel_circle_id, 'manage_roles')
    or not public.current_user_has_channel_permission(target_channel_id, 'view_channel')
  then
    raise exception 'Only members who can manage roles can see channel permissions'
      using errcode = '42501';
  end if;

  return query
  select o.id, o.channel_id, o.role_id, o.user_id, o.allow, o.deny
  from public.circle_channel_overwrites o
  left join public.circle_roles r on r.id = o.role_id
  left join public.circle_members cm
    on cm.circle_id = o.circle_id
    and cm.user_id = o.user_id
  where o.channel_id = target_channel_id
  order by
    (o.role_id is null),
    r.position desc nulls last,
    cm.created_at,
    o.id;
end;
$$;

-- Quick switches on the @everyone overwrite: a private channel denies
-- view_channel, a read-only one denies send_messages; switching off removes
-- that deny. Like Discord, a manager who would lose the permission through
-- the change keeps it: their highest role (or, without one that helps,
-- their member overwrite) gets it allowed, even though that role is not
-- below them.
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

-- Same as 202610130012_circle_roles, but layouts list only the channels the
-- caller can see. Those take the visible channels' places in the new order;
-- hidden channels keep their position and category.
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
end;
$$;

-- Same as 202610130012_circle_roles, but channels list only those the
-- caller can see, each with the caller's permissions in it and whether
-- @everyone is denied view_channel (private) or send_messages (read-only).
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
          'created_by', cc.created_by,
          'current_user_permissions', channel_access.permissions,
          'is_private', coalesce(
            everyone_overwrite.deny
              & public.circle_permission_bit('view_channel') <> 0,
            false
          ),
          'is_read_only', coalesce(
            everyone_overwrite.deny
              & public.circle_permission_bit('send_messages') <> 0,
            false
          )
        )
        order by cc.position, cc.created_at
      )
      from public.circle_channels cc
      cross join lateral (
        select public.circle_channel_permissions(cc.id, auth.uid()) as permissions
      ) channel_access
      left join lateral (
        select o.deny
        from public.circle_channel_overwrites o
        join public.circle_roles r on r.id = o.role_id
        where o.channel_id = cc.id
          and r.is_default
      ) everyone_overwrite on true
      where cc.circle_id = c.id
        and channel_access.permissions
          & public.circle_permission_bit('view_channel') <> 0
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

-- Same as 202610130011_message_threads, but circle channels (and their
-- threads) the caller cannot see are left out, and each conversation says
-- whether the caller may send in it (false only for circle channels and
-- their threads without send_messages). Notifications read this list too.
drop function if exists public.list_conversation_summaries();

create or replace function public.list_conversation_summaries()
returns table (
  id uuid,
  type text,
  title text,
  avatar_url text,
  announcement text,
  announcement_updated_at timestamptz,
  announcement_updated_by uuid,
  last_message_body text,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_type text,
  unread_count bigint,
  pinned_at timestamptz,
  muted_until timestamptz,
  is_muted boolean,
  is_marked_unread boolean,
  member_count bigint,
  mentioned_user_ids uuid[],
  circle_id uuid,
  circle_notification_level text,
  circle_muted_until timestamptz,
  direct_user_id uuid,
  direct_custom_status jsonb,
  parent_conversation_id uuid,
  parent_title text,
  thread_id uuid,
  thread_archived_at timestamptz,
  thread_last_activity_at timestamptz,
  can_send_messages boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with current_memberships as (
    select
      cm.conversation_id,
      cm.last_read_message_id,
      cm.pinned_at,
      cm.muted_until,
      cm.hidden_at,
      cm.manual_unread_at
    from public.conversation_members cm
    where cm.user_id = auth.uid()
      and public.user_has_conversation_channel_permission(
        cm.conversation_id,
        auth.uid(),
        'view_channel'
      )
  ),
  read_markers as (
    select cm.conversation_id, rm.created_at as last_read_at
    from current_memberships cm
    left join public.messages rm on rm.id = cm.last_read_message_id
  ),
  direct_profiles as (
    select
      cm.conversation_id,
      p.id as user_id,
      coalesce(ca.alias, p.display_name) as display_name,
      p.avatar_url,
      case
        when exists (
          select 1
          from public.blocks b
          where b.blocker_id = p.id
            and b.blocked_id = auth.uid()
        ) then null
        else public.custom_status(p)
      end as custom_status
    from public.conversation_members cm
    join public.profiles p on p.id = cm.user_id
    left join public.contact_aliases ca
      on ca.owner_id = auth.uid()
      and ca.friend_id = p.id
    where cm.user_id <> auth.uid()
  ),
  member_counts as (
    select cm.conversation_id, count(*) as member_count
    from public.conversation_members cm
    group by cm.conversation_id
  ),
  last_message_mentions as (
    select mm.message_id, array_agg(distinct mm.user_id) as mentioned_user_ids
    from public.message_mentions mm
    group by mm.message_id
  )
  select
    c.id,
    c.type,
    coalesce(c.title, dp.display_name) as title,
    coalesce(c.avatar_url, dp.avatar_url) as avatar_url,
    c.announcement,
    c.announcement_updated_at,
    c.announcement_updated_by,
    case
      when last_message.recalled_at is not null then 'Message deleted'
      when last_message.type = 'image' then '[Image]'
      else last_message.body
    end as last_message_body,
    last_message.sender_id as last_message_sender_id,
    c.last_message_at,
    last_message.type as last_message_type,
    greatest(
      count(unread_messages.id),
      case when cm.manual_unread_at is null then 0 else 1 end::bigint
    ) as unread_count,
    cm.pinned_at,
    cm.muted_until,
    cm.muted_until is not null and cm.muted_until > now() as is_muted,
    cm.manual_unread_at is not null as is_marked_unread,
    coalesce(mc.member_count, 0) as member_count,
    coalesce(lmm.mentioned_user_ids, array[]::uuid[]) as mentioned_user_ids,
    cc.circle_id,
    case
      when cc.circle_id is null then null
      else coalesce(cns.level, 'all')
    end as circle_notification_level,
    cns.muted_until as circle_muted_until,
    dp.user_id as direct_user_id,
    dp.custom_status as direct_custom_status,
    ct.parent_conversation_id,
    parent_conversation.title as parent_title,
    ct.id as thread_id,
    ct.archived_at as thread_archived_at,
    coalesce(ct.last_message_at, ct.created_at) as thread_last_activity_at,
    cc.id is null
      or public.circle_channel_has_permission(
        cc.id,
        auth.uid(),
        'send_messages'
      ) as can_send_messages
  from public.conversations c
  join current_memberships cm on cm.conversation_id = c.id
  left join read_markers rm on rm.conversation_id = c.id
  left join direct_profiles dp on dp.conversation_id = c.id and c.type = 'direct'
  left join member_counts mc on mc.conversation_id = c.id
  left join public.messages last_message on last_message.id = c.last_message_id
  left join last_message_mentions lmm on lmm.message_id = last_message.id
  left join public.conversation_threads ct on ct.conversation_id = c.id
  left join public.conversations parent_conversation
    on parent_conversation.id = ct.parent_conversation_id
  left join public.circle_channels cc
    on cc.conversation_id = coalesce(ct.parent_conversation_id, c.id)
  left join public.circle_notification_settings cns
    on cns.circle_id = cc.circle_id
    and cns.user_id = auth.uid()
  left join public.messages unread_messages
    on unread_messages.conversation_id = c.id
    and unread_messages.sender_id <> auth.uid()
    and (
      rm.last_read_at is null
      or unread_messages.created_at > rm.last_read_at
    )
  where cm.hidden_at is null
    or c.last_message_at > cm.hidden_at
  group by
    c.id,
    c.type,
    c.title,
    c.avatar_url,
    c.announcement,
    c.announcement_updated_at,
    c.announcement_updated_by,
    dp.user_id,
    dp.display_name,
    dp.avatar_url,
    dp.custom_status,
    last_message.body,
    last_message.sender_id,
    last_message.recalled_at,
    last_message.type,
    c.last_message_at,
    c.updated_at,
    cm.pinned_at,
    cm.muted_until,
    cm.manual_unread_at,
    mc.member_count,
    lmm.mentioned_user_ids,
    cc.id,
    cc.circle_id,
    cns.level,
    cns.muted_until,
    ct.id,
    ct.parent_conversation_id,
    ct.archived_at,
    ct.last_message_at,
    ct.created_at,
    parent_conversation.title
  order by
    cm.pinned_at desc nulls last,
    c.last_message_at desc nulls last,
    c.updated_at desc;
$$;

-- Same as 202610130011_message_threads, but channels the caller cannot see
-- (and their threads) count neither towards unread messages and mentions
-- nor towards channel_count and latest activity.
drop function if exists public.list_circle_summaries();

create or replace function public.list_circle_summaries()
returns table (
  id uuid,
  name text,
  avatar_url text,
  member_count bigint,
  channel_count bigint,
  latest_activity_at timestamptz,
  current_user_role text,
  unread_count bigint,
  mention_count bigint,
  is_muted boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with visible_channels as (
    select cc.id, cc.circle_id, cc.conversation_id
    from public.circle_members current_member
    join public.circle_channels cc on cc.circle_id = current_member.circle_id
    where current_member.user_id = auth.uid()
      and public.circle_channel_has_permission(cc.id, auth.uid(), 'view_channel')
  ),
  circle_conversations as (
    select vc.circle_id, vc.conversation_id
    from visible_channels vc
    union all
    select vc.circle_id, ct.conversation_id
    from visible_channels vc
    join public.conversation_threads ct
      on ct.parent_conversation_id = vc.conversation_id
  ),
  channel_reads as (
    select
      cc.circle_id,
      cc.conversation_id,
      conv_member.manual_unread_at,
      read_message.created_at as last_read_at
    from circle_conversations cc
    join public.conversation_members conv_member
      on conv_member.conversation_id = cc.conversation_id
      and conv_member.user_id = auth.uid()
    left join public.messages read_message
      on read_message.id = conv_member.last_read_message_id
  ),
  channel_counts as (
    select
      cr.circle_id,
      greatest(
        (
          select count(*)
          from public.messages unread_message
          where unread_message.conversation_id = cr.conversation_id
            and unread_message.sender_id <> auth.uid()
            and (
              cr.last_read_at is null
              or unread_message.created_at > cr.last_read_at
            )
        ),
        case when cr.manual_unread_at is null then 0 else 1 end::bigint
      ) as unread_count,
      (
        select count(distinct mentioned_message.id)
        from public.message_mentions mm
        join public.messages mentioned_message
          on mentioned_message.id = mm.message_id
        where mm.conversation_id = cr.conversation_id
          and mm.user_id = auth.uid()
          and mentioned_message.sender_id <> auth.uid()
          and mentioned_message.type <> 'system'
          and (
            cr.last_read_at is null
            or mentioned_message.created_at > cr.last_read_at
          )
      ) as mention_count
    from channel_reads cr
  ),
  circle_counts as (
    select
      channel_count.circle_id,
      sum(channel_count.unread_count)::bigint as unread_count,
      sum(channel_count.mention_count)::bigint as mention_count
    from channel_counts channel_count
    group by channel_count.circle_id
  )
  select
    c.id,
    c.name,
    c.avatar_url,
    count(distinct all_members.user_id) as member_count,
    count(distinct cc.id) as channel_count,
    greatest(
      c.updated_at,
      coalesce(max(cp.created_at), c.updated_at),
      coalesce(max(ch_conversation.last_message_at), c.updated_at)
    ) as latest_activity_at,
    current_member.role as current_user_role,
    coalesce(counts.unread_count, 0) as unread_count,
    coalesce(counts.mention_count, 0) as mention_count,
    coalesce(
      cns.level = 'none'
        or (cns.muted_until is not null and cns.muted_until > now()),
      false
    ) as is_muted
  from public.circles c
  join public.circle_members current_member
    on current_member.circle_id = c.id
    and current_member.user_id = auth.uid()
  left join public.circle_members all_members on all_members.circle_id = c.id
  left join visible_channels cc on cc.circle_id = c.id
  left join public.conversations ch_conversation
    on ch_conversation.id = cc.conversation_id
  left join public.circle_posts cp on cp.circle_id = c.id
  left join circle_counts counts on counts.circle_id = c.id
  left join public.circle_notification_settings cns
    on cns.circle_id = c.id
    and cns.user_id = auth.uid()
  group by
    c.id,
    c.name,
    c.avatar_url,
    c.updated_at,
    current_member.role,
    counts.unread_count,
    counts.mention_count,
    cns.level,
    cns.muted_until
  order by latest_activity_at desc, c.created_at desc;
$$;

-- Same as 202605190003_community_discovery_v1, but channels and messages
-- the caller cannot see are left out.
create or replace function public.search_discovery(search_query text)
returns table (
  result_type text,
  id uuid,
  title text,
  subtitle text,
  avatar_url text,
  conversation_id uuid,
  circle_id uuid,
  channel_id uuid,
  rank real
)
language sql
stable
security definer
set search_path = public
as $$
  with query_input as (
    select trim(coalesce(search_query, '')) as q
  ),
  friend_results as (
    select
      'contact'::text as result_type,
      p.id,
      coalesce(ca.alias, p.display_name) as title,
      p.username as subtitle,
      p.avatar_url,
      null::uuid as conversation_id,
      null::uuid as circle_id,
      null::uuid as channel_id,
      1.0::real as rank
    from query_input qi
    join public.friendships f
      on auth.uid() in (f.user_low_id, f.user_high_id)
    join public.profiles p
      on p.id = case
        when f.user_low_id = auth.uid() then f.user_high_id
        else f.user_low_id
      end
    left join public.contact_aliases ca
      on ca.owner_id = auth.uid()
      and ca.friend_id = p.id
    where qi.q <> ''
      and (
        p.display_name ilike '%' || qi.q || '%'
        or p.username ilike '%' || qi.q || '%'
        or ca.alias ilike '%' || qi.q || '%'
      )
  ),
  group_results as (
    select
      'group'::text as result_type,
      c.id,
      c.title,
      c.announcement as subtitle,
      c.avatar_url,
      c.id as conversation_id,
      null::uuid as circle_id,
      null::uuid as channel_id,
      0.8::real as rank
    from query_input qi
    join public.conversation_members cm
      on cm.user_id = auth.uid()
    join public.conversations c
      on c.id = cm.conversation_id
      and c.type = 'group'
    where qi.q <> ''
      and coalesce(c.title, '') ilike '%' || qi.q || '%'
  ),
  circle_results as (
    select
      'circle'::text as result_type,
      c.id,
      c.name as title,
      count(all_members.user_id)::text || ' members' as subtitle,
      c.avatar_url,
      null::uuid as conversation_id,
      c.id as circle_id,
      null::uuid as channel_id,
      0.7::real as rank
    from query_input qi
    join public.circle_members current_member
      on current_member.user_id = auth.uid()
    join public.circles c
      on c.id = current_member.circle_id
    left join public.circle_members all_members on all_members.circle_id = c.id
    where qi.q <> ''
      and c.name ilike '%' || qi.q || '%'
    group by c.id, c.name, c.avatar_url
  ),
  channel_results as (
    select
      'circle_channel'::text as result_type,
      cc.id,
      cc.name as title,
      c.name as subtitle,
      c.avatar_url,
      cc.conversation_id,
      cc.circle_id,
      cc.id as channel_id,
      0.65::real as rank
    from query_input qi
    join public.circle_members current_member
      on current_member.user_id = auth.uid()
    join public.circle_channels cc
      on cc.circle_id = current_member.circle_id
    join public.circles c
      on c.id = cc.circle_id
    where qi.q <> ''
      and cc.name ilike '%' || qi.q || '%'
      and public.circle_channel_has_permission(cc.id, auth.uid(), 'view_channel')
  ),
  message_results as (
    select
      'message'::text as result_type,
      m.id,
      left(m.body, 80) as title,
      coalesce(c.title, sender.display_name) as subtitle,
      sender.avatar_url,
      m.conversation_id,
      cc.circle_id,
      cc.id as channel_id,
      0.5::real as rank
    from query_input qi
    join public.conversation_members cm
      on cm.user_id = auth.uid()
    join public.messages m
      on m.conversation_id = cm.conversation_id
      and m.recalled_at is null
    join public.conversations c on c.id = m.conversation_id
    join public.profiles sender on sender.id = m.sender_id
    left join public.circle_channels cc on cc.conversation_id = m.conversation_id
    where qi.q <> ''
      and m.body ilike '%' || qi.q || '%'
      and public.user_has_conversation_channel_permission(
        m.conversation_id,
        auth.uid(),
        'view_channel'
      )
  )
  select * from friend_results
  union all
  select * from group_results
  union all
  select * from circle_results
  union all
  select * from channel_results
  union all
  select * from message_results
  order by rank desc, title;
$$;

grant execute on function public.current_user_channel_permissions(uuid) to authenticated;
grant execute on function public.current_user_has_channel_permission(uuid, text) to authenticated;
grant execute on function public.create_thread(uuid, uuid, text) to authenticated;
grant execute on function public.set_channel_overwrite(uuid, uuid, uuid, bigint, bigint) to authenticated;
grant execute on function public.list_channel_overwrites(uuid) to authenticated;
grant execute on function public.set_channel_privacy(uuid, boolean, boolean) to authenticated;
grant execute on function public.reorder_circle_channels(uuid, jsonb) to authenticated;
grant execute on function public.get_circle_detail(uuid) to authenticated;
grant execute on function public.list_conversation_summaries() to authenticated;
grant execute on function public.list_circle_summaries() to authenticated;
grant execute on function public.search_discovery(text) to authenticated;
