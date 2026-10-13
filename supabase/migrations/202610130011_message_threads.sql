-- Threads: side conversations branching off a channel or group message (or
-- standalone, without a root message). Each thread is its own conversation
-- with type 'thread', so messages, reactions, pins, read markers, typing and
-- unread counts work exactly as in any other conversation.
--
-- Membership is materialized: a thread's conversation_members are the parent
-- conversation's members, copied when the thread is created and kept in sync
-- by triggers on the parent's conversation_members (joining the parent adds
-- you to all its threads, leaving removes you). Every existing access check
-- (messages RLS, is_current_user_conversation_member, mark_conversation_read,
-- list_conversation_summaries, ...) therefore applies to threads unchanged,
-- and each member gets their own read marker in the thread.
alter table public.conversations
  drop constraint if exists conversations_type_check;
alter table public.conversations
  add constraint conversations_type_check
  check (type in ('direct', 'group', 'channel', 'thread'));

create table if not exists public.conversation_threads (
  id uuid primary key default gen_random_uuid(),
  parent_conversation_id uuid not null
    references public.conversations(id) on delete cascade,
  root_message_id uuid references public.messages(id) on delete set null,
  conversation_id uuid not null unique
    references public.conversations(id) on delete cascade,
  title text not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  archived_at timestamptz,
  last_message_at timestamptz,
  constraint conversation_threads_title_length check (
    title = btrim(title) and char_length(title) between 1 and 100
  ),
  constraint conversation_threads_not_self
    check (parent_conversation_id <> conversation_id)
);

-- One thread per root message.
create unique index if not exists conversation_threads_root_message_idx
  on public.conversation_threads (root_message_id)
  where root_message_id is not null;

create index if not exists conversation_threads_parent_idx
  on public.conversation_threads (parent_conversation_id, last_message_at desc);

alter table public.conversation_threads enable row level security;

drop policy if exists conversation_threads_select_member on public.conversation_threads;
create policy conversation_threads_select_member
  on public.conversation_threads for select
  to authenticated
  using (public.is_current_user_conversation_member(parent_conversation_id));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'conversation_threads'
  ) then
    alter publication supabase_realtime add table public.conversation_threads;
  end if;
end $$;

-- Joining a parent conversation joins all of its threads.
create or replace function public.sync_thread_members_on_join()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.conversation_members (conversation_id, user_id, role)
  select ct.conversation_id, new.user_id, 'member'
  from public.conversation_threads ct
  where ct.parent_conversation_id = new.conversation_id
  on conflict do nothing;

  return new;
end;
$$;

-- Leaving a parent conversation leaves all of its threads.
create or replace function public.sync_thread_members_on_leave()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.conversation_members cm
  using public.conversation_threads ct
  where ct.parent_conversation_id = old.conversation_id
    and cm.conversation_id = ct.conversation_id
    and cm.user_id = old.user_id;

  return old;
end;
$$;

revoke execute on function public.sync_thread_members_on_join() from public;
revoke execute on function public.sync_thread_members_on_leave() from public;

drop trigger if exists conversation_members_sync_threads_insert on public.conversation_members;
create trigger conversation_members_sync_threads_insert
  after insert on public.conversation_members
  for each row execute function public.sync_thread_members_on_join();

drop trigger if exists conversation_members_sync_threads_delete on public.conversation_members;
create trigger conversation_members_sync_threads_delete
  after delete on public.conversation_members
  for each row execute function public.sync_thread_members_on_leave();

-- Removing a thread row (also when its parent goes away) removes the thread
-- conversation with its messages.
create or replace function public.delete_thread_conversation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.conversations c where c.id = old.conversation_id;
  return old;
end;
$$;

revoke execute on function public.delete_thread_conversation() from public;

drop trigger if exists conversation_threads_delete_conversation on public.conversation_threads;
create trigger conversation_threads_delete_conversation
  after delete on public.conversation_threads
  for each row execute function public.delete_thread_conversation();

-- New thread messages bump the thread's activity (which also tells an open
-- parent conversation, through realtime, to refresh its reply counts) and
-- revive an archived thread.
create or replace function public.touch_thread_from_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversation_threads ct
  set
    last_message_at = new.created_at,
    archived_at = case when new.type = 'system' then ct.archived_at else null end
  where ct.conversation_id = new.conversation_id;

  return new;
end;
$$;

revoke execute on function public.touch_thread_from_message() from public;

drop trigger if exists messages_touch_thread on public.messages;
create trigger messages_touch_thread
  after insert on public.messages
  for each row execute function public.touch_thread_from_message();

-- Thread creators may archive their thread; so may whoever manages the
-- parent: circle owners and admins for channels, group owners and admins
-- for groups. Non-members never can.
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
                and coalesce(public.current_user_circle_role(cc.circle_id), '')
                  in ('owner', 'admin')
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

