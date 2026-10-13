-- Channel webhooks, like Discord's: a secret URL that external services
-- POST to (through the public `webhook` Edge Function) to post messages in
-- a circle text channel under the webhook's name.
--
-- * circle_webhooks: one row per webhook. Only a SHA-256 hash of the token
--   is stored; the token itself is returned once by
--   create_channel_webhook / regenerate_webhook_token. Clients cannot read
--   the table (no policies): list_channel_webhooks returns everything but
--   the hash.
-- * Managing webhooks (create, list, rename, regenerate, delete) needs
--   manage_webhooks in the channel, which includes seeing it; each change
--   is audited as webhook_create / webhook_update / webhook_regenerate /
--   webhook_delete. Webhooks post only into text channels, at most 10 per
--   channel.
-- * post_webhook_message is executable only by service_role (the Edge
--   Function). It checks the token, the content (1 to 2000 characters),
--   that the webhook's creator is still a member with manage_webhooks and
--   send_messages in the channel, and a limit of 30 messages per webhook
--   and minute (webhook_rate, raising WH429). The message is an ordinary
--   text message sent as the creator (sender_id) and marked with
--   webhook_id, webhook_name and webhook_avatar_url; the send trigger still
--   checks the creator's send_messages but skips slowmode, and webhook
--   messages do not count towards the creator's slowmode. Mentions are not
--   parsed; markdown renders as usual.
-- * Clients cannot mark their own messages as webhook messages, and
--   webhook messages cannot be edited (the creator may still delete them).
-- * Unread counts: a webhook message is unread for every member, the
--   creator included (it is not their own message), in
--   list_conversation_summaries and list_circle_summaries, which also
--   return last_message_webhook_name so notifications treat it the same.
--   Deleting a webhook keeps its messages (webhook_id is set to null; the
--   name and avatar stay).
--
-- Error codes of post_webhook_message, mapped to HTTP by the function:
-- P0002 unknown webhook (404), 28000 bad token (401), 22023 invalid
-- content, username or avatar (400), 42501 creator no longer allowed to
-- post (403), WH429 rate limited (429).

create table if not exists public.circle_webhooks (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  channel_id uuid not null,
  name text not null,
  avatar_url text,
  token_hash text not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  constraint circle_webhooks_name_length check (
    name = btrim(name) and char_length(name) between 1 and 80
  ),
  constraint circle_webhooks_avatar_url_format check (
    avatar_url is null
    or (avatar_url ~* '^https?://' and char_length(avatar_url) <= 2048)
  ),
  constraint circle_webhooks_token_hash_format check (
    token_hash ~ '^[0-9a-f]{64}$'
  ),
  constraint circle_webhooks_channel_fkey
    foreign key (channel_id, circle_id)
    references public.circle_channels(id, circle_id)
    on delete cascade
);

create index if not exists circle_webhooks_channel_idx
  on public.circle_webhooks (channel_id, created_at);

create index if not exists circle_webhooks_circle_idx
  on public.circle_webhooks (circle_id);

alter table public.circle_webhooks enable row level security;

revoke all on public.circle_webhooks from anon;
revoke all on public.circle_webhooks from authenticated;

-- Messages posted by each webhook in the current minute.
create table if not exists public.webhook_rate (
  webhook_id uuid primary key references public.circle_webhooks(id) on delete cascade,
  window_start timestamptz not null,
  count integer not null default 0
);

alter table public.webhook_rate enable row level security;

revoke all on public.webhook_rate from anon;
revoke all on public.webhook_rate from authenticated;

alter table public.messages
  add column if not exists webhook_id uuid
    references public.circle_webhooks(id) on delete set null,
  add column if not exists webhook_name text,
  add column if not exists webhook_avatar_url text;

alter table public.messages
  drop constraint if exists messages_webhook_name_length;
alter table public.messages
  add constraint messages_webhook_name_length check (
    webhook_name is null or char_length(webhook_name) between 1 and 80
  );

