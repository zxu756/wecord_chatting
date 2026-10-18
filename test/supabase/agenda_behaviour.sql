-- Behaviour checks for My agenda and the calendar subscription (migrations
-- 202610210500 to 202610210520). Run by test/supabase/agenda_behaviour_test.dart
-- against the local database: it applies the migrations in a transaction,
-- plays people through the RPCs and rolls everything back. Run from the
-- repository root.
\set ON_ERROR_STOP on

begin;

do $$ begin perform pg_advisory_xact_lock(20261017); end $$;

\i supabase/migrations/202610170002_album_counts.sql
\i supabase/migrations/202610170003_album_summaries.sql
\i supabase/migrations/202610170004_album_push.sql
\i supabase/migrations/202610170005_push_language.sql
\i supabase/migrations/202610170010_scheduled_messages.sql
\i supabase/migrations/202610170011_message_reminders.sql
\i supabase/migrations/202610170012_saved_messages.sql
\i supabase/migrations/202610170020_disappearing_messages.sql
\i supabase/migrations/202610170021_view_once_media.sql

-- Chat events write push reminders; an old local database may lack the table.
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null
);

\i supabase/migrations/202610170050_chat_events.sql
\i supabase/migrations/202610170060_notes.sql
\i supabase/migrations/202610170061_note_versions_files.sql
\i supabase/migrations/202610170062_task_lists.sql
\i supabase/migrations/202610170090_ai_guard.sql
\i supabase/migrations/202610170091_ai_guard_hidden.sql
\i supabase/migrations/202610210500_calendar_feed_tokens.sql
\i supabase/migrations/202610210510_my_agenda.sql
\i supabase/migrations/202610210520_calendar_feed_items.sql

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

create function pg_temp.i(name text) returns uuid language sql as $$
  select id from ids where ids.name = i.name;
$$;
grant execute on function pg_temp.i(text) to public;

-- Acts as one of the people, as PostgREST would (null: nobody).
create function pg_temp.act_as(who text) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  if who is not null then
    perform set_config('request.jwt.claim.sub', pg_temp.i(who)::text, true);
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

create function pg_temp.kinds(who text, from_at timestamptz, to_at timestamptz)
returns text language plpgsql as $$
declare
  result text;
begin
  perform pg_temp.act_as(who);
  select coalesce(string_agg(a.kind || ':' || coalesce(a.title, '~'), ', ' order by a.starts_at, a.kind, a.title), '')
  into result
  from public.get_my_agenda(from_at, to_at) a;
  perform pg_temp.act_as(null);
  return result;
end;
$$;
grant execute on function pg_temp.kinds(text, timestamptz, timestamptz) to public;

-- People ------------------------------------------------------------------
insert into ids values
  ('ada', '00000000-0000-4000-8000-0000000000a1'),
  ('bob', '00000000-0000-4000-8000-0000000000b1'),
  ('eve', '00000000-0000-4000-8000-0000000000e1'),
  ('g1', '00000000-0000-4000-8000-00000000f001'),
  ('g2', '00000000-0000-4000-8000-00000000f002'),
  ('g3', '00000000-0000-4000-8000-00000000f005'),
  ('d_bob', '00000000-0000-4000-8000-00000000f003'),
  ('d_eve', '00000000-0000-4000-8000-00000000f004'),
  ('circle', '00000000-0000-4000-8000-00000000c001'),
  ('circle_event', '00000000-0000-4000-8000-00000000ce01');

insert into auth.users (id, email, instance_id, aud, role)
select id, name || '@agenda.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from ids where name in ('ada', 'bob', 'eve');
insert into public.profiles (id, username, display_name)
select id, name || '_agenda', initcap(name) from ids where name in ('ada', 'bob', 'eve');

insert into public.conversations (id, type, title)
values
  (pg_temp.i('g1'), 'group', 'Climbing crew'),
  (pg_temp.i('g2'), 'group', 'Book club'),
  (pg_temp.i('g3'), 'group', 'Chess club'),
  (pg_temp.i('d_bob'), 'direct', null),
  (pg_temp.i('d_eve'), 'direct', null);
