-- Privacy permissions 2.0: who can add me, find me and call me.
--
-- user_privacy_settings gains five choices (group_invite_from, who can pull
-- me into a group, is applied by 202610210420_group_invitations):
--
--   group_invite_from         all_friends, starred_friends or approval.
--   friend_request_from       everyone, friends_of_friends, circle_members
--                             (someone I share a circle with) or nobody.
--   discoverable_by_username  whether a username search finds me.
--   discoverable_by_qr        whether scanning my QR code leads to me.
--   allow_calls_from          friends (everyone I chat with), starred_friends
--                             or nobody; for direct (1:1) calls.
--
-- Direct messages stay friends-only; none of this relaxes that.
--
-- Enforced here, on the server, and not only in the app:
--
--   * friend requests: a BEFORE INSERT trigger on friend_requests, so the
--     send_friend_request RPC and a plain table insert are both held to it.
--     send_friend_request (202605190002) already reads the older
--     friend_request_policy (everyone / friends_of_friends / none); a
--     trigger keeps that column in step with friend_request_from.
--   * username search: the new search_users_by_username RPC, which the app
--     uses instead of reading profiles with ilike. People who are already
--     friends are always found. (Profile rows stay readable by id: chats
--     and member lists need names; only the search is gated.)
--   * QR codes: resolve_user_qr_code (latest: 202610180030_user_qr_codes)
--     returns nothing for someone who turned the QR off, unless the scanner
--     is a friend or the owner.
--   * calls: can_current_user_call_in_conversation (latest:
--     202610140006_direct_calls), the one gate for starting, joining and
--     minting a token for a call, applies allow_calls_from to direct chats.
--     Group calls are not affected.
--
-- users_share_a_friend and users_share_a_circle are the shared "friend of a
-- friend" and "circle mate" tests (also for the mutual-friends work).

alter table public.user_privacy_settings
  add column if not exists friend_request_from text not null default 'everyone',
  add column if not exists discoverable_by_username boolean not null default true,
  add column if not exists discoverable_by_qr boolean not null default true,
  add column if not exists allow_calls_from text not null default 'friends',
  add column if not exists group_invite_from text not null default 'all_friends';

alter table public.user_privacy_settings
  drop constraint if exists user_privacy_settings_group_invite_from_check;
alter table public.user_privacy_settings
  add constraint user_privacy_settings_group_invite_from_check check (
    group_invite_from in ('all_friends', 'starred_friends', 'approval')
  );

alter table public.user_privacy_settings
  drop constraint if exists user_privacy_settings_friend_request_from_check;
alter table public.user_privacy_settings
  add constraint user_privacy_settings_friend_request_from_check check (
    friend_request_from in (
      'everyone', 'friends_of_friends', 'circle_members', 'nobody'
    )
  );

alter table public.user_privacy_settings
  drop constraint if exists user_privacy_settings_allow_calls_from_check;
alter table public.user_privacy_settings
  add constraint user_privacy_settings_allow_calls_from_check check (
    allow_calls_from in ('friends', 'starred_friends', 'nobody')
  );

-- Whoever chose a stricter request policy before keeps it.
update public.user_privacy_settings
set friend_request_from = case friend_request_policy
  when 'none' then 'nobody'
  when 'friends_of_friends' then 'friends_of_friends'
  else friend_request_from
end
where friend_request_policy in ('none', 'friends_of_friends')
  and friend_request_from = 'everyone';

-- The older column follows the new one (send_friend_request still reads it).
create or replace function public.sync_friend_request_policy()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.friend_request_policy := case new.friend_request_from
    when 'nobody' then 'none'
    when 'friends_of_friends' then 'friends_of_friends'
    else 'everyone'
  end;
  return new;
end;
$$;

drop trigger if exists user_privacy_settings_sync_policy
  on public.user_privacy_settings;
create trigger user_privacy_settings_sync_policy
  before insert or update on public.user_privacy_settings
  for each row execute function public.sync_friend_request_policy();

