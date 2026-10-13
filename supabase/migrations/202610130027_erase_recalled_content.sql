-- Deleted messages keep no content.
--
-- Until now recall_message only stamped recalled_at, so a deleted message's
-- body, attachment, mentions, reply snapshot and forward snapshot stayed
-- readable through the API (clients merely hid them). Now:
--
-- * recall_message wipes the row: body = '', attachment, reply_preview and
--   forwarded_from = null, mentions = []. Its message_mentions, reactions,
--   poll votes and pin are deleted, and replies to it lose the quoted text
--   (their reply_preview body becomes '', which clients show as "Message
--   deleted"). Who sent it, when and who deleted it stay, so the
--   "Message deleted" placeholder, reply links and threads keep working.
-- * Storage objects cannot be deleted from SQL, so recall_message returns
--   the message's image / voice object (bucket_id, object_path) when no
--   other live message (e.g. a forwarded copy) still uses it, and the
--   client removes it through the Storage API, best effort. The object is
--   remembered in recalled_message_media, and the storage delete policy
--   message_media_delete_recalled lets whoever deleted the message remove
--   it while nothing references it.
-- * Text messages may have an empty body once deleted.
-- * Messages deleted before this migration are wiped the same way (their
--   objects are remembered, but nobody deletes them automatically).

alter table public.messages
  drop constraint if exists message_body_not_empty;

alter table public.messages
  add constraint message_body_not_empty check (
    type <> 'text'
    or recalled_at is not null
    or char_length(trim(body)) > 0
  );

-- Finds live messages using an object.
create index if not exists messages_attachment_path_idx
  on public.messages ((attachment->>'path'))
  where attachment->>'path' is not null;

create table if not exists public.recalled_message_media (
  bucket_id text not null,
  object_path text not null,
  message_id uuid references public.messages(id) on delete set null,
  deleted_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (bucket_id, object_path)
);

-- Server-side bookkeeping only: no client reads or writes it.
alter table public.recalled_message_media enable row level security;
revoke all on public.recalled_message_media from anon, authenticated;

-- Whether the caller may remove a chat image / voice object: they deleted
-- the message that used it and no message uses it any more.
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
    and coalesce(target_bucket_id in ('chat-images', 'voice-messages'), false)
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

drop policy if exists message_media_delete_recalled on storage.objects;
create policy message_media_delete_recalled
  on storage.objects for delete
  to authenticated
  using (
    bucket_id in ('chat-images', 'voice-messages')
    and public.can_current_user_delete_recalled_media(bucket_id, name)
  );

-- Same as 202610130025_moderator_message_delete, but the message's content
-- is erased and its unused image / voice object is returned for the client
-- to remove from Storage.
drop function if exists public.recall_message(uuid);

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
    or media_bucket not in ('chat-images', 'voice-messages')
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

-- Wipe messages deleted before this migration.
insert into public.recalled_message_media (
  bucket_id,
  object_path,
  message_id,
  deleted_by
)
select
  m.attachment->>'bucket',
  m.attachment->>'path',
  m.id,
  coalesce(m.recalled_by, m.sender_id)
from public.messages m
where m.recalled_at is not null
  and m.attachment->>'bucket' in ('chat-images', 'voice-messages')
  and m.attachment->>'path' is not null
on conflict on constraint recalled_message_media_pkey do nothing;

update public.messages m
set reply_preview = m.reply_preview || jsonb_build_object('body', '')
where jsonb_typeof(m.reply_preview) = 'object'
  and m.reply_preview->>'body' is distinct from ''
  and exists (
    select 1
    from public.messages parent
    where parent.id = m.reply_to_message_id
      and parent.recalled_at is not null
  );

update public.messages m
set
  body = '',
  attachment = null,
  reply_preview = null,
  forwarded_from = null,
  mentions = '[]'::jsonb
where m.recalled_at is not null
  and (
    m.body <> ''
    or m.attachment is not null
    or m.reply_preview is not null
    or m.forwarded_from is not null
    or m.mentions <> '[]'::jsonb
  );

delete from public.message_mentions mm
using public.messages m
where m.id = mm.message_id
  and m.recalled_at is not null;

delete from public.message_reactions r
using public.messages m
where m.id = r.message_id
  and m.recalled_at is not null;

delete from public.message_poll_votes v
using public.messages m
where m.id = v.message_id
  and m.recalled_at is not null;

delete from public.pinned_messages p
using public.messages m
where m.id = p.message_id
  and m.recalled_at is not null;

revoke execute on function public.can_current_user_delete_recalled_media(text, text) from public;
revoke execute on function public.can_current_user_delete_recalled_media(text, text) from anon;
revoke execute on function public.recall_message(uuid) from public;
revoke execute on function public.recall_message(uuid) from anon;

grant execute on function public.can_current_user_delete_recalled_media(text, text) to authenticated;
grant execute on function public.recall_message(uuid) to authenticated;
