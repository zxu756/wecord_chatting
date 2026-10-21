-- Behaviour checks for member titles and honors (C7: migrations 202610270200
-- to 202610270240). Run by test/supabase/member_honors_test.dart against the
-- local database: it applies the migrations in a transaction, plays people
-- through them, and rolls everything back. Run from the repository root.
--
-- What it walks through: who may give a title (nickname rules: permission and
-- rank, the owner, taking your own off, length and characters, audit log);
-- the push for a title (once, per device language, cleaned names); working
-- honors out from the days people were active (weekly levels, streaks and
-- their milestones, idempotent, repaired weeks); what the page reads and
-- what shows next to a name (own numbers only, boards under five names
-- stay unpublished, small circles get nothing); staying out; the circle
-- switch; a circle an admin delisted or suspended; leaving, deleting an
-- account and the data export.
\set ON_ERROR_STOP on

begin;

do $$ begin perform pg_advisory_xact_lock(20261017); end $$;
set local client_min_messages = warning;

-- Every migration after the local baseline (202610170001), in order.
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
\i supabase/migrations/202610270200_member_honors_schema.sql
\i supabase/migrations/202610270210_member_titles.sql
\i supabase/migrations/202610270220_member_honors_compute.sql
\i supabase/migrations/202610270230_member_honors_rpcs.sql
\i supabase/migrations/202610270240_member_honors_export.sql
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
-- ada owns the circle. low holds ModLow (manage_nicknames), high holds
-- ModHigh above it (manage_nicknames and manage_circle). The rest are
-- ordinary members. eve has an account but is not in the circle. root is the
-- platform admin. 'tiny' is a circle of three; 'camp' has six people and is
-- where streaks are tried.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@honors.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'low'),(3,'high'),(4,'bob'),(5,'cat'),(6,'dan'),(7,'fay'),(8,'gus'),(9,'eve'),(10,'root'),(11,'hal'),(12,'ivy'),(13,'jon'),(14,'kim')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_hn', initcap(name)
from (values (1,'ada'),(2,'low'),(3,'high'),(4,'bob'),(5,'cat'),(6,'dan'),(7,'fay'),(8,'gus'),(9,'eve'),(10,'root'),(11,'hal'),(12,'ivy'),(13,'jon'),(14,'kim')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'low'),(3,'high'),(4,'bob'),(5,'cat'),(6,'dan'),(7,'fay'),(8,'gus'),(9,'eve'),(10,'root'),(11,'hal'),(12,'ivy'),(13,'jon'),(14,'kim')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(pg_temp.i('ada'), pg_temp.i(n)), greatest(pg_temp.i('ada'), pg_temp.i(n))
from (values ('low'),('high'),('bob'),('cat'),('dan'),('fay'),('gus'),('hal'),('ivy'),('jon'),('kim')) v(n);
insert into public.app_admins (user_id, role) values (pg_temp.i('root'), 'owner');

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'club', public.create_circle('Honors Club', array[
  pg_temp.i('low'), pg_temp.i('high'), pg_temp.i('bob'), pg_temp.i('cat'),
  pg_temp.i('dan'), pg_temp.i('fay'), pg_temp.i('gus')]);
insert into pg_temp.ids select 'role_high', public.create_circle_role(pg_temp.i('club'), 'ModHigh', null, 128 + 1048576);
insert into pg_temp.ids select 'role_low', public.create_circle_role(pg_temp.i('club'), 'ModLow', null, 128);
select public.set_member_roles(pg_temp.i('club'), pg_temp.i('low'), array[pg_temp.i('role_low')]);
select public.set_member_roles(pg_temp.i('club'), pg_temp.i('high'), array[pg_temp.i('role_high')]);
insert into pg_temp.ids select 'tiny', public.create_circle('Tiny Club', array[pg_temp.i('bob'), pg_temp.i('cat')]);
insert into pg_temp.ids select 'camp', public.create_circle('Camp', array[
  pg_temp.i('hal'), pg_temp.i('ivy'), pg_temp.i('jon'), pg_temp.i('kim'), pg_temp.i('gus')]);
select pg_temp.root();

-- ===================================== 1. the shape of it
do $$
declare
  club uuid := pg_temp.i('club');
