-- Merged forward ("Chat history"): up to 100 messages of one chat sent as ONE
-- message to a direct chat or group.
--
-- * forward_messages_merged(message ids, target conversation, title) checks
--   every selected message with the rules of forward_message (the latest,
--   202610170091_ai_guard_hidden.sql: not deleted, not a system line, poll or
--   sticker, not waiting for AI-guard review) plus the rules of reading:
--   the caller is a member of the chat and may read it (the messages select
--   policy: readable conversation, not expired) and view-once photos and
--   videos are refused. One refused message refuses the whole forward, so
--   nothing is dropped silently.
-- * The content is copied (snapshot) so the recipients can read it although
--   they are not in the source chat: each message's text, its sender's name
--   (the circle nickname in a channel, the webhook's name for a webhook),
--   avatar, time and attachment metadata go into message_bundles.items. The
--   chat message itself is an ordinary 'text' message whose attachment is the
--   card ({kind: 'chat_history', title, count, preview}); it stays small, the
--   items are read on demand. Nested merged forwards are kept one level deep:
--   a forwarded chat history inside the selection brings its own items; what
--   it held itself is left as a "Chat history" line.
-- * Files are not copied (Storage objects cannot be copied from SQL).
--   They are re-referenced the way forward_message does it, through
--   message_bundle_files: members of the chat the bundle was sent to can read
--   those objects (the three chat buckets' select policies are extended), for as
--   long as that message exists. Deleting a file that a live bundle still uses
--   is refused (can_current_user_delete_recalled_media), expiry skips it
--   (claim_expired_media), and when the last bundle using a file goes, a file
--   whose original was deleted meanwhile is queued for removal.
-- * Targets are direct chats and groups only: AutoMod and the AI guard see a
--   message's text, and a bundle's content would pass them unseen in a circle
--   channel.
-- * Deleting the chat-history message deletes its items.

create table if not exists public.message_bundles (
  message_id uuid primary key references public.messages(id) on delete cascade,
  title text not null,
  item_count integer not null check (item_count between 1 and 100),
  items jsonb not null,
  created_at timestamptz not null default now()
);

create table if not exists public.message_bundle_files (
  message_id uuid not null references public.messages(id) on delete cascade,
  bucket_id text not null,
  object_path text not null,
  primary key (message_id, bucket_id, object_path)
);

create index if not exists message_bundle_files_object_idx
  on public.message_bundle_files (bucket_id, object_path);

alter table public.message_bundles enable row level security;
alter table public.message_bundle_files enable row level security;

revoke all on public.message_bundles from anon, authenticated;
revoke all on public.message_bundle_files from anon, authenticated;
grant select on public.message_bundles to authenticated;

-- Whoever can read the chat-history message reads its items (the subquery
-- runs with the messages select policy of the caller). Nobody writes here
-- directly.
drop policy if exists message_bundles_select on public.message_bundles;
create policy message_bundles_select
  on public.message_bundles for select
  to authenticated
  using (
    exists (
      select 1
      from public.messages m
      where m.id = message_bundles.message_id
    )
  );

-- Whether the caller may read the Storage object because a chat-history
-- message in one of their chats bundles it.
create or replace function public.can_current_user_read_bundled_object(
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
    and exists (
      select 1
      from public.message_bundle_files f
      join public.messages m on m.id = f.message_id
      where f.bucket_id = target_bucket_id
        and f.object_path = target_object_path
        and m.recalled_at is null
        and (m.expires_at is null or m.expires_at > now())
        and public.is_current_user_conversation_member(m.conversation_id)
    );
$$;

revoke execute on function public.can_current_user_read_bundled_object(text, text)
  from public, anon;
grant execute on function public.can_current_user_read_bundled_object(text, text)
  to authenticated;

-- Same as 202605180011_daily_chat_polish_v3_security_fix, plus bundled files.
drop policy if exists chat_images_select_member on storage.objects;
create policy chat_images_select_member
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'chat-images'
    and (
      public.is_current_user_conversation_member(
        ((storage.foldername(name))[1])::uuid
      )
      or exists (
        select 1
        from public.messages m
        where m.forwarded_from->>'source_attachment_path' = name
          and m.forwarded_from->>'source_attachment_bucket' = bucket_id
          and m.recalled_at is null
          and public.is_current_user_conversation_member(m.conversation_id)
      )
      or public.can_current_user_read_bundled_object(bucket_id, name)
    )
  );

drop policy if exists voice_messages_select_member on storage.objects;
create policy voice_messages_select_member
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'voice-messages'
    and (
      public.is_current_user_conversation_member(
        split_part(name, '/', 1)::uuid
      )
      or exists (
        select 1
        from public.messages m
        where m.forwarded_from->>'source_attachment_path' = name
          and m.forwarded_from->>'source_attachment_bucket' = bucket_id
          and m.recalled_at is null
          and public.is_current_user_conversation_member(m.conversation_id)
      )
      or public.can_current_user_read_bundled_object(bucket_id, name)
    )
  );

-- Same as 202610140007_file_messages, plus bundled files.
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
      or public.can_current_user_read_bundled_object(bucket_id, name)
    )
  );

