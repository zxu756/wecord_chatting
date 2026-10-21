-- Behaviour checks for media channels and Q&A channels (C9: migrations
-- 202610270300 to 202610270330). Run by test/supabase/channel_types_test.dart
-- against the local database: it applies the migrations in a transaction,
-- plays people through them, and rolls everything back. Run from the
-- repository root.
--
-- What it walks through: the two new kinds and what created them; that the
-- forum functions patched in place kept what later migrations gave them; a
-- media channel (a picture is required, the permission and storage rules, the
-- channel's own conversation takes nothing, tags and pins work); a Q&A channel
-- (who may mark a post solved, which messages can be the answer, locks,
-- timeouts, the K1 take-down, the audit log, the solved filter, the pushes in
-- both languages); AutoMod and templates with the new kinds; the AI guard on
-- a newcomer's media post; leaving, deleting an account and the data export.
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
\i supabase/migrations/202610270200_member_honors_schema.sql
\i supabase/migrations/202610270210_member_titles.sql
\i supabase/migrations/202610270220_member_honors_compute.sql
\i supabase/migrations/202610270230_member_honors_rpcs.sql
\i supabase/migrations/202610270300_channel_types_schema.sql
\i supabase/migrations/202610270310_qa_solved.sql
\i supabase/migrations/202610270320_media_channel_posts.sql
\i supabase/migrations/202610270330_channel_posts_export.sql
\i supabase/migrations/202610270240_member_honors_export.sql
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
-- ada owns the circle. low is a moderator (manage_messages). bob asks and
-- posts pictures, cat answers, dan is an ordinary member, fay is a member bob
-- blocked. eve has an account but is not in the circle. root is the platform
-- admin.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@c9.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'low'),(3,'bob'),(4,'cat'),(5,'dan'),(6,'eve'),(7,'root'),(8,'fay')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_c9', initcap(name)
from (values (1,'ada'),(2,'low'),(3,'bob'),(4,'cat'),(5,'dan'),(6,'eve'),(7,'root'),(8,'fay')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'low'),(3,'bob'),(4,'cat'),(5,'dan'),(6,'eve'),(7,'root'),(8,'fay')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(pg_temp.i('ada'), pg_temp.i(n)), greatest(pg_temp.i('ada'), pg_temp.i(n))
from (values ('low'),('bob'),('cat'),('dan'),('fay')) v(n);
insert into public.app_admins (user_id, role) values (pg_temp.i('root'), 'owner');

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'club', public.create_circle('Gallery Club', array[
  pg_temp.i('low'), pg_temp.i('bob'), pg_temp.i('cat'), pg_temp.i('dan'), pg_temp.i('fay')]);
insert into pg_temp.ids select 'role_mod', public.create_circle_role(pg_temp.i('club'), 'Mod', null, 4);
select public.set_member_roles(pg_temp.i('club'), pg_temp.i('low'), array[pg_temp.i('role_mod')]);
insert into pg_temp.ids select 'photos', public.create_circle_channel(pg_temp.i('club'), 'photos', null, 'media');
insert into pg_temp.ids select 'help', public.create_circle_channel(pg_temp.i('club'), 'help', null, 'qa');
insert into pg_temp.ids select 'talk', public.create_circle_channel(pg_temp.i('club'), 'talk', null, 'forum');
insert into pg_temp.ids select 'chat', public.create_circle_channel(pg_temp.i('club'), 'chat', null, 'text');
select pg_temp.root();

insert into pg_temp.ids
select 'photos_conv', conversation_id from public.circle_channels where id = pg_temp.i('photos');
insert into pg_temp.ids
select 'help_conv', conversation_id from public.circle_channels where id = pg_temp.i('help');
insert into pg_temp.ids
select 'talk_conv', conversation_id from public.circle_channels where id = pg_temp.i('talk');
insert into pg_temp.ids
select 'chat_conv', conversation_id from public.circle_channels where id = pg_temp.i('chat');

-- A picture for a post in the channel whose conversation is [conv].
create function pg_temp.pic(conv uuid, alt text default null) returns jsonb language sql as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'kind', 'image', 'bucket', 'chat-images', 'path', conv::text || '/kite.png',
    'mime_type', 'image/png', 'size', 1000, 'width', 800, 'height', 600, 'alt', alt))
$$;

-- A post, made by [who] (a cast name) in [channel_name] (ids key); returns
-- the payload.
create function pg_temp.post(who text, channel_key text, title text, body text, attachment jsonb default null)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.act(pg_temp.i(who));
  r := public.create_forum_post(pg_temp.i(channel_key), title, body, array[]::uuid[], attachment, '[]'::jsonb);
  perform pg_temp.root();
  return r;
end $$;

-- A message in a post, written by [who].
create function pg_temp.say(conv uuid, who text, body text) returns uuid language plpgsql as $$
declare mid uuid;
begin
  -- Later than the question: everything else in this script shares one
  -- transaction time.
  insert into public.messages (conversation_id, sender_id, type, body, created_at)
  values (conv, pg_temp.i(who), 'text', body, clock_timestamp())
  returning id into mid;
  return mid;
end $$;

grant execute on all functions in schema pg_temp to public;

-- ===================================== 1. the two kinds
do $$
declare
  club uuid := pg_temp.i('club');
  detail jsonb;