begin
  perform pg_temp.expect((select honors_enabled from public.circles where id = club), 'honors are on by default');
  perform pg_temp.expect((select count(*) from public.circle_members where circle_id = club and title is not null) = 0, 'and nobody has a title');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state('select count(*) from public.circle_member_honors') = '42501', 'honors are not a table clients can read');
  perform pg_temp.expect(pg_temp.state('select count(*) from public.circle_member_honor_stats') = '42501', 'nor the streaks');
  perform pg_temp.expect(pg_temp.state('select count(*) from public.circle_honor_prefs') = '42501', 'nor who stays out');
  perform pg_temp.expect(pg_temp.state('select count(*) from public.circle_title_notices') = '42501', 'nor the waiting pushes');
  perform pg_temp.expect(pg_temp.state(format('update public.circle_members set title = ''Boss'' where circle_id = %L and user_id = %L', club, pg_temp.i('bob'))) = 'ok'
    and (select title from public.circle_members where circle_id = club and user_id = pg_temp.i('bob')) is null, 'a member cannot write a title with an update (no policy lets the row change)');
  perform pg_temp.root();
end $$;

-- ===================================== 2. giving a title
do $$
declare
  club uuid := pg_temp.i('club');
  ada uuid := pg_temp.i('ada');
  low uuid := pg_temp.i('low');
  high uuid := pg_temp.i('high');
  bob uuid := pg_temp.i('bob');
  cat uuid := pg_temp.i('cat');
  audits integer;
  r text;
begin
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, ''Boss'')', club, cat)) = '42501', 'a member cannot give a title');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, ''Boss'')', club, bob)) = '42501', 'nor to themselves');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, ''Boss'')', club, bob)) = '42501', 'an outsider cannot');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, ''Boss'')', club, bob)) = '42501', 'nobody signed in cannot');

  perform pg_temp.act(low);
  r := public.set_circle_member_title(club, bob, '  Photo   edit ');
  perform pg_temp.expect(r = 'Photo edit', 'a moderator gives a title, trimmed and with single spaces');
  perform pg_temp.expect((select title from public.circle_members where circle_id = club and user_id = bob) = 'Photo edit', 'it is stored');
  perform pg_temp.expect((select title_set_at from public.circle_members where circle_id = club and user_id = bob) is not null, 'with the time');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, ''Boss'')', club, high)) = '42501', 'not to somebody ranked above');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, ''Boss'')', club, ada)) = '42501', 'nor to the owner');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, ''Helper'')', club, low)) = 'ok', 'but to themselves');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, ''12345678901'')', club, cat)) = '22023', 'eleven characters is too long');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, ''1234567890'')', club, cat)) = 'ok', 'ten is fine');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, ''头衔头衔头衔头衔头衔'')', club, cat)) = 'ok', 'ten Chinese characters are fine');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, ''<b>hi</b>'')', club, cat)) = '22023', 'angle brackets are refused');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, %L)', club, cat, 'Mod' || chr(8238) || 'x')) = '22023', 'so are text direction overrides');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, %L)', club, cat, 'a' || chr(8203) || 'b')) = '22023', 'and invisible spaces');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, ''Boss'')', club, pg_temp.i('eve'))) = 'P0002', 'somebody who is not a member is not found');
  perform pg_temp.expect(public.set_circle_member_title(club, cat, null) is null, 'a blank clears it');
  perform pg_temp.expect((select title from public.circle_members where circle_id = club and user_id = cat) is null, 'cleared');

  perform pg_temp.act(ada);
  perform pg_temp.expect(public.set_circle_member_title(club, ada, 'Founder') = 'Founder', 'the owner gives themselves one');
  perform pg_temp.expect(public.set_circle_member_title(club, high, 'Head mod') = 'Head mod', 'and the one below');
  perform pg_temp.act(high);
  perform pg_temp.expect(public.set_circle_member_title(club, low, 'Mod') = 'Mod', 'a higher moderator retitles a lower one');
  perform pg_temp.act(bob);
  perform pg_temp.expect(public.set_circle_member_title(club, bob, '') is null, 'anyone can take their own title off');
  perform pg_temp.expect((select title from public.circle_members where circle_id = club and user_id = bob) is null, 'it is gone');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, null)', club, low)) = '42501', 'but not somebody else''s');

  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = club and action = 'member_title_update') >= 6, 'every change is in the audit log');
  perform pg_temp.expect((select changes -> 'title' ->> 'new' from public.circle_audit_log where circle_id = club and action = 'member_title_update' and target_id = ada order by created_at desc limit 1) = 'Founder', 'with the new title');
  perform pg_temp.root();
  audits := (select count(*) from public.circle_audit_log where circle_id = club and action = 'member_title_update');
  perform pg_temp.act(low);
  perform public.set_circle_member_title(club, low, 'Mod');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = club and action = 'member_title_update') = audits, 'saving the same title again writes nothing');
