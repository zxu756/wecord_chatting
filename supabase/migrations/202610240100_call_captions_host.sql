-- Call captions (roadmap E1): who may turn captions on.
--
-- Captions are made on each person's own device and shared as text over the
-- call's LiveKit room, so there is nothing to store. What the server does
-- decide is who may START them, and it says so in a way nobody in the room can
-- fake: `livekit-token` asks this function when it mints a token and, for a
-- person who may, puts the participant attribute `cap = 1` in the (signed)
-- token. The apps only believe "captions are on" from a participant carrying
-- that attribute.
--
--  * a voice channel or stage: members who may mute members (the owner,
--    administrators and roles with that permission);
--  * a one-to-one call: either person;
--  * a group call: the person who started it, and the group's owner and
--    admins.
--
-- Nothing is written. The function only answers for the caller.

create or replace function public.can_current_user_host_captions(
  target_channel_id uuid default null,
  target_call_id uuid default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  channel_row public.circle_channels%rowtype;
  call_conversation uuid;
  call_starter uuid;
  conversation_kind text;
  member_role text;
begin
  if uid is null then
    return false;
  end if;

  if target_channel_id is not null then
    select cc.*
    into channel_row
    from public.circle_channels cc
    where cc.id = target_channel_id;

    if channel_row.id is null or channel_row.kind not in ('voice', 'stage') then
      return false;
    end if;
    return public.current_user_has_channel_permission(
        channel_row.id, 'connect_voice')
      and public.current_user_has_channel_permission(
        channel_row.id, 'mute_members');
  end if;

  if target_call_id is not null then
    select dc.conversation_id, dc.started_by, c.type
    into call_conversation, call_starter, conversation_kind
    from public.direct_calls dc
    join public.conversations c on c.id = dc.conversation_id
    where dc.id = target_call_id
      and dc.ended_at is null;

    if call_conversation is null
      or not public.can_current_user_call_in_conversation(call_conversation)
    then
      return false;
    end if;
    if conversation_kind = 'direct' then
      return true;
    end if;
    if call_starter = uid then
      return true;
    end if;
    select cm.role
    into member_role
    from public.conversation_members cm
    where cm.conversation_id = call_conversation
      and cm.user_id = uid;
    return coalesce(member_role in ('owner', 'admin'), false);
  end if;

  return false;
end;
$$;

revoke execute on function public.can_current_user_host_captions(uuid, uuid)
  from public, anon;
grant execute on function public.can_current_user_host_captions(uuid, uuid)
  to authenticated;
