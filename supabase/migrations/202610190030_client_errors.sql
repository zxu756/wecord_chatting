-- Crash and error reports, kept in WeCord's own database (no third-party
-- service). The app batches what went wrong on a device (an uncaught error,
-- a provider that failed, a sign-out nobody asked for, a burst of token
-- refreshes, a redirect loop, a failed RPC or Edge Function call) and sends it
-- to report_client_errors(). The device has already scrubbed it: no message
-- text, local file names, emails or tokens, and a stack trace cut to 8 KB.
--
-- * client_errors is write-only for clients: row level security is on with no
--   policy, and every privilege is revoked from public, anon and
--   authenticated. Only the owner (the SQL editor, `supabase db query
--   --linked`, tool/errors_report.sh) reads it.
-- * report_client_errors(reports jsonb) is security definer and callable by
--   anon too (a sign-in that fails has no session). It never trusts the
--   client: the user is auth.uid() (null when anon), kinds are a fixed list,
--   every text is cut to a length, the context object is dropped when larger
--   than 4 KB, and a batch is at most 20 reports and 64 KB. It never raises
--   for a bad payload (the device must not retry a poison batch): it answers
--   {accepted, dropped}.
-- * Rate limits, per hour, counted in client_error_rate: 60 reports per
--   signed-in user, 10 per anonymous caller (a hash of the caller's address,
--   salted with the hour, never the address itself), 200 for all anonymous
--   callers together and 3000 overall. The rate rows are purged after a day.
-- * purge_old_client_errors() deletes reports older than 30 days; with
--   pg_cron installed (hosted Supabase) it runs daily.

create table if not exists public.client_errors (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  platform text not null default '',
  app_version text not null default '',
  build text not null default '',
  kind text not null,
  message text not null default '',
  stack text not null default '',
  fingerprint text not null check (fingerprint ~ '^[0-9a-f]{8,64}$'),
  count integer not null default 1 check (count between 1 and 10000),
  context jsonb not null default '{}'::jsonb
);

create index if not exists client_errors_created_idx
  on public.client_errors (created_at);
create index if not exists client_errors_fingerprint_idx
  on public.client_errors (fingerprint, created_at desc);

alter table public.client_errors enable row level security;
revoke all on public.client_errors from public, anon, authenticated;

create table if not exists public.client_error_rate (
  bucket text not null,
  window_start timestamptz not null,
  n integer not null default 0,
  primary key (bucket, window_start)
);

alter table public.client_error_rate enable row level security;
revoke all on public.client_error_rate from public, anon, authenticated;

