-- Behaviour checks for interactive components and interaction callbacks (I1:
-- migrations 202610280610 to 202610280660). Run by
-- test/supabase/interactions_test.dart against the local database: it applies
-- the migrations in a transaction, plays people through them, and rolls
-- everything back. Run from the repository root.
--
-- What it walks through: the checker of components (limits, https links only,
-- no inner addresses, no control or direction characters, unknown keys
-- dropped); who may put components on a message (only a bot's own text,
-- only through the bot functions); AutoMod reading the buttons; a bot changing
-- its own message; pressing a component (who may, what is checked, the limits);
-- the bot polling and answering (message, private reply, update, ack); private
-- replies that only their person reads; the callback address (SSRF rules,
-- managers only, the secret shown once), the queue, the retries and the pause;
-- the data export, the clean-up and deleting an account; and that the older
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
-- ada owns the circle club (channels plaza and vault); bob, cat, dan and fay
-- are members; eve is nobody's. Helper and Other are bots of the club. root is
-- the platform admin. vault is private: only ada sees it.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@i1.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'fay'),(7,'root')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_i1', initcap(name)
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

-- Two bots, made the way the bots Edge function does it: a banned login first,
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
grant execute on all functions in schema pg_temp to public;

-- The bot is in the vault conversation too (a bot is a member of every channel
-- conversation); that is not what lets members in.
-- A sample of every component kind.
create function pg_temp.sample() returns jsonb language sql as $$
  select '[
    [{"type":"button","id":"approve","label":"Approve","style":"primary"},
     {"type":"button","id":"reject","label":"Reject","style":"danger"},
     {"type":"link","label":"Docs","url":"https://example.com/docs?a=1#top"}],
    [{"type":"select","id":"pick","placeholder":"Pick a trail","options":[
       {"label":"Ridge","value":"ridge","description":"Hard"},
       {"label":"Lake","value":"lake","default":true},
       {"label":"Forest","value":"forest"}],"min_values":1,"max_values":2}],
    [{"type":"button","id":"note","label":"Add a note","modal":{"title":"Your note","fields":[
       {"id":"text","label":"Note","style":"paragraph","max_length":50},
       {"id":"name","label":"Name","required":false}]}}]
  ]'::jsonb $$;
grant execute on all functions in schema pg_temp to public;

-- A bot message with [comps] in [conv] (default plaza), by the bot [who].
create function pg_temp.bot_send(who text, chan text, content text, comps jsonb default null)
returns uuid language plpgsql as $$
declare r uuid;
begin
  r := public.bot_api_send_message_with_components(pg_temp.tok(who), pg_temp.i(chan), content, null, comps);
  return r;
end $$;
grant execute on all functions in schema pg_temp to public;

-- ===================================== 1. the checker of components
do $$
declare
  ok jsonb;
  bad text;
begin
  ok := public.normalize_message_components(pg_temp.sample());
  perform pg_temp.expect(jsonb_array_length(ok) = 3, 'a sample with three rows passes');
  perform pg_temp.expect(ok -> 0 -> 2 = '{"type":"link","label":"Docs","url":"https://example.com/docs?a=1#top"}'::jsonb, 'a link button passes as it is');
  perform pg_temp.expect(ok -> 1 -> 0 ->> 'min_values' = '1' and ok -> 1 -> 0 ->> 'max_values' = '2', 'a list keeps min and max');
  perform pg_temp.expect(ok -> 2 -> 0 -> 'modal' -> 'fields' -> 0 ->> 'required' = 'true', 'a form field is required unless said otherwise');
  perform pg_temp.expect(ok -> 0 -> 0 ->> 'style' = 'primary' and ok -> 0 -> 1 ->> 'style' = 'danger', 'button styles are kept');
  perform pg_temp.expect(public.normalize_message_components(null) is null and public.normalize_message_components('[]') is null and public.normalize_message_components('null') is null, 'nothing, an empty list and null are no components');
  perform pg_temp.expect(public.normalize_message_components('[[{"type":"button","id":"a","label":" Go ","style":"secondary","evil":"<script>","onclick":"x()"}]]') = '[[{"type":"button","id":"a","label":"Go","style":"secondary"}]]'::jsonb, 'unknown keys are dropped and labels trimmed');
  perform pg_temp.expect(public.normalize_message_components('[[{"type":"button","id":"a","label":"Go"}]]') -> 0 -> 0 ->> 'style' = 'secondary', 'a button is secondary by default');

  -- Things that must be refused, one sentence each.
  for bad in
    select unnest(array[
      '{}',
      '"x"',
      '[[{"type":"button","id":"a","label":"Go"}],[{"type":"button","id":"b","label":"Go"}],[{"type":"button","id":"c","label":"Go"}],[{"type":"button","id":"d","label":"Go"}],[{"type":"button","id":"e","label":"Go"}],[{"type":"button","id":"f","label":"Go"}]]',
      '[[]]',
      '["x"]',
      '[[{"type":"button","id":"a","label":"1"},{"type":"button","id":"b","label":"2"},{"type":"button","id":"c","label":"3"},{"type":"button","id":"d","label":"4"},{"type":"button","id":"e","label":"5"},{"type":"button","id":"f","label":"6"}]]',
      '[[{"type":"button","id":"a","label":""}]]',
      '[[{"type":"button","id":"a","label":"   "}]]',
      '[[{"type":"button","id":"a"}]]',
      '[[{"type":"button","id":"a","label":"0123456789012345678901234567890123456789X"}]]',
      '[[{"type":"button","id":"a","label":"two\nlines"}]]',
      '[[{"type":"button","id":"a","label":"bidi ‮ text"}]]',
      '[[{"type":"button","id":"a","label":"zero​width"}]]',
      '[[{"type":"button","id":"a b","label":"Go"}]]',
      '[[{"type":"button","id":"","label":"Go"}]]',
      '[[{"type":"button","id":"a","label":"Go"},{"type":"button","id":"a","label":"Again"}]]',
      '[[{"type":"button","id":"a","label":"Go","style":"huge"}]]',
      '[[{"type":"button","id":"a","label":"Go","disabled":"yes"}]]',
      '[[{"type":"popup","id":"a","label":"Go"}]]',
      '[[{"type":"link","label":"Go","url":"javascript:alert(1)"}]]',
      '[[{"type":"link","label":"Go","url":"JavaScript:alert(1)"}]]',
      '[[{"type":"link","label":"Go","url":"data:text/html,hi"}]]',
      '[[{"type":"link","label":"Go","url":"http://example.com/"}]]',
      '[[{"type":"link","label":"Go","url":"https://127.0.0.1/"}]]',
      '[[{"type":"link","label":"Go","url":"https://10.0.0.5/admin"}]]',
      '[[{"type":"link","label":"Go","url":"https://localhost/"}]]',
      '[[{"type":"link","label":"Go","url":"https://[::1]/"}]]',
      '[[{"type":"link","label":"Go","url":"https://example.com:8443/"}]]',
      '[[{"type":"link","label":"Go","url":"https://user:pw@example.com/"}]]',
      '[[{"type":"link","label":"Go","url":"https://paypal.com@evil.example/"}]]',
      '[[{"type":"link","label":"Go","url":"https://intranet.internal/"}]]',
      '[[{"type":"link","label":"Go","url":"https://printer.local/"}]]',
      '[[{"type":"link","label":"Go","url":"https://example.com/a b"}]]',
      '[[{"type":"link","label":"Go","url":"https://example.com/\"onmouseover=x"}]]',
      '[[{"type":"link","label":"Go","url":"https://example.com/<script>"}]]',
      '[[{"type":"link","label":"Go","url":"https://example.com\\@evil.example/"}]]',
      '[[{"type":"link","label":"Go"}]]',
      '[[{"type":"link","label":"Go","url":5}]]',
      '[[{"type":"select","id":"s","options":[]}]]',
      '[[{"type":"select","id":"s"}]]',
      '[[{"type":"select","id":"s","options":[{"label":"A","value":"a"},{"label":"B","value":"a"}]}]]',
      '[[{"type":"select","id":"s","options":[{"label":"A","value":"a"}],"max_values":2}]]',
      '[[{"type":"select","id":"s","options":[{"label":"A","value":"a"},{"label":"B","value":"b"}],"min_values":2,"max_values":1}]]',
      '[[{"type":"select","id":"s","options":[{"label":"A","value":"a"}]},{"type":"button","id":"b","label":"Go"}]]',
      '[[{"type":"button","id":"a","label":"Go","modal":{"title":"T","fields":[]}}]]',
      '[[{"type":"button","id":"a","label":"Go","modal":{"title":"T","fields":[{"id":"x","label":"X"},{"id":"x","label":"Y"}]}}]]',
      '[[{"type":"button","id":"a","label":"Go","modal":{"title":"","fields":[{"id":"x","label":"X"}]}}]]',
      '[[{"type":"button","id":"a","label":"Go","modal":{"title":"T","fields":[{"id":"x","label":"X","max_length":5000}]}}]]',
      '[[{"type":"button","id":"a","label":"Go","modal":{"title":"T","fields":[{"id":"x","label":"X","style":"rich"}]}}]]'
    ])
  loop
    perform pg_temp.expect(pg_temp.state(format('select public.normalize_message_components(%L::jsonb)', bad)) = '22023', 'refused: ' || left(bad, 90));
  end loop;

  -- 26 options, 5 rows of 5 is 25 (fine), but 26 select options are not.
  perform pg_temp.expect(pg_temp.state(format('select public.normalize_message_components(%L::jsonb)',
    (select jsonb_build_array(jsonb_build_array(jsonb_build_object('type','select','id','s','options',
      (select jsonb_agg(jsonb_build_object('label','o'||g,'value','v'||g)) from generate_series(1,26) g)))))::text)) = '22023', 'more than 25 options are refused');
  perform pg_temp.expect(public.normalize_message_components(
    (select jsonb_agg(row) from (select (select jsonb_agg(jsonb_build_object('type','button','id','b'||r||c,'label','L')) from generate_series(1,5) c) as row from generate_series(1,5) r) q)
  ) is not null, '5 rows of 5 buttons pass');
  -- The whole thing is at most 8 KB.
  perform pg_temp.expect(pg_temp.state(format('select public.normalize_message_components(%L::jsonb)',
    (select jsonb_build_array(jsonb_build_array(jsonb_build_object('type','select','id','s','options',
      (select jsonb_agg(jsonb_build_object('label',repeat('x',100),'value',repeat('y',99)||g,'description',repeat('z',100))) from generate_series(1,25) g)))))::text)) = '22023', 'over 8 KB is refused');
  perform pg_temp.expect(public.components_https_url_ok('https://example.com') and public.components_https_url_ok('https://sub.example.co.uk:443/a/b?c=d#e') and public.components_https_url_ok('HTTPS://Example.COM/x'), 'good https links pass');
  perform pg_temp.expect(not public.components_https_url_ok('https://example') and not public.components_https_url_ok('https://example.com:80/') and not public.components_https_url_ok('ftp://example.com/') and not public.components_https_url_ok('//example.com/') and not public.components_https_url_ok('https://0x7f.1/') and not public.components_https_url_ok('https://2130706433/') and not public.components_https_url_ok(null), 'bad links do not');
  perform pg_temp.expect(public.message_components_text(ok) like '%Approve%' and public.message_components_text(ok) like '%Ridge%' and public.message_components_text(ok) like '%Your note%' and public.message_components_text(ok) like '%Pick a trail%', 'AutoMod can read every text in the components');
