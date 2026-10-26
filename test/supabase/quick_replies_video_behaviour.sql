-- Behaviour checks for quick replies, the away auto-reply and round video
-- messages (A8 and A13: migrations 202610280300 to 202610280330). Run by
-- test/supabase/quick_replies_video_test.dart against the local database: it
-- applies the migrations in a transaction, plays people through them, and
-- rolls everything back. Run from the repository root.
--
-- What it walks through: the quick-reply table (shortcut rules, the limit of
-- 50, owner only); setting the away reply; who is answered and who is not (a
-- group, a stranger, a blocked person, a bot, a second message within a day,
-- an auto-reply, two people who both have it on); that the reply is the chat's
-- last message and rings even when the message was sent silently; that clients
-- cannot forge an auto-reply; the push claim; the checks on a round video
-- message; deleting an account and the data export.
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
-- ada has the away reply; bob, dan, eve, fay and gus are her friends (dan is
-- blocked, eve is a bot, fay has an away reply of her own, gus's account is
-- deleted); cat is a stranger in a direct chat with her.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@a8.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'fay'),(7,'gus')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_a8', initcap(name)
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'fay'),(7,'gus')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'fay'),(7,'gus')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(pg_temp.i('ada'), pg_temp.i(n)), greatest(pg_temp.i('ada'), pg_temp.i(n))
from (values ('bob'),('dan'),('eve'),('fay'),('gus')) v(n);
-- eve became a bot after the friendship was made (bots cannot be added as friends).
update public.profiles set is_bot = true where id = pg_temp.i('eve');
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('ada'), pg_temp.i('dan'));

insert into pg_temp.ids
select 'dm_a' || n, gen_random_uuid() from (values ('b'),('c'),('d'),('e'),('f'),('g')) v(n);
insert into pg_temp.ids values ('g1', gen_random_uuid()), ('self', gen_random_uuid());
insert into public.conversations (id, type, title)
select pg_temp.i('dm_a' || n), 'direct', null from (values ('b'),('c'),('d'),('e'),('f'),('g')) v(n);
insert into public.conversations (id, type, title)
values (pg_temp.i('g1'), 'group', 'Hike crew'), (pg_temp.i('self'), 'direct', null);
insert into public.conversation_members (conversation_id, user_id, role)
select pg_temp.i('dm_a' || n), pg_temp.i(who), 'member'
from (values ('b','bob'),('c','cat'),('d','dan'),('e','eve'),('f','fay'),('g','gus')) v(n, who)
union all
select pg_temp.i('dm_a' || n), pg_temp.i('ada'), 'member'
from (values ('b'),('c'),('d'),('e'),('f'),('g')) v(n)
union all
select pg_temp.i('g1'), pg_temp.i(who), 'member' from (values ('ada'),('bob'),('cat')) v(who)
union all
select pg_temp.i('self'), pg_temp.i('ada'), 'owner';

create function pg_temp.say(conv text, who text, text_body text) returns uuid language plpgsql as $$
declare r uuid;
begin
  perform pg_temp.root();
  insert into public.messages (conversation_id, sender_id, type, body)
  values (pg_temp.i(conv), pg_temp.i(who), 'text', text_body)
  returning id into r;
  return r;
end $$;

create function pg_temp.autos(conv text) returns integer language sql as $$
  select count(*)::integer from public.messages where conversation_id = pg_temp.i(conv) and auto_reply
$$;

create function pg_temp.age_log() returns void language sql as $$
  update public.away_reply_log set replied_at = now() - interval '25 hours'
$$;

grant execute on all functions in schema pg_temp to public;

-- ===================================== 1. what is left alone
do $$
declare
  def text;
