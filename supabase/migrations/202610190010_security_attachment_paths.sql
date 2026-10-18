-- Security audit (2026-10-19): the path of a chat file is not the sender's to
-- invent.
--
-- A message's attachment names a file in chat-images, chat-files or
-- voice-messages by bucket and path, and the clients write that JSON
-- themselves (messages_insert_member checks nothing about it). Two things read
-- those paths from messages as if they were true:
--
--   1. forward_message and forward_messages_merged copy a message's path and
--      the storage select policies then let every member of the chat it was
--      forwarded to read that file. Someone who once knew the path of a file
--      (a person who left the group, a removed member) could write a message
--      of their own that names it, forward it to a chat of theirs and read the
--      file again.
--   2. The restriction on view-once files (view_once_media_restrict) is looked
--      up by path in all messages. A member could post a fake "view once"
--      message that names the path of somebody else's ordinary picture and
--      lock everybody else (the sender included) out of it.
--
-- BEFORE INSERT, for people using the API (not for the server's own functions
-- such as forward_message, which copy paths they have checked):
--
--   * an attachment that names a file of the three chat buckets must name a
--     file under a conversation the sender is in (the folder is the
--     conversation id; forum posts keep their pictures under the forum's id);
--   * a view-once attachment must name a file no other message names yet.
--     (A retry of the same send, same client id, is not "another message":
--     the unique client id answers it as before.)

-- Whether another message already names the file (looked up as the owner:
-- the caller cannot see every message). A retry of the same send does not
-- count. Only answers for files under the caller's own chats, so it tells
-- nothing about anybody else's.
create or replace function public.chat_file_in_use(
  file_bucket text,
  file_path text,
  sender uuid,
  retry_client_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when split_part(file_path, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then
      public.is_current_user_conversation_member(split_part(file_path, '/', 1)::uuid)
      and exists (
        select 1
        from public.messages other
        where other.attachment->>'path' = file_path
          and other.attachment->>'bucket' = file_bucket
          and not (
            retry_client_id is not null
            and other.sender_id = sender
            and other.client_id = retry_client_id
          )
      )
    else false
  end;
$$;

revoke execute on function public.chat_file_in_use(text, text, uuid, uuid) from public, anon;
grant execute on function public.chat_file_in_use(text, text, uuid, uuid) to authenticated;

-- Not SECURITY DEFINER: current_user must be the caller's role (the server's
-- own functions run as their owner and are left alone).
create or replace function public.messages_check_attachment_path()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  bucket text := new.attachment->>'bucket';
  object_path text := new.attachment->>'path';
  folder text;
begin
  if current_user not in ('authenticated', 'anon')
    or new.attachment is null
    or jsonb_typeof(new.attachment) <> 'object'
    or bucket is null
    or bucket not in ('chat-images', 'chat-files', 'voice-messages')
    or object_path is null
  then
    return new;
  end if;

  folder := split_part(object_path, '/', 1);
  if folder !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or not public.is_current_user_conversation_member(folder::uuid)
  then
    raise exception 'This file does not belong to one of your chats'
      using errcode = '42501';
  end if;

  if new.attachment->>'view_once' = 'true'
    and public.chat_file_in_use(bucket, object_path, new.sender_id, new.client_id)
  then
    raise exception 'View-once media needs a file of its own'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke execute on function public.messages_check_attachment_path() from public, anon, authenticated;

drop trigger if exists messages_check_attachment_path on public.messages;
create trigger messages_check_attachment_path
  before insert on public.messages
  for each row execute function public.messages_check_attachment_path();
