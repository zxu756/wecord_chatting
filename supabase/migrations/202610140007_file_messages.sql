-- File and video messages.
--
-- * Bucket chat-files (private, 50 MB per file) holds any file sent in a
--   chat under <conversation id>/…, like chat-images: members of the
--   conversation (and of conversations a message was forwarded to) can read
--   it, and only people who may send there can upload.
-- * Messages of type 'file' carry {kind: 'file' | 'video', bucket, path,
--   name, size, mime_type}.
-- * Deleting a message (or a ban that deletes messages) also removes its
--   file, as for images and voice messages.

insert into storage.buckets (id, name, public, file_size_limit)
values ('chat-files', 'chat-files', false, 52428800)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit;

drop policy if exists chat_files_select_member on storage.objects;
create policy chat_files_select_member
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'chat-files'
    and (
      public.is_current_user_conversation_member(
        ((storage.foldername(name))[1])::uuid
      )
      or exists (
        select 1
        from public.messages m
        where m.forwarded_from->>'source_attachment_path' = objects.name
          and m.forwarded_from->>'source_attachment_bucket' = objects.bucket_id
          and m.recalled_at is null
          and public.is_current_user_conversation_member(m.conversation_id)
      )
    )
  );

drop policy if exists chat_files_insert_member on storage.objects;
create policy chat_files_insert_member
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'chat-files'
    and public.can_current_user_send_in_conversation(
      ((storage.foldername(name))[1])::uuid
    )
  );

drop policy if exists message_media_delete_recalled on storage.objects;
create policy message_media_delete_recalled
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = any (array['chat-images', 'voice-messages', 'chat-files'])
    and public.can_current_user_delete_recalled_media(bucket_id, name)
  );

