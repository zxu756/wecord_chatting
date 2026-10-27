-- Behaviour checks for the L6 scale work (migrations 202610281200-202610281220):
-- a page of a big circle's or group's members, the member_limit of
-- get_circle_detail, and the push claim in batches of people. Run by
-- test/supabase/scale_pages_test.dart against the local database: it applies
-- every migration after the local baseline in a transaction, plays people
-- through their roles, and rolls everything back. Run from the repository
-- root.
--
-- What it walks through: that pages put together are the whole list in the
-- order get_circle_detail uses, that a search finds the same people as the
-- filter would, who may read a list (members only, not a suspended circle,
-- not people who cannot see a channel), that member_limit keeps the caller,
-- and that the batches of a push claim are the whole claim, once, with the
-- same people left out (muted, do not disturb, blocked, sender).
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
\i supabase/migrations/202610281200_l6_hot_queries.sql
\i supabase/migrations/202610281210_l6_member_pages.sql
\i supabase/migrations/202610281220_l6_push_pages.sql
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

create function pg_temp.root() returns void language plpgsql as $$
begin
  execute 'reset role';
end $$;

create function pg_temp.refused(statement text) returns boolean language plpgsql as $$
begin
  execute statement;
  return false;
exception when others then
  return true;
end $$;

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create function pg_temp.i(n text) returns uuid language sql as $$ select id from pg_temp.ids where name = n $$;

grant execute on all functions in schema pg_temp to public;

