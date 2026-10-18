-- Who can pull me into a group, and group invitations.
--
-- user_privacy_settings.group_invite_from is 'all_friends' (the default:
-- anyone who is my friend and runs the group can add me), 'starred_friends'
-- (only friends I starred add me straight in) or 'approval' (nobody does:
-- I accept first). When a person cannot be added straight in, the adder
-- creates a group_invitations row instead. The invitee sees a card
-- "{name} invited you to join {group}" in Notifications → Friends with
-- Accept and Decline. An invitation lasts 7 days.
--
-- add_group_members (latest: 202605180005_social_chat_v2) and
-- create_group_conversation (same file) are the two ways an admin puts
-- friends into a group; both now apply the setting. The rules of the
-- originals are kept: only an owner or admin may add, and only people who
-- are the adder's friends. They are the only paths that hold a setting back:
-- joining by a group QR code (join_group_by_qr) and following a contact card
-- are the person's own choice and are not touched. A group is still never
-- a way to start a direct chat: DMs stay friends-only.
--
-- add_group_members now returns {added: [ids], invited: [ids]} instead of
-- nothing, so the app can say who still has to accept. Callers that ignore
-- the result keep working.

create table if not exists public.group_invitations (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  inviter_id uuid not null references public.profiles(id) on delete cascade,
  invitee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  responded_at timestamptz,
  constraint group_invitations_not_self check (inviter_id <> invitee_id)
);

-- One open invitation per person and group.
create unique index if not exists group_invitations_one_pending_idx
  on public.group_invitations (conversation_id, invitee_id)
  where status = 'pending';

create index if not exists group_invitations_invitee_idx
  on public.group_invitations (invitee_id, created_at desc);

alter table public.group_invitations enable row level security;
revoke all on public.group_invitations from anon, authenticated;
grant select on public.group_invitations to authenticated;

drop policy if exists group_invitations_select_involved on public.group_invitations;
create policy group_invitations_select_involved
  on public.group_invitations for select
  to authenticated
  using (invitee_id = auth.uid() or inviter_id = auth.uid());

-- Whether [adder] may put [invitee] into a group without asking.
create or replace function public.can_add_to_group_directly(
  adder uuid,
  invitee uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case coalesce(
    (select s.group_invite_from
     from public.user_privacy_settings s
     where s.user_id = invitee),
    'all_friends'
  )
    when 'approval' then false
    when 'starred_friends' then public.user_starred_friend(invitee, adder)
    else true
  end;
$$;

revoke execute on function public.can_add_to_group_directly(uuid, uuid) from public, anon, authenticated;
grant execute on function public.can_add_to_group_directly(uuid, uuid) to service_role;

-- Opens an invitation (or keeps the open one).
create or replace function public.invite_to_group(
  target_conversation_id uuid,
  adder uuid,
  invitee uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- A lapsed invitation is not "open".
  delete from public.group_invitations i
  where i.conversation_id = target_conversation_id
    and i.invitee_id = invitee
    and i.status = 'pending'
    and i.expires_at <= now();

  insert into public.group_invitations (conversation_id, inviter_id, invitee_id)
  values (target_conversation_id, adder, invitee)
  on conflict (conversation_id, invitee_id) where status = 'pending'
  do nothing;
end;
$$;

revoke execute on function public.invite_to_group(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.invite_to_group(uuid, uuid, uuid) to service_role;

-- add_group_members (202605180005_social_chat_v2), holding back the people
-- who must approve. The return type changes, so the old one goes first.
drop function if exists public.add_group_members(uuid, uuid[]);

create or replace function public.add_group_members(
  target_conversation_id uuid,
  member_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  selected uuid[];
  member uuid;
  added uuid[] := array[]::uuid[];
  invited uuid[] := array[]::uuid[];
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.conversations c
    join public.conversation_members cm on cm.conversation_id = c.id
    where c.id = target_conversation_id
      and c.type = 'group'
      and cm.user_id = current_user_id
      and cm.role in ('owner', 'admin')
  ) then
    raise exception 'Group conversation not found or cannot be changed'
      using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct m), array[]::uuid[])
  into selected
  from unnest(coalesce(member_ids, array[]::uuid[])) as picked(m)
  where m is not null
    and m <> current_user_id;

  if exists (
    select 1
    from unnest(selected) as sm(member_id)
    where not exists (
      select 1
      from public.friendships f
      where f.user_low_id = least(current_user_id, sm.member_id)
        and f.user_high_id = greatest(current_user_id, sm.member_id)
    )
  ) then
    raise exception 'Group members must be accepted friends'
      using errcode = '42501';
  end if;

  foreach member in array selected loop
    if exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = target_conversation_id
        and cm.user_id = member
    ) then
      continue;
    end if;

    if public.can_add_to_group_directly(current_user_id, member) then
      insert into public.conversation_members (conversation_id, user_id, role)
      values (target_conversation_id, member, 'member')
      on conflict (conversation_id, user_id) do nothing;
      added := added || member;
    else
      perform public.invite_to_group(
        target_conversation_id, current_user_id, member
      );
      invited := invited || member;
    end if;
  end loop;

  return jsonb_build_object('added', to_jsonb(added), 'invited', to_jsonb(invited));