end $$;

-- ===================================== 3. the push for a title
do $$
declare
  club uuid := pg_temp.i('club');
  low uuid := pg_temp.i('low');
  bob uuid := pg_temp.i('bob');
  cat uuid := pg_temp.i('cat');
  rows integer;
begin
  perform pg_temp.root();
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
  values (bob, 'https://push.example.com/bob-zh', repeat('k', 60), repeat('a', 20), 'zh'),
         (bob, 'https://push.example.com/bob-en', repeat('k', 60), repeat('a', 20), 'en'),
         (pg_temp.i('ada'), 'https://push.example.com/ada', repeat('k', 60), repeat('a', 20), 'en');
  delete from public.circle_title_notices;

  perform pg_temp.act(low);
  perform public.set_circle_member_title(club, bob, 'Editor');
  perform public.set_circle_member_title(club, low, 'Mod');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_title_notices where user_id = bob and push_claimed_at is null) = 1, 'a title given to somebody waits for one push');
  perform pg_temp.expect((select count(*) from public.circle_title_notices where user_id = low) = 0, 'a title you give yourself does not');
  perform pg_temp.act(low);
  perform public.set_circle_member_title(club, bob, 'Chief ed');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_title_notices where user_id = bob and push_claimed_at is null) = 1, 'a second title before the push replaces the first');

  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.state('select * from public.claim_circle_title_pushes()') = '42501', 'only the service role claims pushes');
  perform pg_temp.root();
  create temp table claimed_titles on commit drop as select * from public.claim_circle_title_pushes();
  perform pg_temp.expect((select count(*) from claimed_titles) = 2, 'one row for each device of the person');
  perform pg_temp.expect((select count(*) from claimed_titles where title = '你有新头衔了' and body like '%Honors Club%' and body like '%Chief ed%') = 1, 'the Chinese device gets Chinese words');
  perform pg_temp.expect((select count(*) from claimed_titles where title = 'You have a new title' and body like '%Chief ed%') = 1, 'the English one gets English');
  perform pg_temp.expect((select count(distinct url) from claimed_titles) = 1 and (select url from claimed_titles limit 1) = '/#/circles/' || club::text, 'a tap opens the circle');
  perform pg_temp.expect((select count(*) from public.claim_circle_title_pushes()) = 0, 'a push is claimed once');

  -- One that waited too long is closed without a push.
  insert into public.circle_title_notices (circle_id, user_id, title, created_at)
  values (club, bob, 'Old', now() - interval '20 minutes');
  perform pg_temp.expect((select count(*) from public.claim_circle_title_pushes()) = 0, 'an old one is dropped, not sent late');
  perform pg_temp.expect((select count(*) from public.circle_title_notices where push_claimed_at is null) = 0, 'and closed');

  -- Angle brackets in a circle name cannot be pushed along.
  update public.circles set name = 'Club <b>' where id = club;
  perform pg_temp.act(low);
  perform public.set_circle_member_title(club, cat, 'Scout');
  perform pg_temp.root();
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
  values (cat, 'https://push.example.com/cat', repeat('k', 60), repeat('a', 20), 'en');
  create temp table claimed_titles2 on commit drop as select * from public.claim_circle_title_pushes();
  perform pg_temp.expect((select count(*) from claimed_titles2 where body not like '%<%' and body like '%Club b%') = 1, 'a circle name is cleaned of angle brackets');
  update public.circles set name = 'Honors Club' where id = club;
  perform pg_temp.act(low);
  perform public.set_circle_member_title(club, cat, null);
  perform pg_temp.root();
end $$;

