-- Behaviour checks for group check-in (D3) and group tabs (D8): migrations
-- 202610280500 to 202610280560. Run by test/supabase/checkin_tabs_test.dart
-- against the local database: it applies the migrations in a transaction,
-- plays people through them, and rolls everything back. Run from the
-- repository root.
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

-- A check-in made by [who] in [conv] (a name in ids), in zone [zone].
create function pg_temp.board(who text, conv text, title text, zone text default 'UTC', remind integer default null, ends date default null)
returns uuid language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.act(pg_temp.i(who));
  r := public.create_check_in(pg_temp.i(conv), title, 'Every day', zone, remind, ends);
  perform pg_temp.root();
  return (r ->> 'check_in_id')::uuid;
end $$;

-- The board's today.
create function pg_temp.today(board uuid) returns date language sql as $$
  select public.check_in_local_day(now(), b.time_zone) from public.check_in_boards b where b.id = board
$$;

grant execute on all functions in schema pg_temp to public;

-- ===================================== 1. what is closed, what is not touched
do $$
declare
  def text;
begin
  perform pg_temp.expect(not exists (
    select 1 from information_schema.role_table_grants
    where table_name in ('check_in_streaks', 'check_in_notices', 'conversation_tab_kinds')
      and grantee in ('anon', 'authenticated')
  ), 'streaks, notices and tab kinds are closed to clients');
  perform pg_temp.expect(not exists (
    select 1 from information_schema.role_table_grants
    where table_name in ('check_in_boards', 'check_in_entries', 'conversation_tabs')
      and grantee in ('anon', 'authenticated')
      and privilege_type <> 'SELECT'
  ), 'boards, entries and tabs are read-only for clients');
  def := pg_get_functiondef('public.run_later_dispatch()'::regprocedure);
  perform pg_temp.expect(def not like '%check_in%', 'run_later_dispatch is not touched');
  def := pg_get_functiondef('public.claim_check_in_pushes()'::regprocedure);
  perform pg_temp.expect(def like '%s.language = ''zh''%' and def like '%今天还没打卡%', 'the reminder push is worded in Chinese for zh devices');
  def := pg_get_functiondef('public.chain_note_needs_review(uuid, uuid)'::regprocedure);
  perform pg_temp.expect(def like '%circle_ai_guard%', 'the chain note guard is the one used (not rewritten)');
end $$;

-- ===================================== 2. making a check-in
do $$
declare
  g1 uuid := pg_temp.i('g1');
  b uuid;
  r jsonb;
begin
  b := pg_temp.board('ada', 'g1', 'Read 20 pages', 'Pacific/Auckland', 9 * 60);
  insert into pg_temp.ids values ('read', b);
  perform pg_temp.expect((select time_zone = 'Pacific/Auckland' and remind_minute = 540 and created_by = pg_temp.i('ada') from public.check_in_boards where id = b), 'the zone, the reminder time and the creator are kept');
  perform pg_temp.expect(exists (
    select 1 from public.messages m
    where m.conversation_id = g1 and m.attachment ->> 'kind' = 'check_in'
      and (m.attachment ->> 'check_in_id')::uuid = b and m.body like '%Read 20 pages%'
  ), 'the card is a text message with a check_in attachment');
  perform pg_temp.expect((select message_id is not null from public.check_in_boards where id = b), 'and the board knows its card');

  perform pg_temp.act(pg_temp.i('bob'));
  r := public.create_check_in(g1, '  Run 3 km  ', null, 'Mars/Olympus', null, null);
  perform pg_temp.root();
  perform pg_temp.expect((select time_zone = 'UTC' and title = 'Run 3 km' and description = '' from public.check_in_boards where id = (r ->> 'check_in_id')::uuid), 'any member may make one; an unknown zone counts as UTC; the title is trimmed');
  insert into pg_temp.ids values ('run', (r ->> 'check_in_id')::uuid);

  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_check_in(%L, %L)', g1, 'Nope')) = 'P0002', 'someone outside the group cannot');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_check_in(%L, %L)', pg_temp.i('dm'), 'Nope')) = '22023', 'not in a direct chat');
  perform pg_temp.expect(pg_temp.state(format('select public.create_check_in(%L, %L)', g1, '   ')) = '22023', 'a title is needed');
  perform pg_temp.expect(pg_temp.state(format('select public.create_check_in(%L, %L, null, ''UTC'', 2000)', g1, 'x')) = '22023', 'the reminder time is a minute of the day');
  perform pg_temp.expect(pg_temp.state(format('select public.create_check_in(%L, %L, null, ''UTC'', null, current_date - 2)', g1, 'x')) = '22023', 'the last day is not in the past');
  perform pg_temp.root();
  perform pg_temp.expect(public.check_in_clean_zone('America/New_York') = 'America/New_York' and public.check_in_clean_zone('nope') = 'UTC' and public.check_in_clean_zone(null) = 'UTC', 'zones are checked');

  -- At most five open ones per chat.
  perform pg_temp.board('ada', 'g1', 'Extra ' || n) from generate_series(1, 3) n;
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_check_in(%L, %L)', g1, 'One too many')) = 'P0001', 'five open check-ins per chat');
  perform pg_temp.root();
  -- A circle channel too.
  b := pg_temp.board('ada', 'plazac', 'Daily stand-up');
  insert into pg_temp.ids values ('standup', b);
  perform pg_temp.expect(b is not null, 'a circle channel can have one');
