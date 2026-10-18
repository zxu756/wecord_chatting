-- Behaviour checks for the AI guard (migrations 202610170090 and 202610170091).
-- Run by test/supabase/ai_guard_behaviour_test.dart against a local database
-- that has the earlier migrations; it applies the ones it lacks and these two
-- inside a transaction, acts as several people, checks what they can see, get
-- pushed and decide, and rolls back, so the database (and its cron jobs) is
-- left as it was. Run from the repository root.
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
\i supabase/migrations/202610170020_disappearing_messages.sql
\i supabase/migrations/202610170021_view_once_media.sql
\i supabase/migrations/202610170090_ai_guard.sql
\i supabase/migrations/202610170091_ai_guard_hidden.sql

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@guard.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'mod@guard.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'newt@guard.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d1', 'olly@guard.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve@guard.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_guard', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'mod_guard', 'Mo'),
  ('00000000-0000-4000-8000-0000000000c1', 'newt_guard', 'Newt'),
  ('00000000-0000-4000-8000-0000000000d1', 'olly_guard', 'Olly'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve_guard', 'Eve');

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

-- Runs [stmt] and fails unless it raises SQLSTATE [code].
create function pg_temp.refused(label text, stmt text, code text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    if sqlstate <> code then
      raise exception 'FAILED: % (wanted %, got % %)', label, code, sqlstate, sqlerrm;
    end if;
    raise notice 'ok: %', label;
    return;
  end;
  raise exception 'FAILED: % (nothing was refused)', label;
end;
$$;

-- Sends a text message as one of the people and returns its id (null when
-- AutoMod dropped it).
create function pg_temp.say(who text, text_body text, mention_of text default null)
returns uuid language plpgsql as $$
declare
  sent uuid;
  mentions jsonb := '[]'::jsonb;
begin
  perform pg_temp.act_as(who);
  if mention_of is not null then
    mentions := jsonb_build_array(jsonb_build_object(
      'kind', 'user',
      'user_id', format('00000000-0000-4000-8000-0000000000%s1', mention_of),
      'display_name', 'x',
      'start', 0,
      'end', 1
    ));
  end if;
  sent := public.send_text_message(
    (select id from ids where name = 'channel'),
    text_body, null, null, mentions
  );
  perform pg_temp.act_as(null);
  return sent;
end;
$$;
grant execute on function pg_temp.say(text, text, text) to public;

-- Eve's conversation list row for the channel, whoever is acting.
create function pg_temp.eve_summary()
returns table (unread_count bigint, last_message_body text, last_message_at timestamptz)
language plpgsql as $$
begin
  perform pg_temp.act_as('e');
  return query
  select s.unread_count, s.last_message_body, s.last_message_at
  from public.list_conversation_summaries() s
  where s.id = (select id from ids where name = 'channel');
  perform pg_temp.act_as(null);
end;
$$;
grant execute on function pg_temp.eve_summary() to public;

-- Ada's circle: Mo moderates, Newt joined just now, Olly ten days ago, Eve
-- is a reader with a push subscription.
select pg_temp.act_as('a');
insert into ids select 'circle', public.create_circle('Guarded circle', array[]::uuid[]);
select pg_temp.act_as(null);

insert into ids
select 'channel', cc.conversation_id
from public.circle_channels cc
where cc.circle_id = (select id from ids where name = 'circle') and cc.position = 0;

insert into public.circle_members (circle_id, user_id, role, created_at)
select (select id from ids where name = 'circle'), u.id, 'member',
  case when u.id = '00000000-0000-4000-8000-0000000000d1' then now() - interval '10 days' else now() end
from (values
  ('00000000-0000-4000-8000-0000000000b1'::uuid),
  ('00000000-0000-4000-8000-0000000000c1'::uuid),
  ('00000000-0000-4000-8000-0000000000d1'::uuid),
  ('00000000-0000-4000-8000-0000000000e1'::uuid)
) u(id);
insert into public.conversation_members (conversation_id, user_id, role)
select (select id from ids where name = 'channel'), cm.user_id, cm.role
from public.circle_members cm
where cm.circle_id = (select id from ids where name = 'circle')
on conflict do nothing;

-- Mo has a role with manage messages.
with role as (
  insert into public.circle_roles (circle_id, name, position, permissions)
  values (
    (select id from ids where name = 'circle'), 'Mods', 1,
    public.circle_default_role_permissions() | 4
  )
  returning id
)
insert into public.circle_member_roles (circle_id, user_id, role_id)
select (select id from ids where name = 'circle'), '00000000-0000-4000-8000-0000000000b1', role.id
from role;

insert into public.push_subscriptions (user_id, endpoint, p256dh, auth)
values (
  '00000000-0000-4000-8000-0000000000e1',
  'https://push.example/eve',
  repeat('p', 60),
  repeat('a', 20)
);

-- ------------------------------------------------------------------ settings

-- Off by default: Newt's message is an ordinary one.
select pg_temp.act_as('a');
select pg_temp.check(
  'the guard is off by default and the circle AI is on',
  (select (g->>'enabled')::boolean = false
     and g->>'new_rule' = 'joined_days'
     and (g->>'joined_days')::int = 3
     and g->>'action' = 'hold'
     and (g->>'circle_ai_enabled')::boolean
   from (select public.get_circle_ai_guard((select id from ids where name = 'circle')) g) x)
);
select pg_temp.act_as(null);
insert into ids select 'plain', pg_temp.say('c', 'hello everyone');
select pg_temp.check(
  'an unguarded circle holds nothing',
  (select m.review_state is null from public.messages m where m.id = (select id from ids where name = 'plain'))
  and not exists (select 1 from public.message_reviews)
);

-- Only managers change it, and only valid values.
select pg_temp.act_as('c');
select pg_temp.refused('a member cannot read the guard settings',
  format('select public.get_circle_ai_guard(%L)', (select id from ids where name = 'circle')), '42501');
select pg_temp.refused('a member cannot change the guard',
  format('select public.set_circle_ai_guard(%L, true, ''joined_days'', 3, 10, ''hold'')', (select id from ids where name = 'circle')), '42501');
select pg_temp.act_as('b');
select pg_temp.refused('a moderator without manage circle cannot change the guard',
  format('select public.set_circle_ai_guard(%L, true, ''joined_days'', 3, 10, ''hold'')', (select id from ids where name = 'circle')), '42501');
select pg_temp.act_as('a');
select pg_temp.refused('2 days is not an option',
  format('select public.set_circle_ai_guard(%L, true, ''joined_days'', 2, 10, ''hold'')', (select id from ids where name = 'circle')), '22023');
select pg_temp.refused('delete is not an action',
  format('select public.set_circle_ai_guard(%L, true, ''joined_days'', 3, 10, ''delete'')', (select id from ids where name = 'circle')), '22023');
select public.set_circle_ai_guard((select id from ids where name = 'circle'), true, 'joined_days', 3, 10, 'hold');
select pg_temp.act_as(null);
select pg_temp.check(
  'saving the guard is audited',
  exists (
    select 1 from public.circle_audit_log
    where action = 'guard_update' and actor_id = '00000000-0000-4000-8000-0000000000a1'
      and changes->'enabled'->>'new' = 'true'
  )
);

-- The guard works only while the circle's AI switch is on.
update public.circles set ai_enabled = false where id = (select id from ids where name = 'circle');
insert into ids select 'ai_off', pg_temp.say('c', 'sent while AI is off');
select pg_temp.check(
  'with the circle AI off nothing is held',
  (select m.review_state is null from public.messages m where m.id = (select id from ids where name = 'ai_off'))
  and not exists (select 1 from public.message_reviews)
);
update public.circles set ai_enabled = true where id = (select id from ids where name = 'circle');

-- ----------------------------------------------------------------- fail open

-- Nothing can wake the function here (no Vault secrets): the message is
-- released at once and recorded as not checked.
insert into ids select 'unwakeable', pg_temp.say('c', 'sent with no way to wake the AI');
select pg_temp.check(
  'when the check cannot start the message is released, not checked',
  (select m.review_state is null from public.messages m where m.id = (select id from ids where name = 'unwakeable'))
  and (select r.state = 'released' and r.verdict = 'not_checked' and r.unchecked_reason = 'unavailable'
         and r.push_pending
       from public.message_reviews r where r.message_id = (select id from ids where name = 'unwakeable'))
);

-- Vault secrets the way the dispatcher has them.
select vault.create_secret('http://127.0.0.1:54321/functions/v1', 'wecord_functions_url');
select vault.create_secret('guard-test-secret', 'wecord_dispatch_secret');
delete from public.message_reviews;

-- What Eve sees before anything is held.
create temp table baseline as
select s.unread_count, s.last_message_body, s.last_message_at
from pg_temp.eve_summary() s;
grant select on baseline to public;

-- ------------------------------------------------------------------- holding

insert into ids select 'spam', pg_temp.say('c', 'Win cheap pills now http://evil.example', 'e');
select pg_temp.check(
  'a guarded member''s message waits for the check',
  (select m.review_state = 'checking' from public.messages m where m.id = (select id from ids where name = 'spam'))
  and (select r.state = 'checking' and r.mode = 'hold' and r.circle_id = (select id from ids where name = 'circle')
       from public.message_reviews r where r.message_id = (select id from ids where name = 'spam'))
);
select pg_temp.check(
  'the database woke the ai function with the shared secret',
  exists (
    select 1 from net.http_request_queue q
    where q.url = 'http://127.0.0.1:54321/functions/v1/ai'
      and q.headers->>'Authorization' = 'Bearer guard-test-secret'
      and convert_from(q.body, 'UTF8')::jsonb->>'action' = 'guard'
      and convert_from(q.body, 'UTF8')::jsonb->>'message_id' = (select id::text from ids where name = 'spam')
  )
);

-- Who sees it.
select pg_temp.act_as('c');
select pg_temp.check('the author sees it checking',
  (select count(*) = 1 from public.messages where id = (select id from ids where name = 'spam') and review_state = 'checking'));
select pg_temp.act_as('b');
select pg_temp.check('a moderator sees it',
  (select count(*) = 1 from public.messages where id = (select id from ids where name = 'spam')));
select pg_temp.act_as('e');
select pg_temp.check('another member does not',
  (select count(*) = 0 from public.messages where id = (select id from ids where name = 'spam')));
select pg_temp.act_as('d');
select pg_temp.check('nor does an old member',
  (select count(*) = 0 from public.messages where review_state is not null));

-- It does not count, notify or show for others.
select pg_temp.act_as('e');
select pg_temp.check(
  'the conversation list shows no unread and no latest message',
  (select s.unread_count = b.unread_count and s.last_message_body = b.last_message_body
          and s.last_message_at = b.last_message_at
   from public.list_conversation_summaries() s, baseline b
   where s.id = (select id from ids where name = 'channel'))
);
select pg_temp.check(
  'the circle rail shows no unread and no mention',
  (select s.mention_count = 0
   from public.list_circle_summaries() s where s.id = (select id from ids where name = 'circle'))
);
select pg_temp.check('the inbox shows no mention', (select count(*) = 0 from public.list_inbox()));
select pg_temp.check('search finds nothing',
  (select count(*) = 0 from public.search_messages('pills')));
select pg_temp.act_as(null);
select pg_temp.check(
  'a mention was recorded for later',
  (select count(*) = 1 from public.message_mentions where message_id = (select id from ids where name = 'spam'))
);
select pg_temp.check(
  'no push is handed out and none is marked as sent',
  (select count(*) = 0 from public.claim_push_delivery(
     (select id from ids where name = 'spam'), '00000000-0000-4000-8000-0000000000c1'))
  and not exists (select 1 from public.push_deliveries where message_id = (select id from ids where name = 'spam'))
);
insert into public.conversations (type, title) values ('group', 'Elsewhere') returning id \gset elsewhere_
insert into public.conversation_members (conversation_id, user_id, role)
values (:'elsewhere_id', '00000000-0000-4000-8000-0000000000b1', 'owner');
select pg_temp.act_as('b');
select pg_temp.refused('a message under review cannot be forwarded',
  format('select public.forward_message(%L, %L)', (select id from ids where name = 'spam'), :'elsewhere_id'), '42501');
select pg_temp.act_as(null);

-- The author cannot edit it into something the AI has not seen.
select pg_temp.act_as('c');
select pg_temp.refused('a message under review cannot be edited',
  format('select public.edit_message(%L, ''harmless'')', (select id from ids where name = 'spam')), '42501');
select pg_temp.act_as(null);

-- A client cannot choose its own state.
select pg_temp.act_as('d');
insert into public.messages (conversation_id, sender_id, type, body, review_state)
values ((select id from ids where name = 'channel'), '00000000-0000-4000-8000-0000000000d1', 'text', 'sneaky', 'removed');
select pg_temp.act_as(null);
select pg_temp.check(
  'a client cannot send a review state',
  (select review_state is null from public.messages where body = 'sneaky')
);

-- Only the function (service role) claims, answers and counts.
select pg_temp.act_as('c');
select pg_temp.refused('a member cannot finish a review',
  format('select public.finish_message_review(%L, ''allow'')', (select id from ids where name = 'spam')), '42501');
select pg_temp.refused('a member cannot claim a message',
  format('select * from public.ai_guard_claim(%L)', (select id from ids where name = 'spam')), '42501');
select pg_temp.act_as(null);

-- The function claims it once.
select pg_temp.check(
  'the function claims the text of the waiting message',
  (select count(*) = 1 and bool_and(c.body = 'Win cheap pills now http://evil.example' and c.ai_enabled)
   from public.ai_guard_claim((select id from ids where name = 'spam')) c)
);
select pg_temp.check(
  'a second claim right after gets nothing',
  (select count(*) = 0 from public.ai_guard_claim((select id from ids where name = 'spam')))
);

-- The AI's usage is charged to the circle.
select pg_temp.check(
  'requests are counted per circle with a limit',
  (select allowed and used = 1 from public.ai_consume_circle_request((select id from ids where name = 'circle'), 2))
  and (select allowed and used = 2 from public.ai_consume_circle_request((select id from ids where name = 'circle'), 2))
  and (select not allowed and used = 2 from public.ai_consume_circle_request((select id from ids where name = 'circle'), 2))
);
select public.ai_refund_circle_request((select id from ids where name = 'circle'));
select pg_temp.check('a refund gives one back',
  (select requests = 1 from public.ai_circle_usage where circle_id = (select id from ids where name = 'circle')));

-- The AI says spam: the message stays held.
select pg_temp.check(
  'a flagged message in hold mode is held',
  public.finish_message_review((select id from ids where name = 'spam'), 'spam', 'Looks like a pills advert') = 'held'
);
select pg_temp.check(
  'a second answer changes nothing',
  public.finish_message_review((select id from ids where name = 'spam'), 'allow') is null
);
select pg_temp.check(
  'the message is held for the moderators',
  (select m.review_state = 'held' from public.messages m where m.id = (select id from ids where name = 'spam'))
  and (select r.state = 'held' and r.verdict = 'spam' and r.reason = 'Looks like a pills advert' and not r.push_pending
       from public.message_reviews r where r.message_id = (select id from ids where name = 'spam'))
);
select pg_temp.check(
  'the hold is in the audit log without an actor',
  exists (
    select 1 from public.circle_audit_log
    where action = 'guard_hold' and actor_id is null and target_id = (select id from ids where name = 'spam')
      and changes->>'verdict' = 'spam' and changes->>'reason' = 'Looks like a pills advert'
  )
);
select pg_temp.act_as('c');
select pg_temp.check('the author sees it held',
  (select count(*) = 1 from public.messages where id = (select id from ids where name = 'spam') and review_state = 'held'));
select pg_temp.act_as('e');
select pg_temp.check('others still do not',
  (select count(*) = 0 from public.messages where id = (select id from ids where name = 'spam')));

-- ----------------------------------------------------------------- the queue

select pg_temp.act_as('b');
select pg_temp.check(
  'the moderator''s queue shows the message with the AI''s category and reason',
  (select count(*) = 1
     and bool_and(q.state = 'held' and q.verdict = 'spam' and q.reason = 'Looks like a pills advert'
                  and q.body = 'Win cheap pills now http://evil.example' and q.sender_name = 'Newt'
                  and q.channel_name = 'general')
   from public.list_message_reviews((select id from ids where name = 'circle')) q)
  and public.count_message_reviews((select id from ids where name = 'circle')) = 1
);
select pg_temp.act_as('e');
select pg_temp.check('a member sees no queue and no count',
  (select count(*) = 0 from public.list_message_reviews((select id from ids where name = 'circle')))
  and public.count_message_reviews((select id from ids where name = 'circle')) = 0);
select pg_temp.refused('a member cannot approve',
  format('select public.decide_message_review(%L, ''approve'')', (select id from ids where name = 'spam')), '42501');
select pg_temp.refused('a member cannot remove',
  format('select public.decide_message_review(%L, ''remove'')', (select id from ids where name = 'spam')), '42501');
select pg_temp.act_as('c');
select pg_temp.refused('the author cannot approve their own message',
  format('select public.decide_message_review(%L, ''approve'')', (select id from ids where name = 'spam')), '42501');

-- Mo removes it: it stays hidden from everyone but the author, as deleted.
select pg_temp.act_as('b');
select pg_temp.check('removing returns the new state',
  public.decide_message_review((select id from ids where name = 'spam'), 'remove') = 'removed');
select pg_temp.act_as(null);
select pg_temp.check(
  'a removed message loses its text, stays hidden, and its mentions go',
  (select m.review_state = 'removed' and m.recalled_at is not null and m.body = ''
          and m.recalled_by = '00000000-0000-4000-8000-0000000000b1'
   from public.messages m where m.id = (select id from ids where name = 'spam'))
  and not exists (select 1 from public.message_mentions where message_id = (select id from ids where name = 'spam'))
  and (select r.state = 'removed' and r.decided_by = '00000000-0000-4000-8000-0000000000b1' and not r.push_pending
       from public.message_reviews r where r.message_id = (select id from ids where name = 'spam'))
);
select pg_temp.check(
  'the removal is in the audit log with the moderator',
  exists (
    select 1 from public.circle_audit_log
    where action = 'guard_remove' and actor_id = '00000000-0000-4000-8000-0000000000b1'
      and target_id = (select id from ids where name = 'spam')
  )
);
select pg_temp.act_as('e');
select pg_temp.check('others never see the removed message',
  (select count(*) = 0 from public.messages where id = (select id from ids where name = 'spam')));
select pg_temp.act_as('b');
select pg_temp.check('the queue is empty again',
  public.count_message_reviews((select id from ids where name = 'circle')) = 0);
select pg_temp.refused('a decided message cannot be decided again',
  format('select public.decide_message_review(%L, ''approve'')', (select id from ids where name = 'spam')), 'P0002');
select pg_temp.act_as(null);

-- -------------------------------------------------------------- releasing

-- An allowed message is released: visible, the latest message, counted,
-- searchable, mentioned and pushed once.
insert into ids select 'fine', pg_temp.say('c', 'Hi all, happy to be here @Eve', 'e');
select pg_temp.check('it waits first',
  (select review_state = 'checking' from public.messages where id = (select id from ids where name = 'fine')));
select pg_temp.check(
  'an allowed message is released',
  public.finish_message_review((select id from ids where name = 'fine'), 'allow') = 'released'
);
select pg_temp.act_as('e');
select pg_temp.check('everyone sees it now',
  (select count(*) = 1 from public.messages where id = (select id from ids where name = 'fine') and review_state is null));
select pg_temp.check(
  'it is the latest message and unread',
  (select s.unread_count = (
            select count(*) from public.messages m
            where m.conversation_id = s.id and m.sender_id <> '00000000-0000-4000-8000-0000000000e1'
          )
          and s.last_message_body = 'Hi all, happy to be here @Eve'
   from public.list_conversation_summaries() s where s.id = (select id from ids where name = 'channel'))
);
select pg_temp.check('and a mention',
  (select s.mention_count = 1 from public.list_circle_summaries() s where s.id = (select id from ids where name = 'circle')));
select pg_temp.check('and searchable',
  (select count(*) = 1 from public.search_messages('happy')));
select pg_temp.act_as(null);
select pg_temp.check(
  'the release queued a push',
  (select push_pending from public.message_reviews where message_id = (select id from ids where name = 'fine'))
);
select pg_temp.check(
  'the dispatcher claims the release once',
  (select count(*) = 1 and bool_and(c.sender_id = '00000000-0000-4000-8000-0000000000c1')
   from public.claim_released_message_pushes() c where c.message_id = (select id from ids where name = 'fine'))
  and (select count(*) = 0 from public.claim_released_message_pushes())
);
select pg_temp.check(
  'and the push goes to the others, once',
  (select count(*) = 1 and bool_and(p.title like 'Newt%' and p.body = 'Hi all, happy to be here @Eve')
   from public.claim_push_delivery((select id from ids where name = 'fine'), '00000000-0000-4000-8000-0000000000c1') p)
  and (select count(*) = 0 from public.claim_push_delivery((select id from ids where name = 'fine'), '00000000-0000-4000-8000-0000000000c1'))
);
select pg_temp.check(
  'the release woke the dispatcher too',
  exists (select 1 from net.http_request_queue q where q.url = 'http://127.0.0.1:54321/functions/v1/scheduled-dispatch')
);

-- A message that waited long enough lands at the end of the chat.
insert into ids select 'late', pg_temp.say('c', 'Is the event on Friday?');
update public.messages set created_at = now() - interval '2 hours' where id = (select id from ids where name = 'late');
insert into ids select 'between', pg_temp.say('a', 'The owner talks meanwhile');
select pg_temp.check('the owner is never held',
  (select review_state is null from public.messages where id = (select id from ids where name = 'between')));
select public.finish_message_review((select id from ids where name = 'late'), 'allow');
select pg_temp.check(
  'a message that waited is moved to the end and becomes the latest',
  (select m.created_at >= (select created_at from public.messages where id = (select id from ids where name = 'between'))
   from public.messages m where m.id = (select id from ids where name = 'late'))
  and (select c.last_message_id = (select id from ids where name = 'late')
       from public.conversations c where c.id = (select id from ids where name = 'channel'))
);

-- ------------------------------------------------------- approving a held one

insert into ids select 'borderline', pg_temp.say('c', 'You people are all idiots');
select public.finish_message_review((select id from ids where name = 'borderline'), 'harassment', 'Insults other members');
update public.messages set created_at = now() - interval '30 minutes' where id = (select id from ids where name = 'borderline');
insert into ids select 'after', pg_temp.say('a', 'Anyway, welcome');
select pg_temp.act_as('e');
select pg_temp.check('a held message does not mark the chat unread',
  (select s.unread_count = (
            select count(*) from public.messages m
            where m.conversation_id = s.id and m.sender_id <> '00000000-0000-4000-8000-0000000000e1'
              and m.review_state is null and m.recalled_at is null
          )
   from public.list_conversation_summaries() s where s.id = (select id from ids where name = 'channel')));
select pg_temp.act_as('b');
select pg_temp.check('approving releases it',
  public.decide_message_review((select id from ids where name = 'borderline'), 'approve') = 'approved');
select pg_temp.act_as('e');
select pg_temp.check('the others see it, at the end, and it is unread',
  (select count(*) = 1 from public.messages m
   where m.id = (select id from ids where name = 'borderline')
     and m.review_state is null
     and m.created_at > (select created_at from public.messages where id = (select id from ids where name = 'after')))
  and (select s.unread_count = (
            select count(*) from public.messages m
            where m.conversation_id = s.id and m.sender_id <> '00000000-0000-4000-8000-0000000000e1'
              and m.review_state is null and m.recalled_at is null
          )
   from public.list_conversation_summaries() s where s.id = (select id from ids where name = 'channel')));
select pg_temp.act_as(null);
select pg_temp.check('approval is audited and queues the push',
  exists (select 1 from public.circle_audit_log where action = 'guard_approve' and actor_id = '00000000-0000-4000-8000-0000000000b1'
          and target_id = (select id from ids where name = 'borderline'))
  and (select push_pending and state = 'approved' from public.message_reviews where message_id = (select id from ids where name = 'borderline')));

-- --------------------------------------------------------------- flag mode

select pg_temp.act_as('a');
select public.set_circle_ai_guard((select id from ids where name = 'circle'), true, 'joined_days', 3, 10, 'flag');
select pg_temp.act_as(null);
insert into ids select 'flagme', pg_temp.say('c', 'Send me your password to claim a prize');
select pg_temp.check('in flag mode it still waits for the check',
  (select review_state = 'checking' from public.messages where id = (select id from ids where name = 'flagme')));
select pg_temp.check('a flagged message in flag mode is released with a flag',
  public.finish_message_review((select id from ids where name = 'flagme'), 'scam', 'Asks for a password') = 'flagged');
select pg_temp.act_as('e');
select pg_temp.check('everyone sees it',
  (select count(*) = 1 from public.messages where id = (select id from ids where name = 'flagme') and review_state is null));
select pg_temp.act_as('b');
select pg_temp.check('the moderators find it in the queue as flagged',
  (select count(*) = 1 and bool_and(q.state = 'flagged' and q.verdict = 'scam')
   from public.list_message_reviews((select id from ids where name = 'circle')) q));
select pg_temp.check('removing a visible message leaves a deleted message everyone sees',
  public.decide_message_review((select id from ids where name = 'flagme'), 'remove') = 'removed');
select pg_temp.act_as('e');
select pg_temp.check('which shows as deleted',
  (select count(*) = 1 from public.messages m
   where m.id = (select id from ids where name = 'flagme') and m.review_state is null and m.recalled_at is not null and m.body = ''));
select pg_temp.act_as(null);

-- Dismissing a flag just closes it.
insert into ids select 'flag2', pg_temp.say('c', 'Check out my channel');
select public.finish_message_review((select id from ids where name = 'flag2'), 'spam', 'Self promotion');
select pg_temp.act_as('b');
select pg_temp.check('approving a flagged message closes it',
  public.decide_message_review((select id from ids where name = 'flag2'), 'approve') = 'approved');
select pg_temp.check('the queue is empty', public.count_message_reviews((select id from ids where name = 'circle')) = 0);
select pg_temp.act_as(null);
select pg_temp.check('and a flag that was already visible keeps its push',
  (select push_pending and state = 'approved' from public.message_reviews where message_id = (select id from ids where name = 'flag2')));
select pg_temp.check('while a removed one is never pushed',
  (select not push_pending and state = 'removed' from public.message_reviews where message_id = (select id from ids where name = 'flagme')));

-- ---------------------------------------------------------- who counts as new

-- Olly joined ten days ago: not new by days...
select pg_temp.act_as('a');
select public.set_circle_ai_guard((select id from ids where name = 'circle'), true, 'joined_days', 7, 10, 'hold');
select pg_temp.act_as(null);
insert into ids select 'olly1', pg_temp.say('d', 'Olly here, an old member');
select pg_temp.check('a member who joined long ago is not held (7 days)',
  (select review_state is null from public.messages where id = (select id from ids where name = 'olly1')));
-- ... but with fewer than N messages he is.
select pg_temp.act_as('a');
select public.set_circle_ai_guard((select id from ids where name = 'circle'), true, 'message_count', 3, 5, 'hold');
select pg_temp.act_as(null);
insert into ids select 'olly2', pg_temp.say('d', 'My second message');
select pg_temp.check('with fewer than N messages an old member is held',
  (select review_state = 'checking' from public.messages where id = (select id from ids where name = 'olly2')));
select public.finish_message_review((select id from ids where name = 'olly2'), 'allow');
insert into ids select 'olly3', pg_temp.say('d', 'My third message');
select pg_temp.check('visible messages count, so the third is still checked (3 of 5 so far)',
  (select review_state = 'checking' from public.messages where id = (select id from ids where name = 'olly3')));
select public.finish_message_review((select id from ids where name = 'olly3'), 'spam', 'x');
insert into ids select 'olly4', pg_temp.say('d', 'Fourth, after a held one');
select pg_temp.check('a held message does not make a member trusted',
  (select review_state = 'checking' from public.messages where id = (select id from ids where name = 'olly4')));
select public.finish_message_review((select id from ids where name = 'olly4'), 'allow');
insert into ids select 'olly5', pg_temp.say('d', 'Fifth, four are visible');
select pg_temp.check('one short of N the member is still new',
  (select review_state = 'checking' from public.messages where id = (select id from ids where name = 'olly5')));
select public.finish_message_review((select id from ids where name = 'olly5'), 'allow');
insert into ids select 'olly6', pg_temp.say('d', 'Sixth, five are visible');
select pg_temp.check('after N visible messages the member is no longer new',
  (select review_state is null from public.messages where id = (select id from ids where name = 'olly6')));
select pg_temp.act_as('a');
select public.set_circle_ai_guard((select id from ids where name = 'circle'), true, 'joined_days', 3, 10, 'hold');
select pg_temp.act_as(null);

-- Moderators are never held even when new.
update public.circle_members set created_at = now() where user_id = '00000000-0000-4000-8000-0000000000b1';
insert into ids select 'mod1', pg_temp.say('b', 'Mo, brand new but a moderator');
select pg_temp.check('a new moderator is not held',
  (select review_state is null from public.messages where id = (select id from ids where name = 'mod1')));

-- Only text is checked: a picture message is not held.
select pg_temp.act_as('c');
insert into public.messages (conversation_id, sender_id, type, body, attachment)
values ((select id from ids where name = 'channel'), '00000000-0000-4000-8000-0000000000c1', 'image', '',
        jsonb_build_object('kind', 'image', 'bucket', 'chat-images',
          'path', (select id from ids where name = 'channel')::text || '/x.png'));
select pg_temp.act_as(null);
select pg_temp.check('pictures are not sent to the AI',
  (select review_state is null from public.messages where type = 'image' and sender_id = '00000000-0000-4000-8000-0000000000c1'));

-- ------------------------------------------------------- AutoMod still applies

insert into public.circle_automod_rules (circle_id, name, kind, keywords)
values ((select id from ids where name = 'circle'), 'No badword', 'keyword', array['badword']);
select pg_temp.check('AutoMod still blocks a guarded member''s message before the guard',
  (select pg_temp.say('c', 'this has a badword in it') is null)
  and not exists (select 1 from public.messages where body like '%badword%')
  and not exists (select 1 from public.message_reviews r join public.messages m on m.id = r.message_id where m.body like '%badword%'));

-- ---------------------------------------------------------------- fail open

-- A check that never came back is released by the sweep.
insert into ids select 'stuck', pg_temp.say('c', 'The AI never answers this one');
update public.message_reviews set created_at = now() - interval '2 minutes'
where message_id = (select id from ids where name = 'stuck');
insert into ids select 'fresh', pg_temp.say('c', 'This one is still being checked');
select public.run_ai_guard_sweep();
select pg_temp.check(
  'the sweep releases a check that timed out, not checked',
  (select m.review_state is null from public.messages m where m.id = (select id from ids where name = 'stuck'))
  and (select r.state = 'released' and r.verdict = 'not_checked' and r.unchecked_reason = 'timeout'
       from public.message_reviews r where r.message_id = (select id from ids where name = 'stuck'))
);
select pg_temp.check('and leaves a recent check alone',
  (select review_state = 'checking' from public.messages where id = (select id from ids where name = 'fresh')));

-- Limit, error and not configured are all not-checked releases.
select pg_temp.check('a limit releases the message, not checked',
  public.finish_message_review((select id from ids where name = 'fresh'), 'not_checked', null, 'limit') = 'released');
select pg_temp.check('and says why',
  (select unchecked_reason = 'limit' and verdict = 'not_checked' from public.message_reviews where message_id = (select id from ids where name = 'fresh'))
  and (select review_state is null from public.messages where id = (select id from ids where name = 'fresh')));
insert into ids select 'err', pg_temp.say('c', 'A provider error happens here');
select pg_temp.check('an error releases the message, not checked',
  public.finish_message_review((select id from ids where name = 'err'), 'not_checked', null, 'error') = 'released');
select pg_temp.check('and the message is visible',
  (select review_state is null from public.messages where id = (select id from ids where name = 'err')));
select pg_temp.refused('an unknown verdict is refused',
  format('select public.finish_message_review(%L, ''maybe'')', (select id from ids where name = 'err')), '22023');

rollback;