-- ------------------------------------------------------------------ cast
-- Ada owns the circle "Big" and the group "Plan"; Bob, Cy, Dee, Eli and Fay
-- are members of both (Fay only of the circle). Gus is nobody's member.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '@l6.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from (values ('a1','ada'),('a2','bob'),('a3','cy'),('a4','dee'),('a5','eli'),('a6','fay'),('a7','gus')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '_l6', initcap(name)
from (values ('a1','ada'),('a2','bob'),('a3','cy'),('a4','dee'),('a5','eli'),('a6','fay'),('a7','gus')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || n)::uuid
from (values ('a1','ada'),('a2','bob'),('a3','cy'),('a4','dee'),('a5','eli'),('a6','fay'),('a7','gus')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(pg_temp.i('ada'), pg_temp.i(n)), greatest(pg_temp.i('ada'), pg_temp.i(n))
from (values ('bob'), ('cy'), ('dee'), ('eli'), ('fay'), ('gus')) v(n);

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'group', public.create_group_conversation('Plan', array[pg_temp.i('bob'), pg_temp.i('cy'), pg_temp.i('dee'), pg_temp.i('eli')]);
insert into pg_temp.ids select 'circle', public.create_circle('Big', array[pg_temp.i('bob'), pg_temp.i('cy'), pg_temp.i('dee'), pg_temp.i('eli'), pg_temp.i('fay')]);
select pg_temp.root();
insert into pg_temp.ids
select 'channel', cc.conversation_id from public.circle_channels cc where cc.circle_id = pg_temp.i('circle') order by cc.created_at limit 1;
insert into public.conversation_members (conversation_id, user_id, role)
select pg_temp.i('channel'), cm.user_id, cm.role
from public.circle_members cm where cm.circle_id = pg_temp.i('circle')
on conflict do nothing;
-- Bob has a nickname in the circle; Cy joined the circle after the others.
update public.circle_members set nickname = 'Zed' where circle_id = pg_temp.i('circle') and user_id = pg_temp.i('bob');
update public.circle_members set role = 'admin' where circle_id = pg_temp.i('circle') and user_id = pg_temp.i('eli');

-- ===================================== 1. a circle's members, a page at a time
do $$
declare
  c uuid := pg_temp.i('circle');
  everyone jsonb;
  seen jsonb := '[]';
  page jsonb;
  last_row jsonb;
  n integer := 0;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  everyone := public.get_circle_detail(c)->'members';
  perform pg_temp.expect(jsonb_array_length(everyone) = 6, 'circle: the detail lists the six members');
  perform pg_temp.expect(public.get_circle_detail(c)->'circle' ? 'member_count' and (public.get_circle_detail(c)->'circle'->>'member_count')::int = 6,
    'circle: the detail says how many there are');

  loop
    select coalesce(jsonb_agg(r order by (r->>'sort_rank')::int, r->>'sort_name', r->'profile'->>'id'), '[]') into page
    from public.list_circle_members_page(
      c, 2,
      (last_row->>'sort_rank')::integer, last_row->>'sort_name', (last_row->'profile'->>'id')::uuid, null) r;
    exit when jsonb_array_length(page) = 0 or n > 10;
    seen := seen || page;
    last_row := page->(jsonb_array_length(page) - 1);
    n := n + 1;
  end loop;
  perform pg_temp.expect(n = 3, 'circle: six members in pages of two are three pages (got ' || n || ')');
  perform pg_temp.expect(
    (select jsonb_agg(m->'profile'->'id') from jsonb_array_elements(seen) m)
      = (select jsonb_agg(m->'profile'->'id') from jsonb_array_elements(everyone) m),
    'circle: the pages together are the detail''s list, in its order');
  perform pg_temp.expect(
    (select jsonb_agg(m - 'sort_rank' - 'sort_name' order by m->'profile'->>'id') from jsonb_array_elements(seen) m)
      = (select jsonb_agg(m order by m->'profile'->>'id') from jsonb_array_elements(everyone) m),
    'circle: a member in a page is written exactly as in the detail');
  perform pg_temp.expect(
    (seen->0->'profile'->>'id')::uuid = pg_temp.i('ada') and seen->0->>'role' = 'owner',
    'circle: the owner comes first');
  perform pg_temp.expect(seen->1->>'role' = 'admin', 'circle: then the admins');

  perform pg_temp.expect(
    (select count(*) from public.list_circle_members_page(c, 50, null, null, null, 'ZED')) = 1,
    'circle: a search finds a nickname, in any case');
  perform pg_temp.expect(
    (select r->'profile'->>'username' from public.list_circle_members_page(c, 50, null, null, null, 'zed') r) = 'bob_l6',
    'circle: and it is Bob');
  perform pg_temp.expect(
    (select count(*) from public.list_circle_members_page(c, 50, null, null, null, 'cy_l6')) = 1,
    'circle: a search finds a username');
  perform pg_temp.expect(
    (select count(*) from public.list_circle_members_page(c, 50, null, null, null, 'nobody like this')) = 0,
    'circle: a search with no match is empty');
  perform pg_temp.expect(
    (select count(*) from public.list_circle_members_page(c, 1000)) = 6
      and (select count(*) from public.list_circle_members_page(c, 0)) = 1,
    'circle: the page size is kept between 1 and 200');

  -- member_limit keeps the first of them and the caller.
  perform pg_temp.act(pg_temp.i('fay'));
  everyone := public.get_circle_detail(c, 2)->'members';
  perform pg_temp.expect(jsonb_array_length(everyone) = 3, 'circle: a limit of 2 gives 2 and the caller (got ' || jsonb_array_length(everyone) || ')');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(everyone) m where (m->>'is_current_user')::boolean),
    'circle: the caller is in a limited list');
  perform pg_temp.expect((public.get_circle_detail(c, 2)->'circle'->>'member_count')::int = 6, 'circle: and the count is still all of them');
  perform pg_temp.expect(jsonb_array_length(public.get_circle_detail(c, 100)->'members') = 6, 'circle: a limit above the size gives everyone');
  perform pg_temp.expect(jsonb_array_length(public.get_circle_detail(c)->'members') = 6, 'circle: no limit is everyone');

  -- Strangers get nothing; the circle's members list is for members.
  perform pg_temp.act(pg_temp.i('gus'));
  perform pg_temp.expect((select count(*) from public.list_circle_members_page(c, 50)) = 0, 'circle: a stranger gets no page');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused(format('select * from public.list_circle_members_page(%L, 10)', c)), 'circle: nobody signed in is refused');

  -- A suspended circle shows nobody (as the detail).
  perform pg_temp.root();
  update public.circles set disabled_mode = 'suspend', disabled_at = now() where id = c;
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect((select count(*) from public.list_circle_members_page(c, 50)) = 0, 'circle: a suspended circle gives no page');
  perform pg_temp.root();
  update public.circles set disabled_mode = null, disabled_at = null where id = c;