end $$;

-- ===================================== 2. who may put components on a message
do $$
declare
  m1 uuid;
  m2 uuid;
  sample jsonb := pg_temp.sample();
begin
  -- A bot sends text with components in one write.
  m1 := pg_temp.bot_send('helper', 'plaza', 'Pick one', sample);
  insert into pg_temp.ids values ('m1', m1);
  perform pg_temp.expect(m1 is not null, 'a bot can send a message with components');
  perform pg_temp.expect((select jsonb_array_length(components) from public.messages where id = m1) = 3, 'the components are stored with the message');
  perform pg_temp.expect((select components -> 0 -> 0 ->> 'id' from public.messages where id = m1) = 'approve', 'in the cleaned form');
  perform pg_temp.expect((select type from public.messages where id = m1) = 'text' and (select sender_id from public.messages where id = m1) = pg_temp.i('helper_user'), 'it is a plain text message from the bot');
  perform pg_temp.expect(nullif(current_setting('wecord.message_components', true), '') is null, 'the hand-over setting is cleared after the send');

  -- A plain send is untouched, and the old function still has no components.
  m2 := public.bot_api_send_message(pg_temp.tok('helper'), pg_temp.i('plaza'), 'Plain');
  insert into pg_temp.ids values ('m2', m2);
  perform pg_temp.expect((select components from public.messages where id = m2) is null, 'a message without components has none');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_message_with_components(%L, %L, %L, null, %L::jsonb)', pg_temp.tok('helper'), pg_temp.i('plaza'), 'x', '[[{"type":"link","label":"x","url":"javascript:alert(1)"}]]')) = '22023', 'a bad component is refused and nothing is sent');
  perform pg_temp.expect((select count(*) from public.messages where body = 'x' and sender_id = pg_temp.i('helper_user')) = 0, 'nothing was stored by the refused send');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_message_with_components(%L, %L, %L, null, null)', pg_temp.tok('helper'), pg_temp.i('plaza'), '')) = '22023', 'the text is still required');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_message_with_components(%L, %L, %L, null, null)', 'nope', pg_temp.i('plaza'), 'x')) = '28000', 'a wrong token is refused');

  -- Everyone else is refused: no member, no other table writer.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format($q$insert into public.messages (conversation_id, sender_id, type, body, components) values (%L, %L, 'text', 'hi', '[[{"type":"button","id":"a","label":"Go"}]]')$q$, pg_temp.i('plaza_conv'), pg_temp.i('bob'))) = '42501', 'a member cannot write components');
  perform pg_temp.expect(pg_temp.state(format($q$update public.messages set components = '[[{"type":"button","id":"a","label":"Go"}]]' where id = %L$q$, pg_temp.i('m2'))) in ('42501', 'ok') and (select components from public.messages where id = pg_temp.i('m2')) is null, 'nor add them to a message by update');
  perform pg_temp.act(pg_temp.i('helper_user'));
  perform pg_temp.expect(pg_temp.state(format($q$insert into public.messages (conversation_id, sender_id, type, body, components) values (%L, %L, 'text', 'hi', '[[{"type":"button","id":"a","label":"Go"}]]')$q$, pg_temp.i('plaza_conv'), pg_temp.i('helper_user'))) = '42501', 'even the bot''s own login cannot, outside the bot functions');
  perform pg_temp.root();
  -- The table's owner still cannot dress anything but a bot's text.
  perform pg_temp.expect(pg_temp.state(format($q$insert into public.messages (conversation_id, sender_id, type, body, components) values (%L, %L, 'text', 'hi', '[[{"type":"button","id":"a","label":"Go"}]]')$q$, pg_temp.i('plaza_conv'), pg_temp.i('bob'))) = '42501', 'a member''s message cannot have components, whoever writes it');
  perform pg_temp.expect(pg_temp.state(format($q$insert into public.messages (conversation_id, sender_id, type, body, attachment, components) values (%L, %L, 'system', 'Pinned something', '{}', '[[{"type":"button","id":"a","label":"Go"}]]')$q$, pg_temp.i('plaza_conv'), pg_temp.i('helper_user'))) = '42501', 'a bot cannot put components on a system line');
  perform pg_temp.expect(pg_temp.state(format($q$insert into public.messages (conversation_id, sender_id, type, body, webhook_name, components) values (%L, %L, 'text', 'hi', 'Hook', '[[{"type":"button","id":"a","label":"Go"}]]')$q$, pg_temp.i('plaza_conv'), pg_temp.i('helper_user'))) = '42501', 'nor on a webhook post');
  perform pg_temp.expect(pg_temp.state(format($q$insert into public.messages (conversation_id, sender_id, type, body, components) values (%L, %L, 'text', 'hi', '[[{"type":"button","id":"a","label":"Go","x":1}], 5]')$q$, pg_temp.i('plaza_conv'), pg_temp.i('helper_user'))) = '22023', 'what the server writes is checked again');
  perform pg_temp.expect(pg_temp.state(format($q$insert into public.messages (conversation_id, sender_id, type, body, components) values (%L, %L, 'text', 'hi', '{"a":1}')$q$, pg_temp.i('plaza_conv'), pg_temp.i('helper_user'))) in ('23514', '22023'), 'and components must be a list');

  -- A bot cannot send to a channel it cannot see.
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_send_message_with_components(%L, %L, %L, null, null)', pg_temp.tok('helper'), gen_random_uuid(), 'x')) = 'P0002', 'an unknown channel is not found');
end $$;

-- ===================================== 3. AutoMod reads the buttons
do $$
declare
  rule uuid;
  sent uuid;
begin
  insert into public.circle_automod_rules (circle_id, name, kind, keywords, block_message)
  values (pg_temp.i('club'), 'no-spam-words', 'keyword', array['cheapmeds'], true)
  returning id into rule;
  sent := public.bot_api_send_message_with_components(pg_temp.tok('helper'), pg_temp.i('plaza'), 'Hello there',
    null, '[[{"type":"button","id":"a","label":"Buy cheapmeds now"}]]');
  perform pg_temp.expect(sent is null, 'a blocked word on a button stops the message quietly');
  sent := public.bot_api_send_message_with_components(pg_temp.tok('helper'), pg_temp.i('plaza'), 'Hello there',
    null, '[[{"type":"select","id":"s","options":[{"label":"ok","value":"v","description":"cheapmeds"}]}]]');
  perform pg_temp.expect(sent is null, 'also in an option description');
  sent := public.bot_api_send_message_with_components(pg_temp.tok('helper'), pg_temp.i('plaza'), 'Hello there',
    null, '[[{"type":"button","id":"a","label":"Open","modal":{"title":"cheapmeds","fields":[{"id":"x","label":"X"}]}}]]');
  perform pg_temp.expect(sent is null, 'also in a form title');
  sent := public.bot_api_send_message_with_components(pg_temp.tok('helper'), pg_temp.i('plaza'), 'cheapmeds in the text',
    null, '[[{"type":"button","id":"a","label":"Open"}]]');
  perform pg_temp.expect(sent is null, 'the text is checked as before');
  sent := public.bot_api_send_message_with_components(pg_temp.tok('helper'), pg_temp.i('plaza'), 'Fine',
    null, '[[{"type":"button","id":"a","label":"Open"}]]');
  perform pg_temp.expect(sent is not null, 'and a clean message goes through');
  insert into pg_temp.ids values ('m_clean', sent);
  delete from public.circle_automod_rules where id = rule;
