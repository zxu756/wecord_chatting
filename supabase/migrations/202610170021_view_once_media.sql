-- View-once photos and videos in direct chats and groups.
--
-- * A photo (type 'image') or video (type 'file', kind 'video') sent with
--   attachment.view_once = true can be opened once by each person who did
--   not send it. The trigger messages_check_view_once refuses the flag on
--   anything else, in channels, and in albums; a view-once message has no
--   caption, and it cannot be forwarded.
-- * message_view_once_opens records who opened what. The sender sees every
--   open of their messages (to show "Opened" / "Not opened"), everyone else
--   only their own.
-- * open_view_once(message) is the only way in: it records the open and
--   returns where the file is, once per person; asking again fails with
--   'view_once_already_opened'. The file's Storage policy then lets that
--   person (and the sender) read it; for everyone else a restrictive policy
--   on chat-images and chat-files keeps it closed, so a client that skips
--   the RPC gets nothing. The opener can sign a short-lived URL for two
--   minutes after opening; the app signs one for a minute.
-- * Screenshots and screen recordings cannot be prevented, and the app says
--   so.
-- * The shared media list skips view-once media (and, like reads, expired
--   messages).

create table if not exists public.message_view_once_opens (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  opened_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

alter table public.message_view_once_opens enable row level security;
revoke all on public.message_view_once_opens from anon, authenticated;
grant select on public.message_view_once_opens to authenticated;

drop policy if exists message_view_once_opens_select on public.message_view_once_opens;
create policy message_view_once_opens_select
  on public.message_view_once_opens for select
  to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.messages m
      where m.id = message_view_once_opens.message_id
        and m.sender_id = auth.uid()
    )
  );

-- Realtime matches DELETE events against the old row.
alter table public.message_view_once_opens replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message_view_once_opens'
  ) then
    alter publication supabase_realtime add table public.message_view_once_opens;
  end if;
end $$;

-- Finds view-once media by file (for the Storage policy) without scanning.
create index if not exists messages_view_once_path_idx
  on public.messages ((attachment->>'path'))
  where attachment->>'view_once' = 'true';

create or replace function public.messages_check_view_once()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  conversation_kind text;
begin
  -- A forwarded copy of view-once media would open as often as anyone liked.
  if new.forwarded_from is not null
    and new.forwarded_from->>'source_attachment_path' is not null
    and exists (
      select 1
      from public.messages source
      where source.attachment->>'view_once' = 'true'
        and source.attachment->>'path' = new.forwarded_from->>'source_attachment_path'
        and source.attachment->>'bucket' = new.forwarded_from->>'source_attachment_bucket'
    )
  then
    raise exception 'View-once photos and videos cannot be forwarded'
      using errcode = '42501';
  end if;

  if new.attachment is null or new.attachment->>'view_once' is distinct from 'true' then
    return new;
  end if;

  select c.type
  into conversation_kind
  from public.conversations c
  where c.id = new.conversation_id;

  if new.type not in ('image', 'file')
    or (new.type = 'file' and new.attachment->>'kind' is distinct from 'video')
    or conversation_kind not in ('direct', 'group')
    or new.attachment_group_id is not null
    or new.forwarded_from is not null
  then
    raise exception 'View once is for single photos and videos in direct chats and groups'
      using errcode = '22023';
  end if;

  new.body := '';
  return new;
end;
$$;

drop trigger if exists messages_check_view_once on public.messages;
create trigger messages_check_view_once
  before insert on public.messages
  for each row execute function public.messages_check_view_once();

-- Opens a view-once photo or video, once. Returns the file to sign.
create or replace function public.open_view_once(target_message_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target public.messages%rowtype;
  inserted integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select m.*
  into target
  from public.messages m
  where m.id = target_message_id
    and m.attachment->>'view_once' = 'true';

  if target.id is null
    or not public.is_current_user_conversation_member(target.conversation_id)
    or target.recalled_at is not null
    or (target.expires_at is not null and target.expires_at <= now())
  then
    raise exception 'view_once_unavailable' using errcode = '42501';
  end if;

  if target.sender_id = current_user_id then
    raise exception 'view_once_own_message' using errcode = '42501';
  end if;

  if public.is_current_user_blocked_in_conversation(target.conversation_id) then
    raise exception 'view_once_unavailable' using errcode = '42501';
  end if;

  insert into public.message_view_once_opens (message_id, user_id, conversation_id)
  values (target.id, current_user_id, target.conversation_id)
  on conflict do nothing;
  get diagnostics inserted = row_count;

  if inserted = 0 then
    raise exception 'view_once_already_opened' using errcode = '55000';
  end if;

  return jsonb_build_object(
    'bucket', target.attachment->>'bucket',
    'path', target.attachment->>'path',
    'kind', target.attachment->>'kind',
    'mime_type', target.attachment->>'mime_type',
    'opened_at', now()
  );
end;
$$;

revoke execute on function public.open_view_once(uuid) from public, anon;
grant execute on function public.open_view_once(uuid) to authenticated;

-- Whether the caller may read a chat file: not while it is view-once media
-- they did not send and have not just opened.
create or replace function public.can_current_user_read_chat_object(
  object_bucket text,
  object_path text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1
    from public.messages m
    where m.attachment->>'view_once' = 'true'
      and m.attachment->>'path' = object_path
      and m.attachment->>'bucket' = object_bucket
      and m.sender_id is distinct from auth.uid()
      and not exists (
        select 1
        from public.message_view_once_opens o
        where o.message_id = m.id
          and o.user_id = auth.uid()
          and o.opened_at > now() - interval '2 minutes'
      )
  );
$$;

revoke execute on function public.can_current_user_read_chat_object(text, text) from public, anon;
grant execute on function public.can_current_user_read_chat_object(text, text) to authenticated;

-- Restrictive: every other policy still has to pass as before.
drop policy if exists view_once_media_restrict on storage.objects;
create policy view_once_media_restrict
  on storage.objects as restrictive for select
  to authenticated
  using (
    bucket_id not in ('chat-images', 'chat-files')
    or public.can_current_user_read_chat_object(bucket_id, name)
  );

-- Same as 202605190003_community_discovery_v1, but view-once media and
-- expired messages stay out of the shared media list.
create or replace function public.list_conversation_media(
  target_conversation_id uuid
)
returns table (
  message_id uuid,
  conversation_id uuid,
  sender_id uuid,
  sender_name text,
  type text,
  body text,
  attachment jsonb,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    m.id as message_id,
    m.conversation_id,
    m.sender_id,
    p.display_name as sender_name,
    m.type,
    m.body,
    m.attachment,
    m.created_at
  from public.messages m
  join public.profiles p on p.id = m.sender_id
  where m.conversation_id = target_conversation_id
    and public.is_current_user_conversation_member(target_conversation_id)
    and m.type in ('image', 'voice', 'file')
    and m.recalled_at is null
    and (m.expires_at is null or m.expires_at > now())
    and coalesce(m.attachment->>'view_once', 'false') <> 'true'
  order by m.created_at desc;
$$;
