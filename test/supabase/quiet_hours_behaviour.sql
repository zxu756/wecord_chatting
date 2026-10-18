-- Behaviour checks for quiet hours (migrations 202610210300 and 202610210310).
-- Run by test/supabase/quiet_hours_test.dart against the local database inside
-- a transaction that is rolled back. Run from the repository root.
--
-- Cast: Ada (a1) has quiet hours; Bob (b1) is her friend and starred; Cy (c1)
-- is her friend and chosen as an important contact; Dee (d1) is her friend,
-- neither; Eve (e1) is not her friend.
\set ON_ERROR_STOP on
\o /dev/null

begin;

do $$ begin perform pg_advisory_xact_lock(20261017); end $$;

\i supabase/migrations/202610170002_album_counts.sql
\i supabase/migrations/202610170003_album_summaries.sql
\i supabase/migrations/202610170004_album_push.sql
\i supabase/migrations/202610170005_push_language.sql
\i supabase/migrations/202610170100_push_time_zone.sql
\i supabase/migrations/202610180040_friend_tags_and_stars.sql
\i supabase/migrations/202610210300_notification_settings.sql
\i supabase/migrations/202610210310_quiet_hours.sql

create temp table failures (msg text);
grant all on failures to public;

create function pg_temp.expect(ok boolean, msg text) returns void
language plpgsql security definer as $$
begin
  if not coalesce(ok, false) then
    insert into pg_temp.failures values (msg);
  end if;
end $$;

create function pg_temp.act(user_id uuid) returns void language plpgsql as $$
begin
  execute 'reset role';
  if user_id is null then
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    execute 'set local role anon';
  else
    perform set_config('request.jwt.claim.sub', user_id::text, true);
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', user_id, 'role', 'authenticated')::text,
      true
    );
    execute 'set local role authenticated';
  end if;
end $$;

create function pg_temp.refused(statement text) returns boolean language plpgsql as $$
begin
  execute statement;
  return false;
exception when others then
  return true;
end $$;

grant execute on all functions in schema pg_temp to public;

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@quiet.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@quiet.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@quiet.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee@quiet.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve@quiet.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_quiet', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_quiet', 'Bob'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_quiet', 'Cy'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee_quiet', 'Dee'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve_quiet', 'Eve');

insert into public.friendships (user_low_id, user_high_id)
values
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000b1'),
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000c1'),
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000d1');

