-- Bots are not people to befriend.
--
-- * Friend requests and friendships with a bot account (profiles.is_bot)
--   are refused by triggers, whichever path inserts them, and any that
--   exist already are removed.
-- * list_friends_with_aliases and the mutual friends of
--   get_profile_summary leave bots out; get_profile_summary reports a
--   bot's relationship as 'bot' so the app offers no Add Friend button.
-- * The app's user search filters is_bot as well (profiles are readable,
--   so that part lives in the client query).

create or replace function public.reject_friendship_with_bot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  first_id uuid;
  second_id uuid;
begin
  if tg_table_name = 'friend_requests' then
    first_id := new.requester_id;
    second_id := new.receiver_id;
  else
    first_id := new.user_low_id;
    second_id := new.user_high_id;
  end if;

  if exists (
    select 1
    from public.profiles p
    where p.is_bot
      and p.id in (first_id, second_id)
  ) then
    raise exception 'Bots cannot be added as friends' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function public.reject_friendship_with_bot() from public, anon, authenticated;

drop trigger if exists friend_requests_reject_bots on public.friend_requests;
create trigger friend_requests_reject_bots
  before insert on public.friend_requests
  for each row execute function public.reject_friendship_with_bot();

drop trigger if exists friendships_reject_bots on public.friendships;
create trigger friendships_reject_bots
  before insert on public.friendships
  for each row execute function public.reject_friendship_with_bot();

delete from public.friendships f
using public.profiles p
where p.is_bot
  and p.id in (f.user_low_id, f.user_high_id);

delete from public.friend_requests fr
using public.profiles p
where p.is_bot
  and p.id in (fr.requester_id, fr.receiver_id);

-- Same as 202605180010_daily_chat_polish_v3, without bots.
create or replace function public.list_friends_with_aliases()
returns table (
  id uuid,
  username text,
  display_name text,
  alias text,
  avatar_url text,
  bio text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.username,
    p.display_name,
    ca.alias,
    p.avatar_url,
    p.bio,
    p.created_at,
    p.updated_at
  from public.friendships f
  join public.profiles p
    on p.id = case
      when f.user_low_id = auth.uid() then f.user_high_id
      else f.user_low_id
    end
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid()
    and ca.friend_id = p.id
  where auth.uid() in (f.user_low_id, f.user_high_id)
    and not p.is_bot
  order by coalesce(ca.alias, p.display_name), p.username;
$$;

-- Same as 202610160002_profile_extras, but bots are never mutual friends
-- and a bot's relationship is 'bot'.
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
  has_blocked_me boolean,
  custom_status jsonb,
  banner_url text,
  pronouns text,
  mutual_friends jsonb,
  mutual_circles jsonb
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
  ),
  viewer_friends as (
    select case
      when f.user_low_id = auth.uid() then f.user_high_id
      else f.user_low_id
    end as friend_id
    from public.friendships f
    where auth.uid() in (f.user_low_id, f.user_high_id)
  ),
  target_friends as (
    select case
      when f.user_low_id = target_user_id then f.user_high_id
      else f.user_low_id
    end as friend_id
    from public.friendships f
    where target_user_id in (f.user_low_id, f.user_high_id)
  ),
  mutual_friends as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', p.id,
          'username', p.username,
          'display_name', coalesce(ca.alias, p.display_name),
          'avatar_url', p.avatar_url
        )
        order by lower(coalesce(ca.alias, p.display_name))
      ),
      '[]'::jsonb
    ) as items
    from viewer_friends vf
    join target_friends tf on tf.friend_id = vf.friend_id
    join public.profiles p on p.id = vf.friend_id
    left join public.contact_aliases ca
      on ca.owner_id = auth.uid()
      and ca.friend_id = p.id
    where target_user_id <> auth.uid()
      and p.deleted_at is null
      and not p.is_bot
  ),
  mutual_circles as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'name', c.name,
          'avatar_url', c.avatar_url
        )
        order by lower(c.name)
      ),
      '[]'::jsonb
    ) as items
    from public.circles c
    join public.circle_members viewer
      on viewer.circle_id = c.id
      and viewer.user_id = auth.uid()
    join public.circle_members target
      on target.circle_id = c.id
      and target.user_id = target_user_id
    where target_user_id <> auth.uid()
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
      when p.is_bot then 'bot'
      when exists (select 1 from friendship) then 'friend'
      when exists (select 1 from incoming_request) then 'incoming_request'
      when exists (select 1 from outgoing_request) then 'outgoing_request'
      else 'none'
    end as relationship_status,
    (select id from incoming_request) as incoming_request_id,
    (select id from outgoing_request) as outgoing_request_id,
    bs.is_blocked_by_me,
    bs.has_blocked_me,
    case
      when bs.has_blocked_me then null
      else public.custom_status(p)
    end as custom_status,
    case when bs.has_blocked_me then null else p.banner_url end as banner_url,
    case when bs.has_blocked_me then null else p.pronouns end as pronouns,
    case
      when bs.has_blocked_me then '[]'::jsonb
      else (select items from mutual_friends)
    end as mutual_friends,
    case
      when bs.has_blocked_me then '[]'::jsonb
      else (select items from mutual_circles)
    end as mutual_circles
  from public.profiles p
  cross join block_state bs
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid()
    and ca.friend_id = p.id
  where p.id = target_user_id
    and auth.uid() is not null;
$$;

revoke execute on function public.get_profile_summary(uuid) from public, anon;
grant execute on function public.get_profile_summary(uuid) to authenticated;
