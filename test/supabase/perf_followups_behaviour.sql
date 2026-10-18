-- Behaviour checks for the performance follow-ups (migrations
-- 202610190060 to 202610190062): get_chains reads several chains at once,
-- get_conversation_capabilities answers what the chat thread needs in one
-- call, get_conversation_summary is one row of list_conversation_summaries.
-- Run by test/supabase/perf_followups_test.dart against the local database
-- inside a transaction that is rolled back. Run from the repository root.
--
-- The local database may lack recent migrations, so the script rebuilds the
-- public schema from ALL migrations, in order, inside the transaction (and
-- throws it away at the end).
\set ON_ERROR_STOP on

begin;

-- Behaviour scripts that apply DDL take turns.
select pg_advisory_xact_lock(20261017);
set local client_min_messages = warning;

-- A scratch copy of the schema: everything the migrations make is dropped
-- and made again from the files, so the result does not depend on how far
-- the local database got.
do $$
declare r record;
begin
  for r in
    select policyname, tablename, schemaname from pg_policies
    where schemaname in ('storage', 'realtime') and tablename in ('objects', 'messages')
  loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;
set local storage.allow_delete_query = 'true';
delete from storage.buckets;
drop schema public cascade;
create schema public;
grant usage on schema public to postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on functions to postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on sequences to postgres, anon, authenticated, service_role;


-- Every migration, in order.
\set migrations `f=$(mktemp); for m in supabase/migrations/*.sql; do echo "\\i $m" >> "$f"; done; echo "$f"`
\i :migrations
\! rm -f :migrations

\o /dev/null
create temp table failures (msg text);
grant all on failures to public;

create function pg_temp.expect(ok boolean, msg text) returns void
language plpgsql security definer as $$
begin
  if not coalesce(ok, false) then
    insert into pg_temp.failures values (msg);
  end if;
end $$;

-- Becomes [user_id] (null: nobody signed in).
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

create function pg_temp.root() returns void language plpgsql as $$
begin
  execute 'reset role';
end $$;

-- Whether running [statement] as the current role raises an error.
create function pg_temp.refused(statement text) returns boolean language plpgsql as $$
begin
  execute statement;
  return false;
exception when others then
  return true;
end $$;

grant execute on all functions in schema pg_temp to public;

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create function pg_temp.i(n text) returns uuid language sql as $$ select id from pg_temp.ids where name = n $$;
grant execute on function pg_temp.i(text) to public;

-- ------------------------------------------------------------------ cast
-- Ada owns the group, Dee is its admin, Bob a plain member. Cy knows
-- nobody. Ada also owns a circle with Bob in it.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '@perf.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '_perf', initcap(name)
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || n)::uuid
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(x.a, x.b), greatest(x.a, x.b)
from (values
  (pg_temp.i('ada'), pg_temp.i('bob')),
  (pg_temp.i('ada'), pg_temp.i('dee'))
) x(a, b);

insert into pg_temp.ids select 'group', gen_random_uuid();
insert into pg_temp.ids select 'group2', gen_random_uuid();
insert into pg_temp.ids select 'direct', gen_random_uuid();
insert into public.conversations (id, type, title)
values
  (pg_temp.i('group'), 'group', 'Hike club'),
  (pg_temp.i('group2'), 'group', 'Other group'),
  (pg_temp.i('direct'), 'direct', null);
insert into public.conversation_members (conversation_id, user_id, role)
values
  (pg_temp.i('group'), pg_temp.i('ada'), 'owner'),
  (pg_temp.i('group'), pg_temp.i('dee'), 'admin'),
  (pg_temp.i('group'), pg_temp.i('bob'), 'member'),
  (pg_temp.i('group2'), pg_temp.i('cy'), 'owner'),
  (pg_temp.i('direct'), pg_temp.i('ada'), 'member'),
  (pg_temp.i('direct'), pg_temp.i('bob'), 'member');

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'circle', public.create_circle('Perf circle', array[pg_temp.i('bob')]);
select pg_temp.root();
insert into pg_temp.ids
select 'channel', cc.conversation_id from public.circle_channels cc
where cc.circle_id = pg_temp.i('circle') order by cc.position limit 1;

-- Messages: text from everybody (so there are unread ones), an album of
-- two pictures, a mention, a pinned conversation.
insert into public.messages (id, conversation_id, sender_id, type, body)
select gen_random_uuid(), pg_temp.i('group'), pg_temp.i(who), 'text', 'hello ' || n
from (values ('ada', 1), ('bob', 2), ('dee', 3), ('bob', 4)) v(who, n);
insert into public.messages (conversation_id, sender_id, type, body, attachment, attachment_group_id)
select pg_temp.i('group'), pg_temp.i('bob'), 'image', '',
  jsonb_build_object('bucket', 'chat-images', 'path', pg_temp.i('group') || '/p' || n || '.png', 'mime_type', 'image/png', 'size', 10),
  '11111111-1111-4111-8111-111111111111'
