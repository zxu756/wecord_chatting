-- Behaviour checks for advanced chat privacy (roadmap G6) and screenshot
-- alerts (roadmap G7): migrations 202610280900 to 202610280940. Run by
-- test/supabase/chat_privacy_test.dart against the local database inside a
-- transaction that is rolled back. Run from the repository root.
--
-- What it walks through: who may switch a chat's restriction (a group's
-- admins, either person of a direct chat, each person's own request), what
-- the database then refuses (forwarding, merged forwarding, saving for later,
-- copying pictures into the group space), what the AI features leave out
-- (summaries and translation through conversation_ai_allowed, the assistant,
-- digests and AI questions through conversation_ai_assistant_allowed, digest
-- cards already made), that other chats and threads of other chats are not
-- touched, view-once screenshot reports (who may report, once per kind, the
-- system line, who reads them), what deleting an account takes away, and the
-- two internal functions the data export uses.
--
-- Cast: Ada (a1) owns the group Plan; Bob (b1) is a member of it, Cy (c1) an
-- admin; Dee (d1) is in no chat. Ada and Bob share a direct chat, Ada and Cy
-- another group, Open, that is never restricted.
\set ON_ERROR_STOP on
\o /dev/null

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
\i supabase/migrations/202610280900_chat_privacy_schema.sql
\i supabase/migrations/202610280910_chat_privacy_rpc.sql
\i supabase/migrations/202610280920_chat_privacy_enforce.sql
\i supabase/migrations/202610280930_view_once_screenshots.sql
\i supabase/migrations/202610280940_chat_privacy_account.sql

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
  perform set_config('request.jwt.claim.sub', user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_id, 'role', 'authenticated')::text,
    true
  );
  execute 'set local role authenticated';
end $$;

create function pg_temp.root() returns void language plpgsql as $$
begin
  execute 'reset role';
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
create function pg_temp.errm(statement text) returns text language plpgsql as $$
begin
  execute statement;
  return 'ok';
exception when others then
  return sqlerrm;
end $$;

grant execute on all functions in schema pg_temp to public;

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create function pg_temp.i(n text) returns uuid language sql as $$ select id from pg_temp.ids where name = n $$;
grant execute on function pg_temp.i(text) to public;

-- ------------------------------------------------------------------ cast
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '@privacy.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '_privacy', initcap(name)
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || n)::uuid
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(x.a, x.b), greatest(x.a, x.b)
from (values (pg_temp.i('ada'), pg_temp.i('bob')), (pg_temp.i('ada'), pg_temp.i('cy')), (pg_temp.i('bob'), pg_temp.i('cy'))) x(a, b);

insert into pg_temp.ids values
  ('plan', '00000000-0000-4000-8000-0000000000e1'),
  ('open', '00000000-0000-4000-8000-0000000000e2'),
  ('dm', '00000000-0000-4000-8000-0000000000e3'),
  ('thread', '00000000-0000-4000-8000-0000000000e4');
insert into public.conversations (id, type, title)
values (pg_temp.i('plan'), 'group', 'Plan'), (pg_temp.i('open'), 'group', 'Open'),
  (pg_temp.i('dm'), 'direct', null), (pg_temp.i('thread'), 'thread', null);
insert into public.conversation_members (conversation_id, user_id, role)
values
  (pg_temp.i('plan'), pg_temp.i('ada'), 'owner'),
  (pg_temp.i('plan'), pg_temp.i('bob'), 'member'),
  (pg_temp.i('plan'), pg_temp.i('cy'), 'admin'),
  (pg_temp.i('open'), pg_temp.i('ada'), 'owner'),
  (pg_temp.i('open'), pg_temp.i('bob'), 'member'),
  (pg_temp.i('open'), pg_temp.i('cy'), 'member'),
  (pg_temp.i('dm'), pg_temp.i('ada'), 'member'),
  (pg_temp.i('dm'), pg_temp.i('bob'), 'member');