-- ----------------------------------------------------------- the pure rule
-- The same vectors are in supabase/functions/push/quiet_hours_test.ts and
-- test/features/notifications/quiet_hours_test.dart.
create temp table vectors (
  label text, zone text, days integer[], win_start time, win_end time,
  at timestamptz, expected boolean
);
insert into vectors values
  -- Shanghai (+8, no daylight saving), every day 23:00-07:00.
  ('across midnight: start is in', 'Asia/Shanghai', '{1,2,3,4,5,6,7}', '23:00', '07:00', '2026-10-20 15:00:00+00', true),
  ('across midnight: a minute before', 'Asia/Shanghai', '{1,2,3,4,5,6,7}', '23:00', '07:00', '2026-10-20 14:59:00+00', false),
  ('across midnight: after midnight', 'Asia/Shanghai', '{1,2,3,4,5,6,7}', '23:00', '07:00', '2026-10-20 18:00:00+00', true),
  ('across midnight: last minute', 'Asia/Shanghai', '{1,2,3,4,5,6,7}', '23:00', '07:00', '2026-10-20 22:59:00+00', true),
  ('across midnight: end is out', 'Asia/Shanghai', '{1,2,3,4,5,6,7}', '23:00', '07:00', '2026-10-20 23:00:00+00', false),
  -- Weekdays are the days a window starts: Monday only.
  ('monday night', 'Asia/Shanghai', '{1}', '23:00', '07:00', '2026-10-19 15:30:00+00', true),
  ('tuesday early morning belongs to monday', 'Asia/Shanghai', '{1}', '23:00', '07:00', '2026-10-19 19:00:00+00', true),
  ('monday early morning belongs to sunday', 'Asia/Shanghai', '{1}', '23:00', '07:00', '2026-10-18 19:00:00+00', false),
  ('tuesday night is not picked', 'Asia/Shanghai', '{1}', '23:00', '07:00', '2026-10-20 15:30:00+00', false),
  ('sunday night runs into monday', 'Asia/Shanghai', '{7}', '23:00', '07:00', '2026-10-18 19:00:00+00', true),
  -- Same-day window on weekdays in New York.
  ('workday morning', 'America/New_York', '{1,2,3,4,5}', '09:00', '17:00', '2026-10-23 14:00:00+00', true),
  ('workday evening', 'America/New_York', '{1,2,3,4,5}', '09:00', '17:00', '2026-10-23 21:00:00+00', false),
  ('saturday', 'America/New_York', '{1,2,3,4,5}', '09:00', '17:00', '2026-10-24 14:00:00+00', false),
  -- Daylight saving: the clocks go back in New York on 2026-11-01 at 02:00.
  ('fall back: 06:30 EST is still quiet', 'America/New_York', '{1,2,3,4,5,6,7}', '23:00', '07:00', '2026-11-01 11:30:00+00', true),
  ('fall back: 07:00 EST is over', 'America/New_York', '{1,2,3,4,5,6,7}', '23:00', '07:00', '2026-11-01 12:00:00+00', false),
  ('fall back: 06:30 EDT the day before', 'America/New_York', '{1,2,3,4,5,6,7}', '23:00', '07:00', '2026-10-31 10:30:00+00', true),
  ('fall back: 07:00 EDT the day before', 'America/New_York', '{1,2,3,4,5,6,7}', '23:00', '07:00', '2026-10-31 11:00:00+00', false),
  -- Spring forward: 02:00 EST becomes 03:00 EDT on 2026-03-08.
  ('spring forward: 01:59 EST', 'America/New_York', '{1,2,3,4,5,6,7}', '02:30', '03:30', '2026-03-08 06:59:00+00', false),
  ('spring forward: 03:00 EDT is inside', 'America/New_York', '{1,2,3,4,5,6,7}', '02:30', '03:30', '2026-03-08 07:00:00+00', true),
  ('spring forward: 03:30 EDT is out', 'America/New_York', '{1,2,3,4,5,6,7}', '02:30', '03:30', '2026-03-08 07:30:00+00', false),
  -- London in summer (BST, +1) and a half-hour zone (Kolkata, +5:30).
  ('BST: 23:00', 'Europe/London', '{1,2,3,4,5,6,7}', '23:00', '07:00', '2026-07-01 22:00:00+00', true),
  ('BST: 22:59', 'Europe/London', '{1,2,3,4,5,6,7}', '23:00', '07:00', '2026-07-01 21:59:00+00', false),
  ('Kolkata: 22:00', 'Asia/Kolkata', '{1,2,3,4,5,6,7}', '22:00', '07:00', '2026-10-20 16:30:00+00', true),
  ('Kolkata: 21:59', 'Asia/Kolkata', '{1,2,3,4,5,6,7}', '22:00', '07:00', '2026-10-20 16:29:00+00', false),
  -- Odd settings.
  ('equal start and end is empty', 'UTC', '{1,2,3,4,5,6,7}', '08:00', '08:00', '2026-10-20 08:00:00+00', false),
  ('no days is never quiet', 'UTC', '{}', '22:00', '07:00', '2026-10-20 23:00:00+00', false),
  ('unknown zone counts as UTC', 'Mars/Base', '{1,2,3,4,5,6,7}', '22:00', '07:00', '2026-10-20 23:00:00+00', true),
  ('missing zone counts as UTC', null, '{1,2,3,4,5,6,7}', '22:00', '07:00', '2026-10-20 12:00:00+00', false),
  ('midnight start', 'UTC', '{1,2,3,4,5,6,7}', '00:00', '06:00', '2026-10-20 00:00:00+00', true),
  ('ends at midnight', 'UTC', '{1,2,3,4,5,6,7}', '18:00', '00:00', '2026-10-20 23:59:00+00', true),
  ('ends at midnight: midnight is out', 'UTC', '{1,2,3,4,5,6,7}', '18:00', '00:00', '2026-10-21 00:00:00+00', false);