from generate_series(1, 2) n;
insert into public.messages (conversation_id, sender_id, type, body)
values (pg_temp.i('direct'), pg_temp.i('ada'), 'text', 'psst'),
       (pg_temp.i('direct'), pg_temp.i('bob'), 'text', 'hi ada'),
       (pg_temp.i('channel'), pg_temp.i('ada'), 'text', 'welcome to the channel'),
       (pg_temp.i('channel'), pg_temp.i('bob'), 'text', 'thanks');
insert into public.message_mentions (message_id, conversation_id, user_id)
select c.last_message_id, c.id, pg_temp.i('ada') from public.conversations c where c.id = pg_temp.i('group');
update public.conversation_members set pinned_at = now()
where conversation_id = pg_temp.i('direct') and user_id = pg_temp.i('ada');

-- A thread in the circle channel (Bob started it), Ada's note to self.
select pg_temp.act(pg_temp.i('bob'));
insert into pg_temp.ids
select 'thread_conv', (public.create_thread(pg_temp.i('channel'), null, 'Plans')->>'conversation_id')::uuid;
select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'self', public.get_note_to_self(true);
select pg_temp.root();

-- Chains: two in the group (Ada's, Dee's), one in the other group.
select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'chain_a', (public.create_chain(pg_temp.i('group'), 'Saturday hike', 'bring snacks', null, null, null)->>'chain_id')::uuid;
select public.join_chain(pg_temp.i('chain_a'), 'me');
select pg_temp.act(pg_temp.i('dee'));
insert into pg_temp.ids select 'chain_d', (public.create_chain(pg_temp.i('group'), 'Dinner', null, null, null, 5)->>'chain_id')::uuid;
select pg_temp.act(pg_temp.i('bob'));
select public.join_chain(pg_temp.i('chain_a'), 'plus one');
select public.join_chain(pg_temp.i('chain_d'), '');
select pg_temp.act(pg_temp.i('cy'));
insert into pg_temp.ids select 'chain_other', (public.create_chain(pg_temp.i('group2'), 'Cy only', null, null, null, null)->>'chain_id')::uuid;
select pg_temp.root();

-- ===================================================== 1. get_chains
do $$
declare
  r jsonb;
  who text;
  cid uuid;
begin
  -- Members read their chains together, and each is exactly what get_chain says.
  foreach who in array array['ada', 'bob', 'dee'] loop
    perform pg_temp.act(pg_temp.i(who));
    r := public.get_chains(array[pg_temp.i('chain_a'), pg_temp.i('chain_d')]);
    perform pg_temp.expect(jsonb_array_length(r) = 2, 'get_chains: ' || who || ' reads both chains');
    for cid in select unnest(array[pg_temp.i('chain_a'), pg_temp.i('chain_d')]) loop
      perform pg_temp.expect(
        (select e from jsonb_array_elements(r) e where e->>'id' = cid::text) = public.get_chain(cid),
        'get_chains: ' || who || ' gets exactly what get_chain answers');
    end loop;
  end loop;

  -- The caller's own line and rights are the caller's.
  perform pg_temp.act(pg_temp.i('bob'));
  r := public.get_chains(array[pg_temp.i('chain_a')]);
  perform pg_temp.expect((r->0->>'my_entry_id') is not null, 'get_chains: my_entry_id is the caller''s');
  perform pg_temp.expect((r->0->>'can_manage')::boolean = false, 'get_chains: a plain member cannot manage');
  perform pg_temp.act(pg_temp.i('ada'));
  r := public.get_chains(array[pg_temp.i('chain_a')]);
  perform pg_temp.expect((r->0->>'can_manage')::boolean, 'get_chains: the creator can manage');

  -- An outsider reads nothing: not even that the chains exist.
  perform pg_temp.act(pg_temp.i('cy'));
  r := public.get_chains(array[pg_temp.i('chain_a'), pg_temp.i('chain_d')]);
  perform pg_temp.expect(r = '[]'::jsonb, 'get_chains: an outsider gets nothing');
  perform pg_temp.expect(pg_temp.refused(format('select public.get_chain(%L)', pg_temp.i('chain_a'))),
    'get_chain still refuses an outsider');

  -- Mixed: some readable, some not, some unknown ids, duplicates.
  perform pg_temp.act(pg_temp.i('bob'));
  r := public.get_chains(array[
    pg_temp.i('chain_a'), pg_temp.i('chain_other'), gen_random_uuid(),
    pg_temp.i('chain_a'), null, pg_temp.i('chain_d')]);
  perform pg_temp.expect(jsonb_array_length(r) = 2, 'get_chains: only the readable chains, once each');
  perform pg_temp.expect(not exists (
    select 1 from jsonb_array_elements(r) e where e->>'id' = pg_temp.i('chain_other')::text),
    'get_chains: a chain of a group the caller is not in is left out');

  -- Empty and null lists.
  perform pg_temp.expect(public.get_chains(array[]::uuid[]) = '[]'::jsonb, 'get_chains: empty list');
  perform pg_temp.expect(public.get_chains(null) = '[]'::jsonb, 'get_chains: null list');

  -- At most 50.
  perform pg_temp.expect(pg_temp.refused('select public.get_chains(array(select gen_random_uuid() from generate_series(1, 51)))'),
    'get_chains: more than 50 ids are refused');
  perform pg_temp.expect(not pg_temp.refused('select public.get_chains(array(select gen_random_uuid() from generate_series(1, 50)))'),
    'get_chains: 50 ids are fine');

  -- Nobody signed in, and the anonymous role.
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused(format('select public.get_chains(array[%L::uuid])', pg_temp.i('chain_a'))),
    'get_chains: anonymous callers are refused');

  -- A deleted card takes its chain with it, here too.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.recall_message((select message_id from public.chains where id = pg_temp.i('chain_a')));
  perform pg_temp.act(pg_temp.i('bob'));
  r := public.get_chains(array[pg_temp.i('chain_a'), pg_temp.i('chain_d')]);
  perform pg_temp.expect(jsonb_array_length(r) = 1 and r->0->>'id' = pg_temp.i('chain_d')::text,
    'get_chains: a chain whose card was deleted is gone');
