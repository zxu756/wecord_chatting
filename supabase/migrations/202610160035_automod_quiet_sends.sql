-- AutoMod treats stickers, polls, forwards and forum posts like text.
--
-- 202610160020 refused those sends with an exception when a blocking rule
-- matched, which rolled back the rule's alerts and timeouts. Now they set
-- wecord.automod_soft around their insert like send_text_message: the
-- trigger acts, notes the refusal in circle_automod_notices and drops the
-- row. send_sticker, create_poll and forward_message then return null;
-- the app reads the reason with take_automod_notice for that
-- conversation. A refused forum post leaves no thread behind: its new
-- thread is deleted, the notice moves to the forum's conversation, and
-- create_forum_post returns {automod_blocked: true, conversation_id} (the
-- forum's) so the app knows where to read the notice.


-- Same as 202610130026_circle_emojis, but AutoMod refuses quietly: then
-- nothing is inserted and this returns null.
create or replace function public.send_sticker(
  target_conversation_id uuid,
  target_emoji_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  sticker public.circle_emojis%rowtype;
  created_message_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select e.*
  into sticker
  from public.circle_emojis e
  where e.id = target_emoji_id
    and e.kind = 'sticker';

  if sticker.id is null
    or not public.is_current_user_circle_member(sticker.circle_id)
  then
    raise exception 'Sticker not found or caller cannot use it'
      using errcode = '42501';
  end if;

  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Cannot send messages in this conversation'
      using errcode = '42501';
  end if;

  -- AutoMod (202610160035): a blocked message is dropped, not raised.
  perform set_config('wecord.automod_soft', 'on', true);

  -- The send trigger checks send_messages and slowmode in circle channels.
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
    sticker.name,
    jsonb_build_object(
      'kind', 'sticker',
      'emoji_id', sticker.id,
      'name', sticker.name,
      'circle_id', sticker.circle_id
    )
  )
  returning id into created_message_id;

  perform set_config('wecord.automod_soft', 'off', true);

  return created_message_id;
end;
$$;

-- Same as 202610130026_circle_emojis, but AutoMod refuses quietly: then
-- nothing is inserted and this returns null.
create or replace function public.forward_message(
  source_message_id uuid,
  target_conversation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  source_message public.messages%rowtype;
  source_sender_name text;
  created_message_id uuid;
begin
  select *
  into source_message
  from public.messages
  where id = source_message_id
    and recalled_at is null
    and type <> 'system'
    and type <> 'poll'
    and type <> 'sticker';

  if source_message.id is null
    or not public.is_current_user_conversation_member(source_message.conversation_id)
    or not public.is_current_user_conversation_member(target_conversation_id)
    or public.is_current_user_blocked_in_conversation(target_conversation_id)
  then
    raise exception 'Message cannot be forwarded' using errcode = '42501';
  end if;

  select display_name
  into source_sender_name
  from public.profiles
  where id = source_message.sender_id;

  -- AutoMod (202610160035): a blocked message is dropped, not raised.
  perform set_config('wecord.automod_soft', 'on', true);

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    attachment,
    forwarded_from
  )
  values (
    target_conversation_id,
    auth.uid(),
    source_message.type,
    source_message.body,
    source_message.attachment,
    jsonb_build_object(
      'message_id', source_message.id,
      'sender_id', source_message.sender_id,
      'sender_name', source_sender_name,
      'type', source_message.type,
      'body', source_message.body,
      'source_attachment_bucket', source_message.attachment->>'bucket',
      'source_attachment_path', source_message.attachment->>'path'
    )
  )
  returning id into created_message_id;

  perform set_config('wecord.automod_soft', 'off', true);

  return created_message_id;
end;
$$;

-- Same as 202610130023_polls, but AutoMod refuses quietly: then nothing
-- is inserted and this returns null.
create or replace function public.create_poll(
  target_conversation_id uuid,
  question text,
  options text[],
  multi boolean default false,
  duration_hours integer default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_question text := btrim(coalesce(question, ''));
  trimmed_options text[];
  option_count integer;
  poll_options jsonb;
  poll_ends_at timestamptz;
  created_message_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_question) not between 1 and 300 then
    raise exception 'Poll question must be 1 to 300 characters'
      using errcode = '22023';
  end if;

  select array_agg(btrim(coalesce(item.option_text, '')) order by item.ordinality)
  into trimmed_options
  from unnest(coalesce(options, array[]::text[]))
    with ordinality as item(option_text, ordinality);

  option_count := coalesce(cardinality(trimmed_options), 0);
  if option_count not between 2 and 10 then
    raise exception 'A poll needs 2 to 10 options' using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(trimmed_options) as item(option_text)
    where char_length(item.option_text) not between 1 and 100
  ) then
    raise exception 'Poll options must be 1 to 100 characters'
      using errcode = '22023';
  end if;

  if (
    select count(distinct lower(item.option_text))
    from unnest(trimmed_options) as item(option_text)
  ) <> option_count then
    raise exception 'Poll options must be different' using errcode = '22023';
  end if;

  if duration_hours is not null and duration_hours not between 1 and 168 then
    raise exception 'Poll duration must be 1 to 168 hours'
      using errcode = '22023';
  end if;

  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Cannot send messages in this conversation'
      using errcode = '42501';
  end if;

  select jsonb_agg(
    jsonb_build_object('id', 'o' || item.ordinality, 'text', item.option_text)
    order by item.ordinality
  )
  into poll_options
  from unnest(trimmed_options) with ordinality as item(option_text, ordinality);

  if duration_hours is not null then
    poll_ends_at := now() + make_interval(hours => duration_hours);
  end if;

  -- AutoMod (202610160035): a blocked message is dropped, not raised.
  perform set_config('wecord.automod_soft', 'on', true);

  -- The send trigger checks send_messages and slowmode in circle channels.
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
    'poll',
    trimmed_question,
    jsonb_build_object(
      'kind', 'poll',
      'question', trimmed_question,
      'options', poll_options,
      'multi', coalesce(multi, false),
      'ends_at', poll_ends_at
    )
  )
  returning id into created_message_id;

  perform set_config('wecord.automod_soft', 'off', true);

  return created_message_id;
