-- Behaviour checks for topics (#话题) and circle posts 2.0 (B8): migrations
-- 202610280700 to 202610280770. Run by test/supabase/hashtags_test.dart
-- against the local database: it applies the migrations in a transaction,
-- plays people through them, and rolls everything back. Run from the
-- repository root.
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
\i supabase/migrations/202610280700_hashtags_schema.sql
\i supabase/migrations/202610280710_circle_posts_rpcs.sql
\i supabase/migrations/202610280720_circle_posts_read.sql
\i supabase/migrations/202610280730_moments_hashtags.sql
\i supabase/migrations/202610280740_posts_guard.sql
\i supabase/migrations/202610280750_featured_posts_tab.sql
\i supabase/migrations/202610280760_featured_push.sql
\i supabase/migrations/202610280770_hashtags_account.sql
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
-- ada owns a circle (club) and is its moderator; bob and cat are members; dan
-- is a friend of bob outside the circle; eve is a stranger to everyone.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@b8.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_b8', initcap(name)
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(pg_temp.i(a), pg_temp.i(b)), greatest(pg_temp.i(a), pg_temp.i(b))
from (values ('ada','bob'),('ada','cat'),('bob','cat'),('bob','dan')) v(a, b);

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'club', public.create_circle('Book Club', array[pg_temp.i('bob'), pg_temp.i('cat')]);
insert into pg_temp.ids select 'plaza', public.create_circle_channel(pg_temp.i('club'), 'plaza', null, 'text');
select pg_temp.root();
insert into pg_temp.ids
select 'plazac', cc.conversation_id from public.circle_channels cc where cc.id = pg_temp.i('plaza');
insert into pg_temp.ids values ('g1', gen_random_uuid());
insert into public.conversations (id, type, title) values (pg_temp.i('g1'), 'group', 'Hike crew');
insert into public.conversation_members (conversation_id, user_id, role)
values (pg_temp.i('g1'), pg_temp.i('ada'), 'owner'), (pg_temp.i('g1'), pg_temp.i('bob'), 'member');

grant execute on all functions in schema pg_temp to public;

-- ====================================== 1. reading tags out of text
\set cases `cat test/fixtures/hashtag_cases.json`
create temp table hashtag_cases (j jsonb);
grant all on hashtag_cases to public;
insert into hashtag_cases values (:'cases'::jsonb);

do $$
declare
  cases jsonb;
  c jsonb;
begin
  select j into cases from pg_temp.hashtag_cases;
  for c in select * from jsonb_array_elements(cases -> 'extract') loop
    perform pg_temp.expect(
      to_jsonb(public.hashtags_from_text(c ->> 'input')) = c -> 'tags',
      'extract: ' || replace(c ->> 'input', E'\n', '\n')
    );
  end loop;
  for c in select * from jsonb_array_elements(cases -> 'clean') loop
    perform pg_temp.expect(
      public.hashtag_clean(c ->> 'input') is not distinct from (c ->> 'tag'),
      'clean: ' || (c ->> 'input')
    );
  end loop;
  perform pg_temp.expect(public.hashtags_from_text(null) = '{}', 'no text, no tags');
  perform pg_temp.expect(
    public.hashtag_clean_list(array['A', 'a', '#b', 'x y', '12', 'c']) = array['a', 'b', 'c'],
    'a list is cleaned, folded and kept in order'
  );
  perform pg_temp.expect(
    cardinality(public.hashtag_clean_list(array['a1','a2','a3','a4','a5','a6','a7','a8','a9','b1','b2'])) = 10,
    'ten tags at most'
  );
  perform pg_temp.expect(
    not has_function_privilege('anon', 'public.hashtags_from_text(text)', 'execute'),
    'the reading functions are not for visitors'
  );
end $$;

-- ====================================== 2. Moments: the tags of a post
do $$
declare
  m1 uuid := gen_random_uuid();
  m2 uuid := gen_random_uuid();
  m3 uuid := gen_random_uuid();
  m4 uuid := gen_random_uuid();
  m5 uuid := gen_random_uuid();
  got text[];
begin
  insert into pg_temp.ids values ('m1', m1), ('m2', m2), ('m3', m3), ('m4', m4), ('m5', m5);

  perform pg_temp.act(pg_temp.i('bob'));
  perform public.create_moment(m1, 'Reading #读书 and #Travel today', '[]', null, null, null, 'friends', '{}', '{}', null, '{}');
  perform public.create_moment(m2, 'Secret #secret #读书 note', '[]', null, null, null, 'private', '{}', '{}', null, '{}');
  perform pg_temp.act(pg_temp.i('dan'));
  perform public.create_moment(m3, 'Dan reads #读书 too', '[]', null, null, null, 'friends', '{}', '{}', null, '{}');
  perform pg_temp.act(pg_temp.i('eve'));
  perform public.create_moment(m4, 'Eve is a stranger #读书', '[]', null, null, null, 'friends', '{}', '{}', null, '{}');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.create_moment(m5, 'No tags at all, just C# and a#b', '[]', null, null, null, 'friends', '{}', '{}', null, '{}');
  perform pg_temp.root();

  select p.tags into got from public.moments_posts p where p.id = m1;
  perform pg_temp.expect(got = array['读书', 'travel'], 'a Moment keeps the tags written in it');
  select p.tags into got from public.moments_posts p where p.id = m5;
  perform pg_temp.expect(got = '{}', 'C# and a#b are not tags');
  perform pg_temp.expect(
    not exists (select 1 from information_schema.role_table_grants
      where table_name = 'moments_posts' and grantee in ('anon', 'authenticated')),
    'the table is still closed to clients; the tags are only read through the feed'
  );

  -- The feed with a tag: only what the person may see.
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(
    (select array_agg(f.id) from public.moments_feed(20, null, null, null, null, '读书') f) = array[m1],
    'a friend of bob sees bob''s shared post under the tag, not the private one, a stranger''s or a friend of a friend''s'
  );
  perform pg_temp.expect(
    (select array_agg(f.id) from public.moments_feed(20, null, null, null, null, '#读书') f) = array[m1],
    'a hash in front of the tag does not matter'
  );
  perform pg_temp.expect(
    pg_temp.cnt('select 1 from public.moments_feed(20, null, null, null, null, ''x y'')') = 0
      and pg_temp.cnt('select 1 from public.moments_feed(20, null, null, null, null, ''nothing'')') = 0,
    'a tag that is not one, or not used, finds nothing'
  );
  perform pg_temp.expect(
    pg_temp.cnt('select 1 from public.moments_feed(20)') = 2,
    'the feed without a tag is as before'
  );
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(
    (select count(*) from public.moments_feed(20, null, null, null, null, '读书')) = 3
      and (select array_agg(f.id order by f.created_at, f.id) from public.moments_feed(20, null, null, null, null, 'secret') f) = array[m2],
    'bob sees his own posts (private too) and his friends'' under a tag'
  );
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(
    (select array_agg(f.id) from public.moments_feed(20, null, null, null, null, '读书') f) = array[m4],
    'a stranger sees only their own'
  );

  -- The topics friends use, counted for what the person may see.
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(
    (select jsonb_object_agg(t.tag, t.post_count) from public.list_moment_hashtags() t) = '{"读书": 1, "travel": 1}'::jsonb,
    'topics: counts only cover posts the caller may see'
  );
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(
    (select jsonb_object_agg(t.tag, t.post_count) from public.list_moment_hashtags() t) = '{"读书": 3, "travel": 1, "secret": 1}'::jsonb
      and (select t.tag from public.list_moment_hashtags() t limit 1) = '读书',
    'topics: the most used first, with the person''s own private posts'
  );
  perform pg_temp.act(null);
  perform pg_temp.expect(
    pg_temp.state('select * from public.list_moment_hashtags()') = '42501'
      and pg_temp.state('select public.hashtag_overview(''x'')') = '42501',
    'no topics without signing in'
  );

  -- Hiding a friend's Moments hides them under tags as well.
  perform pg_temp.root();
  insert into public.moments_friend_prefs (owner_id, friend_id, hide_theirs)
  values (pg_temp.i('cat'), pg_temp.i('bob'), true);
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(
    pg_temp.cnt('select 1 from public.moments_feed(20, null, null, null, null, ''读书'')') = 0
      and pg_temp.cnt('select 1 from public.list_moment_hashtags()') = 0,
    'a friend whose Moments you hid is not in a topic either'
  );
  perform pg_temp.expect(
    (public.hashtag_overview('读书') ->> 'moments')::integer = 0,
    'nor in the count of the search'
  );
  perform pg_temp.root();
  delete from public.moments_friend_prefs;

  -- Unfriending removes a post from the topic at once.
  delete from public.friendships
  where least(user_low_id, user_high_id) = least(pg_temp.i('bob'), pg_temp.i('cat'))
    and greatest(user_low_id, user_high_id) = greatest(pg_temp.i('bob'), pg_temp.i('cat'));
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(
    pg_temp.cnt('select 1 from public.moments_feed(20, null, null, null, null, ''读书'')') = 0,
    'after unfriending the topic no longer shows their posts'
  );
  perform pg_temp.root();
  insert into public.friendships (user_low_id, user_high_id)
  values (least(pg_temp.i('bob'), pg_temp.i('cat')), greatest(pg_temp.i('bob'), pg_temp.i('cat')));

  -- The old signature is gone and the new one is for signed-in people.
  perform pg_temp.expect(
    not exists (select 1 from pg_proc where proname = 'moments_feed' and pronargs = 5)
      and has_function_privilege('authenticated', 'public.moments_feed(integer, timestamptz, uuid, uuid, uuid, text)', 'execute')
      and not has_function_privilege('anon', 'public.moments_feed(integer, timestamptz, uuid, uuid, uuid, text)', 'execute'),
    'moments_feed has one signature, for signed-in people'
  );
  perform pg_temp.expect(
    pg_get_functiondef('public.moments_feed(integer, timestamptz, uuid, uuid, uuid, text)'::regprocedure) like '%mentioned_me%'
      and pg_get_functiondef('public.moments_feed(integer, timestamptz, uuid, uuid, uuid, text)'::regprocedure) like '%moments_interaction_visible%',
    'and keeps what the Moments 2.0 feed added'
  );
end $$;

-- ====================================== 3. the overview for the search
do $$
declare
  club uuid := pg_temp.i('club');
  overview jsonb;
begin
  -- Posts in the circle (written below too); here only the Moments count.
  perform pg_temp.act(pg_temp.i('bob'));
  overview := public.hashtag_overview('#读书');
  perform pg_temp.expect((overview ->> 'moments')::integer = 3 and overview ->> 'tag' = '读书', 'the overview counts the Moments bob may see');
  perform pg_temp.expect(public.hashtag_overview('a b') ->> 'tag' is null and (public.hashtag_overview('a b') ->> 'moments')::integer = 0, 'a word that is not a tag has no overview');
  perform pg_temp.root();
end $$;

-- ====================================== 4. circle posts: writing
do $$
declare
  club uuid := pg_temp.i('club');
  p1 uuid;
  p2 uuid;
  legacy uuid;
  row_value public.circle_posts%rowtype;
  state text;
  message text;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  p1 := public.create_circle_post(club, 'We read a lot this month #hiking', null, '  Our  month ' || E'\n' || ' of books ', array['Photos', 'x y', '12', 'photos']);
  insert into pg_temp.ids values ('p1', p1);
  perform pg_temp.root();
  select * into row_value from public.circle_posts where id = p1;
  perform pg_temp.expect(row_value.title = 'Our month of books', 'the title is one line with spaces folded');
  perform pg_temp.expect(row_value.tags = array['photos', 'hiking'], 'tags: the ones picked (cleaned, no repeats) then the ones written in the text');
  perform pg_temp.expect(row_value.featured_at is null, 'a new post is not featured');

  -- The three-argument call of an older app.
  perform pg_temp.act(pg_temp.i('bob'));
  legacy := public.create_circle_post(club, 'An older app posts #classic', null);
  perform pg_temp.expect((select tags from public.circle_posts where id = legacy) = array['classic'] and (select title from public.circle_posts where id = legacy) is null, 'a post from an older app has no title and the tags of its text');
  perform pg_temp.expect(pg_temp.state(format('select public.create_circle_post(%L, ''x'', null, %L)', club, repeat('t', 81))) = '22023', 'a title over 80 characters is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.create_circle_post(%L, '' '', null, ''only a title'')', club)) = '22023', 'a title alone is not a post');
  perform pg_temp.expect((select title from public.circle_posts where id = public.create_circle_post(club, 'blank title', null, '   ')) is null, 'a blank title is no title');
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_circle_post(%L, ''hello'', null, ''Hi'')', club)) = '42501', 'only members post');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select public.create_circle_post(%L, ''hello'')', club)) = '42501', 'and only signed-in people');

  -- Timed out.
  perform pg_temp.root();
  update public.circle_members set timed_out_until = now() + interval '1 hour' where circle_id = club and user_id = pg_temp.i('cat');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_circle_post(%L, ''muted'', null, ''Hi'')', club)) = '42501', 'a member who is timed out cannot post');
  perform pg_temp.root();
  update public.circle_members set timed_out_until = null where circle_id = club and user_id = pg_temp.i('cat');

  -- Raid lockdown: newcomers of the burst post no links.
  perform public.ensure_circle_security(club);
  update public.circle_security set lockdown_until = now() + interval '1 hour', lockdown_window_from = now() - interval '1 hour' where circle_id = club;
  perform pg_temp.act(pg_temp.i('bob'));
  message := pg_temp.msg(format('select public.create_circle_post(%L, ''see https://example.com'', null, ''Link'')', club));
  perform pg_temp.expect(message like 'New members cannot post links%', 'during a lockdown a newcomer cannot post a link in the text');
  message := pg_temp.msg(format('select public.create_circle_post(%L, ''hi'', null, ''www.example.com'')', club));
  perform pg_temp.expect(message like 'New members cannot post links%', 'nor in the title');
  perform pg_temp.expect(pg_temp.state(format('select public.create_circle_post(%L, ''no link here'', null, ''Fine'')', club)) = 'ok', 'a post without a link is fine');
  perform pg_temp.expect(pg_temp.msg(format('select public.update_circle_post(%L, ''Fine'', ''now with https://example.com'', ''{}'')', p1)) like 'New members cannot post links%', 'and an edit cannot add one');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_circle_post(%L, ''see https://example.com'', null, ''Mod'')', club)) = 'ok', 'the owner is not a newcomer');
  perform pg_temp.root();
  update public.circle_security set lockdown_until = null where circle_id = club;

  -- Editing.
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.update_circle_post(%L, ''Mine now'', ''x'', ''{}'')', p1)) = '42501', 'only the author edits a post');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.update_circle_post(%L, ''Mod edit'', ''x'', ''{}'')', p1)) = '42501', 'not even the owner');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.update_circle_post(p1, 'A new title', 'Second draft, no tags in the text', array['Books']);
  perform pg_temp.root();
  select * into row_value from public.circle_posts where id = p1;
  perform pg_temp.expect(row_value.title = 'A new title' and row_value.body = 'Second draft, no tags in the text' and row_value.tags = array['books'], 'an edit replaces the title, the text and the tags');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.update_circle_post(p1, null, 'Second draft, no tags in the text', '{}');
  perform pg_temp.root();
  select * into row_value from public.circle_posts where id = p1;
  perform pg_temp.expect(row_value.title is null and row_value.tags = '{}', 'a title and tags can be taken away');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.update_circle_post(%L, ''t'', '' '', ''{}'')', p1)) = '22023', 'a post without a text or a picture is refused');
  perform public.update_circle_post(p1, 'Back again', 'Text with #again', array['x']);
  perform pg_temp.root();
  perform pg_temp.expect((select tags from public.circle_posts where id = p1) = array['x', 'again'], 'the tags of an edit are the picked ones then the written ones');
