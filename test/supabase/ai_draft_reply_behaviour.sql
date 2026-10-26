-- Behaviour checks for AI reply suggestions (F6: migration 202610280800). Run
-- by test/supabase/ai_draft_reply_test.dart against the local database: it
-- applies every migration after the local baseline in a transaction, plays
-- people through the service role, and rolls everything back. Run from the
-- repository root.
--
-- What it walks through: what the `draft_reply` action may read of a chat (the
-- person's, the group's and the circle's AI switches; a chat the person
-- locked, and the thread of one; chats they cannot read), which messages are
-- left out (recalled, expired, held by the AI guard, view-once, notices,
-- assistant replies, blocked senders either way), the limit, the order, how
-- senders are named, and who may call the function.
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
\i supabase/migrations/202610280800_ai_draft_reply.sql
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

grant execute on all functions in schema pg_temp to public;

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create function pg_temp.i(n text) returns uuid language sql as $$ select id from pg_temp.ids where name = n $$;
grant execute on function pg_temp.i(text) to public;


-- ------------------------------------------------------------------ cast
-- Ada owns the group G ("Plan") and the circle; Bob and Cy are members of
-- both. Dee is nobody's member. Ada is friends with Bob, Cy and Dee; Bob and
-- Cy are friends.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '@dr.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from (values ('d1','ada'),('d2','bob'),('d3','cy'),('d4','dee')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '_dr', initcap(name)
from (values ('d1','ada'),('d2','bob'),('d3','cy'),('d4','dee')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || n)::uuid
from (values ('d1','ada'),('d2','bob'),('d3','cy'),('d4','dee')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(x.a, x.b), greatest(x.a, x.b)
from (values
  (pg_temp.i('ada'), pg_temp.i('bob')),
  (pg_temp.i('ada'), pg_temp.i('cy')),
  (pg_temp.i('ada'), pg_temp.i('dee')),
  (pg_temp.i('bob'), pg_temp.i('cy'))
) x(a, b);

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'group', public.create_group_conversation('Plan', array[pg_temp.i('bob'), pg_temp.i('cy')]);
insert into pg_temp.ids select 'group2', public.create_group_conversation('Trip', array[pg_temp.i('bob'), pg_temp.i('cy')]);
insert into pg_temp.ids select 'circle', public.create_circle('Draft club', array[pg_temp.i('bob'), pg_temp.i('cy')]);
select pg_temp.root();
insert into pg_temp.ids
select 'channel', cc.conversation_id from public.circle_channels cc where cc.circle_id = pg_temp.i('circle') order by cc.created_at limit 1;
insert into public.conversation_members (conversation_id, user_id, role)
select pg_temp.i('channel'), cm.user_id, cm.role
from public.circle_members cm where cm.circle_id = pg_temp.i('circle')
on conflict do nothing;

-- A thread of the group "Plan".
insert into public.conversations (id, type) values ('00000000-0000-4000-8000-0000000000f1', 'thread');
insert into public.conversation_threads (parent_conversation_id, conversation_id, title)
values (pg_temp.i('group'), '00000000-0000-4000-8000-0000000000f1', 'A thread');
insert into pg_temp.ids values ('thread', '00000000-0000-4000-8000-0000000000f1');
insert into public.conversation_members (conversation_id, user_id)
select pg_temp.i('thread'), pg_temp.i(n) from (values ('ada'), ('bob'), ('cy')) v(n);

-- A message in [conv] from [who], [mins] minutes ago.
create function pg_temp.mk(who text, conv uuid, body text, mins integer default 30) returns uuid language plpgsql as $$
declare mid uuid;
begin
  insert into public.messages (conversation_id, sender_id, type, body, created_at)
  values (conv, pg_temp.i(who), 'text', body, now() - make_interval(mins => mins))
  returning id into mid;
  return mid;
end $$;
grant execute on function pg_temp.mk(text, uuid, text, integer) to public;

-- What the function answers for [who] in [conv].
create function pg_temp.ctx(who text, conv uuid, lim integer default 20) returns jsonb language sql as $$
  select public.ai_draft_context(pg_temp.i(who), conv, lim)
$$;
grant execute on function pg_temp.ctx(text, uuid, integer) to public;

create function pg_temp.status(who text, conv uuid) returns text language sql as $$
  select public.ai_draft_context(pg_temp.i(who), conv, 20)->>'status'
$$;
grant execute on function pg_temp.status(text, uuid) to public;

-- The bodies, oldest first, joined with " | ".
create function pg_temp.bodies(who text, conv uuid, lim integer default 20) returns text language sql as $$
  select coalesce(string_agg(e->>'body', ' | ' order by ord), '')
  from jsonb_array_elements(pg_temp.ctx(who, conv, lim)->'messages') with ordinality t(e, ord)
$$;
grant execute on function pg_temp.bodies(text, uuid, integer) to public;

-- ===================================== 1. the basics
do $$
declare g uuid := pg_temp.i('group'); r jsonb; first_msg jsonb;
begin
  perform pg_temp.expect(pg_temp.status('bob', g) = 'ok', 'basics: a member gets ok for an empty chat');
  perform pg_temp.expect(jsonb_array_length(pg_temp.ctx('bob', g)->'messages') = 0, 'basics: and no messages');

  perform pg_temp.mk('cy', g, 'one', 50);
  perform pg_temp.mk('ada', g, 'two', 40);
  perform pg_temp.mk('bob', g, 'three', 30);
  perform pg_temp.mk('cy', g, 'four', 20);

  perform pg_temp.expect(pg_temp.bodies('bob', g) = 'one | two | three | four', 'basics: oldest first (got ' || pg_temp.bodies('bob', g) || ')');
  perform pg_temp.expect(pg_temp.bodies('bob', g, 2) = 'three | four', 'basics: a limit keeps the newest messages, still oldest first');
  perform pg_temp.expect(pg_temp.bodies('bob', g, 0) = 'four', 'basics: a limit of zero is read as one');
  perform pg_temp.expect(pg_temp.bodies('bob', g, null) = 'one | two | three | four', 'basics: no limit is the default');

  r := pg_temp.ctx('bob', g);
  select e into first_msg from jsonb_array_elements(r->'messages') e where e->>'body' = 'three';
  perform pg_temp.expect((first_msg->>'mine')::boolean, 'basics: Bob''s own message is marked mine');
  select e into first_msg from jsonb_array_elements(r->'messages') e where e->>'body' = 'one';
  perform pg_temp.expect(not (first_msg->>'mine')::boolean and first_msg->>'sender' = 'Cy', 'basics: another member''s is not, and carries their name');
  perform pg_temp.expect(pg_temp.bodies('ada', g) = pg_temp.bodies('bob', g), 'basics: every member reads the same chat');

  -- The limit is capped at 30.
  insert into public.messages (conversation_id, sender_id, type, body, created_at)
  select g, pg_temp.i('cy'), 'text', 'bulk ' || lpad(n::text, 2, '0'), now() - make_interval(secs => 100 - n)
  from generate_series(1, 40) n;
  perform pg_temp.expect(jsonb_array_length(pg_temp.ctx('bob', g, 1000)->'messages') = 30, 'basics: never more than 30');
  perform pg_temp.expect(jsonb_array_length(pg_temp.ctx('bob', g)->'messages') = 20, 'basics: twenty by default');
  perform pg_temp.expect(pg_temp.bodies('bob', g, 1) = 'bulk 40', 'basics: the newest of them');
  delete from public.messages where body like 'bulk %';

  -- Other chats are not mixed in.
  perform pg_temp.mk('cy', pg_temp.i('group2'), 'in the other group');
  perform pg_temp.expect(pg_temp.bodies('bob', g) not like '%other group%', 'basics: only the chat asked for');

  -- A file or a picture carries its name.
  insert into public.messages (conversation_id, sender_id, type, body, attachment, created_at)
  values (g, pg_temp.i('cy'), 'file', '', '{"kind":"file","name":"itinerary.pdf"}', now() - interval '1 minute');
  select e into first_msg from jsonb_array_elements(pg_temp.ctx('bob', g, 1)->'messages') e;
  perform pg_temp.expect(first_msg->>'type' = 'file' and first_msg->>'attachment_name' = 'itinerary.pdf', 'basics: a file carries its name');
  delete from public.messages where type = 'file';

  -- A remark name is how the person sees someone.
  insert into public.contact_aliases (owner_id, friend_id, alias) values (pg_temp.i('bob'), pg_temp.i('cy'), 'Cy from work');
  select e into first_msg from jsonb_array_elements(pg_temp.ctx('bob', g)->'messages') e where e->>'body' = 'one';
  perform pg_temp.expect(first_msg->>'sender' = 'Cy from work', 'basics: the person''s own remark name for the sender');
  select e into first_msg from jsonb_array_elements(pg_temp.ctx('ada', g)->'messages') e where e->>'body' = 'one';
  perform pg_temp.expect(first_msg->>'sender' = 'Cy', 'basics: and nobody else''s');
  delete from public.contact_aliases;

  -- Bad input.
  perform pg_temp.expect(public.ai_draft_context(null, g, 20)->>'status' = 'not_found', 'basics: no person is not_found');
  perform pg_temp.expect(public.ai_draft_context(pg_temp.i('bob'), null, 20)->>'status' = 'not_found', 'basics: no chat is not_found');
  perform pg_temp.expect(pg_temp.status('bob', gen_random_uuid()) = 'not_found', 'basics: a chat that does not exist is not_found');
end $$;

-- ===================================== 2. who may read the chat
do $$
declare g uuid := pg_temp.i('group'); ch uuid := pg_temp.i('channel'); dm uuid; note uuid;
begin
  perform pg_temp.expect(pg_temp.status('dee', g) = 'not_found', 'access: a stranger''s group is not found');
  perform pg_temp.expect(pg_temp.status('dee', ch) = 'not_found', 'access: nor a stranger''s channel');
  perform pg_temp.expect(jsonb_array_length(pg_temp.ctx('dee', g)->'messages') = 0, 'access: and no messages come with it');

  perform pg_temp.mk('ada', ch, 'channel news');
  perform pg_temp.expect(pg_temp.status('bob', ch) = 'ok' and pg_temp.bodies('bob', ch) = 'channel news', 'access: a circle channel the person can read is read');

  -- Left a chat.
  delete from public.conversation_members where conversation_id = ch and user_id = pg_temp.i('bob');
  perform pg_temp.expect(pg_temp.status('bob', ch) = 'not_found', 'access: a channel the person left is not found');
  insert into public.conversation_members (conversation_id, user_id) values (ch, pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.status('bob', ch) = 'ok', 'access: back in, it is read again');

  -- Suspended circle.
  update public.circles set disabled_mode = 'suspend', disabled_at = now() where id = pg_temp.i('circle');
  perform pg_temp.expect(pg_temp.status('bob', ch) = 'not_found', 'access: a suspended circle''s channel is not found');
  update public.circles set disabled_mode = null, disabled_at = null where id = pg_temp.i('circle');
  perform pg_temp.expect(pg_temp.status('bob', ch) = 'ok', 'access: restored');

  -- Private chats.
  perform pg_temp.act(pg_temp.i('ada'));
  dm := public.get_or_create_direct_conversation(pg_temp.i('bob'));
  note := public.get_note_to_self(true);
  perform pg_temp.root();
  perform pg_temp.mk('ada', dm, 'private hello');
  perform pg_temp.expect(pg_temp.status('bob', dm) = 'ok' and pg_temp.bodies('bob', dm) = 'private hello', 'access: a private chat is read by its two people');
  perform pg_temp.expect(pg_temp.status('ada', dm) = 'ok', 'access: both');
  perform pg_temp.expect(pg_temp.status('cy', dm) = 'not_found' and pg_temp.status('dee', dm) = 'not_found', 'access: and nobody else');
  perform pg_temp.expect(pg_temp.status('bob', note) = 'not_found', 'access: nobody reads another''s note to self');

  -- A thread of a group the person is in.
  perform pg_temp.mk('cy', pg_temp.i('thread'), 'thread reply');
  perform pg_temp.expect(pg_temp.status('bob', pg_temp.i('thread')) = 'ok' and pg_temp.bodies('bob', pg_temp.i('thread')) = 'thread reply', 'access: a thread of the group is read');
  perform pg_temp.expect(pg_temp.status('dee', pg_temp.i('thread')) = 'not_found', 'access: not by a stranger');
end $$;

-- ===================================== 3. which messages
do $$
declare g uuid := pg_temp.i('group'); m uuid; probe uuid;
begin
  probe := pg_temp.mk('cy', g, 'probe', 5);
  m := probe;
  perform pg_temp.expect(pg_temp.bodies('bob', g, 1) = 'probe', 'messages: an ordinary message is read');

  update public.messages set recalled_at = now() where id = m;
  perform pg_temp.expect(pg_temp.bodies('bob', g, 1) <> 'probe', 'messages: a recalled message is not');
  update public.messages set recalled_at = null where id = m;

  update public.messages set expires_at = now() - interval '1 minute' where id = m;
  perform pg_temp.expect(pg_temp.bodies('bob', g, 1) <> 'probe', 'messages: an expired (disappearing) message is not');
  update public.messages set expires_at = now() + interval '1 hour' where id = m;
  perform pg_temp.expect(pg_temp.bodies('bob', g, 1) = 'probe', 'messages: a disappearing message that has not expired is');
  update public.messages set expires_at = null where id = m;

  update public.messages set review_state = 'checking' where id = m;
  perform pg_temp.expect(pg_temp.bodies('bob', g, 1) <> 'probe', 'messages: a message the AI guard is checking is not');
  update public.messages set review_state = 'held' where id = m;
  perform pg_temp.expect(pg_temp.bodies('bob', g, 1) <> 'probe', 'messages: nor one it holds');
  perform pg_temp.expect(pg_temp.bodies('cy', g, 1) <> 'probe', 'messages: not even for the sender');
  update public.messages set review_state = null where id = m;
  perform pg_temp.expect(pg_temp.bodies('bob', g, 1) = 'probe', 'messages: released, it is');

  -- Notices, view-once pictures, the assistant's replies.
  insert into public.messages (conversation_id, sender_id, type, body, created_at)
    values (g, pg_temp.i('cy'), 'system', 'notice text', now() - interval '1 minute');
  perform pg_temp.expect(pg_temp.bodies('bob', g, 1) = 'probe', 'messages: notices are not');
  insert into public.messages (conversation_id, sender_id, type, body, attachment, created_at)
    values (g, pg_temp.i('cy'), 'image', 'look at this', '{"kind":"image","view_once":true}', now() - interval '1 minute');
  perform pg_temp.expect(pg_temp.bodies('bob', g, 1) = 'probe', 'messages: a view-once picture is not, even with a caption');
  insert into public.messages (conversation_id, sender_id, type, body, attachment, created_at)
    values (g, pg_temp.i('cy'), 'image', 'normal picture', '{"kind":"image"}', now() - interval '1 minute');
  perform pg_temp.expect(pg_temp.bodies('bob', g, 1) = 'normal picture', 'messages: an ordinary picture''s caption is');
  insert into public.messages (conversation_id, sender_id, type, body, created_at, ai_reply)
    values (g, pg_temp.i('ada'), 'text', 'an AI answer', now() - interval '30 seconds', '{"kind":"answer"}');
  perform pg_temp.expect(pg_temp.bodies('bob', g, 1) = 'normal picture', 'messages: replies of the assistant are not');
  delete from public.messages where body in ('notice text', 'look at this', 'normal picture', 'an AI answer');

  -- Blocked either way.
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.block_user(pg_temp.i('cy'));
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.bodies('bob', g, 1) <> 'probe', 'blocked: a sender Bob blocked is not read');
  perform pg_temp.expect(pg_temp.bodies('cy', g, 1) = 'probe', 'blocked: Cy still reads their own message');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.unblock_user(pg_temp.i('cy'));
  perform pg_temp.act(pg_temp.i('cy'));
  perform public.block_user(pg_temp.i('bob'));
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.bodies('bob', g, 1) <> 'probe', 'blocked: nor one who blocked Bob');
  perform pg_temp.act(pg_temp.i('cy'));
  perform public.unblock_user(pg_temp.i('bob'));
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.bodies('bob', g, 1) = 'probe', 'blocked: unblocked, read again');
  delete from public.messages where id = probe;
