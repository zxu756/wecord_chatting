-- Behaviour checks for workflow automation (D9): migrations 202610281300 to
-- 202610281340. Run by test/supabase/workflows_test.dart against the local
-- database: it applies the migrations in a transaction, plays people through
-- them, and rolls everything back. Run from the repository root.
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
\i supabase/migrations/202610281300_workflows_schema.sql
\i supabase/migrations/202610281310_workflows_rpcs.sql
\i supabase/migrations/202610281320_workflows_events.sql
\i supabase/migrations/202610281330_workflows_run.sql
\i supabase/migrations/202610281340_workflows_account.sql
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

-- Back to the table owner, signed out.
create function pg_temp.root() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
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

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create function pg_temp.i(n text) returns uuid language sql as $$ select id from pg_temp.ids where name = n $$;
grant execute on function pg_temp.i(text) to public;
grant execute on all functions in schema pg_temp to public;

-- ------------------------------------------------------------------ cast
-- ada runs a group chat (g1) and a circle (club); bob, cat, dan and fay are in
-- both, gus and the others join later; eve is in neither. root is nobody.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@d9.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'fay'),(7,'gus'),(8,'hal'),
  (9,'ivy'),(10,'jon'),(11,'kim'),(12,'lou'),(13,'mia'),(14,'nia'),(15,'oli'),(16,'root')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_d9', initcap(name)
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'fay'),(7,'gus'),(8,'hal'),
  (9,'ivy'),(10,'jon'),(11,'kim'),(12,'lou'),(13,'mia'),(14,'nia'),(15,'oli'),(16,'root')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'fay'),(7,'gus'),(8,'hal'),
  (9,'ivy'),(10,'jon'),(11,'kim'),(12,'lou'),(13,'mia'),(14,'nia'),(15,'oli'),(16,'root')) v(n, name);

insert into pg_temp.ids values ('g1', gen_random_uuid());
insert into public.conversations (id, type, title) values (pg_temp.i('g1'), 'group', 'Hike crew');
insert into public.conversation_members (conversation_id, user_id, role)
values
  (pg_temp.i('g1'), pg_temp.i('ada'), 'owner'),
  (pg_temp.i('g1'), pg_temp.i('bob'), 'member'),
  (pg_temp.i('g1'), pg_temp.i('cat'), 'member'),
  (pg_temp.i('g1'), pg_temp.i('dan'), 'member'),
  (pg_temp.i('g1'), pg_temp.i('fay'), 'member');
-- ada is a friend of most; jon is one she blocked, hal and ivy are strangers.
insert into public.friendships (user_low_id, user_high_id)
select least(pg_temp.i('ada'), pg_temp.i(n)), greatest(pg_temp.i('ada'), pg_temp.i(n))
from (values ('bob'),('cat'),('dan'),('fay'),('gus'),('jon')) v(n);

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'club', public.create_circle('Hike Club', array[
  pg_temp.i('bob'), pg_temp.i('cat'), pg_temp.i('dan'), pg_temp.i('fay')]);
insert into pg_temp.ids select 'plaza', public.create_circle_channel(pg_temp.i('club'), 'plaza', null, 'text');
insert into pg_temp.ids select 'rules', public.create_circle_channel(pg_temp.i('club'), 'rules', null, 'text');
insert into pg_temp.ids select 'hall', public.create_circle_channel(pg_temp.i('club'), 'hall', null, 'voice');
-- Newbie is a plain role; Helper can moderate; Greeter can manage the circle
-- but not roles.
insert into pg_temp.ids select 'newbie', public.create_circle_role(pg_temp.i('club'), 'Newbie', null, 3, false);
insert into pg_temp.ids select 'helper', public.create_circle_role(pg_temp.i('club'), 'Helper', null, 4, false);
insert into pg_temp.ids select 'greeter', public.create_circle_role(pg_temp.i('club'), 'Greeter', null, 1048576, false);
insert into pg_temp.ids select 'fan', public.create_circle_role(pg_temp.i('club'), 'Fan', null, 3, false);
select public.set_member_roles(pg_temp.i('club'), pg_temp.i('cat'), array[pg_temp.i('greeter')]);
select pg_temp.root();

insert into pg_temp.ids
select 'plazac', cc.conversation_id from public.circle_channels cc where cc.id = pg_temp.i('plaza');
insert into pg_temp.ids
select 'rulesc', cc.conversation_id from public.circle_channels cc where cc.id = pg_temp.i('rules');

grant execute on all functions in schema pg_temp to public;

-- Saves a workflow as [who] and answers it.
create function pg_temp.save(who text, def jsonb) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.act(pg_temp.i(who));
  r := public.save_workflow(def);
  perform pg_temp.root();
  return r;
exception when others then
  perform pg_temp.root();
  raise;
end $$;

-- The error code a save raises, or 'ok'.
create function pg_temp.save_err(who text, def jsonb) returns text language plpgsql as $$
begin
  perform pg_temp.act(pg_temp.i(who));
  begin
    perform public.save_workflow(def);
    perform pg_temp.root();
    return 'ok';
  exception when others then
    perform pg_temp.root();
    return sqlerrm;
  end;
end $$;

create function pg_temp.tick() returns integer language plpgsql as $$
begin
  perform pg_temp.root();
  return public.run_workflow_tick();
end $$;

-- A circle workflow definition.
create function pg_temp.cdef(wname text, kind text, config jsonb, actions jsonb) returns jsonb
language sql as $$
  select jsonb_build_object('circle_id', pg_temp.i('club'), 'name', wname,
    'trigger', jsonb_build_object('kind', kind, 'config', config), 'actions', actions)
$$;

-- A group workflow definition.
create function pg_temp.gdef(wname text, kind text, config jsonb, actions jsonb) returns jsonb
language sql as $$
  select jsonb_build_object('conversation_id', pg_temp.i('g1'), 'name', wname,
    'trigger', jsonb_build_object('kind', kind, 'config', config), 'actions', actions)
$$;