end $$;

-- ===================================== 2. a conversation's members
do $$
declare
  g uuid := pg_temp.i('group');
  ch uuid := pg_temp.i('channel');
  u text;
  conv uuid;
  seen uuid[];
  expected uuid[];
  last_joined timestamptz;
  last_user uuid;
  page jsonb;
  n integer;
begin
  -- Cy may not see the channel (an overwrite on @everyone and Cy).
  perform pg_temp.root();
  insert into public.circle_channel_overwrites (channel_id, circle_id, user_id, allow, deny)
  select cc.id, cc.circle_id, pg_temp.i('cy'), 0, public.circle_permission_bits(array['view_channel'])
  from public.circle_channels cc where cc.conversation_id = ch;

  foreach u in array array['ada', 'bob', 'cy', 'gus'] loop
    foreach conv in array array[g, ch] loop
      perform pg_temp.act(pg_temp.i(u));
      -- What the policy lets this person read of the members.
      expected := (select coalesce(array_agg(user_id order by user_id), '{}') from public.conversation_members where conversation_id = conv);
      seen := '{}'; last_joined := null; last_user := null; n := 0;
      loop
        select coalesce(jsonb_agg(r), '[]') into page
        from public.list_conversation_members_page(conv, 2, last_joined, last_user, null) r;
        exit when jsonb_array_length(page) = 0 or n > 20;
        seen := seen || (select array_agg((r->'profile'->>'id')::uuid) from jsonb_array_elements(page) r);
        select cm.joined_at, cm.user_id into last_joined, last_user
        from public.conversation_members cm
        where cm.conversation_id = conv
          and cm.user_id = (page->(jsonb_array_length(page) - 1)->'profile'->>'id')::uuid;
        n := n + 1;
      end loop;
      perform pg_temp.expect(
        (select coalesce(array_agg(x order by x), '{}') from unnest(seen) x) = expected,
        'members: pages as ' || u || ' in ' || (case when conv = g then 'the group' else 'the channel' end) || ' are what the policy shows ('
          || coalesce(cardinality(seen), 0) || ' of ' || cardinality(expected) || ')');
    end loop;
  end loop;

  -- The ones the policy shows a member of the group: all five, and for Gus nobody.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect((select count(*) from public.list_conversation_members_page(g, 50)) = 5, 'members: a member sees the five');
  perform pg_temp.expect((select r->>'role' from public.list_conversation_members_page(g, 1) r) = 'owner', 'members: oldest first, and the owner joined first');
  perform pg_temp.expect(
    (select count(*) from public.list_conversation_members_page(g, 50, null, null, 'DEE')) = 1,
    'members: a search finds a name');
  perform pg_temp.act(pg_temp.i('gus'));
  perform pg_temp.expect((select count(*) from public.list_conversation_members_page(g, 50)) = 0, 'members: a stranger gets nobody');
  -- Cy cannot see the channel: nobody but his own row.
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect((select count(*) from public.list_conversation_members_page(ch, 50)) <= 1, 'members: someone who cannot see the channel gets at most their own row');
  -- And the others do not see Cy there.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(not exists (
    select 1 from public.list_conversation_members_page(ch, 50) r where (r->'profile'->>'id')::uuid = pg_temp.i('cy')),
    'members: others do not see someone who cannot see the channel');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused(format('select * from public.list_conversation_members_page(%L, 10)', g)), 'members: nobody signed in is refused');
  perform pg_temp.root();