do $$
declare
  v record;
  got boolean;
begin
  for v in select * from vectors loop
    got := public.quiet_window_contains(v.zone, v.days, v.win_start, v.win_end, v.at);
    perform pg_temp.expect(got = v.expected,
      format('window "%s": expected %s, got %s', v.label, v.expected, got));
  end loop;
end $$;

-- ------------------------------------------------------- settings and RLS
do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  cy uuid := '00000000-0000-4000-8000-0000000000c1';
  dee uuid := '00000000-0000-4000-8000-0000000000d1';
  eve uuid := '00000000-0000-4000-8000-0000000000e1';
  changed integer;
  seen integer;
  vips uuid[];
  zone text;
begin
  perform pg_temp.act(ada);
  insert into public.user_notification_settings (user_id, timezone, quiet_enabled, quiet_days)
  values (ada, 'Asia/Shanghai', true, '{3,1,1,2}');
  perform pg_temp.expect(
    (select quiet_days from public.user_notification_settings where user_id = ada) = array[1, 2, 3],
    'days are sorted and unique');
  perform pg_temp.expect(
    (select quiet_start from public.user_notification_settings where user_id = ada) = '22:00',
    'default start is 22:00');
  perform pg_temp.expect(
    (select show_previews from public.user_notification_settings where user_id = ada) is null,
    'previews are not moved yet');

  -- Nobody else reads or writes it.
  perform pg_temp.act(bob);
  select count(*) into seen from public.user_notification_settings;
  perform pg_temp.expect(seen = 0, 'Bob can read Ada''s settings');
  update public.user_notification_settings set quiet_enabled = false where user_id = ada;
  get diagnostics changed = row_count;
  perform pg_temp.expect(changed = 0, 'Bob updated Ada''s settings');
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.user_notification_settings (user_id) values (%L)', ada)),
    'Bob created a row for Ada');
  perform pg_temp.act(null);
  perform pg_temp.expect(
    pg_temp.refused('select * from public.user_notification_settings'),
    'anonymous read allowed');

  -- Bad days are refused; an unknown or malformed zone name is dropped.
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    pg_temp.refused('update public.user_notification_settings set quiet_days = ''{0}'''),
    'day 0 accepted');
  perform pg_temp.expect(
    pg_temp.refused('update public.user_notification_settings set quiet_days = ''{8}'''),
    'day 8 accepted');
  update public.user_notification_settings set timezone = 'Mars/Base' where user_id = ada;
  select s.timezone into zone from public.user_notification_settings s where s.user_id = ada;
  perform pg_temp.expect(zone is null, 'unknown zone name is dropped');
  update public.user_notification_settings set timezone = 'no spaces allowed' where user_id = ada;
  select s.timezone into zone from public.user_notification_settings s where s.user_id = ada;
  perform pg_temp.expect(zone is null, 'malformed zone name is dropped');
  update public.user_notification_settings set timezone = 'Asia/Shanghai' where user_id = ada;

  -- Important contacts are friends, set one at a time.
  perform public.set_important_contact(cy, true);
  perform public.set_important_contact(cy, true);
  select s.vip_user_ids into vips from public.user_notification_settings s where s.user_id = ada;
  perform pg_temp.expect(vips = array[cy], format('Cy is the one important contact, got %s', vips));
  perform pg_temp.expect(
    pg_temp.refused(format('select public.set_important_contact(%L, true)', eve)),
    'a stranger became an important contact');
  perform pg_temp.expect(
    pg_temp.refused(format(
      'update public.user_notification_settings set vip_user_ids = array[%L::uuid]', eve)),
    'a stranger was added through the table');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.set_important_contact(%L, true)', ada)),
    'Ada made herself an important contact');

  -- Without a row yet, marking one creates it (Dee has none).
  perform pg_temp.act(dee);
  perform public.set_important_contact(ada, true);
  perform pg_temp.expect(
    (select count(*) from public.user_notification_settings) = 1,
    'marking an important contact creates the row');
  perform pg_temp.expect(
    (select quiet_enabled from public.user_notification_settings) = false,
    'a created row has quiet hours off');
  perform public.set_important_contact(ada, false);
  perform pg_temp.expect(
    (select vip_user_ids from public.user_notification_settings) = '{}',
    'unmarking removes it');

  perform pg_temp.act(null);
  perform pg_temp.expect(
    pg_temp.refused(format('select public.set_important_contact(%L, true)', ada)),
    'an anonymous caller marked a contact');
  reset role;