create function pg_temp.say(who text, conv uuid, body text) returns uuid language plpgsql as $$
declare m uuid;
begin
  perform pg_temp.act(pg_temp.i(who));
  m := public.send_text_message(conv, body);
  perform pg_temp.root();
  return m;
end $$;

-- The last run of a workflow.
create function pg_temp.last_run(wf uuid) returns public.workflow_runs language sql as $$
  select r from public.workflow_runs r where r.workflow_id = wf order by r.created_at desc, r.id desc limit 1
$$;

create function pg_temp.new_member(circle text, who text) returns void language plpgsql as $$
begin
  perform pg_temp.root();
  insert into public.circle_members (circle_id, user_id, role) values (pg_temp.i(circle), pg_temp.i(who), 'member');
end $$;

grant execute on all functions in schema pg_temp to public;

insert into pg_temp.ids values ('quiz', gen_random_uuid());
create function pg_temp.fields() returns jsonb language sql as $$
  select jsonb_build_array(
    jsonb_build_object('id', 'did', 'type', 'long_text', 'label', 'What did you do this week?', 'required', true))
$$;
grant execute on all functions in schema pg_temp to public;

-- A form in the plaza, one in the rules channel and one in the group, and an
-- anonymous one in the plaza.
select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'form_plaza', (public.create_form(pg_temp.i('plazac'), 'Weekly report', 'Short', pg_temp.fields(), '{"one_per_person": false}'::jsonb) ->> 'form_id')::uuid;
insert into pg_temp.ids select 'form_anon', (public.create_form(pg_temp.i('plazac'), 'Secret poll', null, pg_temp.fields(), '{"anonymous": true}'::jsonb) ->> 'form_id')::uuid;
insert into pg_temp.ids select 'form_group', (public.create_form(pg_temp.i('g1'), 'Trip sign-up', null, pg_temp.fields(), '{"one_per_person": false}'::jsonb) ->> 'form_id')::uuid;
select pg_temp.root();

-- ================================== 1. what is closed, what is not touched
do $$
declare
  def text;
begin
  perform pg_temp.expect(not exists (
    select 1 from information_schema.role_table_grants
    where table_name in ('workflows', 'workflow_runs', 'workflow_push_queue')
      and grantee in ('anon', 'authenticated')
  ), 'the workflow tables are closed to clients');
  def := pg_get_functiondef('public.run_later_dispatch()'::regprocedure);
  perform pg_temp.expect(def not like '%workflow%', 'run_later_dispatch is not touched');
  perform pg_temp.expect(not has_function_privilege('authenticated', 'public.workflow_execute(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.run_workflow_tick(integer)', 'execute')
    and not has_function_privilege('authenticated', 'public.workflow_enqueue(uuid, text, uuid, jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'public.claim_workflow_message_pushes()', 'execute')
    and not has_function_privilege('authenticated', 'public.export_my_workflows(uuid)', 'execute'),
    'clients cannot run the engine, claim pushes or export');
  perform pg_temp.expect(has_function_privilege('authenticated', 'public.save_workflow(jsonb)', 'execute')
    and has_function_privilege('authenticated', 'public.list_workflows(uuid, uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.set_workflow_enabled(uuid, boolean)', 'execute')
    and has_function_privilege('authenticated', 'public.delete_workflow(uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.list_workflow_runs(uuid, integer, timestamptz)', 'execute'),
    'clients can use the functions of part 2');
  perform pg_temp.expect(has_function_privilege('service_role', 'public.claim_workflow_message_pushes()', 'execute')
    and has_function_privilege('service_role', 'public.export_my_workflows(uuid)', 'execute'),
    'the Edge Functions (service role) can claim pushes and export');
  perform pg_temp.expect((
    select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'workflow_user_can_manage', 'workflow_normalize_trigger', 'workflow_normalize_actions',
      'workflow_do_action', 'workflow_execute', 'run_workflow_tick', 'save_workflow',
      'list_workflows', 'workflow_enqueue', 'claim_workflow_message_pushes')
      and (not p.prosecdef or not exists (
        select 1 from unnest(p.proconfig) c where c = 'search_path=public'))
  ) = 0, 'every function is security definer with a fixed search path');
end $$;

-- ====================================================== 2. who can manage
do $$
declare
  club uuid := pg_temp.i('club');
  g1 uuid := pg_temp.i('g1');
  r jsonb;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  r := public.list_workflows(club, null);
  perform pg_temp.expect((r ->> 'can_manage')::boolean and jsonb_array_length(r -> 'workflows') = 0
    and (r -> 'limits' ->> 'max_per_circle')::integer = 20, 'the owner lists the circle''s workflows, with the limits');
  perform pg_temp.expect(pg_temp.state(format('select public.list_workflows(null, %L)', g1)) = 'ok', 'and the group owner the group''s');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.list_workflows(%L, null)', club)) = 'ok', 'a member with manage_circle may');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.list_workflows(%L, null)', club)) = '42501', 'a plain circle member may not');
  perform pg_temp.expect(pg_temp.state(format('select public.list_workflows(null, %L)', g1)) = '42501', 'nor a plain group member');
  perform pg_temp.expect(pg_temp.state(format('select public.get_workflow_options(%L, null)', club)) = '42501', 'nor see the editor''s options');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.list_workflows(%L, null)', club)) = '42501', 'a stranger may not');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select public.list_workflows(%L, null)', club)) = '42501', 'nobody signed in may not');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.msg('select public.list_workflows(null, null)') = 'workflow_scope_invalid', 'a scope is needed');
  perform pg_temp.expect(pg_temp.msg(format('select public.list_workflows(%L, %L)', club, g1)) = 'workflow_scope_invalid', 'and only one');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.save_err('bob', pg_temp.gdef('x', 'member_joined', '{}', '[{"type":"send_message","text":"hi"}]')) = 'workflow_not_allowed', 'a member cannot save a group workflow');
  perform pg_temp.expect(pg_temp.save_err('bob', pg_temp.cdef('x', 'member_joined', '{}', '[{"type":"send_message","text":"hi"}]')) = 'workflow_not_allowed', 'nor a circle workflow');

  -- The options list what the pickers need, and not the powerful roles.
  perform pg_temp.act(pg_temp.i('ada'));
  r := public.get_workflow_options(club, null);
  perform pg_temp.expect(jsonb_array_length(r -> 'channels') >= 3 and not exists (select 1 from jsonb_array_elements(r -> 'channels') x where x ->> 'kind' = 'voice'),'the options list the text channels');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(r -> 'roles') x where x ->> 'name' = 'Newbie')
    and not exists (select 1 from jsonb_array_elements(r -> 'roles') x where x ->> 'name' in ('Helper', 'Greeter')),
    'roles that can moderate or manage are not offered');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(r -> 'forms') x where x ->> 'title' = 'Weekly report')
    and not exists (select 1 from jsonb_array_elements(r -> 'forms') x where x ->> 'title' = 'Trip sign-up'),
    'forms come from the scope only');
  perform pg_temp.root();