end $$;

-- ===================================== 4. the AI switches
do $$
declare g uuid := pg_temp.i('group'); ch uuid := pg_temp.i('channel'); th uuid := pg_temp.i('thread');
begin
  perform pg_temp.mk('cy', g, 'switch probe', 3);

  -- The person's own switch.
  insert into public.user_ai_settings (user_id, ai_enabled) values (pg_temp.i('bob'), false);
  perform pg_temp.expect(pg_temp.status('bob', g) = 'user_off', 'switch: a person who turned AI off gets user_off');
  perform pg_temp.expect(jsonb_array_length(pg_temp.ctx('bob', g)->'messages') = 0, 'switch: and no messages');
  perform pg_temp.expect(pg_temp.status('bob', pg_temp.i('group2')) = 'user_off', 'switch: in every chat');
  perform pg_temp.expect(pg_temp.status('cy', g) = 'ok', 'switch: and it is theirs alone');
  update public.user_ai_settings set ai_enabled = true where user_id = pg_temp.i('bob');
  perform pg_temp.expect(pg_temp.status('bob', g) = 'ok', 'switch: switched on again, ok');

  -- The group owner's switch.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_group_ai_assistant(g, false);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.status('bob', g) = 'ai_off', 'switch: a group that turned WeCord AI off gets ai_off');
  perform pg_temp.expect(pg_temp.status('ada', g) = 'ai_off', 'switch: for its owner too');
  perform pg_temp.expect(pg_temp.status('bob', th) = 'ai_off', 'switch: and for its threads');
  perform pg_temp.expect(pg_temp.status('bob', pg_temp.i('group2')) = 'ok', 'switch: another group is not affected');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_group_ai_assistant(g, true);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.status('bob', g) = 'ok', 'switch: back on');

  -- The circle's switch.
  update public.circles set ai_enabled = false where id = pg_temp.i('circle');
  perform pg_temp.expect(pg_temp.status('bob', ch) = 'ai_off', 'switch: a circle that turned AI off gets ai_off for its channel');
  perform pg_temp.expect(pg_temp.status('ada', ch) = 'ai_off', 'switch: for its owner too');
  perform pg_temp.expect(pg_temp.status('bob', g) = 'ok', 'switch: a group outside it is not affected');
  update public.circles set ai_enabled = true where id = pg_temp.i('circle');
  perform pg_temp.expect(pg_temp.status('bob', ch) = 'ok', 'switch: back on');