end $$;

-- Unfriending takes the friend out of the list.
delete from public.friendships
where user_low_id = '00000000-0000-4000-8000-0000000000a1'
  and user_high_id = '00000000-0000-4000-8000-0000000000c1';
select pg_temp.expect(
  (select vip_user_ids from public.user_notification_settings
   where user_id = '00000000-0000-4000-8000-0000000000a1') = '{}',
  'unfriending removes the important contact');
insert into public.friendships (user_low_id, user_high_id)
values ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000c1');
update public.user_notification_settings
set vip_user_ids = array['00000000-0000-4000-8000-0000000000c1'::uuid]
where user_id = '00000000-0000-4000-8000-0000000000a1';

-- ---------------------------------------------------- the server functions
do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
begin
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    pg_temp.refused(format('select public.in_quiet_hours(%L, now())', ada)),
    'in_quiet_hours is open to signed-in users');
  perform pg_temp.expect(
    pg_temp.refused('select * from public.quiet_hours_recipients(array[]::uuid[], null)'),
    'quiet_hours_recipients is open to signed-in users');
  perform pg_temp.expect(
    pg_temp.refused('select public.notification_time_zone(''00000000-0000-4000-8000-0000000000a1'')'),
    'notification_time_zone is open to signed-in users');
  perform pg_temp.act(null);
  perform pg_temp.expect(
    pg_temp.refused(format('select public.in_quiet_hours(%L, now())', ada)),
    'in_quiet_hours is open to anonymous callers');
  reset role;
end $$;

-- Ada: quiet 22:00-07:00, windows starting Monday to Wednesday, Shanghai.
update public.user_notification_settings
set quiet_enabled = true, quiet_days = '{1,2,3}', timezone = 'Asia/Shanghai'
where user_id = '00000000-0000-4000-8000-0000000000a1';

select pg_temp.expect(
  public.in_quiet_hours('00000000-0000-4000-8000-0000000000a1', '2026-10-19 15:00:00+00'),
  'Monday 23:00 Shanghai is quiet');
select pg_temp.expect(
  not public.in_quiet_hours('00000000-0000-4000-8000-0000000000a1', '2026-10-19 13:59:00+00'),
  'Monday 21:59 Shanghai is not quiet');
select pg_temp.expect(
  public.in_quiet_hours('00000000-0000-4000-8000-0000000000a1', '2026-10-21 20:00:00+00'),
  'Thursday 04:00 Shanghai belongs to Wednesday''s window');
select pg_temp.expect(
  not public.in_quiet_hours('00000000-0000-4000-8000-0000000000a1', '2026-10-22 20:00:00+00'),
  'Friday 04:00 Shanghai belongs to Thursday''s window, which is not picked');

-- Quiet hours off, or no row at all: never quiet.
select pg_temp.expect(
  not public.in_quiet_hours('00000000-0000-4000-8000-0000000000d1', '2026-10-19 15:00:00+00'),
  'a person without settings is never quiet');
update public.user_notification_settings set quiet_enabled = false
where user_id = '00000000-0000-4000-8000-0000000000a1';
select pg_temp.expect(
  not public.in_quiet_hours('00000000-0000-4000-8000-0000000000a1', '2026-10-19 15:00:00+00'),
  'switched off is never quiet');
update public.user_notification_settings set quiet_enabled = true
where user_id = '00000000-0000-4000-8000-0000000000a1';

-- The zone: the settings', else the newest subscription's, else UTC.
insert into public.push_subscriptions
  (user_id, endpoint, p256dh, auth, language, time_zone, last_seen_at)