begin
  perform pg_temp.expect(to_regprocedure('public.run_later_dispatch()') is not null
    and pg_get_functiondef('public.run_later_dispatch()'::regprocedure) not like '%away%', 'run_later_dispatch is not touched');
  def := pg_get_functiondef('public.claim_push_delivery(uuid, uuid)'::regprocedure);
  perform pg_temp.expect(def not like '%away%' and def like '%review_state%', 'claim_push_delivery is not touched');
  def := pg_get_functiondef('public.messages_send_away_reply()'::regprocedure);
  perform pg_temp.expect(def !~ E'\\.bio\\M', 'the trigger reads no bio');
  perform pg_temp.expect(exists (select 1 from pg_trigger where tgname = 'messages_zz_away_reply' and tgrelid = 'public.messages'::regclass)
    and exists (select 1 from pg_trigger where tgname = 'messages_touch_conversation' and tgrelid = 'public.messages'::regclass), 'the reply trigger sits beside the existing message triggers');
  perform pg_temp.expect('messages_zz_away_reply' > all (select tgname::text from pg_trigger where tgrelid = 'public.messages'::regclass and not tgisinternal and tgtype & 4 = 4 and tgname <> 'messages_zz_away_reply' and tgtype & 2 = 0), 'and fires after every other after-insert trigger');
  perform pg_temp.expect(not exists (select 1 from information_schema.role_table_grants where table_name = 'away_reply_log' and grantee in ('anon','authenticated')), 'the reply log is closed to clients');
  perform pg_temp.expect(not has_function_privilege('authenticated', 'public.claim_away_reply_pushes()', 'execute')
    and has_function_privilege('service_role', 'public.claim_away_reply_pushes()', 'execute'), 'only the service role claims the pushes');
end $$;

-- ===================================== 2. quick replies
do $$
declare
  stored record;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  insert into public.quick_replies (user_id, shortcut, body)
  values (pg_temp.i('bob'), ' Addr ', '  12 Main Street  ');
  select shortcut, body into stored from public.quick_replies where user_id = pg_temp.i('bob');
  perform pg_temp.expect(stored.shortcut = 'addr' and stored.body = '12 Main Street', 'a shortcut is lower-cased and trimmed, the body trimmed');
  perform pg_temp.expect(pg_temp.state(format('insert into public.quick_replies (user_id, shortcut, body) values (%L, %L, %L)', pg_temp.i('bob'), 'ADDR', 'again')) = '23505', 'the same shortcut twice is refused');
  perform pg_temp.expect(pg_temp.state(format('insert into public.quick_replies (user_id, shortcut, body) values (%L, %L, %L)', pg_temp.i('bob'), 'two words', 'x')) = '23514', 'a shortcut with a space is refused');
  perform pg_temp.expect(pg_temp.state(format('insert into public.quick_replies (user_id, shortcut, body) values (%L, %L, %L)', pg_temp.i('bob'), 'a/b', 'x')) = '23514', 'and one with a slash');
  perform pg_temp.expect(pg_temp.state(format('insert into public.quick_replies (user_id, shortcut, body) values (%L, %L, %L)', pg_temp.i('bob'), '', 'x')) = '23514', 'and an empty one');
  perform pg_temp.expect(pg_temp.state(format('insert into public.quick_replies (user_id, shortcut, body) values (%L, %L, %L)', pg_temp.i('bob'), repeat('x', 33), 'x')) = '23514', 'and one over 32 characters');
  perform pg_temp.expect(pg_temp.state(format('insert into public.quick_replies (user_id, shortcut, body) values (%L, %L, %L)', pg_temp.i('bob'), 'blank', '   ')) = '23514', 'a blank body is refused');
  perform pg_temp.expect(pg_temp.state(format('insert into public.quick_replies (user_id, shortcut, body) values (%L, %L, %L)', pg_temp.i('bob'), 'long', repeat('y', 2001))) = '23514', 'and one over 2000 characters');
  insert into public.quick_replies (user_id, shortcut, body) values (pg_temp.i('bob'), '地址', '朝阳路 1 号');
  perform pg_temp.expect(exists (select 1 from public.quick_replies where shortcut = '地址'), 'a shortcut can be in Chinese');
  perform pg_temp.expect(pg_temp.state(format('insert into public.quick_replies (user_id, shortcut, body) values (%L, %L, %L)', pg_temp.i('ada'), 'mine', 'x')) <> 'ok', 'nobody saves a phrase for somebody else');

  -- Owner only.
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.quick_replies') = 0, 'ada sees none of bob''s phrases');
  update public.quick_replies set body = 'hijacked';
  perform pg_temp.expect(not exists (select 1 from public.quick_replies where body = 'hijacked'), 'and changes none');
  delete from public.quick_replies;
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.quick_replies where user_id = pg_temp.i('bob')) = 2, 'or deletes any');

  -- Own rows can change but not move.
  perform pg_temp.act(pg_temp.i('bob'));
  update public.quick_replies set body = 'New body', user_id = pg_temp.i('ada') where shortcut = 'addr';
  perform pg_temp.root();
  perform pg_temp.expect((select body from public.quick_replies where shortcut = 'addr') = 'New body'
    and (select user_id from public.quick_replies where shortcut = 'addr') = pg_temp.i('bob'), 'an edit changes the body and keeps the owner');

  -- At most 50.
  insert into public.quick_replies (user_id, shortcut, body)
  select pg_temp.i('cat'), 's' || n, 'phrase ' || n from generate_series(1, 50) n;
  perform pg_temp.expect(pg_temp.state(format('insert into public.quick_replies (user_id, shortcut, body) values (%L, %L, %L)', pg_temp.i('cat'), 'one-too-many', 'x')) = '54000', 'the 51st phrase is refused');
  delete from public.quick_replies where user_id = pg_temp.i('cat') and shortcut = 's1';
  insert into public.quick_replies (user_id, shortcut, body) values (pg_temp.i('cat'), 'again', 'x');
  perform pg_temp.expect(true, 'after one is deleted there is room');
