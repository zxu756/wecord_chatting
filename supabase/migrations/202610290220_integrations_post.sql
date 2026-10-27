-- Rich webhooks, RSS feeds and GitHub (roadmap I6), part 3 of 4: posting.
--
-- integration_post is the one place a webhook-like message is written. It
-- does what post_webhook_message (202610130024, left as it was) does after
-- the token check - the creator must still be a member who can manage
-- webhooks and send messages, 30 messages per webhook and minute (WH429), a
-- message from the creator marked with webhook_id, name and picture - and
-- adds cards (messages.embeds, part 1), K1 (nothing in a suspended circle or
-- from a suspended person) and, for text that comes from other people's
-- servers, AutoMod's blocking keyword rules (integration_text_blocked): a
-- blocked item is dropped quietly.
--
-- Callers (all service role, the Edge Functions):
--   post_webhook_message_rich  the `webhook` function: token, text and/or
--                              cards, link buttons;
--   post_feed_items            the `feed-fetch` function: new feed items;
--   post_github_event          the `github` function: one signed delivery.
-- A text-only call of post_webhook_message_rich is the same as the old
-- function (the old one stays for anyone calling it).
--
-- Error codes, mapped to HTTP by the Edge Functions: P0002 unknown, 28000
-- wrong token, 22023 bad content, 42501 the creator can no longer post or the
-- circle is taken down, WH429 too many messages.

