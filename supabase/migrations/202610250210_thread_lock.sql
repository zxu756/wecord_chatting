-- Moderator tools 2.0 (C5), part 2 of 9: locking a thread.
--
-- A locked thread (conversation_threads.locked_at) can still be read, and its
-- members can still react, but only people who manage messages in the
-- channel (manage_messages, the permission that already pins and archives)
-- can post in it. That covers forum posts, which are threads of a forum
-- channel. Locking is for circle channels only: a thread of a group chat has
-- no moderators.
--
-- * set_thread_locked(thread, locked): manage_messages in the thread's
--   channel, refused while a platform admin has the circle down (K1). It is
--   audited as thread_lock / thread_unlock when the state changes.
-- * messages_reject_locked_thread: a BEFORE INSERT trigger on messages, so
--   every way of sending (the REST insert, send_text_message, stickers,
--   scheduled sends, forwards) is covered. System notices and webhook posts
--   pass; so do the senders who manage messages in the channel. Bots do not:
--   a locked thread is quiet.
-- * get_thread_lock_state(conversation): what the thread page asks to show
--   the lock and to turn the composer into a notice. Kept apart from the
--   conversation summary on purpose, whose function other features rewrite.
--
-- Nothing existing is rewritten.

alter table public.conversation_threads
  add column if not exists locked_at timestamptz,
  add column if not exists locked_by uuid references public.profiles(id) on delete set null;

create or replace function public.set_thread_locked(
  target_thread_id uuid,
  locked boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  thread_row public.conversation_threads%rowtype;
  thread_channel public.circle_channels%rowtype;
  was_locked boolean;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select ct.* into thread_row
  from public.conversation_threads ct
  where ct.id = target_thread_id
  for update;

  if thread_row.id is null then
    raise exception 'Thread not found' using errcode = 'P0002';
  end if;

  select cc.* into thread_channel
  from public.circle_channels cc
  where cc.conversation_id = thread_row.parent_conversation_id;

  if thread_channel.id is null then
    raise exception 'Only threads in a circle can be locked'
      using errcode = '22023';
  end if;

  if not public.user_has_conversation_channel_permission(
    thread_row.parent_conversation_id,
    current_user_id,
    'manage_messages'
  ) or not exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = thread_channel.circle_id
      and cm.user_id = current_user_id
  ) then
    raise exception 'Only members who manage messages can lock a thread'
      using errcode = '42501';
  end if;

  perform public.assert_circle_up(thread_channel.circle_id);

  was_locked := thread_row.locked_at is not null;

  update public.conversation_threads ct
  set
    locked_at = case
      when set_thread_locked.locked then coalesce(ct.locked_at, now())
      else null
    end,
    locked_by = case
      when set_thread_locked.locked then coalesce(ct.locked_by, current_user_id)
      else null
    end
  where ct.id = target_thread_id
  returning * into thread_row;

  if was_locked <> (thread_row.locked_at is not null) then
    perform public.write_circle_audit(
      thread_channel.circle_id,
      case when thread_row.locked_at is null then 'thread_unlock' else 'thread_lock' end,
      'thread',
      thread_row.id,
      thread_row.title,
      jsonb_build_object(
        'channel_id', thread_channel.id,
        'channel_name', thread_channel.name
      )
    );
  end if;

  return jsonb_build_object(
    'thread_id', thread_row.id,
    'locked_at', thread_row.locked_at
  );
end;
$$;

-- Whether a thread is locked, and what the caller may do about it:
-- {thread_id, locked, locked_at, can_lock, can_post}. null when the
-- conversation is not a thread the caller belongs to.
create or replace function public.get_thread_lock_state(
  target_conversation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  thread_row public.conversation_threads%rowtype;
  in_circle boolean;
  moderator boolean := false;
begin
  if current_user_id is null then
    return null;
  end if;

  select ct.* into thread_row
  from public.conversation_threads ct
  where ct.conversation_id = target_conversation_id;

  if thread_row.id is null
    or not public.is_current_user_conversation_member(target_conversation_id)
  then
    return null;
  end if;

  in_circle := exists (
    select 1
    from public.circle_channels cc
    where cc.conversation_id = thread_row.parent_conversation_id
  );

  if in_circle then
    moderator := public.user_has_conversation_channel_permission(
      thread_row.parent_conversation_id,
      current_user_id,
      'manage_messages'
    );
  end if;

  return jsonb_build_object(
    'thread_id', thread_row.id,
    'locked', thread_row.locked_at is not null,
    'locked_at', thread_row.locked_at,
    'can_lock', in_circle and moderator,
    'can_post', thread_row.locked_at is null or moderator
  );
end;
$$;

create or replace function public.reject_locked_thread_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  parent_id uuid;
begin
  -- System notices are written by RPCs; webhooks post as their channel.
  if new.type = 'system'
    or new.webhook_id is not null
    or new.sender_id is null
  then
    return new;
  end if;

  select ct.parent_conversation_id into parent_id
  from public.conversation_threads ct
  where ct.conversation_id = new.conversation_id
    and ct.locked_at is not null;

  if parent_id is null then
    return new;
  end if;

  if not public.user_has_conversation_channel_permission(
    parent_id,
    new.sender_id,
    'manage_messages'
  ) then
    raise exception 'This thread is locked' using
      errcode = '42501',
      detail = 'thread_locked';
  end if;

  return new;
end;
$$;

revoke execute on function public.reject_locked_thread_message()
  from public, anon, authenticated;

drop trigger if exists messages_reject_locked_thread on public.messages;
create trigger messages_reject_locked_thread
  before insert on public.messages
  for each row execute function public.reject_locked_thread_message();

revoke execute on function public.set_thread_locked(uuid, boolean) from public, anon;
revoke execute on function public.get_thread_lock_state(uuid) from public, anon;
grant execute on function public.set_thread_locked(uuid, boolean) to authenticated;
grant execute on function public.get_thread_lock_state(uuid) to authenticated;
