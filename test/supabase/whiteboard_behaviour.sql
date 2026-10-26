-- Behaviour checks for the whiteboard (D10): migrations 202610281400 to
-- 202610281450. Run by test/supabase/whiteboard_test.dart against the local
-- database: it applies the migrations in a transaction, plays people through
-- them, and rolls everything back. Run from the repository root.
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
\i supabase/migrations/202610280100_scheduled_calls_schema.sql
\i supabase/migrations/202610280110_scheduled_calls_events.sql
\i supabase/migrations/202610280120_scheduled_calls_push.sql
\i supabase/migrations/202610280130_scheduled_calls_agenda.sql
\i supabase/migrations/202610280140_scheduled_calls_account.sql
\i supabase/migrations/202610280200_group_space_schema.sql
\i supabase/migrations/202610280210_group_space_albums.sql
\i supabase/migrations/202610280220_group_space_folders.sql
\i supabase/migrations/202610280230_group_space_account.sql
\i supabase/migrations/202610280300_quick_replies.sql
\i supabase/migrations/202610280310_away_auto_reply.sql
\i supabase/migrations/202610280320_video_notes.sql
\i supabase/migrations/202610280330_quick_replies_account.sql
\i supabase/migrations/202610280400_account_security_schema.sql
\i supabase/migrations/202610280410_mfa_recovery_codes.sql
\i supabase/migrations/202610280420_account_security_events.sql
\i supabase/migrations/202610280430_account_security_triggers.sql
\i supabase/migrations/202610280500_checkin_schema.sql
\i supabase/migrations/202610280510_checkin_rpcs.sql
\i supabase/migrations/202610280520_checkin_push.sql
\i supabase/migrations/202610280530_checkin_account.sql
\i supabase/migrations/202610280540_group_tabs_schema.sql
\i supabase/migrations/202610280550_group_tabs_rpcs.sql
\i supabase/migrations/202610280560_group_tabs_account.sql
\i supabase/migrations/202610280610_interactions_schema.sql
\i supabase/migrations/202610280620_interactions_send.sql
\i supabase/migrations/202610280630_interactions_submit.sql
\i supabase/migrations/202610280640_interactions_bot_api.sql
\i supabase/migrations/202610280650_interactions_callbacks.sql
\i supabase/migrations/202610280660_interactions_account.sql
\i supabase/migrations/202610280700_hashtags_schema.sql
\i supabase/migrations/202610280710_circle_posts_rpcs.sql
\i supabase/migrations/202610280720_circle_posts_read.sql
\i supabase/migrations/202610280730_moments_hashtags.sql
\i supabase/migrations/202610280740_posts_guard.sql
\i supabase/migrations/202610280750_featured_posts_tab.sql
\i supabase/migrations/202610280760_featured_push.sql
\i supabase/migrations/202610280770_hashtags_account.sql
\i supabase/migrations/202610280800_ai_draft_reply.sql
\i supabase/migrations/202610280900_chat_privacy_schema.sql
\i supabase/migrations/202610280910_chat_privacy_rpc.sql
\i supabase/migrations/202610280920_chat_privacy_enforce.sql
\i supabase/migrations/202610280930_view_once_screenshots.sql
\i supabase/migrations/202610280940_chat_privacy_account.sql
\i supabase/migrations/202610281400_whiteboard_schema.sql
\i supabase/migrations/202610281410_whiteboard_versions.sql
\i supabase/migrations/202610281420_whiteboard_rpcs.sql
\i supabase/migrations/202610281430_whiteboard_files_realtime.sql
\i supabase/migrations/202610281440_whiteboard_tabs_guard.sql
\i supabase/migrations/202610281450_whiteboard_account.sql
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

-- The conversation of the circle channel 'plaza'.
insert into pg_temp.ids
select 'plazac', cc.conversation_id from public.circle_channels cc where cc.id = pg_temp.i('plaza');

-- A put op for [kind] with [data]; z defaults to 'V'.
create function pg_temp.put(id uuid, kind text, data jsonb, z text default 'V', base integer default null, revive boolean default false)
returns jsonb language sql as $$
  select jsonb_strip_nulls(jsonb_build_object('op', 'put', 'id', id, 'kind', kind, 'z', z, 'data', data,
    'base_rev', base, 'revive', case when revive then true end))
$$;
create function pg_temp.del(id uuid) returns jsonb language sql as $$
  select jsonb_build_object('op', 'del', 'id', id)
$$;
create function pg_temp.stroke(n integer default 3) returns jsonb language sql as $$
  select jsonb_build_object('p', (select jsonb_agg(v) from (select unnest(array[10, 10, 20, 25, 30, 20]) v) q), 'c', 4278190080, 'sw', 3)
$$;
-- The first result of an apply call.
create function pg_temp.first(res jsonb) returns jsonb language sql as $$ select res -> 0 $$;
grant execute on all functions in schema pg_temp to public;

-- ===================================== 1. what is closed, what is not touched
do $$
declare
  def text;
