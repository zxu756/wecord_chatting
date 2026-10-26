-- Behaviour checks for event subscriptions, the bot API 2.0 and the developer
-- page (I2 and I3: migrations 202610281100 to 202610281160). Run by
-- test/supabase/bot_events_test.dart against the local database: it applies
-- the migrations in a transaction, plays people and bots through them, and
-- rolls everything back. Run from the repository root.
--
-- What it walks through: who may set an event address (managers only, the
-- same address rules as the callback, the secret shown once); what is queued
-- for each kind of event and what the payload holds; what a bot is not told
-- (its own doings, people who blocked it, messages under review, chats it
-- cannot read, the words of restricted, locked and disappearing chats); the
-- limits; the queue (claim, lease, retries, failure, pause); the test event;
-- the bot API for channels, groups and direct chats (reading, writing, files,
-- polls, threads, members); how a bot is let into direct chats and groups; the
-- developer page; deleting an account and the data export; and that the older
-- functions were left alone.
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

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create function pg_temp.i(n text) returns uuid language sql as $$ select id from pg_temp.ids where name = n $$;
grant execute on function pg_temp.i(text) to public;
grant execute on all functions in schema pg_temp to public;

-- ------------------------------------------------------------------ cast
-- ada owns the circle club (channels plaza and vault); bob, cat, dan and fay
-- are members; eve is nobody's. Helper and Other are bots of the club. root is
-- the platform admin. vault is private: only ada (and the bots) see it.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@i2.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'fay'),(7,'root')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_i2', initcap(name)
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'fay'),(7,'root')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'fay'),(7,'root')) v(n, name);
insert into public.app_admins (user_id, role) values (pg_temp.i('root'), 'owner');

insert into public.friendships (user_low_id, user_high_id)
select least(pg_temp.i('ada'), pg_temp.i(n)), greatest(pg_temp.i('ada'), pg_temp.i(n))
from (values ('bob'),('cat'),('dan'),('fay')) v(n);

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'club', public.create_circle('Hike Club', array[
  pg_temp.i('bob'), pg_temp.i('cat'), pg_temp.i('dan'), pg_temp.i('fay')]);
insert into pg_temp.ids select 'plaza', public.create_circle_channel(pg_temp.i('club'), 'plaza', null, 'text');
insert into pg_temp.ids select 'vault', public.create_circle_channel(pg_temp.i('club'), 'vault', null, 'text');
select public.set_channel_privacy(pg_temp.i('vault'), true, false);
select pg_temp.root();
insert into pg_temp.ids select 'plaza_conv', conversation_id from public.circle_channels where id = pg_temp.i('plaza');
insert into pg_temp.ids select 'vault_conv', conversation_id from public.circle_channels where id = pg_temp.i('vault');

-- Bots, made the way the bots Edge function does it: a banned login first,
-- then create_circle_bot as the manager.
create temp table tokens (name text primary key, token text not null);
grant all on tokens to public;
insert into pg_temp.ids values ('helper_user', gen_random_uuid()), ('other_user', gen_random_uuid());
insert into auth.users (instance_id, id, aud, role, raw_app_meta_data, raw_user_meta_data, banned_until, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', pg_temp.i(n), 'authenticated', 'authenticated',
  '{"provider":"bot","providers":["bot"]}'::jsonb, '{"bot":true}'::jsonb, 'infinity', now(), now()
from (values ('helper_user'),('other_user')) v(n);
select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'helper', (public.create_circle_bot(pg_temp.i('club'), 'Helper', null, pg_temp.i('helper_user'))->>'id')::uuid;
insert into pg_temp.ids select 'other', (public.create_circle_bot(pg_temp.i('club'), 'Other', null, pg_temp.i('other_user'))->>'id')::uuid;
select pg_temp.root();
-- The bots (and ada) see the private channel.
insert into public.circle_channel_overwrites (circle_id, channel_id, user_id, allow)
select pg_temp.i('club'), pg_temp.i('vault'), pg_temp.i(n),
  public.circle_permission_bit('view_channel') | public.circle_permission_bit('send_messages')
from (values ('helper_user'), ('other_user')) v(n);
-- Tokens are shown once; the script makes known ones.
update public.circle_bots set token_hash = public.webhook_token_hash(rpad('helper-token-', 43, 'a')) where id = pg_temp.i('helper');
update public.circle_bots set token_hash = public.webhook_token_hash(rpad('other-token-', 43, 'b')) where id = pg_temp.i('other');
insert into tokens values ('helper', rpad('helper-token-', 43, 'a')), ('other', rpad('other-token-', 43, 'b'));
create function pg_temp.tok(n text) returns text language sql as $$ select token from pg_temp.tokens where name = n $$;

-- A person says something in a conversation; returns the message id.
create function pg_temp.say(who text, conv text, content text, mention_of text default null)
returns uuid language plpgsql as $$
declare
  r uuid;
  mentions jsonb := '[]'::jsonb;
begin
  if mention_of is not null then
    mentions := jsonb_build_array(jsonb_build_object(
      'kind', 'user', 'user_id', pg_temp.i(mention_of), 'display_name', 'x', 'start', 0, 'end', 1));
  end if;
  perform pg_temp.act(pg_temp.i(who));
  r := public.send_text_message(pg_temp.i(conv), content, null, null, mentions, null);
  perform pg_temp.root();
  return r;
end $$;

-- A bot says something in a channel of its circle (the older route).
create function pg_temp.bot_send(who text, chan text, content text)
returns uuid language plpgsql as $$
begin
  return public.bot_api_send_message_with_components(pg_temp.tok(who), pg_temp.i(chan), content, null, null);
end $$;

-- A person runs a statement; the SQLSTATE it raises, or 'ok'.
create function pg_temp.as_state(who text, stmt text)
returns text language plpgsql as $$
declare r text;
begin
  if who = 'anon' then
    perform pg_temp.act(null);
  else
    perform pg_temp.act(pg_temp.i(who));
  end if;
  begin
    execute stmt;
    r := 'ok';
  exception when others then
    r := sqlstate;
  end;
  perform pg_temp.root();
  return r;
end $$;

-- A person runs a query that returns one jsonb; null when it raises.
create function pg_temp.as_json(who text, stmt text)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.act(pg_temp.i(who));
  begin
    execute stmt into r;
  exception when others then
    r := null;
  end;
  perform pg_temp.root();
  return r;
end $$;

-- Saves an event subscription as [who]; the answer (with the secret, once).
create function pg_temp.sub(who text, bot text, url text, evs text[])
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.act(pg_temp.i(who));
  r := public.set_bot_event_subscription(pg_temp.i(bot), url, evs);
  perform pg_temp.root();
  return r;
end $$;

-- How many deliveries a bot has (of one kind, or of any).
create function pg_temp.evn(bot text, ev text default null)
returns integer language sql as $$
  select count(*)::integer from public.bot_event_deliveries d
  where d.bot_id = pg_temp.i(bot) and (ev is null or d.event = ev)
$$;

-- The payload of the newest delivery of a kind.
create function pg_temp.last_ev(bot text, ev text)
returns jsonb language sql as $$
  select d.payload from public.bot_event_deliveries d
  where d.bot_id = pg_temp.i(bot) and d.event = ev
  order by d.created_at desc, d.id desc limit 1
$$;

create function pg_temp.clear_q() returns void language sql as $$
  delete from public.bot_event_deliveries
$$;

-- The row a bot sees: all its fields.
create function pg_temp.botrow(bot text) returns public.circle_bots language sql as $$
  select b.* from public.circle_bots b where b.id = pg_temp.i(bot)
$$;
grant execute on all functions in schema pg_temp to public;

-- Both bots hear everything; the address is only a label (nothing is sent
-- from the database).
select pg_temp.sub('ada', 'helper', 'https://example.com/events', public.bot_event_types());
select pg_temp.sub('ada', 'other', 'https://example.org/events', array['message.created']);

-- ===================================== 1. who may set an event address
do $$
declare
  bad text;
  r jsonb;
  r2 jsonb;
  r3 jsonb;
  old_secret text;
begin
  select secret into old_secret from public.bot_event_subscriptions where bot_id = pg_temp.i('helper');
  perform pg_temp.expect(old_secret ~ '^[0-9a-f]{64}$', 'the secret is 32 random bytes as hex');

  perform pg_temp.expect(pg_temp.as_state('bob', format('select public.set_bot_event_subscription(%L, %L, %L)', pg_temp.i('helper'), 'https://example.com/e', array['message.created'])) = '42501', 'a member cannot set an event address');
  perform pg_temp.expect(pg_temp.as_state('eve', format('select public.set_bot_event_subscription(%L, %L, %L)', pg_temp.i('helper'), 'https://example.com/e', array['message.created'])) = '42501', 'someone outside the circle cannot');
  perform pg_temp.expect(pg_temp.as_state('anon', format('select public.set_bot_event_subscription(%L, %L, %L)', pg_temp.i('helper'), 'https://example.com/e', array['message.created'])) in ('42501', '42883'), 'nobody signed in cannot');
  perform pg_temp.expect(pg_temp.as_state('bob', format('select public.get_bot_event_subscription(%L)', pg_temp.i('helper'))) = '42501', 'a member cannot read it');
  perform pg_temp.expect(pg_temp.as_state('bob', format('select public.rotate_bot_event_secret(%L)', pg_temp.i('helper'))) = '42501', 'or rotate the secret');
  perform pg_temp.expect(pg_temp.as_state('bob', format('select public.clear_bot_event_subscription(%L)', pg_temp.i('helper'))) = '42501', 'or clear it');
  perform pg_temp.expect(pg_temp.as_state('bob', format('select public.send_bot_test_event(%L)', pg_temp.i('helper'))) = '42501', 'or send a test');
  perform pg_temp.expect(pg_temp.as_state('bob', format('select public.list_bot_event_deliveries(%L)', pg_temp.i('helper'))) = '42501', 'or read the deliveries');
  perform pg_temp.expect(pg_temp.as_state('bob', 'select count(*) from public.bot_event_subscriptions') = '42501', 'the table is closed to clients');
  perform pg_temp.expect(pg_temp.as_state('bob', 'select count(*) from public.bot_event_deliveries') = '42501', 'and so is the queue');
  perform pg_temp.expect(pg_temp.as_state('bob', 'select count(*) from public.bot_api_calls') = '42501', 'and the call log');

  -- The same address rules as the callback (SSRF).
  for bad in
    select unnest(array[
      'http://example.com/hook', 'example.com/hook', '', 'https://localhost/hook', 'https://127.0.0.1/hook',
      'https://10.1.2.3/', 'https://192.168.1.1/', 'https://169.254.169.254/latest/meta-data/',
      'https://2130706433/', 'https://[::1]/', 'https://metadata.google.internal/', 'https://router.local/',
      'https://127.0.0.1.nip.io/', 'https://example.com:8080/hook', 'https://user:pw@example.com/hook',
      'https://example.com/a b'
    ])
  loop
    perform pg_temp.expect(pg_temp.as_state('ada', format('select public.set_bot_event_subscription(%L, %L, %L)', pg_temp.i('helper'), bad, array['message.created'])) = '22023', 'event address refused: ' || bad);
  end loop;
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.set_bot_event_subscription(%L, %L, %L)', pg_temp.i('helper'), 'https://example.com/' || repeat('a', 500), array['message.created'])) = '22023', 'a long event address is refused');

  -- The kinds of event.
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.set_bot_event_subscription(%L, %L, %L)', pg_temp.i('helper'), 'https://example.com/e', array['message.created', 'bogus'])) = '22023', 'an unknown kind is refused');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.set_bot_event_subscription(%L, %L, %L)', pg_temp.i('helper'), 'https://example.com/e', array[]::text[])) = '22023', 'at least one kind');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.set_bot_event_subscription(%L, %L, null)', pg_temp.i('helper'), 'https://example.com/e')) = '22023', 'null kinds are refused');
  perform pg_temp.expect((select secret from public.bot_event_subscriptions where bot_id = pg_temp.i('helper')) = old_secret, 'refused changes leave the subscription alone');

  -- A manager changes the address: the secret is not shown again.
  r2 := pg_temp.sub('ada', 'helper', 'https://example.com/events2', array['message.created', 'reaction.added', 'message.created']);
  perform pg_temp.expect(not r2 ? 'secret', 'changing the address shows no secret');
  perform pg_temp.expect(r2->>'url' = 'https://example.com/events2' and r2->'events' = '["message.created","reaction.added"]'::jsonb, 'and repeats are dropped');
  perform pg_temp.expect((select secret from public.bot_event_subscriptions where bot_id = pg_temp.i('helper')) = old_secret, 'the secret is kept');
  r := pg_temp.as_json('ada', format('select public.get_bot_event_subscription(%L)', pg_temp.i('helper')));
  perform pg_temp.expect(r is not null and not r ? 'secret' and r->>'enabled' = 'true', 'the manager reads the state, never the secret');
  perform pg_temp.expect(position(old_secret in r::text) = 0, 'not even inside another field');

  r3 := pg_temp.as_json('ada', format('select public.rotate_bot_event_secret(%L)', pg_temp.i('helper')));
  perform pg_temp.expect(r3->>'secret' ~ '^[0-9a-f]{64}$' and r3->>'secret' <> old_secret, 'rotating shows a new secret once');
  perform pg_temp.expect((select secret from public.bot_event_subscriptions where bot_id = pg_temp.i('helper')) = r3->>'secret', 'and stores it');

  -- A bot with no token has nothing to receive for.
  update public.circle_bots set token_hash = null where id = pg_temp.i('other');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.set_bot_event_subscription(%L, %L, %L)', pg_temp.i('other'), 'https://example.com/e', array['message.created'])) = '22023', 'a bot without a token takes no subscription');
  update public.circle_bots set token_hash = public.webhook_token_hash(pg_temp.tok('other')) where id = pg_temp.i('other');

  -- The log of who did what holds no secret.
  perform pg_temp.expect((select count(*) from public.circle_audit_log where action = 'bot_events_set' and circle_id = pg_temp.i('club')) >= 3, 'saving is in the circle log');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where action = 'bot_events_rotate') = 1, 'so is rotating');
  perform pg_temp.expect(not exists (select 1 from public.circle_audit_log where action like 'bot_events%' and (changes::text like '%' || old_secret || '%' or changes::text like '%' || (r3->>'secret') || '%')), 'and no secret is in it');
  perform pg_temp.expect((select changes->>'host' from public.circle_audit_log where action = 'bot_events_set' order by created_at desc, id desc limit 1) = 'example.com', 'it names the host, not the whole address');

  -- Clearing forgets the subscription and drops what waited.
  perform pg_temp.clear_q();
  insert into public.bot_event_deliveries (bot_id, event, payload) values (pg_temp.i('other'), 'message.created', '{}');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.clear_bot_event_subscription(%L)', pg_temp.i('other'))) = 'ok', 'a manager clears the subscription');
  perform pg_temp.expect(not exists (select 1 from public.bot_event_subscriptions where bot_id = pg_temp.i('other')), 'it is gone');
  perform pg_temp.expect((select state from public.bot_event_deliveries where bot_id = pg_temp.i('other')) = 'dropped', 'what waited is dropped');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where action = 'bot_events_clear') = 1, 'clearing is in the log');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.clear_bot_event_subscription(%L)', pg_temp.i('other'))) = 'ok', 'clearing again is quiet');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where action = 'bot_events_clear') = 1, 'and logs nothing');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.rotate_bot_event_secret(%L)', pg_temp.i('other'))) = 'P0002', 'rotating a subscription that is not there is refused');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.send_bot_test_event(%L)', pg_temp.i('other'))) = 'P0002', 'so is a test');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_event_subscription_state(%L)', pg_temp.i('other'))) = 'ok' and public.bot_event_subscription_state(pg_temp.i('other'))->>'enabled' = 'false', 'the state of a bot without one says it is off');
