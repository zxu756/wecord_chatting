-- Behaviour checks for rich webhooks, RSS feeds and GitHub (I6): migrations
-- 202610290200 to 202610290230. Run by test/supabase/integrations_test.dart
-- against the local database: it applies the migrations in a transaction,
-- plays people through them, and rolls everything back. Run from the
-- repository root. Nothing here calls an outside address: feeds and GitHub
-- events are handed to the database functions as made-up data.
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
\i supabase/migrations/202610281100_bot_events_schema.sql
\i supabase/migrations/202610281110_bot_events_enqueue.sql
\i supabase/migrations/202610281120_bot_api2_core.sql
\i supabase/migrations/202610281130_bot_api2_chats.sql
\i supabase/migrations/202610281140_bot_api2_access.sql
\i supabase/migrations/202610281150_developer_page.sql
\i supabase/migrations/202610281160_developer_account.sql
\i supabase/migrations/202610281200_l6_hot_queries.sql
\i supabase/migrations/202610281210_l6_member_pages.sql
\i supabase/migrations/202610281220_l6_push_pages.sql
\i supabase/migrations/202610281300_workflows_schema.sql
\i supabase/migrations/202610281310_workflows_rpcs.sql
\i supabase/migrations/202610281320_workflows_events.sql
\i supabase/migrations/202610281330_workflows_run.sql
\i supabase/migrations/202610281340_workflows_account.sql
\i supabase/migrations/202610281400_whiteboard_schema.sql
\i supabase/migrations/202610281410_whiteboard_versions.sql
\i supabase/migrations/202610281420_whiteboard_rpcs.sql
\i supabase/migrations/202610281430_whiteboard_files_realtime.sql
\i supabase/migrations/202610281440_whiteboard_tabs_guard.sql
\i supabase/migrations/202610281450_whiteboard_account.sql
\i supabase/migrations/202610290200_integrations_schema.sql
\i supabase/migrations/202610290210_integrations_rpcs.sql
\i supabase/migrations/202610290220_integrations_post.sql
\i supabase/migrations/202610290230_integrations_account.sql
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


-- Becomes the service role (what the Edge Functions are).
create function pg_temp.svc() returns void language plpgsql as $$
begin
  execute 'reset role';
  execute 'set local role service_role';
end $$;
grant execute on all functions in schema pg_temp to public;

-- ------------------------------------------------------------------ cast
-- ada owns the circle "club" (channels plaza and news); bob is a member who
-- may manage webhooks; cat is a plain member; eve is outside; dan is a member
-- who will leave. root is the platform admin.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@i6.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(7,'root')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_i6', initcap(name)
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(7,'root')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(7,'root')) v(n, name);
insert into public.app_admins (user_id, role) values (pg_temp.i('root'), 'owner');
insert into public.friendships (user_low_id, user_high_id)
select least(pg_temp.i('ada'), pg_temp.i(n)), greatest(pg_temp.i('ada'), pg_temp.i(n))
from (values ('bob'),('cat'),('dan')) v(n);

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'club', public.create_circle('Hike Club', array[
  pg_temp.i('bob'), pg_temp.i('cat'), pg_temp.i('dan')]);
insert into pg_temp.ids select 'plaza', public.create_circle_channel(pg_temp.i('club'), 'plaza', null, 'text');
insert into pg_temp.ids select 'news', public.create_circle_channel(pg_temp.i('club'), 'news', null, 'text');
insert into pg_temp.ids select 'hall', public.create_circle_channel(pg_temp.i('club'), 'hall', null, 'voice');
insert into pg_temp.ids select 'hooks', public.create_circle_role(pg_temp.i('club'), 'Hooks', null, 2048, false);
select public.set_member_roles(pg_temp.i('club'), pg_temp.i('bob'), array[pg_temp.i('hooks')]);
select pg_temp.root();
insert into pg_temp.ids
select 'plazac', cc.conversation_id from public.circle_channels cc where cc.id = pg_temp.i('plaza');
insert into pg_temp.ids
select 'newsc', cc.conversation_id from public.circle_channels cc where cc.id = pg_temp.i('news');

-- A second circle owned by eve, to check nothing crosses over.
select pg_temp.act(pg_temp.i('eve'));
insert into pg_temp.ids select 'other', public.create_circle('Other', array[]::uuid[]);
insert into pg_temp.ids select 'otherch', public.create_circle_channel(pg_temp.i('other'), 'general', null, 'text');
select pg_temp.root();
grant execute on all functions in schema pg_temp to public;

-- ===================================== 1. what is closed, what is not touched
do $$
declare
  def text;