begin
  perform pg_temp.expect(not exists (
    select 1 from information_schema.role_table_grants
    where table_name in ('whiteboard_versions') and grantee in ('anon', 'authenticated')
  ), 'versions are closed to clients');
  perform pg_temp.expect(not exists (
    select 1 from information_schema.role_table_grants
    where table_name in ('whiteboards', 'whiteboard_elements')
      and grantee in ('anon', 'authenticated') and privilege_type <> 'SELECT'
  ), 'boards and elements are read-only for clients');
  def := pg_get_functiondef('public.run_later_dispatch()'::regprocedure);
  perform pg_temp.expect(def not like '%whiteboard%', 'run_later_dispatch is not touched');
  perform pg_temp.expect(exists (select 1 from storage.buckets where id = 'whiteboard-files' and not public), 'the picture bucket is private');
  perform pg_temp.expect(exists (select 1 from public.conversation_tab_kinds where kind = 'whiteboard' and target_type = 'id'), 'the tab kind exists');
  perform pg_temp.expect(exists (select 1 from pg_policies where schemaname = 'realtime' and policyname = 'whiteboard_live_receive')
    and exists (select 1 from pg_policies where schemaname = 'realtime' and policyname = 'whiteboard_live_send'), 'the live channel has its policies');
  perform pg_temp.expect(pg_get_functiondef('public.guard_items_after_write()'::regprocedure) like '%whiteboards%'
    and pg_get_functiondef('public.guard_items_after_write()'::regprocedure) like '%circle_posts%'
    and pg_get_functiondef('public.get_conversation_tabs(uuid, boolean)'::regprocedure) like '%featured_posts%', 'the patches of other packages are still there');
end $$;

-- ===================================== 2. making and listing boards
do $$
declare
  g1 uuid := pg_temp.i('g1');
  r jsonb;
  b uuid;
  n integer;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  r := public.create_whiteboard(g1, '  Trip plan ', null);
  b := (r ->> 'id')::uuid;
  insert into pg_temp.ids values ('b1', b);
  perform pg_temp.expect(r ->> 'title' = 'Trip plan' and (r ->> 'can_edit')::boolean and (r ->> 'can_manage')::boolean and (r ->> 'element_count')::int = 0, 'a board starts empty, trimmed, and its maker can edit and manage it');

  perform pg_temp.expect(public.create_whiteboard(g1, 'again', b) ->> 'id' = b::text, 'sending the same id again returns the board');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_whiteboard(%L, ''x'', %L)', g1, b)) = 'P0002', 'but not for somebody else');
  r := public.create_whiteboard(g1, '', null);
  insert into pg_temp.ids values ('b2', (r ->> 'id')::uuid);
  perform pg_temp.expect(r ->> 'title' = '' and (r ->> 'can_manage')::boolean and not (public.get_whiteboard(b) -> 'board' ->> 'can_manage')::boolean, 'any member may make one, with no title; they manage their own, not the group''s other boards');

  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_whiteboard(%L, ''x'')', g1)) = 'P0002', 'someone outside cannot make one');
  perform pg_temp.expect(pg_temp.state(format('select * from public.list_whiteboards(%L)', g1)) = '42501', 'nor list them');
  perform pg_temp.expect(pg_temp.state(format('select public.get_whiteboard(%L)', b)) = 'P0002', 'nor open one');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.whiteboards') = 0 and pg_temp.cnt('select 1 from public.whiteboard_elements') = 0, 'nor read the tables');

  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_whiteboard(%L, %L)', g1, repeat('t', 101))) = '22023', 'a title over 100 characters is refused');
  select count(*) into n from public.list_whiteboards(g1);
  perform pg_temp.expect(n = 2, 'the chat lists its two boards');
  perform pg_temp.root();
  insert into public.whiteboards (conversation_id, title, created_by) select g1, 'filler ' || x, pg_temp.i('ada') from generate_series(1, 18) x;
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_whiteboard(%L, ''21st'')', g1)) = '22023', 'twenty boards per chat');
  perform pg_temp.root();
  delete from public.whiteboards where title like 'filler %';

  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(public.create_whiteboard(pg_temp.i('dm'), 'Sketch', null) ->> 'title' = 'Sketch', 'a direct chat can have one');
  perform pg_temp.root();
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('bob'), pg_temp.i('ada'));
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_whiteboard(%L, ''x'')', pg_temp.i('dm'))) = '42501', 'not once the other person has blocked you');
  perform pg_temp.root();
  delete from public.blocks where blocker_id = pg_temp.i('bob');
end $$;

