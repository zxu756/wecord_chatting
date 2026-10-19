-- Behaviour checks for the Daily (B1: migrations 202610240200 to 202610240250).
-- Run by test/supabase/stories_test.dart against the local database: it applies
-- every migration the database lacks (the local baseline is 202610170001)
-- inside a transaction, acts as several people through row-level security,
-- and rolls back, so the database is left as it was. Run from the repository
-- root.
--
-- What it walks through: posting (the limits, the file names, the folder),
-- every branch of who sees a daily (friends, close friends, only me, only
-- share with and not share with, tags, "do not let them see my Moments",
-- unfriending, blocks), the tray, who viewed (only the author) and quick
-- emojis, the files in the private bucket, replies as private chat messages,
-- reports and the admin queue, the end of a daily and its purge, the data
-- export and deleting an account.
\set ON_ERROR_STOP on

begin;

-- One behaviour script at a time: they change the same tables, and test
-- files run in parallel.
do $$ begin perform pg_advisory_xact_lock(20261017); end $$;
set local client_min_messages = warning;

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
\i supabase/migrations/202610190022_moments_video.sql
\i supabase/migrations/202610190023_data_export_more.sql
\i supabase/migrations/202610190030_client_errors.sql
\i supabase/migrations/202610190050_realtime_private.sql
\i supabase/migrations/202610190051_storage_limits.sql
\i supabase/migrations/202610190060_get_chains.sql
\i supabase/migrations/202610190061_conversation_capabilities.sql
\i supabase/migrations/202610190062_conversation_summary.sql
\i supabase/migrations/202610190070_presence_visibility.sql
\i supabase/migrations/202610190071_drop_online_users_policy.sql
\i supabase/migrations/202610200010_push_text_language.sql
\i supabase/migrations/202610200020_ai_guard_reason_zh.sql
\i supabase/migrations/202610210110_admin_foundation.sql
\i supabase/migrations/202610210120_circle_takedown.sql
\i supabase/migrations/202610210130_admin_rpcs.sql
\i supabase/migrations/202610210200_chat_folders.sql
\i supabase/migrations/202610210300_notification_settings.sql
\i supabase/migrations/202610210310_quiet_hours.sql
\i supabase/migrations/202610210410_privacy_permissions.sql
\i supabase/migrations/202610210420_group_invitations.sql
\i supabase/migrations/202610210430_login_alerts.sql
\i supabase/migrations/202610210500_calendar_feed_tokens.sql
\i supabase/migrations/202610210510_my_agenda.sql
\i supabase/migrations/202610210520_calendar_feed_items.sql
\i supabase/migrations/202610220110_message_reports.sql
\i supabase/migrations/202610220120_message_reports_admin.sql
\i supabase/migrations/202610220130_terms_acceptance.sql
\i supabase/migrations/202610220210_message_edit_history.sql
\i supabase/migrations/202610220220_edit_review.sql
\i supabase/migrations/202610220230_circle_edit_window.sql
\i supabase/migrations/202610220300_read_receipts_setting.sql
\i supabase/migrations/202610220310_message_read_status.sql
\i supabase/migrations/202610220320_remind_unread.sql
\i supabase/migrations/202610220400_message_translations.sql
\i supabase/migrations/202610220410_translation_prefs.sql
\i supabase/migrations/202610220500_user_stickers.sql
\i supabase/migrations/202610220510_send_personal_sticker.sql
\i supabase/migrations/202610220600_join_requests_schema.sql
\i supabase/migrations/202610220610_join_requests_paths.sql
\i supabase/migrations/202610220620_join_request_rpcs.sql
\i supabase/migrations/202610220630_join_request_push.sql
\i supabase/migrations/202610230100_forms_schema.sql
\i supabase/migrations/202610230110_forms_rpcs.sql
\i supabase/migrations/202610230120_forms_results.sql
\i supabase/migrations/202610230130_export_my_forms.sql
\i supabase/migrations/202610230200_onboarding_guide_schema.sql
\i supabase/migrations/202610230210_onboarding_guide_rpcs.sql
\i supabase/migrations/202610230220_onboarding_greeting.sql
\i supabase/migrations/202610230300_circle_invite_tracking.sql
\i supabase/migrations/202610230310_circle_insights_data.sql
\i supabase/migrations/202610230320_circle_insights_rpc.sql
\i supabase/migrations/202610230330_insights_skip_system.sql
\i supabase/migrations/202610230400_ai_assistant_identity.sql
\i supabase/migrations/202610230410_ai_assistant_jobs.sql
\i supabase/migrations/202610230420_ai_assistant_rpcs.sql
\i supabase/migrations/202610230430_ai_reply_channel_send.sql
\i supabase/migrations/202610230500_ai_digest_schema.sql
\i supabase/migrations/202610230510_ai_digest_rpcs.sql
\i supabase/migrations/202610230520_ai_digest_run.sql
\i supabase/migrations/202610230530_ai_digest_push.sql
\i supabase/migrations/202610230540_export_my_ai_digest.sql
\i supabase/migrations/202610230600_status_visibility.sql
\i supabase/migrations/202610230610_profile_birthday.sql
\i supabase/migrations/202610230620_birthday_push.sql
\i supabase/migrations/202610230630_support_links.sql
\i supabase/migrations/202610230640_friend_source.sql
\i supabase/migrations/202610230650_mutuals.sql
\i supabase/migrations/202610240200_stories_schema.sql
\i supabase/migrations/202610240210_stories_visibility.sql
\i supabase/migrations/202610240220_stories_rpcs.sql
\i supabase/migrations/202610240230_story_reports.sql
\i supabase/migrations/202610240240_stories_signals_cleanup.sql
\i supabase/migrations/202610240250_export_my_stories.sql
\i supabase/migrations/202610240400_urgent_schema.sql
\i supabase/migrations/202610240410_urgent_rpcs.sql
\i supabase/migrations/202610240420_announcement_ack_rpcs.sql
\i supabase/migrations/202610240430_urgent_pushes.sql
\i supabase/migrations/202610240440_scheduled_recurrence_schema.sql
\i supabase/migrations/202610240450_scheduled_recurrence_next.sql
\i supabase/migrations/202610240460_dispatch_urgent.sql
\i supabase/migrations/202610240600_feature_flags.sql
\i supabase/migrations/202610240610_feature_flags_admin.sql
\i supabase/migrations/202610240620_announcements.sql
\i supabase/migrations/202610240630_announcements_admin.sql
\i supabase/migrations/202610240640_user_feedback.sql
\i supabase/migrations/202610240650_feedback_admin.sql
\i supabase/migrations/202610240660_export_my_feedback.sql
\o /dev/null
set local storage.allow_delete_query = 'true';