end $$;

-- ====================================== 5. featuring
do $$
declare
  club uuid := pg_temp.i('club');
  p1 uuid := pg_temp.i('p1');
  audits integer;
  detail jsonb;
  post jsonb;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_post_featured(%L, true)', p1)) = '42501', 'a member cannot feature a post, not even their own');
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_post_featured(%L, true)', p1)) = '42501', 'nor an outsider');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(public.set_circle_post_featured(p1, true), 'the owner features a post');
  perform pg_temp.root();
  perform pg_temp.expect((select featured_at is not null and featured_by = pg_temp.i('ada') from public.circle_posts where id = p1), 'when and by whom is kept');
  select count(*) into audits from public.circle_audit_log where circle_id = club and action = 'post_feature' and target_id = p1;
  perform pg_temp.expect(audits = 1, 'featuring is in the audit log');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_post_featured(p1, true);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_audit_log where action = 'post_feature' and target_id = p1) = 1, 'featuring a featured post changes and logs nothing');

  -- The circle detail carries it.
  perform pg_temp.act(pg_temp.i('bob'));
  detail := public.get_circle_detail(club);
  select e into post from jsonb_array_elements(detail -> 'posts') e where (e ->> 'id')::uuid = p1;
  perform pg_temp.expect(post ->> 'title' = 'Back again' and post -> 'tags' = '["x", "again"]'::jsonb and post ->> 'featured_at' is not null, 'the circle detail has the title, the tags and the time it was featured');
  perform pg_temp.expect((post ->> 'can_feature_post')::boolean = false and (post ->> 'can_manage_post')::boolean = true, 'a member can manage their post but not feature it');
  perform pg_temp.act(pg_temp.i('ada'));
  detail := public.get_circle_detail(club);
  select e into post from jsonb_array_elements(detail -> 'posts') e where (e ->> 'id')::uuid = p1;
  perform pg_temp.expect((post ->> 'can_feature_post')::boolean, 'a moderator can');
  perform pg_temp.expect(post -> 'author' ? 'bio' and post ? 'like_count' and post ? 'comments', 'and the rest of the post is as before');
  perform pg_temp.expect(pg_get_functiondef('public.get_circle_detail(uuid)'::regprocedure) like '%visible_profile_bio%', 'the profile visibility rule stays in the circle detail');

  perform pg_temp.root();
  perform pg_temp.expect(pg_get_functiondef('public.get_circle_detail(uuid)'::regprocedure) not like '%''bio'', author.bio%' and pg_get_functiondef('public.get_circle_detail(uuid)'::regprocedure) not like '%''bio'', p.bio%' and pg_get_functiondef('public.get_circle_detail(uuid)'::regprocedure) not like '%''bio'', comment_author.bio%', 'no bare bio came back');

  -- A suspended circle (K1) is shut to this too.
  update public.circles set disabled_mode = 'suspend', disabled_at = now() where id = club;
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_post_featured(%L, false)', p1)) = '42501', 'a suspended circle cannot feature');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.update_circle_post(%L, ''t'', ''x'', ''{}'')', p1)) = '42501', 'nor edit');
  perform pg_temp.expect(pg_temp.state(format('select public.create_circle_post(%L, ''x'', null, ''t'')', club)) <> 'ok', 'nor post');
  perform pg_temp.root();
  update public.circles set disabled_mode = null, disabled_at = null where id = club;

  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(not public.set_circle_post_featured(p1, false), 'and un-features');
  perform pg_temp.root();
  perform pg_temp.expect((select featured_at is null and featured_by is null from public.circle_posts where id = p1) and exists (select 1 from public.circle_audit_log where action = 'post_unfeature' and target_id = p1), 'un-featuring clears it and is logged');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_post_featured(p1, true);
  perform pg_temp.root();
