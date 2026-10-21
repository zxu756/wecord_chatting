-- Behaviour checks for scheduled calls (E2: migrations 202610280100 to
-- 202610280140). Run by test/supabase/scheduled_calls_test.dart against the
-- local database: it applies the migrations in a transaction, plays people
-- through them, and rolls everything back. Run from the repository root.
--
-- What it walks through: what the patched functions kept; making an event with
-- a call (group chat and direct chat), who may; the call link of an event not
-- counting towards the 50 links a person holds and not being listed; moving
-- and cancelling the event moving and turning off its link; a repeating event
-- handing its call on (and not, once the organiser took it off); the reminder
-- push with and without the call, in both languages; My agenda carrying the
-- code; the data export, the daily purge and deleting an account.
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

-- Back to the table owner, but still "signed in" as the last person acted as.
create function pg_temp.root() returns void language plpgsql as $$
begin
  execute 'reset role';
end $$;

create function pg_temp.state(statement text) returns text language plpgsql as $$
begin
  execute statement;
  return 'ok';
exception when others then
  return sqlstate;
end $$;

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
-- ada runs a group chat (g1); bob and cat are in it; eve is not. ada and bob
-- also have a direct chat (dm). ada, bob and cat are friends.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@e2.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'eve')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_e2', initcap(name)
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'eve')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'eve')) v(n, name);

insert into pg_temp.ids values ('g1', gen_random_uuid()), ('dm', gen_random_uuid());
insert into public.conversations (id, type, title)
values (pg_temp.i('g1'), 'group', 'Hike crew'), (pg_temp.i('dm'), 'direct', null);
insert into public.conversation_members (conversation_id, user_id, role)
values
  (pg_temp.i('g1'), pg_temp.i('ada'), 'owner'),
  (pg_temp.i('g1'), pg_temp.i('bob'), 'member'),
  (pg_temp.i('g1'), pg_temp.i('cat'), 'member'),
  (pg_temp.i('dm'), pg_temp.i('ada'), 'member'),
  (pg_temp.i('dm'), pg_temp.i('bob'), 'member');
insert into public.friendships (user_low_id, user_high_id)
select least(pg_temp.i('ada'), pg_temp.i(n)), greatest(pg_temp.i('ada'), pg_temp.i(n))
from (values ('bob'),('cat')) v(n);

-- A chat event made by [who] in [conv], [mins] minutes from now (lasting
-- [lasts] minutes when given), with [opts] as event_options. Returns the payload.
create function pg_temp.chat_event(who text, title text, mins integer, opts jsonb default null, conv text default 'g1', lasts integer default null)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.act(pg_temp.i(who));
  r := public.create_chat_event(
    pg_temp.i(conv), title, now() + make_interval(mins => mins),
    case when lasts is null then null else now() + make_interval(mins => mins + lasts) end,
    null, null, null, array[15], false, opts);
  perform pg_temp.root();
  return r;
end $$;

-- What opening the call link [code] does for [who]: the status.
create function pg_temp.opens(who text, link_code text) returns text language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.act(pg_temp.i(who));
  r := public.resolve_call_link(link_code);
  perform pg_temp.root();
  return r ->> 'status';
end $$;

-- Claims every reminder push waiting and keeps the rows in pg_temp.claims.
create function pg_temp.claim() returns void language plpgsql as $$
begin
  drop table if exists pg_temp.claims;
  create temp table claims as select * from public.claim_chat_event_reminder_pushes();
  grant all on pg_temp.claims to public;
end $$;

grant execute on all functions in schema pg_temp to public;

-- ===================================== 1. what the patches kept
do $$
declare
  def text;
