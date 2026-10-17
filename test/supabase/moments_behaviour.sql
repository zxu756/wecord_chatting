-- Behaviour checks for Moments and friend tags (migrations 202610180040 to
-- 202610180042). Run by test/supabase/moments_test.dart against the local
-- database inside a transaction that is rolled back. Run from the repository
-- root.
--
-- Cast: Ada (a1) posts. Her friends are Bob (b1), Cy (c1) and Dee (d1); Bob
-- and Dee are friends of each other, Cy is not a friend of either. Fay (f1)
-- is a friend of Bob only, Eli (e1) has no friends. So Ada, Bob and Dee see
-- each other's reactions, Cy sees only Ada's and his own.
\set ON_ERROR_STOP on

begin;

-- Behaviour scripts that apply DDL take turns.
select pg_advisory_xact_lock(20261017);

\i supabase/migrations/202610180040_friend_tags_and_stars.sql
\i supabase/migrations/202610180041_moments.sql
\i supabase/migrations/202610180042_moments_feed.sql

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

-- How many rows [query] returns, as the current role.
create function pg_temp.cnt(query text) returns integer language plpgsql as $$
declare n integer;
begin
  execute format('select count(*) from (%s) q', query) into n;
  return n;
end $$;

-- Whether running [statement] as the current role raises an error.
create function pg_temp.refused(statement text) returns boolean language plpgsql as $$
begin
  execute statement;
  return false;
exception when others then
  return true;
end $$;

-- The posts the current person's feed (or a person's page) returns.
create function pg_temp.feed_ids(author uuid default null) returns uuid[]
language plpgsql as $$
declare ids uuid[];
begin
  select coalesce(array_agg(f.id order by f.created_at desc, f.id desc), '{}')
  into ids
  from public.moments_feed(50, null, null, author, null) f;
  return ids;
end $$;

-- The post itself, readable straight from the table.
create function pg_temp.table_sees(post uuid) returns boolean language plpgsql as $$
begin
  return pg_temp.cnt(format('select 1 from public.moments_posts where id = %L', post)) = 1;
end $$;

-- Whether the current person may read a picture of the bucket.
create function pg_temp.reads(object text) returns boolean language plpgsql as $$
begin
  return pg_temp.cnt(
    format('select 1 from storage.objects where bucket_id = ''moments'' and name = %L', object)
  ) = 1;
end $$;

grant execute on all functions in schema pg_temp to public;

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@mom.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@mom.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@mom.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee@mom.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e1', 'eli@mom.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000f1', 'fay@mom.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_mom', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_mom', 'Bob'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_mom', 'Cy'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee_mom', 'Dee'),
  ('00000000-0000-4000-8000-0000000000e1', 'eli_mom', 'Eli'),
  ('00000000-0000-4000-8000-0000000000f1', 'fay_mom', 'Fay');

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

-- ------------------------------------------------------ tags and stars

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  cy uuid := '00000000-0000-4000-8000-0000000000c1';
  eli uuid := '00000000-0000-4000-8000-0000000000e1';
  family uuid;
begin
  perform pg_temp.act(ada);
  insert into public.friend_tags (owner_id, name) values (ada, '  Family ') returning id into family;
  perform pg_temp.expect((select name from public.friend_tags where id = family) = 'Family', 'a tag name is trimmed');
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.friend_tags (owner_id, name) values (%L, %L)', ada, 'family')),
    'a second tag with the same name (any case) was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.friend_tags (owner_id, name) values (%L, %L)', ada, '   ')),
    'an empty tag name was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.friend_tags (owner_id, name) values (%L, %L)', ada, repeat('x', 31))),
    'a 31 character tag name was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.friend_tags (owner_id, name) values (%L, %L)', bob, 'Mine now')),
    'Ada created a tag for Bob');

  insert into public.friend_tag_members (tag_id, owner_id, friend_id) values (family, ada, bob);
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.friend_tag_members (tag_id, owner_id, friend_id) values (%L, %L, %L)', family, ada, eli)),
    'a non-friend was put in a tag');
  update public.friend_tags set name = 'Relatives' where id = family;
  perform pg_temp.expect((select name from public.friend_tags where id = family) = 'Relatives', 'renaming a tag failed');
  insert into public.friend_stars (owner_id, friend_id) values (ada, bob);
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.friend_stars (owner_id, friend_id) values (%L, %L)', ada, eli)),
    'a non-friend was starred');

  -- Private to the owner.
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.friend_tags') = 0, 'Bob can read Ada''s tags');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.friend_tag_members') = 0, 'Bob can read Ada''s tag members');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.friend_stars') = 0, 'Bob can see he is starred');
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.friend_tag_members (tag_id, owner_id, friend_id) values (%L, %L, %L)', family, bob, ada)),
    'Bob put Ada in a tag of his that is Ada''s');
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.friend_tag_members (tag_id, owner_id, friend_id) values (%L, %L, %L)', family, ada, cy)),
    'Bob added to Ada''s tag');
  delete from public.friend_tags where id = family;
  delete from public.friend_tag_members where tag_id = family;
  update public.friend_tags set name = 'Hacked' where id = family;
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused('select 1 from public.friend_tags'), 'anon read tags');
  perform pg_temp.act(ada);
  perform pg_temp.expect((select name from public.friend_tags where id = family) = 'Relatives', 'Bob changed or removed Ada''s tag');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.friend_tag_members') = 1, 'Bob removed Ada''s tag member');

  -- Removing a member and a star.
  delete from public.friend_tag_members where tag_id = family and friend_id = bob;
  delete from public.friend_stars where friend_id = bob;
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.friend_tag_members') = 0, 'a member was not removed');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.friend_stars') = 0, 'a star was not removed');

  -- Deleting a tag takes its members along.
  insert into public.friend_tag_members (tag_id, owner_id, friend_id) values (family, ada, bob);
  delete from public.friend_tags where id = family;
  perform pg_temp.act(null);
  reset role;
  perform pg_temp.expect(
    (select count(*) from public.friend_tag_members where tag_id = family) = 0,
    'a deleted tag kept its members');
end $$;

-- ----------------------------------------------------- visibility modes

create temp table posts (name text primary key, id uuid not null);
grant all on posts to public;

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  cy uuid := '00000000-0000-4000-8000-0000000000c1';
  dee uuid := '00000000-0000-4000-8000-0000000000d1';
  eli uuid := '00000000-0000-4000-8000-0000000000e1';
  fay uuid := '00000000-0000-4000-8000-0000000000f1';
  family uuid;
  work uuid;
  p_friends uuid := '10000000-0000-4000-8000-000000000001';
  p_private uuid := '10000000-0000-4000-8000-000000000002';
  p_only_bob uuid := '10000000-0000-4000-8000-000000000003';
  p_only_tag uuid := '10000000-0000-4000-8000-000000000004';
  p_except_bob uuid := '10000000-0000-4000-8000-000000000005';
  p_except_tag uuid := '10000000-0000-4000-8000-000000000006';
  p_mixed uuid := '10000000-0000-4000-8000-000000000007';