end $$;
select pg_temp.sub('ada', 'helper', 'https://example.com/events', public.bot_event_types());
select pg_temp.sub('ada', 'other', 'https://example.org/events', array['message.created', 'message.mentioned']);

-- ===================================== 2. what is queued for each kind of event
do $$
declare
  p jsonb;
  m uuid;
  m2 uuid;
  held uuid;
  n integer;
begin
  perform pg_temp.clear_q();

  -- A message in a channel.
  m := pg_temp.say('bob', 'plaza_conv', 'hello helper');
  perform pg_temp.expect(pg_temp.evn('helper', 'message.created') = 1, 'a message in a channel is queued for a bot that subscribed');
  perform pg_temp.expect(pg_temp.evn('other', 'message.created') = 1, 'and for every other bot that did');
  p := pg_temp.last_ev('helper', 'message.created');
  perform pg_temp.expect(p->'message'->>'content' = 'hello helper' and p->'message'->>'id' = m::text and p->'message'->>'type' = 'text', 'with its words, type and id');
  perform pg_temp.expect(p->'chat'->>'kind' = 'channel' and p->'chat'->>'id' = pg_temp.i('plaza_conv')::text and p->'chat'->>'circle_id' = pg_temp.i('club')::text and p->'chat'->>'name' = 'plaza', 'and the chat it was said in');
  perform pg_temp.expect((select array_agg(k order by k) from jsonb_object_keys(p->'message'->'author') k) = array['id','is_bot','name','username'], 'the author is only id, username, name and whether a bot');
  perform pg_temp.expect(p->'message'->'author'->>'username' = 'bob_i2' and (p->'message'->'author'->>'is_bot')::boolean = false, 'with the right values');
  perform pg_temp.expect(p::text not like '%i2.test%' and p::text not like '%bio%' and p::text not like '%birthday%', 'no e-mail, bio or birthday leaves the database');
  perform pg_temp.expect((select actor_id from public.bot_event_deliveries where bot_id = pg_temp.i('helper') and event = 'message.created') = pg_temp.i('bob') and (select conversation_id from public.bot_event_deliveries where bot_id = pg_temp.i('helper') and event = 'message.created') = pg_temp.i('plaza_conv'), 'the row remembers who and where');
  perform pg_temp.expect((select state = 'queued' and attempts = 0 from public.bot_event_deliveries where bot_id = pg_temp.i('helper')), 'it waits to be sent');

  -- The bot's own doings are not told back to it.
  perform pg_temp.clear_q();
  perform pg_temp.bot_send('helper', 'plaza', 'beep');
  perform pg_temp.expect(pg_temp.evn('helper') = 0, 'a bot is not told about its own message');
  perform pg_temp.expect(pg_temp.evn('other', 'message.created') = 1, 'another bot is');
  perform pg_temp.expect(pg_temp.last_ev('other', 'message.created')->'message'->'author'->>'is_bot' = 'true', 'and it can tell the author is a bot');

  -- A person who blocked the bot is not passed on to it.
  perform pg_temp.clear_q();
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('dan'), pg_temp.i('helper_user'));
  perform pg_temp.say('dan', 'plaza_conv', 'from dan');
  perform pg_temp.expect(pg_temp.evn('helper') = 0, 'what a person who blocked the bot says is not queued for it');
  perform pg_temp.expect(pg_temp.evn('other', 'message.created') = 1, 'though it is for the bot they did not block');
  delete from public.blocks where blocker_id = pg_temp.i('dan');

  -- A private channel: only the bots that can view it.
  perform pg_temp.clear_q();
  perform pg_temp.say('ada', 'vault_conv', 'managers only');
  perform pg_temp.expect(pg_temp.evn('helper', 'message.created') = 1 and pg_temp.evn('other', 'message.created') = 1, 'a private channel tells the bots that were let into it');
  delete from public.circle_channel_overwrites where channel_id = pg_temp.i('vault') and user_id = pg_temp.i('other_user');
  perform pg_temp.clear_q();
  perform pg_temp.say('ada', 'vault_conv', 'still managers only');
  perform pg_temp.expect(pg_temp.evn('helper', 'message.created') = 1, 'one that may view it hears');
  perform pg_temp.expect(pg_temp.evn('other') = 0, 'one that may not view it hears nothing');
  insert into public.circle_channel_overwrites (circle_id, channel_id, user_id, allow)
  values (pg_temp.i('club'), pg_temp.i('vault'), pg_temp.i('other_user'), public.circle_permission_bit('view_channel') | public.circle_permission_bit('send_messages'));

  -- A suspended circle is silent.
  perform pg_temp.clear_q();
  update public.circles set disabled_at = now(), disabled_mode = 'suspend' where id = pg_temp.i('club');
  delete from public.circle_members where circle_id = pg_temp.i('club') and user_id = pg_temp.i('fay');
  perform pg_temp.expect(pg_temp.evn('helper') = 0, 'a suspended circle queues nothing');
  update public.circles set disabled_at = null, disabled_mode = null where id = pg_temp.i('club');
  insert into public.circle_members (circle_id, user_id, role, rules_accepted_at) values (pg_temp.i('club'), pg_temp.i('fay'), 'member', now());

  -- Under review (the AI guard), then released or removed.
  perform pg_temp.clear_q();
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_ai_guard(pg_temp.i('club'), true, 'joined_days', 3, 10, 'hold');
  perform pg_temp.root();
  update public.circles set ai_enabled = true where id = pg_temp.i('club');
  perform vault.create_secret('http://127.0.0.1:54321/functions/v1', 'wecord_functions_url');
  perform vault.create_secret('events-test-secret', 'wecord_dispatch_secret');
  held := pg_temp.say('bob', 'plaza_conv', 'Win cheap pills now http://evil.example');
  perform pg_temp.expect((select review_state from public.messages where id = held) = 'checking', 'the guard is holding the message (setup)');
  perform pg_temp.expect(pg_temp.evn('helper') = 0 and pg_temp.evn('other') = 0, 'a message that waits for the AI is not queued');
  perform public.finish_message_review(held, 'spam', 'Spam');
  perform pg_temp.expect(pg_temp.evn('helper') = 0, 'nor is one the AI held');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(public.decide_message_review(held, 'approve') = 'approved', 'a moderator approves it (setup)');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.evn('helper', 'message.created') = 1 and pg_temp.last_ev('helper', 'message.created')->'message'->>'id' = held::text, 'when it is released it is queued, as a new message');
  perform pg_temp.expect(exists (
    select 1 from net.http_request_queue q
    where q.url = 'http://127.0.0.1:54321/functions/v1/bot-events'
      and q.headers->>'Authorization' = 'Bearer events-test-secret'
  ), 'and the bot-events function is woken with the shared secret');
  perform pg_temp.clear_q();
  held := pg_temp.say('cat', 'plaza_conv', 'Win cheap pills now http://evil2.example');
  perform public.finish_message_review(held, 'spam', 'Spam');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(public.decide_message_review(held, 'remove') = 'removed', 'a moderator removes one (setup)');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.evn('helper') = 0, 'a message removed in review is never told');
  perform public.set_circle_ai_guard(pg_temp.i('club'), false, 'joined_days', 3, 10, 'hold');

  -- A system message is not a message.
  perform pg_temp.clear_q();
  insert into public.messages (conversation_id, sender_id, type, body) values (pg_temp.i('plaza_conv'), pg_temp.i('bob'), 'system', 'bob did something');
  perform pg_temp.expect(pg_temp.evn('helper') = 0, 'system messages are not events');

  -- Edit and delete.
  perform pg_temp.clear_q();
  m2 := pg_temp.say('bob', 'plaza_conv', 'first words');
  perform pg_temp.clear_q();
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.edit_message(m2, 'second words');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.evn('helper', 'message.updated') = 1, 'an edit is queued');
  p := pg_temp.last_ev('helper', 'message.updated');
  perform pg_temp.expect(p->'message'->>'content' = 'second words' and p->'message' ? 'edited_at', 'with the new words and the time');
  perform pg_temp.expect(pg_temp.evn('other', 'message.updated') = 0, 'to a bot that did not subscribe to edits');

  perform pg_temp.clear_q();
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.recall_message(m2);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.evn('helper', 'message.deleted') = 1, 'deleting is queued');
  p := pg_temp.last_ev('helper', 'message.deleted');
  perform pg_temp.expect((select array_agg(k order by k) from jsonb_object_keys(p->'message') k) = array['deleted_at','id'], 'with the id and the time, never the words');
  perform pg_temp.expect(p::text not like '%second words%', 'the words are nowhere in it');

  -- A mention reaches only the bot that was mentioned.
  perform pg_temp.clear_q();
  m := pg_temp.say('bob', 'plaza_conv', 'x ping', 'helper_user');
  perform pg_temp.expect(pg_temp.evn('helper', 'message.mentioned') = 1, 'a mention is queued for the bot mentioned');
  perform pg_temp.expect(pg_temp.evn('other', 'message.mentioned') = 0, 'not for another bot');
  p := pg_temp.last_ev('helper', 'message.mentioned');
  perform pg_temp.expect(p->'message'->>'content' = 'x ping' and p->'mention'->>'kind' = 'user' and p->'chat'->>'kind' = 'channel', 'with the message and the kind of mention');
  perform pg_temp.expect(pg_temp.evn('helper', 'message.created') = 1, 'next to the plain message event');

  -- Reactions: who and what, never the words.
  perform pg_temp.clear_q();
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.toggle_message_reaction(m, '👍');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.evn('helper', 'reaction.added') = 1, 'a reaction is queued');
  p := pg_temp.last_ev('helper', 'reaction.added');
  perform pg_temp.expect(p->>'emoji' = '👍' and p->>'message_id' = m::text and p->'user'->>'username' = 'cat_i2', 'with the emoji, the message and who');
  perform pg_temp.expect(p::text not like '%x ping%', 'but not the words of the message');
  perform pg_temp.expect(pg_temp.evn('other', 'reaction.added') = 0, 'only for bots that subscribed');
  perform pg_temp.clear_q();
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.toggle_message_reaction(m, '👍');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.evn('helper') = 0, 'taking a reaction off is not an event');
  perform public.bot_api_add_reaction(pg_temp.tok('helper'), m, '🎉');
  perform pg_temp.expect(pg_temp.evn('helper') = 0, 'a bot is not told about its own reaction');

  -- Joining and leaving the circle.
  perform pg_temp.clear_q();
  insert into public.circle_members (circle_id, user_id, role, rules_accepted_at) values (pg_temp.i('club'), pg_temp.i('eve'), 'member', now());
  perform pg_temp.expect(pg_temp.evn('helper', 'member.joined') = 1, 'someone joining the circle is queued');
  p := pg_temp.last_ev('helper', 'member.joined');
  perform pg_temp.expect(p->>'circle_id' = pg_temp.i('club')::text and p->'user'->>'username' = 'eve_i2', 'with the circle and the person');
  delete from public.circle_members where circle_id = pg_temp.i('club') and user_id = pg_temp.i('eve');
  perform pg_temp.expect(pg_temp.evn('helper', 'member.left') = 1, 'and leaving');
  perform pg_temp.expect(pg_temp.evn('other') = 0, 'the other bot did not ask for either');

  -- A bot's own coming and going is not news to it.
  perform pg_temp.clear_q();
  delete from public.circle_members where circle_id = pg_temp.i('club') and user_id = pg_temp.i('other_user');
  perform pg_temp.expect(pg_temp.evn('helper', 'member.left') = 1, 'another bot leaving is');
  perform pg_temp.expect(pg_temp.evn('other') = 0, 'but the bot that left hears nothing');
  insert into public.circle_members (circle_id, user_id, role, rules_accepted_at) values (pg_temp.i('club'), pg_temp.i('other_user'), 'member', now());

  -- A slash command, for a bot with no callback address.
  perform pg_temp.clear_q();
  insert into public.bot_commands (bot_id, circle_id, name, description) values (pg_temp.i('helper'), pg_temp.i('club'), 'ping', 'Pong');
  perform pg_temp.act(pg_temp.i('dan'));
  perform public.invoke_bot_command(pg_temp.i('plaza_conv'), 'ping', 'now');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.evn('helper', 'interaction.created') = 1, 'a command for a bot without a callback is an event');
  p := pg_temp.last_ev('helper', 'interaction.created');
  perform pg_temp.expect(p->'interaction'->>'command' = 'ping' and p->'interaction'->>'options' = 'now' and p->'interaction'->'user'->>'username' = 'dan_i2', 'with the command and who ran it');

  -- With a callback address, the press goes there instead.
  perform pg_temp.clear_q();
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_bot_callback(pg_temp.i('helper'), 'https://example.com/callback');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.invoke_bot_command(pg_temp.i('plaza_conv'), 'ping', 'cb');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.clear_bot_callback(pg_temp.i('helper'));
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.evn('helper', 'interaction.created') = 0, 'it is not told twice when the callback has it');

  -- Messages of other kinds name the type only.
  perform pg_temp.clear_q();
  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (pg_temp.i('plaza_conv'), pg_temp.i('bob'), 'file', 'the map', '{"kind":"file","bucket":"chat-files","path":"secret/path/map.pdf","name":"map.pdf","size":1234,"mime_type":"application/pdf"}');
  p := pg_temp.last_ev('helper', 'message.created');
  perform pg_temp.expect(p->'message'->'attachment'->>'name' = 'map.pdf' and p->'message'->'attachment'->>'size' = '1234', 'a file is named, with its size');
  perform pg_temp.expect(p::text not like '%secret/path%' and p::text not like '%chat-files%', 'and never where it is stored');
  perform pg_temp.clear_q();
  insert into public.messages (conversation_id, sender_id, type, body) values (pg_temp.i('plaza_conv'), pg_temp.i('bob'), 'sticker', 'wave hello');
  p := pg_temp.last_ev('helper', 'message.created');
  perform pg_temp.expect(p->'message'->>'type' = 'sticker' and not p->'message' ? 'content', 'a sticker is named by type only');
