-- Every broadcast and presence channel is private.
--
-- Why. A public Realtime channel is open to anyone who knows its topic name,
-- signed in or not: they can listen to it and send on it. Three channels of
-- the app were still public:
--
--   online-users               presence   who is online, and their status
--   chat-activity-<chat id>    presence + broadcast ("typing")
--   note-presence-<note id>    presence   who is in a note, and their cursor
--
-- The app now joins all three as private channels (RealtimeChannelConfig
-- private: true), like live-location:<share id> (202610180050_location.sql)
-- and moments:<user id> (202610190020_moments_realtime.sql). A private
-- channel asks the policies on realtime.messages when it is joined (and
-- again when the token is refreshed): "select" decides who may listen,
-- "insert" who may send (for presence: who may track). With these policies
-- in place the project can turn "Allow public access" off in the Realtime
-- settings, so that a public channel can not be opened at all.
--
-- Who may use each topic:
--   chat-activity-<chat id>   people who are members of that chat (for a
--                             circle channel: who may view it), not while
--                             the other person of a direct chat is blocked
--                             (or deleted). Ex-members are out as soon as
--                             the membership row is gone. Broadcast and
--                             presence, listen and send alike.
--   note-presence-<note id>   people who can view the note (so: its chat's
--                             members), not while it is deleted, not while
--                             the other person of a direct chat is
--                             blocked. Presence only; nobody can broadcast.
--   online-users              every signed-in person. This is one global
--                             list of who is online and their status (the
--                             sidebar shows it for friends and members);
--                             signed-out callers get nothing. Presence only.
--
-- Anything else stays refused: a private channel with no matching policy
-- can not be listened to or sent on.

-- ----------------------------------------------------------------- topics

-- The uuid after [prefix] in a topic ('chat-activity-<uuid>'), or null.
create or replace function public.realtime_topic_uuid(topic text, prefix text)
returns uuid
language sql
immutable
set search_path = public
as $$
  select case
    when left(topic, length(prefix)) = prefix
      and substr(topic, length(prefix) + 1)
        ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then substr(topic, length(prefix) + 1)::uuid
  end;
$$;

-- ---------------------------------------------------------- who may do what

-- Typing and who-is-here in a conversation.
create or replace function public.can_use_chat_activity(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select target_conversation_id is not null
    and auth.uid() is not null
    and public.is_current_user_conversation_member(target_conversation_id)
    and not public.is_current_user_blocked_in_conversation(target_conversation_id);
$$;

-- Who is in a note, and where their cursor is.
create or replace function public.can_use_note_presence(target_note_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select target_note_id is not null
    and auth.uid() is not null
    and public.can_current_user_view_note(target_note_id)
    and exists (
      select 1
      from public.notes n
      where n.id = target_note_id
        and n.deleted_at is null
        and not public.is_current_user_blocked_in_conversation(n.conversation_id)
    );
$$;

revoke execute on function public.realtime_topic_uuid(text, text) from public, anon;
revoke execute on function public.can_use_chat_activity(uuid) from public, anon;
revoke execute on function public.can_use_note_presence(uuid) from public, anon;
grant execute on function public.realtime_topic_uuid(text, text) to authenticated;
grant execute on function public.can_use_chat_activity(uuid) to authenticated;
grant execute on function public.can_use_note_presence(uuid) to authenticated;

-- --------------------------------------------------------------- policies

-- Typing and presence in a chat: listen.
drop policy if exists chat_activity_receive on realtime.messages;
create policy chat_activity_receive
  on realtime.messages for select
  to authenticated
  using (
    realtime.messages.extension in ('broadcast', 'presence')
    and public.can_use_chat_activity(
      public.realtime_topic_uuid((select realtime.topic()), 'chat-activity-')
    )
  );

-- ... and send (typing events, tracking oneself).
drop policy if exists chat_activity_send on realtime.messages;
create policy chat_activity_send
  on realtime.messages for insert
  to authenticated
  with check (
    realtime.messages.extension in ('broadcast', 'presence')
    and public.can_use_chat_activity(
      public.realtime_topic_uuid((select realtime.topic()), 'chat-activity-')
    )
  );

-- Who is in a note: listen, and track oneself. No broadcast.
drop policy if exists note_presence_receive on realtime.messages;
create policy note_presence_receive
  on realtime.messages for select
  to authenticated
  using (
    realtime.messages.extension = 'presence'
    and public.can_use_note_presence(
      public.realtime_topic_uuid((select realtime.topic()), 'note-presence-')
    )
  );

drop policy if exists note_presence_send on realtime.messages;
create policy note_presence_send
  on realtime.messages for insert
  to authenticated
  with check (
    realtime.messages.extension = 'presence'
    and public.can_use_note_presence(
      public.realtime_topic_uuid((select realtime.topic()), 'note-presence-')
    )
  );

-- Who is online: any signed-in person, presence only.
drop policy if exists online_users_receive on realtime.messages;
create policy online_users_receive
  on realtime.messages for select
  to authenticated
  using (
    realtime.messages.extension = 'presence'
    and (select realtime.topic()) = 'online-users'
  );

drop policy if exists online_users_send on realtime.messages;
create policy online_users_send
  on realtime.messages for insert
  to authenticated
  with check (
    realtime.messages.extension = 'presence'
    and (select realtime.topic()) = 'online-users'
  );
