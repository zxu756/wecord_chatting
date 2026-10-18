-- Read receipts switch (A6, part 1 of 3).
--
-- user_privacy_settings.send_read_receipts (default true, as things were):
-- the person's choice to tell others when they have read their messages.
-- Like WhatsApp, it works both ways. With it off,
--
--   * others see them as "unknown" in a message's read list, and a direct
--     chat's "Read" never shows for what they read;
--   * they do not see anyone else's receipts either.
--
-- The server enforces it where the app learns who read what:
--
--   * list_read_markers(conversation): the read positions of a conversation,
--     as the caller may know them. The app uses it instead of selecting
--     conversation_members. Other people's positions come back empty when
--     the caller or that person has receipts off, or when the two block each
--     other. Only direct chats and groups of up to 200 members show other
--     people's positions at all; a circle channel, a thread or a bigger group
--     answers with the caller's own row only.
--   * get_message_read_status (202610220310) answers "unknown" for them.
--
-- Whether a person's own unread count and read position still move is not
-- touched: receipts are only about what others get to know.
--
-- Not redefined: mark_conversation_read, list_conversation_summaries and the
-- other functions that read last_read_message_id for the caller's own sake.

alter table public.user_privacy_settings
  add column if not exists send_read_receipts boolean not null default true;

-- Saves the caller's choice. Returns it.
create or replace function public.set_send_read_receipts(enabled boolean)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if enabled is null then
    raise exception 'A value is required' using errcode = '22023';
  end if;

  insert into public.user_privacy_settings (user_id, send_read_receipts)
  values (auth.uid(), enabled)
  on conflict (user_id) do update
  set send_read_receipts = excluded.send_read_receipts;

  return enabled;
end;
$$;

revoke execute on function public.set_send_read_receipts(boolean) from public, anon;
grant execute on function public.set_send_read_receipts(boolean) to authenticated;

-- Whether a person lets others know they read (true unless they turned it
-- off). For the functions below; the app has no use for it.
create or replace function public.read_receipts_enabled(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select s.send_read_receipts
      from public.user_privacy_settings s
      where s.user_id = target_user_id
    ),
    true
  );
$$;

revoke execute on function public.read_receipts_enabled(uuid) from public, anon, authenticated;
grant execute on function public.read_receipts_enabled(uuid) to service_role;

-- The read positions of a conversation, as the caller may know them.
create or replace function public.list_read_markers(target_conversation_id uuid)
returns table (
  user_id uuid,
  last_read_message_id uuid
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  current_user_id uuid := auth.uid();
  conversation_type text;
  member_total integer;
  may_see_others boolean;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id = target_conversation_id
      and cm.user_id = current_user_id
  ) then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  select c.type into conversation_type
  from public.conversations c
  where c.id = target_conversation_id;

  select count(*) into member_total
  from public.conversation_members cm
  where cm.conversation_id = target_conversation_id;

  -- Channels and threads are for many people; a group over 200 too.
  may_see_others := conversation_type in ('direct', 'group')
    and member_total <= 200
    and public.read_receipts_enabled(current_user_id)
    and not exists (
      select 1
      from public.note_to_self_conversations n
      where n.conversation_id = target_conversation_id
    );

  return query
  select
    cm.user_id,
    case
      when cm.user_id = current_user_id then cm.last_read_message_id
      when may_see_others
        and public.read_receipts_enabled(cm.user_id)
        and not public.are_users_blocked(current_user_id, cm.user_id)
      then cm.last_read_message_id
    end
  from public.conversation_members cm
  where cm.conversation_id = target_conversation_id
    and (
      cm.user_id = current_user_id
      or (conversation_type in ('direct', 'group') and member_total <= 200)
    );
end;
$$;

revoke execute on function public.list_read_markers(uuid) from public, anon;
grant execute on function public.list_read_markers(uuid) to authenticated;