begin
  perform pg_temp.expect((select kind from public.circle_channels where id = pg_temp.i('photos')) = 'media', 'a media channel can be made');
  perform pg_temp.expect((select kind from public.circle_channels where id = pg_temp.i('help')) = 'qa', 'and a Q&A channel');
  perform pg_temp.expect(public.circle_channel_kind_has_posts('forum') and public.circle_channel_kind_has_posts('media') and public.circle_channel_kind_has_posts('qa'), 'forum, media and Q&A hold posts');
  perform pg_temp.expect(not public.circle_channel_kind_has_posts('text') and not public.circle_channel_kind_has_posts('voice') and not public.circle_channel_kind_has_posts('stage') and not public.circle_channel_kind_has_posts('announcement'), 'the other kinds do not');
  perform pg_temp.expect(pg_temp.state(format('insert into public.circle_channels (circle_id, conversation_id, name, kind) values (%L, %L, ''x'', ''gallery'')', club, pg_temp.i('chat_conv'))) = '23514', 'an unknown kind is refused by the table');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_circle_channel(%L, ''nope'', null, ''gallery'')', club)) = '22023', 'and by create_circle_channel');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_circle_channel(%L, ''mine'', null, ''media'')', club)) = '42501', 'a member without manage_channels cannot make one');
  perform pg_temp.act(pg_temp.i('ada'));
  detail := public.get_circle_detail(club);
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(detail -> 'channels') ch where ch ->> 'name' = 'photos' and ch ->> 'kind' = 'media'), 'the circle detail names the media kind');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(detail -> 'channels') ch where ch ->> 'name' = 'help' and ch ->> 'kind' = 'qa'), 'and the Q&A kind');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = club and action = 'channel_create' and changes ->> 'kind' in ('media', 'qa')) = 2, 'both creations are in the audit log with their kind');
end $$;

-- ===================================== 2. patched in place: nothing lost
do $$
declare
  def text;
begin
  def := pg_get_functiondef('public.forum_post_payload(public.conversation_threads, public.circle_channels)'::regprocedure);
  perform pg_temp.expect(def like '%visible_profile_bio%' and def !~ E'''bio'',\\s*author\\.bio','forum_post_payload still hides a bio the viewer may not see');
  perform pg_temp.expect(def like '%message_visible_to_current_user%' and def like '%review_state is null%', 'and the review_state filters');
  perform pg_temp.expect(def like '%count(distinct m.attachment_group_id)%', 'and the album counts');
  perform pg_temp.expect(def like '%solved_message_id%' and def like '%solved_at%', 'plus the solved mark');
  def := pg_get_functiondef('public.create_forum_post(uuid, text, text, uuid[], jsonb, jsonb)'::regprocedure);
  perform pg_temp.expect(def like '%automod_soft%' and def like '%automod_blocked%', 'create_forum_post keeps AutoMod''s quiet refusal');
  perform pg_temp.expect(def like '%post_mentions%' and def like '%message_mentions%', 'and the mentions');
  perform pg_temp.expect(def like '%needs a picture%', 'and asks media channels for a picture');
  def := pg_get_functiondef('public.check_channel_message_send()'::regprocedure);
  perform pg_temp.expect(def like '%ai_reply%' and def like '%slowmode%' and def like '%attachment_group_id%', 'check_channel_message_send keeps the assistant, slowmode and album rules');
  perform pg_temp.expect(def like '%circle_channel_kind_has_posts(channel.kind)%', 'and refuses all three post kinds');
  perform pg_temp.expect(pg_get_functiondef('public.get_circle_detail(uuid)'::regprocedure) like '%visible_profile_bio%', 'the circle detail still hides bios');
  perform pg_temp.expect(pg_get_functiondef('public.create_circle_channel(uuid, text, uuid, text)'::regprocedure) like '%write_circle_audit%', 'create_circle_channel still audits');
end $$;

-- ===================================== 3. a media channel
do $$
declare
  photos uuid := pg_temp.i('photos');
  photos_conv uuid := pg_temp.i('photos_conv');
  club uuid := pg_temp.i('club');
  r jsonb;
  ok_post jsonb;
  tag_id uuid;
  rows integer;
begin
  -- A picture is needed.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_forum_post(%L, ''Sunset'', ''golden hour'', array[]::uuid[], null, ''[]''::jsonb)', photos)) = '22023', 'a media post without a picture is refused');
  perform pg_temp.expect(pg_temp.msg(format('select public.create_forum_post(%L, ''Sunset'', ''golden hour'', array[]::uuid[], null, ''[]''::jsonb)', photos)) like '%needs a picture%', 'and says why');
  perform pg_temp.expect(pg_temp.state(format('select public.create_forum_post(%L, ''Sunset'', '''', array[]::uuid[], null, ''[]''::jsonb)', photos)) = '22023', 'an empty one too');
  -- The picture must sit in the channel's folder.
  perform pg_temp.expect(pg_temp.state(format('select public.create_forum_post(%L, ''Sunset'', '''', array[]::uuid[], %L::jsonb, ''[]''::jsonb)', photos, pg_temp.pic(pg_temp.i('talk_conv')))) = '22023', 'a picture from another channel''s folder is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.create_forum_post(%L, ''Sunset'', '''', array[]::uuid[], %L::jsonb, ''[]''::jsonb)', photos, jsonb_build_object('kind', 'file', 'bucket', 'chat-images', 'path', photos_conv::text || '/a.pdf'))) = '22023', 'and so is something that is not an image');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.conversation_threads where parent_conversation_id = photos_conv) = 0, 'a refused post leaves nothing behind');

  -- With one.
  ok_post := pg_temp.post('bob', 'photos', 'Sunset at the pier', '', pg_temp.pic(photos_conv, 'A red kite over the pier'));
  insert into pg_temp.ids values ('post_sunset', (ok_post ->> 'id')::uuid);
  insert into pg_temp.ids values ('post_sunset_conv', (ok_post ->> 'conversation_id')::uuid);
  perform pg_temp.expect(ok_post ->> 'title' = 'Sunset at the pier', 'a post with a picture and no words is made');
  perform pg_temp.expect(ok_post -> 'thumbnail' ->> 'path' = photos_conv::text || '/kite.png', 'its thumbnail is the picture');
  perform pg_temp.expect(ok_post -> 'thumbnail' ->> 'alt' = 'A red kite over the pier', 'with the description the poster wrote');
  perform pg_temp.expect(ok_post ? 'solved_at' and ok_post ? 'solved_message_id' and ok_post -> 'solved_at' = 'null'::jsonb, 'and no solved mark');
  perform pg_temp.expect((select type from public.messages where conversation_id = (ok_post ->> 'conversation_id')::uuid order by created_at limit 1) = 'image', 'its first message is a picture message');
  r := pg_temp.post('cat', 'photos', 'Street cat', 'Met this one today', pg_temp.pic(photos_conv));
  perform pg_temp.expect(r ->> 'title' = 'Street cat' and r -> 'opening_message' ->> 'body' = 'Met this one today', 'a picture with words works too');
  insert into pg_temp.ids values ('post_cat', (r ->> 'id')::uuid);

  -- Who may post, and where.
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_forum_post(%L, ''Hi'', '''', array[]::uuid[], %L::jsonb, ''[]''::jsonb)', photos, pg_temp.pic(photos_conv))) = '42501', 'a stranger cannot post');
  perform pg_temp.expect(pg_temp.state(format('select public.list_forum_posts(%L)', photos)) = '42501', 'nor read the wall');
  perform pg_temp.root();

  -- The channel's own conversation takes no messages, and nobody opens a
  -- thread in it.
  perform pg_temp.expect(pg_temp.state(format('insert into public.messages (conversation_id, sender_id, type, body) values (%L, %L, ''text'', ''hello'')', photos_conv, pg_temp.i('bob'))) = '42501', 'the media channel''s own conversation takes no messages');
  perform pg_temp.expect(pg_get_functiondef('public.create_thread(uuid, uuid, text)'::regprocedure) like '%circle_channel_kind_has_posts(cc.kind)%', 'create_thread refuses all three post kinds (posts are made with create_forum_post)');

  -- Reading the wall.
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect((select count(*) from public.list_forum_posts(photos)) = 2, 'a member reads the wall');
  perform pg_temp.expect((select count(*) from public.list_forum_posts(photos) p where p -> 'thumbnail' is not null and p -> 'thumbnail' <> 'null'::jsonb) = 2, 'every post has its thumbnail');
  perform pg_temp.root();

  -- Tags and pins work in a media channel.
  perform pg_temp.act(pg_temp.i('ada'));
  tag_id := public.create_forum_tag(photos, 'Landscape', '🌄');
  perform pg_temp.expect(tag_id is not null, 'a media channel has tags');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.set_forum_post_tags(pg_temp.i('post_sunset'), array[tag_id]);
  perform pg_temp.expect((select count(*) from public.thread_tags where thread_id = pg_temp.i('post_sunset')) = 1, 'the poster tags their post');
  perform pg_temp.expect(pg_temp.state(format('select public.pin_forum_post(%L, true)', pg_temp.i('post_sunset'))) = '42501', 'but cannot pin it');
  perform pg_temp.act(pg_temp.i('low'));
  perform public.pin_forum_post(pg_temp.i('post_cat'), true);
  perform pg_temp.expect((select (p ->> 'id')::uuid from public.list_forum_posts(photos) p limit 1) = pg_temp.i('post_cat'), 'a moderator pins; pinned posts come first');
  perform pg_temp.expect((select count(*) from public.list_forum_posts(photos, 'activity', tag_id) p) = 1, 'the tag filter works');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = club and action = 'forum_post_pin') = 1, 'the pin is audited');

  -- The ordinary permission bits and overwrites apply.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_channel_overwrite(photos, (select id from public.circle_roles where circle_id = club and is_default), null, 0, 2);
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_forum_post(%L, ''Hi'', '''', array[]::uuid[], %L::jsonb, ''[]''::jsonb)', photos, pg_temp.pic(photos_conv))) = '42501', 'a channel overwrite that takes send_messages away stops posting');
  perform pg_temp.expect((select count(*) from public.list_forum_posts(photos)) = 2, 'but not reading');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_channel_overwrite(photos, (select id from public.circle_roles where circle_id = club and is_default), null, 0, 0);
  perform pg_temp.root();