end $$;

-- ====================================== 6. what shows a post: saved, reported
do $$
declare
  club uuid := pg_temp.i('club');
  p1 uuid := pg_temp.i('p1');
  r uuid;
  snap jsonb;
  extra jsonb;
begin
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.save_item('circle_post', p1);
  select i.extra into extra from public.list_saved_items() i where i.target_id = p1;
  perform pg_temp.expect(extra ->> 'post_title' = 'Back again' and extra -> 'post_tags' = '["x", "again"]'::jsonb and extra ->> 'circle_name' = 'Book Club', 'a kept post tells its title and tags');
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.list_saved_items()') = 0, 'and nobody else has it');

  perform pg_temp.act(pg_temp.i('cat'));
  r := public.report_circle_post(p1, 'spam', 'looks off');
  perform pg_temp.root();
  select snapshot into snap from public.reports where id = r;
  perform pg_temp.expect(snap ->> 'title' = 'Back again' and snap ->> 'post_title' = 'Back again' and snap -> 'post_tags' = '["x", "again"]'::jsonb, 'a report keeps the post''s title and tags');
  perform pg_temp.expect(snap ->> 'body' like 'Text with%' and snap ->> 'circle_name' = 'Book Club', 'and what it kept before');
  -- A post without a title is labelled by its words, as before.
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.update_circle_post(p1, null, 'Text with #again', '{}');
  perform pg_temp.act(pg_temp.i('cat'));
  r := public.report_circle_post(p1, 'spam', '');
  perform pg_temp.root();
  select snapshot into snap from public.reports where id = r;
  perform pg_temp.expect(snap ->> 'title' = 'Text with #again' and snap -> 'post_title' = 'null'::jsonb, 'a post without a title is labelled by its words');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.update_circle_post(p1, 'Back again', 'Text with #again', array['x']);
  perform pg_temp.root();
