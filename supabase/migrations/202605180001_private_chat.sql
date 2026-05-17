create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  display_name text not null,
  avatar_url text,
  bio text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint username_length check (char_length(username) between 3 and 24),
  constraint username_format check (username ~ '^[a-z0-9_]+$')
);

create table public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (
    status in ('pending', 'accepted', 'rejected', 'cancelled')
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint friend_requests_not_self check (requester_id <> receiver_id),
  constraint friend_requests_unique_pair unique (requester_id, receiver_id)
);

create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  user_low_id uuid not null references public.profiles(id) on delete cascade,
  user_high_id uuid not null references public.profiles(id) on delete cascade,
  user_low_remark text,
  user_high_remark text,
  created_at timestamptz not null default now(),
  constraint friendships_ordered_pair check (user_low_id < user_high_id),
  constraint friendships_unique_pair unique (user_low_id, user_high_id)
);

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('direct', 'group', 'channel')),
  title text,
  avatar_url text,
  last_message_id uuid,
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  pinned_at timestamptz,
  muted_until timestamptz,
  last_read_message_id uuid,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  type text not null default 'text' check (type in ('text', 'image', 'file', 'voice')),
  body text not null default '',
  attachment jsonb,
  reply_to_message_id uuid references public.messages(id) on delete set null,
  edited_at timestamptz,
  recalled_at timestamptz,
  created_at timestamptz not null default now(),
  constraint message_body_not_empty check (
    type <> 'text' or char_length(trim(body)) > 0
  )
);

alter table public.conversations
  add constraint conversations_last_message_fk
  foreign key (last_message_id) references public.messages(id) on delete set null;

alter table public.conversation_members
  add constraint conversation_members_last_read_message_fk
  foreign key (last_read_message_id) references public.messages(id) on delete set null;

create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  reason text,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_not_self check (blocker_id <> blocked_id)
);

create index profiles_username_idx on public.profiles using btree (username);
create index friend_requests_receiver_status_idx
  on public.friend_requests (receiver_id, status, created_at desc);
create index friend_requests_requester_status_idx
  on public.friend_requests (requester_id, status, created_at desc);
create index friendships_user_low_idx on public.friendships (user_low_id);
create index friendships_user_high_idx on public.friendships (user_high_id);
create index conversations_last_message_at_idx
  on public.conversations (last_message_at desc nulls last);
create index conversation_members_user_idx
  on public.conversation_members (user_id, joined_at desc);
create index messages_conversation_created_idx
  on public.messages (conversation_id, created_at desc);
