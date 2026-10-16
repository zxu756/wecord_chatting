-- Chat history in pages.
--
-- The chat page loaded every message of a conversation, with the
-- reactions of all of them. It now loads the newest page (about 50
-- messages) and older or newer pages as the reader scrolls, by keyset on
-- (created_at, id): `created_at <= $t and (created_at < $t or id < $id)`,
-- newest first (and the mirror image for newer pages). The first part is
-- the index range; the second only filters the rows at $t itself.
--
-- * messages_conversation_created_id_idx covers those pages in both
--   directions, and the newest message of a conversation. It replaces
--   messages_conversation_created_idx, which it extends with the id tie
--   breaker (two messages may share a created_at).
-- * list_conversation_reactions(conversation_id, message_ids) returns the
--   reactions of the given messages only (the loaded pages), in the same
--   shape and with the same membership check as the one-argument version,
--   which older clients keep using.

create index if not exists messages_conversation_created_id_idx
  on public.messages (conversation_id, created_at desc, id desc);

drop index if exists public.messages_conversation_created_idx;

create or replace function public.list_conversation_reactions(
  target_conversation_id uuid,
  target_message_ids uuid[]
)
returns table (message_id uuid, reactions jsonb)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if coalesce(cardinality(target_message_ids), 0) = 0 then
    return;
  end if;

  if cardinality(target_message_ids) > 500 then
    raise exception 'At most 500 messages at a time' using errcode = '22023';
  end if;

  -- Checked once: it does not depend on the row.
  if not public.is_current_user_conversation_member(target_conversation_id) then
    return;
  end if;

  return query
  select
    grouped.message_id,
    jsonb_agg(
      jsonb_strip_nulls(jsonb_build_object(
        'emoji', grouped.emoji,
        'count', grouped.reaction_count,
        'reacted_by_me', grouped.reacted_by_me,
        'custom_name', custom_emoji.name
      ))
      order by grouped.first_reacted_at, grouped.emoji
    )
  from (
    select
      mr.message_id,
      mr.emoji,
      count(*)::integer as reaction_count,
      coalesce(bool_or(mr.user_id = auth.uid()), false) as reacted_by_me,
      min(mr.created_at) as first_reacted_at
    from public.message_reactions mr
    join public.messages m
      on m.id = mr.message_id
      and m.conversation_id = target_conversation_id
      and m.recalled_at is null
    where mr.conversation_id = target_conversation_id
      and mr.message_id = any(target_message_ids)
    group by mr.message_id, mr.emoji
  ) grouped
  left join public.circle_emojis custom_emoji
    on custom_emoji.id = case
      when grouped.emoji ~ '^custom:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then substr(grouped.emoji, 8)::uuid
    end
  group by grouped.message_id;
end;
$$;

revoke execute on function public.list_conversation_reactions(uuid, uuid[]) from public;
revoke execute on function public.list_conversation_reactions(uuid, uuid[]) from anon;
grant execute on function public.list_conversation_reactions(uuid, uuid[]) to authenticated;
