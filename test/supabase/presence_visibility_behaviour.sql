-- Behaviour checks for who may see that a person is online (migrations
-- 202610190070 and 202610190071). Run by
-- test/supabase/presence_visibility_test.dart against the local database
-- inside a transaction that is rolled back. Run from the repository root.
--
-- Cast: Ada is the person being looked at.
--   Bob   Ada's friend                    Cy   in a circle with Ada
--   Hal   in a group chat with Ada        Ivy  in a direct chat with Ada
--   Dee   a stranger                      Eli  a friend and circle mate whom
--                                              Ada then blocks
--   Gus   a friend and circle mate who then blocks Ada
--   Fay   in a circle with Ada, then leaves it
--   Max   in a group with Ada, then leaves the group
\set ON_ERROR_STOP on

begin;

select pg_advisory_xact_lock(20261017);

\i supabase/migrations/202610190070_presence_visibility.sql

-- The global channel's policies, as 202610190050 made them, so that
-- 202610190071 has something to drop on a database that lacks them.
drop policy if exists online_users_receive on realtime.messages;
create policy online_users_receive
  on realtime.messages for select
  to authenticated
  using (
    realtime.messages.extension = 'presence'
    and (select realtime.topic()) = 'online-users'
  );
drop policy if exists online_users_send on realtime.messages;
create policy online_users_send
  on realtime.messages for insert
  to authenticated
  with check (
    realtime.messages.extension = 'presence'
    and (select realtime.topic()) = 'online-users'
  );

\i supabase/migrations/202610190071_drop_online_users_policy.sql

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

create function pg_temp.root() returns void language plpgsql as $$
begin
  execute 'reset role';
end $$;

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create function pg_temp.i(n text) returns uuid language sql as $$ select id from pg_temp.ids where name = n $$;

-- Whether running [statement] as the current role raises an error.
create function pg_temp.refused(statement text) returns boolean language plpgsql as $$
begin
  execute statement;
  return false;
exception when others then
  return true;
end $$;

-- What [viewer] sees right now: 'name:status', sorted.
create function pg_temp.sees(viewer text) returns text[] language plpgsql as $$
declare r text[];
begin
  perform pg_temp.act(pg_temp.i(viewer));
  select coalesce(array_agg(n.name || ':' || v.status order by n.name), '{}')
  into r
  from public.visible_presence() v
  join pg_temp.ids n on n.id = v.user_id;
  perform pg_temp.root();
  return r;
end $$;

-- Whether [viewer] sees Ada in their list.
create function pg_temp.sees_ada(viewer text) returns boolean language sql as $$
  select exists (select 1 from unnest(pg_temp.sees(viewer)) s where s like 'ada:%');
$$;

-- Same, asking only about [about].
create function pg_temp.sees_one(viewer text, about text) returns text[] language plpgsql as $$
declare r text[];
begin
  perform pg_temp.act(pg_temp.i(viewer));
  select coalesce(array_agg(n.name || ':' || v.status order by n.name), '{}')
  into r
  from public.visible_presence(array[pg_temp.i(about)]) v
  join pg_temp.ids n on n.id = v.user_id;
  perform pg_temp.root();
  return r;
end $$;

-- [who] has the app open (and says it is [away] from the keyboard or not).
create function pg_temp.beat(who text, away boolean default false) returns void language plpgsql as $$
begin
  perform pg_temp.act(pg_temp.i(who));
  perform public.touch_presence(true, case when away then 'idle' else 'online' end);
  perform pg_temp.root();
end $$;

-- [who] picks a status.
create function pg_temp.pick(who text, status text) returns void language plpgsql as $$
begin
  perform pg_temp.act(pg_temp.i(who));
  perform public.set_presence_status(status);
  perform pg_temp.root();
end $$;

-- [who] flips "Show when you are online".
create function pg_temp.show_online(who text, show boolean) returns void language plpgsql as $$
begin
  perform pg_temp.act(pg_temp.i(who));
  perform public.set_show_online_status(show);
  perform pg_temp.root();
end $$;

-- [who] leaves (closes the app).
create function pg_temp.leave(who text) returns void language plpgsql as $$
begin
  perform pg_temp.act(pg_temp.i(who));
  perform public.touch_presence(false);
  perform pg_temp.root();
end $$;