insert into public.conversation_threads (parent_conversation_id, conversation_id, title)
values (pg_temp.i('plan'), pg_temp.i('thread'), 'A thread');

-- ===================================== 1. who may switch it
do $$
declare
  ada uuid := pg_temp.i('ada'); bob uuid := pg_temp.i('bob'); cy uuid := pg_temp.i('cy'); dee uuid := pg_temp.i('dee');
  plan uuid := pg_temp.i('plan'); dm uuid := pg_temp.i('dm'); thread uuid := pg_temp.i('thread');
  r boolean; note_id uuid; n integer;
begin
  perform pg_temp.expect(not public.conversation_restricts_sharing(plan), 'nothing is restricted at the start');

  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.state(format('select public.set_chat_restrict_sharing(%L, true)', plan)) = '42501',
    'a member who is not an admin cannot restrict a group');
  perform pg_temp.act(dee);
  perform pg_temp.expect(
    pg_temp.state(format('select public.set_chat_restrict_sharing(%L, true)', plan)) = '42501',
    'someone outside the group cannot either');
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    pg_temp.state(format('select public.set_chat_restrict_sharing(%L, null)', plan)) = '22023',
    'a missing answer is refused');
  perform pg_temp.expect(
    pg_temp.state(format('select public.set_chat_restrict_sharing(%L, true)', thread)) = '42501',
    'a thread follows its chat and has no switch of its own');

  r := public.set_chat_restrict_sharing(plan, true);
  perform pg_temp.root();
  perform pg_temp.expect(r, 'the owner restricts the group');
  perform pg_temp.expect(
    (select c.restrict_sharing and c.restrict_sharing_by = array[ada] from public.conversations c where c.id = plan),
    'the group records the switch and who turned it on');
  select count(*) into n from public.messages
  where conversation_id = plan and type = 'system' and attachment->>'kind' = 'chat_privacy';
  perform pg_temp.expect(n = 1, 'the group is told, once, got ' || n);
  perform pg_temp.expect(
    exists (select 1 from public.messages where conversation_id = plan and body = 'Ada turned on advanced chat privacy.'
      and (attachment->>'enabled')::boolean and (attachment->>'restricted')::boolean and attachment->>'actor_id' = ada::text),
    'the line names who did it');

  perform pg_temp.act(ada);
  r := public.set_chat_restrict_sharing(plan, true);
  perform pg_temp.root();
  select count(*) into n from public.messages
  where conversation_id = plan and type = 'system' and attachment->>'kind' = 'chat_privacy';
  perform pg_temp.expect(r and n = 1, 'turning on what is on says nothing new');

  perform pg_temp.act(bob);
  perform pg_temp.expect(
    (select c.restrict_sharing from public.conversations c where c.id = plan),
    'every member reads the switch with the chat');
  perform pg_temp.expect(
    pg_temp.state(format('update public.conversations set restrict_sharing = false where id = %L', plan)) <> 'ok'
    or (select c.restrict_sharing from public.conversations c where c.id = plan),
    'and cannot change it by writing the row');
  perform pg_temp.expect(
    pg_temp.state(format('select public.conversation_restricts_sharing(%L)', plan)) = '42501',
    'the internal check is not for signed-in people');
  perform pg_temp.root();
  perform pg_temp.expect(
    (select c.restrict_sharing from public.conversations c where c.id = plan),
    'a direct write changed nothing');
  perform pg_temp.expect(public.conversation_restricts_sharing(thread), 'a thread of a restricted group is restricted');

  perform pg_temp.act(cy);
  r := public.set_chat_restrict_sharing(plan, false);
  perform pg_temp.root();
  perform pg_temp.expect(not r, 'an admin turns it off');
  perform pg_temp.expect(
    (select not c.restrict_sharing and cardinality(c.restrict_sharing_by) = 0 from public.conversations c where c.id = plan)
    and not public.conversation_restricts_sharing(thread),
    'off for the group and its thread');
  select count(*) into n from public.messages
  where conversation_id = plan and type = 'system' and attachment->>'kind' = 'chat_privacy';
  perform pg_temp.expect(n = 2, 'turning it off is announced too, got ' || n);

  -- A direct chat: each person's own request.
  perform pg_temp.act(ada);
  r := public.set_chat_restrict_sharing(dm, true);
  perform pg_temp.expect(r, 'either person restricts a direct chat');
  perform pg_temp.act(bob);
  r := public.set_chat_restrict_sharing(dm, true);
  perform pg_temp.root();
  perform pg_temp.expect(r and (select cardinality(c.restrict_sharing_by) = 2 from public.conversations c where c.id = dm),
    'both can ask at once');
  perform pg_temp.act(ada);
  r := public.set_chat_restrict_sharing(dm, false);
  perform pg_temp.root();
  perform pg_temp.expect(r and public.conversation_restricts_sharing(dm),
    'taking back your own request leaves the other person''s in force');
  perform pg_temp.act(bob);
  r := public.set_chat_restrict_sharing(dm, false);
  perform pg_temp.root();
  perform pg_temp.expect(not r and not public.conversation_restricts_sharing(dm),
    'when nobody asks any more the chat is open again');

  -- The note to self has nothing to restrict.
  perform pg_temp.act(ada);
  perform public.get_note_to_self();
  perform pg_temp.root();
  select n2.conversation_id into note_id from public.note_to_self_conversations n2 where n2.user_id = ada;
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    pg_temp.state(format('select public.set_chat_restrict_sharing(%L, true)', note_id)) = '22023',
    'the note to self cannot be restricted');
  perform pg_temp.root();

  -- Leave the group restricted for the next parts.
  perform pg_temp.act(ada);
  perform public.set_chat_restrict_sharing(plan, true);
  perform pg_temp.root();