-- A thread as the client sees it, with reply and unread counts for the
-- current user.
create or replace function public.thread_payload(thread_row public.conversation_threads)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', thread_row.id,
    'conversation_id', thread_row.conversation_id,
    'parent_conversation_id', thread_row.parent_conversation_id,
    'root_message_id', thread_row.root_message_id,
    'title', thread_row.title,
    'created_by', thread_row.created_by,
    'created_at', thread_row.created_at,
    'archived_at', thread_row.archived_at,
    'last_message_at', thread_row.last_message_at,
    'reply_count', (
      select count(*)
      from public.messages m
      where m.conversation_id = thread_row.conversation_id
        and m.type <> 'system'
        and m.recalled_at is null
    ),
    'unread_count', (
      select count(*)
      from public.conversation_members cm
      left join public.messages read_message
        on read_message.id = cm.last_read_message_id
      join public.messages m
        on m.conversation_id = cm.conversation_id
        and m.sender_id <> auth.uid()
        and (
          read_message.created_at is null
          or m.created_at > read_message.created_at
        )
      where cm.conversation_id = thread_row.conversation_id
        and cm.user_id = auth.uid()
    ),
    'can_manage', public.can_current_user_manage_thread(thread_row.id)
  );
$$;

revoke execute on function public.thread_payload(public.conversation_threads) from public;
revoke execute on function public.thread_payload(public.conversation_threads) from anon;
revoke execute on function public.thread_payload(public.conversation_threads) from authenticated;

-- Starts a thread in a channel or group the caller belongs to. With a root
-- message, returns that message's thread if it already has one. The title
-- defaults to the start of the root message.
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

-- The threads of a conversation the caller belongs to, most recently active
-- first.
create or replace function public.list_threads(parent_conversation_id uuid)
returns setof jsonb
language sql
stable
security definer
set search_path = public
as $$
  select public.thread_payload(ct)
  from public.conversation_threads ct
  where ct.parent_conversation_id = list_threads.parent_conversation_id
    and public.is_current_user_conversation_member(
      list_threads.parent_conversation_id
    )
  order by coalesce(ct.last_message_at, ct.created_at) desc, ct.id;
$$;

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
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.can_current_user_manage_thread(target_thread_id) then
    raise exception 'Only the thread creator or a manager can archive it'
      using errcode = '42501';
  end if;

  update public.conversation_threads ct
  set archived_at = case
    when set_thread_archived.archived then coalesce(ct.archived_at, now())
    else null
  end
  where ct.id = target_thread_id
  returning * into updated_thread;

  return public.thread_payload(updated_thread);
end;
$$;

revoke execute on function public.set_thread_archived(uuid, boolean) from public;
revoke execute on function public.set_thread_archived(uuid, boolean) from anon;
revoke execute on function public.set_thread_archived(uuid, boolean) from authenticated;

create or replace function public.archive_thread(target_thread_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.set_thread_archived(target_thread_id, true);
$$;

create or replace function public.unarchive_thread(target_thread_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.set_thread_archived(target_thread_id, false);
$$;

-- PostgREST computed field: `messages?select=*,thread_summary` returns
-- {thread_id, conversation_id, title, reply_count, last_reply_at,
-- unread_count, archived_at} for a thread's root message, otherwise null.
create or replace function public.thread_summary(message_row public.messages)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'thread_id', payload->'id',
    'conversation_id', payload->'conversation_id',
    'title', payload->'title',
    'reply_count', payload->'reply_count',
    'last_reply_at', payload->'last_message_at',
    'unread_count', payload->'unread_count',
    'archived_at', payload->'archived_at'
  )
  from (
    select public.thread_payload(ct) as payload
    from public.conversation_threads ct
    where ct.root_message_id = message_row.id
      and public.is_current_user_conversation_member(ct.conversation_id)
  ) thread;
$$;

-- Same as 202610130002_pinned_messages, plus threads: members of a thread
-- may pin in it when they may pin in its parent conversation.
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

-- Same as 202610130004_circle_nicknames, but a thread of a circle channel
-- uses the channel's circle.
create or replace function public.circle_channel_nickname(
  target_conversation_id uuid,
  target_user_id uuid
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select cm.nickname
  from public.circle_channels cc
  join public.circle_members cm
    on cm.circle_id = cc.circle_id
    and cm.user_id = target_user_id
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

-- Same as 202610130010_custom_status, plus thread details: the parent
-- conversation and its title, the thread id, archive state and last
-- activity. Threads of circle channels carry the circle and its notification
-- settings, so they notify like their channel. Clients keep threads out of
-- the chat list and show them under their parent instead.
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
  thread_last_activity_at timestamptz
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
    coalesce(ct.last_message_at, ct.created_at) as thread_last_activity_at
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

-- Same as 202610130006_circle_unread_counts, plus unread messages and
-- mentions in the threads of the circle's channels.
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
  with circle_conversations as (
    select cc.circle_id, cc.conversation_id
    from public.circle_members current_member
    join public.circle_channels cc on cc.circle_id = current_member.circle_id
    where current_member.user_id = auth.uid()
    union all
    select cc.circle_id, ct.conversation_id
    from public.circle_members current_member
    join public.circle_channels cc on cc.circle_id = current_member.circle_id
    join public.conversation_threads ct
      on ct.parent_conversation_id = cc.conversation_id
    where current_member.user_id = auth.uid()
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
  left join public.circle_channels cc on cc.circle_id = c.id
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

grant execute on function public.can_current_user_manage_thread(uuid) to authenticated;
grant execute on function public.create_thread(uuid, uuid, text) to authenticated;
grant execute on function public.list_threads(uuid) to authenticated;
grant execute on function public.archive_thread(uuid) to authenticated;
grant execute on function public.unarchive_thread(uuid) to authenticated;
grant execute on function public.thread_summary(public.messages) to authenticated;
grant execute on function public.can_current_user_pin_messages(uuid) to authenticated;
grant execute on function public.list_conversation_summaries() to authenticated;
grant execute on function public.list_circle_summaries() to authenticated;
