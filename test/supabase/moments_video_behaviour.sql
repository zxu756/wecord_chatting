-- Behaviour checks for Moments video (migration 202610190022). Run by
-- test/supabase/moments_video_test.dart against the local database inside a
-- transaction that is rolled back. Run from the repository root.
--
-- Cast as in moments_behaviour.sql: Ada (a1) posts; her friends are Bob (b1),
-- Cy (c1) and Dee (d1); Bob and Dee are friends of each other; Eli (e1) has
-- no friends.
\set ON_ERROR_STOP on

begin;

select pg_advisory_xact_lock(20261017);

\i supabase/migrations/202610180040_friend_tags_and_stars.sql
\i supabase/migrations/202610180041_moments.sql
\i supabase/migrations/202610180042_moments_feed.sql
\i supabase/migrations/202610190020_moments_realtime.sql
\i supabase/migrations/202610190021_moments_push.sql
\i supabase/migrations/202610190022_moments_video.sql

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

-- Whether the current person may read an object of the moments bucket.
create function pg_temp.reads(object text) returns boolean language plpgsql as $$
declare n integer;
begin
  select count(*) into n from storage.objects where bucket_id = 'moments' and name = object;
  return n = 1;
end $$;

-- Puts a file in the bucket as the current person (the insert policy applies).
create function pg_temp.upload(object text, size bigint default 1000) returns void language plpgsql as $$
begin
  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('moments', object, auth.uid(), jsonb_build_object('size', size));
end $$;

grant execute on all functions in schema pg_temp to public;

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@vid.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@vid.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@vid.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee@vid.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e1', 'eli@vid.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_vid', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_vid', 'Bob'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_vid', 'Cy'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee_vid', 'Dee'),
  ('00000000-0000-4000-8000-0000000000e1', 'eli_vid', 'Eli');

create function pg_temp.befriend(a uuid, b uuid) returns void language sql as $$
  insert into public.friendships (user_low_id, user_high_id)
  values (least(a, b), greatest(a, b));
$$;

do $$ begin
  perform pg_temp.befriend('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000b1');
  perform pg_temp.befriend('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000c1');
  perform pg_temp.befriend('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000d1');
  perform pg_temp.befriend('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000d1');
end $$;

-- The video of a post as the app sends it.
create function pg_temp.video(owner uuid, post uuid, ext text default 'mp4', ms integer default 42000, size bigint default 3000000)
returns jsonb language sql as $$
  select jsonb_build_object(
    'path', owner || '/' || post || '-v.' || ext,
    'poster', owner || '/' || post || '-0.jpg',
    'thumb', owner || '/' || post || '-0-t.jpg',
    'w', 1280, 'h', 720, 'duration_ms', ms, 'size', size);
$$;
grant execute on function pg_temp.video(uuid, uuid, text, integer, bigint) to public;

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  cy uuid := '00000000-0000-4000-8000-0000000000c1';
  dee uuid := '00000000-0000-4000-8000-0000000000d1';
  eli uuid := '00000000-0000-4000-8000-0000000000e1';
  v1 uuid := '40000000-0000-4000-8000-000000000001';
  v_bob uuid := '40000000-0000-4000-8000-000000000002';
  v_private uuid := '40000000-0000-4000-8000-000000000003';
  bad uuid := '40000000-0000-4000-8000-000000000009';
  photo_post uuid := '40000000-0000-4000-8000-00000000000a';
  row_ public.moments_posts%rowtype;
  feed_video jsonb;
  freed text[];
  thumb text;