-- The signals sent so far to [who], as "event:name,name" strings, oldest first.
create function pg_temp.signals(who text) returns text[]
language plpgsql security definer as $$
declare r text[];
begin
  select coalesce(array_agg(
    m.event || ':' || coalesce((
      select string_agg(n.name, ',' order by n.name)
      from jsonb_array_elements_text(m.payload->'user_ids') e(id)
      join pg_temp.ids n on n.id = e.id::uuid
    ), '') order by m.inserted_at, m.id), '{}')
  into r
  from realtime.messages m
  where m.topic = 'presence-updates:' || pg_temp.i(who)::text;
  return r;
end $$;

create function pg_temp.clear_signals() returns void
language plpgsql security definer as $$
begin
  delete from realtime.messages where topic like 'presence-updates:%';
end $$;

-- Whether [who] (null: nobody signed in) may do [op] ('listen' or 'send') on
-- the private channel [topic] with the [ext] extension (the policy on
-- realtime.messages, asked as that person).
create function pg_temp.allowed(who uuid, topic text, ext text, op text)
returns boolean language plpgsql as $$
declare ok boolean;
begin
  perform pg_temp.root();
  insert into realtime.messages (topic, extension, payload, event, private)
  values (topic, ext, '{}', 'x', true);
  perform pg_temp.act(who);
  perform set_config('realtime.topic', topic, true);
  begin
    if op = 'listen' then
      select exists (
        select 1 from realtime.messages m where m.topic = allowed.topic and m.extension = ext
      ) into ok;
    else
      insert into realtime.messages (topic, extension, payload, event, private)
      values (topic, ext, '{}', 'y', true);
      ok := true;
    end if;
  exception when insufficient_privilege then
    ok := false;
  end;
  perform pg_temp.root();
  return ok;
end $$;

-- ------------------------------------------------------------------ cast
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || n)::uuid
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee'),('e1','eli'),
  ('f1','fay'),('91','gus'),('a2','hal'),('a3','ivy'),('a4','max')) v(n, name);
insert into auth.users (id, email, instance_id, aud, role)
select id, name || '@presence.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from pg_temp.ids;
insert into public.profiles (id, username, display_name)
select id, name || '_presence', initcap(name) from pg_temp.ids;

create function pg_temp.befriend(a text, b text) returns void language sql as $$
  insert into public.friendships (user_low_id, user_high_id)
  values (least(pg_temp.i(a), pg_temp.i(b)), greatest(pg_temp.i(a), pg_temp.i(b)));
$$;

insert into pg_temp.ids select 'circle', gen_random_uuid();
insert into pg_temp.ids select 'group', gen_random_uuid();
insert into pg_temp.ids select 'direct', gen_random_uuid();
insert into pg_temp.ids select 'outside_group', gen_random_uuid();

grant execute on all functions in schema pg_temp to public;

select pg_temp.befriend('ada', 'bob');
select pg_temp.befriend('ada', 'eli');
select pg_temp.befriend('ada', 'gus');

insert into public.circles (id, name, owner_id)
values (pg_temp.i('circle'), 'Presence circle', pg_temp.i('ada'));
insert into public.circle_members (circle_id, user_id, role)
values
  (pg_temp.i('circle'), pg_temp.i('ada'), 'owner'),
  (pg_temp.i('circle'), pg_temp.i('cy'), 'member'),
  (pg_temp.i('circle'), pg_temp.i('eli'), 'member'),
  (pg_temp.i('circle'), pg_temp.i('gus'), 'member'),
  (pg_temp.i('circle'), pg_temp.i('fay'), 'member');

insert into public.conversations (id, type, title)
values (pg_temp.i('group'), 'group', 'Presence group'),
       (pg_temp.i('direct'), 'direct', null),
       (pg_temp.i('outside_group'), 'group', 'Others');
insert into public.conversation_members (conversation_id, user_id, role)
values
  (pg_temp.i('group'), pg_temp.i('ada'), 'owner'),
  (pg_temp.i('group'), pg_temp.i('hal'), 'member'),
  (pg_temp.i('group'), pg_temp.i('max'), 'member'),
  (pg_temp.i('direct'), pg_temp.i('ada'), 'member'),
  (pg_temp.i('direct'), pg_temp.i('ivy'), 'member'),
  (pg_temp.i('outside_group'), pg_temp.i('dee'), 'owner'),
  (pg_temp.i('outside_group'), pg_temp.i('hal'), 'member');

