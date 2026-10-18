-- Behaviour checks for the live signals of Moments (migration 202610190020).
-- Run by test/supabase/moments_live_test.dart against the local database
-- inside a transaction that is rolled back. Run from the repository root.
--
-- Cast: as in moments_behaviour.sql. Ada (a1) posts; her friends are Bob (b1),
-- Cy (c1) and Dee (d1); Bob and Dee are friends of each other, Cy is not a
-- friend of either; Fay (f1) is a friend of Bob only; Eli (e1) has no friends.
\set ON_ERROR_STOP on

begin;

select pg_advisory_xact_lock(20261017);

\i supabase/migrations/202610180040_friend_tags_and_stars.sql
\i supabase/migrations/202610180041_moments.sql
\i supabase/migrations/202610180042_moments_feed.sql
\i supabase/migrations/202610190020_moments_realtime.sql

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

-- Whether running [statement] as the current role raises an error.
create function pg_temp.refused(statement text) returns boolean language plpgsql as $$
begin
  execute statement;
  return false;
exception when others then
  return true;
end $$;

-- The signals sent so far to [who], as "event:post" strings, oldest first.
create function pg_temp.signals(who uuid) returns text[]
language plpgsql security definer as $$
declare r text[];
begin
  select coalesce(array_agg(m.event || ':' || (m.payload->>'post_id') order by m.inserted_at, m.id), '{}')
  into r
  from realtime.messages m
  where m.topic = 'moments:' || who::text;
  return r;
end $$;

create function pg_temp.clear_signals() returns void
language plpgsql security definer as $$
begin
  delete from realtime.messages where topic like 'moments:%';
end $$;

grant execute on all functions in schema pg_temp to public;

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@live.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@live.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@live.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee@live.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e1', 'eli@live.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000f1', 'fay@live.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_live', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_live', 'Bob'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_live', 'Cy'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee_live', 'Dee'),
  ('00000000-0000-4000-8000-0000000000e1', 'eli_live', 'Eli'),
  ('00000000-0000-4000-8000-0000000000f1', 'fay_live', 'Fay');

create function pg_temp.befriend(a uuid, b uuid) returns void language sql as $$
  insert into public.friendships (user_low_id, user_high_id)
  values (least(a, b), greatest(a, b));
$$;

do $$ begin
  perform pg_temp.befriend('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000b1');
  perform pg_temp.befriend('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000c1');
  perform pg_temp.befriend('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000d1');
  perform pg_temp.befriend('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000d1');
  perform pg_temp.befriend('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1');
end $$;

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  cy uuid := '00000000-0000-4000-8000-0000000000c1';
  dee uuid := '00000000-0000-4000-8000-0000000000d1';
  eli uuid := '00000000-0000-4000-8000-0000000000e1';
  fay uuid := '00000000-0000-4000-8000-0000000000f1';
  work uuid;
  p1 uuid := '20000000-0000-4000-8000-000000000001';
  p_private uuid := '20000000-0000-4000-8000-000000000002';
  p_only_bob uuid := '20000000-0000-4000-8000-000000000003';
  p_except_bob uuid := '20000000-0000-4000-8000-000000000004';
  p_work uuid := '20000000-0000-4000-8000-000000000005';
  c1 uuid;
  c2 uuid;
  payload jsonb;