begin
  perform pg_temp.act(ada);
  insert into public.friend_tags (owner_id, name) values (ada, 'Family') returning id into family;
  insert into public.friend_tags (owner_id, name) values (ada, 'Work') returning id into work;
  -- Family: Bob. Work: Cy and Dee.
  insert into public.friend_tag_members (tag_id, owner_id, friend_id)
  values (family, ada, bob), (work, ada, cy), (work, ada, dee);

  perform public.create_moment(p_friends, 'for all friends');
  perform public.create_moment(p_private, 'just me', '[]', null, null, null, 'private');
  perform public.create_moment(p_only_bob, 'only Bob', '[]', null, null, null, 'only', array[bob]);
  perform public.create_moment(p_only_tag, 'only Work', '[]', null, null, null, 'only', '{}', array[work]);
  perform public.create_moment(p_except_bob, 'not Bob', '[]', null, null, null, 'except', array[bob]);
  perform public.create_moment(p_except_tag, 'not Work', '[]', null, null, null, 'except', '{}', array[work]);
  perform public.create_moment(p_mixed, 'Bob or Work', '[]', null, null, null, 'only', array[bob], array[work]);
  insert into posts values
    ('friends', p_friends), ('private', p_private), ('only_bob', p_only_bob),
    ('only_tag', p_only_tag), ('except_bob', p_except_bob),
    ('except_tag', p_except_tag), ('mixed', p_mixed);

  -- Ada sees all of her own.
  perform pg_temp.expect(cardinality(pg_temp.feed_ids()) = 7, 'Ada does not see all 7 of her posts');
  perform pg_temp.expect(pg_temp.table_sees(p_private), 'Ada does not read her private post');

  -- Bob: friends, only_bob, except_tag (not in Work), mixed.
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.feed_ids() @> array[p_friends, p_only_bob, p_except_tag, p_mixed]
    and cardinality(pg_temp.feed_ids()) = 4,
    format('Bob''s feed is wrong: %s', pg_temp.feed_ids()));
  perform pg_temp.expect(not pg_temp.table_sees(p_private), 'Bob reads the private post');
  perform pg_temp.expect(not pg_temp.table_sees(p_except_bob), 'Bob reads the post hidden from him');
  perform pg_temp.expect(not pg_temp.table_sees(p_only_tag), 'Bob reads Work-only without being in Work');
  perform pg_temp.expect(pg_temp.table_sees(p_mixed), 'Bob does not read Bob-or-Work');

  -- Cy (Work): friends, only_tag, except_bob, mixed.
  perform pg_temp.act(cy);
  perform pg_temp.expect(
    pg_temp.feed_ids() @> array[p_friends, p_only_tag, p_except_bob, p_mixed]
    and cardinality(pg_temp.feed_ids()) = 4,
    format('Cy''s feed is wrong: %s', pg_temp.feed_ids()));
  perform pg_temp.expect(not pg_temp.table_sees(p_except_tag), 'Cy reads the post hidden from Work');
  perform pg_temp.expect(not pg_temp.table_sees(p_only_bob), 'Cy reads the Bob-only post');

  -- Dee (Work, friend of Bob): same as Cy.
  perform pg_temp.act(dee);
  perform pg_temp.expect(
    pg_temp.feed_ids() @> array[p_friends, p_only_tag, p_except_bob, p_mixed]
    and cardinality(pg_temp.feed_ids()) = 4,
    format('Dee''s feed is wrong: %s', pg_temp.feed_ids()));

  -- Strangers, and a friend of a friend, see nothing of Ada's.
  perform pg_temp.act(eli);
  perform pg_temp.expect(cardinality(pg_temp.feed_ids()) = 0, 'Eli (no friends) sees posts');
  perform pg_temp.expect(
    cardinality(pg_temp.feed_ids(ada)) = 0
    and pg_temp.cnt('select 1 from public.moments_posts') = 0,
    'Eli reads Ada''s page or the table');
  perform pg_temp.act(fay);
  perform pg_temp.expect(cardinality(pg_temp.feed_ids()) = 0, 'Fay (friend of Bob) sees Ada''s posts');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.moments_posts') = 0, 'Fay reads the table');

  -- The audience is the author's secret, even for the people it includes.
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.refused('select audience_friend_ids from public.moments_posts'),
    'Bob can read the audience columns');
  perform pg_temp.expect(
    pg_temp.refused('select audience_tag_ids from public.moments_posts'),
    'Bob can read the audience tag columns');
  perform pg_temp.expect(
    pg_temp.refused('select * from public.moments_posts'),
    'select * is allowed on the audience columns');

  -- Tags are read live: Cy joins Family, Bob leaves it.
  perform pg_temp.act(ada);
  insert into public.friend_tags (owner_id, name) values (ada, 'Cousins');
  insert into public.friend_tag_members (tag_id, owner_id, friend_id) values (family, ada, cy);
  perform public.create_moment('10000000-0000-4000-8000-000000000008', 'only Family', '[]', null, null, null, 'only', '{}', array[family]);
  perform pg_temp.act(cy);
  perform pg_temp.expect(pg_temp.table_sees('10000000-0000-4000-8000-000000000008'), 'Cy in Family does not see the Family post');
  perform pg_temp.act(ada);
  delete from public.friend_tag_members where tag_id = family and friend_id = bob;
  perform pg_temp.act(bob);
  perform pg_temp.expect(not pg_temp.table_sees('10000000-0000-4000-8000-000000000008'), 'Bob kept seeing a Family post after leaving Family');
  perform pg_temp.act(ada);
  -- A non-friend and a tag that is not Ada's are dropped from the audience;
  -- "only" with nobody left is visible to the author alone.
  perform public.create_moment('10000000-0000-4000-8000-000000000009', 'only a stranger''s tag', '[]', null, null, null, 'only', array[eli], array['99999999-9999-4999-8999-999999999999']::uuid[]);
  perform pg_temp.act(bob);
  perform pg_temp.expect(not pg_temp.table_sees('10000000-0000-4000-8000-000000000009'), 'an only-post with an empty audience is visible');
  reset role;
  perform pg_temp.expect(
    (select audience_friend_ids = '{}' from public.moments_posts where id = '10000000-0000-4000-8000-000000000009'),
    'a non-friend stayed in the audience');
  perform pg_temp.expect(
    (select audience_tag_ids = '{}' from public.moments_posts where id = '10000000-0000-4000-8000-000000000009'),
    'a tag that is not the author''s stayed in the audience');
  perform pg_temp.expect(
    (select audience_friend_ids = '{}' and audience_tag_ids = '{}' from public.moments_posts where id = '10000000-0000-4000-8000-000000000002'),
    'a private post kept an audience');
end $$;

-- -------------------------------------------------------- visible range

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  p_new uuid := '20000000-0000-4000-8000-000000000001';
  p_2d uuid := '20000000-0000-4000-8000-000000000002';
  p_10d uuid := '20000000-0000-4000-8000-000000000003';
  p_2m uuid := '20000000-0000-4000-8000-000000000004';
  p_8m uuid := '20000000-0000-4000-8000-000000000005';
