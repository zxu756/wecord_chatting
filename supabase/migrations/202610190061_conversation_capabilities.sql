-- Performance: what the person may do in a conversation, in one request.
--
-- Opening a chat asked three times: can_current_user_pin_messages,
-- can_current_user_moderate_polls and can_current_user_moderate_messages
-- (and a fourth, can_current_user_manage_thread, in a thread). They are
-- answered together here by calling those same helpers, so the answers are
-- exactly theirs and every rule stays where it is defined. Latest
-- definitions: pin in 202610160015_group_admin_pins.sql, moderate polls in
-- 202610130023_polls.sql, moderate messages in
-- 202610130025_moderator_message_delete.sql, manage thread in
-- 202610130016_channel_permission_fixes.sql.
--
-- Someone who is not in the conversation (or nobody signed in) can do
-- nothing: all four are false, as the helpers say on their own.

create or replace function public.get_conversation_capabilities(
  target_conversation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  target_thread_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select ct.id
  into target_thread_id
  from public.conversation_threads ct
  where ct.conversation_id = target_conversation_id;

  return jsonb_build_object(
    'can_pin_messages',
      public.can_current_user_pin_messages(target_conversation_id),
    'can_moderate_polls',
      public.can_current_user_moderate_polls(target_conversation_id),
    'can_moderate_messages',
      public.can_current_user_moderate_messages(target_conversation_id),
    'can_manage_thread',
      case
        when target_thread_id is null then false
        else public.can_current_user_manage_thread(target_thread_id)
      end
  );
end;
$$;

revoke execute on function public.get_conversation_capabilities(uuid) from public, anon;
grant execute on function public.get_conversation_capabilities(uuid) to authenticated;
