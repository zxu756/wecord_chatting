-- AI reply suggestions and drafting from the chat (roadmap F6): what the `ai`
-- function's `draft_reply` action may read. One function, for the service
-- role only; the function calls it with the id of the person who asked, which
-- it took from their verified token. Nothing is stored: no table, no cache,
-- and so nothing to export or delete with an account.
--
-- The person taps "Help me reply" in the message box; the function reads the
-- last few messages of that chat as the person sees them, and the model writes
-- two or three replies that the app puts in the box (never sent for them).
--
-- What may be read: the same rules as Ask AI (202610250300), the assistant's
-- context (202610230420) and the daily digest (202610230520), and no looser:
--   * the person turned AI off in Settings (user_ai_settings): nothing;
--   * a chat the person cannot read right now
--     (current_user_readable_conversation_ids, taken as THEM by setting the
--     transaction's JWT claims): "not_found";
--   * a chat where the circle or the group's owner turned AI off
--     (conversation_ai_assistant_allowed; a thread follows its parent): "ai_off";
--   * a chat the person locked (App lock and chat lock, 202610260300, or the
--     thread of one): "locked". AI never reads a locked chat, even one the
--     person has just unlocked on their device - the server cannot tell;
--   * never recalled or expired messages, never messages waiting for or
--     removed by the AI guard or an edit review (review_state), never
--     view-once pictures, never notices, never the assistant's own replies,
--     never a sender the person blocked or who blocked them.
--   The person's own messages are included (they can see them) and marked.
--
-- ai_draft_context(person, chat, limit) answers one jsonb object:
--   {status: ok | user_off | ai_off | locked | not_found,
--    messages: [{id, sender, mine, type, body, attachment_name, webhook_name,
--                created_at}]}      -- oldest first, at most p_limit (1 to 30,
--                                   -- 20 by default); only with status ok.

create or replace function public.ai_draft_context(
  p_user_id uuid,
  p_conversation_id uuid,
  p_limit integer default 20
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  page_size integer := least(greatest(coalesce(p_limit, 20), 1), 30);
  items jsonb;
begin
  if p_user_id is null or p_conversation_id is null then
    return jsonb_build_object('status', 'not_found', 'messages', '[]'::jsonb);
  end if;

  if exists (
    select 1
    from public.user_ai_settings s
    where s.user_id = p_user_id and s.ai_enabled = false
  ) then
    return jsonb_build_object('status', 'user_off', 'messages', '[]'::jsonb);
  end if;

  -- From here on the visibility functions see the person.
  perform set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', p_user_id, 'role', 'authenticated')::text,
    true
  );

  if not exists (
    select 1
    from public.current_user_readable_conversation_ids() r(id)
    where r.id = p_conversation_id
  ) then
    return jsonb_build_object('status', 'not_found', 'messages', '[]'::jsonb);
  end if;

  if not public.conversation_ai_assistant_allowed(p_conversation_id) then
    return jsonb_build_object('status', 'ai_off', 'messages', '[]'::jsonb);
  end if;

  if public.is_conversation_locked(p_user_id, p_conversation_id) then
    return jsonb_build_object('status', 'locked', 'messages', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(q.item order by q.created_at, q.id), '[]'::jsonb)
  into items
  from (
    select
      m.id,
      m.created_at,
      jsonb_build_object(
        'id', m.id,
        'sender', coalesce(
          nullif(btrim(coalesce(m.webhook_name, '')), ''),
          nullif(btrim(coalesce(ca.alias, '')), ''),
          nullif(btrim(p.display_name), ''),
          p.username,
          'Someone'
        ),
        'mine', m.sender_id = p_user_id,
        'type', m.type,
        'body', coalesce(m.body, ''),
        'attachment_name', m.attachment->>'name',
        'webhook_name', m.webhook_name,
        'created_at', m.created_at
      ) as item
    from public.messages m
    left join public.profiles p on p.id = m.sender_id
    left join public.contact_aliases ca
      on ca.owner_id = p_user_id and ca.friend_id = m.sender_id
    where m.conversation_id = p_conversation_id
      and m.recalled_at is null
      and m.review_state is null
      and (m.expires_at is null or m.expires_at > now())
      and coalesce(m.attachment->>'view_once', '') <> 'true'
      and m.type <> 'system'
      and m.ai_reply is null
      and not public.are_users_blocked(m.sender_id, p_user_id)
    order by m.created_at desc, m.id desc
    limit page_size
  ) q;

  return jsonb_build_object('status', 'ok', 'messages', items);
end;
$$;

revoke execute on function public.ai_draft_context(uuid, uuid, integer)
  from public, anon, authenticated;
grant execute on function public.ai_draft_context(uuid, uuid, integer) to service_role;