end $$;

-- ===================================== 3. setting the away reply
do $$
declare
  stored jsonb;
begin
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state($q$select public.set_away_reply(true, 'x', null, false)$q$) = '42501', 'signing in is needed');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state($q$select public.set_away_reply(true, '   ', null, false)$q$) = '22023', 'switching on with no message is refused');
  perform pg_temp.expect(pg_temp.state($q$select public.set_away_reply(false, '', null, true)$q$) = '22023', 'and so is asking for quiet hours with no message');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_away_reply(true, 'away', %L, false)$q$, now() - interval '1 minute')) = '22023', 'an end time in the past is refused');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_away_reply(true, %L, null, false)$q$, repeat('z', 501))) = '22023', 'and a message over 500 characters');
  stored := public.set_away_reply(true, '  Back Monday  ', now() + interval '2 days', false);
  perform pg_temp.root();
  perform pg_temp.expect(stored->>'message' = 'Back Monday' and (stored->>'enabled')::boolean, 'it is stored, trimmed');
  perform pg_temp.expect(public.away_reply_active(pg_temp.i('ada'), now()), 'and it is on');
  perform pg_temp.expect(not public.away_reply_active(pg_temp.i('ada'), now() + interval '3 days'), 'but not after its end time');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_away_reply(false, 'Back Monday', null, false);
  perform pg_temp.root();
  perform pg_temp.expect(not public.away_reply_active(pg_temp.i('ada'), now())
    and (select away_message from public.user_notification_settings where user_id = pg_temp.i('ada')) = 'Back Monday', 'switched off, it is off and the message is kept');
  perform pg_temp.expect(pg_temp.val(format('select away_enabled::text from public.user_notification_settings where user_id = %L', pg_temp.i('ada'))) = 'false', 'with the switch false');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.user_notification_settings') = 0, 'nobody else reads the settings');
  perform pg_temp.root();
end $$;