insert into public.conversation_members (conversation_id, user_id, role)
values
  (pg_temp.i('g1'), pg_temp.i('ada'), 'owner'),
  (pg_temp.i('g1'), pg_temp.i('bob'), 'member'),
  (pg_temp.i('g2'), pg_temp.i('ada'), 'owner'),
  (pg_temp.i('g2'), pg_temp.i('bob'), 'member'),
  (pg_temp.i('g3'), pg_temp.i('bob'), 'owner'),
  (pg_temp.i('g3'), pg_temp.i('ada'), 'member'),
  (pg_temp.i('d_bob'), pg_temp.i('ada'), 'member'),
  (pg_temp.i('d_bob'), pg_temp.i('bob'), 'member'),
  (pg_temp.i('d_eve'), pg_temp.i('ada'), 'member'),
  (pg_temp.i('d_eve'), pg_temp.i('eve'), 'member');

insert into public.circles (id, name, owner_id)
values (pg_temp.i('circle'), 'Hiking circle', pg_temp.i('bob'));
insert into public.circle_members (circle_id, user_id, role)
values
  (pg_temp.i('circle'), pg_temp.i('bob'), 'owner'),
  (pg_temp.i('circle'), pg_temp.i('ada'), 'member');

-- Events -------------------------------------------------------------------
insert into public.chat_events (id, conversation_id, created_by, title, starts_at)
values
  ('00000000-0000-4000-8000-0000000e0001', pg_temp.i('g1'), pg_temp.i('bob'), 'Bouldering night', now() + interval '2 days'),
  ('00000000-0000-4000-8000-0000000e0002', pg_temp.i('g2'), pg_temp.i('bob'), 'Book swap', now() + interval '3 days'),
  ('00000000-0000-4000-8000-0000000e0003', pg_temp.i('g1'), pg_temp.i('bob'), 'Cancelled picnic', now() + interval '4 days'),
  ('00000000-0000-4000-8000-0000000e0004', pg_temp.i('g1'), pg_temp.i('bob'), 'Not coming', now() + interval '5 days'),
  ('00000000-0000-4000-8000-0000000e0005', pg_temp.i('d_eve'), pg_temp.i('eve'), 'Coffee with Eve', now() + interval '6 days');
update public.chat_events set cancelled_at = now()
where id = '00000000-0000-4000-8000-0000000e0003';
insert into public.chat_event_rsvps (event_id, user_id, status, conversation_id)
select e.id, pg_temp.i('ada'), s.status, e.conversation_id
from public.chat_events e
join (values
  ('00000000-0000-4000-8000-0000000e0001'::uuid, 'going'),
  ('00000000-0000-4000-8000-0000000e0002'::uuid, 'maybe'),
  ('00000000-0000-4000-8000-0000000e0003'::uuid, 'going'),
  ('00000000-0000-4000-8000-0000000e0004'::uuid, 'declined'),
  ('00000000-0000-4000-8000-0000000e0005'::uuid, 'going')
) as s(id, status) on s.id = e.id;

insert into public.circle_events (id, circle_id, title, location_type, location_text, starts_at, created_by)
values (pg_temp.i('circle_event'), pg_temp.i('circle'), 'Sunrise hike', 'external', 'North trail', now() + interval '1 day', pg_temp.i('bob'));
insert into public.circle_event_rsvps (event_id, circle_id, user_id)
values (pg_temp.i('circle_event'), pg_temp.i('circle'), pg_temp.i('ada'));

-- Tasks --------------------------------------------------------------------
insert into public.task_lists (id, conversation_id, title, created_by)
values
  ('00000000-0000-4000-8000-0000000a0001', pg_temp.i('g1'), 'Trip', pg_temp.i('bob')),
  ('00000000-0000-4000-8000-0000000a0002', pg_temp.i('g2'), 'Club', pg_temp.i('bob'));
