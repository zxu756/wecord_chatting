create table if not exists public.user_privacy_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  friend_request_policy text not null default 'everyone'
    check (friend_request_policy in ('everyone', 'friends_of_friends', 'none')),
  show_online_status boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  target_user_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (
    reason in ('spam', 'harassment', 'impersonation', 'unsafe_content', 'other')
  ),
  details text not null default '',
  status text not null default 'open' check (
    status in ('open', 'reviewed', 'dismissed')
  ),
  created_at timestamptz not null default now(),
  constraint reports_not_self check (reporter_id <> target_user_id)
);

create index if not exists reports_reporter_created_idx
  on public.reports (reporter_id, created_at desc);
create index if not exists reports_target_created_idx
  on public.reports (target_user_id, created_at desc);

alter table public.user_privacy_settings enable row level security;
alter table public.reports enable row level security;

drop trigger if exists user_privacy_settings_set_updated_at on public.user_privacy_settings;
create trigger user_privacy_settings_set_updated_at
  before update on public.user_privacy_settings
  for each row execute function public.set_updated_at();

create policy user_privacy_settings_select_owner
  on public.user_privacy_settings for select
  to authenticated
  using (user_id = auth.uid());

create policy user_privacy_settings_insert_owner
  on public.user_privacy_settings for insert
  to authenticated
  with check (user_id = auth.uid());

create policy user_privacy_settings_update_owner
  on public.user_privacy_settings for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy reports_select_reporter
  on public.reports for select
  to authenticated
  using (reporter_id = auth.uid());

create or replace function public.are_users_blocked(user_a uuid, user_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.blocks b
    where (b.blocker_id = user_a and b.blocked_id = user_b)
       or (b.blocker_id = user_b and b.blocked_id = user_a)
  );
$$;

drop policy if exists friend_requests_insert_requester on public.friend_requests;

create policy friend_requests_insert_requester
  on public.friend_requests for insert
  to authenticated
  with check (
    requester_id = auth.uid()
    and receiver_id <> auth.uid()
    and status = 'pending'
    and not public.are_users_blocked(requester_id, receiver_id)
  );

