-- Cleaning up groups you no longer use: Settings -> Chats -> Clean up
-- groups lists the group chats nobody has written in for a while, so the
-- caller can leave many at once (each through leave_group_conversation).
--
-- list_inactive_groups(inactive_days) returns the caller's group chats
-- (not direct chats, circle channels or threads) whose last message, or
-- creation when nothing was ever written, is at least inactive_days old,
-- oldest first, with who is in them, the caller's role and whether they
-- may leave right now (the only owner of a group with other members must
-- hand it over first, as leave_group_conversation insists).

create or replace function public.list_inactive_groups(inactive_days integer)
returns table (
  conversation_id uuid,
  title text,
  avatar_url text,
  member_count integer,
  last_activity_at timestamptz,
  my_role text,
  can_leave boolean,
  is_pinned boolean,
  is_muted boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  days integer := greatest(1, least(coalesce(inactive_days, 90), 3650));
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  return query
  select
    c.id,
    c.title,
    c.avatar_url,
    counts.member_count,
    activity.last_at,
    mine.role,
    not (
      mine.role = 'owner'
      and counts.owner_count = 1
      and counts.member_count > 1
    ),
    mine.pinned_at is not null,
    mine.muted_until is not null and mine.muted_until > now()
  from public.conversation_members mine
  join public.conversations c on c.id = mine.conversation_id
  cross join lateral (
    select coalesce(c.last_message_at, c.created_at) as last_at
  ) activity
  cross join lateral (
    select
      count(*)::integer as member_count,
      count(*) filter (where m.role = 'owner')::integer as owner_count
    from public.conversation_members m
    where m.conversation_id = c.id
  ) counts
  where mine.user_id = auth.uid()
    and c.type = 'group'
    and activity.last_at <= now() - make_interval(days => days)
  order by activity.last_at, c.id
  limit 200;
end;
$$;

revoke execute on function public.list_inactive_groups(integer) from public;
revoke execute on function public.list_inactive_groups(integer) from anon;
grant execute on function public.list_inactive_groups(integer) to authenticated;
