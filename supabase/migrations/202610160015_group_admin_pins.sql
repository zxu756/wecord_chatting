-- Group admins can pin.
--
-- In group chats only the owner could pin and unpin messages; admins now
-- can too, as they already manage members and the announcement.
-- pin_message, unpin_message and the clients all ask
-- can_current_user_pin_messages, so this is the only change.

-- Same as 202610130016_channel_permission_fixes, but in groups admins may
-- pin as well as the owner.
create or replace function public.can_current_user_pin_messages(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select case c.type
        when 'direct' then public.is_current_user_conversation_member(c.id)
        when 'group' then exists (
          select 1
          from public.conversation_members cm
          where cm.conversation_id = c.id
            and cm.user_id = auth.uid()
            and cm.role in ('owner', 'admin')
        )
        when 'channel' then public.is_current_user_conversation_member(c.id)
          and exists (
            select 1
            from public.circle_channels ch
            where ch.conversation_id = c.id
              and public.current_user_has_channel_permission(
                ch.id,
                'manage_messages'
              )
          )
        when 'thread' then public.is_current_user_conversation_member(c.id)
          and public.can_current_user_pin_messages(ct.parent_conversation_id)
        else false
      end
      from public.conversations c
      left join public.conversation_threads ct on ct.conversation_id = c.id
      where c.id = target_conversation_id
    ),
    false
  );
$$;

grant execute on function public.can_current_user_pin_messages(uuid) to authenticated;