end $$;

-- ===================================== 4. a bot changes its own message
do $$
declare
  m1 uuid := pg_temp.i('m1');
  ok boolean;
begin
  ok := public.bot_api_edit_message(pg_temp.tok('helper'), m1, null, true, '[[{"type":"button","id":"done","label":"Done","disabled":true}]]');
  perform pg_temp.expect(ok, 'a bot can change only the components');
  perform pg_temp.expect((select components -> 0 -> 0 ->> 'id' from public.messages where id = m1) = 'done' and (select body from public.messages where id = m1) = 'Pick one' and (select edited_at from public.messages where id = m1) is null, 'the text and the edited mark stay');
  ok := public.bot_api_edit_message(pg_temp.tok('helper'), m1, 'Picked: ridge', false, null);
  perform pg_temp.expect(ok and (select body from public.messages where id = m1) = 'Picked: ridge' and (select edited_at from public.messages where id = m1) is not null, 'or only the text');
  perform pg_temp.expect((select components -> 0 -> 0 ->> 'id' from public.messages where id = m1) = 'done', 'which leaves the components');
  perform pg_temp.expect(exists (select 1 from public.message_edits where message_id = m1), 'the edit history trigger saw the change of text');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_edit_message(%L, %L, null, false, null)', pg_temp.tok('helper'), m1)) = '22023', 'a change must change something');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_edit_message(%L, %L, null, true, %L::jsonb)', pg_temp.tok('other'), m1, '[[{"type":"button","id":"x","label":"Hijack"}]]')) = 'P0002', 'another bot cannot change it');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_edit_message(%L, %L, null, true, %L::jsonb)', pg_temp.tok('helper'), pg_temp.i('m2'), '[[{"type":"button","id":"x","label":"Late"}]]')) = 'ok', 'a bot can add components to its own plain message later');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_edit_message(%L, %L, null, true, %L::jsonb)', pg_temp.tok('helper'), pg_temp.i('m2'), '[[{"type":"link","label":"x","url":"javascript:1"}]]')) = '22023', 'and what it adds is checked');
  ok := public.bot_api_edit_message(pg_temp.tok('helper'), pg_temp.i('m2'), null, true, '[]'::jsonb);
  perform pg_temp.expect(ok and (select components from public.messages where id = pg_temp.i('m2')) is null, 'an empty list removes the components');
  ok := public.bot_api_edit_message(pg_temp.tok('helper'), pg_temp.i('m2'), null, true, null);
  perform pg_temp.expect(ok, 'so does null');
  -- Somebody else's message.
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_edit_message(%L, %L, %L, false, null)', pg_temp.tok('helper'), (select id from public.messages where sender_id = pg_temp.i('ada') limit 1), 'x')) = 'P0002' or not exists (select 1 from public.messages where sender_id = pg_temp.i('ada')), 'a bot cannot change a member''s message');
  -- AutoMod on an edit of the text.
  declare rule uuid;
  begin
    insert into public.circle_automod_rules (circle_id, name, kind, keywords, block_message)
    values (pg_temp.i('club'), 'bad', 'keyword', array['cheapmeds'], true) returning id into rule;
    ok := public.bot_api_edit_message(pg_temp.tok('helper'), m1, 'now cheapmeds', false, null);
    perform pg_temp.expect(not ok and (select body from public.messages where id = m1) = 'Picked: ridge', 'AutoMod refuses an edit to the text quietly');
    ok := public.bot_api_edit_message(pg_temp.tok('helper'), m1, null, true, '[[{"type":"button","id":"done","label":"cheapmeds"}]]');
    perform pg_temp.expect(not ok, 'and to the buttons');
    delete from public.circle_automod_rules where id = rule;
  end;
  -- Deleting the message drops its components.
  insert into pg_temp.ids select 'm_del', public.bot_api_send_message_with_components(pg_temp.tok('helper'), pg_temp.i('plaza'), 'bye', null, '[[{"type":"button","id":"a","label":"Go"}]]');
  update public.messages set recalled_at = now() where id = pg_temp.i('m_del');
  perform pg_temp.expect((select components from public.messages where id = pg_temp.i('m_del')) is null, 'a deleted message loses its components');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_edit_message(%L, %L, %L, false, null)', pg_temp.tok('helper'), pg_temp.i('m_del'), 'back')) = 'P0002', 'and cannot be changed');
end $$;

-- ===================================== 5. pressing a component
create function pg_temp.press(who text, msg text, comp text, vals jsonb default null)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.act(pg_temp.i(who));
  r := public.submit_interaction(pg_temp.i(msg), comp, vals);
  perform pg_temp.root();
  return r;
end $$;
-- The SQLSTATE of a press by [who].
create function pg_temp.press_state(who text, msg text, comp text, vals jsonb default null)
returns text language plpgsql as $$
declare r text;
begin
  perform pg_temp.act(pg_temp.i(who));
  begin
    perform public.submit_interaction(pg_temp.i(msg), comp, vals);
    r := 'ok';
  exception when others then
    r := sqlstate;
  end;
  perform pg_temp.root();
  return r;
end $$;
grant execute on all functions in schema pg_temp to public;

-- A fresh message with the sample for these checks (m1 was changed above).
do $$
begin
  insert into pg_temp.ids select 'mc', pg_temp.bot_send('helper', 'plaza', 'Choose', pg_temp.sample());
  insert into pg_temp.ids select 'mv', pg_temp.bot_send('helper', 'vault', 'Secret choice', pg_temp.sample());
end $$;

do $$
declare
  r jsonb;
  row_ public.bot_interactions%rowtype;
begin
  -- A button.
  r := pg_temp.press('bob', 'mc', 'approve');
  perform pg_temp.expect(r ? 'interaction_id' and r->>'bot_name' = 'Helper', 'a member presses a button');
  select * into row_ from public.bot_interactions where id = (r->>'interaction_id')::uuid;
  perform pg_temp.expect(row_.kind = 'component' and row_.user_id = pg_temp.i('bob') and row_.message_id = pg_temp.i('mc') and row_.component_id = 'approve' and row_.component_type = 'button' and row_.component_label = 'Approve' and row_.submitted is null, 'it is an interaction of the bot with the right fields');
  perform pg_temp.expect(row_.command_name is null and row_.bot_id = pg_temp.i('helper') and row_.channel_id = pg_temp.i('plaza') and row_.conversation_id = pg_temp.i('plaza_conv'), 'for the bot, in the channel');
  perform pg_temp.expect(row_.delivery_state = 'none' and (r->>'by_callback')::boolean = false, 'without a callback it waits for a poll');
  perform pg_temp.expect(row_.expires_at > now() + interval '14 minutes', 'for 15 minutes');

  -- One a second.
  perform pg_temp.expect(pg_temp.press_state('bob', 'mc', 'approve') = 'BT429', 'pressing the same button twice in a second is held back');
  perform pg_temp.expect(pg_temp.press_state('cat', 'mc', 'approve') = 'ok', 'another person is not');
  perform pg_temp.expect(pg_temp.press_state('bob', 'mc', 'reject') = 'ok', 'nor another button');

  -- A list.
  r := pg_temp.press('bob', 'mc', 'pick', '["ridge","forest"]');
  select * into row_ from public.bot_interactions where id = (r->>'interaction_id')::uuid;
  perform pg_temp.expect(row_.component_type = 'select' and row_.submitted = '["ridge","forest"]'::jsonb, 'a list gives the chosen values');
  perform pg_temp.expect(pg_temp.press_state('dan', 'mc', 'pick', '[]') = '22023', 'too few choices');
  perform pg_temp.expect(pg_temp.press_state('dan', 'mc', 'pick', '["ridge","lake","forest"]') = '22023', 'too many');
  perform pg_temp.expect(pg_temp.press_state('dan', 'mc', 'pick', '["swamp"]') = '22023', 'an option that is not in the list');
  perform pg_temp.expect(pg_temp.press_state('dan', 'mc', 'pick', '["ridge","ridge"]') = '22023', 'the same option twice');
  perform pg_temp.expect(pg_temp.press_state('dan', 'mc', 'pick', '[1]') = '22023' and pg_temp.press_state('dan', 'mc', 'pick', 'null') = '22023' and pg_temp.press_state('dan', 'mc', 'pick', '{"a":1}') = '22023', 'wrong shapes');
  perform pg_temp.expect(pg_temp.press_state('dan', 'mc', 'pick', '["lake"]') = 'ok', 'one valid choice');
  perform pg_temp.expect(pg_temp.press_state('dan', 'mc', 'approve', '["x"]') = '22023', 'a button takes no values');

  -- A form.
  r := pg_temp.press('bob', 'mc', 'note', '{"text":"  line one\nline two ","name":"Bob"}');
  select * into row_ from public.bot_interactions where id = (r->>'interaction_id')::uuid;
  perform pg_temp.expect(row_.component_type = 'modal' and row_.submitted = '{"text":"line one\nline two","name":"Bob"}'::jsonb, 'a form gives its fields, trimmed');
  perform pg_temp.expect(pg_temp.press_state('cat', 'mc', 'note', '{"name":"x"}') = '22023', 'a required field cannot be left empty');
  perform pg_temp.expect(pg_temp.press_state('cat', 'mc', 'note', jsonb_build_object('text', repeat('x', 51))) = '22023', 'an answer over its length');
  perform pg_temp.expect(pg_temp.press_state('cat', 'mc', 'note', '{"text":"ok","extra":"x"}') = '22023', 'a field the form does not have');
  perform pg_temp.expect(pg_temp.press_state('cat', 'mc', 'note', '{"text":5}') = '22023', 'an answer that is not text');
  perform pg_temp.expect(pg_temp.press_state('cat', 'mc', 'note', '{"text":"ok","name":"a\u0007b"}') = '22023', 'control characters in a short answer');
  perform pg_temp.expect(pg_temp.press_state('cat', 'mc', 'note', '{"text":"fine"}') = 'ok', 'the optional field can be left out');
  perform pg_temp.expect(pg_temp.press_state('cat', 'mc', 'note', null) = '22023', 'a form needs answers');

  -- Not a component, not pressable.
  perform pg_temp.expect(pg_temp.press_state('cat', 'mc', 'ghost') = 'P0002', 'an unknown component');
  perform pg_temp.expect(pg_temp.press_state('cat', 'mc', null) = 'P0002', 'no component');
  perform pg_temp.expect(pg_temp.press_state('cat', 'm2', 'approve') = 'P0002', 'a message without components');
  perform pg_temp.expect(pg_temp.press_state('cat', 'mc', 'Docs') = 'P0002', 'a link has no id to press');
  perform pg_temp.expect(pg_temp.press_state('cat', 'ada_msg', 'x') = 'P0002', 'an unknown message');
