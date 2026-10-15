-- Profile extras.
--
-- * profiles.banner_url: a banner image in the private profile-banners
--   bucket, stored as 'profile-banners/<user id>/<file>' (the prefix tells
--   the app which bucket to sign it from). profiles.pronouns: up to 40
--   characters. Both are set through update_profile_extras and cleared
--   when the account is deleted.
-- * circle_members.avatar_url: a per-circle avatar in profile-avatars
--   ('<user id>/<file>', like profile avatars), shown instead of the
--   global avatar in that circle's member list and channel messages.
--   Members set only their own.
-- * get_profile_summary also returns the banner, pronouns, and the friends
--   and circles the viewer shares with the profile's owner.

alter table public.profiles
  add column if not exists banner_url text,
  add column if not exists pronouns text;

alter table public.profiles
  drop constraint if exists profiles_pronouns_length;
alter table public.profiles
  add constraint profiles_pronouns_length check (
    pronouns is null
    or (pronouns = btrim(pronouns) and char_length(pronouns) between 1 and 40)
  );

alter table public.profiles
  drop constraint if exists profiles_banner_url_length;
alter table public.profiles
  add constraint profiles_banner_url_length check (
    banner_url is null or char_length(banner_url) <= 512
  );

alter table public.circle_members
  add column if not exists avatar_url text;

alter table public.circle_members
  drop constraint if exists circle_members_avatar_url_length;
alter table public.circle_members
  add constraint circle_members_avatar_url_length check (
    avatar_url is null or char_length(avatar_url) <= 512
  );

insert into storage.buckets (id, name, public)
values ('profile-banners', 'profile-banners', false)
on conflict (id) do update
set public = false;

drop policy if exists profile_banners_select_authenticated on storage.objects;
create policy profile_banners_select_authenticated
  on storage.objects for select
  to authenticated
  using (bucket_id = 'profile-banners');

drop policy if exists profile_banners_insert_owner on storage.objects;
create policy profile_banners_insert_owner
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'profile-banners'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Saves the caller's pronouns and banner. Blank pronouns and a null banner
-- clear them; a banner must be one of the caller's own uploads.
create or replace function public.update_profile_extras(
  pronouns text,
  banner_url text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_pronouns text := nullif(btrim(coalesce(update_profile_extras.pronouns, '')), '');
  normalized_banner text := nullif(btrim(coalesce(update_profile_extras.banner_url, '')), '');
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if normalized_pronouns is not null and char_length(normalized_pronouns) > 40 then
    raise exception 'Pronouns must be at most 40 characters'
      using errcode = '22023';
  end if;

  if normalized_banner is not null
    and (
      normalized_banner not like 'profile-banners/' || auth.uid()::text || '/%'
      or char_length(normalized_banner) > 512
    )
  then
    raise exception 'Banner must be one of your uploads' using errcode = '22023';
  end if;

  update public.profiles p
  set
    pronouns = normalized_pronouns,
    banner_url = normalized_banner
  where p.id = auth.uid()
    and p.deleted_at is null;

  if not found then
    raise exception 'Profile not found or cannot be updated'
      using errcode = '42501';
  end if;
end;
$$;

-- A deleted account keeps no banner or pronouns.
create or replace function public.clear_deleted_profile_extras()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.deleted_at is not null then
    new.banner_url := null;
    new.pronouns := null;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_clear_deleted_extras on public.profiles;
create trigger profiles_clear_deleted_extras
  before update of deleted_at on public.profiles
  for each row execute function public.clear_deleted_profile_extras();

-- Sets the caller's own avatar in a circle; null removes it. The file must
-- be one of the caller's uploads to profile-avatars.
create or replace function public.set_circle_avatar(
  target_circle_id uuid,
  avatar_url text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_avatar text := nullif(btrim(coalesce(set_circle_avatar.avatar_url, '')), '');
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if normalized_avatar is not null
    and (
      normalized_avatar not like auth.uid()::text || '/%'
      or char_length(normalized_avatar) > 512
    )
  then
    raise exception 'Avatar must be one of your uploads' using errcode = '22023';
  end if;

  update public.circle_members cm
  set avatar_url = normalized_avatar
  where cm.circle_id = target_circle_id
    and cm.user_id = auth.uid();

  if not found then
    raise exception 'Only circle members can set a circle avatar'
      using errcode = '42501';
  end if;

  return normalized_avatar;
end;
$$;

-- Members' circle avatars, for the circle's own members.
create or replace function public.list_circle_member_avatars(target_circle_id uuid)
returns table (user_id uuid, avatar_url text)
language sql
stable
security definer
set search_path = public
as $$
  select cm.user_id, cm.avatar_url
  from public.circle_members cm
  where cm.circle_id = target_circle_id
    and cm.avatar_url is not null
    and public.is_current_user_circle_member(target_circle_id);
$$;

-- The circle avatar of a user in a circle channel conversation, or null
-- for other conversations. Only the circle's own members can see it.
create or replace function public.circle_channel_avatar(
  target_conversation_id uuid,
  target_user_id uuid
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select cm.avatar_url
  from public.circle_channels cc
  join public.circle_members cm
    on cm.circle_id = cc.circle_id
    and cm.user_id = target_user_id
  where cc.conversation_id = target_conversation_id
    and public.is_current_user_circle_member(cc.circle_id);
$$;

-- PostgREST computed field: `messages?select=*,sender_circle_avatar`.
create or replace function public.sender_circle_avatar(message_row public.messages)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select public.circle_channel_avatar(
    message_row.conversation_id,
    message_row.sender_id
  );
$$;

-- Same as 202610130010_custom_status, plus the banner, pronouns, and the
-- friends and circles shared with the viewer. Like the bio, all of it is
-- hidden from users the profile's owner blocked.
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

revoke execute on function public.update_profile_extras(text, text) from public, anon;
revoke execute on function public.set_circle_avatar(uuid, text) from public, anon;
revoke execute on function public.list_circle_member_avatars(uuid) from public, anon;
revoke execute on function public.sender_circle_avatar(public.messages) from public, anon;
revoke execute on function public.get_profile_summary(uuid) from public, anon;
revoke execute on function public.circle_channel_avatar(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.clear_deleted_profile_extras() from public, anon, authenticated;

grant execute on function public.update_profile_extras(text, text) to authenticated;
grant execute on function public.set_circle_avatar(uuid, text) to authenticated;
grant execute on function public.list_circle_member_avatars(uuid) to authenticated;
grant execute on function public.sender_circle_avatar(public.messages) to authenticated;
grant execute on function public.get_profile_summary(uuid) to authenticated;
