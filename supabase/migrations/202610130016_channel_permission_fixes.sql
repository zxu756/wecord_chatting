-- Loose ends of channel permissions (202610130014) and faster reads.
--
-- * Editing a message and hiding its embeds change what the channel shows,
--   so circle channels and their threads need send_messages for them, like
--   sending. Deleting your own message and reactions still only need access.
-- * Chat images and voice messages are uploaded before their message is
--   sent; uploading into a circle channel (or a thread of one) now needs
--   send_messages there too.
-- * Members who cannot see a channel are left out of its member list (and
--   so of @mention candidates) for everyone but themselves, and
--   send_text_message drops mentions of them.
-- * Pinning and managing threads in a channel follow the channel's
--   manage_messages, so overwrites apply to them as they do to slowmode.
-- * Reads: the messages, reactions, mentions, pins and threads policies
--   asked is_current_user_conversation_member once per row, which since
--   channel permissions computes the caller's permissions for every row of
--   a channel with overwrites. They now compare against the set of
--   conversations the caller can read, computed once per statement, with
--   the same result. The sender nickname and role colour fields become
--   plpgsql so their plans are cached across the rows of a message list.

-- The conversations the caller can read: those they are a member of, minus
-- circle channels (and their threads) without view_channel. Exactly the
-- conversations for which is_current_user_conversation_member is true.
create or replace function public.current_user_readable_conversation_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select cm.conversation_id
  from public.conversation_members cm
  left join public.conversation_threads ct
    on ct.conversation_id = cm.conversation_id
  left join public.circle_channels cc
    on cc.conversation_id = coalesce(ct.parent_conversation_id, cm.conversation_id)
  where cm.user_id = auth.uid()
    and case
      when cc.id is null then true
      when not exists (
          select 1
          from public.circle_channel_overwrites o
          where o.channel_id = cc.id
        )
        and exists (
          select 1
          from public.circle_roles r
          where r.circle_id = cc.circle_id
            and r.is_default
            and r.permissions & 1 <> 0
        )
        then true
      -- view_channel
      else public.circle_channel_permissions(cc.id, auth.uid()) & 1 <> 0
    end;
$$;

revoke execute on function public.current_user_readable_conversation_ids() from public;
revoke execute on function public.current_user_readable_conversation_ids() from anon;

drop policy if exists messages_select_member on public.messages;
create policy messages_select_member
  on public.messages for select
  to authenticated
  using (
    conversation_id in (select public.current_user_readable_conversation_ids())
  );

drop policy if exists message_reactions_select_member on public.message_reactions;
create policy message_reactions_select_member
  on public.message_reactions for select
  to authenticated
  using (
    conversation_id in (select public.current_user_readable_conversation_ids())
  );

drop policy if exists message_mentions_select_member on public.message_mentions;
create policy message_mentions_select_member
  on public.message_mentions for select
  to authenticated
  using (
    conversation_id in (select public.current_user_readable_conversation_ids())
  );

drop policy if exists pinned_messages_select_member on public.pinned_messages;
create policy pinned_messages_select_member
  on public.pinned_messages for select
  to authenticated
  using (
    conversation_id in (select public.current_user_readable_conversation_ids())
  );

drop policy if exists conversation_threads_select_member on public.conversation_threads;
create policy conversation_threads_select_member
  on public.conversation_threads for select
  to authenticated
  using (
    parent_conversation_id in (
      select public.current_user_readable_conversation_ids()
    )
  );

-- Whether a member of a conversation can see it: false outside circle
-- channels only when they are not a member. Answers only callers who are
-- members of the conversation themselves (circle members can read every
-- channel's overwrites anyway).
create or replace function public.conversation_member_can_view(
  target_conversation_id uuid,
  target_user_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id = target_conversation_id
      and cm.user_id = auth.uid()
  ) then
    return false;
  end if;

  return public.user_has_conversation_channel_permission(
    target_conversation_id,
    target_user_id,
    'view_channel'
  );
end;
$$;

revoke execute on function public.conversation_member_can_view(uuid, uuid) from public;
revoke execute on function public.conversation_member_can_view(uuid, uuid) from anon;

-- Same as 202605180001_private_chat, but members who cannot see a circle
-- channel (or its threads) are hidden from everyone else.
drop policy if exists conversation_members_select_member on public.conversation_members;
create policy conversation_members_select_member
  on public.conversation_members for select
  to authenticated
  using (
    user_id = auth.uid()
    or (
      conversation_id in (select public.current_user_readable_conversation_ids())
      and public.conversation_member_can_view(conversation_id, user_id)
    )
  );

-- Whether the caller can send in a conversation: a member who can see it
-- and, in circle channels and their threads, has send_messages.
create or replace function public.can_current_user_send_in_conversation(
  target_conversation_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return public.is_current_user_conversation_member(target_conversation_id)
    and public.user_has_conversation_channel_permission(
      target_conversation_id,
      auth.uid(),
      'send_messages'
    );
end;
$$;

revoke execute on function public.can_current_user_send_in_conversation(uuid) from public;
revoke execute on function public.can_current_user_send_in_conversation(uuid) from anon;

-- Same as 202605180003_image_messages and 202605180010_daily_chat_polish_v3,
-- but uploads need send permission.
drop policy if exists chat_images_insert_member on storage.objects;
create policy chat_images_insert_member
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'chat-images'
    and public.can_current_user_send_in_conversation(
      ((storage.foldername(name))[1])::uuid
    )
  );

drop policy if exists voice_messages_insert_member on storage.objects;
create policy voice_messages_insert_member
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'voice-messages'
    and public.can_current_user_send_in_conversation(
      split_part(name, '/', 1)::uuid
    )
  );

