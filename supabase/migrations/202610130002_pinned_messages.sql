-- System messages ("X pinned a message") are written only by security definer
-- RPCs, never directly by clients.
alter table public.messages
  drop constraint if exists messages_type_check;

alter table public.messages
  add constraint messages_type_check
  check (type in ('text', 'image', 'file', 'voice', 'system'));

drop policy if exists messages_insert_member on public.messages;

create policy messages_insert_member
  on public.messages for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and type <> 'system'
    and forwarded_from is null
    and public.is_current_user_conversation_member(conversation_id)
    and not public.is_current_user_blocked_in_conversation(conversation_id)
  );

create table if not exists public.pinned_messages (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  message_id uuid not null references public.messages(id) on delete cascade,
  pinned_by uuid references public.profiles(id) on delete set null,
  pinned_at timestamptz not null default now(),
  primary key (conversation_id, message_id),
  constraint pinned_messages_message_unique unique (message_id)
);

create index if not exists pinned_messages_conversation_pinned_at_idx
  on public.pinned_messages (conversation_id, pinned_at desc);

-- Realtime matches DELETE events against the old row, so keep conversation_id
-- in it to let an open thread filter unpins by conversation.
alter table public.pinned_messages replica identity full;

alter table public.pinned_messages enable row level security;

create policy pinned_messages_select_member
  on public.pinned_messages for select
  to authenticated
  using (public.is_current_user_conversation_member(conversation_id));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pinned_messages'
  ) then
    alter publication supabase_realtime add table public.pinned_messages;
  end if;
end $$;

-- Direct chats: both members. Groups: the group owner. Circle channels: the
-- circle owner or an admin (moves to manage_messages with custom roles).
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
            join public.circle_members circle_member
              on circle_member.circle_id = ch.circle_id
            where ch.conversation_id = c.id
              and circle_member.user_id = auth.uid()
              and circle_member.role in ('owner', 'admin')
          )
        else false
      end
      from public.conversations c
      where c.id = target_conversation_id
    ),
    false
  );
$$;

-- PostgREST computed field: `messages?select=*,is_pinned`.
create or replace function public.is_pinned(message_row public.messages)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.pinned_messages pm
    where pm.message_id = message_row.id
      and public.is_current_user_conversation_member(pm.conversation_id)
  );
$$;

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

  return true;
end;
$$;

create or replace function public.unpin_message(target_message_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_conversation_id uuid;
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

  return found;
end;
$$;

create or replace function public.list_pinned_messages(
  target_conversation_id uuid
)
returns table (
  message jsonb,
  sender jsonb,
  pinned_by uuid,
  pinned_by_name text,
  pinned_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null
    or not public.is_current_user_conversation_member(target_conversation_id)
  then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  return query
  select
    to_jsonb(m) || jsonb_build_object('is_pinned', true) as message,
    jsonb_build_object(
      'id', sender_profile.id,
      'username', sender_profile.username,
      'display_name', sender_profile.display_name,
      'alias', sender_alias.alias,
      'avatar_url', sender_profile.avatar_url,
      'bio', sender_profile.bio,
      'created_at', sender_profile.created_at,
      'updated_at', sender_profile.updated_at
    ) as sender,
    pm.pinned_by,
    coalesce(pinner_alias.alias, pinner.display_name) as pinned_by_name,
    pm.pinned_at
  from public.pinned_messages pm
  join public.messages m on m.id = pm.message_id
  join public.profiles sender_profile on sender_profile.id = m.sender_id
  left join public.contact_aliases sender_alias
    on sender_alias.owner_id = auth.uid()
    and sender_alias.friend_id = sender_profile.id
  left join public.profiles pinner on pinner.id = pm.pinned_by
  left join public.contact_aliases pinner_alias
    on pinner_alias.owner_id = auth.uid()
    and pinner_alias.friend_id = pinner.id
  where pm.conversation_id = target_conversation_id
    and m.recalled_at is null
  order by pm.pinned_at desc, m.id;
end;
$$;

-- System messages cannot be forwarded: they would be re-sent as the
-- forwarder's own system notice.
create or replace function public.forward_message(
  source_message_id uuid,
  target_conversation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  source_message public.messages%rowtype;
  source_sender_name text;
  created_message_id uuid;
begin
  select *
  into source_message
  from public.messages
  where id = source_message_id
    and recalled_at is null
    and type <> 'system';

  if source_message.id is null
    or not public.is_current_user_conversation_member(source_message.conversation_id)
    or not public.is_current_user_conversation_member(target_conversation_id)
    or public.is_current_user_blocked_in_conversation(target_conversation_id)
  then
    raise exception 'Message cannot be forwarded' using errcode = '42501';
  end if;

  select display_name
  into source_sender_name
  from public.profiles
  where id = source_message.sender_id;

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    attachment,
    forwarded_from
  )
  values (
    target_conversation_id,
    auth.uid(),
    source_message.type,
    source_message.body,
    source_message.attachment,
    jsonb_build_object(
      'message_id', source_message.id,
      'sender_id', source_message.sender_id,
      'sender_name', source_sender_name,
      'type', source_message.type,
      'body', source_message.body,
      'source_attachment_bucket', source_message.attachment->>'bucket',
      'source_attachment_path', source_message.attachment->>'path'
    )
  )
  returning id into created_message_id;

  return created_message_id;
end;
$$;

-- Global search skips system notices such as "X pinned a message."
create or replace function public.search_messages(
  search_query text
)
returns table (
  message_id uuid,
  conversation_id uuid,
  conversation_title text,
  sender_id uuid,
  sender_name text,
  body text,
  type text,
  created_at timestamptz,
  rank real
)
language sql
stable
security definer
set search_path = public
as $$
  select
    m.id,
    m.conversation_id,
    coalesce(c.title, peer.display_name) as conversation_title,
    m.sender_id,
    sender.display_name as sender_name,
    m.body,
    m.type,
    m.created_at,
    ts_rank(
      to_tsvector('simple', m.body),
      websearch_to_tsquery('simple', trim(search_query))
    ) as rank
  from public.messages m
  join public.conversations c on c.id = m.conversation_id
  join public.profiles sender on sender.id = m.sender_id
  left join public.conversation_members direct_peer_membership
    on direct_peer_membership.conversation_id = c.id
    and direct_peer_membership.user_id <> auth.uid()
    and c.type = 'direct'
  left join public.profiles peer on peer.id = direct_peer_membership.user_id
  where trim(search_query) <> ''
    and m.recalled_at is null
    and m.type <> 'system'
    and public.is_current_user_conversation_member(m.conversation_id)
    and to_tsvector('simple', m.body)
      @@ websearch_to_tsquery('simple', trim(search_query))
  order by rank desc, m.created_at desc
  limit 50;
$$;

grant execute on function public.can_current_user_pin_messages(uuid) to authenticated;
grant execute on function public.is_pinned(public.messages) to authenticated;
grant execute on function public.pin_message(uuid) to authenticated;
grant execute on function public.unpin_message(uuid) to authenticated;
grant execute on function public.list_pinned_messages(uuid) to authenticated;