-- ---------------------------------------------------------------- helpers
create function pg_temp.uid(who text) returns uuid language sql immutable as $$
  select ('00000000-0000-4000-8000-0000000000' || who)::uuid;
$$;

-- Becomes [who] (a1, b1, ...); null is a signed-out visitor.
create function pg_temp.act_as(who text) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  if who is null then
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    execute 'set local role anon';
  else
    perform set_config('request.jwt.claim.sub', pg_temp.uid(who)::text, true);
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', pg_temp.uid(who), 'role', 'authenticated')::text,
      true
    );
    execute 'set local role authenticated';
  end if;
end;
$$;

create function pg_temp.root() returns void language plpgsql as $$
begin
  reset role;
end;
$$;

create function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin
  if ok is distinct from true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok: %', label;
end;
$$;

-- Records that [stmt] must raise with SQLSTATE [code].
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

-- The text of the first column of [query], or 'ERR: ...'.
create function pg_temp.val(query text) returns text language plpgsql as $$
declare r text;
begin
  execute query into r;
  return r;
exception when others then
  return 'ERR: ' || sqlerrm;
end;
$$;

create function pg_temp.affected(stmt text) returns bigint language plpgsql as $$
declare n bigint;
begin
  execute stmt;
  get diagnostics n = row_count;
  return n;
end;
$$;

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create function pg_temp.i(n text) returns uuid language sql stable as $$
  select id from pg_temp.ids where name = n;
$$;

grant execute on all functions in schema pg_temp to public;

-- ------------------------------------------------------------- the bucket
-- Puts a file in the stories bucket as the current person (the insert
-- policy applies).
create function pg_temp.upload(object text, size bigint default 1000) returns void language plpgsql as $$
begin
  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('stories', object, auth.uid(), jsonb_build_object('size', size));
end $$;

-- Whether the current person can read an object of the bucket.
create function pg_temp.reads(object text) returns boolean language plpgsql as $$
declare n integer;
begin
  select count(*) into n from storage.objects where bucket_id = 'stories' and name = object;
  return n = 1;
end $$;

-- Posts a photo daily as [who] (files first, then create_story).
create function pg_temp.post(
  who text, sid uuid, vis text default 'friends',
  friends uuid[] default '{}', tags uuid[] default '{}'
) returns void language plpgsql as $$
declare me uuid := pg_temp.uid(who);
begin
  perform pg_temp.act_as(who);
  perform pg_temp.upload(me || '/' || sid || '.jpg');
  perform pg_temp.upload(me || '/' || sid || '-t.jpg');
  perform public.create_story(sid, 'photo', 'mp4', 'caption ' || vis, vis, friends, tags, 720, 1280, null, 1000);
end $$;

-- Whether [who] can select the daily through the table (row level security).
create function pg_temp.sees(who text, sid uuid) returns boolean language plpgsql as $$
declare n integer;
begin
  perform pg_temp.act_as(who);
  select count(*) into n from public.stories where id = sid;
  return n = 1;
end $$;

-- Whether [who] gets the daily from list_author_stories.
create function pg_temp.lists(who text, author text, sid uuid) returns boolean language plpgsql as $$
declare n integer;
begin
  perform pg_temp.act_as(who);
  select count(*) into n from public.list_author_stories(pg_temp.uid(author)) s where s.id = sid;
  return n = 1;
end $$;

-- Whether [who] reads the object.
create function pg_temp.reads_as(who text, object text) returns boolean language plpgsql as $$
begin
  if who = 'root' then
    perform pg_temp.root();
  else
    perform pg_temp.act_as(case when who = 'anon' then null else who end);
  end if;
  return pg_temp.reads(object);
end $$;

grant execute on all functions in schema pg_temp to public;

-- ------------------------------------------------------------------- cast
-- Ada posts. Her friends are Bob, Cy and Dee; Bob and Dee are friends too.
-- Eve has no friends. Root is the platform owner.
insert into auth.users (id, email, instance_id, aud, role)
select pg_temp.uid(v.n), v.name || '@daily.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee'),('e1','eve'),('f1','root')) v(n, name);
insert into public.profiles (id, username, display_name)
select pg_temp.uid(v.n), v.name || '_daily', initcap(v.name)
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee'),('e1','eve'),('f1','root')) v(n, name);
insert into public.app_admins (user_id, role) values (pg_temp.uid('f1'), 'owner');
insert into public.friendships (user_low_id, user_high_id)
select least(pg_temp.uid(v.a), pg_temp.uid(v.b)), greatest(pg_temp.uid(v.a), pg_temp.uid(v.b))
from (values ('a1','b1'),('a1','c1'),('a1','d1'),('b1','d1')) v(a, b);
-- Ada's tag "Family" holds Cy.
insert into public.friend_tags (id, owner_id, name)
values ('7a000000-0000-4000-8000-000000000001', pg_temp.uid('a1'), 'Family');
insert into public.friend_tag_members (tag_id, owner_id, friend_id)
values ('7a000000-0000-4000-8000-000000000001', pg_temp.uid('a1'), pg_temp.uid('c1'));

-- =========================================================== the tables
select pg_temp.act_as('b1');
select pg_temp.refused('nobody reads story_views through the API',
  'select * from public.story_views', '42501');
select pg_temp.refused('nobody reads story_reactions through the API',
  'select * from public.story_reactions', '42501');
select pg_temp.refused('nobody reads the cleanup queue',
  'select * from public.story_media_cleanup', '42501');
select pg_temp.refused('nobody reads story reports through the API',
  'select * from public.story_reports', '42501');
select pg_temp.refused('the audience of a daily is not readable',
  'select audience_friend_ids from public.stories', '42501');
