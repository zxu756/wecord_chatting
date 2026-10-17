-- Behaviour checks for events in group chats and direct messages
-- (migration 202610170050_chat_events). Run by
-- test/supabase/chat_events_behaviour_test.dart against the local database:
-- it applies the migration inside a transaction, plays people through the
-- RPCs and rolls everything back, so the database is left as it was. Run
-- from the repository root.
\set ON_ERROR_STOP on

begin;

-- The behaviour checks all run DDL and write the same tables; take turns so
-- they cannot deadlock when the test runner starts them together.
select pg_advisory_xact_lock(7771001);

\i supabase/migrations/202610170050_chat_events.sql

-- The push subscriptions table comes from an earlier migration that an old
-- local database may not have applied yet.
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null
);

create function pg_temp.act_as(who uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', who::text, true);
$$;

create function pg_temp.check_that(ok boolean, message text) returns void
language plpgsql as $$
begin
  if ok is not true then
    raise exception 'check failed: %', message;
  end if;
end $$;

create function pg_temp.expect_error(stmt text, code text) returns void
language plpgsql as $$
declare
  failed boolean := false;
begin
  begin
    execute stmt;
  exception when others then
    failed := true;
    if sqlstate <> code then
      raise exception 'wanted % but got % (%) from: %', code, sqlstate, sqlerrm, stmt;
    end if;
  end;
  if not failed then
    raise exception 'expected error % from: %', code, stmt;
  end if;
end $$;

-- Ada owns a group with Bob (member) and Cy (admin); Dee is outside.
insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@events.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@events.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@events.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee@events.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_events', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_events', 'Bob'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_events', 'Cy'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee_events', 'Dee');

insert into public.conversations (id, type, title)
values
  ('00000000-0000-4000-8000-00000000f001', 'group', 'Climbing crew'),
  ('00000000-0000-4000-8000-00000000f002', 'direct', null),
  ('00000000-0000-4000-8000-00000000f003', 'channel', 'general');
insert into public.conversation_members (conversation_id, user_id, role)
values
  ('00000000-0000-4000-8000-00000000f001', '00000000-0000-4000-8000-0000000000a1', 'owner'),
  ('00000000-0000-4000-8000-00000000f001', '00000000-0000-4000-8000-0000000000b1', 'member'),
  ('00000000-0000-4000-8000-00000000f001', '00000000-0000-4000-8000-0000000000c1', 'admin'),
  ('00000000-0000-4000-8000-00000000f002', '00000000-0000-4000-8000-0000000000a1', 'member'),
  ('00000000-0000-4000-8000-00000000f002', '00000000-0000-4000-8000-0000000000b1', 'member'),
  ('00000000-0000-4000-8000-00000000f003', '00000000-0000-4000-8000-0000000000a1', 'member');

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

-- Posting ------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');

do $$
declare
  created jsonb;
  announced record;
begin
  created := public.create_chat_event(
    '00000000-0000-4000-8000-00000000f001',
    '  Bouldering night  ',
    now() + interval '3 days',
    now() + interval '3 days 2 hours',
    'Bring chalk.',
    'The gym on 5th',
    'https://example.com/map',
    array[60, 15, 15],
    true
  );
  insert into ids values ('group_event', (created->>'id')::uuid);

  perform pg_temp.check_that(created->>'title' = 'Bouldering night', 'title is trimmed');
  perform pg_temp.check_that((created->>'going_count')::int = 1, 'the creator is going');
  perform pg_temp.check_that(created->>'my_status' = 'going', 'creator status');
  perform pg_temp.check_that((created->>'can_manage')::boolean, 'creator manages');
  perform pg_temp.check_that(created->>'pinned_at' is not null, 'pinned on create');
  perform pg_temp.check_that(created->'reminder_leads' = '[15, 60]'::jsonb, 'reminder leads are sorted and distinct');
  perform pg_temp.check_that(
    jsonb_array_length(created->'attendees') = 1
      and created->'attendees'->0->>'display_name' = 'Ada',
    'attendees list the creator'
  );

  select m.* into announced
  from public.messages m
  where m.conversation_id = '00000000-0000-4000-8000-00000000f001'
    and m.type = 'system';
  perform pg_temp.check_that(announced.attachment->>'kind' = 'event', 'announcement kind');
  perform pg_temp.check_that(
    (announced.attachment->>'event_id')::uuid = (created->>'id')::uuid,
    'announcement points at the event'
  );
  perform pg_temp.check_that(announced.body like '%Bouldering night%', 'announcement text');
  perform pg_temp.check_that(
    (select message_id from public.chat_events where id = (created->>'id')::uuid) = announced.id,
    'event remembers its announcement'
  );