create index if not exists messages_webhook_idx
  on public.messages (webhook_id)
  where webhook_id is not null;

-- Same as 202610130023_polls, but clients cannot post as a webhook.
drop policy if exists messages_insert_member on public.messages;

create policy messages_insert_member
  on public.messages for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and type <> 'system'
    and type <> 'poll'
    and forwarded_from is null
    and webhook_id is null
    and webhook_name is null
    and webhook_avatar_url is null
    and public.is_current_user_conversation_member(conversation_id)
    and not public.is_current_user_blocked_in_conversation(conversation_id)
  );

-- A new random webhook token: 32 bytes, base64url without padding.
create or replace function public.new_webhook_token()
returns text
language sql
volatile
set search_path = public
as $$
  select rtrim(
    translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'),
    '='
  );
$$;

create or replace function public.webhook_token_hash(token text)
returns text
language sql
immutable
set search_path = public
as $$
  select encode(sha256(convert_to(coalesce(token, ''), 'UTF8')), 'hex');
$$;

-- The webhook, when the caller may manage it (manage_webhooks in its
-- channel); raises otherwise.
create or replace function public.channel_webhook_for_management(
  target_webhook_id uuid
)
returns public.circle_webhooks
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  webhook public.circle_webhooks%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select w.*
  into webhook
  from public.circle_webhooks w
  where w.id = target_webhook_id;

  if webhook.id is null
    or not public.current_user_has_channel_permission(
      webhook.channel_id,
      'manage_webhooks'
    )
  then
    raise exception 'Webhook not found or caller cannot manage it'
      using errcode = '42501';
  end if;

  return webhook;
end;
$$;

-- The webhook's payload for clients: everything but the token hash.
create or replace function public.channel_webhook_payload(
  webhook public.circle_webhooks
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', webhook.id,
    'circle_id', webhook.circle_id,
    'channel_id', webhook.channel_id,
    'name', webhook.name,
    'avatar_url', webhook.avatar_url,
    'created_by', webhook.created_by,
    'creator_name', case
      when webhook.created_by is null then null
      else public.circle_member_label(webhook.circle_id, webhook.created_by)
    end,
    'created_at', webhook.created_at,
    'last_used_at', webhook.last_used_at
  );
$$;

revoke execute on function public.new_webhook_token() from public;
revoke execute on function public.new_webhook_token() from anon;
revoke execute on function public.new_webhook_token() from authenticated;
revoke execute on function public.webhook_token_hash(text) from public;
revoke execute on function public.webhook_token_hash(text) from anon;
revoke execute on function public.webhook_token_hash(text) from authenticated;
revoke execute on function public.channel_webhook_for_management(uuid) from public;
revoke execute on function public.channel_webhook_for_management(uuid) from anon;
revoke execute on function public.channel_webhook_for_management(uuid) from authenticated;
revoke execute on function public.channel_webhook_payload(public.circle_webhooks) from public;
revoke execute on function public.channel_webhook_payload(public.circle_webhooks) from anon;
revoke execute on function public.channel_webhook_payload(public.circle_webhooks) from authenticated;

