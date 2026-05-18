alter table public.conversations
  add column if not exists announcement text not null default '';

alter table public.conversation_members
  add column if not exists hidden_at timestamptz,
  add column if not exists manual_unread_at timestamptz;

alter table public.messages
  add column if not exists mentions jsonb not null default '[]'::jsonb;

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
        or jsonb_typeof(mention->'user_id') <> 'string'
        or jsonb_typeof(mention->'start') <> 'number'
        or jsonb_typeof(mention->'end') <> 'number'
        or (
          mention ? 'display_name'
          and jsonb_typeof(mention->'display_name') <> 'string'
        )
        or (
          mention ? 'kind'
          and mention->>'kind' not in ('user', 'all')
        )
    );
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'message_mentions_is_array'
      and conrelid = 'public.messages'::regclass
  ) then
    alter table public.messages
      add constraint message_mentions_is_array
      check (jsonb_typeof(mentions) = 'array');
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'message_mentions_have_valid_shape'
      and conrelid = 'public.messages'::regclass
  ) then
    alter table public.messages
      add constraint message_mentions_have_valid_shape
      check (public.message_mentions_have_valid_shape(mentions));
  end if;
end;
$$;

create table if not exists public.message_mentions (
  message_id uuid not null references public.messages(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null default 'user' check (kind in ('user', 'all')),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, kind)
);

alter table public.message_mentions enable row level security;

drop policy if exists message_mentions_select_member on public.message_mentions;

create policy message_mentions_select_member
  on public.message_mentions for select
  to authenticated
  using (public.is_current_user_conversation_member(conversation_id));

drop function if exists public.list_conversation_summaries();