end $$;

-- ===================================== 3. checking in, a day at a time
do $$
declare
  rd uuid := pg_temp.i('read');
  today date := pg_temp.today(pg_temp.i('read'));
  r jsonb;
  s jsonb;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  r := public.submit_check_in(rd, '  10 pages  ');
  perform pg_temp.expect((r ->> 'streak')::int = 1 and (r ->> 'updated')::boolean = false and (r ->> 'day')::date = today, 'the first check-in: day one of a run');
  r := public.submit_check_in(rd, 'actually 12 pages');
  perform pg_temp.expect((r ->> 'updated')::boolean and (select count(*) from public.check_in_entries where board_id = rd and user_id = pg_temp.i('bob')) = 1, 'the same day again edits the note, it does not add a day');
  perform pg_temp.expect((select note from public.check_in_entries where board_id = rd and user_id = pg_temp.i('bob')) = 'actually 12 pages', 'the note changed');
  perform pg_temp.expect(pg_temp.state(format('select public.submit_check_in(%L, %L)', rd, repeat('x', 201))) = '22023', 'a note is up to 200 characters');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.submit_check_in(%L)', rd)) = 'P0002', 'someone outside the group cannot check in');
  perform pg_temp.expect(pg_temp.state(format('select public.get_check_in(%L)', rd)) = 'P0002', 'or read it');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.check_in_entries') = 0 and pg_temp.cnt('select 1 from public.check_in_boards') = 0, 'or see it in the tables');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select public.submit_check_in(%L)', rd)) in ('42501', '42883'), 'a signed-out client cannot');
  perform pg_temp.root();

  -- Earlier days: cat has been at it for two days, dan stopped a while ago.
  insert into public.check_in_entries (board_id, user_id, day, note)
  values (rd, pg_temp.i('cat'), today - 2, 'a'), (rd, pg_temp.i('cat'), today - 1, 'b'),
         (rd, pg_temp.i('dan'), today - 6, 'c'), (rd, pg_temp.i('dan'), today - 5, 'd'), (rd, pg_temp.i('dan'), today - 4, 'e');
  perform pg_temp.expect((select current_streak = 2 and best_streak = 2 and total_days = 2 and last_day = today - 1 from public.check_in_streaks where board_id = rd and user_id = pg_temp.i('cat')), 'the run is worked out from the days when an entry is written');

  perform pg_temp.act(pg_temp.i('cat'));
  r := public.submit_check_in(rd, 'day three');
  perform pg_temp.expect((r ->> 'streak')::int = 3 and (r ->> 'best_streak')::int = 3 and (r ->> 'total_days')::int = 3, 'yesterday and the day before count: a run of three');
  s := public.get_check_in(rd);
  perform pg_temp.expect((s ->> 'my_streak')::int = 3 and (s ->> 'my_checked_in')::boolean and (s ->> 'today_count')::int = 2 and (s ->> 'member_total')::int = 5, 'the card says today 2 of 5 and a run of 3');
  perform pg_temp.expect(jsonb_array_length(s -> 'entries') = 2 and s -> 'entries' -> 0 ->> 'name' = 'Bob', 'today''s list is in the order people checked in');
  perform pg_temp.expect(jsonb_array_length(s -> 'leaders') = 1 and s -> 'leaders' -> 0 ->> 'name' = 'Cat' and (s -> 'leaders' -> 0 ->> 'streak')::int = 3, 'the leaders are the live runs of two days or more (dan''s run is over)');
  perform pg_temp.expect(jsonb_array_length(s -> 'my_days') = 3, 'and my days are listed for the calendar');
  perform pg_temp.act(pg_temp.i('dan'));
  s := public.get_check_in(rd);
  perform pg_temp.expect((s ->> 'my_streak')::int = 0 and (s ->> 'my_best_streak')::int = 3 and (s ->> 'my_total_days')::int = 3, 'dan''s run is over but his best and his days are kept');
  r := public.submit_check_in(rd);
  perform pg_temp.expect((r ->> 'streak')::int = 1 and (r ->> 'best_streak')::int = 3, 'and he starts a new run');

  -- A day's list, and the days that cannot be asked for.
  s := public.get_check_in_day(rd, today - 1);
  perform pg_temp.expect((s ->> 'count')::int = 1 and s -> 'entries' -> 0 ->> 'name' = 'Cat', 'yesterday''s list');
  perform pg_temp.expect(pg_temp.state(format('select public.get_check_in_day(%L, %L)', rd, today + 1)) = '22023', 'tomorrow cannot be asked for');
  perform pg_temp.expect(pg_temp.state(format('select public.get_check_in_day(%L, %L)', rd, today - 500)) = '22023', 'nor a day over 400 days back');
  perform pg_temp.expect(jsonb_array_length(public.get_check_ins(array[rd, pg_temp.i('run'), gen_random_uuid()])) = 2, 'a batch answers the boards the caller can read');

  -- Undo takes only today back.
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.undo_check_in(rd);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.check_in_entries where board_id = rd and user_id = pg_temp.i('cat')) = 2, 'undo removes today''s check-in only');
  perform pg_temp.expect((select current_streak = 2 from public.check_in_streaks where board_id = rd and user_id = pg_temp.i('cat')), 'and the run is worked out again');
  perform pg_temp.expect((select updated_at > created_at from public.check_in_boards where id = rd), 'every change touches the board (Realtime)');