begin
  perform pg_temp.act(ada);
  perform public.create_moment(p_new, 'new');
  perform public.create_moment(p_2d, 'two days');
  perform public.create_moment(p_10d, 'ten days');
  perform public.create_moment(p_2m, 'two months');
  perform public.create_moment(p_8m, 'eight months');
  reset role;
  update public.moments_posts set created_at = now() - interval '2 days' where id = p_2d;
  update public.moments_posts set created_at = now() - interval '10 days' where id = p_10d;
  update public.moments_posts set created_at = now() - interval '2 months' where id = p_2m;
  update public.moments_posts set created_at = now() - interval '8 months' where id = p_8m;

  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.table_sees(p_8m) and pg_temp.table_sees(p_2m) and pg_temp.table_sees(p_10d),
    'with the range "all" Bob does not see old posts');

  perform pg_temp.act(ada);
  perform public.set_moments_settings('six_months');
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.table_sees(p_2m) and pg_temp.table_sees(p_10d) and not pg_temp.table_sees(p_8m),
    'six months: wrong posts visible');
  perform pg_temp.act(ada);
  perform pg_temp.expect(pg_temp.table_sees(p_8m), 'Ada lost her own old post under the six month range');

  perform public.set_moments_settings('one_month');
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.table_sees(p_10d) and not pg_temp.table_sees(p_2m) and not pg_temp.table_sees(p_8m),
    'one month: wrong posts visible');

  perform pg_temp.act(ada);
  perform public.set_moments_settings('three_days');
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.table_sees(p_new) and pg_temp.table_sees(p_2d) and not pg_temp.table_sees(p_10d),
    'three days: wrong posts visible');
  perform pg_temp.expect(not (p_10d = any (pg_temp.feed_ids())), 'the feed returns a post outside the range');
  perform pg_temp.expect(not (p_10d = any (pg_temp.feed_ids('00000000-0000-4000-8000-0000000000a1'))), 'the page returns a post outside the range');
  perform pg_temp.act(ada);
  perform pg_temp.expect(pg_temp.table_sees(p_8m) and pg_temp.table_sees(p_10d), 'Ada lost her own posts under three days');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.set_moments_settings(%L)', 'forever')),
    'an unknown range was accepted');

  perform public.set_moments_settings('all');
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.table_sees(p_8m), 'going back to "all" did not show old posts again');
  -- Keep the rest of the script on a clean slate.
  perform pg_temp.act(ada);
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.moments_posts where id in (''20000000-0000-4000-8000-000000000003'',''20000000-0000-4000-8000-000000000004'',''20000000-0000-4000-8000-000000000005'')') = 3, 'Ada lost old posts');
  reset role;
  delete from public.moments_posts where id in (p_2d, p_10d, p_2m, p_8m);
end $$;

-- ------------------------------------- "don't let them see" / "hide their"

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  cy uuid := '00000000-0000-4000-8000-0000000000c1';
  eli uuid := '00000000-0000-4000-8000-0000000000e1';
  p_friends uuid := '10000000-0000-4000-8000-000000000001';
begin
  -- Ada: "Don't let them see my Moments" for Bob.
  perform pg_temp.act(ada);
  perform public.set_moments_friend_pref(bob, true, null);
  perform pg_temp.expect(
    pg_temp.refused(format('select public.set_moments_friend_pref(%L, true, null)', eli)),
    'a non-friend could be chosen');
  perform pg_temp.act(bob);
  perform pg_temp.expect(cardinality(pg_temp.feed_ids()) = 0, 'Bob still sees Ada''s posts after she hid them from him');
  perform pg_temp.expect(not pg_temp.table_sees(p_friends), 'Bob still reads Ada''s post in the table');
  perform pg_temp.expect(cardinality(pg_temp.feed_ids(ada)) = 0, 'Bob still sees Ada''s page');
  perform pg_temp.expect(
    (select count(*) from public.get_moments_profile(ada) where cover_path is null and not is_friend) = 1,
    'Bob''s view of Ada''s Moments profile is not closed');
  perform pg_temp.act(cy);
  perform pg_temp.expect(pg_temp.table_sees(p_friends), 'Cy lost Ada''s posts when she hid them from Bob');
  -- Ada still sees Bob's posts (the choice is one way).
  perform pg_temp.act(bob);
  perform public.create_moment('30000000-0000-4000-8000-000000000001', 'Bob posts');
  perform pg_temp.act(ada);
  perform pg_temp.expect(pg_temp.table_sees('30000000-0000-4000-8000-000000000001'), 'Ada cannot see Bob after hiding hers from him');
  perform public.set_moments_friend_pref(bob, false, null);
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.moments_friend_prefs') = 0, 'both switches off keeps a row');
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.table_sees(p_friends), 'Bob does not see Ada''s posts again');

  -- Cy: "Hide their Moments" for Ada. Her posts leave Cy's feed, but her
  -- page still opens and a single post can still be read.
  perform pg_temp.act(cy);
  perform public.set_moments_friend_pref(ada, null, true);
  perform pg_temp.expect(not (p_friends = any (pg_temp.feed_ids())), 'a hidden friend''s post is in the feed');
  perform pg_temp.expect(p_friends = any (pg_temp.feed_ids(ada)), 'a hidden friend''s page does not open');
  perform pg_temp.expect(
    (select count(*) from public.moments_unseen_summary()) = 0
    or (select new_count from public.moments_unseen_summary()) is null,
    'a hidden friend counts as new');
  perform pg_temp.expect(
    (select count(*) from public.list_moments_friend_prefs() where hide_theirs and not hide_mine) = 1,
    'the hidden friend is not listed');
  perform public.set_moments_friend_pref(ada, null, false);
  perform pg_temp.expect(p_friends = any (pg_temp.feed_ids()), 'un-hiding did not bring the posts back');
end $$;

-- ------------------------------------------- likes and comments (mutual)

create temp table interactions (name text primary key, id uuid not null);
grant all on interactions to public;

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  cy uuid := '00000000-0000-4000-8000-0000000000c1';
  dee uuid := '00000000-0000-4000-8000-0000000000d1';
  eli uuid := '00000000-0000-4000-8000-0000000000e1';
  fay uuid := '00000000-0000-4000-8000-0000000000f1';
  post uuid := '10000000-0000-4000-8000-000000000001';
  private_post uuid := '10000000-0000-4000-8000-000000000002';
  bob_comment uuid;
  dee_reply uuid;
  cy_comment uuid;
  likes_json jsonb;
  comments_json jsonb;
  row_data record;
