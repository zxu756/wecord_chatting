-- Security audit (2026-10-19): messages that are hidden from readers
-- (expired, waiting for the AI guard) must also stay hidden in the functions
-- that read the messages table as its owner.
--
-- The messages select policy hides expired messages (202610170020) and
-- messages waiting for review (202610170090), but SECURITY DEFINER functions
-- bypass that policy, and several of them took a message id from the caller
-- and trusted it:
--
--   * create_task_from_message copied the text of an expired or held message
--     into a task the whole chat reads (a held message's id is known to
--     members through message_mentions and chains).
--   * create_thread titled a thread, which the whole channel sees, with the
--     first words of an expired or held message.
--   * forward_message forwarded an expired message that the purge had not
--     deleted yet (the purge runs every minute, and not at all without
--     pg_cron).
--   * save_message, set_message_reminder and toggle_message_reaction accepted
--     expired and held messages; claim_local_reminders handed out the text
--     of an expired one.
--   * list_conversation_summaries showed an expired latest message and
--     counted expired messages as unread; search_messages and
--     search_message_context found expired messages.
--   * A live location kept streaming after its (disappearing) card expired.
--
-- Each function below is the latest definition with the missing rule added;
-- nothing else is changed.

CREATE OR REPLACE FUNCTION public.create_thread(parent_conversation_id uuid, root_message_id uuid DEFAULT NULL::uuid, title text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  parent_type text;
  root_message public.messages%rowtype;
  existing_thread public.conversation_threads%rowtype;
  created_thread public.conversation_threads%rowtype;
  created_conversation_id uuid;
  normalized_title text := nullif(
    regexp_replace(btrim(coalesce(create_thread.title, '')), '\s+', ' ', 'g'),
    ''
  );
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select c.type
  into parent_type
  from public.conversations c
  where c.id = create_thread.parent_conversation_id;

  if parent_type is null
    or not public.is_current_user_conversation_member(
      create_thread.parent_conversation_id
    )
  then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  if parent_type not in ('channel', 'group') then
    raise exception 'Threads can only start in channels and groups'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.circle_channels cc
    where cc.conversation_id = create_thread.parent_conversation_id
      and cc.kind = 'forum'
  ) then
    raise exception 'Forum channels take posts, not threads'
      using errcode = '22023';
  end if;

  if not public.user_has_conversation_channel_permission(
    create_thread.parent_conversation_id,
    current_user_id,
    'send_messages'
  ) then
    raise exception 'You do not have permission to send messages in this channel'
      using errcode = '42501';
  end if;

  if create_thread.root_message_id is not null then
    -- Lock the root so concurrent calls agree on a single thread.
    select m.*
    into root_message
    from public.messages m
    where m.id = create_thread.root_message_id
      and m.conversation_id = create_thread.parent_conversation_id
      and (m.expires_at is null or m.expires_at > now())
      and public.message_visible_to_current_user(m.review_state, m.sender_id, m.conversation_id)
    for update;

    if root_message.id is null then
      raise exception 'Root message not found in this conversation'
        using errcode = '22023';
    end if;

    select ct.*
    into existing_thread
    from public.conversation_threads ct
    where ct.root_message_id = root_message.id;

    if existing_thread.id is not null then
      return public.thread_payload(existing_thread);
    end if;

    if root_message.recalled_at is not null or root_message.type = 'system' then
      raise exception 'Threads cannot start from this message'
        using errcode = '22023';
    end if;

    normalized_title := coalesce(
      normalized_title,
      nullif(
        left(regexp_replace(btrim(root_message.body), '\s+', ' ', 'g'), 40),
        ''
      ),
      case root_message.type
        when 'image' then 'Image'
        when 'voice' then 'Voice message'
        else 'Thread'
      end
    );
  end if;

  if normalized_title is null then
    raise exception 'Thread title is required' using errcode = '22023';
  end if;

  if char_length(normalized_title) > 100 then
    raise exception 'Thread title must be at most 100 characters'
      using errcode = '22023';
  end if;

  insert into public.conversations (type, title)
  values ('thread', normalized_title)
  returning id into created_conversation_id;

  insert into public.conversation_members (conversation_id, user_id, role)
  select created_conversation_id, cm.user_id, 'member'
  from public.conversation_members cm
  where cm.conversation_id = create_thread.parent_conversation_id
  on conflict do nothing;

  insert into public.conversation_threads (
    parent_conversation_id,
    root_message_id,
    conversation_id,
    title,
    created_by
  )
  values (
    create_thread.parent_conversation_id,
    create_thread.root_message_id,
    created_conversation_id,
    normalized_title,
    current_user_id
  )
  returning * into created_thread;

  return public.thread_payload(created_thread);