create or replace function public.get_profile_summary(target_user_id uuid)
returns table (
  id uuid,
  username text,
  display_name text,
  alias text,
  avatar_url text,
  bio text,
  relationship_status text,
  incoming_request_id uuid,
  outgoing_request_id uuid,
  is_blocked_by_me boolean,
  has_blocked_me boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with friendship as (
    select 1
    from public.friendships f
    where f.user_low_id = least(auth.uid(), target_user_id)
      and f.user_high_id = greatest(auth.uid(), target_user_id)
  ),
  incoming_request as (
    select fr.id
    from public.friend_requests fr
    where fr.requester_id = target_user_id
      and fr.receiver_id = auth.uid()
      and fr.status = 'pending'
    order by fr.created_at desc
    limit 1
  ),
  outgoing_request as (
    select fr.id
    from public.friend_requests fr
    where fr.requester_id = auth.uid()
      and fr.receiver_id = target_user_id
      and fr.status = 'pending'
    order by fr.created_at desc
    limit 1
  ),
  block_state as (
    select
      exists (
        select 1
        from public.blocks b
        where b.blocker_id = auth.uid()
          and b.blocked_id = target_user_id
      ) as is_blocked_by_me,
      exists (
        select 1
        from public.blocks b
        where b.blocker_id = target_user_id
          and b.blocked_id = auth.uid()
      ) as has_blocked_me
  )
  select
    p.id,
    p.username,
    p.display_name,
    ca.alias,
    p.avatar_url,
    case when bs.has_blocked_me then '' else p.bio end as bio,
    case
      when p.id = auth.uid() then 'self'
      when bs.is_blocked_by_me then 'blocked'
      when bs.has_blocked_me then 'blocked_by_them'
      when exists (select 1 from friendship) then 'friend'
      when exists (select 1 from incoming_request) then 'incoming_request'
      when exists (select 1 from outgoing_request) then 'outgoing_request'
      else 'none'
    end as relationship_status,
    (select id from incoming_request) as incoming_request_id,
    (select id from outgoing_request) as outgoing_request_id,
    bs.is_blocked_by_me,
    bs.has_blocked_me
  from public.profiles p
  cross join block_state bs
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid()
    and ca.friend_id = p.id
  where p.id = target_user_id
    and auth.uid() is not null;
$$;

create or replace function public.block_user(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  low_user_id uuid;
  high_user_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if target_user_id is null or target_user_id = current_user_id then
    raise exception 'Cannot block this user' using errcode = '22023';
  end if;

  with block_row(blocker_id, blocked_id) as (
    values (current_user_id, target_user_id)
  )
  insert into public.blocks (blocker_id, blocked_id)
  select blocker_id, blocked_id
  from block_row
  where blocked_id <> auth.uid()
  on conflict (blocker_id, blocked_id) do nothing;

  delete from public.friend_requests
  where (
      requester_id = current_user_id
      and receiver_id = target_user_id
    )
    or (
      requester_id = target_user_id
      and receiver_id = current_user_id
    );

  low_user_id = least(current_user_id, target_user_id);
  high_user_id = greatest(current_user_id, target_user_id);

  delete from public.friendships
  where user_low_id = low_user_id
    and user_high_id = high_user_id;
end;
$$;

create or replace function public.unblock_user(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if target_user_id is null or target_user_id = auth.uid() then
    raise exception 'Cannot unblock this user' using errcode = '22023';
  end if;

  delete from public.blocks
  where blocker_id = auth.uid()
    and blocked_id = target_user_id;
end;
$$;

create or replace function public.report_user(
  target_user_id uuid,
  report_reason text,
  report_details text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  created_report_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if target_user_id is null or not (target_user_id <> auth.uid()) then
    raise exception 'Cannot report this user' using errcode = '22023';
  end if;

  insert into public.reports (
    reporter_id,
    target_user_id,
    reason,
    details
  )
  values (
    auth.uid(),
    report_user.target_user_id,
    report_user.report_reason,
    left(coalesce(report_user.report_details, ''), 1000)
  )
  returning id into created_report_id;

  return created_report_id;
end;
$$;

create or replace function public.send_friend_request(target_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  created_request_id uuid;
  existing_request public.friend_requests%rowtype;
  low_user_id uuid;
  high_user_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if target_user_id is null or target_user_id = current_user_id then
    raise exception 'Cannot send a friend request to this user'
      using errcode = '22023';
  end if;

  if public.are_users_blocked(current_user_id, target_user_id) then
    raise exception 'Cannot send a friend request to this user'
      using errcode = '42501';
  end if;

  low_user_id = least(current_user_id, target_user_id);
  high_user_id = greatest(current_user_id, target_user_id);

  if exists (
    select 1
    from public.friendships
    where user_low_id = low_user_id
      and user_high_id = high_user_id
  ) then
    raise exception 'Users are already friends' using errcode = '22023';
  end if;

  select *
  into existing_request
  from public.friend_requests
  where requester_id = target_user_id
    and receiver_id = current_user_id
    and status = 'pending'
  limit 1;

  if existing_request.id is not null then
    raise exception 'This user has already sent you a friend request'
      using errcode = '22023';
  end if;

  insert into public.friend_requests (requester_id, receiver_id)
  values (current_user_id, target_user_id)
  on conflict (requester_id, receiver_id) do update
  set
    status = 'pending',
    updated_at = now()
  where public.friend_requests.status in ('rejected', 'cancelled')
  returning id into created_request_id;

  if created_request_id is null then
    raise exception 'Friend request already exists' using errcode = '23505';
  end if;

  return created_request_id;
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

  if public.are_users_blocked(current_user_id, other_user_id) then
    raise exception 'Cannot start a direct conversation with this user'
      using errcode = '42501';
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
