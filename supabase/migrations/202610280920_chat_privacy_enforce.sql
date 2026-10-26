-- Advanced chat privacy (roadmap G6), part 3 of 4: what the server refuses.
--
-- Nothing here depends on the app hiding a button: each rule is enforced in
-- the database, where the content is.
--
--   Forwarding
--     * A BEFORE INSERT trigger on messages refuses a message that is a
--       forward (forwarded_from carries the source message) when the source
--       chat is restricted. forward_message is not rewritten: every way of
--       forwarding goes through the trigger, the way view-once media is
--       refused (messages_check_view_once, 202610170021).
--     * A BEFORE INSERT trigger on message_bundles does the same for a merged
--       forward ("chat history"): every message it carries must come from a
--       chat that is not restricted. forward_messages_merged is not rewritten.
--
--   Saving
--     * A BEFORE INSERT trigger on saved_items refuses to keep a message of
--       a restricted chat for later.
--     * add_album_items_from_messages and add_folder_files_from_messages (the
--       group space, 202610280210 and 202610280220) refuse to copy a
--       restricted chat's pictures and videos into the space. Patched in
--       place from their live definitions.
--
--   AI
--     * conversation_ai_allowed (202610170031) is what the `ai` Edge Function
--       asks, as the caller, before it does anything with a chat: summaries,
--       rewrite and translate with a chat, auto-translate, transcription,
--       "make tasks", link checks, meeting minutes, note assist. It answers
--       false for a restricted chat, so each of them stops with the
--       function's existing "AI is off here" answer. Patched in place.
--     * conversation_ai_assistant_allowed (202610230400) is the same question
--       for the code that has no caller: the @WeCord assistant's jobs, the
--       daily digest and AI questions (ask). Patched in place, so those three
--       leave a restricted chat out the way they leave out a locked one
--       (202610260300) without being rewritten.
--     * list_my_ai_digests (202610230510, patched by 202610260300) stops
--       listing the parts of earlier digest cards that are about a chat that
--       is restricted now.
--
-- Each patch must find its anchor and change the text, or the migration
-- stops and says so (no silent no-op), and a second run changes nothing.

create or replace function public.messages_check_restricted_forward()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  source_message_id uuid;
begin
  if new.forwarded_from is null
    or jsonb_typeof(new.forwarded_from) <> 'object'
    or coalesce(new.forwarded_from->>'message_id', '')
      !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  then
    return new;
  end if;

  source_message_id := (new.forwarded_from->>'message_id')::uuid;
  if exists (
    select 1
    from public.messages source
    where source.id = source_message_id
      and public.conversation_restricts_sharing(source.conversation_id)
  ) then
    raise exception 'chat_privacy_restricted'
      using errcode = '42501',
        detail = 'This chat has advanced chat privacy turned on, so its messages cannot be forwarded.';
  end if;
  return new;
end;
$$;

revoke execute on function public.messages_check_restricted_forward()
  from public, anon, authenticated;

drop trigger if exists messages_check_restricted_forward on public.messages;
create trigger messages_check_restricted_forward
  before insert on public.messages
  for each row
  when (new.forwarded_from is not null)
  execute function public.messages_check_restricted_forward();

create or replace function public.message_bundles_check_restricted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  source_id text;
begin
  if new.items is null or jsonb_typeof(new.items) <> 'array' then
    return new;
  end if;
  for item in select i from jsonb_array_elements(new.items) i loop
    source_id := item->>'message_id';
    if source_id is not null
      and source_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and exists (
        select 1
        from public.messages source
        where source.id = source_id::uuid
          and public.conversation_restricts_sharing(source.conversation_id)
      )
    then
      raise exception 'chat_privacy_restricted'
        using errcode = '42501',
          detail = 'This chat has advanced chat privacy turned on, so its messages cannot be forwarded.';
    end if;
  end loop;
  return new;
end;
$$;

revoke execute on function public.message_bundles_check_restricted()
  from public, anon, authenticated;

drop trigger if exists message_bundles_check_restricted on public.message_bundles;
create trigger message_bundles_check_restricted
  before insert on public.message_bundles
  for each row execute function public.message_bundles_check_restricted();