begin
  perform pg_temp.expect(not exists (
    select 1 from information_schema.role_table_grants
    where table_name in ('channel_feeds', 'channel_github_hooks', 'github_deliveries')
      and grantee in ('anon', 'authenticated')
  ), 'feeds, hooks and deliveries are closed to clients');
  perform pg_temp.expect(
    (select relrowsecurity from pg_class where oid = 'public.channel_github_hooks'::regclass)
    and (select relrowsecurity from pg_class where oid = 'public.channel_feeds'::regclass),
    'row level security is on');
  def := pg_get_functiondef('public.run_later_dispatch()'::regprocedure);
  perform pg_temp.expect(def not like '%feed%' and def not like '%github%', 'run_later_dispatch is not touched');
  perform pg_temp.expect(
    not has_function_privilege('authenticated', 'public.post_feed_items(uuid, jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.github_hook_for_delivery(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.post_webhook_message_rich(uuid, text, text, text, text, jsonb, jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'public.claim_channel_feeds(integer)', 'execute')
    and has_function_privilege('service_role', 'public.post_github_event(uuid, text, text, jsonb)', 'execute')
    and has_function_privilege('authenticated', 'public.add_channel_feed(uuid, text)', 'execute')
    and not has_function_privilege('anon', 'public.add_channel_feed(uuid, text)', 'execute'),
    'the service functions are for the service role, the management ones for signed-in people');
  perform pg_temp.expect(
    pg_get_functiondef('public.post_webhook_message(uuid, text, text, text, text)'::regprocedure) like '%webhook_rate%',
    'the plain webhook function is still there');
  perform pg_temp.expect(
    pg_get_functiondef('public.list_channel_webhooks(uuid)'::regprocedure) like '%kind = ''incoming''%'
    and pg_get_functiondef('public.create_channel_webhook(uuid, text)'::regprocedure) like '%announcement%'
    and pg_get_functiondef('public.create_channel_webhook(uuid, text)'::regprocedure) like '%kind = ''incoming''%',
    'the webhook list and limit were patched in place, announcement channels kept');
  perform pg_temp.expect(
    pg_get_functiondef('public.write_circle_audit(uuid, text, text, uuid, text, jsonb)'::regprocedure) is not null
    and pg_get_functiondef('public.messages_guard_components()'::regprocedure) like '%Only a bot%',
    'the bot component guard is untouched');
end $$;

-- ===================================== 2. what a card may hold
do $$
declare
  r jsonb;
  long_text text := repeat('x', 1501);
begin
  r := public.normalize_message_embeds(
    '[{"title":" Build passed ","url":"https://ci.example.com/run/1","description":"All 40 checks\nwere green.","color":"#2EA043",
       "author":{"name":"CI","url":"https://ci.example.com","icon_url":"https://ci.example.com/i.png"},
       "fields":[{"name":"Branch","value":"main","inline":true},{"name":"Time","value":"3m"}],
       "image":{"url":"https://ci.example.com/graph.png"},"thumbnail":"https://ci.example.com/t.png",
       "footer":{"text":"ci.example.com"},"timestamp":"2026-10-28T10:00:00+02:00","bogus":1}]'::jsonb,
    '[[{"type":"link","label":"Open","url":"https://ci.example.com/run/1"}]]'::jsonb);
  perform pg_temp.expect(r #>> '{cards,0,title}' = 'Build passed' and r #>> '{cards,0,color}' = '#2ea043'
    and r #>> '{cards,0,timestamp}' = '2026-10-28T08:00:00Z' and not (r -> 'cards' -> 0 ? 'bogus')
    and r #>> '{cards,0,thumbnail,url}' = 'https://ci.example.com/t.png'
    and jsonb_array_length(r -> 'cards' -> 0 -> 'fields') = 2 and (r #>> '{cards,0,fields,1,inline}') = 'false'
    and r #>> '{components,0,0,type}' = 'link', 'a full card is kept, trimmed, with unknown keys dropped');
  perform pg_temp.expect(public.normalize_message_embeds('[]'::jsonb) is null and public.normalize_message_embeds(null) is null,
    'no cards is nothing');
  perform pg_temp.expect(public.normalize_message_embeds('[{"color":65280,"title":"t"}]'::jsonb) #>> '{cards,0,color}' = '#00ff00', 'a colour can be a number');

  perform pg_temp.must_refuse('select public.normalize_message_embeds(''[{"title":"a"},{"title":"b"},{"title":"c"},{"title":"d"}]''::jsonb)', 'four cards are too many');
  perform pg_temp.must_refuse('select public.normalize_message_embeds(''[{"url":"https://x.example.com"}]''::jsonb)', 'a card needs something to show');
  perform pg_temp.must_refuse('select public.normalize_message_embeds(''[{"title":"t","url":"http://x.example.com"}]''::jsonb)', 'http addresses are refused');
  perform pg_temp.must_refuse('select public.normalize_message_embeds(''[{"title":"t","url":"https://192.168.0.1/x"}]''::jsonb)', 'so are IP addresses');
  perform pg_temp.must_refuse('select public.normalize_message_embeds(''[{"title":"t","image":{"url":"https://localhost/x.png"}}]''::jsonb)', 'and inner names, on pictures too');
  perform pg_temp.must_refuse('select public.normalize_message_embeds(''[{"title":"t","author":{"name":"a","icon_url":"javascript:alert(1)"}}]''::jsonb)', 'and scripts');
  perform pg_temp.must_refuse(format('select public.normalize_message_embeds(%L::jsonb)', jsonb_build_array(jsonb_build_object('description', long_text))::text), 'a long description is refused');
  perform pg_temp.must_refuse(format('select public.normalize_message_embeds(%L::jsonb)', jsonb_build_array(jsonb_build_object('title', 'a' || chr(8238) || 'b'))::text), 'a direction override is refused');
  perform pg_temp.must_refuse(format('select public.normalize_message_embeds(%L::jsonb)', jsonb_build_array(jsonb_build_object('title', 'a' || chr(10) || 'b'))::text), 'a title is one line');
  perform pg_temp.must_refuse(format('select public.normalize_message_embeds(%L::jsonb)', jsonb_build_array(jsonb_build_object('title', 't', 'description', 'a' || chr(8203) || 'b'))::text), 'a zero-width character is refused');
  perform pg_temp.must_refuse('select public.normalize_message_embeds(''[{"title":"t","color":"red"}]''::jsonb)', 'a colour that is not one is refused');
  perform pg_temp.must_refuse('select public.normalize_message_embeds(''[{"title":"t","timestamp":"soon"}]''::jsonb)', 'a time that is not one is refused');
  perform pg_temp.must_refuse(format('select public.normalize_message_embeds(%L::jsonb)',
    jsonb_build_array(jsonb_build_object('title', 't', 'fields', (select jsonb_agg(jsonb_build_object('name', 'n' || x, 'value', 'v')) from generate_series(1, 11) x)))::text), 'eleven fields are too many');
  perform pg_temp.must_refuse('select public.normalize_message_embeds(''[{"title":"t"}]''::jsonb, ''[[{"type":"button","id":"go","label":"Go"}]]''::jsonb)', 'a webhook cannot add a button nobody answers');
  perform pg_temp.must_refuse('select public.normalize_message_embeds(null, ''[[{"type":"link","label":"Go","url":"https://x.example.com"}]]''::jsonb)', 'link buttons need a card');
  perform pg_temp.must_refuse('select public.normalize_message_embeds(''[{"title":"t"}]''::jsonb, ''[[{"type":"link","label":"Go","url":"http://x.example.com"}]]''::jsonb)', 'link buttons follow the I1 rules (https only)');
  perform pg_temp.must_refuse(format('select public.normalize_message_embeds(%L::jsonb)',
    (select jsonb_agg(jsonb_build_object('title', 't', 'description', repeat('d', 1500),
      'fields', jsonb_build_array(jsonb_build_object('name', 'n', 'value', repeat('v', 300)), jsonb_build_object('name', 'm', 'value', repeat('w', 300)))))
     from generate_series(1, 3))::text), 'cards over 6000 characters together are refused');

  perform pg_temp.expect(public.embeds_strip_text(E'  a‮ b​\n\n  c  ', 50) = 'a b c', 'stripping drops hidden characters and tidies space');
  perform pg_temp.expect(char_length(public.embeds_strip_text(repeat('y', 500), 100)) = 100 and public.embeds_strip_text(repeat('y', 500), 100) like '%…', 'and cuts with an ellipsis');
  perform pg_temp.expect(public.integration_card('{"title":"t","url":"http://x.example.com","color":"nope","fields":[{"name":"","value":"v"}]}'::jsonb) = '{"title":"t"}'::jsonb, 'text from outside loses what does not fit instead of failing');
  perform pg_temp.expect(public.integration_card('{"url":"https://x.example.com"}'::jsonb) is null, 'a card with nothing to show is nothing');
  perform pg_temp.expect(public.message_embeds_summary('{"cards":[{"title":"Hello there"}]}') = 'Hello there'
    and public.message_embeds_summary('{"cards":[{"description":"first\nsecond"}]}') = 'first'
    and public.message_embeds_summary('{"cards":[{"fields":[{"name":"A","value":"b"}]}]}') = 'A: b', 'the one-line summary');
end $$;

-- ===================================== 3. rich incoming webhooks
do $$
declare
  hook jsonb;
  hid uuid;
  tok text;
  m uuid;
  row_ record;
  plaza uuid := pg_temp.i('plazac');
begin
  perform pg_temp.act(pg_temp.i('ada'));
  hook := public.create_channel_webhook(pg_temp.i('plaza'), 'CI');
  hid := (hook ->> 'id')::uuid;
  tok := hook ->> 'token';
  insert into pg_temp.ids values ('wh1', hid);
  perform pg_temp.svc();

  m := public.post_webhook_message_rich(hid, tok, 'Deploy done', 'CI bot', null,
    '[{"title":"v1.2 shipped","url":"https://ci.example.com/r/1","color":"#2ea043","description":"3 fixes"}]'::jsonb,
    '[[{"type":"link","label":"Open","url":"https://ci.example.com/r/1"}]]'::jsonb);
  perform pg_temp.root();
  select * into row_ from public.messages where id = m;
  perform pg_temp.expect(row_.body = 'Deploy done' and row_.webhook_id = hid and row_.webhook_name = 'CI bot'
    and row_.embeds #>> '{cards,0,title}' = 'v1.2 shipped' and row_.embeds #>> '{components,0,0,label}' = 'Open'
    and not (row_.embeds ? 'summary') and row_.type = 'text' and row_.sender_id = pg_temp.i('ada'),
    'text and a card are stored on one webhook message');

  perform pg_temp.svc();
  m := public.post_webhook_message_rich(hid, tok, null, null, null, '[{"title":"Only a card","description":"body"}]'::jsonb, null);
  perform pg_temp.root();
  select * into row_ from public.messages where id = m;
  perform pg_temp.expect(row_.body = 'Only a card' and (row_.embeds ->> 'summary')::boolean and row_.webhook_name = 'CI',
    'a message of only a card has a one-line body, marked as a summary');

  perform pg_temp.svc();
  perform pg_temp.expect(pg_temp.state(format('select public.post_webhook_message_rich(%L, %L)', hid, tok)) = '22023', 'nothing to post is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.post_webhook_message_rich(%L, %L, ''hi'')', hid, repeat('a', 43))) = '28000', 'a wrong token is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.post_webhook_message_rich(%L, %L, ''hi'', null, null, ''[{"title":"t","url":"http://x"}]''::jsonb)', hid, tok)) = '22023', 'a bad card is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.post_webhook_message_rich(%L, %L, %L)', hid, tok, repeat('z', 2001))) = '22023', 'text over 2000 characters is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.post_webhook_message_rich(%L, %L, ''hi'')', gen_random_uuid(), tok)) = 'P0002', 'an unknown webhook is refused');
  perform pg_temp.root();

  -- Clients can never set cards.
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format(
    'insert into public.messages (conversation_id, sender_id, type, body, embeds) values (%L, %L, ''text'', ''x'', ''{"cards":[{"title":"fake"}]}''::jsonb)',
    plaza, pg_temp.i('ada'))) in ('42501', '23514'), 'a member cannot insert cards');
  perform pg_temp.expect(pg_temp.state(format(
    'update public.messages set embeds = ''{"cards":[{"title":"fake"}]}''::jsonb where id = %L', m)) in ('42501', 'ok'), 'nor add them to a message');
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.messages where embeds::text like '%fake%'), 'nothing of it sticks');
  perform pg_temp.expect(pg_temp.state(format(
    'insert into public.messages (conversation_id, sender_id, type, body, embeds) values (%L, %L, ''text'', ''x'', ''{"cards":[{"title":"fake"}]}''::jsonb)',
    plaza, pg_temp.i('ada'))) = '42501', 'not even a message that is not a webhook''s, by the server');

  -- 30 a minute.
  perform pg_temp.svc();
  for i in 1..28 loop
    perform public.post_webhook_message_rich(hid, tok, 'n' || i);
  end loop;
  perform pg_temp.expect(pg_temp.state(format('select public.post_webhook_message_rich(%L, %L, ''one too many'')', hid, tok)) = 'WH429', 'the 31st message in a minute is limited');
  perform pg_temp.root();

  -- Taking a message back takes its cards.
  update public.messages set recalled_at = now() where id = m;
  perform pg_temp.expect((select embeds from public.messages where id = m) is null, 'deleting the message drops its cards');

  -- The old function still posts plain text.
  update public.webhook_rate set window_start = now() - interval '2 minutes' where webhook_id = hid;
  perform pg_temp.svc();
  perform pg_temp.expect(public.post_webhook_message(hid, tok, 'plain', null, null) is not null, 'the plain function still works');
  perform pg_temp.root();
  perform pg_temp.expect((select embeds from public.messages where body = 'plain' and webhook_id = hid) is null, 'with no cards');
