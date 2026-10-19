-- Urgent messages (A7, part 2 of 4): the functions.
--
-- send_message_urgent(message, people): the sender of a message makes it
-- urgent for people in the conversation.
--
--   * Only your own message, one that can still be seen: not deleted, not
--     expired, not waiting for review, not a system line or a webhook post.
--   * You must still be able to send in the conversation (so a muted,
--     timed-out or banned member can not use it to be heard).
--   * Who: at most 10 people each time, members of the conversation who can
--     see it, never yourself or a bot. Quietly left out: people who blocked
--     you or whom you blocked, and people who turned urgent messages off for
--     you (urgent_sender_mutes). Left out people are not told apart from
--     the others, so nobody learns that they were muted; if nobody is left
--     the call fails with nobody_to_urgent (so in a direct chat with a
--     blocked person it can not be used).
--   * 5 times in any 24 hours per sender (rate_limited, 53400). A call that
--     reaches nobody does not use one up.
--   * A person already made urgent for the message is skipped (it stays
--     urgent once for them).
--   It returns how many people were told, and wakes the scheduled-dispatch
--   function, which pushes within seconds (claim_urgent_pushes,
--   202610240430). The push breaks through quiet hours, Do Not Disturb and
--   mutes (the function does not apply them to urgent pushes), and goes out
--   a second time 10 minutes later while the person has not confirmed.
--
-- ack_message_urgent(message): the person confirms ("Got it"). The second
-- push is not sent once they did.
--
-- list_my_pending_urgents(conversation): the urgent messages waiting for the
-- caller's confirmation (the red banner and the Notifications card), for one
-- conversation or all. Gone once confirmed, or when the message is deleted,
-- expired, hidden, or the caller left or blocked the sender; after 7 days.
--
-- get_message_urgent_status(message): the sender sees who they made it
-- urgent for and who confirmed.
--
-- set_urgent_from_sender(sender, allowed): "Don't allow urgent messages from
-- this person" and its undo. Turning it off also confirms what is waiting
-- from that person.
-- list_urgent_muted_senders(): the people turned off, for the settings page.
-- my_urgent_quota(): used and allowed in the last 24 hours.

create or replace function public.send_message_urgent(
  p_message_id uuid,
  p_target_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  me uuid := auth.uid();
  message public.messages%rowtype;
  wanted uuid[];
  valid uuid[];
  urgent_id uuid;
  inserted integer;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select m.* into message from public.messages m where m.id = p_message_id;
  if message.id is null then
    raise exception 'Message not found' using errcode = 'P0002';
  end if;
  if message.sender_id is distinct from me then
    raise exception 'Only the sender can make a message urgent'
      using errcode = '42501';
  end if;
  if message.recalled_at is not null
    or message.type = 'system'
    or message.webhook_id is not null
    or message.review_state is not null
    or (message.expires_at is not null and message.expires_at <= now())
    or exists (
      select 1 from public.note_to_self_conversations n
      where n.conversation_id = message.conversation_id
    )
  then
    raise exception 'This message can not be made urgent' using errcode = '22023';
  end if;
  if not public.can_current_user_send_in_conversation(message.conversation_id) then
    raise exception 'Cannot send messages in this conversation'
      using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct t), array[]::uuid[])
  into wanted
  from unnest(coalesce(p_target_ids, array[]::uuid[])) t
  where t is not null and t <> me;
  if cardinality(wanted) = 0 then
    raise exception 'nobody_to_urgent';
  end if;
  if cardinality(wanted) > 10 then
    raise exception 'too_many_targets' using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(wanted) w
    where not exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id = message.conversation_id and cm.user_id = w
    )
  ) then
    raise exception 'Only members of the conversation can be made urgent'
      using errcode = '42501';
  end if;

  -- Two taps at once count once each.
  perform pg_advisory_xact_lock(hashtextextended('urgent:' || me::text, 0));

  if (
    select count(*)
    from public.message_urgents u
    where u.sender_id = me and u.created_at > now() - interval '24 hours'
  ) >= 5 then
    raise exception 'rate_limited' using errcode = '53400';
  end if;

  select coalesce(array_agg(cm.user_id), array[]::uuid[])
  into valid
  from public.conversation_members cm
  join public.profiles p on p.id = cm.user_id
  where cm.conversation_id = message.conversation_id
    and cm.user_id = any (wanted)
    and not p.is_bot
    and not public.are_users_blocked(me, cm.user_id)
    and not exists (
      select 1 from public.urgent_sender_mutes s
      where s.user_id = cm.user_id and s.sender_id = me
    )
    and not public.conversation_in_suspended_circle(message.conversation_id)
    and public.user_has_conversation_channel_permission(
      message.conversation_id, cm.user_id, 'view_channel'
    );
  if cardinality(valid) = 0 then
    raise exception 'nobody_to_urgent';
  end if;

  insert into public.message_urgents (message_id, conversation_id, sender_id)
  values (message.id, message.conversation_id, me)
  returning id into urgent_id;

  insert into public.message_urgent_targets (urgent_id, message_id, user_id)
  select urgent_id, message.id, v
  from unnest(valid) v
  on conflict (message_id, user_id) do nothing;
  get diagnostics inserted = row_count;

  if inserted = 0 then
    -- All of them were made urgent before: nothing new, nothing used up.
    raise exception 'nobody_to_urgent';
  end if;

  perform public.wake_scheduled_dispatch();
  return inserted;
end;
$$;

revoke execute on function public.send_message_urgent(uuid, uuid[]) from public, anon;
grant execute on function public.send_message_urgent(uuid, uuid[]) to authenticated;