end $$;

-- ===================================== 4. pictures, blocking, closing
do $$
declare
  rd uuid := pg_temp.i('read');
  g1 uuid := pg_temp.i('g1');
  good text;
  today date := pg_temp.today(pg_temp.i('read'));
  s jsonb;
begin
  good := g1::text || '/check-ins/' || rd::text || '/p1.jpg';
  insert into storage.objects (bucket_id, name, owner, owner_id)
  values ('chat-images', good, pg_temp.i('fay'), pg_temp.i('fay')::text),
         ('chat-images', g1::text || '/check-ins/' || rd::text || '/p2.jpg', pg_temp.i('bob'), pg_temp.i('bob')::text);

  perform pg_temp.act(pg_temp.i('fay'));
  perform pg_temp.expect(pg_temp.state(format('select public.submit_check_in(%L, %L, %L::jsonb)', rd, 'pic', jsonb_build_object('bucket', 'chat-images', 'path', g1::text || '/forms/x/p1.jpg'))) = '22023', 'a picture outside the check-in folder is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.submit_check_in(%L, %L, %L::jsonb)', rd, 'pic', jsonb_build_object('bucket', 'chat-media', 'path', good))) = '22023', 'and one in another bucket');
  perform pg_temp.expect(pg_temp.state(format('select public.submit_check_in(%L, %L, %L::jsonb)', rd, 'pic', jsonb_build_object('bucket', 'chat-images', 'path', g1::text || '/check-ins/' || rd::text || '/p2.jpg'))) = '22023', 'and somebody else''s file');
  perform pg_temp.expect(pg_temp.state(format('select public.submit_check_in(%L, %L, %L::jsonb)', rd, 'pic', jsonb_build_object('bucket', 'chat-images', 'path', good, 'mime_type', 'image/jpeg'))) = 'ok', 'her own file in the folder is fine');
  s := public.get_check_in(rd);
  perform pg_temp.expect(s -> 'my_photo' ->> 'path' = good, 'and comes back as hers');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(s -> 'entries') e where e -> 'photo' ->> 'path' = good), 'in the list too');

  -- Blocking: ada blocked bob, so bob is not in ada's list.
  perform pg_temp.root();
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('ada'), pg_temp.i('bob'));
  perform pg_temp.act(pg_temp.i('ada'));
  s := public.get_check_in(rd);
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(s -> 'entries') e where e ->> 'user_id' = pg_temp.i('bob')::text), 'a person the caller blocked is not in the list');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.submit_check_in(%L)', rd)) in ('ok', '42501'), 'blocking in the group does not stop a member who may still send');
  perform pg_temp.root();
  delete from public.blocks;

  -- Closing: the maker and a moderator (the group's owner) can; a plain member cannot.
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_check_in_closed(%L, true)', rd)) = '42501', 'a member cannot close it');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_check_in_closed(%L, true)', pg_temp.i('run'))) = 'ok', 'its maker can');
  perform pg_temp.expect(pg_temp.state(format('select public.submit_check_in(%L)', pg_temp.i('run'))) = 'P0001', 'a closed check-in takes no more days');
  perform pg_temp.expect(pg_temp.state(format('select public.undo_check_in(%L)', pg_temp.i('run'))) = 'P0001', 'and no undo');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_check_in_closed(%L, false)', pg_temp.i('run'))) = 'ok', 'the group''s owner can reopen it');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.submit_check_in(%L)', pg_temp.i('run'))) = 'ok', 'and then it takes days again');

  -- A last day that has passed closes it.
  perform pg_temp.root();
  update public.check_in_boards set ends_on = public.check_in_local_day(now(), 'UTC') - 1 where id = pg_temp.i('run');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.submit_check_in(%L)', pg_temp.i('run'))) = 'P0001', 'a board past its last day is closed');
  perform pg_temp.expect((public.get_check_in(pg_temp.i('run')) ->> 'closed')::boolean, 'and says so');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.set_check_in_closed(pg_temp.i('run'), false);
  perform pg_temp.expect((select ends_on is null from public.check_in_boards where id = pg_temp.i('run')), 'reopening drops a last day that has passed');
  perform pg_temp.root();