begin
  def := pg_get_functiondef('public.chat_event_json(public.chat_events)'::regprocedure);
  perform pg_temp.expect(def like '%scheduled_call_code%' and def like '%my_checked_in%' and def like '%waitlist_count%' and def like '%photo_count%' and def like '%can_manage_chat_event%', 'chat_event_json has the call and all that Events 2.0 put in');
  def := pg_get_functiondef('public.create_chat_event(uuid, text, timestamptz, timestamptz, text, text, text, integer[], boolean, jsonb)'::regprocedure);
  perform pg_temp.expect(def like '%scheduled_call_apply%' and def like '%events2_merge_options%' and def like '%chat_event_check_conversation%', 'create_chat_event attaches the call and keeps the rest');
  def := pg_get_functiondef('public.update_chat_event(uuid, text, timestamptz, timestamptz, text, text, text, integer[], jsonb)'::regprocedure);
  perform pg_temp.expect(def like '%scheduled_call_apply%' and def like '%events2_promote%' and def like '%can_manage_chat_event%', 'update_chat_event the same');
  def := pg_get_functiondef('public.create_call_link(uuid, uuid, text)'::regprocedure);
  perform pg_temp.expect(def like '%not cl.for_event%' and def like '%>= 50%' and def like '%can_current_user_connect_voice%', 'create_call_link still limits to 50 and skips event links');
  def := pg_get_functiondef('public.list_call_links(uuid, uuid)'::regprocedure);
  perform pg_temp.expect(def like '%not cl.for_event%' and def like '%revoked_at is null%', 'list_call_links skips event links');
  def := pg_get_functiondef('public.agenda_items_core(timestamptz, timestamptz, text[])'::regprocedure);
  perform pg_temp.expect(def like '%scheduled_call_code%' and def like '%message_visible_to_current_user%' and def like '%current_user_can_see_circle_event%', 'agenda_items_core has the call and keeps its rules');
  def := pg_get_functiondef('public.claim_chat_event_reminder_pushes(integer)'::regprocedure);
  perform pg_temp.expect(def like '%s.language = ''zh''%' and def like '%分钟后开始%' and def like '%点按加入通话%' and def like '%Tap to join the call%' and def like '%cm.muted_until%', 'the reminder push is worded in both languages and respects the mute');
  perform pg_temp.expect(to_regprocedure('public.run_later_dispatch()') is not null and pg_get_functiondef('public.run_later_dispatch()'::regprocedure) not like '%scheduled_call%', 'run_later_dispatch is not touched');
  perform pg_temp.expect(pg_get_functiondef('public.events2_spawn_next(timestamptz)'::regprocedure) not like '%scheduled_call%', 'events2_spawn_next is not touched');
  perform pg_temp.expect(not has_function_privilege('authenticated', 'public.scheduled_call_make_link(uuid, uuid, timestamptz)', 'execute') and not has_function_privilege('authenticated', 'public.scheduled_call_apply(public.chat_events, jsonb)', 'execute') and not has_function_privilege('authenticated', 'public.scheduled_call_code(text)', 'execute'), 'the helpers are closed to clients');
  perform pg_temp.expect(not has_function_privilege('authenticated', 'public.claim_chat_event_reminder_pushes(integer)', 'execute') and has_function_privilege('service_role', 'public.claim_chat_event_reminder_pushes(integer)', 'execute'), 'the claim function is for the service role only');
end $$;

-- ===================================== 2. making an event with a call
do $$
declare
  e jsonb;
  link record;
  ev uuid;
