-- Personal stickers (A11), part 2 of 2: sending one.
--
-- A sticker from someone's library (202610220500) is never read by the people
-- it is sent to: the app first copies the file into the chat's own folder in
-- chat-images (<conversation id>/<name>.<png|gif|webp>, the path rule of
-- 202610190010 and the upload rule of 202610130016: a member who may send),
-- then calls this function. It sends a message of the existing 'sticker' type
-- like send_sticker does (members only, not blocked, the send trigger applies
-- send_messages, slowmode, AutoMod and the AI guard as usual), with the
-- attachment
--
--   {kind: 'sticker', personal: true, bucket: 'chat-images', path,
--    mime_type, width, height, animated, size}
--
-- and an empty body. Clients cannot insert stickers directly (202610130026),
-- so this is the only way a personal sticker becomes a message.
--
-- The caller must own the library sticker (that it is the one being sent),
-- and the copy must be a file they uploaded themselves in this conversation's
-- folder. Nothing here names a path of the library or of anyone else's chat.

create or replace function public.send_personal_sticker(
  target_conversation_id uuid,
  target_sticker_id uuid,
  chat_path text
)
returns uuid
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  current_user_id uuid := auth.uid();
  library_sticker public.user_stickers%rowtype;
  stored_owner text;
  stored_size bigint;
  extension text;
  mime text;
  created_message_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select s.*
  into library_sticker
  from public.user_stickers s
  where s.id = target_sticker_id
    and s.owner_id = current_user_id;

  if library_sticker.id is null then
    raise exception 'Sticker not found' using errcode = '42501';
  end if;

  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Cannot send messages in this conversation'
      using errcode = '42501';
  end if;

  -- The copy sits directly in this conversation's folder.
  if chat_path is null
    or chat_path !~ ('^' || target_conversation_id::text || '/[A-Za-z0-9_-]{1,80}\.(png|gif|webp)$')
  then
    raise exception 'The sticker copy must be in this conversation''s folder'
      using errcode = '42501';
  end if;
  extension := substring(chat_path from '\.([a-z]+)$');
  mime := 'image/' || extension;

  -- The file is there and the caller put it there.
  select coalesce(o.owner_id, o.owner::text), (o.metadata->>'size')::bigint
  into stored_owner, stored_size
  from storage.objects o
  where o.bucket_id = 'chat-images'
    and o.name = chat_path;

  if not found then
    raise exception 'Copy the sticker into the chat first' using errcode = '22023';
  end if;
  if stored_owner is distinct from current_user_id::text then
    raise exception 'The sticker copy is not yours' using errcode = '42501';
  end if;

  -- AutoMod (202610160035): a blocked message is dropped, not raised.
  perform set_config('wecord.automod_soft', 'on', true);

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    attachment
  )
  values (
    target_conversation_id,
    current_user_id,
    'sticker',
    '',
    jsonb_build_object(
      'kind', 'sticker',
      'personal', true,
      'bucket', 'chat-images',
      'path', chat_path,
      'mime_type', mime,
      'width', library_sticker.width,
      'height', library_sticker.height,
      'animated', library_sticker.animated,
      'size', stored_size
    )
  )
  returning id into created_message_id;

  perform set_config('wecord.automod_soft', 'off', true);

  return created_message_id;
end;
$$;

revoke execute on function public.send_personal_sticker(uuid, uuid, text) from public, anon;
grant execute on function public.send_personal_sticker(uuid, uuid, text) to authenticated;