-- ===================================== 4. the numbers honors come from
-- Last week (Monday to Sunday, UTC): ada 7 days, bob 5, cat 6, dan 3,
-- fay 4, low 3, gus 2. Six people earn a level, so the board is published.
select pg_temp.root();
insert into public.circle_member_daily (circle_id, day, user_id)
select pg_temp.i('club'), public.honors_week_start() + d, pg_temp.i(u)
from (values ('ada', 7), ('bob', 5), ('cat', 6), ('dan', 3), ('fay', 4), ('low', 3), ('gus', 2)) v(u, n),
     generate_series(0, 6) d
where d < n;
-- Camp: hal 31 days to yesterday, ivy 10, jon 3 then a gap then one more,
-- kim 7 days that ended 3 days ago, gus only the day before yesterday.
insert into public.circle_member_daily (circle_id, day, user_id)
select pg_temp.i('camp'), public.insights_today() - d, pg_temp.i('hal') from generate_series(1, 31) d;
insert into public.circle_member_daily (circle_id, day, user_id)
select pg_temp.i('camp'), public.insights_today() - d, pg_temp.i('ivy') from generate_series(1, 10) d;
insert into public.circle_member_daily (circle_id, day, user_id)
select pg_temp.i('camp'), public.insights_today() - d, pg_temp.i('jon') from unnest(array[1, 2, 3, 5]) d;
insert into public.circle_member_daily (circle_id, day, user_id)
select pg_temp.i('camp'), public.insights_today() - d, pg_temp.i('kim') from generate_series(4, 10) d;
-- Three people in a circle of three also have days.
insert into public.circle_member_daily (circle_id, day, user_id)
select pg_temp.i('tiny'), public.honors_week_start() + d, pg_temp.i(u)
from (values ('bob'), ('cat')) v(u), generate_series(0, 6) d;

do $$
declare
  club uuid := pg_temp.i('club');
  camp uuid := pg_temp.i('camp');
  n integer;
  before_rows integer;
  after_rows integer;
