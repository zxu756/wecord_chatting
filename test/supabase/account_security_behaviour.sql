-- Behaviour checks for two-step recovery codes and passkeys (G4: migrations
-- 202610280400 to 202610280430). Run by test/supabase/account_security_test.dart
-- against the local database: it applies the migrations in a transaction,
-- plays people through them, and rolls everything back. Run from the
-- repository root.
--
-- What it walks through: what is closed to clients; making codes (only from a
-- session that just passed the authenticator, ten at a time, replacing the
-- old set, only a salted hash kept, at most five sets an hour); trying a code
-- (typing variants, a used code, the lock after five wrong ones, someone
-- else's account); finishing a recovery (the code given back when removing
-- the authenticator failed, the rest erased when it worked); the security
-- record and its answers; the passkey and authenticator triggers on Auth's
-- tables (including deleting a login that has a passkey); the pushes in
-- Chinese and English; the export; deleting an account.
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

-- Becomes [user_id] (null: nobody signed in) with the claims of a session at
-- [aal]; [totp_age] is how many seconds ago a code from the authenticator
-- app was entered in it (null: never).
create function pg_temp.act(user_id uuid, aal text default 'aal1', totp_age integer default null) returns void language plpgsql as $$
declare
  now_s bigint := extract(epoch from now())::bigint;
  amr jsonb := jsonb_build_array(jsonb_build_object('method', 'password', 'timestamp', now_s - 3600));
begin
  execute 'reset role';
  if user_id is null then
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    execute 'set local role anon';
  else
    if totp_age is not null then
      amr := amr || jsonb_build_array(jsonb_build_object('method', 'totp', 'timestamp', now_s - totp_age));
    end if;
    perform set_config('request.jwt.claim.sub', user_id::text, true);
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object('sub', user_id, 'role', 'authenticated', 'aal', aal, 'amr', amr)::text,
      true
    );
    execute 'set local role authenticated';
  end if;
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

-- The codes a person was shown, kept so the script can type them.
create temp table shown (who text, n integer, code text);
grant all on shown to public;

grant execute on all functions in schema pg_temp to public;

-- ------------------------------------------------------------------ cast
-- ada has two-step verification and uses everything; bob is another account;
-- cat is for the limit on making codes, dan for deleting a login with a
-- passkey, eve for passkeys.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@g4.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_g4', initcap(name)
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve')) v(n, name);

-- ada's authenticator app, verified.
insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at, secret)
values (gen_random_uuid(), pg_temp.i('ada'), 'Authenticator app', 'totp', 'verified', now(), now(), 'JBSWY3DPEHPK3PXP');

grant execute on all functions in schema pg_temp to public;

