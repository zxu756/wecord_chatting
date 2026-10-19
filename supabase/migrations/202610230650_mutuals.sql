-- Mutual friends, group chats and circles (A14), and the profile extras the
-- profile page needs in one call.
--
-- get_mutuals(target)
--   The friends the caller and the target both have, the group chats both are
--   in, and the circles both are in: always the numbers; the names (and
--   groups' titles) only when the target is the caller's own friend. A person
--   the caller is not friends with only ever gets numbers, so nobody can use
--   it to map out who is in which group. A mutual friend is a friend of BOTH
--   people, nobody else.
--   Rules it follows:
--     * a person who blocked the caller (or the other way round), a deleted
--       account or a bot shows nothing;
--     * "who can see my profile" (can_view_profile_details,
--       202610170101): someone the target keeps their profile from gets
--       nothing, as get_profile_summary already does;
--     * bots and deleted accounts are never counted as mutual friends;
--     * circles are listed by name; channels, private or not, are not
--       touched;
--     * the caller's own profile has no mutuals.
--
-- get_mutual_counts(ids)
--   Only the number of mutual friends for up to 50 people (the request cards
--   show "3 mutual friends"), with the same rules; a person the rules hide
--   is left out.
--
-- get_profile_extras(target)
--   One call for the profile page: mutuals (get_mutuals), the birthday when
--   the caller may see it (can_view_birthday), the support links when the
--   caller may see the profile (can_view_profile_details), and how the
--   friendship, or the request waiting for an answer, started (source; only
--   its two people see it).

create or replace function public.get_mutuals(target_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  is_friend boolean;
  friend_ids uuid[];
  group_ids uuid[];
  circle_ids uuid[];
  empty jsonb := jsonb_build_object(
    'friend_count', 0, 'group_count', 0, 'circle_count', 0,
    'friends', '[]'::jsonb, 'groups', '[]'::jsonb, 'circles', '[]'::jsonb,
    'is_friend', false
  );
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if target_user_id is null or target_user_id = me then
    return empty;
  end if;
  if public.are_users_blocked(me, target_user_id)
    or not public.can_view_profile_details(target_user_id)
    or not exists (
      select 1
      from public.profiles t
      where t.id = target_user_id and t.deleted_at is null and not t.is_bot
    )
  then
    return empty;
  end if;

  is_friend := exists (
    select 1
    from public.friendships f
    where f.user_low_id = least(me, target_user_id)
      and f.user_high_id = greatest(me, target_user_id)
  );

  select coalesce(array_agg(p.id), array[]::uuid[]) into friend_ids
  from public.friendships mine
  join public.friendships theirs
    on (case when mine.user_low_id = me then mine.user_high_id else mine.user_low_id end)
     = (case when theirs.user_low_id = target_user_id then theirs.user_high_id else theirs.user_low_id end)
  join public.profiles p
    on p.id = case when mine.user_low_id = me then mine.user_high_id else mine.user_low_id end
  where me in (mine.user_low_id, mine.user_high_id)
    and target_user_id in (theirs.user_low_id, theirs.user_high_id)
    and p.deleted_at is null
    and not p.is_bot;

  select coalesce(array_agg(c.id), array[]::uuid[]) into group_ids
  from public.conversations c
  join public.conversation_members mine
    on mine.conversation_id = c.id and mine.user_id = me
  join public.conversation_members theirs
    on theirs.conversation_id = c.id and theirs.user_id = target_user_id
  where c.type = 'group';

  select coalesce(array_agg(c.id), array[]::uuid[]) into circle_ids
  from public.circles c
  join public.circle_members mine
    on mine.circle_id = c.id and mine.user_id = me
  join public.circle_members theirs
    on theirs.circle_id = c.id and theirs.user_id = target_user_id;

  return jsonb_build_object(
    'friend_count', cardinality(friend_ids),
    'group_count', cardinality(group_ids),
    'circle_count', cardinality(circle_ids),
    'is_friend', is_friend,
    'friends', case when not is_friend then '[]'::jsonb else coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', p.id,
          'username', p.username,
          'display_name', coalesce(nullif(btrim(ca.alias), ''), p.display_name),
          'avatar_url', p.avatar_url
        )
        order by lower(coalesce(nullif(btrim(ca.alias), ''), p.display_name))
      )
      from public.profiles p
      left join public.contact_aliases ca
        on ca.owner_id = me and ca.friend_id = p.id
      where p.id = any (friend_ids)
    ), '[]'::jsonb) end,
    'groups', case when not is_friend then '[]'::jsonb else coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'title', c.title,
          'avatar_url', c.avatar_url
        )
        order by lower(coalesce(c.title, ''))
      )
      from public.conversations c
      where c.id = any (group_ids)
    ), '[]'::jsonb) end,
    'circles', case when not is_friend then '[]'::jsonb else coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'name', c.name,
          'avatar_url', c.avatar_url
        )
        order by lower(c.name)
      )
      from public.circles c
      where c.id = any (circle_ids)
    ), '[]'::jsonb) end
  );