begin
  perform pg_temp.root();
  n := public.run_circle_honors();
  perform pg_temp.expect(n >= 12, 'the run counts the people who take part (' || n || ')');
  perform pg_temp.expect((select level from public.circle_member_honors where circle_id = club and user_id = pg_temp.i('ada') and kind = 'weekly' and period_start = public.honors_week_start()) = 3, '7 active days is level 3');
  perform pg_temp.expect((select level from public.circle_member_honors where circle_id = club and user_id = pg_temp.i('bob') and kind = 'weekly') = 2, '5 days is level 2');
  perform pg_temp.expect((select level from public.circle_member_honors where circle_id = club and user_id = pg_temp.i('cat') and kind = 'weekly') = 2, '6 days is level 2');
  perform pg_temp.expect((select level from public.circle_member_honors where circle_id = club and user_id = pg_temp.i('dan') and kind = 'weekly') = 1, '3 days is level 1');
  perform pg_temp.expect((select level from public.circle_member_honors where circle_id = club and user_id = pg_temp.i('fay') and kind = 'weekly') = 1, '4 days is level 1');
  perform pg_temp.expect((select count(*) from public.circle_member_honors where circle_id = club and user_id = pg_temp.i('gus') and kind = 'weekly') = 0, '2 days is none');
  perform pg_temp.expect((select count(*) from public.circle_member_honors where circle_id = club and kind = 'weekly') = 6, 'six people on last week''s board');
  perform pg_temp.expect((select current_streak from public.circle_member_honor_stats where circle_id = camp and user_id = pg_temp.i('hal')) = 31, 'a run of 31 days ending yesterday is a streak of 31');
  perform pg_temp.expect((select current_streak from public.circle_member_honor_stats where circle_id = camp and user_id = pg_temp.i('ivy')) = 10, '10 days is 10');
  perform pg_temp.expect((select current_streak from public.circle_member_honor_stats where circle_id = camp and user_id = pg_temp.i('jon')) = 3, 'a gap ends the run: 3');
  perform pg_temp.expect((select best_streak from public.circle_member_honor_stats where circle_id = camp and user_id = pg_temp.i('jon')) = 3, 'and the best is the longest run');
  perform pg_temp.expect((select current_streak from public.circle_member_honor_stats where circle_id = camp and user_id = pg_temp.i('kim')) = 0, 'a run that ended 3 days ago is not a streak any more');
  perform pg_temp.expect((select best_streak from public.circle_member_honor_stats where circle_id = camp and user_id = pg_temp.i('kim')) = 7, 'but it is the best');
  perform pg_temp.expect((select string_agg(level::text, ',' order by level) from public.circle_member_honors where circle_id = camp and user_id = pg_temp.i('hal') and kind = 'streak') = '7,30', 'milestones 7 and 30 for 31 days');
  perform pg_temp.expect((select string_agg(level::text, ',' order by level) from public.circle_member_honors where circle_id = camp and user_id = pg_temp.i('ivy') and kind = 'streak') = '7', 'only 7 for 10');
  perform pg_temp.expect((select count(*) from public.circle_member_honors where circle_id = camp and user_id = pg_temp.i('jon') and kind = 'streak') = 0, 'none for 3');
  perform pg_temp.expect((select period_start from public.circle_member_honors where circle_id = camp and user_id = pg_temp.i('hal') and kind = 'streak' and level = 30) = public.insights_today() - 31 + 29, 'a milestone is dated the day it was reached');
  perform pg_temp.expect((select count(*) from public.circle_member_honors where circle_id = pg_temp.i('tiny')) = 0 and (select count(*) from public.circle_member_honor_stats where circle_id = pg_temp.i('tiny')) = 0, 'a circle of three gets no honors');

  select count(*) into before_rows from public.circle_member_honors;
  perform public.run_circle_honors();
  select count(*) into after_rows from public.circle_member_honors;
  perform pg_temp.expect(before_rows = after_rows, 'running it again changes nothing');
  perform pg_temp.expect((select count(*) from public.circle_member_honors where circle_id = camp and user_id = pg_temp.i('hal') and kind = 'streak') = 2, 'a milestone is awarded once');

  -- Days a person was seen later change the level; a person who dropped
  -- below the line loses it.
  delete from public.circle_member_daily where circle_id = club and user_id = pg_temp.i('dan') and day = public.honors_week_start();
  perform public.run_circle_honors();
  perform pg_temp.expect((select count(*) from public.circle_member_honors where circle_id = club and user_id = pg_temp.i('dan') and kind = 'weekly') = 0, 'a week repaired with fewer days drops the level');
  insert into public.circle_member_daily values (club, public.honors_week_start(), pg_temp.i('dan'));
  perform public.run_circle_honors();
  perform pg_temp.expect((select count(*) from public.circle_member_honors where circle_id = club and user_id = pg_temp.i('dan') and kind = 'weekly') = 1, 'and gets it back');
end $$;

-- ===================================== 5. what the page reads
do $$
declare
  club uuid := pg_temp.i('club');
  camp uuid := pg_temp.i('camp');
  g jsonb;
  b jsonb;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  g := public.get_circle_honors(club);
  perform pg_temp.expect((g ->> 'enabled')::boolean and (g ->> 'eligible')::boolean and (g ->> 'participating')::boolean, 'enabled, eligible and taking part');
  perform pg_temp.expect(not (g ->> 'can_manage')::boolean, 'a member cannot manage');
  perform pg_temp.expect((g -> 'mine' ->> 'week_days') is not null, 'my own numbers are there');
  perform pg_temp.expect(g -> 'mine' -> 'honors' -> 0 ->> 'kind' = 'weekly' and (g -> 'mine' -> 'honors' -> 0 ->> 'level')::int = 2, 'with the level I earned');
  perform pg_temp.expect((g -> 'board' ->> 'published')::boolean, 'the board is published');
  perform pg_temp.expect(jsonb_array_length(g -> 'board' -> 'entries') = 6, 'with six people');
  perform pg_temp.expect(not (g::text like '%week_days%' and (select count(*) from jsonb_array_elements(g -> 'board' -> 'entries') e where e ? 'days' or e ? 'streak' or e ? 'count') > 0), 'a board entry has no day count');
  perform pg_temp.expect(g -> 'board' -> 'entries' -> 0 ->> 'user_id' = pg_temp.i('ada')::text, 'level 3 first');
  perform pg_temp.expect(not (g -> 'board' -> 'entries' @> jsonb_build_array(jsonb_build_object('user_id', pg_temp.i('gus'), 'level', 1))), 'and nobody below the line');

  perform pg_temp.act(pg_temp.i('hal'));
  g := public.get_circle_honors(camp);
  perform pg_temp.expect((g -> 'mine' ->> 'streak')::int = 31 and (g -> 'mine' ->> 'best_streak')::int = 31, 'I see my own streak');
  perform pg_temp.expect(not (g -> 'board' ->> 'published')::boolean and jsonb_array_length(g -> 'board' -> 'entries') = 0, 'camp has 6 people but fewer than 5 on the board: nothing is published');
  perform pg_temp.expect(g::text not like '%' || pg_temp.i('ivy')::text || '%', 'and nobody else''s streak is in the answer');

  perform pg_temp.act(pg_temp.i('bob'));
  g := public.get_circle_honors(pg_temp.i('tiny'));
  perform pg_temp.expect(not (g ->> 'eligible')::boolean and g -> 'mine' = 'null'::jsonb and g -> 'board' = 'null'::jsonb, 'a circle of three has none of it');

  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.get_circle_honors(%L)', club)) = '42501', 'an outsider is refused');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select public.get_circle_honors(%L)', club)) = '42501', 'and nobody signed in');

  perform pg_temp.act(pg_temp.i('high'));
  perform pg_temp.expect((public.get_circle_honors(club) ->> 'can_manage')::boolean, 'a manager can manage');