-- Same as 202610140007_file_messages, but a file a chat-history message
-- still shows is not deleted.
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
    )
    and not exists (
      select 1
      from public.message_bundle_files f
      where f.bucket_id = target_bucket_id
        and f.object_path = target_object_path
    );
$$;

revoke execute on function public.can_current_user_delete_recalled_media(text, text)
  from public, anon;

-- Same as 202610170020_disappearing_messages, but entries a chat-history
-- message uses are dropped too.
create or replace function public.claim_expired_media(max_rows integer default 200)
returns table (bucket_id text, object_path text)
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.recalled_message_media r
  where r.expired
    and (
      exists (
        select 1
        from public.messages m
        where m.attachment->>'path' = r.object_path
          and m.attachment->>'bucket' = r.bucket_id
      )
      or exists (
        select 1
        from public.message_bundle_files f
        where f.object_path = r.object_path
          and f.bucket_id = r.bucket_id
      )
    );

  return query
  select r.bucket_id, r.object_path
  from public.recalled_message_media r
  where r.expired
  order by r.created_at
  limit greatest(1, least(coalesce(max_rows, 200), 1000));
end;
$$;

revoke execute on function public.claim_expired_media(integer) from public, anon, authenticated;
grant execute on function public.claim_expired_media(integer) to service_role;

-- A message that is deleted takes its items with it (the foreign keys do the
-- same when the row itself goes).
create or replace function public.release_message_bundle()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.message_bundle_files where message_id = new.id;
  delete from public.message_bundles where message_id = new.id;
  return null;
end;
$$;

drop trigger if exists messages_release_bundle on public.messages;
create trigger messages_release_bundle
  after update of recalled_at on public.messages
  for each row
  when (old.recalled_at is null and new.recalled_at is not null)
  execute function public.release_message_bundle();

-- The last chat-history message that used a file is gone. If the file's
-- own message was deleted meanwhile (which kept the file alive for the
-- bundle), the file is queued for removal now; the expire-messages Edge
-- Function removes queued files nothing uses.
create or replace function public.release_bundle_file()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
      select 1
      from public.messages m
      where m.attachment->>'path' = old.object_path
        and m.attachment->>'bucket' = old.bucket_id
    )
    and not exists (
      select 1
      from public.message_bundle_files f
      where f.bucket_id = old.bucket_id
        and f.object_path = old.object_path
    )
  then
    update public.recalled_message_media r
    set expired = true,
      created_at = now()
    where r.bucket_id = old.bucket_id
      and r.object_path = old.object_path;
  end if;
  return null;
end;
$$;

drop trigger if exists message_bundle_files_release on public.message_bundle_files;
create trigger message_bundle_files_release
  after delete on public.message_bundle_files
  for each row execute function public.release_bundle_file();