insert into public.task_items (id, list_id, title, status, due_at, due_has_time, completed_at)
values
  ('00000000-0000-4000-8000-0000000b0001', '00000000-0000-4000-8000-0000000a0001', 'Book the hut', 'todo', now() + interval '2 days', true, null),
  ('00000000-0000-4000-8000-0000000b0002', '00000000-0000-4000-8000-0000000a0001', 'Done thing', 'done', now() + interval '2 days', true, now()),
  ('00000000-0000-4000-8000-0000000b0003', '00000000-0000-4000-8000-0000000a0001', 'No due date', 'todo', null, false, null),
  ('00000000-0000-4000-8000-0000000b0004', '00000000-0000-4000-8000-0000000a0002', 'Pick the book', 'todo', now() + interval '3 days', false, null),
  ('00000000-0000-4000-8000-0000000b0005', '00000000-0000-4000-8000-0000000a0001', 'Not mine', 'todo', now() + interval '2 days', true, null),
  ('00000000-0000-4000-8000-0000000b0006', '00000000-0000-4000-8000-0000000a0001', 'Overdue chore', 'todo', now() - interval '2 days', false, null);
insert into public.task_item_assignees (item_id, list_id, user_id)
select i.id, i.list_id, pg_temp.i('ada')
from public.task_items i
where i.id <> '00000000-0000-4000-8000-0000000b0005';

-- Messages, reminders and scheduled messages -------------------------------
insert into public.messages (id, conversation_id, sender_id, body)
values
  ('00000000-0000-4000-8000-0000000c0001', pg_temp.i('g1'), pg_temp.i('bob'), 'Bring the rope'),
  ('00000000-0000-4000-8000-0000000c0002', pg_temp.i('g1'), pg_temp.i('bob'), 'Gone soon'),
  ('00000000-0000-4000-8000-0000000c0003', pg_temp.i('g3'), pg_temp.i('bob'), 'Held for review'),
  ('00000000-0000-4000-8000-0000000c0004', pg_temp.i('g2'), pg_temp.i('bob'), 'Chapter one'),
  ('00000000-0000-4000-8000-0000000c0005', pg_temp.i('g1'), pg_temp.i('bob'), 'Recalled words');
update public.messages set expires_at = now() - interval '1 minute'
where id = '00000000-0000-4000-8000-0000000c0002';
update public.messages set review_state = 'held'
where id = '00000000-0000-4000-8000-0000000c0003';
update public.messages set recalled_at = now()
where id = '00000000-0000-4000-8000-0000000c0005';

insert into public.message_reminders (id, user_id, message_id, conversation_id, remind_at, dismissed_at)
values
  ('00000000-0000-4000-8000-0000000d0001', pg_temp.i('ada'), '00000000-0000-4000-8000-0000000c0001', pg_temp.i('g1'), now() + interval '1 day', null),
  ('00000000-0000-4000-8000-0000000d0002', pg_temp.i('ada'), '00000000-0000-4000-8000-0000000c0002', pg_temp.i('g1'), now() + interval '1 day 1 hour', null),
  ('00000000-0000-4000-8000-0000000d0003', pg_temp.i('ada'), '00000000-0000-4000-8000-0000000c0003', pg_temp.i('g3'), now() + interval '1 day 2 hours', null),
  ('00000000-0000-4000-8000-0000000d0004', pg_temp.i('ada'), '00000000-0000-4000-8000-0000000c0004', pg_temp.i('g2'), now() + interval '2 days', null),
  ('00000000-0000-4000-8000-0000000d0005', pg_temp.i('ada'), '00000000-0000-4000-8000-0000000c0001', pg_temp.i('g1'), now() + interval '2 days', now()),
  ('00000000-0000-4000-8000-0000000d0006', pg_temp.i('ada'), '00000000-0000-4000-8000-0000000c0005', pg_temp.i('g1'), now() + interval '1 day 3 hours', null),
  ('00000000-0000-4000-8000-0000000d0007', pg_temp.i('bob'), '00000000-0000-4000-8000-0000000c0001', pg_temp.i('g1'), now() + interval '1 day', null);

