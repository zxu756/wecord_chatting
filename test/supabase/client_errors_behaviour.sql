-- Behaviour checks for crash and error reports (migration 202610190030).
-- Run by test/supabase/client_errors_test.dart against the local database;
-- applies the migration inside a transaction, acts as anon and signed-in
-- people, checks the limits and that nobody but the owner reads the table,
-- and rolls back. Run from the repository root.
\set ON_ERROR_STOP on

begin;

do $$ begin perform pg_advisory_xact_lock(20261017); end $$;

\i supabase/migrations/202610190030_client_errors.sql

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@err.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@err.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');

create function pg_temp.act_as(who text) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.headers', '', true);
  if who = 'anon' then
    execute 'set local role anon';
  elsif who is not null then
    perform set_config(
      'request.jwt.claim.sub',
      format('00000000-0000-4000-8000-0000000000%s1', who),
      true
    );
    execute 'set local role authenticated';
  end if;
end;
$$;
grant execute on function pg_temp.act_as(text) to public;

create function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin
  if ok is distinct from true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok: %', label;
end;
$$;
grant execute on function pg_temp.check(text, boolean) to public;

create function pg_temp.refused(label text, stmt text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when insufficient_privilege then
    raise notice 'ok: %', label;
    return;
  end;
  raise exception 'FAILED: % (nothing was refused)', label;
end;
$$;
grant execute on function pg_temp.refused(text, text) to public;

-- n well-formed reports with distinct fingerprints starting at [first].
create function pg_temp.reports(n integer, first integer default 1) returns jsonb language sql as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', 'flutter_error',
    'message', 'StateError: boom',
    'stack', '#0  main (package:wecord/main.dart:1:1)',
    'fingerprint', lpad(to_hex(i), 16, '0'),
    'count', 2,
    'platform', 'macos',
    'app_version', '0.1.0',
    'build', '1',
    'context', jsonb_build_object('route', '/home', 'locale', 'en')
  )), '[]'::jsonb)
  from generate_series(first, first + n - 1) as i
$$;
grant execute on function pg_temp.reports(integer, integer) to public;

-- A signed-in person reports.
select pg_temp.act_as('a');
select pg_temp.check(
  'a signed-in person can report',
  (public.report_client_errors(pg_temp.reports(3))->>'accepted')::integer = 3
);

-- Clients can never read or change the table (or its rate counters).
select pg_temp.refused('signed-in people cannot read client_errors',
  'select count(*) from public.client_errors');
select pg_temp.refused('signed-in people cannot write client_errors',
  'insert into public.client_errors (kind, fingerprint) values (''x'', ''0123456789abcdef'')');
select pg_temp.refused('signed-in people cannot delete client_errors',
  'delete from public.client_errors');
select pg_temp.refused('signed-in people cannot read the rate counters',
  'select count(*) from public.client_error_rate');
select pg_temp.refused('signed-in people cannot call the purge',
  'select public.purge_old_client_errors()');
select pg_temp.refused('signed-in people cannot call the bucket helper',
  'select public.client_error_take(''x'', 1, 1)');

select pg_temp.act_as('anon');
select pg_temp.refused('anon cannot read client_errors',
  'select count(*) from public.client_errors');
select pg_temp.refused('anon cannot write client_errors',
  'insert into public.client_errors (kind, fingerprint) values (''x'', ''0123456789abcdef'')');
select pg_temp.check(
  'anon can report (a sign-in that fails has no session)',
  (public.report_client_errors(pg_temp.reports(2, 100))->>'accepted')::integer = 2
);

-- What was stored: the user is the caller, null for anon.
select pg_temp.act_as(null);
select pg_temp.check(
  'the user is auth.uid(), null for anon',
  (select count(*) from public.client_errors
    where user_id = '00000000-0000-4000-8000-0000000000a1') = 3
  and (select count(*) from public.client_errors where user_id is null) = 2
);
select pg_temp.check(
  'fields are stored',
  (select count(*) from public.client_errors
    where platform = 'macos' and app_version = '0.1.0' and build = '1'
      and kind = 'flutter_error' and count = 2
      and context->>'route' = '/home') = 5
);

-- Bad input is cleaned up or dropped, never raised on.
select pg_temp.act_as('b');
select pg_temp.check(
  'null and non-array payloads are ignored',
  (public.report_client_errors(null)->>'accepted')::integer = 0
  and (public.report_client_errors('{"a":1}'::jsonb)->>'accepted')::integer = 0
  and (public.report_client_errors('[]'::jsonb)->>'accepted')::integer = 0
);
select pg_temp.check(
  'a report without a valid fingerprint is dropped',
  public.report_client_errors(
    '[{"kind":"flutter_error","message":"x"},{"kind":"flutter_error","fingerprint":"NOT HEX!!"},7,"s"]'::jsonb
  ) = '{"accepted":0,"dropped":4}'::jsonb
);
select pg_temp.check(
  'an unknown kind is accepted as other',
  (public.report_client_errors(jsonb_build_array(jsonb_build_object(
    'kind', 'drop table',
    'message', repeat('m', 5000),
    'stack', repeat('s', 20000),
    'platform', repeat('p', 100),
    'fingerprint', 'abcdef0123456789',
    'count', 999999,
    'context', jsonb_build_object('x', repeat('c', 5000))
  )))->>'accepted')::integer = 1
);
select pg_temp.act_as(null);
select pg_temp.check(
  'stored row was cut to the limits',
  (select kind = 'other' and length(message) = 1000 and length(stack) = 8192
      and length(platform) = 32 and count = 1 and context = '{}'::jsonb
    from public.client_errors where fingerprint = 'abcdef0123456789')
);

