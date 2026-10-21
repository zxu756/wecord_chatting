-- Behaviour checks for Events 2.0 (C10: migrations 202610270400 to
-- 202610270470). Run by test/supabase/events2_test.dart against the local
-- database: it applies the migrations in a transaction, plays people through
-- them, and rolls everything back. Run from the repository root.
--
-- What it walks through: what the rewritten functions kept; a repeating chat
-- event across daylight saving (Auckland, New York, a month's end); capacity,
-- the waiting list and the push for a seat; questions and answers; checking in
-- with a code; the photos; circle events with the same, the audit log and the
-- K1 take-down; the AI guard reading the questions; leaving, deleting an
-- account and the data export.
\set ON_ERROR_STOP on

begin;

do $$ begin perform pg_advisory_xact_lock(20261017); end $$;
set local client_min_messages = warning;

-- Every migration after the local baseline (202610170001), in order.
\i supabase/migrations/202610170001_media_albums.sql
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
\i supabase/migrations/202610240100_call_captions_host.sql
\i supabase/migrations/202610240200_stories_schema.sql
\i supabase/migrations/202610240210_stories_visibility.sql
\i supabase/migrations/202610240220_stories_rpcs.sql
\i supabase/migrations/202610240230_story_reports.sql
\i supabase/migrations/202610240240_stories_signals_cleanup.sql
\i supabase/migrations/202610240250_export_my_stories.sql
\i supabase/migrations/202610240300_notes_tables.sql
\i supabase/migrations/202610240310_note_comments.sql
\i supabase/migrations/202610240320_note_templates.sql
\i supabase/migrations/202610240330_note_publish.sql
\i supabase/migrations/202610240340_notes2_account.sql
\i supabase/migrations/202610240400_urgent_schema.sql
\i supabase/migrations/202610240410_urgent_rpcs.sql
\i supabase/migrations/202610240420_announcement_ack_rpcs.sql
\i supabase/migrations/202610240430_urgent_pushes.sql
\i supabase/migrations/202610240440_scheduled_recurrence_schema.sql
\i supabase/migrations/202610240450_scheduled_recurrence_next.sql
\i supabase/migrations/202610240460_dispatch_urgent.sql
\i supabase/migrations/202610240500_quote_and_silent.sql
\i supabase/migrations/202610240510_voice_channel_status.sql
\i supabase/migrations/202610240600_feature_flags.sql
\i supabase/migrations/202610240610_feature_flags_admin.sql
\i supabase/migrations/202610240620_announcements.sql
\i supabase/migrations/202610240630_announcements_admin.sql
\i supabase/migrations/202610240640_user_feedback.sql
\i supabase/migrations/202610240650_feedback_admin.sql
\i supabase/migrations/202610240660_export_my_feedback.sql
\i supabase/migrations/202610250100_task_lists2_schema.sql
\i supabase/migrations/202610250110_task_lists2_rpcs.sql
\i supabase/migrations/202610250120_task_lists2_triggers.sql
\i supabase/migrations/202610250130_task_lists2_export.sql
\i supabase/migrations/202610250200_ban_expiry.sql
\i supabase/migrations/202610250210_thread_lock.sql
\i supabase/migrations/202610250220_mod_notes.sql
\i supabase/migrations/202610250230_ban_appeals.sql
\i supabase/migrations/202610250240_member_filter_batch.sql
\i supabase/migrations/202610250250_raid_schema.sql
\i supabase/migrations/202610250260_raid_detect.sql
\i supabase/migrations/202610250270_raid_rpcs.sql
\i supabase/migrations/202610250280_moderation_push.sql
\i supabase/migrations/202610250300_ai_ask.sql
\i supabase/migrations/202610250400_saved_items_schema.sql
\i supabase/migrations/202610250410_saved_items_rpcs.sql
\i supabase/migrations/202610250420_saved_notes_bucket.sql
\i supabase/migrations/202610250430_export_my_saved_items.sql
\i supabase/migrations/202610250510_merged_forward_alt_text.sql
\i supabase/migrations/202610260100_ops_metrics_schema.sql
\i supabase/migrations/202610260110_ops_metrics_compute.sql
\i supabase/migrations/202610260120_ops_metrics_admin.sql
\i supabase/migrations/202610260130_error_groups.sql
\i supabase/migrations/202610260140_ops_alerts_schema.sql
\i supabase/migrations/202610260150_ops_health_checks.sql
\i supabase/migrations/202610260160_ops_alerts_admin.sql
\i supabase/migrations/202610260170_ops_alert_push.sql
\i supabase/migrations/202610260200_guard2_scope.sql
\i supabase/migrations/202610260210_guard2_items.sql
\i supabase/migrations/202610260220_link_preview_final_url.sql
\i supabase/migrations/202610260300_chat_lock.sql
\i supabase/migrations/202610260500_circle_slug.sql
\i supabase/migrations/202610260510_public_circle_card.sql
\i supabase/migrations/202610260600_moments2_schema.sql
\i supabase/migrations/202610260610_moments2_write.sql
\i supabase/migrations/202610260620_moments2_read.sql
\i supabase/migrations/202610260630_moments2_push.sql
\i supabase/migrations/202610260640_moment_card.sql
\i supabase/migrations/202610260650_moments2_account.sql
\i supabase/migrations/202610270100_kb_schema.sql
\i supabase/migrations/202610270110_kb_rpcs.sql
\i supabase/migrations/202610270120_kb_required_reading.sql
\i supabase/migrations/202610270130_kb_account.sql
\i supabase/migrations/202610270200_member_honors_schema.sql
\i supabase/migrations/202610270210_member_titles.sql
\i supabase/migrations/202610270220_member_honors_compute.sql
\i supabase/migrations/202610270230_member_honors_rpcs.sql
\i supabase/migrations/202610270240_member_honors_export.sql
\i supabase/migrations/202610270300_channel_types_schema.sql
\i supabase/migrations/202610270310_qa_solved.sql
\i supabase/migrations/202610270320_media_channel_posts.sql
\i supabase/migrations/202610270330_channel_posts_export.sql
\i supabase/migrations/202610270400_events2_schema.sql
\i supabase/migrations/202610270410_events2_chat_events.sql
\i supabase/migrations/202610270420_events2_circle_events.sql
\i supabase/migrations/202610270430_events2_sweep.sql
\i supabase/migrations/202610270440_events2_checkin.sql
\i supabase/migrations/202610270450_events2_photos.sql
\i supabase/migrations/202610270460_events2_push_guard.sql
\i supabase/migrations/202610270470_events2_account.sql
\o /dev/null

create temp table failures (msg text);
grant all on failures to public;
create temp table checked (msg text);
grant all on checked to public;

create function pg_temp.expect(ok boolean, msg text) returns void
language plpgsql security definer as $$
begin
  insert into pg_temp.checked values (msg);
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

-- Back to the table owner, but still "signed in" as the last person acted
-- as (the claims stay): what a SECURITY DEFINER function sees.
create function pg_temp.root() returns void language plpgsql as $$
begin
  execute 'reset role';
end $$;

create function pg_temp.cnt(query text) returns integer language plpgsql as $$
declare n integer;
begin
  execute format('select count(*) from (%s) q', query) into n;
  return n;
end $$;

create function pg_temp.refused(statement text) returns boolean language plpgsql as $$
begin
  execute statement;
  return false;
exception when others then
  return true;
end $$;

-- The SQLSTATE a statement raises, or 'ok'.
create function pg_temp.state(statement text) returns text language plpgsql as $$
begin
  execute statement;
  return 'ok';
exception when others then
  return sqlstate;
end $$;

-- The message a statement raises, or 'ok'.
create function pg_temp.msg(statement text) returns text language plpgsql as $$
begin
  execute statement;
  return 'ok';
exception when others then
  return sqlerrm;
end $$;

create function pg_temp.val(query text) returns text language plpgsql as $$
declare r text;
begin
  execute query into r;
  return r;
exception when others then
  return 'ERR: ' || sqlerrm;
end $$;

create function pg_temp.must_refuse(statement text, msg text) returns void language plpgsql as $$
begin
  perform pg_temp.expect(pg_temp.refused(statement), msg);
end $$;


create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create function pg_temp.i(n text) returns uuid language sql as $$ select id from pg_temp.ids where name = n $$;
grant execute on function pg_temp.i(text) to public;
grant execute on all functions in schema pg_temp to public;

-- ------------------------------------------------------------------ cast
-- ada runs a group chat (g1) and a circle (club); bob, cat, dan and fay are in
-- both; eve is in neither. root is the platform admin.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@c10.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'fay'),(7,'root')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_c10', initcap(name)
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'fay'),(7,'root')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'fay'),(7,'root')) v(n, name);
insert into public.app_admins (user_id, role) values (pg_temp.i('root'), 'owner');

insert into pg_temp.ids values ('g1', gen_random_uuid()), ('g2', gen_random_uuid()), ('dm', gen_random_uuid());
insert into public.conversations (id, type, title)
values (pg_temp.i('g1'), 'group', 'Hike crew'), (pg_temp.i('g2'), 'group', 'Other crew'),
  (pg_temp.i('dm'), 'direct', null);
insert into public.conversation_members (conversation_id, user_id, role)
values
  (pg_temp.i('g1'), pg_temp.i('ada'), 'owner'),
  (pg_temp.i('g1'), pg_temp.i('bob'), 'member'),
  (pg_temp.i('g1'), pg_temp.i('cat'), 'member'),
  (pg_temp.i('g1'), pg_temp.i('dan'), 'member'),
  (pg_temp.i('g1'), pg_temp.i('fay'), 'member'),
  (pg_temp.i('g2'), pg_temp.i('eve'), 'owner'),
  (pg_temp.i('dm'), pg_temp.i('ada'), 'member'),
  (pg_temp.i('dm'), pg_temp.i('bob'), 'member');