end $$;

-- ===================================== 2. what the server refuses
do $$
declare
  ada uuid := pg_temp.i('ada'); bob uuid := pg_temp.i('bob'); cy uuid := pg_temp.i('cy');
  plan uuid := pg_temp.i('plan'); open_chat uuid := pg_temp.i('open');
  m_plan uuid; m_open uuid; copy_id uuid; bundle uuid; album jsonb; alb uuid; img uuid; doc uuid; result jsonb;
begin
  insert into public.messages (conversation_id, sender_id, type, body)
  values (plan, ada, 'text', 'the secret plan') returning id into m_plan;
  insert into public.messages (conversation_id, sender_id, type, body)
  values (open_chat, ada, 'text', 'open news') returning id into m_open;

  -- Forwarding.
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    pg_temp.errm(format('select public.forward_message(%L, %L)', m_plan, open_chat)) = 'chat_privacy_restricted',
    'a message of a restricted chat cannot be forwarded');
  perform pg_temp.expect(
    pg_temp.state(format('select public.forward_message(%L, %L)', m_plan, open_chat)) = '42501',
    'with a permission error');
  copy_id := public.forward_message(m_open, plan);
  perform pg_temp.expect(copy_id is not null, 'a message can be forwarded INTO a restricted chat');
  perform pg_temp.expect(
    pg_temp.errm(format('select public.forward_message(%L, %L)', copy_id, open_chat)) = 'chat_privacy_restricted',
    'but the copy there is as restricted as the rest of that chat');
  perform pg_temp.expect(
    pg_temp.errm(format('select public.forward_messages_merged(array[%L::uuid], %L, ''x'')', m_plan, open_chat)) = 'chat_privacy_restricted',
    'a merged forward of a restricted chat is refused');
  perform pg_temp.expect(
    (select count(*) from public.messages where conversation_id = open_chat and type = 'text' and body like 'Chat history:%') = 0,
    'and leaves nothing behind');
  bundle := public.forward_messages_merged(array[m_open], plan, 'Open');
  perform pg_temp.expect(bundle is not null, 'a merged forward INTO a restricted chat works');
  perform pg_temp.expect(
    pg_temp.errm(format('select public.forward_message(%L, %L)', bundle, open_chat)) = 'chat_privacy_restricted',
    'and cannot be forwarded on from there');

  -- Saving for later.
  perform pg_temp.expect(
    pg_temp.errm(format('select public.save_message(%L)', m_plan)) = 'chat_privacy_restricted',
    'a message of a restricted chat cannot be saved for later');
  perform pg_temp.expect(
    pg_temp.errm(format('select public.save_item(''message'', %L)', m_plan)) = 'chat_privacy_restricted',
    'not through save_item either');
  perform pg_temp.expect(
    pg_temp.state(format('select public.save_message(%L)', m_open)) = 'ok',
    'a message of another chat still can');

  -- The group space.
  perform pg_temp.act(bob);
  album := public.create_group_album(plan, 'Trip');
  alb := (album->>'id')::uuid;
  perform pg_temp.root();
  img := gen_random_uuid(); doc := gen_random_uuid();
  insert into public.messages (id, conversation_id, sender_id, type, body, attachment)
  values
    (img, plan, bob, 'image', '', jsonb_build_object('kind', 'image', 'bucket', 'chat-images',
      'path', plan::text || '/a.jpg', 'mime_type', 'image/jpeg', 'size', 1000)),
    (doc, plan, bob, 'file', '', jsonb_build_object('kind', 'file', 'bucket', 'chat-files',
      'path', plan::text || '/f.pdf', 'mime_type', 'application/pdf', 'size', 1000, 'name', 'f.pdf'));
  insert into storage.objects (bucket_id, name)
  values ('chat-images', plan::text || '/a.jpg'), ('chat-files', plan::text || '/f.pdf');
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.errm(format('select public.add_album_items_from_messages(%L, array[%L::uuid])', alb, img)) = 'chat_privacy_restricted',
    'pictures of a restricted chat do not go into an album');
  perform pg_temp.expect(
    pg_temp.errm(format('select public.add_folder_files_from_messages(%L, null, array[%L::uuid])', plan, doc)) = 'chat_privacy_restricted',
    'files of a restricted chat do not go into a folder');

  -- Switching it off makes all of it work again; switching it on stops it.
  perform pg_temp.act(cy);
  perform public.set_chat_restrict_sharing(plan, false);
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    pg_temp.state(format('select public.forward_message(%L, %L)', m_plan, open_chat)) = 'ok',
    'forwarding works again when the chat is open');
  perform pg_temp.expect(
    pg_temp.state(format('select public.save_message(%L)', m_plan)) = 'ok',
    'so does saving');
  perform pg_temp.act(bob);
  result := public.add_album_items_from_messages(alb, array[img]);
  perform pg_temp.expect((result->>'added')::int = 1, 'and the album');
  result := public.add_folder_files_from_messages(plan, null, array[doc]);
  perform pg_temp.expect((result->>'added')::int = 1, 'and the folder');
  perform pg_temp.act(ada);
  perform public.set_chat_restrict_sharing(plan, true);
  perform pg_temp.root();