insert into public.scheduled_messages (id, owner_id, conversation_id, body, send_at, status)
values
  ('00000000-0000-4000-8000-0000000f0001', pg_temp.i('ada'), pg_temp.i('g1'), 'Happy birthday!', now() + interval '12 hours', 'pending'),
  ('00000000-0000-4000-8000-0000000f0002', pg_temp.i('ada'), pg_temp.i('g2'), 'Reading tonight', now() + interval '13 hours', 'pending'),
  ('00000000-0000-4000-8000-0000000f0003', pg_temp.i('ada'), pg_temp.i('g1'), 'Already sent', now() + interval '14 hours', 'sent'),
  ('00000000-0000-4000-8000-0000000f0004', pg_temp.i('ada'), pg_temp.i('g1'), 'Failed one', now() + interval '15 hours', 'failed'),
  ('00000000-0000-4000-8000-0000000f0005', pg_temp.i('bob'), pg_temp.i('g1'), 'Bob own', now() + interval '16 hours', 'pending');

-- What Ada sees ------------------------------------------------------------
do $$
declare
  mine text;
begin
  -- Not signed in: refused.
  perform pg_temp.act_as(null);
  begin
    perform * from public.get_my_agenda(now(), now() + interval '30 days');
    raise exception 'FAILED: anonymous agenda was allowed';
  exception when sqlstate '42501' then
    null;
  end;

  mine := pg_temp.kinds('ada', now() - interval '10 days', now() + interval '30 days');
  raise notice 'ada: %', mine;

  perform pg_temp.check('chat events: going and maybe only',
    mine like '%chat_event:Bouldering night%' and mine like '%chat_event:Book swap%'
    and mine not like '%Not coming%' and mine not like '%Cancelled picnic%');
  perform pg_temp.check('circle event I am interested in', mine like '%circle_event:Sunrise hike%');
  perform pg_temp.check('open tasks assigned to me with a due date',
    mine like '%task:Book the hut%' and mine like '%task:Pick the book%'
    and mine like '%task:Overdue chore%'
    and mine not like '%Done thing%' and mine not like '%No due date%' and mine not like '%Not mine%');
  perform pg_temp.check('reminders: text only while readable',
    mine like '%reminder:Bring the rope%'
    and mine like '%reminder:Chapter one%'
    and mine not like '%Gone soon%' and mine not like '%Held for review%' and mine not like '%Recalled words%');
  perform pg_temp.check('pending scheduled messages only, mine only',
    mine like '%scheduled_message:Happy birthday!%' and mine like '%scheduled_message:Reading tonight%'
    and mine not like '%Already sent%' and mine not like '%Failed one%' and mine not like '%Bob own%');
  perform pg_temp.check('a direct chat is named after the other person',
    (select place_name from public.agenda_items_for_user(pg_temp.i('ada'), now(), now() + interval '30 days') where target_id = '00000000-0000-4000-8000-0000000e0005') = 'Eve');
end $$;

do $$
declare
  rows_in_range integer;
begin
  perform pg_temp.act_as('ada');
  select count(*) into rows_in_range
  from public.get_my_agenda(now(), now() + interval '30 days') a
  where a.kind = 'reminder';
  perform pg_temp.check('five open reminders: the dismissed one and Bob''s are not Ada''s agenda', rows_in_range = 5);
  select count(*) into rows_in_range
  from public.get_my_agenda(now(), now() + interval '30 days') a
  where a.kind = 'reminder' and a.title is null;
  perform pg_temp.check('reminders about expired, held and recalled messages carry no text', rows_in_range = 3);

  begin
    perform * from public.get_my_agenda(now(), now() - interval '1 day');
    raise exception 'FAILED: backwards range accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform * from public.get_my_agenda(now(), now() + interval '500 days');
    raise exception 'FAILED: huge range accepted';
  exception when sqlstate '22023' then null;
  end;

  -- The range cuts: nothing within the first hour.
  perform pg_temp.check('the range limits the list',
    (select count(*) from public.get_my_agenda(now(), now() + interval '1 hour')) = 0);
  -- Places are named.
  perform pg_temp.check('conversation and circle names',
    (select place_name from public.get_my_agenda(now(), now() + interval '30 days') where title = 'Bouldering night') = 'Climbing crew'
    and (select place_name from public.get_my_agenda(now(), now() + interval '30 days') where title = 'Sunrise hike') = 'Hiking circle');
  perform pg_temp.act_as(null);
