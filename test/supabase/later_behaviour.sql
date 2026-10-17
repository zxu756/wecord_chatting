-- Behaviour checks for scheduled messages, reminders and saved messages
-- (migrations 202610170010 to 202610170012). Run by
-- test/supabase/later_behaviour_test.dart against a local database that has
-- the earlier migrations; it applies these migrations inside a transaction
-- and rolls everything back, so the database (and its cron jobs) is left
-- as it was. Run from the repository root.
\set ON_ERROR_STOP on

begin;

-- One behaviour script at a time: they change the same tables, and test
-- files run in parallel.
select pg_advisory_xact_lock(7770001);

\i supabase/migrations/202610170010_scheduled_messages.sql
\i supabase/migrations/202610170011_message_reminders.sql
\i supabase/migrations/202610170012_saved_messages.sql

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@later.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@later.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@later.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_later', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_later', 'Bob'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_later', 'Cy');

-- Acts as one of the people, as PostgREST would.
create function pg_temp.act_as(who text) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  if who is not null then
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

-- Ada's group with Bob (Cy is outside it).
with conv as (
  insert into public.conversations (type, title) values ('group', 'Later group') returning id
), members as (
  insert into public.conversation_members (conversation_id, user_id, role)
  select conv.id, member.id, member.role
  from conv, (values
    ('00000000-0000-4000-8000-0000000000a1'::uuid, 'owner'),
    ('00000000-0000-4000-8000-0000000000b1'::uuid, 'member')
  ) as member(id, role)
)
insert into ids select 'group', id from conv;

-- ---------------------------------------------------------------- scheduled

select pg_temp.act_as('a');

-- Ada queues a message for the future.
insert into public.scheduled_messages (owner_id, conversation_id, body, send_at)
select '00000000-0000-4000-8000-0000000000a1', id, '  See you at 9  ', now() + interval '1 hour'
from ids where name = 'group';
select pg_temp.check(
  'a queued message is pending and trimmed',
  (select count(*) = 1 and bool_and(status = 'pending' and body = 'See you at 9')
   from public.scheduled_messages)
);

-- The past is refused; so is queueing for someone else or a conversation
-- the caller is not in.
do $$
begin
  begin
    insert into public.scheduled_messages (owner_id, conversation_id, body, send_at)
    select '00000000-0000-4000-8000-0000000000a1', id, 'late', now() - interval '1 hour'
    from ids where name = 'group';
    raise exception 'FAILED: a time in the past was accepted';
  exception when sqlstate '22023' then
    raise notice 'ok: the past is refused';
  end;
  begin
    insert into public.scheduled_messages (owner_id, conversation_id, body, send_at)
    select '00000000-0000-4000-8000-0000000000b1', id, 'as bob', now() + interval '1 hour'
    from ids where name = 'group';
    raise exception 'FAILED: queued as somebody else';
  exception when insufficient_privilege then
    raise notice 'ok: queueing as somebody else is refused';
  end;
end;
$$;

-- Bob sees none of Ada's queue, and cannot change or delete it.
select pg_temp.act_as('b');
select pg_temp.check(
  'the queue is private',
  (select count(*) = 0 from public.scheduled_messages)
);
update public.scheduled_messages set body = 'hacked';
delete from public.scheduled_messages;
select pg_temp.act_as(null);
select pg_temp.check(
  'others cannot edit or delete it',
  (select count(*) = 1 and bool_and(body = 'See you at 9') from public.scheduled_messages)
);

-- Cy is not in the group.
select pg_temp.act_as('c');
do $$
begin
  insert into public.scheduled_messages (owner_id, conversation_id, body, send_at)
  select '00000000-0000-4000-8000-0000000000c1', id, 'hi', now() + interval '1 hour'
  from ids where name = 'group';
  raise exception 'FAILED: a non-member queued a message';
exception when insufficient_privilege then
  raise notice 'ok: non-members cannot queue';
end;
$$;

-- Ada edits her message: the new text and time stick, the conversation
-- cannot be changed.
select pg_temp.act_as('a');
update public.scheduled_messages
set body = 'See you at 10', send_at = now() + interval '2 hours';
select pg_temp.check(
  'editing changes the text and time',
  (select count(*) = 1 and bool_and(body = 'See you at 10' and send_at > now() + interval '90 minutes')
   from public.scheduled_messages)
);
do $$
begin
  update public.scheduled_messages set conversation_id = gen_random_uuid();
  raise exception 'FAILED: moved to another conversation';