-- ===================================== 4. who is answered
do $$
declare
  original uuid;
  reply record;
  first_reply uuid;
  due integer;
  claimed integer;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_away_reply(true, 'Back Monday', null, false);
  perform pg_temp.root();

  original := pg_temp.say('dm_ab', 'bob', 'hello');
  perform pg_temp.expect(pg_temp.autos('dm_ab') = 1, 'a friend writing to ada gets one auto-reply');
  select * into reply from public.messages where conversation_id = pg_temp.i('dm_ab') and auto_reply;
  first_reply := reply.id;
  perform pg_temp.expect(reply.sender_id = pg_temp.i('ada') and reply.body = 'Back Monday' and reply.type = 'text' and not reply.silent, 'it is ada''s text message with her words');
  perform pg_temp.expect(reply.created_at > (select created_at from public.messages where id = original), 'it comes after the message it answers');
  perform pg_temp.expect((select last_message_id from public.conversations where id = pg_temp.i('dm_ab')) = reply.id, 'and is the chat''s last message');
  perform pg_temp.expect((select count(*) from public.away_reply_log where away_user_id = pg_temp.i('ada') and to_user_id = pg_temp.i('bob') and message_id = reply.id) = 1, 'it is logged');

  perform pg_temp.say('dm_ab', 'bob', 'are you there?');
  perform pg_temp.expect(pg_temp.autos('dm_ab') = 1, 'a second message the same day gets none');

  perform pg_temp.age_log();
  perform pg_temp.say('dm_ab', 'bob', 'next day');
  perform pg_temp.expect(pg_temp.autos('dm_ab') = 2, 'a day later it answers again');

  -- A message sent silently is answered, and the answer rings.
  perform pg_temp.age_log();
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.send_silent_text_message(pg_temp.i('dm_ab'), 'quiet one', null, null, '[]'::jsonb, null);
  perform pg_temp.root();
  perform pg_temp.expect((select silent from public.messages where body = 'quiet one') and pg_temp.autos('dm_ab') = 3
    and not (select silent from public.messages where conversation_id = pg_temp.i('dm_ab') and auto_reply order by created_at desc limit 1), 'the answer to a silent message is not silent');
  perform pg_temp.expect(coalesce(current_setting('wecord.send_silent', true), 'off') = 'off', 'and the silent setting is left as it was');

  -- Where it does not answer.
  perform pg_temp.say('g1', 'bob', 'hi all');
  perform pg_temp.expect(pg_temp.autos('g1') = 0, 'no answer in a group');
  perform pg_temp.say('dm_ac', 'cat', 'hello stranger');
  perform pg_temp.expect(pg_temp.autos('dm_ac') = 0, 'no answer to somebody who is not a friend');
  perform pg_temp.say('dm_ad', 'dan', 'let me back');
  perform pg_temp.expect(pg_temp.autos('dm_ad') = 0, 'none to a blocked person');
  perform pg_temp.say('dm_ae', 'eve', 'beep');
  perform pg_temp.expect(pg_temp.autos('dm_ae') = 0, 'none to a bot');
  update public.profiles set deleted_at = now() where id = pg_temp.i('gus');
  perform pg_temp.say('dm_ag', 'gus', 'ghost');
  perform pg_temp.expect(pg_temp.autos('dm_ag') = 0, 'none to a deleted account');
  perform pg_temp.say('self', 'ada', 'note to self');
  perform pg_temp.expect(pg_temp.autos('self') = 0, 'none in a note to self');
  insert into public.messages (conversation_id, sender_id, type, body)
  values (pg_temp.i('dm_ab'), pg_temp.i('bob'), 'system', 'bob did something');
  perform pg_temp.expect(pg_temp.autos('dm_ab') = 3, 'none to a system notice');
  perform pg_temp.say('dm_ab', 'ada', 'my own message');
  perform pg_temp.expect(pg_temp.autos('dm_ab') = 3 and not exists (select 1 from public.messages where sender_id = pg_temp.i('bob') and auto_reply), 'ada writing to bob (who has no reply) triggers nothing');

  -- Two people who both have it on do not answer each other for ever.
  perform pg_temp.act(pg_temp.i('fay'));
  perform public.set_away_reply(true, 'Fay is out', null, false);
  perform pg_temp.root();
  perform pg_temp.say('dm_af', 'fay', 'hi ada');
  perform pg_temp.expect((select count(*) from public.messages where conversation_id = pg_temp.i('dm_af')) = 2 and pg_temp.autos('dm_af') = 1, 'fay writes, ada answers once, fay does not answer the answer');
  perform pg_temp.say('dm_af', 'ada', 'ok');
  perform pg_temp.expect((select count(*) from public.messages where conversation_id = pg_temp.i('dm_af')) = 4 and pg_temp.autos('dm_af') = 2, 'ada writes and fay answers once; then it stops');
  perform pg_temp.say('dm_af', 'fay', 'again');
  perform pg_temp.expect((select count(*) from public.messages where conversation_id = pg_temp.i('dm_af')) = 5, 'and a second message from either gets no answer that day');

  -- Switched off, ended, or the ceiling.
  perform pg_temp.age_log();
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_away_reply(false, 'Back Monday', null, false);
  perform pg_temp.root();
  perform pg_temp.say('dm_ab', 'bob', 'while switched off');
  perform pg_temp.expect(pg_temp.autos('dm_ab') = 3, 'switched off, it does not answer');
  update public.user_notification_settings set away_enabled = true, away_until = now() - interval '1 minute' where user_id = pg_temp.i('ada');
  perform pg_temp.say('dm_ab', 'bob', 'after it ended');
  perform pg_temp.expect(pg_temp.autos('dm_ab') = 3, 'past its end time, it does not answer');
  update public.user_notification_settings set away_until = null where user_id = pg_temp.i('ada');
  insert into public.away_reply_log (away_user_id, to_user_id, conversation_id)
  select pg_temp.i('ada'), pg_temp.i('cat'), pg_temp.i('dm_ac') from generate_series(1, 300);
  perform pg_temp.say('dm_ab', 'bob', 'over the ceiling');
  perform pg_temp.expect(pg_temp.autos('dm_ab') = 3, 'after 300 replies in a day it stops');
  delete from public.away_reply_log where message_id is null;
  perform pg_temp.say('dm_ab', 'bob', 'under the ceiling again');
  perform pg_temp.expect(pg_temp.autos('dm_ab') = 4, 'and carries on when the day''s count is down');

  -- Quiet hours.
  perform pg_temp.age_log();
  update public.user_notification_settings set away_enabled = false, away_in_quiet_hours = true, quiet_enabled = false where user_id = pg_temp.i('ada');
  perform pg_temp.say('dm_ab', 'bob', 'outside quiet hours');
  perform pg_temp.expect(pg_temp.autos('dm_ab') = 4, 'with quiet hours not running, "also in quiet hours" does not answer');
  update public.user_notification_settings set quiet_enabled = true, quiet_days = '{1,2,3,4,5,6,7}', quiet_start = '00:00', quiet_end = '23:59:59' where user_id = pg_temp.i('ada');
  perform pg_temp.say('dm_ab', 'bob', 'inside quiet hours');
  perform pg_temp.expect(pg_temp.autos('dm_ab') = 5, 'inside them it answers');

  -- The push claim: each reply once.
  due := (select count(*) from public.away_reply_log where message_id is not null and push_claimed_at is null and replied_at > now() - interval '15 minutes');
  claimed := (select count(*) from public.claim_away_reply_pushes());
  perform pg_temp.expect(due >= 1 and claimed = due, 'the replies still waiting for a push are claimed (the older ones are not)');
  perform pg_temp.expect((select count(*) from public.claim_away_reply_pushes()) = 0, 'and only once');