end $$;

-- ===================================== 4. a Q&A channel: asking and answering
do $$
declare
  club uuid := pg_temp.i('club');
  help uuid := pg_temp.i('help');
  help_conv uuid := pg_temp.i('help_conv');
  q jsonb;
  talk_post jsonb;
  st jsonb;
  a1 uuid;
  a2 uuid;
begin
  q := pg_temp.post('bob', 'help', 'How do I focus the lens?', 'It stays blurry at the edges.');
  insert into pg_temp.ids values ('q1', (q ->> 'id')::uuid);
  insert into pg_temp.ids values ('q1_conv', (q ->> 'conversation_id')::uuid);
  perform pg_temp.expect(q ->> 'solved_at' is null and q ->> 'solved_message_id' is null, 'a new question is open');
  perform pg_temp.expect(pg_temp.state(format('insert into public.messages (conversation_id, sender_id, type, body) values (%L, %L, ''text'', ''hi'')', help_conv, pg_temp.i('bob'))) = '42501', 'the Q&A channel''s own conversation takes no messages');
  a1 := pg_temp.say(pg_temp.i('q1_conv'), 'cat', 'Turn the ring until the edges sharpen.');
  a2 := pg_temp.say(pg_temp.i('q1_conv'), 'dan', 'Clean the front element.');
  insert into pg_temp.ids values ('a1', a1), ('a2', a2);
  insert into pg_temp.ids select 'opening', public.qa_opening_message_id(pg_temp.i('q1_conv'));
  perform pg_temp.expect((select sender_id from public.messages where id = pg_temp.i('opening')) = pg_temp.i('bob'), 'the question is the first message of the post');

  -- A post in an ordinary forum has no Q&A state.
  talk_post := pg_temp.post('bob', 'talk', 'Favourite lens?', 'Tell me.');
  insert into pg_temp.ids values ('t1_conv', (talk_post ->> 'conversation_id')::uuid), ('t1', (talk_post ->> 'id')::uuid);
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(public.get_qa_post_state(pg_temp.i('t1_conv')) is null, 'a forum post has no Q&A state');
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L)', pg_temp.i('t1'))) = '22023', 'and cannot be marked solved');
  perform pg_temp.expect(pg_temp.state(format('select public.reopen_qa_post(%L)', pg_temp.i('t1'))) = '22023', 'or reopened');
  perform pg_temp.expect(pg_temp.state(format('select public.list_qa_posts(%L)', pg_temp.i('talk'))) = '22023', 'and its channel is not listed as Q&A');

  -- The state each person gets.
  st := public.get_qa_post_state(pg_temp.i('q1_conv'));
  perform pg_temp.expect((st ->> 'can_mark')::boolean and not (st ->> 'solved')::boolean, 'the asker can mark their question');
  perform pg_temp.expect((st ->> 'opening_message_id')::uuid = pg_temp.i('opening') and st ->> 'answer_message_id' is null, 'the state names the question itself');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(not (public.get_qa_post_state(pg_temp.i('q1_conv')) ->> 'can_mark')::boolean, 'another member cannot');
  perform pg_temp.act(pg_temp.i('low'));
  perform pg_temp.expect((public.get_qa_post_state(pg_temp.i('q1_conv')) ->> 'can_mark')::boolean, 'a moderator can');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(public.get_qa_post_state(pg_temp.i('q1_conv')) is null, 'a stranger gets nothing');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select public.get_qa_post_state(%L)', pg_temp.i('q1_conv'))) = '42501', 'and nobody signed in cannot even ask');
  perform pg_temp.root();