-- Creates a webhook in a text channel. Returns its payload with the token,
-- which is never shown again.
create or replace function public.create_channel_webhook(
  target_channel_id uuid,
  webhook_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
  trimmed_name text := btrim(coalesce(webhook_name, ''));
  token text := public.new_webhook_token();
  created public.circle_webhooks%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cc.*
  into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel.id is null
    or not public.current_user_has_channel_permission(
      channel.id,
      'manage_webhooks'
    )
  then
    raise exception 'Channel not found or caller cannot manage its webhooks'
      using errcode = '42501';
  end if;

  if channel.kind <> 'text' then
    raise exception 'Webhooks post only into text channels'
      using errcode = '22023';
  end if;

  if char_length(trimmed_name) not between 1 and 80 then
    raise exception 'Webhook name must be 1 to 80 characters'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('webhooks:' || channel.id::text, 0));

  if (
    select count(*)
    from public.circle_webhooks w
    where w.channel_id = channel.id
  ) >= 10 then
    raise exception 'A channel can have at most 10 webhooks'
      using errcode = '54000';
  end if;

  insert into public.circle_webhooks (
    circle_id,
    channel_id,
    name,
    token_hash,
    created_by
  )
  values (
    channel.circle_id,
    channel.id,
    trimmed_name,
    public.webhook_token_hash(token),
    auth.uid()
  )
  returning * into created;

  perform public.write_circle_audit(
    channel.circle_id,
    'webhook_create',
    'webhook',
    created.id,
    created.name,
    jsonb_build_object('channel_name', channel.name)
  );

  return public.channel_webhook_payload(created)
    || jsonb_build_object('token', token);
end;
$$;

create or replace function public.list_channel_webhooks(target_channel_id uuid)
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
  select public.channel_webhook_payload(w)
  from public.circle_webhooks w
  where w.channel_id = target_channel_id
  order by w.created_at, w.id;
end;
$$;