end $$;

-- ======================================================== 3. what is refused
do $$
declare
  club uuid := pg_temp.i('club');
  plaza text := pg_temp.i('plaza')::text;
  ok_send jsonb := jsonb_build_array(jsonb_build_object('type', 'send_message', 'channel_id', pg_temp.i('plaza'), 'text', 'Hi'));
begin
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('', 'member_joined', '{}', ok_send)) = 'workflow_text_invalid', 'a name is needed');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef(repeat('n', 61), 'member_joined', '{}', ok_send)) = 'workflow_text_invalid', 'at most 60 characters');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'nonsense', '{}', ok_send)) = 'workflow_trigger_invalid', 'an unknown trigger');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'member_joined', '{}', '[]')) = 'workflow_actions_invalid', 'at least one action');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'member_joined', '{}', (select jsonb_agg(a) from generate_series(1, 6), lateral (select ok_send -> 0 as a) q))) = 'workflow_actions_invalid', 'at most five actions');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'member_joined', '{}', '[{"type":"explode"}]')) = 'workflow_action_invalid', 'an unknown action');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'member_joined', '{}', '[{"type":"send_message","text":"hi"}]')) = 'workflow_channel_invalid', 'a circle action needs a channel (a join has no "here")');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'member_joined', '{}', jsonb_build_array(jsonb_build_object('type', 'send_message', 'channel_id', gen_random_uuid(), 'text', 'Hi')))) = 'workflow_channel_invalid', 'a channel of another circle');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'member_joined', '{}', jsonb_build_array(jsonb_build_object('type', 'send_message', 'channel_id', pg_temp.i('hall'), 'text', 'Hi')))) = 'workflow_channel_invalid', 'a voice channel');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'member_joined', '{}', jsonb_build_array(jsonb_build_object('type', 'send_message', 'channel_id', pg_temp.i('plaza'), 'text', repeat('a', 501))))) = 'workflow_text_invalid', 'a text over 500 characters');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'member_joined', '{}', jsonb_build_array(jsonb_build_object('type', 'send_message', 'channel_id', pg_temp.i('plaza'), 'text', E'hi‮dog')))) = 'workflow_text_invalid', 'a text that reorders letters');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'member_joined', '{}', jsonb_build_array(jsonb_build_object('type', 'add_role', 'role_id', pg_temp.i('helper'))))) = 'workflow_role_invalid', 'a role that can moderate cannot be handed out');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'member_joined', '{}', jsonb_build_array(jsonb_build_object('type', 'add_role', 'role_id', pg_temp.i('greeter'))))) = 'workflow_role_invalid', 'nor one that manages the circle');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'member_joined', '{}', jsonb_build_array(jsonb_build_object('type', 'add_role', 'role_id', gen_random_uuid())))) = 'workflow_role_invalid', 'nor one that does not exist');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.gdef('x', 'member_joined', '{}', jsonb_build_array(jsonb_build_object('type', 'add_role', 'role_id', pg_temp.i('newbie'))))) = 'workflow_role_invalid', 'a group has no roles');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'schedule', '{"recurrence":"daily","time":"09:00"}', '[{"type":"send_dm","text":"hi"}]')) = 'workflow_needs_member', 'a direct message needs a member, a clock has none');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'schedule', '{"recurrence":"daily","time":"09:00"}', jsonb_build_array(jsonb_build_object('type', 'send_message', 'channel_id', pg_temp.i('plaza'), 'text', 'Hi {member}')))) = 'workflow_needs_member', 'nor does {member} mean anything');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'member_joined', '{}', ('[{"type":"create_task","from_message":true,"channel_id":"' || plaza || '"}]')::jsonb)) = 'workflow_needs_message', 'a task from a message needs a message');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'member_joined', '{}', jsonb_build_array(jsonb_build_object('type', 'send_form', 'channel_id', pg_temp.i('plaza'), 'form_id', pg_temp.i('form_group'))))) = 'workflow_form_invalid', 'a form of another chat');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'form_submitted', jsonb_build_object('form_id', pg_temp.i('form_anon')), ok_send)) = 'workflow_form_anonymous', 'nobody listens to an anonymous form');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'form_submitted', jsonb_build_object('form_id', pg_temp.i('form_group')), ok_send)) = 'workflow_form_invalid', 'nor to a form of another chat');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'schedule', '{"recurrence":"daily","time":"25:00"}', ok_send)) = 'workflow_trigger_invalid', 'a time that is no time');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'schedule', '{"recurrence":"weekly","time":"09:00"}', ok_send)) = 'workflow_trigger_invalid', 'a weekly rule needs a weekday');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'schedule', '{"recurrence":"daily","time":"09:00","until":"2020-01-01"}', ok_send)) = 'workflow_trigger_invalid', 'an end date in the past');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'keyword', '{"words":[]}', ok_send)) = 'workflow_trigger_invalid', 'a keyword rule needs words');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'keyword', jsonb_build_object('words', (select jsonb_agg('w' || n) from generate_series(1, 11) n)), ok_send)) = 'workflow_trigger_invalid', 'at most ten words');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'reaction', '{"emoji":""}', ok_send)) = 'workflow_trigger_invalid', 'a reaction rule needs an emoji');
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.cdef('x', 'reaction', jsonb_build_object('emoji', 'x', 'channel_id', gen_random_uuid()), ok_send)) = 'workflow_channel_invalid', 'and a channel of this circle');
  perform pg_temp.expect(pg_temp.save_err('ada', jsonb_build_object('name', 'x', 'trigger', jsonb_build_object('kind', 'member_joined'), 'actions', ok_send)) = 'workflow_not_allowed' or pg_temp.save_err('ada', jsonb_build_object('name', 'x', 'trigger', jsonb_build_object('kind', 'member_joined'), 'actions', ok_send)) = 'workflow_scope_invalid', 'a workflow has a scope');
  perform pg_temp.expect(not exists (select 1 from public.workflows), 'nothing was saved by all of these');