end $$;

-- ===================================== 3. what AI leaves out
do $$
declare
  ada uuid := pg_temp.i('ada'); bob uuid := pg_temp.i('bob'); cy uuid := pg_temp.i('cy');
  plan uuid := pg_temp.i('plan'); open_chat uuid := pg_temp.i('open'); dm uuid := pg_temp.i('dm'); thread uuid := pg_temp.i('thread');
  n integer; found uuid[]; digest uuid;
begin
  perform pg_temp.act(ada);
  perform pg_temp.expect(not public.conversation_ai_allowed(plan), 'AI features stop at a restricted group');
  perform pg_temp.expect(not public.conversation_ai_allowed(thread), 'and at its threads');
  perform pg_temp.expect(public.conversation_ai_allowed(open_chat), 'another group is not touched');
  perform pg_temp.expect(public.conversation_ai_allowed(dm), 'nor a direct chat nobody restricted');
  perform pg_temp.act(bob);
  perform pg_temp.expect(not public.conversation_ai_allowed(plan), 'for every member alike');
  perform pg_temp.root();
  perform pg_temp.expect(not public.conversation_ai_assistant_allowed(plan), 'the assistant stops there too');
  perform pg_temp.expect(not public.conversation_ai_assistant_allowed(thread), 'and in its threads');
  perform pg_temp.expect(public.conversation_ai_assistant_allowed(open_chat), 'and still answers in another group');
  perform pg_temp.expect(public.conversation_ai_assistant_allowed(dm), 'and a direct chat');

  -- Digest, AI questions, and digest cards already made.
  insert into public.messages (conversation_id, sender_id, type, body, created_at)
  values
    (plan, bob, 'text', 'Plan lunch on Friday', now() - interval '30 minutes'),
    (open_chat, bob, 'text', 'Trip tickets are booked', now() - interval '30 minutes');
  insert into public.ai_digest_subscriptions (user_id, conversation_id) values (ada, plan), (ada, open_chat);

  select count(distinct conversation_id) into n
  from public.ai_digest_messages(ada, now() - interval '2 hours', now());
  perform pg_temp.expect(n = 1, 'digest: only the open chat is covered, got ' || n);
  perform pg_temp.expect(
    not exists (select 1 from public.ai_digest_messages(ada, now() - interval '2 hours', now()) where conversation_id = plan),
    'digest: nothing of the restricted chat');
  found := public.ai_ask_conversations(ada, '{"type":"everywhere"}'::jsonb);
  perform pg_temp.expect(not (plan = any(found)) and open_chat = any(found), 'ask: everywhere leaves the restricted chat out');
  perform pg_temp.expect(
    public.ai_ask_scope(ada, jsonb_build_object('type', 'conversation', 'id', plan))->>'status' = 'ai_off',
    'ask: a question about the restricted chat is told AI is off there');

  insert into public.ai_digests (user_id, local_date, window_start, window_end, status, items, finished_at)
  values (ada, current_date, now() - interval '2 hours', now(), 'done',
    jsonb_build_array(
      jsonb_build_object('conversation_id', plan, 'summary', 'Lunch plans', 'message_count', 1),
      jsonb_build_object('conversation_id', open_chat, 'summary', 'Tickets', 'message_count', 1)),
    now())
  returning id into digest;
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    (select jsonb_array_length(items) from public.list_my_ai_digests() where id = digest) = 1,
    'cards: the restricted chat is no longer listed');
  perform pg_temp.expect(
    not exists (select 1 from public.list_my_ai_digests() l, jsonb_array_elements(l.items) e where e->>'conversation_id' = plan::text),
    'cards: not even its summary');
  perform pg_temp.act(cy);
  perform public.set_chat_restrict_sharing(plan, false);
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    (select jsonb_array_length(items) from public.list_my_ai_digests() where id = digest) = 2,
    'cards: open again, listed again');
  perform pg_temp.expect(public.conversation_ai_allowed(plan), 'AI is allowed again when the chat is open');
  perform pg_temp.root();
  perform pg_temp.expect(public.conversation_ai_assistant_allowed(plan), 'and the assistant');
  perform pg_temp.expect(
    plan = any(public.ai_ask_conversations(ada, '{"type":"everywhere"}'::jsonb)),
    'and AI questions');

  -- The old locks and switches still count: a locked chat stays locked, a
  -- group that turned the assistant off keeps it off.
  perform pg_temp.act(ada);
  perform public.set_conversation_locked(plan, true);
  perform pg_temp.root();
  perform pg_temp.expect(
    not (plan = any(public.ai_ask_conversations(ada, '{"type":"everywhere"}'::jsonb))),
    'a locked chat is still left out (G2 patch kept)');
  perform pg_temp.act(ada);
  perform public.set_conversation_locked(plan, false);
  perform pg_temp.root();
  insert into public.group_ai_settings (conversation_id, assistant_enabled) values (plan, false);
  perform pg_temp.expect(not public.conversation_ai_assistant_allowed(plan), 'the group''s own assistant switch still counts');
  delete from public.group_ai_settings where conversation_id = plan;

  perform pg_temp.act(ada);
  perform public.set_chat_restrict_sharing(plan, true);
  perform pg_temp.root();