end $$;

-- ===================================== 3. chats the bot may not read, and what is held back
-- A group of ada, bob and cat. Helper starts closed to groups and to direct
-- chats.
select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'plan', public.create_group_conversation('Plan', array[pg_temp.i('bob'), pg_temp.i('cat')]);
select pg_temp.root();

do $$
declare
  p jsonb;
  m uuid;
  dm uuid;
begin
  perform pg_temp.clear_q();
  perform pg_temp.say('bob', 'plan', 'nobody invited a bot');
  perform pg_temp.expect(pg_temp.evn('helper') = 0, 'a group without the bot queues nothing for it');

  -- Adding a bot to a group.
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.add_bot_to_group(%L, %L)', pg_temp.i('plan'), pg_temp.i('helper_user'))) = '42501', 'a bot that is closed to groups cannot be added');
  perform pg_temp.expect(pg_temp.as_state('bob', format('select public.set_bot_availability(%L, %L, true, true)', pg_temp.i('helper'), 'Helps')) = '42501', 'a member cannot open the bot to groups');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.set_bot_availability(%L, %L, true, true)', pg_temp.i('helper'), 'bad' || chr(10) || 'line')) = '22023', 'a description has no line breaks');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.set_bot_availability(%L, %L, true, true)', pg_temp.i('helper'), repeat('x', 201))) = '22023', 'or more than 200 letters');
  p := pg_temp.as_json('ada', format('select public.set_bot_availability(%L, %L, true, true)', pg_temp.i('helper'), 'Helps with plans'));
  perform pg_temp.expect(p->>'allow_direct' = 'true' and p->>'allow_groups' = 'true' and p->>'description' = 'Helps with plans', 'a manager opens the bot to direct chats and groups');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where action = 'bot_open_update') = 1, 'in the circle log');

  perform pg_temp.expect(pg_temp.as_state('bob', format('select public.add_bot_to_group(%L, %L)', pg_temp.i('plan'), pg_temp.i('helper_user'))) = '42501', 'only the group owner adds a bot');
  perform pg_temp.expect(pg_temp.as_state('eve', format('select public.add_bot_to_group(%L, %L)', pg_temp.i('plan'), pg_temp.i('helper_user'))) = '42501', 'not an outsider either');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.add_bot_to_group(%L, %L)', pg_temp.i('plan'), pg_temp.i('bob'))) = '42501', 'a person is not a bot');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.add_bot_to_group(%L, %L)', pg_temp.i('plaza_conv'), pg_temp.i('helper_user'))) = '42501', 'a channel is not a group');
  perform pg_temp.expect(pg_temp.as_state('anon', format('select public.add_bot_to_group(%L, %L)', pg_temp.i('plan'), pg_temp.i('helper_user'))) in ('42501', '42883'), 'nobody signed in cannot');
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('ada'), pg_temp.i('helper_user'));
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.add_bot_to_group(%L, %L)', pg_temp.i('plan'), pg_temp.i('helper_user'))) = '42501', 'a bot the owner blocked is refused');
  delete from public.blocks where blocker_id = pg_temp.i('ada');

  -- Before the bot joins: a message it must not read afterwards.
  m := pg_temp.say('bob', 'plan', 'said before the bot came');
  update public.messages set created_at = now() - interval '2 hours' where id = m;

  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.add_bot_to_group(%L, %L)', pg_temp.i('plan'), pg_temp.i('helper_user'))) = 'ok', 'the owner adds the bot');
  perform pg_temp.expect(exists (select 1 from public.conversation_members where conversation_id = pg_temp.i('plan') and user_id = pg_temp.i('helper_user')), 'it is a member of the group');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.add_bot_to_group(%L, %L)', pg_temp.i('plan'), pg_temp.i('helper_user'))) = 'ok' and (select count(*) from public.conversation_members where conversation_id = pg_temp.i('plan') and user_id = pg_temp.i('helper_user')) = 1, 'adding twice changes nothing');
  perform pg_temp.expect(pg_temp.as_json('bob', format('select public.list_group_bots(%L)', pg_temp.i('plan'))) @> jsonb_build_array(jsonb_build_object('name', 'Helper')), 'every member sees which bots are in the group');
  perform pg_temp.expect(pg_temp.as_state('eve', format('select public.list_group_bots(%L)', pg_temp.i('plan'))) = '42501', 'an outsider does not');

  -- Now the bot hears the group.
  perform pg_temp.clear_q();
  perform pg_temp.say('bob', 'plan', 'the plan is to hike');
  perform pg_temp.expect(pg_temp.evn('helper', 'message.created') = 1, 'a group with the bot in it is queued for it');
  p := pg_temp.last_ev('helper', 'message.created');
  perform pg_temp.expect(p->'chat'->>'kind' = 'group' and p->'chat'->>'name' = 'Plan' and not p->'chat' ? 'circle_id' and p->'message'->>'content' = 'the plan is to hike', 'as a group, with its words');

  -- Closing the door at once.
  perform pg_temp.clear_q();
  update public.circle_bots set allow_groups = false where id = pg_temp.i('helper');
  perform pg_temp.say('bob', 'plan', 'after the door closed');
  perform pg_temp.expect(pg_temp.evn('helper') = 0, 'turning groups off stops the events at once');
  update public.circle_bots set allow_groups = true where id = pg_temp.i('helper');

  -- A group member joining or leaving.
  perform pg_temp.clear_q();
  insert into public.conversation_members (conversation_id, user_id, role) values (pg_temp.i('plan'), pg_temp.i('fay'), 'member');
  perform pg_temp.expect(pg_temp.evn('helper', 'member.joined') = 1 and pg_temp.last_ev('helper', 'member.joined')->'user'->>'username' = 'fay_i2' and pg_temp.last_ev('helper', 'member.joined')->'chat'->>'kind' = 'group', 'someone joining the group is queued');
  delete from public.conversation_members where conversation_id = pg_temp.i('plan') and user_id = pg_temp.i('fay');
  perform pg_temp.expect(pg_temp.evn('helper', 'member.left') = 1, 'and leaving');

  -- What is held back: a restricted chat (G6).
  perform pg_temp.clear_q();
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_chat_restrict_sharing(pg_temp.i('plan'), true);
  perform pg_temp.root();
  perform pg_temp.say('bob', 'plan', 'a restricted secret');
  p := pg_temp.last_ev('helper', 'message.created');
  perform pg_temp.expect(p->'message'->>'content_withheld' = 'restricted' and not p->'message' ? 'content', 'in a restricted chat the words are held back');
  perform pg_temp.expect(p::text not like '%restricted secret%', 'they are nowhere in the event');
  perform pg_temp.expect(p->'message'->'author'->>'username' = 'bob_i2' and p->'message'->>'type' = 'text', 'only that it happened');
  perform pg_temp.clear_q();
  perform pg_temp.say('bob', 'plan', 'another one', 'helper_user');
  perform pg_temp.expect(pg_temp.last_ev('helper', 'message.mentioned')->'message'->>'content_withheld' = 'restricted', 'a mention is held back too');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.set_bot_availability(%L, %L, true, true)', pg_temp.i('helper'), 'Helps with plans')) = 'ok', 'a manager can still change the settings');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_chat_restrict_sharing(pg_temp.i('plan'), false);
  perform pg_temp.root();

  -- A chat a member locked (G2).
  perform pg_temp.clear_q();
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.set_conversation_locked(pg_temp.i('plan'), true);
  perform pg_temp.root();
  perform pg_temp.say('bob', 'plan', 'a locked secret');
  p := pg_temp.last_ev('helper', 'message.created');
  perform pg_temp.expect(p->'message'->>'content_withheld' = 'locked' and p::text not like '%locked secret%', 'in a chat a member locked, the words are held back');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.set_conversation_locked(pg_temp.i('plan'), false);
  perform pg_temp.root();
  perform pg_temp.clear_q();
  perform pg_temp.say('bob', 'plan', 'an open plan');
  perform pg_temp.expect(pg_temp.last_ev('helper', 'message.created')->'message'->>'content' = 'an open plan', 'unlocking brings the words back');

  -- A disappearing message and a view-once picture.
  perform pg_temp.clear_q();
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_disappearing_messages(pg_temp.i('plan'), 86400);
  perform pg_temp.root();
  perform pg_temp.clear_q();
  perform pg_temp.say('bob', 'plan', 'this will vanish');
  p := pg_temp.last_ev('helper', 'message.created');
  perform pg_temp.expect(p->'message'->>'content_withheld' = 'disappearing' and p::text not like '%vanish%', 'a disappearing message is held back');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_disappearing_messages(pg_temp.i('plan'), null);
  perform pg_temp.root();
  perform pg_temp.clear_q();
  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (pg_temp.i('plan'), pg_temp.i('bob'), 'image', 'look once', '{"kind":"image","bucket":"chat-images","path":"x/y.jpg","name":"y.jpg","view_once":"true"}');
  p := pg_temp.last_ev('helper', 'message.created');
  perform pg_temp.expect(p->'message'->>'content_withheld' = 'view_once' and p::text not like '%look once%' and p::text not like '%y.jpg%', 'and so is a view-once picture');

  -- A restricted group cannot take a bot.
  perform pg_temp.act(pg_temp.i('ada'));
  insert into pg_temp.ids select 'plan2', public.create_group_conversation('Plan two', array[pg_temp.i('bob'), pg_temp.i('cat')]);
  perform public.set_chat_restrict_sharing(pg_temp.i('plan2'), true);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.add_bot_to_group(%L, %L)', pg_temp.i('plan2'), pg_temp.i('helper_user'))) = '22023', 'a restricted group cannot take a bot');
end $$;

-- ===================================== 4. limits
do $$
declare
  dropped_before integer;
begin
  perform pg_temp.clear_q();
  update public.bot_event_subscriptions set window_start = now(), window_count = 298, dropped_count = 0 where bot_id = pg_temp.i('helper');
  perform pg_temp.say('bob', 'plaza_conv', 'one');
  perform pg_temp.say('bob', 'plaza_conv', 'two');
  perform pg_temp.say('bob', 'plaza_conv', 'three');
  perform pg_temp.say('bob', 'plaza_conv', 'four');
  perform pg_temp.expect(pg_temp.evn('helper', 'message.created') = 2, 'a bot gets at most 300 events a minute');
  perform pg_temp.expect((select dropped_count from public.bot_event_subscriptions where bot_id = pg_temp.i('helper')) = 2, 'the rest are counted');
  perform pg_temp.expect(public.bot_event_subscription_state(pg_temp.i('helper'))->>'dropped_count' = '2', 'and shown to the managers');
  perform pg_temp.expect(pg_temp.evn('other', 'message.created') = 4, 'one bot''s limit is not another''s');

  update public.bot_event_subscriptions set window_start = now() - interval '2 minutes' where bot_id = pg_temp.i('helper');
  perform pg_temp.say('bob', 'plaza_conv', 'five');
  perform pg_temp.expect(pg_temp.evn('helper', 'message.created') = 3, 'a new minute starts again');

  -- At most 1000 waiting.
  perform pg_temp.clear_q();
  insert into public.bot_event_deliveries (bot_id, event, payload)
  select pg_temp.i('helper'), 'message.created', '{}' from generate_series(1, 1000);
  update public.bot_event_subscriptions set window_start = null, window_count = 0, dropped_count = 0 where bot_id = pg_temp.i('helper');
  perform pg_temp.say('bob', 'plaza_conv', 'six');
  perform pg_temp.expect(pg_temp.evn('helper') = 1000, 'no more than 1000 wait for a bot');
  perform pg_temp.expect((select dropped_count from public.bot_event_subscriptions where bot_id = pg_temp.i('helper')) = 1, 'and the one over is counted');
  perform pg_temp.clear_q();
  update public.bot_event_subscriptions set window_start = null, window_count = 0, dropped_count = 0 where bot_id = pg_temp.i('helper');