-- ===================================== 1. what is closed, what is not
do $$
begin
  perform pg_temp.expect(not exists (
    select 1 from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name in ('mfa_recovery_codes', 'mfa_recovery_attempts', 'account_security_events')
      and grantee in ('anon', 'authenticated', 'PUBLIC')
  ), 'the three tables are closed to clients');
  perform pg_temp.expect(
    not has_function_privilege('authenticated', 'public.consume_mfa_recovery_code(uuid, text)', 'execute')
    and not has_function_privilege('anon', 'public.consume_mfa_recovery_code(uuid, text)', 'execute')
    and has_function_privilege('service_role', 'public.consume_mfa_recovery_code(uuid, text)', 'execute'),
    'only the service role can try a code for someone');
  perform pg_temp.expect(
    not has_function_privilege('authenticated', 'public.finish_mfa_recovery(uuid, uuid, boolean, integer)', 'execute')
    and not has_function_privilege('authenticated', 'public.claim_account_security_pushes()', 'execute')
    and not has_function_privilege('authenticated', 'public.export_my_account_security(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.record_account_security_event(uuid, text, jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'public.recovery_code_hash(text, text)', 'execute'),
    'finishing, pushing, exporting, recording and hashing are not for clients');
  perform pg_temp.expect(
    has_function_privilege('authenticated', 'public.generate_mfa_recovery_codes()', 'execute')
    and not has_function_privilege('anon', 'public.generate_mfa_recovery_codes()', 'execute')
    and not has_function_privilege('anon', 'public.my_mfa_recovery_status()', 'execute')
    and not has_function_privilege('anon', 'public.list_my_security_events()', 'execute')
    and not has_function_privilege('anon', 'public.resolve_security_event(uuid, text)', 'execute'),
    'making codes, the status and the record are for signed-in people only');
  perform pg_temp.expect(
    (select bool_and(p.prosecdef and p.proconfig::text like '%search_path=public%')
     from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('generate_mfa_recovery_codes', 'my_mfa_recovery_status', 'consume_mfa_recovery_code',
         'finish_mfa_recovery', 'list_my_security_events', 'resolve_security_event',
         'claim_account_security_pushes', 'export_my_account_security', 'record_account_security_event',
         'passkey_security_event', 'mfa_factor_removed_forget_codes')),
    'every function is security definer with search_path = public');
  perform pg_temp.expect(
    pg_get_functiondef('public.claim_security_alert_pushes()'::regprocedure) like '%你的账号在新设备上登录%'
    and pg_get_functiondef('public.run_later_dispatch()'::regprocedure) not like '%account_security%'
    and pg_get_functiondef('public.user_devices_login_alert()'::regprocedure) like '%login_alerts%',
    'new-login alerts and the every-minute dispatcher are not touched');
end $$;

-- ===================================== 2. making codes
select pg_temp.act(null);
select pg_temp.expect(pg_temp.state('select public.generate_mfa_recovery_codes()') = '42501', 'nobody signed in cannot make codes');

select pg_temp.act(pg_temp.i('ada'), 'aal1', null);
select pg_temp.expect(pg_temp.msg('select public.generate_mfa_recovery_codes()') = 'aal2_required', 'a session that has not passed the authenticator is refused');
select pg_temp.act(pg_temp.i('ada'), 'aal2', null);
select pg_temp.expect(pg_temp.msg('select public.generate_mfa_recovery_codes()') = 'fresh_verification_required', 'aal2 with no code from the authenticator in the token is refused');
select pg_temp.act(pg_temp.i('ada'), 'aal2', 1200);
select pg_temp.expect(pg_temp.msg('select public.generate_mfa_recovery_codes()') = 'fresh_verification_required', 'a code entered 20 minutes ago is too old');
select pg_temp.root();
select pg_temp.expect(not exists (select 1 from public.mfa_recovery_codes) and not exists (select 1 from public.account_security_events), 'nothing was made or recorded by the refusals');

select pg_temp.act(pg_temp.i('ada'), 'aal2', 30);
insert into pg_temp.shown select 'ada', n, code from unnest(public.generate_mfa_recovery_codes()) with ordinality as t(code, n);
select pg_temp.root();
do $$
begin
  perform pg_temp.expect((select count(*) = 10 from pg_temp.shown where who = 'ada'), 'ten codes are shown');
  perform pg_temp.expect((select bool_and(code ~ '^[A-HJ-NP-Z2-9]{5}-[A-HJ-NP-Z2-9]{5}$') from pg_temp.shown where who = 'ada'), 'written XXXXX-XXXXX from letters and digits without look-alikes');
  perform pg_temp.expect((select count(distinct code) = 10 from pg_temp.shown where who = 'ada'), 'all different');
  perform pg_temp.expect((select count(*) = 10 and count(distinct salt) = 10 and bool_and(used_at is null) from public.mfa_recovery_codes where user_id = pg_temp.i('ada')), 'ten stored, each with its own salt, none used');
  perform pg_temp.expect(not exists (
    select 1 from public.mfa_recovery_codes c, pg_temp.shown s
    where s.who = 'ada' and (c.code_hash ilike '%' || replace(s.code, '-', '') || '%' or c.salt ilike '%' || replace(s.code, '-', '') || '%')
  ), 'a code is nowhere in the table');
  perform pg_temp.expect(not exists (
    select 1 from public.mfa_recovery_codes c
    where c.code_hash !~ '^[0-9a-f]{64}$'
  ), 'only a SHA-256 hash is kept');
  perform pg_temp.expect((
    select count(*) = 10
    from pg_temp.shown s
    join public.mfa_recovery_codes c
      on c.user_id = pg_temp.i('ada')
     and c.code_hash = encode(extensions.digest(c.salt || replace(s.code, '-', ''), 'sha256'), 'hex')
    where s.who = 'ada'
  ), 'the hash is the salt and the code, hashed');
  perform pg_temp.expect((select count(*) = 1 from public.account_security_events where user_id = pg_temp.i('ada') and kind = 'recovery_codes_generated'), 'making codes is in the security record');
end $$;

select pg_temp.act(pg_temp.i('ada'), 'aal2', 30);
select pg_temp.expect((select remaining = 10 and total = 10 and locked_until is null from public.my_mfa_recovery_status()), 'the status counts ten');
select pg_temp.act(pg_temp.i('bob'), 'aal1', null);
select pg_temp.expect((select remaining = 0 and total = 0 from public.my_mfa_recovery_status()), 'and shows nothing of ada to bob');
select pg_temp.expect(pg_temp.state('select * from public.mfa_recovery_codes') = '42501', 'a client cannot read the table');
select pg_temp.root();

-- A new set replaces the old one.
create temp table old_codes as select code from pg_temp.shown where who = 'ada';
grant all on old_codes to public;
delete from pg_temp.shown where who = 'ada';
select pg_temp.act(pg_temp.i('ada'), 'aal2', 60);
insert into pg_temp.shown select 'ada', n, code from unnest(public.generate_mfa_recovery_codes()) with ordinality as t(code, n);
select pg_temp.root();
do $$
begin
  perform pg_temp.expect((select count(*) = 10 from public.mfa_recovery_codes where user_id = pg_temp.i('ada')), 'making new codes leaves ten, not twenty');
  perform pg_temp.expect(not exists (select 1 from old_codes o join pg_temp.shown s on s.code = o.code), 'the new codes are not the old ones');
  perform pg_temp.expect(
    (public.consume_mfa_recovery_code(pg_temp.i('ada'), (select code from old_codes limit 1))) ->> 'reason' = 'invalid',
    'an old code no longer works');
end $$;

-- ===================================== 3. using a code
do $$
declare
  r jsonb;
  c1 text := (select code from pg_temp.shown where who = 'ada' and n = 1);
  c2 text := (select code from pg_temp.shown where who = 'ada' and n = 2);
begin
  -- The failure above counted once. Four more are left before the lock.
  perform pg_temp.expect((select failed_count = 1 from public.mfa_recovery_attempts where user_id = pg_temp.i('ada')), 'a wrong code is counted');

  r := public.consume_mfa_recovery_code(pg_temp.i('ada'), lower(replace(c1, '-', ' ')));
  perform pg_temp.expect((r ->> 'ok')::boolean and (r ->> 'remaining')::int = 9 and r ->> 'code_id' is not null,
    'a right code works however it is typed (lower case, a space for the dash)');
  perform pg_temp.expect((select failed_count = 0 and locked_until is null from public.mfa_recovery_attempts where user_id = pg_temp.i('ada')), 'and clears the count');
  r := public.consume_mfa_recovery_code(pg_temp.i('ada'), c1);
  perform pg_temp.expect(r ->> 'reason' = 'invalid' and (r ->> 'attempts_left')::int = 4, 'the same code twice does not work');
  perform pg_temp.expect((select count(*) = 1 from public.mfa_recovery_codes where user_id = pg_temp.i('ada') and used_at is not null), 'exactly one is used up');

  -- Bad shapes are wrong codes, not errors.
  r := public.consume_mfa_recovery_code(pg_temp.i('ada'), '');
  perform pg_temp.expect(r ->> 'reason' = 'invalid' and (r ->> 'attempts_left')::int = 3, 'an empty code is a wrong one');
  r := public.consume_mfa_recovery_code(pg_temp.i('ada'), null);
  perform pg_temp.expect(r ->> 'reason' = 'invalid' and (r ->> 'attempts_left')::int = 2, 'so is null');
  r := public.consume_mfa_recovery_code(pg_temp.i('ada'), left(replace(c2, '-', ''), 9));
  perform pg_temp.expect(r ->> 'reason' = 'invalid' and (r ->> 'attempts_left')::int = 1, 'so is a code with a character missing');

  -- The fifth failure locks.
  r := public.consume_mfa_recovery_code(pg_temp.i('ada'), 'AAAAA-AAAAA');
  perform pg_temp.expect(r ->> 'reason' = 'locked' and (r ->> 'retry_after_seconds')::int = 1800, 'the fifth wrong code locks for 30 minutes');
  perform pg_temp.expect((select count(*) = 1 from public.account_security_events where user_id = pg_temp.i('ada') and kind = 'recovery_locked'), 'and is in the security record');
  r := public.consume_mfa_recovery_code(pg_temp.i('ada'), c2);
  perform pg_temp.expect(r ->> 'reason' = 'locked' and (r ->> 'retry_after_seconds')::int > 1700, 'while locked even the right code is refused');
  perform pg_temp.expect((select count(*) = 1 from public.mfa_recovery_codes where user_id = pg_temp.i('ada') and used_at is not null), 'and nothing is used up');
  r := public.consume_mfa_recovery_code(pg_temp.i('ada'), 'AAAAA-AAAAA');
  perform pg_temp.expect(r ->> 'reason' = 'locked'
    and (select count(*) = 1 from public.account_security_events where user_id = pg_temp.i('ada') and kind = 'recovery_locked'),
    'trying again while locked does not raise another alert');

  -- The lock runs out.
  update public.mfa_recovery_attempts set locked_until = now() - interval '1 second' where user_id = pg_temp.i('ada');
  r := public.consume_mfa_recovery_code(pg_temp.i('ada'), 'AAAAA-AAAAA');
  perform pg_temp.expect(r ->> 'reason' = 'invalid' and (r ->> 'attempts_left')::int = 4, 'after the lock the count starts again');
  update public.mfa_recovery_attempts set locked_until = now() - interval '1 second', failed_count = 0 where user_id = pg_temp.i('ada');
  r := public.consume_mfa_recovery_code(pg_temp.i('ada'), c2);
  perform pg_temp.expect((r ->> 'ok')::boolean and (r ->> 'remaining')::int = 8, 'and a right code works again');
  insert into pg_temp.ids values ('used_code', (r ->> 'code_id')::uuid);

  -- Not someone else's.
  r := public.consume_mfa_recovery_code(pg_temp.i('bob'), c1);
  perform pg_temp.expect(r ->> 'reason' = 'no_codes', 'bob, who has no codes, gets nothing from ada''s');
  perform pg_temp.expect((select count(*) = 10 from public.mfa_recovery_codes where user_id = pg_temp.i('ada')), 'and nothing of ada''s changed');
end $$;

-- A client cannot call the consuming functions at all.
select pg_temp.act(pg_temp.i('ada'), 'aal1', null);
select pg_temp.expect(pg_temp.state($$select public.consume_mfa_recovery_code(auth.uid(), 'AAAAA-AAAAA')$$) = '42501', 'a signed-in client cannot try a code through the database');
select pg_temp.expect(pg_temp.state($$select public.finish_mfa_recovery(auth.uid(), gen_random_uuid(), true, 0)$$) = '42501', 'nor finish a recovery');
select pg_temp.root();

-- ===================================== 4. finishing
do $$
begin
  -- Failure: the code is given back.
  perform public.finish_mfa_recovery(pg_temp.i('ada'), pg_temp.i('used_code'), false);
  perform pg_temp.expect((select used_at is null from public.mfa_recovery_codes where id = pg_temp.i('used_code')) and (select count(*) = 1 from public.mfa_recovery_codes where user_id = pg_temp.i('ada') and used_at is not null), 'if the authenticator could not be removed the code is given back (only that one; the first stays used)');
  perform pg_temp.expect((select count(*) = 0 from public.account_security_events where user_id = pg_temp.i('ada') and kind = 'recovery_code_used'), 'and nothing is recorded');

  -- Someone else's account cannot be used to give a code back.
  update public.mfa_recovery_codes set used_at = now() where id = pg_temp.i('used_code');
  perform public.finish_mfa_recovery(pg_temp.i('bob'), pg_temp.i('used_code'), false);
  perform pg_temp.expect((select used_at is not null from public.mfa_recovery_codes where id = pg_temp.i('used_code')), 'giving a code back only works for its own account');

  -- Success: recorded, and the rest of the codes go.
  perform public.finish_mfa_recovery(pg_temp.i('ada'), pg_temp.i('used_code'), true, 8);
  perform pg_temp.expect((select count(*) = 0 from public.mfa_recovery_codes where user_id = pg_temp.i('ada')), 'after a recovery the other codes are gone (two-step is off)');
  perform pg_temp.expect((select count(*) = 1 and bool_and((detail ->> 'remaining')::int = 8) from public.account_security_events where user_id = pg_temp.i('ada') and kind = 'recovery_code_used'), 'and it is in the security record');
end $$;
select pg_temp.act(pg_temp.i('ada'), 'aal1', null);
select pg_temp.expect((select remaining = 0 and total = 0 from public.my_mfa_recovery_status()), 'the status then shows none');
select pg_temp.root();

-- ===================================== 5. the limit on making codes
select pg_temp.act(pg_temp.i('cat'), 'aal2', 10);
do $$
declare
  n integer;
  outcome text := 'ok';
begin
  for n in 1..5 loop
    perform public.generate_mfa_recovery_codes();
  end loop;
  begin
    perform public.generate_mfa_recovery_codes();
  exception when others then
    outcome := sqlerrm;
  end;
  perform pg_temp.expect(outcome = 'rate_limited', 'the sixth set within an hour is refused');
end $$;
select pg_temp.root();
select pg_temp.expect((select count(*) = 10 from public.mfa_recovery_codes where user_id = pg_temp.i('cat')), 'and the fifth set is the one that stands');

-- ===================================== 6. the record
insert into public.account_security_events (user_id, kind, detail) values (pg_temp.i('bob'), 'passkey_added', '{"name":"Bob phone"}');
insert into pg_temp.ids select 'ada_event', id from public.account_security_events where user_id = pg_temp.i('ada') and kind = 'recovery_code_used';
insert into pg_temp.ids select 'bob_event', id from public.account_security_events where user_id = pg_temp.i('bob');
select pg_temp.act(pg_temp.i('ada'), 'aal1', null);
select pg_temp.expect((select count(*) = 4 from public.list_my_security_events()), 'ada sees her own four events (made twice, locked, used)');
select pg_temp.expect(not exists (select 1 from public.list_my_security_events() where kind = 'passkey_added'), 'and none of bob''s');
select pg_temp.expect(pg_temp.state(format($$select public.resolve_security_event(%L, 'denied')$$, pg_temp.i('bob_event'))) = '42501', 'ada cannot answer bob''s event');
select pg_temp.expect(pg_temp.state(format($$select public.resolve_security_event(%L, 'whatever')$$, pg_temp.i('ada_event'))) = '22023', 'an unknown answer is refused');
select public.resolve_security_event(pg_temp.i('ada_event'), 'denied');
select public.resolve_security_event(pg_temp.i('ada_event'), 'confirmed');
select pg_temp.expect((select resolution = 'denied' from public.list_my_security_events() where id = pg_temp.i('ada_event')), 'an event is answered once; the first answer stays');
select pg_temp.root();

-- ===================================== 7. passkeys and the authenticator, as Auth changes them
do $$
declare
  cred uuid := gen_random_uuid();
begin
  if to_regclass('auth.webauthn_credentials') is null then
    return;
  end if;
  perform pg_temp.expect(exists (select 1 from pg_trigger where tgname = 'passkey_security_event' and tgrelid = 'auth.webauthn_credentials'::regclass), 'the passkey trigger is installed');
  insert into auth.webauthn_credentials (id, user_id, credential_id, public_key, friendly_name)
  values (cred, pg_temp.i('eve'), decode('0102030405', 'hex'), decode('aabbcc', 'hex'), 'iCloud Keychain');
  perform pg_temp.expect((select count(*) = 1 and bool_and(detail ->> 'name' = 'iCloud Keychain') from public.account_security_events where user_id = pg_temp.i('eve') and kind = 'passkey_added'), 'adding a passkey is recorded, with its name');
  delete from auth.webauthn_credentials where id = cred;
  perform pg_temp.expect((select count(*) = 1 from public.account_security_events where user_id = pg_temp.i('eve') and kind = 'passkey_removed'), 'removing it is recorded');

  -- Deleting the login removes the passkeys and must not fail or write.
  insert into auth.webauthn_credentials (id, user_id, credential_id, public_key, friendly_name)
  values (gen_random_uuid(), pg_temp.i('dan'), decode('0a0b0c0d', 'hex'), decode('aabbcc', 'hex'), 'Dan key');
  delete from public.account_security_events where user_id = pg_temp.i('dan');
  delete from auth.users where id = pg_temp.i('dan');
  perform pg_temp.expect(not exists (select 1 from auth.webauthn_credentials where user_id = pg_temp.i('dan'))
    and not exists (select 1 from public.account_security_events where user_id = pg_temp.i('dan')), 'deleting an account with a passkey works and records nothing');
end $$;

do $$
declare
  factor uuid := gen_random_uuid();
  other uuid := gen_random_uuid();
begin
  -- bob gets a verified authenticator, an unfinished one and some codes.
  insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at, secret)
  values (factor, pg_temp.i('bob'), 'Authenticator app', 'totp', 'verified', now(), now(), 'JBSWY3DPEHPK3PXP'),
         (other, pg_temp.i('bob'), 'Other', 'totp', 'unverified', now() + interval '1 second', now(), 'JBSWY3DPEHPK3PXP');
  insert into public.mfa_recovery_codes (user_id, salt, code_hash) values (pg_temp.i('bob'), 'a', 'b');
  delete from auth.mfa_factors where id = other;
  perform pg_temp.expect(exists (select 1 from public.mfa_recovery_codes where user_id = pg_temp.i('bob')), 'dropping an unfinished authenticator keeps the codes');
  delete from auth.mfa_factors where id = factor;
  perform pg_temp.expect(not exists (select 1 from public.mfa_recovery_codes where user_id = pg_temp.i('bob')), 'turning two-step verification off removes the codes');