end $$;

-- ===================================== 4. screenshot reports
do $$
declare
  ada uuid := pg_temp.i('ada'); bob uuid := pg_temp.i('bob'); cy uuid := pg_temp.i('cy'); dee uuid := pg_temp.i('dee');
  dm uuid := pg_temp.i('dm'); open_chat uuid := pg_temp.i('open');
  once uuid; plain uuid; once2 uuid; once3 uuid; gonce uuid; r boolean; n integer;
begin
  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (dm, ada, 'image', '', jsonb_build_object('kind', 'image', 'bucket', 'chat-images', 'path', dm::text || '/once.jpg', 'view_once', true))
  returning id into once;
  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (dm, ada, 'image', '', jsonb_build_object('kind', 'image', 'bucket', 'chat-images', 'path', dm::text || '/plain.jpg'))
  returning id into plain;
  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (dm, ada, 'file', '', jsonb_build_object('kind', 'video', 'bucket', 'chat-files', 'path', dm::text || '/once.mp4', 'view_once', true))
  returning id into once2;
  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (dm, ada, 'image', '', jsonb_build_object('kind', 'image', 'bucket', 'chat-images', 'path', dm::text || '/once3.jpg', 'view_once', true))
  returning id into once3;
  insert into pg_temp.ids values ('once', once);

  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.errm(format('select public.report_view_once_screenshot(%L)', once)) = 'view_once_not_open',
    'nobody reports a photo they have not opened');
  perform public.open_view_once(once);
  perform public.open_view_once(once2);
  perform public.open_view_once(once3);

  r := public.report_view_once_screenshot(once, 'screenshot');
  perform pg_temp.root();
  perform pg_temp.expect(r, 'a screenshot of an open photo is recorded');
  select count(*) into n from public.messages
  where conversation_id = dm and type = 'system' and attachment->>'kind' = 'screenshot';
  perform pg_temp.expect(n = 1, 'and the chat is told, got ' || n);
  perform pg_temp.expect(
    exists (select 1 from public.messages where conversation_id = dm and body = 'Bob took a screenshot of a view-once photo.'
      and attachment->>'event' = 'screenshot' and attachment->>'media' = 'photo'
      and attachment->>'message_id' = once::text and attachment->>'actor_id' = bob::text),
    'the line says who, what and which photo');

  perform pg_temp.act(bob);
  r := public.report_view_once_screenshot(once, 'screenshot');
  perform pg_temp.root();
  select count(*) into n from public.messages
  where conversation_id = dm and type = 'system' and attachment->>'kind' = 'screenshot';
  perform pg_temp.expect(not r and n = 1, 'the same report twice says nothing the second time');

  perform pg_temp.act(bob);
  r := public.report_view_once_screenshot(once, 'recording');
  perform pg_temp.root();
  perform pg_temp.expect(r, 'a screen recording is a report of its own');
  perform pg_temp.expect(
    exists (select 1 from public.messages where conversation_id = dm
      and body = 'Bob was recording the screen while a view-once photo was open.' and attachment->>'event' = 'recording'),
    'with its own wording');
  perform pg_temp.act(bob);
  r := public.report_view_once_screenshot(once2, 'screenshot');
  perform pg_temp.root();
  perform pg_temp.expect(
    exists (select 1 from public.messages where conversation_id = dm
      and body = 'Bob took a screenshot of a view-once video.' and attachment->>'media' = 'video'),
    'a video is a video');

  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.state(format('select public.report_view_once_screenshot(%L, ''selfie'')', once)) = '22023',
    'an unknown kind of report is refused');
  perform pg_temp.expect(
    pg_temp.state(format('select public.report_view_once_screenshot(%L)', plain)) = '42501',
    'an ordinary photo has no reports');
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    pg_temp.state(format('select public.report_view_once_screenshot(%L)', once)) = '42501',
    'the sender does not report on their own photo');
  perform pg_temp.act(dee);
  perform pg_temp.expect(
    pg_temp.state(format('select public.report_view_once_screenshot(%L)', once)) = '42501',
    'nor does someone outside the chat');

  -- Too long ago.
  perform pg_temp.root();
  update public.message_view_once_opens set opened_at = now() - interval '31 minutes'
  where message_id = once3 and user_id = bob;
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.errm(format('select public.report_view_once_screenshot(%L)', once3)) = 'view_once_not_open',
    'a photo opened half an hour ago is no longer open');

  -- Blocked.
  perform pg_temp.root();
  update public.message_view_once_opens set opened_at = now() where message_id = once3 and user_id = bob;
  insert into public.blocks (blocker_id, blocked_id) values (ada, bob);
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.errm(format('select public.report_view_once_screenshot(%L)', once3)) = 'view_once_unavailable',
    'someone blocked in the chat reports nothing');
  perform pg_temp.root();
  delete from public.blocks;

  -- Deleted photo.
  update public.messages set recalled_at = now(), recalled_by = ada where id = once3;
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.errm(format('select public.report_view_once_screenshot(%L)', once3)) = 'view_once_unavailable',
    'and a deleted photo has none');
  perform pg_temp.root();

  -- Who reads the reports.
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    (select count(*) from public.message_view_once_screenshots) = 3,
    'the sender reads every report about their photos');
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    (select count(*) from public.message_view_once_screenshots) = 3,
    'the person who reported reads their own');
  perform pg_temp.act(dee);
  perform pg_temp.expect(
    (select count(*) from public.message_view_once_screenshots) = 0,
    'nobody else reads any');
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.state(format('insert into public.message_view_once_screenshots (message_id, user_id, conversation_id, event) values (%L, %L, %L, ''screenshot'')', once3, bob, dm)) <> 'ok',
    'and nobody writes a report directly');
  perform pg_temp.root();

  -- A group: the sender sees everyone's reports, a member only their own.
  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (open_chat, ada, 'image', '', jsonb_build_object('kind', 'image', 'bucket', 'chat-images', 'path', open_chat::text || '/g.jpg', 'view_once', true))
  returning id into gonce;
  perform pg_temp.act(bob);
  perform public.open_view_once(gonce);
  perform public.report_view_once_screenshot(gonce);
  perform pg_temp.act(cy);
  perform public.open_view_once(gonce);
  perform public.report_view_once_screenshot(gonce);
  perform pg_temp.root();
  perform pg_temp.act(ada);
  perform pg_temp.expect((select count(*) from public.message_view_once_screenshots where message_id = gonce) = 2,
    'in a group the sender reads both members'' reports');
  perform pg_temp.act(cy);
  perform pg_temp.expect((select count(*) from public.message_view_once_screenshots where message_id = gonce) = 1,
    'a member reads only their own');
  perform pg_temp.root();
  select count(*) into n from public.messages
  where conversation_id = open_chat and type = 'system' and attachment->>'kind' = 'screenshot';
  perform pg_temp.expect(n = 2, 'and the group sees two lines, got ' || n);