values
  ('00000000-0000-4000-8000-0000000000a1', 'https://push.test/ada-old', repeat('p', 60), repeat('a', 20), 'en', 'Europe/Paris', now() - interval '2 days'),
  ('00000000-0000-4000-8000-0000000000a1', 'https://push.test/ada-new', repeat('q', 60), repeat('b', 20), 'zh', 'America/New_York', now());
select pg_temp.expect(
  public.notification_time_zone('00000000-0000-4000-8000-0000000000a1') = 'Asia/Shanghai',
  'the settings'' zone comes first');
update public.user_notification_settings set timezone = null
where user_id = '00000000-0000-4000-8000-0000000000a1';
select pg_temp.expect(
  public.notification_time_zone('00000000-0000-4000-8000-0000000000a1') = 'America/New_York',
  'the newest subscription''s zone is next');
delete from public.push_subscriptions
where user_id = '00000000-0000-4000-8000-0000000000a1';
select pg_temp.expect(
  public.notification_time_zone('00000000-0000-4000-8000-0000000000a1') = 'UTC',
  'UTC is the last resort');
update public.user_notification_settings set timezone = 'Asia/Shanghai'
where user_id = '00000000-0000-4000-8000-0000000000a1';

-- --------------------------------------------- who a message breaks through
create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  cy uuid := '00000000-0000-4000-8000-0000000000c1';
  dee uuid := '00000000-0000-4000-8000-0000000000d1';
  conv uuid;
  m uuid;
begin
  insert into public.conversations (type, title) values ('group', 'Quiet group') returning id into conv;
  insert into public.conversation_members (conversation_id, user_id, role)
  values (conv, ada, 'owner'), (conv, bob, 'member'), (conv, cy, 'member'), (conv, dee, 'member');
  insert into ids values ('conv', conv);

  insert into public.messages (conversation_id, sender_id, type, body) values (conv, dee, 'text', 'plain') returning id into m;
  insert into ids values ('plain', m);
  insert into public.messages (conversation_id, sender_id, type, body) values (conv, bob, 'text', 'from starred') returning id into m;
  insert into ids values ('starred', m);
  insert into public.messages (conversation_id, sender_id, type, body) values (conv, cy, 'text', 'from vip') returning id into m;
  insert into ids values ('vip', m);
  insert into public.messages (conversation_id, sender_id, type, body) values (conv, dee, 'text', 'hey @ada') returning id into m;
  insert into ids values ('mention', m);
  insert into public.message_mentions (message_id, conversation_id, user_id, kind) values (m, conv, ada, 'user');
  insert into public.messages (conversation_id, sender_id, type, body) values (conv, dee, 'text', 'hey @everyone') returning id into m;
  insert into ids values ('everyone', m);
  insert into public.message_mentions (message_id, conversation_id, user_id, kind) values (m, conv, ada, 'all');
  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (conv, dee, 'system', 'Dee started a call.', '{"kind":"call"}') returning id into m;
  insert into ids values ('call', m);
  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (conv, dee, 'system', 'Dee pinned a message.', '{"kind":"pin"}') returning id into m;
  insert into ids values ('notice', m);

  insert into public.friend_stars (owner_id, friend_id) values (ada, bob);
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language, time_zone)
  values
    (ada, 'https://push.test/ada-1', repeat('p', 60), repeat('a', 20), 'en', 'Asia/Shanghai'),
    (ada, 'https://push.test/ada-2', repeat('q', 60), repeat('b', 20), 'zh', null),
    (dee, 'https://push.test/dee', repeat('r', 60), repeat('c', 20), 'en', null);
end $$;

create function pg_temp.breaks(message_name text, flag_endpoint text default 'https://push.test/ada-1')
returns boolean language sql as $$
  select r.breaks_through
  from public.quiet_hours_recipients(
    (select array_agg(id) from public.push_subscriptions),
    (select id from ids where name = message_name)
  ) r
  join public.push_subscriptions s on s.id = r.subscription_id
  where s.endpoint = flag_endpoint
$$;
grant execute on function pg_temp.breaks(text, text) to public;

do $$
declare
  rows integer;
  r record;