begin
  e := pg_temp.chat_event('ada', 'Thursday sync', 3 * 24 * 60, '{"call": true}', 'g1', 60);
  ev := (e ->> 'id')::uuid;
  perform pg_temp.expect(e ->> 'call_link_code' ~ '^[a-z0-9]{12}$', 'an event made with call = true has a call link code');
  select * into link from public.call_links where code = e ->> 'call_link_code';
  perform pg_temp.expect(link.for_event and link.conversation_id = pg_temp.i('g1') and link.created_by = pg_temp.i('ada') and link.channel_id is null, 'the link is an event link to the chat, made by the organiser');
  perform pg_temp.expect(link.expires_at = (select ends_at + interval '1 hour' from public.chat_events where id = ev), 'it works until an hour after the event ends');
  perform pg_temp.expect((select call_link_code from public.chat_events where id = ev) = e ->> 'call_link_code', 'the event holds the code');

  perform pg_temp.expect(pg_temp.opens('bob', e ->> 'call_link_code') = 'ok', 'a member opening it joins the chat''s call');
  perform pg_temp.expect(pg_temp.opens('eve', e ->> 'call_link_code') = 'no_access', 'someone outside the chat gets nothing from it');

  -- An event with no end: three hours after the start.
  e := pg_temp.chat_event('ada', 'Open ended', 3 * 24 * 60, '{"call": true}');
  perform pg_temp.expect((select cl.expires_at - ev2.starts_at from public.call_links cl, public.chat_events ev2 where cl.code = e ->> 'call_link_code' and ev2.id = (e ->> 'id')::uuid) = interval '3 hours', 'with no end it lasts the two hours of an open event plus the hour');

  -- No call asked: none made.
  e := pg_temp.chat_event('ada', 'Plain lunch', 3 * 24 * 60);
  perform pg_temp.expect(e ->> 'call_link_code' is null and e ? 'call_link_code', 'an event made without asking has no call (the key is there, null)');
  e := pg_temp.chat_event('ada', 'No call lunch', 3 * 24 * 60, '{"call": false}');
  perform pg_temp.expect(e ->> 'call_link_code' is null, 'call = false makes none');
  perform pg_temp.expect((select count(*) from public.call_links where for_event) = 2, 'only the two asked for were made');

  -- A member (not the organiser) sees the code in the list and the single read.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect((select x ->> 'call_link_code' from public.list_chat_events(pg_temp.i('g1'), false) x where x ->> 'id' = ev::text) ~ '^[a-z0-9]{12}$', 'list_chat_events carries it for members');
  perform pg_temp.expect(public.get_chat_event(ev) ->> 'call_link_code' ~ '^[a-z0-9]{12}$', 'and get_chat_event');
  perform pg_temp.root();

  -- Who may.
  perform pg_temp.expect(pg_temp.state($q$select pg_temp.chat_event('eve', 'Sneaky', 100, '{"call": true}')$q$) <> 'ok', 'a stranger cannot make an event with a call');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format($q$select public.scheduled_call_make_link(%L, %L, now())$q$, pg_temp.i('g1'), pg_temp.i('bob'))) = '42501', 'a client cannot make an event link by hand');
  perform pg_temp.root();
end $$;

-- A direct chat whose other person takes no calls cannot have an event with a call.
do $$
declare
  e jsonb;
begin
  e := pg_temp.chat_event('ada', 'Call with bob', 1000, '{"call": true}', 'dm');
  perform pg_temp.expect(e ->> 'call_link_code' is not null, 'a direct chat event can have a call');
  insert into public.user_privacy_settings (user_id, allow_calls_from)
  values (pg_temp.i('bob'), 'nobody')
  on conflict (user_id) do update set allow_calls_from = 'nobody';
  perform pg_temp.expect(pg_temp.msg($q$select pg_temp.chat_event('ada', 'Call 2', 1000, '{"call": true}', 'dm')$q$) like '%cannot call%', 'if bob takes no calls, ada cannot attach one');
  e := pg_temp.chat_event('ada', 'Just a chat date', 1000, null, 'dm');
  perform pg_temp.expect(e ->> 'call_link_code' is null, 'but she can still make the event');
  delete from public.user_privacy_settings where user_id = pg_temp.i('bob');
end $$;

-- ===================================== 3. event links are not the person's own
do $$
declare
  n integer;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect((select count(*) from public.list_call_links(pg_temp.i('g1'), null)) = 0, 'the call link sheet does not list the links events made');
  for n in 1..50 loop
    perform public.create_call_link(pg_temp.i('g1'), null, 'week');
  end loop;
  perform pg_temp.expect(true, 'fifty own links can be made with event links around');
  perform pg_temp.expect(pg_temp.state(format($q$select public.create_call_link(%L, null, 'week')$q$, pg_temp.i('g1'))) = '53400', 'the fifty-first is refused as before');
  perform pg_temp.expect((select count(*) from public.list_call_links(pg_temp.i('g1'), null)) = 50, 'and the sheet lists those fifty');
  perform pg_temp.root();
  delete from public.call_links where not for_event;
