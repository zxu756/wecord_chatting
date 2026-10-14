-- Bans and timeouts.
--
-- * Two new permissions: ban_members (1 << 15) and moderate_members
--   (1 << 16). Roles that could kick members get both, so existing
--   moderators keep moderating.
-- * circle_bans lists who may not join a circle. A trigger on circle_members
--   refuses them on every join path (invite links, friend invites,
--   discovery). ban_circle_member removes the member (like a kick), can
--   delete their circle messages from the last hours, and also bans people
--   who are not members. unban_circle_member and list_circle_bans manage
--   the list.
-- * circle_members.timed_out_until: while it is in the future the member's
--   circle and channel permissions shrink to view_channel, so they can read
--   but not send, react, start threads, invite or join voice. Timing out
--   also drops them from the circle's voice channels.

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
    when 'ban_members' then 32768::bigint
    when 'moderate_members' then 65536::bigint
    else null
  end;
end;
$$;

create or replace function public.circle_all_permissions()
returns bigint
language sql
immutable
set search_path = public
as $$
  select 131071::bigint;
$$;

alter table public.circle_roles
  drop constraint if exists circle_roles_permissions_range;

alter table public.circle_roles
  add constraint circle_roles_permissions_range check (
    permissions >= 0 and permissions <= 131071
  );

update public.circle_roles
set permissions = permissions | 32768 | 65536
where permissions & 32 <> 0;

alter table public.circle_members
  add column if not exists timed_out_until timestamptz;

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
        -- Timed-out members can only read.
        when cm.timed_out_until > now()
          then granted.permissions & public.circle_permission_bit('view_channel')
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
  is_timed_out boolean;
  permissions bigint;
  everyone_deny bigint;
  everyone_allow bigint;
  roles_deny bigint;
  roles_allow bigint;
  member_deny bigint;
  member_allow bigint;
begin
  select
    cc.circle_id,
    c.owner_id = target_user_id,
    coalesce(cm.timed_out_until > now(), false)
  into channel_circle_id, is_owner, is_timed_out
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
  if permissions & 16384 <> 0 and not is_timed_out then
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

  -- Timed-out members can only read.
  if is_timed_out then
    permissions := permissions & 1;
  end if;

  -- view_channel
  if permissions & 1 = 0 then
    return 0;
  end if;

  return permissions;
end;
$$;

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
        and (cm.timed_out_until is null or cm.timed_out_until <= now())
    )
  then
    return true;
  end if;

  return public.circle_channel_permissions(found_channel_id, target_user_id)
    & permission_bit <> 0;
end;
$$;

create table if not exists public.circle_bans (
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  reason text,
  banned_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (circle_id, user_id),
  constraint circle_bans_reason_length check (
    reason is null or char_length(reason) between 1 and 512
  )
);

alter table public.circle_bans enable row level security;

drop policy if exists circle_bans_select_moderator on public.circle_bans;
create policy circle_bans_select_moderator
  on public.circle_bans for select
  to authenticated
  using (public.current_user_has_circle_permission(circle_id, 'ban_members'));

revoke insert, update, delete on public.circle_bans from anon, authenticated;

create or replace function public.reject_banned_circle_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.circle_bans b
    where b.circle_id = new.circle_id
      and b.user_id = new.user_id
  ) then
    raise exception 'Banned from this circle' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function public.reject_banned_circle_member() from public;

drop trigger if exists circle_members_reject_banned on public.circle_members;
create trigger circle_members_reject_banned
  before insert on public.circle_members
  for each row execute function public.reject_banned_circle_member();