end $$;

-- Leaving a group removes its items -----------------------------------------
do $$
declare
  before_leaving text;
  after_leaving text;
begin
  before_leaving := pg_temp.kinds('ada', now() - interval '10 days', now() + interval '30 days');
  perform pg_temp.check('before leaving the book club',
    before_leaving like '%Book swap%' and before_leaving like '%Pick the book%'
    and before_leaving like '%Chapter one%' and before_leaving like '%Reading tonight%');

  delete from public.conversation_members
  where conversation_id = pg_temp.i('g2') and user_id = pg_temp.i('ada');

  after_leaving := pg_temp.kinds('ada', now() - interval '10 days', now() + interval '30 days');
  perform pg_temp.check('after leaving the group its event, task, reminder and scheduled message are gone',
    after_leaving not like '%Book swap%' and after_leaving not like '%Pick the book%'
    and after_leaving not like '%Chapter one%' and after_leaving not like '%Reading tonight%');
  perform pg_temp.check('the other groups are untouched',
    after_leaving like '%Bouldering night%' and after_leaving like '%Book the hut%'
    and after_leaving like '%Happy birthday!%' and after_leaving like '%Bring the rope%');

  -- Being removed from the chat has the same effect.
  delete from public.conversation_members
  where conversation_id = pg_temp.i('g1') and user_id = pg_temp.i('ada');
  after_leaving := pg_temp.kinds('ada', now() - interval '10 days', now() + interval '30 days');
  perform pg_temp.check('after leaving the climbing crew too',
    after_leaving not like '%Bouldering night%' and after_leaving not like '%Book the hut%'
    and after_leaving not like '%Happy birthday!%' and after_leaving not like '%Bring the rope%'
    and after_leaving not like '%Overdue chore%');
  perform pg_temp.check('the circle event and the other chats stay',
    after_leaving like '%Sunrise hike%' and after_leaving like '%Coffee with Eve%');

  -- A held message is not Ada's to read, but her reminder stays (no text).
  perform pg_temp.check('a held message stays hidden from a member',
    after_leaving like '%reminder:~%' and after_leaving not like '%Held for review%');
end $$;

-- Leaving a circle ----------------------------------------------------------
do $$
declare
  result text;
begin
  delete from public.circle_members
  where circle_id = pg_temp.i('circle') and user_id = pg_temp.i('ada');
  result := pg_temp.kinds('ada', now(), now() + interval '30 days');
  perform pg_temp.check('after leaving the circle its event is gone', result not like '%Sunrise hike%');
end $$;

-- Blocking ------------------------------------------------------------------
do $$
declare
  result text;
begin
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('eve'), pg_temp.i('ada'));
  result := pg_temp.kinds('ada', now(), now() + interval '30 days');
  perform pg_temp.check('a direct chat with someone who blocked me is left out', result not like '%Coffee with Eve%');
  delete from public.blocks;
  result := pg_temp.kinds('ada', now(), now() + interval '30 days');
  perform pg_temp.check('and comes back when the block ends', result like '%Coffee with Eve%');
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('ada'), pg_temp.i('eve'));
  result := pg_temp.kinds('ada', now(), now() + interval '30 days');
  perform pg_temp.check('a direct chat with someone I blocked is left out', result not like '%Coffee with Eve%');
  delete from public.blocks;
end $$;

-- Bob sees his own -------------------------------------------------------------
do $$
declare
  result text;
