-- Who can see my bio, pronouns, banner and mutuals.
--
-- user_privacy_settings.profile_visibility is 'everyone' (the default),
-- 'friends_and_circles' (friends, and people who share a circle with me)
-- or 'friends' (friends only). get_profile_summary applies it: to anyone
-- else it returns an empty bio, no pronouns or banner and no mutual friends
-- or circles, and says so (profile_hidden). Names, avatars, status and
-- the relationship stay visible; people always see their own profile.
-- Same as 202610160034_bots_are_not_friends otherwise.

alter table public.user_privacy_settings
  add column if not exists profile_visibility text not null default 'everyone';

alter table public.user_privacy_settings
  drop constraint if exists user_privacy_settings_profile_visibility_check;
alter table public.user_privacy_settings
  add constraint user_privacy_settings_profile_visibility_check check (
    profile_visibility in ('everyone', 'friends_and_circles', 'friends')
  );

-- Saves the caller's choice (their row is created when they have none).
create or replace function public.set_profile_visibility(visibility text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if visibility is null
    or visibility not in ('everyone', 'friends_and_circles', 'friends')
  then
    raise exception 'Choose everyone, friends and shared circles, or friends only'
      using errcode = '22023';
  end if;

  insert into public.user_privacy_settings as s (user_id, profile_visibility)
  values (auth.uid(), set_profile_visibility.visibility)
  on conflict (user_id) do update
  set profile_visibility = excluded.profile_visibility;
end;
$$;

revoke execute on function public.set_profile_visibility(text) from public, anon;
grant execute on function public.set_profile_visibility(text) to authenticated;

drop function if exists public.get_profile_summary(uuid);

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
  mutual_circles jsonb,
  profile_hidden boolean
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
  visibility as (
    select coalesce(
      (
        select ups.profile_visibility
        from public.user_privacy_settings ups
        where ups.user_id = target_user_id
      ),
      'everyone'
    ) as setting
  ),
  access as (
    select (
      target_user_id = auth.uid()
      or v.setting = 'everyone'
      or exists (select 1 from friendship)
      or (
        v.setting = 'friends_and_circles'
        and exists (
          select 1
          from public.circle_members mine
          join public.circle_members theirs
            on theirs.circle_id = mine.circle_id
            and theirs.user_id = target_user_id
          where mine.user_id = auth.uid()
        )
      )
    ) as allowed
    from visibility v
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
    case
      when bs.has_blocked_me or not (select allowed from access) then ''
      else p.bio
    end as bio,
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
    case
      when bs.has_blocked_me or not (select allowed from access) then null
      else p.banner_url
    end as banner_url,
    case
      when bs.has_blocked_me or not (select allowed from access) then null
      else p.pronouns
    end as pronouns,
    case
      when bs.has_blocked_me or not (select allowed from access) then '[]'::jsonb
      else (select items from mutual_friends)
    end as mutual_friends,
    case
      when bs.has_blocked_me or not (select allowed from access) then '[]'::jsonb
      else (select items from mutual_circles)
    end as mutual_circles,
    not (select allowed from access) as profile_hidden
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