end $$;

-- Disabled components, links.
do $$
declare
  md uuid;
begin
  md := pg_temp.bot_send('helper', 'plaza', 'Closed', '[[{"type":"button","id":"off","label":"Off","disabled":true},{"type":"button","id":"on","label":"On"}]]');
  insert into pg_temp.ids values ('md', md);
  perform pg_temp.expect(pg_temp.press_state('bob', 'md', 'off') = '22023', 'a disabled button cannot be pressed');
  perform pg_temp.expect(pg_temp.press_state('bob', 'md', 'on') = 'ok', 'its neighbour can');
end $$;

-- ===================================== 6. only someone who can see the message
do $$
declare
  c integer;
begin
  perform pg_temp.expect(pg_temp.press_state('eve', 'mc', 'approve') = 'P0002', 'someone outside the circle cannot press, and cannot tell it exists');
  perform pg_temp.expect(pg_temp.press_state('eve', 'mc', 'ghost') = 'P0002', 'the same answer for a wrong component');
  perform pg_temp.expect(pg_temp.press_state('bob', 'mv', 'approve') = 'P0002', 'a member who cannot see the channel cannot press');
  perform pg_temp.expect(pg_temp.press_state('ada', 'mv', 'approve') = 'ok', 'a member who can, can');
  -- The anonymous role.
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select public.submit_interaction(%L, %L, null)', pg_temp.i('mc'), 'approve')) = '42501', 'nobody signed in is refused');
  perform pg_temp.root();

  -- Deleted, expired or waiting for the AI guard.
  insert into pg_temp.ids select 'mr', pg_temp.bot_send('helper', 'plaza', 'Recalled soon', '[[{"type":"button","id":"a","label":"A"}]]');
  update public.messages set recalled_at = now() where id = pg_temp.i('mr');
  perform pg_temp.expect(pg_temp.press_state('cat', 'mr', 'a') = 'P0002', 'a deleted message cannot be pressed');
  insert into pg_temp.ids select 'mx', pg_temp.bot_send('helper', 'plaza', 'Short lived', '[[{"type":"button","id":"a","label":"A"}]]');
  update public.messages set expires_at = now() - interval '1 minute' where id = pg_temp.i('mx');
  perform pg_temp.expect(pg_temp.press_state('cat', 'mx', 'a') = 'P0002', 'an expired disappearing message cannot');
  insert into pg_temp.ids select 'mh', pg_temp.bot_send('helper', 'plaza', 'Held', '[[{"type":"button","id":"a","label":"A"}]]');
  update public.messages set review_state = 'held' where id = pg_temp.i('mh');
  perform pg_temp.expect(pg_temp.press_state('cat', 'mh', 'a') = 'P0002', 'a message the AI guard holds cannot');
  update public.messages set review_state = null where id = pg_temp.i('mh');

  -- A suspended account (K1) and a blocked bot.
  insert into public.app_user_suspensions (user_id, reason) values (pg_temp.i('fay'), 'test');
  perform pg_temp.expect(pg_temp.press_state('fay', 'mc', 'approve') = '42501', 'a suspended account cannot press');
  delete from public.app_user_suspensions where user_id = pg_temp.i('fay');
  perform pg_temp.expect(pg_temp.press_state('fay', 'mc', 'approve') = 'ok', 'and can once it is lifted');
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('cat'), pg_temp.i('helper_user'));
  perform pg_temp.expect(pg_temp.press_state('cat', 'md', 'on') = '42501', 'someone who blocked the bot cannot use it');
  delete from public.blocks where blocker_id = pg_temp.i('cat');

  -- A suspended circle (K1): nothing is readable.
  update public.circles set disabled_at = now(), disabled_mode = 'suspend' where id = pg_temp.i('club');
  perform pg_temp.expect(pg_temp.press_state('dan', 'md', 'on') = 'P0002', 'a suspended circle takes no presses');
  update public.circles set disabled_at = null, disabled_mode = null where id = pg_temp.i('club');
  perform pg_temp.expect(pg_temp.press_state('dan', 'md', 'on') = 'ok', 'and takes them again');

  -- The bot is gone from the circle.
  insert into pg_temp.ids select 'mo', pg_temp.bot_send('other', 'plaza', 'Other bot', '[[{"type":"button","id":"a","label":"A"}]]');
  perform pg_temp.expect(pg_temp.press_state('bob', 'mo', 'a') = 'ok', 'another bot''s button works');
  delete from public.circle_members where circle_id = pg_temp.i('club') and user_id = pg_temp.i('other_user');
  perform pg_temp.expect(pg_temp.press_state('cat', 'mo', 'a') = 'P0002', 'a bot that left the circle takes no presses');
  insert into public.circle_members (circle_id, user_id, role, rules_accepted_at) values (pg_temp.i('club'), pg_temp.i('other_user'), 'member', now());
end $$;

-- ===================================== 7. limits
do $$
begin
  -- 30 presses a minute per person.
  insert into public.bot_interactions (kind, bot_id, circle_id, channel_id, conversation_id, user_id, message_id, component_id, component_type, component_label, responded_at)
  select 'component', pg_temp.i('helper'), pg_temp.i('club'), pg_temp.i('plaza'), pg_temp.i('plaza_conv'), pg_temp.i('fay'), pg_temp.i('mc'), 'filler' || g, 'button', 'f', now()
  from generate_series(1, 30) g;
  perform pg_temp.expect(pg_temp.press_state('fay', 'md', 'on') = 'BT429', 'more than 30 presses a minute are held back');
  delete from public.bot_interactions where component_id like 'filler%';
  perform pg_temp.expect(pg_temp.press_state('fay', 'md', 'on') = 'ok', 'and it passes when the minute is quiet');

  -- A bot with 200 unanswered presses takes no more.
  insert into public.bot_interactions (kind, bot_id, circle_id, channel_id, conversation_id, user_id, message_id, component_id, component_type, component_label)
  select 'component', pg_temp.i('other'), pg_temp.i('club'), pg_temp.i('plaza'), pg_temp.i('plaza_conv'), pg_temp.i('ada'), pg_temp.i('mo'), 'filler' || g, 'button', 'f'
  from generate_series(1, 200) g;
  perform pg_temp.expect(pg_temp.press_state('dan', 'mo', 'a') = 'BT429', 'a bot with 200 presses waiting is busy');
  delete from public.bot_interactions where component_id like 'filler%';
  perform pg_temp.expect(pg_temp.press_state('dan', 'mo', 'a') = 'ok', 'and is not once they are gone');
end $$;

-- ===================================== 8. the bot polls and answers
do $$
declare
  polled jsonb;
  item jsonb;
  picked uuid;