-- Removes a member from a circle, its channels and their threads.
create or replace function public.remove_circle_member_rows(
  target_circle_id uuid,
  target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
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
end;
$$;

revoke execute on function public.remove_circle_member_rows(uuid, uuid) from public;
revoke execute on function public.remove_circle_member_rows(uuid, uuid) from anon;
revoke execute on function public.remove_circle_member_rows(uuid, uuid) from authenticated;

-- Bans a member or anyone else. Returns the deleted messages' image and
-- voice objects that nothing else uses, for the client to remove from
-- Storage (as recall_message does).
create or replace function public.ban_circle_member(
  target_circle_id uuid,
  target_user_id uuid,
  ban_reason text default null,
  delete_message_hours integer default 0
)
returns table (bucket_id text, object_path text)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_reason text := nullif(btrim(coalesce(ban_reason, '')), '');
  is_member boolean;
  banned_label text;
  deleted_count integer := 0;
  target public.messages%rowtype;
  media_bucket text;
  media_path text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'ban_members'
  ) then
    raise exception 'Only members who can ban members can ban members'
      using errcode = '42501';
  end if;

  if trimmed_reason is not null and char_length(trimmed_reason) > 512 then
    raise exception 'Ban reason is too long' using errcode = '22023';
  end if;

  if coalesce(delete_message_hours, 0) not between 0 and 168 then
    raise exception 'Messages can be deleted from up to 7 days back'
      using errcode = '22023';
  end if;

  -- Serialises with role changes, so the rank check below holds.
  perform 1 from public.circles where id = target_circle_id for no key update;

  if target_user_id = current_user_id then
    raise exception 'You cannot ban yourself' using errcode = '22023';
  end if;

  if not exists (select 1 from public.profiles p where p.id = target_user_id) then
    raise exception 'User not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from public.circles c
    where c.id = target_circle_id
      and c.owner_id = target_user_id
  ) then
    raise exception 'The circle owner cannot be banned' using errcode = '42501';
  end if;

  is_member := exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = target_circle_id
      and cm.user_id = target_user_id
  );

  if is_member
    and public.circle_member_rank(target_circle_id, target_user_id)
      >= public.circle_member_rank(target_circle_id, current_user_id)
  then
    raise exception 'Cannot ban a member ranked at or above you'
      using errcode = '42501';
  end if;

  banned_label := public.circle_member_label(target_circle_id, target_user_id);

  insert into public.circle_bans (circle_id, user_id, reason, banned_by)
  values (target_circle_id, target_user_id, trimmed_reason, current_user_id)
  on conflict (circle_id, user_id) do update
  set
    reason = excluded.reason,
    banned_by = excluded.banned_by,
    created_at = now();

  if is_member then
    perform public.remove_circle_member_rows(target_circle_id, target_user_id);
  end if;

  if coalesce(delete_message_hours, 0) > 0 then
    for target in
      select m.*
      from public.messages m
      where m.sender_id = target_user_id
        and m.webhook_id is null
        and m.recalled_at is null
        and m.type <> 'system'
        and m.created_at >= now() - make_interval(hours => delete_message_hours)
        and m.conversation_id in (
          select cc.conversation_id
          from public.circle_channels cc
          where cc.circle_id = target_circle_id
          union all
          select ct.conversation_id
          from public.conversation_threads ct
          join public.circle_channels cc
            on cc.conversation_id = ct.parent_conversation_id
          where cc.circle_id = target_circle_id
        )
      for update of m
    loop
      deleted_count := deleted_count + 1;
      media_bucket := target.attachment->>'bucket';
      media_path := target.attachment->>'path';
      if media_bucket is null
        or media_bucket not in ('chat-images', 'voice-messages')
        or media_path is null
      then
        media_bucket := null;
        media_path := null;
      end if;

      update public.messages m
      set
        recalled_at = now(),
        recalled_by = current_user_id,
        body = '',
        attachment = null,
        reply_preview = null,
        forwarded_from = null,
        mentions = '[]'::jsonb
      where m.id = target.id;

      delete from public.message_mentions mm where mm.message_id = target.id;
      delete from public.message_reactions r where r.message_id = target.id;
      delete from public.message_poll_votes v where v.message_id = target.id;
      delete from public.pinned_messages p where p.message_id = target.id;

      update public.messages m
      set reply_preview = m.reply_preview || jsonb_build_object('body', '')
      where m.reply_to_message_id = target.id
        and jsonb_typeof(m.reply_preview) = 'object';

      if media_path is not null then
        insert into public.recalled_message_media (
          bucket_id,
          object_path,
          message_id,
          deleted_by
        )
        values (media_bucket, media_path, target.id, current_user_id)
        on conflict on constraint recalled_message_media_pkey do update
        set
          message_id = excluded.message_id,
          deleted_by = excluded.deleted_by,
          created_at = now();

        if not exists (
          select 1
          from public.messages m
          where m.attachment->>'path' = media_path
            and m.attachment->>'bucket' = media_bucket
        ) then
          bucket_id := media_bucket;
          object_path := media_path;
          return next;
        end if;
      end if;
    end loop;
  end if;

  perform public.write_circle_audit(
    target_circle_id,
    'member_ban',
    'member',
    target_user_id,
    banned_label,
    jsonb_strip_nulls(jsonb_build_object(
      'reason', trimmed_reason,
      'deleted_messages', nullif(deleted_count, 0)
    ))
  );
end;
$$;

create or replace function public.unban_circle_member(
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
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'ban_members'
  ) then
    raise exception 'Only members who can ban members can unban them'
      using errcode = '42501';
  end if;

  delete from public.circle_bans b
  where b.circle_id = target_circle_id
    and b.user_id = target_user_id;

  if not found then
    raise exception 'Ban not found' using errcode = 'P0002';
  end if;

  perform public.write_circle_audit(
    target_circle_id,
    'member_unban',
    'member',
    target_user_id,
    public.circle_member_label(target_circle_id, target_user_id),
    '{}'::jsonb
  );
end;
$$;