end $$;

-- ===================================== 6. what shows next to a name
do $$
declare
  club uuid := pg_temp.i('club');
  camp uuid := pg_temp.i('camp');
begin
  perform pg_temp.act(pg_temp.i('gus'));
  perform pg_temp.expect((select title from public.list_circle_member_flair(club) where user_id = pg_temp.i('ada')) = 'Founder', 'a title shows to every member');
  perform pg_temp.expect((select weekly_level from public.list_circle_member_flair(club) where user_id = pg_temp.i('ada')) = 3, 'with last week''s level');
  perform pg_temp.expect((select count(*) from public.list_circle_member_flair(club) where user_id = pg_temp.i('gus')) = 0, 'someone with neither is not listed');
  perform pg_temp.expect((select streak_level from public.list_circle_member_flair(camp) where user_id = pg_temp.i('hal')) = 30, 'the highest streak milestone they are on');
  perform pg_temp.expect((select streak_level from public.list_circle_member_flair(camp) where user_id = pg_temp.i('ivy')) = 7, 'a small one');
  perform pg_temp.expect((select count(*) from public.list_circle_member_flair(camp) where user_id in (pg_temp.i('kim'), pg_temp.i('jon'))) = 0, 'a broken streak shows nothing');
  perform pg_temp.expect((select weekly_level from public.list_circle_member_flair(camp) where user_id = pg_temp.i('hal')) is null, 'camp''s board is not published, so no weekly level is shown');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select * from public.list_circle_member_flair(%L)', club)) = '42501', 'an outsider cannot ask');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select * from public.list_circle_member_flair(%L)', club)) = '42501', 'nor nobody');
end $$;

-- ===================================== 7. staying out
do $$
declare
  club uuid := pg_temp.i('club');
  bob uuid := pg_temp.i('bob');
  g jsonb;