-- Only these keys of an attachment are copied; view_once and anything else
-- is left behind.
create or replace function public.merged_forward_attachment(att jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select case
    when att is null
      or jsonb_typeof(att) <> 'object'
      or att->>'bucket' is null
      or att->>'path' is null
      or att->>'bucket' not in ('chat-images', 'voice-messages', 'chat-files')
    then null
    else (
      select jsonb_object_agg(e.key, e.value)
      from jsonb_each(att) e
      where e.key in (
        'kind', 'bucket', 'path', 'name', 'mime_type', 'size',
        'width', 'height', 'blurhash', 'duration_ms'
      )
    )
  end;
$$;

-- One message as an item of a bundle. Reads as the owner: callers have
-- already checked that the forwarder may read the message.
create or replace function public.merged_forward_item(
  src public.messages,
  with_nested boolean
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  sender_name text;
  sender_avatar text;
  item_attachment jsonb;
  nested jsonb;
  source_bundle public.message_bundles%rowtype;
begin
  if src.webhook_name is not null then
    sender_name := src.webhook_name;
    sender_avatar := src.webhook_avatar_url;
  else
    select
      coalesce(nullif(btrim(public.sender_nickname(src)), ''), p.display_name),
      coalesce(nullif(btrim(public.sender_circle_avatar(src)), ''), p.avatar_url)
    into sender_name, sender_avatar
    from public.profiles p
    where p.id = src.sender_id;
  end if;

  if src.type in ('image', 'file', 'voice') then
    item_attachment := public.merged_forward_attachment(src.attachment);
  elsif src.type = 'text' and src.attachment->>'kind' = 'contact_card' then
    item_attachment := src.attachment;
  elsif src.type = 'text' and src.attachment->>'kind' = 'chat_history' then
    item_attachment := jsonb_build_object(
      'kind', 'chat_history',
      'title', src.attachment->>'title',
      'count', src.attachment->'count'
    );
    if with_nested then
      select * into source_bundle
      from public.message_bundles b
      where b.message_id = src.id;
      if source_bundle.message_id is not null then
        nested := jsonb_build_object(
          'title', source_bundle.title,
          'count', source_bundle.item_count,
          -- What it held itself stays a line: one level only.
          'items', (
            select coalesce(jsonb_agg(i - 'nested'), '[]'::jsonb)
            from jsonb_array_elements(source_bundle.items) i
          )
        );
      end if;
    end if;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'message_id', src.id,
    'sender_id', src.sender_id,
    'sender_name', coalesce(sender_name, ''),
    'sender_avatar', sender_avatar,
    'created_at', src.created_at,
    'type', src.type,
    'body', src.body,
    'attachment', item_attachment,
    'nested', nested
  ));
end;
$$;

revoke execute on function public.merged_forward_attachment(jsonb) from public, anon, authenticated;
revoke execute on function public.merged_forward_item(public.messages, boolean)
  from public, anon, authenticated;