end;
$function$;

CREATE OR REPLACE FUNCTION public.forward_message(source_message_id uuid, target_conversation_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    and (expires_at is null or expires_at > now())
    and type <> 'system'
    and type <> 'poll'
    and type <> 'sticker'
    and review_state is null;

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
$function$;

CREATE OR REPLACE FUNCTION public.create_task_from_message(p_message_id uuid, p_list_id uuid DEFAULT NULL::uuid, p_title text DEFAULT NULL::text, p_item_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  m public.messages%rowtype;
  target_list uuid := p_list_id;
  item_title text;
  existing public.task_items%rowtype;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into m
  from public.messages
  where id = p_message_id
    and (expires_at is null or expires_at > now())
    and public.message_visible_to_current_user(review_state, sender_id, conversation_id);
  if m.id is null or not public.is_current_user_conversation_member(m.conversation_id) then
    raise exception 'Message not found' using errcode = 'P0002';
  end if;
  if m.recalled_at is not null or m.type = 'system' then
    raise exception 'This message cannot become a task' using errcode = '22023';
  end if;
  if not public.can_current_user_write_docs(m.conversation_id) then
    raise exception 'You cannot create tasks here' using errcode = '42501';
  end if;

  -- Sent before (the answer got lost).
  if p_item_id is not null then
    select * into existing from public.task_items where id = p_item_id;
    if existing.id is not null then
      return public.task_item_json(existing);
    end if;
  end if;

  if target_list is null then
    select l.id into target_list
    from public.task_lists l
    where l.conversation_id = m.conversation_id and l.deleted_at is null
    order by l.created_at, l.id
    limit 1;
    if target_list is null then
      target_list := (
        public.create_task_list(m.conversation_id, 'Tasks', null)->>'id'
      )::uuid;
    end if;
  elsif not exists (
    select 1 from public.task_lists l
    where l.id = target_list and l.conversation_id = m.conversation_id and l.deleted_at is null
  ) then
    raise exception 'List not found' using errcode = 'P0002';
  end if;

  item_title := nullif(btrim(coalesce(p_title, '')), '');
  if item_title is null then
    item_title := nullif(btrim(split_part(btrim(m.body), E'\n', 1)), '');
  end if;
  if item_title is null then
    item_title := case m.type
      when 'image' then 'Picture'
      when 'voice' then 'Voice message'
      when 'file' then coalesce(nullif(m.attachment->>'name', ''), 'File')
      when 'poll' then coalesce(nullif(m.attachment->>'question', ''), 'Poll')
      else 'Task from a message'
    end;
  end if;
  item_title := left(item_title, 300);

  return public.upsert_task_item(
    target_list,
    jsonb_build_object(
      'id', coalesce(p_item_id, gen_random_uuid()),
      'title', item_title,
      'source_message_id', m.id
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_message(p_message_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  target_conversation_id uuid;
  saved_id uuid;
  saved_count integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select m.conversation_id
  into target_conversation_id
  from public.messages m
  where m.id = p_message_id
    and m.recalled_at is null
    and (m.expires_at is null or m.expires_at > now())
    and public.message_visible_to_current_user(m.review_state, m.sender_id, m.conversation_id)
    and m.conversation_id in (select public.current_user_readable_conversation_ids());
  if target_conversation_id is null then
    raise exception 'Message not found' using errcode = 'P0002';
  end if;

  select s.id
  into saved_id
  from public.saved_messages s
  where s.user_id = current_user_id
    and s.message_id = p_message_id;
  if saved_id is not null then
    return saved_id;
  end if;

  select count(*)
  into saved_count
  from public.saved_messages s
  where s.user_id = current_user_id;
  if saved_count >= 1000 then
    raise exception 'Too many saved messages' using errcode = '53400';
  end if;

  insert into public.saved_messages (user_id, message_id, conversation_id)
  values (current_user_id, p_message_id, target_conversation_id)
  on conflict do nothing
  returning id into saved_id;

  if saved_id is null then
    select s.id
    into saved_id
    from public.saved_messages s
    where s.user_id = current_user_id
      and s.message_id = p_message_id;
  end if;
  return saved_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_message_reminder(p_message_id uuid, p_remind_at timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  target_conversation_id uuid;
  reminder_id uuid;
  open_count integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_remind_at is null
    or p_remind_at < now() - interval '1 minute'
    or p_remind_at > now() + interval '1 year'
  then
    raise exception 'Reminder time must be in the next year' using errcode = '22023';
  end if;

  select m.conversation_id
  into target_conversation_id
  from public.messages m
  where m.id = p_message_id
    and m.recalled_at is null
    and (m.expires_at is null or m.expires_at > now())
    and public.message_visible_to_current_user(m.review_state, m.sender_id, m.conversation_id)
    and m.conversation_id in (select public.current_user_readable_conversation_ids());
  if target_conversation_id is null then
    raise exception 'Message not found' using errcode = 'P0002';
  end if;

  -- One open reminder per message: setting it again moves it.
  delete from public.message_reminders r
  where r.user_id = current_user_id
    and r.message_id = p_message_id
    and r.dismissed_at is null;

  select count(*)
  into open_count
  from public.message_reminders r
  where r.user_id = current_user_id
    and r.dismissed_at is null
    and r.remind_at > now();
  if open_count >= 200 then
    raise exception 'Too many reminders' using errcode = '53400';
  end if;

  insert into public.message_reminders (user_id, message_id, conversation_id, remind_at)
  values (current_user_id, p_message_id, target_conversation_id, p_remind_at)
  returning id into reminder_id;

  return reminder_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.toggle_message_reaction(target_message_id uuid, target_emoji text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  normalized_emoji text := btrim(coalesce(target_emoji, ''));
  target_conversation_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(normalized_emoji) not between 1 and 64 then
    raise exception 'Reaction emoji must be 1 to 64 characters'
      using errcode = '22023';
  end if;

  select m.conversation_id
  into target_conversation_id
  from public.messages m
  where m.id = target_message_id
    and m.recalled_at is null
    and (m.expires_at is null or m.expires_at > now())
    and public.message_visible_to_current_user(m.review_state, m.sender_id, m.conversation_id);

  if target_conversation_id is null
    or not public.is_current_user_conversation_member(target_conversation_id)
  then
    raise exception 'Message not found or caller is not a member'
      using errcode = '42501';
  end if;

  delete from public.message_reactions
  where message_id = target_message_id
    and user_id = current_user_id
    and emoji = normalized_emoji;

  if found then
    return false;
  end if;

  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Message cannot be reacted to' using errcode = '42501';
  end if;

  if normalized_emoji like 'custom:%'
    and (
      normalized_emoji !~ '^custom:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or not exists (
        select 1
        from public.circle_emojis e
        join public.circle_members cm
          on cm.circle_id = e.circle_id
          and cm.user_id = current_user_id
        where e.id = substr(normalized_emoji, 8)::uuid
          and e.kind = 'emoji'
      )
    )
  then
    raise exception 'Unknown custom emoji' using errcode = '22023';
  end if;

  insert into public.message_reactions (
    message_id,
    user_id,
    emoji,
    conversation_id
  )
  values (
    target_message_id,
    current_user_id,
    normalized_emoji,
    target_conversation_id
  )
  on conflict do nothing;

  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.claim_local_reminders()
 RETURNS TABLE(reminder_id uuid, conversation_id uuid, message_id uuid, remind_at timestamp with time zone, sender_name text, body text, type text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  return query
  with due as (
    update public.message_reminders r
    set local_notified_at = now()
    where r.user_id = auth.uid()
      and r.remind_at <= now()
      and r.local_notified_at is null
      and r.dismissed_at is null
    returning r.id, r.conversation_id, r.message_id, r.remind_at
  )
  select
    due.id,
    due.conversation_id,
    due.message_id,
    due.remind_at,
    coalesce(
      m.webhook_name,
      nullif(btrim(public.sender_nickname(m)), ''),
      nullif(btrim(p.display_name), ''),
      p.username
    ),
    m.body,
    m.type
  from due
  join public.messages m on m.id = due.message_id
  join public.profiles p on p.id = m.sender_id
  where due.remind_at > now() - interval '1 hour'
    and m.recalled_at is null
    and (m.expires_at is null or m.expires_at > now())
    and public.message_visible_to_current_user(m.review_state, m.sender_id, m.conversation_id)
    and due.conversation_id in (select public.current_user_readable_conversation_ids())
  order by due.remind_at;
end;
$function$;

CREATE OR REPLACE FUNCTION public.list_conversation_summaries()
 RETURNS TABLE(id uuid, type text, title text, avatar_url text, announcement text, announcement_updated_at timestamp with time zone, announcement_updated_by uuid, last_message_body text, last_message_sender_id uuid, last_message_at timestamp with time zone, last_message_type text, last_message_webhook_name text, last_message_attachment_kind text, last_message_album jsonb, unread_count bigint, pinned_at timestamp with time zone, muted_until timestamp with time zone, is_muted boolean, is_marked_unread boolean, member_count bigint, mentioned_user_ids uuid[], circle_id uuid, circle_notification_level text, circle_muted_until timestamp with time zone, direct_user_id uuid, direct_custom_status jsonb, parent_conversation_id uuid, parent_title text, thread_id uuid, thread_archived_at timestamp with time zone, thread_last_activity_at timestamp with time zone, can_send_messages boolean, slowmode_seconds integer, is_note_to_self boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with current_memberships as (
    select
      cm.conversation_id,
      cm.last_read_message_id,
      cm.pinned_at,
      cm.muted_until,
      cm.hidden_at,
      cm.manual_unread_at
    from public.conversation_members cm
    where cm.user_id = auth.uid()
      and public.user_has_conversation_channel_permission(
        cm.conversation_id,
        auth.uid(),
        'view_channel'
      )
  ),
  read_markers as (
    select cm.conversation_id, rm.created_at as last_read_at
    from current_memberships cm
    left join public.messages rm on rm.id = cm.last_read_message_id
  ),
  -- Messages from others (and webhooks) after the read marker, an album
  -- counted once. Worked out per conversation on its own, so the summary
  -- query below needs no GROUP BY over all its columns.
  unread_counts as (
    select
      rm.conversation_id,
      count(unread_messages.id)
        - count(unread_messages.attachment_group_id)
        + count(distinct unread_messages.attachment_group_id) as unread_count
    from read_markers rm
    join public.messages unread_messages
      on unread_messages.conversation_id = rm.conversation_id
      and unread_messages.review_state is null
      and (unread_messages.expires_at is null or unread_messages.expires_at > now())
      -- A pat is only a line in the chat, never unread.
      and not (
        unread_messages.type = 'system'
        and unread_messages.attachment->>'kind' = 'pat'
      )
      and (
        unread_messages.sender_id <> auth.uid()
        or unread_messages.webhook_name is not null
      )
      and (
        rm.last_read_at is null
        or unread_messages.created_at > rm.last_read_at
      )
    group by rm.conversation_id
  ),
  direct_profiles as (
    select
      cm.conversation_id,
      p.id as user_id,
      coalesce(ca.alias, p.display_name) as display_name,
      p.avatar_url,
      case
        when exists (
          select 1
          from public.blocks b
          where b.blocker_id = p.id
            and b.blocked_id = auth.uid()
        ) then null
        else public.custom_status(p)
      end as custom_status
    from public.conversation_members cm
    join public.profiles p on p.id = cm.user_id
    left join public.contact_aliases ca
      on ca.owner_id = auth.uid()
      and ca.friend_id = p.id
    where cm.user_id <> auth.uid()
  ),
  member_counts as (
    select cm.conversation_id, count(*) as member_count
    from public.conversation_members cm
    group by cm.conversation_id
  ),
  last_message_mentions as (
    select mm.message_id, array_agg(distinct mm.user_id) as mentioned_user_ids
    from public.message_mentions mm
    group by mm.message_id
  )
  select
    c.id,
    c.type,
    coalesce(c.title, dp.display_name) as title,
    coalesce(c.avatar_url, dp.avatar_url) as avatar_url,
    c.announcement,
    c.announcement_updated_at,
    c.announcement_updated_by,
    case
      when last_message.recalled_at is not null then 'Message deleted'
      when last_message.type = 'image' then '[Image]'
      else last_message.body
    end as last_message_body,
    last_message.sender_id as last_message_sender_id,
    c.last_message_at,
    last_message.type as last_message_type,
    last_message.webhook_name as last_message_webhook_name,
    case
      when last_message.recalled_at is not null then null
      when last_message.type <> 'file' then null
      when last_message.attachment->>'kind' = 'video'
        or last_message.attachment->>'mime_type' like 'video/%' then 'video'
      else 'file'
    end as last_message_attachment_kind,
    case
      when album.total >= 2 then album.counts
      else null
    end as last_message_album,
    greatest(
      coalesce(uc.unread_count, 0),
      case when cm.manual_unread_at is null then 0 else 1 end::bigint
    ) as unread_count,
    cm.pinned_at,
    cm.muted_until,
    cm.muted_until is not null and cm.muted_until > now() as is_muted,
    cm.manual_unread_at is not null as is_marked_unread,
    coalesce(mc.member_count, 0) as member_count,
    coalesce(lmm.mentioned_user_ids, array[]::uuid[]) as mentioned_user_ids,
    cc.circle_id,
    case
      when cc.circle_id is null then null
      else coalesce(cns.level, 'all')
    end as circle_notification_level,
    cns.muted_until as circle_muted_until,
    dp.user_id as direct_user_id,
    dp.custom_status as direct_custom_status,
    ct.parent_conversation_id,
    parent_conversation.title as parent_title,
    ct.id as thread_id,
    ct.archived_at as thread_archived_at,
    coalesce(ct.last_message_at, ct.created_at) as thread_last_activity_at,
    cc.id is null
      or public.circle_channel_has_permission(
        cc.id,
        auth.uid(),
        'send_messages'
      ) as can_send_messages,
    case
      when ct.id is null
        and cc.slowmode_seconds > 0
        and not public.circle_channel_has_permission(
          cc.id,
          auth.uid(),
          'manage_messages'
        )
        then cc.slowmode_seconds
      else 0
    end as slowmode_seconds,
    nts.conversation_id is not null as is_note_to_self
  from public.conversations c
  join current_memberships cm on cm.conversation_id = c.id
  left join read_markers rm on rm.conversation_id = c.id
  left join direct_profiles dp on dp.conversation_id = c.id and c.type = 'direct'
  left join member_counts mc on mc.conversation_id = c.id
  left join public.messages last_message
    on last_message.id = c.last_message_id
    -- An expired message is gone even before the purge deletes it, and one
    -- waiting for review is not the chat's latest message for anyone else.
    and (last_message.expires_at is null or last_message.expires_at > now())
    and public.message_visible_to_current_user(last_message.review_state, last_message.sender_id, last_message.conversation_id)
  left join last_message_mentions lmm on lmm.message_id = last_message.id
  -- The rest of the latest message's album, if it is in one.
  left join lateral (
    select
      count(*) as total,
      jsonb_build_object(
        'images', count(*) filter (where album_message.type = 'image'),
        'videos', count(*) filter (
          where album_message.type = 'file'
            and coalesce(
              album_message.attachment->>'kind' = 'video'
                or album_message.attachment->>'mime_type' like 'video/%',
              false
            )
        ),
        'files', count(*) filter (
          where album_message.type = 'file'
            and not coalesce(
              album_message.attachment->>'kind' = 'video'
                or album_message.attachment->>'mime_type' like 'video/%',
              false
            )
        )
      ) as counts
    from public.messages album_message
    where album_message.conversation_id = c.id
      and album_message.sender_id = last_message.sender_id
      and album_message.attachment_group_id = last_message.attachment_group_id
      and album_message.recalled_at is null
  ) album
    on last_message.attachment_group_id is not null
    and last_message.recalled_at is null
  left join public.conversation_threads ct on ct.conversation_id = c.id
  left join public.conversations parent_conversation
    on parent_conversation.id = ct.parent_conversation_id
  left join public.circle_channels cc
    on cc.conversation_id = coalesce(ct.parent_conversation_id, c.id)
  left join public.circle_notification_settings cns
    on cns.circle_id = cc.circle_id
    and cns.user_id = auth.uid()
  left join unread_counts uc on uc.conversation_id = c.id
  left join public.note_to_self_conversations nts
    on nts.conversation_id = c.id
    and nts.user_id = auth.uid()
  where cm.hidden_at is null
    or c.last_message_at > cm.hidden_at
  order by
    (nts.conversation_id is not null) desc,
    cm.pinned_at desc nulls last,
    c.last_message_at desc nulls last,
    c.updated_at desc;
$function$;

CREATE OR REPLACE FUNCTION public.search_messages(query text, filters jsonb, scope jsonb, sort text, max_results integer, cursor jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  caller uuid := auth.uid();
  search_text text := left(btrim(coalesce(query, '')), 256);
  f jsonb := coalesce(filters, '{}'::jsonb);
  sort_by text := coalesce(nullif(sort, ''), 'newest');
  page_size integer := least(greatest(coalesce(max_results, 25), 1), 50);
  conversation_ids uuid[];
  in_ids uuid[];
  from_ids uuid[];
  mention_ids uuid[];
  kinds text[];
  offset_minutes integer;
  lower_bound timestamptz;
  upper_bound timestamptz;
  vector_sql constant text := 'e.vector';
  document_sql constant text := 'e.document';
  conditions text := '';
  rank_query tsquery;
  rank_sql text := '0::real';
  term record;
  term_text text;
  term_query tsquery;
  term_condition text;
  has_criteria boolean := false;
  cursor_sql text := '';
  order_sql text;
  base_sql text;
  page jsonb;
  results jsonb := '[]'::jsonb;
  next_cursor jsonb;
  counts jsonb;
  places jsonb;
  total integer;
  row_count integer;
  last_row jsonb;
begin
  if caller is null then
    raise exception 'Sign in to search messages' using errcode = '42501';
  end if;
  if sort_by not in ('newest', 'oldest', 'relevance') then
    raise exception 'Unknown search sort %', sort_by using errcode = '22023';
  end if;

  conversation_ids := public.search_scope_conversation_ids(scope);

  in_ids := public.search_uuid_array(f->'in');
  if cardinality(in_ids) > 0 then
    has_criteria := true;
    conversation_ids := array(
      select unnest(conversation_ids)
      intersect
      select unnest(
        public.search_scope_conversation_ids(
          jsonb_build_object('type', 'conversation', 'id', to_jsonb(in_ids))
        )
      )
    );
  end if;

  if cardinality(conversation_ids) = 0 then
    return jsonb_build_object(
      'results', '[]'::jsonb,
      'next_cursor', null,
      'total', case when cursor is null then 0 end,
      'total_capped', false,
      'conversations', '[]'::jsonb
    );
  end if;

  -- Words and phrases.
  for term in
    select
      coalesce(match[1], match[3]) = '-' as negated,
      lower(btrim(coalesce(match[2], match[4]))) as text
    from regexp_matches(search_text, '(-?)"([^"]*)"?|(-?)(\S+)', 'g') match
  loop
    term_text := term.text;
    continue when term_text is null or term_text = '';
    term_query := phraseto_tsquery(
      'simple'::regconfig,
      public.search_split_cjk(term_text)
    );
    term_condition := null;
    if numnode(term_query) > 0 then
      term_condition := format('%s @@ %L::tsquery', vector_sql, term_query::text);
    end if;
    if char_length(term_text) >= 3 then
      term_condition := concat_ws(
        ' or ',
        term_condition,
        format(
          '%s like %L',
          document_sql,
          public.search_like_pattern(term_text)
        )
      );
    end if;
    continue when term_condition is null;
    if term.negated then
      conditions := conditions || format(' and not (%s)', term_condition);
    else
      has_criteria := true;
      conditions := conditions || format(' and (%s)', term_condition);
      if numnode(term_query) > 0 then
        rank_query := case
          when rank_query is null then term_query
          else rank_query && term_query
        end;
      end if;
    end if;
  end loop;

  -- Filters.
  from_ids := public.search_uuid_array(f->'from');
  if cardinality(from_ids) > 0 then
    has_criteria := true;
    conditions := conditions
      || format(' and e.sender_id = any(%L::uuid[])', from_ids);
  end if;

  mention_ids := public.search_uuid_array(f->'mentions');
  if cardinality(mention_ids) > 0 then
    has_criteria := true;
    conditions := conditions || format(
      ' and e.message_id in (select mm.message_id from public.message_mentions mm'
      ' where mm.kind = ''user'' and mm.user_id = any(%L::uuid[]))',
      mention_ids
    );
  end if;

  select coalesce(array_agg(distinct k), '{}'::text[])
  into kinds
  from jsonb_array_elements_text(
    case jsonb_typeof(f->'has')
      when 'array' then f->'has'
      when 'string' then jsonb_build_array(f->'has')
      else '[]'::jsonb
    end
  ) k;
  if exists (
    select 1 from unnest(kinds) k
    where k not in ('image', 'video', 'file', 'voice', 'poll', 'sticker', 'link')
  ) then
    raise exception 'Unknown has: filter' using errcode = '22023';
  end if;
  if cardinality(kinds) > 0 then
    has_criteria := true;
    conditions := conditions || format(
      ' and e.kinds @> %L::text[]',
      kinds
    );
  end if;

  offset_minutes := coalesce((f->>'utc_offset_minutes')::integer, 0);
  lower_bound := public.search_filter_instant(f->>'after', offset_minutes, 1);
  upper_bound := public.search_filter_instant(f->>'before', offset_minutes, 0);
  if f->>'during' is not null then
    lower_bound := greatest(
      lower_bound,
      public.search_filter_instant(f->>'during', offset_minutes, 0)
    );
    upper_bound := least(
      upper_bound,
      public.search_filter_instant(f->>'during', offset_minutes, 1)
    );
  end if;
  if lower_bound is not null then
    has_criteria := true;
    conditions := conditions
      || format(' and e.created_at >= %L::timestamptz', lower_bound);
  end if;
  if upper_bound is not null then
    has_criteria := true;
    conditions := conditions
      || format(' and e.created_at < %L::timestamptz', upper_bound);
  end if;

  if jsonb_typeof(f->'pinned') = 'boolean' then
    has_criteria := true;
    conditions := conditions || format(
      ' and e.message_id %s (select pm.message_id from public.pinned_messages pm'
      ' where pm.conversation_id = any($1))',
      case when (f->>'pinned')::boolean then 'in' else 'not in' end
    );
  end if;

  if not has_criteria then
    return jsonb_build_object(
      'results', '[]'::jsonb,
      'next_cursor', null,
      'total', case when cursor is null then 0 end,
      'total_capped', false,
      'conversations', '[]'::jsonb
    );
  end if;

  if sort_by = 'relevance' and rank_query is not null then
    rank_sql := format(
      'ts_rank_cd(%s, %L::tsquery)::real',
      vector_sql,
      rank_query::text
    );
  end if;

  base_sql := format(
    'select e.message_id as id, e.created_at, %s as search_rank'
    ' from public.message_search_entries e'
    ' where e.conversation_id = any($1)%s',
    rank_sql,
    conditions
  );

  if cursor is not null then
    cursor_sql := case sort_by
      when 'oldest' then format(
        ' where (r.created_at, r.id) > (%L::timestamptz, %L::uuid)',
        cursor->>'created_at', cursor->>'id'
      )
      when 'newest' then format(
        ' where (r.created_at, r.id) < (%L::timestamptz, %L::uuid)',
        cursor->>'created_at', cursor->>'id'
      )
      else format(
        ' where (r.search_rank, r.created_at, r.id)'
        ' < (%L::real, %L::timestamptz, %L::uuid)',
        coalesce(cursor->>'rank', '0'), cursor->>'created_at', cursor->>'id'
      )
    end;
  end if;
  order_sql := case sort_by
    when 'oldest' then 'r.created_at asc, r.id asc'
    when 'newest' then 'r.created_at desc, r.id desc'
    else 'r.search_rank desc, r.created_at desc, r.id desc'
  end;

  execute format(
    'select coalesce(jsonb_agg('
    '  public.search_message_json(m, r.search_rank, $2)'
    '  order by r.ordinal), ''[]''::jsonb)'
    ' from (select r.*, row_number() over (order by %s) as ordinal'
    '  from (select * from (%s) r%s order by %s limit %s) r) r'
    ' join public.messages m on m.id = r.id'
    ' and (m.expires_at is null or m.expires_at > now())',
    order_sql,
    base_sql,
    cursor_sql,
    order_sql,
    page_size + 1
  ) into page using conversation_ids, caller;

  row_count := jsonb_array_length(page);
  if row_count > page_size then
    results := page - page_size;
    last_row := results->(page_size - 1);
    next_cursor := jsonb_build_object(
      'created_at', last_row->'created_at',
      'id', last_row->'id',
      'rank', last_row->'rank'
    );
  else
    results := page;
  end if;

  -- Where each result lives, once per conversation.
  select coalesce(
    jsonb_object_agg(id, public.search_conversation_json(id, caller)),
    '{}'::jsonb
  )
  into places
  from (
    select distinct (item->>'conversation_id')::uuid as id
    from jsonb_array_elements(results) item
  ) page_conversations;
  select coalesce(jsonb_agg(
    item || jsonb_build_object('conversation', places->(item->>'conversation_id'))
    order by ordinal
  ), '[]'::jsonb)
  into results
  from jsonb_array_elements(results) with ordinality as items(item, ordinal);

  if cursor is null then
    execute format(
      'select coalesce(sum(n), 0)::integer, coalesce(jsonb_agg(jsonb_build_object('
      '  ''conversation_id'', conversation_id, ''count'', n) order by n desc), ''[]''::jsonb)'
      ' from (select conversation_id, count(*) as n'
      '  from (select e.conversation_id from public.message_search_entries e'
      '   where e.conversation_id = any($1)%s limit 1001) capped'
      '  group by conversation_id) per_conversation',
      conditions
    ) into total, counts using conversation_ids;
  end if;

  return jsonb_build_object(
    'results', results,
    'next_cursor', next_cursor,
    'total', case when cursor is null then least(total, 1000) end,
    'total_capped', coalesce(total > 1000, false),
    'conversations', coalesce(counts, '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.search_message_context(target_message_id uuid, before_count integer, after_count integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  caller uuid := auth.uid();
  target public.messages;
  before_rows jsonb;
  after_rows jsonb;
begin
  if caller is null then
    raise exception 'Sign in to search messages' using errcode = '42501';
  end if;
  select m.* into target
  from public.messages m
  where m.id = target_message_id
    and m.conversation_id in (
      select public.current_user_readable_conversation_ids()
    )
    and public.message_visible_to_current_user(m.review_state, m.sender_id, m.conversation_id)
    and (m.expires_at is null or m.expires_at > now());
  if target.id is null then
    return jsonb_build_object('before', '[]'::jsonb, 'after', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(public.search_message_json(b, 0, caller)
    order by b.created_at, b.id), '[]'::jsonb)
  into before_rows
  from (
    select m.*
    from public.messages m
    where m.conversation_id = target.conversation_id
      and (m.created_at, m.id) < (target.created_at, target.id)
      and m.recalled_at is null
      and m.type <> 'system'
      and public.message_visible_to_current_user(m.review_state, m.sender_id, m.conversation_id)
    and (m.expires_at is null or m.expires_at > now())
    order by m.created_at desc, m.id desc
    limit least(greatest(coalesce(before_count, 1), 0), 10)
  ) b;

  select coalesce(jsonb_agg(public.search_message_json(a, 0, caller)
    order by a.created_at, a.id), '[]'::jsonb)
  into after_rows
  from (
    select m.*
    from public.messages m
    where m.conversation_id = target.conversation_id
      and (m.created_at, m.id) > (target.created_at, target.id)
      and m.recalled_at is null
      and m.type <> 'system'
      and public.message_visible_to_current_user(m.review_state, m.sender_id, m.conversation_id)
    and (m.expires_at is null or m.expires_at > now())
    order by m.created_at, m.id
    limit least(greatest(coalesce(after_count, 1), 0), 10)
  ) a;

  return jsonb_build_object('before', before_rows, 'after', after_rows);
end;
$function$;

CREATE OR REPLACE FUNCTION public.can_see_live_location_share(target_share_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.live_location_shares s
    where s.id = target_share_id
      and auth.uid() is not null
      and public.is_current_user_conversation_member(s.conversation_id)
      and (
        s.user_id = auth.uid()
        or (
          not public.are_users_blocked(auth.uid(), s.user_id)
          and exists (
            select 1
            from public.messages m
            where m.id = s.message_id
              and m.recalled_at is null
              and (m.expires_at is null or m.expires_at > now())
              and m.review_state is null
          )
        )
      )
  );
$function$;