begin
  perform pg_temp.act(bob);
  perform pg_temp.expect(not public.set_my_honors_participation(club, false), 'a member stays out');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_member_honors where circle_id = club and user_id = bob) = 0, 'their honors are deleted');
  perform pg_temp.expect((select count(*) from public.circle_honor_prefs where circle_id = club and user_id = bob) = 1, 'and the choice is kept');
  perform public.run_circle_honors();
  perform pg_temp.expect((select count(*) from public.circle_member_honors where circle_id = club and user_id = bob) = 0, 'the nightly run does not bring them back');
  perform pg_temp.expect((select count(*) from public.circle_member_honor_stats where circle_id = club and user_id = bob) = 0, 'nor a streak');
  perform pg_temp.act(pg_temp.i('cat'));
  g := public.get_circle_honors(club);
  perform pg_temp.expect(jsonb_array_length(g -> 'board' -> 'entries') = 5, 'they are not on the board');
  perform pg_temp.expect((g -> 'board' ->> 'published')::boolean, 'five are still enough');
  perform pg_temp.expect((select count(*) from public.list_circle_member_flair(club) where user_id = bob and weekly_level is not null) = 0, 'nor next to their name');
  perform pg_temp.act(bob);
  g := public.get_circle_honors(club);
  perform pg_temp.expect(not (g ->> 'participating')::boolean and g -> 'mine' = 'null'::jsonb, 'they see that they are out, and no numbers');

  -- A fifth person staying out leaves four: the board says nothing.
  perform pg_temp.act(pg_temp.i('dan'));
  perform public.set_my_honors_participation(club, false);
  perform pg_temp.act(pg_temp.i('cat'));
  g := public.get_circle_honors(club);
  perform pg_temp.expect(not (g -> 'board' ->> 'published')::boolean and jsonb_array_length(g -> 'board' -> 'entries') = 0, 'with fewer than five names the board is not published');
  perform pg_temp.expect((select count(*) from public.list_circle_member_flair(club) where weekly_level is not null) = 0, 'and no weekly level shows next to any name');
  perform pg_temp.expect((g -> 'mine' -> 'honors' -> 0 ->> 'level')::int = 2, 'though cat still sees their own');

  perform pg_temp.act(bob);
  perform pg_temp.expect(public.set_my_honors_participation(club, true), 'coming back');
  perform pg_temp.act(pg_temp.i('dan'));
  perform public.set_my_honors_participation(club, true);
  perform pg_temp.root();
  perform public.run_circle_honors();
  perform pg_temp.expect((select level from public.circle_member_honors where circle_id = club and user_id = bob and kind = 'weekly') = 2, 'the next run works them out again');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_my_honors_participation(%L, false)', club)) = '42501', 'an outsider cannot choose');
  perform pg_temp.root();
end $$;

-- ===================================== 8. turning honors off for the circle
do $$
declare
  club uuid := pg_temp.i('club');
  g jsonb;
begin
  perform pg_temp.act(pg_temp.i('low'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_honors_enabled(%L, false)', club)) = '42501', 'nicknames are not enough to switch honors off');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_honors_enabled(%L, false)', club)) = '42501', 'nor being a member');
  perform pg_temp.act(pg_temp.i('high'));
  perform pg_temp.expect(not public.set_circle_honors_enabled(club, false), 'a manager switches them off');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_member_honors where circle_id = club) = 0, 'what was worked out is deleted');
  perform pg_temp.expect((select count(*) from public.circle_member_honor_stats where circle_id = club) = 0, 'with the streaks');
  perform public.run_circle_honors();
  perform pg_temp.expect((select count(*) from public.circle_member_honors where circle_id = club) = 0, 'the nightly run leaves the circle alone');
  perform pg_temp.act(pg_temp.i('cat'));
  g := public.get_circle_honors(club);
  perform pg_temp.expect(not (g ->> 'enabled')::boolean and g -> 'mine' = 'null'::jsonb and g -> 'board' = 'null'::jsonb, 'the page says honors are off');
  perform pg_temp.expect((select count(*) from public.list_circle_member_flair(club) where weekly_level is not null or streak_level is not null) = 0, 'no honor next to a name');
  perform pg_temp.expect((select title from public.list_circle_member_flair(club) where user_id = pg_temp.i('ada')) = 'Founder', 'but titles stay');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = club and action = 'honors_update') = 1, 'the switch is in the audit log');
  perform pg_temp.act(pg_temp.i('high'));
  perform pg_temp.expect(public.set_circle_honors_enabled(club, true), 'and back on');
  perform pg_temp.root();
  perform public.run_circle_honors();
  perform pg_temp.expect((select count(*) from public.circle_member_honors where circle_id = club and kind = 'weekly') = 6, 'the next run brings the week back');
end $$;

-- ===================================== 9. a circle an admin took down
do $$
declare
  club uuid := pg_temp.i('club');
  camp uuid := pg_temp.i('camp');
