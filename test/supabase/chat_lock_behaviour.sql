-- Behaviour checks for the app lock and chat lock (roadmap G2: migration
-- 202610260300). Run by test/supabase/chat_lock_test.dart against the local
-- database inside a transaction that is rolled back. Run from the repository
-- root.
--
-- What it walks through: locking a chat (only a person's own direct and group
-- chats, and only through the person's own row), unlocking, leaving a chat
-- takes it out of the list, a thread follows its parent chat, the push text
-- that replaces the real one (per subscription language, only for the person
-- who locked it), and the three readers of chat content that leave locked
-- chats out: the daily digest, the digest cards already made, and AI
-- questions.
--
-- Cast: Ada (a1), Bob (b1) and Cy (c1) are friends; Ada and Bob share a
-- direct chat and two groups with Cy. Dee (d1) joins Bob and Cy in a group
-- Ada is not in.
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

grant execute on all functions in schema pg_temp to public;

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create function pg_temp.i(n text) returns uuid language sql as $$ select id from pg_temp.ids where name = n $$;
grant execute on function pg_temp.i(text) to public;

-- ------------------------------------------------------------------ cast
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '@lock.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '_lock', initcap(name)
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || n)::uuid
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(x.a, x.b), greatest(x.a, x.b)
from (values (pg_temp.i('ada'), pg_temp.i('bob')), (pg_temp.i('ada'), pg_temp.i('cy')), (pg_temp.i('bob'), pg_temp.i('cy')), (pg_temp.i('bob'), pg_temp.i('dee')), (pg_temp.i('cy'), pg_temp.i('dee'))) x(a, b);

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'direct', public.get_or_create_direct_conversation(pg_temp.i('bob'));
insert into pg_temp.ids select 'group', public.create_group_conversation('Plan', array[pg_temp.i('bob'), pg_temp.i('cy')]);
insert into pg_temp.ids select 'group2', public.create_group_conversation('Trip', array[pg_temp.i('bob'), pg_temp.i('cy')]);
select pg_temp.act(pg_temp.i('cy'));
insert into pg_temp.ids select 'cygroup', public.create_group_conversation('Cy only', array[pg_temp.i('bob'), pg_temp.i('dee')]);
select pg_temp.root();

-- A thread of the group "Plan".
insert into public.conversations (id, type) values ('00000000-0000-4000-8000-0000000000f1', 'thread');
insert into public.conversation_threads (parent_conversation_id, conversation_id, title)
values (pg_temp.i('group'), '00000000-0000-4000-8000-0000000000f1', 'A thread');
insert into pg_temp.ids values ('thread', '00000000-0000-4000-8000-0000000000f1');

insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
values
  (pg_temp.i('ada'), 'https://push.test/ada-en', repeat('p', 60), repeat('a', 20), 'en'),
  (pg_temp.i('ada'), 'https://push.test/ada-zh', repeat('q', 60), repeat('b', 20), 'zh'),
  (pg_temp.i('bob'), 'https://push.test/bob', repeat('r', 60), repeat('c', 20), 'zh');

-- ===================================== 1. locking and unlocking
do $$
declare
  ada uuid := pg_temp.i('ada'); g uuid := pg_temp.i('group'); d uuid := pg_temp.i('direct');
  list uuid[];
