-- Announcement channels that other circles can follow, like Discord's.
--
-- * circle_channels.kind gains 'announcement': a text channel whose
--   messages can be published to the channels that follow it. It behaves
--   like a text channel otherwise (messages, threads, pins, slowmode).
--   The kind check keeps 'stage' from the stage channels migration
--   (202610160018).
--   Webhooks still post only into plain text channels.
-- * set_channel_announcement(channel_id, enabled) turns a text channel
--   into an announcement channel and back (manage_channels in it).
--   Turning it back removes every follow of it. create_circle_channel is
--   left alone: clients create a text channel and convert it.
-- * channel_follows: a target channel (text or announcement) receives the
--   published messages of a source announcement channel. Clients cannot
--   read the table; the RPCs below return what they need.
-- * follow_announcement_channel(source, target): the caller must see the
--   source channel (so be a member of its circle: there are no public
--   circles to follow from outside, which is also the safer rule) and
--   have manage_webhooks in the target channel, as for creating a webhook
--   there. At most 10 follows per target channel; following twice is a
--   no-op. Audited in the target circle as channel_follow_create.
-- * unfollow_announcement_channel(follow_id): manage_webhooks in the
--   target channel; audited as channel_follow_delete.
-- * list_channel_follows(target): the follows into a channel, for its
--   settings (manage_webhooks there). list_follow_targets(source): the
--   text and announcement channels of the caller's circles where they have
--   manage_webhooks, marking those that already follow the source.
-- * publish_message(message_id): publishes a text message of an
--   announcement channel (not of its threads) once. The author (with
--   send_messages) or anyone with manage_messages in the channel may
--   publish; at most 10 publishes per channel and hour (errcode PB429).
--   Every follow gets a copy: an ordinary text message in the target sent
--   as the member who set the follow up, shown under the name
--   "<circle> #<channel>" (webhook_name, so it skips slowmode, counts as
--   unread for that member too and cannot be edited) with the source
--   circle's avatar, and `crosspost` = {source_message_id,
--   source_conversation_id, source_channel_id, source_circle_id,
--   circle_name, channel_name, author_id, author_name}. Follows whose
--   member left or can no longer send there and manage webhooks are
--   skipped, and so are copies the target refuses. Returns how many
--   channels got the message.
-- * messages.published_at marks published messages. Editing a published
--   message edits its copies; deleting it deletes them.
-- * Clients cannot set crosspost or published_at themselves
--   (messages_guard_server_fields, a trigger, so the insert policy stays
--   as it is).

alter table public.circle_channels
  drop constraint if exists circle_channels_kind_check;

alter table public.circle_channels
  add constraint circle_channels_kind_check
  check (kind in ('text', 'voice', 'forum', 'stage', 'announcement'));

alter table public.messages
  add column if not exists crosspost jsonb,
  add column if not exists published_at timestamptz;

alter table public.messages
  drop constraint if exists messages_crosspost_object;
alter table public.messages
  add constraint messages_crosspost_object check (
    crosspost is null or jsonb_typeof(crosspost) = 'object'
  );

create index if not exists messages_crosspost_source_idx
  on public.messages ((crosspost->>'source_message_id'))
  where crosspost is not null;

-- Fields only server functions may set. Security invoker on purpose: rows
-- inserted by security definer functions arrive as their owner, rows
-- inserted through the API as authenticated / anon.
create or replace function public.messages_guard_server_fields()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon')
    and (new.crosspost is not null or new.published_at is not null)
  then
    raise exception 'These message fields are set by the server'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists messages_guard_server_fields on public.messages;
create trigger messages_guard_server_fields
  before insert on public.messages
  for each row execute function public.messages_guard_server_fields();

create table if not exists public.channel_follows (
  id uuid primary key default gen_random_uuid(),
  source_channel_id uuid not null
    references public.circle_channels(id) on delete cascade,
  source_circle_id uuid not null references public.circles(id) on delete cascade,
  target_channel_id uuid not null
    references public.circle_channels(id) on delete cascade,
  target_circle_id uuid not null references public.circles(id) on delete cascade,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint channel_follows_unique unique (source_channel_id, target_channel_id),
  constraint channel_follows_not_self check (source_channel_id <> target_channel_id)
);