end $$;

-- ===================================== 5. solving
do $$
declare
  club uuid := pg_temp.i('club');
  help uuid := pg_temp.i('help');
  q1 uuid := pg_temp.i('q1');
  conv uuid := pg_temp.i('q1_conv');
  st jsonb;
  bad uuid;
begin
  -- Who may.
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L, %L)', q1, pg_temp.i('a1'))) = '42501', 'a member who is not the asker cannot pick the answer');
  perform pg_temp.expect(pg_temp.state(format('select public.reopen_qa_post(%L)', q1)) = '42501', 'nor reopen');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L, %L)', q1, pg_temp.i('a1'))) = '42501', 'a stranger cannot');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L)', q1)) = '42501', 'nobody signed in cannot');

  -- Which messages.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L, %L)', q1, pg_temp.i('opening'))) = '22023', 'the question itself is not an answer');
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L, %L)', q1, gen_random_uuid())) = '22023', 'a message that does not exist is not');
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L, %L)', q1, (select id from public.messages where conversation_id = pg_temp.i('t1_conv') limit 1))) = '22023', 'nor one from another post');
  perform pg_temp.root();
  insert into public.messages (conversation_id, sender_id, type, body) values (conv, pg_temp.i('cat'), 'system', 'a notice') returning id into bad;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L, %L)', q1, bad)) = '22023', 'a system notice is not');
  perform pg_temp.root();
  bad := pg_temp.say(conv, 'cat', 'taken back');
  update public.messages set recalled_at = now() where id = bad;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L, %L)', q1, bad)) = '22023', 'a message deleted for everyone is not');
  perform pg_temp.root();
  bad := pg_temp.say(conv, 'cat', 'waiting for review');
  update public.messages set review_state = 'held' where id = bad;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L, %L)', q1, bad)) = '22023', 'a message held for review is not');
  perform pg_temp.root();
  bad := pg_temp.say(conv, 'cat', 'gone soon');
  update public.messages set expires_at = now() - interval '1 minute' where id = bad;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L, %L)', q1, bad)) = '22023', 'an expired message is not');
  perform pg_temp.root();
  bad := pg_temp.say(conv, 'cat', 'look once');
  update public.messages set attachment = '{"kind":"image","view_once":true}'::jsonb where id = bad;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L, %L)', q1, bad)) = '22023', 'a view-once picture is not');

  -- Accepting an answer.
  st := public.mark_post_solved(q1, pg_temp.i('a1'));
  perform pg_temp.expect((st ->> 'solved')::boolean and (st ->> 'answer_message_id')::uuid = pg_temp.i('a1'), 'the asker accepts an answer and the state says so');
  perform pg_temp.root();
  perform pg_temp.expect((select solved_by from public.conversation_threads where id = q1) = pg_temp.i('bob') and (select solved_at from public.conversation_threads where id = q1) is not null, 'who and when are kept');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = club and action = 'forum_post_solved' and target_id = q1) = 1, 'the audit log has it');
  perform pg_temp.expect((select changes ->> 'answer_message_id' from public.circle_audit_log where circle_id = club and action = 'forum_post_solved' order by created_at desc limit 1) = pg_temp.i('a1')::text, 'with the answer');

  -- The post and the list.
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect((select (p ->> 'solved_message_id')::uuid from public.list_forum_posts(help) p where (p ->> 'id')::uuid = q1) = pg_temp.i('a1'), 'the post list carries the accepted answer');
  perform pg_temp.expect((select count(*) from public.list_qa_posts(help, 'activity', null, 'solved')) = 1 and (select count(*) from public.list_qa_posts(help, 'activity', null, 'unsolved')) = 0, 'the solved filter finds it');
  perform pg_temp.expect((select count(*) from public.list_qa_posts(help)) = 1 and (select count(*) from public.list_qa_posts(help, 'created', null, 'all')) = 1, 'and all shows everything');
  perform pg_temp.expect(pg_temp.state(format('select public.list_qa_posts(%L, ''activity'', null, ''maybe'')', help)) = '22023', 'a made-up filter is refused');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.list_qa_posts(%L)', help)) = '42501', 'a stranger cannot list');
  perform pg_temp.root();

  -- The same again changes nothing; another answer moves the mark.
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.mark_post_solved(q1, pg_temp.i('a1'));
  perform public.mark_post_solved(q1);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = club and action = 'forum_post_solved') = 1, 'accepting the same again, or marking a solved post, writes nothing');
  perform pg_temp.act(pg_temp.i('bob'));
  st := public.mark_post_solved(q1, pg_temp.i('a2'));
  perform pg_temp.expect((st ->> 'answer_message_id')::uuid = pg_temp.i('a2'), 'another answer takes the mark');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = club and action = 'forum_post_solved') = 2, 'and is audited');

  -- An answer that is later deleted for everyone stops being the answer; the
  -- post stays solved.
  update public.messages set recalled_at = now() where id = pg_temp.i('a2');
  perform pg_temp.act(pg_temp.i('dan'));
  st := public.get_qa_post_state(conv);
  perform pg_temp.expect((st ->> 'solved')::boolean and st ->> 'answer_message_id' is null, 'a deleted answer no longer shows as the answer, the question stays solved');
  perform pg_temp.root();
  update public.messages set recalled_at = null where id = pg_temp.i('a2');

  -- Hard deletion clears the link, not the solved state.
  bad := pg_temp.say(conv, 'dan', 'to be removed');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.mark_post_solved(q1, bad);
  perform pg_temp.root();
  delete from public.messages where id = bad;
  perform pg_temp.expect((select solved_message_id from public.conversation_threads where id = q1) is null and (select solved_at from public.conversation_threads where id = q1) is not null, 'deleting the accepted message for good leaves the post solved');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.mark_post_solved(q1, pg_temp.i('a1'));

  -- Reopening.
  st := public.reopen_qa_post(q1);
  perform pg_temp.expect(not (st ->> 'solved')::boolean and st ->> 'answer_message_id' is null, 'the asker reopens');
  perform pg_temp.root();
  perform pg_temp.expect((select solved_at is null and solved_by is null and solved_message_id is null from public.conversation_threads where id = q1), 'everything about the mark is cleared');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = club and action = 'forum_post_reopened') = 1, 'and it is in the audit log');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.reopen_qa_post(q1);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = club and action = 'forum_post_reopened') = 1, 'reopening an open question writes nothing');