begin
  -- Only the bot's own presses.
  polled := public.bot_api_poll_interactions(pg_temp.tok('helper'), 100);
  perform pg_temp.expect(jsonb_array_length(polled) >= 5, 'the bot gets the presses waiting for it');
  perform pg_temp.expect((select bool_and(e ->> 'type' = 'component') from jsonb_array_elements(polled) e), 'each says it is a component press');
  select e into item from jsonb_array_elements(polled) e where e -> 'component' ->> 'id' = 'pick' and e -> 'values' = '["ridge","forest"]'::jsonb limit 1;
  perform pg_temp.expect(item is not null and item ->> 'message_id' = pg_temp.i('mc')::text and item ->> 'channel_id' = pg_temp.i('plaza')::text and item -> 'component' ->> 'type' = 'select' and (item -> 'ephemeral')::boolean = false, 'with the message, the channel, the component and the choice');
  perform pg_temp.expect(item -> 'user' ->> 'id' = pg_temp.i('bob')::text and item -> 'user' ->> 'username' = 'bob_i1', 'and who pressed');
  perform pg_temp.expect(item ? 'created_at' and item ? 'expires_at' and not item ? 'command', 'a press has no command');
  perform pg_temp.expect(jsonb_array_length(public.bot_api_poll_interactions(pg_temp.tok('helper'), 100)) = 0, 'a second poll finds nothing new');
  update public.bot_interactions set claimed_at = now() - interval '31 seconds' where id = (item ->> 'id')::uuid;
  perform pg_temp.expect(jsonb_array_length(public.bot_api_poll_interactions(pg_temp.tok('helper'), 100)) = 1, 'one that was not answered comes again after 30 seconds');
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(public.bot_api_poll_interactions(pg_temp.tok('other'), 100)) e where e ->> 'id' = item ->> 'id'), 'another bot never sees it');

  -- Slash commands still come the old way.
  insert into public.bot_commands (bot_id, circle_id, name, description) values (pg_temp.i('helper'), pg_temp.i('club'), 'ping', 'Pong');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.invoke_bot_command(pg_temp.i('plaza_conv'), 'ping', 'now');
  perform pg_temp.root();
  polled := public.bot_api_poll_interactions(pg_temp.tok('helper'), 100);
  select e into item from jsonb_array_elements(polled) e where e ->> 'type' = 'command';
  perform pg_temp.expect(item ->> 'command' = 'ping' and item ->> 'options' = 'now' and item -> 'user' ->> 'id' = pg_temp.i('cat')::text, 'a command keeps its old fields');
  insert into pg_temp.ids values ('cmd_interaction', (item ->> 'id')::uuid);
end $$;

-- ===================================== 9. the answers
create function pg_temp.pending(who text, msg text, comp text, vals jsonb default null)
returns uuid language plpgsql as $$
declare r jsonb;
begin
  r := pg_temp.press(who, msg, comp, vals);
  return (r ->> 'interaction_id')::uuid;
end $$;
create function pg_temp.respond_state(tok text, iid uuid, body jsonb)
returns text language plpgsql as $$
declare r text;
begin
  begin
    perform public.bot_api_respond(pg_temp.tok(tok), iid, body);
    r := 'ok';
  exception when others then
    r := sqlstate;
  end;
  return r;
end $$;
grant execute on all functions in schema pg_temp to public;

do $$
declare
  i1 uuid;
  i2 uuid;
  i3 uuid;
  i4 uuid;
  i5 uuid;
  mid uuid;
  eid uuid;
begin
  -- A public message: shows who pressed what.
  i1 := pg_temp.pending('ada', 'md', 'on');
  mid := public.bot_api_respond(pg_temp.tok('helper'), i1, '{"content":"Thanks Ada","components":[[{"type":"button","id":"again","label":"Again"}]]}');
  perform pg_temp.expect(mid is not null and (select body from public.messages where id = mid) = 'Thanks Ada' and (select components -> 0 -> 0 ->> 'id' from public.messages where id = mid) = 'again', 'a message answer is posted, with components if given');
  perform pg_temp.expect((select interaction ->> 'component_label' from public.messages where id = mid) = 'On' and (select interaction ->> 'user_name' from public.messages where id = mid) = 'Ada' and (select interaction ->> 'command' from public.messages where id = mid) = '', 'and says who pressed which button');
  perform pg_temp.expect((select responded_at is not null and response_kind = 'message' and response_message_id = mid from public.bot_interactions where id = i1), 'the press is marked answered');
  perform pg_temp.expect(pg_temp.respond_state('helper', i1, '{"content":"Again"}') = '23505', 'only one answer');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(public.interaction_status(i1) ->> 'status' = 'answered' and public.interaction_status(i1) ->> 'response_kind' = 'message', 'the person who pressed sees it answered');
  perform pg_temp.root();

  -- Another bot, another person: no.
  i2 := pg_temp.pending('cat', 'md', 'on');
  perform pg_temp.expect(pg_temp.respond_state('other', i2, '{"content":"mine"}') = 'P0002', 'another bot cannot answer it');
  i5 := (select id from public.bot_interactions where user_id = pg_temp.i('bob') and responded_at is null limit 1);
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.interaction_status(%L)', i2)) = 'P0002', 'nor can another person read its state');
  perform pg_temp.expect(public.interaction_status(i5) ->> 'status' = 'pending', 'but their own is pending');
  perform pg_temp.root();

  -- Bad answers.
  perform pg_temp.expect(pg_temp.respond_state('helper', i2, '{"type":"shout"}') = '22023', 'an unknown type');
  perform pg_temp.expect(pg_temp.respond_state('helper', i2, '{"content":""}') = '22023', 'a message needs text');
  perform pg_temp.expect(pg_temp.respond_state('helper', i2, jsonb_build_object('content', repeat('x', 2001))) = '22023', 'of 2000 characters at most');
  perform pg_temp.expect(pg_temp.respond_state('helper', i2, '{"type":"ack","content":"x"}') = '22023', 'an ack has no text');
  perform pg_temp.expect(pg_temp.respond_state('helper', i2, '{"content":"x","components":[[{"type":"link","label":"a","url":"javascript:1"}]]}') = '22023', 'components in an answer are checked');
  perform pg_temp.expect(pg_temp.respond_state('helper', i2, '"x"') = '22023' and pg_temp.respond_state('helper', i2, null) = '22023', 'the answer is an object');
  perform pg_temp.expect(pg_temp.respond_state('helper', gen_random_uuid(), '{"content":"x"}') = 'P0002', 'an unknown interaction');
  perform pg_temp.expect((select responded_at is null from public.bot_interactions where id = i2), 'none of that answered it');

  -- A private reply.
  mid := public.bot_api_respond(pg_temp.tok('helper'), i2, '{"type":"ephemeral","content":"Only for Cat","components":[[{"type":"button","id":"secret","label":"Secret"}]]}');
  perform pg_temp.expect(mid is not null and (select count(*) from public.messages where body = 'Only for Cat') = 0, 'a private reply is not a message');
  insert into pg_temp.ids values ('eph1', mid);
  perform pg_temp.expect((select user_id = pg_temp.i('cat') and message_id = pg_temp.i('md') and conversation_id = pg_temp.i('plaza_conv') and bot_id = pg_temp.i('helper') from public.bot_ephemeral_messages where id = mid), 'it is the presser''s, in this chat, from this bot');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.bot_ephemeral_messages') = 1, 'the person reads their own private reply');
  perform pg_temp.expect(jsonb_array_length(public.list_my_ephemeral_messages(pg_temp.i('plaza_conv'))) = 1 and public.list_my_ephemeral_messages(pg_temp.i('plaza_conv')) -> 0 ->> 'bot_name' = 'Helper', 'the list names the bot');
  perform pg_temp.root();
  foreach eid in array array[pg_temp.i('ada'), pg_temp.i('bob'), pg_temp.i('dan'), pg_temp.i('eve')] loop
    perform pg_temp.act(eid);
    perform pg_temp.expect(pg_temp.cnt('select 1 from public.bot_ephemeral_messages') = 0, 'nobody else reads it (' || (select username from public.profiles where id = eid) || ')');
    perform pg_temp.expect(jsonb_array_length(public.list_my_ephemeral_messages(pg_temp.i('plaza_conv'))) = 0, 'and the list is empty for them');
    perform pg_temp.root();
  end loop;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format($q$update public.bot_ephemeral_messages set body = 'x'$q$)) in ('42501', 'ok') and (select count(*) from public.bot_ephemeral_messages) = 0, 'a member cannot change them');
  perform pg_temp.expect(pg_temp.refused(format($q$insert into public.bot_ephemeral_messages (bot_id, conversation_id, user_id, body) values (%L, %L, %L, 'x')$q$, pg_temp.i('helper'), pg_temp.i('plaza_conv'), pg_temp.i('bob'))), 'or write one');
  perform pg_temp.root();
  -- Pressing a button of a private reply goes to the bot, with the message it hangs on.
  i3 := pg_temp.pending('cat', 'eph1', 'secret');
  perform pg_temp.expect((select ephemeral_id = pg_temp.i('eph1') and message_id = pg_temp.i('md') and conversation_id = pg_temp.i('plaza_conv') from public.bot_interactions where id = i3), 'a press on a private reply is for the bot with its message');
  perform pg_temp.expect((select (e -> 'ephemeral')::boolean and e ->> 'message_id' = pg_temp.i('md')::text from jsonb_array_elements(public.bot_api_poll_interactions(pg_temp.tok('helper'), 100)) e where e ->> 'id' = i3::text), 'and the bot is told it was a private one');
  perform pg_temp.expect(pg_temp.press_state('bob', 'eph1', 'secret') = 'P0002', 'nobody else can press it');
  -- Update the private reply in place.
  perform pg_temp.expect(public.bot_api_respond(pg_temp.tok('helper'), i3, '{"type":"update","content":"Changed for Cat","components":[]}') = pg_temp.i('eph1'), 'an update changes the private reply');
  perform pg_temp.expect((select body = 'Changed for Cat' and components is null from public.bot_ephemeral_messages where id = pg_temp.i('eph1')), 'its text and components');
  -- Dismiss.
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.dismiss_ephemeral_message(pg_temp.i('eph1'));
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.bot_ephemeral_messages where id = pg_temp.i('eph1')), 'someone else cannot dismiss it');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.dismiss_ephemeral_message(pg_temp.i('eph1'));
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.bot_ephemeral_messages where id = pg_temp.i('eph1')), 'the person can');

  -- Update the message pressed on.
  i4 := pg_temp.pending('dan', 'mc', 'reject');
  mid := public.bot_api_respond(pg_temp.tok('helper'), i4, '{"type":"update","content":"Rejected by Dan","components":[[{"type":"button","id":"undo","label":"Undo"}]]}');
  perform pg_temp.expect(mid = pg_temp.i('mc') and (select body from public.messages where id = pg_temp.i('mc')) = 'Rejected by Dan' and (select components -> 0 -> 0 ->> 'id' from public.messages where id = pg_temp.i('mc')) = 'undo', 'an update changes the message the person pressed on');
  perform pg_temp.expect((select response_kind = 'update' and response_message_id is null from public.bot_interactions where id = i4), 'and is noted as an update');
  perform pg_temp.expect(pg_temp.press_state('bob', 'mc', 'approve') = 'P0002', 'the old buttons are gone');
  i5 := pg_temp.pending('bob', 'mc', 'undo');
  perform pg_temp.expect(pg_temp.respond_state('helper', i5, '{"type":"update"}') = '22023', 'an update changes something');
  mid := public.bot_api_respond(pg_temp.tok('helper'), i5, '{"type":"ack"}');
  perform pg_temp.expect(mid is null and (select response_kind from public.bot_interactions where id = i5) = 'ack', 'an ack answers without showing anything');
  -- A press on a message the bot may not change (somebody else''s message).
  -- Commands: only messages.
  perform pg_temp.expect(pg_temp.respond_state('helper', pg_temp.i('cmd_interaction'), '{"type":"ephemeral","content":"x"}') = '22023', 'a slash command is answered with a message');
  mid := public.bot_api_respond(pg_temp.tok('helper'), pg_temp.i('cmd_interaction'), '{"content":"pong","components":[[{"type":"button","id":"p","label":"Pong"}]]}');
  perform pg_temp.expect(mid is not null and (select interaction ->> 'command' = 'ping' and interaction ->> 'user_name' = 'Cat' and components is not null from public.messages where id = mid), 'which can carry components and says who used which command');
  insert into pg_temp.ids select 'mn', pg_temp.bot_send('helper', 'plaza', 'Fresh', '[[{"type":"button","id":"go","label":"Go"}]]');
  i1 := pg_temp.pending('bob', 'mn', 'go');
  perform pg_temp.expect(pg_temp.state(format('select public.bot_api_respond_interaction(%L, %L, %L)', pg_temp.tok('helper'), i1, 'old way')) = '22023', 'the old answer function refuses a press');
  insert into pg_temp.ids values ('cmd2', gen_random_uuid());
  perform pg_temp.act(pg_temp.i('dan'));
  perform public.invoke_bot_command(pg_temp.i('plaza_conv'), 'ping', '');
  perform pg_temp.root();
  perform pg_temp.expect(public.bot_api_respond_interaction(pg_temp.tok('helper'), (select id from public.bot_interactions where kind = 'command' and user_id = pg_temp.i('dan')), 'old pong') is not null, 'but still answers a command');
