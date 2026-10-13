-- Forum posts record their @mentions like other messages: create_forum_post
-- takes post_mentions in send_text_message's shape ({user_id, display_name,
-- start, end, kind} over the trimmed body), stores the ones of members who
-- can see the forum on the opening message and in message_mentions, and
-- drops the others (202610130016). Mentioned users must be members of the
-- forum's conversation. Image-only posts take no mentions.

drop function if exists public.create_forum_post(uuid, text, text, uuid[], jsonb);

-- Same as 202610130020_forum_channels, plus post_mentions.
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

revoke execute on function public.create_forum_post(uuid, text, text, uuid[], jsonb, jsonb) from public;
revoke execute on function public.create_forum_post(uuid, text, text, uuid[], jsonb, jsonb) from anon;
grant execute on function public.create_forum_post(uuid, text, text, uuid[], jsonb, jsonb) to authenticated;
