-- Leaving a circle and handing it over.
--
-- leave_circle: any member but the owner leaves the circle, every channel
-- conversation of it and every thread under those channels, exactly like
-- kick_circle_member removes someone. Their messages, posts and invite
-- links stay; they can rejoin with a valid invite.
--
-- transfer_circle_ownership: the owner hands the circle to another member,
-- who becomes owner (in the circle and its channel conversations). The old
-- owner stays as a plain member without assigned roles, which can be
-- granted again. The owner has to do this before leaving.
create or replace function public.leave_circle(target_circle_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  -- Serialises with ownership transfers, so the owner check below holds.
  perform 1 from public.circles where id = target_circle_id for no key update;

  if not public.is_current_user_circle_member(target_circle_id) then
    raise exception 'Circle not found or caller is not a member'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.circles c
    where c.id = target_circle_id
      and c.owner_id = current_user_id
  ) then
    raise exception 'Transfer ownership before leaving the circle'
      using errcode = '42501';
  end if;

  delete from public.conversation_members cm
  using public.conversation_threads ct
  join public.circle_channels cc on cc.conversation_id = ct.parent_conversation_id
  where cc.circle_id = target_circle_id
    and cm.conversation_id = ct.conversation_id
    and cm.user_id = current_user_id;

  delete from public.conversation_members cm
  using public.circle_channels cc
  where cc.circle_id = target_circle_id
    and cm.conversation_id = cc.conversation_id
    and cm.user_id = current_user_id;

  delete from public.circle_members cm
  where cm.circle_id = target_circle_id
    and cm.user_id = current_user_id;
end;
$$;

create or replace function public.transfer_circle_ownership(
  target_circle_id uuid,
  new_owner_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  current_owner_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select c.owner_id into current_owner_id
  from public.circles c
  where c.id = target_circle_id
  for update;

  if current_owner_id is null or current_owner_id <> current_user_id then
    raise exception 'Only the circle owner can transfer ownership'
      using errcode = '42501';
  end if;

  if new_owner_id is null or new_owner_id = current_user_id then
    raise exception 'Choose another member to own the circle'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = target_circle_id
      and cm.user_id = new_owner_id
  ) then
    raise exception 'Circle member not found' using errcode = 'P0002';
  end if;

  update public.circles c
  set owner_id = new_owner_id
  where c.id = target_circle_id;

  update public.circle_members cm
  set role = case when cm.user_id = new_owner_id then 'owner' else 'member' end
  where cm.circle_id = target_circle_id
    and cm.user_id in (current_user_id, new_owner_id);

  delete from public.circle_member_roles mr
  where mr.circle_id = target_circle_id
    and mr.user_id = current_user_id;

  update public.conversation_members cm
  set role = case when cm.user_id = new_owner_id then 'owner' else 'member' end
  from public.circle_channels cc
  where cc.circle_id = target_circle_id
    and cm.conversation_id = cc.conversation_id
    and cm.user_id in (current_user_id, new_owner_id)
    and cm.role is distinct from
      case when cm.user_id = new_owner_id then 'owner' else 'member' end;
end;
$$;

revoke execute on function public.leave_circle(uuid) from public;
revoke execute on function public.leave_circle(uuid) from anon;
revoke execute on function public.transfer_circle_ownership(uuid, uuid) from public;
revoke execute on function public.transfer_circle_ownership(uuid, uuid) from anon;
grant execute on function public.leave_circle(uuid) to authenticated;
grant execute on function public.transfer_circle_ownership(uuid, uuid) to authenticated;