end $$;

-- ===================================== 10. where a bot wants presses sent
create function pg_temp.set_cb(who text, bot text, url text)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.act(pg_temp.i(who));
  r := public.set_bot_callback(pg_temp.i(bot), url);
  perform pg_temp.root();
  return r;
end $$;
create function pg_temp.cb_state(who text, stmt text)
returns text language plpgsql as $$
declare r text;
begin
  perform pg_temp.act(pg_temp.i(who));
  begin
    execute stmt;
    r := 'ok';
  exception when others then
    r := sqlstate;
  end;
  perform pg_temp.root();
  return r;
end $$;
grant execute on all functions in schema pg_temp to public;

do $$
declare
  bad text;
  r jsonb;
  claimed jsonb;
  item jsonb;
  iid uuid;
  iid2 uuid;
  secret1 text;
  n integer;
begin
  -- Addresses that must be refused (SSRF).
  for bad in
    select unnest(array[
      'http://example.com/hook', 'ftp://example.com/', 'example.com/hook', '', ' ', 'https://', 'https:///hook',
      'https://localhost/hook', 'https://LOCALHOST/hook', 'https://localhost.localdomain/hook',
      'https://127.0.0.1/hook', 'https://127.1/hook', 'https://0.0.0.0/', 'https://10.1.2.3/', 'https://172.16.0.1/',
      'https://192.168.1.1/', 'https://169.254.169.254/latest/meta-data/', 'https://100.64.0.1/', 'https://2130706433/',
      'https://0x7f000001/', 'https://017700000001/', 'https://[::1]/', 'https://[::ffff:127.0.0.1]/', 'https://[fe80::1]/',
      'https://metadata.google.internal/', 'https://router.local/', 'https://nas.lan/', 'https://db.corp/', 'https://x.home/',
      'https://app.intranet/', 'https://svc.private/', 'https://1.0.0.127.in-addr.arpa/', 'https://foo.localhost/',
      'https://127.0.0.1.nip.io/', 'https://10.0.0.1.sslip.io/', 'https://anything.localtest.me/',
      'https://example.com:8080/hook', 'https://example.com:22/', 'https://example.com:443:80/',
      'https://user@example.com/hook', 'https://user:pw@example.com/hook', 'https://example.com\@evil.example/',
      'https://exa mple.com/', 'https://example.com/a b', 'https://exam_ple.com/', 'https://-bad.example.com/',
      'https://example.com/%0d%0aInjected: 1'
    ])
  loop
    perform pg_temp.expect(public.bot_callback_url_problem(bad) is not null, 'address refused: ' || bad);
  end loop;
  -- The one with the encoded line break is only a path; it is fine, say so.
  perform pg_temp.expect(public.bot_callback_url_problem('https://example.com/hook') is null and public.bot_callback_url_problem('https://bots.example.co.uk/wecord/hook?token=abc') is null and public.bot_callback_url_problem('https://example.com:443/hook') is null, 'ordinary https addresses pass');
  perform pg_temp.expect(public.bot_callback_url_problem('https://example.com/' || repeat('a', 500)) is not null, 'a long address is refused');

  -- Only managers.
  perform pg_temp.expect(pg_temp.cb_state('bob', format('select public.set_bot_callback(%L, %L)', pg_temp.i('helper'), 'https://example.com/hook')) = '42501', 'a member cannot set a callback');
  perform pg_temp.expect(pg_temp.cb_state('eve', format('select public.get_bot_callback(%L)', pg_temp.i('helper'))) = '42501', 'nor read one');
  perform pg_temp.expect(pg_temp.cb_state('ada', format('select public.set_bot_callback(%L, %L)', pg_temp.i('helper'), 'https://127.0.0.1/hook')) = '22023', 'the manager is told the address is not allowed');
  perform pg_temp.expect(not exists (select 1 from public.bot_callbacks), 'nothing was saved');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select public.set_bot_callback(%L, %L)', pg_temp.i('helper'), 'https://example.com/hook')) in ('42501', '42883'), 'nobody signed in cannot');
  perform pg_temp.root();

  -- Set.
  r := pg_temp.set_cb('ada', 'helper', 'https://example.com/hook');
  secret1 := r ->> 'secret';
  perform pg_temp.expect(secret1 ~ '^[0-9a-f]{64}$' and r ->> 'url' = 'https://example.com/hook' and (r ->> 'enabled')::boolean, 'the first time a secret is made and shown');
  perform pg_temp.expect((select secret from public.bot_callbacks where bot_id = pg_temp.i('helper')) = secret1, 'and kept');
  r := pg_temp.set_cb('ada', 'helper', 'https://example.com/hook2');
  perform pg_temp.expect(not r ? 'secret' and (select secret = secret1 and url = 'https://example.com/hook2' from public.bot_callbacks where bot_id = pg_temp.i('helper')), 'changing the address keeps the secret and does not show it');
  perform pg_temp.act(pg_temp.i('ada'));
  r := public.get_bot_callback(pg_temp.i('helper'));
  perform pg_temp.root();
  perform pg_temp.expect(r ->> 'url' = 'https://example.com/hook2' and not r ? 'secret' and not r::text like '%' || secret1 || '%', 'the secret is never read back');
  perform pg_temp.expect(exists (select 1 from public.circle_audit_log where circle_id = pg_temp.i('club') and action = 'bot_callback_set') and not exists (select 1 from public.circle_audit_log where circle_id = pg_temp.i('club') and changes::text like '%' || secret1 || '%'), 'the change is in the audit log, without the secret');
  perform pg_temp.expect(not has_table_privilege('authenticated', 'public.bot_callbacks', 'select') and not has_table_privilege('anon', 'public.bot_callbacks', 'select'), 'clients cannot read the table');

  -- Presses are queued for the callback.
  insert into pg_temp.ids select 'mq', pg_temp.bot_send('helper', 'plaza', 'Queue', '[[{"type":"button","id":"q1","label":"Q1"},{"type":"button","id":"q2","label":"Q2"}]]');
  r := pg_temp.press('bob', 'mq', 'q1');
  iid := (r ->> 'interaction_id')::uuid;
  perform pg_temp.expect((r ->> 'by_callback')::boolean and (select delivery_state = 'queued' and next_attempt_at is not null from public.bot_interactions where id = iid), 'with a callback a press is queued and the person is told');
  perform pg_temp.expect(jsonb_array_length(public.bot_api_poll_interactions(pg_temp.tok('helper'), 100)) = 0 or not exists (select 1 from jsonb_array_elements(public.bot_api_poll_interactions(pg_temp.tok('helper'), 100)) e where e ->> 'id' = iid::text), 'a queued press is not handed out by a poll');
  -- A slash command too.
  perform pg_temp.act(pg_temp.i('fay'));
  perform public.invoke_bot_command(pg_temp.i('plaza_conv'), 'ping', 'cb');
  perform pg_temp.root();
  iid2 := (select id from public.bot_interactions where user_id = pg_temp.i('fay') and kind = 'command');
  perform pg_temp.expect((select delivery_state from public.bot_interactions where id = iid2) = 'queued', 'commands go to the callback as well');

  -- The function claims them.
  perform pg_temp.expect(pg_temp.cb_state('bob', 'select public.claim_bot_callbacks(10)') = '42501', 'members cannot claim');
  claimed := public.claim_bot_callbacks(10);
  select e into item from jsonb_array_elements(claimed) e where e ->> 'interaction_id' = iid::text;
  perform pg_temp.expect(jsonb_array_length(claimed) = 2 and item ->> 'url' = 'https://example.com/hook2' and item ->> 'secret' = secret1 and (item ->> 'attempt')::int = 1, 'the claim carries the address, the secret and the attempt');
  perform pg_temp.expect(item -> 'payload' ->> 'type' = 'component' and item -> 'payload' -> 'component' ->> 'id' = 'q1' and item -> 'payload' -> 'user' ->> 'username' = 'bob_i1' and item ->> 'bot_id' = pg_temp.i('helper')::text, 'and what the bot gets');
  perform pg_temp.expect(jsonb_array_length(public.claim_bot_callbacks(10)) = 0, 'a claimed press is not claimed again for 30 seconds');
  perform pg_temp.expect((select delivery_state = 'sending' and next_attempt_at > now() + interval '25 seconds' from public.bot_interactions where id = iid), 'it is a lease');

  -- A failure is tried again, with a pause, four times, then goes to polling.
  perform public.finish_bot_callback(iid, false, 500, 'HTTP 500');
  perform pg_temp.expect((select delivery_state = 'queued' and next_attempt_at between now() + interval '4 seconds' and now() + interval '6 seconds' and delivery_error = 'HTTP 500' from public.bot_interactions where id = iid), 'a failure is queued again after 5 seconds');
  update public.bot_interactions set next_attempt_at = now() where id = iid;
  claimed := public.claim_bot_callbacks(10);
  perform pg_temp.expect((claimed -> 0 ->> 'attempt')::int = 2, 'the second try');
  perform public.finish_bot_callback(iid, false, null, 'timeout');
  perform pg_temp.expect((select next_attempt_at between now() + interval '29 seconds' and now() + interval '31 seconds' from public.bot_interactions where id = iid), 'then after 30 seconds');
  update public.bot_interactions set next_attempt_at = now() where id = iid;
  perform public.claim_bot_callbacks(10);
  perform public.finish_bot_callback(iid, false, null, 'timeout');
  perform pg_temp.expect((select next_attempt_at between now() + interval '119 seconds' and now() + interval '121 seconds' from public.bot_interactions where id = iid), 'then after two minutes');
  update public.bot_interactions set next_attempt_at = now() where id = iid;
  claimed := public.claim_bot_callbacks(10);
  perform pg_temp.expect((claimed -> 0 ->> 'attempt')::int = 4, 'the fourth try is the last');
  perform public.finish_bot_callback(iid, false, 502, 'bad gateway');
  perform pg_temp.expect((select delivery_state = 'failed' from public.bot_interactions where id = iid), 'then the press is given up');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(public.bot_api_poll_interactions(pg_temp.tok('helper'), 100)) e where e ->> 'id' = iid::text), 'and goes back to polling');
  perform pg_temp.expect((select consecutive_failures = 1 and last_status = 502 and last_failure_at is not null and enabled from public.bot_callbacks where bot_id = pg_temp.i('helper')), 'the callback notes the failure');

  -- Success.
  perform public.finish_bot_callback(iid2, true, 200, null);
  perform pg_temp.expect((select delivery_state = 'delivered' and delivered_at is not null from public.bot_interactions where id = iid2), 'a delivered press is marked');
  perform pg_temp.expect((select consecutive_failures = 0 and last_success_at is not null from public.bot_callbacks where bot_id = pg_temp.i('helper')), 'and the callback is well again');
  perform public.finish_bot_callback(iid2, false, 500, 'late report');
  perform pg_temp.expect((select delivery_state = 'delivered' from public.bot_interactions where id = iid2), 'a late report changes nothing');
  -- A delivered press can still be answered.
  perform pg_temp.expect(public.bot_api_respond(pg_temp.tok('helper'), iid2, '{"content":"pong via callback"}') is not null, 'the bot answers a delivered press through the API');

  -- Expired and answered ones are not sent.
  r := pg_temp.press('dan', 'mq', 'q2');
  update public.bot_interactions set expires_at = now() - interval '1 second' where id = (r ->> 'interaction_id')::uuid;
  claimed := public.claim_bot_callbacks(10);
  perform pg_temp.expect(jsonb_array_length(claimed) = 0 and (select delivery_state from public.bot_interactions where id = (r ->> 'interaction_id')::uuid) = 'failed', 'an expired press is not sent');

  -- 20 presses lost for good turn the callback off.
  update public.bot_callbacks set consecutive_failures = 19 where bot_id = pg_temp.i('helper');
  update public.bot_interactions set delivery_state = 'sending', delivery_attempts = 4 where id = iid;
  perform public.finish_bot_callback(iid, false, 500, 'down');
  perform pg_temp.expect((select not enabled and consecutive_failures = 20 from public.bot_callbacks where bot_id = pg_temp.i('helper')), 'twenty lost presses in a row turn the callback off');
  r := pg_temp.press('cat', 'mq', 'q1');
  perform pg_temp.expect(not (r ->> 'by_callback')::boolean and (select delivery_state from public.bot_interactions where id = (r ->> 'interaction_id')::uuid) = 'none', 'and presses wait for a poll again');
  -- Setting it again turns it on.
  r := pg_temp.set_cb('ada', 'helper', 'https://example.com/hook3');
  perform pg_temp.expect((select enabled and consecutive_failures = 0 and last_error is null from public.bot_callbacks where bot_id = pg_temp.i('helper')), 'setting the address again turns it back on');

  -- Rotating the secret.
  perform pg_temp.expect(pg_temp.cb_state('bob', format('select public.rotate_bot_callback_secret(%L)', pg_temp.i('helper'))) = '42501', 'only managers rotate');
  perform pg_temp.act(pg_temp.i('ada'));
  r := public.rotate_bot_callback_secret(pg_temp.i('helper'));
  perform pg_temp.root();
  perform pg_temp.expect(r ->> 'secret' ~ '^[0-9a-f]{64}$' and r ->> 'secret' <> secret1 and (select secret = r ->> 'secret' from public.bot_callbacks where bot_id = pg_temp.i('helper')), 'a new secret replaces the old');
  perform pg_temp.expect(pg_temp.cb_state('ada', format('select public.rotate_bot_callback_secret(%L)', pg_temp.i('other'))) = 'P0002', 'a bot without a callback has nothing to rotate');

  -- Clearing sends waiting presses back to polling.
  r := pg_temp.press('fay', 'mq', 'q1');
  iid := (r ->> 'interaction_id')::uuid;
  perform pg_temp.expect((select delivery_state from public.bot_interactions where id = iid) = 'queued', 'queued again');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.clear_bot_callback(pg_temp.i('helper'));
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.bot_callbacks) and (select delivery_state from public.bot_interactions where id = iid) = 'none', 'clearing removes the callback and the queue');
  perform pg_temp.expect(exists (select 1 from public.circle_audit_log where circle_id = pg_temp.i('club') and action = 'bot_callback_rotate') and exists (select 1 from public.circle_audit_log where circle_id = pg_temp.i('club') and action = 'bot_callback_clear'), 'rotating and clearing are audited');

  -- The wake does nothing without the project's secrets, and never fails.
  perform pg_temp.expect(pg_temp.state('select public.wake_bot_callbacks()') = 'ok' and pg_temp.state('select public.wake_bot_callbacks_if_due()') = 'ok', 'waking is safe where Vault or pg_net is missing');