end $$;

-- ====================================== 7. the overview and tags in a circle
do $$
declare
  club uuid := pg_temp.i('club');
  overview jsonb;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  overview := public.hashtag_overview('again');
  perform pg_temp.expect(overview -> 'circles' -> 0 ->> 'name' = 'Book Club' and (overview -> 'circles' -> 0 ->> 'post_count')::integer = 1, 'the overview names the circles that have the tag');
  perform pg_temp.act(pg_temp.i('dan'));
  overview := public.hashtag_overview('again');
  perform pg_temp.expect(overview -> 'circles' = '[]'::jsonb, 'a person who is not in the circle is told nothing about it');
  perform pg_temp.root();
  update public.circles set disabled_mode = 'suspend', disabled_at = now() where id = club;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(public.hashtag_overview('again') -> 'circles' = '[]'::jsonb, 'nor of a suspended one');
  perform pg_temp.root();
  update public.circles set disabled_mode = null, disabled_at = null where id = club;
end $$;

-- ====================================== 8. the AI guard
do $$
declare
  club uuid := pg_temp.i('club');
  gp uuid;
  gp2 uuid;
  review uuid;
  listed jsonb;
begin
  perform pg_temp.root();
  perform vault.create_secret('http://127.0.0.1:54321/functions/v1', 'wecord_functions_url');
  perform vault.create_secret('b8-test-secret', 'wecord_dispatch_secret');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_ai_guard(club, true, 'joined_days', 3, 10, 'hold');
  perform pg_temp.root();
  perform pg_temp.expect((select check_constraint_ok from (select pg_get_constraintdef(oid) like '%circle_post%' and pg_get_constraintdef(oid) like '%task_item%' and pg_get_constraintdef(oid) like '%circle_event%' as check_constraint_ok from pg_constraint where conname = 'guard_item_reviews_type') q), 'the guard accepts posts and still the rest');

  perform pg_temp.act(pg_temp.i('cat'));
  gp := public.create_circle_post(club, 'Win a free prize, click now', null, 'Free prize inside');
  perform pg_temp.act(pg_temp.i('ada'));
  gp2 := public.create_circle_post(club, 'A moderator''s post', null, 'Rules');
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.guard_item_reviews r where r.item_type = 'circle_post' and r.item_id = gp and r.circle_id = club and r.actor_id = pg_temp.i('cat')), 'a new member''s post is recorded for the check');
  perform pg_temp.expect((select r.state from public.guard_item_reviews r where r.item_id = gp) = 'checking', 'and is being checked, not held back');
  perform pg_temp.expect(not exists (select 1 from public.guard_item_reviews r where r.item_id = gp2), 'a moderator''s post is not');
  perform pg_temp.expect((select t.title from public.guard_item_text('circle_post', gp) t) = 'Free prize inside' and (select t.detail from public.guard_item_text('circle_post', gp) t) = 'Win a free prize, click now', 'the guard reads the title, and the text as the detail');

  select r.id into review from public.guard_item_reviews r where r.item_id = gp;
  perform public.finish_guard_item_review(review, 'spam', 'Looks like spam', '看起来像垃圾信息', null);
  perform pg_temp.act(pg_temp.i('ada'));
  select jsonb_agg(to_jsonb(l)) into listed from public.list_guard_item_reviews(club) l;
  perform pg_temp.expect(listed -> 0 ->> 'item_type' = 'circle_post' and listed -> 0 ->> 'title' = 'Free prize inside' and listed -> 0 ->> 'verdict' = 'spam', 'what the AI flags is in the review queue with the post''s title');
  perform pg_temp.expect(public.count_guard_item_reviews(club) = 1, 'and in the count');
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.circle_audit_log where circle_id = club and action = 'guard_item_flag' and changes ->> 'item_type' = 'circle_post'), 'the flag is audited');

  -- A deleted post leaves the queue.
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.delete_circle_post(gp);
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(public.count_guard_item_reviews(club) = 0, 'a deleted post leaves the queue');
  perform pg_temp.root();

  -- Changing the title checks again (after a minute).
  perform pg_temp.act(pg_temp.i('cat'));
  gp := public.create_circle_post(club, 'hello', null, 'Hello');
  perform pg_temp.root();
  update public.guard_item_reviews set created_at = now() - interval '2 minutes' where item_id = gp;
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.update_circle_post(gp, 'Buy now', 'hello', '{}');
  perform pg_temp.root();
  perform pg_temp.expect((select r.state from public.guard_item_reviews r where r.item_id = gp) in ('checking', 'released'), 'an edited title is checked again');
  perform pg_temp.expect((select r.created_at > now() - interval '1 minute' from public.guard_item_reviews r where r.item_id = gp), 'with a new time');