end $$;

-- ===================================== 5. the queue
do $$
declare
  claimed jsonb;
  item jsonb;
  first_id uuid;
  second_id uuid;
  sub_secret text;
  step integer;
  expected interval[] := array[interval '5 seconds', interval '30 seconds', interval '2 minutes', interval '10 minutes', interval '1 hour'];
begin
  delete from public.bot_event_subscriptions where bot_id = pg_temp.i('other');
  perform pg_temp.clear_q();
  select secret into sub_secret from public.bot_event_subscriptions where bot_id = pg_temp.i('helper');

  perform pg_temp.say('bob', 'plaza_conv', 'queued one');
  perform pg_temp.say('bob', 'plaza_conv', 'queued two');
  select id into first_id from public.bot_event_deliveries where payload->'message'->>'content' = 'queued one';
  select id into second_id from public.bot_event_deliveries where id <> first_id;
  update public.bot_event_deliveries set created_at = now() - interval '1 minute' where id = first_id;

  perform pg_temp.expect(pg_temp.as_state('bob', 'select public.claim_bot_events(20)') = '42501', 'a client cannot claim deliveries');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.finish_bot_event(%L, true)', first_id)) = '42501', 'or finish them');
  claimed := public.claim_bot_events(20);
  perform pg_temp.expect(jsonb_array_length(claimed) = 2, 'the function claims what is due');
  select e into item from jsonb_array_elements(claimed) e where e->>'delivery_id' = first_id::text;
  perform pg_temp.expect(item->>'url' = 'https://example.com/events' and item->>'secret' = sub_secret and item->>'event' = 'message.created' and (item->>'attempt')::int = 1, 'with the address, the secret, the kind and the attempt');
  perform pg_temp.expect(item->>'circle_id' = pg_temp.i('club')::text and item->'data'->'message'->>'content' = 'queued one' and item->>'bot_id' = pg_temp.i('helper')::text, 'the circle and the data');
  perform pg_temp.expect((select state = 'sending' and attempts = 1 and next_attempt_at > now() from public.bot_event_deliveries where id = first_id), 'a claim is a lease');
  perform pg_temp.expect(jsonb_array_length(public.claim_bot_events(20)) = 0, 'nothing is handed out twice');

  perform public.finish_bot_event(first_id, true, 200, null);
  perform pg_temp.expect((select state = 'delivered' and delivered_at is not null and last_status = 200 and last_error is null from public.bot_event_deliveries where id = first_id), 'a delivery is recorded');
  perform pg_temp.expect((select last_success_at is not null and consecutive_failures = 0 and last_error is null from public.bot_event_subscriptions where bot_id = pg_temp.i('helper')), 'and shown on the subscription');
  perform public.finish_bot_event(first_id, false, 500, 'late');
  perform pg_temp.expect((select state from public.bot_event_deliveries where id = first_id) = 'delivered', 'a finished delivery is not changed again');

  -- Retries: 5 seconds, 30 seconds, 2 minutes, 10 minutes, an hour, then failed.
  for step in 1..5 loop
    perform public.finish_bot_event(second_id, false, 503, 'http_503');
    perform pg_temp.expect((select state = 'queued' and attempts = step and next_attempt_at = now() + expected[step] and last_status = 503 and last_error = 'http_503' from public.bot_event_deliveries where id = second_id), 'try ' || step || ' failed: tried again after ' || expected[step]);
    perform pg_temp.expect(jsonb_array_length(public.claim_bot_events(20)) = 0, 'not before it is due (' || step || ')');
    update public.bot_event_deliveries set next_attempt_at = now() where id = second_id;
    claimed := public.claim_bot_events(20);
    perform pg_temp.expect(jsonb_array_length(claimed) = 1 and (claimed->0->>'attempt')::int = step + 1, 'and then it comes again as try ' || (step + 1));
  end loop;
  perform public.finish_bot_event(second_id, false, 503, 'http_503');
  perform pg_temp.expect((select state = 'failed' and attempts = 6 from public.bot_event_deliveries where id = second_id), 'six tries and it has failed');
  perform pg_temp.expect((select consecutive_failures = 1 and last_failure_at is not null from public.bot_event_subscriptions where bot_id = pg_temp.i('helper')), 'which counts against the subscription');
  perform pg_temp.expect(jsonb_array_length(public.claim_bot_events(20)) = 0, 'and it is not claimed again');

  -- 20 failures in a row pause the subscription; saving it again turns it on.
  update public.bot_event_subscriptions set consecutive_failures = 19 where bot_id = pg_temp.i('helper');
  insert into public.bot_event_deliveries (bot_id, event, payload, state, attempts) values (pg_temp.i('helper'), 'message.created', '{}', 'sending', 6) returning id into first_id;
  perform public.finish_bot_event(first_id, false, 500, 'x');
  perform pg_temp.expect((select not enabled and consecutive_failures = 20 from public.bot_event_subscriptions where bot_id = pg_temp.i('helper')), 'twenty lost in a row pause the subscription');
  perform pg_temp.clear_q();
  perform pg_temp.say('bob', 'plaza_conv', 'while paused');
  perform pg_temp.expect(pg_temp.evn('helper') = 0, 'a paused subscription queues nothing');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.send_bot_test_event(%L)', pg_temp.i('helper'))) = '22023', 'and takes no test');
  perform pg_temp.expect((pg_temp.as_json('ada', format('select public.get_bot_event_subscription(%L)', pg_temp.i('helper'))))->>'enabled' = 'false', 'the manager sees it is paused');
  perform pg_temp.sub('ada', 'helper', 'https://example.com/events', public.bot_event_types());
  perform pg_temp.expect((select enabled and consecutive_failures = 0 from public.bot_event_subscriptions where bot_id = pg_temp.i('helper')), 'saving the address again turns it on');
  perform pg_temp.expect((select secret from public.bot_event_subscriptions where bot_id = pg_temp.i('helper')) = sub_secret, 'with the same secret');

  -- Queued while the subscription was on, claimed after it went off.
  perform pg_temp.clear_q();
  perform pg_temp.say('bob', 'plaza_conv', 'then switched off');
  update public.bot_event_subscriptions set enabled = false where bot_id = pg_temp.i('helper');
  claimed := public.claim_bot_events(20);
  perform pg_temp.expect(jsonb_array_length(claimed) = 0 and (select state = 'dropped' from public.bot_event_deliveries limit 1), 'what waits for a subscription that went off is dropped');
  update public.bot_event_subscriptions set enabled = true where bot_id = pg_temp.i('helper');

  -- A revoked token ends delivery.
  perform pg_temp.clear_q();
  perform pg_temp.say('bob', 'plaza_conv', 'then revoked');
  update public.circle_bots set token_hash = null where id = pg_temp.i('helper');
  claimed := public.claim_bot_events(20);
  perform pg_temp.expect(jsonb_array_length(claimed) = 0 and (select state = 'dropped' from public.bot_event_deliveries limit 1), 'a revoked token ends delivery');
  update public.circle_bots set token_hash = public.webhook_token_hash(pg_temp.tok('helper')) where id = pg_temp.i('helper');

  -- The owner of the subscription lost the right to manage the circle.
  perform pg_temp.clear_q();
  perform pg_temp.say('bob', 'plaza_conv', 'owner will be gone');
  update public.bot_event_subscriptions set owner_id = pg_temp.i('bob') where bot_id = pg_temp.i('helper');
  perform pg_temp.expect(jsonb_array_length(public.claim_bot_events(20)) = 0, 'a subscription whose owner does not manage the circle sends nothing');
  perform pg_temp.expect((select not enabled and last_error = 'owner_lost_access' from public.bot_event_subscriptions where bot_id = pg_temp.i('helper')), 'it is paused, with the reason');
  perform pg_temp.sub('ada', 'helper', 'https://example.com/events', public.bot_event_types());
  perform pg_temp.expect((select enabled and owner_id = pg_temp.i('ada') from public.bot_event_subscriptions where bot_id = pg_temp.i('helper')), 'a manager saving it again takes it over');

  -- Too old.
  perform pg_temp.clear_q();
  insert into public.bot_event_deliveries (bot_id, event, payload, conversation_id, created_at) values (pg_temp.i('helper'), 'message.created', '{}', pg_temp.i('plaza_conv'), now() - interval '7 hours');
  claimed := public.claim_bot_events(20);
  perform pg_temp.expect(jsonb_array_length(claimed) = 0 and (select state = 'dropped' and last_error = 'expired' from public.bot_event_deliveries limit 1), 'an event older than 6 hours is dropped, not sent late');

  -- The place closed to the bot after the event: checked again before sending.
  perform pg_temp.clear_q();
  perform pg_temp.say('bob', 'plan', 'before the bot is removed');
  perform pg_temp.expect(pg_temp.evn('helper', 'message.created') = 1, 'a group event is waiting (setup)');
  perform pg_temp.expect(pg_temp.as_state('bob', format('select public.remove_bot_from_group(%L, %L)', pg_temp.i('plan'), pg_temp.i('helper_user'))) = '42501', 'only the owner removes a bot');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.remove_bot_from_group(%L, %L)', pg_temp.i('plan'), pg_temp.i('bob'))) = '22023', 'and only a bot');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.remove_bot_from_group(%L, %L)', pg_temp.i('plan'), pg_temp.i('helper_user'))) = 'ok', 'the owner removes the bot');
  perform pg_temp.expect(not exists (select 1 from public.conversation_members where conversation_id = pg_temp.i('plan') and user_id = pg_temp.i('helper_user')), 'it is out of the group');
  claimed := public.claim_bot_events(20);
  perform pg_temp.expect(jsonb_array_length(claimed) = 0 and (select state = 'dropped' and last_error = 'no_access' from public.bot_event_deliveries limit 1), 'what was waiting for the group is dropped');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.add_bot_to_group(%L, %L)', pg_temp.i('plan'), pg_temp.i('helper_user'))) = 'ok', 'and it can be put back');

  perform pg_temp.clear_q();
  perform pg_temp.say('bob', 'plaza_conv', 'a private channel closes');
  update public.circle_channel_overwrites set allow = 0 where channel_id = pg_temp.i('vault') and user_id = pg_temp.i('helper_user');
  perform pg_temp.say('ada', 'vault_conv', 'managers');
  perform pg_temp.expect(pg_temp.evn('helper') = 1, 'a bot that cannot view a channel is queued nothing from it');
  insert into public.bot_event_deliveries (bot_id, event, payload, conversation_id) values (pg_temp.i('helper'), 'message.created', '{}', pg_temp.i('vault_conv'));
  perform pg_temp.expect(jsonb_array_length(public.claim_bot_events(20)) = 1, 'the channel it can still view is sent, the one it cannot is dropped');
  perform pg_temp.expect((select state from public.bot_event_deliveries where conversation_id = pg_temp.i('vault_conv')) = 'dropped', 'dropped (vault)');
  update public.circle_channel_overwrites set allow = public.circle_permission_bit('view_channel') | public.circle_permission_bit('send_messages') where channel_id = pg_temp.i('vault') and user_id = pg_temp.i('helper_user');

  -- A suspended circle: events about the circle (nobody's chat) are dropped too.
  perform pg_temp.clear_q();
  insert into public.circle_members (circle_id, user_id, role, rules_accepted_at) values (pg_temp.i('club'), pg_temp.i('eve'), 'member', now());
  perform pg_temp.expect(pg_temp.evn('helper', 'member.joined') = 1, 'a circle event is waiting (setup)');
  update public.circles set disabled_at = now(), disabled_mode = 'suspend' where id = pg_temp.i('club');
  perform pg_temp.expect(jsonb_array_length(public.claim_bot_events(20)) = 0, 'a suspended circle sends nothing already queued');
  update public.circles set disabled_at = null, disabled_mode = null where id = pg_temp.i('club');
  delete from public.circle_members where circle_id = pg_temp.i('club') and user_id = pg_temp.i('eve');
  perform pg_temp.clear_q();
end $$;

-- ===================================== 6. test event, deliveries, clean-up
do $$
declare
  ping uuid;
  list jsonb;
  claimed jsonb;
  woke integer;
begin
  perform pg_temp.clear_q();
  perform pg_temp.expect(pg_temp.as_state('eve', format('select public.send_bot_test_event(%L)', pg_temp.i('helper'))) = '42501', 'an outsider cannot send a test');
  ping := pg_temp.as_json('ada', format('select to_jsonb(public.send_bot_test_event(%L))', pg_temp.i('helper')))#>>'{}';
  perform pg_temp.expect(ping is not null, 'a manager sends a test event');
  perform pg_temp.expect((select event = 'ping' and state = 'queued' and payload->>'message' like 'This is a test%' and actor_id = pg_temp.i('ada') from public.bot_event_deliveries where id = ping), 'it is queued like any other');
  claimed := public.claim_bot_events(20);
  perform pg_temp.expect(jsonb_array_length(claimed) = 1 and claimed->0->>'event' = 'ping' and claimed->0->'data'->'bot'->>'name' = 'Helper', 'and handed to the function with the bot''s name');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.send_bot_test_event(%L)', pg_temp.i('helper'))) = 'ok', 'a few tests are fine');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.send_bot_test_event(%L)', pg_temp.i('helper'))) = 'ok', '...');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.send_bot_test_event(%L)', pg_temp.i('helper'))) = 'ok', '....');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.send_bot_test_event(%L)', pg_temp.i('helper'))) = 'ok', '.....');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.send_bot_test_event(%L)', pg_temp.i('helper'))) = 'BT429', 'but not more than 5 a minute');

  list := pg_temp.as_json('ada', format('select public.list_bot_event_deliveries(%L, 3)', pg_temp.i('helper')));
  perform pg_temp.expect(jsonb_array_length(list) = 3, 'the managers read the latest deliveries');
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(list) e where e ? 'payload' or e ? 'data' or e::text like '%This is a test%'), 'without what was in them');
  perform pg_temp.expect(list->0 ? 'state' and list->0 ? 'attempts' and list->0 ? 'event' and list->0 ? 'created_at', 'only whether it arrived');
  perform pg_temp.expect(jsonb_array_length(pg_temp.as_json('ada', format('select public.list_bot_event_deliveries(%L, 1000)', pg_temp.i('helper')))) = 5, 'at most 100 are listed (5 here)');

  -- Wakes only when something is due.
  select count(*) into woke from net.http_request_queue where url like '%/bot-events';
  perform public.wake_bot_events_if_due();
  perform pg_temp.expect((select count(*) from net.http_request_queue where url like '%/bot-events') > woke, 'a due delivery wakes the function (retry cron)');
  perform pg_temp.clear_q();
  select count(*) into woke from net.http_request_queue where url like '%/bot-events';
  perform public.wake_bot_events_if_due();
  perform pg_temp.expect((select count(*) from net.http_request_queue where url like '%/bot-events') = woke, 'and nothing is sent when nothing is');

  -- Clean-up after 7 days.
  insert into public.bot_event_deliveries (bot_id, event, payload, created_at) values (pg_temp.i('helper'), 'ping', '{}', now() - interval '8 days'), (pg_temp.i('helper'), 'ping', '{}', now() - interval '6 days');
  perform public.purge_bot_events();
  perform pg_temp.expect((select count(*) from public.bot_event_deliveries) = 1, 'deliveries older than 7 days are removed');

  perform pg_temp.expect(pg_temp.as_state('bob', 'select public.purge_bot_events()') = '42501' and pg_temp.as_state('bob', 'select public.wake_bot_events()') = '42501', 'clients cannot run the clean-up or the wake-up');
  perform pg_temp.clear_q();