end $$;

-- ===================================== 5. a circle channel, and K1
do $$
declare
  su uuid := pg_temp.i('standup');
  club uuid := pg_temp.i('club');
  r jsonb;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  r := public.submit_check_in(su, 'present');
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.circle_member_daily d where d.circle_id = club and d.user_id = pg_temp.i('bob') and d.day = public.insights_today()), 'a check-in in a channel is a day of activity for the circle (C7 streak)');
  perform pg_temp.expect(not exists (select 1 from public.circle_member_daily d where d.circle_id = club and d.user_id = pg_temp.i('cat')), 'and only for the one who checked in');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect((public.get_check_in(su) ->> 'member_total')::int = 5, 'a channel counts its circle''s people');
  perform pg_temp.root();

  update public.circles set disabled_at = now(), disabled_mode = 'suspend' where id = club;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.submit_check_in(%L)', su)) = 'P0002', 'a circle an admin suspended (K1) takes no check-ins');
  perform pg_temp.expect(pg_temp.state(format('select public.get_check_in(%L)', su)) = 'P0002', 'and shows nothing');
  perform pg_temp.root();
  update public.circles set disabled_at = null, disabled_mode = null where id = club;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.get_check_in(%L)', su)) = 'ok', 'a restored circle works again');
  perform pg_temp.root();
end $$;

-- ===================================== 6. the daily reminder and its push
do $$
declare
  rm uuid;
  minute_now integer := extract(hour from now() at time zone 'UTC')::int * 60 + extract(minute from now() at time zone 'UTC')::int;
  swept jsonb;
  n integer;
  rows_en integer;
  rows_zh integer;
  r record;
