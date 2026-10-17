-- Contact cards: a person or a circle sent as a card message.
--
-- send_contact_card(conversation, kind, id) stores an ordinary 'text' message
-- whose attachment is the card, like the note, task and list cards of
-- 202610170061:
--
--   * kind 'user': {kind: 'contact_card', card: 'user', user_id, name,
--     username, avatar_url}. The sender must be allowed to see that profile
--     (can_view_profile_details, 202610170101: the setting "who can see my
--     profile", and blocks in both directions), so a card never carries a
--     person who hid from the sender, and nobody the sender blocked or who
--     blocked them. The card holds only what chat already shows of anyone
--     (name, @username, avatar); the profile behind it is read through
--     get_profile_summary, which applies the same rules to whoever taps it.
--   * kind 'circle': {kind: 'contact_card', card: 'circle', circle_id, name,
--     avatar_url, member_count, invite_code}. The sender needs the circle's
--     Create invites permission, exactly like create_circle_invite; the card
--     carries an invite (an unexpired one the sender made for cards is
--     reused, else a 7-day invite is created, with an audit entry as for any
--     invite), and tapping it opens the existing invite page (preview and
--     Join). Revoking the invite stops the card from working.

create or replace function public.send_contact_card(
  target_conversation_id uuid,
  card_kind text,
  card_target_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  profile_row public.profiles%rowtype;
  circle_row public.circles%rowtype;
  member_total integer;
  invite_code text;
  card jsonb;
  label text;
  created_message_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if card_kind not in ('user', 'circle') or card_target_id is null then
    raise exception 'Unknown contact card' using errcode = '22023';
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

  if card_kind = 'user' then
    select * into profile_row
    from public.profiles p
    where p.id = card_target_id
      and p.deleted_at is null;

    if profile_row.id is null
      or public.are_users_blocked(current_user_id, card_target_id)
      or not public.can_view_profile_details(card_target_id)
    then
      raise exception 'This contact cannot be shared' using errcode = '42501';
    end if;

    label := profile_row.display_name;
    card := jsonb_strip_nulls(jsonb_build_object(
      'kind', 'contact_card',
      'card', 'user',
      'user_id', profile_row.id,
      'name', profile_row.display_name,
      'username', profile_row.username,
      'avatar_url', profile_row.avatar_url
    ));
  else
    select * into circle_row
    from public.circles c
    where c.id = card_target_id;

    if circle_row.id is null
      or not public.current_user_has_circle_permission(
        card_target_id,
        'create_invites'
      )
    then
      raise exception 'This circle cannot be shared' using errcode = '42501';
    end if;

    select ci.code
    into invite_code
    from public.circle_invites ci
    where ci.circle_id = card_target_id
      and ci.created_by = current_user_id
      and ci.revoked_at is null
      and ci.max_uses is null
      and ci.expires_at > now() + interval '1 day'
      and ci.expires_at < now() + interval '8 days'
    order by ci.created_at desc
    limit 1;

    if invite_code is null then
      invite_code := public.create_circle_invite(card_target_id, 168, null);
    end if;

    select count(*)
    into member_total
    from public.circle_members cm
    where cm.circle_id = card_target_id;

    label := circle_row.name;
    card := jsonb_strip_nulls(jsonb_build_object(
      'kind', 'contact_card',
      'card', 'circle',
      'circle_id', circle_row.id,
      'name', circle_row.name,
      'avatar_url', circle_row.avatar_url,
      'member_count', member_total,
      'invite_code', invite_code
    ));
  end if;

  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (
    target_conversation_id,
    current_user_id,
    'text',
    'Contact card: ' || label,
    card
  )
  returning id into created_message_id;

  return created_message_id;
end;
$$;

revoke execute on function public.send_contact_card(uuid, text, uuid)
  from public, anon;
grant execute on function public.send_contact_card(uuid, text, uuid)
  to authenticated;