end $$;
select pg_temp.sub('ada', 'other', 'https://example.org/events', array['message.created', 'message.mentioned']);

-- ===================================== 7. bot API 2.0: who the bot is, where it can go
do $$
declare
  me jsonb;
  chats jsonb;
  tok text := pg_temp.tok('helper');
  n integer;
begin
  me := public.bot_api_me(tok);
  perform pg_temp.expect(me->>'name' = 'Helper' and me->>'username' is not null and me->>'description' = 'Helps with plans' and (me->>'allow_direct')::boolean and (me->>'allow_groups')::boolean, 'the bot sees its name, username, description and what it is open to');
  perform pg_temp.expect(me->>'circle_name' = 'Hike Club' and me->>'user_id' = pg_temp.i('helper_user')::text, 'and what it saw before');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_me(%L)', 'nope')) = '28000' and pg_temp.state(format('select public.bot_api_me(%L)', repeat('z', 43))) = '28000', 'a wrong token is refused');
  perform pg_temp.expect(pg_temp.as_state('bob', format('select public.bot_api_me(%L)', tok)) = '42501' and pg_temp.as_state('anon', format('select public.bot_api_me(%L)', tok)) = '42501', 'and clients cannot call the bot functions at all');

  chats := public.bot_api_list_channels(tok);
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(chats) e where e->>'name' = 'plaza' and e->>'chat_id' = pg_temp.i('plaza_conv')::text and e->>'id' = pg_temp.i('plaza')::text), 'the channel list names the chat of each channel');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(chats) e where e->>'name' = 'vault' and e->>'chat_id' = pg_temp.i('vault_conv')::text), 'including the private one it was let into');

  chats := public.bot_api_list_chats(tok);
  perform pg_temp.expect(jsonb_array_length(chats) = 1 and chats->0->>'id' = pg_temp.i('plan')::text and chats->0->>'kind' = 'group' and chats->0->>'name' = 'Plan', 'the chat list holds the groups and direct chats the bot is in');
  perform pg_temp.expect((chats->0->>'member_count')::int = 4 and (chats->0->>'restricted')::boolean = false, 'with the size and whether it is restricted');
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(chats) e where e->>'id' in (pg_temp.i('plaza_conv')::text, pg_temp.i('vault_conv')::text)), 'channels are listed as channels, not as chats');

  -- The same group for a bot that is not in it.
  perform pg_temp.expect(public.bot_api_list_chats(pg_temp.tok('other')) = '[]'::jsonb, 'a bot sees only the chats it is in');
end $$;

-- ===================================== 8. reading a chat
do $$
declare
  tok text := pg_temp.tok('helper');
  list jsonb;
  m uuid;
  secret_msg uuid;
begin
  perform pg_temp.clear_q();
  delete from public.bot_rate;
  perform pg_temp.say('bob', 'plan', 'plain words');
  perform pg_temp.say('cat', 'plan', 'cat says hi');
  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (pg_temp.i('plan'), pg_temp.i('bob'), 'image', 'one look', '{"kind":"image","bucket":"chat-images","path":"a/b.jpg","name":"b.jpg","view_once":"true"}')
  returning id into secret_msg;

  list := public.bot_api_list_chat_messages(tok, pg_temp.i('plan'));
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(list) e where e->>'content' = 'plain words'), 'the bot reads what is said in a group');
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(list) e where e->>'content' = 'said before the bot came'), 'but only what was said after it joined');
  perform pg_temp.expect(list->0->>'created_at' >= list->1->>'created_at', 'newest first');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(list) e where e->>'id' = secret_msg::text and e->>'content_withheld' = 'view_once' and not e ? 'content' and e::text not like '%b.jpg%'), 'a view-once picture is named, never given');
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(list) e where e->'author' ? 'email' or e->'author' ? 'bio'), 'authors carry no e-mail or bio');
  perform pg_temp.expect(jsonb_array_length(public.bot_api_list_chat_messages(tok, pg_temp.i('plan'), 2)) = 2, 'the count is respected');
  perform pg_temp.expect(jsonb_array_length(public.bot_api_list_chat_messages(tok, pg_temp.i('plan'), 100000)) <= 100, 'and capped');
  perform pg_temp.expect(jsonb_array_length(public.bot_api_list_chat_messages(tok, pg_temp.i('plan'), 50, now() - interval '1 year')) = 0, 'a time limit pages backwards');

  -- Held back in a restricted chat.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_chat_restrict_sharing(pg_temp.i('plan'), true);
  perform pg_temp.root();
  list := public.bot_api_list_chat_messages(tok, pg_temp.i('plan'));
  perform pg_temp.expect(jsonb_array_length(list) > 0 and not exists (select 1 from jsonb_array_elements(list) e where e ? 'content') and not exists (select 1 from jsonb_array_elements(list) e where e->>'content_withheld' is distinct from 'restricted'), 'in a restricted chat no message gives its words');
  perform pg_temp.expect(list::text not like '%plain words%' and list::text not like '%cat says hi%', 'they are nowhere in the answer');
  perform pg_temp.expect((public.bot_api_list_chats(tok)->0->>'restricted')::boolean, 'the chat list says it is restricted');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_chat_restrict_sharing(pg_temp.i('plan'), false);
  perform pg_temp.root();

  -- Held back in a locked chat.
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.set_conversation_locked(pg_temp.i('plan'), true);
  perform pg_temp.root();
  list := public.bot_api_list_chat_messages(tok, pg_temp.i('plan'));
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(list) e where e ? 'content') and list::text not like '%plain words%', 'a chat a member locked gives no words either');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.set_conversation_locked(pg_temp.i('plan'), false);
  perform pg_temp.root();

  -- Someone who blocked the bot is left out.
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('bob'), pg_temp.i('helper_user'));
  list := public.bot_api_list_chat_messages(tok, pg_temp.i('plan'));
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(list) e where e->>'content' = 'cat says hi') and not exists (select 1 from jsonb_array_elements(list) e where e->'author'->>'username' = 'bob_i2'), 'what a person who blocked the bot said is left out');
  delete from public.blocks where blocker_id = pg_temp.i('bob');

  -- A message under review is not there.
  update public.messages set review_state = 'held' where id = secret_msg;
  list := public.bot_api_list_chat_messages(tok, pg_temp.i('plan'));
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(list) e where e->>'id' = secret_msg::text), 'a message under review is not there');
  update public.messages set review_state = null where id = secret_msg;

  -- Chats it may not read look like chats that are not there.
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_list_chat_messages(%L, %L)', tok, pg_temp.i('plan2'))) = 'P0002', 'a group the bot is not in is not found');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_list_chat_messages(%L, %L)', tok, gen_random_uuid())) = 'P0002', 'nor is a chat that does not exist');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_list_chat_messages(%L, %L)', pg_temp.tok('other'), pg_temp.i('plan'))) = 'P0002', 'nor is a group another bot is in');
  perform pg_temp.expect(jsonb_array_length(public.bot_api_list_chat_messages(tok, pg_temp.i('plaza_conv'))) > 0, 'a channel is read by its chat id');
  delete from public.circle_channel_overwrites where channel_id = pg_temp.i('vault') and user_id = pg_temp.i('other_user');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_list_chat_messages(%L, %L)', pg_temp.tok('other'), pg_temp.i('vault_conv'))) = 'P0002', 'a private channel the bot may not view is not found');
  insert into public.circle_channel_overwrites (circle_id, channel_id, user_id, allow)
  values (pg_temp.i('club'), pg_temp.i('vault'), pg_temp.i('other_user'), public.circle_permission_bit('view_channel') | public.circle_permission_bit('send_messages'));
  update public.circles set disabled_at = now(), disabled_mode = 'suspend' where id = pg_temp.i('club');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_list_chat_messages(%L, %L)', tok, pg_temp.i('plaza_conv'))) = 'P0002', 'a suspended circle is not found');
  update public.circles set disabled_at = null, disabled_mode = null where id = pg_temp.i('club');
  update public.circle_bots set allow_groups = false where id = pg_temp.i('helper');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_list_chat_messages(%L, %L)', tok, pg_temp.i('plan'))) = 'P0002' and public.bot_api_list_chats(tok) = '[]'::jsonb, 'closing the bot to groups closes the group at once');
  update public.circle_bots set allow_groups = true where id = pg_temp.i('helper');
end $$;

-- ===================================== 9. writing
do $$
declare
  tok text := pg_temp.tok('helper');
  m uuid;
  reply_target uuid;
  other_chat_msg uuid;
  r uuid;
  n integer;
  hit text;