begin
  perform pg_temp.act(ada);

  -- ------------------------------------------------ a good video post
  perform pg_temp.upload(ada || '/' || v1 || '-0.jpg');
  perform pg_temp.upload(ada || '/' || v1 || '-0-t.jpg');
  perform pg_temp.upload(ada || '/' || v1 || '-v.mp4', 3000000);
  perform public.create_moment(v1, 'a walk', '[]', null, null, null, 'friends', '{}', '{}', pg_temp.video(ada, v1));
  reset role;
  select * into row_ from public.moments_posts where id = v1;
  perform pg_temp.act(ada);
  perform pg_temp.expect(row_.kind = 'video' and row_.photos = '[]'::jsonb, 'a video post should be of kind video, without photos');
  perform pg_temp.expect(
    row_.video->>'path' = ada || '/' || v1 || '-v.mp4'
    and row_.video->>'mime' = 'video/mp4'
    and (row_.video->>'duration_ms')::int = 42000
    and (row_.video->>'size')::bigint = 3000000,
    format('the video was stored wrongly: %s', row_.video));
  -- Again with the same id changes nothing.
  perform public.create_moment(v1, 'a walk', '[]', null, null, null, 'friends', '{}', '{}', pg_temp.video(ada, v1));
  perform pg_temp.expect((select count(*) from public.moments_posts where id = v1) = 1, 'posting the video twice made two');

  -- ----------------------------------------------------- what is refused
  perform pg_temp.upload(ada || '/' || bad || '-0.jpg');
  perform pg_temp.upload(ada || '/' || bad || '-v.mp4');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, '''', ''[]'', null, null, null, ''friends'', ''{}'', ''{}'', %L::jsonb)', bad, pg_temp.video(ada, bad, 'mp4', 61001))),
    'a video over a minute was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, '''', ''[]'', null, null, null, ''friends'', ''{}'', ''{}'', %L::jsonb)', bad, pg_temp.video(ada, bad, 'mp4', 0))),
    'a video of no length was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, '''', ''[]'', null, null, null, ''friends'', ''{}'', ''{}'', %L::jsonb)', bad, pg_temp.video(ada, bad, 'mp4', 1000, 52428801))),
    'a video over 50 MB was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, '''', ''[]'', null, null, null, ''friends'', ''{}'', ''{}'', %L::jsonb)', bad, pg_temp.video(ada, bad, 'avi'))),
    'a video of an unknown type was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, '''', ''[]'', null, null, null, ''friends'', ''{}'', ''{}'', %L::jsonb)', bad, pg_temp.video(bob, bad))),
    'a video in somebody else''s folder was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, '''', ''[]'', null, null, null, ''friends'', ''{}'', ''{}'', %L::jsonb)', bad, pg_temp.video(ada, v1))),
    'a video named after another post was accepted');
  -- Not uploaded yet.
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, '''', ''[]'', null, null, null, ''friends'', ''{}'', ''{}'', %L::jsonb)', v_bob, pg_temp.video(ada, v_bob))),
    'a video that was never uploaded was accepted');
  -- Photos or a link as well.
  perform pg_temp.expect(
    pg_temp.refused(format(
      'select public.create_moment(%L, '''', %L::jsonb, null, null, null, ''friends'', ''{}'', ''{}'', %L::jsonb)',
      bad,
      jsonb_build_array(jsonb_build_object('path', ada || '/' || bad || '-0.jpg', 'thumb', ada || '/' || bad || '-0-t.jpg')),
      pg_temp.video(ada, bad))),
    'a post with photos and a video was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, '''', ''[]'', ''https://example.com'', null, null, ''friends'', ''{}'', ''{}'', %L::jsonb)', bad, pg_temp.video(ada, bad))),
    'a post with a link and a video was accepted');
  perform pg_temp.expect(
    (select count(*) from public.moments_posts where id = bad) = 0,
    'a refused video left a post');
  -- Nobody uploads a video into somebody else's folder, or something else.
  perform pg_temp.expect(
    pg_temp.refused(format('select pg_temp.upload(%L)', bob || '/' || bad || '-v.mp4')),
    'Ada uploaded into Bob''s folder');
  perform pg_temp.expect(
    pg_temp.refused(format('select pg_temp.upload(%L)', ada || '/' || bad || '-v.avi')),
    'a .avi was uploaded');
  perform pg_temp.expect(
    pg_temp.refused(format('select pg_temp.upload(%L)', ada || '/' || bad || '-x.mp4')),
    'an odd name was uploaded');

  -- A photo post still works with the new signature.
  perform pg_temp.upload(ada || '/' || photo_post || '-0.jpg');
  perform pg_temp.upload(ada || '/' || photo_post || '-0-t.jpg');
  perform public.create_moment(photo_post, '', jsonb_build_array(jsonb_build_object(
    'path', ada || '/' || photo_post || '-0.jpg', 'thumb', ada || '/' || photo_post || '-0-t.jpg', 'w', 10, 'h', 10)));
  perform pg_temp.expect((select kind from public.moments_posts where id = photo_post) = 'photos', 'a photo post broke');

  -- -------------------------------------------- who may read the files
  perform pg_temp.expect(
    pg_temp.reads(ada || '/' || v1 || '-v.mp4') and pg_temp.reads(ada || '/' || v1 || '-0.jpg'),
    'Ada cannot read her own video');

  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.reads(ada || '/' || v1 || '-v.mp4'), 'a friend cannot read the video of a friends post');
  perform pg_temp.expect(pg_temp.reads(ada || '/' || v1 || '-0.jpg') and pg_temp.reads(ada || '/' || v1 || '-0-t.jpg'), 'a friend cannot read the poster');
  select f.video into feed_video from public.moments_feed(20, null, null, null, v1) f;
  perform pg_temp.expect(feed_video->>'path' = ada || '/' || v1 || '-v.mp4', format('the feed does not carry the video: %s', feed_video));
  perform pg_temp.expect(
    pg_temp.refused('select audience_friend_ids from public.moments_posts'),
    'the audience is readable');
  perform pg_temp.expect(
    (select video->>'path' from public.moments_posts where id = v1) is not null,
    'the video column is not readable');

  perform pg_temp.act(eli);
  perform pg_temp.expect(not pg_temp.reads(ada || '/' || v1 || '-v.mp4'), 'a stranger can read the video');
  perform pg_temp.expect(not pg_temp.reads(ada || '/' || v1 || '-0.jpg'), 'a stranger can read the poster');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused('select 1 from storage.objects where bucket_id = ''moments''') or not pg_temp.reads(ada || '/' || v1 || '-v.mp4'), 'anon reads the video');

  -- "Only share with Bob": Cy and Dee cannot read the video.
  perform pg_temp.act(ada);
  perform pg_temp.upload(ada || '/' || v_bob || '-0.jpg');
  perform pg_temp.upload(ada || '/' || v_bob || '-0-t.jpg');
  perform pg_temp.upload(ada || '/' || v_bob || '-v.mov', 4000000);
  perform public.create_moment(v_bob, '', '[]', null, null, null, 'only', array[bob], '{}', pg_temp.video(ada, v_bob, 'mov'));
  perform pg_temp.expect((select video->>'mime' from public.moments_posts where id = v_bob) = 'video/quicktime', 'a .mov is not video/quicktime');
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.reads(ada || '/' || v_bob || '-v.mov'), 'Bob cannot read the video shared with him');
  perform pg_temp.act(cy);
  perform pg_temp.expect(not pg_temp.reads(ada || '/' || v_bob || '-v.mov') and not pg_temp.reads(ada || '/' || v_bob || '-0.jpg'),
    'Cy can read the video shared only with Bob');
  perform pg_temp.act(dee);
  perform pg_temp.expect(not pg_temp.reads(ada || '/' || v_bob || '-v.mov'), 'Dee can read the video shared only with Bob');
  perform pg_temp.expect(pg_temp.reads(ada || '/' || v1 || '-v.mp4'), 'Dee cannot read the friends video');

  -- Private.
  perform pg_temp.act(ada);
  perform pg_temp.upload(ada || '/' || v_private || '-0.jpg');
  perform pg_temp.upload(ada || '/' || v_private || '-0-t.jpg');
  perform pg_temp.upload(ada || '/' || v_private || '-v.webm');
  perform public.create_moment(v_private, '', '[]', null, null, null, 'private', '{}', '{}', pg_temp.video(ada, v_private, 'webm'));
  perform pg_temp.act(bob);
  perform pg_temp.expect(not pg_temp.reads(ada || '/' || v_private || '-v.webm'), 'a friend can read a private video');

  -- Don't let them see my Moments (Dee), the visible range, unfriending, blocks.
  perform pg_temp.act(ada);
  perform public.set_moments_friend_pref(dee, true, null);
  perform pg_temp.act(dee);
  perform pg_temp.expect(not pg_temp.reads(ada || '/' || v1 || '-v.mp4'), 'Dee still reads the video after being hidden from');
  perform pg_temp.act(ada);
  perform public.set_moments_friend_pref(dee, false, null);

  reset role;
  update public.moments_posts set created_at = now() - interval '10 days' where id = v1;
  update public.moments_settings set visible_range = 'three_days' where user_id = ada;
  insert into public.moments_settings (user_id, visible_range) values (ada, 'three_days')
  on conflict (user_id) do update set visible_range = 'three_days';
  perform pg_temp.act(bob);
  perform pg_temp.expect(not pg_temp.reads(ada || '/' || v1 || '-v.mp4'), 'a video older than the visible range is readable');
  reset role;
  update public.moments_settings set visible_range = 'all' where user_id = ada;
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.reads(ada || '/' || v1 || '-v.mp4'), 'the range reset did not give the video back');

  reset role;
  delete from public.friendships where user_low_id = least(ada, bob) and user_high_id = greatest(ada, bob);
  perform pg_temp.act(bob);
  perform pg_temp.expect(not pg_temp.reads(ada || '/' || v1 || '-v.mp4'), 'an unfriended person still reads the video');
  reset role;
  perform pg_temp.befriend(ada, bob);
  insert into public.blocks (blocker_id, blocked_id) values (cy, ada);
  perform pg_temp.act(cy);
  perform pg_temp.expect(not pg_temp.reads(ada || '/' || v1 || '-v.mp4'), 'a blocked friend still reads the video');
  reset role;
  delete from public.blocks where blocker_id = cy;

  -- ------------------------------------- notifications show the poster
  perform pg_temp.act(bob);
  insert into public.moments_likes (post_id, user_id) values (v1, bob);
  perform pg_temp.act(ada);
  select n.post_thumb into thumb from public.list_moments_notifications(10) n where n.post_id = v1;
  perform pg_temp.expect(thumb = ada || '/' || v1 || '-0-t.jpg', format('the notification should show the poster, got %s', thumb));

  -- ------------------------------------------------ deleting the post
  select array_agg(object_path order by object_path) into freed from public.delete_moment(v1);
  perform pg_temp.expect(
    freed = array[ada || '/' || v1 || '-0-t.jpg', ada || '/' || v1 || '-0.jpg', ada || '/' || v1 || '-v.mp4']::text[]
    or (select count(*) from unnest(freed)) = 3,
    format('deleting a video post should hand back its three files, got %s', freed));
  perform pg_temp.expect(
    freed @> array[ada || '/' || v1 || '-v.mp4']::text[],
    'the video file is not handed back for removal');
end $$;

reset role;
do $$
declare
  failed text;
begin
  select string_agg(msg, E'\n') into failed from pg_temp.failures;
  if failed is not null then
    raise exception E'moments video checks failed:\n%', failed;
  end if;
end $$;

rollback;
