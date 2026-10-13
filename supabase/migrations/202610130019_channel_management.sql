-- Channel management, like Discord's channel overview: members with
-- manage_channels (who can see the channel) rename it, set its topic or
-- delete it.
--
-- * circle_channels.topic: optional text (at most 1024 characters) shown
--   under the channel name.
-- * circle_channels.kind: 'text' for every channel so far; 'forum' and
--   'voice' are reserved for later items. create_circle_channel takes an
--   optional target_kind (only 'text' for now), so existing callers keep
--   working.
-- * update_circle_channel(target_channel_id, channel_name, channel_topic):
--   renames the channel (and its conversation) and sets or clears the
--   topic. Logged as channel_update with the changed fields; calls that
--   change nothing are not logged.
-- * delete_circle_channel(target_channel_id): deletes the channel's
--   conversation, which cascades to the channel row, its messages,
--   members, overwrites and threads (each thread row deletes its own
--   conversation). Logged as channel_delete. Any channel may be deleted,
--   the last one included; clients show a circle without channels.
-- * get_circle_detail returns each channel's topic and kind.
--
-- circle_channels gets replica identity full, so realtime DELETE events
-- carry circle_id and reach the circle's subscribers, who then reload.

alter table public.circle_channels
  add column if not exists topic text;

alter table public.circle_channels
  drop constraint if exists circle_channels_topic_length;
alter table public.circle_channels
  add constraint circle_channels_topic_length
  check (topic is null or char_length(topic) between 1 and 1024);

alter table public.circle_channels
  add column if not exists kind text not null default 'text';

alter table public.circle_channels
  drop constraint if exists circle_channels_kind_check;
alter table public.circle_channels
  add constraint circle_channels_kind_check
  check (kind in ('text', 'voice', 'forum'));

alter table public.circle_channels replica identity full;

-- Same as 202610130018_circle_audit_log, plus the channel's kind. Only text
-- channels can be created for now.
drop function if exists public.create_circle_channel(uuid, text, uuid);

create or replace function public.create_circle_channel(
  target_circle_id uuid,
  channel_name text,
  target_category_id uuid default null,
  target_kind text default 'text'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_name text := trim(coalesce(channel_name, ''));
  channel_kind text := coalesce(target_kind, 'text');
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

  if channel_kind <> 'text' then
    raise exception 'Unsupported channel type' using errcode = '22023';
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
    created_by,
    kind
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
    current_user_id,
    channel_kind
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
      'kind', channel_kind,
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

-- Renames a channel and sets its topic (null or blank clears it). Needs
-- manage_channels and access to the channel.
create or replace function public.update_circle_channel(
  target_channel_id uuid,
  channel_name text,
  channel_topic text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_name text := trim(coalesce(channel_name, ''));
  trimmed_topic text := nullif(btrim(coalesce(channel_topic, '')), '');
  channel public.circle_channels%rowtype;
  audit_changes jsonb := '{}'::jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_name) = 0 or char_length(trimmed_name) > 48 then
    raise exception 'Channel name must be between 1 and 48 characters'
      using errcode = '22023';
  end if;

  if trimmed_topic is not null and char_length(trimmed_topic) > 1024 then
    raise exception 'Channel topic must be at most 1024 characters'
      using errcode = '22023';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id
  for update;

  if channel.id is null
    or not public.current_user_has_circle_permission(
      channel.circle_id,
      'manage_channels'
    )
    or not public.current_user_has_channel_permission(
      target_channel_id,
      'view_channel'
    )
  then
    raise exception 'Only members who can manage channels can edit channels'
      using errcode = '42501';
  end if;

  if channel.name is distinct from trimmed_name then
    audit_changes := audit_changes || jsonb_build_object(
      'name',
      jsonb_build_object('old', channel.name, 'new', trimmed_name)
    );
  end if;

  if channel.topic is distinct from trimmed_topic then
    audit_changes := audit_changes || jsonb_build_object(
      'topic',
      jsonb_build_object('old', channel.topic, 'new', trimmed_topic)
    );
  end if;

  if audit_changes = '{}'::jsonb then
    return;
  end if;

  update public.circle_channels cc
  set name = trimmed_name,
      topic = trimmed_topic,
      updated_at = now()
  where cc.id = target_channel_id;

  update public.conversations c
  set title = trimmed_name
  where c.id = channel.conversation_id
    and c.title is distinct from trimmed_name;

  perform public.write_circle_audit(
    channel.circle_id,
    'channel_update',
    'channel',
    channel.id,
    trimmed_name,
    audit_changes
  );
end;
$$;

-- Deletes a channel with its messages and threads. Needs manage_channels
-- and access to the channel.
create or replace function public.delete_circle_channel(target_channel_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  channel public.circle_channels%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel.id is null
    or not public.current_user_has_circle_permission(
      channel.circle_id,
      'manage_channels'
    )
    or not public.current_user_has_channel_permission(
      target_channel_id,
      'view_channel'
    )
  then
    raise exception 'Only members who can manage channels can delete channels'
      using errcode = '42501';
  end if;

  -- Serialize with channel creation and reordering in the circle.
  perform 1 from public.circles c where c.id = channel.circle_id for no key update;

  perform public.write_circle_audit(
    channel.circle_id,
    'channel_delete',
    'channel',
    channel.id,
    channel.name,
    jsonb_build_object(
      'name', channel.name,
      'kind', channel.kind,
      'topic', channel.topic,
      'category_id', channel.category_id,
      'category_name', (
        select ccc.name
        from public.circle_channel_categories ccc
        where ccc.id = channel.category_id
      ),
      'thread_count', (
        select count(*)
        from public.conversation_threads ct
        where ct.parent_conversation_id = channel.conversation_id
      )
    )
  );

  -- Cascades to the channel row, messages, members, overwrites and
  -- threads.
  delete from public.conversations c where c.id = channel.conversation_id;
end;
$$;

-- Same as 202610130015_channel_slowmode, plus each channel's topic and kind.
-- slowmode.
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
          ),
          'slowmode_seconds', cc.slowmode_seconds,
          'topic', cc.topic,
          'kind', cc.kind
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

revoke execute on function public.update_circle_channel(uuid, text, text) from public;
revoke execute on function public.update_circle_channel(uuid, text, text) from anon;
revoke execute on function public.delete_circle_channel(uuid) from public;
revoke execute on function public.delete_circle_channel(uuid) from anon;

grant execute on function public.create_circle_channel(uuid, text, uuid, text) to authenticated;
grant execute on function public.update_circle_channel(uuid, text, text) to authenticated;
grant execute on function public.delete_circle_channel(uuid) to authenticated;
grant execute on function public.get_circle_detail(uuid) to authenticated;