end;
$$;

-- Same as 202610130021_forum_post_mentions, but AutoMod refuses quietly
-- (see the header).
create or replace function public.create_forum_post(
  target_channel_id uuid,
  post_title text,
  post_body text,
  tag_ids uuid[] default array[]::uuid[],
  post_attachment jsonb default null,
  post_mentions jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  channel public.circle_channels%rowtype;
  normalized_title text := nullif(
    regexp_replace(btrim(coalesce(post_title, '')), '\s+', ' ', 'g'),
    ''
  );
  trimmed_body text := btrim(coalesce(post_body, ''));
  normalized_tag_ids uuid[];
  visible_mentions jsonb;
  created_conversation_id uuid;
  created_thread public.conversation_threads%rowtype;
  created_message_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel.id is null
    or not public.can_current_user_send_in_conversation(channel.conversation_id)
  then
    raise exception 'Channel not found or caller cannot post in it'
      using errcode = '42501';
  end if;

  if channel.kind <> 'forum' then
    raise exception 'Channel is not a forum' using errcode = '22023';
  end if;

  if normalized_title is null or char_length(normalized_title) > 100 then
    raise exception 'Post title must be between 1 and 100 characters'
      using errcode = '22023';
  end if;

  if char_length(trimmed_body) > 4000 then
    raise exception 'Post body must be at most 4000 characters'
      using errcode = '22023';
  end if;

  if post_attachment is not null and (
    jsonb_typeof(post_attachment) <> 'object'
    or post_attachment ->> 'kind' is distinct from 'image'
    or post_attachment ->> 'bucket' is distinct from 'chat-images'
    or coalesce(post_attachment ->> 'path', '')
      not like channel.conversation_id::text || '/%'
  ) then
    raise exception 'Post images must be uploaded to this forum'
      using errcode = '22023';
  end if;

  if char_length(trimmed_body) = 0 and post_attachment is null then
    raise exception 'Post body is required' using errcode = '22023';
  end if;

  if post_mentions is not null
    and jsonb_typeof(post_mentions) is distinct from 'array'
  then
    raise exception 'Mentions must be an array' using errcode = '22023';
  end if;

  if char_length(trimmed_body) = 0 then
    post_mentions := '[]'::jsonb;
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(post_mentions, '[]'::jsonb)) mention
    where (mention->>'user_id') is not null
      and not exists (
        select 1
        from public.conversation_members cm
        where cm.conversation_id = channel.conversation_id
          and cm.user_id = (mention->>'user_id')::uuid
      )
  ) then
    raise exception 'mentioned users must be conversation members'
      using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(item.mention order by item.ordinality), '[]'::jsonb)
  into visible_mentions
  from jsonb_array_elements(coalesce(post_mentions, '[]'::jsonb))
    with ordinality as item(mention, ordinality)
  where (item.mention->>'user_id') is null
    or public.user_has_conversation_channel_permission(
      channel.conversation_id,
      (item.mention->>'user_id')::uuid,
      'view_channel'
    );

  normalized_tag_ids := public.normalize_forum_tag_ids(channel.id, tag_ids);

  insert into public.conversations (type, title)
  values ('thread', normalized_title)
  returning id into created_conversation_id;

  insert into public.conversation_members (conversation_id, user_id, role)
  select created_conversation_id, cm.user_id, 'member'
  from public.conversation_members cm
  where cm.conversation_id = channel.conversation_id
  on conflict do nothing;

  insert into public.conversation_threads (
    parent_conversation_id,
    root_message_id,
    conversation_id,
    title,
    created_by
  )
  values (
    channel.conversation_id,
    null,
    created_conversation_id,
    normalized_title,
    current_user_id
  )
  returning * into created_thread;

  -- AutoMod (202610160035): a blocked message is dropped, not raised.
  perform set_config('wecord.automod_soft', 'on', true);

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    attachment,
    mentions
  )
  values (
    created_conversation_id,
    current_user_id,
    case when char_length(trimmed_body) = 0 then 'image' else 'text' end,
    trimmed_body,
    post_attachment,
    visible_mentions
  )
  returning id into created_message_id;

  perform set_config('wecord.automod_soft', 'off', true);

  if created_message_id is null then
    -- The notice goes to the forum, where the app looks for it, and the
    -- empty thread goes away.
    delete from public.circle_automod_notices n
    where n.user_id = current_user_id
      and n.conversation_id = channel.conversation_id;

    update public.circle_automod_notices n
    set conversation_id = channel.conversation_id
    where n.user_id = current_user_id
      and n.conversation_id = created_conversation_id;

    delete from public.conversations c where c.id = created_conversation_id;

    return jsonb_build_object(
      'automod_blocked', true,
      'conversation_id', channel.conversation_id
    );
  end if;

  insert into public.message_mentions (
    message_id,
    conversation_id,
    user_id,
    kind
  )
  select
    created_message_id,
    created_conversation_id,
    (mention->>'user_id')::uuid,
    coalesce(nullif(mention->>'kind', ''), 'user')
  from jsonb_array_elements(visible_mentions) mention
  where (mention->>'user_id') is not null
  on conflict do nothing;

  insert into public.thread_tags (thread_id, tag_id, channel_id)
  select created_thread.id, tag_id, channel.id
  from unnest(normalized_tag_ids) as tag_id;

  -- The first message bumped the thread's activity.
  select ct.* into created_thread
  from public.conversation_threads ct
  where ct.id = created_thread.id;

  return public.forum_post_payload(created_thread, channel);
end;
$$;

revoke execute on function public.send_sticker(uuid, uuid) from public, anon;
revoke execute on function public.forward_message(uuid, uuid) from public, anon;
revoke execute on function public.create_poll(uuid, text, text[], boolean, integer) from public, anon;
revoke execute on function public.create_forum_post(uuid, text, text, uuid[], jsonb, jsonb) from public, anon;
grant execute on function public.send_sticker(uuid, uuid) to authenticated;
grant execute on function public.forward_message(uuid, uuid) to authenticated;
grant execute on function public.create_poll(uuid, text, text[], boolean, integer) to authenticated;
grant execute on function public.create_forum_post(uuid, text, text, uuid[], jsonb, jsonb) to authenticated;
