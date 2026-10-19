-- Announcements that need a confirmation (A7, part 3 of 4): the functions.
--
-- Groups only (a group's announcement is what conversations.announcement
-- holds; direct chats have none, and a circle channel keeps its topic
-- elsewhere). update_group_profile (202605190003) is not touched: the text
-- is saved as before and this asks for confirmations on top of it.
--
-- set_announcement_requires_ack(group, required): the owner or an admin asks
--   members to confirm, or stops asking. Turning it on needs an announcement,
--   counts the person asking as confirmed, and asks everyone else once (the
--   push of claim_announcement_ack_pushes, which counts as a reminder for the
--   limit below). Turning it off clears the confirmations (a trigger of
--   202610240400); so does a new announcement text.
-- ack_announcement(group): a member confirms.
-- get_announcement_ack_state(group): for any member, "12 of 30 confirmed" and
--   whether they did; can_manage and the next time a reminder is allowed.
-- list_announcement_ack_members(group): the owner and admins see who
--   confirmed and who did not.
-- remind_announcement_unacked(group): the owner or an admin asks the members
--   who have not confirmed. At most once every 6 hours for a group
--   (rate_limited, 53400), and not when nobody is left (nobody_to_remind).
--   Blocked people (either way) and bots are left out.
-- list_my_pending_announcement_acks(): the caller's groups with an
--   announcement waiting for their confirmation (the Notifications card).
--
-- Bots (profiles.is_bot) are not counted as members here, since they can not
-- confirm. Everyone else in the group is.

create or replace function public.announcement_ack_member_ids(
  p_conversation_id uuid
)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select cm.user_id
  from public.conversation_members cm
  join public.profiles p on p.id = cm.user_id
  where cm.conversation_id = p_conversation_id
    and not p.is_bot;
$$;

revoke execute on function public.announcement_ack_member_ids(uuid)
  from public, anon, authenticated;
grant execute on function public.announcement_ack_member_ids(uuid) to service_role;