exception when insufficient_privilege then
  raise notice 'ok: the conversation is fixed';
end;
$$;

-- Nothing is due yet.
select pg_temp.act_as(null);
select pg_temp.check(
  'nothing is sent early',
  public.dispatch_due_scheduled_messages() = 0
  and not exists (select 1 from public.messages where body = 'See you at 10')
);

-- Due: the cron job sends it as Ada, once.
update public.scheduled_messages set send_at = now() - interval '5 seconds';
select pg_temp.check('a due message is sent', public.dispatch_due_scheduled_messages() = 1);
select pg_temp.check(
  'it is Ada''s message in the group with the scheduled id as client id',
  (select count(*) = 1
     and bool_and(m.sender_id = '00000000-0000-4000-8000-0000000000a1'
       and m.conversation_id = (select id from ids where name = 'group')
       and m.client_id = s.id and s.status = 'sent' and s.sent_message_id = m.id)
   from public.messages m
   join public.scheduled_messages s on s.sent_message_id = m.id
   where m.body = 'See you at 10')
);
select pg_temp.check('dispatching again sends nothing', public.dispatch_due_scheduled_messages() = 0);
select pg_temp.check(
  'the push is claimed once',
  (select count(*) = 1 from public.claim_scheduled_message_pushes())
  and (select count(*) = 0 from public.claim_scheduled_message_pushes())
);
-- The cron job's call with a push waiting but no Vault secrets (or pg_net)
-- here: it must not fail.
update public.scheduled_messages set push_claimed_at = null where status = 'sent';
do $$
begin
  perform public.run_later_dispatch();
  raise notice 'ok: the cron wake-up works without Vault secrets';
end;
$$;

-- Send now.
select pg_temp.act_as('a');
insert into public.scheduled_messages (owner_id, conversation_id, body, send_at)
select '00000000-0000-4000-8000-0000000000a1', id, 'Right away', now() + interval '1 day'
from ids where name = 'group';
create temp table sent_now (id uuid);
grant all on sent_now to public;
insert into sent_now
select public.send_scheduled_message_now(
  (select id from public.scheduled_messages where body = 'Right away')
);
select pg_temp.check(
  'send now delivers at once',
  (select count(*) = 1 from sent_now where id is not null)
  and exists (select 1 from public.messages m join sent_now n on n.id = m.id where m.body = 'Right away')
);

-- Ada leaves the group before a queued message goes out: it fails with the
-- reason, and nothing is sent.
insert into public.scheduled_messages (owner_id, conversation_id, body, send_at)
select '00000000-0000-4000-8000-0000000000a1', id, 'Too late', now() + interval '1 hour'
from ids where name = 'group';
select pg_temp.act_as(null);
delete from public.conversation_members
where user_id = '00000000-0000-4000-8000-0000000000a1'
  and conversation_id = (select id from ids where name = 'group');
update public.scheduled_messages set send_at = now() - interval '1 second' where body = 'Too late';
select public.dispatch_due_scheduled_messages();
select pg_temp.check(
  'a refused message fails with the reason',
  (select count(*) = 1 and bool_and(status = 'failed' and last_error is not null)
   from public.scheduled_messages where body = 'Too late')
  and not exists (select 1 from public.messages where body = 'Too late')
);

-- Slowmode: Bob's queued message waits out the channel's slowmode.
select pg_temp.act_as(null);
insert into public.friendships (user_low_id, user_high_id)
values ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000b1');
select pg_temp.act_as('a');
select public.create_circle('Slow circle', array['00000000-0000-4000-8000-0000000000b1']::uuid[]);
select pg_temp.act_as(null);
insert into ids
select 'channel', cc.conversation_id
from public.circle_channels cc
join public.circles c on c.id = cc.circle_id
where c.name = 'Slow circle'
order by cc."position"
limit 1;
update public.circle_channels set slowmode_seconds = 600
where conversation_id = (select id from ids where name = 'channel');
insert into public.messages (conversation_id, sender_id, type, body)
select id, '00000000-0000-4000-8000-0000000000b1', 'text', 'first' from ids where name = 'channel';
insert into public.scheduled_messages (owner_id, conversation_id, body, send_at)
select '00000000-0000-4000-8000-0000000000b1', id, 'second', now() + interval '1 hour'
from ids where name = 'channel';
update public.scheduled_messages set send_at = now() - interval '1 second' where body = 'second';
select public.dispatch_due_scheduled_messages();
select pg_temp.check(
  'slowmode puts the message back for later',
  (select count(*) = 1
     and bool_and(status = 'pending' and attempts = 1 and send_at > now() + interval '5 minutes')
   from public.scheduled_messages where body = 'second')
  and not exists (select 1 from public.messages where body = 'second')
);

