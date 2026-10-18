-- Behaviour checks for the data export tables and rate limit (migration
-- 202610170053_data_export) and for what the export reads from Moments,
-- chains, notes, lists, saved messages and so on (202610190023_data_export_more). Run by
-- test/supabase/data_export_behaviour_test.dart against the local
-- database inside a transaction that is rolled back. Run from the
-- repository root.
\set ON_ERROR_STOP on

begin;

-- The behaviour checks all run DDL and write the same tables; take turns so
-- they cannot deadlock when the test runner starts them together.
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
\i supabase/migrations/202610170053_data_export.sql
\i supabase/migrations/202610170060_notes.sql
\i supabase/migrations/202610170061_note_versions_files.sql
\i supabase/migrations/202610170062_task_lists.sql
\i supabase/migrations/202610170063_task_notifications.sql
\i supabase/migrations/202610170064_tasks_from_messages.sql
\i supabase/migrations/202610170065_conversation_workspace.sql
\i supabase/migrations/202610170090_ai_guard.sql
\i supabase/migrations/202610170091_ai_guard_hidden.sql
\i supabase/migrations/202610170110_chat_wallpapers.sql
\i supabase/migrations/202610180040_friend_tags_and_stars.sql
\i supabase/migrations/202610180041_moments.sql
\i supabase/migrations/202610180042_moments_feed.sql
\i supabase/migrations/202610180060_group_chains.sql
\i supabase/migrations/202610190023_data_export_more.sql

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

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000f1', 'ada@export.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000f2', 'bob@export.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000f1', 'ada_export', 'Ada'),
  ('00000000-0000-4000-8000-0000000000f2', 'bob_export', 'Bob');

-- The bucket is private, with a size limit and ZIP only.
do $$
begin
  perform pg_temp.check_that(
    (select not public and allowed_mime_types = array['application/zip'] and file_size_limit > 0
       from storage.buckets where id = 'data-exports'),
    'the bucket is private, ZIP only'
  );
end $$;

-- The first request starts an export.
create temp table started (name text primary key, id uuid not null);
grant all on started to public;

do $$
declare
  first_try record;
begin
  select * into first_try
  from public.begin_data_export('00000000-0000-4000-8000-0000000000f1');
  perform pg_temp.check_that(first_try.started, 'the first request starts');
  perform pg_temp.check_that(first_try.status = 'working', 'and is working');
  insert into started values ('first', first_try.export_id);
  perform pg_temp.check_that(
    (select stage = 'queued' and progress = 0 from public.data_exports where id = first_try.export_id),
    'queued at 0'
  );
end $$;

-- A second request while it works is refused and points at it.
do $$
declare
  second_try record;
begin
  select * into second_try
  from public.begin_data_export('00000000-0000-4000-8000-0000000000f1');
  perform pg_temp.check_that(not second_try.started, 'a second request does not start');
  perform pg_temp.check_that(second_try.status = 'working', 'it says the export is working');
  perform pg_temp.check_that(
    second_try.export_id = (select id from started where name = 'first'),
    'and which one'
  );
  perform pg_temp.check_that(
    second_try.retry_after_seconds between 86000 and 86400,
    'about a day to wait'
  );
end $$;

-- Once ready it still counts for 24 hours.
update public.data_exports set status = 'ready', stage = 'ready', progress = 100,
  file_path = 'x/y.zip', completed_at = now(), expires_at = now() + interval '7 days'
where id = (select id from started where name = 'first');

do $$
declare
  third_try record;
begin
  select * into third_try
  from public.begin_data_export('00000000-0000-4000-8000-0000000000f1');
  perform pg_temp.check_that(not third_try.started and third_try.status = 'ready', 'a ready export blocks a new one');
end $$;

-- Others are not held up by it.
do $$
declare
  bob_try record;
begin
  select * into bob_try
  from public.begin_data_export('00000000-0000-4000-8000-0000000000f2');
  perform pg_temp.check_that(bob_try.started, 'another person can export');
