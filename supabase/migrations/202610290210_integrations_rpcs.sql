-- Rich webhooks, RSS feeds and GitHub (roadmap I6), part 2 of 4: managing
-- feeds and GitHub hooks, and keeping them out of the plain webhook list.
--
-- Who: the same people as for webhooks, "manage webhooks" in the channel
-- (current_user_has_channel_permission). A circle that an admin took down
-- (K1, delist or suspend) takes no new feeds or hooks and no changes.
--
-- * Feeds: add_channel_feed / list_channel_feeds / set_channel_feed_enabled /
--   remove_channel_feed. The address is checked here (https, a real host
--   name, no address, no inner name: bot_callback_url_problem) and again,
--   with a DNS lookup, before every read by the feed-fetch function. At most
--   10 feeds per circle and 5 per channel, one address once per channel.
-- * GitHub: add_github_hook / list_github_hooks / update_github_hook /
--   regenerate_github_secret / set_github_hook_enabled / remove_github_hook.
--   The secret is made here (32 random bytes), returned once and never by a
--   list. At most 10 hooks per circle and 5 per channel.
-- * Every change is audited: feed_add, feed_pause, feed_resume, feed_remove,
--   github_add, github_update, github_regenerate, github_pause,
--   github_resume, github_remove.
-- * A feed or a hook posts as the person who made it (the owner of its hidden
--   webhook row). If that person leaves the circle or loses the permission,
--   the feed or hook pauses itself; the person who turns it back on becomes
--   the one it posts as.
--
-- Plain webhooks are patched, in place from the live definitions (so the
-- announcement channels of 202610160037 stay), to see only kind 'incoming':
--   * create_channel_webhook: the limit of 10 per channel counts only them;
--   * list_channel_webhooks: lists only them;
--   * channel_webhook_for_management: rename, regenerate and delete only
--     reach them (a feed's hidden row is not a URL anyone can use).
-- Each patch must find its anchor and change the text, or the migration stops
-- and says so, and a second run changes nothing.

do $$
declare
  def text;
  patched text;
  needle text;
begin
  def := pg_get_functiondef('public.create_channel_webhook(uuid, text)'::regprocedure);
  if def not like '%w.kind = ''incoming''%' then
    needle := E'    from public.circle_webhooks w\n    where w.channel_id = channel.id\n  ) >= 10 then';
    if (length(def) - length(replace(def, needle, ''))) <> length(needle) then
      raise exception 'create_channel_webhook changed shape; patch it by hand';
    end if;
    patched := replace(
      def,
      needle,
      E'    from public.circle_webhooks w\n    where w.channel_id = channel.id\n      and w.kind = ''incoming''\n  ) >= 10 then'
    );
    execute patched;
  end if;

  def := pg_get_functiondef('public.list_channel_webhooks(uuid)'::regprocedure);
  if def not like '%w.kind = ''incoming''%' then
    needle := E'  where w.channel_id = target_channel_id\n';
    if (length(def) - length(replace(def, needle, ''))) <> length(needle) then
      raise exception 'list_channel_webhooks changed shape; patch it by hand';
    end if;
    patched := replace(
      def,
      needle,
      E'  where w.channel_id = target_channel_id\n    and w.kind = ''incoming''\n'
    );
    execute patched;
  end if;

  def := pg_get_functiondef('public.channel_webhook_for_management(uuid)'::regprocedure);
  if def not like '%w.kind = ''incoming''%' then
    needle := E'  where w.id = target_webhook_id;\n';
    if (length(def) - length(replace(def, needle, ''))) <> length(needle) then
      raise exception 'channel_webhook_for_management changed shape; patch it by hand';
    end if;
    patched := replace(
      def,
      needle,
      E'  where w.id = target_webhook_id\n    and w.kind = ''incoming'';\n'
    );
    execute patched;
  end if;
end;
$$;

-- ------------------------------------------------------------ helpers

-- The channel, when the caller may manage its integrations and the circle is
-- not taken down (K1); raises otherwise.
create or replace function public.integration_channel_for_management(
  target_channel_id uuid
)
returns public.circle_channels
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel.id is null
    or not public.current_user_has_channel_permission(channel.id, 'manage_webhooks')
  then
    raise exception 'Channel not found or caller cannot manage its integrations'
      using errcode = '42501';
  end if;

  if exists (
    select 1 from public.circles c
    where c.id = channel.circle_id and c.disabled_at is not null
  ) then
    raise exception 'This circle was taken down' using errcode = '42501';
  end if;

  if channel.kind not in ('text', 'announcement') then
    raise exception 'Integrations post only into text and announcement channels'
      using errcode = '22023';
  end if;
  return channel;
end;
$$;

-- Why the person a feed or hook posts as can no longer do it, or null when
-- they can: creator_gone (no person, or the account was deleted),
-- creator_lost_access (left the channel, lost "manage webhooks" or "send
-- messages", or the account is suspended by the platform).
create or replace function public.integration_creator_problem(
  target_webhook_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  webhook public.circle_webhooks%rowtype;
  conversation uuid;
begin
  select w.* into webhook from public.circle_webhooks w where w.id = target_webhook_id;
  if webhook.id is null or webhook.created_by is null
    or exists (
      select 1 from public.profiles p
      where p.id = webhook.created_by and p.deleted_at is not null
    )
  then
    return 'creator_gone';
  end if;

  select cc.conversation_id into conversation
  from public.circle_channels cc where cc.id = webhook.channel_id;

  if conversation is null
    or not exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id = conversation and cm.user_id = webhook.created_by
    )
    or not public.circle_channel_has_permission(webhook.channel_id, webhook.created_by, 'manage_webhooks')
    or not public.circle_channel_has_permission(webhook.channel_id, webhook.created_by, 'send_messages')
    or public.is_user_suspended(webhook.created_by)
  then
    return 'creator_lost_access';
  end if;
  return null;
end;
$$;

-- A hidden webhook row for a feed or a hook: the messages' webhook_id, name
-- and the person they are posted as. Its token is thrown away.
create or replace function public.integration_make_webhook(
  target_channel public.circle_channels,
  hook_kind text,
  hook_name text
)
returns public.circle_webhooks
language plpgsql
security definer
set search_path = public
as $$
declare
  created public.circle_webhooks%rowtype;
begin
  insert into public.circle_webhooks (
    circle_id, channel_id, name, token_hash, created_by, kind
  )
  values (
    target_channel.circle_id,
    target_channel.id,
    left(btrim(hook_name), 80),
    public.webhook_token_hash(public.new_webhook_token()),
    auth.uid(),
    hook_kind
  )
  returning * into created;
  return created;
end;
$$;

revoke execute on function public.integration_channel_for_management(uuid) from public, anon, authenticated;
revoke execute on function public.integration_creator_problem(uuid) from public, anon, authenticated;
revoke execute on function public.integration_make_webhook(public.circle_channels, text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------- feeds

create or replace function public.channel_feed_payload(feed public.channel_feeds)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', feed.id,
    'circle_id', feed.circle_id,
    'channel_id', feed.channel_id,
    'url', feed.url,
    'title', feed.title,
    'enabled', feed.enabled,
    'paused_reason', feed.paused_reason,
    'consecutive_failures', feed.consecutive_failures,
    'last_status', feed.last_status,
    'last_error', feed.last_error,
    'last_fetched_at', feed.last_fetched_at,
    'last_success_at', feed.last_success_at,
    'last_item_at', feed.last_item_at,
    'items_posted', feed.items_posted,
    'created_at', feed.created_at,
    'created_by', w.created_by,
    'creator_name', case
      when w.created_by is null then null
      else public.circle_member_label(feed.circle_id, w.created_by)
    end
  )
  from public.circle_webhooks w
  where w.id = feed.webhook_id;
$$;

revoke execute on function public.channel_feed_payload(public.channel_feeds) from public, anon, authenticated;

create or replace function public.add_channel_feed(
  target_channel_id uuid,
  feed_url text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype :=
    public.integration_channel_for_management(target_channel_id);
  clean_url text := btrim(coalesce(feed_url, ''));
  url_problem text := public.bot_callback_url_problem(btrim(coalesce(feed_url, '')));
  feed_host text;
  hidden public.circle_webhooks%rowtype;
  created public.channel_feeds%rowtype;
begin
  if url_problem is not null then
    raise exception '%', url_problem using errcode = '22023';
  end if;
  feed_host := lower(substring(clean_url from '^https://([^/?#:]+)'));

  perform pg_advisory_xact_lock(hashtextextended('integrations:' || channel.circle_id::text, 0));

  if (select count(*) from public.channel_feeds f where f.circle_id = channel.circle_id) >= 10 then
    raise exception 'A circle can follow at most 10 feeds' using errcode = '54000';
  end if;
  if (select count(*) from public.channel_feeds f where f.channel_id = channel.id) >= 5 then
    raise exception 'A channel can follow at most 5 feeds' using errcode = '54000';
  end if;
  if exists (
    select 1 from public.channel_feeds f
    where f.channel_id = channel.id and f.url = clean_url
  ) then
    raise exception 'This channel already follows that feed' using errcode = '23505';
  end if;

  hidden := public.integration_make_webhook(channel, 'rss', feed_host);
  insert into public.channel_feeds (circle_id, channel_id, webhook_id, url)
  values (channel.circle_id, channel.id, hidden.id, clean_url)
  returning * into created;

  perform public.write_circle_audit(
    channel.circle_id,
    'feed_add',
    'feed',
    created.id,
    feed_host,
    jsonb_build_object('channel_name', channel.name, 'url', clean_url)
  );
  return public.channel_feed_payload(created);
end;
$$;

create or replace function public.list_channel_feeds(target_channel_id uuid)
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
  if not public.current_user_has_channel_permission(target_channel_id, 'manage_webhooks') then
    raise exception 'Channel not found or caller cannot manage its integrations'
      using errcode = '42501';
  end if;
  return query
  select public.channel_feed_payload(f)
  from public.channel_feeds f
  where f.channel_id = target_channel_id
  order by f.created_at, f.id;
end;
$$;

-- Pauses or resumes a feed. Resuming starts a read right away, forgets the
-- failures, and (when the feed lost the person it posts as) makes the caller
-- that person.
create or replace function public.set_channel_feed_enabled(
  target_feed_id uuid,
  turn_on boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  feed public.channel_feeds%rowtype;
  channel public.circle_channels%rowtype;
  updated public.channel_feeds%rowtype;
begin
  select f.* into feed from public.channel_feeds f where f.id = target_feed_id for update;
  if feed.id is null then
    raise exception 'Feed not found or caller cannot manage it' using errcode = '42501';
  end if;
  channel := public.integration_channel_for_management(feed.channel_id);

  if turn_on then
    if public.integration_creator_problem(feed.webhook_id) is not null then
      if not public.current_user_has_channel_permission(channel.id, 'send_messages') then
        raise exception 'You cannot post in this channel' using errcode = '42501';
      end if;
      update public.circle_webhooks w set created_by = auth.uid() where w.id = feed.webhook_id;
    end if;
    update public.channel_feeds f
    set enabled = true, paused_reason = null, consecutive_failures = 0,
        last_error = null, next_fetch_at = now(), lease_until = null
    where f.id = feed.id
    returning * into updated;
  else
    update public.channel_feeds f
    set enabled = false, paused_reason = null
    where f.id = feed.id
    returning * into updated;
  end if;

  perform public.write_circle_audit(
    feed.circle_id,
    case when turn_on then 'feed_resume' else 'feed_pause' end,
    'feed',
    feed.id,
    lower(substring(feed.url from '^https://([^/?#:]+)')),
    jsonb_build_object('channel_name', channel.name)
  );
  return public.channel_feed_payload(updated);
end;
$$;

create or replace function public.remove_channel_feed(target_feed_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  feed public.channel_feeds%rowtype;
  channel public.circle_channels%rowtype;
begin
  select f.* into feed from public.channel_feeds f where f.id = target_feed_id for update;
  if feed.id is null then
    raise exception 'Feed not found or caller cannot manage it' using errcode = '42501';
  end if;
  channel := public.integration_channel_for_management(feed.channel_id);

  -- The hidden webhook row goes and takes the feed with it; the messages it
  -- posted stay (their webhook_id becomes null).
  delete from public.circle_webhooks w where w.id = feed.webhook_id;

  perform public.write_circle_audit(
    feed.circle_id,
    'feed_remove',
    'feed',
    feed.id,
    lower(substring(feed.url from '^https://([^/?#:]+)')),
    jsonb_build_object('channel_name', channel.name)
  );
end;
$$;

-- --------------------------------------------------------------- GitHub

create or replace function public.channel_github_hook_payload(hook public.channel_github_hooks)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', hook.id,
    'circle_id', hook.circle_id,
    'channel_id', hook.channel_id,
    'label', hook.label,
    'events', to_jsonb(hook.events),
    'enabled', hook.enabled,
    'paused_reason', hook.paused_reason,
    'last_delivery_at', hook.last_delivery_at,
    'last_event', hook.last_event,
    'deliveries_count', hook.deliveries_count,
    'created_at', hook.created_at,
    'created_by', w.created_by,
    'creator_name', case
      when w.created_by is null then null
      else public.circle_member_label(hook.circle_id, w.created_by)
    end
  )
  from public.circle_webhooks w
  where w.id = hook.webhook_id;
$$;

-- The event names of a hook, cleaned: known names only, each once, sorted;
-- null or empty means all of them.
create or replace function public.github_hook_events(event_names text[])
returns text[]
language plpgsql
immutable
set search_path = public
as $$
declare
  known text[] := array['issue_comment', 'issues', 'pull_request', 'push', 'release', 'workflow_run'];
  cleaned text[];
begin
  if event_names is null or cardinality(event_names) = 0 then
    return known;
  end if;
  if exists (select 1 from unnest(event_names) e where e is null or e <> all (known)) then
    raise exception 'Events can be: issue_comment, issues, pull_request, push, release, workflow_run'
      using errcode = '22023';
  end if;
  select array_agg(distinct e order by e) into cleaned from unnest(event_names) e;
  return cleaned;
end;
$$;

revoke execute on function public.channel_github_hook_payload(public.channel_github_hooks) from public, anon, authenticated;
revoke execute on function public.github_hook_events(text[]) from public, anon, authenticated;

create or replace function public.add_github_hook(
  target_channel_id uuid,
  hook_label text,
  event_names text[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype :=
    public.integration_channel_for_management(target_channel_id);
  clean_label text := btrim(coalesce(hook_label, ''));
  clean_events text[] := public.github_hook_events(event_names);
  new_secret text := public.new_webhook_token();
  hidden public.circle_webhooks%rowtype;
  created public.channel_github_hooks%rowtype;
begin
  if char_length(clean_label) not between 1 and 80 then
    raise exception 'The name must be 1 to 80 characters' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('integrations:' || channel.circle_id::text, 0));

  if (select count(*) from public.channel_github_hooks h where h.circle_id = channel.circle_id) >= 10 then
    raise exception 'A circle can have at most 10 GitHub connections' using errcode = '54000';
  end if;
  if (select count(*) from public.channel_github_hooks h where h.channel_id = channel.id) >= 5 then
    raise exception 'A channel can have at most 5 GitHub connections' using errcode = '54000';
  end if;

  hidden := public.integration_make_webhook(channel, 'github', clean_label);
  insert into public.channel_github_hooks (
    circle_id, channel_id, webhook_id, label, events, secret
  )
  values (channel.circle_id, channel.id, hidden.id, clean_label, clean_events, new_secret)
  returning * into created;

  perform public.write_circle_audit(
    channel.circle_id,
    'github_add',
    'github',
    created.id,
    clean_label,
    jsonb_build_object('channel_name', channel.name, 'events', to_jsonb(clean_events))
  );
  return public.channel_github_hook_payload(created)
    || jsonb_build_object('secret', new_secret);
end;
$$;

create or replace function public.list_github_hooks(target_channel_id uuid)
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
  if not public.current_user_has_channel_permission(target_channel_id, 'manage_webhooks') then
    raise exception 'Channel not found or caller cannot manage its integrations'
      using errcode = '42501';
  end if;
  return query
  select public.channel_github_hook_payload(h)
  from public.channel_github_hooks h
  where h.channel_id = target_channel_id
  order by h.created_at, h.id;
end;
$$;

create or replace function public.update_github_hook(
  target_hook_id uuid,
  hook_label text,
  event_names text[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  hook public.channel_github_hooks%rowtype;
  channel public.circle_channels%rowtype;
  clean_label text := btrim(coalesce(hook_label, ''));
  clean_events text[] := public.github_hook_events(event_names);
  updated public.channel_github_hooks%rowtype;
begin
  select h.* into hook from public.channel_github_hooks h where h.id = target_hook_id for update;
  if hook.id is null then
    raise exception 'GitHub connection not found or caller cannot manage it' using errcode = '42501';
  end if;
  channel := public.integration_channel_for_management(hook.channel_id);
  if char_length(clean_label) not between 1 and 80 then
    raise exception 'The name must be 1 to 80 characters' using errcode = '22023';
  end if;

  update public.channel_github_hooks h
  set label = clean_label, events = clean_events
  where h.id = hook.id
  returning * into updated;
  update public.circle_webhooks w set name = clean_label where w.id = hook.webhook_id;

  perform public.write_circle_audit(
    hook.circle_id,
    'github_update',
    'github',
    hook.id,
    clean_label,
    jsonb_build_object(
      'channel_name', channel.name,
      'events', to_jsonb(clean_events)
    ) || case
      when clean_label <> hook.label
        then jsonb_build_object('label', jsonb_build_object('old', hook.label, 'new', clean_label))
      else '{}'::jsonb
    end
  );
  return public.channel_github_hook_payload(updated);
end;
$$;

-- A new secret; the old one stops working at once. Returned once.
create or replace function public.regenerate_github_secret(target_hook_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  hook public.channel_github_hooks%rowtype;
  channel public.circle_channels%rowtype;
  new_secret text := public.new_webhook_token();
  updated public.channel_github_hooks%rowtype;
begin
  select h.* into hook from public.channel_github_hooks h where h.id = target_hook_id for update;
  if hook.id is null then
    raise exception 'GitHub connection not found or caller cannot manage it' using errcode = '42501';
  end if;
  channel := public.integration_channel_for_management(hook.channel_id);

  update public.channel_github_hooks h set secret = new_secret
  where h.id = hook.id
  returning * into updated;

  perform public.write_circle_audit(
    hook.circle_id, 'github_regenerate', 'github', hook.id, hook.label,
    jsonb_build_object('channel_name', channel.name)
  );
  return public.channel_github_hook_payload(updated)
    || jsonb_build_object('secret', new_secret);
end;
$$;

create or replace function public.set_github_hook_enabled(
  target_hook_id uuid,
  turn_on boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  hook public.channel_github_hooks%rowtype;
  channel public.circle_channels%rowtype;
  updated public.channel_github_hooks%rowtype;
begin
  select h.* into hook from public.channel_github_hooks h where h.id = target_hook_id for update;
  if hook.id is null then
    raise exception 'GitHub connection not found or caller cannot manage it' using errcode = '42501';
  end if;
  channel := public.integration_channel_for_management(hook.channel_id);

  if turn_on then
    if public.integration_creator_problem(hook.webhook_id) is not null then
      if not public.current_user_has_channel_permission(channel.id, 'send_messages') then
        raise exception 'You cannot post in this channel' using errcode = '42501';
      end if;
      update public.circle_webhooks w set created_by = auth.uid() where w.id = hook.webhook_id;
    end if;
    update public.channel_github_hooks h
    set enabled = true, paused_reason = null
    where h.id = hook.id
    returning * into updated;
  else
    update public.channel_github_hooks h
    set enabled = false, paused_reason = null
    where h.id = hook.id
    returning * into updated;
  end if;

  perform public.write_circle_audit(
    hook.circle_id,
    case when turn_on then 'github_resume' else 'github_pause' end,
    'github', hook.id, hook.label,
    jsonb_build_object('channel_name', channel.name)
  );
  return public.channel_github_hook_payload(updated);
end;
$$;

create or replace function public.remove_github_hook(target_hook_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  hook public.channel_github_hooks%rowtype;
  channel public.circle_channels%rowtype;
begin
  select h.* into hook from public.channel_github_hooks h where h.id = target_hook_id for update;
  if hook.id is null then
    raise exception 'GitHub connection not found or caller cannot manage it' using errcode = '42501';
  end if;
  channel := public.integration_channel_for_management(hook.channel_id);

  delete from public.circle_webhooks w where w.id = hook.webhook_id;

  perform public.write_circle_audit(
    hook.circle_id, 'github_remove', 'github', hook.id, hook.label,
    jsonb_build_object('channel_name', channel.name)
  );
end;
$$;

do $$
declare
  name text;
begin
  foreach name in array array[
    'add_channel_feed(uuid, text)',
    'list_channel_feeds(uuid)',
    'set_channel_feed_enabled(uuid, boolean)',
    'remove_channel_feed(uuid)',
    'add_github_hook(uuid, text, text[])',
    'list_github_hooks(uuid)',
    'update_github_hook(uuid, text, text[])',
    'regenerate_github_secret(uuid)',
    'set_github_hook_enabled(uuid, boolean)',
    'remove_github_hook(uuid)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon', name);
    execute format('grant execute on function public.%s to authenticated', name);
  end loop;
end;
$$;