end $$;

select pg_temp.expect_error(
  $$select public.create_chat_event('00000000-0000-4000-8000-00000000f001', '', now() + interval '1 day')$$,
  '22023'
);
select pg_temp.expect_error(
  $$select public.create_chat_event('00000000-0000-4000-8000-00000000f001', 'Past', now() - interval '1 day')$$,
  '22023'
);
select pg_temp.expect_error(
  $$select public.create_chat_event('00000000-0000-4000-8000-00000000f001', 'Backwards', now() + interval '2 days', now() + interval '1 day')$$,
  '22023'
);
-- Circle channels have their own events.
select pg_temp.expect_error(
  $$select public.create_chat_event('00000000-0000-4000-8000-00000000f003', 'Nope', now() + interval '1 day')$$,
  '22023'
);

select pg_temp.act_as('00000000-0000-4000-8000-0000000000d1');
select pg_temp.expect_error(
  $$select public.create_chat_event('00000000-0000-4000-8000-00000000f001', 'Outsider', now() + interval '1 day')$$,
  '42501'
);

-- Answering ----------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');

do $$
declare
  event_id uuid := (select id from ids where name = 'group_event');
  after jsonb;
begin
  after := public.rsvp_chat_event(event_id, 'going');
  perform pg_temp.check_that((after->>'going_count')::int = 2, 'two going');
  perform pg_temp.check_that(after->>'my_status' = 'going', 'my status going');

  after := public.rsvp_chat_event(event_id, 'maybe');
  perform pg_temp.check_that(
    (after->>'going_count')::int = 1 and (after->>'maybe_count')::int = 1,
    'changing the answer moves the count'
  );
  perform pg_temp.check_that(
    after->'attendees'->0->>'display_name' = 'Ada'
      and after->'attendees'->1->>'display_name' = 'Bob',
    'going attendees come first'
  );

  after := public.rsvp_chat_event(event_id, 'declined');
  perform pg_temp.check_that(
    (after->>'maybe_count')::int = 0 and (after->>'declined_count')::int = 1,
    'declined is counted apart'
  );
  perform pg_temp.check_that(jsonb_array_length(after->'attendees') = 1, 'declined people are not attendees');

  after := public.rsvp_chat_event(event_id, null);
  perform pg_temp.check_that(after->>'my_status' is null, 'clearing the answer');
  perform pg_temp.check_that((after->>'declined_count')::int = 0, 'cleared answers vanish');

  perform public.rsvp_chat_event(event_id, 'maybe');
end $$;

select pg_temp.expect_error(
  format($$select public.rsvp_chat_event(%L, 'attending')$$, (select id from ids where name = 'group_event')),
  '22023'
);

-- Members read through RLS, outsiders see nothing.
set local role authenticated;
do $$
begin
  perform pg_temp.check_that(
    (select count(*) from public.chat_events) = 1
      and (select count(*) from public.chat_event_rsvps) = 2,
    'a member reads the event and answers'
  );
end $$;
reset role;

select pg_temp.act_as('00000000-0000-4000-8000-0000000000d1');
set local role authenticated;
do $$
begin
  perform pg_temp.check_that(
    (select count(*) from public.chat_events) = 0
      and (select count(*) from public.chat_event_rsvps) = 0,
    'an outsider reads nothing'
  );
end $$;
reset role;

do $$
declare
  event_id uuid := (select id from ids where name = 'group_event');
begin
  perform pg_temp.check_that(public.get_chat_event(event_id) is null, 'outsiders get no event');
  perform pg_temp.check_that(
    (select count(*) from public.list_chat_events('00000000-0000-4000-8000-00000000f001')) = 0,
    'outsiders list no events'
  );
end $$;
select pg_temp.expect_error(
  format($$select public.rsvp_chat_event(%L, 'going')$$, (select id from ids where name = 'group_event')),
  '42501'
);

-- Managing -----------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select pg_temp.expect_error(
  format($$select public.cancel_chat_event(%L)$$, (select id from ids where name = 'group_event')),
  '42501'
);
select pg_temp.expect_error(
  format($$select public.pin_chat_event(%L, false)$$, (select id from ids where name = 'group_event')),
  '42501'
);
select pg_temp.expect_error(
  format($$select public.update_chat_event(%L, 'Hijacked', now() + interval '4 days')$$, (select id from ids where name = 'group_event')),
  '42501'
);