create or replace function public.list_circle_bans(target_circle_id uuid)
returns table (
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  reason text,
  banned_by_name text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.current_user_has_circle_permission(
    target_circle_id,
    'ban_members'
  ) then
    raise exception 'Only members who can ban members can see bans'
      using errcode = '42501';
  end if;

  return query
  select
    b.user_id,
    p.username,
    p.display_name,
    p.avatar_url,
    b.reason,
    case
      when b.banned_by is null then null
      else public.circle_member_label(target_circle_id, b.banned_by)
    end,
    b.created_at
  from public.circle_bans b
  join public.profiles p on p.id = b.user_id
  where b.circle_id = target_circle_id
  order by b.created_at desc;
end;
$$;

-- Times a member out for up to 28 days; 0 (or null) seconds ends it.
-- Returns when the timeout ends, or null once removed.
create or replace function public.timeout_circle_member(
  target_circle_id uuid,
  target_user_id uuid,
  duration_seconds integer
)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  seconds integer := coalesce(duration_seconds, 0);
  ends_at timestamptz;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'moderate_members'
  ) then
    raise exception 'Only members who can time out members can do that'
      using errcode = '42501';
  end if;

  if seconds < 0 or seconds > 2419200 then
    raise exception 'Timeouts last up to 28 days' using errcode = '22023';
  end if;

  perform 1 from public.circles where id = target_circle_id for no key update;

  if target_user_id = current_user_id then
    raise exception 'You cannot time yourself out' using errcode = '22023';
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
    raise exception 'The circle owner cannot be timed out'
      using errcode = '42501';
  end if;

  if public.circle_member_rank(target_circle_id, target_user_id)
    >= public.circle_member_rank(target_circle_id, current_user_id)
  then
    raise exception 'Cannot time out a member ranked at or above you'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.circle_roles r
    where r.circle_id = target_circle_id
      and r.permissions & 16384 <> 0
      and (
        r.is_default
        or exists (
          select 1
          from public.circle_member_roles mr
          where mr.circle_id = target_circle_id
            and mr.user_id = target_user_id
            and mr.role_id = r.id
        )
      )
  ) then
    raise exception 'Administrators cannot be timed out' using errcode = '42501';
  end if;

  ends_at := case when seconds = 0 then null else now() + make_interval(secs => seconds) end;

  update public.circle_members cm
  set timed_out_until = ends_at
  where cm.circle_id = target_circle_id
    and cm.user_id = target_user_id;

  if ends_at is not null then
    delete from public.voice_states vs
    where vs.circle_id = target_circle_id
      and vs.user_id = target_user_id;
  end if;

  perform public.write_circle_audit(
    target_circle_id,
    case when ends_at is null then 'member_timeout_remove' else 'member_timeout' end,
    'member',
    target_user_id,
    public.circle_member_label(target_circle_id, target_user_id),
    case
      when ends_at is null then '{}'::jsonb
      else jsonb_build_object('until', ends_at, 'seconds', seconds)
    end
  );

  return ends_at;
end;
$$;

-- Reactions and poll votes don't go through send_messages, so timed-out
-- members are stopped here.
create or replace function public.reject_timed_out_member_action()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.circle_channels cc
    join public.circle_members cm
      on cm.circle_id = cc.circle_id
      and cm.user_id = new.user_id
    where cc.id = public.conversation_circle_channel_id(new.conversation_id)
      and cm.timed_out_until > now()
  ) then
    raise exception 'You are timed out in this circle' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function public.reject_timed_out_member_action() from public;

drop trigger if exists message_reactions_reject_timed_out on public.message_reactions;
create trigger message_reactions_reject_timed_out
  before insert on public.message_reactions
  for each row execute function public.reject_timed_out_member_action();

drop trigger if exists message_poll_votes_reject_timed_out on public.message_poll_votes;
create trigger message_poll_votes_reject_timed_out
  before insert on public.message_poll_votes
  for each row execute function public.reject_timed_out_member_action();

-- Same as 202610130020_forum_channels, plus each member's timeout.
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
          'timed_out_until', case
            when cm.timed_out_until > now() then cm.timed_out_until
          end,
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
          ),
          'slowmode_seconds', cc.slowmode_seconds,
          'topic', cc.topic,
          'kind', cc.kind,
          'tags', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', ft.id,
                'channel_id', ft.channel_id,
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

revoke execute on function public.ban_circle_member(uuid, uuid, text, integer) from public;
revoke execute on function public.ban_circle_member(uuid, uuid, text, integer) from anon;
grant execute on function public.ban_circle_member(uuid, uuid, text, integer) to authenticated;
revoke execute on function public.unban_circle_member(uuid, uuid) from public;
revoke execute on function public.unban_circle_member(uuid, uuid) from anon;
grant execute on function public.unban_circle_member(uuid, uuid) to authenticated;
revoke execute on function public.list_circle_bans(uuid) from public;
revoke execute on function public.list_circle_bans(uuid) from anon;
grant execute on function public.list_circle_bans(uuid) to authenticated;
revoke execute on function public.timeout_circle_member(uuid, uuid, integer) from public;
revoke execute on function public.timeout_circle_member(uuid, uuid, integer) from anon;
grant execute on function public.timeout_circle_member(uuid, uuid, integer) to authenticated;