insert into public.friendships (user_low_id, user_high_id)
select least(pg_temp.i('ada'), pg_temp.i(n)), greatest(pg_temp.i('ada'), pg_temp.i(n))
from (values ('bob'),('cat'),('dan'),('fay')) v(n);

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'club', public.create_circle('Hike Club', array[
  pg_temp.i('bob'), pg_temp.i('cat'), pg_temp.i('dan'), pg_temp.i('fay')]);
insert into pg_temp.ids select 'plaza', public.create_circle_channel(pg_temp.i('club'), 'plaza', null, 'text');
insert into pg_temp.ids select 'hall', public.create_circle_channel(pg_temp.i('club'), 'hall', null, 'voice');
select pg_temp.root();

grant execute on all functions in schema pg_temp to public;

-- A chat event made by [who] in group g1 (or [conv]), [mins] minutes from
-- now, with [opts] as event_options. Returns the payload.
create function pg_temp.chat_event(who text, title text, mins integer, opts jsonb default null, conv text default 'g1')
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.act(pg_temp.i(who));
  r := public.create_chat_event(
    pg_temp.i(conv), title, now() + make_interval(mins => mins), null, null, null, null,
    array[15], false, opts);
  perform pg_temp.root();
  return r;
end $$;

-- A circle event made by [who], [mins] minutes from now.
create function pg_temp.circle_event(who text, title text, mins integer, opts jsonb default null)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.act(pg_temp.i(who));
  r := public.create_circle_event(
    pg_temp.i('club'), title, null, 'external', null, 'The trailhead',
    now() + make_interval(mins => mins), null, opts);
  perform pg_temp.root();
  return r;
end $$;

grant execute on all functions in schema pg_temp to public;

-- ===================================== 1. what the rewrites kept
do $$
declare
  def text;