-- Cy is an admin of the group: may pin, and pinning moves the pin.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
do $$
declare
  first_id uuid := (select id from ids where name = 'group_event');
  second jsonb;
begin
  second := public.create_chat_event(
    '00000000-0000-4000-8000-00000000f001',
    'Gear swap',
    now() + interval '5 days'
  );
  insert into ids values ('second_event', (second->>'id')::uuid);
  perform pg_temp.check_that(second->>'pinned_at' is null, 'not pinned unless asked');
  perform pg_temp.check_that(second->'reminder_leads' = '[15]'::jsonb, 'default reminder is 15 minutes');

  perform public.pin_chat_event((second->>'id')::uuid, true);
  perform pg_temp.check_that(
    (select pinned_at is null from public.chat_events where id = first_id),
    'pinning another event unpins the first'
  );
  perform pg_temp.check_that(
    (select pinned_at is not null from public.chat_events where id = (second->>'id')::uuid),
    'the new event is pinned'
  );

  -- An admin may change someone else's event.
  perform public.update_chat_event(
    first_id, 'Bouldering night!', now() + interval '3 days',
    null, null, 'New gym', null, array[]::integer[]
  );
  perform pg_temp.check_that(
    (select title = 'Bouldering night!' and reminder_leads = '{}' and link_url is null
       from public.chat_events where id = first_id),
    'admin edits the event'
  );
  perform public.update_chat_event(
    first_id, 'Bouldering night!', now() + interval '3 days',
    null, null, 'New gym', null, array[15]
  );
end $$;

-- Listing ------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
do $$
declare
  listed jsonb[];
begin
  select array_agg(e) into listed
  from public.list_chat_events('00000000-0000-4000-8000-00000000f001') as e;
  perform pg_temp.check_that(cardinality(listed) = 2, 'both upcoming events are listed');
  perform pg_temp.check_that(listed[1]->>'title' = 'Bouldering night!', 'soonest first');

  -- A finished event only shows with include_past.
  insert into public.chat_events (
    conversation_id, created_by, title, starts_at, ends_at
  )
  values (
    '00000000-0000-4000-8000-00000000f001',
    '00000000-0000-4000-8000-0000000000a1',
    'Last week', now() - interval '8 days', now() - interval '8 days' + interval '1 hour'
  );
  perform pg_temp.check_that(
    (select count(*) from public.list_chat_events('00000000-0000-4000-8000-00000000f001')) = 2,
    'past events are hidden'
  );
  perform pg_temp.check_that(
    (select count(*) from public.list_chat_events('00000000-0000-4000-8000-00000000f001', true)) = 3,
    'past events show on request'
  );
end $$;

-- Direct messages: either person manages -----------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
do $$
declare
  dm jsonb;
begin
  dm := public.create_chat_event(
    '00000000-0000-4000-8000-00000000f002',
    'Coffee', now() + interval '1 day', null, null, null, null, array[60]
  );
  insert into ids values ('dm_event', (dm->>'id')::uuid);
end $$;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
do $$
declare
  dm_id uuid := (select id from ids where name = 'dm_event');
  after jsonb;
begin
  perform pg_temp.check_that((public.get_chat_event(dm_id)->>'can_manage')::boolean, 'the other person manages a direct event');
  perform public.rsvp_chat_event(dm_id, 'going');
  after := public.cancel_chat_event(dm_id);
  perform pg_temp.check_that(after->>'cancelled_at' is not null, 'cancelled');
end $$;
select pg_temp.expect_error(
  format($$select public.rsvp_chat_event(%L, 'going')$$, (select id from ids where name = 'dm_event')),
  '22023'
);

-- Reminders ----------------------------------------------------------------
-- A fresh event an hour away that reminds at 1 hour and 15 minutes.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
do $$
declare
  soon jsonb;
  soon_id uuid;
  starts timestamptz := now() + interval '50 minutes';