begin
  insert into public.chat_event_rsvps (event_id, user_id, status, conversation_id)
  values ('00000000-0000-4000-8000-0000000e0001', pg_temp.i('bob'), 'going', pg_temp.i('g1'));
  result := pg_temp.kinds('bob', now(), now() + interval '30 days');
  perform pg_temp.check('another person gets their own list',
    result like '%Bouldering night%' and result like '%reminder:Bring the rope%'
    and result like '%scheduled_message:Bob own%' and result not like '%Happy birthday!%'
    and result not like '%Book the hut%');
end $$;

-- The calendar subscription ---------------------------------------------------
create function pg_temp.hash(token text) returns text language sql as $$
  select encode(sha256(convert_to(token, 'UTF8')), 'hex');
$$;
grant execute on function pg_temp.hash(text) to public;

do $$
declare
  first_token text;
  second_token text;
  feed jsonb;
  settings jsonb;
begin
  -- Put Ada back in her groups and circle, so there is something to show.
  insert into public.conversation_members (conversation_id, user_id, role)
  values (pg_temp.i('g1'), pg_temp.i('ada'), 'owner'), (pg_temp.i('g2'), pg_temp.i('ada'), 'owner');
  insert into public.circle_members (circle_id, user_id, role)
  values (pg_temp.i('circle'), pg_temp.i('ada'), 'member');
  insert into public.circle_event_rsvps (event_id, circle_id, user_id)
  values (pg_temp.i('circle_event'), pg_temp.i('circle'), pg_temp.i('ada'));

  -- Signed-out people cannot make a link; signed-in people make their own.
  perform pg_temp.act_as(null);
  begin
    perform public.create_calendar_feed_token();
    raise exception 'FAILED: anonymous token allowed';
  exception when sqlstate '42501' then null;
  end;

  perform pg_temp.act_as('ada');
  settings := public.get_calendar_feed_settings();
  perform pg_temp.check('no link yet', settings->>'enabled' = 'false');
  first_token := public.create_calendar_feed_token(false, 480, 'zh-CN');
  perform pg_temp.check('the token is 192 random bits in hex, with no user id',
    first_token ~ '^[0-9a-f]{48}$' and position(replace(pg_temp.i('ada')::text, '-', '') in first_token) = 0);
  settings := public.get_calendar_feed_settings();
  perform pg_temp.check('the link exists and shows no content by default',
    settings->>'enabled' = 'true' and settings->>'include_content' = 'false');

  -- Nobody can read the table, and the token itself is not in it.
  begin
    perform count(*) from public.calendar_feed_tokens;
    raise exception 'FAILED: tokens table readable';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.act_as(null);
  perform pg_temp.check('only the hash is stored',
    (select count(*) from public.calendar_feed_tokens where token_hash = first_token) = 0
    and (select token_hash from public.calendar_feed_tokens) = pg_temp.hash(first_token));

  -- The service door.
  feed := public.calendar_feed_items(pg_temp.hash(first_token), now() - interval '1 day', now() + interval '60 days');
  perform pg_temp.check('the feed answers ok with Ada''s options',
    feed->>'status' = 'ok' and feed->>'include_content' = 'false'
    and feed->>'language' = 'zh' and (feed->>'utc_offset_minutes')::int = 480);
  perform pg_temp.check('events and tasks only',
    (select count(*) from jsonb_array_elements(feed->'items') i) = 6
    and not exists (
      select 1 from jsonb_array_elements(feed->'items') i
      where i->>'kind' not in ('chat_event', 'circle_event', 'task')
    ));
  perform pg_temp.check('the feed''s lookup leaves no person set',
    coalesce(current_setting('request.jwt.claim.sub', true), '') = '');

  perform pg_temp.check('an unknown token is invalid',
    public.calendar_feed_items(pg_temp.hash('nope'), now(), now() + interval '1 day')->>'status' = 'invalid'
    and public.calendar_feed_items('not-a-hash', now(), now() + interval '1 day')->>'status' = 'invalid'
    and public.calendar_feed_items(null, now(), now() + interval '1 day')->>'status' = 'invalid');

  -- The content switch.
  perform pg_temp.act_as('ada');
  perform public.set_calendar_feed_options(true);
  perform pg_temp.act_as(null);
  perform pg_temp.check('content can be switched on',
    public.calendar_feed_items(pg_temp.hash(first_token), now(), now() + interval '60 days')->>'include_content' = 'true');

  -- Reset: the old link stops working.
  perform pg_temp.act_as('ada');
  second_token := public.create_calendar_feed_token(false, 0, 'en');
  perform pg_temp.act_as(null);
  perform pg_temp.check('a reset makes a different token', second_token <> first_token);
  perform pg_temp.check('the old token is dead and the new one works',
    public.calendar_feed_items(pg_temp.hash(first_token), now(), now() + interval '1 day')->>'status' = 'invalid'
    and public.calendar_feed_items(pg_temp.hash(second_token), now(), now() + interval '1 day')->>'status' = 'ok');
  perform pg_temp.check('a reset starts with content off again',
    public.calendar_feed_items(pg_temp.hash(second_token), now(), now() + interval '1 day')->>'include_content' = 'false');

  -- Rate limit: 30 requests an hour.
  update public.calendar_feed_tokens set window_started_at = now(), window_count = 0;
  for n in 1..30 loop
    feed := public.calendar_feed_items(pg_temp.hash(second_token), now(), now() + interval '1 day');
    if feed->>'status' <> 'ok' then
      raise exception 'FAILED: request % was refused', n;
    end if;
  end loop;
  feed := public.calendar_feed_items(pg_temp.hash(second_token), now(), now() + interval '1 day');
  perform pg_temp.check('the 31st request in an hour is limited',
    feed->>'status' = 'limited' and (feed->>'retry_after')::int between 1 and 3600);
  perform pg_temp.check('a refused request is not counted again',
    (select window_count from public.calendar_feed_tokens) = 30);
  update public.calendar_feed_tokens set window_started_at = now() - interval '2 hours';
  perform pg_temp.check('the window resets after an hour',
    public.calendar_feed_items(pg_temp.hash(second_token), now(), now() + interval '1 day')->>'status' = 'ok');

  -- Who may call what.
  perform pg_temp.check('signed-in people cannot call the service doors',
    not has_function_privilege('authenticated', 'public.calendar_feed_items(text, timestamptz, timestamptz)', 'execute')
    and not has_function_privilege('anon', 'public.calendar_feed_items(text, timestamptz, timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public.agenda_items_for_user(uuid, timestamptz, timestamptz, text[])', 'execute')
    and not has_function_privilege('authenticated', 'public.agenda_items_core(timestamptz, timestamptz, text[])', 'execute')
    and has_function_privilege('service_role', 'public.calendar_feed_items(text, timestamptz, timestamptz)', 'execute')
    and has_function_privilege('authenticated', 'public.get_my_agenda(timestamptz, timestamptz)', 'execute')
    and not has_function_privilege('anon', 'public.get_my_agenda(timestamptz, timestamptz)', 'execute'));

  -- A deleted account's link stops working.
  update public.profiles set deleted_at = now() where id = pg_temp.i('ada');
  perform pg_temp.check('a deleted account''s link is invalid',
    public.calendar_feed_items(pg_temp.hash(second_token), now(), now() + interval '1 day')->>'status' = 'invalid');
  update public.profiles set deleted_at = null where id = pg_temp.i('ada');

  -- Turning it off.
  perform pg_temp.act_as('ada');
  perform public.delete_calendar_feed_token();
  perform pg_temp.check('turned off', public.get_calendar_feed_settings()->>'enabled' = 'false');
  perform pg_temp.act_as(null);
  perform pg_temp.check('a turned-off link is invalid',
    public.calendar_feed_items(pg_temp.hash(second_token), now(), now() + interval '1 day')->>'status' = 'invalid');
end $$;

rollback;