end $$;

-- ===================================================== 4. a member joins
do $$
declare
  club uuid := pg_temp.i('club');
  plazac uuid := pg_temp.i('plazac');
  wf jsonb;
  wid uuid;
  run public.workflow_runs;
  dm uuid;
  pushed integer;
  who text;
begin
  wf := pg_temp.save('ada', pg_temp.cdef('Welcome', 'member_joined', '{}', jsonb_build_array(
    jsonb_build_object('type', 'send_message', 'channel_id', pg_temp.i('plaza'), 'text', 'Welcome {member} to {place}!'),
    jsonb_build_object('type', 'add_role', 'role_id', pg_temp.i('newbie')),
    jsonb_build_object('type', 'send_dm', 'text', 'Hi {member}, glad you are here'))));
  wid := (wf ->> 'id')::uuid;
  insert into pg_temp.ids values ('w_join', wid);
  perform pg_temp.expect(wf ->> 'name' = 'Welcome' and (wf ->> 'enabled')::boolean and (wf ->> 'created_by_me')::boolean, 'a workflow is saved, on, and runs as its saver');
  perform pg_temp.expect(exists (select 1 from public.circle_audit_log where circle_id = club and action = 'workflow_create' and target_label = 'Welcome'), 'the circle''s audit log says who made it');

  -- Ada blocked jon; gus is her friend, hal a stranger.
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('ada'), pg_temp.i('jon'));
  perform pg_temp.new_member('club', 'gus');
  perform pg_temp.new_member('club', 'hal');
  perform pg_temp.new_member('club', 'jon');
  perform pg_temp.expect((select count(*) from public.workflow_runs where workflow_id = wid and status = 'queued') = 3, 'each join is queued, nothing is done in the joiner''s transaction');
  perform pg_temp.expect(not exists (select 1 from public.messages where conversation_id = plazac and body like 'Welcome%'), 'and nothing is sent yet');

  perform pg_temp.expect(pg_temp.tick() = 3, 'the tick takes the three runs');
  perform pg_temp.expect(exists (select 1 from public.messages m where m.conversation_id = plazac and m.body = 'Welcome Gus to Hike Club!' and m.sender_id = pg_temp.i('ada') and m.auto_reply), 'the welcome is said as the creator, marked automatic, with the name and the circle filled in');
  perform pg_temp.expect(exists (select 1 from public.circle_member_roles where circle_id = club and user_id = pg_temp.i('gus') and role_id = pg_temp.i('newbie'))
    and exists (select 1 from public.circle_member_roles where circle_id = club and user_id = pg_temp.i('hal') and role_id = pg_temp.i('newbie')), 'the role is given');
  select cm.conversation_id into dm from public.conversation_members cm
    join public.conversation_members o on o.conversation_id = cm.conversation_id and o.user_id = pg_temp.i('gus')
    join public.conversations c on c.id = cm.conversation_id and c.type = 'direct'
    where cm.user_id = pg_temp.i('ada');
  perform pg_temp.expect(dm is not null and exists (select 1 from public.messages where conversation_id = dm and body = 'Hi Gus, glad you are here'), 'a friend gets the direct message');
  run := (select r from public.workflow_runs r where r.workflow_id = wid and r.actor_id = pg_temp.i('hal'));
  perform pg_temp.expect(run.status = 'succeeded' and run.results -> 2 ->> 'detail' = 'not_friends' and run.results -> 2 ->> 'status' = 'skipped', 'a stranger is not messaged: the action is skipped, never forced');
  run := (select r from public.workflow_runs r where r.workflow_id = wid and r.actor_id = pg_temp.i('jon'));
  perform pg_temp.expect(run.results -> 2 ->> 'detail' = 'blocked', 'and a blocked person is not messaged either');
  perform pg_temp.expect(not exists (select 1 from public.conversation_members cm join public.conversation_members o on o.conversation_id = cm.conversation_id and o.user_id = pg_temp.i('hal') where cm.user_id = pg_temp.i('ada') and exists (select 1 from public.conversations c where c.id = cm.conversation_id and c.type = 'direct')), 'no direct chat was made with the stranger');
  perform pg_temp.expect(current_setting('request.jwt.claim.sub', true) = '' and coalesce(current_setting('wecord.workflow_run', true), '') in ('', 'off'), 'the run leaves the session as it found it');

  perform pg_temp.expect((select count(*) from public.claim_workflow_message_pushes()) = 4, 'the four messages sent wait for their push, and the claim hands them out');
  perform pg_temp.expect((select count(*) from public.claim_workflow_message_pushes()) = 0, 'once');
  perform pg_temp.expect((select last_run_at is not null and fail_streak = 0 from public.workflows where id = wid), 'the workflow knows it ran');

  -- A client cannot mark its own message as automatic.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.refused(format('insert into public.messages (conversation_id, sender_id, body, auto_reply) values (%L, %L, ''x'', true)', plazac, pg_temp.i('bob'))), 'a client cannot make an automatic message');
  perform pg_temp.root();
end $$;

-- ===================================== 5. a reaction makes a task (and G6)
do $$
declare
  club uuid := pg_temp.i('club');
  plazac uuid := pg_temp.i('plazac');
  rulesc uuid := pg_temp.i('rulesc');
  wid uuid;
  m1 uuid;
  m2 uuid;
  m3 uuid;
  m4 uuid;
  run public.workflow_runs;