-- ===================================================== 1. who sees Ada
do $$
declare
  who text;
begin
  -- Everybody has the app open.
  foreach who in array array['ada','bob','cy','dee','eli','fay','gus','hal','ivy','max'] loop
    perform pg_temp.beat(who);
  end loop;

  foreach who in array array['bob', 'cy', 'hal', 'ivy', 'eli', 'gus', 'fay', 'max'] loop
    perform pg_temp.expect(
      pg_temp.sees(who) @> array['ada:online'],
      format('%s (shares something with Ada) does not see Ada online: %s', who, pg_temp.sees(who)));
    perform pg_temp.expect(
      pg_temp.sees_one(who, 'ada') = array['ada:online'],
      format('%s asking about Ada alone does not see her: %s', who, pg_temp.sees_one(who, 'ada')));
  end loop;
  perform pg_temp.expect(pg_temp.sees('dee') = array['hal:online'],
    format('a stranger sees people online: %s', pg_temp.sees('dee')));
  perform pg_temp.expect(pg_temp.sees_one('dee', 'ada') = '{}',
    'a stranger asking about Ada sees her');

  -- Who Ada sees: each kind of contact, not the stranger, not herself.
  perform pg_temp.expect(
    pg_temp.sees('ada') = array['bob:online','cy:online','eli:online','fay:online','gus:online','hal:online','ivy:online','max:online'],
    format('Ada sees %s', pg_temp.sees('ada')));

  -- Chat mates of chat mates are strangers.
  perform pg_temp.expect(pg_temp.sees('hal') = array['ada:online','dee:online','max:online'],
    format('Hal sees %s', pg_temp.sees('hal')));
  perform pg_temp.expect(pg_temp.sees('bob') = array['ada:online'],
    format('Bob (a friend of Ada only) sees %s', pg_temp.sees('bob')));
end $$;

-- ============================================ 2. blocks hide both ways
do $$
begin
  -- Ada blocks Eli; Gus blocks Ada.
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('ada'), pg_temp.i('eli'));
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('gus'), pg_temp.i('ada'));

  perform pg_temp.expect(pg_temp.sees('eli') @> array['ada:online'] is false and pg_temp.sees_one('eli', 'ada') = '{}',
    'someone Ada blocked still sees Ada online');
  perform pg_temp.expect(pg_temp.sees('gus') @> array['ada:online'] is false and pg_temp.sees_one('gus', 'ada') = '{}',
    'someone who blocked Ada still sees Ada online');
  perform pg_temp.expect(
    not (pg_temp.sees('ada') && array['eli:online', 'gus:online']),
    format('Ada sees someone she blocked or who blocked her: %s', pg_temp.sees('ada')));
  perform pg_temp.expect(pg_temp.sees_one('ada', 'eli') = '{}' and pg_temp.sees_one('ada', 'gus') = '{}',
    'Ada asking about a blocked person sees them');
  -- The others still do.
  perform pg_temp.expect(pg_temp.sees('bob') = array['ada:online'] and pg_temp.sees('cy') @> array['ada:online'],
    'a block of someone else hid Ada from her friends');

  -- Unblocking brings it back (Gus still blocks Ada).
  delete from public.blocks where blocker_id = pg_temp.i('ada');
  perform pg_temp.expect(pg_temp.sees('eli') @> array['ada:online'],
    'after unblocking, Eli does not see Ada');
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('ada'), pg_temp.i('eli'));
end $$;

