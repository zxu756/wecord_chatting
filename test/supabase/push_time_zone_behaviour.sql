-- Behaviour checks for the time zone of push subscriptions (migration
-- 202610170100). Run by test/supabase/push_time_zone_test.dart against a local
-- database that has the earlier migrations; it applies the push migrations
-- inside a transaction and rolls everything back. Run from the repository root.
\set ON_ERROR_STOP on

begin;

-- One behaviour script at a time: they change the same tables, and test
-- files run in parallel.
do $$ begin perform pg_advisory_xact_lock(20261017); end $$;
-- The scripts that apply the same earlier migrations take this one.

\i supabase/migrations/202610170002_album_counts.sql
\i supabase/migrations/202610170003_album_summaries.sql
\i supabase/migrations/202610170004_album_push.sql
\i supabase/migrations/202610170005_push_language.sql
\i supabase/migrations/202610170100_push_time_zone.sql

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a9', 'ada@zone.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a9', 'ada_zone', 'Ada');

do $$
declare
  failures text := '';
  zone text;
  lang text;
  n integer;
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a9', true);

  -- The zone is saved with the subscription.
  perform public.register_push_subscription(
    'https://push.test/zone1', repeat('k', 60), repeat('a', 16), 'ua', 'zh', 'Asia/Shanghai');
  select s.time_zone, s.language into zone, lang
  from public.push_subscriptions s where s.endpoint = 'https://push.test/zone1';
  if zone is distinct from 'Asia/Shanghai' or lang is distinct from 'zh' then
    failures := failures || format(E'\nsaved zone %s language %s', zone, lang);
  end if;

  -- The five argument call of the earlier app still works and has no zone.
  perform public.register_push_subscription(
    'https://push.test/zone2', repeat('k', 60), repeat('a', 16), 'ua', 'en');
  select s.time_zone into zone from public.push_subscriptions s
  where s.endpoint = 'https://push.test/zone2';
  if zone is not null then
    failures := failures || format(E'\nold call zone %s', zone);
  end if;

  -- An older app saving the same browser again doesn't wipe the zone...
  perform public.register_push_subscription(
    'https://push.test/zone1', repeat('k', 60), repeat('a', 16), 'ua', 'zh');
  select s.time_zone into zone from public.push_subscriptions s
  where s.endpoint = 'https://push.test/zone1';
  if zone is distinct from 'Asia/Shanghai' then
    failures := failures || format(E'\nzone after old save %s', zone);
  end if;

  -- ...and a newer save (the traveller landed) replaces it.
  perform public.register_push_subscription(
    'https://push.test/zone1', repeat('k', 60), repeat('a', 16), 'ua', 'zh', 'America/Los_Angeles');
  select s.time_zone into zone from public.push_subscriptions s
  where s.endpoint = 'https://push.test/zone1';
  if zone is distinct from 'America/Los_Angeles' then
    failures := failures || format(E'\nzone after travel %s', zone);
  end if;

  -- Blank or malformed names are dropped, the subscription is kept.
  perform public.register_push_subscription(
    'https://push.test/zone3', repeat('k', 60), repeat('a', 16), 'ua', 'en', '   ');
  perform public.register_push_subscription(
    'https://push.test/zone4', repeat('k', 60), repeat('a', 16), 'ua', 'en', 'Not a zone; drop table');
  select count(*) into n from public.push_subscriptions s
  where s.endpoint in ('https://push.test/zone3', 'https://push.test/zone4')
    and s.time_zone is null;
  if n <> 2 then
    failures := failures || format(E'\nblank and malformed zones kept: %s of 2 are null', n);
  end if;

  -- The table itself refuses a malformed name too.
  begin
    insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, time_zone)
    values ('00000000-0000-4000-8000-0000000000a9', 'https://push.test/bad',
            repeat('k', 60), repeat('a', 16), 'Not a zone');
    failures := failures || E'\ntime zone check missing';
  exception when check_violation then
    null;
  end;

  -- Only one register function exists (an ambiguous call would fail).
  select count(*) into n from pg_proc p
  where p.pronamespace = 'public'::regnamespace
    and p.proname = 'register_push_subscription';
  if n <> 1 then
    failures := failures || format(E'\n%s register_push_subscription overloads', n);
  end if;

  -- Anonymous callers can't register.
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.register_push_subscription(
      'https://push.test/anon', repeat('k', 60), repeat('a', 16), 'ua', 'en', 'UTC');
    failures := failures || E'\nanonymous register allowed';
  exception when insufficient_privilege then
    null;
  end;

  if failures <> '' then
    raise exception 'push time zone checks failed:%', failures;
  end if;
end $$;

rollback;