select pg_temp.refused('nobody writes dailies through the API',
  $q$insert into public.stories (author_id, media_kind, media_path, thumb_path)
     values (pg_temp.uid('b1'), 'photo', 'x', 'y')$q$, '42501');
select pg_temp.act_as(null);
select pg_temp.refused('a visitor posts nothing',
  $q$select public.create_story('5c000000-0000-4000-8000-0000000000f0', 'photo')$q$, '42501');
select pg_temp.refused('a visitor reads no tray', 'select * from public.stories_tray()', '42501');

-- ============================================================= posting
select pg_temp.post('a1', '5c000000-0000-4000-8000-000000000001');
select pg_temp.root();
select pg_temp.check('a posted daily lasts 24 hours',
  (select expires_at - created_at = interval '24 hours'
     and media_path = pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000001.jpg'
     and thumb_path = pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000001-t.jpg'
   from public.stories where id = '5c000000-0000-4000-8000-000000000001'));
select pg_temp.act_as('a1');
select public.create_story('5c000000-0000-4000-8000-000000000001', 'photo');
select pg_temp.root();
select pg_temp.check('posting the same id again changes nothing',
  (select count(*) = 1 from public.stories where id = '5c000000-0000-4000-8000-000000000001'));
select pg_temp.act_as('b1');
select pg_temp.refused('somebody else''s id is taken',
  $q$select public.create_story('5c000000-0000-4000-8000-000000000001', 'photo')$q$, '23505');

select pg_temp.act_as('a1');
-- Nothing uploaded yet.
select pg_temp.refused('a daily that was never uploaded',
  $q$select public.create_story('5c000000-0000-4000-8000-000000000002', 'photo')$q$, '22023');