end;
$$;

revoke execute on function public.get_mutuals(uuid) from public, anon;
grant execute on function public.get_mutuals(uuid) to authenticated;

create or replace function public.get_mutual_counts(user_ids uuid[])
returns table (
  user_id uuid,
  friend_count integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  one uuid;
  answer jsonb;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if user_ids is null then
    return;
  end if;
  if cardinality(user_ids) > 50 then
    raise exception 'Ask for at most 50 people at a time' using errcode = '22023';
  end if;
  for one in select distinct u from unnest(user_ids) u where u is not null and u <> me loop
    -- Same rules as get_mutuals; a hidden person has no row.
    if public.are_users_blocked(me, one)
      or not public.can_view_profile_details(one)
      or not exists (
        select 1 from public.profiles t
        where t.id = one and t.deleted_at is null and not t.is_bot
      )
    then
      continue;
    end if;
    user_id := one;
    select count(*)::integer into friend_count
    from public.friendships mine
    join public.friendships theirs
      on (case when mine.user_low_id = me then mine.user_high_id else mine.user_low_id end)
       = (case when theirs.user_low_id = one then theirs.user_high_id else theirs.user_low_id end)
    join public.profiles p
      on p.id = case when mine.user_low_id = me then mine.user_high_id else mine.user_low_id end
    where me in (mine.user_low_id, mine.user_high_id)
      and one in (theirs.user_low_id, theirs.user_high_id)
      and p.deleted_at is null
      and not p.is_bot;
    return next;
  end loop;
end;
$$;

revoke execute on function public.get_mutual_counts(uuid[]) from public, anon;
grant execute on function public.get_mutual_counts(uuid[]) to authenticated;

create or replace function public.get_profile_extras(target_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  birthday jsonb := null;
  shown_links jsonb := '[]'::jsonb;
  how text := null;
  target public.profiles%rowtype;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into target
  from public.profiles p
  where p.id = target_user_id;
  if target.id is null then
    raise exception 'Profile not found' using errcode = '42501';
  end if;

  if public.can_view_birthday(target_user_id) and target.birthday_month is not null then
    birthday := jsonb_build_object(
      'month', target.birthday_month,
      'day', target.birthday_day
    );
  end if;

  if target.deleted_at is null
    and public.can_view_profile_details(target_user_id)
  then
    shown_links := target.links;
  end if;

  if target_user_id <> me then
    select f.source into how
    from public.friendships f
    where f.user_low_id = least(me, target_user_id)
      and f.user_high_id = greatest(me, target_user_id);
    if not found then
      select r.source into how
      from public.friend_requests r
      where r.requester_id = target_user_id
        and r.receiver_id = me
        and r.status = 'pending'
      order by r.created_at desc
      limit 1;
    end if;
  end if;

  return jsonb_build_object(
    'birthday', birthday,
    'links', shown_links,
    'source', how,
    'mutuals', public.get_mutuals(target_user_id)
  );
end;
$$;

revoke execute on function public.get_profile_extras(uuid) from public, anon;
grant execute on function public.get_profile_extras(uuid) to authenticated;