-- AutoMod's blocking keyword and regex rules of the circle, applied to text
-- that no member wrote: the rules' exempt roles do not matter (nobody holds a
-- role here), the exempt channels do.
create or replace function public.integration_text_blocked(
  target_conversation_id uuid,
  message_text text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  channel_id uuid := public.conversation_circle_channel_id(target_conversation_id);
  body_text text := coalesce(message_text, '');
begin
  if channel_id is null or body_text = '' then
    return false;
  end if;
  return exists (
    select 1
    from public.circle_channels cc
    join public.circle_automod_rules r on r.circle_id = cc.circle_id
    where cc.id = channel_id
      and r.enabled
      and r.kind = 'keyword'
      and r.block_message
      and not (cc.id = any (r.exempt_channel_ids))
      and (
        exists (
          select 1 from unnest(r.keywords) k
          where body_text ~* public.circle_automod_keyword_pattern(k)
        )
        or exists (
          select 1 from unnest(r.regex_patterns) p where body_text ~* p
        )
      )
  );
exception when others then
  return false;
end;
$$;

revoke execute on function public.integration_text_blocked(uuid, text) from public, anon, authenticated;

-- Writes one webhook message. [cleaned_embeds] went through
-- normalize_message_embeds (or is null). Returns the message's id, or null
-- when [screen_text] is set and AutoMod blocks the text.
create or replace function public.integration_post(
  target_webhook_id uuid,
  content text,
  username text,
  avatar_url text,
  cleaned_embeds jsonb,
  screen_text boolean
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
  message_body text;
  stored_embeds jsonb := cleaned_embeds;
  created_message_id uuid;
begin
  select w.* into webhook from public.circle_webhooks w where w.id = target_webhook_id;
  if webhook.id is null then
    raise exception 'Unknown webhook' using errcode = 'P0002';
  end if;

  if trimmed_content = '' and cleaned_embeds is null then
    raise exception 'A message needs text or cards' using errcode = '22023';
  end if;
  if char_length(trimmed_content) > 2000 then
    raise exception 'Content must be at most 2000 characters' using errcode = '22023';
  end if;
  if trimmed_username is not null and char_length(trimmed_username) > 80 then
    raise exception 'Username must be at most 80 characters' using errcode = '22023';
  end if;
  if trimmed_avatar_url is not null
    and (
      trimmed_avatar_url !~* '^https?://[^[:space:]]+$'
      or char_length(trimmed_avatar_url) > 2048
    )
  then
    raise exception 'Avatar URL must be an http(s) URL' using errcode = '22023';
  end if;

  select cc.* into channel from public.circle_channels cc where cc.id = webhook.channel_id;

  -- K1: nothing is posted into a suspended circle, or by a suspended person.
  if public.circle_is_suspended(webhook.circle_id)
    or (webhook.created_by is not null and public.is_user_suspended(webhook.created_by))
  then
    raise exception 'The webhook''s creator can no longer post in this channel'
      using errcode = '42501';
  end if;

  if webhook.created_by is null
    or not exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id = channel.conversation_id
        and cm.user_id = webhook.created_by
    )
    or not public.circle_channel_has_permission(channel.id, webhook.created_by, 'manage_webhooks')
    or not public.circle_channel_has_permission(channel.id, webhook.created_by, 'send_messages')
  then
    raise exception 'The webhook''s creator can no longer post in this channel'
      using errcode = '42501';
  end if;

  if screen_text and public.integration_text_blocked(
    channel.conversation_id,
    concat_ws(E'\n', nullif(trimmed_content, ''), public.message_embeds_text(cleaned_embeds))
  ) then
    return null;
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

  if trimmed_content <> '' then
    message_body := trimmed_content;
  else
    -- Only cards: a one-line summary is the text for notifications, the chat
    -- list and search, and the app draws just the cards.
    message_body := public.message_embeds_summary(cleaned_embeds);
    stored_embeds := stored_embeds || '{"summary": true}'::jsonb;
  end if;

  insert into public.messages (
    conversation_id, sender_id, type, body,
    webhook_id, webhook_name, webhook_avatar_url, embeds
  )
  values (
    channel.conversation_id,
    webhook.created_by,
    'text',
    message_body,
    webhook.id,
    coalesce(trimmed_username, webhook.name),
    coalesce(trimmed_avatar_url, webhook.avatar_url),
    stored_embeds
  )
  returning id into created_message_id;

  update public.circle_webhooks w set last_used_at = now() where w.id = webhook.id;
  return created_message_id;
end;
$$;

revoke execute on function public.integration_post(uuid, text, text, text, jsonb, boolean) from public, anon, authenticated;

-- ------------------------------------------------------- incoming, rich

create or replace function public.post_webhook_message_rich(
  target_webhook_id uuid,
  webhook_token text,
  content text default null,
  username text default null,
  avatar_url text default null,
  embeds jsonb default null,
  components jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  webhook public.circle_webhooks%rowtype;
begin
  select w.* into webhook from public.circle_webhooks w where w.id = target_webhook_id;
  -- A feed's or a hook's hidden row has no URL anybody can use.
  if webhook.id is null or webhook.kind <> 'incoming' then
    raise exception 'Unknown webhook' using errcode = 'P0002';
  end if;
  if webhook.token_hash <> public.webhook_token_hash(webhook_token) then
    raise exception 'Invalid webhook token' using errcode = '28000';
  end if;

  return public.integration_post(
    webhook.id,
    content,
    username,
    avatar_url,
    public.normalize_message_embeds(embeds, components),
    false
  );
end;
$$;

revoke execute on function public.post_webhook_message_rich(uuid, text, text, text, text, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.post_webhook_message_rich(uuid, text, text, text, text, jsonb, jsonb) to service_role;

-- ----------------------------------------------------------- the cards of
-- text from other servers

-- Makes a card built from outside text fit the rules instead of refusing it:
-- texts are stripped and cut, an address that is not an https website is
-- dropped, a colour that is not one is dropped, at most 8 fields. Anything
-- else is left out. The result still goes through normalize_message_embeds.
create or replace function public.integration_card(raw jsonb)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  card jsonb := '{}'::jsonb;
  piece text;
  field jsonb;
  fields_out jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(raw) <> 'object' then
    return null;
  end if;

  piece := public.embeds_strip_text(raw->>'title', 120);
  if piece <> '' then card := card || jsonb_build_object('title', piece); end if;
  piece := public.embeds_strip_text(raw->>'description', 1500, true);
  if piece <> '' then card := card || jsonb_build_object('description', piece); end if;
  if public.components_https_url_ok(raw->>'url') then
    card := card || jsonb_build_object('url', raw->>'url');
  end if;
  if (raw->>'color') ~ '^#[0-9a-fA-F]{6}$' then
    card := card || jsonb_build_object('color', lower(raw->>'color'));
  end if;

  piece := public.embeds_strip_text(raw#>>'{author,name}', 60);
  if piece <> '' then
    card := card || jsonb_build_object('author', jsonb_strip_nulls(jsonb_build_object(
      'name', piece,
      'url', case when public.components_https_url_ok(raw#>>'{author,url}')
        then raw#>>'{author,url}' end
    )));
  end if;

  if jsonb_typeof(raw->'fields') = 'array' then
    for field in select value from jsonb_array_elements(raw->'fields') limit 8 loop
      if jsonb_typeof(field) = 'object'
        and public.embeds_strip_text(field->>'name', 60) <> ''
        and public.embeds_strip_text(field->>'value', 300, true) <> ''
      then
        fields_out := fields_out || jsonb_build_array(jsonb_build_object(
          'name', public.embeds_strip_text(field->>'name', 60),
          'value', public.embeds_strip_text(field->>'value', 300, true),
          'inline', coalesce(field->>'inline' = 'true', false)
        ));
      end if;
    end loop;
    if jsonb_array_length(fields_out) > 0 then
      card := card || jsonb_build_object('fields', fields_out);
    end if;
  end if;

  piece := public.embeds_strip_text(raw#>>'{footer,text}', 100);
  if piece <> '' then
    card := card || jsonb_build_object('footer', jsonb_build_object('text', piece));
  end if;

  if (raw->>'timestamp') ~ '^\d{4}-\d{2}-\d{2}([T ][0-9:.]+)?(Z|[+-]\d{2}:?\d{2})?$' then
    begin
      card := card || jsonb_build_object(
        'timestamp',
        to_char((raw->>'timestamp')::timestamptz at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
      );
    exception when others then
      null;
    end;
  end if;

  -- An address or a colour alone is not something to show.
  if not (card ? 'title' or card ? 'description' or card ? 'fields' or card ? 'author') then
    return null;
  end if;
  return card;
end;
$$;

revoke execute on function public.integration_card(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------- feeds

-- Feeds that are due: at most [max_count], at most one per web site (so a
-- site is not hit by several of our requests at once), none in a suspended
-- circle, none whose poster can no longer post (those pause themselves,
-- here). A claimed feed is left alone for 5 minutes, so a read that never
-- finished comes back, and two wake-ups never read the same feed.
create or replace function public.claim_channel_feeds(max_count integer default 10)
returns table (
  feed_id uuid,
  url text,
  etag text,
  last_modified text,
  seen_keys text[],
  initialized boolean
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  candidate public.channel_feeds%rowtype;
  problem text;
begin
  for candidate in
    select f.*
    from public.channel_feeds f
    where f.id in (
      select distinct on (lower(substring(d.url from '^https://([^/?#]+)'))) d.id
      from public.channel_feeds d
      join public.circles c on c.id = d.circle_id
      where d.enabled
        and d.next_fetch_at <= now()
        and (d.lease_until is null or d.lease_until < now())
        and c.disabled_mode is distinct from 'suspend'
      order by lower(substring(d.url from '^https://([^/?#]+)')), d.next_fetch_at
    )
    order by f.next_fetch_at
    limit greatest(least(coalesce(max_count, 10), 20), 1)
    for update skip locked
  loop
    problem := public.integration_creator_problem(candidate.webhook_id);
    if problem is not null then
      update public.channel_feeds f
      set enabled = false, paused_reason = problem, lease_until = null
      where f.id = candidate.id;
      continue;
    end if;

    update public.channel_feeds f
    set lease_until = now() + interval '5 minutes'
    where f.id = candidate.id;

    feed_id := candidate.id;
    url := candidate.url;
    etag := candidate.etag;
    last_modified := candidate.last_modified;
    seen_keys := candidate.seen_keys;
    initialized := candidate.initialized;
    return next;
  end loop;
end;
$$;

-- Records how a read went. A good read (or "not modified") keeps what was
-- learnt - the feed's title (also the name its messages carry), the cache
-- headers, the items seen - and schedules the next read 15 to 17 minutes
-- away. A failed read waits 30 minutes, then an hour, 2, 4, 6 hours; a feed
-- that failed 8 times in a row, or that is plainly not usable ([permanent]:
-- not a feed, an address that is not public), pauses itself and says why in
-- last_error.
create or replace function public.finish_channel_feed(
  target_feed_id uuid,
  fetch_ok boolean,
  http_status integer,
  error_code text,
  new_etag text,
  new_last_modified text,
  feed_title text,
  new_seen text[],
  permanent boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  feed public.channel_feeds%rowtype;
  clean_title text := public.embeds_strip_text(feed_title, 80);
  failures integer;
begin
  select f.* into feed from public.channel_feeds f where f.id = target_feed_id for update;
  if feed.id is null then
    return;
  end if;

  if fetch_ok then
    update public.channel_feeds f
    set consecutive_failures = 0,
        last_error = null,
        last_status = http_status,
        last_fetched_at = now(),
        last_success_at = now(),
        etag = left(new_etag, 300),
        last_modified = left(new_last_modified, 100),
        title = coalesce(nullif(clean_title, ''), f.title),
        seen_keys = case
          when new_seen is null then f.seen_keys
          else new_seen[1:200]
        end,
        initialized = true,
        next_fetch_at = now() + interval '15 minutes' + random() * interval '2 minutes',
        lease_until = null
    where f.id = feed.id;
    if clean_title <> '' then
      update public.circle_webhooks w set name = clean_title where w.id = feed.webhook_id;
    end if;
    return;
  end if;

  failures := feed.consecutive_failures + 1;
  update public.channel_feeds f
  set consecutive_failures = failures,
      last_error = left(regexp_replace(coalesce(error_code, 'error'), '[^A-Za-z0-9_ .-]', '', 'g'), 60),
      last_status = http_status,
      last_fetched_at = now(),
      next_fetch_at = now() + least(15 * power(2, least(failures, 5)), 360)::integer * interval '1 minute',
      lease_until = null,
      enabled = case when permanent or failures >= 8 then false else f.enabled end,
      paused_reason = case when permanent or failures >= 8 then 'failing' else f.paused_reason end
  where f.id = feed.id;
end;
$$;

-- Posts new feed items (oldest first, at most 5 a read, at most 48 a day per
-- feed) as cards. [feed_items] is a list of {title, link, summary,
-- published}, already read out of the feed; whatever comes in is stripped and
-- cut to fit (integration_card), an item that still does not fit is skipped,
-- AutoMod's blocking keywords drop an item quietly, and a poster who can no
-- longer post pauses the feed. Returns {posted, skipped}.
create or replace function public.post_feed_items(
  target_feed_id uuid,
  feed_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  feed public.channel_feeds%rowtype;
  item jsonb;
  card jsonb;
  cleaned jsonb;
  result uuid;
  posted integer := 0;
  skipped integer := 0;
  today date := (now() at time zone 'UTC')::date;
  used_today integer;
  label text;
  problem text;
begin
  select f.* into feed from public.channel_feeds f where f.id = target_feed_id for update;
  if feed.id is null then
    raise exception 'Unknown feed' using errcode = 'P0002';
  end if;
  if not feed.enabled or jsonb_typeof(feed_items) is distinct from 'array' then
    return jsonb_build_object('posted', 0, 'skipped', 0);
  end if;

  used_today := case when feed.window_day = today then feed.window_count else 0 end;
  label := coalesce(feed.title, lower(substring(feed.url from '^https://([^/?#:]+)')));

  for item in select value from jsonb_array_elements(feed_items) limit 5 loop
    if used_today + posted >= 48 then
      skipped := skipped + 1;
      continue;
    end if;
    card := public.integration_card(jsonb_build_object(
      'title', item->>'title',
      'url', item->>'link',
      'description', item->>'summary',
      'color', '#ee802f',
      'footer', jsonb_build_object('text', label),
      'timestamp', item->>'published'
    ));
    if card is null then
      skipped := skipped + 1;
      continue;
    end if;

    begin
      cleaned := public.normalize_message_embeds(jsonb_build_array(card), null);
      result := public.integration_post(feed.webhook_id, '', null, null, cleaned, true);
      if result is null then
        skipped := skipped + 1;
      else
        posted := posted + 1;
      end if;
    exception when others then
      if sqlstate = 'WH429' then
        skipped := skipped + 1;
        exit;
      elsif sqlstate = '42501' then
        problem := public.integration_creator_problem(feed.webhook_id);
        if problem is not null then
          update public.channel_feeds f
          set enabled = false, paused_reason = problem
          where f.id = feed.id;
        end if;
        exit;
      else
        skipped := skipped + 1;
      end if;
    end;
  end loop;

  update public.channel_feeds f
  set items_posted = f.items_posted + posted,
      last_item_at = case when posted > 0 then now() else f.last_item_at end,
      window_day = today,
      window_count = used_today + posted
  where f.id = feed.id;

  return jsonb_build_object('posted', posted, 'skipped', skipped);
end;
$$;

-- --------------------------------------------------------------- GitHub

-- What the github function needs to check a delivery: the secret and the
-- settings. Service role only; the secret is never returned to a client.
create or replace function public.github_hook_for_delivery(target_hook_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', h.id,
    'secret', h.secret,
    'enabled', h.enabled,
    'events', to_jsonb(h.events),
    'label', h.label
  )
  from public.channel_github_hooks h
  where h.id = target_hook_id;
$$;

-- One delivery that passed the signature check. [card] is what the function
-- made of the event. Returns {status}: posted | duplicate | ignored (an event
-- this hook does not send) | paused | blocked (AutoMod). The delivery id is
-- remembered for 10 minutes so a request sent twice posts once.
create or replace function public.post_github_event(
  target_hook_id uuid,
  delivery text,
  event_name text,
  card jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  hook public.channel_github_hooks%rowtype;
  inserted integer;
  problem text;
  cleaned jsonb;
  made jsonb := public.integration_card(card);
  result uuid;
begin
  select h.* into hook from public.channel_github_hooks h where h.id = target_hook_id for update;
  if hook.id is null then
    raise exception 'Unknown GitHub connection' using errcode = 'P0002';
  end if;
  if not hook.enabled then
    return jsonb_build_object('status', 'paused');
  end if;
  if event_name is null or event_name <> all (hook.events) then
    return jsonb_build_object('status', 'ignored');
  end if;
  if made is null then
    return jsonb_build_object('status', 'ignored');
  end if;

  delete from public.github_deliveries d
  where d.hook_id = hook.id and d.received_at < now() - interval '10 minutes';
  insert into public.github_deliveries (hook_id, delivery_id)
  values (hook.id, left(coalesce(nullif(btrim(delivery), ''), gen_random_uuid()::text), 80))
  on conflict do nothing;
  get diagnostics inserted = row_count;
  if inserted = 0 then
    return jsonb_build_object('status', 'duplicate');
  end if;

  problem := public.integration_creator_problem(hook.webhook_id);
  if problem is not null then
    update public.channel_github_hooks h
    set enabled = false, paused_reason = problem
    where h.id = hook.id;
    return jsonb_build_object('status', 'paused');
  end if;

  cleaned := public.normalize_message_embeds(jsonb_build_array(made), null);
  result := public.integration_post(hook.webhook_id, '', hook.label, null, cleaned, true);

  update public.channel_github_hooks h
  set last_delivery_at = now(),
      last_event = event_name,
      deliveries_count = h.deliveries_count + 1
  where h.id = hook.id;

  return jsonb_build_object('status', case when result is null then 'blocked' else 'posted' end);
end;
$$;

do $$
declare
  name text;
begin
  foreach name in array array[
    'claim_channel_feeds(integer)',
    'finish_channel_feed(uuid, boolean, integer, text, text, text, text, text[], boolean)',
    'post_feed_items(uuid, jsonb)',
    'github_hook_for_delivery(uuid)',
    'post_github_event(uuid, text, text, jsonb)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', name);
    execute format('grant execute on function public.%s to service_role', name);
  end loop;
end;
$$;

-- ---------------------------------------------------- waking, cron, purge

-- Wakes the feed-fetch function the way I2 wakes bot-events: with the Vault
-- secrets wecord_functions_url and wecord_dispatch_secret, the secret as the
-- bearer token. Quietly does nothing where Vault or pg_net, or a secret, is
-- missing. run_later_dispatch() is not touched: this has its own cron job.
create or replace function public.wake_feed_fetch()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  functions_url text;
  dispatch_secret text;
begin
  select d.decrypted_secret into functions_url
  from vault.decrypted_secrets d where d.name = 'wecord_functions_url';
  select d.decrypted_secret into dispatch_secret
  from vault.decrypted_secrets d where d.name = 'wecord_dispatch_secret';

  if functions_url is null or dispatch_secret is null then
    return;
  end if;

  perform net.http_post(
    url := rtrim(functions_url, '/') || '/feed-fetch',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || dispatch_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 5000
  );
exception when others then
  null;
end;
$$;

-- Wakes the function when a feed is due.
create or replace function public.wake_feed_fetch_if_due()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.channel_feeds f
    where f.enabled
      and f.next_fetch_at <= now()
      and (f.lease_until is null or f.lease_until < now())
  ) then
    perform public.wake_feed_fetch();
  end if;
end;
$$;

-- GitHub deliveries older than a day.
create or replace function public.purge_integrations()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.github_deliveries d where d.received_at < now() - interval '1 day';
end;
$$;

revoke execute on function public.wake_feed_fetch() from public, anon, authenticated;
revoke execute on function public.wake_feed_fetch_if_due() from public, anon, authenticated;
revoke execute on function public.purge_integrations() from public, anon, authenticated;
grant execute on function public.wake_feed_fetch() to service_role;
grant execute on function public.wake_feed_fetch_if_due() to service_role;
grant execute on function public.purge_integrations() to service_role;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.unschedule(jobid)
    from cron.job
    where jobname in ('wecord-feed-fetch', 'wecord-integrations-purge');
    -- Every 5 minutes it looks for feeds that are due; a feed is read at most
    -- every 15 minutes (finish_channel_feed).
    perform cron.schedule(
      'wecord-feed-fetch',
      '*/5 * * * *',
      'select public.wake_feed_fetch_if_due()'
    );
    perform cron.schedule(
      'wecord-integrations-purge',
      '41 * * * *',
      'select public.purge_integrations()'
    );
  else
    raise notice 'pg_cron is not available: call wake_feed_fetch_if_due() and purge_integrations() from another scheduler';
  end if;
exception when others then
  raise notice 'Could not schedule the integration jobs with pg_cron: %', sqlerrm;
end;
$$;