end $$;

-- ===================================== 3. the push claim in batches
-- Everyone has a device (Bob two). Cy muted the group, Dee set Do Not Disturb,
-- Eli blocked Ada: they hear nothing. So Bob (2 devices) is the only one.
-- Then they are let back one at a time.
insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
select pg_temp.i(n), 'https://push.example/l6/' || n || '/' || k, repeat('p', 50), repeat('a', 20), 'en'
from (values ('ada'), ('bob'), ('cy'), ('dee'), ('eli')) v(n), generate_series(1, 2) k
where k = 1 or n = 'bob';

create function pg_temp.say(conv uuid, body text) returns uuid language plpgsql as $$
declare mid uuid;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  mid := public.send_text_message(conv, body);
  perform pg_temp.root();
  return mid;
end $$;
grant execute on function pg_temp.say(uuid, text) to public;

-- The people (and devices) a claim hands out, all in one go.
create function pg_temp.claimed(msg uuid, sender text) returns text language sql as $$
  select coalesce(string_agg(recipient || ':' || devices, ',' order by recipient), '')
  from (
    select p.username as recipient, count(*) as devices
    from public.claim_push_delivery(msg, pg_temp.i(sender)) c
    join public.push_subscriptions s on s.id = c.subscription_id
    join public.profiles p on p.id = s.user_id
    group by p.username
  ) t
$$;
grant execute on function pg_temp.claimed(uuid, text) to public;

-- The same, in batches of [size] people.
create function pg_temp.claimed_in_batches(msg uuid, sender text, size integer) returns text language plpgsql as $$
declare
  cursor_user uuid;
  batch_people integer;
  batches integer := 0;
  result text := '';
  sizes text := '';
begin
  loop
    select count(distinct c.recipient_id), (array_agg(c.recipient_id order by c.recipient_id desc))[1]
    into batch_people, cursor_user
    from public.claim_push_delivery(msg, pg_temp.i(sender), cursor_user, size) c;
    exit when batch_people = 0 or batches > 20;
    batches := batches + 1;
    sizes := sizes || batch_people || ' ';
    exit when batch_people < size;
  end loop;
  return sizes;
end $$;
grant execute on function pg_temp.claimed_in_batches(uuid, text, integer) to public;

-- The rows of each batch put together (the first call claims the message).
create function pg_temp.batches(msg uuid, sender text, size integer) returns text language plpgsql as $$
declare
  cursor_user uuid;
  batch_people integer;
  n integer := 0;
  collected text[] := '{}';
  piece text;
begin
  loop
    create temp table if not exists pg_temp.batch_rows (recipient_id uuid, subscription_id uuid) on commit drop;
    truncate pg_temp.batch_rows;
    insert into pg_temp.batch_rows
    select c.recipient_id, c.subscription_id from public.claim_push_delivery(msg, pg_temp.i(sender), cursor_user, size) c;
    select count(distinct recipient_id), (array_agg(recipient_id order by recipient_id desc))[1] into batch_people, cursor_user from pg_temp.batch_rows;
    select string_agg(p.username || ':' || b.n, ',' order by p.username) into piece
    from (select recipient_id, count(*) as n from pg_temp.batch_rows group by recipient_id) b
    join public.profiles p on p.id = b.recipient_id;
    collected := collected || coalesce(piece, '');
    n := n + 1;
    exit when batch_people < size or n > 20;
  end loop;
  return array_to_string(array_remove(collected, ''), ',');
end $$;
grant execute on function pg_temp.batches(uuid, text, integer) to public;

do $$
declare
  g uuid := pg_temp.i('group');
  m1 uuid; m2 uuid; m3 uuid; m4 uuid;
  whole text;