begin
  perform pg_temp.expect(
    not public.is_conversation_locked(ada, g), 'nothing is locked at the start');

  perform pg_temp.act(ada);
  perform public.set_conversation_locked(g, true);
  perform public.set_conversation_locked(g, true);
  perform pg_temp.root();
  select locked_conversation_ids into list from public.user_notification_settings where user_id = ada;
  perform pg_temp.expect(list = array[g], 'locking twice keeps one entry');
  perform pg_temp.expect(public.is_conversation_locked(ada, g), 'a locked chat is locked');
  perform pg_temp.expect(not public.is_conversation_locked(pg_temp.i('bob'), g), 'and it is locked for the one who locked it only');
  perform pg_temp.expect(not public.is_conversation_locked(ada, d), 'another chat of the same person is not');

  perform pg_temp.act(ada);
  perform public.set_conversation_locked(d, true);
  perform pg_temp.root();
  perform pg_temp.expect(
    (select cardinality(locked_conversation_ids) from public.user_notification_settings where user_id = ada) = 2,
    'a direct chat can be locked too');

  -- Not someone else's chat, and not through a direct write either.
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    pg_temp.state(format('select public.set_conversation_locked(%L, true)', pg_temp.i('cygroup'))) = '23514',
    'a chat the person is not in cannot be locked');
  perform pg_temp.expect(
    pg_temp.state(format(
      'update public.user_notification_settings set locked_conversation_ids = locked_conversation_ids || %L::uuid where user_id = %L',
      pg_temp.i('cygroup'), ada)) = '23514',
    'nor by writing the list directly');
  perform pg_temp.expect(
    pg_temp.state(format(
      'update public.user_notification_settings set locked_conversation_ids = %L::uuid[] where user_id = %L',
      array[g, g], ada)) = 'ok',
    'a direct write of the list works');
  perform pg_temp.expect(
    (select cardinality(locked_conversation_ids) from public.user_notification_settings where user_id = ada) = 1,
    'a direct write is tidied: no duplicates, and a chat left out is unlocked');
  perform pg_temp.expect(
    pg_temp.state('select public.set_conversation_locked(null, true)') = '22023',
    'a missing chat is refused');
  perform pg_temp.root();

  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(
    (select count(*) from public.user_notification_settings where user_id = ada) = 0,
    'nobody reads another person''s locked list');
  perform pg_temp.root();

  -- A thread follows its parent chat.
  perform pg_temp.expect(public.is_conversation_locked(ada, pg_temp.i('thread')), 'a thread of a locked chat is locked');
  perform pg_temp.expect(not public.is_conversation_locked(pg_temp.i('bob'), pg_temp.i('thread')), 'and only for the one who locked the chat');

  perform pg_temp.act(ada);
  perform public.set_conversation_locked(g, false);
  perform public.set_conversation_locked(g, false);
  perform pg_temp.root();
  perform pg_temp.expect(not public.is_conversation_locked(ada, g), 'unlocking unlocks');
  perform pg_temp.expect(not public.is_conversation_locked(ada, pg_temp.i('thread')), 'and its thread');

  -- Only the service role calls the internal functions.
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    pg_temp.state(format('select public.is_conversation_locked(%L, %L)', pg_temp.i('bob'), g)) = '42501',
    'a signed-in person cannot ask whether someone else locked a chat');
  perform pg_temp.expect(
    pg_temp.state(format('select * from public.locked_chat_push_text(%L::jsonb)', '[]')) = '42501',
    'nor read the push text function');
  perform pg_temp.root();
end $$;

-- ===================================== 2. the push text
do $$
declare
  ada uuid := pg_temp.i('ada'); g uuid := pg_temp.i('group'); d uuid := pg_temp.i('direct');
  ada_en uuid; ada_zh uuid; bob_sub uuid; pairs jsonb; r record; n integer;
begin
  select id into ada_en from public.push_subscriptions where endpoint = 'https://push.test/ada-en';
  select id into ada_zh from public.push_subscriptions where endpoint = 'https://push.test/ada-zh';
  select id into bob_sub from public.push_subscriptions where endpoint = 'https://push.test/bob';

  perform pg_temp.act(ada);
  perform public.set_conversation_locked(g, true);
  perform pg_temp.root();

  pairs := jsonb_build_array(
    jsonb_build_object('subscription_id', ada_en, 'conversation_id', g),
    jsonb_build_object('subscription_id', ada_zh, 'conversation_id', g),
    jsonb_build_object('subscription_id', ada_en, 'conversation_id', d),
    jsonb_build_object('subscription_id', bob_sub, 'conversation_id', g),
    jsonb_build_object('subscription_id', ada_en, 'conversation_id', null));

  select count(*) into n from public.locked_chat_push_text(pairs);
  perform pg_temp.expect(n = 2, 'only the pairs of a person who locked that chat get a text, got ' || n);
  select * into r from public.locked_chat_push_text(pairs) where subscription_id = ada_en;
  perform pg_temp.expect(r.body = 'You have a new message' and r.title = 'WeCord', 'an English device is told in English');
  select * into r from public.locked_chat_push_text(pairs) where subscription_id = ada_zh;
  perform pg_temp.expect(r.body = '你收到一条新消息' and r.title = 'WeCord', 'a Chinese device is told in Chinese');
  perform pg_temp.expect(
    not exists (select 1 from public.locked_chat_push_text(pairs) where subscription_id = bob_sub),
    'the other member of the chat still gets the real text');
  perform pg_temp.expect(
    (select count(*) from public.locked_chat_push_text('{"not":"an array"}'::jsonb)) = 0
    and (select count(*) from public.locked_chat_push_text('[]'::jsonb)) = 0,
    'nothing to mask, nothing returned');
  perform pg_temp.expect(
    not exists (select 1 from public.locked_chat_push_text(pairs) where body ilike '%Plan%'),
    'the text names no chat and no sender');
end $$;

-- ===================================== 3. leaving a chat
do $$
declare ada uuid := pg_temp.i('ada'); g uuid := pg_temp.i('group');
begin
  perform pg_temp.expect(public.is_conversation_locked(ada, g), 'locked before leaving');
  delete from public.conversation_members where conversation_id = g and user_id = ada;
  perform pg_temp.expect(not public.is_conversation_locked(ada, g), 'leaving a chat takes it out of the locked list');
  insert into public.conversation_members (conversation_id, user_id, role) values (g, ada, 'member');
  perform pg_temp.expect(not public.is_conversation_locked(ada, g), 'and coming back does not lock it again');
