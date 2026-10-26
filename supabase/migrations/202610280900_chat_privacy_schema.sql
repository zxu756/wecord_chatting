-- Advanced chat privacy (roadmap G6), part 1 of 4: the switch.
--
-- A direct chat or a group can be set so that what is said in it stays in it:
--
--   * no forwarding and no merged forwarding of its messages,
--   * no saving its messages for later (Saved),
--   * no adding its pictures and videos to the group space,
--   * no AI reading it: catch-up summaries, translation, "make tasks",
--     "ask AI", the @WeCord assistant and the daily digest all leave it out,
--   * the account data export leaves out what was said in it,
--   * the app hides copy, save-to-device, share and "copy text from picture".
--
-- What this cannot do, and the app says so: it cannot stop a screenshot, a
-- photo of the screen, or a person copying by hand. The first part is a
-- guard for the people who use the app as it is meant to be used; the data
-- never leaves the server for AI and exports.
--
-- Who may switch it:
--   * direct chat: either person. Each person switches their own request on
--     or off; the chat is restricted while at least one request is on, so one
--     person cannot undo what the other asked for.
--   * group: the owner and the admins. One switch for the whole group.
--
-- Columns of conversations (members read them with the rest of the row;
-- nobody writes them directly, only set_chat_restrict_sharing in
-- 202610280910 does):
--
--   restrict_sharing     whether the chat is restricted
--   restrict_sharing_by  who asked: both people of a direct chat can be in
--                        it; a group keeps the admin who last turned it on
--
-- A thread follows the chat it belongs to (conversation_restricts_sharing).

alter table public.conversations
  add column if not exists restrict_sharing boolean not null default false;

alter table public.conversations
  add column if not exists restrict_sharing_by uuid[] not null default '{}';

alter table public.conversations
  drop constraint if exists conversations_restrict_sharing_by_check;
alter table public.conversations
  add constraint conversations_restrict_sharing_by_check
  check (cardinality(restrict_sharing_by) <= 2);

-- Whether the chat, or the chat a thread belongs to, is restricted.
-- Internal: the server-side checks call it (they run as the function owner).
create or replace function public.conversation_restricts_sharing(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select c.restrict_sharing
    from public.conversations c
    where c.id = coalesce(
      (
        select ct.parent_conversation_id
        from public.conversation_threads ct
        where ct.conversation_id = p_conversation_id
      ),
      p_conversation_id
    )
  ), false);
$$;

revoke execute on function public.conversation_restricts_sharing(uuid)
  from public, anon, authenticated;
grant execute on function public.conversation_restricts_sharing(uuid)
  to service_role;