-- ---------------------------------------------------------------- reminders

-- Ada got a message from Bob (the group had Ada removed above: add her back).
select pg_temp.act_as(null);
insert into public.conversation_members (conversation_id, user_id, role)
select id, '00000000-0000-4000-8000-0000000000a1', 'member' from ids where name = 'group';
insert into public.messages (conversation_id, sender_id, type, body)
select id, '00000000-0000-4000-8000-0000000000b1', 'text', 'Bring the tripod' from ids where name = 'group';
insert into ids
select 'tripod', m.id from public.messages m where m.body = 'Bring the tripod';

select pg_temp.act_as('a');
create temp table reminder_ids (id uuid);
grant all on reminder_ids to public;
insert into reminder_ids
select public.set_message_reminder((select id from ids where name = 'tripod'), now() + interval '1 hour');

do $$
begin
  begin
    perform public.set_message_reminder((select id from ids where name = 'tripod'), now() - interval '1 day');
    raise exception 'FAILED: a past reminder was accepted';
  exception when sqlstate '22023' then
    raise notice 'ok: a reminder in the past is refused';
  end;
end;
$$;

select pg_temp.check(
  'an upcoming reminder lists as not fired with the message',
  (select count(*) = 1 and bool_and(not fired and available and body = 'Bring the tripod' and sender_display_name = 'Bob')
   from public.list_my_reminders())
);

-- Setting it again moves it rather than adding another.
select public.set_message_reminder((select id from ids where name = 'tripod'), now() + interval '3 hours');
select pg_temp.check(
  'one open reminder per message',
  (select count(*) = 1 from public.list_my_reminders())
  and (select count(*) = 1 from public.message_reminders)
);

-- Others cannot see it or remind about what they cannot read.
select pg_temp.act_as('b');
select pg_temp.check(
  'reminders are private',
  (select count(*) = 0 from public.list_my_reminders())
  and (select count(*) = 0 from public.message_reminders)
);
select pg_temp.act_as('c');
do $$
begin
  perform public.set_message_reminder((select id from ids where name = 'tripod'), now() + interval '1 hour');
  raise exception 'FAILED: reminded about a message in a group Cy is not in';
exception when sqlstate 'P0002' then
  raise notice 'ok: no reminders about messages the caller cannot read';
end;
$$;

-- Time passes: the reminder is fired for the list, and the open app is told
-- once.
select pg_temp.act_as(null);
update public.message_reminders set remind_at = now() - interval '2 minutes';
select pg_temp.act_as('a');
select pg_temp.check(
  'a due reminder lists as fired',
  (select count(*) = 1 and bool_and(fired) from public.list_my_reminders())
);
create temp table claimed_local (n integer);
grant all on claimed_local to public;
insert into claimed_local select count(*) from public.claim_local_reminders();
insert into claimed_local select count(*) from public.claim_local_reminders();
select pg_temp.check(
  'the open app is told once, with the sender and text',
  (select array_agg(n order by ctid) = array[1, 0] from claimed_local)
);

-- The push: claimed once for Ada's subscription, "Reminder" / "Bob: text".
select pg_temp.act_as(null);
insert into public.push_subscriptions (user_id, endpoint, p256dh, auth)
values (
  '00000000-0000-4000-8000-0000000000a1',
  'https://push.example.com/ada',
  repeat('p', 60),
  repeat('a', 20)
);
create temp table pushes as select * from public.claim_reminder_pushes();
select pg_temp.check(
  'the reminder is pushed once as "Reminder" with the sender and text',
  (select count(*) = 1 and bool_and(title = 'Reminder' and body = 'Bob: Bring the tripod'
     and endpoint = 'https://push.example.com/ada' and tag like 'reminder-%') from pushes)
  and (select count(*) = 0 from public.claim_reminder_pushes())
);

-- Do Not Disturb keeps the push back, and a deleted message reads as
-- unavailable.
insert into public.messages (conversation_id, sender_id, type, body)
select id, '00000000-0000-4000-8000-0000000000b1', 'text', 'Second thing' from ids where name = 'group';
select pg_temp.act_as('a');
select public.set_message_reminder((select id from public.messages where body = 'Second thing'), now() + interval '1 hour');
select pg_temp.act_as(null);
update public.message_reminders set remind_at = now() - interval '1 minute'
where message_id = (select id from public.messages where body = 'Second thing');
insert into public.user_privacy_settings (user_id, presence_status)
values ('00000000-0000-4000-8000-0000000000a1', 'dnd')
on conflict (user_id) do update set presence_status = 'dnd';
select pg_temp.check('Do Not Disturb holds the push back', (select count(*) = 0 from public.claim_reminder_pushes()));