end $$;

-- ===================================== 4. switching it on and off, moving, cancelling
do $$
declare
  e jsonb;
  ev uuid;
  v_code text;
  starts timestamptz := now() + interval '4 days';
begin
  e := pg_temp.chat_event('ada', 'Switchable', 4 * 24 * 60);
  ev := (e ->> 'id')::uuid;
  perform pg_temp.act(pg_temp.i('ada'));
  -- An update with no `call` key (an older app) leaves it as it is.
  e := public.update_chat_event(ev, 'Switchable', starts, null, null, null, null, array[15], '{"capacity": 5}');
  perform pg_temp.expect(e ->> 'call_link_code' is null and (e ->> 'capacity')::int = 5, 'an update without the call key keeps no call');
  e := public.update_chat_event(ev, 'Switchable', starts, null, null, null, null, array[15], '{"call": true}');
  v_code := e ->> 'call_link_code';
  perform pg_temp.expect(v_code is not null and (e ->> 'capacity')::int = 5, 'an update with call = true attaches one and keeps the other options');
  e := public.update_chat_event(ev, 'Switchable', starts, null, null, null, null, array[15], '{"recurrence": null}');
  perform pg_temp.expect(e ->> 'call_link_code' = v_code, 'an update without the call key keeps the call');
  e := public.update_chat_event(ev, 'Switchable', starts, null, null, null, null, array[15], '{"call": true}');
  perform pg_temp.expect(e ->> 'call_link_code' = v_code, 'asking again does not make a second link');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.call_links cl where cl.for_event and cl.conversation_id = pg_temp.i('g1') and cl.code = v_code) = 1, 'one link');

  -- Moving the event moves the link's expiry.
  perform pg_temp.act(pg_temp.i('ada'));
  e := public.update_chat_event(ev, 'Switchable', starts + interval '2 days', starts + interval '2 days 90 minutes', null, null, null, array[15], null);
  perform pg_temp.root();
  perform pg_temp.expect((select cl.expires_at from public.call_links cl where cl.code = v_code) = starts + interval '2 days 150 minutes', 'moving the event moves the link''s expiry (end plus an hour)');
  perform pg_temp.expect(e ->> 'call_link_code' = v_code, 'and the code stays');

  -- Switching it off turns the link off.
  perform pg_temp.act(pg_temp.i('ada'));
  e := public.update_chat_event(ev, 'Switchable', starts + interval '2 days', null, null, null, null, array[15], '{"call": false}');
  perform pg_temp.root();
  perform pg_temp.expect(e ->> 'call_link_code' is null and (select cl.revoked_at is not null from public.call_links cl where cl.code = v_code), 'call = false removes it and turns the link off');
  perform pg_temp.expect(pg_temp.opens('bob', v_code) = 'revoked', 'opening the old link says it was turned off');

  -- A member who is not the organiser cannot change it.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format($q$select public.update_chat_event(%L, 'Switchable', now() + interval '5 days', null, null, null, null, array[15], '{"call": true}')$q$, ev)) = '42501', 'only an organiser can switch it on');
  perform pg_temp.root();

  -- Cancelling the event turns the link off.
  e := pg_temp.chat_event('ada', 'To cancel', 5 * 24 * 60, '{"call": true}');
  v_code := e ->> 'call_link_code';
  perform pg_temp.expect(pg_temp.opens('bob', v_code) = 'ok', 'it opens before');
  perform pg_temp.act(pg_temp.i('ada'));
  e := public.cancel_chat_event((e ->> 'id')::uuid);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.opens('bob', v_code) = 'revoked', 'cancelling the event turns its link off');
  perform pg_temp.expect(e ->> 'call_link_code' is null, 'and the payload shows none');

  -- An event that ran out of link shows none.
  e := pg_temp.chat_event('ada', 'Old news', 60, '{"call": true}');
  update public.call_links set expires_at = now() - interval '1 minute' where code = e ->> 'call_link_code';
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(public.get_chat_event((e ->> 'id')::uuid) ->> 'call_link_code' is null, 'once the link has expired the event shows no call');
  perform pg_temp.root();