create or replace function public.rename_channel_webhook(
  target_webhook_id uuid,
  webhook_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  webhook public.circle_webhooks%rowtype :=
    public.channel_webhook_for_management(target_webhook_id);
  trimmed_name text := btrim(coalesce(webhook_name, ''));
  renamed public.circle_webhooks%rowtype;
begin
  if char_length(trimmed_name) not between 1 and 80 then
    raise exception 'Webhook name must be 1 to 80 characters'
      using errcode = '22023';
  end if;

  if trimmed_name = webhook.name then
    return public.channel_webhook_payload(webhook);
  end if;

  update public.circle_webhooks w
  set name = trimmed_name
  where w.id = webhook.id
  returning * into renamed;

  perform public.write_circle_audit(
    webhook.circle_id,
    'webhook_update',
    'webhook',
    webhook.id,
    renamed.name,
    jsonb_build_object(
      'name',
      jsonb_build_object('old', webhook.name, 'new', renamed.name)
    )
  );

  return public.channel_webhook_payload(renamed);
end;
$$;

-- Replaces the token, so the old URL stops working. Returns the payload
-- with the new token, which is never shown again.
create or replace function public.regenerate_webhook_token(
  target_webhook_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  webhook public.circle_webhooks%rowtype :=
    public.channel_webhook_for_management(target_webhook_id);
  token text := public.new_webhook_token();
begin
  update public.circle_webhooks w
  set token_hash = public.webhook_token_hash(token)
  where w.id = webhook.id;

  perform public.write_circle_audit(
    webhook.circle_id,
    'webhook_regenerate',
    'webhook',
    webhook.id,
    webhook.name,
    '{}'::jsonb
  );

  return public.channel_webhook_payload(webhook)
    || jsonb_build_object('token', token);
end;
$$;

create or replace function public.delete_channel_webhook(target_webhook_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  webhook public.circle_webhooks%rowtype :=
    public.channel_webhook_for_management(target_webhook_id);
begin
  delete from public.circle_webhooks w
  where w.id = webhook.id;

  perform public.write_circle_audit(
    webhook.circle_id,
    'webhook_delete',
    'webhook',
    webhook.id,
    webhook.name,
    jsonb_build_object(
      'channel_name',
      (
        select cc.name
        from public.circle_channels cc
        where cc.id = webhook.channel_id
      )
    )
  );
end;
$$;

-- Posts a message through a webhook. Only the `webhook` Edge Function
-- (service_role) may call this; see the header for checks and errors.
create or replace function public.post_webhook_message(
  target_webhook_id uuid,
  webhook_token text,
  content text,
  username text default null,
  avatar_url text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  webhook public.circle_webhooks%rowtype;
  channel public.circle_channels%rowtype;
  trimmed_content text := btrim(coalesce(content, ''));
  trimmed_username text := nullif(btrim(coalesce(username, '')), '');
  trimmed_avatar_url text := nullif(btrim(coalesce(avatar_url, '')), '');
  sent_this_minute integer;
  created_message_id uuid;
begin
  select w.*
  into webhook
  from public.circle_webhooks w
  where w.id = target_webhook_id;

  if webhook.id is null then
    raise exception 'Unknown webhook' using errcode = 'P0002';
  end if;

  if webhook.token_hash <> public.webhook_token_hash(webhook_token) then
    raise exception 'Invalid webhook token' using errcode = '28000';
  end if;

  if char_length(trimmed_content) not between 1 and 2000 then
    raise exception 'Content must be 1 to 2000 characters'
      using errcode = '22023';
  end if;

  if trimmed_username is not null and char_length(trimmed_username) > 80 then
    raise exception 'Username must be at most 80 characters'
      using errcode = '22023';
  end if;

  if trimmed_avatar_url is not null
    and (
      trimmed_avatar_url !~* '^https?://[^[:space:]]+$'
      or char_length(trimmed_avatar_url) > 2048
    )
  then
    raise exception 'Avatar URL must be an http(s) URL'
      using errcode = '22023';
  end if;

  select cc.*
  into channel
  from public.circle_channels cc
  where cc.id = webhook.channel_id;

  if webhook.created_by is null
    or not exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = channel.conversation_id
        and cm.user_id = webhook.created_by
    )
    or not public.circle_channel_has_permission(
      channel.id,
      webhook.created_by,
      'manage_webhooks'
    )
    or not public.circle_channel_has_permission(
      channel.id,
      webhook.created_by,
      'send_messages'
    )
  then
    raise exception 'The webhook''s creator can no longer post in this channel'
      using errcode = '42501';
  end if;

  insert into public.webhook_rate as rate (webhook_id, window_start, count)
  values (webhook.id, date_trunc('minute', now()), 1)
  on conflict (webhook_id) do update
  set
    count = case
      when rate.window_start = excluded.window_start then rate.count + 1
      else 1
    end,
    window_start = excluded.window_start
  returning rate.count into sent_this_minute;

  if sent_this_minute > 30 then
    raise exception 'Webhook rate limit: at most 30 messages per minute'
      using errcode = 'WH429';
  end if;

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    webhook_id,
    webhook_name,
    webhook_avatar_url
  )
  values (
    channel.conversation_id,
    webhook.created_by,
    'text',
    trimmed_content,
    webhook.id,
    coalesce(trimmed_username, webhook.name),
    coalesce(trimmed_avatar_url, webhook.avatar_url)
  )
  returning id into created_message_id;

  update public.circle_webhooks w
  set last_used_at = now()
  where w.id = webhook.id;

  return created_message_id;
end;
$$;

revoke execute on function public.post_webhook_message(uuid, text, text, text, text) from public;
revoke execute on function public.post_webhook_message(uuid, text, text, text, text) from anon;
revoke execute on function public.post_webhook_message(uuid, text, text, text, text) from authenticated;
grant execute on function public.post_webhook_message(uuid, text, text, text, text) to service_role;

-- Same as 202610130020_forum_channels, but webhook messages skip slowmode
-- and do not count towards their creator's.
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

-- Same as 202610130016_channel_permission_fixes, but webhook messages cannot
-- be edited (their sender is the webhook's creator).
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
    and m.webhook_name is null
    and m.recalled_at is null
    and public.is_current_user_conversation_member(m.conversation_id)
  returning m.id into edited_message_id;

  if edited_message_id is null then
    raise exception 'Message not found or cannot be edited'
      using errcode = '42501';
  end if;
end;
$$;

-- Same as 202610130015_channel_slowmode, but webhook messages are unread
-- for their creator too, and the latest message says whether a webhook
-- posted it.
drop function if exists public.list_conversation_summaries();

create or replace function public.list_conversation_summaries()
returns table (
  id uuid,
  type text,
  title text,
  avatar_url text,
  announcement text,
  announcement_updated_at timestamptz,
  announcement_updated_by uuid,
  last_message_body text,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_type text,
  last_message_webhook_name text,
  unread_count bigint,
  pinned_at timestamptz,
  muted_until timestamptz,
  is_muted boolean,
  is_marked_unread boolean,
  member_count bigint,
  mentioned_user_ids uuid[],
  circle_id uuid,
  circle_notification_level text,
  circle_muted_until timestamptz,
  direct_user_id uuid,
  direct_custom_status jsonb,
  parent_conversation_id uuid,
  parent_title text,
  thread_id uuid,
  thread_archived_at timestamptz,
  thread_last_activity_at timestamptz,
  can_send_messages boolean,
  slowmode_seconds integer
)
language sql
stable
security definer
set search_path = public
as $$
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
    greatest(
      count(unread_messages.id),
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
    end as slowmode_seconds
  from public.conversations c
  join current_memberships cm on cm.conversation_id = c.id
  left join read_markers rm on rm.conversation_id = c.id
  left join direct_profiles dp on dp.conversation_id = c.id and c.type = 'direct'
  left join member_counts mc on mc.conversation_id = c.id
  left join public.messages last_message on last_message.id = c.last_message_id
  left join last_message_mentions lmm on lmm.message_id = last_message.id
  left join public.conversation_threads ct on ct.conversation_id = c.id
  left join public.conversations parent_conversation
    on parent_conversation.id = ct.parent_conversation_id
  left join public.circle_channels cc
    on cc.conversation_id = coalesce(ct.parent_conversation_id, c.id)
  left join public.circle_notification_settings cns
    on cns.circle_id = cc.circle_id
    and cns.user_id = auth.uid()
  left join public.messages unread_messages
    on unread_messages.conversation_id = c.id
    and (
      unread_messages.sender_id <> auth.uid()
      or unread_messages.webhook_name is not null
    )
    and (
      rm.last_read_at is null
      or unread_messages.created_at > rm.last_read_at
    )
  where cm.hidden_at is null
    or c.last_message_at > cm.hidden_at
  group by
    c.id,
    c.type,
    c.title,
    c.avatar_url,
    c.announcement,
    c.announcement_updated_at,
    c.announcement_updated_by,
    dp.user_id,
    dp.display_name,
    dp.avatar_url,
    dp.custom_status,
    last_message.body,
    last_message.sender_id,
    last_message.recalled_at,
    last_message.type,
    last_message.webhook_name,
    c.last_message_at,
    c.updated_at,
    cm.pinned_at,
    cm.muted_until,
    cm.manual_unread_at,
    mc.member_count,
    lmm.mentioned_user_ids,
    cc.id,
    cc.circle_id,
    cc.slowmode_seconds,
    cns.level,
    cns.muted_until,
    ct.id,
    ct.parent_conversation_id,
    ct.archived_at,
    ct.last_message_at,
    ct.created_at,
    parent_conversation.title
  order by
    cm.pinned_at desc nulls last,
    c.last_message_at desc nulls last,
    c.updated_at desc;
$$;

-- Same as 202610130014_channel_permission_overwrites, but webhook messages
-- are unread for their creator too.
create or replace function public.list_circle_summaries()
returns table (
  id uuid,
  name text,
  avatar_url text,
  member_count bigint,
  channel_count bigint,
  latest_activity_at timestamptz,
  current_user_role text,
  unread_count bigint,
  mention_count bigint,
  is_muted boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with visible_channels as (
    select cc.id, cc.circle_id, cc.conversation_id
    from public.circle_members current_member
    join public.circle_channels cc on cc.circle_id = current_member.circle_id
    where current_member.user_id = auth.uid()
      and public.circle_channel_has_permission(cc.id, auth.uid(), 'view_channel')
  ),
  circle_conversations as (
    select vc.circle_id, vc.conversation_id
    from visible_channels vc
    union all
    select vc.circle_id, ct.conversation_id
    from visible_channels vc
    join public.conversation_threads ct
      on ct.parent_conversation_id = vc.conversation_id
  ),
  channel_reads as (
    select
      cc.circle_id,
      cc.conversation_id,
      conv_member.manual_unread_at,
      read_message.created_at as last_read_at
    from circle_conversations cc
    join public.conversation_members conv_member
      on conv_member.conversation_id = cc.conversation_id
      and conv_member.user_id = auth.uid()
    left join public.messages read_message
      on read_message.id = conv_member.last_read_message_id
  ),
  channel_counts as (
    select
      cr.circle_id,
      greatest(
        (
          select count(*)
          from public.messages unread_message
          where unread_message.conversation_id = cr.conversation_id
            and (
              unread_message.sender_id <> auth.uid()
              or unread_message.webhook_name is not null
            )
            and (
              cr.last_read_at is null
              or unread_message.created_at > cr.last_read_at
            )
        ),
        case when cr.manual_unread_at is null then 0 else 1 end::bigint
      ) as unread_count,
      (
        select count(distinct mentioned_message.id)
        from public.message_mentions mm
        join public.messages mentioned_message
          on mentioned_message.id = mm.message_id
        where mm.conversation_id = cr.conversation_id
          and mm.user_id = auth.uid()
          and mentioned_message.sender_id <> auth.uid()
          and mentioned_message.type <> 'system'
          and (
            cr.last_read_at is null
            or mentioned_message.created_at > cr.last_read_at
          )
      ) as mention_count
    from channel_reads cr
  ),
  circle_counts as (
    select
      channel_count.circle_id,
      sum(channel_count.unread_count)::bigint as unread_count,
      sum(channel_count.mention_count)::bigint as mention_count
    from channel_counts channel_count
    group by channel_count.circle_id
  )
  select
    c.id,
    c.name,
    c.avatar_url,
    count(distinct all_members.user_id) as member_count,
    count(distinct cc.id) as channel_count,
    greatest(
      c.updated_at,
      coalesce(max(cp.created_at), c.updated_at),
      coalesce(max(ch_conversation.last_message_at), c.updated_at)
    ) as latest_activity_at,
    current_member.role as current_user_role,
    coalesce(counts.unread_count, 0) as unread_count,
    coalesce(counts.mention_count, 0) as mention_count,
    coalesce(
      cns.level = 'none'
        or (cns.muted_until is not null and cns.muted_until > now()),
      false
    ) as is_muted
  from public.circles c
  join public.circle_members current_member
    on current_member.circle_id = c.id
    and current_member.user_id = auth.uid()
  left join public.circle_members all_members on all_members.circle_id = c.id
  left join visible_channels cc on cc.circle_id = c.id
  left join public.conversations ch_conversation
    on ch_conversation.id = cc.conversation_id
  left join public.circle_posts cp on cp.circle_id = c.id
  left join circle_counts counts on counts.circle_id = c.id
  left join public.circle_notification_settings cns
    on cns.circle_id = c.id
    and cns.user_id = auth.uid()
  group by
    c.id,
    c.name,
    c.avatar_url,
    c.updated_at,
    current_member.role,
    counts.unread_count,
    counts.mention_count,
    cns.level,
    cns.muted_until
  order by latest_activity_at desc, c.created_at desc;
$$;

grant execute on function public.create_channel_webhook(uuid, text) to authenticated;
grant execute on function public.list_channel_webhooks(uuid) to authenticated;
grant execute on function public.rename_channel_webhook(uuid, text) to authenticated;
grant execute on function public.regenerate_webhook_token(uuid) to authenticated;
grant execute on function public.delete_channel_webhook(uuid) to authenticated;
grant execute on function public.edit_message(uuid, text) to authenticated;
grant execute on function public.list_conversation_summaries() to authenticated;
grant execute on function public.list_circle_summaries() to authenticated;