end $$;

-- ====================================== 9. the featured tab
do $$
declare
  club uuid := pg_temp.i('club');
  plazac uuid := pg_temp.i('plazac');
  g1 uuid := pg_temp.i('g1');
  tabs jsonb;
  tab jsonb;
begin
  perform pg_temp.expect(exists (select 1 from public.conversation_tab_kinds where kind = 'featured_posts' and target_type = 'none'), 'featured_posts is a tab kind without a target');
  perform pg_temp.act(pg_temp.i('ada'));
  tab := public.add_conversation_tab(plazac, 'featured_posts', null, 'Featured');
  perform pg_temp.expect(tab is not null, 'a moderator adds it under a circle channel');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''featured_posts'', null, ''Featured'')', g1)) <> 'ok', 'a group chat has no circle, so it cannot');
  perform pg_temp.expect(pg_temp.state(format('select public.add_conversation_tab(%L, ''featured_posts'', ''x'', ''Featured'')', plazac)) <> 'ok', 'and it has no target');
  tabs := public.get_conversation_tabs(plazac);
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(tabs -> 'tabs') e where e ->> 'kind' = 'featured_posts' and (e ->> 'available')::boolean and e ->> 'circle_id' = club::text), 'it is listed with the circle');
  perform pg_temp.root();
  update public.circles set disabled_mode = 'suspend', disabled_at = now() where id = club;
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.get_conversation_tabs(%L, true)', plazac)) = 'P0002', 'a suspended circle shows no tabs at all (the channel cannot be read)');
  perform pg_temp.root();
  update public.circles set disabled_mode = null, disabled_at = null where id = club;
  perform pg_temp.expect(pg_get_functiondef('public.get_conversation_tabs(uuid, boolean)'::regprocedure) like '%check_in_boards%' and pg_get_functiondef('public.get_conversation_tabs(uuid, boolean)'::regprocedure) like '%''kb'' then home_circle%', 'the tabs of earlier kinds are as they were');
