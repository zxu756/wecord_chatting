-- @here and @role mentions.
--
-- * circle_roles.mentionable: anyone who can send in a channel may mention
--   the role. Otherwise only members with mention_everyone there can, the
--   same permission @here needs. Set with set_circle_role_mentionable
--   (manage_roles, below the caller's highest role, audited).
-- * Mentions in send_text_message may now be {kind: 'here', start, end,
--   user_ids} and {kind: 'role', role_id, start, end}. Presence lives only
--   in Realtime, so the sender's app says who is online for @here; the
--   server keeps those who are members of the conversation and can see it.
--   A role mention reaches every member holding the role who can see the
--   conversation. Mentions the sender may not make stay plain text.
-- * The message keeps {kind: 'here'} and {kind: 'role', role_id,
--   display_name, color} (who was online is not stored); message_mentions
--   gets one row per reached member with kind 'here' or 'role', so unread
--   mention badges, the inbox and push (claim_push_delivery) count them as
--   mentions with no change of their own.
-- * list_conversation_mention_roles(conversation) gives the composer the
--   roles the caller may mention there and whether @here is allowed.

alter table public.circle_roles
  add column if not exists mentionable boolean not null default false;

alter table public.message_mentions
  drop constraint if exists message_mentions_kind_check;
alter table public.message_mentions
  add constraint message_mentions_kind_check
  check (kind in ('user', 'all', 'here', 'role'));

-- Same as 202605180008_social_chat_v3, plus the 'here' and 'role' kinds:
-- a role mention needs a role_id; neither needs a user_id.
create or replace function public.message_mentions_have_valid_shape(
  mentions jsonb
)
returns boolean
language sql
immutable
as $$
  select jsonb_typeof(mentions) = 'array'
    and not exists (
      select 1
      from jsonb_array_elements(mentions) mention
      where jsonb_typeof(mention) <> 'object'
        or (
          coalesce(mention->>'kind', 'user') in ('user', 'all')
          and jsonb_typeof(mention->'user_id') <> 'string'
        )
        or (
          mention->>'kind' = 'role'
          and jsonb_typeof(mention->'role_id') is distinct from 'string'
        )
        or jsonb_typeof(mention->'start') <> 'number'
        or jsonb_typeof(mention->'end') <> 'number'
        or (
          mention ? 'display_name'
          and jsonb_typeof(mention->'display_name') <> 'string'
        )
        or (
          mention ? 'kind'
          and mention->>'kind' not in ('user', 'all', 'here', 'role')
        )
    );
$$;

-- The mentions a message keeps: user mentions of members who can see the
-- conversation, @here when the sender has mention_everyone, and roles of
-- the conversation's circle that are mentionable (or any role with
-- mention_everyone). Role mentions carry the role's current name and
-- colour; @here drops its user_ids.
create or replace function public.resolve_message_mentions(
  target_conversation_id uuid,
  sender_id uuid,
  mentions jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  can_mention_everyone boolean := public.user_has_conversation_channel_permission(
    target_conversation_id,
    sender_id,
    'mention_everyone'
  );
  circle_id_of_channel uuid;
  item record;
  kind text;
  mentioned_role public.circle_roles%rowtype;
  resolved jsonb := '[]'::jsonb;
begin
  select cc.circle_id
  into circle_id_of_channel
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(target_conversation_id);

  for item in
    select value as mention
    from jsonb_array_elements(coalesce(mentions, '[]'::jsonb)) with ordinality
    order by ordinality
  loop
    kind := coalesce(nullif(item.mention->>'kind', ''), 'user');
    if kind = 'here' then
      if can_mention_everyone then
        resolved := resolved || jsonb_build_array(jsonb_build_object(
          'kind', 'here',
          'display_name', 'here',
          'start', item.mention->'start',
          'end', item.mention->'end'
        ));
      end if;
    elsif kind = 'role' then
      mentioned_role := null;
      if circle_id_of_channel is not null
        and coalesce(item.mention->>'role_id', '')
          ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then
        select r.* into mentioned_role
        from public.circle_roles r
        where r.id = (item.mention->>'role_id')::uuid
          and r.circle_id = circle_id_of_channel
          and not r.is_default;
      end if;
      if mentioned_role.id is not null
        and (mentioned_role.mentionable or can_mention_everyone)
      then
        resolved := resolved || jsonb_build_array(jsonb_build_object(
          'kind', 'role',
          'role_id', mentioned_role.id,
          'display_name', mentioned_role.name,
          'color', mentioned_role.color,
          'start', item.mention->'start',
          'end', item.mention->'end'
        ));
      end if;
    elsif (item.mention->>'user_id') is null
      or public.user_has_conversation_channel_permission(
        target_conversation_id,
        (item.mention->>'user_id')::uuid,
        'view_channel'
      )
    then
      resolved := resolved || jsonb_build_array(item.mention);
    end if;
  end loop;

  return resolved;
end;
$$;

-- Records who a sent message mentions in message_mentions: mentioned
-- users, the online members named by @here, and the holders of mentioned
-- roles; only members of the conversation who can see it, never the
-- sender for @here and roles. stored_mentions is what
-- resolve_message_mentions kept; requested_mentions what the sender sent
-- (for @here's user_ids).
create or replace function public.record_message_mentions(
  target_message_id uuid,
  target_conversation_id uuid,
  sender_id uuid,
  requested_mentions jsonb,
  stored_mentions jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.message_mentions (
    message_id,
    conversation_id,
    user_id,
    kind
  )
  select
    target_message_id,
    target_conversation_id,
    (mention->>'user_id')::uuid,
    coalesce(nullif(mention->>'kind', ''), 'user')
  from jsonb_array_elements(stored_mentions) mention
  where coalesce(nullif(mention->>'kind', ''), 'user') in ('user', 'all')
    and (mention->>'user_id') is not null
  on conflict do nothing;

  if exists (
    select 1
    from jsonb_array_elements(stored_mentions) mention
    where mention->>'kind' = 'here'
  ) then
    insert into public.message_mentions (
      message_id,
      conversation_id,
      user_id,
      kind
    )
    select distinct
      target_message_id,
      target_conversation_id,
      cm.user_id,
      'here'
    from jsonb_array_elements(coalesce(requested_mentions, '[]'::jsonb)) mention
    cross join lateral jsonb_array_elements_text(
      case
        when jsonb_typeof(mention->'user_ids') = 'array' then mention->'user_ids'
        else '[]'::jsonb
      end
    ) online(user_id)
    join public.conversation_members cm
      on cm.conversation_id = target_conversation_id
      and cm.user_id::text = lower(online.user_id)
    where mention->>'kind' = 'here'
      and cm.user_id <> sender_id
      and public.user_has_conversation_channel_permission(
        target_conversation_id,
        cm.user_id,
        'view_channel'
      )
    on conflict do nothing;
  end if;

  insert into public.message_mentions (
    message_id,
    conversation_id,
    user_id,
    kind
  )
  select distinct
    target_message_id,
    target_conversation_id,
    cm.user_id,
    'role'
  from jsonb_array_elements(stored_mentions) mention
  join public.circle_member_roles mr
    on mr.role_id = (mention->>'role_id')::uuid
  join public.conversation_members cm
    on cm.conversation_id = target_conversation_id
    and cm.user_id = mr.user_id
  where mention->>'kind' = 'role'
    and cm.user_id <> sender_id
    and public.user_has_conversation_channel_permission(
      target_conversation_id,
      cm.user_id,
      'view_channel'
    )
  on conflict do nothing;
end;
$$;

revoke execute on function public.resolve_message_mentions(uuid, uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.record_message_mentions(uuid, uuid, uuid, jsonb, jsonb) from public, anon, authenticated;

-- Same as 202610130016_channel_permission_fixes, but mentions go through
-- resolve_message_mentions and record_message_mentions, so @here and role
-- mentions reach their members.
create or replace function public.send_text_message(
  target_conversation_id uuid,
  body text,
  reply_to_message_id uuid default null,
  reply_preview jsonb default null,
  mentions jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_body text := trim(coalesce(body, ''));
  visible_mentions jsonb;
  created_message_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_body) = 0 then
    raise exception 'Message body is required' using errcode = '22023';
  end if;

  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Cannot send messages in this conversation'
      using errcode = '42501';
  end if;

  if send_text_message.reply_to_message_id is not null and not exists (
    select 1
    from public.messages m
    where m.id = send_text_message.reply_to_message_id
      and m.conversation_id = target_conversation_id
  ) then
    raise exception 'Reply message does not belong to conversation'
      using errcode = '22023';
  end if;

  if jsonb_typeof(coalesce(mentions, '[]'::jsonb)) <> 'array' then
    raise exception 'mentions must be an array' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(mentions, '[]'::jsonb)) mention
    where coalesce(nullif(mention->>'kind', ''), 'user') in ('user', 'all')
      and (mention->>'user_id') is not null
      and not exists (
        select 1
        from public.conversation_members cm
        where cm.conversation_id = target_conversation_id
          and cm.user_id = (mention->>'user_id')::uuid
      )
  ) then
    raise exception 'mentioned users must be conversation members'
      using errcode = '42501';
  end if;

  visible_mentions := public.resolve_message_mentions(
    target_conversation_id,
    current_user_id,
    mentions
  );

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    reply_to_message_id,
    reply_preview,
    mentions
  )
  values (
    target_conversation_id,
    current_user_id,
    'text',
    trimmed_body,
    send_text_message.reply_to_message_id,
    send_text_message.reply_preview,
    visible_mentions
  )
  returning id into created_message_id;

  perform public.record_message_mentions(
    created_message_id,
    target_conversation_id,
    current_user_id,
    mentions,
    visible_mentions
  );

  return created_message_id;
end;
$$;

-- The roles the caller may mention in a conversation (mentionable ones, or
-- all of the circle's roles with mention_everyone), highest first, and
-- whether they may use @here. Outside circle channels there are no roles
-- and @here is allowed.
create or replace function public.list_conversation_mention_roles(
  target_conversation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  can_mention_everyone boolean;
  circle_id_of_channel uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  can_mention_everyone := public.user_has_conversation_channel_permission(
    target_conversation_id,
    current_user_id,
    'mention_everyone'
  );

  select cc.circle_id
  into circle_id_of_channel
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(target_conversation_id);

  return jsonb_build_object(
    'can_mention_everyone', can_mention_everyone,
    'roles', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', r.id,
          'name', r.name,
          'color', r.color,
          'mentionable', r.mentionable
        )
        order by r.position desc
      )
      from public.circle_roles r
      where r.circle_id = circle_id_of_channel
        and not r.is_default
        and (r.mentionable or can_mention_everyone)
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.list_conversation_mention_roles(uuid) from public, anon;
grant execute on function public.list_conversation_mention_roles(uuid) to authenticated;

-- Lets anyone (true) or only members with mention_everyone (false) mention
-- a role. Same rules as update_circle_role (202610130018_circle_audit_log):
-- manage_roles, and only roles below the caller's highest one; audited as
-- a role update.
create or replace function public.set_circle_role_mentionable(
  target_role_id uuid,
  is_mentionable boolean
)
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
    raise exception 'The default role cannot be mentioned' using errcode = '22023';
  end if;

  perform 1 from public.circles where id = target_role.circle_id for no key update;

  select r.* into target_role
  from public.circle_roles r
  where r.id = target_role_id;

  if target_role.position
    >= public.circle_member_rank(target_role.circle_id, current_user_id)
  then
    raise exception 'Cannot edit a role at or above your highest role'
      using errcode = '42501';
  end if;

  if target_role.mentionable = coalesce(is_mentionable, false) then
    return;
  end if;

  update public.circle_roles
  set mentionable = coalesce(is_mentionable, false)
  where id = target_role_id;

  perform public.write_circle_audit(
    target_role.circle_id,
    'role_update',
    'role',
    target_role_id,
    target_role.name,
    jsonb_build_object(
      'mentionable',
      jsonb_build_object(
        'old', target_role.mentionable,
        'new', coalesce(is_mentionable, false)
      )
    )
  );
end;
$$;

revoke execute on function public.set_circle_role_mentionable(uuid, boolean) from public, anon;
grant execute on function public.set_circle_role_mentionable(uuid, boolean) to authenticated;

-- Same as 202610140001_inbox, but @here and role mentions get their own
-- reasons instead of reading as @all.
create or replace function public.list_inbox(p_limit integer default 50)
returns table (
  message_id uuid,
  conversation_id uuid,
  sender_id uuid,
  sender_display_name text,
  sender_avatar_url text,
  webhook_name text,
  body text,
  type text,
  created_at timestamptz,
  reason text,
  is_unread boolean
)
language sql
stable
security invoker
set search_path = public
as $$
  with since as (
    select now() - interval '30 days' as at
  ),
  mentioned as (
    select
      mm.message_id,
      case
        when bool_or(mm.kind = 'user') then 'mention'
        when bool_or(mm.kind = 'role') then 'mention_role'
        when bool_or(mm.kind = 'here') then 'mention_here'
        else 'mention_all'
      end as reason
    from public.message_mentions mm, since
    where mm.user_id = auth.uid()
      and mm.created_at > since.at
    group by mm.message_id
  ),
  replied as (
    select reply.id as message_id, 'reply'::text as reason
    from public.messages parent
    join public.messages reply on reply.reply_to_message_id = parent.id
    cross join since
    where parent.sender_id = auth.uid()
      and reply.created_at > since.at
  ),
  -- A reply that also mentions the user is listed once, as a mention.
  hits as (
    select distinct on (message_id) message_id, reason
    from (
      select message_id, reason, 0 as rank from mentioned
      union all
      select message_id, reason, 1 as rank from replied
    ) candidates
    order by message_id, rank
  )
  select
    m.id,
    m.conversation_id,
    m.sender_id,
    p.display_name,
    p.avatar_url,
    m.webhook_name,
    m.body,
    m.type,
    m.created_at,
    hits.reason,
    m.created_at > coalesce(last_read.created_at, '-infinity'::timestamptz)
  from hits
  join public.messages m on m.id = hits.message_id
  join public.profiles p on p.id = m.sender_id
  join public.conversation_members cm
    on cm.conversation_id = m.conversation_id
   and cm.user_id = auth.uid()
  left join public.messages last_read on last_read.id = cm.last_read_message_id
  where m.sender_id <> auth.uid()
    and m.recalled_at is null
    and m.type <> 'system'
  order by m.created_at desc, m.id desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

revoke execute on function public.list_inbox(integer) from public;
revoke execute on function public.list_inbox(integer) from anon;
grant execute on function public.list_inbox(integer) to authenticated;