end $$;

-- ===================================== 4. feeds: managing them
do $$
declare
  p jsonb;
  n integer;
  plaza uuid := pg_temp.i('plaza');
  club uuid := pg_temp.i('club');
  hidden uuid;
begin
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, ''https://blog.example.com/feed.xml'')', plaza)) = '42501', 'a plain member cannot add a feed');
  perform pg_temp.expect(pg_temp.state(format('select * from public.list_channel_feeds(%L)', plaza)) = '42501', 'nor list them');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, ''https://blog.example.com/feed.xml'')', plaza)) = '42501', 'nor someone outside');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, ''https://blog.example.com/feed.xml'')', plaza)) = '42501', 'nor someone signed out');

  perform pg_temp.act(pg_temp.i('bob'));
  p := public.add_channel_feed(plaza, '  https://blog.example.com/feed.xml ');
  insert into pg_temp.ids values ('feed1', (p ->> 'id')::uuid);
  perform pg_temp.expect(p ->> 'url' = 'https://blog.example.com/feed.xml' and (p ->> 'enabled')::boolean and p ->> 'created_by' = pg_temp.i('bob')::text
    and p ->> 'creator_name' = 'Bob' and p -> 'title' = 'null'::jsonb, 'a member who manages webhooks adds a feed');
  perform pg_temp.expect(not (p ? 'secret') and not (p ? 'seen_keys'), 'the payload has no internals');
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, ''https://blog.example.com/feed.xml'')', plaza)) = '23505', 'the same address twice in a channel is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, ''https://blog.example.com/feed.xml'')', pg_temp.i('news'))) = 'ok', 'but another channel may follow it');
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, ''https://blog.example.com/feed.xml'')', pg_temp.i('hall'))) = '22023', 'a voice channel cannot');

  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, ''http://blog.example.com/feed.xml'')', plaza)) = '22023', 'http is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, ''https://10.0.0.1/feed.xml'')', plaza)) = '22023', 'an IP address is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, ''https://localhost/feed.xml'')', plaza)) = '22023', 'localhost is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, ''https://printer.local/feed.xml'')', plaza)) = '22023', 'an inner name is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, ''https://a.b.nip.io/feed.xml'')', plaza)) = '22023', 'a name that points at the caller is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, ''https://u:p@blog.example.com/feed.xml'')', plaza)) = '22023', 'a user name in the address is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, ''https://blog.example.com:8443/feed.xml'')', plaza)) = '22023', 'another port is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, %L)', plaza, 'https://blog.example.com/' || repeat('a', 500))) = '22023', 'a long address is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, '''')', plaza)) = '22023', 'an empty one too');

  -- 5 per channel, 10 per circle.
  for i in 2..5 loop
    perform public.add_channel_feed(plaza, 'https://site' || i || '.example.com/rss');
  end loop;
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, ''https://site6.example.com/rss'')', plaza)) = '54000', 'a channel follows at most 5 feeds');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('ada'));
  for i in 2..5 loop
    perform public.add_channel_feed(pg_temp.i('news'), 'https://news' || i || '.example.com/rss');
  end loop;
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, ''https://news6.example.com/rss'')', pg_temp.i('news'))) = '54000', 'a full channel stays full for the owner too');
  perform pg_temp.root();
  select count(*) into n from public.channel_feeds where circle_id = club;
  perform pg_temp.expect(n = 10, 'ten feeds in the circle');
  perform pg_temp.act(pg_temp.i('ada'));
  insert into pg_temp.ids select 'extrach', public.create_circle_channel(club, 'extra', null, 'text');
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, ''https://extra.example.com/rss'')', pg_temp.i('extrach'))) = '54000', 'a circle follows at most 10 feeds');

  perform pg_temp.act(pg_temp.i('bob'));
  select count(*) into n from public.list_channel_feeds(plaza);
  perform pg_temp.expect(n = 5, 'the list shows the channel''s feeds');
  select count(*) into n from public.list_channel_webhooks(plaza);
  perform pg_temp.expect(n = 1, 'but the plain webhook list shows only the real webhook');
  perform pg_temp.root();
  select webhook_id into hidden from public.channel_feeds where id = pg_temp.i('feed1');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.rename_channel_webhook(%L, ''x'')', hidden)) = '42501'
    and pg_temp.state(format('select public.delete_channel_webhook(%L)', hidden)) = '42501', 'the plain webhook functions cannot reach a feed''s hidden row');
  perform pg_temp.svc();
  perform pg_temp.expect(pg_temp.state(format('select public.post_webhook_message_rich(%L, %L, ''x'')', hidden, repeat('a', 43))) = 'P0002', 'the rich function does not know it either');
  perform pg_temp.root();

  -- Pause, resume, remove.
  perform pg_temp.act(pg_temp.i('bob'));
  p := public.set_channel_feed_enabled(pg_temp.i('feed1'), false);
  perform pg_temp.expect(not (p ->> 'enabled')::boolean and p -> 'paused_reason' = 'null'::jsonb, 'pausing');
  p := public.set_channel_feed_enabled(pg_temp.i('feed1'), true);
  perform pg_temp.expect((p ->> 'enabled')::boolean, 'resuming');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_channel_feed_enabled(%L, false)', pg_temp.i('feed1'))) = '42501'
    and pg_temp.state(format('select public.remove_channel_feed(%L)', pg_temp.i('feed1'))) = '42501', 'a plain member can do neither nor remove it');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.remove_channel_feed(%L)', pg_temp.i('feed1'))) = '42501', 'nor someone from another circle');

  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.root();
  select id into hidden from public.channel_feeds where channel_id = plaza and url like '%site5%';
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.remove_channel_feed(hidden);
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.channel_feeds where url like '%site5%' and channel_id = plaza)
    and not exists (select 1 from public.circle_webhooks where kind = 'rss' and name = 'site5.example.com' and channel_id = plaza), 'removing a feed removes its hidden row');

  -- Audit.
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = club and action = 'feed_add') >= 9
    and exists (select 1 from public.circle_audit_log where circle_id = club and action = 'feed_pause' and actor_id = pg_temp.i('bob'))
    and exists (select 1 from public.circle_audit_log where circle_id = club and action = 'feed_resume')
    and exists (select 1 from public.circle_audit_log where circle_id = club and action = 'feed_remove'), 'every change is in the audit log');