-- ===================================== 3. drawing: ops, rules and limits
do $$
declare
  b uuid := pg_temp.i('b1');
  s1 uuid := gen_random_uuid();
  s2 uuid := gen_random_uuid();
  sh uuid := gen_random_uuid();
  st uuid := gen_random_uuid();
  tx uuid := gen_random_uuid();
  im uuid := gen_random_uuid();
  res jsonb;
  got jsonb;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  res := public.whiteboard_apply_ops(b, jsonb_build_array(
    pg_temp.put(s1, 'stroke', pg_temp.stroke(), 'V'),
    pg_temp.put(s2, 'stroke', jsonb_build_object('p', jsonb_build_array(5, 5), 'pr', jsonb_build_array(50), 'hl', true, 'sw', 12), 'W'),
    pg_temp.put(sh, 'shape', '{"s":"rect","x":0,"y":0,"w":100,"h":60,"c":4278190080,"f":4294967295,"sw":2,"r":0.5}', 'X'),
    pg_temp.put(st, 'sticky', '{"x":10,"y":10,"w":120,"h":120,"c":4294957568,"t":"Book the hut"}', 'Y'),
    pg_temp.put(tx, 'text', '{"x":0,"y":200,"t":"Saturday","fs":24,"a":"l"}', 'Z'),
    pg_temp.put(im, 'image', jsonb_build_object('x', 0, 'y', 0, 'w', 100, 'h', 80, 'path', b::text || '/pic.jpg'), 'a')
  ));
  perform pg_temp.expect((select count(*) from jsonb_array_elements(res) e where e ->> 'status' = 'ok' and (e ->> 'rev')::int = 1) = 6, 'a member draws all five kinds, each at revision 1');
  perform pg_temp.root();
  perform pg_temp.expect((select element_count = 6 and data_size > 100 from public.whiteboards where id = b), 'the board counts its elements and their size');
  perform pg_temp.act(pg_temp.i('ada'));
  got := public.get_whiteboard(b);
  perform pg_temp.expect(jsonb_array_length(got -> 'elements') = 6 and got -> 'elements' -> 0 ->> 'id' = s1::text and got -> 'elements' -> 5 ->> 'id' = im::text, 'the board comes back in drawing order');

  -- Invalid elements are refused one by one, the rest go through.
  res := public.whiteboard_apply_ops(b, jsonb_build_array(
    pg_temp.put(gen_random_uuid(), 'stroke', '{"p":[1,2,3]}'),
    pg_temp.put(gen_random_uuid(), 'stroke', '{"p":[1,2],"evil":1}'),
    pg_temp.put(gen_random_uuid(), 'stroke', '{"p":["a","b"]}'),
    pg_temp.put(gen_random_uuid(), 'stroke', '{"p":[1,200000]}'),
    pg_temp.put(gen_random_uuid(), 'stroke', '{"p":[1,2],"pr":[1,2]}'),
    pg_temp.put(gen_random_uuid(), 'shape', '{"s":"star","x":0,"y":0,"w":1,"h":1}'),
    pg_temp.put(gen_random_uuid(), 'shape', '{"s":"rect","x":0,"y":0}'),
    pg_temp.put(gen_random_uuid(), 'sticky', jsonb_build_object('x', 0, 'y', 0, 'w', 100, 'h', 100, 't', repeat('a', 1001))),
    pg_temp.put(gen_random_uuid(), 'text', '{"x":0,"y":0,"t":5}'),
    pg_temp.put(gen_random_uuid(), 'image', jsonb_build_object('x', 0, 'y', 0, 'w', 100, 'h', 80, 'path', gen_random_uuid()::text || '/other.jpg')),
    pg_temp.put(gen_random_uuid(), 'image', '{"x":0,"y":0,"w":100,"h":80,"path":"../../x"}'),
    pg_temp.put(gen_random_uuid(), 'line', '{}'),
    pg_temp.put(gen_random_uuid(), 'stroke', pg_temp.stroke(), 'not valid!'),
    pg_temp.put(gen_random_uuid(), 'shape', '{"s":"rect","x":0,"y":0,"w":1,"h":1,"sw":900}'),
    '{"op":"zap","id":"00000000-0000-4000-8000-000000000001"}'::jsonb,
    '{"op":"put","id":"nope"}'::jsonb,
    pg_temp.put(gen_random_uuid(), 'text', '{"x":1,"y":1,"t":"fine"}', 'b')
  ));
  perform pg_temp.expect((select count(*) from jsonb_array_elements(res) e where e ->> 'status' = 'rejected') = 16 and res -> 16 ->> 'status' = 'ok', 'malformed elements, unknown keys, other boards'' pictures and bad ops are rejected; the valid one goes in');
  perform pg_temp.expect(pg_temp.state(format('select public.whiteboard_apply_ops(%L, ''{}'')', b)) = '22023', 'ops must be an array');
  perform pg_temp.expect(pg_temp.state(format('select public.whiteboard_apply_ops(%L, %L)', b, (select jsonb_agg(pg_temp.del(gen_random_uuid())) from generate_series(1, 201))::text)) = '22023', 'at most 200 ops at once');

  -- A repeated send is not a change; a stale one is a conflict.
  res := public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.put(sh, 'shape', '{"s":"rect","x":0,"y":0,"w":100,"h":60,"c":4278190080,"f":4294967295,"sw":2,"r":0.5}', 'X', 1)));
  perform pg_temp.expect(res -> 0 ->> 'status' = 'ok' and (res -> 0 ->> 'rev')::int = 1, 'the same content again changes nothing');
  perform pg_temp.act(pg_temp.i('bob'));
  res := public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.put(sh, 'shape', '{"s":"rect","x":50,"y":0,"w":100,"h":60,"c":4278190080,"f":4294967295,"sw":2,"r":0.5}', 'X', 1)));
  perform pg_temp.expect(res -> 0 ->> 'status' = 'ok' and (res -> 0 ->> 'rev')::int = 2, 'a change on the current revision is applied');
  perform pg_temp.act(pg_temp.i('ada'));
  res := public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.put(sh, 'shape', '{"s":"rect","x":0,"y":50,"w":100,"h":60,"c":4278190080,"f":4294967295,"sw":2,"r":0.5}', 'X', 1)));
  perform pg_temp.expect(res -> 0 ->> 'status' = 'conflict' and (res -> 0 -> 'element' ->> 'rev')::int = 2 and (res -> 0 -> 'element' -> 'data' ->> 'x')::int = 50, 'a change on an old revision comes back as a conflict with the current element');
  perform pg_temp.root();
  perform pg_temp.expect((select data ->> 'y' = '0' from public.whiteboard_elements where id = sh), 'and nothing was applied');
  perform pg_temp.act(pg_temp.i('ada'));
  res := public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.put(sh, 'shape', '{"s":"rect","x":50,"y":50,"w":100,"h":60,"c":4278190080,"f":4294967295,"sw":2,"r":0.5}', 'X', 2)));
  perform pg_temp.expect(res -> 0 ->> 'status' = 'ok' and (res -> 0 ->> 'rev')::int = 3, 'merged and sent again on the new revision, it goes through');
  res := public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.put(sh, 'sticky', '{"x":0,"y":0,"w":100,"h":100}', 'X', 3)));
  perform pg_temp.expect(res -> 0 ->> 'reason' = 'bad kind', 'the kind of an element never changes');
  res := public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.put(sh, 'shape', '{"s":"rect","x":50,"y":50,"w":100,"h":60}', 'c')));
  perform pg_temp.expect(res -> 0 ->> 'status' = 'conflict', 'a put with no revision for an element that exists is a conflict');

  -- Rubbing out, and bringing it back.
  res := public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.del(s2)));
  perform pg_temp.expect(res -> 0 ->> 'status' = 'ok' and (res -> 0 ->> 'rev')::int = 2, 'a rub-out is a tombstone at the next revision');
  perform pg_temp.root();
  perform pg_temp.expect((select deleted and data = '{}'::jsonb from public.whiteboard_elements where id = s2), 'its data is emptied');
  perform pg_temp.expect((select element_count = 6 from public.whiteboards where id = b), 'and it is no longer counted (5 + 1 added above)');
  perform pg_temp.act(pg_temp.i('bob'));
  res := public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.del(s2), pg_temp.del(gen_random_uuid())));
  perform pg_temp.expect(res -> 0 ->> 'status' = 'ok' and res -> 1 ->> 'status' = 'ok', 'rubbing out twice, or what never was, is fine');
  res := public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.put(s2, 'stroke', '{"p":[5,5]}', 'W', 1)));
  perform pg_temp.expect(res -> 0 ->> 'status' = 'conflict' and (res -> 0 -> 'element' ->> 'deleted')::boolean, 'an edit that arrives late for a rubbed-out element does not bring it back');
  res := public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.put(s2, 'stroke', '{"p":[5,5],"hl":true}', 'W', 1, true)));
  perform pg_temp.expect(res -> 0 ->> 'status' = 'conflict', 'nor does a revive with a stale revision');
  res := public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.put(s2, 'stroke', '{"p":[5,5],"hl":true}', 'W', 2, true)));
  perform pg_temp.expect(res -> 0 ->> 'status' = 'ok' and (res -> 0 ->> 'rev')::int = 3, 'undo of the rub-out, which saw the tombstone, brings it back');
  perform pg_temp.root();
  perform pg_temp.expect((select not deleted and data ->> 'hl' = 'true' from public.whiteboard_elements where id = s2) and (select element_count = 7 from public.whiteboards where id = b), 'with its data and counted again');
  perform pg_temp.expect(exists (select 1 from public.whiteboard_elements where id = s2 and updated_by = pg_temp.i('bob')), 'the last editor is kept');

  -- An element of another board is not touched.
  insert into pg_temp.ids values ('other_el', gen_random_uuid());
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.whiteboard_apply_ops(pg_temp.i('b2'), jsonb_build_array(pg_temp.put(pg_temp.i('other_el'), 'text', '{"x":0,"y":0,"t":"b2"}', 'V')));
  res := public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.put(pg_temp.i('other_el'), 'text', '{"x":0,"y":0,"t":"hijack"}', 'V', 1), pg_temp.del(pg_temp.i('other_el'))));
  perform pg_temp.expect(res -> 0 ->> 'reason' = 'bad id' and res -> 1 ->> 'status' = 'ok', 'the id of another board''s element is refused and cannot be rubbed out from here');
  perform pg_temp.root();
  perform pg_temp.expect((select data ->> 't' = 'b2' and not deleted from public.whiteboard_elements where id = pg_temp.i('other_el')), 'and it is untouched');

  -- Limits.
  perform pg_temp.root();
  update public.whiteboards set element_count = 2999 where id = b;
  perform pg_temp.act(pg_temp.i('bob'));
  res := public.whiteboard_apply_ops(b, jsonb_build_array(
    pg_temp.put(gen_random_uuid(), 'text', '{"x":1,"y":1,"t":"3000th"}', 'c'),
    pg_temp.put(gen_random_uuid(), 'text', '{"x":1,"y":1,"t":"3001st"}', 'd')));
  perform pg_temp.expect(res -> 0 ->> 'status' = 'ok' and res -> 1 ->> 'reason' = 'too many elements', 'a board holds 3000 elements');
  perform pg_temp.root();
  update public.whiteboards set element_count = 10, data_size = 5999990 where id = b;
  perform pg_temp.act(pg_temp.i('bob'));
  res := public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.put(gen_random_uuid(), 'text', '{"x":1,"y":1,"t":"too much data in total"}', 'e')));
  perform pg_temp.expect(res -> 0 ->> 'reason' = 'too much data', 'and 6 MB of data');
  perform pg_temp.root();
  update public.whiteboards set element_count = (select count(*) from public.whiteboard_elements where board_id = b and not deleted),
    data_size = (select coalesce(sum(length(data::text)), 0) from public.whiteboard_elements where board_id = b and not deleted) where id = b;
  perform pg_temp.act(pg_temp.i('bob'));
  res := public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.put(gen_random_uuid(), 'stroke',
    jsonb_build_object('p', (select jsonb_agg(x % 1000) from generate_series(1, 4002) x)), 'f')));
  perform pg_temp.expect(res -> 0 ->> 'reason' = 'invalid element', 'a stroke over 2000 points is refused');
  res := public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.put(gen_random_uuid(), 'stroke',
    jsonb_build_object('p', (select jsonb_agg(x * 99.5) from generate_series(1, 4000) x)), 'f')));
  perform pg_temp.expect(res -> 0 ->> 'reason' = 'invalid element', 'and a stroke over 40000 characters');

  -- Tombstones do not pile up.
  perform pg_temp.root();
  update public.whiteboard_elements set updated_at = now() - interval '31 days' where id = s2 and false;
  insert into public.whiteboard_elements (id, board_id, z, kind, deleted, updated_at)
  select gen_random_uuid(), b, 'V', 'text', true, now() - interval '40 days' from generate_series(1, 3);
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.put(gen_random_uuid(), 'text', '{"x":1,"y":1,"t":"new"}', 'g')));
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.whiteboard_elements where board_id = b and deleted and updated_at < now() - interval '30 days'), 'tombstones over a month old are tidied');
end $$;