end $$;

-- ===================================== 5. nobody forges an auto-reply
do $$
declare
  mine uuid;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('insert into public.messages (conversation_id, sender_id, type, body, auto_reply) values (%L, %L, %L, %L, true)', pg_temp.i('dm_ab'), pg_temp.i('bob'), 'text', 'I am a robot')) = '42501', 'a client cannot make an auto-reply');
  insert into public.messages (conversation_id, sender_id, type, body)
  values (pg_temp.i('dm_ab'), pg_temp.i('bob'), 'text', 'real words') returning id into mine;
  update public.messages set auto_reply = true where id = mine;
  perform pg_temp.root();
  perform pg_temp.expect(not (select auto_reply from public.messages where id = mine), 'nor turn a message into one');
  update public.messages set auto_reply = false where conversation_id = pg_temp.i('dm_ab') and auto_reply;
  perform pg_temp.expect(exists (select 1 from public.messages where conversation_id = pg_temp.i('dm_ab') and auto_reply), 'and the flag does not change after, even for the owner');
end $$;

-- ===================================== 6. round video messages
do $$
declare
  conv text := pg_temp.i('dm_ab')::text;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  -- [attachment] with the given [extra] merged in.
  perform pg_temp.expect(pg_temp.state(format($q$insert into public.messages (conversation_id, sender_id, type, body, attachment) values (%L, %L, 'file', '', %L::jsonb)$q$,
    conv, pg_temp.i('bob'),
    json_build_object('kind','video','bucket','chat-files','path',conv || '/note-1.mp4','name','note.mp4','mime_type','video/mp4','size',2500000,'video_note',true,'duration_ms',12000)::text)) = 'ok', 'a round video message of 12 seconds is stored');
  perform pg_temp.expect(pg_temp.state(format($q$insert into public.messages (conversation_id, sender_id, type, body, attachment) values (%L, %L, 'file', '', %L::jsonb)$q$,
    conv, pg_temp.i('bob'),
    json_build_object('kind','video','bucket','chat-files','path',conv || '/note-2.mp4','name','note.mp4','mime_type','video/mp4','size',2500000,'duration_ms',900000)::text)) = 'ok', 'an ordinary video is not held to the limits');
  perform pg_temp.expect(pg_temp.state(format($q$insert into public.messages (conversation_id, sender_id, type, body, attachment) values (%L, %L, 'file', '', %L::jsonb)$q$,
    conv, pg_temp.i('bob'),
    json_build_object('kind','video','bucket','chat-files','path',conv || '/note-3.mp4','name','note.mp4','mime_type','video/mp4','size',2500000,'video_note',true,'duration_ms',61001)::text)) = '22023', 'over 60 seconds is refused');
  perform pg_temp.expect(pg_temp.state(format($q$insert into public.messages (conversation_id, sender_id, type, body, attachment) values (%L, %L, 'file', '', %L::jsonb)$q$,
    conv, pg_temp.i('bob'),
    json_build_object('kind','video','bucket','chat-files','path',conv || '/note-4.mp4','name','note.mp4','mime_type','video/mp4','size',2500000,'video_note',true)::text)) = '22023', 'no length is refused');
  perform pg_temp.expect(pg_temp.state(format($q$insert into public.messages (conversation_id, sender_id, type, body, attachment) values (%L, %L, 'file', '', %L::jsonb)$q$,
    conv, pg_temp.i('bob'),
    json_build_object('kind','video','bucket','chat-files','path',conv || '/note-5.mp4','name','note.mp4','mime_type','video/mp4','size',40000000,'video_note',true,'duration_ms',30000)::text)) = '22023', 'over 30 MB is refused');
  perform pg_temp.expect(pg_temp.state(format($q$insert into public.messages (conversation_id, sender_id, type, body, attachment) values (%L, %L, 'file', '', %L::jsonb)$q$,
    conv, pg_temp.i('bob'),
    json_build_object('kind','video','bucket','chat-files','path',conv || '/note-6.mp4','name','note.mp4','mime_type','video/mp4','size',2500000,'video_note','yes','duration_ms',3000)::text)) = '22023', 'a flag that is not true is refused');
  perform pg_temp.expect(pg_temp.state(format($q$insert into public.messages (conversation_id, sender_id, type, body, attachment) values (%L, %L, 'file', '', %L::jsonb)$q$,
    conv, pg_temp.i('bob'),
    json_build_object('kind','file','bucket','chat-files','path',conv || '/note-7.pdf','name','a.pdf','mime_type','application/pdf','size',2500,'video_note',true,'duration_ms',3000)::text)) = '22023', 'a file that is not a video is refused');
  perform pg_temp.expect(pg_temp.state(format($q$insert into public.messages (conversation_id, sender_id, type, body, attachment, attachment_group_id) values (%L, %L, 'file', '', %L::jsonb, gen_random_uuid())$q$,
    conv, pg_temp.i('bob'),
    json_build_object('kind','video','bucket','chat-files','path',conv || '/note-8.mp4','name','note.mp4','mime_type','video/mp4','size',2500000,'video_note',true,'duration_ms',3000)::text)) = '22023', 'a note is never part of an album');
  perform pg_temp.expect(pg_temp.state(format($q$insert into public.messages (conversation_id, sender_id, type, body, attachment) values (%L, %L, 'file', '', %L::jsonb)$q$,
    conv, pg_temp.i('bob'),
    json_build_object('kind','video','bucket','chat-files','path',conv || '/note-9.mp4','name','note.mp4','mime_type','video/mp4','size',2500000,'video_note',true,'duration_ms',3000,'view_once',true)::text)) = 'ok', 'a view-once note is fine');
  perform pg_temp.root();