end $$;

-- ===================================== 5. what the data export uses
do $$
declare
  ada uuid := pg_temp.i('ada'); bob uuid := pg_temp.i('bob');
  plan uuid := pg_temp.i('plan'); open_chat uuid := pg_temp.i('open'); thread uuid := pg_temp.i('thread');
  exported jsonb; ids uuid[];
begin
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    pg_temp.state(format('select public.export_my_chat_privacy(%L)', ada)) = '42501',
    'a signed-in person cannot call the export function');
  perform pg_temp.expect(
    pg_temp.state(format('select public.restricted_conversation_ids(array[%L::uuid])', plan)) = '42501',
    'nor ask which chats are restricted');
  perform pg_temp.root();

  ids := public.restricted_conversation_ids(array[plan, open_chat, thread, gen_random_uuid(), null]);
  perform pg_temp.expect(plan = any(ids) and thread = any(ids) and not (open_chat = any(ids)) and cardinality(ids) = 2,
    'the service role learns which chats are restricted, threads included');
  perform pg_temp.expect(cardinality(public.restricted_conversation_ids(null)) = 0, 'no list, no answer');

  exported := public.export_my_chat_privacy(ada);
  perform pg_temp.expect(
    jsonb_array_length(exported->'requested_in') = 1
    and exported->'requested_in'->0->>'conversation_id' = plan::text,
    'the export lists the chats Ada asked to restrict');
  perform pg_temp.expect(jsonb_array_length(exported->'screenshot_reports') = 0, 'and the reports she made (none)');
  exported := public.export_my_chat_privacy(bob);
  perform pg_temp.expect(jsonb_array_length(exported->'screenshot_reports') = 4,
    'Bob''s export has his four reports, got ' || jsonb_array_length(exported->'screenshot_reports'));
  perform pg_temp.expect(jsonb_array_length(exported->'requested_in') = 0, 'and none of anyone else''s requests');