end $$;

-- =========================================== 2. get_conversation_capabilities
do $$
declare
  who text;
  conv text;
  caps jsonb;
  conv_id uuid;
begin
  -- It says exactly what the four helpers say, for everyone, everywhere
  -- (including a conversation that is not there).
  foreach who in array array['ada', 'bob', 'cy', 'dee'] loop
    perform pg_temp.act(pg_temp.i(who));
    foreach conv in array array['group', 'group2', 'direct', 'channel', 'thread_conv', 'self', 'nowhere'] loop
      conv_id := case when conv = 'nowhere' then gen_random_uuid() else pg_temp.i(conv) end;
      caps := public.get_conversation_capabilities(conv_id);
      perform pg_temp.expect(
        (caps->>'can_pin_messages')::boolean = public.can_current_user_pin_messages(conv_id)
        and (caps->>'can_moderate_polls')::boolean = public.can_current_user_moderate_polls(conv_id)
        and (caps->>'can_moderate_messages')::boolean = public.can_current_user_moderate_messages(conv_id)
        and (caps->>'can_manage_thread')::boolean = coalesce((
          select public.can_current_user_manage_thread(ct.id)
          from public.conversation_threads ct where ct.conversation_id = conv_id), false),
        'capabilities: ' || who || ' in ' || conv || ' matches the helpers');
    end loop;
  end loop;

  -- And the answers themselves are right.
  perform pg_temp.act(pg_temp.i('ada'));
  caps := public.get_conversation_capabilities(pg_temp.i('group'));
  perform pg_temp.expect(
    (caps->>'can_pin_messages')::boolean and (caps->>'can_moderate_polls')::boolean
    and (caps->>'can_moderate_messages')::boolean and not (caps->>'can_manage_thread')::boolean,
    'capabilities: the owner of a group pins and moderates');
  perform pg_temp.act(pg_temp.i('dee'));
  caps := public.get_conversation_capabilities(pg_temp.i('group'));
  perform pg_temp.expect((caps->>'can_pin_messages')::boolean and (caps->>'can_moderate_messages')::boolean,
    'capabilities: an admin of a group pins and moderates');
  perform pg_temp.act(pg_temp.i('bob'));
  caps := public.get_conversation_capabilities(pg_temp.i('group'));
  perform pg_temp.expect(
    not (caps->>'can_pin_messages')::boolean and not (caps->>'can_moderate_polls')::boolean
    and not (caps->>'can_moderate_messages')::boolean,
    'capabilities: a plain member of a group can do none of it');
  caps := public.get_conversation_capabilities(pg_temp.i('direct'));
  perform pg_temp.expect((caps->>'can_pin_messages')::boolean and not (caps->>'can_moderate_messages')::boolean,
    'capabilities: in a direct chat both people pin, nobody moderates');
  caps := public.get_conversation_capabilities(pg_temp.i('thread_conv'));
  perform pg_temp.expect((caps->>'can_manage_thread')::boolean, 'capabilities: a thread''s starter manages it');
  perform pg_temp.act(pg_temp.i('cy'));
  caps := public.get_conversation_capabilities(pg_temp.i('group'));
  perform pg_temp.expect(caps = jsonb_build_object(
      'can_pin_messages', false, 'can_moderate_polls', false,
      'can_moderate_messages', false, 'can_manage_thread', false),
    'capabilities: an outsider can do nothing');

  -- Nobody signed in.
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused(format('select public.get_conversation_capabilities(%L)', pg_temp.i('group'))),
    'capabilities: anonymous callers are refused');