end $$;

-- ====================================== 10. the push
do $$
declare
  club uuid := pg_temp.i('club');
  p2 uuid;
  claimed record;
  n integer;
begin
  perform pg_temp.root();
  update public.circle_post_feature_notices set push_claimed_at = now();
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
  values
    (pg_temp.i('bob'), 'https://push.example/bob-zh', repeat('k', 60), repeat('a', 20), 'zh'),
    (pg_temp.i('bob'), 'https://push.example/bob-en', repeat('k', 60), repeat('a', 20), 'en'),
    (pg_temp.i('ada'), 'https://push.example/ada-en', repeat('k', 60), repeat('a', 20), 'en');
  perform pg_temp.act(pg_temp.i('bob'));
  p2 := public.create_circle_post(club, 'Pictures from <b>the lake</b> trip', null, 'Lake <trip>');
  perform pg_temp.root();
  insert into pg_temp.ids values ('p2', p2);

  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_post_featured(p2, true);
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.circle_post_feature_notices where post_id = p2 and user_id = pg_temp.i('bob') and actor_id = pg_temp.i('ada')), 'featuring writes one notice for the author');

  create temp table claimed_featured on commit drop as select * from public.claim_featured_post_pushes();
  perform pg_temp.expect((select count(*) from claimed_featured where title = '你的帖子被设为精华' and body = '「Book Club」的版主把你的帖子「Lake trip」设为了精华。') = 1, 'the Chinese device gets Chinese words, with the circle and the title');
  perform pg_temp.expect((select count(*) from claimed_featured where title = 'Your post was featured' and body = 'A moderator featured your post "Lake trip" in Book Club.') = 1, 'the English one gets English');
  perform pg_temp.expect((select count(*) from claimed_featured) = 2, 'one push per device of the author, none for the moderator');
  perform pg_temp.expect((select count(*) from claimed_featured where url = '/#/circles/' || club::text || '/posts/' || p2::text and tag = 'featured-' || p2::text) = 2, 'a tap opens the post');
  perform pg_temp.expect((select count(*) from claimed_featured where body like '%<%' or body like '%>%') = 0, 'angle brackets are cleaned away');
  perform pg_temp.expect((select count(*) from public.claim_featured_post_pushes()) = 0, 'a push is claimed once');

  -- Featuring again does not push again.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_post_featured(p2, false);
  perform public.set_circle_post_featured(p2, true);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_post_feature_notices where post_id = p2) = 1 and (select count(*) from public.claim_featured_post_pushes()) = 0, 'the same post never pushes twice');

  -- A moderator featuring their own post tells nobody.
  perform pg_temp.act(pg_temp.i('ada'));
  p2 := public.create_circle_post(club, 'mine', null, 'Mine');
  perform public.set_circle_post_featured(p2, true);
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.circle_post_feature_notices where post_id = p2), 'featuring your own post sends nothing');
end $$;