begin
  delete from public.bot_rate;
  perform pg_temp.clear_q();

  -- Text, into a group.
  m := public.bot_api_send_chat_message(tok, pg_temp.i('plan'), '  hello from the bot ');
  perform pg_temp.expect(m is not null and (select sender_id = pg_temp.i('helper_user') and body = 'hello from the bot' and type = 'text' from public.messages where id = m), 'a bot says something in a group, as itself');
  perform pg_temp.expect(pg_temp.evn('helper') = 0, 'and is not told about it');
  insert into pg_temp.ids values ('botmsg', m);

  select id into reply_target from public.messages where conversation_id = pg_temp.i('plan') and body = 'plain words';
  r := public.bot_api_send_chat_message(tok, pg_temp.i('plan'), 'a reply', reply_target);
  perform pg_temp.expect((select reply_to_message_id = reply_target and reply_preview->>'body' = 'plain words' from public.messages where id = r), 'with a reply and its preview');
  select id into other_chat_msg from public.messages where conversation_id = pg_temp.i('plaza_conv') limit 1;
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_chat_message(%L, %L, %L, %L)', tok, pg_temp.i('plan'), 'wrong reply', other_chat_msg)) = '22023', 'a reply to a message of another chat is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_chat_message(%L, %L, %L)', tok, pg_temp.i('plan'), '   ')) = '22023', 'an empty text is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_chat_message(%L, %L, %L)', tok, pg_temp.i('plan'), repeat('x', 2001))) = '22023', 'and a very long one');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_chat_message(%L, %L, %L)', tok, pg_temp.i('plan2'), 'hi')) = 'P0002', 'a group the bot is not in is not found');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_chat_message(%L, %L, %L)', 'bad', pg_temp.i('plan'), 'hi')) = '28000', 'a wrong token is refused');
  r := public.bot_api_send_chat_message(tok, pg_temp.i('plan'), 'with a button', null, '[[{"type":"button","id":"go","label":"Go"}]]');
  perform pg_temp.expect((select components->0->0->>'id' = 'go' from public.messages where id = r), 'components go along');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_chat_message(%L, %L, %L, null, %L::jsonb)', tok, pg_temp.i('plan'), 'bad button', '[[{"type":"button","id":"go"}]]')) = '22023', 'and are checked');
  r := public.bot_api_send_chat_message(tok, pg_temp.i('plaza_conv'), 'into a channel by chat id');
  perform pg_temp.expect(r is not null and (select conversation_id = pg_temp.i('plaza_conv') from public.messages where id = r), 'a channel takes a message by its chat id');
  r := public.bot_api_send_chat_message(tok, pg_temp.i('plaza_conv'), '@everyone read this');
  perform pg_temp.expect(not exists (select 1 from public.message_mentions where message_id = r and kind in ('everyone', 'here', 'role')), 'a bot cannot mention everyone (as a member without the right cannot)');

  -- Writes are limited like every bot write.
  delete from public.bot_rate;
  n := 0;
  loop
    n := n + 1;
    exit when n > 70 or pg_temp.state(format('select public.bot_api_send_chat_message(%L, %L, %L)', tok, pg_temp.i('plan'), 'spam ' || n)) = 'BT429';
  end loop;
  perform pg_temp.expect(n between 55 and 65, 'a bot writes at most 60 times a minute (stopped at ' || n || ')');
  delete from public.bot_rate;

  -- Polls.
  r := public.bot_api_create_poll(tok, pg_temp.i('plan'), 'Where to?', array['Lake', 'Ridge'], false, 24, false);
  perform pg_temp.expect(r is not null and (select type = 'poll' and sender_id = pg_temp.i('helper_user') from public.messages where id = r), 'a bot makes a poll');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_create_poll(%L, %L, %L, %L)', tok, pg_temp.i('plan'), 'One option?', array['Only'])) in ('22023', '23514'), 'a poll needs two options');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_create_poll(%L, %L, %L, %L)', tok, pg_temp.i('plan2'), 'Where?', array['A', 'B'])) = 'P0002', 'in a chat it can read');

  -- Threads.
  select id into other_chat_msg from public.messages where conversation_id = pg_temp.i('plaza_conv') and sender_id = pg_temp.i('bob') limit 1;
  insert into pg_temp.ids select 'thread', (public.bot_api_create_thread(tok, other_chat_msg, 'Discuss')->>'chat_id')::uuid;
  perform pg_temp.expect(exists (select 1 from public.conversation_threads where conversation_id = pg_temp.i('thread') and parent_conversation_id = pg_temp.i('plaza_conv')), 'a bot starts a thread from a message');
  perform pg_temp.expect(public.bot_api_create_thread(tok, other_chat_msg, 'Discuss')->>'chat_id' = pg_temp.i('thread')::text, 'asking again gives the same thread');
  r := public.bot_api_send_chat_message(tok, pg_temp.i('thread'), 'in the thread');
  perform pg_temp.expect(r is not null, 'and writes in it');
  perform pg_temp.expect(jsonb_array_length(public.bot_api_list_chat_messages(tok, pg_temp.i('thread'))) >= 1, 'and reads it');
  select id into other_chat_msg from public.messages where conversation_id = pg_temp.i('plan') and body = 'plain words';
  insert into pg_temp.ids select 'thread2', (public.bot_api_create_thread(tok, other_chat_msg, 'Plan talk')->>'chat_id')::uuid;
  perform pg_temp.expect(jsonb_array_length(public.bot_api_list_chat_messages(tok, pg_temp.i('thread2'))) >= 0, 'a thread of a group is open to it too');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_create_thread(%L, %L)', tok, gen_random_uuid())) = 'P0002', 'a thread from a message that is not there is not found');
  update public.circle_bots set allow_groups = false where id = pg_temp.i('helper');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_list_chat_messages(%L, %L)', tok, pg_temp.i('thread2'))) = 'P0002', 'closing groups closes their threads');
  update public.circle_bots set allow_groups = true where id = pg_temp.i('helper');

  -- Editing and deleting its own messages.
  perform pg_temp.expect(public.bot_api_edit_message(tok, pg_temp.i('botmsg'), 'edited by the bot'), 'a bot edits its own message in a group');
  perform pg_temp.expect((select body = 'edited by the bot' and edited_at is not null from public.messages where id = pg_temp.i('botmsg')), 'and the words change');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_edit_message(%L, %L, %L)', tok, reply_target, 'hijack')) = 'P0002', 'but not a person''s');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_edit_message(%L, %L, %L)', pg_temp.tok('other'), pg_temp.i('botmsg'), 'hijack')) = 'P0002', 'nor another bot''s');
  perform pg_temp.expect((select body from public.messages where id = reply_target) = 'plain words', 'nothing changed');

  perform pg_temp.expect(public.bot_api_delete_message(tok, pg_temp.i('botmsg')) = '[]'::jsonb, 'a bot deletes its own message');
  perform pg_temp.expect((select recalled_at is not null and body = '' from public.messages where id = pg_temp.i('botmsg')), 'it is gone for everyone');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_delete_message(%L, %L)', tok, reply_target)) = 'P0002', 'not a person''s message');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_delete_message(%L, %L)', pg_temp.tok('other'), r)) = 'P0002', 'nor another bot''s');
  perform pg_temp.expect((select recalled_at is null from public.messages where id = reply_target), 'which stays');

  -- Reactions.
  perform public.bot_api_add_reaction(tok, reply_target, '👍');
  perform pg_temp.expect(exists (select 1 from public.message_reactions where message_id = reply_target and user_id = pg_temp.i('helper_user') and emoji = '👍'), 'a bot reacts in a group');
  perform public.bot_api_add_reaction(tok, reply_target, '👍');
  perform pg_temp.expect((select count(*) from public.message_reactions where message_id = reply_target and user_id = pg_temp.i('helper_user')) = 1, 'reacting twice keeps one');
  perform public.bot_api_remove_reaction(tok, reply_target, '👍');
  perform pg_temp.expect(not exists (select 1 from public.message_reactions where message_id = reply_target and user_id = pg_temp.i('helper_user')), 'and takes it back');
  perform public.bot_api_remove_reaction(tok, reply_target, '👍');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_remove_reaction(%L, %L, %L)', tok, gen_random_uuid(), '👍')) = 'P0002', 'a message that is not there is not found');
  select id into other_chat_msg from public.messages where conversation_id = pg_temp.i('vault_conv') limit 1;
  update public.circle_channel_overwrites set allow = 0 where channel_id = pg_temp.i('vault') and user_id = pg_temp.i('helper_user');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_add_reaction(%L, %L, %L)', tok, other_chat_msg, '👍')) = 'P0002', 'a message in a channel the bot cannot view is not found');
  update public.circle_channel_overwrites set allow = public.circle_permission_bit('view_channel') | public.circle_permission_bit('send_messages') where channel_id = pg_temp.i('vault') and user_id = pg_temp.i('helper_user');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_add_reaction(%L, %L, %L)', tok, pg_temp.i('botmsg'), '👍')) = 'P0002', 'a deleted message takes no reaction');
end $$;

-- ===================================== 10. files
do $$
declare
  tok text := pg_temp.tok('helper');
  good text;
  m uuid;
begin
  delete from public.bot_rate;
  good := pg_temp.i('plan')::text || '/' || pg_temp.i('helper_user')::text || '/' || gen_random_uuid()::text || '-notes.txt';
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_file_message(%L, %L, %L, %L, 100, %L)', tok, pg_temp.i('plan'), good, 'notes.txt', 'text/plain')) = '22023', 'a file that was not stored is refused');
  insert into storage.objects (bucket_id, name) values ('chat-files', good);
  m := public.bot_api_send_file_message(tok, pg_temp.i('plan'), good, 'notes.txt', 100, 'text/plain', 'the notes');
  perform pg_temp.expect(m is not null and (select type = 'file' and body = 'the notes' and attachment->>'path' = good and attachment->>'name' = 'notes.txt' and (attachment->>'size')::int = 100 and attachment->>'mime_type' = 'text/plain' and sender_id = pg_temp.i('helper_user') from public.messages where id = m), 'a bot posts a file it stored in its own folder');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_file_message(%L, %L, %L, %L, 100, %L)', tok, pg_temp.i('plan'), good, 'notes.txt', 'text/plain')) = '23505', 'the same file cannot be posted twice');
  good := pg_temp.i('plan')::text || '/' || pg_temp.i('other_user')::text || '/' || gen_random_uuid()::text || '-x.txt';
  insert into storage.objects (bucket_id, name) values ('chat-files', good);
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_file_message(%L, %L, %L, %L, 100, %L)', tok, pg_temp.i('plan'), good, 'x.txt', 'text/plain')) = '22023', 'a path in another user''s folder is refused');
  good := pg_temp.i('plaza_conv')::text || '/' || pg_temp.i('helper_user')::text || '/' || gen_random_uuid()::text || '-y.txt';
  insert into storage.objects (bucket_id, name) values ('chat-files', good);
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_file_message(%L, %L, %L, %L, 100, %L)', tok, pg_temp.i('plan'), good, 'y.txt', 'text/plain')) = '22023', 'and so is a path of another chat');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_file_message(%L, %L, %L, %L, 100, %L)', tok, pg_temp.i('plan'), '../../etc/passwd', 'p', 'text/plain')) = '22023', 'and a path that walks away');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_file_message(%L, %L, %L, %L, 100, %L)', tok, pg_temp.i('plaza_conv'), good, 'y.txt', 'text/plain')) = 'ok', 'while the right path in a channel is fine');
  good := pg_temp.i('plan')::text || '/' || pg_temp.i('helper_user')::text || '/' || gen_random_uuid()::text || '-z.bin';
  insert into storage.objects (bucket_id, name) values ('chat-files', good);
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_file_message(%L, %L, %L, %L, 0, %L)', tok, pg_temp.i('plan'), good, 'z.bin', 'x/y')) = '22023', 'an empty file is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_file_message(%L, %L, %L, %L, 52428801, %L)', tok, pg_temp.i('plan'), good, 'z.bin', 'x/y')) = '22023', 'and one over 50 MB');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_file_message(%L, %L, %L, %L, 10, %L)', tok, pg_temp.i('plan'), good, 'a' || chr(10) || 'b', 'x/y')) = '22023', 'and a name with a line break');
  m := public.bot_api_send_file_message(tok, pg_temp.i('plan'), good, 'z.bin', 10, 'not a mime');
  perform pg_temp.expect((select attachment->>'mime_type' = 'application/octet-stream' from public.messages where id = m), 'an odd type becomes a plain download');
  good := pg_temp.i('plan2')::text || '/' || pg_temp.i('helper_user')::text || '/' || gen_random_uuid()::text || '-q.txt';
  insert into storage.objects (bucket_id, name) values ('chat-files', good);
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_file_message(%L, %L, %L, %L, 10, %L)', tok, pg_temp.i('plan2'), good, 'q.txt', 'text/plain')) = 'P0002', 'a chat the bot is not in is not found');
end $$;

-- ===================================== 11. who is in a chat
do $$
declare
  tok text := pg_temp.tok('helper');
  list jsonb;
  one jsonb;
begin
  delete from public.bot_rate;
  list := public.bot_api_list_members(tok, pg_temp.i('plan'));
  perform pg_temp.expect(jsonb_array_length(list) = 4, 'the members of a group are listed');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(list) e where e->>'username' = 'ada_i2' and e->>'role' = 'owner') and exists (select 1 from jsonb_array_elements(list) e where e->>'username' = 'bob_i2' and e->>'role' = 'member'), 'with their roles');
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(list) e, jsonb_object_keys(e) k where k not in ('id', 'username', 'name', 'is_bot', 'role')), 'and nothing but id, username, name, role and whether a bot');
  perform pg_temp.expect(list::text not like '%i2.test%', 'no e-mail');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(list) e where e->>'username' is not null and (e->>'is_bot')::boolean), 'the bot itself shows as a bot');
  perform pg_temp.expect(jsonb_array_length(public.bot_api_list_members(tok, pg_temp.i('plan'), 2)) = 2, 'a page is as long as asked');
  perform pg_temp.expect((select count(*) from jsonb_array_elements(public.bot_api_list_members(tok, pg_temp.i('plan'), 100, (list->0->>'id')::uuid))) = 3, 'and goes on after a person');

  list := public.bot_api_list_members(tok, pg_temp.i('plaza_conv'));
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(list) e where e->>'username' = 'bob_i2') and not exists (select 1 from jsonb_array_elements(list) e where e ? 'role'), 'a channel lists its members, with the name they go by in the circle');
  list := public.bot_api_list_members(tok, pg_temp.i('vault_conv'));
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(list) e where e->>'username' = 'bob_i2'), 'a private channel lists only those who can view it');

  one := public.bot_api_get_member(tok, pg_temp.i('plan'), pg_temp.i('ada'));
  perform pg_temp.expect(one->>'username' = 'ada_i2' and one->>'role' = 'owner', 'one member');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_get_member(%L, %L, %L)', tok, pg_temp.i('plan'), pg_temp.i('eve'))) = 'P0002', 'someone who is not in the chat is not found');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_get_member(%L, %L, %L)', tok, pg_temp.i('plan2'), pg_temp.i('ada'))) = 'P0002', 'nor in a chat the bot cannot read');

  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('bob'), pg_temp.i('helper_user'));
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(public.bot_api_list_members(tok, pg_temp.i('plan'))) e where e->>'username' = 'bob_i2') and pg_temp.state(format('select public.bot_api_get_member(%L, %L, %L)', tok, pg_temp.i('plan'), pg_temp.i('bob'))) = 'P0002', 'a person who blocked the bot is not listed');
  delete from public.blocks where blocker_id = pg_temp.i('bob');
  update public.profiles set deleted_at = now() where id = pg_temp.i('cat');
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(public.bot_api_list_members(tok, pg_temp.i('plan'))) e where e->>'username' = 'cat_i2'), 'nor is an account that was deleted');
  update public.profiles set deleted_at = null where id = pg_temp.i('cat');
