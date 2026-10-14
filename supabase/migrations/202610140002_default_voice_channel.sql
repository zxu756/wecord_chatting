-- New circles start with a "General" voice channel under the text
-- channel, so members can hop into voice without setting one up first.

create or replace function public.create_circle(
  circle_name text,
  member_ids uuid[] default array[]::uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_name text := trim(coalesce(circle_name, ''));
  created_circle_id uuid;
  created_conversation_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_name) = 0 or char_length(trimmed_name) > 80 then
    raise exception 'Circle name must be between 1 and 80 characters'
      using errcode = '22023';
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

  insert into public.circles (name, owner_id)
  values (trimmed_name, current_user_id)
  returning id into created_circle_id;

  insert into public.circle_roles (circle_id, name, position, permissions, is_default)
  values (
    created_circle_id,
    '@everyone',
    0,
    public.circle_default_role_permissions(),
    true
  );

  insert into public.circle_members (circle_id, user_id, role)
  values (created_circle_id, current_user_id, 'owner');

  insert into public.circle_members (circle_id, user_id, role)
  select created_circle_id, invited.member_id, 'member'
  from (
    select distinct member_id
    from unnest(coalesce(member_ids, array[]::uuid[])) as candidate(member_id)
    where member_id is not null
      and member_id <> current_user_id
  ) invited
  where exists (
    select 1
    from public.friendships f
    where f.user_low_id = least(current_user_id, invited.member_id)
      and f.user_high_id = greatest(current_user_id, invited.member_id)
  )
    and not public.are_users_blocked(current_user_id, invited.member_id)
  on conflict do nothing;

  insert into public.conversations (type, title)
  values ('channel', 'general')
  returning id into created_conversation_id;

  insert into public.conversation_members (conversation_id, user_id, role)
  select created_conversation_id, cm.user_id, cm.role
  from public.circle_members cm
  where cm.circle_id = created_circle_id
  on conflict do nothing;

  insert into public.circle_channels (
    circle_id,
    conversation_id,
    name,
    position,
    created_by
  )
  values (
    created_circle_id,
    created_conversation_id,
    'general',
    0,
    current_user_id
  );

  insert into public.conversations (type, title)
  values ('channel', 'General')
  returning id into created_conversation_id;

  insert into public.conversation_members (conversation_id, user_id, role)
  select created_conversation_id, cm.user_id, cm.role
  from public.circle_members cm
  where cm.circle_id = created_circle_id
  on conflict do nothing;

  insert into public.circle_channels (
    circle_id,
    conversation_id,
    name,
    position,
    created_by,
    kind
  )
  values (
    created_circle_id,
    created_conversation_id,
    'General',
    1,
    current_user_id,
    'voice'
  );

  return created_circle_id;
end;
$$;

grant execute on function public.create_circle(text, uuid[]) to authenticated;