-- ====================================== 11. when the push is not sent
do $$
declare
  club uuid := pg_temp.i('club');
  bob uuid := pg_temp.i('bob');
  ada uuid := pg_temp.i('ada');
  p uuid;
  n integer;
begin
  -- Each case: a post of bob's, featured by ada, claimed.
  perform pg_temp.act(bob);
  p := public.create_circle_post(club, 'muted circle', null, 'Muted');
  perform pg_temp.root();
  insert into public.circle_notification_settings (circle_id, user_id, level) values (club, bob, 'none')
  on conflict (circle_id, user_id) do update set level = 'none';
  perform pg_temp.act(ada);
  perform public.set_circle_post_featured(p, true);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.claim_featured_post_pushes()) = 0, 'a circle set to none sends nothing');
  delete from public.circle_notification_settings where circle_id = club and user_id = bob;

  perform pg_temp.act(bob);
  p := public.create_circle_post(club, 'blocked', null, 'Blocked');
  perform pg_temp.root();
  insert into public.blocks (blocker_id, blocked_id) values (bob, ada);
  perform pg_temp.act(ada);
  perform public.set_circle_post_featured(p, true);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.claim_featured_post_pushes()) = 0, 'nothing across a block');
  delete from public.blocks;

  perform pg_temp.act(bob);
  p := public.create_circle_post(club, 'suspended circle', null, 'Suspended');
  perform pg_temp.act(ada);
  perform public.set_circle_post_featured(p, true);
  perform pg_temp.root();
  update public.circles set disabled_mode = 'suspend', disabled_at = now() where id = club;
  perform pg_temp.expect((select count(*) from public.claim_featured_post_pushes()) = 0, 'nothing from a suspended circle');
  update public.circles set disabled_mode = null, disabled_at = null where id = club;

  perform pg_temp.act(bob);
  p := public.create_circle_post(club, 'stale', null, 'Stale');
  perform pg_temp.act(ada);
  perform public.set_circle_post_featured(p, true);
  perform pg_temp.root();
  update public.circle_post_feature_notices set created_at = now() - interval '20 minutes' where post_id = p;
  perform pg_temp.expect((select count(*) from public.claim_featured_post_pushes()) = 0, 'a notice that waited too long sends nothing');
  perform pg_temp.expect((select push_claimed_at is not null from public.circle_post_feature_notices where post_id = p), 'and is closed');

  perform pg_temp.act(bob);
  p := public.create_circle_post(club, 'removed', null, 'Removed');
  perform pg_temp.act(ada);
  perform public.set_circle_post_featured(p, true);
  perform pg_temp.act(bob);
  perform public.delete_circle_post(p);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.claim_featured_post_pushes()) = 0, 'a post that is gone sends nothing');

  perform pg_temp.act(bob);
  p := public.create_circle_post(club, 'unfeatured', null, 'Unfeatured');
  perform pg_temp.act(ada);
  perform public.set_circle_post_featured(p, true);
  perform public.set_circle_post_featured(p, false);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.claim_featured_post_pushes()) = 0, 'nor one that is not featured any more');

  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.state('select * from public.claim_featured_post_pushes()') = '42501', 'only the service role claims pushes');
  perform pg_temp.root();
  perform pg_temp.expect(has_function_privilege('service_role', 'public.claim_featured_post_pushes()', 'execute'), 'the dispatch function can');
  perform pg_temp.expect(pg_get_functiondef('public.claim_featured_post_pushes()'::regprocedure) like '%s.language = ''zh''%', 'it words each device in its language');
  perform pg_temp.expect(pg_get_functiondef('public.run_later_dispatch()'::regprocedure) not like '%featured%', 'run_later_dispatch is not touched');