end $$;

-- ===================================== 12. direct chats with a bot
do $$
declare
  tok text := pg_temp.tok('helper');
  dm uuid;
  dm2 uuid;
  list jsonb;
  m uuid;
  p jsonb;
begin
  delete from public.bot_rate;
  perform pg_temp.clear_q();

  -- Friends only, for people.
  perform pg_temp.expect(pg_temp.as_state('cat', format('select public.get_or_create_direct_conversation(%L)', pg_temp.i('dan'))) <> 'ok', 'people still need to be friends to chat (cat and dan are not)');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.get_or_create_direct_conversation(%L)', pg_temp.i('cat'))) = 'ok', 'and friends still can');
  perform pg_temp.expect(pg_temp.as_state('eve', format('select public.get_or_create_direct_conversation(%L)', pg_temp.i('cat'))) <> 'ok', 'a stranger still cannot');
  perform pg_temp.expect(pg_temp.as_state('eve', format('select public.get_or_create_direct_conversation(%L)', pg_temp.i('eve'))) <> 'ok', 'nor oneself');

  -- A bot that is closed to direct chats.
  update public.circle_bots set allow_direct = false where id = pg_temp.i('helper');
  perform pg_temp.expect(pg_temp.as_state('eve', format('select public.get_or_create_direct_conversation(%L)', pg_temp.i('helper_user'))) <> 'ok', 'a bot that is closed to direct chats takes none');
  perform pg_temp.expect(not public.bot_accepts_direct_chat(pg_temp.i('eve'), pg_temp.i('helper_user')), 'bot_accepts_direct_chat says so');
  update public.circle_bots set allow_direct = true where id = pg_temp.i('helper');
  perform pg_temp.expect(public.bot_accepts_direct_chat(pg_temp.i('eve'), pg_temp.i('helper_user')), 'and says yes once it is open');
  perform pg_temp.expect(not public.bot_accepts_direct_chat(pg_temp.i('eve'), pg_temp.i('bob')), 'never for a person');
  perform pg_temp.expect(not public.bot_accepts_direct_chat(pg_temp.i('other_user'), pg_temp.i('helper_user')), 'nor when the one asking is a bot');
  update public.circle_bots set token_hash = null where id = pg_temp.i('helper');
  perform pg_temp.expect(not public.bot_accepts_direct_chat(pg_temp.i('eve'), pg_temp.i('helper_user')), 'nor for a bot with no working token');
  update public.circle_bots set token_hash = public.webhook_token_hash(tok) where id = pg_temp.i('helper');
  update public.circles set disabled_at = now(), disabled_mode = 'suspend' where id = pg_temp.i('club');
  perform pg_temp.expect(not public.bot_accepts_direct_chat(pg_temp.i('eve'), pg_temp.i('helper_user')), 'nor in a suspended circle');
  update public.circles set disabled_at = null, disabled_mode = null where id = pg_temp.i('club');

  -- A stranger opens a chat with the open bot.
  perform pg_temp.act(pg_temp.i('eve'));
  dm := public.get_or_create_direct_conversation(pg_temp.i('helper_user'));
  perform pg_temp.root();
  insert into pg_temp.ids values ('dm_eve', dm);
  perform pg_temp.expect(dm is not null and (select count(*) = 2 from public.conversation_members where conversation_id = dm and user_id in (pg_temp.i('eve'), pg_temp.i('helper_user'))), 'a person who is not its friend can chat with an open bot');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(public.get_or_create_direct_conversation(pg_temp.i('helper_user')) = dm, 'opening it again gives the same chat');
  perform pg_temp.root();

  -- Blocked.
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('dan'), pg_temp.i('helper_user'));
  perform pg_temp.expect(pg_temp.as_state('dan', format('select public.get_or_create_direct_conversation(%L)', pg_temp.i('helper_user'))) <> 'ok', 'someone who blocked the bot cannot start a chat with it');
  delete from public.blocks where blocker_id = pg_temp.i('dan');

  -- The bot reads and writes there.
  list := public.bot_api_list_chats(tok);
  perform pg_temp.expect(jsonb_array_length(list) = 2 and exists (select 1 from jsonb_array_elements(list) e where e->>'id' = dm::text and e->>'kind' = 'direct' and e->'peer'->>'username' = 'eve_i2' and not e ? 'name'), 'the direct chat is in the bot''s chat list, with the person');
  perform pg_temp.say('eve', 'dm_eve', 'hi bot');
  perform pg_temp.expect(pg_temp.evn('helper', 'message.created') = 1, 'what the person says is an event');
  p := pg_temp.last_ev('helper', 'message.created');
  perform pg_temp.expect(p->'chat'->>'kind' = 'direct' and p->'message'->>'content' = 'hi bot' and not p->'chat' ? 'circle_id', 'in a direct chat');
  perform pg_temp.expect(public.bot_api_list_chat_messages(tok, dm)->0->>'content' = 'hi bot', 'and can be read');
  m := public.bot_api_send_chat_message(tok, dm, 'hello eve');
  perform pg_temp.expect(m is not null, 'the bot answers');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect((select count(*) from public.messages where conversation_id = dm and body = 'hello eve') = 1, 'and the person reads it');
  perform pg_temp.root();
  perform pg_temp.expect(jsonb_array_length(public.bot_api_list_members(tok, dm)) = 2, 'the chat has two members');

  -- Restricted (G6): the words are held back.
  perform pg_temp.clear_q();
  perform pg_temp.act(pg_temp.i('eve'));
  perform public.set_chat_restrict_sharing(dm, true);
  perform pg_temp.root();
  perform pg_temp.say('eve', 'dm_eve', 'a private secret');
  p := pg_temp.last_ev('helper', 'message.created');
  perform pg_temp.expect(p->'message'->>'content_withheld' = 'restricted' and p::text not like '%private secret%', 'a restricted direct chat gives no words');
  perform pg_temp.act(pg_temp.i('eve'));
  perform public.set_chat_restrict_sharing(dm, false);
  perform pg_temp.root();
end $$;

do $$
declare
  tok text := pg_temp.tok('helper');
  dm uuid := pg_temp.i('dm_eve');
begin
  delete from public.blocks where blocker_id = pg_temp.i('eve') and blocked_id = pg_temp.i('helper_user');
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('eve'), pg_temp.i('helper_user'));
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_chat_message(%L, %L, %L)', tok, dm, 'still there?')) = 'P0002', 'once the person blocks the bot it cannot write in that chat');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_list_chat_messages(%L, %L)', tok, dm)) = 'P0002', 'nor read it');
  delete from public.blocks where blocker_id = pg_temp.i('eve');

  -- Closing the door.
  perform pg_temp.clear_q();
  update public.circle_bots set allow_direct = false where id = pg_temp.i('helper');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_list_chat_messages(%L, %L)', tok, dm)) = 'P0002' and public.bot_api_list_chats(tok)->0->>'id' = pg_temp.i('plan')::text, 'turning direct chats off closes the chats at once');
  perform pg_temp.say('eve', 'dm_eve', 'anyone there');
  perform pg_temp.expect(pg_temp.evn('helper') = 0, 'and stops the events');
  update public.circle_bots set allow_direct = true where id = pg_temp.i('helper');
end $$;

-- ===================================== 13. finding a bot, and putting bots in groups
do $$
declare
  found jsonb;
  tok text := pg_temp.tok('helper');
  n integer;
  i integer;
  bot_user uuid;
  bot_id uuid;
begin
  delete from public.bot_rate;

  found := pg_temp.as_json('bob', format('select public.search_open_bots(%L)', 'help'));
  perform pg_temp.expect(jsonb_array_length(found) = 1 and found->0->>'name' = 'Helper' and found->0->>'description' = 'Helps with plans' and found->0->>'user_id' = pg_temp.i('helper_user')::text, 'people find a bot that is open to them by name');
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(found) e, jsonb_object_keys(e) k where k not in ('user_id', 'name', 'username', 'avatar_url', 'description', 'allow_direct', 'allow_groups')), 'with nothing about its circle, owner or token');
  perform pg_temp.expect(jsonb_array_length(pg_temp.as_json('eve', format('select public.search_open_bots(%L)', 'HELPER'))) = 1, 'in any case, for anybody signed in');
  perform pg_temp.expect(jsonb_array_length(pg_temp.as_json('eve', format('select public.search_open_bots(%L)', (select username from public.profiles where id = pg_temp.i('helper_user'))))) = 1, 'or by username');
  perform pg_temp.expect(pg_temp.as_json('bob', format('select public.search_open_bots(%L)', 'h')) = '[]'::jsonb, 'one letter finds nothing');
  perform pg_temp.expect(pg_temp.as_json('bob', format('select public.search_open_bots(%L)', '%%')) = '[]'::jsonb and pg_temp.as_json('bob', format('select public.search_open_bots(%L)', '__')) = '[]'::jsonb, 'wildcards are not wildcards');
  perform pg_temp.expect(pg_temp.as_json('bob', format('select public.search_open_bots(%L)', 'oth')) = '[]'::jsonb, 'a bot that is closed to both is not found');
  perform pg_temp.expect(pg_temp.as_state('anon', format('select public.search_open_bots(%L)', 'help')) = '42501', 'nobody signed in cannot search');
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('dan'), pg_temp.i('helper_user'));
  perform pg_temp.expect(pg_temp.as_json('dan', format('select public.search_open_bots(%L)', 'help')) = '[]'::jsonb, 'a bot the person blocked is not shown');
  delete from public.blocks where blocker_id = pg_temp.i('dan');
  update public.circle_bots set token_hash = null where id = pg_temp.i('helper');
  perform pg_temp.expect(pg_temp.as_json('bob', format('select public.search_open_bots(%L)', 'help')) = '[]'::jsonb, 'nor one with no token');
  update public.circle_bots set token_hash = public.webhook_token_hash(tok) where id = pg_temp.i('helper');
  update public.circles set disabled_at = now(), disabled_mode = 'suspend' where id = pg_temp.i('club');
  perform pg_temp.expect(pg_temp.as_json('bob', format('select public.search_open_bots(%L)', 'help')) = '[]'::jsonb, 'nor one of a suspended circle');
  update public.circles set disabled_at = null, disabled_mode = null where id = pg_temp.i('club');

  -- At most five bots in a group.
  perform pg_temp.act(pg_temp.i('ada'));
  for i in 1..4 loop
    bot_user := gen_random_uuid();
    perform pg_temp.root();
    insert into auth.users (instance_id, id, aud, role, raw_app_meta_data, raw_user_meta_data, banned_until, created_at, updated_at)
    values ('00000000-0000-0000-0000-000000000000', bot_user, 'authenticated', 'authenticated', '{"provider":"bot","providers":["bot"]}'::jsonb, '{"bot":true}'::jsonb, 'infinity', now(), now());
    perform pg_temp.act(pg_temp.i('ada'));
    bot_id := (public.create_circle_bot(pg_temp.i('club'), 'Extra ' || i, null, bot_user)->>'id')::uuid;
    perform pg_temp.root();
    update public.circle_bots set token_hash = public.webhook_token_hash(rpad('extra-' || i, 43, 'c')), allow_groups = true where id = bot_id;
    insert into pg_temp.ids values ('x' || i, bot_user);
  end loop;
  perform pg_temp.root();
  update public.circle_bots set allow_groups = true where id = pg_temp.i('other');

  for i in 1..3 loop
    perform pg_temp.expect(pg_temp.as_state('ada', format('select public.add_bot_to_group(%L, %L)', pg_temp.i('plan'), pg_temp.i('x' || i))) = 'ok', 'bot ' || (i + 1) || ' of 5 joins the group');
  end loop;
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.add_bot_to_group(%L, %L)', pg_temp.i('plan'), pg_temp.i('other_user'))) = 'ok', 'bot 5 of 5 joins');
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.add_bot_to_group(%L, %L)', pg_temp.i('plan'), pg_temp.i('x4'))) = '54000', 'a sixth bot is refused');
  perform pg_temp.expect(jsonb_array_length(pg_temp.as_json('bob', format('select public.list_group_bots(%L)', pg_temp.i('plan')))) = 5, 'the members see all five');
  for i in 1..3 loop
    perform pg_temp.as_state('ada', format('select public.remove_bot_from_group(%L, %L)', pg_temp.i('plan'), pg_temp.i('x' || i)));
  end loop;
  perform pg_temp.as_state('ada', format('select public.remove_bot_from_group(%L, %L)', pg_temp.i('plan'), pg_temp.i('other_user')));
  perform pg_temp.expect(jsonb_array_length(pg_temp.as_json('bob', format('select public.list_group_bots(%L)', pg_temp.i('plan')))) = 1, 'and removing them leaves the first');
  update public.circle_bots set allow_groups = false where id = pg_temp.i('other');
end $$;

-- ===================================== 14. the call log and the developer page
do $$
declare
  tok text := pg_temp.tok('helper');
  list jsonb;
  mine jsonb;
  n integer;