-- A batch holds at most 20 reports and 64 KB.
select pg_temp.act_as('b');
select pg_temp.check(
  'only the first 20 of a batch are kept',
  public.report_client_errors(pg_temp.reports(25, 1000)) = '{"accepted":20,"dropped":5}'::jsonb
);
select pg_temp.check(
  'a batch over 64 KB is dropped whole',
  (public.report_client_errors(jsonb_build_array(jsonb_build_object(
    'kind', 'flutter_error',
    'fingerprint', 'abcdef0123456780',
    'message', repeat('m', 70000)
  )))->>'accepted')::integer = 0
);

-- Per-user limit: 60 an hour. Bob has used 4 (dropped ones count
-- too) + 1 + 20 so far.
select pg_temp.check(
  'a signed-in person is limited to 60 reports an hour',
  (public.report_client_errors(pg_temp.reports(20, 2000))->>'accepted')::integer = 20
  and (public.report_client_errors(pg_temp.reports(20, 3000))->>'accepted')::integer = 15
  and (public.report_client_errors(pg_temp.reports(5, 4000))->>'accepted')::integer = 0
);
select pg_temp.act_as('a');
select pg_temp.check(
  'another person is not affected by that limit',
  (public.report_client_errors(pg_temp.reports(5, 5000))->>'accepted')::integer = 5
);

-- Anonymous callers: 10 an hour each (by address), 200 all together.
select pg_temp.act_as('anon');
select set_config('request.headers', '{"x-forwarded-for":"203.0.113.9, 10.0.0.1"}', true);
select pg_temp.check(
  'an anonymous caller is limited to 10 an hour',
  (public.report_client_errors(pg_temp.reports(10, 6000))->>'accepted')::integer = 10
  and (public.report_client_errors(pg_temp.reports(3, 6100))->>'accepted')::integer = 0
);
select set_config('request.headers', '{"x-forwarded-for":"203.0.113.77"}', true);
select pg_temp.check(
  'a different address has its own allowance',
  (public.report_client_errors(pg_temp.reports(4, 6200))->>'accepted')::integer = 4
);

select pg_temp.act_as(null);
select pg_temp.check(
  'the caller address is never stored',
  not exists (select 1 from public.client_error_rate where bucket like '%203.0.113%')
  and not exists (select 1 from public.client_errors where context::text like '%203.0.113%')
);

-- The global caps.
update public.client_error_rate set n = 199 where bucket = 'a:all';
select pg_temp.act_as('anon');
select set_config('request.headers', '{"x-forwarded-for":"198.51.100.1"}', true);
select pg_temp.check(
  'anonymous callers share a cap of 200 an hour',
  (public.report_client_errors(pg_temp.reports(5, 7000))->>'accepted')::integer = 1
  and (public.report_client_errors(pg_temp.reports(5, 7100))->>'accepted')::integer = 0
);
select pg_temp.act_as(null);
update public.client_error_rate set n = 2999 where bucket = 'all';
select pg_temp.act_as('a');
select pg_temp.check(
  'everyone shares a cap of 3000 an hour',
  (public.report_client_errors(pg_temp.reports(5, 8000))->>'accepted')::integer = 1
  and (public.report_client_errors(pg_temp.reports(5, 8100))->>'accepted')::integer = 0
);

-- Purge: reports older than 30 days and old counters go; newer stay.
select pg_temp.act_as(null);
update public.client_errors set created_at = now() - interval '31 days'
  where fingerprint in ('0000000000000001', '0000000000000064');
create temp table purged as select public.purge_old_client_errors() as n;
select pg_temp.check(
  'the purge removes reports older than 30 days only',
  (select n from purged) = 2
  and (select count(*) from public.client_errors) > 0
  and not exists (select 1 from public.client_errors
    where created_at < now() - interval '30 days')
);
insert into public.client_error_rate values ('u:old', now() - interval '2 days', 5);
delete from purged;
insert into purged select public.purge_old_client_errors();
select pg_temp.check(
  'the purge removes old counters',
  (select n from purged) = 0
  and not exists (select 1 from public.client_error_rate where bucket = 'u:old')
);

-- Scheduled daily where pg_cron exists.
select pg_temp.check(
  'the daily purge is scheduled when pg_cron is installed',
  not exists (select 1 from pg_extension where extname = 'pg_cron')
  or exists (select 1 from cron.job where jobname = 'client-errors-purge')
);

rollback;