end $$;

-- ===================================== 5. GitHub connections: managing them
do $$
declare
  p jsonb;
  s1 text;
  plaza uuid := pg_temp.i('plaza');
  n integer;
begin
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.add_github_hook(%L, ''wecord/app'')', plaza)) = '42501', 'a plain member cannot add a connection');

  perform pg_temp.act(pg_temp.i('bob'));
  p := public.add_github_hook(plaza, ' wecord/app ', array['push', 'pull_request', 'push']);
  insert into pg_temp.ids values ('gh1', (p ->> 'id')::uuid);
  s1 := p ->> 'secret';
  perform pg_temp.expect(p ->> 'label' = 'wecord/app' and s1 ~ '^[A-Za-z0-9_-]{43}$' and p -> 'events' = '["pull_request", "push"]'::jsonb, 'a connection is made with a secret, shown now');
  p := public.add_github_hook(plaza, 'all-events');
  insert into pg_temp.ids values ('gh2', (p ->> 'id')::uuid);
  perform pg_temp.expect(jsonb_array_length(p -> 'events') = 6, 'no events means all of them');
  perform pg_temp.expect(pg_temp.state(format('select public.add_github_hook(%L, ''x'', array[''star''])', plaza)) = '22023', 'an event GitHub sends that we do not know is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_github_hook(%L, '''')', plaza)) = '22023', 'a name is needed');

  select count(*) into n from public.list_github_hooks(plaza) h where h::text like '%secret%';
  perform pg_temp.expect(n = 0 and (select count(*) from public.list_github_hooks(plaza)) = 2, 'the list never shows the secret');

  p := public.update_github_hook(pg_temp.i('gh1'), 'wecord/web', array['release']);
  perform pg_temp.expect(p ->> 'label' = 'wecord/web' and p -> 'events' = '["release"]'::jsonb and not (p ? 'secret'), 'renaming and choosing events');
  perform pg_temp.root();
  perform pg_temp.expect((select name from public.circle_webhooks where id = (select webhook_id from public.channel_github_hooks where id = pg_temp.i('gh1'))) = 'wecord/web', 'the name its messages carry follows');
  perform pg_temp.act(pg_temp.i('bob'));
  p := public.regenerate_github_secret(pg_temp.i('gh1'));
  perform pg_temp.expect(p ->> 'secret' <> s1 and (p ->> 'secret') ~ '^[A-Za-z0-9_-]{43}$', 'a new secret replaces the old');
  perform pg_temp.root();
  perform pg_temp.expect((select secret from public.channel_github_hooks where id = pg_temp.i('gh1')) = p ->> 'secret', 'which is the one that signs');

  perform pg_temp.act(pg_temp.i('bob'));
  p := public.set_github_hook_enabled(pg_temp.i('gh2'), false);
  perform pg_temp.expect(not (p ->> 'enabled')::boolean, 'pausing a connection');
  p := public.set_github_hook_enabled(pg_temp.i('gh2'), true);
  perform pg_temp.expect((p ->> 'enabled')::boolean, 'and resuming');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.regenerate_github_secret(%L)', pg_temp.i('gh1'))) = '42501'
    and pg_temp.state(format('select public.remove_github_hook(%L)', pg_temp.i('gh1'))) = '42501', 'a plain member cannot change or remove it');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.update_github_hook(%L, ''x'', null)', pg_temp.i('gh1'))) = '42501', 'nor can another circle''s owner');

  perform pg_temp.act(pg_temp.i('ada'));
  for i in 3..5 loop
    perform public.add_github_hook(plaza, 'repo' || i);
  end loop;
  perform pg_temp.expect(pg_temp.state(format('select public.add_github_hook(%L, ''sixth'')', plaza)) = '54000', 'a channel has at most 5 connections');

  perform pg_temp.act(pg_temp.i('bob'));
  perform public.remove_github_hook(pg_temp.i('gh2'));
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.channel_github_hooks where id = pg_temp.i('gh2')), 'a connection can be removed');
  perform pg_temp.expect(exists (select 1 from public.circle_audit_log where action = 'github_add' and target_label = 'wecord/app')
    and exists (select 1 from public.circle_audit_log where action = 'github_update')
    and exists (select 1 from public.circle_audit_log where action = 'github_regenerate')
    and exists (select 1 from public.circle_audit_log where action = 'github_remove')
    and not exists (select 1 from public.circle_audit_log where changes::text like '%' || s1 || '%'), 'audited, and no secret in the log');
end $$;

-- ===================================== 6. reading feeds and posting their items
do $$
declare
  f1 uuid := pg_temp.i('feed1');
  c record;
  n integer;
  r jsonb;
  m record;
  plaza uuid := pg_temp.i('plaza');
begin
  perform pg_temp.root();
  -- The other feeds are not due yet; only feed1 and one more per site.
  update public.channel_feeds set next_fetch_at = now() + interval '1 day' where id <> f1;
  perform pg_temp.svc();
  select count(*) into n from public.claim_channel_feeds(10);
  perform pg_temp.expect(n = 1, 'a due feed is claimed');
  select count(*) into n from public.claim_channel_feeds(10);
  perform pg_temp.expect(n = 0, 'and not again while it is being read');
  perform pg_temp.root();
  perform pg_temp.expect((select lease_until > now() from public.channel_feeds where id = f1), 'it holds a lease');
  update public.channel_feeds set lease_until = now() - interval '1 minute' where id = f1;

  -- One feed per web site in a claim.
  update public.channel_feeds set next_fetch_at = now() - interval '1 minute'
  where id in (select id from public.channel_feeds where url like 'https://news%' limit 3);
  update public.channel_feeds set url = 'https://news2.example.com/other', next_fetch_at = now() - interval '2 minutes'
  where url = 'https://news3.example.com/rss';
  perform pg_temp.svc();
  select count(*) into n from public.claim_channel_feeds(10);
  perform pg_temp.expect(n = 3, 'a due feed per site: feed1 and two news feeds, not two of one site');
  perform pg_temp.root();
  update public.channel_feeds set lease_until = null where id <> f1;
  update public.channel_feeds set next_fetch_at = now() + interval '1 day' where id <> f1;
  update public.channel_feeds set lease_until = now() - interval '1 minute', next_fetch_at = now() - interval '1 minute' where id = f1;

  -- First good read: remember, post nothing.
  perform pg_temp.svc();
  perform public.finish_channel_feed(f1, true, 200, null, '"abc"', 'Wed, 28 Oct 2026 08:00:00 GMT', 'The <b>Trail</b> Blog', array['k1', 'k2'], false);
  perform pg_temp.root();
  select * into c from public.channel_feeds where id = f1;
  perform pg_temp.expect(c.initialized and c.etag = '"abc"' and c.title = 'The <b>Trail</b> Blog' and c.seen_keys = array['k1', 'k2']
    and c.next_fetch_at >= now() + interval '15 minutes' and c.next_fetch_at <= now() + interval '18 minutes' and c.lease_until is null and c.consecutive_failures = 0,
    'a good read saves the cache headers, the title and what was seen, and waits 15 minutes');
  perform pg_temp.expect((select name from public.circle_webhooks where id = c.webhook_id) = 'The <b>Trail</b> Blog', 'the feed''s messages carry its title');

  -- Items become cards.
  perform pg_temp.svc();
  r := public.post_feed_items(f1, jsonb_build_array(
    jsonb_build_object('title', 'First <script>post</script>', 'link', 'https://blog.example.com/p/1', 'summary', E'Some   text‮ with\n\n\nbreaks', 'published', '2026-10-28T07:00:00Z'),
    jsonb_build_object('title', 'Second', 'link', 'javascript:alert(1)', 'summary', '', 'published', 'yesterday'),
    jsonb_build_object('title', null, 'link', null, 'summary', null),
    jsonb_build_object('title', 'Fourth', 'link', 'http://blog.example.com/p/4')));
  perform pg_temp.root();
  perform pg_temp.expect((r ->> 'posted')::int = 3 and (r ->> 'skipped')::int = 1, 'three items posted, the empty one skipped');
  select * into m from public.messages where webhook_id = c.webhook_id and body like 'First%';
  perform pg_temp.expect(m.embeds #>> '{cards,0,title}' = 'First <script>post</script>' and m.embeds #>> '{cards,0,url}' = 'https://blog.example.com/p/1'
    and m.embeds #>> '{cards,0,footer,text}' = 'The <b>Trail</b> Blog' and (m.embeds ->> 'summary')::boolean and m.sender_id = pg_temp.i('bob')
    and m.embeds #>> '{cards,0,description}' !~ '[‮]' and m.embeds #>> '{cards,0,timestamp}' = '2026-10-28T07:00:00Z' and m.webhook_name = 'The <b>Trail</b> Blog',
    'the text is kept as plain text (no tags are parsed), cleaned, with the link and time');
  perform pg_temp.expect(exists (select 1 from public.messages where webhook_id = c.webhook_id and body = 'Second' and not (embeds #> '{cards,0}' ? 'url') and not (embeds #> '{cards,0}' ? 'timestamp'))
    and exists (select 1 from public.messages where webhook_id = c.webhook_id and body = 'Fourth' and not (embeds #> '{cards,0}' ? 'url')), 'a link that is not https is left off');
  perform pg_temp.expect((select last_item_at is not null and items_posted = 3 and window_count = 3 from public.channel_feeds where id = f1), 'the counters');

  -- At most five at once.
  perform pg_temp.svc();
  r := public.post_feed_items(f1, (select jsonb_agg(jsonb_build_object('title', 'bulk ' || x, 'link', 'https://blog.example.com/b/' || x)) from generate_series(1, 9) x));
  perform pg_temp.root();
  perform pg_temp.expect((r ->> 'posted')::int = 5, 'five items at most per read');

  -- AutoMod's blocking keywords drop an item quietly, whatever role the poster has.
  insert into public.circle_automod_rules (circle_id, name, kind, keywords, block_message)
  values (pg_temp.i('club'), 'no-bad-words', 'keyword', array['forbiddenword'], true);
  perform pg_temp.svc();
  r := public.post_feed_items(f1, jsonb_build_array(
    jsonb_build_object('title', 'Nice day', 'summary', 'with a ForbiddenWord inside'),
    jsonb_build_object('title', 'Clean one', 'summary', 'fine')));
  perform pg_temp.root();
  perform pg_temp.expect((r ->> 'posted')::int = 1 and (r ->> 'skipped')::int = 1
    and not exists (select 1 from public.messages where body = 'Nice day') and exists (select 1 from public.messages where body = 'Clean one'), 'a blocked item is dropped and the rest posts');
  update public.circle_automod_rules set exempt_channel_ids = array[pg_temp.i('plaza')] where name = 'no-bad-words';
  perform pg_temp.svc();
  r := public.post_feed_items(f1, jsonb_build_array(jsonb_build_object('title', 'Allowed here', 'summary', 'forbiddenword')));
  perform pg_temp.root();
  perform pg_temp.expect((r ->> 'posted')::int = 1, 'unless the channel is exempt');
  delete from public.circle_automod_rules where name = 'no-bad-words';

  -- A day's cap.
  update public.channel_feeds set window_count = 47, window_day = (now() at time zone 'UTC')::date where id = f1;
  perform pg_temp.svc();
  r := public.post_feed_items(f1, jsonb_build_array(jsonb_build_object('title', 'cap a'), jsonb_build_object('title', 'cap b')));
  perform pg_temp.root();
  perform pg_temp.expect((r ->> 'posted')::int = 1 and (r ->> 'skipped')::int = 1, '48 items a day per feed');
  update public.channel_feeds set window_count = 0 where id = f1;

  -- Failures back off, then pause.
  perform pg_temp.svc();
  perform public.finish_channel_feed(f1, false, 500, 'http_500', null, null, null, null, false);
  perform pg_temp.root();
  select * into c from public.channel_feeds where id = f1;
  perform pg_temp.expect(c.consecutive_failures = 1 and c.enabled and c.next_fetch_at >= now() + interval '29 minutes' and c.last_error = 'http_500' and c.last_status = 500 and c.title = 'The <b>Trail</b> Blog',
    'a failed read waits 30 minutes and keeps what it learnt');
  for i in 2..7 loop
    perform pg_temp.svc();
    perform public.finish_channel_feed(f1, false, null, 'timeout', null, null, null, null, false);
    perform pg_temp.root();
  end loop;
  perform pg_temp.expect((select enabled and consecutive_failures = 7 and next_fetch_at <= now() + interval '361 minutes' from public.channel_feeds where id = f1), 'the wait stops growing at 6 hours');
  perform pg_temp.svc();
  perform public.finish_channel_feed(f1, false, null, 'timeout', null, null, null, null, false);
  perform pg_temp.root();
  perform pg_temp.expect((select not enabled and paused_reason = 'failing' and last_error = 'timeout' from public.channel_feeds where id = f1), 'eight in a row pause it');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.set_channel_feed_enabled(f1, true);
  perform pg_temp.root();
  perform pg_temp.expect((select enabled and consecutive_failures = 0 and paused_reason is null and last_error is null from public.channel_feeds where id = f1), 'resuming forgets the failures');
  perform pg_temp.svc();
  perform public.finish_channel_feed(f1, false, null, 'not_a_feed', null, null, null, null, true);
  perform pg_temp.root();
  perform pg_temp.expect((select not enabled and paused_reason = 'failing' and last_error = 'not_a_feed' from public.channel_feeds where id = f1), 'a plainly unusable feed pauses at once');
  perform pg_temp.svc();
  perform public.finish_channel_feed(f1, false, null, 'bad <script>' || repeat('x', 100), null, null, null, null, false);
  perform pg_temp.root();
  perform pg_temp.expect((select char_length(last_error) <= 60 and last_error !~ '[<>]' from public.channel_feeds where id = f1), 'the error text kept is short and plain');

  -- A suspended circle is not read; a poster who left is paused.
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.set_channel_feed_enabled(f1, true);
  perform pg_temp.root();
  update public.circles set disabled_at = now(), disabled_mode = 'suspend' where id = pg_temp.i('club');
  perform pg_temp.svc();
  select count(*) into n from public.claim_channel_feeds(10);
  perform pg_temp.expect(n = 0, 'a suspended circle''s feeds are not read');
  perform pg_temp.expect(pg_temp.state(format('select public.post_feed_items(%L, ''[{"title":"x"}]''::jsonb)', f1)) = 'ok', 'posting there does not raise');
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.messages where body = 'x' and webhook_id is not null), 'but posts nothing');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, ''https://later.example.com/rss'')', pg_temp.i('news'))) = '42501'
    and pg_temp.state(format('select public.add_github_hook(%L, ''later'')', pg_temp.i('news'))) = '42501', 'nothing can be added to a taken-down circle');
  perform pg_temp.root();
  update public.circles set disabled_mode = 'delist' where id = pg_temp.i('club');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.add_channel_feed(%L, ''https://later.example.com/rss'')', pg_temp.i('news'))) = '42501', 'nor to a delisted one');
  perform pg_temp.root();
  update public.circles set disabled_at = null, disabled_mode = null where id = pg_temp.i('club');

  -- Bob loses the permission: the feed pauses itself on the next claim.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_member_roles(pg_temp.i('club'), pg_temp.i('bob'), array[]::uuid[]);
  perform pg_temp.root();
  update public.channel_feeds set next_fetch_at = now() - interval '1 minute', lease_until = null where id = f1;
  perform pg_temp.svc();
  select count(*) into n from public.claim_channel_feeds(10) where feed_id = f1;
  perform pg_temp.root();
  perform pg_temp.expect(n = 0 and (select not enabled and paused_reason = 'creator_lost_access' from public.channel_feeds where id = f1), 'a poster who lost the permission pauses the feed');
  -- Ada turns it on and becomes the poster.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_channel_feed_enabled(f1, true);
  perform pg_temp.root();
  perform pg_temp.expect((select created_by from public.circle_webhooks where id = (select webhook_id from public.channel_feeds where id = f1)) = pg_temp.i('ada')
    and (select enabled from public.channel_feeds where id = f1), 'whoever turns it on becomes the one it posts as');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_member_roles(pg_temp.i('club'), pg_temp.i('bob'), array[pg_temp.i('hooks')]);
  perform pg_temp.root();
end $$;

-- ===================================== 7. GitHub deliveries
do $$
declare
  g1 uuid := pg_temp.i('gh1');
  hook jsonb;
  r jsonb;
  card jsonb := '{"title":"[wecord/web] 2 new commits pushed to main","url":"https://github.com/wecord/web/compare/a...b","color":"#2ea043",
    "author":{"name":"wecord/web","url":"https://github.com/wecord/web"},
    "description":"`abc1234` fix the thing - Ada\n`def5678` add test - Bob","footer":{"text":"pushed by ada"}}';
begin
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.github_hook_for_delivery(%L)', g1)) = '42501', 'a member cannot read a connection''s secret');
  perform pg_temp.svc();
  hook := public.github_hook_for_delivery(g1);
  perform pg_temp.expect(hook ->> 'secret' = (select secret from public.channel_github_hooks where id = g1) and hook -> 'events' = '["release"]'::jsonb, 'the function can');
  perform pg_temp.expect(public.github_hook_for_delivery(gen_random_uuid()) is null, 'an unknown connection has nothing');

  r := public.post_github_event(g1, 'd-1', 'push', card);
  perform pg_temp.expect(r ->> 'status' = 'ignored', 'an event this connection does not send is ignored');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.update_github_hook(g1, 'wecord/web', array['push', 'release']);
  perform pg_temp.svc();
  r := public.post_github_event(g1, 'd-2', 'push', card);
  perform pg_temp.expect(r ->> 'status' = 'posted', 'a chosen event is posted');
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.messages m where m.webhook_name = 'wecord/web' and m.embeds #>> '{cards,0,title}' like '[wecord/web] 2 new commits%' and m.embeds #>> '{cards,0,color}' = '#2ea043' and m.sender_id = pg_temp.i('bob')), 'as a card named after the connection');
  perform pg_temp.expect((select deliveries_count = 1 and last_event = 'push' and last_delivery_at is not null from public.channel_github_hooks where id = g1), 'the counters');
  perform pg_temp.svc();
  r := public.post_github_event(g1, 'd-2', 'push', card);
  perform pg_temp.expect(r ->> 'status' = 'duplicate', 'the same delivery twice posts once');
  r := public.post_github_event(g1, 'd-3', 'push', '{"url":"https://x.example.com"}');
  perform pg_temp.expect(r ->> 'status' = 'ignored', 'a card with nothing to show is ignored');
  r := public.post_github_event(g1, 'd-4', 'push', jsonb_build_object('title', 'A ' || chr(8238) || 'title <b>x</b>', 'url', 'http://github.com/x', 'description', repeat('word ', 1000)));
  perform pg_temp.expect(r ->> 'status' = 'posted', 'odd text is cleaned, not refused');
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.messages m where m.embeds #>> '{cards,0,title}' = 'A title <b>x</b>' and not (m.embeds #> '{cards,0}' ? 'url') and char_length(m.embeds #>> '{cards,0,description}') <= 1500), 'cleaned and cut');

  insert into public.circle_automod_rules (circle_id, name, kind, keywords, block_message)
  values (pg_temp.i('club'), 'gh', 'keyword', array['badword'], true);
  perform pg_temp.svc();
  r := public.post_github_event(g1, 'd-5', 'push', '{"title":"has a badword"}');
  perform pg_temp.expect(r ->> 'status' = 'blocked', 'AutoMod can block what GitHub sends');
  perform pg_temp.root();
  delete from public.circle_automod_rules where name = 'gh';

  -- 30 a minute.
  perform pg_temp.svc();
  for i in 1..28 loop
    perform public.post_github_event(g1, 'bulk-' || i, 'push', jsonb_build_object('title', 'c' || i));
  end loop;
  perform pg_temp.expect(pg_temp.state(format('select public.post_github_event(%L, ''bulk-x'', ''push'', ''{"title":"c"}'')', g1)) = 'WH429', 'at most 30 a minute');
  perform pg_temp.root();

  -- Turned off, and a poster who is gone.
  update public.github_deliveries set received_at = now() - interval '1 hour';
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_github_hook_enabled(g1, false);
  perform pg_temp.svc();
  perform pg_temp.expect(public.post_github_event(g1, 'd-9', 'push', card) ->> 'status' = 'paused', 'a paused connection posts nothing');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_github_hook_enabled(g1, true);
  perform public.set_member_roles(pg_temp.i('club'), pg_temp.i('bob'), array[]::uuid[]);
  perform pg_temp.svc();
  perform pg_temp.expect(public.post_github_event(g1, 'd-10', 'push', card) ->> 'status' = 'paused', 'a poster who lost the permission pauses it');
  perform pg_temp.root();
  perform pg_temp.expect((select not enabled and paused_reason = 'creator_lost_access' from public.channel_github_hooks where id = g1), 'with the reason');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_member_roles(pg_temp.i('club'), pg_temp.i('bob'), array[pg_temp.i('hooks')]);
  perform public.set_github_hook_enabled(g1, true);
  perform pg_temp.root();

  -- K1.
  update public.circles set disabled_at = now(), disabled_mode = 'suspend' where id = pg_temp.i('club');
  perform pg_temp.svc();
  perform pg_temp.expect(pg_temp.state(format('select public.post_github_event(%L, ''d-11'', ''push'', ''{"title":"x"}'')', g1)) = '42501', 'a suspended circle takes nothing from GitHub');
  perform pg_temp.root();
  update public.circles set disabled_at = null, disabled_mode = null where id = pg_temp.i('club');

  -- Purge.
  perform pg_temp.svc();
  perform public.purge_integrations();
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.github_deliveries where received_at < now() - interval '1 day'), 'old deliveries are purged');
end $$;

-- ===================================== 8. the wake-up and the cron job
do $$
declare
  def text;
begin
  def := pg_get_functiondef('public.wake_feed_fetch()'::regprocedure);
  perform pg_temp.expect(def like '%wecord_functions_url%' and def like '%wecord_dispatch_secret%' and def like '%/feed-fetch%', 'it wakes feed-fetch with the Vault secrets');
  perform pg_temp.expect(pg_temp.state('select public.wake_feed_fetch()') = 'ok' and pg_temp.state('select public.wake_feed_fetch_if_due()') = 'ok', 'and does nothing where there is no Vault');
  if to_regclass('cron.job') is not null then
    perform pg_temp.expect(exists (select 1 from cron.job where jobname = 'wecord-feed-fetch' and schedule = '*/5 * * * *')
      and exists (select 1 from cron.job where jobname = 'wecord-integrations-purge'), 'the cron jobs are set');
  end if;
end $$;

-- ===================================== 9. the account
do $$
declare
  exported jsonb;
  feed_id uuid;
begin
  perform pg_temp.root();
  exported := public.export_my_integrations(pg_temp.i('bob'));
  perform pg_temp.expect(jsonb_array_length(exported -> 'feeds') >= 1 and jsonb_array_length(exported -> 'github') >= 1
    and exported::text not like '%secret%' and exported::text not like '%token%', 'the export has my feeds and connections and no secret');
  perform pg_temp.expect(exported -> 'feeds' -> 0 ->> 'address' like 'https://%' and exported -> 'github' -> 0 ->> 'circle' = 'Hike Club', 'with where they are');
  perform pg_temp.expect(public.export_my_integrations(pg_temp.i('cat')) = jsonb_build_object('feeds', '[]'::jsonb, 'github', '[]'::jsonb), 'a stranger''s export is empty');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.export_my_integrations(%L)', pg_temp.i('bob'))) = '42501', 'clients cannot call the export');
  perform pg_temp.root();
  perform pg_temp.expect(has_function_privilege('service_role', 'public.export_my_integrations(uuid)', 'execute'), 'the data-export function can');

  -- Bob made feed2 on news? No: ada did. Bob made several on plaza.
  perform pg_temp.expect(exists (select 1 from public.channel_feeds f join public.circle_webhooks w on w.id = f.webhook_id where w.created_by = pg_temp.i('bob') and f.enabled), 'bob has running feeds');
  update public.profiles set deleted_at = now() where id = pg_temp.i('bob');
  perform pg_temp.expect(not exists (select 1 from public.channel_feeds f join public.circle_webhooks w on w.id = f.webhook_id where w.created_by = pg_temp.i('bob'))
    and not exists (select 1 from public.channel_feeds f join public.circle_webhooks w on w.id = f.webhook_id where f.enabled and w.created_by is null)
    and exists (select 1 from public.channel_feeds f where f.paused_reason = 'creator_gone'), 'deleting an account pauses what it posted and takes the name off');
  perform pg_temp.expect(exists (select 1 from public.channel_github_hooks where paused_reason = 'creator_gone' and not enabled), 'GitHub connections too');
  perform pg_temp.expect(exists (select 1 from public.channel_feeds f where f.paused_reason = 'creator_gone' and f.url like '%blog.example.com%'), 'and the feed stays with its circle');
  select f.id into feed_id from public.channel_feeds f where f.paused_reason = 'creator_gone' limit 1;
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_channel_feed_enabled(feed_id, true);
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.channel_feeds f join public.circle_webhooks w on w.id = f.webhook_id where w.created_by = pg_temp.i('ada') and f.enabled and f.paused_reason is null), 'an owner can take one over');

  -- Deleting a channel takes its feeds and connections.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.delete_circle_channel(pg_temp.i('news'));
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.channel_feeds where channel_id = pg_temp.i('news'))
    and not exists (select 1 from public.circle_webhooks where channel_id = pg_temp.i('news')), 'deleting a channel deletes them');
end $$;

\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'integrations: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