-- ===================================== 4. who may draw
do $$
declare
  b uuid := pg_temp.i('b1');
  res jsonb;
begin
  -- "Only managers can edit".
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.update_whiteboard_meta(%L, ''{"managers_only": true}'')', b)) = '42501', 'a plain member cannot lock a board');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.update_whiteboard_meta(b, '{"managers_only": true}');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.whiteboard_apply_ops(%L, ''[]'')', b)) = '42501', 'a locked board takes no drawing from a member');
  perform pg_temp.expect(public.get_whiteboard(b) -> 'board' ->> 'can_edit' = 'false' and jsonb_array_length(public.get_whiteboard(b) -> 'elements') > 0, 'but they can still look at it');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.whiteboard_apply_ops(%L, ''[]'')', b)) = 'ok', 'the owner can draw on it');
  perform public.update_whiteboard_meta(b, '{"managers_only": false}');

  -- Outsiders and a suspended account.
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.whiteboard_apply_ops(%L, ''[]'')', b)) = 'P0002', 'someone outside cannot draw');
  perform pg_temp.expect(pg_temp.state(format('select public.update_whiteboard_meta(%L, ''{"title":"x"}'')', b)) = 'P0002', 'or rename');
  perform pg_temp.root();
  insert into public.app_user_suspensions (user_id, reason) values (pg_temp.i('bob'), 'test') on conflict do nothing;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.whiteboard_apply_ops(%L, ''[]'')', b)) = '42501', 'a suspended account cannot draw');
  perform pg_temp.root();
  delete from public.app_user_suspensions where user_id = pg_temp.i('bob');

  -- Renaming.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(public.update_whiteboard_meta(b, '{"title":"  Hike plan "}') ->> 'title' = 'Hike plan', 'anyone who can draw can rename');
  perform pg_temp.expect(pg_temp.state(format('select public.update_whiteboard_meta(%L, %L)', b, jsonb_build_object('title', repeat('t', 101))::text)) = '22023', 'to at most 100 characters');
  perform pg_temp.expect(pg_temp.state(format('select public.update_whiteboard_meta(%L, ''[1]'')', b)) = '22023', 'the patch is an object');