begin
  -- ------------------------------------------------------ new posts
  perform pg_temp.act(ada);
  perform public.create_moment(p1, 'hello');
  perform pg_temp.expect(
    pg_temp.signals(bob) = array['post:' || p1]
    and pg_temp.signals(cy) = array['post:' || p1]
    and pg_temp.signals(dee) = array['post:' || p1],
    format('a friends post did not signal every friend: %s %s %s', pg_temp.signals(bob), pg_temp.signals(cy), pg_temp.signals(dee)));
  perform pg_temp.expect(
    pg_temp.signals(ada) = '{}' and pg_temp.signals(eli) = '{}' and pg_temp.signals(fay) = '{}',
    'the author, a stranger or a friend of a friend was signalled of a post');

  -- The payload is only the post id.
  reset role;
  select m.payload - 'id' into payload from realtime.messages m
  where m.topic = 'moments:' || bob::text limit 1;
  perform pg_temp.expect(payload = jsonb_build_object('post_id', p1),
    format('the signal carries more than the post id: %s', payload));
  perform pg_temp.expect(
    (select bool_and(m.private) from realtime.messages m where m.topic like 'moments:%'),
    'a signal went out on a public channel');

  -- Posting the same id again is not news.
  perform pg_temp.clear_signals();
  perform pg_temp.act(ada);
  perform public.create_moment(p1, 'hello');
  perform pg_temp.expect(pg_temp.signals(bob) = '{}', 'posting the same id twice signalled twice');

  -- Visibility modes.
  perform pg_temp.clear_signals();
  perform public.create_moment(p_private, 'just me', '[]', null, null, null, 'private');
  perform pg_temp.expect(
    pg_temp.signals(bob) = '{}' and pg_temp.signals(cy) = '{}' and pg_temp.signals(dee) = '{}',
    'a private post signalled a friend');
  perform public.create_moment(p_only_bob, 'only Bob', '[]', null, null, null, 'only', array[bob]);
  perform pg_temp.expect(
    pg_temp.signals(bob) = array['post:' || p_only_bob]
    and pg_temp.signals(cy) = '{}' and pg_temp.signals(dee) = '{}',
    'an only-Bob post signalled someone else');
  perform pg_temp.clear_signals();
  perform public.create_moment(p_except_bob, 'not Bob', '[]', null, null, null, 'except', array[bob]);
  perform pg_temp.expect(
    pg_temp.signals(bob) = '{}'
    and pg_temp.signals(cy) = array['post:' || p_except_bob]
    and pg_temp.signals(dee) = array['post:' || p_except_bob],
    'a post hidden from Bob signalled Bob or missed the others');
  -- A tag.
  insert into public.friend_tags (owner_id, name) values (ada, 'Work') returning id into work;
  insert into public.friend_tag_members (tag_id, owner_id, friend_id) values (work, ada, cy);
  perform pg_temp.clear_signals();
  perform public.create_moment(p_work, 'Work only', '[]', null, null, null, 'only', '{}', array[work]);
  perform pg_temp.expect(
    pg_temp.signals(cy) = array['post:' || p_work] and pg_temp.signals(bob) = '{}' and pg_temp.signals(dee) = '{}',
    'a Work-only post signalled the wrong people');

  -- "Don't let them see my Moments" holds back the signal.
  perform public.set_moments_friend_pref(dee, true, null);
  perform pg_temp.clear_signals();
  perform public.create_moment('20000000-0000-4000-8000-000000000006', 'hidden from Dee');
  perform pg_temp.expect(
    pg_temp.signals(dee) = '{}' and cardinality(pg_temp.signals(bob)) = 1,
    'a post signalled a friend Ada hides her Moments from');
  perform public.set_moments_friend_pref(dee, false, null);

  -- --------------------------------------------- likes and comments
  perform pg_temp.clear_signals();
  perform pg_temp.act(bob);
  insert into public.moments_likes (post_id, user_id) values (p1, bob);
  perform pg_temp.expect(
    pg_temp.signals(ada) = array['reaction:' || p1]
    and pg_temp.signals(dee) = array['reaction:' || p1],
    format('a like did not signal Ada and Dee: %s %s', pg_temp.signals(ada), pg_temp.signals(dee)));
  perform pg_temp.expect(
    pg_temp.signals(cy) = '{}',
    'Cy (not a friend of Bob) was told of Bob''s like');
  perform pg_temp.expect(
    pg_temp.signals(bob) = '{}' and pg_temp.signals(eli) = '{}' and pg_temp.signals(fay) = '{}',
    'Bob himself, a stranger or Bob''s other friend was told of the like');

  -- Taking the like back is a change too.
  perform pg_temp.clear_signals();
  delete from public.moments_likes where post_id = p1 and user_id = bob;
  perform pg_temp.expect(
    pg_temp.signals(ada) = array['reaction:' || p1] and pg_temp.signals(dee) = array['reaction:' || p1],
    'taking a like back signalled nobody');

  -- Cy comments: only Ada (friend of both) hears; Bob and Dee are not
  -- friends of Cy.
  perform pg_temp.clear_signals();
  perform pg_temp.act(cy);
  insert into public.moments_comments (post_id, author_id, body) values (p1, cy, 'nice') returning id into c1;
  perform pg_temp.expect(
    pg_temp.signals(ada) = array['reaction:' || p1]
    and pg_temp.signals(bob) = '{}' and pg_temp.signals(dee) = '{}' and pg_temp.signals(cy) = '{}',
    format('Cy''s comment reached the wrong people: ada %s bob %s dee %s', pg_temp.signals(ada), pg_temp.signals(bob), pg_temp.signals(dee)));

  -- Bob replies to Dee's comment: Cy must not hear (not a friend of Bob).
  perform pg_temp.act(dee);
  insert into public.moments_comments (post_id, author_id, body) values (p1, dee, 'mine too') returning id into c2;
  perform pg_temp.clear_signals();
  perform pg_temp.act(bob);
  insert into public.moments_comments (post_id, author_id, body, reply_to_comment_id) values (p1, bob, 'agreed', c2);
  perform pg_temp.expect(
    pg_temp.signals(ada) = array['reaction:' || p1] and pg_temp.signals(dee) = array['reaction:' || p1]
    and pg_temp.signals(cy) = '{}' and pg_temp.signals(bob) = '{}',
    'a reply reached someone who cannot see it');

  -- Ada deletes Cy's comment from her post: Cy (the commenter) hears too.
  perform pg_temp.clear_signals();
  perform pg_temp.act(ada);
  delete from public.moments_comments where id = c1;
  perform pg_temp.expect(
    pg_temp.signals(cy) = array['reaction:' || p1] and pg_temp.signals(ada) = '{}',
    'Cy did not hear that his comment was removed');

  -- ---------------------------------------------------- post removed
  perform pg_temp.clear_signals();
  perform public.delete_moment(p1);
  perform pg_temp.expect(
    pg_temp.signals(bob) = array['post_removed:' || p1]
    and pg_temp.signals(cy) = array['post_removed:' || p1]
    and pg_temp.signals(dee) = array['post_removed:' || p1],
    format('removing a post did not signal its audience once: %s', pg_temp.signals(bob)));
  -- The comments and likes going with it say nothing more.
  perform pg_temp.expect(
    not exists (select 1 from realtime.messages m where m.event = 'reaction'),
    'a removed post sent a reaction signal per comment');
  perform pg_temp.clear_signals();
  perform public.delete_moment(p_private);
  perform pg_temp.expect(pg_temp.signals(bob) = '{}', 'removing a private post signalled');
  perform public.delete_moment(p_only_bob);
  perform pg_temp.expect(
    pg_temp.signals(bob) = array['post_removed:' || p_only_bob] and pg_temp.signals(cy) = '{}',
    'removing an only-Bob post signalled someone else');

  -- ------------------------------------------- who may listen
  perform pg_temp.clear_signals();
  reset role;
  perform public.moments_signal(bob, 'post', p_work);
  perform pg_temp.act(bob);
  perform set_config('realtime.topic', 'moments:' || bob::text, true);
  perform pg_temp.expect(
    (select count(*) from realtime.messages where topic = 'moments:' || bob::text) = 1,
    'Bob cannot receive on his own topic');
  perform set_config('realtime.topic', 'moments:' || ada::text, true);
  perform pg_temp.expect(
    (select count(*) from realtime.messages) = 0,
    'Bob can receive on another person''s topic');
  perform set_config('realtime.topic', 'moments:' || bob::text, true);
  perform pg_temp.expect(
    pg_temp.refused(format('insert into realtime.messages (topic, extension, payload, event, private) values (%L, ''broadcast'', ''{}'', ''post'', true)', 'moments:' || cy::text)),
    'Bob can send on another person''s topic');
  perform pg_temp.expect(
    pg_temp.refused(format('insert into realtime.messages (topic, extension, payload, event, private) values (%L, ''broadcast'', ''{}'', ''post'', true)', 'moments:' || bob::text)),
    'Bob can send on his own topic');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.moments_signal(%L, ''post'', %L)', cy, p_work)),
    'the signal sender is callable by the app');
  perform pg_temp.act(null);
  perform pg_temp.expect(
    pg_temp.refused('select count(*) from realtime.messages') or (select count(*) from realtime.messages) = 0,
    'anon reads signals');
end $$;

reset role;
do $$
declare
  failed text;
begin
  select string_agg(msg, E'\n') into failed from pg_temp.failures;
  if failed is not null then
    raise exception E'moments live checks failed:\n%', failed;
  end if;
end $$;

rollback;
