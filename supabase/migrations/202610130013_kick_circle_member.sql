-- Kicking members out of a circle. Needs kick_members, and like Discord
-- the target must rank strictly below the caller (so nobody can kick the
-- owner). Members leave on their own, never through this RPC.
--
-- The kicked member leaves every channel conversation of the circle and
-- every thread under those channels, then the circle itself; removing the
-- circle_members row cascades to their assigned roles and notification
-- settings. Their messages, posts and invite links stay; they can rejoin
-- with a valid invite.
create or replace function public.kick_circle_member(
  target_circle_id uuid,
  target_user_id uuid
)
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

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'kick_members'
  ) then
    raise exception 'Only members who can kick members can kick members'
      using errcode = '42501';
  end if;

  -- Serialises with role changes, so the rank check below holds.
  perform 1 from public.circles where id = target_circle_id for no key update;

  if target_user_id = current_user_id then
    raise exception 'Leave the circle instead of kicking yourself'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = target_circle_id
      and cm.user_id = target_user_id
  ) then
    raise exception 'Circle member not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from public.circles c
    where c.id = target_circle_id
      and c.owner_id = target_user_id
  ) then
    raise exception 'The circle owner cannot be kicked' using errcode = '42501';
  end if;

  if public.circle_member_rank(target_circle_id, target_user_id)
    >= public.circle_member_rank(target_circle_id, current_user_id)
  then
    raise exception 'Cannot kick a member ranked at or above you'
      using errcode = '42501';
  end if;

  -- Threads first: the leave trigger on conversation_members would remove
  -- these too, but the kick should not depend on it.
  delete from public.conversation_members cm
  using public.conversation_threads ct
  join public.circle_channels cc on cc.conversation_id = ct.parent_conversation_id
  where cc.circle_id = target_circle_id
    and cm.conversation_id = ct.conversation_id
    and cm.user_id = target_user_id;

  delete from public.conversation_members cm
  using public.circle_channels cc
  where cc.circle_id = target_circle_id
    and cm.conversation_id = cc.conversation_id
    and cm.user_id = target_user_id;

  delete from public.circle_members cm
  where cm.circle_id = target_circle_id
    and cm.user_id = target_user_id;
end;
$$;

revoke execute on function public.kick_circle_member(uuid, uuid) from public;
revoke execute on function public.kick_circle_member(uuid, uuid) from anon;
grant execute on function public.kick_circle_member(uuid, uuid) to authenticated;
