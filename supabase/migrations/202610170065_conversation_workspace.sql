-- What a conversation's Notes and Lists hold, in one call: for the badges
-- on the chat header's buttons and the pinned note banner.
--
--   {
--     "notes": <number of notes>,
--     "pinned_note": <note, as get_pinned_note> | null,
--     "lists": <number of lists>,
--     "open_tasks": <open items>,
--     "mine": <open items assigned to the caller>,
--     "overdue": <open items past their due date>,
--     "can_create": <the caller can send here>
--   }

create or replace function public.get_conversation_workspace(p_conversation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  pinned_row public.notes%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.is_current_user_conversation_member(p_conversation_id) then
    raise exception 'Conversation not found' using errcode = '42501';
  end if;

  select * into pinned_row
  from public.notes
  where conversation_id = p_conversation_id and pinned and deleted_at is null;

  return jsonb_build_object(
    'notes', (
      select count(*) from public.notes
      where conversation_id = p_conversation_id and deleted_at is null
    ),
    'pinned_note', case when pinned_row.id is null then null else public.note_json(pinned_row) end,
    'lists', (
      select count(*) from public.task_lists
      where conversation_id = p_conversation_id and deleted_at is null
    ),
    'open_tasks', (
      select count(*)
      from public.task_items i
      join public.task_lists l on l.id = i.list_id and l.deleted_at is null
      where l.conversation_id = p_conversation_id
        and i.deleted_at is null and i.completed_at is null
    ),
    'mine', (
      select count(*)
      from public.task_items i
      join public.task_lists l on l.id = i.list_id and l.deleted_at is null
      where l.conversation_id = p_conversation_id
        and i.deleted_at is null and i.completed_at is null
        and exists (
          select 1 from public.task_item_assignees a
          where a.item_id = i.id and a.user_id = auth.uid()
        )
    ),
    'overdue', (
      select count(*)
      from public.task_items i
      join public.task_lists l on l.id = i.list_id and l.deleted_at is null
      where l.conversation_id = p_conversation_id
        and i.deleted_at is null and i.completed_at is null
        and i.due_at < now()
    ),
    'can_create', public.can_current_user_write_docs(p_conversation_id)
  );
end;
$$;

revoke execute on function public.get_conversation_workspace(uuid) from public, anon;
grant execute on function public.get_conversation_workspace(uuid) to authenticated;