-- Takes up to [want] reports from a bucket of at most [cap] per hour and
-- returns how many it granted.
create or replace function public.client_error_take(
  bucket_key text,
  want integer,
  cap integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  w timestamptz := date_trunc('hour', now());
  used integer;
  granted integer;
begin
  if want <= 0 then
    return 0;
  end if;
  insert into public.client_error_rate (bucket, window_start, n)
  values (bucket_key, w, 0)
  on conflict (bucket, window_start) do nothing;
  select n into used
  from public.client_error_rate
  where bucket = bucket_key and window_start = w
  for update;
  granted := least(want, greatest(cap - used, 0));
  if granted > 0 then
    update public.client_error_rate
    set n = n + granted
    where bucket = bucket_key and window_start = w;
  end if;
  return granted;
end;
$$;

revoke execute on function public.client_error_take(text, integer, integer)
  from public, anon, authenticated;

create or replace function public.report_client_errors(reports jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  max_batch constant integer := 20;
  max_bytes constant integer := 65536;
  w timestamptz := date_trunc('hour', now());
  total integer;
  want integer;
  granted integer;
  own_bucket text;
  headers jsonb;
  caller text;
  item jsonb;
  kind_value text;
  fingerprint_value text;
  count_value integer;
  context_value jsonb;
  accepted integer := 0;
begin
  if reports is null or jsonb_typeof(reports) <> 'array' then
    return jsonb_build_object('accepted', 0, 'dropped', 0);
  end if;
  total := jsonb_array_length(reports);
  if total = 0 then
    return jsonb_build_object('accepted', 0, 'dropped', 0);
  end if;
  if octet_length(reports::text) > max_bytes then
    return jsonb_build_object('accepted', 0, 'dropped', total);
  end if;

  want := least(total, max_batch);

  if uid is not null then
    own_bucket := 'u:' || uid::text;
    granted := public.client_error_take(own_bucket, want, 60);
  else
    begin
      headers := coalesce(
        nullif(current_setting('request.headers', true), '')::jsonb,
        '{}'::jsonb
      );
    exception when others then
      headers := '{}'::jsonb;
    end;
    caller := split_part(
      coalesce(headers->>'cf-connecting-ip', headers->>'x-forwarded-for', ''),
      ',',
      1
    );
    -- A hash salted with the hour: enough to count one caller, not to find
    -- out who it was, and it means nothing after the hour.
    own_bucket := 'a:' || encode(
      sha256(convert_to(caller || '|' || w::text, 'UTF8')),
      'hex'
    );
    granted := public.client_error_take(own_bucket, want, 10);
    granted := public.client_error_take('a:all', granted, 200);
  end if;
  granted := public.client_error_take('all', granted, 3000);

  for item in
    select value from jsonb_array_elements(reports) limit granted
  loop
    if jsonb_typeof(item) <> 'object' then
      continue;
    end if;

    fingerprint_value := case
      when jsonb_typeof(item->'fingerprint') = 'string'
        then item->>'fingerprint'
    end;
    if fingerprint_value is null
        or fingerprint_value !~ '^[0-9a-f]{8,64}$' then
      continue;
    end if;

    kind_value := case
      when jsonb_typeof(item->'kind') = 'string' then item->>'kind'
    end;
    if kind_value is null or kind_value not in (
      'flutter_error',
      'platform_error',
      'zone_error',
      'provider_error',
      'auth_unexpected_sign_out',
      'auth_refresh_burst',
      'router_redirect_loop',
      'rpc_error',
      'function_error',
      'sign_in_error'
    ) then
      kind_value := 'other';
    end if;

    count_value := case
      when jsonb_typeof(item->'count') = 'number'
        and (item->>'count') ~ '^[0-9]{1,5}$'
        then least(greatest((item->>'count')::integer, 1), 10000)
      else 1
    end;

    context_value := case
      when jsonb_typeof(item->'context') = 'object'
        and octet_length((item->'context')::text) <= 4096
        then item->'context'
      else '{}'::jsonb
    end;

    insert into public.client_errors (
      user_id, platform, app_version, build, kind, message, stack,
      fingerprint, count, context
    )
    values (
      uid,
      left(case when jsonb_typeof(item->'platform') = 'string'
        then item->>'platform' else '' end, 32),
      left(case when jsonb_typeof(item->'app_version') = 'string'
        then item->>'app_version' else '' end, 32),
      left(case when jsonb_typeof(item->'build') = 'string'
        then item->>'build' else '' end, 32),
      kind_value,
      left(case when jsonb_typeof(item->'message') = 'string'
        then item->>'message' else '' end, 1000),
      left(case when jsonb_typeof(item->'stack') = 'string'
        then item->>'stack' else '' end, 8192),
      fingerprint_value,
      count_value,
      context_value
    );
    accepted := accepted + 1;
  end loop;

  return jsonb_build_object('accepted', accepted, 'dropped', total - accepted);
end;
$$;

revoke execute on function public.report_client_errors(jsonb) from public;
grant execute on function public.report_client_errors(jsonb)
  to anon, authenticated;

create or replace function public.purge_old_client_errors()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  removed integer;
begin
  delete from public.client_errors
  where created_at < now() - interval '30 days';
  get diagnostics removed = row_count;
  delete from public.client_error_rate
  where window_start < now() - interval '1 day';
  return removed;
end;
$$;

revoke execute on function public.purge_old_client_errors()
  from public, anon, authenticated;

-- With pg_cron installed (hosted Supabase), tidy up daily. Without it (local
-- development) nothing is scheduled and this stays a plain function.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'client-errors-purge',
      '23 4 * * *',
      'select public.purge_old_client_errors()'
    );
  end if;
end $$;