-- Sends the messages as one chat-history message and returns its id (null
-- when AutoMod dropped it, like forward_message).
create or replace function public.forward_messages_merged(
  source_message_ids uuid[],
  target_conversation_id uuid,
  conversation_title text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  ids uuid[];
  found_count integer;
  source_conversation_id uuid;
  refused_count integer;
  target_type text;
  title_text text;
  all_items jsonb;
  preview jsonb;
  created_message_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct x), array[]::uuid[])
  into ids
  from unnest(source_message_ids) as x
  where x is not null;

  if cardinality(ids) < 1 or cardinality(ids) > 100 then
    raise exception 'Choose between 1 and 100 messages' using errcode = '22023';
  end if;

  select count(*), min(m.conversation_id::text)::uuid
  into found_count, source_conversation_id
  from public.messages m
  where m.id = any (ids);

  if found_count <> cardinality(ids)
    or exists (
      select 1
      from public.messages m
      where m.id = any (ids)
        and m.conversation_id <> source_conversation_id
    )
  then
    raise exception 'Messages cannot be forwarded' using errcode = '42501';
  end if;

  -- The forwarder reads them: a member who may read the chat.
  if not public.is_current_user_conversation_member(source_conversation_id)
    or source_conversation_id not in (
      select public.current_user_readable_conversation_ids()
    )
  then
    raise exception 'Messages cannot be forwarded' using errcode = '42501';
  end if;

  -- What forward_message refuses, and what a reader cannot see.
  select count(*)
  into refused_count
  from public.messages m
  where m.id = any (ids)
    and (
      m.recalled_at is not null
      or m.type in ('system', 'poll', 'sticker')
      or m.review_state is not null
      or (m.expires_at is not null and m.expires_at <= now())
      or coalesce(m.attachment->>'view_once', 'false') = 'true'
    );
  if refused_count > 0 then
    raise exception 'Some messages cannot be forwarded' using errcode = '42501';
  end if;

  select c.type
  into target_type
  from public.conversations c
  where c.id = target_conversation_id;

  if target_type is null
    or not public.is_current_user_conversation_member(target_conversation_id)
    or public.is_current_user_blocked_in_conversation(target_conversation_id)
    or not public.can_current_user_send_in_conversation(target_conversation_id)
  then
    raise exception 'Messages cannot be forwarded' using errcode = '42501';
  end if;

  if target_type not in ('direct', 'group') then
    raise exception 'Chat history can be sent to direct chats and groups'
      using errcode = '42501';
  end if;

  title_text := left(
    coalesce(nullif(btrim(coalesce(conversation_title, '')), ''), 'Chat'),
    80
  );

  select jsonb_agg(
    public.merged_forward_item(m, true) order by m.created_at, m.id
  )
  into all_items
  from public.messages m
  where m.id = any (ids);

  select coalesce(jsonb_agg(line), '[]'::jsonb)
  into preview
  from (
    select jsonb_build_object(
      'name', coalesce(i->>'sender_name', ''),
      'kind', case
        when i->>'type' = 'image' then 'image'
        when i->>'type' = 'voice' then 'voice'
        when i->>'type' = 'file' and i->'attachment'->>'kind' = 'video' then 'video'
        when i->>'type' = 'file' then 'file'
        when i->'attachment'->>'kind' = 'chat_history' then 'history'
        when i->'attachment'->>'kind' = 'contact_card' then 'contact'
        else 'text'
      end,
      'text', left(
        regexp_replace(
          case
            when i->>'type' = 'file' then coalesce(i->'attachment'->>'name', '')
            else coalesce(i->>'body', '')
          end,
          '\s+', ' ', 'g'
        ),
        80
      )
    ) as line
    from jsonb_array_elements(all_items) with ordinality as t(i, n)
    where n <= 4
    order by n
  ) lines;

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
    'text',
    'Chat history: ' || title_text,
    jsonb_build_object(
      'kind', 'chat_history',
      'title', title_text,
      'count', cardinality(ids),
      'preview', preview
    )
  )
  returning id into created_message_id;

  perform set_config('wecord.automod_soft', 'off', true);

  if created_message_id is null then
    return null;
  end if;

  insert into public.message_bundles (message_id, title, item_count, items)
  values (created_message_id, title_text, cardinality(ids), all_items);

  insert into public.message_bundle_files (message_id, bucket_id, object_path)
  select distinct created_message_id, f.bucket_id, f.object_path
  from (
    select
      i->'attachment'->>'bucket' as bucket_id,
      i->'attachment'->>'path' as object_path
    from jsonb_array_elements(all_items) i
    union all
    select
      n->'attachment'->>'bucket',
      n->'attachment'->>'path'
    from jsonb_array_elements(all_items) i,
      jsonb_array_elements(coalesce(i->'nested'->'items', '[]'::jsonb)) n
  ) f
  where f.bucket_id in ('chat-images', 'voice-messages', 'chat-files')
    and f.object_path is not null;

  return created_message_id;
end;
$$;

revoke execute on function public.forward_messages_merged(uuid[], uuid, text)
  from public, anon;
grant execute on function public.forward_messages_merged(uuid[], uuid, text)
  to authenticated;