end $$;

-- ===================================== 11. account, export, clean-up, the rest
do $$
declare
  exported jsonb;
  n integer;
begin
  exported := public.export_my_interactions(pg_temp.i('bob'));
  perform pg_temp.expect(jsonb_array_length(exported -> 'presses') >= 5, 'the export lists the person''s presses');
  perform pg_temp.expect((select bool_and(e ->> 'bot' = 'Helper' or e ->> 'bot' = 'Other') from jsonb_array_elements(exported -> 'presses') e) and not exported::text like '%secret%' and not exported::text like '%token%', 'with the bot''s name, and no secrets');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(exported -> 'presses') e where e ->> 'component' = 'Add a note' and e -> 'values' ->> 'text' = 'line one' || chr(10) || 'line two'), 'including what they typed in a form');
  perform pg_temp.expect(public.export_my_interactions(pg_temp.i('eve')) = '{"presses":[],"private_replies":[]}'::jsonb, 'a stranger''s export is empty');
  perform pg_temp.expect(jsonb_array_length(public.export_my_interactions(pg_temp.i('cat')) -> 'private_replies') = 0, 'a dismissed private reply is not exported');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.export_my_interactions(%L)', pg_temp.i('bob'))) = '42501', 'clients cannot call the export');
  perform pg_temp.root();
  perform pg_temp.expect(has_function_privilege('service_role', 'public.export_my_interactions(uuid)', 'execute'), 'the data-export function can');

  -- Private replies: at most 20 per person and chat; the newest stay.
  n := 0;
  insert into public.bot_ephemeral_messages (bot_id, conversation_id, user_id, body, created_at)
  select pg_temp.i('helper'), pg_temp.i('plaza_conv'), pg_temp.i('dan'), 'r' || g, now() + g * interval '1 second' from generate_series(1, 25) g;
  perform pg_temp.expect((select count(*) from public.bot_ephemeral_messages where user_id = pg_temp.i('dan')) = 20 and exists (select 1 from public.bot_ephemeral_messages where user_id = pg_temp.i('dan') and body = 'r25') and not exists (select 1 from public.bot_ephemeral_messages where user_id = pg_temp.i('dan') and body = 'r5'), 'only the newest 20 private replies are kept');
  update public.bot_ephemeral_messages set expires_at = now() - interval '1 minute' where body = 'r25';
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(public.list_my_ephemeral_messages(pg_temp.i('plaza_conv'))) e where e ->> 'body' = 'r25') and pg_temp.cnt('select 1 from public.bot_ephemeral_messages where body = ''r25''') = 0, 'an expired private reply is not listed or readable');
  perform pg_temp.root();

  -- Clean-up.
  update public.bot_interactions set created_at = now() - interval '8 days' where user_id = pg_temp.i('ada');
  update public.bot_ephemeral_messages set expires_at = now() - interval '2 hours' where body = 'r1';
  perform pg_temp.expect(pg_temp.cb_state('bob', 'select public.purge_bot_interactions()') = '42501', 'members cannot run the clean-up');
  perform public.purge_bot_interactions();
  perform pg_temp.expect(not exists (select 1 from public.bot_interactions where user_id = pg_temp.i('ada')) and exists (select 1 from public.bot_interactions where user_id = pg_temp.i('bob')), 'old presses are removed, new ones stay');
  perform pg_temp.expect(not exists (select 1 from public.bot_ephemeral_messages where body = 'r1'), 'and long-expired private replies');

  -- Account deletion erases presses and private replies.
  perform pg_temp.expect(exists (select 1 from public.bot_interactions where user_id = pg_temp.i('bob')) and exists (select 1 from public.bot_ephemeral_messages where user_id = pg_temp.i('dan')), 'before: there is something to erase');
  update public.profiles set deleted_at = now() where id in (pg_temp.i('bob'), pg_temp.i('dan'));
  perform pg_temp.expect(not exists (select 1 from public.bot_interactions where user_id in (pg_temp.i('bob'), pg_temp.i('dan'))) and not exists (select 1 from public.bot_ephemeral_messages where user_id in (pg_temp.i('bob'), pg_temp.i('dan'))), 'deleting an account erases what the person pressed, typed and was told privately');
  perform pg_temp.expect(exists (select 1 from public.bot_interactions where user_id = pg_temp.i('cat')), 'and nobody else''s');

  -- Closed tables and untouched functions.
  perform pg_temp.expect(not has_table_privilege('authenticated', 'public.bot_interactions', 'select') and not has_table_privilege('authenticated', 'public.bot_interactions', 'insert') and not has_table_privilege('anon', 'public.bot_interactions', 'select'), 'clients cannot touch bot_interactions');
  perform pg_temp.expect(has_table_privilege('authenticated', 'public.bot_ephemeral_messages', 'select') and not has_table_privilege('authenticated', 'public.bot_ephemeral_messages', 'insert') and not has_table_privilege('authenticated', 'public.bot_ephemeral_messages', 'update') and not has_table_privilege('authenticated', 'public.bot_ephemeral_messages', 'delete') and not has_table_privilege('anon', 'public.bot_ephemeral_messages', 'select'), 'private replies can only be read, and only by their owner');
  perform pg_temp.expect((select relrowsecurity from pg_class where oid = 'public.bot_ephemeral_messages'::regclass) and (select relrowsecurity from pg_class where oid = 'public.bot_callbacks'::regclass), 'row security is on');
  perform pg_temp.expect(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'bot_ephemeral_messages') or not exists (select 1 from pg_publication where pubname = 'supabase_realtime'), 'private replies are in realtime (row security still applies)');
  perform pg_temp.expect(pg_get_functiondef('public.run_later_dispatch()'::regprocedure) not like '%bot_%', 'run_later_dispatch is not touched');
  perform pg_temp.expect(pg_get_functiondef('public.messages_guard_server_fields()'::regprocedure) like '%interaction is not null%', 'the guard of the other server-only fields is not rewritten');
  perform pg_temp.expect(pg_get_functiondef('public.send_text_message(uuid, text, uuid, jsonb, jsonb, uuid)'::regprocedure) not like '%components%', 'send_text_message is not rewritten');
  perform pg_temp.expect(pg_get_functiondef('public.message_visible_to_current_user(text, uuid, uuid)'::regprocedure) like '%can_current_user_moderate_messages%', 'message visibility is not touched');
  perform pg_temp.expect(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('submit_interaction','set_bot_callback','get_bot_callback','rotate_bot_callback_secret','clear_bot_callback','interaction_status','list_my_ephemeral_messages','dismiss_ephemeral_message') and not p.prosecdef), 'the RPCs are security definer');
  perform pg_temp.expect(not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('bot_api_respond','bot_api_edit_message','bot_api_send_message_with_components','claim_bot_callbacks','finish_bot_callback','bot_send_text','bot_interaction_payload','normalize_message_components')
      and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
  ), 'the bot and server functions are closed to clients');
  perform pg_temp.expect(not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('submit_interaction','set_bot_callback','get_bot_callback','rotate_bot_callback_secret','clear_bot_callback','interaction_status','list_my_ephemeral_messages','dismiss_ephemeral_message')
      and has_function_privilege('anon', p.oid, 'execute')
  ), 'and the member RPCs are closed to anon');
  perform pg_temp.expect(not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef and p.proname in ('submit_interaction','set_bot_callback','get_bot_callback','rotate_bot_callback_secret','clear_bot_callback','interaction_status','list_my_ephemeral_messages','dismiss_ephemeral_message','bot_api_respond','bot_api_edit_message','bot_api_send_message_with_components','claim_bot_callbacks','finish_bot_callback','bot_send_text','bot_text_blocked','bot_components_automod','bot_edit_own_message','bot_interaction_payload','bot_callback_state','wake_bot_callbacks','erase_interactions_of_deleted_account','export_my_interactions')
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c = 'search_path=public')
  ), 'every definer function pins search_path to public');
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform pg_temp.expect(exists (select 1 from cron.job where jobname = 'wecord-bot-callbacks-retry' and schedule = '* * * * *') and exists (select 1 from cron.job where jobname = 'wecord-bot-interactions-purge'), 'the retry and the clean-up are cron jobs of their own');
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
    raise exception 'interactions: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
