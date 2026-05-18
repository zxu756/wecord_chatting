create or replace function public.recall_message(
  target_message_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  recalled_conversation_id uuid;
begin
  update public.messages m
  set recalled_at = now()
  where m.id = target_message_id
    and m.sender_id = auth.uid()
    and public.is_current_user_conversation_member(m.conversation_id)
  returning m.conversation_id into recalled_conversation_id;

  if recalled_conversation_id is null then
    raise exception 'Message not found or cannot be deleted'
      using errcode = '42501';
  end if;
end;
$$;