begin
  def := pg_get_functiondef('public.circle_event_profile(uuid, uuid)'::regprocedure);
  perform pg_temp.expect(def like '%visible_profile_bio%' and def !~ E'''bio'',\\s*p\\.bio', 'circle_event_profile still hides a bio the viewer may not see (not rewritten)');
  def := pg_get_functiondef('public.circle_event_payload(public.circle_events)'::regprocedure);
  perform pg_temp.expect(def like '%circle_event_profile%' and def like '%manage_events%', 'circle_event_payload still names the creator through circle_event_profile and keeps can_manage');
  def := pg_get_functiondef('public.guard_items_after_write()'::regprocedure);
  perform pg_temp.expect(def like '%knowledge base%', 'guard_items_after_write keeps what D6 patched (not rewritten)');
  def := pg_get_functiondef('public.guard_item_text(text, uuid)'::regprocedure);
  perform pg_temp.expect(def like '%events2_question_labels%' and def like '%cancelled_at is null%' and def like '%task_items%', 'guard_item_text reads the questions and keeps the rest');
  perform pg_temp.expect(exists (select 1 from pg_trigger where tgname = 'guard_items_circle_events_upd' and tgrelid = 'public.circle_events'::regclass), 'the title and description guard triggers are still there');
  perform pg_temp.expect(exists (select 1 from pg_trigger where tgname = 'guard_items_circle_events_questions' and tgrelid = 'public.circle_events'::regclass), 'and a changed set of questions starts a check');
  def := pg_get_functiondef('public.claim_chat_event_reminder_pushes(integer)'::regprocedure);
  perform pg_temp.expect(def like '%s.language = ''zh''%' and def like '%分钟后开始%', 'the event reminder push is untouched and still worded in Chinese');
  perform pg_temp.expect(to_regprocedure('public.create_chat_event(uuid, text, timestamptz, timestamptz, text, text, text, integer[], boolean)') is null, 'the old create_chat_event signature is gone (no ambiguous call)');
  perform pg_temp.expect(to_regprocedure('public.create_circle_event(uuid, text, text, text, uuid, text, timestamptz, timestamptz)') is null, 'and the old create_circle_event one');
  perform pg_temp.expect(to_regprocedure('public.run_later_dispatch()') is not null and pg_get_functiondef('public.run_later_dispatch()'::regprocedure) not like '%events2%', 'run_later_dispatch is not touched');
  perform pg_temp.expect(not exists (select 1 from information_schema.role_table_grants where table_name in ('event_waitlist','event_check_in_codes','event_check_ins','event_photos','event_notices') and grantee in ('anon','authenticated')), 'the new tables are closed to clients');
end $$;

-- ===================================== 2. the wall clock across daylight saving
do $$
declare
  anchor timestamptz;
  second_start timestamptz;
begin
  -- Auckland: NZDT starts on Sunday 27 September 2026. A Saturday 10:00 stays 10:00.
  anchor := timestamptz '2026-09-19 10:00:00+12';
  perform pg_temp.expect(public.events2_next_start('weekly', anchor, 'Pacific/Auckland', anchor) = timestamptz '2026-09-26 10:00:00+12', 'Auckland weekly: the week before the change');
  perform pg_temp.expect(public.events2_next_start('weekly', anchor, 'Pacific/Auckland', timestamptz '2026-09-26 10:00:00+12') = timestamptz '2026-10-03 10:00:00+13', 'Auckland weekly: across the change it is still 10:00 on the wall (an hour earlier in UTC)');
  -- New York: EST returns on Sunday 1 November 2026.
  anchor := timestamptz '2026-10-24 10:00:00-04';
  perform pg_temp.expect(public.events2_next_start('weekly', anchor, 'America/New_York', timestamptz '2026-10-31 10:00:00-04') = timestamptz '2026-11-07 10:00:00-05', 'New York weekly: 10:00 before and after the clocks go back');
  perform pg_temp.expect(public.events2_next_start('biweekly', anchor, 'America/New_York', anchor) = timestamptz '2026-11-07 10:00:00-05', 'biweekly skips a week');
  perform pg_temp.expect(public.events2_next_start('biweekly', anchor, 'America/New_York', timestamptz '2026-11-07 10:00:00-05') = timestamptz '2026-11-21 10:00:00-05', 'and again');
  -- Monthly on the 31st.
  anchor := timestamptz '2026-01-31 18:00:00+00';
  second_start := public.events2_next_start('monthly', anchor, 'Europe/London', anchor);
  perform pg_temp.expect(second_start = timestamptz '2026-02-28 18:00:00+00', 'monthly on the 31st: February has its last day');
  perform pg_temp.expect(public.events2_next_start('monthly', anchor, 'Europe/London', second_start) = timestamptz '2026-03-31 18:00:00+01', 'and March goes back to the 31st, at 18:00 London time (BST)');
  perform pg_temp.expect(public.events2_next_start('monthly', anchor, 'Europe/London', timestamptz '2026-03-31 18:00:00+01') = timestamptz '2026-04-30 18:00:00+01', 'April has its 30th');
  -- Counted from the anchor, not from the last start: a long gap lands on the pattern.
  perform pg_temp.expect(public.events2_next_start('weekly', timestamptz '2026-09-19 10:00:00+12', 'Pacific/Auckland', timestamptz '2026-12-01 00:00:00+13') = timestamptz '2026-12-05 10:00:00+13', 'after a gap the next start is still on the weekly pattern');
  -- A wall time that does not exist that day is moved on, not lost.
  perform pg_temp.expect(public.events2_next_start('weekly', timestamptz '2026-03-01 02:30:00-05', 'America/New_York', timestamptz '2026-03-01 02:30:00-05') is not null, 'a 02:30 that falls in the spring-forward gap still gets a start');
  perform pg_temp.expect(public.events2_next_start('weekly', timestamptz '2026-03-01 02:30:00-05', 'America/New_York', timestamptz '2026-03-08 06:00:00-04') = timestamptz '2026-03-15 02:30:00-04', 'and the week after is 02:30 again');
  -- Bad input.
  perform pg_temp.expect(public.events2_next_start('daily', anchor, 'UTC', anchor) is null, 'only weekly, biweekly and monthly repeat');
  perform pg_temp.expect(public.events2_next_start('weekly', timestamptz '2026-09-19 10:00:00+00', 'Mars/Olympus', timestamptz '2026-09-19 10:00:00+00') = timestamptz '2026-09-26 10:00:00+00', 'an unknown zone counts as UTC');
end $$;

-- ===================================== 3. making a chat event with options
do $$
declare
  g1 uuid := pg_temp.i('g1');
  e jsonb;
  qs jsonb := '[
    {"id":"meals","label":"Vegetarian?","type":"choice","options":["Yes","No"],"required":true},
    {"id":"guests","label":"How many guests?","type":"number"},
    {"id":"note","label":"Anything we should know?","type":"text"}]'::jsonb;
begin
  e := pg_temp.chat_event('ada', 'Saturday hike', 3 * 24 * 60, jsonb_build_object(
    'recurrence', 'weekly', 'timezone', 'Pacific/Auckland', 'capacity', 2, 'questions', qs,
    'cover_path', g1::text || '/events/cover1.jpg'));
  insert into pg_temp.ids values ('hike', (e ->> 'id')::uuid);
  perform pg_temp.expect(e ->> 'recurrence' = 'weekly' and e ->> 'recurrence_tz' = 'Pacific/Auckland', 'the repeat and the zone are kept');
  perform pg_temp.expect((e ->> 'capacity')::int = 2 and jsonb_array_length(e -> 'questions') = 3, 'capacity and questions are kept');
  perform pg_temp.expect(e ->> 'cover_path' = g1::text || '/events/cover1.jpg', 'and the cover');
  perform pg_temp.expect(e ->> 'series_id' is not null and (select recurrence_anchor from public.chat_events where id = (e ->> 'id')::uuid) = (select starts_at from public.chat_events where id = (e ->> 'id')::uuid), 'a series gets an id and counts from its first start');
  perform pg_temp.expect((e ->> 'going_count')::int = 1 and e ->> 'my_status' = 'going', 'the organiser is Going and takes a seat');
  perform pg_temp.expect((select count(*) from public.messages where conversation_id = g1 and type = 'system' and attachment ->> 'event_id' = e ->> 'id') = 1, 'the event is announced in the chat as before');

  -- An event without options is as before.
  e := pg_temp.chat_event('ada', 'Plain lunch', 3 * 24 * 60);
  insert into pg_temp.ids values ('lunch', (e ->> 'id')::uuid);
  perform pg_temp.expect(e ->> 'recurrence' is null and e ->> 'capacity' is null and e -> 'questions' = '[]'::jsonb and e ->> 'cover_path' is null, 'with no options an event has none');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect((public.create_chat_event(g1, 'Old call', now() + interval '2 days') ->> 'id') is not null, 'an old client''s call (title and start only) still works');
  perform pg_temp.expect((public.update_chat_event(pg_temp.i('lunch'), 'Plain lunch!', now() + interval '3 days') ->> 'title') = 'Plain lunch!', 'and an update without options keeps the event as it was');
  perform pg_temp.root();

  -- Bad options are refused.
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_chat_event(%L, ''x'', now() + interval ''1 day'', null, null, null, null, array[15], false, %L)', g1, '{"recurrence":"daily"}')) = '22023', 'a daily repeat is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.create_chat_event(%L, ''x'', now() + interval ''1 day'', null, null, null, null, array[15], false, %L)', g1, '{"capacity":0}')) = '22023', 'capacity 0 is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.create_chat_event(%L, ''x'', now() + interval ''1 day'', null, null, null, null, array[15], false, %L)', g1, '{"capacity":10001}')) = '22023', 'and 10001');
  perform pg_temp.expect(pg_temp.state(format('select public.create_chat_event(%L, ''x'', now() + interval ''1 day'', null, null, null, null, array[15], false, %L)', g1, jsonb_build_object('questions', (select jsonb_agg(jsonb_build_object('label', 'q' || n)) from generate_series(1, 6) n)))) = '22023', 'six questions are refused');
  perform pg_temp.expect(pg_temp.state(format('select public.create_chat_event(%L, ''x'', now() + interval ''1 day'', null, null, null, null, array[15], false, %L)', g1, '{"questions":[{"label":"Pick","type":"choice","options":["only one"]}]}')) = '22023', 'a choice needs two options');
  perform pg_temp.expect(pg_temp.state(format('select public.create_chat_event(%L, ''x'', now() + interval ''1 day'', null, null, null, null, array[15], false, %L)', g1, '{"questions":[{"label":"","type":"text"}]}')) = '22023', 'a question needs words');
  perform pg_temp.expect(pg_temp.state(format('select public.create_chat_event(%L, ''x'', now() + interval ''1 day'', null, null, null, null, array[15], false, %L)', g1, jsonb_build_object('cover_path', pg_temp.i('g2')::text || '/events/other.jpg'))) = '22023', 'a cover outside the chat''s own folder is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.create_chat_event(%L, ''x'', now() + interval ''1 day'', null, null, null, null, array[15], false, %L)', g1, jsonb_build_object('cover_path', g1::text || '/../x.jpg'))) = '22023', 'and one that climbs out of it');
  perform pg_temp.expect((public.create_chat_event(g1, 'Odd zone', now() + interval '2 days', null, null, null, null, array[15], false, '{"recurrence":"monthly","timezone":"Mars/Olympus"}') ->> 'recurrence_tz') = 'UTC', 'an unknown zone becomes UTC');
  perform pg_temp.root();

  -- Who may make one.
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_chat_event(%L, ''x'', now() + interval ''1 day'')', g1)) = '42501', 'someone outside the chat cannot make an event in it');
  perform pg_temp.root();

  -- K1: a suspended account writes nothing.
  insert into public.app_user_suspensions (user_id, until, reason) values (pg_temp.i('fay'), null, 'test');
  perform pg_temp.act(pg_temp.i('fay'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_chat_event(%L, ''x'', now() + interval ''1 day'')', g1)) = '42501', 'a suspended account cannot make an event');
  perform pg_temp.expect(pg_temp.state(format('select public.rsvp_chat_event(%L, ''going'')', pg_temp.i('lunch'))) = '42501', 'nor answer one');
  perform pg_temp.root();
  delete from public.app_user_suspensions where user_id = pg_temp.i('fay');
end $$;

-- ===================================== 4. questions, capacity and the waiting list
do $$
declare
  hike uuid := pg_temp.i('hike');
  e jsonb;
begin
  -- Required questions have to be answered to say Going.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.rsvp_chat_event(%L, ''going'')', hike)) = '22023', 'Going without the required answer is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.rsvp_chat_event(%L, ''going'', %L)', hike, '{"meals":"Maybe"}')) = '22023', 'an answer that is not one of the choices is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.rsvp_chat_event(%L, ''going'', %L)', hike, '{"meals":"Yes","guests":"lots"}')) = '22023', 'a number question takes a number');
  perform pg_temp.expect(pg_temp.state(format('select public.rsvp_chat_event(%L, ''going'', %L)', hike, jsonb_build_object('meals', 'Yes', 'note', repeat('x', 501)))) = '22023', 'and an answer at most 500 characters');
  perform pg_temp.expect((public.rsvp_chat_event(hike, 'maybe') ->> 'my_status') = 'maybe', 'Maybe needs no answers');
  e := public.rsvp_chat_event(hike, 'going', '{"meals":"Yes","guests":"1","stranger":"dropped"}');
  perform pg_temp.root();
  perform pg_temp.expect(e ->> 'my_status' = 'going' and (e ->> 'going_count')::int = 2, 'bob takes the second seat');
  perform pg_temp.expect((select answers from public.chat_event_rsvps where event_id = hike and user_id = pg_temp.i('bob')) = '{"meals":"Yes","guests":"1"}'::jsonb, 'his answers are kept, and an unknown question is dropped');

  -- The event is full: cat and dan wait, in order.
  perform pg_temp.act(pg_temp.i('cat'));
  e := public.rsvp_chat_event(hike, 'going', '{"meals":"No"}');
  perform pg_temp.root();
  perform pg_temp.expect((e ->> 'my_waitlisted')::boolean and e ->> 'my_status' is null and (e ->> 'going_count')::int = 2 and (e ->> 'waitlist_count')::int = 1, 'cat is put on the waiting list; the seats stay at two');
  perform pg_temp.act(pg_temp.i('dan'));
  e := public.rsvp_chat_event(hike, 'going', '{"meals":"Yes"}');
  perform pg_temp.root();
  perform pg_temp.expect((e ->> 'waitlist_count')::int = 2 and (e ->> 'my_waitlisted')::boolean, 'and dan after her');
  update public.event_waitlist set created_at = now() - interval '1 hour' where chat_event_id = hike and user_id = pg_temp.i('cat');

  -- A seat that frees goes to the first in line, who is told.
  perform pg_temp.act(pg_temp.i('bob'));
  e := public.rsvp_chat_event(hike, 'declined');
  perform pg_temp.root();
  perform pg_temp.expect((select status from public.chat_event_rsvps where event_id = hike and user_id = pg_temp.i('cat')) = 'going', 'cat moves up when bob drops out');
  perform pg_temp.expect((select answers from public.chat_event_rsvps where event_id = hike and user_id = pg_temp.i('cat')) = '{"meals":"No"}'::jsonb, 'with the answers she gave');
  perform pg_temp.expect((select count(*) from public.event_waitlist where chat_event_id = hike) = 1 and exists (select 1 from public.event_waitlist where chat_event_id = hike and user_id = pg_temp.i('dan')), 'dan still waits');
  perform pg_temp.expect((select count(*) from public.event_notices where user_id = pg_temp.i('cat') and chat_event_id = hike and kind = 'waitlist_promoted' and push_claimed_at is null) = 1, 'cat has a push waiting');
  perform pg_temp.expect((select count(*) from public.event_notices where user_id = pg_temp.i('dan')) = 0, 'dan has none yet');

  -- Maybe takes no seat; Going again joins the line.
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.rsvp_chat_event(hike, 'maybe');
  e := public.rsvp_chat_event(hike, 'going', '{"meals":"Yes"}');
  perform pg_temp.root();
  perform pg_temp.expect((e ->> 'my_waitlisted')::boolean and (e ->> 'waitlist_count')::int = 2, 'bob changing his mind joins the line behind dan');

  -- Leaving the line.
  perform pg_temp.act(pg_temp.i('bob'));
  e := public.rsvp_chat_event(hike, null);
  perform pg_temp.root();
  perform pg_temp.expect(not (e ->> 'my_waitlisted')::boolean and (e ->> 'waitlist_count')::int = 1 and e ->> 'my_status' is null, 'clearing the answer takes bob off the line');

  -- More seats let people in.
  perform pg_temp.act(pg_temp.i('ada'));
  e := public.update_chat_event(hike, 'Saturday hike', (select starts_at from public.chat_events where id = hike), null, null, null, null, array[15], '{"capacity":3}');
  perform pg_temp.root();
  perform pg_temp.expect((e ->> 'capacity')::int = 3 and (e ->> 'going_count')::int = 3 and (e ->> 'waitlist_count')::int = 0, 'raising the capacity moves dan up');
  perform pg_temp.expect((select count(*) from public.event_notices where user_id = pg_temp.i('dan') and kind = 'waitlist_promoted') = 1, 'and tells him');
  perform pg_temp.expect(public.events2_promote('chat', hike) = 0, 'moving people up again changes nothing');

  -- An update that leaves the options out keeps them; a null clears one.
  perform pg_temp.act(pg_temp.i('ada'));
  e := public.update_chat_event(hike, 'Saturday hike!', (select starts_at from public.chat_events where id = hike));
  perform pg_temp.expect(e ->> 'recurrence' = 'weekly' and (e ->> 'capacity')::int = 3 and jsonb_array_length(e -> 'questions') = 3, 'an update without options keeps repeat, capacity and questions');
  e := public.update_chat_event(hike, 'Saturday hike!', (select starts_at from public.chat_events where id = hike), null, null, null, null, array[15], '{"capacity":null}');
  perform pg_temp.expect(e ->> 'capacity' is null and e ->> 'recurrence' = 'weekly', 'a null capacity clears it and leaves the rest');
  e := public.update_chat_event(hike, 'Saturday hike!', (select starts_at from public.chat_events where id = hike), null, null, null, null, array[15], '{"capacity":3}');
  perform pg_temp.root();

  -- Who can change it.
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.update_chat_event(%L, ''Mine now'', now() + interval ''5 days'', null, null, null, null, array[15], %L)', hike, '{"capacity":50}')) = '42501', 'a member who did not make it cannot change its options');
  perform pg_temp.root();
end $$;

-- ===================================== 5. checking in
do $$
declare
  g1 uuid := pg_temp.i('g1');
  e jsonb;
  soon uuid;
  far uuid := pg_temp.i('lunch');
  code jsonb;
  old_code text;
  r jsonb;
begin
  e := pg_temp.chat_event('ada', 'Trailhead meetup', 30);
  soon := (e ->> 'id')::uuid;
  insert into pg_temp.ids values ('soon', soon);
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.rsvp_chat_event(soon, 'going');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.rsvp_chat_event(soon, 'maybe');
  perform pg_temp.root();

  -- Only an organiser makes a code.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_event_check_in_code(''chat'', %L)', soon)) = '42501', 'a member who does not run the event cannot make a check-in code');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_event_check_in_code(''chat'', %L)', soon)) = '42501', 'nor can a stranger');
  perform pg_temp.act(pg_temp.i('ada'));
  code := public.create_event_check_in_code('chat', soon);
  perform pg_temp.root();
  perform pg_temp.expect((code ->> 'code') ~ '^[a-z0-9]{12}$' and code ->> 'path' = '/checkin/' || (code ->> 'code'), 'the organiser gets a 12 symbol code and the path for its QR');
  perform pg_temp.expect(not exists (select 1 from public.event_check_in_codes where code_hash = code ->> 'code') and (select count(*) from public.event_check_in_codes where code_hash = encode(sha256(convert_to(code ->> 'code', 'UTF8')), 'hex')) = 1, 'only a hash of the code is stored');
  perform pg_temp.expect((select expires_at from public.event_check_in_codes where chat_event_id = soon and revoked_at is null) > now() + interval '3 hours', 'it works until three hours after the end');

  -- Scanning.
  perform pg_temp.act(pg_temp.i('bob'));
  r := public.check_in_event(code ->> 'code');
  perform pg_temp.expect(r ->> 'event_id' = soon::text and r ->> 'title' = 'Trailhead meetup' and not (r ->> 'already')::boolean and r ->> 'kind' = 'chat', 'bob checks in');
  r := public.check_in_event(code ->> 'code');
  perform pg_temp.expect((r ->> 'already')::boolean, 'a second scan says he is already in');
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(not (public.check_in_event(code ->> 'code') ->> 'already')::boolean, 'dan never answered and still checks in (a walk-in)');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.check_in_event(%L)', code ->> 'code')) = '42501', 'someone outside the chat cannot check in');
  perform pg_temp.expect(pg_temp.state('select public.check_in_event(''aaaaaaaaaaaa'')') = '22023', 'a code that does not exist is refused');
  perform pg_temp.expect(pg_temp.state('select public.check_in_event(''nope'')') = '22023', 'and one that is not a code');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.event_check_ins where chat_event_id = soon) = 2, 'two check-ins are recorded, one each');

  -- A new code cancels the old one.
  old_code := code ->> 'code';
  perform pg_temp.act(pg_temp.i('ada'));
  code := public.create_event_check_in_code('chat', soon);
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.check_in_event(%L)', old_code)) = '22023', 'a new code cancels the one before');
  perform pg_temp.expect(not (public.check_in_event(code ->> 'code') ->> 'already')::boolean, 'and the new one works for cat');
  perform pg_temp.root();
  update public.event_check_in_codes set expires_at = now() - interval '1 minute' where chat_event_id = soon and revoked_at is null;
  perform pg_temp.act(pg_temp.i('fay'));
  perform pg_temp.expect(pg_temp.state(format('select public.check_in_event(%L)', code ->> 'code')) = '22023', 'a code past its end is refused');
  perform pg_temp.root();

  -- Not before the doors open.
  perform pg_temp.act(pg_temp.i('ada'));
  code := public.create_event_check_in_code('chat', far);
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.check_in_event(%L)', code ->> 'code')) = '22023', 'check-in opens two hours before the start, not three days before');
  perform pg_temp.root();

  -- A waiting list does not get in.
  e := pg_temp.chat_event('ada', 'Tiny dinner', 30, '{"capacity":1}');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.rsvp_chat_event((e ->> 'id')::uuid, 'going');
  perform pg_temp.act(pg_temp.i('ada'));
  code := public.create_event_check_in_code('chat', (e ->> 'id')::uuid);
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.check_in_event(%L)', code ->> 'code')) = '22023', 'someone on the waiting list cannot check in');
  perform pg_temp.root();

  -- The organiser's list.
  perform pg_temp.act(pg_temp.i('ada'));
  r := public.list_event_registrations('chat', soon);
  perform pg_temp.expect(jsonb_array_length(r -> 'registrations') = 3 and jsonb_array_length(r -> 'walk_ins') = 1, 'the organiser sees who signed up (ada, bob, cat) and who walked in (dan)');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(r -> 'registrations') x where x ->> 'username' = 'bob_c10' and x ->> 'checked_in_at' is not null and x ->> 'status' = 'going'), 'with bob''s check-in');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(r -> 'registrations') x where x ->> 'username' = 'ada_c10' and x ->> 'checked_in_at' is null), 'and ada not yet ticked');
  perform public.set_event_check_in('chat', soon, pg_temp.i('ada'), true);
  perform public.set_event_check_in('chat', soon, pg_temp.i('bob'), false);
  r := public.list_event_registrations('chat', soon);
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(r -> 'registrations') x where x ->> 'username' = 'ada_c10' and x ->> 'checked_in_at' is not null) and exists (select 1 from jsonb_array_elements(r -> 'registrations') x where x ->> 'username' = 'bob_c10' and x ->> 'checked_in_at' is null), 'an organiser can tick a person on and off');
  perform pg_temp.expect(pg_temp.state(format('select public.set_event_check_in(''chat'', %L, %L, true)', soon, pg_temp.i('eve'))) = '22023', 'but not someone who is not in the chat');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.list_event_registrations(''chat'', %L)', soon)) = '42501', 'a member cannot read the answers and the list');
  perform pg_temp.expect(pg_temp.state(format('select public.set_event_check_in(''chat'', %L, %L, true)', soon, pg_temp.i('bob'))) = '42501', 'or tick people');
  perform pg_temp.root();

  -- The answers on the list are only for organisers; the payload shows only mine.
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(not exists (select 1 from public.list_chat_events(g1, true) ev where ev::text like '%"answers"%'), 'the event payload has no list of answers');
  perform pg_temp.root();
end $$;

-- ===================================== 6. the photos
do $$
declare
  g1 uuid := pg_temp.i('g1');
  soon uuid := pg_temp.i('soon');
  far uuid := pg_temp.i('lunch');
  photo jsonb;
  path1 text := pg_temp.i('g1')::text || '/events/p1.jpg';
begin
  insert into storage.objects (bucket_id, name)
  select 'chat-images', g1::text || '/events/p' || n || '.jpg' from generate_series(1, 25) n;
  insert into storage.objects (bucket_id, name) values ('chat-images', pg_temp.i('g2')::text || '/events/other.jpg');

  perform pg_temp.act(pg_temp.i('bob'));
  photo := public.add_event_photo('chat', soon, path1);
  perform pg_temp.expect(photo ->> 'bucket' = 'chat-images' and (photo ->> 'mine')::boolean, 'someone who signed up adds a picture');
  perform pg_temp.expect(pg_temp.state(format('select public.add_event_photo(''chat'', %L, %L)', soon, path1)) = '22023', 'the same picture twice is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_event_photo(''chat'', %L, %L)', soon, pg_temp.i('g2')::text || '/events/other.jpg')) = '22023', 'a picture from another chat''s folder is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_event_photo(''chat'', %L, %L)', soon, g1::text || '/events/missing.jpg')) = '22023', 'one that was not uploaded is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_event_photo(''chat'', %L, %L)', soon, g1::text || '/../x.jpg')) = '22023', 'and one that climbs out of the folder');
  perform pg_temp.expect(pg_temp.state(format('select public.add_event_photo(''chat'', %L, %L)', far, g1::text || '/events/p2.jpg')) = '22023', 'pictures cannot be added days before the event');
  perform pg_temp.act(pg_temp.i('fay'));
  perform pg_temp.expect(pg_temp.state(format('select public.add_event_photo(''chat'', %L, %L)', soon, g1::text || '/events/p3.jpg')) = '42501', 'someone who neither signed up nor checked in cannot add one');
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect((public.add_event_photo('chat', soon, g1::text || '/events/p4.jpg') ->> 'id') is not null, 'a walk-in who checked in can');
  perform pg_temp.root();

  -- Seen by everyone who can see the event, not by others.
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect((select count(*) from public.list_event_photos('chat', soon)) = 2, 'the members see both pictures');
  perform pg_temp.expect(exists (select 1 from public.list_event_photos('chat', soon) p where p ->> 'uploader_name' = 'Bob' and not (p ->> 'can_delete')::boolean), 'with who added them, and no delete for cat');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select count(*) from public.list_event_photos(''chat'', %L)', soon)) = '42501', 'a stranger sees nothing');
  perform pg_temp.root();

  -- Blocked people's pictures are left out.
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('cat'), pg_temp.i('dan'));
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect((select count(*) from public.list_event_photos('chat', soon)) = 1, 'a picture of somebody cat blocked is left out');
  perform pg_temp.root();
  delete from public.blocks where blocker_id = pg_temp.i('cat');

  -- Deleting.
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.delete_event_photo(%L)', photo ->> 'id')) = '42501', 'cat cannot delete bob''s picture');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(exists (select 1 from public.list_event_photos('chat', soon) p where (p ->> 'can_delete')::boolean and p ->> 'uploader_name' = 'Dan'), 'the organiser may delete any');
  perform public.delete_event_photo((select (p ->> 'id')::uuid from public.list_event_photos('chat', soon) p where p ->> 'uploader_name' = 'Dan'));
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.delete_event_photo((photo ->> 'id')::uuid);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.event_photos where chat_event_id = soon) = 0, 'the organiser and the owner can delete');

  -- A limit per person.
  perform pg_temp.act(pg_temp.i('bob'));
  for n in 1..20 loop
    perform public.add_event_photo('chat', soon, g1::text || '/events/p' || n || '.jpg');
  end loop;
  perform pg_temp.expect(pg_temp.state(format('select public.add_event_photo(''chat'', %L, %L)', soon, g1::text || '/events/p21.jpg')) = '22023', 'twenty pictures per person per event');
  perform pg_temp.root();
end $$;

-- ===================================== 7. a series makes its next occurrence
do $$
declare
  g1 uuid := pg_temp.i('g1');
  hike uuid := pg_temp.i('hike');
  src public.chat_events%rowtype;
  nxt public.chat_events%rowtype;
  made integer;
  expected timestamptz;
  e jsonb;
  third public.chat_events%rowtype;
begin
  select * into src from public.chat_events where id = hike;
  -- Pin it, to see the pin move.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.pin_chat_event(hike, true);
  perform pg_temp.root();

  made := public.events2_spawn_next(src.starts_at - interval '1 minute');
  perform pg_temp.expect((select next_spawned_at from public.chat_events where id = hike) is null and (select count(*) from public.chat_events where series_id = src.series_id) = 1, 'nothing is made before the occurrence starts');

  made := public.events2_spawn_next(src.starts_at + interval '1 minute');
  perform pg_temp.expect(made = 1, 'once it has started the next one is made');
  select * into nxt from public.chat_events where series_id = src.series_id and id <> hike;
  expected := public.events2_next_start('weekly', src.recurrence_anchor, 'Pacific/Auckland', src.starts_at + interval '1 minute');
  perform pg_temp.expect(nxt.starts_at = expected and nxt.starts_at > src.starts_at, 'it is on the weekly pattern in the series'' zone');
  perform pg_temp.expect(
    (nxt.starts_at at time zone 'Pacific/Auckland')::time = (src.starts_at at time zone 'Pacific/Auckland')::time
    and (nxt.starts_at at time zone 'Pacific/Auckland')::date - (src.starts_at at time zone 'Pacific/Auckland')::date = 7,
    'seven days later at the same Auckland wall time');
  perform pg_temp.expect(nxt.title = src.title and nxt.cover_path = src.cover_path and nxt.questions = src.questions and nxt.capacity = src.capacity and nxt.recurrence = 'weekly' and nxt.recurrence_anchor = src.recurrence_anchor and nxt.reminder_leads = src.reminder_leads, 'it carries the title, cover, questions, capacity and repeat');
  perform pg_temp.expect(nxt.pinned_at is not null and (select pinned_at from public.chat_events where id = hike) is null, 'the pin moves to it');
  perform pg_temp.expect((select status from public.chat_event_rsvps where event_id = nxt.id and user_id = nxt.created_by) = 'going' and (select count(*) from public.chat_event_rsvps where event_id = nxt.id) = 1, 'the organiser is Going; everybody else answers again');
  perform pg_temp.expect((select count(*) from public.messages where conversation_id = g1 and type = 'system' and attachment ->> 'event_id' = nxt.id::text) = 1 and nxt.message_id is not null, 'it is announced in the chat');
  perform pg_temp.expect((select next_spawned_at from public.chat_events where id = hike) is not null, 'the first is marked as done');
  perform pg_temp.expect(public.events2_spawn_next(src.starts_at + interval '2 minutes') = 0 and (select count(*) from public.chat_events where series_id = src.series_id) = 2, 'running it again makes nothing more');

  -- The new occurrence is the next link.
  made := public.events2_spawn_next(nxt.starts_at + interval '1 minute');
  perform pg_temp.expect(made = 1, 'and it makes the one after');
  select * into third from public.chat_events where series_id = src.series_id and starts_at > nxt.starts_at;
  perform pg_temp.expect(third.starts_at = public.events2_next_start('weekly', src.recurrence_anchor, 'Pacific/Auckland', nxt.starts_at + interval '1 minute'), 'on the pattern again');

  -- After an outage: the first start after now, not the ones that were missed.
  e := pg_temp.chat_event('ada', 'Monday standup', 60, '{"recurrence":"weekly","timezone":"Europe/London"}');
  select * into src from public.chat_events where id = (e ->> 'id')::uuid;
  made := public.events2_spawn_next(src.starts_at + interval '40 days');
  select * into nxt from public.chat_events where series_id = src.series_id and id <> src.id;
  perform pg_temp.expect(made >= 1 and nxt.starts_at > src.starts_at + interval '40 days' and nxt.starts_at <= src.starts_at + interval '47 days', 'after 40 days of outage the next one is within a week of now');

  -- A series whose organiser left the chat ends.
  e := pg_temp.chat_event('dan', 'Dan''s weekly', 60, '{"recurrence":"weekly","timezone":"UTC"}');
  select * into src from public.chat_events where id = (e ->> 'id')::uuid;
  delete from public.conversation_members where conversation_id = g1 and user_id = pg_temp.i('dan');
  made := public.events2_spawn_next(src.starts_at + interval '1 minute');
  perform pg_temp.expect(made = 0 and (select recurrence from public.chat_events where id = src.id) is null, 'when the organiser has left the chat the series ends');
  insert into public.conversation_members (conversation_id, user_id, role) values (g1, pg_temp.i('dan'), 'member');

  -- A suspended organiser pauses it.
  e := pg_temp.chat_event('cat', 'Cat''s weekly', 60, '{"recurrence":"weekly","timezone":"UTC"}');
  select * into src from public.chat_events where id = (e ->> 'id')::uuid;
  insert into public.app_user_suspensions (user_id, until, reason) values (pg_temp.i('cat'), null, 'test');
  made := public.events2_spawn_next(src.starts_at + interval '1 minute');
  perform pg_temp.expect(made = 0 and (select recurrence from public.chat_events where id = src.id) = 'weekly' and (select next_spawned_at from public.chat_events where id = src.id) is null, 'a suspended organiser pauses the series');
  delete from public.app_user_suspensions where user_id = pg_temp.i('cat');
  made := public.events2_spawn_next(src.starts_at + interval '1 minute');
  perform pg_temp.expect(made = 1, 'and lifting it lets it go on');

  -- Moving the start moves the anchor.
  e := pg_temp.chat_event('ada', 'Moved weekly', 3 * 24 * 60, '{"recurrence":"weekly","timezone":"Asia/Tokyo"}');
  select * into src from public.chat_events where id = (e ->> 'id')::uuid;
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.update_chat_event(src.id, 'Moved weekly', src.starts_at + interval '2 hours');
  perform pg_temp.root();
  perform pg_temp.expect((select recurrence_anchor from public.chat_events where id = src.id) = src.starts_at + interval '2 hours', 'moving the start moves the anchor with it');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.update_chat_event(src.id, 'Moved weekly', src.starts_at + interval '2 hours', null, null, null, null, array[15], '{"recurrence":null}');
  perform pg_temp.root();
  perform pg_temp.expect((select recurrence from public.chat_events where id = src.id) is null and (select recurrence_anchor from public.chat_events where id = src.id) is null and public.events2_spawn_next(src.starts_at + interval '1 day') >= 0, 'turning the repeat off ends it');
end $$;

-- ===================================== 8. cancelling one, or the whole series
do $$
declare
  hike uuid := pg_temp.i('hike');
  series uuid;
  upcoming uuid;
  e jsonb;
begin
  select series_id into series from public.chat_events where id = hike;
  -- The first occurrence has happened by now.
  update public.chat_events set starts_at = now() - interval '1 day' where id = hike;
  select id into upcoming from public.chat_events where series_id = series and cancelled_at is null and starts_at > (select starts_at from public.chat_events where id = hike) order by starts_at limit 1;

  -- One occurrence: the series goes on.
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.cancel_chat_event(%L)', upcoming)) = 'ok', 'cancelling one occurrence works as before (no second argument)');
  perform pg_temp.root();
  perform pg_temp.expect((select cancelled_at from public.chat_events where id = upcoming) is not null and (select recurrence from public.chat_events where id = upcoming) = 'weekly', 'that occurrence is cancelled; the series is not');
  perform pg_temp.expect((select count(*) from public.chat_events where series_id = series and cancelled_at is null and recurrence is not null) >= 1, 'the later ones are still on');

  -- The whole series.
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.cancel_chat_event(%L, true)', upcoming)) = '42501', 'a member cannot end the series');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.cancel_chat_event(upcoming, true);
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.chat_events where series_id = series and recurrence is not null), 'ending the series stops any more from being made');
  perform pg_temp.expect(not exists (select 1 from public.chat_events where series_id = series and starts_at > now() and cancelled_at is null), 'and cancels the ones still ahead');
  perform pg_temp.expect((select cancelled_at from public.chat_events where id = hike) is null, 'the one that already happened is left alone');
end $$;

-- ===================================== 9. the sweep
do $$
declare
  g1 uuid := pg_temp.i('g1');
  e jsonb;
  ev uuid;
  r jsonb;
begin
  e := pg_temp.chat_event('ada', 'Sweep dinner', 3 * 24 * 60, '{"capacity":3}');
  ev := (e ->> 'id')::uuid;
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.rsvp_chat_event(ev, 'going');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.rsvp_chat_event(ev, 'going');
  perform pg_temp.act(pg_temp.i('dan'));
  e := public.rsvp_chat_event(ev, 'going');
  perform pg_temp.root();
  perform pg_temp.expect((e ->> 'my_waitlisted')::boolean, 'dan waits for the sweep dinner');
  -- bob leaves the group: his seat is free, though his answer is still there.
  delete from public.conversation_members where conversation_id = g1 and user_id = pg_temp.i('bob');
  perform pg_temp.expect((select count(*) from public.event_waitlist where chat_event_id = ev) = 1, 'before the sweep dan is still waiting');
  r := public.events2_sweep();
  perform pg_temp.expect((r ->> 'promoted')::int >= 1 and not exists (select 1 from public.event_waitlist where chat_event_id = ev), 'the sweep moves dan into the seat bob left');
  insert into public.conversation_members (conversation_id, user_id, role) values (g1, pg_temp.i('bob'), 'member');

  -- A person who left while waiting is dropped, not promoted.
  e := pg_temp.chat_event('ada', 'Sweep brunch', 3 * 24 * 60, '{"capacity":1}');
  ev := (e ->> 'id')::uuid;
  perform pg_temp.act(pg_temp.i('fay'));
  perform public.rsvp_chat_event(ev, 'going');
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.event_waitlist where chat_event_id = ev and user_id = pg_temp.i('fay')), 'fay waits for the brunch');
  delete from public.conversation_members where conversation_id = g1 and user_id = pg_temp.i('fay');
  update public.chat_event_rsvps set status = 'declined' where event_id = ev and user_id = pg_temp.i('ada');
  r := public.events2_sweep();
  perform pg_temp.expect(not exists (select 1 from public.event_waitlist where chat_event_id = ev) and not exists (select 1 from public.chat_event_rsvps where event_id = ev and user_id = pg_temp.i('fay') and status = 'going'), 'someone who left the chat while waiting is dropped, not given the seat');
  insert into public.conversation_members (conversation_id, user_id, role) values (g1, pg_temp.i('fay'), 'member');
end $$;

-- ===================================== 10. circle events
do $$
declare
  club uuid := pg_temp.i('club');
  e jsonb;
  ev uuid;
  qs jsonb := '[
    {"id":"size","label":"T-shirt size","type":"choice","options":["S","M","L"],"required":true},
    {"id":"diet","label":"Dietary needs","type":"text"}]'::jsonb;
begin
  e := pg_temp.circle_event('ada', 'Club picnic', 2 * 24 * 60, jsonb_build_object(
    'recurrence', 'monthly', 'timezone', 'America/New_York', 'capacity', 1, 'questions', qs,
    'cover_path', club::text || '/events/picnic.jpg'));
  ev := (e ->> 'id')::uuid;
  insert into pg_temp.ids values ('picnic', ev);
  perform pg_temp.expect(e ->> 'recurrence' = 'monthly' and e ->> 'recurrence_tz' = 'America/New_York' and (e ->> 'capacity')::int = 1 and jsonb_array_length(e -> 'questions') = 2 and e ->> 'series_id' is not null, 'a circle event keeps its repeat, zone, capacity and questions');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = club and action = 'event_create' and target_id = ev and changes ->> 'recurrence' = 'monthly') = 1, 'the audit log says it repeats');

  -- Old calls still work.
  perform pg_temp.act(pg_temp.i('ada'));
  e := public.create_circle_event(club, 'Plain meet', null, 'external', null, 'Park', now() + interval '2 days');
  insert into pg_temp.ids values ('plain', (e ->> 'id')::uuid);
  perform pg_temp.expect(e ->> 'recurrence' is null and e -> 'questions' = '[]'::jsonb, 'an event made the old way has no options');
  perform pg_temp.root();

  -- Who can.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_circle_event(%L, ''x'', null, ''external'', null, ''Park'', now() + interval ''2 days'')', club)) = '42501', 'a member without manage_events cannot make an event');
  perform pg_temp.expect(pg_temp.state(format('select public.update_circle_event(%L, ''x'', null, ''external'', null, ''Park'', now() + interval ''2 days'', null, %L)', ev, '{"capacity":9}')) = '42501', 'or change its options');
  perform pg_temp.root();

  -- Signing up with answers.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.register_circle_event(%L)', ev)) = '22023', 'the required question has to be answered');
  perform pg_temp.expect(pg_temp.state(format('select public.toggle_event_interest(%L)', ev)) = '22023', 'and the old toggle cannot skip it');
  perform pg_temp.expect(pg_temp.state(format('select public.register_circle_event(%L, %L)', ev, '{"size":"XXL"}')) = '22023', 'an answer outside the choices is refused');
  e := public.register_circle_event(ev, '{"size":"M","diet":"none"}');
  perform pg_temp.root();
  perform pg_temp.expect((e ->> 'interested_by_me')::boolean and (e ->> 'interested_count')::int = 1 and e -> 'my_answers' = '{"size":"M","diet":"none"}'::jsonb, 'bob signs up and sees his answers');
  perform pg_temp.act(pg_temp.i('cat'));
  e := public.register_circle_event(ev, '{"size":"S"}');
  perform pg_temp.root();
  perform pg_temp.expect(not (e ->> 'interested_by_me')::boolean and (e ->> 'my_waitlisted')::boolean and (e ->> 'waitlist_count')::int = 1 and (e ->> 'interested_count')::int = 1, 'cat is on the waiting list: the one seat is bob''s');
  perform pg_temp.act(pg_temp.i('dan'));
  perform public.register_circle_event(ev, '{"size":"L"}');
  perform pg_temp.root();

  -- The seat moves on.
  perform pg_temp.act(pg_temp.i('bob'));
  e := public.unregister_circle_event(ev);
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.circle_event_rsvps where event_id = ev and user_id = pg_temp.i('cat')) and not exists (select 1 from public.event_waitlist where circle_event_id = ev and user_id = pg_temp.i('cat')), 'when bob leaves, cat takes the seat');
  perform pg_temp.expect((select answers from public.circle_event_rsvps where event_id = ev and user_id = pg_temp.i('cat')) = '{"size":"S"}'::jsonb, 'with her answers');
  perform pg_temp.expect((select count(*) from public.event_notices where circle_event_id = ev and user_id = pg_temp.i('cat')) = 1 and (select count(*) from public.event_notices where circle_event_id = ev and user_id = pg_temp.i('dan')) = 0, 'and a push waits for cat only');

  -- The old toggle: on a plain event it signs up and leaves, as before.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(public.toggle_event_interest(pg_temp.i('plain')) and not public.toggle_event_interest(pg_temp.i('plain')), 'toggle_event_interest still signs up and leaves a plain event');
  perform pg_temp.root();

  -- Changing the capacity: more seats, dan moves up; the audit log says so.
  perform pg_temp.act(pg_temp.i('ada'));
  e := public.update_circle_event(ev, 'Club picnic', null, 'external', null, 'The trailhead', (select starts_at from public.circle_events where id = ev), null, '{"capacity":2}');
  perform pg_temp.root();
  perform pg_temp.expect((e ->> 'capacity')::int = 2 and (e ->> 'interested_count')::int = 2 and (e ->> 'waitlist_count')::int = 0, 'raising the capacity moves dan up');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = club and action = 'event_update' and target_id = ev and changes -> 'capacity' ->> 'new' = '2') = 1, 'the audit log records the new capacity');

  -- The payload keeps naming the creator through the profile function.
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect((select (p -> 'creator' ->> 'username') from public.list_circle_events(club) p where p ->> 'id' = ev::text) = 'ada_c10', 'the payload still names the creator');
  perform pg_temp.root();

  -- The guard reads the questions as well as the description.
  perform pg_temp.expect((select detail from public.guard_item_text('circle_event', ev)) like '%T-shirt size%' and (select detail from public.guard_item_text('circle_event', ev)) like '%Dietary needs%', 'the AI guard is handed the questions');
  perform pg_temp.expect((select title from public.guard_item_text('circle_event', pg_temp.i('plain'))) = 'Plain meet', 'and still the title of every event');
end $$;

-- ===================================== 11. circle events: series, check-in, photos, cancelling
do $$
declare
  club uuid := pg_temp.i('club');
  ev uuid := pg_temp.i('picnic');
  src public.circle_events%rowtype;
  nxt public.circle_events%rowtype;
  code jsonb;
  made integer;
  r jsonb;
begin
  select * into src from public.circle_events where id = ev;
  made := public.events2_spawn_next(src.starts_at + interval '1 minute');
  select * into nxt from public.circle_events where series_id = src.series_id and id <> ev;
  perform pg_temp.expect(made >= 1 and nxt.id is not null, 'the circle event makes its next occurrence');
  perform pg_temp.expect(nxt.starts_at = public.events2_next_start('monthly', src.recurrence_anchor, 'America/New_York', src.starts_at + interval '1 minute') and (nxt.starts_at at time zone 'America/New_York')::time = (src.starts_at at time zone 'America/New_York')::time, 'a month later at the same New York wall time');
  perform pg_temp.expect(nxt.created_by = src.created_by and nxt.capacity = src.capacity and nxt.questions = src.questions and nxt.cover_path = src.cover_path and nxt.channel_id is not distinct from src.channel_id, 'with the same organiser, capacity, questions and cover');
  perform pg_temp.expect(not exists (select 1 from public.circle_event_rsvps where event_id = nxt.id), 'nobody is signed up to it yet');

  -- Check-in in a circle (an event that starts soon).
  perform pg_temp.act(pg_temp.i('ada'));
  r := public.create_circle_event(club, 'Soon meet', null, 'external', null, 'Plaza', now() + interval '20 minutes');
  insert into pg_temp.ids values ('soonc', (r ->> 'id')::uuid);
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.register_circle_event(pg_temp.i('soonc'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_event_check_in_code(''circle'', %L)', pg_temp.i('soonc'))) = '42501', 'a circle member without manage_events cannot make a code');
  perform pg_temp.act(pg_temp.i('ada'));
  code := public.create_event_check_in_code('circle', pg_temp.i('soonc'));
  perform pg_temp.act(pg_temp.i('bob'));
  r := public.check_in_event(code ->> 'code');
  perform pg_temp.expect(r ->> 'kind' = 'circle' and r ->> 'scope_id' = club::text and not (r ->> 'already')::boolean, 'a circle member checks in');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.check_in_event(%L)', code ->> 'code')) = '42501', 'a stranger to the circle cannot');
  perform pg_temp.root();
  insert into storage.objects (bucket_id, name) values ('chat-media', club::text || '/events/c1.jpg');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect((public.add_event_photo('circle', pg_temp.i('soonc'), club::text || '/events/c1.jpg') ->> 'bucket') = 'chat-media', 'a circle event''s picture lives in the circle''s folder of chat-media');
  perform pg_temp.expect(pg_temp.state(format('select public.add_event_photo(''circle'', %L, %L)', pg_temp.i('soonc'), pg_temp.i('g1')::text || '/events/p9.jpg')) = '22023', 'and not in a chat''s');
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(pg_temp.state(format('select public.add_event_photo(''circle'', %L, %L)', pg_temp.i('soonc'), club::text || '/events/c1.jpg')) = '42501', 'someone who did not sign up or check in cannot add one');
  perform pg_temp.root();

  -- Cancelling a series.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.cancel_circle_event(nxt.id, true);
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.circle_events where series_id = src.series_id and recurrence is not null) and (select cancelled_at from public.circle_events where id = nxt.id) is not null, 'ending a circle series cancels what is ahead and stops more');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = club and action = 'event_cancel' and target_id = nxt.id and changes ->> 'series' = 'true') = 1, 'and the audit log says it was the series');

  -- Leaving the circle takes the sign-up and the waiting place along.
  perform pg_temp.act(pg_temp.i('ada'));
  r := public.create_circle_event(club, 'Full house', null, 'external', null, 'Hall', now() + interval '2 days', null, '{"capacity":1}');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.register_circle_event((r ->> 'id')::uuid);
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.register_circle_event((r ->> 'id')::uuid);
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.event_waitlist where circle_event_id = (r ->> 'id')::uuid and user_id = pg_temp.i('cat')), 'cat waits for Full house');
  -- My agenda (D2, and so the calendar feed) lists the seat, not the waiting place.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(exists (select 1 from public.get_my_agenda(now(), now() + interval '10 days') a where a.title = 'Full house'), 'the agenda lists the event bob has a seat in');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(not exists (select 1 from public.get_my_agenda(now(), now() + interval '10 days') a where a.title = 'Full house'), 'and not the one cat only waits for');
  perform pg_temp.root();
  delete from public.circle_members where circle_id = club and user_id = pg_temp.i('cat');
  perform pg_temp.expect(not exists (select 1 from public.event_waitlist where user_id = pg_temp.i('cat') and circle_event_id is not null), 'leaving the circle takes her off the waiting list');
  delete from public.circle_members where circle_id = club and user_id = pg_temp.i('bob');
  perform pg_temp.expect(public.events2_sweep() is not null, 'the sweep runs with seats freed by people who left');
  insert into public.circle_members (circle_id, user_id, role) values (club, pg_temp.i('bob'), 'member'), (club, pg_temp.i('cat'), 'member');
end $$;

-- ===================================== 12. K1: delisted and suspended circles
do $$
declare
  club uuid := pg_temp.i('club');
  r jsonb;
  src public.circle_events%rowtype;
  made integer;
  plain uuid := pg_temp.i('plain');
begin
  perform pg_temp.act(pg_temp.i('ada'));
  r := public.create_circle_event(club, 'K1 series', null, 'external', null, 'Hall', now() + interval '3 days', null, '{"recurrence":"weekly","timezone":"UTC"}');
  perform pg_temp.root();
  select * into src from public.circle_events where id = (r ->> 'id')::uuid;

  -- Delisted: members go on, organisers change nothing.
  perform pg_temp.act(pg_temp.i('root'));
  perform public.admin_disable_circle(club, 'delist', 'test');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_circle_event(%L, ''x'', null, ''external'', null, ''Hall'', now() + interval ''2 days'')', club)) = '42501', 'a delisted circle takes no new event from its organisers');
  perform pg_temp.expect(pg_temp.state(format('select public.update_circle_event(%L, ''x'', null, ''external'', null, ''Hall'', now() + interval ''2 days'')', plain)) = '42501', 'no change');
  perform pg_temp.expect(pg_temp.state(format('select public.cancel_circle_event(%L)', plain)) = '42501', 'and no cancelling');
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(pg_temp.state(format('select public.register_circle_event(%L)', plain)) = 'ok', 'but members can still sign up');
  perform pg_temp.root();
  made := public.events2_spawn_next(src.starts_at + interval '1 minute');
  perform pg_temp.expect((select count(*) from public.circle_events where series_id = src.series_id) = 2, 'and a series goes on');

  -- Suspended: nothing in, signing out still works.
  perform pg_temp.act(pg_temp.i('root'));
  perform public.admin_disable_circle(club, 'suspend', 'test');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.register_circle_event(%L)', pg_temp.i('soonc'))) = '42501', 'a suspended circle takes no sign-up');
  perform pg_temp.expect(pg_temp.state(format('select public.add_event_photo(''circle'', %L, %L)', pg_temp.i('soonc'), pg_temp.i('club')::text || '/events/c1.jpg')) = '42501', 'no pictures');
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(pg_temp.state(format('select public.unregister_circle_event(%L)', plain)) = 'ok', 'but people can still leave an event');
  perform pg_temp.root();
  select * into src from public.circle_events where series_id = src.series_id order by starts_at desc limit 1;
  made := public.events2_spawn_next(src.starts_at + interval '1 minute');
  perform pg_temp.expect((select count(*) from public.circle_events where series_id = src.series_id) = 2, 'a suspended circle''s series waits');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.check_in_event(%L)', 'aaaaaaaaaaaa')) = '22023', 'a bad code is still just a bad code');
  perform pg_temp.root();
end $$;

-- ===================================== 13. the push for a seat
do $$
declare
  g1 uuid := pg_temp.i('g1');
  club uuid := pg_temp.i('club');
  e jsonb;
  ev uuid;
  n integer;
  zh record;
  en record;
begin
  delete from public.event_notices;
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
  values (pg_temp.i('bob'), 'https://push.example.com/bob-zh', repeat('k', 60), repeat('a', 20), 'zh'),
         (pg_temp.i('bob'), 'https://push.example.com/bob-en', repeat('k', 60), repeat('a', 20), 'en'),
         (pg_temp.i('cat'), 'https://push.example.com/cat-en', repeat('k', 60), repeat('a', 20), 'en');

  -- A chat event: bob moves up when ada steps back.
  e := pg_temp.chat_event('ada', 'Pizza night', 2 * 24 * 60, '{"capacity":1}');
  ev := (e ->> 'id')::uuid;
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.rsvp_chat_event(ev, 'going');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.rsvp_chat_event(ev, 'declined');
  perform pg_temp.root();
  select count(*) into n from public.claim_event_notice_pushes();
  perform pg_temp.expect(n = 2, 'bob''s two devices are each pushed once');
  -- The claim marked them; ask again with a fresh notice to look at the words.
  delete from public.event_notices;
  insert into public.event_notices (user_id, kind, chat_event_id) values (pg_temp.i('bob'), 'waitlist_promoted', ev);
  select * into zh from public.claim_event_notice_pushes() c where c.endpoint like '%bob-zh';
  insert into public.event_notices (user_id, kind, chat_event_id) values (pg_temp.i('bob'), 'waitlist_promoted', ev);
  select * into en from public.claim_event_notice_pushes() c where c.endpoint like '%bob-en';
  perform pg_temp.expect(zh.title = '你已报名成功' and zh.body like '%Pizza night%' and zh.body like '%<t:%:f>%' and zh.body like '%候补%', 'a Chinese device is told in Chinese, with the start as a time token');
  perform pg_temp.expect(en.title = 'You got a seat' and en.body like '%Pizza night%' and en.body like '%<t:%:f>%' and en.body like '%waiting list%', 'an English one in English');
  perform pg_temp.expect(zh.conversation_id = g1 and zh.circle_id is null and zh.url = '/#/chats/' || g1::text, 'a chat event''s push carries its conversation (so a locked chat is masked) and opens it');
  perform pg_temp.expect(zh.tag like 'event-seat-%', 'one tag per notice');
  perform pg_temp.expect((select count(*) from public.claim_event_notice_pushes()) = 0, 'a notice is pushed once');

  -- Not for what it would be noise to say.
  delete from public.event_notices;
  insert into public.event_notices (user_id, kind, chat_event_id, created_at)
  values (pg_temp.i('bob'), 'waitlist_promoted', ev, now() - interval '20 minutes');
  perform pg_temp.expect((select count(*) from public.claim_event_notice_pushes()) = 0, 'a notice older than 15 minutes sends nothing');
  perform pg_temp.expect((select push_claimed_at from public.event_notices) is not null, 'and is closed');

  e := pg_temp.chat_event('ada', 'Muted lunch', 2 * 24 * 60, '{"capacity":1}');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.rsvp_chat_event((e ->> 'id')::uuid, 'going');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.rsvp_chat_event((e ->> 'id')::uuid, 'declined');
  perform pg_temp.root();
  update public.conversation_members set muted_until = now() + interval '1 day' where conversation_id = g1 and user_id = pg_temp.i('cat');
  perform pg_temp.expect((select count(*) from public.event_notices where user_id = pg_temp.i('cat')) = 1 and (select count(*) from public.claim_event_notice_pushes()) = 0, 'a chat the person muted gets no push');
  update public.conversation_members set muted_until = null where conversation_id = g1 and user_id = pg_temp.i('cat');

  e := pg_temp.chat_event('ada', 'Cancelled lunch', 2 * 24 * 60, '{"capacity":1}');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.rsvp_chat_event((e ->> 'id')::uuid, 'going');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.rsvp_chat_event((e ->> 'id')::uuid, 'declined');
  perform public.cancel_chat_event((e ->> 'id')::uuid);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.claim_event_notice_pushes()) = 0, 'a cancelled event gets no push');

  -- A title cannot pass for a time token.
  delete from public.event_notices;
  e := pg_temp.chat_event('ada', '<t:1> sneaky', 2 * 24 * 60, '{"capacity":1}');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.rsvp_chat_event((e ->> 'id')::uuid, 'going');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.rsvp_chat_event((e ->> 'id')::uuid, 'declined');
  perform pg_temp.root();
  select * into zh from public.claim_event_notice_pushes() c where c.endpoint like '%bob-zh';
  perform pg_temp.expect(zh.body is not null and zh.body not like '%<t:1>%' and zh.body like '%t:1 sneaky%', 'angle brackets are taken out of the title');

  -- A circle event, while the circle is suspended and after.
  delete from public.event_notices;
  update public.circles set disabled_at = null, disabled_mode = null where id = club;
  e := pg_temp.circle_event('ada', 'Hall party', 2 * 24 * 60, '{"capacity":1}');
  ev := (e ->> 'id')::uuid;
  perform pg_temp.act(pg_temp.i('dan'));
  perform public.register_circle_event(ev);
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.register_circle_event(ev);
  perform pg_temp.act(pg_temp.i('dan'));
  perform public.unregister_circle_event(ev);
  perform pg_temp.root();
  update public.circles set disabled_at = now(), disabled_mode = 'suspend' where id = club;
  perform pg_temp.expect((select count(*) from public.claim_event_notice_pushes()) = 0, 'a suspended circle sends no push');
  update public.circles set disabled_at = null, disabled_mode = null where id = club;
  insert into public.event_notices (user_id, kind, circle_event_id) values (pg_temp.i('cat'), 'waitlist_promoted', ev);
  select * into en from public.claim_event_notice_pushes() c where c.endpoint like '%cat-en';
  perform pg_temp.expect(en.title = 'You got a seat' and en.body like '%Hall party%' and en.url = '/#/circles/' || club::text || '/events?event=' || ev::text and en.circle_id is null, 'a circle event''s push opens the event in the circle');
  insert into public.event_notices (user_id, kind, circle_event_id) values (pg_temp.i('cat'), 'waitlist_promoted', ev);
  insert into public.circle_notification_settings (circle_id, user_id, level) values (club, pg_temp.i('cat'), 'none')
  on conflict (circle_id, user_id) do update set level = 'none';
  perform pg_temp.expect((select count(*) from public.claim_event_notice_pushes()) = 0, 'a circle set to no notifications gets no push');
end $$;

-- ===================================== 14. leaving, deleting an account and the export
do $$
declare
  club uuid := pg_temp.i('club');
  g1 uuid := pg_temp.i('g1');
  e jsonb;
  ev uuid;
  exported jsonb;
  qs jsonb := '[{"id":"q1","label":"Your motto","type":"text"}]'::jsonb;
begin
  e := pg_temp.circle_event('ada', 'Export fest', 2 * 24 * 60, jsonb_build_object('questions', qs, 'capacity', 1));
  ev := (e ->> 'id')::uuid;
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.register_circle_event(ev, '{"q1":"bob-motto"}');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.register_circle_event(ev, '{"q1":"cat-secret"}');
  perform pg_temp.root();

  exported := public.export_my_events2(pg_temp.i('bob'));
  perform pg_temp.expect(exported::text like '%bob-motto%' and exported::text not like '%cat-secret%', 'the export holds my answers and nobody else''s');
  perform pg_temp.expect(jsonb_array_length(exported -> 'signed_up') >= 1 and exported -> 'signed_up' -> 0 ? 'answers', 'my sign-ups come with their answers');
  exported := public.export_my_events2(pg_temp.i('cat'));
  perform pg_temp.expect(jsonb_array_length(exported -> 'waiting') >= 1 and exported::text like '%cat-secret%' and exported::text not like '%bob-motto%', 'and the waiting list I am on, with my answers only');
  exported := public.export_my_events2(pg_temp.i('ada'));
  perform pg_temp.expect(jsonb_array_length(exported -> 'events_made') >= 3 and exported::text like '%Your motto%' and exported::text not like '%bob-motto%' and exported::text not like '%cat-secret%', 'the organiser gets the events made with their settings, never the answers');
  perform pg_temp.expect(exported -> 'events_made' @> '[{"kind":"chat","repeats":"weekly","time_zone":"Europe/London"}]'::jsonb, 'including the repeat and its zone');
  insert into public.event_photos (chat_event_id, user_id, bucket, path)
  values (pg_temp.i('soon'), pg_temp.i('dan'), 'chat-images', g1::text || '/events/dan.jpg');
  exported := public.export_my_events2(pg_temp.i('dan'));
  perform pg_temp.expect(jsonb_array_length(exported -> 'check_ins') >= 1 and jsonb_array_length(exported -> 'photos') = 1, 'check-ins and pictures are exported');
  exported := public.export_my_events2(pg_temp.i('eve'));
  perform pg_temp.expect(exported = jsonb_build_object('signed_up', '[]'::jsonb, 'waiting', '[]'::jsonb, 'check_ins', '[]'::jsonb, 'photos', '[]'::jsonb, 'events_made', '[]'::jsonb), 'a stranger''s export is empty');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.export_my_events2(%L)', pg_temp.i('bob'))) = '42501', 'clients cannot call the export');
  perform pg_temp.root();
  perform pg_temp.expect(has_function_privilege('service_role', 'public.export_my_events2(uuid)', 'execute'), 'the data-export function can');

  -- Deleting an account erases it.
  perform pg_temp.expect(exists (select 1 from public.event_check_ins where user_id = pg_temp.i('dan')) and exists (select 1 from public.event_photos where user_id = pg_temp.i('dan')), 'dan has check-ins and a picture before');
  insert into public.event_waitlist (circle_event_id, circle_id, user_id) values (ev, club, pg_temp.i('dan'));
  insert into public.event_notices (user_id, kind, circle_event_id) values (pg_temp.i('dan'), 'waitlist_promoted', ev);
  insert into public.circle_event_rsvps (event_id, circle_id, user_id, answers)
  select id, circle_id, pg_temp.i('dan'), '{"q1":"dan-motto"}' from public.circle_events where id = ev;
  update public.profiles set deleted_at = now() where id = pg_temp.i('dan');
  perform pg_temp.expect(not exists (select 1 from public.event_check_ins where user_id = pg_temp.i('dan'))
    and not exists (select 1 from public.event_photos where user_id = pg_temp.i('dan'))
    and not exists (select 1 from public.event_waitlist where user_id = pg_temp.i('dan'))
    and not exists (select 1 from public.event_notices where user_id = pg_temp.i('dan')), 'deleting an account erases check-ins, pictures, waiting places and pushes');
  perform pg_temp.expect(not exists (select 1 from public.circle_event_rsvps where user_id = pg_temp.i('dan') and answers <> '{}'::jsonb) and not exists (select 1 from public.chat_event_rsvps where user_id = pg_temp.i('dan') and answers <> '{}'::jsonb), 'and the answers they gave');

  -- The scheduled jobs: the sweep has its own, the dispatcher is not touched.
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform pg_temp.expect(exists (select 1 from cron.job where jobname = 'wecord-events2-sweep' and schedule = '*/5 * * * *'), 'the sweep is a cron job of its own, every 5 minutes');
    perform pg_temp.expect((select command from cron.job where jobname = 'wecord-later-dispatch') not like '%events2%', 'and the every-minute dispatcher does not run it');
  end if;
end $$;

\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'events 2.0: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