-- Asks the members who have not confirmed, once. Returns how many.
create or replace function public.queue_announcement_ack_reminders(
  p_conversation_id uuid,
  p_sender_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  queued integer;
begin
  insert into public.announcement_ack_reminders (conversation_id, user_id, sender_id)
  select p_conversation_id, m, p_sender_id
  from public.announcement_ack_member_ids(p_conversation_id) m
  where m <> p_sender_id
    and not exists (
      select 1 from public.announcement_acks a
      where a.conversation_id = p_conversation_id and a.user_id = m
    )
    and not public.are_users_blocked(p_sender_id, m);
  get diagnostics queued = row_count;

  if queued > 0 then
    update public.conversations c
    set announcement_ack_reminded_at = now()
    where c.id = p_conversation_id;
    perform public.wake_scheduled_dispatch();
  end if;
  return queued;
end;
$$;

revoke execute on function public.queue_announcement_ack_reminders(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.queue_announcement_ack_reminders(uuid, uuid)
  to service_role;

create or replace function public.set_announcement_requires_ack(
  p_conversation_id uuid,
  p_required boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  me uuid := auth.uid();
  conv public.conversations%rowtype;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select c.* into conv
  from public.conversations c
  where c.id = p_conversation_id and c.type = 'group'
  for update;
  if conv.id is null or not exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = conv.id
      and cm.user_id = me
      and cm.role in ('owner', 'admin')
  ) then
    raise exception 'Group conversation not found or cannot be updated'
      using errcode = '42501';
  end if;

  if coalesce(p_required, false) = conv.announcement_requires_ack then
    return;
  end if;

  if coalesce(p_required, false) then
    if btrim(coalesce(conv.announcement, '')) = '' then
      raise exception 'empty_announcement' using errcode = '22023';
    end if;
    update public.conversations c
    set announcement_requires_ack = true
    where c.id = conv.id;
    -- Whoever asks has read it.
    insert into public.announcement_acks (conversation_id, user_id)
    values (conv.id, me)
    on conflict do nothing;
    perform public.queue_announcement_ack_reminders(conv.id, me);
  else
    update public.conversations c
    set announcement_requires_ack = false
    where c.id = conv.id;
  end if;
end;
$$;

revoke execute on function public.set_announcement_requires_ack(uuid, boolean)
  from public, anon;
grant execute on function public.set_announcement_requires_ack(uuid, boolean)
  to authenticated;

create or replace function public.ack_announcement(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.conversations c
    join public.conversation_members cm on cm.conversation_id = c.id
    where c.id = p_conversation_id
      and c.type = 'group'
      and cm.user_id = auth.uid()
  ) then
    raise exception 'Group conversation not found' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.conversations c
    where c.id = p_conversation_id and c.announcement_requires_ack
  ) then
    raise exception 'This announcement does not need a confirmation'
      using errcode = '22023';
  end if;
  insert into public.announcement_acks (conversation_id, user_id)
  values (p_conversation_id, auth.uid())
  on conflict do nothing;
end;
$$;

revoke execute on function public.ack_announcement(uuid) from public, anon;
grant execute on function public.ack_announcement(uuid) to authenticated;

create or replace function public.get_announcement_ack_state(
  p_conversation_id uuid
)
returns table (
  requires_ack boolean,
  total integer,
  acked integer,
  i_acked boolean,
  can_manage boolean,
  next_reminder_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  conv public.conversations%rowtype;
  my_role text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cm.role into my_role
  from public.conversation_members cm
  where cm.conversation_id = p_conversation_id and cm.user_id = auth.uid();
  select c.* into conv
  from public.conversations c
  where c.id = p_conversation_id and c.type = 'group';
  if conv.id is null or my_role is null then
    raise exception 'Group conversation not found' using errcode = '42501';
  end if;

  return query
  select
    conv.announcement_requires_ack,
    case when conv.announcement_requires_ack then (
      select count(*)::integer
      from public.announcement_ack_member_ids(conv.id) m
    ) else 0 end,
    case when conv.announcement_requires_ack then (
      select count(*)::integer
      from public.announcement_ack_member_ids(conv.id) m
      join public.announcement_acks a
        on a.conversation_id = conv.id and a.user_id = m
    ) else 0 end,
    exists (
      select 1 from public.announcement_acks a
      where a.conversation_id = conv.id and a.user_id = auth.uid()
    ),
    my_role in ('owner', 'admin'),
    case
      when my_role in ('owner', 'admin')
        and conv.announcement_requires_ack
        and conv.announcement_ack_reminded_at is not null
      then conv.announcement_ack_reminded_at + interval '6 hours'
    end;
end;
$$;

revoke execute on function public.get_announcement_ack_state(uuid) from public, anon;
grant execute on function public.get_announcement_ack_state(uuid) to authenticated;

create or replace function public.list_announcement_ack_members(
  p_conversation_id uuid
)
returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
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
    select 1
    from public.conversations c
    join public.conversation_members cm on cm.conversation_id = c.id
    where c.id = p_conversation_id
      and c.type = 'group'
      and cm.user_id = auth.uid()
      and cm.role in ('owner', 'admin')
  ) then
    raise exception 'Only the owner and admins can see who confirmed'
      using errcode = '42501';
  end if;

  return query
  select
    m,
    coalesce(nullif(btrim(ca.alias), ''), nullif(btrim(p.display_name), ''), p.username),
    p.avatar_url,
    a.acked_at
  from public.announcement_ack_member_ids(p_conversation_id) m
  join public.profiles p on p.id = m
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid() and ca.friend_id = m
  left join public.announcement_acks a
    on a.conversation_id = p_conversation_id and a.user_id = m
  order by (a.acked_at is not null), a.acked_at, p.display_name, m;
end;
$$;

revoke execute on function public.list_announcement_ack_members(uuid) from public, anon;
grant execute on function public.list_announcement_ack_members(uuid) to authenticated;

create or replace function public.remind_announcement_unacked(
  p_conversation_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  me uuid := auth.uid();
  conv public.conversations%rowtype;
  queued integer;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select c.* into conv
  from public.conversations c
  where c.id = p_conversation_id and c.type = 'group'
  for update;
  if conv.id is null or not exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = conv.id
      and cm.user_id = me
      and cm.role in ('owner', 'admin')
  ) then
    raise exception 'Group conversation not found or cannot be updated'
      using errcode = '42501';
  end if;
  if not conv.announcement_requires_ack then
    raise exception 'This announcement does not need a confirmation'
      using errcode = '22023';
  end if;
  if conv.announcement_ack_reminded_at is not null
    and conv.announcement_ack_reminded_at > now() - interval '6 hours'
  then
    raise exception 'rate_limited' using errcode = '53400';
  end if;

  queued := public.queue_announcement_ack_reminders(conv.id, me);
  if queued = 0 then
    raise exception 'nobody_to_remind';
  end if;
  return queued;
end;
$$;

revoke execute on function public.remind_announcement_unacked(uuid) from public, anon;
grant execute on function public.remind_announcement_unacked(uuid) to authenticated;

create or replace function public.list_my_pending_announcement_acks()
returns table (
  conversation_id uuid,
  title text,
  announcement text,
  announcement_updated_at timestamptz,
  asked_by_name text,
  asked_by_avatar_url text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    coalesce(nullif(btrim(c.title), ''), 'Group'),
    left(btrim(c.announcement), 300),
    c.announcement_updated_at,
    p.display_name,
    p.avatar_url
  from public.conversations c
  join public.conversation_members cm
    on cm.conversation_id = c.id and cm.user_id = auth.uid()
  left join public.profiles p on p.id = c.announcement_updated_by
  where auth.uid() is not null
    and c.type = 'group'
    and c.announcement_requires_ack
    and btrim(coalesce(c.announcement, '')) <> ''
    and not exists (
      select 1 from public.announcement_acks a
      where a.conversation_id = c.id and a.user_id = auth.uid()
    )
  order by coalesce(c.announcement_updated_at, c.created_at) desc, c.id
  limit 50;
$$;

revoke execute on function public.list_my_pending_announcement_acks() from public, anon;
grant execute on function public.list_my_pending_announcement_acks() to authenticated;
