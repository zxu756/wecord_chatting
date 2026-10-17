-- Disappearing messages in direct chats and groups.
--
-- * conversations.disappear_after_seconds: off (null), 24 hours, 7 days or
--   90 days. set_disappearing_messages changes it: either person in a
--   direct chat, the owner or an admin in a group. A system line announces
--   every change ({kind: 'disappearing', seconds, actor_id, actor_name}).
--   Only messages sent afterwards expire; earlier ones stay.
-- * messages.expires_at is set by the server when a message is stored (a
--   trigger, so every way of sending gets it, and nothing a client sends
--   for it counts). System lines never expire.
-- * An expired message is gone for readers at once: the messages select
--   policy hides it. purge_expired_messages() then deletes the rows (and
--   the rows hanging off them), puts the files nothing else uses in the
--   recalled_message_media list, and fixes the conversation's latest
--   message and the members' read markers. It runs from pg_cron every
--   minute when the extension exists (scheduled at the bottom); nothing
--   else depends on cron, because reads already skip expired rows.
-- * Storage objects cannot be deleted from SQL, so the expire-messages Edge
--   Function (service role) claims the queued files with
--   claim_expired_media(), removes them and confirms with
--   finish_expired_media(). It can be called by pg_net, a scheduled
--   function or any scheduler holding the service role key.

alter table public.conversations
  add column if not exists disappear_after_seconds integer;

alter table public.conversations
  drop constraint if exists conversations_disappear_after_check;
alter table public.conversations
  add constraint conversations_disappear_after_check check (
    disappear_after_seconds is null
    or disappear_after_seconds in (86400, 604800, 7776000)
  );

alter table public.messages
  add column if not exists expires_at timestamptz;

create index if not exists messages_expires_at_idx
  on public.messages (expires_at)
  where expires_at is not null;

alter table public.recalled_message_media
  add column if not exists expired boolean not null default false;

-- The server alone decides when a message expires.
create or replace function public.messages_set_expiry()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  seconds integer;
begin
  new.expires_at := null;
  if new.type = 'system' then
    return new;
  end if;
  select c.disappear_after_seconds
  into seconds
  from public.conversations c
  where c.id = new.conversation_id
    and c.type in ('direct', 'group');
  if seconds is not null then
    new.expires_at := now() + make_interval(secs => seconds);
  end if;
  return new;
end;
$$;

drop trigger if exists messages_set_expiry on public.messages;
create trigger messages_set_expiry
  before insert on public.messages
  for each row execute function public.messages_set_expiry();

-- Same as 202610130016_channel_permission_fixes, but expired messages are
-- not readable, whether or not they have been deleted yet.
drop policy if exists messages_select_member on public.messages;
create policy messages_select_member
  on public.messages for select
  to authenticated
  using (
    conversation_id in (select public.current_user_readable_conversation_ids())
    and (expires_at is null or expires_at > now())
  );

-- Sets (or, with null, turns off) the timer of a direct chat or group.
create or replace function public.set_disappearing_messages(
  target_conversation_id uuid,
  seconds integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  conversation public.conversations%rowtype;
  actor_name text;
  announcement text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if seconds is not null and seconds not in (86400, 604800, 7776000) then
    raise exception 'Choose 24 hours, 7 days, 90 days or off'
      using errcode = '22023';
  end if;

  select c.*
  into conversation
  from public.conversations c
  where c.id = target_conversation_id
    and c.type in ('direct', 'group')
  for update;

  if conversation.id is null
    or not public.is_current_user_conversation_member(conversation.id)
  then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  if conversation.type = 'group' and not exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id = conversation.id
      and cm.user_id = current_user_id
      and cm.role in ('owner', 'admin')
  ) then
    raise exception 'Only the owner and admins can change disappearing messages'
      using errcode = '42501';
  end if;

  if public.is_current_user_blocked_in_conversation(conversation.id) then
    raise exception 'Cannot change this conversation' using errcode = '42501';
  end if;

  if conversation.disappear_after_seconds is not distinct from seconds then
    return;
  end if;

  update public.conversations c
  set disappear_after_seconds = seconds
  where c.id = conversation.id;

  select nullif(btrim(p.display_name), '')
  into actor_name
  from public.profiles p
  where p.id = current_user_id;

  announcement := coalesce(actor_name, 'Someone') || case seconds
    when 86400 then ' set messages to disappear after 24 hours.'
    when 604800 then ' set messages to disappear after 7 days.'
    when 7776000 then ' set messages to disappear after 90 days.'
    else ' turned off disappearing messages.'
  end;

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    attachment
  )
  values (
    conversation.id,
    current_user_id,
    'system',
    announcement,
    jsonb_build_object(
      'kind', 'disappearing',
      'seconds', seconds,
      'actor_id', current_user_id,
      'actor_name', coalesce(actor_name, 'Someone')
    )
  );
end;
$$;

revoke execute on function public.set_disappearing_messages(uuid, integer) from public, anon;
grant execute on function public.set_disappearing_messages(uuid, integer) to authenticated;

