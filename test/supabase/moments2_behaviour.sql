-- Behaviour checks for Moments 2.0 (roadmap B2: migrations 202610260600 to
-- 202610260650). Run by test/supabase/moments2_test.dart against the local
-- database inside a transaction that is rolled back. Run from the repository
-- root.
--
-- What it walks through: "Remind who to read" (only friends who can see the
-- post are kept, one notice each, the author alone sees who, the push is
-- worded per language), pinning (three at most, first on a person's page,
-- once), videos up to 3 minutes, picture descriptions on photos, a picture on
-- a comment (the file is the commenter's, follows the comment's visibility
-- and goes with an unfriend), the Moment card for a chat (the card holds
-- nothing, the reader is checked every time), and deleting an account.
--
-- Cast: Ada (a1) posts; her friends are Bob (b1), Cy (c1) and Dee (d1); Bob
-- and Dee are friends of each other; Eli (e1) has no friends.
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

create function pg_temp.refused(statement text) returns boolean language plpgsql as $$
begin
  execute statement;
  return false;
exception when others then
  return true;
end $$;

-- The SQLSTATE a statement fails with, or null when it works.
create function pg_temp.failure(statement text) returns text language plpgsql as $$
begin
  execute statement;
  return null;
exception when others then
  return sqlstate;
end $$;

-- Whether the current person may read an object of the moments bucket.
create function pg_temp.reads(object text) returns boolean language plpgsql as $$
declare n integer;
begin
  select count(*) into n from storage.objects where bucket_id = 'moments' and name = object;
  return n = 1;
end $$;

-- Puts a file in the bucket as the current person (the insert policy applies).
create function pg_temp.upload(object text, size bigint default 1000) returns void language plpgsql as $$
begin
  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('moments', object, auth.uid(), jsonb_build_object('size', size));
end $$;

create function pg_temp.befriend(a uuid, b uuid) returns void language sql as $$
  insert into public.friendships (user_low_id, user_high_id)
  values (least(a, b), greatest(a, b));
$$;

-- The video of a post as the app sends it.
create function pg_temp.video(owner uuid, post uuid, ext text default 'mp4', ms integer default 42000, size bigint default 3000000)
returns jsonb language sql as $$
  select jsonb_build_object(
    'path', owner || '/' || post || '-v.' || ext,
    'poster', owner || '/' || post || '-0.jpg',
    'thumb', owner || '/' || post || '-0-t.jpg',
    'w', 1280, 'h', 720, 'duration_ms', ms, 'size', size);
$$;

create temp table got (label text, subscription_id uuid, endpoint text, title text, body text, tag text, url text);
grant all on got to public;

-- Claims the pushes as the service role and files the rows under [label].
create function pg_temp.claim(label text, caller uuid default null, post uuid default null)
returns integer language plpgsql security definer as $$
declare n integer;
begin
  insert into pg_temp.got
  select label, c.subscription_id, c.endpoint, c.title, c.body, c.tag, c.url
  from public.claim_moments_pushes(caller, post) c;
  get diagnostics n = row_count;
  return n;
end $$;

grant execute on all functions in schema pg_temp to public;

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@m2.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@m2.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@m2.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee@m2.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e1', 'eli@m2.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_m2', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_m2', 'Bob'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_m2', 'Cy'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee_m2', 'Dee'),
  ('00000000-0000-4000-8000-0000000000e1', 'eli_m2', 'Eli');

insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
values
  ('00000000-0000-4000-8000-0000000000a1', 'https://push.test/ada-en', repeat('p', 60), repeat('a', 20), 'en'),
  ('00000000-0000-4000-8000-0000000000b1', 'https://push.test/bob-zh', repeat('q', 60), repeat('b', 20), 'zh'),
  ('00000000-0000-4000-8000-0000000000c1', 'https://push.test/cy-en', repeat('r', 60), repeat('c', 20), 'en');