-- ========================================= 3. status, and show online = off
do $$
begin
  -- Away from the keyboard turns Online into Idle.
  perform pg_temp.beat('ada', true);
  perform pg_temp.expect(pg_temp.sees('bob') = array['ada:idle'], format('away: %s', pg_temp.sees('bob')));
  perform pg_temp.beat('ada', false);
  perform pg_temp.expect(pg_temp.sees('bob') = array['ada:online'], format('back: %s', pg_temp.sees('bob')));

  -- Do Not Disturb is the saved status; the client can not change it.
  perform pg_temp.pick('ada', 'dnd');
  perform pg_temp.expect(pg_temp.sees('bob') = array['ada:dnd'], format('dnd: %s', pg_temp.sees('bob')));
  perform pg_temp.beat('ada', true);
  perform pg_temp.expect(pg_temp.sees('bob') = array['ada:dnd'], format('dnd while away: %s', pg_temp.sees('bob')));
  perform pg_temp.pick('ada', 'online');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.touch_presence(true, 'dnd');
  perform public.touch_presence(true, 'invisible');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.sees('bob') = array['ada:online'], format('a client claimed a status for itself: %s', pg_temp.sees('bob')));

  -- A picked Idle.
  perform pg_temp.pick('ada', 'idle');
  perform pg_temp.expect(pg_temp.sees('bob') = array['ada:idle'], 'picked idle');
  perform pg_temp.pick('ada', 'online');

  -- Invisible: nobody sees Ada.
  perform pg_temp.pick('ada', 'invisible');
  perform pg_temp.expect(
    not pg_temp.sees_ada('bob') and not pg_temp.sees_ada('cy') and not pg_temp.sees_ada('hal')
      and not pg_temp.sees_ada('ivy') and pg_temp.sees_one('bob', 'ada') = '{}',
    'Ada is Invisible and somebody sees her');
  -- ... though she keeps beating, and still sees them.
  perform pg_temp.beat('ada');
  perform pg_temp.expect(pg_temp.sees('bob') = '{}', 'an Invisible person who beats is seen');
  perform pg_temp.expect(pg_temp.sees('ada') @> array['bob:online', 'cy:online'], 'an Invisible person can not see others');
  perform pg_temp.pick('ada', 'online');
  perform pg_temp.expect(pg_temp.sees('bob') = array['ada:online'], 'online again after Invisible');

  -- Show when you are online = off: nobody sees Ada (server side, whatever
  -- the client does).
  perform pg_temp.show_online('ada', false);
  perform pg_temp.expect(
    not pg_temp.sees_ada('bob') and not pg_temp.sees_ada('cy') and not pg_temp.sees_ada('ivy')
      and pg_temp.sees_one('hal', 'ada') = '{}' and pg_temp.sees_one('bob', 'ada') = '{}',
    'Ada hides her online status and somebody sees her');
  perform pg_temp.beat('ada');
  perform pg_temp.expect(pg_temp.sees('bob') = '{}', 'a client that keeps beating shows through "show online = off"');
  perform pg_temp.expect(pg_temp.sees('ada') @> array['bob:online'], 'hiding oneself hides others from oneself');
  perform pg_temp.show_online('ada', true);
  perform pg_temp.expect(pg_temp.sees('bob') = array['ada:online'], 'online status shown again');
end $$;

-- ============================================ 4. ex-members, staleness
do $$
begin
  perform pg_temp.expect(pg_temp.sees('fay') @> array['ada:online'], 'Fay (a circle mate) does not see Ada');
  perform pg_temp.expect(pg_temp.sees('max') @> array['ada:online'], 'Max (a group mate) does not see Ada');

  delete from public.circle_members where circle_id = pg_temp.i('circle') and user_id = pg_temp.i('fay');
  perform pg_temp.expect(pg_temp.sees('fay') = '{}' and pg_temp.sees_one('fay', 'ada') = '{}',
    format('an ex circle member still sees Ada: %s', pg_temp.sees('fay')));
  perform pg_temp.expect(not (pg_temp.sees('ada') && array['fay:online']), 'Ada still sees an ex circle member');

  delete from public.conversation_members where conversation_id = pg_temp.i('group') and user_id = pg_temp.i('max');
  perform pg_temp.expect(pg_temp.sees('max') = '{}' and pg_temp.sees_one('max', 'ada') = '{}',
    format('an ex group member still sees Ada: %s', pg_temp.sees('max')));

  -- Unfriending: Bob only ever shared the friendship.
  delete from public.friendships
  where user_low_id = least(pg_temp.i('ada'), pg_temp.i('bob'))
    and user_high_id = greatest(pg_temp.i('ada'), pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.sees('bob') = '{}', 'an ex friend still sees Ada');
  perform pg_temp.befriend('ada', 'bob');

  -- A client that left, or went quiet, is offline.
  perform pg_temp.leave('ada');
  perform pg_temp.expect(not pg_temp.sees_ada('bob') and not pg_temp.sees_ada('cy'), 'Ada said she left and is still seen');
  perform pg_temp.beat('ada');
  perform pg_temp.expect(pg_temp.sees('bob') = array['ada:online'], 'Ada is back and not seen');
  update public.presence_state set seen_at = now() - interval '4 minutes' where user_id = pg_temp.i('ada');
  perform pg_temp.expect(pg_temp.sees('bob') = '{}' and pg_temp.sees_one('cy', 'ada') = '{}',
    'Ada vanished 4 minutes ago and is still seen');
  perform pg_temp.beat('ada');
  perform pg_temp.expect(pg_temp.sees('bob') = array['ada:online'], 'Ada beat again and is not seen');

  -- An older app: only is_online.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.touch_presence(is_online => true);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.sees('bob') = array['ada:online'], 'the old call touch_presence(is_online) broke');