end $$;

-- ===================================== 4. what reads chat content
do $$
declare
  ada uuid := pg_temp.i('ada'); bob uuid := pg_temp.i('bob'); g uuid := pg_temp.i('group'); g2 uuid := pg_temp.i('group2');
  n integer; found uuid[]; digest uuid;
begin
  insert into public.messages (conversation_id, sender_id, type, body, created_at)
  values
    (g, bob, 'text', 'Plan lunch on Friday', now() - interval '30 minutes'),
    (g2, bob, 'text', 'Trip tickets are booked', now() - interval '30 minutes');
  insert into public.ai_digest_subscriptions (user_id, conversation_id) values (ada, g), (ada, g2);

  -- Nothing locked: both chats are covered.
  select count(distinct conversation_id) into n
  from public.ai_digest_messages(ada, now() - interval '2 hours', now());
  perform pg_temp.expect(n = 2, 'digest: both followed chats are covered when nothing is locked, got ' || n);
  found := public.ai_ask_conversations(ada, '{"type":"everywhere"}'::jsonb);
  perform pg_temp.expect(g = any(found) and g2 = any(found), 'ask: both chats can be searched when nothing is locked');

  -- A digest card already made, covering both.
  insert into public.ai_digests (user_id, local_date, window_start, window_end, status, items, finished_at)
  values (ada, current_date, now() - interval '2 hours', now(), 'done',
    jsonb_build_array(
      jsonb_build_object('conversation_id', g, 'summary', 'Lunch plans', 'message_count', 1),
      jsonb_build_object('conversation_id', g2, 'summary', 'Tickets', 'message_count', 1)),
    now())
  returning id into digest;
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    (select jsonb_array_length(items) from public.list_my_ai_digests() where id = digest) = 2,
    'cards: both chats are listed when nothing is locked');
  perform public.set_conversation_locked(g, true);
  perform pg_temp.root();

  select count(distinct conversation_id) into n
  from public.ai_digest_messages(ada, now() - interval '2 hours', now());
  perform pg_temp.expect(n = 1, 'digest: the locked chat is left out, got ' || n);
  perform pg_temp.expect(
    not exists (select 1 from public.ai_digest_messages(ada, now() - interval '2 hours', now()) where conversation_id = g),
    'digest: no message of the locked chat');
  perform pg_temp.expect(
    exists (select 1 from public.ai_digest_messages(ada, now() - interval '2 hours', now()) where conversation_id = g2),
    'digest: the other chat is still covered');
  -- Bob did not lock it.
  insert into public.ai_digest_subscriptions (user_id, conversation_id) values (bob, g);
  insert into public.messages (conversation_id, sender_id, type, body, created_at)
  values (g, ada, 'text', 'Sounds good', now() - interval '20 minutes');
  perform pg_temp.expect(
    exists (select 1 from public.ai_digest_messages(bob, now() - interval '2 hours', now()) where conversation_id = g),
    'digest: a chat Ada locked is still covered for Bob');

  found := public.ai_ask_conversations(ada, '{"type":"everywhere"}'::jsonb);
  perform pg_temp.expect(not (g = any(found)) and g2 = any(found), 'ask: everywhere leaves the locked chat out');
  perform pg_temp.expect(
    cardinality(public.ai_ask_conversations(ada, jsonb_build_object('type', 'conversation', 'id', g))) = 0,
    'ask: a question scoped to the locked chat finds nothing to search');
  perform pg_temp.expect(
    public.ai_ask_scope(ada, jsonb_build_object('type', 'conversation', 'id', g))->>'status' = 'ai_off',
    'ask: and is told so, not given an answer');
  perform pg_temp.expect(
    g = any(public.ai_ask_conversations(bob, '{"type":"everywhere"}'::jsonb)),
    'ask: Bob can still ask about the chat');

  perform pg_temp.act(ada);
  perform pg_temp.expect(
    (select jsonb_array_length(items) from public.list_my_ai_digests() where id = digest) = 1,
    'cards: the locked chat is no longer listed');
  perform pg_temp.expect(
    not exists (select 1 from public.list_my_ai_digests() l, jsonb_array_elements(l.items) e where e->>'conversation_id' = g::text),
    'cards: not even its summary');
  perform public.set_conversation_locked(g, false);
  perform pg_temp.expect(
    (select jsonb_array_length(items) from public.list_my_ai_digests() where id = digest) = 2,
    'cards: unlocking lists it again');
  perform pg_temp.root();
  perform pg_temp.expect(
    g = any(public.ai_ask_conversations(ada, '{"type":"everywhere"}'::jsonb)),
    'ask: and it can be searched again');
end $$;

reset role;
do $$
declare
  failed text;
begin
  select string_agg(msg, E'\n') into failed from pg_temp.failures;
  if failed is not null then
    raise exception E'chat lock checks failed:\n%', failed;
  end if;
end $$;

rollback;