end $$;

-- ===================================== 5. repeating events hand the call on
do $$
declare
  e jsonb;
  first_id uuid;
  series uuid;
  second_id uuid;
  third_id uuid;
  first_code text;
  second_code text;
  made integer;
begin
  e := pg_temp.chat_event('ada', 'Weekly stand-up', 60, '{"call": true, "recurrence": "weekly", "timezone": "UTC"}', 'g1', 30);
  first_id := (e ->> 'id')::uuid;
  first_code := e ->> 'call_link_code';
  select series_id into series from public.chat_events where id = first_id;
  perform pg_temp.expect(first_code is not null and series is not null, 'a weekly event with a call');

  made := public.events2_spawn_next(now() + interval '2 hours');
  perform pg_temp.expect(made >= 1, 'the next occurrence is made');
  select x.id, x.call_link_code into second_id, second_code from public.chat_events x where x.series_id = series and x.id <> first_id;
  perform pg_temp.expect(second_code is not null and second_code <> first_code, 'it has a call link of its own');
  perform pg_temp.expect((select cl.expires_at from public.call_links cl where cl.code = second_code) = (select x.ends_at + interval '1 hour' from public.chat_events x where x.id = second_id), 'which works until an hour after that occurrence ends');
  perform pg_temp.expect(pg_temp.opens('bob', second_code) = 'ok', 'and opens');
  perform pg_temp.expect((select cl.created_by from public.call_links cl where cl.code = second_code) = pg_temp.i('ada'), 'in the organiser''s name');

  -- The organiser takes the call off this occurrence: the next one has none.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.update_chat_event(
    second_id, 'Weekly stand-up',
    (select x.starts_at from public.chat_events x where x.id = second_id),
    (select x.ends_at from public.chat_events x where x.id = second_id),
    null, null, null, array[15], '{"call": false}');
  perform pg_temp.root();
  made := public.events2_spawn_next(now() + interval '9 days');
  select x.id into third_id from public.chat_events x where x.series_id = series and x.id not in (first_id, second_id);
  perform pg_temp.expect(third_id is not null, 'the third occurrence is made');
  perform pg_temp.expect((select x.call_link_code from public.chat_events x where x.id = third_id) is null, 'with no call, as the one before had none');

  -- A series with no call makes none.
  e := pg_temp.chat_event('ada', 'Plain weekly', 60, '{"recurrence": "weekly", "timezone": "UTC"}');
  perform public.events2_spawn_next(now() + interval '2 hours');
  perform pg_temp.expect(not exists (
    select 1 from public.chat_events x where x.title = 'Plain weekly' and x.call_link_code is not null
  ), 'a series without a call stays without');
end $$;

-- ===================================== 6. the reminder
do $$
declare
  e jsonb;
  zh record;
  en record;