begin
  perform pg_temp.act(bob);
  insert into public.moments_likes (post_id, user_id) values (post, bob);
  perform pg_temp.act(cy);
  insert into public.moments_likes (post_id, user_id) values (post, cy);
  perform pg_temp.act(dee);
  insert into public.moments_likes (post_id, user_id) values (post, dee);

  -- Liking as someone else, or a post you cannot see, is refused.
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.moments_likes (post_id, user_id) values (%L, %L)', post, bob)),
    'Dee liked as Bob (a duplicate or a forgery went through)');
  perform pg_temp.act(eli);
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.moments_likes (post_id, user_id) values (%L, %L)', post, eli)),
    'a stranger liked the post');
  perform pg_temp.act(fay);
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.moments_likes (post_id, user_id) values (%L, %L)', post, fay)),
    'a friend of a friend liked the post');
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.moments_likes (post_id, user_id) values (%L, %L)', private_post, bob)),
    'Bob liked a private post');

  -- Who sees which like (table and feed): Ada all three, Bob himself and
  -- Dee (a friend of both Ada and Bob), Cy only himself (not a friend of
  -- Bob or Dee), and Dee sees Bob and herself.
  perform pg_temp.act(ada);
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.moments_likes') = 3, 'Ada does not see all 3 likes');
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.cnt(format('select 1 from public.moments_likes where user_id = %L', cy)) = 0,
    'Bob sees Cy''s like (not his friend)');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.moments_likes') = 2, 'Bob should see his and Dee''s likes');
  perform pg_temp.act(cy);
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.moments_likes') = 1, 'Cy should see only his own like');
  perform pg_temp.act(dee);
  perform pg_temp.expect(
    pg_temp.cnt(format('select 1 from public.moments_likes where user_id = %L', cy)) = 0,
    'Dee sees Cy''s like');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.moments_likes') = 2, 'Dee should see Bob''s and hers');

  -- The feed agrees, with counts that do not leak either.
  perform pg_temp.act(cy);
  select * into row_data from public.moments_feed(5, null, null, null, post);
  perform pg_temp.expect(row_data.like_count = 1 and row_data.liked_by_me and jsonb_array_length(row_data.likes) = 1,
    format('Cy''s feed shows %s likes', row_data.like_count));
  perform pg_temp.act(ada);
  select * into row_data from public.moments_feed(5, null, null, null, post);
  perform pg_temp.expect(row_data.like_count = 3 and not row_data.liked_by_me, 'Ada''s feed should show 3 likes');
  perform pg_temp.act(bob);
  select * into row_data from public.moments_feed(5, null, null, null, post);
  perform pg_temp.expect(row_data.like_count = 2 and row_data.liked_by_me, 'Bob''s feed should show 2 likes');

  -- Comments. Bob comments; Cy comments; Dee replies to Bob.
  perform pg_temp.act(bob);
  insert into public.moments_comments (post_id, author_id, body) values (post, bob, 'nice one') returning id into bob_comment;
  perform pg_temp.act(cy);
  insert into public.moments_comments (post_id, author_id, body) values (post, cy, 'Cy here') returning id into cy_comment;
  perform pg_temp.act(dee);
  insert into public.moments_comments (post_id, author_id, reply_to_comment_id, body)
  values (post, dee, bob_comment, 'agree') returning id into dee_reply;
  perform pg_temp.expect(
    (select reply_to_user_id from public.moments_comments where id = dee_reply) = bob,
    'a reply did not record who it answers');

  -- Cy cannot reply to Bob's comment: he cannot see it.
  perform pg_temp.act(cy);
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.moments_comments (post_id, author_id, reply_to_comment_id, body) values (%L, %L, %L, %L)', post, cy, bob_comment, 'hi Bob')),
    'Cy replied to a comment of a stranger');
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.moments_comments (post_id, author_id, body) values (%L, %L, %L)', post, bob, 'as Bob')),
    'Cy commented as Bob');
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.moments_comments (post_id, author_id, body) values (%L, %L, %L)', post, cy, '   ')),
    'a blank comment was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.moments_comments (post_id, author_id, body) values (%L, %L, %L)', post, cy, repeat('x', 501))),
    'a 501 character comment was accepted');
  perform pg_temp.act(eli);
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.moments_comments (post_id, author_id, body) values (%L, %L, %L)', post, eli, 'hello')),
    'a stranger commented');

  -- Who sees which comment: Ada all 3; Bob his own and Dee's reply (not Cy's);
  -- Cy only his own; Dee Bob's, hers (not Cy's).
  perform pg_temp.act(ada);
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.moments_comments') = 3, 'Ada does not see all 3 comments');
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.cnt('select 1 from public.moments_comments') = 2
    and pg_temp.cnt(format('select 1 from public.moments_comments where id = %L', cy_comment)) = 0,
    'Bob should see his comment and Dee''s reply, not Cy''s');
  perform pg_temp.act(cy);
  perform pg_temp.expect(
    pg_temp.cnt('select 1 from public.moments_comments') = 1
    and pg_temp.cnt(format('select 1 from public.moments_comments where id = %L', cy_comment)) = 1,
    'Cy should see only his own comment');
  perform pg_temp.act(dee);
  perform pg_temp.expect(
    pg_temp.cnt('select 1 from public.moments_comments') = 2
    and pg_temp.cnt(format('select 1 from public.moments_comments where id = %L', cy_comment)) = 0,
    'Dee should see Bob''s comment and her reply, not Cy''s');
  select * into row_data from public.moments_feed(5, null, null, null, post);
  perform pg_temp.expect(row_data.comment_count = 2 and jsonb_array_length(row_data.comments) = 2,
    format('Dee''s feed shows %s comments', row_data.comment_count));
  perform pg_temp.expect(
    exists (
      select 1 from jsonb_array_elements(row_data.comments) c
      where c->>'name' = 'Dee' and c->>'reply_to_name' = 'Bob'
        and (c->>'reply_to_user_id')::uuid = bob
    ),
    'the reply does not name who it answers');

  -- A reply to a stranger's comment stays hidden from someone who is not
  -- friends with the person replied to: Ada (friend of all) sees it; once
  -- Cy comments and Ada replies to Cy, Bob (not Cy's friend) does not see
  -- Ada's reply, though he is her friend.
  perform pg_temp.act(ada);
  insert into public.moments_comments (post_id, author_id, reply_to_comment_id, body)
  values (post, ada, cy_comment, 'welcome Cy');
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.cnt('select 1 from public.moments_comments where body = ''welcome Cy''') = 0,
    'Bob sees Ada''s reply to Cy, whom he does not know');
  perform pg_temp.act(cy);
  perform pg_temp.expect(
    pg_temp.cnt('select 1 from public.moments_comments where body = ''welcome Cy''') = 1,
    'Cy does not see the reply to him');

  -- Deleting. Cy cannot delete Bob's comment; Dee (who sees it) cannot
  -- either; the commenter and the poster can.
  perform pg_temp.act(cy);
  delete from public.moments_comments where id = bob_comment;
  perform pg_temp.act(dee);
  delete from public.moments_comments where id = bob_comment;
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    pg_temp.cnt(format('select 1 from public.moments_comments where id = %L', bob_comment)) = 1,
    'a comment was deleted by someone who is neither its author nor the poster');
  perform pg_temp.act(bob);
  -- Bob's reply parent is deleted: Dee's reply remains, as an answer to Bob.
  perform pg_temp.act(ada);
  delete from public.moments_comments where id = bob_comment;
  perform pg_temp.expect(
    pg_temp.cnt(format('select 1 from public.moments_comments where id = %L', bob_comment)) = 0,
    'the poster could not delete a comment');
  perform pg_temp.expect(
    pg_temp.cnt(format('select 1 from public.moments_comments where id = %L', dee_reply)) = 1,
    'deleting a comment took its replies along');
  perform pg_temp.act(dee);
  delete from public.moments_comments where id = dee_reply;
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    pg_temp.cnt(format('select 1 from public.moments_comments where id = %L', dee_reply)) = 0,
    'the author could not delete their comment');
  -- Likes: own only.
  perform pg_temp.act(dee);
  delete from public.moments_likes where user_id = bob;
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.moments_likes where user_id = %L', bob)) = 1, 'Dee removed Bob''s like');
  delete from public.moments_likes where post_id = post and user_id = bob;
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.moments_likes where user_id = %L', bob)) = 0, 'Bob could not unlike');
  insert into public.moments_likes (post_id, user_id) values (post, bob);

  -- Anonymous callers get nothing.
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused('select 1 from public.moments_likes'), 'anon reads likes');
  perform pg_temp.expect(pg_temp.refused('select * from public.moments_feed()'), 'anon reads the feed');