create or replace function public.list_conversation_summaries()
returns table (
  id uuid,
  type text,
  title text,
  avatar_url text,
  announcement text,
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
  mentioned_user_ids uuid[]
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
  ),
  read_markers as (
    select cm.conversation_id, rm.created_at as last_read_at
    from current_memberships cm
    left join public.messages rm on rm.id = cm.last_read_message_id
  ),
  direct_profiles as (
    select cm.conversation_id, p.display_name, p.avatar_url
    from public.conversation_members cm
    join public.profiles p on p.id = cm.user_id
    where cm.user_id <> auth.uid()
  ),
  member_counts as (
    select cm.conversation_id, count(*) as member_count
    from public.conversation_members cm
    group by cm.conversation_id
  ),
  unread_mentions as (
    select m.conversation_id, array_agg(distinct mm.user_id) as mentioned_user_ids
    from current_memberships cm
    left join read_markers rm on rm.conversation_id = cm.conversation_id
    join public.messages m on m.conversation_id = cm.conversation_id
      and m.sender_id <> auth.uid()
      and (
        rm.last_read_at is null
        or m.created_at > rm.last_read_at
      )
    join public.message_mentions mm on mm.message_id = m.id
    group by m.conversation_id
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
    coalesce(um.mentioned_user_ids, lmm.mentioned_user_ids, array[]::uuid[]) as mentioned_user_ids
  from public.conversations c
  join current_memberships cm on cm.conversation_id = c.id
  left join read_markers rm on rm.conversation_id = c.id
  left join direct_profiles dp on dp.conversation_id = c.id and c.type = 'direct'
  left join member_counts mc on mc.conversation_id = c.id
  left join public.messages last_message on last_message.id = c.last_message_id
  left join unread_mentions um on um.conversation_id = c.id
  left join last_message_mentions lmm on lmm.message_id = last_message.id
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
    dp.display_name,
    dp.avatar_url,
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
    um.mentioned_user_ids,
    lmm.mentioned_user_ids
  order by
    cm.pinned_at desc nulls last,
    c.last_message_at desc nulls last,
    c.updated_at desc;
$$;

create or replace function public.set_conversation_pinned(
  target_conversation_id uuid,
  pinned boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.conversation_members
  set pinned_at = case when pinned then now() else null end
  where conversation_id = target_conversation_id
    and user_id = auth.uid();
end;
$$;

create or replace function public.set_conversation_muted(
  target_conversation_id uuid,
  muted boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.conversation_members
  set muted_until = case when muted then now() + interval '100 years' else null end
  where conversation_id = target_conversation_id
    and user_id = auth.uid();
end;
$$;

create or replace function public.mark_conversation_unread(
  target_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  update public.conversation_members
  set manual_unread_at = now()
  where conversation_id = target_conversation_id
    and user_id = auth.uid();
end;
$$;

create or replace function public.hide_conversation(
  target_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  update public.conversation_members
  set hidden_at = now()
  where conversation_id = target_conversation_id
    and user_id = auth.uid();
end;
$$;

create or replace function public.mark_conversation_read(
  target_conversation_id uuid,
  target_message_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  if target_message_id is not null and not exists (
    select 1
    from public.messages m
    where m.id = target_message_id
      and m.conversation_id = target_conversation_id
  ) then
    raise exception 'Read marker message does not belong to conversation'
      using errcode = '22023';
  end if;

  update public.conversation_members
  set
    last_read_message_id = target_message_id,
    manual_unread_at = null
  where conversation_id = target_conversation_id
    and user_id = auth.uid();
end;
$$;

create or replace function public.get_or_create_direct_conversation(other_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  low_user_id uuid;
  high_user_id uuid;
  existing_conversation_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if other_user_id is null or other_user_id = current_user_id then
    raise exception 'A direct conversation requires another user'
      using errcode = '22023';
  end if;

  low_user_id = least(current_user_id, other_user_id);
  high_user_id = greatest(current_user_id, other_user_id);

  if not exists (
    select 1
    from public.friendships
    where user_low_id = low_user_id
      and user_high_id = high_user_id
  ) then
    raise exception 'Users must be friends to start a direct conversation'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    ('x' || substr(md5(low_user_id::text || high_user_id::text), 1, 16))::bit(64)::bigint
  );

  select c.id into existing_conversation_id
  from public.conversations c
  where c.type = 'direct'
    and exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = c.id
        and cm.user_id = current_user_id
    )
    and exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = c.id
        and cm.user_id = other_user_id
    )
    and (
      select count(*)
      from public.conversation_members cm
      where cm.conversation_id = c.id
    ) = 2
  order by c.created_at
  limit 1;

  if existing_conversation_id is not null then
    update public.conversation_members
    set hidden_at = null
    where conversation_id = existing_conversation_id
      and user_id = current_user_id;

    return existing_conversation_id;
  end if;

  insert into public.conversations (type)
  values ('direct')
  returning id into existing_conversation_id;

  insert into public.conversation_members (conversation_id, user_id)
  values
    (existing_conversation_id, current_user_id),
    (existing_conversation_id, other_user_id);

  return existing_conversation_id;
end;
$$;

create or replace function public.update_group_profile(
  target_conversation_id uuid,
  group_title text,
  avatar_url text,
  announcement text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  trimmed_title text := trim(coalesce(group_title, ''));
  updated_conversation_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_title) = 0 then
    raise exception 'Group title is required' using errcode = '22023';
  end if;

  update public.conversations c
  set
    title = trimmed_title,
    avatar_url = update_group_profile.avatar_url,
    announcement = coalesce(update_group_profile.announcement, '')
  where c.id = target_conversation_id
    and c.type = 'group'
    and exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = c.id
        and cm.user_id = auth.uid()
        and cm.role in ('owner', 'admin')
    )
  returning c.id into updated_conversation_id;

  if updated_conversation_id is null then
    raise exception 'Group conversation not found or cannot be updated'
      using errcode = '42501';
  end if;
end;
$$;

create or replace function public.leave_group_conversation(
  target_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_role text;
  owner_count integer;
  member_count integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cm.role into caller_role
  from public.conversation_members cm
  join public.conversations c on c.id = cm.conversation_id
  where cm.conversation_id = target_conversation_id
    and cm.user_id = auth.uid()
    and c.type = 'group';

  if caller_role is null then
    raise exception 'Group conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  select count(*) into owner_count
  from public.conversation_members
  where conversation_id = target_conversation_id
    and role = 'owner';

  select count(*) into member_count
  from public.conversation_members
  where conversation_id = target_conversation_id;

  if caller_role = 'owner' and owner_count = 1 and member_count > 1 then
    raise exception 'Sole owner cannot leave while other members remain'
      using errcode = '42501';
  end if;

  delete from public.conversation_members
  where conversation_id = target_conversation_id
    and user_id = auth.uid();
end;
$$;

create or replace function public.remove_group_member(
  target_conversation_id uuid,
  target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text;
  target_role text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if target_user_id = auth.uid() then
    raise exception 'Use leave_group_conversation to leave a group'
      using errcode = '22023';
  end if;

  select actor.role into actor_role
  from public.conversation_members actor
  join public.conversations c on c.id = actor.conversation_id
  where actor.conversation_id = target_conversation_id
    and actor.user_id = auth.uid()
    and c.type = 'group';

  select target.role into target_role
  from public.conversation_members target
  where target.conversation_id = target_conversation_id
    and target.user_id = target_user_id;

  if target_role is null then
    raise exception 'Target member not found' using errcode = '42501';
  end if;

  -- Permission contract: actor.role = 'owner'
  -- Permission contract: actor.role = 'admin'
  if not (
    actor_role = 'owner'
    or (actor_role = 'admin' and target_role = 'member')
  ) then
    raise exception 'Caller cannot remove this group member'
      using errcode = '42501';
  end if;

  delete from public.conversation_members
  where conversation_id = target_conversation_id
    and user_id = target_user_id;
end;
$$;

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

  if reply_to_message_id is not null and not exists (
    select 1
    from public.messages m
    where m.id = reply_to_message_id
      and m.conversation_id = target_conversation_id
  ) then
    raise exception 'Reply message does not belong to conversation'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(mentions, '[]'::jsonb)) mention
    where (mention->>'user_id') is not null
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
    reply_to_message_id,
    reply_preview,
    coalesce(mentions, '[]'::jsonb)
  )
  returning id into created_message_id;

  insert into public.message_mentions (
    message_id,
    conversation_id,
    user_id,
    kind
  )
  select
    created_message_id,
    target_conversation_id,
    (mention->>'user_id')::uuid,
    coalesce(nullif(mention->>'kind', ''), 'user')
  from jsonb_array_elements(coalesce(mentions, '[]'::jsonb)) mention
  where (mention->>'user_id') is not null
  on conflict do nothing;

  return created_message_id;
end;
$$;

insert into storage.buckets (id, name, public)
values ('group-avatars', 'group-avatars', false)
on conflict (id) do update
set public = false;

drop policy if exists group_avatars_select_member on storage.objects;

create policy group_avatars_select_member
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'group-avatars'
    and public.is_current_user_conversation_member(
      ((storage.foldername(name))[1])::uuid
    )
  );

drop policy if exists group_avatars_insert_admin on storage.objects;

create policy group_avatars_insert_admin
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'group-avatars'
    and exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = ((storage.foldername(name))[1])::uuid
        and cm.user_id = auth.uid()
        and cm.role in ('owner', 'admin')
    )
  );