end $$;

-- ===================================== 6. moderators, locks, timeouts, K1
do $$
declare
  club uuid := pg_temp.i('club');
  q1 uuid := pg_temp.i('q1');
  st jsonb;
begin
  -- A moderator solves without an answer, and can lift it.
  perform pg_temp.act(pg_temp.i('low'));
  st := public.mark_post_solved(q1);
  perform pg_temp.expect((st ->> 'solved')::boolean and st ->> 'answer_message_id' is null, 'a moderator marks it solved without picking an answer');
  st := public.mark_post_solved(q1, pg_temp.i('a1'));
  perform pg_temp.expect((st ->> 'answer_message_id')::uuid = pg_temp.i('a1'), 'and then picks one');
  perform public.reopen_qa_post(q1);
  perform pg_temp.root();

  -- A locked post is for moderators.
  perform pg_temp.act(pg_temp.i('low'));
  perform public.set_thread_locked(q1, true);
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(not (public.get_qa_post_state(pg_temp.i('q1_conv')) ->> 'can_mark')::boolean, 'while the post is locked the asker cannot mark it');
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L, %L)', q1, pg_temp.i('a1'))) = '42501', 'the call is refused too');
  perform pg_temp.act(pg_temp.i('low'));
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L, %L)', q1, pg_temp.i('a1'))) = 'ok', 'a moderator still can');
  perform public.reopen_qa_post(q1);
  perform public.set_thread_locked(q1, false);
  perform pg_temp.root();

  -- A timed-out asker cannot.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.timeout_circle_member(club, pg_temp.i('bob'), 600);
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L, %L)', q1, pg_temp.i('a1'))) = '42501', 'a timed-out asker cannot mark it');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.timeout_circle_member(club, pg_temp.i('bob'), 0);
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L, %L)', q1, pg_temp.i('a1'))) = 'ok', 'after the timeout they can');
  perform public.reopen_qa_post(q1);

  -- An asker who lost view_channel cannot.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_channel_overwrite(pg_temp.i('help'), (select id from public.circle_roles where circle_id = club and is_default), null, 0, 1);
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L)', q1)) = '42501', 'an asker who can no longer see the channel cannot');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_channel_overwrite(pg_temp.i('help'), (select id from public.circle_roles where circle_id = club and is_default), null, 0, 0);

  -- Somebody who left cannot.
  perform pg_temp.root();
  delete from public.circle_members where circle_id = club and user_id = pg_temp.i('fay');
  perform pg_temp.act(pg_temp.i('fay'));
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L)', q1)) = '42501', 'somebody who left the circle cannot');
  perform pg_temp.root();
  insert into public.circle_members (circle_id, user_id, role) values (club, pg_temp.i('fay'), 'member');

  -- K1: a circle the platform has taken down takes no marks and no posts.
  perform pg_temp.act(pg_temp.i('root'));
  perform public.admin_disable_circle(club, 'suspend', 'test');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L, %L)', q1, pg_temp.i('a1'))) = '42501', 'a suspended circle takes no marks');
  perform pg_temp.expect(pg_temp.state(format('select public.create_forum_post(%L, ''Late'', ''x'', array[]::uuid[], null, ''[]''::jsonb)', pg_temp.i('help'))) = '42501', 'and no new questions');
  perform pg_temp.expect(pg_temp.state(format('select public.create_forum_post(%L, ''Late'', '''', array[]::uuid[], %L::jsonb, ''[]''::jsonb)', pg_temp.i('photos'), pg_temp.pic(pg_temp.i('photos_conv')))) = '42501', 'nor new pictures');
  perform pg_temp.act(pg_temp.i('low'));
  perform pg_temp.expect(pg_temp.state(format('select public.mark_post_solved(%L, %L)', q1, pg_temp.i('a1'))) = '42501', 'not even from a moderator');
  perform pg_temp.expect(pg_temp.state(format('select public.reopen_qa_post(%L)', q1)) = '42501', 'nor reopening');
  perform pg_temp.act(pg_temp.i('root'));
  perform public.admin_enable_circle(club, 'back');
  perform pg_temp.root();
end $$;

-- ===================================== 7. the pushes
do $$
declare
  club uuid := pg_temp.i('club');
  q jsonb;
  qid uuid;
  conv uuid;
  c1 uuid;
  d1 uuid;
  b1 uuid;
  rows integer;
begin
  perform pg_temp.root();
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
  values (pg_temp.i('cat'), 'https://push.example.com/cat-zh', repeat('k', 60), repeat('a', 20), 'zh'),
         (pg_temp.i('cat'), 'https://push.example.com/cat-en', repeat('k', 60), repeat('a', 20), 'en'),
         (pg_temp.i('bob'), 'https://push.example.com/bob-zh', repeat('k', 60), repeat('a', 20), 'zh'),
         (pg_temp.i('dan'), 'https://push.example.com/dan-en', repeat('k', 60), repeat('a', 20), 'en');
  delete from public.qa_answer_notices;

  q := pg_temp.post('bob', 'help', 'Why is my <b>sky</b> grey?', 'Shot at noon.');
  qid := (q ->> 'id')::uuid;
  conv := (q ->> 'conversation_id')::uuid;
  c1 := pg_temp.say(conv, 'cat', 'Raise the exposure.');
  d1 := pg_temp.say(conv, 'dan', 'Use a polarizer.');
  b1 := pg_temp.say(conv, 'bob', 'Update: found it myself.');

  -- Your own answer, accepted by you: nothing to tell.
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.mark_post_solved(qid, b1);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.qa_answer_notices) = 0, 'accepting your own answer tells nobody');

  perform pg_temp.act(pg_temp.i('bob'));
  perform public.mark_post_solved(qid, c1);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.qa_answer_notices where user_id = pg_temp.i('cat') and kind = 'answer_accepted' and push_claimed_at is null) = 1, 'the author of an accepted answer is told');
  perform pg_temp.expect((select count(*) from public.qa_answer_notices where user_id = pg_temp.i('bob')) = 0, 'the asker is not told about their own doing');

  perform pg_temp.act(pg_temp.i('bob'));
  perform public.mark_post_solved(qid, d1);
  perform public.mark_post_solved(qid, c1);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.qa_answer_notices where user_id = pg_temp.i('dan')) = 1, 'another accepted answer tells its author');
  perform pg_temp.expect((select count(*) from public.qa_answer_notices where user_id = pg_temp.i('cat')) = 1, 'but the same news about the same post is not sent twice in a day');

  -- A moderator solves it for somebody else.
  q := pg_temp.post('bob', 'help', 'What is a prime lens?', 'New to this.');
  insert into pg_temp.ids values ('q3', (q ->> 'id')::uuid);
  c1 := pg_temp.say((q ->> 'conversation_id')::uuid, 'cat', 'A fixed focal length.');
  perform pg_temp.act(pg_temp.i('low'));
  perform public.mark_post_solved(pg_temp.i('q3'), c1);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.qa_answer_notices where thread_id = pg_temp.i('q3') and user_id = pg_temp.i('cat') and kind = 'answer_accepted') = 1, 'a moderator accepting an answer tells its author');
  perform pg_temp.expect((select count(*) from public.qa_answer_notices where thread_id = pg_temp.i('q3') and user_id = pg_temp.i('bob') and kind = 'marked_solved') = 1, 'and the asker');

  q := pg_temp.post('bob', 'help', 'Is f/1.8 enough?', 'For portraits.');
  insert into pg_temp.ids values ('q4', (q ->> 'id')::uuid);
  perform pg_temp.act(pg_temp.i('low'));
  perform public.mark_post_solved(pg_temp.i('q4'));
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.qa_answer_notices where thread_id = pg_temp.i('q4') and user_id = pg_temp.i('bob') and kind = 'marked_solved') = 1, 'a moderator solving without an answer tells the asker');

  -- Across a block, to somebody who left, to a bot: nothing.
  q := pg_temp.post('bob', 'help', 'Tripod or monopod?', 'Hiking.');
  insert into pg_temp.ids values ('q5', (q ->> 'id')::uuid);
  c1 := pg_temp.say((q ->> 'conversation_id')::uuid, 'dan', 'Monopod.');
  d1 := pg_temp.say((q ->> 'conversation_id')::uuid, 'fay', 'Tripod.');
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('dan'), pg_temp.i('low'));
  perform pg_temp.act(pg_temp.i('low'));
  perform public.mark_post_solved(pg_temp.i('q5'), c1);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.qa_answer_notices where thread_id = pg_temp.i('q5') and user_id = pg_temp.i('dan')) = 0, 'nothing is sent across a block');
  delete from public.circle_members where circle_id = club and user_id = pg_temp.i('fay');
  perform pg_temp.act(pg_temp.i('low'));
  perform public.mark_post_solved(pg_temp.i('q5'), d1);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.qa_answer_notices where thread_id = pg_temp.i('q5') and user_id = pg_temp.i('fay')) = 0, 'nor to somebody who left the circle');
  insert into public.circle_members (circle_id, user_id, role) values (club, pg_temp.i('fay'), 'member');
  perform pg_temp.expect((select count(*) from public.qa_answer_notices n where not exists (select 1 from public.circle_members cm where cm.circle_id = n.circle_id and cm.user_id = n.user_id)) = 0, 'every waiting push is for a member');

  -- Claiming.
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state('select * from public.claim_qa_answer_pushes()') = '42501', 'only the service role claims pushes');
  perform pg_temp.root();
  create temp table claimed_qa on commit drop as select * from public.claim_qa_answer_pushes();
  perform pg_temp.expect((select count(*) from claimed_qa where title = '你的回答被采纳了' and body like '%Gallery Club%' and body like '%采纳了你的回答%') >= 1, 'the Chinese device of an answerer gets Chinese words');
  perform pg_temp.expect((select count(*) from claimed_qa where title = 'Your answer was accepted' and body like 'Your answer to "%" in Gallery Club was accepted.') >= 1, 'the English one gets English');
  perform pg_temp.expect((select count(*) from claimed_qa where title = '你的问题已解决' and body like '版主把「Gallery Club」里的问题「%」标为了已解决。') >= 1, 'a solved question is worded in Chinese for the asker');
  perform pg_temp.expect((select count(*) from claimed_qa where title = 'Your question was marked solved') = 0, 'and only the asker''s Chinese device exists here');
  perform pg_temp.expect((select count(*) from claimed_qa where body like '%<%' or body like '%>%') = 0, 'angle brackets in a post title are cleaned away');
  perform pg_temp.expect((select count(*) from claimed_qa where body like '%Why is my bsky/b grey%') >= 1, 'which leaves the rest of the title');
  perform pg_temp.expect((select count(*) from claimed_qa where url !~ ('^/#/circles/' || club::text || '/channels/[0-9a-f-]{36}$')) = 0, 'a tap opens the post');
  perform pg_temp.expect((select count(*) from claimed_qa where tag !~ '^qa-[0-9a-f-]{36}$') = 0, 'each push is tagged by its notice');
  perform pg_temp.expect((select count(*) from public.claim_qa_answer_pushes()) = 0, 'a push is claimed once');
  perform pg_temp.expect((select count(*) from public.qa_answer_notices where push_claimed_at is null) = 0, 'and all are closed');

  -- One that waited too long is closed without a push.
  insert into public.qa_answer_notices (user_id, circle_id, thread_id, kind, created_at)
  values (pg_temp.i('cat'), club, pg_temp.i('q3'), 'answer_accepted', now() - interval '20 minutes');
  perform pg_temp.expect((select count(*) from public.claim_qa_answer_pushes()) = 0, 'an old one is dropped, not sent late');

  -- A circle that is down sends nothing.
  insert into public.qa_answer_notices (user_id, circle_id, thread_id, kind)
  values (pg_temp.i('cat'), club, pg_temp.i('q3'), 'answer_accepted');
  update public.circles set disabled_at = now(), disabled_mode = 'delist' where id = club;
  perform pg_temp.expect((select count(*) from public.claim_qa_answer_pushes()) = 0, 'a circle taken down sends nothing');
  update public.circles set disabled_at = null, disabled_mode = null where id = club;
end $$;

-- ===================================== 8. AutoMod, templates, raid protection, the AI guard
do $$
declare
  club uuid := pg_temp.i('club');
  photos uuid := pg_temp.i('photos');
  photos_conv uuid := pg_temp.i('photos_conv');
  rule_id uuid;
  r jsonb;
  before_threads integer;
  code text;
  copy_id uuid;
begin
  -- AutoMod never names a post channel for its alerts, and blocks a post's words.
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format(
    'select public.save_circle_automod_rule(%L, %L::jsonb)', club,
    jsonb_build_object('name', 'alerts', 'kind', 'mention_spam', 'mention_limit', 5, 'alert_channel_id', photos)
  )) <> 'ok', 'an AutoMod rule cannot send its alerts into a media channel');
  perform pg_temp.expect(pg_temp.state(format(
    'select public.save_circle_automod_rule(%L, %L::jsonb)', club,
    jsonb_build_object('name', 'alerts2', 'kind', 'mention_spam', 'mention_limit', 5, 'alert_channel_id', pg_temp.i('help'))
  )) <> 'ok', 'nor into a Q&A channel');
  rule_id := public.save_circle_automod_rule(club, jsonb_build_object(
    'name', 'no shouting', 'kind', 'keyword', 'keywords', jsonb_build_array('forbiddenword'),
    'block_message', true, 'block_reason', 'Not here'));
  perform pg_temp.root();
  before_threads := (select count(*) from public.conversation_threads where parent_conversation_id = photos_conv);
  r := pg_temp.post('dan', 'photos', 'Look at this', 'a forbiddenword caption', pg_temp.pic(photos_conv));
  perform pg_temp.expect((r ->> 'automod_blocked')::boolean, 'AutoMod blocks a media post''s words quietly');
  perform pg_temp.expect((select count(*) from public.conversation_threads where parent_conversation_id = photos_conv) = before_threads, 'and leaves no empty post behind');
  r := pg_temp.post('dan', 'help', 'A question', 'a forbiddenword question');
  perform pg_temp.expect((r ->> 'automod_blocked')::boolean, 'and a Q&A question''s');
  delete from public.circle_automod_rules where id = rule_id;

  -- A template keeps the kinds and the tags.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.create_forum_tag(pg_temp.i('help'), 'Gear', null);
  code := public.create_circle_template(club, 'Gallery', 'A wall and a help desk') ->> 'code';
  perform pg_temp.act(pg_temp.i('bob'));
  copy_id := public.create_circle_from_template(code, 'Copy Club');
  perform pg_temp.root();
  perform pg_temp.expect((select kind from public.circle_channels where circle_id = copy_id and name = 'photos') = 'media'
    and (select kind from public.circle_channels where circle_id = copy_id and name = 'help') = 'qa', 'a circle made from a template gets its media and Q&A channels');
  perform pg_temp.expect((select count(*) from public.forum_tags where channel_id = (select id from public.circle_channels where circle_id = copy_id and name = 'photos')) = 1
    and (select count(*) from public.forum_tags where channel_id = (select id from public.circle_channels where circle_id = copy_id and name = 'help')) = 1, 'with their tags');

  -- Raid protection: links from newcomers wait while the circle is locked down.
  delete from public.circle_members where circle_id = club and user_id = pg_temp.i('fay');
  insert into public.circle_members (circle_id, user_id, role) values (club, pg_temp.i('fay'), 'member');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.start_circle_lockdown(club, 1);
  perform pg_temp.act(pg_temp.i('fay'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_forum_post(%L, ''Link'', ''see https://example.com'', array[]::uuid[], %L::jsonb, ''[]''::jsonb)', photos, pg_temp.pic(photos_conv))) = '42501', 'a newcomer cannot put a link in a media post during a lockdown');
  perform pg_temp.expect(pg_temp.state(format('select public.create_forum_post(%L, ''Link'', ''see https://example.com'', array[]::uuid[], null, ''[]''::jsonb)', pg_temp.i('help'))) = '42501', 'nor in a question');
  perform pg_temp.expect(pg_temp.state(format('select public.create_forum_post(%L, ''Pic'', '''', array[]::uuid[], %L::jsonb, ''[]''::jsonb)', photos, pg_temp.pic(photos_conv))) = 'ok', 'but a plain picture goes through');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.end_circle_lockdown(club);
  perform pg_temp.root();

  -- The AI guard checks a newcomer's words in a post.
  perform vault.create_secret('http://127.0.0.1:54321/functions/v1', 'wecord_functions_url');
  perform vault.create_secret('guard-test-secret', 'wecord_dispatch_secret');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_ai_guard(club, true, 'joined_days', 3, 10, 'hold');
  perform pg_temp.root();
  r := pg_temp.post('dan', 'photos', 'Fresh from the market', 'Win cheap pills now http://evil.example', pg_temp.pic(photos_conv));
  perform pg_temp.expect((select review_state from public.messages where conversation_id = (r ->> 'conversation_id')::uuid order by created_at limit 1) = 'checking', 'a newcomer''s media post waits for the AI guard');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect((select count(*) from public.list_forum_posts(photos) p where (p ->> 'id')::uuid = (r ->> 'id')::uuid and p -> 'opening_message' = 'null'::jsonb and p -> 'thumbnail' = 'null'::jsonb) = 1, 'others see neither its words nor its picture meanwhile');
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect((select count(*) from public.list_forum_posts(photos) p where (p ->> 'id')::uuid = (r ->> 'id')::uuid and p -> 'opening_message' <> 'null'::jsonb) = 1, 'the author sees their own');
  perform pg_temp.root();
  -- Same in a question; and a held answer cannot be accepted.
  r := pg_temp.post('dan', 'help', 'Where to buy filters?', 'Win cheap pills now http://evil.example');
  perform pg_temp.expect((select review_state from public.messages where conversation_id = (r ->> 'conversation_id')::uuid order by created_at limit 1) = 'checking', 'a newcomer''s question waits for the AI guard too');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_ai_guard(club, false, 'joined_days', 3, 10, 'hold');
  perform pg_temp.root();