select pg_temp.upload(pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000002.jpg');
select pg_temp.refused('a daily without its thumbnail',
  $q$select public.create_story('5c000000-0000-4000-8000-000000000002', 'photo')$q$, '22023');
select pg_temp.upload(pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000002-t.jpg');
select pg_temp.refused('an unknown kind',
  $q$select public.create_story('5c000000-0000-4000-8000-000000000002', 'gif')$q$, '22023');
select pg_temp.refused('an unknown audience',
  $q$select public.create_story('5c000000-0000-4000-8000-000000000002', 'photo', 'mp4', '', 'public')$q$, '22023');
select pg_temp.refused('"only" with nobody chosen',
  $q$select public.create_story('5c000000-0000-4000-8000-000000000002', 'photo', 'mp4', '', 'only')$q$, '22023');
select pg_temp.refused('"close friends" before there are any',
  $q$select public.create_story('5c000000-0000-4000-8000-000000000002', 'photo', 'mp4', '', 'close')$q$, '22023');
select pg_temp.refused('"only" with a stranger only (strangers are dropped)',
  format($q$select public.create_story('5c000000-0000-4000-8000-000000000002', 'photo', 'mp4', '', 'only', array[%L]::uuid[])$q$, pg_temp.uid('e1')), '22023');
select pg_temp.root();
select pg_temp.check('nothing was made by the refusals',
  (select count(*) = 0 from public.stories where id = '5c000000-0000-4000-8000-000000000002'));

-- Videos: 15 seconds, 20 MB, mp4 mov webm.
select pg_temp.act_as('a1');
select pg_temp.upload(pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000003.jpg');
select pg_temp.upload(pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000003-t.jpg');
select pg_temp.refused('a video that was never uploaded',
  $q$select public.create_story('5c000000-0000-4000-8000-000000000003', 'video', 'mp4', '', 'friends', '{}', '{}', 720, 1280, 9000, 1000)$q$, '22023');
select pg_temp.upload(pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000003-v.mp4', 3000000);
select pg_temp.refused('a video over 15 seconds',
  $q$select public.create_story('5c000000-0000-4000-8000-000000000003', 'video', 'mp4', '', 'friends', '{}', '{}', 720, 1280, 16001, 3000000)$q$, '22023');
select pg_temp.refused('a video of no length',
  $q$select public.create_story('5c000000-0000-4000-8000-000000000003', 'video', 'mp4', '', 'friends', '{}', '{}', 720, 1280, 0, 3000000)$q$, '22023');
select pg_temp.refused('a video of an unknown type',
  $q$select public.create_story('5c000000-0000-4000-8000-000000000003', 'video', 'avi', '', 'friends', '{}', '{}', 720, 1280, 9000, 3000000)$q$, '22023');
select public.create_story('5c000000-0000-4000-8000-000000000003', 'video', 'mp4', '', 'friends', '{}', '{}', 720, 1280, 15000, 3000000);
select pg_temp.root();
select pg_temp.check('a 15 second video is a video daily with a poster',
  (select media_kind = 'video' and mime = 'video/mp4' and duration_ms = 15000
     and poster_path = pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000003.jpg'
     and media_path = pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000003-v.mp4'
   from public.stories where id = '5c000000-0000-4000-8000-000000000003'));
select pg_temp.act_as('a1');
select pg_temp.upload(pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000004.jpg');
select pg_temp.upload(pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000004-t.jpg');
select pg_temp.upload(pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000004-v.mp4', 20971521);
select pg_temp.refused('a video over 20 MB',
  $q$select public.create_story('5c000000-0000-4000-8000-000000000004', 'video', 'mp4', '', 'friends', '{}', '{}', 720, 1280, 9000, 1000)$q$, '22023');

-- Nobody uploads into somebody else's folder, or under an odd name.
select pg_temp.refused('Ada uploads into Bob''s folder',
  format($q$select pg_temp.upload(%L)$q$, pg_temp.uid('b1') || '/5c000000-0000-4000-8000-000000000009.jpg'), '42501');
select pg_temp.refused('an odd file name',
  format($q$select pg_temp.upload(%L)$q$, pg_temp.uid('a1') || '/notes.txt'), '42501');
select pg_temp.refused('a .avi',
  format($q$select pg_temp.upload(%L)$q$, pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000009-v.avi'), '42501');

-- Fifty at a time.
select pg_temp.root();
insert into public.stories (author_id, media_kind, media_path, thumb_path)
select pg_temp.uid('d1'), 'photo', 'p' || g, 't' || g from generate_series(1, 50) g;
select pg_temp.act_as('d1');
select pg_temp.upload(pg_temp.uid('d1') || '/5c000000-0000-4000-8000-000000000051.jpg');
select pg_temp.upload(pg_temp.uid('d1') || '/5c000000-0000-4000-8000-000000000051-t.jpg');
select pg_temp.refused('a 51st live daily',
  $q$select public.create_story('5c000000-0000-4000-8000-000000000051', 'photo')$q$, '54000');
select pg_temp.root();
delete from public.stories where author_id = pg_temp.uid('d1');
delete from public.story_media_cleanup;

-- ====================================================== who sees what
-- Friends: Bob, Cy, Dee yes; Eve no; Ada herself yes.
select pg_temp.check('friends see a "friends" daily',
  pg_temp.sees('b1', '5c000000-0000-4000-8000-000000000001')
  and pg_temp.sees('c1', '5c000000-0000-4000-8000-000000000001')
  and pg_temp.sees('d1', '5c000000-0000-4000-8000-000000000001'));
select pg_temp.check('a stranger does not',
  not pg_temp.sees('e1', '5c000000-0000-4000-8000-000000000001'));
select pg_temp.check('the author does',
  pg_temp.sees('a1', '5c000000-0000-4000-8000-000000000001'));
select pg_temp.check('the list sees the same',
  pg_temp.lists('b1', 'a1', '5c000000-0000-4000-8000-000000000001')
  and not pg_temp.lists('e1', 'a1', '5c000000-0000-4000-8000-000000000001'));

-- Only me.
select pg_temp.post('a1', '5c000000-0000-4000-8000-000000000011', 'private');
select pg_temp.check('"only me" is seen by nobody else',
  pg_temp.sees('a1', '5c000000-0000-4000-8000-000000000011')
  and not pg_temp.sees('b1', '5c000000-0000-4000-8000-000000000011')
  and not pg_temp.sees('c1', '5c000000-0000-4000-8000-000000000011'));

-- Close friends. A stranger cannot be made one; the list is checked.
select pg_temp.act_as('a1');
select public.set_close_friends(array[pg_temp.uid('b1'), pg_temp.uid('e1')]);
select pg_temp.check('only friends can be close friends',
  (select array_agg(friend_id) = array[pg_temp.uid('b1')] from public.list_close_friends()));
select pg_temp.post('a1', '5c000000-0000-4000-8000-000000000012', 'close');
select pg_temp.check('close friends see a "close" daily, other friends do not',
  pg_temp.sees('b1', '5c000000-0000-4000-8000-000000000012')
  and not pg_temp.sees('c1', '5c000000-0000-4000-8000-000000000012')
  and not pg_temp.sees('d1', '5c000000-0000-4000-8000-000000000012')
  and not pg_temp.sees('e1', '5c000000-0000-4000-8000-000000000012')
  and pg_temp.sees('a1', '5c000000-0000-4000-8000-000000000012'));
select pg_temp.act_as('c1');
select pg_temp.check('nobody reads another person''s close friends',
  (select count(*) = 0 from public.story_close_friends where owner_id = pg_temp.uid('a1')));

-- Only share with Bob and the tag Family (Cy).
select pg_temp.post('a1', '5c000000-0000-4000-8000-000000000013', 'only',
  array[pg_temp.uid('b1'), pg_temp.uid('e1')], array['7a000000-0000-4000-8000-000000000001']::uuid[]);
select pg_temp.check('"only share with" takes friends and tags',
  pg_temp.sees('b1', '5c000000-0000-4000-8000-000000000013')
  and pg_temp.sees('c1', '5c000000-0000-4000-8000-000000000013')
  and not pg_temp.sees('d1', '5c000000-0000-4000-8000-000000000013')
  and not pg_temp.sees('e1', '5c000000-0000-4000-8000-000000000013'));
select pg_temp.root();
select pg_temp.check('a stranger chosen is dropped from the audience',
  (select cardinality(audience_friend_ids) = 1 from public.stories where id = '5c000000-0000-4000-8000-000000000013'));
-- A friend added to the tag later sees it too (tags are read live).
insert into public.friend_tag_members (tag_id, owner_id, friend_id)
values ('7a000000-0000-4000-8000-000000000001', pg_temp.uid('a1'), pg_temp.uid('d1'));
select pg_temp.check('a friend added to the tag later sees it',
  pg_temp.sees('d1', '5c000000-0000-4000-8000-000000000013'));
select pg_temp.root();
delete from public.friend_tag_members where friend_id = pg_temp.uid('d1');

-- Don't share with Bob.
select pg_temp.post('a1', '5c000000-0000-4000-8000-000000000014', 'except', array[pg_temp.uid('b1')]);
select pg_temp.check('"don''t share with" hides it from those chosen only',
  not pg_temp.sees('b1', '5c000000-0000-4000-8000-000000000014')
  and pg_temp.sees('c1', '5c000000-0000-4000-8000-000000000014')
  and pg_temp.sees('d1', '5c000000-0000-4000-8000-000000000014')
  and not pg_temp.sees('e1', '5c000000-0000-4000-8000-000000000014'));

-- "Don't let them see my Moments" (Dee) hides the dailies too.
select pg_temp.act_as('a1');
select public.set_moments_friend_pref(pg_temp.uid('d1'), true, null);
select pg_temp.check('"don''t let them see my Moments" hides dailies too',
  not pg_temp.sees('d1', '5c000000-0000-4000-8000-000000000001')
  and not pg_temp.sees('d1', '5c000000-0000-4000-8000-000000000014')
  and pg_temp.sees('c1', '5c000000-0000-4000-8000-000000000001'));
select pg_temp.act_as('a1');
select public.set_moments_friend_pref(pg_temp.uid('d1'), false, null);
select pg_temp.check('and they come back when it is turned off',
  pg_temp.sees('d1', '5c000000-0000-4000-8000-000000000001'));

-- Unfriending takes effect at once, and takes the close friend off the list.
select pg_temp.root();
delete from public.friendships
where user_low_id = least(pg_temp.uid('a1'), pg_temp.uid('b1'))
  and user_high_id = greatest(pg_temp.uid('a1'), pg_temp.uid('b1'));
select pg_temp.check('an unfriended person sees nothing of hers',
  not pg_temp.sees('b1', '5c000000-0000-4000-8000-000000000001')
  and not pg_temp.sees('b1', '5c000000-0000-4000-8000-000000000012')
  and not pg_temp.lists('b1', 'a1', '5c000000-0000-4000-8000-000000000001')
  and not pg_temp.reads(pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000001.jpg'));
select pg_temp.root();
select pg_temp.check('and is no longer a close friend',
  (select count(*) = 0 from public.story_close_friends where owner_id = pg_temp.uid('a1')));
insert into public.friendships (user_low_id, user_high_id)
values (least(pg_temp.uid('a1'), pg_temp.uid('b1')), greatest(pg_temp.uid('a1'), pg_temp.uid('b1')));
select pg_temp.check('being friends again does not make them a close friend',
  pg_temp.sees('b1', '5c000000-0000-4000-8000-000000000001')
  and not pg_temp.sees('b1', '5c000000-0000-4000-8000-000000000012'));

-- Blocking, either way.
select pg_temp.root();
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.uid('c1'), pg_temp.uid('a1'));
select pg_temp.check('a blocked friend sees nothing (they blocked her)',
  not pg_temp.sees('c1', '5c000000-0000-4000-8000-000000000001'));
select pg_temp.root();
delete from public.blocks;
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.uid('a1'), pg_temp.uid('c1'));
select pg_temp.check('a blocked friend sees nothing (she blocked them)',
  not pg_temp.sees('c1', '5c000000-0000-4000-8000-000000000001'));
select pg_temp.root();
delete from public.blocks;

-- ============================================================ the tray
select pg_temp.act_as('d1');
select pg_temp.check('Dee''s tray has Ada with her new dailies, none of Dee''s own',
  (select count(*) = 1 and bool_and(author_id = pg_temp.uid('a1')) and max(story_count) >= 3
     and min(unseen_count) = max(story_count) and bool_and(not is_me)
   from public.stories_tray()));
select pg_temp.act_as('e1');
select pg_temp.check('a stranger''s tray is empty',
  (select count(*) = 0 from public.stories_tray()));
select pg_temp.act_as('a1');
select pg_temp.check('Ada''s own row comes first, nothing unseen',
  (select is_me and unseen_count = 0 and story_count >= 4 from public.stories_tray() limit 1));
select pg_temp.act_as('d1');
select public.mark_story_viewed('5c000000-0000-4000-8000-000000000001');
select pg_temp.check('viewing counts one less unseen',
  (select unseen_count = story_count - 1 from public.stories_tray() where author_id = pg_temp.uid('a1')));
select pg_temp.check('the list says which were viewed',
  (select viewed from public.list_author_stories(pg_temp.uid('a1')) where id = '5c000000-0000-4000-8000-000000000001')
  and not (select viewed from public.list_author_stories(pg_temp.uid('a1')) where id = '5c000000-0000-4000-8000-000000000014'));
select public.mark_story_viewed('5c000000-0000-4000-8000-000000000001');
select pg_temp.root();
select pg_temp.check('viewing twice counts once',
  (select count(*) = 1 from public.story_views where story_id = '5c000000-0000-4000-8000-000000000001' and viewer_id = pg_temp.uid('d1')));
-- "Hide their Moments" also hides their ring.
select pg_temp.act_as('d1');
select public.set_moments_friend_pref(pg_temp.uid('a1'), null, true);
select pg_temp.check('a friend whose Moments I hid has no ring',
  (select count(*) = 0 from public.stories_tray()));
select public.set_moments_friend_pref(pg_temp.uid('a1'), null, false);

-- ======================================================== who viewed
select pg_temp.act_as('b1');
select public.mark_story_viewed('5c000000-0000-4000-8000-000000000001');
select public.react_to_story('5c000000-0000-4000-8000-000000000001', E'❤️');
select pg_temp.act_as('e1');
select public.mark_story_viewed('5c000000-0000-4000-8000-000000000001');
select pg_temp.act_as('a1');
select public.mark_story_viewed('5c000000-0000-4000-8000-000000000001');
select pg_temp.root();
select pg_temp.check('a stranger''s view and the author''s own are not recorded',
  (select count(*) = 2 from public.story_views where story_id = '5c000000-0000-4000-8000-000000000001'));
select pg_temp.act_as('a1');
select pg_temp.check('Ada sees who viewed and the emoji',
  (select count(*) = 2
     and bool_or(viewer_id = pg_temp.uid('b1') and emoji = E'❤️')
     and bool_or(viewer_id = pg_temp.uid('d1') and emoji is null)
   from public.list_story_viewers('5c000000-0000-4000-8000-000000000001')));
select pg_temp.check('and the counts',
  (select view_count = 2 and reaction_count = 1
   from public.list_author_stories(pg_temp.uid('a1')) where id = '5c000000-0000-4000-8000-000000000001'));
select pg_temp.act_as('b1');
select pg_temp.refused('a viewer cannot list the viewers',
  $q$select * from public.list_story_viewers('5c000000-0000-4000-8000-000000000001')$q$, 'P0002');
select pg_temp.check('a viewer sees no counts',
  (select view_count = 0 and reaction_count = 0 and my_reaction = E'❤️'
   from public.list_author_stories(pg_temp.uid('a1')) where id = '5c000000-0000-4000-8000-000000000001'));
select pg_temp.act_as('e1');
select pg_temp.refused('a stranger cannot list the viewers',
  $q$select * from public.list_story_viewers('5c000000-0000-4000-8000-000000000001')$q$, 'P0002');
select pg_temp.refused('a stranger cannot react',
  $q$select public.react_to_story('5c000000-0000-4000-8000-000000000001', 'x')$q$, 'P0002');
select pg_temp.act_as('a1');
select pg_temp.refused('Ada cannot react to her own',
  $q$select public.react_to_story('5c000000-0000-4000-8000-000000000001', 'x')$q$, '22023');
select pg_temp.act_as('b1');
select public.react_to_story('5c000000-0000-4000-8000-000000000001', E'\U0001F525');
select pg_temp.root();
select pg_temp.check('one reaction per person, replaced when changed',
  (select count(*) = 1 and max(emoji) = E'\U0001F525' from public.story_reactions where story_id = '5c000000-0000-4000-8000-000000000001' and user_id = pg_temp.uid('b1')));
select pg_temp.act_as('b1');
select public.react_to_story('5c000000-0000-4000-8000-000000000001', null);
select pg_temp.root();
select pg_temp.check('null takes the reaction back',
  (select count(*) = 0 from public.story_reactions where user_id = pg_temp.uid('b1')));
-- A viewer who was unfriended is not listed any more.
select pg_temp.root();
delete from public.friendships
where user_low_id = least(pg_temp.uid('a1'), pg_temp.uid('d1'))
  and user_high_id = greatest(pg_temp.uid('a1'), pg_temp.uid('d1'));
select pg_temp.act_as('a1');
select pg_temp.check('an unfriended viewer drops out of the list',
  (select count(*) = 1 and bool_and(viewer_id = pg_temp.uid('b1'))
   from public.list_story_viewers('5c000000-0000-4000-8000-000000000001')));
select pg_temp.root();
insert into public.friendships (user_low_id, user_high_id)
values (least(pg_temp.uid('a1'), pg_temp.uid('d1')), greatest(pg_temp.uid('a1'), pg_temp.uid('d1')));

-- ==================================================== the stored files
select pg_temp.check('friends read the files of a daily they see',
  pg_temp.reads_as('c1', pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000001.jpg')
  and pg_temp.reads_as('c1', pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000001-t.jpg')
  and pg_temp.reads_as('c1', pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000003-v.mp4'));
select pg_temp.check('not the files of one they do not (close friends only)',
  not pg_temp.reads_as('c1', pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000012.jpg')
  and not pg_temp.reads_as('c1', pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000011-t.jpg'));
select pg_temp.check('a stranger reads nothing',
  not pg_temp.reads_as('e1', pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000001.jpg')
  and not pg_temp.reads_as('e1', pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000003-v.mp4'));
select pg_temp.check('a visitor reads nothing',
  not pg_temp.reads_as('anon', pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000001.jpg'));
select pg_temp.check('the author reads her own',
  pg_temp.reads_as('a1', pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000011.jpg'));
select pg_temp.act_as('c1');
select pg_temp.check('a friend cannot delete her files',
  pg_temp.affected(format($q$delete from storage.objects where bucket_id = 'stories' and name = %L$q$,
    pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000001.jpg')) = 0);
select pg_temp.root();
select pg_temp.check('and her file is still there',
  (select count(*) from storage.objects where bucket_id = 'stories' and name = pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000001.jpg') = 1);

-- ============================================================ replying
select pg_temp.act_as('c1');
select public.send_story_reply('5c000000-0000-4000-8000-000000000001', '  Love this  ', '9c000000-0000-4000-8000-000000000001');
select pg_temp.check('Cy''s reply is a private chat message with a story_ref',
  (select m.type = 'text' and m.body = 'Love this'
     and m.attachment->>'kind' = 'story_ref'
     and m.attachment->>'story_id' = '5c000000-0000-4000-8000-000000000001'
     and m.attachment->>'owner_id' = pg_temp.uid('a1')::text
   from public.messages m
   where m.client_id = '9c000000-0000-4000-8000-000000000001'));
select pg_temp.root();
select pg_temp.check('the chat is the direct chat of the two',
  (select c.type = 'direct' and (select count(*) from public.conversation_members cm where cm.conversation_id = c.id) = 2
   from public.messages m join public.conversations c on c.id = m.conversation_id
   where m.client_id = '9c000000-0000-4000-8000-000000000001'));
select pg_temp.act_as('c1');
select pg_temp.check('the same client id gives the same message',
  public.send_story_reply('5c000000-0000-4000-8000-000000000001', 'Love this', '9c000000-0000-4000-8000-000000000001')
  = (select id from public.messages where client_id = '9c000000-0000-4000-8000-000000000001'));
select pg_temp.refused('an empty reply',
  $q$select public.send_story_reply('5c000000-0000-4000-8000-000000000001', '   ')$q$, '22023');
select pg_temp.refused('a reply to a daily she cannot see (close friends only)',
  $q$select public.send_story_reply('5c000000-0000-4000-8000-000000000012', 'hi')$q$, 'P0002');
select pg_temp.check('the reply card is told about the daily',
  (select media_kind = 'photo' and author_id = pg_temp.uid('a1') from public.get_story_ref('5c000000-0000-4000-8000-000000000001')));
select pg_temp.check('and nothing about one she cannot see',
  (select count(*) = 0 from public.get_story_ref('5c000000-0000-4000-8000-000000000012')));
select pg_temp.act_as('e1');
select pg_temp.refused('a stranger''s reply',
  $q$select public.send_story_reply('5c000000-0000-4000-8000-000000000001', 'hi')$q$, 'P0002');
select pg_temp.act_as('a1');
select pg_temp.refused('a reply to her own daily',
  $q$select public.send_story_reply('5c000000-0000-4000-8000-000000000001', 'hi')$q$, '22023');
-- Friends only, and not across a block.
select pg_temp.root();
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.uid('c1'), pg_temp.uid('a1'));
select pg_temp.act_as('c1');
select pg_temp.refused('a reply after Cy blocked Ada',
  $q$select public.send_story_reply('5c000000-0000-4000-8000-000000000001', 'hi again')$q$, 'P0002');
select pg_temp.root();
delete from public.blocks;
select pg_temp.root();
delete from public.friendships
where user_low_id = least(pg_temp.uid('a1'), pg_temp.uid('c1'))
  and user_high_id = greatest(pg_temp.uid('a1'), pg_temp.uid('c1'));
select pg_temp.act_as('c1');
select pg_temp.refused('a reply after being unfriended',
  $q$select public.send_story_reply('5c000000-0000-4000-8000-000000000001', 'hi again')$q$, 'P0002');
select pg_temp.root();
insert into public.friendships (user_low_id, user_high_id)
values (least(pg_temp.uid('a1'), pg_temp.uid('c1')), greatest(pg_temp.uid('a1'), pg_temp.uid('c1')));

-- =========================================================== reporting
select pg_temp.act_as('d1');
select pg_temp.refused('an unknown reason',
  $q$select public.report_story('5c000000-0000-4000-8000-000000000001', 'because')$q$, '22023');
select pg_temp.act_as('e1');
select pg_temp.refused('a stranger cannot report what she cannot see',
  $q$select public.report_story('5c000000-0000-4000-8000-000000000001', 'spam')$q$, 'P0002');
select pg_temp.act_as('a1');
select pg_temp.refused('nobody reports their own',
  $q$select public.report_story('5c000000-0000-4000-8000-000000000001', 'spam')$q$, '22023');
select pg_temp.act_as('d1');
create temp table first_report (id uuid);
grant all on first_report to public;
insert into first_report select public.report_story('5c000000-0000-4000-8000-000000000001', 'harassment', 'rude caption', false);
select pg_temp.check('reporting the same daily again returns the first report',
  public.report_story('5c000000-0000-4000-8000-000000000001', 'spam')
  = (select id from first_report));
select pg_temp.root();
select pg_temp.check('the report keeps a copy of the daily',
  (select snapshot->>'caption' = 'caption friends' and snapshot->>'media_kind' = 'photo'
     and snapshot->>'author_id' = pg_temp.uid('a1')::text and reported_user_id = pg_temp.uid('a1')
   from public.story_reports where reporter_id = pg_temp.uid('d1')));
select pg_temp.act_as('a1');
select pg_temp.refused('the reported person cannot read the reports',
  'select count(*) from public.story_reports', '42501');
select pg_temp.refused('nor ask the admin functions',
  'select public.admin_list_story_reports()', '42501');
select pg_temp.act_as('d1');
select pg_temp.refused('the reporter cannot read the queue either',
  'select public.admin_list_story_reports()', '42501');
select pg_temp.act_as('c1');
select public.report_story('5c000000-0000-4000-8000-000000000014', 'spam', '', true);
select pg_temp.root();
select pg_temp.check('"also block" blocks the author',
  public.are_users_blocked(pg_temp.uid('c1'), pg_temp.uid('a1')));
select pg_temp.root();
delete from public.blocks;
-- (Blocking unfriends: Ada and Cy are friends again.)
insert into public.friendships (user_low_id, user_high_id)
values (least(pg_temp.uid('a1'), pg_temp.uid('c1')), greatest(pg_temp.uid('a1'), pg_temp.uid('c1')))
on conflict do nothing;
delete from public.story_reports where reporter_id = pg_temp.uid('c1');
-- Twenty a day.
insert into public.story_reports (reporter_id, story_id, reported_user_id, reason)
select pg_temp.uid('c1'), null, pg_temp.uid('a1'), 'spam' from generate_series(1, 20);
select pg_temp.act_as('c1');
select pg_temp.refused('the 21st report in a day',
  $q$select public.report_story('5c000000-0000-4000-8000-000000000014', 'spam')$q$, '54000');
select pg_temp.root();
delete from public.story_reports where story_id is null;

-- The admin queue.
select pg_temp.act_as('f1');
select pg_temp.check('the owner sees the report',
  (select jsonb_array_length(x) = 1
     and x->0->>'kind' = 'story' and x->0->>'status' = 'open'
   from (select public.admin_list_story_reports('open') x) y));
select pg_temp.check('one report in full, with the daily still up',
  (select x->'report'->'snapshot'->>'caption' is not null
     and (x->'subject'->>'live')::boolean
     and x->'responsible_user'->>'username' = 'ada_daily'
   from (select public.admin_get_story_report(
     (select id from first_report)) x) y));
select pg_temp.check('an admin reads the files of a reported daily',
  pg_temp.reads(pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000001.jpg')
  and pg_temp.reads(pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000001-t.jpg'));
select pg_temp.check('but not of one nobody reported',
  not pg_temp.reads(pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000011.jpg'));
select pg_temp.refused('an unknown action',
  format($q$select public.admin_resolve_story_report(%L, 'hang')$q$,
    (select id from first_report)), '22023');
select pg_temp.refused('suspend needs the author suspended first',
  format($q$select public.admin_resolve_story_report(%L, 'suspend')$q$,
    (select id from first_report)), '22023');
select pg_temp.check('deleting the daily closes the report',
  (select x->>'status' = 'reviewed' and x->>'resolution' = 'story_deleted'
   from (select public.admin_resolve_story_report(
     (select id from first_report), 'delete_story', 'rude') x) y));
select pg_temp.root();
select pg_temp.check('the daily is gone, its files are queued, and the audit says so',
  (select count(*) = 0 from public.stories where id = '5c000000-0000-4000-8000-000000000001')
  and (select count(*) = 2 from public.story_media_cleanup
       where object_path like pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000001%')
  and (select count(*) = 1 from public.admin_audit_log where action = 'resolve_story_report')
  and (select status = 'actioned' and story_id is null from public.story_reports where reporter_id = pg_temp.uid('d1')));
select pg_temp.act_as('f1');
select pg_temp.refused('a handled report cannot be handled again',
  format($q$select public.admin_resolve_story_report(%L, 'dismiss')$q$,
    (select id from first_report)), 'P0002');
select pg_temp.act_as('b1');
select pg_temp.refused('a person cannot handle reports',
  format($q$select public.admin_resolve_story_report(%L, 'dismiss')$q$,
    (select id from first_report)), '42501');
select pg_temp.root();
-- Reports lose the copy 90 days after they were handled.
update public.story_reports set handled_at = now() - interval '91 days' where reporter_id = pg_temp.uid('d1');
select public.purge_old_story_report_data();
select pg_temp.check('a handled report loses its copy after 90 days',
  (select snapshot is null and reason = 'harassment' from public.story_reports where reporter_id = pg_temp.uid('d1')));

-- =========================================================== the end
-- Expiry: nobody sees an ended daily, not even the author.
select pg_temp.root();
update public.stories set expires_at = now() - interval '1 minute'
where id = '5c000000-0000-4000-8000-000000000013';
select pg_temp.check('an ended daily is seen by nobody, the author included',
  not pg_temp.sees('a1', '5c000000-0000-4000-8000-000000000013')
  and not pg_temp.sees('b1', '5c000000-0000-4000-8000-000000000013')
  and not pg_temp.lists('a1', 'a1', '5c000000-0000-4000-8000-000000000013')
  and not pg_temp.reads_as('a1', pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000013.jpg'));
select pg_temp.act_as('b1');
select pg_temp.refused('no reply to an ended daily',
  $q$select public.send_story_reply('5c000000-0000-4000-8000-000000000013', 'late')$q$, 'P0002');
select pg_temp.refused('no reaction to an ended daily',
  $q$select public.react_to_story('5c000000-0000-4000-8000-000000000013', 'x')$q$, 'P0002');
select pg_temp.check('no card for an ended daily',
  (select count(*) = 0 from public.get_story_ref('5c000000-0000-4000-8000-000000000013')));
select pg_temp.act_as('a1');
select pg_temp.refused('no viewers list for an ended daily',
  $q$select * from public.list_story_viewers('5c000000-0000-4000-8000-000000000013')$q$, 'P0002');

-- A reported daily is kept for the admins until the report is handled.
select pg_temp.root();
insert into public.story_reports (reporter_id, story_id, reported_user_id, reason)
values (pg_temp.uid('e1'), '5c000000-0000-4000-8000-000000000014', pg_temp.uid('a1'), 'spam');
update public.stories set expires_at = now() - interval '2 minutes'
where id in ('5c000000-0000-4000-8000-000000000014');
select pg_temp.act_as('b1');
select pg_temp.refused('only the service role purges',
  'select public.purge_expired_stories()', '42501');
select pg_temp.refused('and only it claims files',
  'select * from public.claim_story_media()', '42501');
select pg_temp.root();
create temp table purged (n integer);
grant all on purged to public;
insert into purged select public.purge_expired_stories(100);
select pg_temp.check('the purge keeps a daily with an open report, drops the rest',
  (select n = 1 from purged)
  and (select count(*) = 1 from public.stories where id = '5c000000-0000-4000-8000-000000000014')
  and (select count(*) = 0 from public.stories where id = '5c000000-0000-4000-8000-000000000013'));
select pg_temp.check('the files of the purged daily are queued',
  (select count(*) = 2 from public.story_media_cleanup
   where object_path like pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000013%'));
select pg_temp.check('an admin reads the reported daily after its end',
  pg_temp.reads_as('f1', pg_temp.uid('a1') || '/5c000000-0000-4000-8000-000000000014.jpg'));
select pg_temp.root();
update public.stories set expires_at = now() - interval '31 days'
where id = '5c000000-0000-4000-8000-000000000014';
delete from purged;
insert into purged select public.purge_expired_stories(100);
select pg_temp.check('an open report keeps it for 30 days past the end at most',
  (select n = 1 from purged));
select pg_temp.check('claiming hands out the queued files',
  (select count(*) from public.claim_story_media(2)) = 2
  and (select count(*) from public.claim_story_media(1000)) = (select count(*) from public.story_media_cleanup));
select public.finish_story_media((select array_agg(object_path) from public.story_media_cleanup));
select pg_temp.check('the queue is empty after finishing',
  (select count(*) = 0 from public.story_media_cleanup));

-- Waking the function does nothing without the Vault secrets, and is not for people.
select pg_temp.root();
select public.wake_expire_stories();
select pg_temp.act_as('b1');
select pg_temp.refused('only the service role wakes expire-stories',
  'select public.wake_expire_stories()', '42501');
select pg_temp.root();

-- ============================================================= export
select pg_temp.root();
select pg_temp.check('the export holds only the person''s dailies',
  (select jsonb_array_length(x->'stories') = (select count(*) from public.stories where author_id = pg_temp.uid('a1'))
     and jsonb_array_length(x->'close_friends') = 0
   from (select public.export_my_stories(pg_temp.uid('a1')) x) y));
select pg_temp.check('Cy''s export holds his report and none of Ada''s dailies',
  (select jsonb_array_length(x->'stories') = 0 and jsonb_typeof(x->'reports') = 'array'
   from (select public.export_my_stories(pg_temp.uid('c1')) x) y));
select pg_temp.act_as('a1');
select pg_temp.refused('nobody exports through the API',
  format($q$select public.export_my_stories(%L)$q$, pg_temp.uid('a1')), '42501');

-- =========================================================== the signal
select pg_temp.root();
select pg_temp.check('only the person''s own signal topic is open to listen on',
  exists (select 1 from pg_policies where schemaname = 'realtime' and tablename = 'messages'
          and policyname = 'stories_signals_receive_own' and cmd = 'SELECT'));

-- =========================================================== the account
select pg_temp.post('d1', '5c000000-0000-4000-8000-0000000000d1');
select pg_temp.act_as('a1');
select public.mark_story_viewed('5c000000-0000-4000-8000-0000000000d1');
select public.react_to_story('5c000000-0000-4000-8000-0000000000d1', 'x');
select pg_temp.post('a1', '5c000000-0000-4000-8000-0000000000a1');
select pg_temp.act_as('d1');
select public.mark_story_viewed('5c000000-0000-4000-8000-0000000000a1');
select pg_temp.root();
select pg_temp.check('before deleting: Ada has dailies and has viewed one of Dee''s',
  (select count(*) > 0 from public.stories where author_id = pg_temp.uid('a1'))
  and (select count(*) = 1 from public.story_views where viewer_id = pg_temp.uid('a1')));
select pg_temp.act_as('a1');
select count(*) from public.prepare_account_deletion();
select pg_temp.root();
select pg_temp.check('deleting an account takes her dailies, files queued, and her views',
  (select count(*) = 0 from public.stories where author_id = pg_temp.uid('a1'))
  and (select count(*) = 0 from public.story_views v where v.viewer_id = pg_temp.uid('a1'))
  and (select count(*) = 0 from public.story_reactions v where v.user_id = pg_temp.uid('a1'))
  and (select count(*) > 0 from public.story_media_cleanup where object_path like pg_temp.uid('a1') || '/%'));
select pg_temp.check('and nobody else''s',
  (select count(*) = 1 from public.stories where author_id = pg_temp.uid('d1')));
select pg_temp.act_as('d1');
select pg_temp.check('her dailies are gone from everybody''s tray',
  (select count(*) = 0 from public.stories_tray() where author_id = pg_temp.uid('a1')));

\o
rollback;
