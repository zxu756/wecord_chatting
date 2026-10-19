-- Quoting part of a message (A9) and sending without a push (A9).
--
-- * reply_preview.quote: a reply may quote one piece of the message it
--   answers. The client puts {"quote": {"text": ..., "start": n, "end": n}}
--   into the reply_preview it already sends. The server checks that the text
--   really is in the original message (a forged quote would put words in
--   someone else's mouth), that the original is one the sender can quote
--   (same conversation, not recalled, not expired, not under review for
--   somebody who cannot see it), and keeps only text, start and end.
--   When the original is recalled or erased the reply's preview body is
--   blanked by the recall functions (202610130027 and later); the quote is
--   blanked with it, so a recalled message's words do not live on in replies.
-- * messages.silent: the message is stored and shown like any other, counts
--   as unread, but no push is sent for it (the push functions drop it, see
--   supabase/functions/push/silent_messages.ts). Set on insert only.
--   send_silent_text_message(...) is send_text_message(...) with that flag,
--   in one transaction; send_text_message itself is not rewritten.

alter table public.messages
  add column if not exists silent boolean not null default false;

-- ---------------------------------------------------------------- silent

create or replace function public.messages_apply_silent()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(current_setting('wecord.send_silent', true), '') = 'on' then
    new.silent := true;
  end if;
  return new;
end;
$$;

drop trigger if exists messages_apply_silent on public.messages;
create trigger messages_apply_silent
  before insert on public.messages
  for each row execute function public.messages_apply_silent();

-- Silence is decided when a message is sent and does not change after.
create or replace function public.messages_silent_unchanged()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.silent := old.silent;
  return new;
end;
$$;

drop trigger if exists messages_silent_unchanged on public.messages;
create trigger messages_silent_unchanged
  before update of silent on public.messages
  for each row execute function public.messages_silent_unchanged();

-- send_text_message, without a push for the recipients.
create or replace function public.send_silent_text_message(
  target_conversation_id uuid,
  body text,
  reply_to_message_id uuid default null,
  reply_preview jsonb default null,
  mentions jsonb default '[]'::jsonb,
  client_id uuid default null
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  created_message_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  perform set_config('wecord.send_silent', 'on', true);
  created_message_id := public.send_text_message(
    target_conversation_id,
    body,
    reply_to_message_id,
    reply_preview,
    mentions,
    client_id
  );
  perform set_config('wecord.send_silent', 'off', true);
  return created_message_id;
end;
$$;

revoke execute on function public.send_silent_text_message(uuid, text, uuid, jsonb, jsonb, uuid) from public;
revoke execute on function public.send_silent_text_message(uuid, text, uuid, jsonb, jsonb, uuid) from anon;
grant execute on function public.send_silent_text_message(uuid, text, uuid, jsonb, jsonb, uuid) to authenticated;

-- Which of these messages are silent: what the push functions ask before
-- they send. Service role only (the clients read the column themselves).
create or replace function public.silent_message_ids(message_ids uuid[])
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select m.id
  from public.messages m
  where m.id = any(message_ids)
    and m.silent;
$$;

revoke execute on function public.silent_message_ids(uuid[]) from public, anon, authenticated;
grant execute on function public.silent_message_ids(uuid[]) to service_role;

-- ----------------------------------------------------------------- quote

create or replace function public.messages_check_reply_quote()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  quote jsonb;
  quote_text text;
  quote_start jsonb;
  quote_end jsonb;
  original public.messages;
  clean jsonb;
begin
  if new.reply_preview is null
    or jsonb_typeof(new.reply_preview) <> 'object'
    or not (new.reply_preview ? 'quote')
  then
    return new;
  end if;

  -- The recall functions blank a reply's preview body when its original
  -- goes: the quote goes with it.
  if tg_op = 'UPDATE'
    and new.reply_preview->>'body' = ''
    and old.reply_preview->>'body' is distinct from ''
  then
    new.reply_preview := new.reply_preview - 'quote';
    return new;
  end if;

  -- Rows that already had their quote checked are left alone.
  if tg_op = 'UPDATE'
    and new.reply_preview->'quote' is not distinct from old.reply_preview->'quote'
  then
    return new;
  end if;

  quote := new.reply_preview->'quote';
  if jsonb_typeof(quote) = 'null' then
    new.reply_preview := new.reply_preview - 'quote';
    return new;
  end if;
  if jsonb_typeof(quote) <> 'object' or jsonb_typeof(quote->'text') <> 'string' then
    raise exception 'The quote must have text' using errcode = '22023';
  end if;
  quote_text := quote->>'text';
  if char_length(quote_text) not between 1 and 500 then
    raise exception 'A quote is 1 to 500 characters' using errcode = '22023';
  end if;
  if new.reply_to_message_id is null then
    raise exception 'A quote needs the message it answers' using errcode = '22023';
  end if;

  select m.*
  into original
  from public.messages m
  where m.id = new.reply_to_message_id
    and m.conversation_id = new.conversation_id
    and m.recalled_at is null
    and (m.expires_at is null or m.expires_at > now())
    and public.message_visible_to_current_user(
      m.review_state, m.sender_id, m.conversation_id
    );
  if original.id is null or strpos(original.body, quote_text) = 0 then
    raise exception 'The quoted text is not in the message' using errcode = '22023';
  end if;

  clean := jsonb_build_object('text', quote_text);
  quote_start := quote->'start';
  quote_end := quote->'end';
  if jsonb_typeof(quote_start) = 'number' and jsonb_typeof(quote_end) = 'number'
    and (quote_start::text) ~ '^[0-9]{1,5}$'
    and (quote_end::text) ~ '^[0-9]{1,5}$'
    and quote_start::text::integer < quote_end::text::integer
  then
    clean := clean || jsonb_build_object(
      'start', quote_start::text::integer,
      'end', quote_end::text::integer
    );
  end if;
  new.reply_preview := new.reply_preview || jsonb_build_object('quote', clean);
  return new;
end;
$$;

drop trigger if exists messages_check_reply_quote on public.messages;
create trigger messages_check_reply_quote
  before insert or update of reply_preview on public.messages
  for each row execute function public.messages_check_reply_quote();