end $$;

-- ------------------------------------------------------ notifications

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  cy uuid := '00000000-0000-4000-8000-0000000000c1';
  dee uuid := '00000000-0000-4000-8000-0000000000d1';
  post uuid := '40000000-0000-4000-8000-000000000001';
  bob_comment uuid;
  n integer;
  ids uuid[];
begin
  reset role;
  delete from public.moments_notifications;
  perform pg_temp.act(ada);
  perform public.create_moment(post, 'notify me');

  perform pg_temp.act(bob);
  insert into public.moments_likes (post_id, user_id) values (post, bob);
  perform pg_temp.act(cy);
  insert into public.moments_likes (post_id, user_id) values (post, cy);
  perform pg_temp.act(bob);
  insert into public.moments_comments (post_id, author_id, body) values (post, bob, 'first') returning id into bob_comment;
  perform pg_temp.act(dee);
  insert into public.moments_comments (post_id, author_id, reply_to_comment_id, body)
  values (post, dee, bob_comment, 'second');
  perform pg_temp.act(ada);
  insert into public.moments_comments (post_id, author_id, reply_to_comment_id, body)
  values (post, ada, bob_comment, 'my own reply');

  -- Ada: Bob and Cy liked, Bob and Dee commented. Her own reply is not hers
  -- to be told about.
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    (select count(*) from public.list_moments_notifications() where kind = 'like') = 2,
    'Ada should have 2 like notices');
  perform pg_temp.expect(
    (select count(*) from public.list_moments_notifications() where kind = 'comment') = 2,
    format('Ada should have 2 comment notices, has %s',
      (select count(*) from public.list_moments_notifications() where kind = 'comment')));
  perform pg_temp.expect(
    (select count(*) from public.list_moments_notifications() where actor_id = ada) = 0,
    'Ada was told of her own action');
  perform pg_temp.expect(
    (select count(*) from public.list_moments_notifications() where is_unread) = 4,
    'the notices should be unread');
  -- Bob: Dee and Ada replied to him. Cy, who is not Bob's friend, is not
  -- told Bob liked; Bob is not told about Cy's like.
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    (select count(*) from public.list_moments_notifications() where kind = 'reply') = 2,
    'Bob should have 2 reply notices');
  perform pg_temp.expect(
    (select count(*) from public.list_moments_notifications()) = 2,
    'Bob has notices he should not have');
  -- Cy has none: nobody replied to him.
  perform pg_temp.act(cy);
  perform pg_temp.expect((select count(*) from public.list_moments_notifications()) = 0, 'Cy has notices');
  -- Dee gets nothing for Ada's reply to Bob.
  perform pg_temp.act(dee);
  perform pg_temp.expect((select count(*) from public.list_moments_notifications()) = 0, 'Dee has notices');

  -- Reading, one by one and all.
  perform pg_temp.act(ada);
  select array_agg(id) into ids from (select id from public.list_moments_notifications() limit 1) q;
  perform public.mark_moments_notifications_read(ids);
  perform pg_temp.expect((select count(*) from public.list_moments_notifications() where is_unread) = 3, 'marking one read changed the wrong number');
  perform public.mark_moments_notifications_read();
  perform pg_temp.expect((select count(*) from public.list_moments_notifications() where is_unread) = 0, 'mark all read left unread notices');
  -- Somebody else's notices are not Cy's to mark.
  perform pg_temp.act(cy);
  perform public.mark_moments_notifications_read();

  -- Notifications are not readable directly.
  perform pg_temp.act(ada);
  perform pg_temp.expect(pg_temp.refused('select 1 from public.moments_notifications'), 'the notifications table is readable');

  -- Unliking takes the notice back; unfriending hides the rest.
  perform pg_temp.act(bob);
  delete from public.moments_likes where post_id = post and user_id = bob;
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    (select count(*) from public.list_moments_notifications() where kind = 'like') = 1,
    'unliking left its notice');
  reset role;
  delete from public.friendships
  where user_low_id = least(bob, ada) and user_high_id = greatest(bob, ada);
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    (select count(*) from public.list_moments_notifications() where actor_id = bob) = 0,
    'Ada still gets notices from the friend she removed');
  perform pg_temp.expect(
    (select count(*) from public.list_moments_notifications() where actor_id = cy) = 1,
    'unfriending Bob removed Cy''s notice');
  reset role;
  perform pg_temp.befriend(ada, bob);

  -- Deleting the post deletes the notices.
  perform pg_temp.act(ada);
  perform public.delete_moment(post);
  perform pg_temp.expect((select count(*) from public.list_moments_notifications()) = 0, 'notices outlived their post');
end $$;

-- ----------------------------------------------------------- pictures

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  cy uuid := '00000000-0000-4000-8000-0000000000c1';
  eli uuid := '00000000-0000-4000-8000-0000000000e1';
  fay uuid := '00000000-0000-4000-8000-0000000000f1';
  dee uuid := '00000000-0000-4000-8000-0000000000d1';
  open_post uuid := '50000000-0000-4000-8000-000000000001';
  secret_post uuid := '50000000-0000-4000-8000-000000000002';
  except_cy uuid := '50000000-0000-4000-8000-000000000003';
  open_photo text;
  open_thumb text;
  secret_photo text;
  except_photo text;
  cover text := '00000000-0000-4000-8000-0000000000a1/cover-60000000-0000-4000-8000-000000000001.jpg';
  freed text;
  paths text[];
  seen integer;