update public.messages set recalled_at = now(), body = '' where body = 'Second thing';
select pg_temp.act_as('a');
select pg_temp.check(
  'a deleted message reads as unavailable',
  (select count(*) = 1 from public.list_my_reminders() where not available and body is null)
);

-- Dismissing takes it off the list; the cron call copes.
select public.dismiss_message_reminder(r.reminder_id) from public.list_my_reminders() r;
select pg_temp.check('dismissed reminders are gone', (select count(*) = 0 from public.list_my_reminders()));
select pg_temp.act_as(null);
do $$
begin
  perform public.run_later_dispatch();
  raise notice 'ok: the cron call copes with reminders';
end;
$$;

-- -------------------------------------------------------------------- saved

select pg_temp.act_as('a');
create temp table saved_ids (name text, id uuid);
grant all on saved_ids to public;
insert into saved_ids
select 'tripod', public.save_message((select id from ids where name = 'tripod'));
insert into saved_ids
select 'again', public.save_message((select id from ids where name = 'tripod'));
select pg_temp.check(
  'saving twice keeps one entry',
  (select count(distinct id) = 1 from saved_ids)
  and (select count(*) = 1 from public.saved_messages)
);

select pg_temp.check(
  'a saved message lists with its text and sender',
  (select count(*) = 1
     and bool_and(available and body = 'Bring the tripod' and sender_display_name = 'Bob'
       and done_at is null)
   from public.list_saved_messages())
);

-- Others cannot save what they cannot read, and see nothing of Ada's list.
select pg_temp.act_as('c');
do $$
begin
  perform public.save_message((select id from ids where name = 'tripod'));
  raise exception 'FAILED: saved a message Cy cannot read';
exception when sqlstate 'P0002' then
  raise notice 'ok: nothing is saved that the caller cannot read';
end;
$$;
select pg_temp.check(
  'the saved list is private',
  (select count(*) = 0 from public.list_saved_messages())
  and (select count(*) = 0 from public.saved_messages)
);
select pg_temp.act_as('b');
delete from public.saved_messages;
select pg_temp.act_as(null);
select pg_temp.check(
  'others cannot remove it',
  (select count(*) = 1 from public.saved_messages)
);

-- Done and back.
select pg_temp.act_as('a');
select public.set_saved_message_done((select id from public.saved_messages), true);
select pg_temp.check(
  'mark done',
  (select count(*) = 1 and bool_and(done_at is not null) from public.list_saved_messages())
);
select public.set_saved_message_done((select id from public.saved_messages), false);
select pg_temp.check(
  'undo makes it active again',
  (select count(*) = 1 and bool_and(done_at is null) from public.list_saved_messages())
);

-- Lose access: Ada leaves the group, the entry stays, as unavailable.
select pg_temp.act_as(null);
delete from public.conversation_members
where user_id = '00000000-0000-4000-8000-0000000000a1'
  and conversation_id = (select id from ids where name = 'group');
select pg_temp.act_as('a');
select pg_temp.check(
  'a message the user can no longer read is unavailable',
  (select count(*) = 1 and bool_and(not available and body is null and sender_display_name is null)
   from public.list_saved_messages())
);
select pg_temp.act_as(null);
insert into public.conversation_members (conversation_id, user_id, role)
select id, '00000000-0000-4000-8000-0000000000a1', 'member' from ids where name = 'group';

-- Deleting the message (as the sender does) leaves the entry unavailable.
update public.messages set recalled_at = now(), body = '' where body = 'Bring the tripod';
select pg_temp.act_as('a');
select pg_temp.check(
  'a deleted message is unavailable',
  (select count(*) = 1 and bool_and(not available and body is null) from public.list_saved_messages())
);

-- Hard deletion clears the link but keeps the entry, which can be removed.
select pg_temp.act_as(null);
delete from public.messages where body = '';
select pg_temp.act_as('a');
select pg_temp.check(
  'a removed message leaves an unavailable entry',
  (select count(*) = 1 and bool_and(message_id is null and not available)
   from public.list_saved_messages())
);
delete from public.saved_messages;
select pg_temp.check('removing deletes the entry', (select count(*) = 0 from public.list_saved_messages()));

rollback;