end $$;

-- After 24 hours a new one starts.
update public.data_exports
set created_at = now() - interval '25 hours'
where id = (select id from started where name = 'first');
do $$
declare
  next_day record;
begin
  select * into next_day
  from public.begin_data_export('00000000-0000-4000-8000-0000000000f1');
  perform pg_temp.check_that(next_day.started, 'a day later a new export starts');
  insert into started values ('second', next_day.export_id);
end $$;

-- A failed attempt does not count against the limit...
update public.data_exports set status = 'failed', error = 'export_failed'
where id = (select id from started where name = 'second');
do $$
declare
  retry record;
begin
  select * into retry
  from public.begin_data_export('00000000-0000-4000-8000-0000000000f1');
  perform pg_temp.check_that(retry.started, 'after a failure one can try again');
  insert into started values ('third', retry.export_id);
end $$;

-- ...and an export stuck for 20 minutes is given up on.
update public.data_exports set created_at = now() - interval '21 minutes'
where id = (select id from started where name = 'third');
do $$
declare
  after_stuck record;
begin
  select * into after_stuck
  from public.begin_data_export('00000000-0000-4000-8000-0000000000f1');
  perform pg_temp.check_that(after_stuck.started, 'a stuck export does not block');
  perform pg_temp.check_that(
    (select status = 'failed' and error = 'timeout' from public.data_exports
       where id = (select id from started where name = 'third')),
    'the stuck one is marked failed'
  );
end $$;

-- People read their own rows and files, nothing else, and write nothing.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000f1');
set local role authenticated;
do $$
begin
  perform pg_temp.check_that(
    (select count(*) from public.data_exports) = (select count(*) from public.data_exports where user_id = '00000000-0000-4000-8000-0000000000f1'),
    'only own export rows are visible'
  );
  perform pg_temp.check_that(
    (select count(*) from public.data_exports) > 0,
    'own rows are visible'
  );
end $$;
reset role;

set local role authenticated;
do $$
begin
  begin
    perform public.begin_data_export('00000000-0000-4000-8000-0000000000f1');
    raise exception 'check failed: members must not start exports themselves';
  exception when insufficient_privilege then
    null;
  end;
  begin
    insert into public.data_exports (user_id) values ('00000000-0000-4000-8000-0000000000f1');
    raise exception 'check failed: members must not write export rows';
  exception when insufficient_privilege then
    null;
  end;
end $$;
reset role;

-- Storage: the owner reads their folder; others and anonymous do not; no
-- one writes through the API.
insert into storage.objects (bucket_id, name, owner_id)
values
  ('data-exports', '00000000-0000-4000-8000-0000000000f1/20261017T140309Z.zip', null),
  ('data-exports', '00000000-0000-4000-8000-0000000000f2/20261017T140309Z.zip', null);

select pg_temp.act_as('00000000-0000-4000-8000-0000000000f1');
set local role authenticated;
do $$
begin
  perform pg_temp.check_that(
    (select count(*) from storage.objects where bucket_id = 'data-exports') = 1
      and (select name from storage.objects where bucket_id = 'data-exports')
        = '00000000-0000-4000-8000-0000000000f1/20261017T140309Z.zip',
    'a person sees only their own export file'
  );
  begin
    insert into storage.objects (bucket_id, name)
    values ('data-exports', '00000000-0000-4000-8000-0000000000f1/own-upload.zip');
    raise exception 'check failed: uploads through the API must be refused';
  exception when others then
    if sqlerrm like 'check failed%' then
      raise;
    end if;
  end;
end $$;
reset role;

-- =====================================================================
-- Part two (202610190023): Moments, tags, stars, chains, notes, lists,
-- saved messages, reminders, scheduled messages and wallpapers.
--
-- Ada (f1) exports. Bob (f2) is her friend; Cy (f3) is Bob's friend only.
-- G is a group of Ada and Bob; H is a group of Bob and Cy (Ada is not in
-- it). Everything Bob or Cy wrote carries a BOB-/CY- marker that must never
-- appear in Ada's export.
-- =====================================================================