end $$;

-- ======================================================== 5. signals
do $$
declare
  p jsonb;
begin
  perform pg_temp.clear_signals();

  -- Leaving: told to the online viewers who may see her, and nobody else.
  perform pg_temp.leave('ada');
  perform pg_temp.expect(pg_temp.signals('bob') = array['changed:ada'], format('Bob was told %s', pg_temp.signals('bob')));
  perform pg_temp.expect(pg_temp.signals('cy') = array['changed:ada'] and pg_temp.signals('hal') = array['changed:ada']
    and pg_temp.signals('ivy') = array['changed:ada'],
    'a circle, group or direct chat mate was not told that Ada left');
  perform pg_temp.expect(pg_temp.signals('dee') = '{}', 'a stranger was told about Ada');
  perform pg_temp.expect(pg_temp.signals('eli') = '{}' and pg_temp.signals('gus') = '{}', 'a blocked person was told about Ada');
  perform pg_temp.expect(pg_temp.signals('ada') = '{}', 'Ada was told about herself');
  perform pg_temp.expect(pg_temp.signals('fay') = '{}' and pg_temp.signals('max') = '{}', 'an ex-member was told about Ada');

  -- The payload is only ids, on a private message.
  select m.payload - 'id' into p from realtime.messages m
  where m.topic = 'presence-updates:' || pg_temp.i('bob')::text limit 1;
  perform pg_temp.expect(p = jsonb_build_object('user_ids', jsonb_build_array(pg_temp.i('ada'))),
    format('the payload is not just the ids: %s', p));
  perform pg_temp.expect((select m.private from realtime.messages m
    where m.topic = 'presence-updates:' || pg_temp.i('bob')::text limit 1), 'the signal is not private');

  -- Coming back is signalled; a plain heartbeat is not.
  perform pg_temp.clear_signals();
  perform pg_temp.beat('ada');
  perform pg_temp.expect(pg_temp.signals('bob') = array['changed:ada'], 'coming back was not signalled');
  perform pg_temp.clear_signals();
  update public.presence_state set seen_at = now() - interval '1 minute' where user_id = pg_temp.i('ada');
  perform pg_temp.beat('ada');
  perform pg_temp.expect(pg_temp.signals('bob') = '{}', 'a plain heartbeat was signalled');

  -- Away and back; a status change; the switch.
  perform pg_temp.beat('ada', true);
  perform pg_temp.expect(pg_temp.signals('bob') = array['changed:ada'], 'going idle was not signalled');
  perform pg_temp.beat('ada', false);
  perform pg_temp.clear_signals();
  perform pg_temp.pick('ada', 'dnd');
  perform pg_temp.expect(pg_temp.signals('bob') = array['changed:ada'] and pg_temp.signals('cy') = array['changed:ada'],
    'a status change was not signalled');
  perform pg_temp.pick('ada', 'online');
  perform pg_temp.clear_signals();
  perform pg_temp.show_online('ada', false);
  perform pg_temp.expect(pg_temp.signals('bob') = array['changed:ada'] and pg_temp.signals('dee') = '{}',
    format('hiding was not signalled to a viewer only: %s', pg_temp.signals('bob')));
  perform pg_temp.show_online('ada', true);

  -- Someone who has the app closed is not told (they read on opening).
  perform pg_temp.leave('cy');
  perform pg_temp.clear_signals();
  perform pg_temp.pick('ada', 'dnd');
  perform pg_temp.pick('ada', 'online');
  perform pg_temp.expect(pg_temp.signals('cy') = '{}', 'someone offline was told');
  perform pg_temp.expect(pg_temp.signals('bob') <> '{}', 'someone online was not told');
  perform pg_temp.beat('cy');

  -- Relationship changes tell the people concerned.
  perform pg_temp.clear_signals();
  delete from public.circle_members where circle_id = pg_temp.i('circle') and user_id = pg_temp.i('cy');
  perform pg_temp.expect(pg_temp.signals('cy') = array['reset:'], format('leaving a circle: the leaver got %s', pg_temp.signals('cy')));
  perform pg_temp.expect(pg_temp.signals('ada') = array['changed:cy'], format('leaving a circle: Ada got %s', pg_temp.signals('ada')));
  perform pg_temp.expect(pg_temp.signals('dee') = '{}', 'leaving a circle told a stranger');
  perform pg_temp.clear_signals();
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('dee'), pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.signals('dee') = array['changed:bob'] and pg_temp.signals('bob') = array['changed:dee'],
    'a block did not tell both people');
