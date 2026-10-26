-- Bot API 2.0 (roadmap I3), part 2 of 5: what a bot can do in a chat.
--
-- Every function here is for the service role (the bot-api Edge Function),
-- takes the bot's token, and works on a chat (a conversation) the bot may read
-- (bot_conversation_access, 202610281100): a channel or thread of its own
-- circle, a group it was put in, a direct chat people started with it.
-- Writes count against the bot's 60 per minute (count_bot_write) and run as the
-- bot (act_as_bot), so the permissions, timeouts, slowmode, AutoMod and
-- blocks that bind a member bind the bot too.
--
--   bot_api_list_chats          the groups and direct chats the bot is in
--   bot_api_list_chat_messages  recent messages of a chat, newest first
--   bot_api_send_chat_message   text (with components) into a chat
--   bot_api_send_file_message   a file the Edge Function already stored
--   bot_api_create_poll         a poll
--   bot_api_create_thread       a thread from a message
--   bot_api_delete_message      deletes the bot's own message
--   bot_api_remove_reaction     takes the bot's reaction off
--   bot_api_list_members        who is in the chat (public profile only)
--   bot_api_get_member          one of them
--
-- What a bot reads is what the events carry (202610281110): people are {id,
-- username, name, is_bot} (plus role in a group), never a bio, status,
-- birthday, presence or e-mail; messages under review, deleted or disappeared
-- are not there; people who blocked the bot do not show up and their messages
-- are left out; the words of a restricted chat (G6), a chat a member locked
-- (G2), a disappearing message and a view-once picture are held back
-- (content_withheld); in groups and direct chats a bot reads only what was
-- said after it joined.

-- ------------------------------------------------------------- reading