end $$;

-- ===================================== 8. pushes
insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language, created_at)
values
  (pg_temp.i('ada'), 'https://push.example/ada-zh', repeat('k', 60), repeat('a', 20), 'zh', now() - interval '1 hour'),
  (pg_temp.i('ada'), 'https://push.example/ada-en', repeat('k', 60), repeat('a', 20), 'en', now() - interval '1 day'),
  (pg_temp.i('ada'), 'https://push.example/ada-new', repeat('k', 60), repeat('a', 20), 'en', now() + interval '1 minute'),
  (pg_temp.i('eve'), 'https://push.example/eve-zh', repeat('k', 60), repeat('a', 20), 'zh', now() - interval '1 hour');

-- Every event so far is waiting for its push. Ada's are an hour old at
-- most; make the first one old enough to be news no more.
update public.account_security_events set created_at = now() - interval '1 hour' where user_id = pg_temp.i('ada');
create temp table pushes as select * from public.claim_account_security_pushes();
grant all on pushes to public;
do $$
begin
  perform pg_temp.expect(not exists (select 1 from pushes p join public.push_subscriptions s on s.id = p.subscription_id where s.user_id = pg_temp.i('ada')),
    'events that are an hour old produce no push');
  perform pg_temp.expect(exists (select 1 from pushes p join public.push_subscriptions s on s.id = p.subscription_id where s.user_id = pg_temp.i('eve')), 'eve''s device is told about her passkeys');
  perform pg_temp.expect((select bool_and(p.url = '/#/notifications' and p.tag like 'account-security-%' and p.conversation_id is null) from pushes p), 'a push opens Notifications and has its own tag');
  perform pg_temp.expect((select bool_and(p.title ~ '[一-鿿]' and p.body ~ '[一-鿿]' and p.body ~ '<t:[0-9]+:f>') from pushes p join public.push_subscriptions s on s.id = p.subscription_id where s.endpoint = 'https://push.example/eve-zh'), 'a Chinese device gets Chinese text with a time token');