begin
  update public.check_in_boards set closed_at = now() where title like 'Extra %';
  rm := pg_temp.board('ada', 'g1', 'Evening review', 'UTC', greatest(0, minute_now - 10));
  insert into pg_temp.ids values ('review', rm);
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
  values (pg_temp.i('bob'), 'https://push.example.com/bob-zh', repeat('k', 60), repeat('a', 20), 'zh'),
         (pg_temp.i('cat'), 'https://push.example.com/cat-en', repeat('k', 60), repeat('a', 20), 'en'),
         (pg_temp.i('dan'), 'https://push.example.com/dan-en', repeat('k', 60), repeat('a', 20), 'en'),
         (pg_temp.i('eve'), 'https://push.example.com/eve-en', repeat('k', 60), repeat('a', 20), 'en');
  -- Streak for bob so the words carry it: yesterday and the day before.
  insert into public.check_in_entries (board_id, user_id, day, note)
  values (rm, pg_temp.i('bob'), public.check_in_local_day(now(), 'UTC') - 2, ''), (rm, pg_temp.i('bob'), public.check_in_local_day(now(), 'UTC') - 1, '');
  -- Ada already checked in today, so she is not reminded.
  insert into public.check_in_entries (board_id, user_id, day, note)
  values (rm, pg_temp.i('ada'), public.check_in_local_day(now(), 'UTC'), '');

  swept := public.check_in_sweep();
  perform pg_temp.expect((swept ->> 'notices')::int >= 4, 'the sweep reminds the people who have not checked in');
  perform pg_temp.expect(not exists (select 1 from public.check_in_notices where board_id = rm and user_id = pg_temp.i('ada')), 'but not the one who did');
  perform pg_temp.expect(not exists (select 1 from public.check_in_notices where board_id = rm and user_id = pg_temp.i('eve')), 'nor someone outside the group');
  perform pg_temp.expect((select last_reminded_on = public.check_in_local_day(now(), 'UTC') from public.check_in_boards where id = rm), 'it remembers it did today');
  select count(*) into n from public.check_in_notices where board_id = rm;
  swept := public.check_in_sweep();
  perform pg_temp.expect((select count(*) from public.check_in_notices where board_id = rm) = n, 'a second sweep the same day adds no second notice');

  -- cat muted the chat: her push is not sent.
  update public.conversation_members set muted_until = now() + interval '1 day' where conversation_id = pg_temp.i('g1') and user_id = pg_temp.i('cat');
  select count(*) filter (where title = 'Time to check in'), count(*) filter (where title = '今天还没打卡')
  into rows_en, rows_zh from public.claim_check_in_pushes();
  perform pg_temp.expect(rows_zh = 1, 'bob''s Chinese device gets a Chinese push');
  perform pg_temp.expect(rows_en = 1, 'dan''s English device gets an English one; cat muted the chat and eve is outside');
  perform pg_temp.expect((select count(*) from public.claim_check_in_pushes()) = 0, 'each notice is claimed once');
  update public.conversation_members set muted_until = null where conversation_id = pg_temp.i('g1') and user_id = pg_temp.i('cat');

  -- The words and the route.
  update public.check_in_notices set push_claimed_at = null where board_id = rm and user_id = pg_temp.i('bob');
  select * into r from public.claim_check_in_pushes() limit 1;
  perform pg_temp.expect(r.body like '%已连续 2 天%' and r.conversation_id = pg_temp.i('g1') and r.url = '/#/chats/' || pg_temp.i('g1')::text, 'a run that would break is named; the push carries its chat (locked chats and quiet hours apply)');
  update public.check_in_notices set push_claimed_at = null, created_at = now() - interval '1 hour' where board_id = rm and user_id = pg_temp.i('dan');
  perform pg_temp.expect((select count(*) from public.claim_check_in_pushes() where subscription_id in (select id from public.push_subscriptions where user_id = pg_temp.i('dan'))) = 0, 'a notice over 30 minutes old is closed without a push');

  -- Someone who checked in since is not pushed.
  update public.check_in_notices set push_claimed_at = null where board_id = rm and user_id = pg_temp.i('fay');
  insert into public.check_in_entries (board_id, user_id, day, note) values (rm, pg_temp.i('fay'), public.check_in_local_day(now(), 'UTC'), '');
  perform pg_temp.expect((select count(*) from public.claim_check_in_pushes()) = 0, 'and nobody is pushed who has checked in meanwhile');

  -- A closed board sends nothing and a reminder time that passed 3 hours ago is skipped.
  update public.check_in_boards set closed_at = now(), last_reminded_on = null where id = rm;
  delete from public.check_in_notices where board_id = rm;
  perform public.check_in_sweep();
  perform pg_temp.expect(not exists (select 1 from public.check_in_notices where board_id = rm), 'a closed board is not reminded');
  update public.check_in_boards set closed_at = null, remind_minute = case when minute_now >= 300 then minute_now - 250 else 1439 end, last_reminded_on = null where id = rm;
  perform public.check_in_sweep();
  perform pg_temp.expect(not exists (select 1 from public.check_in_notices where board_id = rm), 'a reminder more than three hours late is skipped');

  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform pg_temp.expect(exists (select 1 from cron.job where jobname = 'wecord-check-in-sweep' and schedule = '*/5 * * * *'), 'the sweep is a cron job of its own, every 5 minutes');
    perform pg_temp.expect((select command from cron.job where jobname = 'wecord-later-dispatch') not like '%check_in%', 'and the every-minute dispatcher does not run it');
  end if;