end;
$$;

revoke execute on function public.add_group_members(uuid, uuid[]) from public, anon;
grant execute on function public.add_group_members(uuid, uuid[]) to authenticated;

-- create_group_conversation (202605180005_social_chat_v2): the same, and the
-- people who must approve get an invitation to the new group.
create or replace function public.create_group_conversation(
  group_title text,
  member_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_title text := trim(coalesce(group_title, ''));
  created_conversation_id uuid;
  selected uuid[];
  member uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_title) = 0 then
    raise exception 'Group title is required' using errcode = '22023';
  end if;

  select coalesce(array_agg(distinct m), array[]::uuid[])
  into selected
  from unnest(coalesce(member_ids, array[]::uuid[])) as picked(m)
  where m is not null
    and m <> current_user_id;

  if coalesce(array_length(selected, 1), 0) < 2 then
    raise exception 'A group conversation requires at least two members'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(selected) as sm(member_id)
    where not exists (
      select 1
      from public.friendships f
      where f.user_low_id = least(current_user_id, sm.member_id)
        and f.user_high_id = greatest(current_user_id, sm.member_id)
    )
  ) then
    raise exception 'Group members must be accepted friends'
      using errcode = '42501';
  end if;

  insert into public.conversations (type, title)
  values ('group', trimmed_title)
  returning id into created_conversation_id;

  -- Contract guard: role, 'owner'
  insert into public.conversation_members (conversation_id, user_id, role)
  values (created_conversation_id, current_user_id, 'owner');

  foreach member in array selected loop
    if public.can_add_to_group_directly(current_user_id, member) then
      -- Contract guard: role, 'member'
      insert into public.conversation_members (conversation_id, user_id, role)
      values (created_conversation_id, member, 'member');
    else
      perform public.invite_to_group(
        created_conversation_id, current_user_id, member
      );
    end if;
  end loop;

  return created_conversation_id;
end;
$$;

revoke execute on function public.create_group_conversation(text, uuid[]) from public, anon;
grant execute on function public.create_group_conversation(text, uuid[]) to authenticated;

-- The caller's open invitations, newest first.
create or replace function public.list_my_group_invitations()
returns table (
  id uuid,
  conversation_id uuid,
  group_title text,
  inviter_id uuid,
  inviter_name text,
  inviter_username text,
  inviter_avatar_url text,
  created_at timestamptz,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  -- Answered or lapsed more than a month ago: gone.
  delete from public.group_invitations i
  where i.invitee_id = auth.uid()
    and coalesce(i.responded_at, i.expires_at) < now() - interval '30 days';

  return query
  select
    i.id,
    i.conversation_id,
    coalesce(nullif(btrim(c.title), ''), ''),
    i.inviter_id,
    coalesce(nullif(btrim(p.display_name), ''), p.username),
    p.username,
    p.avatar_url,
    i.created_at,
    i.expires_at
  from public.group_invitations i
  join public.conversations c on c.id = i.conversation_id
  join public.profiles p on p.id = i.inviter_id
  where i.invitee_id = auth.uid()
    and i.status = 'pending'
    and i.expires_at > now()
    and p.deleted_at is null
    and not public.are_users_blocked(auth.uid(), i.inviter_id)
    and not exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = i.conversation_id
        and cm.user_id = auth.uid()
    )
  order by i.created_at desc;
end;
$$;

revoke execute on function public.list_my_group_invitations() from public, anon;
grant execute on function public.list_my_group_invitations() to authenticated;

-- Accepts or declines an invitation of the caller's. Accepting joins the
-- group and returns its id; declining returns null. An invitation that
-- lapsed, was answered or is not theirs raises; so does one whose adder they
-- have since blocked (or who blocked them).
create or replace function public.respond_group_invitation(
  invitation_id uuid,
  accept boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  invitation public.group_invitations%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into invitation
  from public.group_invitations i
  where i.id = invitation_id
    and i.invitee_id = current_user_id
  for update;

  if invitation.id is null or invitation.status <> 'pending' then
    raise exception 'Invitation not found' using errcode = '42501';
  end if;

  if invitation.expires_at <= now() then
    raise exception 'This invitation has expired' using errcode = '22023';
  end if;

  if not coalesce(accept, false) then
    update public.group_invitations i
    set status = 'declined', responded_at = now()
    where i.id = invitation.id;
    return null;
  end if;

  if public.are_users_blocked(current_user_id, invitation.inviter_id) then
    raise exception 'This invitation is no longer available'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.conversations c
    where c.id = invitation.conversation_id
      and c.type = 'group'
  ) then
    raise exception 'This group no longer exists' using errcode = '22023';
  end if;

  insert into public.conversation_members (conversation_id, user_id, role)
  values (invitation.conversation_id, current_user_id, 'member')
  on conflict (conversation_id, user_id) do nothing;

  update public.group_invitations i
  set status = 'accepted', responded_at = now()
  where i.id = invitation.id;

  return invitation.conversation_id;
end;
$$;

revoke execute on function public.respond_group_invitation(uuid, boolean) from public, anon;
grant execute on function public.respond_group_invitation(uuid, boolean) to authenticated;