create or replace function public.ack_message_urgent(p_message_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  confirmed integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  update public.message_urgent_targets t
  set acked_at = now()
  where t.message_id = p_message_id
    and t.user_id = auth.uid()
    and t.acked_at is null;
  get diagnostics confirmed = row_count;
  return confirmed;
end;
$$;

revoke execute on function public.ack_message_urgent(uuid) from public, anon;
grant execute on function public.ack_message_urgent(uuid) to authenticated;

create or replace function public.list_my_pending_urgents(
  p_conversation_id uuid default null
)
returns table (
  urgent_id uuid,
  message_id uuid,
  conversation_id uuid,
  sender_id uuid,
  sender_display_name text,
  sender_avatar_url text,
  body text,
  type text,
  message_created_at timestamptz,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    t.urgent_id,
    t.message_id,
    u.conversation_id,
    u.sender_id,
    coalesce(nullif(btrim(ca.alias), ''), nullif(btrim(p.display_name), ''), p.username),
    p.avatar_url,
    left(btrim(coalesce(m.body, '')), 200),
    m.type,
    m.created_at,
    t.created_at
  from public.message_urgent_targets t
  join public.message_urgents u on u.id = t.urgent_id
  join public.messages m on m.id = t.message_id
  join public.profiles p on p.id = u.sender_id
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid() and ca.friend_id = u.sender_id
  where auth.uid() is not null
    and t.user_id = auth.uid()
    and t.acked_at is null
    and t.created_at > now() - interval '7 days'
    and (p_conversation_id is null or u.conversation_id = p_conversation_id)
    and m.recalled_at is null
    and (m.expires_at is null or m.expires_at > now())
    and public.message_visible_to_current_user(
      m.review_state, m.sender_id, m.conversation_id
    )
    and exists (
      select 1
      from public.conversation_members me
      where me.conversation_id = u.conversation_id
        and me.user_id = auth.uid()
    )
    and not public.are_users_blocked(auth.uid(), u.sender_id)
    and not exists (
      select 1 from public.urgent_sender_mutes s
      where s.user_id = auth.uid() and s.sender_id = u.sender_id
    )
  order by t.created_at desc, t.urgent_id
  limit 50;
$$;

revoke execute on function public.list_my_pending_urgents(uuid) from public, anon;
grant execute on function public.list_my_pending_urgents(uuid) to authenticated;

create or replace function public.get_message_urgent_status(p_message_id uuid)
returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
  urgent_at timestamptz,
  acked_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.messages m
    where m.id = p_message_id and m.sender_id = auth.uid()
  ) then
    raise exception 'Only the sender can see this' using errcode = '42501';
  end if;

  return query
  select
    t.user_id,
    coalesce(nullif(btrim(ca.alias), ''), nullif(btrim(p.display_name), ''), p.username),
    p.avatar_url,
    t.created_at,
    t.acked_at
  from public.message_urgent_targets t
  join public.profiles p on p.id = t.user_id
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid() and ca.friend_id = t.user_id
  where t.message_id = p_message_id
    and exists (
      select 1 from public.conversation_members cm
      join public.messages m on m.id = t.message_id
      where cm.conversation_id = m.conversation_id and cm.user_id = t.user_id
    )
    and not public.are_users_blocked(auth.uid(), t.user_id)
  order by t.created_at, t.user_id;
end;
$$;

revoke execute on function public.get_message_urgent_status(uuid) from public, anon;
grant execute on function public.get_message_urgent_status(uuid) to authenticated;

create or replace function public.set_urgent_from_sender(
  p_sender_id uuid,
  p_allowed boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_sender_id is null or p_sender_id = auth.uid() then
    raise exception 'Invalid sender' using errcode = '22023';
  end if;

  if coalesce(p_allowed, true) then
    delete from public.urgent_sender_mutes s
    where s.user_id = auth.uid() and s.sender_id = p_sender_id;
    return;
  end if;

  insert into public.urgent_sender_mutes (user_id, sender_id)
  values (auth.uid(), p_sender_id)
  on conflict do nothing;

  -- What is waiting from them is no longer urgent for me.
  update public.message_urgent_targets t
  set acked_at = now()
  from public.message_urgents u
  where u.id = t.urgent_id
    and u.sender_id = p_sender_id
    and t.user_id = auth.uid()
    and t.acked_at is null;
end;
$$;

revoke execute on function public.set_urgent_from_sender(uuid, boolean) from public, anon;
grant execute on function public.set_urgent_from_sender(uuid, boolean) to authenticated;

create or replace function public.list_urgent_muted_senders()
returns table (
  sender_id uuid,
  display_name text,
  avatar_url text,
  muted_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    s.sender_id,
    coalesce(nullif(btrim(ca.alias), ''), nullif(btrim(p.display_name), ''), p.username),
    p.avatar_url,
    s.created_at
  from public.urgent_sender_mutes s
  join public.profiles p on p.id = s.sender_id
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid() and ca.friend_id = s.sender_id
  where auth.uid() is not null
    and s.user_id = auth.uid()
  order by s.created_at desc
  limit 200;
$$;

revoke execute on function public.list_urgent_muted_senders() from public, anon;
grant execute on function public.list_urgent_muted_senders() to authenticated;

create or replace function public.my_urgent_quota()
returns table (used integer, allowed integer)
language sql
stable
security definer
set search_path = public
as $$
  select
    (
      select count(*)::integer
      from public.message_urgents u
      where u.sender_id = auth.uid()
        and u.created_at > now() - interval '24 hours'
    ),
    5;
$$;

revoke execute on function public.my_urgent_quota() from public, anon;
grant execute on function public.my_urgent_quota() to authenticated;