-- A video column may or may not exist yet (it is added in a later
-- migration): the export must carry it whenever it is there.
alter table public.moments_posts add column if not exists video jsonb;

insert into auth.users (id, email, instance_id, aud, role)
values ('00000000-0000-4000-8000-0000000000f3', 'cy@export.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values ('00000000-0000-4000-8000-0000000000f3', 'cy_export', 'Cy');

create function pg_temp.has(doc jsonb, needle text) returns boolean
language sql as $$ select position(needle in doc::text) > 0 $$;

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000f1';
  bob uuid := '00000000-0000-4000-8000-0000000000f2';
  cy uuid := '00000000-0000-4000-8000-0000000000f3';
  g uuid := '00000000-0000-4000-8000-000000000a01';
  h uuid := '00000000-0000-4000-8000-000000000a02';
  family uuid := '00000000-0000-4000-8000-000000000b01';
  bob_tag uuid := '00000000-0000-4000-8000-000000000b02';
  ada_post uuid := '00000000-0000-4000-8000-000000000c01';
  bob_post uuid := '00000000-0000-4000-8000-000000000c02';
  m_ada uuid := '00000000-0000-4000-8000-000000000d01';
  m_bob uuid := '00000000-0000-4000-8000-000000000d02';
  m_bob_h uuid := '00000000-0000-4000-8000-000000000d03';
  chain_a uuid := '00000000-0000-4000-8000-000000000e01';
  chain_b uuid := '00000000-0000-4000-8000-000000000e02';
  chain_h uuid := '00000000-0000-4000-8000-000000000e03';
  note_a uuid := '00000000-0000-4000-8000-000000000f01';
  note_b uuid := '00000000-0000-4000-8000-000000000f02';
  note_h uuid := '00000000-0000-4000-8000-000000000f03';
  note_gone uuid := '00000000-0000-4000-8000-000000000f04';
  list_a uuid := '00000000-0000-4000-8000-000000000a11';
  list_b uuid := '00000000-0000-4000-8000-000000000a12';
  list_h uuid := '00000000-0000-4000-8000-000000000a13';
  item_a uuid := '00000000-0000-4000-8000-000000000a21';
begin
  insert into public.friendships (user_low_id, user_high_id)
  values (least(ada, bob), greatest(ada, bob)), (least(bob, cy), greatest(bob, cy));

  insert into public.conversations (id, type, title)
  values (g, 'group', 'Hike group'), (h, 'group', 'Bob and Cy only');
  insert into public.conversation_members (conversation_id, user_id, role)
  values (g, ada, 'owner'), (g, bob, 'member'), (h, bob, 'owner'), (h, cy, 'member');

  -- Tags, stars, Moments choices.
  insert into public.friend_tags (id, owner_id, name)
  values (family, ada, 'Family'), (bob_tag, bob, 'BOB-TAG');
  insert into public.friend_tag_members (tag_id, owner_id, friend_id)
  values (family, ada, bob), (bob_tag, bob, cy);
  insert into public.friend_stars (owner_id, friend_id) values (ada, bob), (bob, cy);
  insert into public.moments_settings (user_id, visible_range, cover_path)
  values
    (ada, 'one_month', ada::text || '/cover-00000000-0000-4000-8000-000000000001.jpg'),
    (bob, 'three_days', bob::text || '/cover-00000000-0000-4000-8000-000000000002.jpg');
  insert into public.moments_friend_prefs (owner_id, friend_id, hide_mine, hide_theirs)
  values (ada, bob, true, false), (bob, cy, false, true);

  -- Posts: Ada's (shared with Bob and the Family tag, a photo and a video)
  -- and Bob's.
  insert into public.moments_posts (
    id, author_id, body, kind, photos, location, visibility,
    audience_friend_ids, audience_tag_ids, video
  )
  values (
    ada_post, ada, 'ADA-POST', 'photos',
    jsonb_build_array(jsonb_build_object('path', ada::text || '/' || ada_post::text || '-0.jpg', 'w', 10, 'h', 10)),
    'Rome', 'only', array[bob], array[family],
    jsonb_build_object('path', ada::text || '/' || ada_post::text || '-v.mp4', 'size', 1234)
  );
  insert into public.moments_posts (id, author_id, body, kind, visibility)
  values (bob_post, bob, 'BOB-POST', 'text', 'friends');

  insert into public.moments_comments (post_id, author_id, body)
  values
    (ada_post, bob, 'BOB-COMMENT-ON-ADA'),
    (ada_post, ada, 'ADA-COMMENT-ON-OWN'),
    (bob_post, ada, 'ADA-COMMENT-ON-BOB');
  insert into public.moments_likes (post_id, user_id)
  values (ada_post, bob), (bob_post, ada);

  -- Messages and what hangs on them.
  insert into public.messages (id, conversation_id, sender_id, type, body)
  values
    (m_ada, g, ada, 'text', 'ADA-MESSAGE'),
    (m_bob, g, bob, 'text', 'BOB-MESSAGE'),
    (m_bob_h, h, bob, 'text', 'BOB-HIDDEN-MESSAGE');
  insert into public.saved_messages (user_id, message_id, conversation_id)
  values (ada, m_ada, g), (ada, m_bob, g), (bob, m_bob, g), (bob, m_bob_h, h);
  insert into public.message_reminders (user_id, message_id, conversation_id, remind_at)
  values
    (ada, m_ada, g, now() + interval '1 day'),
    (ada, m_bob, g, now() + interval '2 days'),
    (bob, m_bob, g, now() + interval '3 days');
  insert into public.scheduled_messages (owner_id, conversation_id, body, send_at)
  values
    (ada, g, 'ADA-SCHEDULED', now() + interval '1 day'),
    (bob, g, 'BOB-SCHEDULED', now() + interval '1 day');
  insert into public.chat_wallpapers (user_id, conversation_id, kind, preset_id)
  values (ada, g, 'preset', 'aurora');
  insert into public.chat_wallpapers (user_id, conversation_id, kind, photo_path)
  values (bob, null, 'photo', bob::text || '/00000000-0000-4000-8000-000000000003.jpg');

  -- Chains: Ada's (Bob joined), Bob's (Ada joined), Bob's in H.
  insert into public.chains (id, conversation_id, created_by, title, description, example)
  values
    (chain_a, g, ada, 'Ada chain', 'ADA-CHAIN-DESC', 'ADA-EXAMPLE'),
    (chain_b, g, bob, 'Bob chain', 'BOB-CHAIN-DESC', 'BOB-EXAMPLE'),
    (chain_h, h, bob, 'BOB-HIDDEN-CHAIN', 'BOB-HIDDEN-DESC', '');
  insert into public.chain_entries (chain_id, user_id, note)
  values
    (chain_a, ada, 'ADA-ENTRY'), (chain_a, bob, 'BOB-ENTRY'),
    (chain_b, bob, 'BOB-ENTRY-2'), (chain_b, ada, 'ADA-ENTRY-2'),
    (chain_h, bob, 'BOB-HIDDEN-ENTRY'), (chain_h, cy, 'CY-HIDDEN-ENTRY');

  -- Notes: Ada's (Bob edited a line), Bob's (Ada edited a line), Bob's in H
  -- (Ada cannot see it), and one Ada deleted.
  insert into public.notes (id, conversation_id, title, created_by, updated_by, deleted_at)
  values
    (note_a, g, 'Ada note', ada, ada, null),
    (note_b, g, 'Bob note', bob, bob, null),
    (note_h, h, 'BOB-HIDDEN-NOTE-TITLE', bob, bob, null),
    (note_gone, g, 'DELETED-NOTE-TITLE', ada, ada, now());
  insert into public.note_blocks (id, note_id, pos, text, updated_by)
  values
    (gen_random_uuid(), note_a, 'a', 'ADA-LINE', ada),
    (gen_random_uuid(), note_a, 'b', 'BOB-LINE-IN-ADA-NOTE', bob),
    (gen_random_uuid(), note_b, 'a', 'BOB-LINE', bob),
    (gen_random_uuid(), note_b, 'b', 'ADA-LINE-IN-NOTE-OF-BOB', ada),
    (gen_random_uuid(), note_h, 'a', 'BOB-HIDDEN-NOTE-TEXT', bob),
    (gen_random_uuid(), note_gone, 'a', 'DELETED-NOTE-TEXT', ada);

  -- Task lists: Ada's, Bob's with an item of Ada's, Bob's in H.
  insert into public.task_lists (id, conversation_id, title, created_by)
  values
    (list_a, g, 'Ada list', ada),
    (list_b, g, 'Bob list', bob),
    (list_h, h, 'BOB-HIDDEN-LIST', bob);
  insert into public.task_items (id, list_id, title, status, created_by)
  values
    (item_a, list_a, 'ADA-TASK', 'todo', ada),
    (gen_random_uuid(), list_a, 'BOB-TASK-IN-ADA-LIST', 'todo', bob),
    (gen_random_uuid(), list_b, 'ADA-TASK-IN-BOB-LIST', 'todo', ada),
    (gen_random_uuid(), list_b, 'BOB-TASK', 'todo', bob),
    (gen_random_uuid(), list_h, 'BOB-HIDDEN-TASK', 'todo', bob);
  insert into public.task_item_assignees (item_id, list_id, user_id)
  values (item_a, list_a, bob);
end $$;

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000f1';
  moments jsonb := public.export_my_moments('00000000-0000-4000-8000-0000000000f1');
  extras jsonb := public.export_my_extras('00000000-0000-4000-8000-0000000000f1');
  bob_moments jsonb := public.export_my_moments('00000000-0000-4000-8000-0000000000f2');
  bob_extras jsonb := public.export_my_extras('00000000-0000-4000-8000-0000000000f2');
  both_docs text := moments::text || extras::text;
  marker text;
begin
  -- Moments: mine is there.
  perform pg_temp.check_that(moments #>> '{settings,visible_range}' = 'one_month', 'my visible range');
  perform pg_temp.check_that(moments #>> '{settings,cover_path}' like ada::text || '/cover-%', 'my cover file');
  perform pg_temp.check_that(jsonb_array_length(moments -> 'posts') = 1, 'only my post');
  perform pg_temp.check_that(moments #>> '{posts,0,body}' = 'ADA-POST', 'my post text');
  perform pg_temp.check_that(moments #>> '{posts,0,location}' = 'Rome', 'my post place');
  perform pg_temp.check_that(moments #>> '{posts,0,visibility}' = 'only', 'my post visibility');
  perform pg_temp.check_that(moments #>> '{posts,0,photos,0,path}' like ada::text || '/%-0.jpg', 'my photo file');
  perform pg_temp.check_that(moments #>> '{posts,0,video,path}' like ada::text || '/%-v.mp4', 'a video column flows through');
  perform pg_temp.check_that(moments #>> '{posts,0,audience_friends,0,username}' = 'bob_export', 'the audience is named');
  perform pg_temp.check_that(moments #>> '{posts,0,audience_tags,0,name}' = 'Family', 'the audience tag is named');
  perform pg_temp.check_that(jsonb_array_length(moments -> 'comments') = 2, 'my two comments');
  perform pg_temp.check_that(
    (select c ->> 'post_text' from jsonb_array_elements(moments -> 'comments') c where c ->> 'text' = 'ADA-COMMENT-ON-OWN') = 'ADA-POST',
    'my own post text comes with my comment on it'
  );
  perform pg_temp.check_that(
    (select c ->> 'post_text' from jsonb_array_elements(moments -> 'comments') c where c ->> 'text' = 'ADA-COMMENT-ON-BOB') is null,
    'the text of Bob''s post does not'
  );
  perform pg_temp.check_that(
    (select c #>> '{post_author,display_name}' from jsonb_array_elements(moments -> 'comments') c where c ->> 'text' = 'ADA-COMMENT-ON-BOB') = 'Bob',
    'but his name does'
  );
  perform pg_temp.check_that(jsonb_array_length(moments -> 'likes') = 1, 'my one like');
  perform pg_temp.check_that(moments #>> '{likes,0,post_id}' = '00000000-0000-4000-8000-000000000c02', 'a like is a post id');
  perform pg_temp.check_that(moments #>> '{friend_prefs,0,friend,username}' = 'bob_export' and (moments #>> '{friend_prefs,0,hide_mine}')::boolean, 'my choice for a friend');
  perform pg_temp.check_that(moments #>> '{tags,0,name}' = 'Family' and moments #>> '{tags,0,friends,0,username}' = 'bob_export', 'my tag and who is in it');
  perform pg_temp.check_that(moments #>> '{stars,0,friend,username}' = 'bob_export' and jsonb_array_length(moments -> 'stars') = 1, 'my star');

  -- Part two: mine is there.
  perform pg_temp.check_that(jsonb_array_length(extras -> 'chains') = 2, 'the chain I made and the one I joined');
  perform pg_temp.check_that(
    (select c #>> '{my_entry,text}' from jsonb_array_elements(extras -> 'chains') c where c ->> 'title' = 'Ada chain') = 'ADA-ENTRY',
    'my entry in my chain'
  );
  perform pg_temp.check_that(
    (select c #>> '{my_entry,text}' from jsonb_array_elements(extras -> 'chains') c where c ->> 'title' = 'Bob chain') = 'ADA-ENTRY-2',
    'my entry in the chain I joined'
  );
  perform pg_temp.check_that(
    (select c ->> 'description' from jsonb_array_elements(extras -> 'chains') c where c ->> 'title' = 'Bob chain') is null,
    'the description of a chain I did not make is not exported'
  );
  perform pg_temp.check_that(jsonb_array_length(extras -> 'notes') = 2, 'my note and the one I wrote a line in; not the deleted one');
  perform pg_temp.check_that(
    (select jsonb_array_length(n -> 'blocks') from jsonb_array_elements(extras -> 'notes') n where n ->> 'title' = 'Ada note') = 1,
    'only my line of my note'
  );
  perform pg_temp.check_that(jsonb_array_length(extras -> 'task_lists') = 2, 'my list and the list I added to');
  perform pg_temp.check_that(
    (select jsonb_array_length(l -> 'items') from jsonb_array_elements(extras -> 'task_lists') l where l ->> 'title' = 'Ada list') = 1
    and (select l #>> '{items,0,assigned_to,0,username}' from jsonb_array_elements(extras -> 'task_lists') l where l ->> 'title' = 'Ada list') = 'bob_export',
    'only my item, with who it is assigned to by name'
  );
  perform pg_temp.check_that(jsonb_array_length(extras -> 'saved_messages') = 2, 'my two saved messages');
  perform pg_temp.check_that(
    (select s ->> 'text' from jsonb_array_elements(extras -> 'saved_messages') s where (s ->> 'from_you')::boolean) = 'ADA-MESSAGE',
    'the text of the one I wrote'
  );
  perform pg_temp.check_that(
    (select count(*) from jsonb_array_elements(extras -> 'saved_messages') s where not (s ->> 'from_you')::boolean and s ->> 'text' is null) = 1,
    'no text for the one Bob wrote'
  );
  perform pg_temp.check_that(jsonb_array_length(extras -> 'reminders') = 2, 'my two reminders');
  perform pg_temp.check_that(
    (select count(*) from jsonb_array_elements(extras -> 'reminders') r where r ->> 'text' is not null) = 1,
    'a reminder carries text only when the message is mine'
  );
  perform pg_temp.check_that(
    jsonb_array_length(extras -> 'scheduled_messages') = 1 and extras #>> '{scheduled_messages,0,text}' = 'ADA-SCHEDULED',
    'my scheduled message only'
  );
  perform pg_temp.check_that(
    jsonb_array_length(extras -> 'wallpapers') = 1 and extras #>> '{wallpapers,0,preset_id}' = 'aurora',
    'my wallpaper only'
  );

  -- Nothing of Bob's or Cy's, or from where Ada is not, gets in.
  foreach marker in array array[
    'BOB-POST', 'BOB-COMMENT', 'BOB-TAG', 'BOB-MESSAGE', 'BOB-HIDDEN', 'BOB-ENTRY',
    'BOB-CHAIN', 'BOB-EXAMPLE', 'BOB-LINE', 'BOB-NOTE', 'BOB-TASK', 'BOB-SCHEDULED',
    'CY-', 'DELETED-NOTE', 'cy_export', 'Bob and Cy only',
    '00000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000002'
  ] loop
    perform pg_temp.check_that(position(marker in both_docs) = 0, 'Ada''s export holds ' || marker);
  end loop;

  -- And the same the other way round for Bob.
  foreach marker in array array['ADA-POST', 'ADA-COMMENT', 'ADA-MESSAGE', 'ADA-SCHEDULED', 'ADA-ENTRY', 'ADA-LINE', 'ADA-TASK', 'ADA-CHAIN', 'Family'] loop
    perform pg_temp.check_that(
      position(marker in (bob_moments::text || bob_extras::text)) = 0,
      'Bob''s export holds ' || marker
    );
  end loop;
  perform pg_temp.check_that(bob_moments #>> '{posts,0,body}' = 'BOB-POST', 'Bob''s own export has his post');
  perform pg_temp.check_that(pg_temp.has(bob_extras, 'BOB-HIDDEN-NOTE-TEXT'), 'Bob''s own export has his hidden note');
end $$;

-- A person with little of it gets empty sections, not errors.
do $$
declare
  nothing jsonb := public.export_my_moments('00000000-0000-4000-8000-0000000000f3');
  more jsonb := public.export_my_extras('00000000-0000-4000-8000-0000000000f3');
begin
  perform pg_temp.check_that(
    nothing -> 'settings' = 'null'::jsonb and jsonb_array_length(nothing -> 'posts') = 0 and jsonb_array_length(nothing -> 'tags') = 0,
    'an empty Moments export'
  );
  perform pg_temp.check_that(
    jsonb_array_length(more -> 'notes') = 0 and jsonb_array_length(more -> 'chains') = 1
      and more #>> '{chains,0,my_entry,text}' = 'CY-HIDDEN-ENTRY',
    'Cy has one chain entry of their own'
  );
end $$;

-- The export functions are for the service role: not for the app.
set local role authenticated;
do $$
begin
  begin
    perform public.export_my_moments('00000000-0000-4000-8000-0000000000f1');
    raise exception 'check failed: members must not call export_my_moments';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform public.export_my_extras('00000000-0000-4000-8000-0000000000f1');
    raise exception 'check failed: members must not call export_my_extras';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform public.export_person_json('00000000-0000-4000-8000-0000000000f1');
    raise exception 'check failed: members must not call export_person_json';
  exception when insufficient_privilege then
    null;
  end;
end $$;
reset role;
do $$
begin
  begin
    perform public.export_my_moments(null);
    raise exception 'check failed: a user is required';
  exception when sqlstate '22023' then
    null;
  end;
end $$;

rollback;