end $$;

-- ===================================== 9. leaving, deleting an account, the data export
do $$
declare
  club uuid := pg_temp.i('club');
  x jsonb;
  y jsonb;
begin
  perform pg_temp.root();
  x := public.export_my_channel_posts(pg_temp.i('bob'));
  perform pg_temp.expect(jsonb_array_length(x -> 'media_posts') = 1 and x -> 'media_posts' -> 0 ->> 'title' = 'Sunset at the pier', 'the export has my media posts with their title');
  perform pg_temp.expect(x -> 'media_posts' -> 0 -> 'picture' ->> 'description' = 'A red kite over the pier' and x -> 'media_posts' -> 0 -> 'picture' ->> 'path' like '%/kite.png', 'with the picture and the description I wrote');
  perform pg_temp.expect(jsonb_array_length(x -> 'questions') >= 4 and exists (select 1 from jsonb_array_elements(x -> 'questions') e where (e ->> 'solved')::boolean), 'and my questions, with whether they were solved');
  perform pg_temp.expect(x::text not like '%Street cat%' and x::text not like '%Fresh from the market%', 'but not other people''s posts');
  y := public.export_my_channel_posts(pg_temp.i('cat'));
  perform pg_temp.expect(jsonb_array_length(y -> 'accepted_answers') >= 1 and y -> 'accepted_answers' -> 0 ? 'accepted_at', 'the answers of mine that were accepted');
  perform pg_temp.expect(y::text not like '%How do I focus the lens%' and y::text not like '%prime lens%', 'without the titles of other people''s questions');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.export_my_channel_posts(%L)', pg_temp.i('cat'))) = '42501', 'only the service role asks for it');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select public.export_my_channel_posts(%L)', pg_temp.i('cat'))) = '42501', 'not even the signed out');
  perform pg_temp.root();

  -- Closed to clients.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state('select count(*) from public.qa_answer_notices') = '42501', 'the waiting pushes are not a table clients can read');
  perform pg_temp.expect(pg_temp.state(format('update public.conversation_threads set solved_at = now() where id = %L', pg_temp.i('q4'))) = 'ok'
    and (select solved_at from public.conversation_threads where id = pg_temp.i('q4')) is not null
    and (select solved_by from public.conversation_threads where id = pg_temp.i('q4')) = pg_temp.i('low'), 'a client cannot write the solved mark with an update (no policy lets the row change)');
  perform pg_temp.root();

  -- Leaving takes the waiting pushes along; deleting an account too, and the
  -- post stays solved without naming them.
  insert into public.qa_answer_notices (user_id, circle_id, thread_id, kind)
  values (pg_temp.i('dan'), club, pg_temp.i('q3'), 'answer_accepted'), (pg_temp.i('cat'), club, pg_temp.i('q3'), 'answer_accepted');
  delete from public.circle_members where circle_id = club and user_id = pg_temp.i('dan');
  perform pg_temp.expect((select count(*) from public.qa_answer_notices where user_id = pg_temp.i('dan')) = 0, 'leaving the circle takes the waiting pushes along');
  perform pg_temp.expect((select solved_by from public.conversation_threads where id = pg_temp.i('q4')) = pg_temp.i('low'), 'a moderator who solved q4 is named');
  update public.profiles set deleted_at = now() where id = pg_temp.i('low');
  perform pg_temp.expect((select solved_by from public.conversation_threads where id = pg_temp.i('q4')) is null and (select solved_at from public.conversation_threads where id = pg_temp.i('q4')) is not null, 'a deleted account is no longer named as the one who solved a post, which stays solved');
  update public.profiles set deleted_at = now() where id = pg_temp.i('cat');
  perform pg_temp.expect((select count(*) from public.qa_answer_notices where user_id = pg_temp.i('cat')) = 0, 'a deleted account''s waiting pushes are erased');
end $$;
\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'channel types: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