create or replace function public.bot_api_list_chats(bot_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
begin
  return coalesce((
    select jsonb_agg(item order by sort_at desc, id)
    from (
      select
        c.id,
        coalesce(c.last_message_at, c.created_at) as sort_at,
        jsonb_strip_nulls(jsonb_build_object(
          'id', c.id,
          'kind', c.type,
          'name', case when c.type = 'group' then nullif(btrim(c.title), '') end,
          'member_count', case
            when c.type = 'group' then (
              select count(*) from public.conversation_members m
              where m.conversation_id = c.id
            )
          end,
          'peer', case
            when c.type = 'direct' then (
              select public.bot_event_person(null, m.user_id)
              from public.conversation_members m
              where m.conversation_id = c.id and m.user_id <> bot.user_id
              limit 1
            )
          end,
          'restricted', public.conversation_restricts_sharing(c.id)
        )) as item
      from public.conversations c
      join public.conversation_members cm
        on cm.conversation_id = c.id and cm.user_id = bot.user_id
      where c.type in ('group', 'direct')
        and public.bot_conversation_access(bot, c.id)
      order by coalesce(c.last_message_at, c.created_at) desc
      limit 200
    ) chats
  ), '[]'::jsonb);
end;
$$;

create or replace function public.bot_api_list_chat_messages(
  bot_token text,
  target_chat_id uuid,
  max_count integer default 50,
  before_time timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  chat_id uuid := public.bot_visible_conversation(bot, target_chat_id);
  circle uuid := public.bot_event_circle_of(target_chat_id);
  joined timestamptz;
begin
  -- Outside a circle a bot reads what was said after it came.
  if circle is null then
    select cm.joined_at into joined
    from public.conversation_members cm
    where cm.conversation_id = chat_id and cm.user_id = bot.user_id;
  end if;

  return coalesce((
    select jsonb_agg(item order by created_at desc, id desc)
    from (
      select
        m.id,
        m.created_at,
        public.bot_event_message_json(
          m,
          circle,
          public.bot_event_withheld_reason(chat_id, m)
        )
        || jsonb_build_object(
          'chat_id', chat_id,
          'deleted', m.recalled_at is not null
        )
        || case
          when m.interaction is not null
            then jsonb_build_object('interaction', m.interaction)
          else '{}'::jsonb
        end as item
      from public.messages m
      where m.conversation_id = chat_id
        and m.type <> 'system'
        and m.review_state is null
        and (m.expires_at is null or m.expires_at > now())
        and (before_time is null or m.created_at < before_time)
        and (joined is null or m.created_at >= joined)
        and not public.are_users_blocked(m.sender_id, bot.user_id)
      order by m.created_at desc, m.id desc
      limit least(greatest(coalesce(max_count, 50), 1), 100)
    ) page
  ), '[]'::jsonb);
end;
$$;

-- ------------------------------------------------------------- writing

create or replace function public.bot_api_send_chat_message(
  bot_token text,
  target_chat_id uuid,
  content text,
  reply_to_message_id uuid default null,
  message_components jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  chat_id uuid := public.bot_visible_conversation(bot, target_chat_id);
  circle uuid := public.bot_event_circle_of(target_chat_id);
  trimmed_content text := btrim(coalesce(content, ''));
  cleaned jsonb := public.normalize_message_components(message_components);
  reply public.messages%rowtype;
  preview jsonb;
begin
  if char_length(trimmed_content) not between 1 and 2000 then
    raise exception 'Content must be 1 to 2000 characters' using errcode = '22023';
  end if;

  if reply_to_message_id is not null then
    select m.* into reply
    from public.messages m
    where m.id = bot_api_send_chat_message.reply_to_message_id
      and m.conversation_id = chat_id
      and m.review_state is null;

    if reply.id is null then
      raise exception 'Reply message not found in this chat' using errcode = '22023';
    end if;

    preview := jsonb_build_object(
      'message_id', reply.id,
      'sender_name', coalesce(
        reply.webhook_name,
        coalesce(
          public.bot_event_person(circle, reply.sender_id)->>'name',
          ''
        )
      ),
      'body', case
        when reply.recalled_at is null
          and public.bot_event_withheld_reason(chat_id, reply) is null
          then left(reply.body, 200)
        else ''
      end,
      'type', reply.type
    );
  end if;

  perform public.count_bot_write(bot);

  -- AutoMod reads the texts of the buttons like the message itself.
  if cleaned is not null
    and public.bot_components_automod(chat_id, bot.user_id, cleaned)
  then
    return null;
  end if;

  perform public.act_as_bot(bot);

  return public.bot_send_text(chat_id, trimmed_content, reply.id, preview, cleaned);
end;
$$;

-- A file the bot-api function put into chat-files under
-- <chat id>/<bot user id>/<uuid>-<name>. The function checks the size and
-- stores the bytes; this one makes sure the path is the bot's own, the file is
-- there and nothing else names it, and posts the message. Returns the id, or
-- null when AutoMod dropped the message (the function then removes the file).
create or replace function public.bot_api_send_file_message(
  bot_token text,
  target_chat_id uuid,
  file_path text,
  file_name text,
  file_size bigint,
  file_mime text,
  caption text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  chat_id uuid := public.bot_visible_conversation(bot, target_chat_id);
  cleaned_name text := public.components_clean_text(
    to_jsonb(coalesce(file_name, '')), 'The file name', 1, 120
  );
  cleaned_caption text := btrim(coalesce(caption, ''));
  mime text := lower(btrim(coalesce(file_mime, 'application/octet-stream')));
  created_id uuid;
begin
  if file_path is null
    or file_path !~ ('^' || chat_id::text || '/' || bot.user_id::text || '/[0-9a-f-]{36}-[^/]{1,150}$')
  then
    raise exception 'The file is not in the bot''s folder of this chat' using errcode = '22023';
  end if;
  if file_size is null or file_size not between 1 and 52428800 then
    raise exception 'A file is 1 byte to 50 MB' using errcode = '22023';
  end if;
  if mime !~ '^[a-z0-9][a-z0-9.+-]*/[a-z0-9][a-z0-9.+-]*$' or char_length(mime) > 100 then
    mime := 'application/octet-stream';
  end if;
  if char_length(cleaned_caption) > 2000 then
    raise exception 'The caption is at most 2000 characters' using errcode = '22023';
  end if;
  if cleaned_caption ~ '[​-‏‪-‮⁠-⁤⁦-⁩﻿]' then
    raise exception 'The caption has characters that are not allowed' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from storage.objects o
    where o.bucket_id = 'chat-files' and o.name = file_path
  ) then
    raise exception 'The file was not stored' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.messages m
    where m.attachment->>'path' = file_path
      and m.attachment->>'bucket' = 'chat-files'
  ) then
    raise exception 'That file is already in a message' using errcode = '23505';
  end if;

  perform public.count_bot_write(bot);
  perform public.act_as_bot(bot);

  -- AutoMod (202610160035): a blocked message is dropped, not raised.
  perform set_config('wecord.automod_soft', 'on', true);
  begin
    insert into public.messages (conversation_id, sender_id, type, body, attachment)
    values (
      chat_id,
      bot.user_id,
      'file',
      cleaned_caption,
      jsonb_build_object(
        'kind', case when mime like 'video/%' then 'video' else 'file' end,
        'bucket', 'chat-files',
        'path', file_path,
        'name', cleaned_name,
        'size', file_size,
        'mime_type', mime
      )
    )
    returning id into created_id;
  exception when others then
    perform set_config('wecord.automod_soft', 'off', true);
    raise;
  end;
  perform set_config('wecord.automod_soft', 'off', true);

  return created_id;
end;
$$;

create or replace function public.bot_api_create_poll(
  bot_token text,
  target_chat_id uuid,
  question text,
  options text[],
  multi boolean default false,
  duration_hours integer default null,
  anonymous boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  chat_id uuid := public.bot_visible_conversation(bot, target_chat_id);
  texts text;
begin
  texts := btrim(coalesce(question, '')) || E'\n'
    || array_to_string(coalesce(options, array[]::text[]), E'\n');

  perform public.count_bot_write(bot);

  if public.bot_text_blocked(chat_id, bot.user_id, texts) then
    return null;
  end if;

  perform public.act_as_bot(bot);

  return public.create_poll(
    chat_id,
    question,
    options,
    coalesce(multi, false),
    duration_hours,
    null,
    null,
    coalesce(anonymous, false),
    false,
    null
  );
end;
$$;

-- Starts a thread from a message (or gives the one it already has).
create or replace function public.bot_api_create_thread(
  bot_token text,
  target_message_id uuid,
  thread_title text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  message public.messages%rowtype;
  made jsonb;
begin
  select m.* into message
  from public.messages m
  where m.id = target_message_id;

  if message.id is null
    or message.type = 'system'
    or message.recalled_at is not null
    or message.review_state is not null
    or not public.bot_conversation_access(bot, message.conversation_id)
  then
    raise exception 'Message not found' using errcode = 'P0002';
  end if;

  if thread_title is not null and public.bot_text_blocked(
    message.conversation_id, bot.user_id, thread_title
  ) then
    return null;
  end if;

  perform public.count_bot_write(bot);
  perform public.act_as_bot(bot);

  made := public.create_thread(message.conversation_id, message.id, thread_title);

  return jsonb_build_object(
    'chat_id', made->'conversation_id',
    'title', made->'title',
    'root_message_id', made->'root_message_id',
    'parent_chat_id', made->'parent_conversation_id'
  );
end;
$$;

-- Deletes the bot's own message. Returns the files that were attached, which
-- the function removes from storage ([{bucket, path}]).
create or replace function public.bot_api_delete_message(
  bot_token text,
  target_message_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  message public.messages%rowtype;
  media jsonb;
begin
  select m.* into message
  from public.messages m
  where m.id = target_message_id;

  if message.id is null
    or message.sender_id <> bot.user_id
    or message.type = 'system'
    or not public.bot_conversation_access(bot, message.conversation_id)
  then
    raise exception 'Message not found' using errcode = 'P0002';
  end if;

  perform public.count_bot_write(bot);
  perform public.act_as_bot(bot);

  select coalesce(jsonb_agg(jsonb_build_object('bucket', r.bucket_id, 'path', r.object_path)), '[]'::jsonb)
  into media
  from public.recall_message(message.id) r;

  return media;
end;
$$;

-- Takes the bot's own reaction off (nothing when it has not reacted).
create or replace function public.bot_api_remove_reaction(
  bot_token text,
  target_message_id uuid,
  emoji text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  message public.messages%rowtype;
begin
  select m.* into message
  from public.messages m
  where m.id = target_message_id;

  if message.id is null
    or message.recalled_at is not null
    or not public.bot_conversation_access(bot, message.conversation_id)
  then
    raise exception 'Message not found' using errcode = 'P0002';
  end if;

  if not exists (
    select 1
    from public.message_reactions r
    where r.message_id = message.id
      and r.user_id = bot.user_id
      and r.emoji = btrim(coalesce(bot_api_remove_reaction.emoji, ''))
  ) then
    return;
  end if;

  perform public.count_bot_write(bot);
  perform public.act_as_bot(bot);
  perform public.toggle_message_reaction(message.id, bot_api_remove_reaction.emoji);
end;
$$;

-- ------------------------------------------------------------- members

-- Who is in the chat, as the bot may know them: id, username, name, whether a
-- bot and (in a group) their role. People who blocked the bot, people who left
-- their account and people who can no longer see the channel are left out.
create or replace function public.bot_api_list_members(
  bot_token text,
  target_chat_id uuid,
  max_count integer default 100,
  after_user uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  chat_id uuid := public.bot_visible_conversation(bot, target_chat_id);
  circle uuid := public.bot_event_circle_of(target_chat_id);
  channel_id uuid := public.conversation_circle_channel_id(target_chat_id);
begin
  return coalesce((
    select jsonb_agg(item order by user_id)
    from (
      select
        cm.user_id,
        public.bot_event_person(circle, cm.user_id)
        || case
          when circle is null and cm.role in ('owner', 'admin')
            then jsonb_build_object('role', cm.role)
          when circle is null then jsonb_build_object('role', 'member')
          else '{}'::jsonb
        end as item
      from public.conversation_members cm
      join public.profiles p on p.id = cm.user_id
      where cm.conversation_id = chat_id
        and p.deleted_at is null
        and (after_user is null or cm.user_id > after_user)
        and not public.are_users_blocked(cm.user_id, bot.user_id)
        and (
          channel_id is null
          or public.circle_channel_has_permission(channel_id, cm.user_id, 'view_channel')
        )
      order by cm.user_id
      limit least(greatest(coalesce(max_count, 100), 1), 200)
    ) page
  ), '[]'::jsonb);
end;
$$;

create or replace function public.bot_api_get_member(
  bot_token text,
  target_chat_id uuid,
  target_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  chat_id uuid := public.bot_visible_conversation(bot, target_chat_id);
  circle uuid := public.bot_event_circle_of(target_chat_id);
  channel_id uuid := public.conversation_circle_channel_id(target_chat_id);
  found jsonb;
begin
  select
    public.bot_event_person(circle, cm.user_id)
    || case
      when circle is null and cm.role in ('owner', 'admin')
        then jsonb_build_object('role', cm.role)
      when circle is null then jsonb_build_object('role', 'member')
      else '{}'::jsonb
    end
  into found
  from public.conversation_members cm
  join public.profiles p on p.id = cm.user_id
  where cm.conversation_id = chat_id
    and cm.user_id = target_user_id
    and p.deleted_at is null
    and not public.are_users_blocked(cm.user_id, bot.user_id)
    and (
      channel_id is null
      or public.circle_channel_has_permission(channel_id, cm.user_id, 'view_channel')
    );

  if found is null then
    raise exception 'Member not found' using errcode = 'P0002';
  end if;
  return found;
end;
$$;

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'bot_api_list_chats(text)',
    'bot_api_list_chat_messages(text, uuid, integer, timestamptz)',
    'bot_api_send_chat_message(text, uuid, text, uuid, jsonb)',
    'bot_api_send_file_message(text, uuid, text, text, bigint, text, text)',
    'bot_api_create_poll(text, uuid, text, text[], boolean, integer, boolean)',
    'bot_api_create_thread(text, uuid, text)',
    'bot_api_delete_message(text, uuid)',
    'bot_api_remove_reaction(text, uuid, text)',
    'bot_api_list_members(text, uuid, integer, uuid)',
    'bot_api_get_member(text, uuid, uuid)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', fn);
    execute format('grant execute on function public.%s to service_role', fn);
  end loop;
end $$;