-- Saves the caller's choices; a parameter left out keeps what is saved.
create or replace function public.set_privacy_permissions(
  friend_request_from text default null,
  discoverable_by_username boolean default null,
  discoverable_by_qr boolean default null,
  group_invite_from text default null,
  allow_calls_from text default null
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

  if friend_request_from is not null and friend_request_from not in (
    'everyone', 'friends_of_friends', 'circle_members', 'nobody'
  ) then
    raise exception 'Choose who can send you friend requests'
      using errcode = '22023';
  end if;
  if group_invite_from is not null and group_invite_from not in (
    'all_friends', 'starred_friends', 'approval'
  ) then
    raise exception 'Choose who can add you to groups'
      using errcode = '22023';
  end if;
  if allow_calls_from is not null and allow_calls_from not in (
    'friends', 'starred_friends', 'nobody'
  ) then
    raise exception 'Choose who can call you' using errcode = '22023';
  end if;

  insert into public.user_privacy_settings as s (user_id)
  values (auth.uid())
  on conflict (user_id) do nothing;

  update public.user_privacy_settings s
  set
    friend_request_from = coalesce(
      set_privacy_permissions.friend_request_from, s.friend_request_from
    ),
    discoverable_by_username = coalesce(
      set_privacy_permissions.discoverable_by_username,
      s.discoverable_by_username
    ),
    discoverable_by_qr = coalesce(
      set_privacy_permissions.discoverable_by_qr, s.discoverable_by_qr
    ),
    group_invite_from = coalesce(
      set_privacy_permissions.group_invite_from, s.group_invite_from
    ),
    allow_calls_from = coalesce(
      set_privacy_permissions.allow_calls_from, s.allow_calls_from
    )
  where s.user_id = auth.uid();
end;
$$;

revoke execute on function public.set_privacy_permissions(text, boolean, boolean, text, text)
  from public, anon;
grant execute on function public.set_privacy_permissions(text, boolean, boolean, text, text)
  to authenticated;

-- Shared tests ---------------------------------------------------------

-- Whether [user_a] and [user_b] have a friend in common.
create or replace function public.users_share_a_friend(user_a uuid, user_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from (
      select case when f.user_low_id = user_a then f.user_high_id
                  else f.user_low_id end as friend_id
      from public.friendships f
      where user_a in (f.user_low_id, f.user_high_id)
    ) a
    join (
      select case when f.user_low_id = user_b then f.user_high_id
                  else f.user_low_id end as friend_id
      from public.friendships f
      where user_b in (f.user_low_id, f.user_high_id)
    ) b on b.friend_id = a.friend_id
    where a.friend_id not in (user_a, user_b)
  );
$$;

-- Whether [user_a] and [user_b] are in a circle together.
create or replace function public.users_share_a_circle(user_a uuid, user_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.circle_members a
    join public.circle_members b on b.circle_id = a.circle_id
    where a.user_id = user_a
      and b.user_id = user_b
  );
$$;

-- Whether [user_a] and [user_b] are friends.
create or replace function public.users_are_friends(user_a uuid, user_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.friendships f
    where f.user_low_id = least(user_a, user_b)
      and f.user_high_id = greatest(user_a, user_b)
  );
$$;

-- Whether [owner] has starred [friend_id].
create or replace function public.user_starred_friend(owner uuid, friend_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.friend_stars s
    where s.owner_id = owner
      and s.friend_id = user_starred_friend.friend_id
  );
$$;

revoke execute on function public.users_share_a_friend(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.users_share_a_circle(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.users_are_friends(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.user_starred_friend(uuid, uuid) from public, anon, authenticated;
grant execute on function public.users_share_a_friend(uuid, uuid) to service_role;
grant execute on function public.users_share_a_circle(uuid, uuid) to service_role;
grant execute on function public.users_are_friends(uuid, uuid) to service_role;
grant execute on function public.user_starred_friend(uuid, uuid) to service_role;

-- Friend requests ------------------------------------------------------

create or replace function public.friend_requests_check_privacy()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  allowed_from text;
begin
  if new.status is distinct from 'pending' then
    return new;
  end if;

  select s.friend_request_from
  into allowed_from
  from public.user_privacy_settings s
  where s.user_id = new.receiver_id;

  allowed_from := coalesce(allowed_from, 'everyone');

  if allowed_from = 'nobody' then
    raise exception 'This user is not accepting friend requests'
      using errcode = '42501';
  end if;

  if allowed_from = 'friends_of_friends'
    and not public.users_share_a_friend(new.requester_id, new.receiver_id)
  then
    raise exception 'This user only accepts friend requests from friends of friends'
      using errcode = '42501';
  end if;

  if allowed_from = 'circle_members'
    and not public.users_share_a_circle(new.requester_id, new.receiver_id)
  then
    raise exception 'This user only accepts friend requests from people in a shared circle'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke execute on function public.friend_requests_check_privacy() from public, anon, authenticated;

drop trigger if exists friend_requests_check_privacy on public.friend_requests;
create trigger friend_requests_check_privacy
  before insert on public.friend_requests
  for each row execute function public.friend_requests_check_privacy();

-- Username search ------------------------------------------------------

-- People whose username contains [search_query], 20 at most, for the Add
-- Friend screen. Not the caller, bots, deleted accounts, anyone who blocked
-- or was blocked by the caller, or anyone who turned off "find me by
-- username" (unless they are already the caller's friend).
create or replace function public.search_users_by_username(search_query text)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  needle text := btrim(coalesce(search_query, ''));
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if needle = '' then
    return;
  end if;

  return query
  select p.id, p.username, p.display_name, p.avatar_url, p.created_at, p.updated_at
  from public.profiles p
  left join public.user_privacy_settings s on s.user_id = p.id
  where p.username ilike '%' || replace(replace(replace(needle, '\', '\\'), '%', '\%'), '_', '\_') || '%'
    and p.id <> current_user_id
    and p.deleted_at is null
    and not p.is_bot
    and not public.are_users_blocked(current_user_id, p.id)
    and (
      coalesce(s.discoverable_by_username, true)
      or public.users_are_friends(current_user_id, p.id)
    )
  order by p.username
  limit 20;
end;
$$;

revoke execute on function public.search_users_by_username(text) from public, anon;
grant execute on function public.search_users_by_username(text) to authenticated;

-- QR codes -------------------------------------------------------------

-- resolve_user_qr_code (202610180030_user_qr_codes), and a person who turned
-- off "find me by QR code" does not resolve for anyone but a friend.
create or replace function public.resolve_user_qr_code(qr_code text)
returns table (
  user_id uuid,
  username text,
  display_name text,
  avatar_url text
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.username, p.display_name, p.avatar_url
  from public.user_qr_codes q
  join public.profiles p on p.id = q.user_id
  left join public.user_privacy_settings s on s.user_id = p.id
  where auth.uid() is not null
    and q.code = lower(btrim(coalesce(qr_code, '')))
    and p.deleted_at is null
    and (
      p.id = auth.uid()
      or (
        not public.are_users_blocked(auth.uid(), p.id)
        and (
          coalesce(s.discoverable_by_qr, true)
          or public.users_are_friends(auth.uid(), p.id)
        )
      )
    );
$$;

revoke execute on function public.resolve_user_qr_code(text) from public, anon;
grant execute on function public.resolve_user_qr_code(text) to authenticated;

-- Calls ----------------------------------------------------------------

-- Whether [callee] takes calls from [caller] by their allow_calls_from.
create or replace function public.user_accepts_calls_from(callee uuid, caller uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case coalesce(
    (select s.allow_calls_from
     from public.user_privacy_settings s
     where s.user_id = callee),
    'friends'
  )
    when 'nobody' then false
    when 'starred_friends' then public.user_starred_friend(callee, caller)
    else true
  end;
$$;

revoke execute on function public.user_accepts_calls_from(uuid, uuid) from public, anon, authenticated;
grant execute on function public.user_accepts_calls_from(uuid, uuid) to service_role;

-- can_current_user_call_in_conversation (202610140006_direct_calls) with
-- the other person's allow_calls_from applied to direct chats.
create or replace function public.can_current_user_call_in_conversation(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.conversations c
    where c.id = target_conversation_id
      and c.type in ('direct', 'group')
  )
    and public.is_current_user_conversation_member(target_conversation_id)
    and not public.is_current_user_blocked_in_conversation(target_conversation_id)
    and not exists (
      select 1
      from public.conversations c
      join public.conversation_members other
        on other.conversation_id = c.id
        and other.user_id <> auth.uid()
      where c.id = target_conversation_id
        and c.type = 'direct'
        and not public.user_accepts_calls_from(other.user_id, auth.uid())
    );
$$;

revoke execute on function public.can_current_user_call_in_conversation(uuid) from public, anon;
grant execute on function public.can_current_user_call_in_conversation(uuid) to authenticated;