end $$;

-- ====================================== 12. leaving, and the data
do $$
declare
  club uuid := pg_temp.i('club');
  bob uuid := pg_temp.i('bob');
  ada uuid := pg_temp.i('ada');
  p uuid;
  exported jsonb;
begin
  perform pg_temp.act(bob);
  p := public.create_circle_post(club, 'will be waiting', null, 'Waiting');
  perform pg_temp.act(ada);
  perform public.set_circle_post_featured(p, true);
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.circle_post_feature_notices where post_id = p and push_claimed_at is null), 'a notice waits for the dispatch');

  -- The export is for the data-export function.
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.state(format('select public.export_my_circle_posts(%L)', bob)) = '42501', 'a signed-in person cannot call the export');
  perform pg_temp.root();
  exported := public.export_my_circle_posts(bob);
  perform pg_temp.expect(jsonb_array_length(exported -> 'posts') >= 3, 'bob''s posts are exported');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(exported -> 'posts') e where e ->> 'title' = 'Back again' and e -> 'tags' = '["x", "again"]'::jsonb and e ->> 'circle' = 'Book Club' and (e ->> 'featured')::boolean and e ->> 'text' = 'Text with #again'), 'with title, text, tags, circle and the featured mark');
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(exported -> 'posts') e where e ->> 'text' like 'A moderator%'), 'never other people''s posts');
  perform pg_temp.expect(public.export_my_circle_posts(pg_temp.i('eve')) = '{"posts": []}'::jsonb, 'a stranger exports nothing');
  perform pg_temp.expect(has_function_privilege('service_role', 'public.export_my_circle_posts(uuid)', 'execute') and not has_function_privilege('authenticated', 'public.export_my_circle_posts(uuid)', 'execute'), 'only the data-export function can');
  delete from public.circle_members where circle_id = club and user_id = bob;
  exported := public.export_my_circle_posts(bob);
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(exported -> 'posts') e where e ? 'circle'), 'after leaving the circle its name is left out');
  insert into public.circle_members (circle_id, user_id, role) values (club, bob, 'member');

  -- Deleting the account.
  update public.profiles set deleted_at = now() where id = bob;
  perform pg_temp.expect(not exists (select 1 from public.circle_post_feature_notices where user_id = bob), 'deleting an account erases the pushes still waiting');
  perform pg_temp.expect(not exists (select 1 from public.moments_posts where author_id = bob), 'the Moments with their tags go when the account is deleted (Moments 2.0 erases them)');
  perform pg_temp.expect(exists (select 1 from public.circle_posts where author_id = bob), 'the circle posts go when the account itself is removed (cascade), not earlier');
  delete from public.profiles where id = bob;
  perform pg_temp.expect(not exists (select 1 from public.circle_posts where author_id = bob), 'and then so do the circle posts');
  perform pg_temp.expect(exists (select 1 from public.circle_posts where author_id = ada), 'other people''s posts stay');

  -- Nothing in the older dispatchers was rewritten.
  perform pg_temp.expect(
    not exists (select 1 from pg_proc where proname = 'run_later_dispatch' and pg_get_functiondef(oid) like '%hashtag%'),
    'run_later_dispatch is not touched'
  );
  perform pg_temp.expect(
    (select count(*) from cron.job where jobname like '%hashtag%' or jobname like '%featured%') = 0,
    'and no new cron job was needed'
  );
end $$;

\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'topics and circle posts 2.0: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