begin
  wid := (pg_temp.save('ada', pg_temp.cdef('Reactions to tasks', 'reaction',
    jsonb_build_object('emoji', '✅', 'channel_id', pg_temp.i('plaza')),
    '[{"type":"create_task","from_message":true}]')) ->> 'id')::uuid;
  insert into pg_temp.ids values ('w_react', wid);

  m1 := pg_temp.say('bob', plazac, 'Please fix the roof');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.toggle_message_reaction(m1, '✅');
  perform pg_temp.act(pg_temp.i('dan'));
  perform public.toggle_message_reaction(m1, '✅');
  perform pg_temp.act(pg_temp.i('dan'));
  perform public.toggle_message_reaction(m1, '👍');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.workflow_runs where workflow_id = wid) = 1, 'two check marks on one message are one run, another emoji none');
  perform pg_temp.tick();
  perform pg_temp.expect(exists (select 1 from public.task_items i where i.source_message_id = m1 and i.title = 'Please fix the roof'), 'the task is made from the message');
  run := pg_temp.last_run(wid);
  perform pg_temp.expect(run.status = 'succeeded' and run.actor_id = pg_temp.i('cat'), 'and the log says who reacted');

  -- A reaction in another channel is not heard.
  m2 := pg_temp.say('bob', rulesc, 'Be nice');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.toggle_message_reaction(m2, '✅');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.workflow_runs where workflow_id = wid) = 1, 'a check mark in another channel starts nothing');

  -- Private-chat limits (G6) keep what is said in the chat.
  update public.conversations set restrict_sharing = true where id = plazac;
  m3 := pg_temp.say('bob', plazac, 'A secret plan');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.toggle_message_reaction(m3, '✅');
  perform pg_temp.root();
  perform pg_temp.tick();
  run := pg_temp.last_run(wid);
  perform pg_temp.expect(run.results -> 0 ->> 'detail' = 'chat_restricted' and not exists (select 1 from public.task_items i where i.source_message_id = m3), 'a chat with private-chat limits (G6) makes no task from its messages');
  update public.conversations set restrict_sharing = false where id = plazac;

  -- Disappearing messages are not copied into a task either.
  update public.conversations set disappear_after_seconds = 86400 where id = plazac;
  m4 := pg_temp.say('bob', plazac, 'This will vanish');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.toggle_message_reaction(m4, '✅');
  perform pg_temp.root();
  perform pg_temp.tick();
  perform pg_temp.expect(not exists (select 1 from public.task_items i where i.source_message_id = m4), 'nor a disappearing message');
  update public.conversations set disappear_after_seconds = null where id = plazac;
end $$;

-- ================================= 6. a keyword answers, and does not loop
do $$
declare
  plazac uuid := pg_temp.i('plazac');
  wid uuid;
  m uuid;
  replies integer;
begin
  wid := (pg_temp.save('ada', pg_temp.cdef('Help desk', 'keyword', '{"words":["Help", "  HELP  ", "need support"]}',
    '[{"type":"send_message","text":"We can help, {member}."}]')) ->> 'id')::uuid;
  insert into pg_temp.ids values ('w_kw', wid);
  perform pg_temp.expect((select trigger_config -> 'words' from public.workflows where id = wid) = '["help", "need support"]'::jsonb, 'words are lowered, trimmed and made distinct');

  m := pg_temp.say('bob', plazac, 'I need HELP with the map');
  perform pg_temp.say('bob', plazac, 'Nice weather');
  perform pg_temp.expect((select count(*) from public.workflow_runs where workflow_id = wid) = 1, 'a message with a word starts one run, another message none');
  perform pg_temp.tick();
  replies := (select count(*) from public.messages where conversation_id = plazac and body = 'We can help, Bob.' and auto_reply);
  perform pg_temp.expect(replies = 1, 'the answer is sent where it was asked');
  perform pg_temp.tick();
  perform pg_temp.tick();
  perform pg_temp.expect((select count(*) from public.workflow_runs where workflow_id = wid) = 1, 'the answer has the word too, but it starts nothing: no loop');

  -- One member cannot use up the day.
  for n in 1..14 loop
    perform pg_temp.say('bob', plazac, 'help ' || n);
  end loop;
  perform pg_temp.expect((select count(*) from public.workflow_runs where workflow_id = wid and actor_id = pg_temp.i('bob')) = 10, 'one member starts at most ten runs a day in one workflow');
  perform pg_temp.say('dan', plazac, 'help from dan');
  perform pg_temp.expect((select count(*) from public.workflow_runs where workflow_id = wid and actor_id = pg_temp.i('dan')) = 1, 'and the others still can');
  perform pg_temp.tick();
  perform pg_temp.tick();
  perform pg_temp.tick();
end $$;

-- ================================================ 7. the clock (D4 rule)
do $$
declare
  plazac uuid := pg_temp.i('plazac');
  wid uuid;
  w public.workflows;
  forms_before integer;
  forms_after integer;
  run public.workflow_runs;
  due timestamptz;
