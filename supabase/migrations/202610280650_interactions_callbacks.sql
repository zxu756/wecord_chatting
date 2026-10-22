-- Interactive components and interaction callbacks (roadmap I1), part 5 of 6:
-- sending a press to the bot's own server.
--
-- A bot can always poll (GET /interactions, part 4). A bot that has a server
-- may also ask for a callback: each interaction (a slash command or a press
-- on a component) is then POSTed to its address as it happens. The
-- `bot-callbacks` Edge Function does the sending; this part is the settings,
-- the queue and the rules.
--
-- * The address: https only, a real host name (no IP address, no
--   "localhost", no .local / .internal / .lan ... names, no well-known names
--   that point at inner addresses), the default port, at most 500 characters
--   (bot_callback_url_problem). That is the first check; the function checks
--   again before every send by looking the name up and refusing any private,
--   loopback, link-local, multicast or reserved address, and does not follow
--   redirects (supabase/functions/bot-callbacks/ssrf.ts).
-- * The secret: 64 hex characters made by the server, shown once when the
--   callback is set or the secret is rotated, kept in bot_callbacks (closed to
--   clients). Every request carries X-WeCord-Timestamp (seconds) and
--   X-WeCord-Signature: v1=<hex HMAC-SHA256 of "<timestamp>.<body>">. The bot
--   rejects a timestamp more than five minutes old and the same interaction id
--   twice (docs/bot-api.md).
-- * Delivery: the interaction is queued by a trigger when the bot has an
--   enabled callback (delivery_state 'queued'), the function is woken at once
--   (wake_bot_callbacks, the way the project wakes its functions: Vault
--   secrets, DISPATCH_SECRET as the bearer token), claims up to 20 at a time
--   (claim_bot_callbacks), sends with a 5 second timeout and reports
--   (finish_bot_callback). A failed send is tried again after 5 seconds,
--   30 seconds and 2 minutes, four tries at most; then the press goes back to
--   polling (state 'failed'), so nothing is lost while it can still be
--   answered. 20 presses in a row that failed for good turn the callback
--   off (enabled = false); the managers see why.
-- * A separate pg_cron job wakes the function every minute when something
--   is due (retries; run_later_dispatch is not touched), and an hourly one
--   removes interactions older than 7 days and expired private replies.
-- * Managers (manage_circle) set, rotate and clear the callback and read its
--   state; each change is in the circle's audit log (bot_callback_set,
--   bot_callback_rotate, bot_callback_clear). The secret is never readable
--   again.

create or replace function public.bot_callback_url_problem(callback_url text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when callback_url is null or btrim(callback_url) = '' then 'The address is empty'
    when callback_url <> btrim(callback_url) then 'The address has spaces around it'
    when char_length(callback_url) > 500 then 'The address is too long'
    when callback_url !~* '^https://' then 'The address must start with https://'
    when not public.components_https_url_ok(callback_url)
      then 'The address must be a website name with https on the usual port (no IP addresses, no inner names)'
    when callback_url ~* '^https://[^/?#]*(\.|^)(nip\.io|sslip\.io|xip\.io|localtest\.me|lvh\.me|traefik\.me)(:443)?([/?#]|$)'
      then 'That name points at the machine it is called from'
    else null
  end;
$$;

revoke execute on function public.bot_callback_url_problem(text) from public, anon, authenticated;

create or replace function public.bot_callback_state(target_bot_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select jsonb_build_object(
      'url', c.url,
      'enabled', c.enabled,
      'consecutive_failures', c.consecutive_failures,
      'last_status', c.last_status,
      'last_error', c.last_error,
      'last_success_at', c.last_success_at,
      'last_failure_at', c.last_failure_at
    )
    from public.bot_callbacks c
    where c.bot_id = target_bot_id
  ), jsonb_build_object('url', null, 'enabled', false));
$$;

revoke execute on function public.bot_callback_state(uuid) from public, anon, authenticated;