-- Same as 202610130027_erase_recalled_content, plus chat-files.
create or replace function public.can_current_user_delete_recalled_media(
  target_bucket_id text,
  target_object_path text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
    and coalesce(target_bucket_id in ('chat-images', 'voice-messages', 'chat-files'), false)
    and exists (
      select 1
      from public.recalled_message_media r
      where r.bucket_id = target_bucket_id
        and r.object_path = target_object_path
        and r.deleted_by = auth.uid()
    )
    and not exists (
      select 1
      from public.messages m
      where m.attachment->>'path' = target_object_path
        and m.attachment->>'bucket' = target_bucket_id
    );
$$;

create or replace function public.recall_message(
  target_message_id uuid
)
returns table (bucket_id text, object_path text)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target public.messages%rowtype;
  is_own boolean;
  channel public.circle_channels%rowtype;
  media_bucket text;
  media_path text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select m.*
  into target
  from public.messages m
  where m.id = target_message_id
  for update;

  if target.id is null
    or target.type = 'system'
    or not public.is_current_user_conversation_member(target.conversation_id)
  then
    raise exception 'Message not found or cannot be deleted'
      using errcode = '42501';
  end if;

  -- Webhook messages are sent as their creator, who may delete them.
  is_own := coalesce(target.sender_id = current_user_id, false);

  if not is_own
    and not public.can_current_user_moderate_messages(target.conversation_id)
  then
    raise exception 'Message not found or cannot be deleted'
      using errcode = '42501';
  end if;

  if target.recalled_at is not null then
    return;
  end if;

  media_bucket := target.attachment->>'bucket';
  media_path := target.attachment->>'path';
  if media_bucket is null
    or media_bucket not in ('chat-images', 'voice-messages', 'chat-files')
    or media_path is null
  then
    media_bucket := null;
    media_path := null;
  end if;

  update public.messages m
  set
    recalled_at = now(),
    recalled_by = current_user_id,
    body = '',
    attachment = null,
    reply_preview = null,
    forwarded_from = null,
    mentions = '[]'::jsonb
  where m.id = target.id;

  delete from public.message_mentions mm where mm.message_id = target.id;
  delete from public.message_reactions r where r.message_id = target.id;
  delete from public.message_poll_votes v where v.message_id = target.id;
  delete from public.pinned_messages p where p.message_id = target.id;

  -- Replies stop quoting it.
  update public.messages m
  set reply_preview = m.reply_preview || jsonb_build_object('body', '')
  where m.reply_to_message_id = target.id
    and jsonb_typeof(m.reply_preview) = 'object';

  if media_path is not null then
    insert into public.recalled_message_media (
      bucket_id,
      object_path,
      message_id,
      deleted_by
    )
    values (media_bucket, media_path, target.id, current_user_id)
    on conflict on constraint recalled_message_media_pkey do update
    set
      message_id = excluded.message_id,
      deleted_by = excluded.deleted_by,
      created_at = now();

    -- A forwarded copy may still show it.
    if not exists (
      select 1
      from public.messages m
      where m.attachment->>'path' = media_path
        and m.attachment->>'bucket' = media_bucket
    ) then
      bucket_id := media_bucket;
      object_path := media_path;
      return next;
    end if;
  end if;

  if is_own then
    return;
  end if;

  select cc.*
  into channel
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(target.conversation_id);

  if channel.id is not null then
    perform public.write_circle_audit(
      channel.circle_id,
      'message_delete',
      'message',
      target.id,
      coalesce(
        target.webhook_name,
        public.circle_member_label(channel.circle_id, target.sender_id)
      ),
      jsonb_strip_nulls(jsonb_build_object(
        'channel_id', channel.id,
        'channel_name', channel.name,
        'author_id', case when target.webhook_name is null then target.sender_id end,
        'webhook_id', target.webhook_id
      ))
    );
  end if;
end;
$$;

-- Same as 202610140004_bans_and_timeouts, plus chat-files.
create or replace function public.ban_circle_member(
  target_circle_id uuid,
  target_user_id uuid,
  ban_reason text default null,
  delete_message_hours integer default 0
)
returns table (bucket_id text, object_path text)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_reason text := nullif(btrim(coalesce(ban_reason, '')), '');
  is_member boolean;
  banned_label text;
  deleted_count integer := 0;
  target public.messages%rowtype;
  media_bucket text;
  media_path text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'ban_members'
  ) then
    raise exception 'Only members who can ban members can ban members'
      using errcode = '42501';
  end if;

  if trimmed_reason is not null and char_length(trimmed_reason) > 512 then
    raise exception 'Ban reason is too long' using errcode = '22023';
  end if;

  if coalesce(delete_message_hours, 0) not between 0 and 168 then
    raise exception 'Messages can be deleted from up to 7 days back'
      using errcode = '22023';
  end if;

  -- Serialises with role changes, so the rank check below holds.
  perform 1 from public.circles where id = target_circle_id for no key update;

  if target_user_id = current_user_id then
    raise exception 'You cannot ban yourself' using errcode = '22023';
  end if;

  if not exists (select 1 from public.profiles p where p.id = target_user_id) then
    raise exception 'User not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from public.circles c
    where c.id = target_circle_id
      and c.owner_id = target_user_id
  ) then
    raise exception 'The circle owner cannot be banned' using errcode = '42501';
  end if;

  is_member := exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = target_circle_id
      and cm.user_id = target_user_id
  );

  if is_member
    and public.circle_member_rank(target_circle_id, target_user_id)
      >= public.circle_member_rank(target_circle_id, current_user_id)
  then
    raise exception 'Cannot ban a member ranked at or above you'
      using errcode = '42501';
  end if;

  banned_label := public.circle_member_label(target_circle_id, target_user_id);

  insert into public.circle_bans (circle_id, user_id, reason, banned_by)
  values (target_circle_id, target_user_id, trimmed_reason, current_user_id)
  on conflict (circle_id, user_id) do update
  set
    reason = excluded.reason,
    banned_by = excluded.banned_by,
    created_at = now();

  if is_member then
    perform public.remove_circle_member_rows(target_circle_id, target_user_id);
  end if;

  if coalesce(delete_message_hours, 0) > 0 then
    for target in
      select m.*
      from public.messages m
      where m.sender_id = target_user_id
        and m.webhook_id is null
        and m.recalled_at is null
        and m.type <> 'system'
        and m.created_at >= now() - make_interval(hours => delete_message_hours)
        and m.conversation_id in (
          select cc.conversation_id
          from public.circle_channels cc
          where cc.circle_id = target_circle_id
          union all
          select ct.conversation_id
          from public.conversation_threads ct
          join public.circle_channels cc
            on cc.conversation_id = ct.parent_conversation_id
          where cc.circle_id = target_circle_id
        )
      for update of m
    loop
      deleted_count := deleted_count + 1;
      media_bucket := target.attachment->>'bucket';
      media_path := target.attachment->>'path';
      if media_bucket is null
        or media_bucket not in ('chat-images', 'voice-messages', 'chat-files')
        or media_path is null
      then
        media_bucket := null;
        media_path := null;
      end if;

      update public.messages m
      set
        recalled_at = now(),
        recalled_by = current_user_id,
        body = '',
        attachment = null,
        reply_preview = null,
        forwarded_from = null,
        mentions = '[]'::jsonb
      where m.id = target.id;

      delete from public.message_mentions mm where mm.message_id = target.id;
      delete from public.message_reactions r where r.message_id = target.id;
      delete from public.message_poll_votes v where v.message_id = target.id;
      delete from public.pinned_messages p where p.message_id = target.id;

      update public.messages m
      set reply_preview = m.reply_preview || jsonb_build_object('body', '')
      where m.reply_to_message_id = target.id
        and jsonb_typeof(m.reply_preview) = 'object';

      if media_path is not null then
        insert into public.recalled_message_media (
          bucket_id,
          object_path,
          message_id,
          deleted_by
        )
        values (media_bucket, media_path, target.id, current_user_id)
        on conflict on constraint recalled_message_media_pkey do update
        set
          message_id = excluded.message_id,
          deleted_by = excluded.deleted_by,
          created_at = now();

        if not exists (
          select 1
          from public.messages m
          where m.attachment->>'path' = media_path
            and m.attachment->>'bucket' = media_bucket
        ) then
          bucket_id := media_bucket;
          object_path := media_path;
          return next;
        end if;
      end if;
    end loop;
  end if;

  perform public.write_circle_audit(
    target_circle_id,
    'member_ban',
    'member',
    target_user_id,
    banned_label,
    jsonb_strip_nulls(jsonb_build_object(
      'reason', trimmed_reason,
      'deleted_messages', nullif(deleted_count, 0)
    ))
  );
end;
$$;