begin
  delete from public.chat_event_reminders;
  delete from public.push_subscriptions;
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
  values (pg_temp.i('bob'), 'https://push.example.com/bob-zh', repeat('k', 60), repeat('a', 20), 'zh'),
         (pg_temp.i('cat'), 'https://push.example.com/cat-en', repeat('k', 60), repeat('a', 20), 'en');

  -- Soon, with a call.
  e := pg_temp.chat_event('ada', 'Standup call', 10, '{"call": true}');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.rsvp_chat_event((e ->> 'id')::uuid, 'going');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.rsvp_chat_event((e ->> 'id')::uuid, 'maybe');
  perform pg_temp.root();
  perform public.chat_event_due_reminders(now());
  perform pg_temp.claim();
  select * into zh from pg_temp.claims c where c.endpoint like '%bob-zh' and c.title = 'Standup call';
  select * into en from pg_temp.claims c where c.endpoint like '%cat-en' and c.title = 'Standup call';
  perform pg_temp.expect(zh.body like '%分钟后开始 · 点按加入通话' and zh.call_link_code = e ->> 'call_link_code', 'a Chinese device is told it starts in minutes and to tap to join, with the code');
  perform pg_temp.expect(en.body like 'Starts in % minutes · Tap to join the call' and en.call_link_code = e ->> 'call_link_code', 'an English one in English');
  perform pg_temp.expect(zh.conversation_id = pg_temp.i('g1') and zh.title = 'Standup call', 'the push still carries the chat (so a locked chat is masked) and the title');
  perform pg_temp.claim();
  perform pg_temp.expect((select count(*) from pg_temp.claims) = 0, 'a reminder is pushed once');

  -- Soon, without a call: as before.
  delete from public.chat_event_reminders;
  e := pg_temp.chat_event('ada', 'No call here', 10);
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.rsvp_chat_event((e ->> 'id')::uuid, 'going');
  perform pg_temp.root();
  perform public.chat_event_due_reminders(now());
  perform pg_temp.claim();
  select * into zh from pg_temp.claims c where c.endpoint like '%bob-zh' and c.title = 'No call here';
  perform pg_temp.expect(zh.body like '%分钟后开始' and zh.body not like '%通话%' and zh.call_link_code is null, 'an event without a call is worded as before');

  -- The hour before: says there is a call, but no link to open yet.
  delete from public.chat_event_reminders;
  e := pg_temp.chat_event('ada', 'Later call', 2 * 24 * 60, '{"call": true}');
  update public.chat_events set reminder_leads = array[15, 60] where id = (e ->> 'id')::uuid;
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.rsvp_chat_event((e ->> 'id')::uuid, 'going');
  perform pg_temp.root();
  perform public.chat_event_due_reminders((select x.starts_at from public.chat_events x where x.id = (e ->> 'id')::uuid) - interval '59 minutes');
  perform pg_temp.claim();
  select * into zh from pg_temp.claims c where c.endpoint like '%bob-zh' and c.title = 'Later call';
  perform pg_temp.expect(zh.body = '约 1 小时后开始 · 附带通话' and zh.call_link_code is null, 'the 1 hour reminder says there is a call and opens the chat');

  -- A muted chat and a cancelled event get nothing, as before.
  delete from public.chat_event_reminders;
  e := pg_temp.chat_event('ada', 'Muted call', 10, '{"call": true}');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.rsvp_chat_event((e ->> 'id')::uuid, 'going');
  perform pg_temp.root();
  perform public.chat_event_due_reminders(now());
  update public.conversation_members set muted_until = now() + interval '1 day' where conversation_id = pg_temp.i('g1') and user_id = pg_temp.i('bob');
  perform pg_temp.claim();
  perform pg_temp.expect((select count(*) from pg_temp.claims c where c.endpoint like '%bob-zh') = 0, 'a chat the person muted gets no reminder');
  update public.conversation_members set muted_until = null where conversation_id = pg_temp.i('g1') and user_id = pg_temp.i('bob');
end $$;

-- ===================================== 7. My agenda and the calendar feed
do $$
declare
  e jsonb;
  row_meta jsonb;
begin
  e := pg_temp.chat_event('ada', 'Agenda call', 6 * 60, '{"call": true}');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.rsvp_chat_event((e ->> 'id')::uuid, 'going');
  select a.meta into row_meta from public.get_my_agenda(now(), now() + interval '2 days') a where a.target_id = (e ->> 'id')::uuid;
  perform pg_temp.expect(row_meta ->> 'call_link_code' = e ->> 'call_link_code' and row_meta ->> 'status' = 'going', 'My agenda carries the call code and keeps the answer');
  select a.meta into row_meta from public.get_my_agenda(now(), now() + interval '2 days') a where a.title = 'No call here';
  perform pg_temp.expect(row_meta ? 'status' and row_meta ->> 'call_link_code' is null, 'an event without a call has a null code');
  perform pg_temp.root();

  -- agenda_items_for_user is the door of the calendar feed.
  select a.meta into row_meta from public.agenda_items_for_user(
    pg_temp.i('bob'), now(), now() + interval '2 days', array['chat_event']
  ) a where a.target_id = (e ->> 'id')::uuid;
  perform pg_temp.expect(row_meta ->> 'call_link_code' = e ->> 'call_link_code', 'the feed''s door has it too');

  -- Cancelled: gone from the agenda as before.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.cancel_chat_event((e ->> 'id')::uuid);
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(not exists (select 1 from public.get_my_agenda(now(), now() + interval '2 days') a where a.target_id = (e ->> 'id')::uuid), 'a cancelled event leaves the agenda');
  perform pg_temp.root();