end $$;

-- ===================================== 5. versions, clearing and restoring
do $$
declare
  b uuid := pg_temp.i('b1');
  v uuid;
  v_manual uuid;
  before_count integer;
  listed integer;
  got jsonb;
  extra uuid := gen_random_uuid();
  n integer;
  vcount integer;
begin
  perform pg_temp.root();
  select element_count into before_count from public.whiteboards where id = b;
  -- A burst after a quiet spell takes a snapshot of how it was.
  update public.whiteboards set created_at = now() - interval '2 hours', updated_at = now() - interval '20 minutes', last_snapshot_at = null where id = b;
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.put(extra, 'text', '{"x":9,"y":9,"t":"after the quiet"}', 'h')));
  perform pg_temp.root();
  select id into v from public.whiteboard_versions where board_id = b and kind = 'auto' order by created_at desc limit 1;
  perform pg_temp.expect(v is not null and (select element_count = before_count from public.whiteboard_versions where id = v), 'the first change after a quiet spell snapshots the board as it was');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.put(gen_random_uuid(), 'text', '{"x":9,"y":9,"t":"again"}', 'i')));
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.whiteboard_versions where board_id = b) = 1, 'but not for the next one');

  -- A named version by anyone who can draw; a stranger sees nothing.
  perform pg_temp.act(pg_temp.i('cat'));
  v_manual := public.create_whiteboard_version(b, ' Before lunch ');
  select count(*) into listed from public.list_whiteboard_versions(b);
  perform pg_temp.root();
  select element_count into vcount from public.whiteboard_versions where id = v_manual;
  perform pg_temp.expect(listed = 2 and (select label from public.whiteboard_versions where id = v_manual) = 'Before lunch', 'a named version is kept and listed');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_whiteboard_version(%L, %L)', b, repeat('n', 121))) = '22023', 'a name is at most 120 characters');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select * from public.list_whiteboard_versions(%L)', b)) = 'P0002' and pg_temp.state(format('select public.get_whiteboard_version(%L)', v_manual)) = 'P0002', 'an outsider sees no versions');
  perform pg_temp.expect(pg_temp.state('select 1 from public.whiteboard_versions') = '42501', 'nor the table');

  -- Restoring: managers and the maker only.
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.restore_whiteboard_version(%L)', v_manual)) = '42501', 'a plain member cannot restore');
  perform pg_temp.expect(pg_temp.state(format('select public.clear_whiteboard(%L)', b)) = '42501', 'or clear');
  perform pg_temp.act(pg_temp.i('ada'));
  got := public.get_whiteboard_version(v_manual);
  perform pg_temp.expect(jsonb_array_length(got -> 'elements') = vcount, 'a version can be looked at');
  perform public.clear_whiteboard(b);
  perform pg_temp.expect(jsonb_array_length(public.get_whiteboard(b) -> 'elements') = 0, 'clearing empties the board');
  perform pg_temp.root();
  perform pg_temp.expect((select element_count = 0 and data_size = 0 from public.whiteboards where id = b) and exists (select 1 from public.whiteboard_versions where board_id = b and kind = 'restore'), 'after a snapshot of it');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.restore_whiteboard_version(v_manual);
  got := public.get_whiteboard(b);
  perform pg_temp.expect(jsonb_array_length(got -> 'elements') = vcount and (got -> 'board' ->> 'element_count')::int = jsonb_array_length(got -> 'elements'), 'restoring brings the elements back and the count with them');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.whiteboard_elements where board_id = b and not deleted) = jsonb_array_length(got -> 'elements'), 'with no stray elements');
  -- Elements come back with a higher revision than the tombstone, so a stale client conflicts.
  perform pg_temp.expect(not exists (select 1 from public.whiteboard_elements where board_id = b and not deleted and rev < 3 and kind = 'shape'), 'at a newer revision');

  -- Eight versions at most.
  perform pg_temp.act(pg_temp.i('ada'));
  for n in 1..10 loop
    perform public.create_whiteboard_version(b, 'v' || n);
  end loop;
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.whiteboard_versions where board_id = b) = 8, 'a board keeps its newest eight versions');
  perform pg_temp.expect(exists (select 1 from public.whiteboard_versions where board_id = b and label = 'v10'), 'the newest is among them');