begin
  perform pg_temp.root();
  -- Cy muted the group, Dee is on Do Not Disturb, Eli blocked Ada.
  update public.conversation_members set muted_until = now() + interval '1 day' where conversation_id = g and user_id = pg_temp.i('cy');
  insert into public.user_privacy_settings (user_id, presence_status) values (pg_temp.i('dee'), 'dnd')
  on conflict (user_id) do update set presence_status = 'dnd';
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('eli'), pg_temp.i('ada'));

  m1 := pg_temp.say(g, 'one');
  whole := pg_temp.claimed(m1, 'ada');
  perform pg_temp.expect(whole = 'bob_l6:2', 'claim: muted, Do Not Disturb and blocked people hear nothing, the sender neither (got ' || whole || ')');
  perform pg_temp.expect(pg_temp.claimed(m1, 'ada') = '', 'claim: a message is claimed once');

  -- A claim for someone who did not send it gives nothing, in any batch.
  m2 := pg_temp.say(g, 'two');
  perform pg_temp.expect(pg_temp.claimed(m2, 'bob') = '', 'claim: not for someone else''s message');
  perform pg_temp.expect(pg_temp.claimed(m2, 'ada') = 'bob_l6:2', 'claim: and it can still be claimed by the sender after');

  -- Let Cy and Dee back, unblock Eli: four people hear, Bob with two devices.
  update public.conversation_members set muted_until = null where conversation_id = g and user_id = pg_temp.i('cy');
  update public.user_privacy_settings set presence_status = 'online' where user_id = pg_temp.i('dee');
  delete from public.blocks where blocker_id = pg_temp.i('eli');

  m1 := pg_temp.say(g, 'three');
  whole := pg_temp.claimed(m1, 'ada');
  perform pg_temp.expect(whole = 'bob_l6:2,cy_l6:1,dee_l6:1,eli_l6:1', 'claim: everyone else hears, once per device (got ' || whole || ')');

  m3 := pg_temp.say(g, 'four');
  perform pg_temp.expect(pg_temp.batches(m3, 'ada', 1) = whole, 'claim: batches of one person put together are the whole claim (got ' || pg_temp.batches(m3, 'ada', 1) || ')');
  m4 := pg_temp.say(g, 'five');
  perform pg_temp.expect(pg_temp.batches(m4, 'ada', 3) = whole, 'claim: and batches of three');
  perform pg_temp.expect(pg_temp.batches(pg_temp.say(g, 'six'), 'ada', 4) = whole, 'claim: and a batch of exactly the number of people');
  perform pg_temp.expect(pg_temp.batches(pg_temp.say(g, 'seven'), 'ada', 100) = whole, 'claim: and one batch for all');

  m1 := pg_temp.say(g, 'eight');
  perform pg_temp.expect(pg_temp.claimed_in_batches(m1, 'ada', 3) = '3 1 ', 'claim: four people in batches of three are 3 then 1');

  -- A later batch of a message nobody claimed gives nothing; the first batch claims it.
  m2 := pg_temp.say(g, 'nine');
  perform pg_temp.expect(
    (select count(*) from public.claim_push_delivery(m2, pg_temp.i('ada'), pg_temp.i('bob'), 10)) = 0,
    'claim: a batch after the first of an unclaimed message is empty');
  perform pg_temp.expect(pg_temp.claimed(m2, 'ada') = whole, 'claim: and the message could still be claimed after');

  -- The old two-argument call is still there (the app's Edge Functions of before).
  perform pg_temp.expect(has_function_privilege('service_role', 'public.claim_push_delivery(uuid, uuid, uuid, integer)', 'execute'), 'claim: the service role can call it');
  perform pg_temp.expect(not has_function_privilege('authenticated', 'public.claim_push_delivery(uuid, uuid, uuid, integer)', 'execute'), 'claim: a signed-in person cannot');
  perform pg_temp.expect(not has_function_privilege('anon', 'public.claim_push_delivery(uuid, uuid, uuid, integer)', 'execute'), 'claim: nor anon');
  perform pg_temp.expect(not exists (select 1 from pg_proc where proname = 'claim_push_delivery' and pronargs = 2), 'claim: there is one function, not two');
end $$;

\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'scale pages: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