-- Deletes up to [batch_limit] expired messages and tidies up after them.
-- Returns how many it deleted; call again while it returns a full batch.
create or replace function public.purge_expired_messages(
  batch_limit integer default 500
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  expired_ids uuid[];
  expired_conversations uuid[];
  deleted_count integer;
begin
  select
    coalesce(array_agg(batch.id), array[]::uuid[]),
    coalesce(array_agg(distinct batch.conversation_id), array[]::uuid[])
  into expired_ids, expired_conversations
  from (
    select m.id, m.conversation_id
    from public.messages m
    where m.expires_at is not null
      and m.expires_at <= now()
    order by m.expires_at
    limit greatest(1, least(coalesce(batch_limit, 500), 5000))
    for update skip locked
  ) batch;

  if cardinality(expired_ids) = 0 then
    return 0;
  end if;

  -- Read markers and the latest message must not point into the gap.
  update public.conversation_members cm
  set last_read_message_id = (
    select m.id
    from public.messages m
    join public.messages gone on gone.id = cm.last_read_message_id
    where m.conversation_id = cm.conversation_id
      and m.id <> all (expired_ids)
      and (m.created_at, m.id) <= (gone.created_at, gone.id)
    order by m.created_at desc, m.id desc
    limit 1
  )
  where cm.last_read_message_id = any (expired_ids);

  -- A reply keeps no copy of what it answered.
  update public.messages r
  set reply_preview = null
  where r.reply_to_message_id = any (expired_ids)
    and r.id <> all (expired_ids)
    and r.reply_preview is not null;

  insert into public.recalled_message_media as r (
    bucket_id,
    object_path,
    message_id,
    deleted_by,
    expired
  )
  select distinct on (media.bucket, media.path)
    media.bucket,
    media.path,
    null::uuid,
    null::uuid,
    true
  from (
    select
      m.attachment->>'bucket' as bucket,
      m.attachment->>'path' as path
    from public.messages m
    where m.id = any (expired_ids)
      and m.attachment->>'path' is not null
      and m.attachment->>'bucket' in ('chat-images', 'voice-messages', 'chat-files')
  ) media
  on conflict on constraint recalled_message_media_pkey do update
  set expired = true, created_at = now();

  delete from public.messages m
  where m.id = any (expired_ids);
  get diagnostics deleted_count = row_count;

  update public.conversations c
  set
    last_message_id = latest.id,
    last_message_at = coalesce(latest.created_at, c.last_message_at)
  from (
    select
      conversation_id,
      (
        select m.id
        from public.messages m
        where m.conversation_id = conv.conversation_id
        order by m.created_at desc, m.id desc
        limit 1
      ) as id,
      (
        select m.created_at
        from public.messages m
        where m.conversation_id = conv.conversation_id
        order by m.created_at desc, m.id desc
        limit 1
      ) as created_at
    from unnest(expired_conversations) as conv(conversation_id)
  ) latest
  where c.id = latest.conversation_id
    and c.last_message_id is null;

  return deleted_count;
end;
$$;

revoke execute on function public.purge_expired_messages(integer) from public, anon, authenticated;
grant execute on function public.purge_expired_messages(integer) to service_role;

-- The queued files nothing uses any more, for expire-messages to remove.
-- Entries a message uses again (a forwarded copy) are dropped.
create or replace function public.claim_expired_media(max_rows integer default 200)
returns table (bucket_id text, object_path text)
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.recalled_message_media r
  where r.expired
    and exists (
      select 1
      from public.messages m
      where m.attachment->>'path' = r.object_path
        and m.attachment->>'bucket' = r.bucket_id
    );

  return query
  select r.bucket_id, r.object_path
  from public.recalled_message_media r
  where r.expired
  order by r.created_at
  limit greatest(1, least(coalesce(max_rows, 200), 1000));
end;
$$;

create or replace function public.finish_expired_media(
  buckets text[],
  paths text[]
)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.recalled_message_media r
  using unnest(buckets, paths) as done(bucket_id, object_path)
  where r.expired
    and r.bucket_id = done.bucket_id
    and r.object_path = done.object_path;
$$;

revoke execute on function public.claim_expired_media(integer) from public, anon, authenticated;
revoke execute on function public.finish_expired_media(text[], text[]) from public, anon, authenticated;
grant execute on function public.claim_expired_media(integer) to service_role;
grant execute on function public.finish_expired_media(text[], text[]) to service_role;

-- Scheduling. Only when pg_cron can be used; reads skip expired rows
-- either way, so a project without it still hides them at once and
-- deletes them whenever purge_expired_messages() is called.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'wecord-purge-expired-messages';
    perform cron.schedule(
      'wecord-purge-expired-messages',
      '* * * * *',
      'select public.purge_expired_messages(2000)'
    );
  else
    raise notice 'pg_cron is not available: call purge_expired_messages() from another scheduler';
  end if;
exception when others then
  raise notice 'Could not schedule the purge with pg_cron: %', sqlerrm;
end;
$$;

-- File removal needs the Edge Function: with pg_net and two vault secrets
-- (project_url, service_role_key) a second job calls it every five
-- minutes; otherwise schedule expire-messages some other way.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
    and exists (select 1 from pg_available_extensions where name = 'pg_net')
    and exists (select 1 from pg_namespace where nspname = 'vault')
  then
    create extension if not exists pg_net;
    if exists (
      select 1 from vault.decrypted_secrets where name = 'project_url'
    ) and exists (
      select 1 from vault.decrypted_secrets where name = 'service_role_key'
    ) then
      perform cron.unschedule(jobid)
      from cron.job
      where jobname = 'wecord-expire-message-files';
      perform cron.schedule(
        'wecord-expire-message-files',
        '*/5 * * * *',
        $job$
        select net.http_post(
          url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
            || '/functions/v1/expire-messages',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || (
              select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'
            )
          ),
          body := '{}'::jsonb
        )
        $job$
      );
    else
      raise notice 'Add vault secrets project_url and service_role_key to schedule expire-messages';
    end if;
  end if;
exception when others then
  raise notice 'Could not schedule expire-messages: %', sqlerrm;
end;
$$;