do $$ begin
  perform pg_temp.befriend('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000b1');
  perform pg_temp.befriend('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000c1');
  perform pg_temp.befriend('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000d1');
  perform pg_temp.befriend('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000d1');
end $$;

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  cy uuid := '00000000-0000-4000-8000-0000000000c1';
  dee uuid := '00000000-0000-4000-8000-0000000000d1';
  eli uuid := '00000000-0000-4000-8000-0000000000e1';
  alt_post uuid := '60000000-0000-4000-8000-0000000000a0';
  m1 uuid := '60000000-0000-4000-8000-0000000000b1';
  m2 uuid := '60000000-0000-4000-8000-0000000000b2';
  m3 uuid := '60000000-0000-4000-8000-0000000000b3';
  m4 uuid := '60000000-0000-4000-8000-0000000000b4';
  m5 uuid := '60000000-0000-4000-8000-0000000000b5';
  p_a uuid := '60000000-0000-4000-8000-0000000000c1';
  p_b uuid := '60000000-0000-4000-8000-0000000000c2';
  p_c uuid := '60000000-0000-4000-8000-0000000000c3';
  p_d uuid := '60000000-0000-4000-8000-0000000000c4';
  p_e uuid := '60000000-0000-4000-8000-0000000000c5';
  v180 uuid := '60000000-0000-4000-8000-0000000000d1';
  v181 uuid := '60000000-0000-4000-8000-0000000000d2';
  v_bad uuid := '60000000-0000-4000-8000-0000000000d3';
  bob_post uuid := '60000000-0000-4000-8000-0000000000e1';
  cid uuid := '61000000-0000-4000-8000-000000000001';
  cid_text uuid := '61000000-0000-4000-8000-000000000002';
  cid_bad uuid := '61000000-0000-4000-8000-000000000003';
  cid_gone uuid := '61000000-0000-4000-8000-000000000004';
  photos_value jsonb;
  asked uuid[];
  stored uuid[];
  n integer;
  feed_row record;
  rows_ integer;
  first_rows uuid[];
  page_two uuid[];
  conv_ab uuid;
  conv_bd uuid;
  msg uuid;
  att jsonb;
  image_value jsonb;
  state text;
  zh_title text;
  en_title text;
  more jsonb;