begin
  reset role;
  open_photo := ada || '/' || open_post || '-0.jpg';
  open_thumb := ada || '/' || open_post || '-0-t.jpg';
  secret_photo := ada || '/' || secret_post || '-0.jpg';
  except_photo := ada || '/' || except_cy || '-0.jpg';

  -- The bucket: private, image only, small.
  perform pg_temp.expect(
    exists (
      select 1 from storage.buckets
      where id = 'moments' and not public
        and file_size_limit between 1 and 10485760
        and allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
    ),
    'the moments bucket is not private, small and image only');

  -- Ada uploads (files first, the post after).
  perform pg_temp.act(ada);
  insert into storage.objects (bucket_id, name, owner, owner_id)
  values
    ('moments', open_photo, ada, ada::text),
    ('moments', open_thumb, ada, ada::text),
    ('moments', secret_photo, ada, ada::text),
    ('moments', except_photo, ada, ada::text),
    ('moments', cover, ada, ada::text);
  perform pg_temp.expect(
    pg_temp.refused(format('insert into storage.objects (bucket_id, name, owner, owner_id) values (''moments'', %L, %L, %L)', ada || '/notes.txt', ada, ada::text)),
    'a file with a free-form name was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('insert into storage.objects (bucket_id, name, owner, owner_id) values (''moments'', %L, %L, %L)', ada || '/' || open_post || '-9.jpg', ada, ada::text)),
    'a ninth photo index was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('insert into storage.objects (bucket_id, name, owner, owner_id) values (''moments'', %L, %L, %L)', ada || '/x/' || open_post || '-1.jpg', ada, ada::text)),
    'a nested path was accepted');
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.refused(format('insert into storage.objects (bucket_id, name, owner, owner_id) values (''moments'', %L, %L, %L)', ada || '/' || open_post || '-1.jpg', bob, bob::text)),
    'Bob wrote into Ada''s folder');

  perform pg_temp.act(ada);
  perform public.create_moment(
    open_post, 'with a picture',
    jsonb_build_array(jsonb_build_object('path', open_photo, 'thumb', open_thumb, 'w', 800, 'h', 600)));
  perform public.create_moment(
    secret_post, 'private picture',
    jsonb_build_array(jsonb_build_object('path', secret_photo, 'thumb', ada || '/' || secret_post || '-0-t.jpg', 'w', 800, 'h', 600)),
    null, null, null, 'private');
  perform public.create_moment(
    except_cy, 'not for Cy',
    jsonb_build_array(jsonb_build_object('path', except_photo, 'thumb', ada || '/' || except_cy || '-0-t.jpg', 'w', 800, 'h', 600)),
    null, null, null, 'except', array[cy]);
  perform public.set_moments_settings(null, cover);

  -- Who reads what.
  perform pg_temp.expect(pg_temp.reads(open_photo) and pg_temp.reads(secret_photo), 'Ada cannot read her own pictures');
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.reads(open_photo) and pg_temp.reads(open_thumb), 'Bob cannot read a friends-only picture');
  perform pg_temp.expect(not pg_temp.reads(secret_photo), 'Bob reads a private picture');
  perform pg_temp.expect(pg_temp.reads(except_photo), 'Bob cannot read a picture shared with him');
  perform pg_temp.expect(pg_temp.reads(cover), 'Bob cannot read his friend''s cover');
  perform pg_temp.act(cy);
  perform pg_temp.expect(pg_temp.reads(open_photo), 'Cy cannot read a friends-only picture');
  perform pg_temp.expect(not pg_temp.reads(except_photo), 'Cy reads a picture hidden from him');
  perform pg_temp.act(eli);
  perform pg_temp.expect(
    not pg_temp.reads(open_photo) and not pg_temp.reads(open_thumb) and not pg_temp.reads(cover),
    'a stranger reads pictures');
  perform pg_temp.expect(
    pg_temp.cnt('select 1 from storage.objects where bucket_id = ''moments''') = 0,
    'a stranger lists the bucket');
  perform pg_temp.act(fay);
  perform pg_temp.expect(not pg_temp.reads(open_photo) and not pg_temp.reads(cover), 'a friend of a friend reads pictures');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.cnt('select 1 from storage.objects where bucket_id = ''moments''') = 0, 'anon lists the bucket');

  -- Hiding Moments from Bob closes the pictures and the cover.
  perform pg_temp.act(ada);
  perform public.set_moments_friend_pref(bob, true, null);
  perform pg_temp.act(bob);
  perform pg_temp.expect(not pg_temp.reads(open_photo) and not pg_temp.reads(cover), 'Bob reads pictures after being hidden from');
  perform pg_temp.act(ada);
  perform public.set_moments_friend_pref(bob, false, null);

  -- The visible range closes old pictures.
  reset role;
  update public.moments_posts set created_at = now() - interval '45 days' where id = open_post;
  perform pg_temp.act(ada);
  perform public.set_moments_settings('one_month');
  perform pg_temp.act(bob);
  perform pg_temp.expect(not pg_temp.reads(open_photo) and not pg_temp.reads(open_thumb), 'Bob reads a picture older than the visible range');
  perform pg_temp.act(ada);
  perform public.set_moments_settings('all');

  -- Blocking and unfriending close everything at once.
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.reads(open_photo) and pg_temp.reads(cover), 'Bob cannot read again after the range reset');
  reset role;
  delete from public.friendships
  where user_low_id = least(bob, ada) and user_high_id = greatest(bob, ada);
  perform pg_temp.act(bob);
  perform pg_temp.expect(not pg_temp.reads(open_photo) and not pg_temp.reads(cover), 'Bob reads pictures after being unfriended');
  perform pg_temp.expect(
    (select count(*) from public.moments_feed(50) where author_id = ada) = 0,
    'Bob''s feed has Ada''s posts after being unfriended');
  reset role;
  perform pg_temp.befriend(ada, bob);
  -- A block row alone (the friendship still there) is enough.
  insert into public.blocks (blocker_id, blocked_id) values (bob, ada);
  perform pg_temp.act(bob);
  perform pg_temp.expect(not pg_temp.reads(open_photo) and not pg_temp.table_sees(open_post), 'Bob reads Ada''s post after blocking her');
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    cardinality(pg_temp.feed_ids(bob)) = 0,
    'Ada reads Bob''s page though Bob blocked her');
  reset role;
  delete from public.blocks where blocker_id = bob and blocked_id = ada;

  -- The real block function removes the friendship too.
  perform pg_temp.act(cy);
  perform public.block_user(ada);
  perform pg_temp.expect(not pg_temp.reads(open_photo), 'Cy reads pictures after blocking Ada');
  perform pg_temp.expect(
    (select count(*) from public.moments_feed(50) where author_id = ada) = 0,
    'Cy''s feed has Ada''s posts after blocking');
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    cardinality(pg_temp.feed_ids(cy)) = 0,
    'Ada reads Cy''s page after Cy blocked her');
  reset role;
  perform pg_temp.befriend(ada, cy);
  delete from public.blocks where blocker_id = cy and blocked_id = ada;

  -- Nobody but the owner removes or replaces files.
  -- (Storage refuses deletes from SQL unless told it is on purpose.)
  perform set_config('storage.allow_delete_query', 'true', true);
  perform pg_temp.act(bob);
  delete from storage.objects where bucket_id = 'moments' and name = open_photo;
  update storage.objects set name = bob || '/' || open_post || '-0.jpg' where bucket_id = 'moments' and name = open_photo;
  reset role;
  perform pg_temp.expect(
    exists (select 1 from storage.objects where bucket_id = 'moments' and name = open_photo),
    'Bob removed or moved Ada''s picture');

  -- delete_moment returns the picture and thumbnail; only the author may.
  perform pg_temp.act(bob);
  perform pg_temp.expect((select count(*) from public.delete_moment(open_post)) = 0, 'Bob deleted Ada''s post');
  perform pg_temp.act(ada);
  select array_agg(object_path order by object_path) into paths from public.delete_moment(open_post);
  perform pg_temp.expect(
    paths = array[open_photo, open_thumb] or paths = array[open_thumb, open_photo],
    format('delete_moment returned %s', paths));
  delete from storage.objects where bucket_id = 'moments' and name = any (paths);
  perform pg_temp.expect(not pg_temp.table_sees(open_post), 'the deleted post is still there');
  -- The cover can be replaced and cleared; the old file is handed back.
  select public.set_moments_settings(null, null, true) into freed;
  perform pg_temp.expect(freed = cover, format('clearing the cover freed %s', freed));
  perform pg_temp.expect(
    pg_temp.refused(format('select public.set_moments_settings(null, %L)', bob || '/cover-60000000-0000-4000-8000-000000000001.jpg')),
    'Ada set a cover from Bob''s folder');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.set_moments_settings(null, %L)', 'not a path')),
    'a malformed cover path was accepted');