-- Same as 202605180005_social_chat_v2, but circle channels and their
-- threads need send_messages.
create or replace function public.edit_message(
  target_message_id uuid,
  body text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  trimmed_body text := trim(coalesce(body, ''));
  edited_message_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_body) = 0 then
    raise exception 'Message body is required' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.messages m
    where m.id = target_message_id
      and m.sender_id = auth.uid()
      and public.is_current_user_conversation_member(m.conversation_id)
      and not public.user_has_conversation_channel_permission(
        m.conversation_id,
        auth.uid(),
        'send_messages'
      )
  ) then
    raise exception 'You do not have permission to send messages in this channel'
      using errcode = '42501';
  end if;

  update public.messages m
  set
    body = trimmed_body,
    edited_at = now()
  where m.id = target_message_id
    and m.sender_id = auth.uid()
    and m.type = 'text'
    and m.recalled_at is null
    and public.is_current_user_conversation_member(m.conversation_id)
  returning m.id into edited_message_id;

  if edited_message_id is null then
    raise exception 'Message not found or cannot be edited'
      using errcode = '42501';
  end if;
end;
$$;

-- Same as 202610130009_link_previews, but circle channels and their
-- threads need send_messages.
create or replace function public.set_message_suppress_embeds(
  target_message_id uuid,
  suppress boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_message_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.messages m
  set suppress_embeds = coalesce(suppress, true)
  where m.id = target_message_id
    and m.sender_id = auth.uid()
    and m.type = 'text'
    and m.recalled_at is null
    and public.is_current_user_conversation_member(m.conversation_id)
    and public.user_has_conversation_channel_permission(
      m.conversation_id,
      auth.uid(),
      'send_messages'
    )
  returning m.id into updated_message_id;

  if updated_message_id is null then
    raise exception 'Message not found or caller cannot change its embeds'
      using errcode = '42501';
  end if;
end;
$$;

-- Same as 202605190002_fix_identity_safety_blocking, but mentions of
-- members who cannot see the channel are dropped (from the message and
-- from message_mentions).
create or replace function public.send_text_message(
  target_conversation_id uuid,
  body text,
  reply_to_message_id uuid default null,
  reply_preview jsonb default null,
  mentions jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_body text := trim(coalesce(body, ''));
  visible_mentions jsonb;
  created_message_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_body) = 0 then
    raise exception 'Message body is required' using errcode = '22023';
  end if;

  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Cannot send messages in this conversation'
      using errcode = '42501';
  end if;

  if send_text_message.reply_to_message_id is not null and not exists (
    select 1
    from public.messages m
    where m.id = send_text_message.reply_to_message_id
      and m.conversation_id = target_conversation_id
  ) then
    raise exception 'Reply message does not belong to conversation'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(mentions, '[]'::jsonb)) mention
    where (mention->>'user_id') is not null
      and not exists (
        select 1
        from public.conversation_members cm
        where cm.conversation_id = target_conversation_id
          and cm.user_id = (mention->>'user_id')::uuid
      )
  ) then
    raise exception 'mentioned users must be conversation members'
      using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(item.mention order by item.ordinality), '[]'::jsonb)
  into visible_mentions
  from jsonb_array_elements(coalesce(mentions, '[]'::jsonb))
    with ordinality as item(mention, ordinality)
  where (item.mention->>'user_id') is null
    or public.user_has_conversation_channel_permission(
      target_conversation_id,
      (item.mention->>'user_id')::uuid,
      'view_channel'
    );

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    reply_to_message_id,
    reply_preview,
    mentions
  )
  values (
    target_conversation_id,
    current_user_id,
    'text',
    trimmed_body,
    send_text_message.reply_to_message_id,
    send_text_message.reply_preview,
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
    target_conversation_id,
    (mention->>'user_id')::uuid,
    coalesce(nullif(mention->>'kind', ''), 'user')
  from jsonb_array_elements(visible_mentions) mention
  where (mention->>'user_id') is not null
  on conflict do nothing;

  return created_message_id;
end;
$$;

-- Same as 202610130012_circle_roles, but channels use the caller's
-- manage_messages in the channel (overwrites included).
create or replace function public.can_current_user_pin_messages(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select case c.type
        when 'direct' then public.is_current_user_conversation_member(c.id)
        when 'group' then exists (
          select 1
          from public.conversation_members cm
          where cm.conversation_id = c.id
            and cm.user_id = auth.uid()
            and cm.role = 'owner'
        )
        when 'channel' then public.is_current_user_conversation_member(c.id)
          and exists (
            select 1
            from public.circle_channels ch
            where ch.conversation_id = c.id
              and public.current_user_has_channel_permission(
                ch.id,
                'manage_messages'
              )
          )
        when 'thread' then public.is_current_user_conversation_member(c.id)
          and public.can_current_user_pin_messages(ct.parent_conversation_id)
        else false
      end
      from public.conversations c
      left join public.conversation_threads ct on ct.conversation_id = c.id
      where c.id = target_conversation_id
    ),
    false
  );