begin
  wid := (pg_temp.save('ada', pg_temp.cdef('Friday report', 'schedule',
    '{"recurrence":"weekly","day":5,"time":"09:00","zone":"Asia/Shanghai"}',
    jsonb_build_array(
      jsonb_build_object('type', 'send_message', 'channel_id', pg_temp.i('plaza'), 'text', 'Weekly report for {date}'),
      jsonb_build_object('type', 'send_form', 'channel_id', pg_temp.i('plaza'), 'form_id', pg_temp.i('form_plaza'), 'deadline_days', 3)))) ->> 'id')::uuid;
  insert into pg_temp.ids values ('w_sched', wid);
  select * into w from public.workflows where id = wid;
  perform pg_temp.expect(w.next_run_at > now() and w.next_run_at = public.recurrence_next('weekly', 5, '09:00', 'Asia/Shanghai', now(), null), 'the next time comes from the D4 rule');

  forms_before := (select count(*) from public.forms where conversation_id = plazac);
  update public.workflows set next_run_at = now() - interval '10 minutes' where id = wid;
  perform pg_temp.tick();
  forms_after := (select count(*) from public.forms where conversation_id = plazac);
  run := pg_temp.last_run(wid);
  perform pg_temp.expect(run.status = 'succeeded' and run.actor_id is null, 'a due schedule runs, for nobody in particular');
  perform pg_temp.expect(exists (select 1 from public.messages where conversation_id = plazac and body = 'Weekly report for ' || to_char(now() at time zone 'Asia/Shanghai', 'YYYY-MM-DD')), 'it posts the message with the date');
  perform pg_temp.expect(forms_after = forms_before + 1 and exists (
    select 1 from public.forms f where f.conversation_id = plazac and f.title like 'Weekly report · %' and f.settings ? 'deadline' and f.creator_id = pg_temp.i('ada')), 'and a fresh copy of the form, with a deadline, made by the creator');
  perform pg_temp.expect((select next_run_at > now() from public.workflows where id = wid), 'the next time moves on');

  -- A run that is hours late is not run late: it is logged as missed.
  update public.workflows set next_run_at = now() - interval '5 hours' where id = wid;
  forms_before := (select count(*) from public.forms where conversation_id = plazac);
  perform pg_temp.tick();
  run := pg_temp.last_run(wid);
  perform pg_temp.expect(run.status = 'skipped' and run.skip_reason = 'missed' and (select count(*) from public.forms where conversation_id = plazac) = forms_before, 'a run more than two hours late is logged as missed, not run');

  -- Pause and resume.
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.set_workflow_enabled(wid, false);
  perform pg_temp.root();
  select * into w from public.workflows where id = wid;
  perform pg_temp.expect(not w.enabled and w.paused_reason = 'manual' and w.next_run_at is null, 'a manager can pause it');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.set_workflow_enabled(wid, true);
  perform pg_temp.root();
  select * into w from public.workflows where id = wid;
  perform pg_temp.expect(w.enabled and w.next_run_at > now() and w.created_by = pg_temp.i('cat'), 'and resume it: the one who resumes is the one it runs as');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_workflow_enabled(wid, true);
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.circle_audit_log where action = 'workflow_pause') and exists (select 1 from public.circle_audit_log where action = 'workflow_resume'), 'pausing and resuming are in the audit log');
  perform pg_temp.expect((select created_by = pg_temp.i('ada') from public.workflows where id = wid), 'ada resumed it, so it runs as her again');
end $$;

-- ============================================= 8. a form is answered (group)
do $$
declare
  g1 uuid := pg_temp.i('g1');
  wid uuid;
  form uuid := pg_temp.i('form_group');
begin
  wid := (pg_temp.save('ada', pg_temp.gdef('Thank signers', 'form_submitted', jsonb_build_object('form_id', form),
    '[{"type":"send_message","text":"Thanks {member}, got your answer."},{"type":"create_task","title":"Check the answer of {member}"}]')) ->> 'id')::uuid;
  insert into pg_temp.ids values ('w_form', wid);
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.submit_form_response(form, '{"did":"hiked"}'::jsonb);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.workflow_runs where workflow_id = wid) = 1, 'an answer queues a run');
  perform pg_temp.tick();
  perform pg_temp.expect(exists (select 1 from public.messages where conversation_id = g1 and body = 'Thanks Bob, got your answer.' and sender_id = pg_temp.i('ada') and auto_reply), 'the thanks is said in the group');
  perform pg_temp.expect(exists (select 1 from public.task_items i join public.task_lists l on l.id = i.list_id where l.conversation_id = g1 and i.title = 'Check the answer of Bob'), 'and the task is made');
  perform pg_temp.expect((pg_temp.last_run(wid)).status = 'succeeded', 'the run succeeded');
end $$;

-- ================================== 9. the creator loses the right to manage
do $$
declare
  g1 uuid := pg_temp.i('g1');
  club uuid := pg_temp.i('club');
  wid uuid;
  w public.workflows;
  run public.workflow_runs;
  seen integer;