end $$;

-- ---------------------------------------------------------- the feed

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  cy uuid := '00000000-0000-4000-8000-0000000000c1';
  eli uuid := '00000000-0000-4000-8000-0000000000e1';
  i integer;
  first_page uuid[];
  second_page uuid[];
  rows_a record;
  last_row record;
  summary record;
  all_ids uuid[];
begin
  reset role;
  delete from public.moments_posts;
  perform pg_temp.act(ada);
  for i in 1..5 loop
    perform public.create_moment(('70000000-0000-4000-8000-00000000000' || i)::uuid, 'post ' || i);
  end loop;
  perform pg_temp.act(cy);
  for i in 6..7 loop
    perform public.create_moment(('70000000-0000-4000-8000-00000000000' || i)::uuid, 'post ' || i);
  end loop;
  reset role;
  -- A shared timestamp tests the id tie-break.
  update public.moments_posts set created_at = now() - interval '1 hour'
  where id in ('70000000-0000-4000-8000-000000000003', '70000000-0000-4000-8000-000000000004');
  update public.moments_posts set created_at = now() - interval '2 hours'
  where id = '70000000-0000-4000-8000-000000000002';
  update public.moments_posts set created_at = now() - interval '3 hours'
  where id = '70000000-0000-4000-8000-000000000001';
  update public.moments_posts set created_at = now() - interval '30 minutes'
  where id = '70000000-0000-4000-8000-000000000006';

  -- Bob: Ada's five (Cy's two are not for him: not his friend).
  perform pg_temp.act(bob);
  select array_agg(f.id order by f.created_at desc, f.id desc) into first_page
  from public.moments_feed(2) f;
  perform pg_temp.expect(cardinality(first_page) = 2, 'the first page is not 2 posts');
  select f.* into last_row from public.moments_feed(2) f order by f.created_at asc, f.id asc limit 1;
  select array_agg(f.id order by f.created_at desc, f.id desc) into second_page
  from public.moments_feed(2, last_row.created_at, last_row.id) f;
  perform pg_temp.expect(cardinality(second_page) = 2, 'the second page is not 2 posts');
  perform pg_temp.expect(not (first_page && second_page), 'the pages overlap');
  select f.* into last_row from public.moments_feed(2, last_row.created_at, last_row.id) f order by f.created_at asc, f.id asc limit 1;
  all_ids := first_page || second_page || coalesce((
    select array_agg(f.id) from public.moments_feed(2, last_row.created_at, last_row.id) f), '{}');
  perform pg_temp.expect(cardinality(all_ids) = 5, format('paging returned %s of 5 posts', cardinality(all_ids)));
  perform pg_temp.expect(
    all_ids = (select array_agg(id order by created_at desc, id desc) from public.moments_posts where author_id = ada),
    'paging does not follow newest first');
  perform pg_temp.expect(cardinality(pg_temp.feed_ids(cy)) = 0, 'Bob reads Cy''s page');
  perform pg_temp.expect(
    (select count(*) from public.moments_feed(500)) = 5,
    'a huge limit was not capped or returned the wrong posts');

  -- Ada: her five and Cy's two.
  perform pg_temp.act(ada);
  perform pg_temp.expect(cardinality(pg_temp.feed_ids()) = 7, 'Ada''s feed is not 7 posts');
  perform pg_temp.expect(cardinality(pg_temp.feed_ids(cy)) = 2, 'Cy''s page is not 2 posts');
  perform pg_temp.expect(
    (select count(*) from public.moments_feed(10, null, null, null, '70000000-0000-4000-8000-000000000006')) = 1,
    'a single post was not returned');
  perform pg_temp.expect(
    (select count(*) from public.moments_feed(10, null, null, null, '70000000-0000-4000-8000-000000000001')) = 1,
    'a single post of her own was not returned');
  perform pg_temp.act(eli);
  perform pg_temp.expect(
    (select count(*) from public.moments_feed(10, null, null, null, '70000000-0000-4000-8000-000000000001')) = 0,
    'a stranger got a single post');

  -- The author is shown under the caller's alias for them.
  reset role;
  insert into public.contact_aliases (owner_id, friend_id, alias) values (bob, ada, 'Ada from school');
  perform pg_temp.act(bob);
  select * into rows_a from public.moments_feed(1, null, null, ada);
  perform pg_temp.expect(rows_a.author_name = 'Ada from school', 'the alias is not used for the author');
  perform pg_temp.expect(
    rows_a.photos = '[]'::jsonb and rows_a.like_count = 0 and rows_a.comment_count = 0,
    'an empty post has likes or pictures');

  -- The new-posts badge.
  reset role;
  delete from public.moments_settings;
  perform pg_temp.act(bob);
  select * into summary from public.moments_unseen_summary();
  perform pg_temp.expect(summary.new_count = 5 and summary.latest_author_id = ada,
    format('Bob''s badge: %s from %s', summary.new_count, summary.latest_author_id));
  perform pg_temp.expect(summary.latest_author_name = 'Ada from school', 'the badge poster has no alias');
  perform pg_temp.act(ada);
  select * into summary from public.moments_unseen_summary();
  perform pg_temp.expect(summary.new_count = 2 and summary.latest_author_id = cy, 'Ada''s badge is wrong');
  perform public.mark_moments_seen();
  perform pg_temp.expect((select count(*) from public.moments_unseen_summary()) = 0, 'the badge stays after opening Moments');
  perform pg_temp.act(cy);
  perform public.create_moment('70000000-0000-4000-8000-000000000008', 'fresh');
  perform public.create_moment('70000000-0000-4000-8000-000000000009', 'not for Ada', '[]', null, null, null, 'except', array[ada]);
  reset role;
  -- (One transaction has one now(): move the posts after Ada's visit.)
  update public.moments_posts set created_at = clock_timestamp() + interval '1 second'
  where id in ('70000000-0000-4000-8000-000000000008', '70000000-0000-4000-8000-000000000009');
  perform pg_temp.act(ada);
  perform pg_temp.expect((select new_count from public.moments_unseen_summary()) = 1, 'a new post does not count');
  -- (Cy's second post is hidden from Ada, so it did not count above.)

  -- Covers: friends get the path, strangers no row at all.
  perform pg_temp.act(cy);
  perform public.set_moments_settings(null, cy || '/cover-60000000-0000-4000-8000-000000000002.jpg');
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    (select cover_path from public.get_moments_profile(cy)) = cy || '/cover-60000000-0000-4000-8000-000000000002.jpg',
    'a friend does not get the cover');
  perform pg_temp.act(eli);
  perform pg_temp.expect((select count(*) from public.get_moments_profile(cy)) = 0, 'a stranger got a Moments profile');
  perform pg_temp.act(cy);
  perform pg_temp.expect((select count(*) from public.get_moments_profile(cy)) = 1, 'nobody can open their own Moments profile');
  -- The settings table is private, and so is the preferences table.
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    pg_temp.cnt(format('select 1 from public.moments_settings where user_id = %L', cy)) = 0,
    'Ada reads Cy''s settings');
  perform pg_temp.expect(
    pg_temp.refused(format('update public.moments_settings set visible_range = ''three_days'' where user_id = %L', ada)),
    'settings can be written directly');
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.moments_posts (author_id, body) values (%L, ''x'')', ada)),
    'posts can be inserted directly');
