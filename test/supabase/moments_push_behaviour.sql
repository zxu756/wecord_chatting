-- Behaviour checks for Moments push (migration 202610190021). Run by
-- test/supabase/moments_push_test.dart against the local database inside a
-- transaction that is rolled back. Run from the repository root.
--
-- Cast as in moments_behaviour.sql: Ada (a1) posts; her friends are Bob (b1),
-- Cy (c1) and Dee (d1); Bob and Dee are friends of each other, Cy is not a
-- friend of either; Fay (f1) is a friend of Bob only.
\set ON_ERROR_STOP on

begin;

select pg_advisory_xact_lock(20261017);

\i supabase/migrations/202610170002_album_counts.sql
\i supabase/migrations/202610170003_album_summaries.sql
\i supabase/migrations/202610170004_album_push.sql
\i supabase/migrations/202610170005_push_language.sql
\i supabase/migrations/202610170010_scheduled_messages.sql
\i supabase/migrations/202610170011_message_reminders.sql
\i supabase/migrations/202610170012_saved_messages.sql
\i supabase/migrations/202610170020_disappearing_messages.sql
\i supabase/migrations/202610170021_view_once_media.sql
\i supabase/migrations/202610170022_device_sessions.sql
\i supabase/migrations/202610170023_poll_upgrade.sql
\i supabase/migrations/202610170024_profile_visibility.sql
\i supabase/migrations/202610170030_ai_usage.sql
\i supabase/migrations/202610170031_circle_ai_switch.sql
\i supabase/migrations/202610170040_call_links.sql
\i supabase/migrations/202610170050_chat_events.sql
\i supabase/migrations/202610170052_inactive_groups.sql
\i supabase/migrations/202610170053_data_export.sql
\i supabase/migrations/202610170060_notes.sql
\i supabase/migrations/202610170061_note_versions_files.sql
\i supabase/migrations/202610170062_task_lists.sql
\i supabase/migrations/202610170063_task_notifications.sql
\i supabase/migrations/202610170064_tasks_from_messages.sql
\i supabase/migrations/202610170065_conversation_workspace.sql
\i supabase/migrations/202610170070_dispatch_more.sql
\i supabase/migrations/202610170090_ai_guard.sql
\i supabase/migrations/202610170091_ai_guard_hidden.sql
\i supabase/migrations/202610170100_push_time_zone.sql
\i supabase/migrations/202610170101_profile_visibility_enforced.sql
\i supabase/migrations/202610170110_chat_wallpapers.sql
\i supabase/migrations/202610180030_user_qr_codes.sql
\i supabase/migrations/202610180031_group_qr_codes.sql
\i supabase/migrations/202610180032_pat.sql
\i supabase/migrations/202610180033_note_to_self.sql
\i supabase/migrations/202610180034_chat_list_pat_note.sql
\i supabase/migrations/202610180040_friend_tags_and_stars.sql
\i supabase/migrations/202610180041_moments.sql
\i supabase/migrations/202610180042_moments_feed.sql
\i supabase/migrations/202610180050_location.sql
\i supabase/migrations/202610180060_group_chains.sql
\i supabase/migrations/202610180070_merged_forward.sql
\i supabase/migrations/202610180071_contact_cards.sql
\i supabase/migrations/202610190010_security_attachment_paths.sql
\i supabase/migrations/202610190011_security_hidden_messages.sql
\i supabase/migrations/202610190012_security_chains.sql
\i supabase/migrations/202610190013_security_deleted_content.sql
\i supabase/migrations/202610190020_moments_realtime.sql
\i supabase/migrations/202610190021_moments_push.sql

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
  ('00000000-0000-4000-8000-0000000000a1', 'ada@push.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@push.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@push.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee@push.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000f1', 'fay@push.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_push', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_push', 'Bob'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_push', 'Cy'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee_push', 'Dee'),
  ('00000000-0000-4000-8000-0000000000f1', 'fay_push', 'Fay');

create function pg_temp.befriend(a uuid, b uuid) returns void language sql as $$
  insert into public.friendships (user_low_id, user_high_id)
  values (least(a, b), greatest(a, b));
$$;

-- Ada has two browsers, one English and one Chinese; Bob has one.
insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
values
  ('00000000-0000-4000-8000-0000000000a1', 'https://push.test/ada-en', repeat('p', 60), repeat('a', 20), 'en'),
  ('00000000-0000-4000-8000-0000000000a1', 'https://push.test/ada-zh', repeat('q', 60), repeat('b', 20), 'zh'),
  ('00000000-0000-4000-8000-0000000000b1', 'https://push.test/bob', repeat('r', 60), repeat('c', 20), 'en'),
  ('00000000-0000-4000-8000-0000000000c1', 'https://push.test/cy', repeat('s', 60), repeat('d', 20), 'en');

do $$ begin
  perform pg_temp.befriend('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000b1');
  perform pg_temp.befriend('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000c1');
  perform pg_temp.befriend('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000d1');
  perform pg_temp.befriend('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000d1');
  perform pg_temp.befriend('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1');
end $$;

create temp table got (label text, subscription_id uuid, endpoint text, title text, body text, tag text, url text);
grant all on got to public;

-- Claims as the service role and files the rows under [label].
create function pg_temp.claim(label text, caller uuid default null, post uuid default null)
returns integer language plpgsql security definer as $$
declare n integer;
begin
  insert into pg_temp.got
  select label, c.subscription_id, c.endpoint, c.title, c.body, c.tag, c.url
  from public.claim_moments_pushes(caller, post) c;
  get diagnostics n = row_count;
  return n;
end $$;
grant execute on function pg_temp.claim(text, uuid, uuid) to public;

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  cy uuid := '00000000-0000-4000-8000-0000000000c1';
  dee uuid := '00000000-0000-4000-8000-0000000000d1';
  p1 uuid := '30000000-0000-4000-8000-000000000001';
  p2 uuid := '30000000-0000-4000-8000-000000000002';
  c_cy uuid;
  c_ada uuid;
  n integer;
begin
  perform pg_temp.act(ada);
  perform public.create_moment(p1, 'hello world');

  -- ------------------------------------------------------------- a like
  perform pg_temp.act(bob);
  insert into public.moments_likes (post_id, user_id) values (p1, bob);
  perform pg_temp.act(null);
  reset role;

  -- Someone else's app cannot claim Bob's like.
  perform pg_temp.expect(pg_temp.claim('wrong caller', cy, p1) = 0, 'Cy claimed Bob''s like');
  perform pg_temp.expect(pg_temp.claim('wrong post', bob, p2) = 0, 'a like was claimed for another post');
  n := pg_temp.claim('like', bob, p1);
  perform pg_temp.expect(n = 2, format('a like should reach both of Ada''s browsers, got %s', n));
  perform pg_temp.expect(
    (select title from got where label = 'like' and endpoint like '%ada-en') = 'Bob liked your Moment',
    'the English title is wrong');
  perform pg_temp.expect(
    (select title from got where label = 'like' and endpoint like '%ada-zh') = 'Bob 赞了你的朋友圈',
    'the Chinese title is wrong');
  perform pg_temp.expect(
    (select bool_and(body = 'hello world' and tag = 'moments-' || p1 and url = '/#/moments/' || p1)
     from got where label = 'like'),
    'a like push should show the post, tagged and linked to it');
  -- Once.
  perform pg_temp.expect(pg_temp.claim('again', bob, p1) = 0 and pg_temp.claim('sweep', null, null) = 0,
    'a like was pushed twice');

  -- ------------------------------------------------------- alias wins
  insert into public.contact_aliases (owner_id, friend_id, alias) values (ada, cy, 'Cyrus');

  -- ---------------------------------------------------- comment, reply
  perform pg_temp.act(cy);
  insert into public.moments_comments (post_id, author_id, body) values (p1, cy, 'lovely <b>day</b>') returning id into c_cy;
  reset role;
  n := pg_temp.claim('comment', cy, p1);
  perform pg_temp.expect(n = 2, format('a comment should reach Ada''s two browsers, got %s', n));
  perform pg_temp.expect(
    (select title from got where label = 'comment' and endpoint like '%ada-en') = 'Cyrus commented on your Moment'
    and (select body from got where label = 'comment' and endpoint like '%ada-en') = 'lovely <b>day</b>',
    'the comment push should use the alias and show the text');
  perform pg_temp.expect(
    (select title from got where label = 'comment' and endpoint like '%ada-zh') = 'Cyrus 评论了你的朋友圈',
    'the Chinese comment title is wrong');

  -- Ada replies to Cy: Cy hears of the reply (and Ada is not told of her own).
  perform pg_temp.act(ada);
  insert into public.moments_comments (post_id, author_id, body, reply_to_comment_id) values (p1, ada, 'thanks!', c_cy) returning id into c_ada;
  reset role;
  n := pg_temp.claim('reply', ada, p1);
  perform pg_temp.expect(n = 1, format('a reply should reach Cy''s one browser, got %s', n));
  perform pg_temp.expect(
    (select title from got where label = 'reply') = 'Ada replied to your comment'
    and (select endpoint from got where label = 'reply') like '%/cy',
    'the reply push is wrong');

  -- Bob (friend of Ada, not of Cy) cannot see Cy's comment, and Cy's comment
  -- never produced a push to Bob.
  perform pg_temp.expect(not exists (select 1 from got where endpoint like '%/bob'), 'Bob was pushed');

  -- ------------------------------ visibility is checked at push time
  perform pg_temp.act(ada);
  perform public.create_moment(p2, 'second post');
  perform pg_temp.act(bob);
  insert into public.moments_likes (post_id, user_id) values (p2, bob);
  perform pg_temp.act(cy);
  insert into public.moments_comments (post_id, author_id, body) values (p2, cy, 'before the break up');
  reset role;
  -- Ada unfriends Bob before the push is claimed: Bob's like is not pushed,
  -- Cy's comment still is.
  delete from public.friendships
  where user_low_id = least(ada, bob) and user_high_id = greatest(ada, bob);
  n := pg_temp.claim('unfriended', null, null);
  perform pg_temp.expect(
    n = 2 and not exists (select 1 from got where label = 'unfriended' and title like 'Bob%' )
    and exists (select 1 from got where label = 'unfriended' and title like 'Cyrus%'),
    format('unfriending before the push should cancel only Bob''s like, got %s', n));
  perform pg_temp.befriend(ada, bob);

  -- ------------------------------------------------ Do Not Disturb
  insert into public.user_privacy_settings (user_id, presence_status) values (ada, 'dnd')
  on conflict (user_id) do update set presence_status = 'dnd';
  perform pg_temp.act(dee);
  insert into public.moments_likes (post_id, user_id) values (p1, dee);
  reset role;
  perform pg_temp.expect(pg_temp.claim('dnd', dee, p1) = 0, 'Do Not Disturb was pushed through');
  perform pg_temp.expect(
    (select pushed_at is not null from public.moments_notifications where actor_id = dee and post_id = p1),
    'a notification held back by Do Not Disturb should still be closed');
  update public.user_privacy_settings set presence_status = 'online' where user_id = ada;

  -- --------------------------------------- the Moments switch
  perform pg_temp.act(ada);
  perform public.set_moments_settings(p_push_enabled => false);
  perform pg_temp.expect(
    (select push_enabled from public.moments_settings where user_id = ada) = false,
    'the switch was not saved');
  perform pg_temp.act(bob);
  insert into public.moments_comments (post_id, author_id, body) values (p1, bob, 'switch off');
  reset role;
  perform pg_temp.expect(pg_temp.claim('switch off', bob, p1) = 0, 'a push went out with Moments notifications off');
  perform pg_temp.act(ada);
  perform public.set_moments_settings(p_push_enabled => true);
  -- Other settings keep the switch.
  perform public.set_moments_settings(p_visible_range => 'one_month');
  perform pg_temp.expect(
    (select push_enabled from public.moments_settings where user_id = ada),
    'saving the range turned the switch off');
  perform public.set_moments_settings(p_visible_range => 'all');

  -- ------------------------------------------------- stale ones
  perform pg_temp.act(bob);
  insert into public.moments_comments (post_id, author_id, body) values (p1, bob, 'long ago');
  reset role;
  update public.moments_notifications set created_at = now() - interval '11 minutes'
  where actor_id = bob and snippet = 'long ago';
  perform pg_temp.expect(pg_temp.claim('stale', null, null) = 0, 'an old notification was pushed');
  perform pg_temp.expect(
    (select pushed_at is not null from public.moments_notifications where snippet = 'long ago'),
    'an old notification stayed open');

  -- ------------------------------------------ the sweep, no caller
  perform pg_temp.act(bob);
  insert into public.moments_comments (post_id, author_id, body) values (p1, bob, 'swept');
  reset role;
  perform pg_temp.expect(pg_temp.claim('sweep', null, null) = 2, 'the sweep did not find a fresh notification');

  -- -------------------------------------- only the service role
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    pg_temp.refused('select * from public.claim_moments_pushes()'),
    'the app can claim pushes');
  perform pg_temp.act(null);
  perform pg_temp.expect(
    pg_temp.refused('select * from public.claim_moments_pushes()'),
    'anon can claim pushes');
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    pg_temp.refused('select pushed_at from public.moments_notifications'),
    'the app can read pushed_at');
end $$;

reset role;
do $$
declare
  failed text;
begin
  select string_agg(msg, E'\n') into failed from pg_temp.failures;
  if failed is not null then
    raise exception E'moments push checks failed:\n%', failed;
  end if;
end $$;

rollback;