end $$;

-- ===================================== 8. data export, the purge, deleting an account
do $$
declare
  exported jsonb;
  made integer;
begin
  exported := public.export_my_scheduled_calls(pg_temp.i('ada'));
  perform pg_temp.expect(jsonb_array_length(exported) >= 5, 'the export lists the events ada made with a call');
  perform pg_temp.expect(not exists (
    select 1 from public.chat_events x
    where x.call_link_code is not null and position(x.call_link_code in exported::text) > 0
  ), 'it never holds a link''s code');
  perform pg_temp.expect((exported -> 0) ? 'title' and (exported -> 0) ? 'link_works_until', 'but the title and when it works until');
  perform pg_temp.expect(public.export_my_scheduled_calls(pg_temp.i('eve')) = '[]'::jsonb, 'a stranger''s export is empty');
  perform pg_temp.expect(public.export_my_scheduled_calls(pg_temp.i('bob')) = '[]'::jsonb, 'and so is a member''s who made none');
  -- It travels inside the Events 2.0 export, which keeps everything it had.
  exported := public.export_my_events2(pg_temp.i('ada'));
  perform pg_temp.expect(jsonb_array_length(exported -> 'calls_made') >= 5 and exported ? 'signed_up' and exported ? 'events_made' and exported ? 'photos', 'export_my_events2 has calls_made next to all it had');
  perform pg_temp.expect(public.export_my_events2(pg_temp.i('eve')) -> 'calls_made' = '[]'::jsonb, 'empty for a stranger');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.export_my_scheduled_calls(%L)', pg_temp.i('ada'))) = '42501' and pg_temp.state(format('select public.export_my_events2(%L)', pg_temp.i('ada'))) = '42501', 'clients cannot call the exports');
  perform pg_temp.root();
  perform pg_temp.expect(has_function_privilege('service_role', 'public.export_my_scheduled_calls(uuid)', 'execute'), 'the data-export function can');

  -- The purge removes event links that ended over a week ago, not the others, not personal ones.
  insert into public.call_links (code, created_by, conversation_id, expires_at)
  values ('personal0001', pg_temp.i('ada'), pg_temp.i('g1'), now() - interval '30 days');
  update public.call_links set expires_at = now() - interval '8 days'
  where code = (select x.call_link_code from public.chat_events x where x.title = 'Old news');
  made := public.purge_scheduled_call_links();
  perform pg_temp.expect(made = 1, 'the daily purge removes only event links over a week old');
  perform pg_temp.expect(exists (select 1 from public.call_links where code = 'personal0001'), 'and leaves a person''s own links');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state('select public.purge_scheduled_call_links()') = '42501', 'but a client cannot run it');
  perform pg_temp.root();

  -- Deleting an account turns the person's links off.
  perform pg_temp.expect(pg_temp.opens('bob', (select x.call_link_code from public.chat_events x where x.title = 'Thursday sync')) = 'ok', 'a link opens before the organiser leaves');
  update public.profiles set deleted_at = now() where id = pg_temp.i('ada');
  perform pg_temp.expect(pg_temp.opens('bob', (select x.call_link_code from public.chat_events x where x.title = 'Thursday sync')) = 'revoked', 'deleting the account turns the links of its events off');

  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform pg_temp.expect(exists (select 1 from cron.job where jobname = 'wecord-scheduled-call-links-purge' and schedule = '41 4 * * *'), 'the purge is a cron job of its own');
    perform pg_temp.expect((select command from cron.job where jobname = 'wecord-later-dispatch') not like '%scheduled_call%', 'and the every-minute dispatcher does not run it');
  end if;
end $$;

\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'scheduled calls: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
