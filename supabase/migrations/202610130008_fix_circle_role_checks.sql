-- current_user_circle_role() returns null for non-members, and
-- `null not in (...)` is null, so these checks let outsiders through.

create or replace function public.invite_circle_members(
  target_circle_id uuid,
  member_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  caller_role text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select public.current_user_circle_role(target_circle_id) into caller_role;

  if coalesce(caller_role, '') not in ('owner', 'admin') then
    raise exception 'Only circle owners and admins can invite members'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from unnest(coalesce(member_ids, array[]::uuid[])) as candidate(member_id)
    where candidate.member_id is null
      or candidate.member_id = current_user_id
      or not exists (
        select 1
        from public.profiles p
        where p.id = candidate.member_id
      )
      or not exists (
        select 1
        from public.friendships f
        where f.user_low_id = least(current_user_id, candidate.member_id)
          and f.user_high_id = greatest(current_user_id, candidate.member_id)
      )
      or public.are_users_blocked(current_user_id, candidate.member_id)
  ) then
    raise exception 'Invalid circle invite members' using errcode = '42501';
  end if;

  if exists (
    select 1
    from unnest(coalesce(member_ids, array[]::uuid[])) as candidate(member_id)
    join public.circle_members cm
      on cm.circle_id = target_circle_id
      and cm.user_id = candidate.member_id
  ) then
    raise exception 'User is already a circle member' using errcode = '23505';
  end if;

  with invited as (
    select distinct member_id
    from unnest(coalesce(member_ids, array[]::uuid[])) as candidate(member_id)
    where member_id is not null
      and member_id <> current_user_id
  ),
  allowed as (
    select invited.member_id
    from invited
    where exists (
      select 1
      from public.friendships f
      where f.user_low_id = least(current_user_id, invited.member_id)
        and f.user_high_id = greatest(current_user_id, invited.member_id)
    )
      and not public.are_users_blocked(current_user_id, invited.member_id)
  ),
  inserted as (
    insert into public.circle_members (circle_id, user_id, role)
    select target_circle_id, allowed.member_id, 'member'
    from allowed
    on conflict do nothing
    returning user_id
  )
  insert into public.conversation_members (conversation_id, user_id, role)
  select cc.conversation_id, inserted.user_id, 'member'
  from inserted
  cross join public.circle_channels cc
  where cc.circle_id = target_circle_id
  on conflict do nothing;
end;
$$;

create or replace function public.delete_circle_post(target_post_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_post public.circle_posts%rowtype;
  caller_role text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into target_post
  from public.circle_posts
  where id = target_post_id
    and deleted_at is null;

  if target_post.id is null then
    raise exception 'Post not found' using errcode = '42501';
  end if;

  select public.current_user_circle_role(target_post.circle_id) into caller_role;

  if target_post.author_id <> current_user_id
    and coalesce(caller_role, '') not in ('owner', 'admin')
  then
    raise exception 'Caller cannot delete this post' using errcode = '42501';
  end if;

  update public.circle_posts
  set deleted_at = now()
  where id = target_post_id;
end;
$$;