begin
  -- ====================================== picture descriptions (ALT)
  perform pg_temp.act(ada);
  perform public.create_moment(
    alt_post, 'photos', jsonb_build_array(
      jsonb_build_object('path', ada || '/' || alt_post || '-0.jpg', 'thumb', ada || '/' || alt_post || '-0-t.jpg', 'w', 10, 'h', 10, 'alt', '  A dog asleep on a sofa  '),
      jsonb_build_object('path', ada || '/' || alt_post || '-1.jpg', 'thumb', ada || '/' || alt_post || '-1-t.jpg', 'w', 10, 'h', 10, 'alt', repeat('x', 1500)),
      jsonb_build_object('path', ada || '/' || alt_post || '-2.jpg', 'thumb', ada || '/' || alt_post || '-2-t.jpg', 'w', 10, 'h', 10, 'alt', 5),
      jsonb_build_object('path', ada || '/' || alt_post || '-3.jpg', 'thumb', ada || '/' || alt_post || '-3-t.jpg', 'w', 10, 'h', 10, 'alt', '   ')
    ));
  reset role;
  select photos into photos_value from public.moments_posts where id = alt_post;
  perform pg_temp.expect(photos_value->0->>'alt' = 'A dog asleep on a sofa', format('a description should be trimmed, got %s', photos_value->0));
  perform pg_temp.expect(char_length(photos_value->1->>'alt') = 1000, 'a long description should be cut at 1000 characters');
  perform pg_temp.expect(not (photos_value->2 ? 'alt'), 'a description that is not text should be dropped');
  perform pg_temp.expect(not (photos_value->3 ? 'alt'), 'an empty description should be dropped');
  perform pg_temp.expect((photos_value->0->>'w')::int = 10, 'the other keys of a photo should stay');
  -- Friends read it in the feed.
  perform pg_temp.act(bob);
  select f.photos into photos_value from public.moments_feed(20, null, null, null, alt_post) f;
  perform pg_temp.expect(photos_value->0->>'alt' = 'A dog asleep on a sofa', 'a friend should read the description in the feed');

  -- ================================================= Remind who to read
  perform pg_temp.act(ada);
  -- Eli is no friend, Ada is herself, Cy and Bob are friends who see it.
  perform public.create_moment(m1, 'look at this', '[]', null, null, null, 'friends', '{}', '{}', null, array[bob, eli, ada, cy, bob]);
  reset role;
  select mentioned_user_ids into stored from public.moments_posts where id = m1;
  perform pg_temp.expect(
    stored @> array[bob, cy] and cardinality(stored) = 2,
    format('only the friends should be kept, got %s', stored));
  perform pg_temp.expect(
    (select count(*) from public.moments_notifications where kind = 'mention' and post_id = m1 and user_id in (bob, cy) and actor_id = ada) = 2,
    'each reminded friend should get one notice');
  perform pg_temp.expect(
    (select count(*) from public.moments_notifications where kind = 'mention' and post_id = m1 and user_id in (eli, ada)) = 0,
    'a stranger or the author should get no notice');

  -- Posting the same id again changes nothing and reminds nobody twice.
  perform pg_temp.act(ada);
  perform public.create_moment(m1, 'look at this', '[]', null, null, null, 'friends', '{}', '{}', null, array[dee, bob]);
  reset role;
  perform pg_temp.expect(
    (select count(*) from public.moments_notifications where kind = 'mention' and post_id = m1) = 2
    and not exists (select 1 from public.moments_posts where id = m1 and dee = any (mentioned_user_ids)),
    'posting the same id again reminded somebody');

  -- Only the people who can see this very post.
  perform pg_temp.act(ada);
  perform public.create_moment(m2, 'just for Cy', '[]', null, null, null, 'only', array[cy], '{}', null, array[bob, cy, dee]);
  perform public.create_moment(m3, 'just me', '[]', null, null, null, 'private', '{}', '{}', null, array[bob]);
  perform public.set_moments_friend_pref(dee, true, null);
  perform public.create_moment(m4, 'Dee is hidden from', '[]', null, null, null, 'friends', '{}', '{}', null, array[dee, bob]);
  perform public.set_moments_friend_pref(dee, false, null);
  reset role;
  select mentioned_user_ids into stored from public.moments_posts where id = m2;
  perform pg_temp.expect(stored = array[cy], format('"Only share with" should keep only Cy, got %s', stored));
  select mentioned_user_ids into stored from public.moments_posts where id = m3;
  perform pg_temp.expect(cardinality(stored) = 0, '"Only me" should remind nobody');
  select mentioned_user_ids into stored from public.moments_posts where id = m4;
  perform pg_temp.expect(stored = array[bob], format('a friend hidden from should not be reminded, got %s', stored));
  perform pg_temp.expect(
    (select count(*) from public.moments_notifications where kind = 'mention' and user_id = dee) = 0,
    'Dee should have no notice');

  -- A blocked friend is not reminded either.
  insert into public.blocks (blocker_id, blocked_id) values (cy, ada);
  perform pg_temp.act(ada);
  perform public.create_moment(m5, 'Cy blocked me', '[]', null, null, null, 'friends', '{}', '{}', null, array[cy, bob]);
  reset role;
  select mentioned_user_ids into stored from public.moments_posts where id = m5;
  perform pg_temp.expect(not (cy = any (stored)), 'a blocked person was reminded');
  delete from public.blocks where blocker_id = cy;

  -- Thirty-one people are too many.
  perform pg_temp.act(ada);
  perform pg_temp.expect(
    pg_temp.refused(format(
      'select public.create_moment(%L, ''x'', ''[]'', null, null, null, ''friends'', ''{}'', ''{}'', null, %L::uuid[])',
      '60000000-0000-4000-8000-0000000000ff',
      (select array_agg(gen_random_uuid()) from generate_series(1, 31)))),
    '31 people were accepted');

  -- The list of who was reminded is not readable through the API.
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.refused('select mentioned_user_ids from public.moments_posts'),
    'a friend read mentioned_user_ids');
  perform pg_temp.expect(
    pg_temp.refused('select pinned_at from public.moments_posts'),
    'a friend read pinned_at');

  -- The feed: the author sees the names, the reminded person that they were.
  perform pg_temp.act(ada);
  select f.mentioned_me, f.mentions into feed_row from public.moments_feed(20, null, null, null, m1) f;
  perform pg_temp.expect(
    not feed_row.mentioned_me and jsonb_array_length(feed_row.mentions) = 2,
    format('the author should see who was reminded, got %s', feed_row.mentions));
  perform pg_temp.act(bob);
  select f.mentioned_me, f.mentions into feed_row from public.moments_feed(20, null, null, null, m1) f;
  perform pg_temp.expect(
    feed_row.mentioned_me and feed_row.mentions = '[]'::jsonb,
    'the reminded person should be told, and nobody else named');
  perform pg_temp.act(dee);
  select f.mentioned_me, f.mentions into feed_row from public.moments_feed(20, null, null, null, m1) f;
  perform pg_temp.expect(
    not feed_row.mentioned_me and feed_row.mentions = '[]'::jsonb,
    'a friend who was not reminded sees nothing of it');

  -- The notice in the inbox, and it goes with the friendship.
  perform pg_temp.act(bob);
  select count(*) into n from public.list_moments_notifications(50) l where l.kind = 'mention' and l.post_id = m1 and l.actor_id = ada and l.is_unread;
  perform pg_temp.expect(n = 1, 'the reminder should be in the inbox');
  reset role;
  delete from public.friendships where user_low_id = least(ada, bob) and user_high_id = greatest(ada, bob);
  perform pg_temp.act(bob);
  select count(*) into n from public.list_moments_notifications(50) l where l.kind = 'mention';
  perform pg_temp.expect(n = 0, 'a reminder outlived the friendship');
  reset role;
  perform pg_temp.befriend(ada, bob);

  -- The push: worded per language, only to people who still see the post.
  reset role;
  perform pg_temp.expect(pg_temp.claim('mention', ada, m1) = 2, 'both reminded friends should get a push');
  select title into zh_title from pg_temp.got where label = 'mention' and endpoint = 'https://push.test/bob-zh';
  select title into en_title from pg_temp.got where label = 'mention' and endpoint = 'https://push.test/cy-en';
  perform pg_temp.expect(zh_title = 'Ada 提醒你看TA的朋友圈', format('the Chinese push is %s', zh_title));
  perform pg_temp.expect(en_title = 'Ada reminded you to read their Moment', format('the English push is %s', en_title));
  perform pg_temp.expect(
    (select body from pg_temp.got where label = 'mention' and endpoint = 'https://push.test/cy-en') = 'look at this',
    'the push body should be the start of the post');
  perform pg_temp.expect(pg_temp.claim('again', ada, m1) = 0, 'a reminder was pushed twice');

  -- ===================================================== pinning
  perform pg_temp.act(ada);
  perform public.create_moment(p_a, 'a');
  perform public.create_moment(p_b, 'b');
  perform public.create_moment(p_c, 'c');
  perform public.create_moment(p_d, 'd');
  perform public.create_moment(p_e, 'e');
  perform public.set_moment_pinned(p_a, true);
  perform public.set_moment_pinned(p_b, true);
  perform public.set_moment_pinned(p_c, true);
  perform public.set_moment_pinned(p_a, true);
  perform pg_temp.expect(
    pg_temp.failure(format('select public.set_moment_pinned(%L, true)', p_d)) = '54000',
    'a fourth pin should be refused with 54000');
  perform public.set_moment_pinned(p_b, false);
  perform public.set_moment_pinned(p_d, true);
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.refused(format('select public.set_moment_pinned(%L, true)', p_e)),
    'a friend pinned somebody else''s post');
  perform pg_temp.act(eli);
  perform pg_temp.expect(
    pg_temp.refused(format('select public.set_moment_pinned(%L, true)', p_e)),
    'a stranger pinned somebody else''s post');

  -- A person's page starts with the pins, later pages leave them out.
  perform pg_temp.act(bob);
  select array_agg(f.id order by ord) into first_rows
  from (select f.id, row_number() over () as ord from public.moments_feed(3, null, null, ada, null) f) f;
  select count(*) into rows_ from public.moments_feed(3, null, null, ada, null) f where f.pinned_at is not null;
  perform pg_temp.expect(rows_ = 3, format('three pinned posts should come first, got %s', rows_));
  perform pg_temp.expect(
    (select bool_and(f.pinned_at is not null) from (select f.* from public.moments_feed(3, null, null, ada, null) f limit 3) f),
    'the pinned posts should be the first rows');
  perform pg_temp.expect(cardinality(first_rows) = 6, format('three pinned and three more, got %s', cardinality(first_rows)));
  select f.created_at as at, f.id as id into feed_row from public.moments_feed(3, null, null, ada, null) f where f.pinned_at is null order by f.created_at, f.id limit 1;
  select array_agg(f.id) into page_two from public.moments_feed(3, feed_row.at, feed_row.id, ada, null) f;
  perform pg_temp.expect(
    not exists (select 1 from public.moments_feed(50, feed_row.at, feed_row.id, ada, null) f where f.pinned_at is not null),
    'a later page showed a pinned post again');
  -- The feed itself stays by time.
  perform pg_temp.expect(
    (select f.pinned_at is not null from public.moments_feed(50, null, null, null, null) f where f.id = p_a),
    'the feed should carry pinned_at');
  -- A pin the viewer may not see stays hidden.
  perform pg_temp.act(ada);
  perform public.set_moment_pinned(p_a, false);
  perform public.create_moment('60000000-0000-4000-8000-0000000000c9', 'pinned for Cy', '[]', null, null, null, 'only', array[cy], '{}');
  perform public.set_moment_pinned('60000000-0000-4000-8000-0000000000c9', true);
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    not exists (select 1 from public.moments_feed(50, null, null, ada, null) f where f.id = '60000000-0000-4000-8000-0000000000c9'),
    'a pinned post the viewer may not see was shown');
  perform pg_temp.act(cy);
  perform pg_temp.expect(
    (select f.id from public.moments_feed(50, null, null, ada, null) f limit 1) = '60000000-0000-4000-8000-0000000000c9',
    'Cy should see the pinned post first');

  -- ================================================ videos to 3 minutes
  perform pg_temp.act(ada);
  perform pg_temp.upload(ada || '/' || v180 || '-0.jpg');
  perform pg_temp.upload(ada || '/' || v180 || '-0-t.jpg');
  perform pg_temp.upload(ada || '/' || v180 || '-v.mp4', 3000000);
  perform public.create_moment(v180, '', '[]', null, null, null, 'friends', '{}', '{}', pg_temp.video(ada, v180, 'mp4', 180000));
  perform pg_temp.upload(ada || '/' || v181 || '-0.jpg');
  perform pg_temp.upload(ada || '/' || v181 || '-0-t.jpg');
  perform pg_temp.upload(ada || '/' || v181 || '-v.mp4', 3000000);
  perform public.create_moment(v181, '', '[]', null, null, null, 'friends', '{}', '{}', pg_temp.video(ada, v181, 'mp4', 181000));
  perform pg_temp.upload(ada || '/' || v_bad || '-0.jpg');
  perform pg_temp.upload(ada || '/' || v_bad || '-v.mp4', 3000000);
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, '''', ''[]'', null, null, null, ''friends'', ''{}'', ''{}'', %L::jsonb)', v_bad, pg_temp.video(ada, v_bad, 'mp4', 181001))),
    'a video over 3 minutes was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('select public.create_moment(%L, '''', ''[]'', null, null, null, ''friends'', ''{}'', ''{}'', %L::jsonb)', v_bad, pg_temp.video(ada, v_bad, 'mp4', 120000, 52428801))),
    'a video over 50 MB was accepted');

  -- ============================================ a picture on a comment
  perform pg_temp.act(bob);
  perform pg_temp.upload(bob || '/c-' || cid || '.png', 5000);
  insert into public.moments_comments (id, post_id, author_id, body, image)
  values (cid, m1, bob, '', jsonb_build_object('path', bob || '/c-' || cid || '.png', 'w', 300, 'h', 9999, 'alt', '  a cat sticker  ', 'x', 1));
  reset role;
  select image into image_value from public.moments_comments where id = cid;
  perform pg_temp.expect(
    image_value = jsonb_build_object('path', bob || '/c-' || cid || '.png', 'w', 300, 'h', 4096, 'alt', 'a cat sticker'),
    format('the picture should be cleaned, got %s', image_value));

  perform pg_temp.act(bob);
  -- No words and no picture.
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.moments_comments (post_id, author_id, body) values (%L, %L, '''')', m1, bob)),
    'an empty comment was accepted');
  -- A picture that is not this comment's, or not Bob's, or not there.
  perform pg_temp.upload(bob || '/c-' || cid_bad || '.png');
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.moments_comments (id, post_id, author_id, body, image) values (%L, %L, %L, '''', %L::jsonb)', cid_text, m1, bob, jsonb_build_object('path', bob || '/c-' || cid_bad || '.png'))),
    'a picture named after another comment was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.moments_comments (id, post_id, author_id, body, image) values (%L, %L, %L, '''', %L::jsonb)', cid_text, m1, bob, jsonb_build_object('path', ada || '/c-' || cid_text || '.png'))),
    'a picture in somebody else''s folder was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.moments_comments (id, post_id, author_id, body, image) values (%L, %L, %L, ''hi'', %L::jsonb)', cid_gone, m1, bob, jsonb_build_object('path', bob || '/c-' || cid_gone || '.png'))),
    'a picture that was never uploaded was accepted');
  perform pg_temp.expect(
    pg_temp.refused(format('insert into public.moments_comments (id, post_id, author_id, body, image) values (%L, %L, %L, ''hi'', ''"x"''::jsonb)', cid_gone, m1, bob)),
    'a picture that is not an object was accepted');
  -- Words alone still work, and so do words with a picture.
  insert into public.moments_comments (id, post_id, author_id, body) values (cid_text, m1, bob, '  nice  ');
  perform pg_temp.expect((select body from public.moments_comments where id = cid_text) = 'nice', 'words alone should still work');
  -- Files: the right name, the right folder, an allowed type.
  perform pg_temp.expect(
    pg_temp.refused(format('select pg_temp.upload(%L)', ada || '/c-' || cid_gone || '.png')),
    'Bob uploaded a comment picture into Ada''s folder');
  perform pg_temp.expect(
    pg_temp.refused(format('select pg_temp.upload(%L)', bob || '/c-oops.png')),
    'an oddly named comment picture was uploaded');
  perform pg_temp.expect(
    pg_temp.refused(format('select pg_temp.upload(%L)', bob || '/c-' || cid_gone || '.bmp')),
    'a .bmp comment picture was uploaded');
  perform pg_temp.upload(bob || '/c-' || cid_gone || '.gif');

  -- Who reads the picture: whoever may see the comment.
  perform pg_temp.act(ada);
  perform pg_temp.expect(pg_temp.reads(bob || '/c-' || cid || '.png'), 'the post author cannot read a comment picture');
  perform pg_temp.act(dee);
  perform pg_temp.expect(pg_temp.reads(bob || '/c-' || cid || '.png'), 'a friend of both cannot read the comment picture');
  perform pg_temp.act(cy);
  perform pg_temp.expect(not pg_temp.reads(bob || '/c-' || cid || '.png'), 'a stranger of the commenter reads the picture');
  perform pg_temp.act(eli);
  perform pg_temp.expect(not pg_temp.reads(bob || '/c-' || cid || '.png'), 'a stranger reads the comment picture');
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.reads(bob || '/c-' || cid || '.png'), 'Bob cannot read his own picture');

  -- In the feed, and in the notice.
  perform pg_temp.act(ada);
  select f.comments into image_value from public.moments_feed(20, null, null, null, m1) f;
  perform pg_temp.expect(
    exists (select 1 from jsonb_array_elements(image_value) c where c->'image'->>'path' = bob || '/c-' || cid || '.png' and c->'image'->>'alt' = 'a cat sticker'),
    'the feed should carry the comment picture');
  select count(*) into n from public.list_moments_notifications(50) l where l.kind = 'comment' and l.comment_id = cid and l.has_image and l.snippet = '';
  perform pg_temp.expect(n = 1, 'the notice of a picture-only comment should say so');
  reset role;
  perform pg_temp.expect(pg_temp.claim('picture', bob, m1) >= 1, 'the comment should be pushed');
  perform pg_temp.expect(
    exists (select 1 from pg_temp.got where label = 'picture' and endpoint = 'https://push.test/ada-en' and body = '[Picture]'),
    'a picture-only comment should be pushed as [Picture]');

  -- Unfriending cuts the picture off at once.
  delete from public.friendships where user_low_id = least(ada, bob) and user_high_id = greatest(ada, bob);
  perform pg_temp.act(ada);
  perform pg_temp.expect(not pg_temp.reads(bob || '/c-' || cid || '.png'), 'an unfriended post author still reads the comment picture');
  perform pg_temp.act(dee);
  perform pg_temp.expect(not pg_temp.reads(bob || '/c-' || cid || '.png'), 'the picture outlived the post''s visibility');
  reset role;
  perform pg_temp.befriend(ada, bob);

  -- ============================================ the Moment card
  perform pg_temp.act(ada);
  conv_ab := public.get_or_create_direct_conversation(bob);
  msg := public.send_moment_card(conv_ab, m1);
  reset role;
  select m.attachment, m.body into att, state from public.messages m where m.id = msg;
  perform pg_temp.expect(
    att = jsonb_build_object('kind', 'moment_card', 'post_id', m1) and state = '[Moment]',
    format('the card should hold nothing but the post id, got %s %s', att, state));
  perform pg_temp.expect(
    public.card_body_zh(state, att) = '[朋友圈]',
    'the push of a Moment card should read in Chinese');
  perform pg_temp.act(bob);
  perform pg_temp.expect((select count(*) from public.get_moment_card(m1)) = 1, 'a friend should see the card');
  select excerpt into state from public.get_moment_card(m1);
  perform pg_temp.expect(state = 'look at this', 'the card should show the start of the post');
  perform pg_temp.act(eli);
  perform pg_temp.expect((select count(*) from public.get_moment_card(m1)) = 0, 'a stranger saw the card');
  -- A Moment the reader may not see is not shown through a card either.
  perform pg_temp.act(ada);
  perform public.send_moment_card(conv_ab, m2);
  perform pg_temp.act(bob);
  perform pg_temp.expect((select count(*) from public.get_moment_card(m2)) = 0, 'a card showed a Moment its reader may not see');
  perform pg_temp.act(cy);
  perform pg_temp.expect((select count(*) from public.get_moment_card(m2)) = 1, 'Cy should see the Moment shared with Cy');
  -- Only what the sender sees can be sent; only into one's own chats.
  conv_bd := null;
  perform pg_temp.act(bob);
  conv_bd := public.get_or_create_direct_conversation(dee);
  perform pg_temp.expect(
    pg_temp.failure(format('select public.send_moment_card(%L, %L)', conv_bd, m2)) = '42501',
    'Bob sent a Moment he cannot see');
  perform pg_temp.act(cy);
  perform pg_temp.expect(
    pg_temp.failure(format('select public.send_moment_card(%L, %L)', conv_ab, m2)) = '42501',
    'Cy sent a card into a chat he is not in');
  -- Dee sees m1 and may share it with Bob; Bob can read it too.
  perform pg_temp.act(dee);
  perform public.send_moment_card(conv_bd, m1);
  -- Taking the Moment back, or unfriending, closes the card.
  perform pg_temp.act(ada);
  perform public.set_moments_friend_pref(bob, true, null);
  perform pg_temp.act(bob);
  perform pg_temp.expect((select count(*) from public.get_moment_card(m1)) = 0, '"Don''t let them see my Moments" should close the card');
  perform pg_temp.act(ada);
  perform public.set_moments_friend_pref(bob, false, null);

  -- ============================================= taking your data
  reset role;
  more := public.export_my_moments_more(ada);
  perform pg_temp.expect(jsonb_array_length(more->'pinned') = 3, format('three pins should be exported, got %s', more->'pinned'));
  perform pg_temp.expect(
    exists (select 1 from jsonb_array_elements(more->'reminded') r where r->>'post_id' = m1::text and jsonb_array_length(r->'people') = 2),
    'the people Ada reminded should be exported');
  more := public.export_my_moments_more(bob);
  perform pg_temp.expect(
    exists (select 1 from jsonb_array_elements(more->'reminded_by') r where r->>'post_id' = m1::text and r->'from'->>'display_name' = 'Ada')
    and not (more->'reminded_by'->0 ? 'body'),
    'the reminders Bob got should be exported without the post text');
  perform pg_temp.expect(
    exists (select 1 from jsonb_array_elements(more->'comment_pictures') r where r->>'comment_id' = cid::text and r->>'description' = 'a cat sticker' and r->>'bucket' = 'moments'),
    'the picture of Bob''s comment should be exported');
  perform pg_temp.expect(
    pg_temp.refused('select public.export_my_moments_more(null)'),
    'an export for nobody was accepted');
  perform pg_temp.act(bob);
  perform pg_temp.expect(
    pg_temp.refused(format('select public.export_my_moments_more(%L)', bob)),
    'the app may not ask for an export directly');

  -- ============================================= deleting an account
  perform pg_temp.act(bob);
  perform public.create_moment(bob_post, 'Bob''s own', '[]', null, null, null, 'friends', '{}', '{}', null, array[ada]);
  reset role;
  perform pg_temp.expect(
    (select count(*) from public.moments_notifications where user_id = ada and kind = 'mention' and post_id = bob_post) = 1,
    'Ada should have been reminded by Bob');
  update public.profiles set deleted_at = now(), display_name = 'Deleted User' where id = bob;
  perform pg_temp.expect(not exists (select 1 from public.moments_posts where author_id = bob), 'a deleted account kept its Moments');
  perform pg_temp.expect(not exists (select 1 from public.moments_comments where author_id = bob), 'a deleted account kept its comments');
  perform pg_temp.expect(
    not exists (select 1 from public.moments_posts where bob = any (mentioned_user_ids)),
    'a deleted account is still named in a reminder list');
  perform pg_temp.expect(
    not exists (select 1 from public.moments_notifications where user_id = bob or actor_id = bob),
    'a deleted account kept its Moments notices');
  perform pg_temp.expect(
    exists (select 1 from public.moments_posts where id = m1) and (select cardinality(mentioned_user_ids) from public.moments_posts where id = m1) = 1,
    'other people''s posts should stay, without the deleted person in their lists');
end $$;

reset role;
do $$
declare
  failed text;
begin
  select string_agg(msg, E'\n') into failed from pg_temp.failures;
  if failed is not null then
    raise exception E'moments 2.0 checks failed:\n%', failed;
  end if;
end $$;

rollback;