end $$;

-- ===================================== 6. pictures and the live channel
do $$
declare
  b uuid := pg_temp.i('b1');
  n integer;
  d uuid;
begin
  perform pg_temp.expect(public.whiteboard_file_board_id(b::text || '/a.jpg') = b and public.whiteboard_file_board_id('x/a.jpg') is null and public.whiteboard_file_board_id(b::text || '/a/b.jpg') is null, 'a picture path is <board id>/<file>');

  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(public.can_current_user_upload_whiteboard_file(b), 'a member can add pictures');
  perform pg_temp.expect(public.can_use_whiteboard_live(b) and public.can_send_whiteboard_live(b), 'and join the live channel and send on it');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(not public.can_current_user_upload_whiteboard_file(b) and not public.can_use_whiteboard_live(b) and not public.can_send_whiteboard_live(b) and not public.can_current_user_view_whiteboard(b), 'an outsider can do none of it');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select public.can_use_whiteboard_live(%L)', b)) = '42501', 'nor a signed-out caller');

  perform pg_temp.act(pg_temp.i('ada'));
  perform public.update_whiteboard_meta(b, '{"managers_only": true}');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(public.can_use_whiteboard_live(b) and not public.can_send_whiteboard_live(b) and not public.can_current_user_upload_whiteboard_file(b), 'on a locked board a member listens and shows themselves, but cannot send or add pictures');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.update_whiteboard_meta(b, '{"managers_only": false}');

  -- 60 pictures at most.
  perform pg_temp.root();
  insert into storage.objects (bucket_id, name, owner)
  select 'whiteboard-files', b::text || '/f' || x || '.jpg', pg_temp.i('ada') from generate_series(1, 60) x;
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(not public.can_current_user_upload_whiteboard_file(b), 'sixty pictures per board');
  perform pg_temp.root();
  -- Storage refuses a plain delete; the Storage API would do this.
  set local session_replication_role = replica;
  delete from storage.objects where bucket_id = 'whiteboard-files' and name like b::text || '/f%';
  set local session_replication_role = origin;

  -- The direct chat's block shuts the live channel.
  perform pg_temp.act(pg_temp.i('ada'));
  d := (public.create_whiteboard(pg_temp.i('dm'), 'Sketch 2', null) ->> 'id')::uuid;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(public.can_use_whiteboard_live(d), 'the other person of a direct chat can join its live channel');
  perform pg_temp.root();
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('ada'), pg_temp.i('bob'));
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(not public.can_use_whiteboard_live(d), 'not once blocked');
  perform pg_temp.root();
  delete from public.blocks where blocker_id = pg_temp.i('ada');
end $$;

-- ===================================== 7. the whiteboard as a tab
do $$
declare
  g1 uuid := pg_temp.i('g1');
  g2 uuid := pg_temp.i('g2');
  b uuid := pg_temp.i('b1');
  other uuid;
  tab jsonb;
  tab_id uuid;