end $$;

-- ===================================== 6. deleting an account
do $$
declare
  ada uuid := pg_temp.i('ada'); bob uuid := pg_temp.i('bob'); cy uuid := pg_temp.i('cy');
  plan uuid := pg_temp.i('plan'); dm uuid := pg_temp.i('dm');
begin
  -- Ada and Bob both ask for the direct chat; Cy turns the group on after Ada.
  perform pg_temp.act(ada);
  perform public.set_chat_restrict_sharing(dm, true);
  perform pg_temp.act(bob);
  perform public.set_chat_restrict_sharing(dm, true);
  perform pg_temp.act(cy);
  perform public.set_chat_restrict_sharing(plan, false);
  perform public.set_chat_restrict_sharing(plan, true);
  perform pg_temp.root();
  perform pg_temp.expect(
    (select c.restrict_sharing_by = array[cy] from public.conversations c where c.id = plan),
    'the group remembers the admin who turned it on');

  update public.profiles set deleted_at = now() where id = bob;
  perform pg_temp.expect(
    not exists (select 1 from public.message_view_once_screenshots where user_id = bob),
    'deleting an account erases the person''s screenshot reports');
  perform pg_temp.expect(
    (select c.restrict_sharing and c.restrict_sharing_by = array[ada] from public.conversations c where c.id = dm),
    'a direct chat stays restricted for the person who is left, without the deleted request');
  update public.profiles set deleted_at = now() where id = cy;
  perform pg_temp.expect(
    (select c.restrict_sharing and cardinality(c.restrict_sharing_by) = 0 from public.conversations c where c.id = plan),
    'a group keeps its switch when the admin who turned it on goes');
  perform pg_temp.expect(
    exists (select 1 from public.messages where conversation_id = dm and attachment->>'kind' = 'screenshot'),
    'the lines already in the chat stay');
end $$;

reset role;
do $$
declare
  failed text;
begin
  select string_agg(msg, E'\n') into failed from pg_temp.failures;
  if failed is not null then
    raise exception E'chat privacy checks failed:\n%', failed;
  end if;
end $$;

rollback;
