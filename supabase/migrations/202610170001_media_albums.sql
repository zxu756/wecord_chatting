-- Albums: several photos, videos and files sent together.
--
-- An album is not a new kind of message. Each picture, video or file stays
-- a message of its own (so reactions, replies, forwards, deleting, the
-- media page and search all keep working), and the messages of one send
-- share an attachment_group_id. Clients show consecutive messages of one
-- sender with the same group id as one grid.
--
-- * messages.attachment_group_id: set by the sender's app on the image and
--   file messages of one album, null otherwise (older clients, single
--   sends, forwards).
-- * An album holds at most 10 messages.
-- * Slowmode counts an album as one send: the first message is checked as
--   before, and the rest of the album (sent within two minutes of its
--   first message) passes. The 10 message limit bounds what this lets
--   through.
-- * The caption of an album is the body of its first message.

alter table public.messages
  add column if not exists attachment_group_id uuid;

alter table public.messages
  drop constraint if exists messages_attachment_group_type;

alter table public.messages
  add constraint messages_attachment_group_type
  check (attachment_group_id is null or type in ('image', 'file'));

create index if not exists messages_attachment_group_idx
  on public.messages (conversation_id, attachment_group_id)
  where attachment_group_id is not null;

-- Same as 202610160005_voice_text_chat, plus the album limit and the album
-- rule in slowmode.
create or replace function public.check_channel_message_send()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
  last_sent_at timestamptz;
  remaining_seconds integer;
  album_size integer;
  album_started_at timestamptz;
begin
  if new.type = 'system' then
    return new;
  end if;

  if not public.user_has_conversation_channel_permission(
    new.conversation_id,
    new.sender_id,
    'send_messages'
  ) then
    raise exception 'You do not have permission to send messages in this channel'
      using errcode = '42501';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.conversation_id = new.conversation_id;

  -- A forum channel's own conversation takes no messages: they go into
  -- its posts (threads).
  if channel.kind = 'forum' then
    raise exception 'Messages in a forum channel go into its posts'
      using errcode = '42501';
  end if;

  if new.attachment_group_id is not null then
    select count(*), min(m.created_at)
    into album_size, album_started_at
    from public.messages m
    where m.conversation_id = new.conversation_id
      and m.sender_id = new.sender_id
      and m.attachment_group_id = new.attachment_group_id;

    if album_size >= 10 then
      raise exception 'An album can hold up to 10 items'
        using errcode = '22023';
    end if;

    -- The rest of an album sent a moment ago: slowmode already let its
    -- first message through.
    if album_size > 0 and album_started_at > now() - interval '2 minutes' then
      return new;
    end if;
  end if;

  -- Webhook messages skip slowmode (they have their own rate limit).
  if channel.id is null
    or new.webhook_name is not null
    or channel.slowmode_seconds <= 0
    or public.circle_channel_has_permission(
      channel.id,
      new.sender_id,
      'manage_messages'
    )
  then
    return new;
  end if;

  -- One send per member and channel at a time, so two quick sends cannot
  -- both pass.
  perform pg_advisory_xact_lock(
    hashtextextended(new.conversation_id::text || ':' || new.sender_id::text, 0)
  );

  select max(m.created_at) into last_sent_at
  from public.messages m
  where m.conversation_id = new.conversation_id
    and m.sender_id = new.sender_id
    and m.type <> 'system'
    and m.webhook_name is null;

  if last_sent_at is not null
    and last_sent_at + make_interval(secs => channel.slowmode_seconds) > now()
  then
    remaining_seconds := greatest(
      1,
      ceil(
        extract(
          epoch from
            last_sent_at + make_interval(secs => channel.slowmode_seconds) - now()
        )
      )::integer
    );
    raise exception 'Slowmode is enabled. Try again in % seconds.', remaining_seconds
      using errcode = 'P0001',
        detail = format('slowmode_remaining_seconds=%s', remaining_seconds);
  end if;

  return new;
end;
$$;

revoke execute on function public.check_channel_message_send() from public;
revoke execute on function public.check_channel_message_send() from anon;
revoke execute on function public.check_channel_message_send() from authenticated;
