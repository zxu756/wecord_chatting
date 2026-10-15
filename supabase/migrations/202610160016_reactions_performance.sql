-- Faster reactions on the chat page.
--
-- The chat page loaded every message with the reactions computed field,
-- and reactions() checked is_current_user_conversation_member once per
-- reaction row. In circle channels that check works out the caller's
-- channel permissions (roles and overwrites), so a busy channel did that
-- work tens of thousands of times per load, and every reaction anyone
-- added reloads the page.
--
-- * list_conversation_reactions(conversation_id) returns the reactions of
--   every message of a conversation in one pass ({message_id, reactions},
--   reactions as reactions() returns them; messages without reactions
--   are left out), checking membership once. The chat page uses it
--   instead of the computed field.
-- * message_reactions_conversation_message_idx covers it: the rows of a
--   conversation come out grouped by message and emoji, from the index
--   alone. It replaces message_reactions_conversation_idx, which the
--   realtime filter and the cascade from conversations use the same way.
-- * reactions() itself (still used elsewhere and by older clients)
--   answers [] from the primary key for messages without reactions,
--   checks membership once per message, and reads only reactions stored
--   under the message's own conversation, so a forged row cannot borrow
--   another conversation's membership. Its output is unchanged.

create index if not exists message_reactions_conversation_message_idx
  on public.message_reactions (conversation_id, message_id, emoji)
  include (user_id, created_at);

drop index if exists public.message_reactions_conversation_idx;

-- Same as 202610130026_circle_emojis, but cheaper (see above).
create or replace function public.reactions(message_row public.messages)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case
    when message_row.recalled_at is not null then '[]'::jsonb
    when not exists (
      select 1
      from public.message_reactions mr
      where mr.message_id = message_row.id
    ) then '[]'::jsonb
    -- Messages deleted before 202610130027 may still have reactions.
    when exists (
      select 1
      from public.messages m
      where m.id = message_row.id
        and m.recalled_at is not null
    ) then '[]'::jsonb
    when not public.is_current_user_conversation_member(
      message_row.conversation_id
    ) then '[]'::jsonb
    else (
      select coalesce(
        jsonb_agg(
          jsonb_strip_nulls(jsonb_build_object(
            'emoji', grouped.emoji,
            'count', grouped.reaction_count,
            'reacted_by_me', grouped.reacted_by_me,
            'custom_name', custom_emoji.name
          ))
          order by grouped.first_reacted_at, grouped.emoji
        ),
        '[]'::jsonb
      )
      from (
        select
          mr.emoji,
          count(*)::integer as reaction_count,
          coalesce(bool_or(mr.user_id = auth.uid()), false) as reacted_by_me,
          min(mr.created_at) as first_reacted_at
        from public.message_reactions mr
        where mr.message_id = message_row.id
          and mr.conversation_id = message_row.conversation_id
        group by mr.emoji
      ) grouped
      left join public.circle_emojis custom_emoji
        on custom_emoji.id = case
          when grouped.emoji ~ '^custom:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            then substr(grouped.emoji, 8)::uuid
        end
    )
  end;
$$;

create or replace function public.list_conversation_reactions(
  target_conversation_id uuid
)
returns table (message_id uuid, reactions jsonb)
language sql
stable
security definer
set search_path = public
as $$
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
      -- Evaluated once: it does not depend on the row.
      and public.is_current_user_conversation_member(target_conversation_id)
    group by mr.message_id, mr.emoji
  ) grouped
  left join public.circle_emojis custom_emoji
    on custom_emoji.id = case
      when grouped.emoji ~ '^custom:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then substr(grouped.emoji, 8)::uuid
    end
  group by grouped.message_id;
$$;

revoke execute on function public.list_conversation_reactions(uuid) from public;
revoke execute on function public.list_conversation_reactions(uuid) from anon;
grant execute on function public.reactions(public.messages) to authenticated;
grant execute on function public.list_conversation_reactions(uuid) to authenticated;
