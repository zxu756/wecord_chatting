-- Moments 2.0 (roadmap B2), part 5 of 6: sharing a Moment into a chat.
--
-- send_moment_card(conversation, post) stores an ordinary 'text' message
-- whose attachment is the card, like the contact, note and task cards:
--   {kind: 'moment_card', post_id}
-- and the body "[Moment]". The card holds NOTHING of the Moment: no words, no
-- picture, no name. Whoever opens the chat asks get_moment_card, which answers
-- only when that person may see the Moment right now
-- (moments_post_visible_to for them), so forwarding a Moment to someone its
-- audience leaves out shows "Can't view this Moment", and unfriending,
-- blocking, "Don't let them see my Moments", the visible range and deleting
-- the post all take effect at once. Tapping a card opens the Moment, which is
-- read through the same rules (moments_feed).
--
-- The sender must be able to see the Moment (their own, or a friend's they may
-- see) and be allowed to write in the conversation (the contact card's
-- checks). The picture in the card is read through the moments bucket's own
-- select rule, so it cannot be fetched without the right to see the post.
--
-- card_body_zh (latest: 202610200010_push_text_language.sql) gains
-- 'moment_card' -> "[朋友圈]" so the push of such a message reads in Chinese
-- too; every card it already worded is copied unchanged.

create or replace function public.send_moment_card(
  target_conversation_id uuid,
  p_post_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  created_message_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_post_id is null then
    raise exception 'Unknown Moment' using errcode = '22023';
  end if;

  if not public.is_current_user_conversation_member(target_conversation_id)
    or not public.can_current_user_send_in_conversation(target_conversation_id)
  then
    raise exception 'You cannot send messages here' using errcode = '42501';
  end if;
  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Cannot send messages in this conversation'
      using errcode = '42501';
  end if;

  if not public.moments_can_view(p_post_id) then
    raise exception 'This Moment cannot be shared' using errcode = '42501';
  end if;

  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (
    target_conversation_id,
    current_user_id,
    'text',
    '[Moment]',
    jsonb_build_object('kind', 'moment_card', 'post_id', p_post_id)
  )
  returning id into created_message_id;

  return created_message_id;
end;
$$;

-- What a card in a chat shows, only while the caller may see the Moment: no
-- row means "Can't view this Moment".
create or replace function public.get_moment_card(p_post_id uuid)
returns table (
  post_id uuid,
  author_id uuid,
  author_name text,
  author_avatar_url text,
  kind text,
  excerpt text,
  thumb text,
  photo_count integer,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  return query
  select
    p.id,
    p.author_id,
    coalesce(nullif(btrim(ca.alias), ''), pr.display_name),
    pr.avatar_url,
    p.kind,
    left(p.body, 140),
    coalesce(p.photos->0->>'thumb', p.video->>'thumb'),
    jsonb_array_length(p.photos),
    p.created_at
  from public.moments_posts p
  join public.profiles pr on pr.id = p.author_id
  left join public.contact_aliases ca
    on ca.owner_id = me and ca.friend_id = p.author_id
  where p.id = p_post_id
    and public.moments_post_visible_to(me, p);
end;
$$;

revoke execute on function public.send_moment_card(uuid, uuid) from public, anon;
revoke execute on function public.get_moment_card(uuid) from public, anon;
grant execute on function public.send_moment_card(uuid, uuid) to authenticated;
grant execute on function public.get_moment_card(uuid) to authenticated;

-- card_body_zh (202610200010) plus the Moment card.
create or replace function public.card_body_zh(
  message_body text,
  message_attachment jsonb
)
returns text
language sql
immutable
set search_path = public
as $$
  select case message_attachment->>'kind'
    when 'live_location' then '[实时位置]'
    when 'chat_history' then
      '[聊天记录] ' || coalesce(message_attachment->>'title', '')
    when 'contact_card' then
      '[名片] ' || coalesce(message_attachment->>'name', '')
    when 'moment_card' then '[朋友圈]'
    when 'note' then
      coalesce(message_attachment->>'icon', '') || ' '
        || coalesce(nullif(btrim(message_attachment->>'title'), ''), '未命名笔记')
    when 'list' then
      coalesce(message_attachment->>'icon', '') || ' '
        || coalesce(nullif(btrim(message_attachment->>'title'), ''), '未命名列表')
    else message_body
  end;
$$;

revoke execute on function public.card_body_zh(text, jsonb) from public, anon, authenticated;
grant execute on function public.card_body_zh(text, jsonb) to service_role;