end $$;

-- ===================================== 7. group tabs
do $$
declare
  g1 uuid := pg_temp.i('g1');
  g2 uuid := pg_temp.i('g2');
  plazac uuid := pg_temp.i('plazac');
  note_id uuid := gen_random_uuid();
  other_note uuid := gen_random_uuid();
  list_id uuid := gen_random_uuid();
  form_id uuid := gen_random_uuid();
  t jsonb;
  tabs jsonb;
  tab_id uuid;
begin
  insert into public.notes (id, conversation_id, title, icon, created_by) values
    (note_id, g1, 'House rules', E'\U0001F4D8', pg_temp.i('ada')),
    (other_note, g2, 'Elsewhere', E'\U0001F4D8', pg_temp.i('eve'));
  insert into public.task_lists (id, conversation_id, title, created_by) values (list_id, g1, 'Chores', pg_temp.i('ada'));
  insert into public.forms (id, conversation_id, creator_id, title, fields) values (form_id, g1, pg_temp.i('ada'), 'Orphan form', '[]'::jsonb);

  perform pg_temp.act(pg_temp.i('bob'));
  t := public.get_conversation_tabs(g1);
  perform pg_temp.expect(t -> 'tabs' = '[]'::jsonb and (t ->> 'can_manage')::boolean = false, 'a chat starts with no tabs, and a member cannot manage them');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''link'', ''https://example.com'', ''Site'')', g1)) = '42501', 'a plain member cannot add a tab');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.get_conversation_tabs(%L)', g1)) = 'P0002', 'someone outside cannot read them');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.conversation_tabs') = 0, 'or see the table');

  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect((public.get_conversation_tabs(g1) ->> 'can_manage')::boolean, 'the group''s owner can manage them');
  t := public.add_conversation_tab(g1, 'note', note_id::text, null);
  tab_id := (t ->> 'id')::uuid;
  perform pg_temp.expect((select title = 'House rules' and sort = 0 from public.conversation_tabs where id = tab_id), 'a note tab takes the note''s title and goes last');
  perform public.add_conversation_tab(g1, 'list', list_id::text, 'Our chores list');
  perform public.add_conversation_tab(g1, 'link', 'https://example.com/guide', 'Guide');
  perform public.add_conversation_tab(g1, 'check_in', pg_temp.i('read')::text, '');
  perform public.add_conversation_tab(g1, 'space', null, 'Space');
  perform public.add_conversation_tab(g1, 'form', form_id::text, null);
  perform public.add_conversation_tab(g1, 'events', null, 'Events');

  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''note'', %L, ''Again'')', g1, note_id::text)) = 'P0001', 'the same target twice is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''note'', %L, ''Not ours'')', g1, other_note::text)) = '22023', 'a note of another chat is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''note'', ''not-a-uuid'', ''x'')', g1)) = '22023', 'a bad id is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''link'', ''javascript:alert(1)'', ''x'')', g1)) = '22023', 'a javascript link is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''link'', ''ftp://example.com/x'', ''x'')', g1)) = '22023', 'and ftp');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''link'', ''https://'', ''x'')', g1)) = '22023', 'and an address with no host');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''link'', %L, ''x'')', g1, 'https://example.com/' || repeat('a', 500))) = '22023', 'and a very long one');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''link'', ''https://example.com/x'', %L)', g1, repeat('t', 41))) = 'ok', 'a long title is cut to 40, not refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''kb'', null, ''KB'')', g1)) = '22023', 'the knowledge base needs a circle channel');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''space'', ''x'', ''S'')', g1)) = '22023', 'a kind with no target takes none');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''mystery'', null, ''S'')', g1)) in ('22023', '23503'), 'an unknown kind is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''link'', ''https://example.com/y'', '''')', g1)) = '22023', 'a link tab needs a title of its own');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''events'', null, ''E'')', pg_temp.i('dm'))) = '22023', 'no tabs in a direct chat');

  -- Reading: the orphan form (its card was never made) is left out, the live titles show.
  tabs := public.get_conversation_tabs(g1) -> 'tabs';
  perform pg_temp.expect(jsonb_array_length(tabs) = 7 and not exists (select 1 from jsonb_array_elements(tabs) e where e ->> 'kind' = 'form'), 'a form whose card is not readable is left out');
  perform pg_temp.expect(jsonb_array_length(public.get_conversation_tabs(g1, true) -> 'tabs') = 8, 'but the manage sheet can ask for it');
  perform pg_temp.expect(tabs -> 0 ->> 'title' = 'House rules' and tabs -> 0 ->> 'icon' = E'\U0001F4D8', 'the note''s icon comes with it');
  perform pg_temp.root();
  update public.notes set title = 'Group rules' where id = note_id;
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(public.get_conversation_tabs(g1) -> 'tabs' -> 0 ->> 'title' = 'Group rules', 'the live title follows a rename');
  perform pg_temp.expect((select e ->> 'title' from jsonb_array_elements(public.get_conversation_tabs(g1) -> 'tabs') e where e ->> 'kind' = 'check_in') = 'Read 20 pages', 'a check-in tab shows the check-in''s title');

  -- Limit of 12.
  perform public.add_conversation_tab(g1, 'link', 'https://example.com/' || n, 'L' || n) from generate_series(1, 4) n;
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''link'', ''https://example.com/last'', ''Last'')', g1)) = 'P0001', 'twelve tabs at most');

  -- Rename, reorder, remove.
  perform public.update_conversation_tab(tab_id, '  Rules  ');
  perform pg_temp.expect((select title from public.conversation_tabs where id = tab_id) = 'Rules', 'a tab can be renamed');
  perform pg_temp.expect(pg_temp.state(format('select public.update_conversation_tab(%L, ''   '')', tab_id)) = '22023', 'but not to nothing');
  perform public.reorder_conversation_tabs(g1, (select array_agg(id order by sort desc) from public.conversation_tabs where conversation_id = g1));
  perform pg_temp.expect((select sort from public.conversation_tabs where id = tab_id) = 11, 'tabs can be put in a new order');
  perform public.reorder_conversation_tabs(g1, array[tab_id]);
  perform pg_temp.expect((select sort from public.conversation_tabs where id = tab_id) = 0 and (select count(distinct sort) from public.conversation_tabs where conversation_id = g1) = 12, 'tabs not listed follow, with no gaps or twins');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.delete_conversation_tab(%L)', tab_id)) = '42501', 'a member cannot remove one');
  perform pg_temp.expect(pg_temp.state(format('select public.reorder_conversation_tabs(%L, array[]::uuid[])', g1)) = '42501', 'or reorder');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.delete_conversation_tab(tab_id);
  perform pg_temp.expect(not exists (select 1 from public.conversation_tabs where id = tab_id), 'the owner can');

  -- A tab goes with its target.
  perform public.add_conversation_tab(g1, 'note', note_id::text, 'Rules again');
  perform pg_temp.root();
  update public.notes set deleted_at = now() where id = note_id;
  perform pg_temp.expect(not exists (select 1 from public.conversation_tabs where kind = 'note' and target = note_id::text), 'a deleted note takes its tab');
  update public.task_lists set deleted_at = now() where id = list_id;
  perform pg_temp.expect(not exists (select 1 from public.conversation_tabs where kind = 'list'), 'and a deleted list');
  delete from public.forms where id = form_id;
  perform pg_temp.expect(not exists (select 1 from public.conversation_tabs where kind = 'form'), 'and a removed form');
  delete from public.check_in_boards where id = pg_temp.i('read');
  perform pg_temp.expect(not exists (select 1 from public.conversation_tabs where kind = 'check_in'), 'and a removed check-in');

  -- A circle channel: the knowledge base tab works.
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''kb'', null, ''Knowledge base'')', plazac)) = 'ok', 'a channel can have the knowledge base tab');
  perform pg_temp.expect(public.get_conversation_tabs(plazac) -> 'tabs' -> 0 ->> 'circle_id' = pg_temp.i('club')::text, 'and the tab says which circle');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''space'', null, ''S'')', plazac)) = '42501', 'a circle member without manage_messages cannot');

  -- K1: nobody reads or changes tabs in a suspended circle.
  perform pg_temp.root();
  update public.circles set disabled_at = now(), disabled_mode = 'suspend' where id = pg_temp.i('club');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.get_conversation_tabs(%L)', plazac)) = 'P0002', 'a suspended circle (K1) shows no tabs');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''events'', null, ''E'')', plazac)) = 'P0002', 'and takes none');
  perform pg_temp.root();
  update public.circles set disabled_at = null, disabled_mode = null where id = pg_temp.i('club');