end $$;

-- ===================================== 7. deleting an account, and the export
do $$
declare
  exported jsonb;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  insert into public.quick_replies (user_id, shortcut, body) values (pg_temp.i('ada'), 'hours', 'Open 9 to 5');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.export_my_quick_replies(%L)', pg_temp.i('bob'))) = '42501', 'clients cannot call the export');
  perform pg_temp.root();
  perform pg_temp.expect(has_function_privilege('service_role', 'public.export_my_quick_replies(uuid)', 'execute'), 'the data-export function can');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_away_reply(true, 'Back Monday', null, true);
  perform pg_temp.root();
  exported := public.export_my_quick_replies(pg_temp.i('ada'));
  perform pg_temp.expect(jsonb_array_length(exported->'quick_replies') = 1 and exported->'quick_replies'->0->>'shortcut' = 'hours'
    and exported->'away'->>'message' = 'Back Monday' and (exported->'away'->>'during_quiet_hours')::boolean, 'ada''s export holds her phrases and her away settings');
  exported := public.export_my_quick_replies(pg_temp.i('gus'));
  perform pg_temp.expect(exported = jsonb_build_object('quick_replies', '[]'::jsonb, 'away', null), 'a person with none exports nothing');
  exported := public.export_my_quick_replies(pg_temp.i('bob'));
  perform pg_temp.expect(jsonb_array_length(exported->'quick_replies') = 2 and not (exported::text like '%hours%'), 'and nobody''s export holds another''s phrases');

  perform pg_temp.expect(exists (select 1 from public.away_reply_log where away_user_id = pg_temp.i('ada')), 'ada has a reply log before');
  update public.profiles set deleted_at = now() where id = pg_temp.i('ada');
  perform pg_temp.expect(not exists (select 1 from public.quick_replies where user_id = pg_temp.i('ada')), 'deleting an account erases the phrases');
  perform pg_temp.expect(not exists (select 1 from public.user_notification_settings where user_id = pg_temp.i('ada') and (away_enabled or away_message is not null or away_in_quiet_hours)), 'switches the reply off and forgets its words');
  perform pg_temp.expect(not exists (select 1 from public.away_reply_log where away_user_id = pg_temp.i('ada') or to_user_id = pg_temp.i('ada')), 'and drops the log');
  perform pg_temp.say('dm_ab', 'bob', 'anybody home');
  perform pg_temp.expect(pg_temp.autos('dm_ab') = 5, 'nothing answers for a deleted account');
  perform pg_temp.expect(pg_temp.val($q$select count(*)::text from public.quick_replies where user_id = (select id from pg_temp.ids where name = 'bob')$q$) = '2', 'other people''s phrases stay');

  -- The scheduled job has its own, the dispatcher is not touched.
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform pg_temp.expect(exists (select 1 from cron.job where jobname = 'wecord-away-reply-push' and schedule = '* * * * *'), 'the push wake-up is a cron job of its own');
    perform pg_temp.expect((select command from cron.job where jobname = 'wecord-later-dispatch') not like '%away%', 'and the every-minute dispatcher does not run it');
  end if;
end $$;

\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'quick replies and video notes: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