create or replace function public.saved_items_check_restricted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.kind = 'message'
    and new.conversation_id is not null
    and public.conversation_restricts_sharing(new.conversation_id)
  then
    raise exception 'chat_privacy_restricted'
      using errcode = '42501',
        detail = 'This chat has advanced chat privacy turned on, so its messages cannot be saved.';
  end if;
  return new;
end;
$$;

revoke execute on function public.saved_items_check_restricted()
  from public, anon, authenticated;

drop trigger if exists saved_items_check_restricted on public.saved_items;
create trigger saved_items_check_restricted
  before insert on public.saved_items
  for each row
  when (new.kind = 'message')
  execute function public.saved_items_check_restricted();

-- The readers and copiers, patched in place so nothing they gained since is
-- lost.
do $$
declare
  def text;
  patched text;
begin
  -- The group space: pictures and videos of the chat into an album.
  def := pg_get_functiondef('public.add_album_items_from_messages(uuid, uuid[])'::regprocedure);
  if def not like '%conversation_restricts_sharing%' then
    patched := replace(
      def,
      E'  perform public.group_space_access(album.conversation_id, ''add'');\n',
      E'  perform public.group_space_access(album.conversation_id, ''add'');\n  if public.conversation_restricts_sharing(album.conversation_id) then\n    raise exception ''chat_privacy_restricted'' using errcode = ''42501'';\n  end if;\n'
    );
    if patched = def or patched not like '%conversation_restricts_sharing%' then
      raise exception 'add_album_items_from_messages changed shape; patch it by hand';
    end if;
    execute patched;
  end if;

  -- The group space: files of the chat into a folder.
  def := pg_get_functiondef('public.add_folder_files_from_messages(uuid, uuid, uuid[])'::regprocedure);
  if def not like '%conversation_restricts_sharing%' then
    patched := replace(
      def,
      E'  perform public.group_space_access(p_conversation_id, ''add'');\n',
      E'  perform public.group_space_access(p_conversation_id, ''add'');\n  if public.conversation_restricts_sharing(p_conversation_id) then\n    raise exception ''chat_privacy_restricted'' using errcode = ''42501'';\n  end if;\n'
    );
    if patched = def or patched not like '%conversation_restricts_sharing%' then
      raise exception 'add_folder_files_from_messages changed shape; patch it by hand';
    end if;
    execute patched;
  end if;

  -- What the `ai` Edge Function asks as the caller (202610170031).
  def := pg_get_functiondef('public.conversation_ai_allowed(uuid)'::regprocedure);
  if def not like '%conversation_restricts_sharing%' then
    patched := replace(
      def,
      E'  select coalesce(\n    (\n      select c.ai_enabled or not',
      E'  select not public.conversation_restricts_sharing(target_conversation_id)\n  and coalesce(\n    (\n      select c.ai_enabled or not'
    );
    if patched = def or patched not like '%conversation_restricts_sharing%' then
      raise exception 'conversation_ai_allowed changed shape; patch it by hand';
    end if;
    execute patched;
  end if;

  -- The same question for the assistant, the digest and AI questions
  -- (202610230400).
  def := pg_get_functiondef('public.conversation_ai_assistant_allowed(uuid)'::regprocedure);
  if def not like '%conversation_restricts_sharing%' then
    patched := replace(
      def,
      E'  select\n    coalesce(\n      (select c.ai_enabled',
      E'  select\n    not public.conversation_restricts_sharing(target_conversation_id)\n    and coalesce(\n      (select c.ai_enabled'
    );
    if patched = def or patched not like '%conversation_restricts_sharing%' then
      raise exception 'conversation_ai_assistant_allowed changed shape; patch it by hand';
    end if;
    execute patched;
  end if;

  -- The digest cards already made (202610230510, 202610260300).
  def := pg_get_functiondef('public.list_my_ai_digests()'::regprocedure);
  if def not like '%conversation_restricts_sharing%' then
    patched := replace(
      def,
      E'      and not public.is_conversation_locked(me, x.conversation_id)\n',
      E'      and not public.is_conversation_locked(me, x.conversation_id)\n      and not public.conversation_restricts_sharing(x.conversation_id)\n'
    );
    if patched = def or patched not like '%conversation_restricts_sharing%' then
      raise exception 'list_my_ai_digests changed shape; patch it by hand';
    end if;
    execute patched;
  end if;
end;
$$;