begin
  perform pg_temp.act(pg_temp.i('eve'));
  other := (public.create_whiteboard(g2, 'Elsewhere', null) ->> 'id')::uuid;
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''whiteboard'', %L, null)', g1, other::text)) = '22023', 'a board of another chat is refused as a target');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''whiteboard'', null, ''x'')', g1)) = '22023', 'and a tab with no target');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''whiteboard'', ''nope'', ''x'')', g1)) = '22023', 'and a bad id');
  tab := public.add_conversation_tab(g1, 'whiteboard', b::text, null);
  tab_id := (tab ->> 'id')::uuid;
  perform pg_temp.expect((select title = 'Hike plan' from public.conversation_tabs where id = tab_id), 'a whiteboard tab with no title takes the board''s');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''whiteboard'', %L, ''Again'')', g1, b::text)) = 'P0001', 'the same board twice is refused');
  perform public.update_whiteboard_meta(b, '{"title":"Hike plan v2"}');
  perform pg_temp.act(pg_temp.i('bob'));
  tab := public.get_conversation_tabs(g1) -> 'tabs' -> 0;
  perform pg_temp.expect(tab ->> 'kind' = 'whiteboard' and tab ->> 'title' = 'Hike plan v2' and (tab ->> 'available')::boolean, 'the tab shows the live title');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(public.get_conversation_tabs(g1) -> 'tabs' @> '[{"kind": "whiteboard"}]'::jsonb, 'and is listed for members');

  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from pg_trigger where tgname = 'conversation_tabs_whiteboard_gone'), 'a tab goes when its board does');
  insert into pg_temp.ids select 'dead', (select (public.create_whiteboard(g1, 'Dead', null) ->> 'id')::uuid from (select pg_temp.act(pg_temp.i('ada'))) q);
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.add_conversation_tab(g1, 'whiteboard', pg_temp.i('dead')::text, null);
  perform pg_temp.expect(exists (select 1 from public.conversation_tabs where target = pg_temp.i('dead')::text), 'a second tab');
  perform public.delete_whiteboard(pg_temp.i('dead'));
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.conversation_tabs where kind = 'whiteboard' and target = pg_temp.i('dead')::text), 'deleting the board removes its tab');
  perform pg_temp.expect(exists (select 1 from public.conversation_tabs where kind = 'whiteboard' and target = b::text), 'and only its tab');
end $$;

-- ===================================== 8. deleting a board
do $$
declare
  g1 uuid := pg_temp.i('g1');
  d uuid;
  paths integer;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  d := (public.create_whiteboard(g1, 'Bob''s', null) ->> 'id')::uuid;
  perform public.whiteboard_apply_ops(d, jsonb_build_array(
    pg_temp.put(gen_random_uuid(), 'text', '{"x":0,"y":0,"t":"bye"}', 'V'),
    pg_temp.put(gen_random_uuid(), 'image', jsonb_build_object('x', 0, 'y', 0, 'w', 100, 'h', 80, 'path', d::text || '/p.png'), 'W')));
  perform public.create_whiteboard_version(d, 'keep');
  perform pg_temp.root();
  insert into storage.objects (bucket_id, name, owner) values ('whiteboard-files', d::text || '/p.png', pg_temp.i('bob'));
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select * from public.delete_whiteboard(%L)', d)) = '42501', 'a member cannot delete somebody else''s board');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select * from public.delete_whiteboard(%L)', d)) = 'ok', 'the owner of the group can');
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.whiteboard_elements where board_id = d) and not exists (select 1 from public.whiteboard_versions where board_id = d), 'its elements and versions go');
  perform pg_temp.expect((select deleted_at is not null and title = '' from public.whiteboards where id = d), 'the board is gone, its title with it');
  perform pg_temp.act(pg_temp.i('bob'));
  d := (public.create_whiteboard(g1, 'Bob''s second', null) ->> 'id')::uuid;
  perform pg_temp.root();
  insert into storage.objects (bucket_id, name, owner) values ('whiteboard-files', d::text || '/q.png', pg_temp.i('bob'));
  perform pg_temp.act(pg_temp.i('bob'));
  select count(*) into paths from public.delete_whiteboard(d);
  perform pg_temp.expect(paths = 1, 'the maker can delete theirs, and is told which pictures to remove');
  perform pg_temp.expect(pg_temp.state(format('select public.get_whiteboard(%L)', d)) = 'P0002' and pg_temp.state(format('select public.whiteboard_apply_ops(%L, ''[]'')', d)) = 'P0002', 'a deleted board cannot be opened or drawn on');
  perform pg_temp.expect(public.can_current_user_delete_whiteboard_files(d), 'and its pictures can then be removed');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(not public.can_current_user_delete_whiteboard_files(d), 'but not by anyone');
  perform pg_temp.expect(not exists (select 1 from public.list_whiteboards(g1) l where l.id = d), 'it is not listed');
end $$;

-- ===================================== 9. the AI guard reads the title
do $$
declare
  club uuid := pg_temp.i('club');
  plazac uuid := pg_temp.i('plazac');
  wb uuid;
  wb2 uuid;
  review uuid;
  listed jsonb;