end $$;
select pg_temp.expect(not exists (select 1 from public.claim_account_security_pushes()), 'an event is pushed once');

-- Fresh events: Chinese and English devices, worded by kind.
insert into public.account_security_events (user_id, kind, detail) values (pg_temp.i('ada'), 'recovery_code_used', '{"remaining":3}'), (pg_temp.i('ada'), 'passkey_added', '{"name":"Work <b>laptop</b>"}');
create temp table pushes2 as select * from public.claim_account_security_pushes();
grant all on pushes2 to public;
do $$
begin
  perform pg_temp.expect((select count(*) = 4 from pushes2), 'two events to two older devices are four pushes');
  perform pg_temp.expect((select count(*) = 2 and bool_and(p.title = '有人用恢复码通过了两步验证' or p.title = '你的账号新增了通行密钥') from pushes2 p join public.push_subscriptions s on s.id = p.subscription_id where s.endpoint = 'https://push.example/ada-zh'), 'the Chinese device gets Chinese titles');
  perform pg_temp.expect((select count(*) = 2 and bool_and(p.title = 'A recovery code was used to sign in' or p.title = 'A passkey was added to your account') from pushes2 p join public.push_subscriptions s on s.id = p.subscription_id where s.endpoint = 'https://push.example/ada-en'), 'the English device gets English titles');
  perform pg_temp.expect(not exists (select 1 from pushes2 where body like '%<b>%' or body like '%</b>%'), 'angle brackets in a passkey name are dropped, so it cannot pass for a time token');
  perform pg_temp.expect(exists (select 1 from pushes2 where body like 'Work blaptop/b, <t:%:f>. Not you?%'), 'the name is in the text');