end $$;

-- ============================================== 6. policies and grants
do $$
declare
  topic text := 'presence-updates:' || pg_temp.i('bob');
  who text;
begin
  perform pg_temp.expect(pg_temp.allowed(pg_temp.i('bob'), topic, 'broadcast', 'listen'),
    'a person can not listen to their own presence topic');
  foreach who in array array['ada', 'dee', 'eli'] loop
    perform pg_temp.expect(not pg_temp.allowed(pg_temp.i(who), topic, 'broadcast', 'listen'),
      format('%s can listen to Bobs presence topic', who));
  end loop;
  perform pg_temp.expect(not pg_temp.allowed(null, topic, 'broadcast', 'listen'), 'anon listens to a presence topic');
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('bob'), topic, 'broadcast', 'send'),
    'a person can send on their own presence topic');
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('ada'), topic, 'broadcast', 'send'),
    'a person can send on somebody elses presence topic');
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('bob'), topic, 'presence', 'listen'),
    'a presence extension is allowed on the signal topic');
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('bob'), topic || 'x', 'broadcast', 'listen'),
    'a near topic is allowed');

  -- The global channel is closed to everybody.
  foreach who in array array['ada', 'bob', 'dee'] loop
    perform pg_temp.expect(not pg_temp.allowed(pg_temp.i(who), 'online-users', 'presence', 'listen'),
      format('%s can still listen to online-users', who));
    perform pg_temp.expect(not pg_temp.allowed(pg_temp.i(who), 'online-users', 'presence', 'send'),
      format('%s can still track on online-users', who));
  end loop;

  -- Who may call what.
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused('select * from public.visible_presence()'), 'anon reads presence');
  perform pg_temp.expect(pg_temp.refused('select public.touch_presence(true)'), 'anon beats');
  perform pg_temp.act(pg_temp.i('dee'));
  perform pg_temp.expect(pg_temp.refused('select * from public.presence_state'), 'a person reads presence_state');
  perform pg_temp.expect(pg_temp.refused(format('select public.presence_contacts(%L)', pg_temp.i('ada'))),
    'a person lists the contacts of somebody else');
  perform pg_temp.expect(pg_temp.refused(format('select public.presence_can_see(%L, %L)', pg_temp.i('ada'), pg_temp.i('bob'))),
    'a person asks who sees whom');
  perform pg_temp.expect(pg_temp.refused(format('select public.presence_notify(%L)', pg_temp.i('ada'))),
    'a person sends signals');
  perform pg_temp.expect(pg_temp.refused(format('select public.presence_send(%L, %L, %L)', pg_temp.i('ada'), 'changed', '[]')),
    'a person sends a signal directly');
  perform pg_temp.expect(pg_temp.refused(
    format('select * from public.visible_presence(%L::uuid[])', (select array_agg(gen_random_uuid()) from generate_series(1, 201)))),
    'more than 200 ids were accepted');
  perform pg_temp.root();
end $$;

reset role;
do $$
declare
  failed text;
begin
  select string_agg(msg, E'\n') into failed from pg_temp.failures;
  if failed is not null then
    raise exception E'presence visibility checks failed:\n%', failed;
  end if;
end $$;

rollback;