create index if not exists channel_follows_target_idx
  on public.channel_follows (target_channel_id, created_at);

alter table public.channel_follows enable row level security;

revoke all on public.channel_follows from anon;
revoke all on public.channel_follows from authenticated;

create or replace function public.set_channel_announcement(
  target_channel_id uuid,
  enabled boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
  new_kind text := case when coalesce(enabled, false) then 'announcement' else 'text' end;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id
  for update;

  if channel.id is null
    or not public.current_user_has_channel_permission(channel.id, 'manage_channels')
  then
    raise exception 'Channel not found or caller cannot manage it'
      using errcode = '42501';
  end if;

  if channel.kind not in ('text', 'announcement') then
    raise exception 'Only text channels can be announcement channels'
      using errcode = '22023';
  end if;

  if channel.kind = new_kind then
    return;
  end if;

  update public.circle_channels cc
  set kind = new_kind
  where cc.id = channel.id;

  if new_kind = 'text' then
    delete from public.channel_follows f
    where f.source_channel_id = channel.id;
  end if;

  perform public.write_circle_audit(
    channel.circle_id,
    'channel_update',
    'channel',
    channel.id,
    channel.name,
    jsonb_build_object(
      'kind',
      jsonb_build_object('old', channel.kind, 'new', new_kind)
    )
  );
end;
$$;

-- The payload of a follow for the target channel's settings.
create or replace function public.channel_follow_payload(
  follow public.channel_follows
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', follow.id,
    'source_channel_id', follow.source_channel_id,
    'source_channel_name', source_channel.name,
    'source_circle_id', follow.source_circle_id,
    'source_circle_name', source_circle.name,
    'source_circle_avatar_url', source_circle.avatar_url,
    'target_channel_id', follow.target_channel_id,
    'target_circle_id', follow.target_circle_id,
    'created_by', follow.created_by,
    'creator_name', case
      when follow.created_by is null then null
      else public.circle_member_label(follow.target_circle_id, follow.created_by)
    end,
    'created_at', follow.created_at
  )
  from public.circle_channels source_channel
  join public.circles source_circle on source_circle.id = source_channel.circle_id
  where source_channel.id = follow.source_channel_id;
$$;

revoke execute on function public.channel_follow_payload(public.channel_follows) from public;
revoke execute on function public.channel_follow_payload(public.channel_follows) from anon;
revoke execute on function public.channel_follow_payload(public.channel_follows) from authenticated;

create or replace function public.follow_announcement_channel(
  source_channel_id uuid,
  target_channel_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  source public.circle_channels%rowtype;
  target public.circle_channels%rowtype;
  existing public.channel_follows%rowtype;
  created public.channel_follows%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cc.* into source
  from public.circle_channels cc
  where cc.id = follow_announcement_channel.source_channel_id;

  if source.id is null
    or not public.current_user_has_channel_permission(source.id, 'view_channel')
  then
    raise exception 'Channel not found' using errcode = '42501';
  end if;

  if source.kind <> 'announcement' then
    raise exception 'Only announcement channels can be followed'
      using errcode = '22023';
  end if;

  select cc.* into target
  from public.circle_channels cc
  where cc.id = follow_announcement_channel.target_channel_id;

  if target.id is null
    or not public.current_user_has_channel_permission(target.id, 'manage_webhooks')
  then
    raise exception 'Channel not found or caller cannot manage its webhooks'
      using errcode = '42501';
  end if;

  if target.kind not in ('text', 'announcement') or target.id = source.id then
    raise exception 'Announcements can only go to another text channel'
      using errcode = '22023';
  end if;

  select f.* into existing
  from public.channel_follows f
  where f.source_channel_id = source.id
    and f.target_channel_id = target.id;

  if existing.id is not null then
    return public.channel_follow_payload(existing);
  end if;

  perform pg_advisory_xact_lock(hashtextextended('follows:' || target.id::text, 0));

  if (
    select count(*)
    from public.channel_follows f
    where f.target_channel_id = target.id
  ) >= 10 then
    raise exception 'A channel can follow at most 10 announcement channels'
      using errcode = '54000';
  end if;

  insert into public.channel_follows (
    source_channel_id,
    source_circle_id,
    target_channel_id,
    target_circle_id,
    created_by
  )
  values (source.id, source.circle_id, target.id, target.circle_id, auth.uid())
  returning * into created;

  perform public.write_circle_audit(
    target.circle_id,
    'channel_follow_create',
    'channel',
    target.id,
    target.name,
    jsonb_build_object(
      'source_channel_name', source.name,
      'source_circle_name', (select c.name from public.circles c where c.id = source.circle_id)
    )
  );

  return public.channel_follow_payload(created);
end;
$$;

create or replace function public.unfollow_announcement_channel(target_follow_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  follow public.channel_follows%rowtype;
  payload jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select f.* into follow
  from public.channel_follows f
  where f.id = target_follow_id;

  if follow.id is null
    or not public.current_user_has_channel_permission(
      follow.target_channel_id,
      'manage_webhooks'
    )
  then
    raise exception 'Follow not found or caller cannot manage it'
      using errcode = '42501';
  end if;

  payload := public.channel_follow_payload(follow);

  delete from public.channel_follows f where f.id = follow.id;

  perform public.write_circle_audit(
    follow.target_circle_id,
    'channel_follow_delete',
    'channel',
    follow.target_channel_id,
    (select cc.name from public.circle_channels cc where cc.id = follow.target_channel_id),
    jsonb_build_object(
      'source_channel_name', payload->>'source_channel_name',
      'source_circle_name', payload->>'source_circle_name'
    )
  );
end;
$$;

create or replace function public.list_channel_follows(target_channel_id uuid)
returns setof jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_channel_permission(
    target_channel_id,
    'manage_webhooks'
  ) then
    raise exception 'Channel not found or caller cannot manage its webhooks'
      using errcode = '42501';
  end if;

  return query
  select public.channel_follow_payload(f)
  from public.channel_follows f
  where f.target_channel_id = list_channel_follows.target_channel_id
  order by f.created_at, f.id;
end;
$$;

create or replace function public.list_follow_targets(source_channel_id uuid)
returns table (
  channel_id uuid,
  channel_name text,
  circle_id uuid,
  circle_name text,
  is_following boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    cc.id,
    cc.name,
    c.id,
    c.name,
    exists (
      select 1
      from public.channel_follows f
      where f.source_channel_id = list_follow_targets.source_channel_id
        and f.target_channel_id = cc.id
    )
  from public.circle_members cm
  join public.circles c on c.id = cm.circle_id
  join public.circle_channels cc on cc.circle_id = c.id
  where cm.user_id = auth.uid()
    and cc.kind in ('text', 'announcement')
    and cc.id <> list_follow_targets.source_channel_id
    and public.circle_channel_has_permission(cc.id, auth.uid(), 'manage_webhooks')
  order by c.name, c.id, cc.position, cc.created_at;
$$;

create or replace function public.publish_message(target_message_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  message public.messages%rowtype;
  channel public.circle_channels%rowtype;
  source_circle public.circles%rowtype;
  follow public.channel_follows%rowtype;
  target public.circle_channels%rowtype;
  author_name text;
  copy_name text;
  copy_avatar text;
  payload jsonb;
  delivered integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select m.* into message
  from public.messages m
  where m.id = target_message_id
  for update;

  select cc.* into channel
  from public.circle_channels cc
  where cc.conversation_id = message.conversation_id;

  if message.id is null
    or channel.id is null
    or not public.current_user_has_channel_permission(channel.id, 'view_channel')
  then
    raise exception 'Message not found' using errcode = '42501';
  end if;

  if not (
    public.current_user_has_channel_permission(channel.id, 'manage_messages')
    or (
      message.sender_id = auth.uid()
      and message.webhook_name is null
      and public.current_user_has_channel_permission(channel.id, 'send_messages')
    )
  ) then
    raise exception 'Only the author or members who manage messages can publish'
      using errcode = '42501';
  end if;

  if channel.kind <> 'announcement' then
    raise exception 'Only messages of announcement channels can be published'
      using errcode = '22023';
  end if;

  if message.type <> 'text'
    or message.recalled_at is not null
    or message.crosspost is not null
  then
    raise exception 'Only text messages can be published' using errcode = '22023';
  end if;

  if message.published_at is not null then
    raise exception 'This message was already published' using errcode = '23505';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('publish:' || channel.id::text, 0));

  if (
    select count(*)
    from public.messages m
    where m.conversation_id = channel.conversation_id
      and m.published_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception 'At most 10 messages per hour can be published from a channel'
      using errcode = 'PB429';
  end if;

  update public.messages m
  set published_at = now()
  where m.id = message.id;

  select c.* into source_circle
  from public.circles c
  where c.id = channel.circle_id;

  author_name := coalesce(
    message.webhook_name,
    public.circle_member_label(channel.circle_id, message.sender_id)
  );
  copy_name := left(source_circle.name, 78 - least(char_length(channel.name), 40))
    || ' #' || left(channel.name, 40);
  copy_avatar := source_circle.avatar_url;
  payload := jsonb_build_object(
    'source_message_id', message.id,
    'source_conversation_id', channel.conversation_id,
    'source_channel_id', channel.id,
    'source_circle_id', channel.circle_id,
    'circle_name', source_circle.name,
    'channel_name', channel.name,
    'author_id', case when message.webhook_name is null then message.sender_id end,
    'author_name', author_name
  );

  for follow in
    select f.*
    from public.channel_follows f
    where f.source_channel_id = channel.id
    order by f.created_at
  loop
    select cc.* into target
    from public.circle_channels cc
    where cc.id = follow.target_channel_id;

    if follow.created_by is null
      or target.id is null
      or not exists (
        select 1
        from public.conversation_members cm
        where cm.conversation_id = target.conversation_id
          and cm.user_id = follow.created_by
      )
      or not public.circle_channel_has_permission(target.id, follow.created_by, 'send_messages')
      or not public.circle_channel_has_permission(target.id, follow.created_by, 'manage_webhooks')
    then
      continue;
    end if;

    -- A copy the target refuses (say, a filter there) skips that follow
    -- instead of failing the publish.
    begin
      insert into public.messages (
        conversation_id,
        sender_id,
        type,
        body,
        webhook_name,
        webhook_avatar_url,
        crosspost
      )
      values (
        target.conversation_id,
        follow.created_by,
        'text',
        message.body,
        copy_name,
        copy_avatar,
        payload
      );
      delivered := delivered + 1;
    exception when others then
      null;
    end;
  end loop;

  return delivered;
end;
$$;

-- Edits and deletions of a published message reach its copies.
create or replace function public.sync_published_message_copies()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.recalled_at is not null and old.recalled_at is null then
    update public.messages m
    set
      recalled_at = new.recalled_at,
      body = '',
      mentions = '[]'::jsonb
    where m.crosspost is not null
      and m.crosspost->>'source_message_id' = new.id::text
      and m.recalled_at is null;

    delete from public.message_reactions r
    using public.messages m
    where r.message_id = m.id
      and m.crosspost is not null
      and m.crosspost->>'source_message_id' = new.id::text;
  elsif new.recalled_at is null and new.body is distinct from old.body then
    update public.messages m
    set
      body = new.body,
      edited_at = coalesce(new.edited_at, now())
    where m.crosspost is not null
      and m.crosspost->>'source_message_id' = new.id::text
      and m.recalled_at is null;
  end if;
  return new;
end;
$$;

revoke execute on function public.sync_published_message_copies() from public;
revoke execute on function public.sync_published_message_copies() from anon;
revoke execute on function public.sync_published_message_copies() from authenticated;

drop trigger if exists messages_sync_published_copies on public.messages;
create trigger messages_sync_published_copies
  after update of body, recalled_at on public.messages
  for each row
  when (new.published_at is not null)
  execute function public.sync_published_message_copies();

grant execute on function public.set_channel_announcement(uuid, boolean) to authenticated;
grant execute on function public.follow_announcement_channel(uuid, uuid) to authenticated;
grant execute on function public.unfollow_announcement_channel(uuid) to authenticated;
grant execute on function public.list_channel_follows(uuid) to authenticated;
grant execute on function public.list_follow_targets(uuid) to authenticated;
grant execute on function public.publish_message(uuid) to authenticated;