end $$;

-- ===================================== 8. the account: deleting it and taking the data
do $$
declare
  g1 uuid := pg_temp.i('g1');
  exported jsonb;
begin
  perform pg_temp.expect(exists (select 1 from public.check_in_entries where user_id = pg_temp.i('bob')) and exists (select 1 from public.check_in_streaks where user_id = pg_temp.i('bob')), 'bob has check-ins and a run before');
  exported := public.export_my_check_ins(pg_temp.i('bob'));
  perform pg_temp.expect(jsonb_array_length(exported -> 'check_ins') >= 3 and jsonb_array_length(exported -> 'streaks') >= 1 and jsonb_array_length(exported -> 'boards_made') = 1, 'the export has my days, my runs and the check-in I made');
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(exported -> 'check_ins') e where e ->> 'note' = 'day three'), 'and nobody else''s notes');
  perform pg_temp.expect(public.export_my_check_ins(pg_temp.i('eve')) = jsonb_build_object('check_ins', '[]'::jsonb, 'streaks', '[]'::jsonb, 'boards_made', '[]'::jsonb), 'a stranger''s export is empty');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.export_my_check_ins(%L)', pg_temp.i('bob'))) = '42501', 'clients cannot call the export');
  perform pg_temp.expect(pg_temp.state(format('select public.export_my_group_tabs(%L)', pg_temp.i('bob'))) = '42501', 'nor the tabs export');
  perform pg_temp.root();
  perform pg_temp.expect(has_function_privilege('service_role', 'public.export_my_check_ins(uuid)', 'execute') and has_function_privilege('service_role', 'public.export_my_group_tabs(uuid)', 'execute'), 'the data-export function can');

  exported := public.export_my_group_tabs(pg_temp.i('ada'));
  perform pg_temp.expect(jsonb_array_length(exported -> 'tabs_added') >= 5 and exists (select 1 from jsonb_array_elements(exported -> 'tabs_added') e where e ->> 'link' = 'https://example.com/guide'), 'the tabs I added are exported, with their links');
  perform pg_temp.expect(public.export_my_group_tabs(pg_temp.i('eve')) = jsonb_build_object('tabs_added', '[]'::jsonb), 'a stranger''s tabs export is empty');

  insert into public.check_in_entries (board_id, user_id, day, note) values (pg_temp.i('review'), pg_temp.i('cat'), current_date, 'cat stays');
  update public.profiles set deleted_at = now() where id = pg_temp.i('bob');
  perform pg_temp.expect(not exists (select 1 from public.check_in_entries where user_id = pg_temp.i('bob')) and not exists (select 1 from public.check_in_streaks where user_id = pg_temp.i('bob')) and not exists (select 1 from public.check_in_notices where user_id = pg_temp.i('bob')), 'deleting an account erases check-ins, runs and reminders');
  perform pg_temp.expect(exists (select 1 from public.check_in_boards where created_by = pg_temp.i('bob')), 'the check-in they made stays in its chat');
  perform pg_temp.expect(exists (select 1 from public.check_in_entries where user_id = pg_temp.i('cat')), 'and other people''s days stay');

  update public.profiles set deleted_at = now() where id = pg_temp.i('ada');
  perform pg_temp.expect(not exists (select 1 from public.conversation_tabs where created_by = pg_temp.i('ada')) and exists (select 1 from public.conversation_tabs where conversation_id = g1), 'the tabs of a deleted account stay, without their name');
end $$;

\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'check-in and group tabs: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