begin
  -- A group: bob is made an admin, saves a workflow, and is made a member again.
  update public.conversation_members set role = 'admin' where conversation_id = g1 and user_id = pg_temp.i('bob');
  wid := (pg_temp.save('bob', pg_temp.gdef('Greet newcomers', 'member_joined', '{}',
    '[{"type":"send_message","text":"Hello {member}, welcome to {place}"}]')) ->> 'id')::uuid;
  insert into pg_temp.ids values ('w_bob', wid);
  perform pg_temp.expect((select created_by = pg_temp.i('bob') from public.workflows where id = wid), 'an admin can make a group workflow');
  update public.conversation_members set role = 'member' where conversation_id = g1 and user_id = pg_temp.i('bob');
  seen := (select count(*) from public.messages where conversation_id = g1 and body like 'Hello %');
  insert into public.conversation_members (conversation_id, user_id, role) values (g1, pg_temp.i('hal'), 'member');
  perform pg_temp.expect((select count(*) from public.workflow_runs where workflow_id = wid) = 1, 'a join in the group is queued');
  perform pg_temp.tick();
  select * into w from public.workflows where id = wid;
  run := pg_temp.last_run(wid);
  perform pg_temp.expect(not w.enabled and w.paused_reason = 'creator_lost_permission' and run.status = 'skipped' and run.skip_reason = 'creator_lost_permission', 'when the creator is no longer an admin the workflow pauses itself');
  perform pg_temp.expect((select count(*) from public.messages where conversation_id = g1 and body like 'Hello %') = seen, 'and says nothing');

  -- ada takes it over.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_workflow_enabled(wid, true);
  perform pg_temp.root();
  insert into public.conversation_members (conversation_id, user_id, role) values (g1, pg_temp.i('ivy'), 'member');
  perform pg_temp.tick();
  perform pg_temp.expect(exists (select 1 from public.messages where conversation_id = g1 and body = 'Hello Ivy, welcome to Hike crew' and sender_id = pg_temp.i('ada')), 'whoever turns it back on becomes the one it runs as');

  -- A circle: cat has manage_circle through Greeter, but not manage_roles.
  wid := (pg_temp.save('cat', pg_temp.cdef('Roles for newcomers', 'member_joined', '{}',
    jsonb_build_array(jsonb_build_object('type', 'add_role', 'role_id', pg_temp.i('fan'))))) ->> 'id')::uuid;
  insert into pg_temp.ids values ('w_cat', wid);
  perform pg_temp.new_member('club', 'ivy');
  perform pg_temp.new_member('club', 'kim');
  perform pg_temp.tick();
  run := (select r from public.workflow_runs r where r.workflow_id = wid and r.actor_id = pg_temp.i('ivy'));
  perform pg_temp.expect(run.status = 'failed' and run.results -> 0 ->> 'status' = 'failed' and run.error is not null, 'a role cannot be given by someone who cannot manage roles: the action fails and the log says so');
  perform pg_temp.expect(not exists (select 1 from public.circle_member_roles where circle_id = club and user_id = pg_temp.i('ivy') and role_id = pg_temp.i('fan')), 'the workflow cannot do what its creator cannot');
  perform pg_temp.expect((select fail_streak = 2 and enabled from public.workflows where id = wid), 'two failures are counted');
  perform pg_temp.new_member('club', 'lou');
  perform pg_temp.new_member('club', 'mia');
  perform pg_temp.new_member('club', 'nia');
  perform pg_temp.tick();
  select * into w from public.workflows where id = wid;
  perform pg_temp.expect(not w.enabled and w.paused_reason = 'failures', 'five failures in a row pause the workflow');

  -- cat loses Greeter: a keyword workflow of hers pauses.
  wid := (pg_temp.save('cat', pg_temp.cdef('Cat keyword', 'keyword', '{"words":["pizza"]}',
    '[{"type":"send_message","text":"Pizza!"}]')) ->> 'id')::uuid;
  insert into pg_temp.ids values ('w_cat2', wid);
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_member_roles(club, pg_temp.i('cat'), array[]::uuid[]);
  perform pg_temp.root();
  perform pg_temp.say('dan', pg_temp.i('plazac'), 'Who wants pizza?');
  perform pg_temp.tick();
  select * into w from public.workflows where id = wid;
  perform pg_temp.expect(not w.enabled and w.paused_reason = 'creator_lost_permission' and not exists (select 1 from public.messages where body = 'Pizza!'), 'a circle manager who loses the right pauses their workflows too');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_workflow_enabled(%L, true)', wid)) = '42501', 'and they cannot turn it back on');
  perform pg_temp.root();
end $$;

-- ================================================ 10. K1 and the limits
do $$
declare
  club uuid := pg_temp.i('club');
  wid uuid := pg_temp.i('w_join');
  before integer;
  extra integer;
begin
  -- A suspended circle starts and runs nothing.
  before := (select count(*) from public.workflow_runs where workflow_id = wid);
  update public.circles set disabled_at = now(), disabled_mode = 'suspend' where id = club;
  -- Nobody can join a suspended circle; a row put in by hand shows the
  -- trigger would not queue it either.
  perform pg_temp.expect(pg_temp.refused(format('insert into public.circle_members (circle_id, user_id, role) values (%L, %L, ''member'')', club, pg_temp.i('oli'))), 'nobody joins a suspended circle');
  perform public.workflow_enqueue(wid, 'test:k1', pg_temp.i('oli'), '{}'::jsonb);
  perform pg_temp.expect((select count(*) from public.workflow_runs where workflow_id = wid) = before, 'a suspended circle (K1) queues nothing');
  update public.circles set disabled_at = null, disabled_mode = null where id = club;
  -- A run queued before the takedown is skipped.
  insert into public.workflow_runs (workflow_id, event_key, actor_id) values (wid, 'test:suspended', pg_temp.i('eve'));
  update public.circles set disabled_at = now(), disabled_mode = 'suspend' where id = club;
  perform pg_temp.tick();
  perform pg_temp.expect((select skip_reason from public.workflow_runs where workflow_id = wid and event_key = 'test:suspended') = 'circle_suspended', 'a run that waited through a takedown is skipped');
  update public.circles set disabled_at = null, disabled_mode = null where id = club;
  -- A delisted circle still works.
  update public.circles set disabled_at = now(), disabled_mode = 'delist' where id = club;
  insert into public.workflow_runs (workflow_id, event_key, actor_id) values (wid, 'test:delisted', pg_temp.i('eve'));
  perform pg_temp.tick();
  perform pg_temp.expect((select status from public.workflow_runs where workflow_id = wid and event_key = 'test:delisted') <> 'skipped', 'a delisted circle keeps its workflows');
  update public.circles set disabled_at = null, disabled_mode = null where id = club;

  -- The day's ceiling: 200 runs, then one "daily limit" line and no more.
  insert into public.workflow_runs (workflow_id, event_key, status, finished_at)
  select wid, 'fill:' || n, 'succeeded', now() from generate_series(1, 200) n;
  perform pg_temp.new_member('club', 'eve');
  extra := (select count(*) from public.workflow_runs where workflow_id = wid and skip_reason = 'daily_limit');
  perform pg_temp.expect(extra = 1, 'past 200 runs a day the log gets one daily-limit line');
  perform pg_temp.expect(not exists (select 1 from public.workflow_runs where workflow_id = wid and actor_id = pg_temp.i('eve') and event_key like 'join:%'), 'and the join is not queued');
  delete from public.circle_members where circle_id = club and user_id = pg_temp.i('eve');
  insert into public.circle_members (circle_id, user_id, role) values (club, pg_temp.i('eve'), 'member');
  perform pg_temp.expect((select count(*) from public.workflow_runs where workflow_id = wid and skip_reason = 'daily_limit') = 1, 'one line a day, not one per event');
  delete from public.workflow_runs where workflow_id = wid and event_key like 'fill:%';
  delete from public.circle_members where circle_id = club and user_id = pg_temp.i('eve');