end $$;

-- ------------------------------------------------- creating validation

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  id1 uuid := '80000000-0000-4000-8000-000000000001';
  nine jsonb;
  ten jsonb;
  i integer;
begin
  perform pg_temp.act(ada);
  select jsonb_agg(jsonb_build_object('path', ada || '/' || id1 || '-' || n || '.jpg', 'thumb', ada || '/' || id1 || '-' || n || '-t.jpg', 'w', 100, 'h', 100) order by n)
  into nine from generate_series(0, 8) n;
  select jsonb_agg(jsonb_build_object('path', ada || '/' || id1 || '-' || n || '.jpg', 'thumb', ada || '/' || id1 || '-' || n || '-t.jpg', 'w', 100, 'h', 100) order by n)
  into ten from generate_series(0, 9) n;
  perform pg_temp.expect(public.create_moment(id1, 'nine', nine) = id1, 'nine photos were refused');
  perform pg_temp.expect(
    (select kind from public.moments_posts where id = id1) = 'photos', 'a post with photos is not of kind photos');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, %L, %L::jsonb)', '80000000-0000-4000-8000-000000000002', 'ten', ten)),
    'ten photos were accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, %L, %L::jsonb)', '80000000-0000-4000-8000-000000000003', '', '[]')),
    'an empty post was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, %L, %L::jsonb)', '80000000-0000-4000-8000-000000000004', 'x',
      jsonb_build_array(jsonb_build_object('path', bob || '/' || '80000000-0000-4000-8000-000000000004' || '-0.jpg', 'thumb', bob || '/80000000-0000-4000-8000-000000000004-0-t.jpg')))),
    'photos from another folder were accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, %L, %L::jsonb)', '80000000-0000-4000-8000-000000000005', 'x',
      jsonb_build_array(jsonb_build_object('path', ada || '/other-0.jpg', 'thumb', ada || '/other-0-t.jpg')))),
    'photos of another post were accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, %L, %L::jsonb, %L)', '80000000-0000-4000-8000-000000000006', 'x', nine, 'https://a.test')),
    'photos and a link together were accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, %L, %L::jsonb, %L)', '80000000-0000-4000-8000-000000000007', 'x', '[]', 'javascript:alert(1)')),
    'a javascript link was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, %L, ''[]''::jsonb, null, null, null, %L)', '80000000-0000-4000-8000-000000000008', 'x', 'everyone')),
    'an unknown visibility was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, %L)', '80000000-0000-4000-8000-000000000009', repeat('x', 2001))),
    'a 2001 character post was accepted');
  perform public.create_moment('80000000-0000-4000-8000-000000000010', '', '[]', 'https://example.com/a', 'A page', 'Lisbon');
  perform pg_temp.expect(
    (select kind = 'link' and link_title = 'A page' and location = 'Lisbon' from public.moments_posts where id = '80000000-0000-4000-8000-000000000010'),
    'a link post was not stored as such');

  -- Posting the same id again is a no-op; another person cannot take it.
  perform pg_temp.expect(public.create_moment(id1, 'changed') = id1, 'posting the same id again failed');
  perform pg_temp.expect((select body from public.moments_posts where id = id1) = 'nine', 'posting again changed the post');
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, %L)', id1, 'mine now')),
    'Bob took Ada''s post id');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused('select public.create_moment(gen_random_uuid(), ''x'')'), 'anon posted');
end $$;

-- --------------------------------------- unfriending cleans up tags etc.

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  dee uuid := '00000000-0000-4000-8000-0000000000d1';
  tag uuid;
begin
  perform pg_temp.act(ada);
  select id into tag from public.friend_tags where owner_id = ada and name = 'Work';
  insert into public.friend_stars (owner_id, friend_id) values (ada, dee);
  perform public.set_moments_friend_pref(dee, true, true);
  perform pg_temp.expect(
    (select count(*) from public.friend_tag_members where tag_id = tag and friend_id = dee) = 1,
    'Dee should be in Work');
  reset role;
  delete from public.friendships
  where user_low_id = least(ada, dee) and user_high_id = greatest(ada, dee);
  perform pg_temp.expect(
    (select count(*) from public.friend_tag_members where tag_id = tag and friend_id = dee) = 0,
    'unfriending left Dee in the tag');
  perform pg_temp.expect(
    (select count(*) from public.friend_stars where friend_id = dee) = 0,
    'unfriending left the star');
  perform pg_temp.expect(
    (select count(*) from public.moments_friend_prefs where friend_id = dee) = 0,
    'unfriending left the Moments choices');
end $$;

-- -------------------------------------------------- the rule is strict

-- Account deletion (profile gone) takes posts, comments and likes along.
do $$
declare
  cy uuid := '00000000-0000-4000-8000-0000000000c1';
begin
  reset role;
  delete from public.profiles where id = cy;
  perform pg_temp.expect(
    (select count(*) from public.moments_posts where author_id = cy) = 0
    and (select count(*) from public.moments_comments where author_id = cy) = 0,
    'a deleted profile kept its Moments');
end $$;

reset role;
do $$
declare
  failed text;
begin
  select string_agg(msg, E'\n') into failed from pg_temp.failures;
  if failed is not null then
    raise exception E'moments checks failed:\n%', failed;
  end if;
end $$;

rollback;