-- The callback of a bot as its managers see it (never the secret).
create or replace function public.get_bot_callback(target_bot_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.circle_bot_for_management(target_bot_id);
begin
  return public.bot_callback_state(bot.id);
end;
$$;

-- Sets the address. The first time (or after clearing) a secret is made and
-- returned once; changing only the address keeps the secret and returns none.
create or replace function public.set_bot_callback(
  target_bot_id uuid,
  callback_url text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.circle_bot_for_management(target_bot_id);
  problem text := public.bot_callback_url_problem(callback_url);
  new_secret text;
  existing public.bot_callbacks%rowtype;
begin
  if problem is not null then
    raise exception '%', problem using errcode = '22023';
  end if;

  select c.* into existing from public.bot_callbacks c where c.bot_id = bot.id;

  if existing.bot_id is null then
    new_secret := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.bot_callbacks (bot_id, url, secret)
    values (bot.id, callback_url, new_secret);
  else
    update public.bot_callbacks c
    set
      url = callback_url,
      enabled = true,
      consecutive_failures = 0,
      last_error = null,
      updated_at = now()
    where c.bot_id = bot.id;
  end if;

  perform public.write_circle_audit(
    bot.circle_id,
    'bot_callback_set',
    'bot',
    bot.id,
    bot.name,
    jsonb_build_object('host', substring(callback_url from '^https://([^/?#:]+)'))
  );

  return public.bot_callback_state(bot.id)
    || case when new_secret is not null then jsonb_build_object('secret', new_secret) else '{}'::jsonb end;
end;
$$;

create or replace function public.rotate_bot_callback_secret(target_bot_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.circle_bot_for_management(target_bot_id);
  new_secret text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  update public.bot_callbacks c
  set secret = new_secret, updated_at = now()
  where c.bot_id = bot.id;

  if not found then
    raise exception 'This bot has no callback' using errcode = 'P0002';
  end if;

  perform public.write_circle_audit(
    bot.circle_id, 'bot_callback_rotate', 'bot', bot.id, bot.name, '{}'::jsonb
  );

  return public.bot_callback_state(bot.id) || jsonb_build_object('secret', new_secret);
end;
$$;

-- Turns the callback off and forgets it: what was queued goes back to polling.
create or replace function public.clear_bot_callback(target_bot_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.circle_bot_for_management(target_bot_id);
begin
  delete from public.bot_callbacks c where c.bot_id = bot.id;

  if found then
    update public.bot_interactions bi
    set delivery_state = 'none'
    where bi.bot_id = bot.id
      and bi.delivery_state in ('queued', 'sending');

    perform public.write_circle_audit(
      bot.circle_id, 'bot_callback_clear', 'bot', bot.id, bot.name, '{}'::jsonb
    );
  end if;
end;
$$;

revoke execute on function public.get_bot_callback(uuid) from public, anon;
revoke execute on function public.set_bot_callback(uuid, text) from public, anon;
revoke execute on function public.rotate_bot_callback_secret(uuid) from public, anon;
revoke execute on function public.clear_bot_callback(uuid) from public, anon;
grant execute on function public.get_bot_callback(uuid) to authenticated;
grant execute on function public.set_bot_callback(uuid, text) to authenticated;
grant execute on function public.rotate_bot_callback_secret(uuid) to authenticated;
grant execute on function public.clear_bot_callback(uuid) to authenticated;

-- ------------------------------------------------------------------- the queue

create or replace function public.bot_interactions_route_delivery()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.bot_callbacks c
    where c.bot_id = new.bot_id and c.enabled
  ) then
    new.delivery_state := 'queued';
    new.next_attempt_at := now();
  end if;
  return new;
end;
$$;

-- Wakes the bot-callbacks function the way the rest of the project wakes its
-- functions (wake_expire_stories, 202610240240): with the Vault secrets
-- wecord_functions_url and wecord_dispatch_secret, the secret as the bearer
-- token. Quietly does nothing where Vault or pg_net, or a secret, is missing.
create or replace function public.wake_bot_callbacks()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  functions_url text;
  dispatch_secret text;
begin
  select d.decrypted_secret
  into functions_url
  from vault.decrypted_secrets d
  where d.name = 'wecord_functions_url';
  select d.decrypted_secret
  into dispatch_secret
  from vault.decrypted_secrets d
  where d.name = 'wecord_dispatch_secret';

  if functions_url is null or dispatch_secret is null then
    return;
  end if;

  perform net.http_post(
    url := rtrim(functions_url, '/') || '/bot-callbacks',
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

create or replace function public.bot_interactions_wake_callbacks()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.wake_bot_callbacks();
  return null;
end;
$$;

revoke execute on function public.bot_interactions_route_delivery() from public, anon, authenticated;
revoke execute on function public.bot_interactions_wake_callbacks() from public, anon, authenticated;
revoke execute on function public.wake_bot_callbacks() from public, anon, authenticated;
grant execute on function public.wake_bot_callbacks() to service_role;

drop trigger if exists bot_interactions_route_delivery on public.bot_interactions;
create trigger bot_interactions_route_delivery
  before insert on public.bot_interactions
  for each row execute function public.bot_interactions_route_delivery();

drop trigger if exists bot_interactions_wake_callbacks on public.bot_interactions;
create trigger bot_interactions_wake_callbacks
  after insert on public.bot_interactions
  for each row
  when (new.delivery_state = 'queued')
  execute function public.bot_interactions_wake_callbacks();

-- For the bot-callbacks function (service role): takes up to [max_count] due
-- interactions with their address and secret. A claim is a 30 second lease: if
-- the function dies, the interaction is due again after that.
create or replace function public.claim_bot_callbacks(max_count integer default 20)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  -- Answered meanwhile: nothing more to send.
  update public.bot_interactions bi
  set delivery_state = 'delivered'
  where bi.delivery_state in ('queued', 'sending')
    and bi.responded_at is not null;

  -- No longer answerable, or tried enough: back to polling.
  update public.bot_interactions bi
  set delivery_state = 'failed',
      delivery_error = coalesce(bi.delivery_error, 'expired')
  where bi.delivery_state in ('queued', 'sending')
    and (
      bi.expires_at <= now()
      or (bi.delivery_state = 'sending' and bi.next_attempt_at <= now() and bi.delivery_attempts >= 4)
    );

  -- The callback was turned off: back to polling.
  update public.bot_interactions bi
  set delivery_state = 'none'
  where bi.delivery_state in ('queued', 'sending')
    and not exists (
      select 1 from public.bot_callbacks c
      where c.bot_id = bi.bot_id and c.enabled
    );

  with picked as (
    select bi.id
    from public.bot_interactions bi
    join public.bot_callbacks c on c.bot_id = bi.bot_id and c.enabled
    where bi.delivery_state in ('queued', 'sending')
      and bi.next_attempt_at <= now()
      and bi.expires_at > now()
      and bi.responded_at is null
      and bi.delivery_attempts < 4
    order by bi.next_attempt_at
    limit least(greatest(coalesce(max_count, 20), 1), 50)
    for update of bi skip locked
  ),
  claimed as (
    update public.bot_interactions bi
    set
      delivery_state = 'sending',
      delivery_attempts = bi.delivery_attempts + 1,
      next_attempt_at = now() + interval '30 seconds'
    from picked
    where bi.id = picked.id
    returning bi.*
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'interaction_id', c.id,
      'bot_id', c.bot_id,
      'circle_id', c.circle_id,
      'attempt', c.delivery_attempts,
      'url', cb.url,
      'secret', cb.secret,
      'payload', public.bot_interaction_payload(c)
    )
    order by c.created_at
  ), '[]'::jsonb)
  into result
  from claimed c
  join public.bot_callbacks cb on cb.bot_id = c.bot_id;

  return result;
end;
$$;

-- The function reports what happened to one send.
create or replace function public.finish_bot_callback(
  target_interaction_id uuid,
  delivered boolean,
  http_status integer default null,
  error_text text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  row_state public.bot_interactions%rowtype;
  final_state text;
begin
  select bi.* into row_state
  from public.bot_interactions bi
  where bi.id = target_interaction_id
    and bi.delivery_state = 'sending'
  for update;

  if row_state.id is null then
    return;
  end if;

  final_state := case
    when delivered then 'delivered'
    when row_state.delivery_attempts >= 4 then 'failed'
    else 'queued'
  end;

  update public.bot_interactions bi
  set
    delivery_state = final_state,
    delivered_at = case when delivered then now() else bi.delivered_at end,
    delivery_error = case when delivered then null else left(coalesce(error_text, 'failed'), 200) end,
    next_attempt_at = case
      when final_state = 'queued' then now() + case row_state.delivery_attempts
        when 1 then interval '5 seconds'
        when 2 then interval '30 seconds'
        else interval '2 minutes'
      end
      else bi.next_attempt_at
    end
  where bi.id = row_state.id;

  update public.bot_callbacks c
  set
    last_status = http_status,
    last_error = case when delivered then null else left(coalesce(error_text, 'failed'), 200) end,
    last_success_at = case when delivered then now() else c.last_success_at end,
    last_failure_at = case when delivered then c.last_failure_at else now() end,
    consecutive_failures = case
      when delivered then 0
      when final_state = 'failed' then c.consecutive_failures + 1
      else c.consecutive_failures
    end,
    enabled = case
      when not delivered and final_state = 'failed' and c.consecutive_failures + 1 >= 20 then false
      else c.enabled
    end
  where c.bot_id = row_state.bot_id;
end;
$$;

revoke execute on function public.claim_bot_callbacks(integer) from public, anon, authenticated;
revoke execute on function public.finish_bot_callback(uuid, boolean, integer, text) from public, anon, authenticated;
grant execute on function public.claim_bot_callbacks(integer) to service_role;
grant execute on function public.finish_bot_callback(uuid, boolean, integer, text) to service_role;

-- Wakes the function when something is due (retries).
create or replace function public.wake_bot_callbacks_if_due()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.bot_interactions bi
    where bi.delivery_state in ('queued', 'sending')
      and bi.next_attempt_at <= now()
      and bi.expires_at > now()
  ) then
    perform public.wake_bot_callbacks();
  end if;
end;
$$;

-- Presses and commands older than 7 days, and private replies that expired.
create or replace function public.purge_bot_interactions()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.bot_interactions bi
  where bi.created_at < now() - interval '7 days';
  delete from public.bot_ephemeral_messages e
  where e.expires_at < now() - interval '1 hour';
end;
$$;

revoke execute on function public.wake_bot_callbacks_if_due() from public, anon, authenticated;
revoke execute on function public.purge_bot_interactions() from public, anon, authenticated;
grant execute on function public.wake_bot_callbacks_if_due() to service_role;
grant execute on function public.purge_bot_interactions() to service_role;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.unschedule(jobid)
    from cron.job
    where jobname in ('wecord-bot-callbacks-retry', 'wecord-bot-interactions-purge');
    perform cron.schedule(
      'wecord-bot-callbacks-retry',
      '* * * * *',
      'select public.wake_bot_callbacks_if_due()'
    );
    perform cron.schedule(
      'wecord-bot-interactions-purge',
      '17 * * * *',
      'select public.purge_bot_interactions()'
    );
  else
    raise notice 'pg_cron is not available: call wake_bot_callbacks_if_due() and purge_bot_interactions() from another scheduler';
  end if;
exception when others then
  raise notice 'Could not schedule the bot callback jobs with pg_cron: %', sqlerrm;
end;
$$;