begin
  delete from public.bot_api_calls;
  perform public.bot_api_log_call(tok, 'get', '/chats/{id}/messages', 200);
  perform public.bot_api_log_call(tok, 'POST', '/chats/{id}/messages', 429);
  perform public.bot_api_log_call(tok, 'GET', repeat('x', 200), 99999);
  perform public.bot_api_log_call(rpad('unknown-', 43, 'z'), 'GET', '/me', 200);
  perform public.bot_api_log_call('not a token', 'GET', '/me', 200);
  perform public.bot_api_log_call(null, 'GET', '/me', 200);
  perform pg_temp.expect((select count(*) from public.bot_api_calls) = 3, 'a call is logged for a working token and for nothing else');
  perform pg_temp.expect(exists (select 1 from public.bot_api_calls where method = 'GET' and route = '/chats/{id}/messages' and status = 200) and exists (select 1 from public.bot_api_calls where status = 599 and char_length(route) = 80), 'the method in capitals, the route cut and the status kept in range');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_log_call(%L, %L, %L, 200)', tok, 'not a verb!', '/x')) <> 'ok', 'a bad method is refused');
  perform pg_temp.expect(pg_temp.as_state('bob', format('select public.bot_api_log_call(%L, %L, %L, 200)', tok, 'GET', '/x')) = '42501', 'clients cannot write the log');

  list := pg_temp.as_json('ada', format('select public.list_bot_api_calls(%L, 2)', pg_temp.i('helper')));
  perform pg_temp.expect(jsonb_array_length(list) = 2 and list->0 ? 'method' and list->0 ? 'route' and list->0 ? 'status' and list->0 ? 'at', 'managers read the latest calls');
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(list) e, jsonb_object_keys(e) k where k not in ('at', 'method', 'route', 'status')), 'which are only the method, the route, the status and the time');
  perform pg_temp.expect(pg_temp.as_state('bob', format('select public.list_bot_api_calls(%L)', pg_temp.i('helper'))) = '42501' and pg_temp.as_state('eve', format('select public.list_bot_api_calls(%L)', pg_temp.i('helper'))) = '42501' and pg_temp.as_state('anon', format('select public.list_bot_api_calls(%L)', pg_temp.i('helper'))) = '42501', 'others cannot');

  update public.bot_api_calls set at = now() - interval '8 days' where status = 599;
  perform public.purge_bot_api_calls();
  perform pg_temp.expect((select count(*) from public.bot_api_calls) = 2, 'calls older than 7 days are removed');

  -- The developer page is for those who manage a circle.
  perform pg_temp.expect(pg_temp.as_json('ada', 'select to_jsonb(public.my_developer_access())') = 'true'::jsonb, 'a circle''s owner has the developer page');
  perform pg_temp.expect(pg_temp.as_json('bob', 'select to_jsonb(public.my_developer_access())') = 'false'::jsonb and pg_temp.as_json('eve', 'select to_jsonb(public.my_developer_access())') = 'false'::jsonb, 'a plain member and an outsider do not');
  perform pg_temp.expect(pg_temp.as_state('anon', 'select public.my_developer_access()') = '42501', 'nobody signed in cannot ask');
  perform pg_temp.root();
  update public.circle_members set role = 'admin' where circle_id = pg_temp.i('club') and user_id = pg_temp.i('cat');
  perform pg_temp.expect(pg_temp.as_json('cat', 'select to_jsonb(public.my_developer_access())') is not null, 'an admin is asked');
  update public.circle_members set role = 'member' where circle_id = pg_temp.i('club') and user_id = pg_temp.i('cat');

  mine := pg_temp.as_json('ada', 'select public.list_my_developer_bots()');
  perform pg_temp.expect(jsonb_array_length(mine) >= 2 and exists (select 1 from jsonb_array_elements(mine) e where e->>'name' = 'Helper' and e->>'circle_name' = 'Hike Club'), 'the owner sees the circle''s bots');
  perform pg_temp.expect((select e->'events'->>'url' = 'https://example.com/events' and (e->'events'->>'enabled')::boolean and (e->>'allow_direct')::boolean and (e->>'calls_last_day')::int = 2 and e->>'description' = 'Helps with plans' from jsonb_array_elements(mine) e where e->>'name' = 'Helper'), 'with the address, the switches and how busy it was');
  perform pg_temp.expect(mine::text not like '%token_hash%' and mine::text not like '%' || encode(sha256(convert_to(tok, 'UTF8')), 'hex') || '%' and mine::text not like '%' || (select secret from public.bot_event_subscriptions where bot_id = pg_temp.i('helper')) || '%', 'and never a token, a hash or a secret');
  perform pg_temp.expect(pg_temp.as_json('bob', 'select public.list_my_developer_bots()') = '[]'::jsonb and pg_temp.as_json('eve', 'select public.list_my_developer_bots()') = '[]'::jsonb, 'a plain member sees no bots here');
  perform pg_temp.expect(pg_temp.as_state('anon', 'select public.list_my_developer_bots()') = '42501', 'and nobody signed in is refused');
end $$;

-- ===================================== 15. deleting an account, and the data export
do $$
declare
  exp jsonb;
begin
  perform pg_temp.clear_q();
  perform pg_temp.say('bob', 'plaza_conv', 'bob wrote this');
  perform pg_temp.say('cat', 'plaza_conv', 'cat wrote this');
  insert into public.bot_event_deliveries (bot_id, event, payload, actor_id) values (pg_temp.i('helper'), 'reaction.added', '{}', pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.evn('helper') = 3, 'events about two people are waiting (setup)');
  update public.bot_event_subscriptions set owner_id = pg_temp.i('bob') where bot_id = pg_temp.i('helper');

  update public.profiles set deleted_at = now() where id = pg_temp.i('bob');
  perform pg_temp.expect(not exists (select 1 from public.bot_event_deliveries where actor_id = pg_temp.i('bob')), 'deleting an account removes the events that were about the person');
  perform pg_temp.expect(exists (select 1 from public.bot_event_deliveries where actor_id = pg_temp.i('cat')), 'and nobody else''s');
  perform pg_temp.expect((select not enabled and last_error = 'owner_lost_access' from public.bot_event_subscriptions where bot_id = pg_temp.i('helper')), 'a subscription the person owned is paused');
  update public.profiles set deleted_at = null where id = pg_temp.i('bob');
  perform pg_temp.sub('ada', 'helper', 'https://example.com/events', public.bot_event_types());

  -- Export.
  perform pg_temp.expect(pg_temp.as_state('ada', format('select public.export_my_developer(%L)', pg_temp.i('ada'))) = '42501', 'the export is for the export function only');
  exp := public.export_my_developer(pg_temp.i('ada'));
  perform pg_temp.expect(jsonb_array_length(exp->'bots') >= 2, 'the export holds the bots the person made');
  perform pg_temp.expect((select e->>'event_address' = 'https://example.com/events' and e->>'circle' = 'Hike Club' and (e->>'open_to_direct_chats')::boolean and e->>'description' = 'Helps with plans' and e->'event_kinds' @> '["message.created"]' from jsonb_array_elements(exp->'bots') e where e->>'name' = 'Helper'), 'with their address, kinds and switches');
  perform pg_temp.expect(exp::text not like '%token%' and exp::text not like '%secret%' and exp::text not like '%' || (select secret from public.bot_event_subscriptions where bot_id = pg_temp.i('helper')) || '%', 'never a token or a secret');
  perform pg_temp.expect(public.export_my_developer(pg_temp.i('bob')) = '{"bots": []}'::jsonb, 'a person with no bots has none');
  perform pg_temp.expect(pg_temp.state(format('select public.export_my_developer(%L)', null)) = '22023', 'a user is required');
end $$;

-- ===================================== 16. closed doors, and the older functions left alone
do $$
declare
  server_only text[] := array[
    'bot_event_types()', 'bot_conversation_access(circle_bots,uuid)', 'claim_bot_events(integer)', 'finish_bot_event(uuid,boolean,integer,text)',
    'wake_bot_events()', 'wake_bot_events_if_due()', 'purge_bot_events()', 'bot_api_log_call(text,text,text,integer)', 'purge_bot_api_calls()',
    'bot_visible_conversation(circle_bots,uuid)', 'bot_api_list_chats(text)', 'bot_api_list_chat_messages(text,uuid,integer,timestamp with time zone)',
    'bot_api_send_chat_message(text,uuid,text,uuid,jsonb)', 'bot_api_send_file_message(text,uuid,text,text,bigint,text,text)',
    'bot_api_create_poll(text,uuid,text,text[],boolean,integer,boolean)', 'bot_api_create_thread(text,uuid,text)', 'bot_api_delete_message(text,uuid)',
    'bot_api_remove_reaction(text,uuid,text)', 'bot_api_list_members(text,uuid,integer,uuid)', 'bot_api_get_member(text,uuid,uuid)',
    'export_my_developer(uuid)', 'bot_accepts_direct_chat(uuid,uuid)', 'bot_event_enqueue(uuid,text,uuid,uuid,jsonb)', 'bot_event_recipients(text,uuid)',
    'bot_event_withheld_reason(uuid,messages)', 'bot_event_message_json(messages,uuid,text)', 'bot_event_person(uuid,uuid)', 'bot_event_chat(uuid)',
    'erase_bot_events_of_deleted_account()', 'messages_bot_events_insert()', 'messages_bot_events_update()', 'message_mentions_bot_events()',
    'message_reactions_bot_events()', 'circle_members_bot_events()', 'conversation_members_bot_events()', 'bot_interactions_bot_events()'
  ];
  member_rpcs text[] := array[
    'set_bot_event_subscription', 'get_bot_event_subscription', 'rotate_bot_event_secret', 'clear_bot_event_subscription', 'send_bot_test_event',
    'list_bot_event_deliveries', 'set_bot_availability', 'add_bot_to_group', 'remove_bot_from_group', 'list_group_bots', 'search_open_bots',
    'my_developer_access', 'list_my_developer_bots', 'list_bot_api_calls'
  ];
  fn text;
  def text;
begin
  foreach fn in array server_only loop
    perform pg_temp.expect(
      to_regprocedure('public.' || fn) is not null
      and not has_function_privilege('anon', to_regprocedure('public.' || fn), 'execute')
      and not has_function_privilege('authenticated', to_regprocedure('public.' || fn), 'execute'),
      'closed to clients: ' || fn);
  end loop;
  perform pg_temp.expect(has_function_privilege('service_role', 'public.claim_bot_events(integer)'::regprocedure, 'execute')
    and has_function_privilege('service_role', 'public.bot_api_list_chats(text)'::regprocedure, 'execute')
    and has_function_privilege('service_role', 'public.export_my_developer(uuid)'::regprocedure, 'execute')
    and has_function_privilege('service_role', 'public.bot_api_log_call(text,text,text,integer)'::regprocedure, 'execute'), 'and open to the service role');
  perform pg_temp.expect(not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any (member_rpcs)
      and (has_function_privilege('anon', p.oid, 'execute') or not has_function_privilege('authenticated', p.oid, 'execute'))
  ), 'the member functions are for signed-in people only');
  perform pg_temp.expect(not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any (member_rpcs) and not p.prosecdef
  ), 'and are security definer');
  perform pg_temp.expect(not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and (p.proname = any (member_rpcs) or p.oid = any (array(select to_regprocedure('public.' || f)::oid from unnest(server_only) f)))
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c = 'search_path=public')
  ), 'every definer function pins search_path to public');
  perform pg_temp.expect(not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname in ('bot_event_subscriptions', 'bot_event_deliveries', 'bot_api_calls') and not c.relrowsecurity
  ), 'the new tables have row level security on');
  perform pg_temp.expect(not exists (
    select 1 from information_schema.role_table_grants g
    where g.table_schema = 'public' and g.table_name in ('bot_event_subscriptions', 'bot_event_deliveries', 'bot_api_calls') and g.grantee in ('anon', 'authenticated', 'PUBLIC')
  ), 'and no grants to clients');

  -- Nothing older was taken apart.
  def := pg_get_functiondef('public.get_or_create_direct_conversation(uuid)'::regprocedure);
  perform pg_temp.expect(def like '%bot_accepts_direct_chat%' and def like '%friendships%' and def like '%are_users_blocked%', 'the direct chat function keeps its friends check, its block check and has the one exception');
  perform pg_temp.expect((length(def) - length(replace(def, 'bot_accepts_direct_chat', ''))) / length('bot_accepts_direct_chat') = 1, 'once');
  def := pg_get_functiondef('public.run_later_dispatch()'::regprocedure);
  perform pg_temp.expect(def not like '%bot_event%' and def not like '%bot_api_calls%', 'the every-minute dispatcher does not run them');
  perform pg_temp.expect(not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('bot_api_me', 'bot_api_list_channels', 'bot_edit_own_message', 'bot_api_add_reaction', 'bot_api_list_chats', 'bot_api_list_members', 'bot_api_get_member', 'list_group_bots', 'search_open_bots', 'export_my_developer', 'bot_event_person', 'list_my_developer_bots')
      and pg_get_functiondef(p.oid) ~ '[a-z_]+\.bio\M'
  ), 'no function reads a bare bio');
  perform pg_temp.expect(public.bot_api_me(pg_temp.tok('other')) ? 'circle_name' and (select count(*) from pg_proc where proname = 'bot_api_send_message_with_components') = 1, 'the older bot functions are still there');
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform pg_temp.expect(exists (select 1 from cron.job where jobname = 'wecord-bot-events-retry' and schedule = '* * * * *') and exists (select 1 from cron.job where jobname = 'wecord-bot-events-purge') and exists (select 1 from cron.job where jobname = 'wecord-bot-api-calls-purge'), 'the retry and the two clean-ups are cron jobs of their own');
    perform pg_temp.expect((select command from cron.job where jobname = 'wecord-later-dispatch') not like '%bot_%', 'and the every-minute dispatcher does not run them');
  end if;
end $$;

\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'bot events: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