begin
  -- Only Ada's two subscriptions have quiet hours on.
  select count(*) into rows from public.quiet_hours_recipients(
    (select array_agg(id) from public.push_subscriptions), null);
  perform pg_temp.expect(rows = 2, format('two quiet subscriptions, got %s', rows));
  select * into r from public.quiet_hours_recipients(
    (select array_agg(id) from public.push_subscriptions), null)
  order by time_zone nulls last limit 1;
  perform pg_temp.expect(r.time_zone = 'Asia/Shanghai', 'the window carries the zone');
  perform pg_temp.expect(r.quiet_days = array[1, 2, 3], 'the window carries the days');
  perform pg_temp.expect(r.quiet_start = '22:00' and r.quiet_end = '07:00', 'the window carries the times');

  perform pg_temp.expect(pg_temp.breaks('plain') = false, 'an ordinary message must not break through');
  perform pg_temp.expect(pg_temp.breaks('plain', 'https://push.test/ada-2') = false, 'plain, second browser');
  perform pg_temp.expect(pg_temp.breaks('starred') = true, 'a starred friend breaks through');
  perform pg_temp.expect(pg_temp.breaks('starred', 'https://push.test/ada-2') = true, 'starred, second browser');
  perform pg_temp.expect(pg_temp.breaks('vip') = true, 'an important contact breaks through');
  perform pg_temp.expect(pg_temp.breaks('mention') = true, 'an @mention breaks through');
  perform pg_temp.expect(pg_temp.breaks('everyone') = false, '@everyone does not break through');
  perform pg_temp.expect(pg_temp.breaks('call') = true, 'a call breaks through');
  perform pg_temp.expect(pg_temp.breaks('notice') = false, 'another system notice does not');

  -- No message (reminders, tasks, events): nothing breaks through.
  select bool_or(breaks_through) into r from public.quiet_hours_recipients(
    (select array_agg(id) from public.push_subscriptions), null);
  perform pg_temp.expect(r.bool_or is not true, 'without a message nothing breaks through');

  -- Each exception follows its switch.
  update public.user_notification_settings
  set allow_starred = false where user_id = '00000000-0000-4000-8000-0000000000a1';
  perform pg_temp.expect(pg_temp.breaks('starred') = false, 'starred switched off');
  perform pg_temp.expect(pg_temp.breaks('vip') = true, 'starred off leaves the important contact');
  update public.user_notification_settings
  set allow_mentions = false where user_id = '00000000-0000-4000-8000-0000000000a1';
  perform pg_temp.expect(pg_temp.breaks('mention') = false, 'mentions switched off');
  update public.user_notification_settings
  set allow_calls = false where user_id = '00000000-0000-4000-8000-0000000000a1';
  perform pg_temp.expect(pg_temp.breaks('call') = false, 'calls switched off');
  update public.user_notification_settings
  set vip_user_ids = '{}' where user_id = '00000000-0000-4000-8000-0000000000a1';
  perform pg_temp.expect(pg_temp.breaks('vip') = false, 'no longer an important contact');
  update public.user_notification_settings
  set allow_starred = true, allow_mentions = true, allow_calls = true
  where user_id = '00000000-0000-4000-8000-0000000000a1';

  -- Switched off: not listed at all.
  update public.user_notification_settings set quiet_enabled = false
  where user_id = '00000000-0000-4000-8000-0000000000a1';
  select count(*) into rows from public.quiet_hours_recipients(
    (select array_agg(id) from public.push_subscriptions), null);
  perform pg_temp.expect(rows = 0, 'switched off means not listed');
end $$;

-- Quiet hours change nothing about the claim: the claim function is the
-- version before this migration.
select pg_temp.expect(
  position('quiet' in pg_get_functiondef('public.claim_push_delivery(uuid, uuid)'::regprocedure)) = 0,
  'claim_push_delivery was not touched');

\o

do $$
declare
  failures text;
begin
  select string_agg(msg, E'\n') into failures from pg_temp.failures;
  if failures is not null then
    raise exception E'quiet hours checks failed:\n%', failures;
  end if;
end $$;

rollback;