end $$;

-- ===================================== 9. the export
do $$
declare
  e jsonb;
begin
  insert into public.mfa_recovery_codes (user_id, salt, code_hash) values (pg_temp.i('ada'), 'pepper', 'digest');
  e := public.export_my_account_security(pg_temp.i('ada'));
  perform pg_temp.expect(jsonb_array_length(e -> 'events') >= 4, 'the export lists the events');
  perform pg_temp.expect((e -> 'recovery_codes' ->> 'remaining')::int = 1, 'and how many codes are left');
  perform pg_temp.expect(e::text not like '%pepper%' and e::text not like '%digest%' and e::text not like '%code_hash%' and e::text not like '%salt%', 'but never a hash or a salt');
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(e -> 'events') x where x ->> 'kind' is null), 'every event has a kind');
  perform pg_temp.expect(jsonb_typeof(e -> 'passkeys') = 'array', 'the passkeys are a list');
  e := public.export_my_account_security(pg_temp.i('bob'));
  perform pg_temp.expect(e::text not like '%laptop%', 'and one person''s export has none of another''s');
  perform pg_temp.expect(pg_temp.state('select public.export_my_account_security(null)') = '22023', 'a user is required');
end $$;

-- ===================================== 10. deleting an account
do $$
begin
  insert into public.mfa_recovery_attempts (user_id, failed_count) values (pg_temp.i('ada'), 2) on conflict (user_id) do update set failed_count = 2;
  update public.profiles set deleted_at = now() where id = pg_temp.i('ada');
  perform pg_temp.expect(not exists (select 1 from public.mfa_recovery_codes where user_id = pg_temp.i('ada'))
    and not exists (select 1 from public.mfa_recovery_attempts where user_id = pg_temp.i('ada'))
    and not exists (select 1 from public.account_security_events where user_id = pg_temp.i('ada')),
    'deleting an account erases the codes, the attempts and the record');
  perform pg_temp.expect(exists (select 1 from public.mfa_recovery_codes where user_id = pg_temp.i('cat')), 'and nobody else''s');
  -- The login row going away takes the codes too.
  delete from auth.users where id = pg_temp.i('cat');
  perform pg_temp.expect(not exists (select 1 from public.mfa_recovery_codes where user_id = pg_temp.i('cat')), 'removing the login removes the codes');
end $$;

\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'account security: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