end $$;

-- ===================================== 5. a chat the person locked
do $$
declare g uuid := pg_temp.i('group'); th uuid := pg_temp.i('thread'); dm uuid;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.set_conversation_locked(g, true);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.status('bob', g) = 'locked', 'lock: a chat the person locked is locked');
  perform pg_temp.expect(jsonb_array_length(pg_temp.ctx('bob', g)->'messages') = 0, 'lock: and nothing is read');
  perform pg_temp.expect(pg_temp.status('bob', th) = 'locked', 'lock: a thread follows its parent chat');
  perform pg_temp.expect(pg_temp.status('cy', g) = 'ok' and pg_temp.status('cy', th) = 'ok', 'lock: and it is the person''s lock alone');
  perform pg_temp.expect(pg_temp.status('bob', pg_temp.i('group2')) = 'ok', 'lock: other chats are not locked');

  -- The person's AI switch is looked at first, then the chat.
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.set_conversation_locked(g, false);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.status('bob', g) = 'ok' and pg_temp.status('bob', th) = 'ok', 'lock: unlocked, the chat is read again');

  -- A private chat can be locked too.
  perform pg_temp.act(pg_temp.i('ada'));
  dm := public.get_or_create_direct_conversation(pg_temp.i('cy'));
  perform public.set_conversation_locked(dm, true);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.status('ada', dm) = 'locked', 'lock: a private chat the person locked is locked');
  perform pg_temp.expect(pg_temp.status('cy', dm) = 'ok', 'lock: not for the other person');
end $$;

-- ===================================== 6. who may call
do $$
declare f text := 'public.ai_draft_context(uuid, uuid, integer)';
begin
  perform pg_temp.root();
  perform pg_temp.expect(has_function_privilege('service_role', f, 'execute'), 'permissions: the service role can call it');
  perform pg_temp.expect(not has_function_privilege('authenticated', f, 'execute'), 'permissions: a signed-in person cannot');
  perform pg_temp.expect(not has_function_privilege('anon', f, 'execute'), 'permissions: nor anon');

  -- A signed-in person cannot read somebody else's chat by calling it.
  perform pg_temp.act(pg_temp.i('dee'));
  perform pg_temp.must_refuse(format('select public.ai_draft_context(%L, %L, 20)', pg_temp.i('bob'), pg_temp.i('group')),
    'permissions: Dee cannot run it as Bob');
  perform pg_temp.act(null);
  perform pg_temp.must_refuse(format('select public.ai_draft_context(%L, %L, 20)', pg_temp.i('bob'), pg_temp.i('group')),
    'permissions: nobody signed in cannot either');
  perform pg_temp.root();
end $$;

\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'draft reply: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