end $$;

-- ================================================= 3. get_conversation_summary
create function pg_temp.summary_matches_list() returns text language plpgsql as $$
declare
  who text;
  conv text;
  conv_id uuid;
  one jsonb;
  listed jsonb;
  seen integer := 0;
  bad text := '';
begin
  foreach who in array array['ada', 'bob', 'cy', 'dee'] loop
    perform pg_temp.act(pg_temp.i(who));
    foreach conv in array array['group', 'group2', 'direct', 'channel', 'thread_conv', 'self', 'nowhere'] loop
      conv_id := case when conv = 'nowhere' then gen_random_uuid() else pg_temp.i(conv) end;
      select to_jsonb(s) into one from public.get_conversation_summary(conv_id) s;
      select to_jsonb(l) into listed from public.list_conversation_summaries() l where l.id = conv_id;
      if one is distinct from listed then
        bad := bad || format(' [%s/%s: %s vs %s]', who, conv, one, listed);
      end if;
      if listed is not null then
        seen := seen + 1;
      end if;
    end loop;
  end loop;
  perform pg_temp.root();
  if seen < 8 then
    bad := bad || ' [too few conversations compared: ' || seen || ']';
  end if;
  return bad;
end $$;
grant execute on function pg_temp.summary_matches_list() to public;

select pg_temp.expect(pg_temp.summary_matches_list() = '', 'summary: one row equals the list row for everyone (' || pg_temp.summary_matches_list() || ')');

-- Unread counts move as the person reads; a hidden conversation is left out
-- until something newer arrives; a muted one is the same.
select pg_temp.act(pg_temp.i('bob'));
select public.mark_conversation_read(pg_temp.i('group'), (select last_message_id from public.conversations where id = pg_temp.i('group')));
select pg_temp.expect((select unread_count from public.get_conversation_summary(pg_temp.i('group'))) = 0, 'summary: read means no unread');
select pg_temp.root();
update public.conversation_members set muted_until = now() + interval '1 day', manual_unread_at = now()
where conversation_id = pg_temp.i('direct') and user_id = pg_temp.i('bob');
update public.conversation_members set hidden_at = now() + interval '1 second' where conversation_id = pg_temp.i('group') and user_id = pg_temp.i('bob');
select pg_temp.expect(pg_temp.summary_matches_list() = '', 'summary: hidden, muted and marked unread still equal the list (' || pg_temp.summary_matches_list() || ')');
select pg_temp.act(pg_temp.i('bob'));
select pg_temp.expect(not exists (select 1 from public.get_conversation_summary(pg_temp.i('group'))), 'summary: a hidden conversation is left out');
select pg_temp.expect((select is_muted and is_marked_unread from public.get_conversation_summary(pg_temp.i('direct'))), 'summary: muted and marked unread show');
select pg_temp.root();
-- (A transaction has one "now": the new message is stamped a minute on.)
insert into public.messages (conversation_id, sender_id, type, body, created_at)
values (pg_temp.i('group'), pg_temp.i('ada'), 'text', 'back again', now() + interval '1 minute');
select pg_temp.act(pg_temp.i('bob'));
select pg_temp.expect(exists (select 1 from public.get_conversation_summary(pg_temp.i('group')) where unread_count >= 1), 'summary: a new message brings a hidden conversation back');
select pg_temp.root();
select pg_temp.expect(pg_temp.summary_matches_list() = '', 'summary: after the new message it still equals the list (' || pg_temp.summary_matches_list() || ')');

-- Nobody signed in; and only for people who are in.
select pg_temp.act(null);
select pg_temp.expect(pg_temp.refused(format('select * from public.get_conversation_summary(%L)', pg_temp.i('group'))), 'summary: anonymous callers are refused');
select pg_temp.act(pg_temp.i('cy'));
select pg_temp.expect(not exists (select 1 from public.get_conversation_summary(pg_temp.i('group'))), 'summary: an outsider gets no row');
select pg_temp.root();

-- ----------------------------------------------------------------- result
\o
do $$
declare n integer; msgs text;
begin
  select count(*), string_agg(msg, E'\n  ') into n, msgs from pg_temp.failures;
  if n > 0 then
    raise exception E'% check(s) failed:\n  %', n, msgs;
  end if;
  raise notice 'all perf follow-up checks passed';
end $$;

rollback;