begin
  perform pg_temp.act(pg_temp.i('root'));
  perform public.admin_disable_circle(club, 'delist', 'x');
  perform pg_temp.act(pg_temp.i('high'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, ''Late'')', club, pg_temp.i('cat'))) = '42501', 'a delisted circle takes no new title');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_honors_enabled(%L, false)', club)) = '42501', 'nor the honors switch');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_my_honors_participation(%L, false)', club)) = '42501', 'nor a choice');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, null)', club, pg_temp.i('low'))) = '42501', 'nor a title taken off');
  perform pg_temp.root();
  perform pg_temp.expect(not public.honors_circle_active(club), 'no honors are worked out for it');
  perform public.run_circle_honors();
  perform pg_temp.expect((select count(*) from public.circle_member_honor_stats where circle_id = club) = 0, 'the nightly run skips it');

  perform pg_temp.act(pg_temp.i('root'));
  perform public.admin_enable_circle(club, 'x');
  perform public.admin_disable_circle(club, 'suspend', 'x');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(public.get_circle_honors(club) is null, 'a suspended circle gives no honors');
  perform pg_temp.expect((select count(*) from public.list_circle_member_flair(club)) = 0, 'and no titles');
  perform pg_temp.act(pg_temp.i('high'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, ''Late'')', club, pg_temp.i('cat'))) = '42501', 'it takes no title either');
  perform pg_temp.act(pg_temp.i('root'));
  perform public.admin_enable_circle(club, 'x');
  perform pg_temp.act(pg_temp.i('high'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_member_title(%L, %L, ''Back'')', club, pg_temp.i('cat'))) = 'ok', 'once it is back it does');
  perform pg_temp.root();
end $$;

-- ===================================== 10. leaving, deleting an account, the export
do $$
declare
  club uuid := pg_temp.i('club');
  cat uuid := pg_temp.i('cat');
  fay uuid := pg_temp.i('fay');
  x jsonb;
begin
  perform pg_temp.root();
  perform public.run_circle_honors();
  x := public.export_my_honors(pg_temp.i('ada'));
  perform pg_temp.expect(x::text like '%Founder%' and x::text like '%Honors Club%', 'the export has my titles with their circle');
  perform pg_temp.expect(jsonb_array_length(x -> 'honors') >= 1 and jsonb_array_length(x -> 'streaks') >= 1, 'my honors and streaks');
  perform pg_temp.expect(x::text not like '%' || pg_temp.i('bob')::text || '%' and x::text not like '%Back%', 'and nobody else''s');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.set_my_honors_participation(club, false);
  perform pg_temp.root();
  x := public.export_my_honors(pg_temp.i('bob'));
  perform pg_temp.expect(jsonb_array_length(x -> 'opted_out') = 1, 'the circles I stay out of');
  perform pg_temp.act(cat);
  perform pg_temp.expect(pg_temp.state(format('select public.export_my_honors(%L)', cat)) = '42501', 'only the service role asks for it');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select public.export_my_honors(%L)', cat)) = '42501', 'not even the signed out');

  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_member_honors where circle_id = club and user_id = fay) = 1, 'fay has a weekly honor');
  delete from public.circle_members where circle_id = club and user_id = fay;
  perform pg_temp.expect((select count(*) from public.circle_member_honors where user_id = fay and circle_id = club) = 0
    and (select count(*) from public.circle_member_honor_stats where user_id = fay and circle_id = club) = 0, 'leaving the circle takes the honors along');

  perform pg_temp.expect((select count(*) from public.circle_member_honors where user_id = cat) >= 1
    and (select title from public.circle_members where circle_id = club and user_id = cat) = 'Back', 'cat has honors and a title');
  insert into public.circle_title_notices (circle_id, user_id, title) values (club, cat, 'Back');
  update public.profiles set deleted_at = now() where id = cat;
  perform pg_temp.expect((select count(*) from public.circle_member_honors where user_id = cat) = 0
    and (select count(*) from public.circle_member_honor_stats where user_id = cat) = 0
    and (select count(*) from public.circle_honor_prefs where user_id = cat) = 0
    and (select count(*) from public.circle_title_notices where user_id = cat) = 0, 'a deleted account: honors, streak, choices and waiting pushes are erased');
  perform pg_temp.expect((select title from public.circle_members where circle_id = club and user_id = cat) is null, 'and the title');
  perform public.run_circle_honors();
  perform pg_temp.expect((select count(*) from public.circle_member_honors where user_id = cat) = 0, 'the nightly run does not bring them back');
end $$;
\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'member honors: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