$$;

-- Same as 202610130012_circle_roles, but threads of a circle channel use
-- the caller's manage_messages in the channel (overwrites included).
create or replace function public.can_current_user_manage_thread(
  target_thread_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select public.is_current_user_conversation_member(ct.parent_conversation_id)
        and (
          ct.created_by = auth.uid()
          or case parent.type
            when 'channel' then exists (
              select 1
              from public.circle_channels cc
              where cc.conversation_id = parent.id
                and public.current_user_has_channel_permission(
                  cc.id,
                  'manage_messages'
                )
            )
            when 'group' then exists (
              select 1
              from public.conversation_members cm
              where cm.conversation_id = parent.id
                and cm.user_id = auth.uid()
                and cm.role in ('owner', 'admin')
            )
            else false
          end
        )
      from public.conversation_threads ct
      join public.conversations parent on parent.id = ct.parent_conversation_id
      where ct.id = target_thread_id
    ),
    false
  );
$$;

-- Same as 202610130011_message_threads, as plpgsql: message lists ask for
-- every row and nested SQL functions are planned on each call.
create or replace function public.circle_channel_nickname(
  target_conversation_id uuid,
  target_user_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  found_nickname text;
begin
  select cm.nickname
  into found_nickname
  from public.circle_channels cc
  join public.circle_members cm
    on cm.circle_id = cc.circle_id
    and cm.user_id = target_user_id
  where cc.conversation_id = coalesce(
      (
        select ct.parent_conversation_id
        from public.conversation_threads ct
        where ct.conversation_id = target_conversation_id
      ),
      target_conversation_id
    )
    and exists (
      select 1
      from public.circle_members viewer
      where viewer.circle_id = cc.circle_id
        and viewer.user_id = auth.uid()
    );

  return found_nickname;
end;
$$;

-- Same as 202610130012_circle_roles, as plpgsql (see above).
create or replace function public.circle_channel_role_color(
  target_conversation_id uuid,
  target_user_id uuid
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  found_color integer;
begin
  select (
    select r.color
    from public.circle_member_roles mr
    join public.circle_roles r on r.id = mr.role_id
    where mr.circle_id = cc.circle_id
      and mr.user_id = target_user_id
      and r.color is not null
    order by r.position desc
    limit 1
  )
  into found_color
  from public.circle_channels cc
  where cc.conversation_id = coalesce(
      (
        select ct.parent_conversation_id
        from public.conversation_threads ct
        where ct.conversation_id = target_conversation_id
      ),
      target_conversation_id
    )
    and exists (
      select 1
      from public.circle_members viewer
      where viewer.circle_id = cc.circle_id
        and viewer.user_id = auth.uid()
    );

  return found_color;
end;
$$;

grant execute on function public.current_user_readable_conversation_ids() to authenticated;
grant execute on function public.conversation_member_can_view(uuid, uuid) to authenticated;
grant execute on function public.can_current_user_send_in_conversation(uuid) to authenticated;
grant execute on function public.edit_message(uuid, text) to authenticated;
grant execute on function public.set_message_suppress_embeds(uuid, boolean) to authenticated;
grant execute on function public.send_text_message(uuid, text, uuid, jsonb, jsonb) to authenticated;
grant execute on function public.can_current_user_pin_messages(uuid) to authenticated;
grant execute on function public.can_current_user_manage_thread(uuid) to authenticated;