end $$;

do $$
declare
  g1 uuid := pg_temp.i('g1');
  n integer;
begin
  -- A group holds five workflows: two exist.
  n := (select count(*) from public.workflows where conversation_id = g1);
  for k in 1..(5 - n) loop
    perform pg_temp.save('ada', pg_temp.gdef('Filler ' || k, 'member_joined', '{}', '[{"type":"send_message","text":"x"}]'));
  end loop;
  perform pg_temp.expect(pg_temp.save_err('ada', pg_temp.gdef('One too many', 'member_joined', '{}', '[{"type":"send_message","text":"x"}]')) = 'workflow_limit_reached', 'a group holds five workflows');
  -- Changing one is not creating one.
  perform pg_temp.expect(pg_temp.save_err('ada', jsonb_build_object('id', pg_temp.i('w_form'), 'name', 'Renamed',
    'trigger', jsonb_build_object('kind', 'form_submitted', 'config', jsonb_build_object('form_id', pg_temp.i('form_group'))),
    'actions', '[{"type":"send_message","text":"Thanks"}]'::jsonb)) = 'ok', 'a full group can still change a workflow');
  perform pg_temp.expect((select name = 'Renamed' from public.workflows where id = pg_temp.i('w_form')), 'and it is renamed');
end $$;

-- =========================================== 11. the log, pausing, deleting
do $$
declare
  club uuid := pg_temp.i('club');
  wid uuid := pg_temp.i('w_join');
  log jsonb;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  log := public.list_workflow_runs(wid, 5);
  perform pg_temp.expect(jsonb_array_length(log) = 5, 'the log lists runs, newest first, a page at a time');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(public.list_workflow_runs(wid, 100)) x where x -> 'actor' ->> 'name' = 'Gus' and x ->> 'status' = 'succeeded'), 'with who it was about and how it went');
  perform pg_temp.expect(not (public.list_workflows(club, null)::text like '%Welcome Gus%'), 'and no message text is kept in the list');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.list_workflow_runs(%L)', wid)) = '42501', 'a member cannot read the log');
  perform pg_temp.expect(pg_temp.state(format('select public.set_workflow_enabled(%L, false)', wid)) = '42501', 'nor pause');
  perform pg_temp.expect(pg_temp.state(format('select public.delete_workflow(%L)', wid)) = '42501', 'nor delete');
  perform pg_temp.root();

  -- A paused workflow starts nothing.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_workflow_enabled(wid, false);
  perform pg_temp.root();
  perform pg_temp.new_member('club', 'eve');
  perform pg_temp.expect(not exists (select 1 from public.workflow_runs where workflow_id = wid and event_key like 'join:' || pg_temp.i('eve')::text || '%'), 'a paused workflow starts nothing');
  -- A run queued before the pause is skipped.
  insert into public.workflow_runs (workflow_id, event_key, actor_id) values (wid, 'test:paused', pg_temp.i('eve'));
  perform pg_temp.tick();
  perform pg_temp.expect((select skip_reason from public.workflow_runs where workflow_id = wid and event_key = 'test:paused') = 'paused', 'and one queued before is skipped');

  perform pg_temp.act(pg_temp.i('ada'));
  perform public.delete_workflow(wid);
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.workflows where id = wid) and not exists (select 1 from public.workflow_runs where workflow_id = wid), 'deleting takes the runs with it');
  perform pg_temp.expect(exists (select 1 from public.circle_audit_log where circle_id = club and action = 'workflow_delete' and target_label = 'Welcome'), 'and is in the audit log');
  perform pg_temp.expect(exists (select 1 from public.circle_audit_log where circle_id = club and action = 'workflow_role_add' and target_label = 'Gus'), 'a role a workflow gave is in the audit log too');
end $$;

-- ===================================================== 12. leaving WeCord
do $$
declare
  exported jsonb;
  seen integer;
begin
  exported := public.export_my_workflows(pg_temp.i('ada'));
  perform pg_temp.expect(jsonb_array_length(exported -> 'workflows_made') >= 5 and exists (select 1 from jsonb_array_elements(exported -> 'workflows_made') x where x ->> 'name' = 'Friday report'), 'the export lists the workflows I made');
  exported := public.export_my_workflows(pg_temp.i('gus'));
  perform pg_temp.expect(jsonb_array_length(exported -> 'workflows_made') = 0, 'a member who made none exports none');
  perform pg_temp.expect(public.export_my_workflows(pg_temp.i('eve')) ->> 'runs_about_me' is not null, 'and a run about them is theirs to export');

  insert into public.workflow_runs (workflow_id, event_key, actor_id) values (pg_temp.i('w_react'), 'test:queued-for-bob', pg_temp.i('bob'));
  update public.profiles set deleted_at = now() where id = pg_temp.i('bob');
  perform pg_temp.expect(not exists (select 1 from public.workflow_runs where actor_id = pg_temp.i('bob')), 'deleting an account takes the person out of the log and drops their queued runs');
  perform pg_temp.expect((select enabled from public.workflows where id = pg_temp.i('w_bob')) is false or not exists (select 1 from public.workflows where id = pg_temp.i('w_bob') and created_by = pg_temp.i('bob')), 'the workflows of a deleted account are no longer theirs');

  update public.profiles set deleted_at = now() where id = pg_temp.i('ada');
  perform pg_temp.expect(not exists (select 1 from public.workflows where created_by = pg_temp.i('ada'))
    and not exists (select 1 from public.workflows where enabled and created_by is null)
    and exists (select 1 from public.workflows where paused_reason = 'creator_gone'), 'the workflows of a deleted account pause with no creator, and stay in their circle');
  delete from public.circle_members where circle_id = pg_temp.i('club') and user_id = pg_temp.i('eve');
  seen := (select count(*) from public.messages where auto_reply);
  perform pg_temp.new_member('club', 'eve');
  perform pg_temp.tick();
  perform pg_temp.expect((select count(*) from public.messages where auto_reply) = seen, 'nothing runs as nobody');
end $$;

\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'workflows: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