begin
  perform pg_temp.root();
  perform vault.create_secret('http://127.0.0.1:54321/functions/v1', 'wecord_functions_url');
  perform vault.create_secret('d10-test-secret', 'wecord_dispatch_secret');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_ai_guard(club, true, 'joined_days', 3, 10, 'hold');
  perform pg_temp.root();
  perform pg_temp.expect((select pg_get_constraintdef(oid) like '%whiteboard%' and pg_get_constraintdef(oid) like '%circle_post%' and pg_get_constraintdef(oid) like '%task_item%' from pg_constraint where conname = 'guard_item_reviews_type'), 'the guard accepts whiteboards and still the rest');

  perform pg_temp.act(pg_temp.i('cat'));
  wb := (public.create_whiteboard(plazac, 'Win a free prize', null) ->> 'id')::uuid;
  perform pg_temp.act(pg_temp.i('ada'));
  wb2 := (public.create_whiteboard(plazac, 'Moderator board', null) ->> 'id')::uuid;
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.guard_item_reviews r where r.item_type = 'whiteboard' and r.item_id = wb and r.circle_id = club and r.actor_id = pg_temp.i('cat') and r.conversation_id = plazac), 'a new member''s board title is recorded for the check');
  perform pg_temp.expect((select r.state from public.guard_item_reviews r where r.item_id = wb) = 'checking', 'and is checked, not held back');
  perform pg_temp.expect(not exists (select 1 from public.guard_item_reviews r where r.item_id = wb2), 'a moderator''s is not');
  perform pg_temp.expect((select t.title from public.guard_item_text('whiteboard', wb) t) = 'Win a free prize', 'the guard reads the title');

  select r.id into review from public.guard_item_reviews r where r.item_id = wb;
  perform public.finish_guard_item_review(review, 'spam', 'Looks like spam', null, null);
  perform pg_temp.act(pg_temp.i('ada'));
  select jsonb_agg(to_jsonb(l)) into listed from public.list_guard_item_reviews(club) l;
  perform pg_temp.expect(listed -> 0 ->> 'item_type' = 'whiteboard' and listed -> 0 ->> 'title' = 'Win a free prize', 'what the AI flags is in the review queue');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.delete_whiteboard(wb);
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(public.count_guard_item_reviews(club) = 0, 'a deleted board leaves the queue');

  -- A new title is checked again after a minute.
  perform pg_temp.act(pg_temp.i('cat'));
  wb := (public.create_whiteboard(plazac, 'hello', null) ->> 'id')::uuid;
  perform pg_temp.root();
  update public.guard_item_reviews set created_at = now() - interval '2 minutes' where item_id = wb;
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.update_whiteboard_meta(wb, '{"title":"Buy now"}');
  perform pg_temp.root();
  perform pg_temp.expect((select r.created_at > now() - interval '1 minute' from public.guard_item_reviews r where r.item_id = wb), 'a changed title is checked again');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.update_whiteboard_meta(pg_temp.i('b1'), '{"title":"x"}');
  perform pg_temp.root();
end $$;

-- ===================================== 10. a suspended circle (K1)
do $$
declare
  plazac uuid := pg_temp.i('plazac');
  cb uuid;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  cb := (public.create_whiteboard(plazac, 'Channel board', null) ->> 'id')::uuid;
  perform pg_temp.expect(public.get_whiteboard(cb) -> 'board' ->> 'can_edit' = 'true', 'a channel can have one');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(public.get_whiteboard(cb) -> 'board' ->> 'can_manage' = 'false' and public.get_whiteboard(cb) -> 'board' ->> 'can_edit' = 'true', 'channel members draw on it');
  perform pg_temp.root();
  update public.circles set disabled_at = now(), disabled_mode = 'suspend' where id = pg_temp.i('club');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.get_whiteboard(%L)', cb)) = 'P0002', 'a suspended circle shows no board');
  perform pg_temp.expect(pg_temp.state(format('select public.whiteboard_apply_ops(%L, ''[]'')', cb)) = 'P0002', 'takes no drawing');
  perform pg_temp.expect(not public.can_use_whiteboard_live(cb) and not public.can_current_user_view_whiteboard(cb), 'and no live channel');
  perform pg_temp.expect(pg_temp.state(format('select public.create_whiteboard(%L, ''x'')', plazac)) = 'P0002', 'or a new board');
  perform pg_temp.root();
  update public.circles set disabled_at = null, disabled_mode = null where id = pg_temp.i('club');
end $$;

-- ===================================== 11. the account
do $$
declare
  b uuid := pg_temp.i('b1');
  exported jsonb;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.whiteboard_apply_ops(b, jsonb_build_array(pg_temp.put(gen_random_uuid(), 'text', '{"x":3,"y":3,"t":"bob was here"}', 'k')));
  perform pg_temp.root();
  exported := public.export_my_whiteboards(pg_temp.i('bob'));
  perform pg_temp.expect(jsonb_array_length(exported -> 'boards_made') >= 1 and exists (select 1 from jsonb_array_elements(exported -> 'drawn_on') e where (e ->> 'sticky_notes')::int + (e ->> 'texts')::int + (e ->> 'strokes')::int >= 1), 'the export has my boards and what I drew');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(exported -> 'drawn_on') e where e -> 'words' @> '"bob was here"'::jsonb), 'with the words I wrote');
  perform pg_temp.expect(public.export_my_whiteboards(pg_temp.i('dan')) = jsonb_build_object('boards_made', '[]'::jsonb, 'drawn_on', '[]'::jsonb), 'a stranger''s export is empty');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.export_my_whiteboards(%L)', pg_temp.i('bob'))) = '42501', 'clients cannot call the export');
  perform pg_temp.root();
  perform pg_temp.expect(has_function_privilege('service_role', 'public.export_my_whiteboards(uuid)', 'execute'), 'the data-export function can');

  update public.profiles set deleted_at = now() where id = pg_temp.i('bob');
  perform pg_temp.expect(not exists (select 1 from public.whiteboards where created_by = pg_temp.i('bob') or updated_by = pg_temp.i('bob'))
    and not exists (select 1 from public.whiteboard_elements where updated_by = pg_temp.i('bob'))
    and not exists (select 1 from public.whiteboard_versions where created_by = pg_temp.i('bob')), 'deleting an account takes the name off boards, elements and versions');
  perform pg_temp.expect(exists (select 1 from public.whiteboard_elements where board_id = b and not deleted), 'what was drawn stays');
end $$;

\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'whiteboard: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