create index messages_sender_idx on public.messages (sender_id);
create index blocks_blocked_idx on public.blocks (blocked_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger friend_requests_set_updated_at
  before update on public.friend_requests
  for each row execute function public.set_updated_at();

create trigger conversations_set_updated_at
  before update on public.conversations
  for each row execute function public.set_updated_at();

create or replace function public.accept_friend_request(request_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  accepted_request public.friend_requests%rowtype;
  low_user_id uuid;
  high_user_id uuid;
  friendship_id uuid;
begin
  update public.friend_requests
  set status = 'accepted'
  where id = request_id
    and receiver_id = auth.uid()
    and status = 'pending'
  returning * into accepted_request;

  if accepted_request.id is null then
    raise exception 'Friend request not found or cannot be accepted'
      using errcode = '42501';
  end if;

  low_user_id = least(accepted_request.requester_id, accepted_request.receiver_id);
  high_user_id = greatest(accepted_request.requester_id, accepted_request.receiver_id);

  insert into public.friendships (user_low_id, user_high_id)
  values (low_user_id, high_user_id)
  on conflict (user_low_id, user_high_id) do nothing
  returning id into friendship_id;

  if friendship_id is null then
    select id into friendship_id
    from public.friendships
    where user_low_id = low_user_id
      and user_high_id = high_user_id;
  end if;

  return friendship_id;
end;
$$;

create or replace function public.reject_friend_request(request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  rejected_request_id uuid;
begin
  update public.friend_requests
  set status = 'rejected'
  where id = request_id
    and receiver_id = auth.uid()
    and status = 'pending'
  returning id into rejected_request_id;

  if rejected_request_id is null then
    raise exception 'Friend request not found or cannot be rejected'
      using errcode = '42501';
  end if;
end;
$$;

create or replace function public.cancel_friend_request(request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  cancelled_request_id uuid;
begin
  update public.friend_requests
  set status = 'cancelled'
  where id = request_id
    and requester_id = auth.uid()
    and status = 'pending'
  returning id into cancelled_request_id;

  if cancelled_request_id is null then
    raise exception 'Friend request not found or cannot be cancelled'
      using errcode = '42501';
  end if;
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
  conversation_id uuid;
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

  select c.id into conversation_id
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

  if conversation_id is not null then
    return conversation_id;
  end if;

  insert into public.conversations (type)
  values ('direct')
  returning id into conversation_id;

  insert into public.conversation_members (conversation_id, user_id)
  values
    (conversation_id, current_user_id),
    (conversation_id, other_user_id);

  return conversation_id;
end;
$$;

create or replace function public.touch_conversation_from_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversations
  set
    last_message_id = new.id,
    last_message_at = new.created_at,
    updated_at = now()
  where id = new.conversation_id;

  return new;
end;
$$;

create or replace function public.is_conversation_member(
  check_conversation_id uuid,
  check_user_id uuid
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
      and cm.user_id = check_user_id
  );
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
  if not public.is_conversation_member(target_conversation_id, auth.uid()) then
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
  set last_read_message_id = target_message_id
  where conversation_id = target_conversation_id
    and user_id = auth.uid();
end;
$$;

create trigger messages_touch_conversation
  after insert on public.messages
  for each row execute function public.touch_conversation_from_message();

alter table public.profiles enable row level security;
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.blocks enable row level security;

create policy profiles_select_authenticated
  on public.profiles for select
  to authenticated
  using (true);

create policy profiles_insert_own
  on public.profiles for insert
  to authenticated
  with check (id = auth.uid());

create policy profiles_update_own
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy friend_requests_select_participants
  on public.friend_requests for select
  to authenticated
  using (requester_id = auth.uid() or receiver_id = auth.uid());

create policy friend_requests_insert_requester
  on public.friend_requests for insert
  to authenticated
  with check (
    requester_id = auth.uid()
    and receiver_id <> auth.uid()
    and status = 'pending'
  );

create policy friend_requests_delete_requester
  on public.friend_requests for delete
  to authenticated
  using (requester_id = auth.uid() and status = 'pending');

create policy friendships_select_participants
  on public.friendships for select
  to authenticated
  using (auth.uid() in (user_low_id, user_high_id));

create policy conversations_select_member
  on public.conversations for select
  to authenticated
  using (public.is_conversation_member(id, auth.uid()));

create policy conversation_members_select_member
  on public.conversation_members for select
  to authenticated
  using (
    user_id = auth.uid()
    or public.is_conversation_member(conversation_id, auth.uid())
  );

create policy messages_select_member
  on public.messages for select
  to authenticated
  using (public.is_conversation_member(conversation_id, auth.uid()));

create policy messages_insert_member
  on public.messages for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_conversation_member(conversation_id, auth.uid())
  );

create policy blocks_select_owner
  on public.blocks for select
  to authenticated
  using (blocker_id = auth.uid());

create policy blocks_insert_owner
  on public.blocks for insert
  to authenticated
  with check (blocker_id = auth.uid() and blocked_id <> auth.uid());

create policy blocks_update_owner
  on public.blocks for update
  to authenticated
  using (blocker_id = auth.uid())
  with check (blocker_id = auth.uid() and blocked_id <> auth.uid());

create policy blocks_delete_owner
  on public.blocks for delete
  to authenticated
  using (blocker_id = auth.uid());