begin
  soon := public.create_chat_event(
    '00000000-0000-4000-8000-00000000f001',
    'Quick belay check', starts, null, null, null, null, array[15, 60]
  );
  soon_id := (soon->>'id')::uuid;
  insert into ids values ('soon_event', soon_id);

  perform public.rsvp_chat_event(soon_id, 'maybe');  -- no: Ada is the creator, now Maybe
  perform pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
  perform public.rsvp_chat_event(soon_id, 'going');
  perform pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  perform public.rsvp_chat_event(soon_id, 'declined');

  -- Two days before nothing is due.
  perform pg_temp.check_that(
    public.chat_event_due_reminders(starts - interval '2 days') = 0,
    'nothing due two days ahead'
  );
  -- 50 minutes ahead the 1 hour reminder is due for Going and Maybe people
  -- (Ada, Bob), not for Cy who declined. Earlier events are further away.
  perform pg_temp.check_that(
    public.chat_event_due_reminders(now()) = 2,
    'two people get the 1 hour reminder'
  );
  perform pg_temp.check_that(
    public.chat_event_due_reminders(now()) = 0,
    'running again adds nothing'
  );
  perform pg_temp.check_that(
    (select count(*) from public.chat_event_reminders where event_id = soon_id and lead_minutes = 60) = 2,
    'the reminders are the 1 hour ones'
  );

  -- Ten minutes ahead the 15 minute one is due; late answerers get only it.
  perform pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  perform public.rsvp_chat_event(soon_id, 'going');
  perform pg_temp.check_that(
    public.chat_event_due_reminders(starts - interval '10 minutes') = 3,
    'Ada, Bob and the late Cy get the 15 minute reminder'
  );
  perform pg_temp.check_that(
    (select count(*) from public.chat_event_reminders where event_id = soon_id and user_id = '00000000-0000-4000-8000-0000000000c1') = 1,
    'a late answer gets one reminder, not two'
  );
  perform pg_temp.check_that(
    public.chat_event_due_reminders(starts + interval '1 minute') = 0,
    'nothing after the start'
  );
end $$;

-- The inbox shows them, newest first, and they can be read.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
do $$
declare
  listed record;
begin
  select * into listed from public.list_chat_event_reminders();
  perform pg_temp.check_that(listed.title = 'Quick belay check' and listed.is_unread, 'the inbox lists the unread reminder');
  perform pg_temp.check_that(
    (select count(*) from public.list_chat_event_reminders()) = 2,
    'Bob has both reminders'
  );
  perform public.mark_chat_event_reminders_read();
  perform pg_temp.check_that(
    not exists (select 1 from public.list_chat_event_reminders() where is_unread),
    'marked read'
  );
end $$;

-- Push: one claim per reminder, nothing for muted chats or people without
-- a subscription.
insert into public.push_subscriptions (user_id, endpoint, p256dh, auth)
values
  ('00000000-0000-4000-8000-0000000000a1', 'https://push.example/ada', repeat('p', 60), repeat('a', 20)),
  ('00000000-0000-4000-8000-0000000000b1', 'https://push.example/bob', repeat('p', 60), repeat('a', 20));
update public.conversation_members
set muted_until = now() + interval '1 day'
where conversation_id = '00000000-0000-4000-8000-00000000f001'
  and user_id = '00000000-0000-4000-8000-0000000000b1';

do $$
declare
  claimed record;
  total integer;
begin
  select count(*) into total from public.claim_chat_event_reminder_pushes();
  -- Ada has two reminders (1 hour, 15 minutes) and one device; Bob is muted;
  -- Cy has no device.
  perform pg_temp.check_that(total = 2, format('Ada is pushed both reminders (got %s)', total));
  perform pg_temp.check_that(
    (select count(*) from public.claim_chat_event_reminder_pushes()) = 0,
    'pushes are claimed once'
  );
  perform pg_temp.check_that(
    (select count(*) from public.chat_event_reminders where push_sent_at is not null) = 5,
    'every reminder was marked, pushed or not'
  );
end $$;

-- Moving an event starts the reminders over; cancelling stops them.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
do $$
declare
  soon_id uuid := (select id from ids where name = 'soon_event');
begin
  perform public.update_chat_event(
    soon_id, 'Quick belay check', now() + interval '20 minutes',
    null, null, null, null, array[15, 60]
  );
  perform pg_temp.check_that(
    (select count(*) from public.chat_event_reminders where event_id = soon_id) = 0,
    'moving an event clears its reminders'
  );
  perform public.cancel_chat_event(soon_id);
  perform pg_temp.check_that(
    public.chat_event_due_reminders(now()) = 0,
    'cancelled events do not remind'
  );
end $$;

-- The scheduler functions are not for members.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
set local role authenticated;
select pg_temp.expect_error($$select public.chat_event_due_reminders()$$, '42501');
select pg_temp.expect_error($$select * from public.claim_chat_event_reminder_pushes()$$, '42501');
select pg_temp.expect_error(
  $$insert into public.chat_events (conversation_id, title, starts_at) values ('00000000-0000-4000-8000-00000000f001', 'Direct', now())$$,
  '42501'
);
reset role;

rollback;
