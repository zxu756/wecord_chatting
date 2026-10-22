-- Behaviour checks for the group space (B6: migrations 202610280200 to
-- 202610280230). Run by test/supabase/group_space_test.dart against the local
-- database: it applies the migrations in a transaction, plays people through
-- them, and rolls everything back. Run from the repository root.
--
-- What it walks through: who may read, add, rename and remove; albums and
-- folders from chat messages (and what is refused: view-once, expiring,
-- recalled, forwarded, in review, other chats); uploads under <chat>/space/;
-- the guard that keeps a recalled message's file while the space names it and
-- hands it back when the last entry goes; disappearing messages switching the
-- space off; blocks; the albums of events; leaving, deleting an account and the
-- data export.
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
\i supabase/migrations/202610280200_group_space_schema.sql
\i supabase/migrations/202610280210_group_space_albums.sql
\i supabase/migrations/202610280220_group_space_folders.sql
\i supabase/migrations/202610280230_group_space_account.sql
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
-- ada owns the group g1; bob, cat, dan and fay are members; eve is outside.
-- g2 is another group (eve's); dm is a direct chat of ada and bob.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@b6.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'fay')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_b6', initcap(name)
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'fay')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'fay')) v(n, name);

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
  (pg_temp.i('g1'), pg_temp.i('fay'), 'admin'),
  (pg_temp.i('g2'), pg_temp.i('eve'), 'owner'),
  (pg_temp.i('dm'), pg_temp.i('ada'), 'member'),
  (pg_temp.i('dm'), pg_temp.i('bob'), 'member');
insert into public.friendships (user_low_id, user_high_id)
select least(pg_temp.i('ada'), pg_temp.i(n)), greatest(pg_temp.i('ada'), pg_temp.i(n))
from (values ('bob'),('cat'),('dan'),('fay')) v(n);

-- A message with a file in the chat's folder. kind: image | video | file.
create function pg_temp.msg_file(sender text, conv text, kind text, file text, extra jsonb default '{}'::jsonb)
returns uuid language plpgsql as $$
declare
  mid uuid := gen_random_uuid();
  bucket text := case when kind = 'image' then 'chat-images' else 'chat-files' end;
begin
  insert into public.messages (id, conversation_id, sender_id, type, body, attachment)
  values (mid, pg_temp.i(conv), pg_temp.i(sender),
    case when kind = 'image' then 'image' else 'file' end, '',
    jsonb_build_object('kind', kind, 'bucket', bucket, 'path', pg_temp.i(conv)::text || '/' || file,
      'mime_type', case kind when 'image' then 'image/jpeg' when 'video' then 'video/mp4' else 'application/pdf' end,
      'size', 1000, 'name', file) || extra);
  insert into storage.objects (bucket_id, name) values (bucket, pg_temp.i(conv)::text || '/' || file);
  return mid;
end $$;

create function pg_temp.status(statement text) returns text language plpgsql as $$
begin
  execute statement;
  return 'ok';
exception when others then
  return sqlerrm;
end $$;

grant execute on all functions in schema pg_temp to public;

-- ===================================== 1. nothing was rewritten
do $$
declare
  def text;
begin
  def := pg_get_functiondef('public.list_conversation_media(uuid)'::regprocedure);
  perform pg_temp.expect(def like '%view_once%' and def like '%expires_at%', 'list_conversation_media is not rewritten (keeps view-once and expiry)');
  def := pg_get_functiondef('public.recall_message(uuid)'::regprocedure);
  perform pg_temp.expect(def like '%recalled_message_media%', 'recall_message is not rewritten');
  perform pg_temp.expect(not exists (select 1 from pg_policies where tablename in ('conversation_albums', 'album_items', 'conversation_folders', 'folder_files')), 'no table has a policy: every way in is an RPC');
  perform pg_temp.expect(not has_table_privilege('authenticated', 'public.album_items', 'select') and not has_table_privilege('authenticated', 'public.folder_files', 'insert'), 'clients cannot read or write the tables');
  perform pg_temp.expect(has_function_privilege('authenticated', 'public.create_group_album(uuid, text)', 'execute') and not has_function_privilege('anon', 'public.create_group_album(uuid, text)', 'execute'), 'signed-in people call the RPCs, the public does not');
  perform pg_temp.expect(not has_function_privilege('authenticated', 'public.group_space_access(uuid, text)', 'execute'), 'the access check is internal');
end $$;

-- The rest of the script looks at the tables as a test, not as a client.
grant select on public.album_items, public.folder_files, public.conversation_albums, public.conversation_folders to authenticated;
grant select on public.recalled_message_media to authenticated;
create policy test_read on public.album_items for select to authenticated using (true);
create policy test_read on public.folder_files for select to authenticated using (true);
create policy test_read on public.conversation_albums for select to authenticated using (true);
create policy test_read on public.conversation_folders for select to authenticated using (true);
create policy test_read on public.recalled_message_media for select to authenticated using (true);

-- ===================================== 2. who may use the space
do $$
declare
  g1 uuid := pg_temp.i('g1');
  info jsonb;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  info := public.get_group_space(g1);
  perform pg_temp.expect((info->>'supported')::boolean and (info->>'enabled')::boolean and (info->>'can_add')::boolean and not (info->>'is_admin')::boolean, 'a member sees the space, can add, is no admin');
  perform pg_temp.act(pg_temp.i('fay'));
  perform pg_temp.expect((public.get_group_space(g1)->>'is_admin')::boolean, 'an admin of the group is an admin of the space');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect((public.get_group_space(g1)->>'is_admin')::boolean, 'and so is the owner');
  perform pg_temp.expect(public.get_group_space(pg_temp.i('dm')) = '{"supported": false}'::jsonb, 'a direct chat has no space');
  perform pg_temp.expect(pg_temp.state(format('select public.create_group_album(%L, ''x'')', pg_temp.i('dm'))) = '22023', 'and cannot make an album');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.get_group_space(%L)', g1)) = '42501', 'an outsider is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.list_group_albums(%L)', g1)) = '42501', 'cannot list albums');
  perform pg_temp.expect(pg_temp.state(format('select public.list_group_folders(%L)', g1)) = '42501', 'nor folders');
  perform pg_temp.expect(pg_temp.state(format('select public.create_group_folder(%L, ''x'')', g1)) = '42501', 'nor make one');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select public.get_group_space(%L)', g1)) in ('42501', '42883'), 'nobody signed in is refused');
  perform pg_temp.root();
end $$;

-- ===================================== 3. albums
do $$
declare
  g1 uuid := pg_temp.i('g1');
  album jsonb;
  alb uuid;
  m1 uuid; m2 uuid; m3 uuid; m_video uuid; m_file uuid; m_once uuid; m_exp uuid; m_review uuid; m_fwd uuid; m_other uuid; m_recalled uuid;
  result jsonb;
  listed jsonb;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  album := public.create_group_album(g1, '  Trip 2026 ');
  alb := (album->>'id')::uuid;
  insert into pg_temp.ids values ('album1', alb);
  perform pg_temp.expect(album->>'name' = 'Trip 2026', 'the name is trimmed');
  perform pg_temp.expect(pg_temp.state(format('select public.create_group_album(%L, %L)', g1, 'trip 2026')) = '22023', 'a name is unique in the group, whatever the case');
  perform pg_temp.expect(pg_temp.state(format('select public.create_group_album(%L, %L)', g1, '   ')) = '22023', 'an empty name is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.create_group_album(%L, %L)', g1, repeat('x', 41))) = '22023', 'a name over 40 characters is refused');
  perform pg_temp.root();

  -- Messages to pick from.
  m1 := pg_temp.msg_file('cat', 'g1', 'image', 'a1.jpg', '{"width": 800, "height": 600, "alt": "A hut", "blurhash": "LEHV6nWB2yk8"}');
  m2 := pg_temp.msg_file('cat', 'g1', 'image', 'a2.jpg');
  m3 := pg_temp.msg_file('dan', 'g1', 'image', 'a3.jpg');
  m_video := pg_temp.msg_file('cat', 'g1', 'video', 'v1.mp4');
  m_file := pg_temp.msg_file('cat', 'g1', 'file', 'f1.pdf');
  m_once := pg_temp.msg_file('cat', 'g1', 'image', 'once.jpg', '{"view_once": true}');
  m_exp := pg_temp.msg_file('cat', 'g1', 'image', 'exp.jpg');
  update public.messages set expires_at = now() + interval '1 day' where id = m_exp;
  m_review := pg_temp.msg_file('cat', 'g1', 'image', 'review.jpg');
  update public.messages set review_state = 'held' where id = m_review;
  m_recalled := pg_temp.msg_file('cat', 'g1', 'image', 'gone.jpg');
  update public.messages set recalled_at = now() where id = m_recalled;
  m_fwd := gen_random_uuid();
  insert into public.messages (id, conversation_id, sender_id, type, body, attachment)
  values (m_fwd, g1, pg_temp.i('cat'), 'image', '', jsonb_build_object('kind', 'image', 'bucket', 'chat-images',
    'path', pg_temp.i('g2')::text || '/elsewhere.jpg', 'mime_type', 'image/jpeg', 'size', 10));
  m_other := pg_temp.msg_file('eve', 'g2', 'image', 'other.jpg');
  insert into pg_temp.ids values ('m1', m1), ('m2', m2), ('m3', m3), ('mvideo', m_video), ('mfile', m_file), ('mrecalled', m_recalled), ('mother', m_other);

  perform pg_temp.act(pg_temp.i('bob'));
  result := public.add_album_items_from_messages(alb, array[m1, m2, m_video]);
  perform pg_temp.expect((result->>'added')::int = 3 and (result->>'skipped')::int = 0, 'pictures and a video are added');
  result := public.add_album_items_from_messages(alb, array[m1, m_file, m_once, m_exp, m_review, m_fwd, m_other, m_recalled]);
  perform pg_temp.expect((result->>'added')::int = 0, 'a repeat, a file, view-once, expiring, in review, forwarded, from another chat, deleted: none added');
  perform pg_temp.expect((result->>'skipped')::int = 7, 'each refusal is counted (a message of another chat is not even looked at)');
  listed := (select jsonb_agg(x) from public.list_album_items(alb) x);
  perform pg_temp.expect(jsonb_array_length(listed) = 3, 'the album lists three');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(listed) e where e->>'alt' = 'A hut' and e->>'blurhash' = 'LEHV6nWB2yk8' and (e->>'width')::int = 800 and e->>'adder_name' = 'Bob' and (e->>'from_chat')::boolean), 'the description, size and who added it come along');
  perform pg_temp.expect(pg_temp.state(format('select public.add_album_items_from_messages(%L, %L)', alb, array(select gen_random_uuid() from generate_series(1, 51)))) = '22023', 'more than 50 at a time is refused');

  -- An outsider, a message of the wrong group.
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.add_album_items_from_messages(%L, %L)', alb, array[m_other])) = '42501', 'an outsider cannot add');
  perform pg_temp.expect(pg_temp.state(format('select public.list_album_items(%L)', alb)) = '42501', 'nor read an album');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.rename_group_album(%L, ''Mine'')', alb)) = '42501', 'a member cannot rename someone else''s album');
  perform pg_temp.expect(pg_temp.state(format('select public.delete_group_album(%L)', alb)) = '42501', 'nor delete it');
  perform pg_temp.expect((select count(*) from public.list_group_albums(g1) a where a->>'name' = 'Trip 2026' and (a->>'item_count')::int = 3 and not (a->>'can_manage')::boolean) = 1, 'the list shows the count, and that cat cannot manage it');
  perform pg_temp.expect((select a->'cover'->>'path' from public.list_group_albums(g1) a where a->>'name' = 'Trip 2026') = g1::text || '/a1.jpg' or (select a->'cover'->>'path' from public.list_group_albums(g1) a where a->>'name' = 'Trip 2026') like g1::text || '/a%.jpg', 'a picture is the cover');
  -- Cat adds one of her own.
  result := public.add_album_items_from_messages(alb, array[m3]);
  perform pg_temp.expect((result->>'added')::int = 1, 'any member can add to any album');

  -- Remove: the person who added it, an admin; not a bystander.
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(pg_temp.state(format('select public.remove_album_item(%L)', (select id from public.album_items where album_id = alb and path like '%a3.jpg'))) = '42501', 'dan cannot remove cat''s picture');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.status(format('select * from public.remove_album_item(%L)', (select id from public.album_items where album_id = alb and path like '%a3.jpg'))) = 'ok', 'cat removes the one she added');
  perform pg_temp.expect(not exists (select 1 from public.recalled_message_media where object_path like '%a3.jpg'), 'its file stays in the chat, since the message is still there');
  perform pg_temp.act(pg_temp.i('fay'));
  perform pg_temp.expect(pg_temp.status(format('select public.rename_group_album(%L, ''Trip 2026 (all)'')', alb)) = 'ok', 'an admin renames bob''s album');
  perform pg_temp.root();
end $$;

-- ===================================== 4. a deleted message's file stays while it is named
do $$
declare
  g1 uuid := pg_temp.i('g1');
  alb uuid := pg_temp.i('album1');
  m1 uuid := pg_temp.i('m1');
  item_id uuid;
  fpath text := pg_temp.i('g1')::text || '/a1.jpg';
  freed record;
begin
  -- The sender recalls the message the picture came from.
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.status(format('select * from public.recall_message(%L)', m1)) = 'ok', 'cat deletes the message with the hut picture');
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.recalled_message_media where object_path = fpath), 'the file is not queued for removal: the album names it');
  perform pg_temp.expect(not public.can_current_user_delete_recalled_media('chat-images', fpath), 'and nobody may delete it');
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect((select count(*) from public.list_album_items(alb) e where e->>'alt' = 'A hut') = 1, 'the album still shows it');

  -- Removing the last entry hands the file back: as the person who removed it.
  perform pg_temp.act(pg_temp.i('fay'));
  select id into item_id from public.album_items where album_id = alb and path = pg_temp.i('g1')::text || '/a1.jpg';
  select * into freed from public.remove_album_item(item_id);
  perform pg_temp.expect(freed.object_path = fpath and freed.bucket_id = 'chat-images', 'removing it answers which file to delete');
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.recalled_message_media where object_path = fpath and deleted_by = pg_temp.i('fay')), 'and queues it for the person who removed it');
  perform pg_temp.act(pg_temp.i('fay'));
  perform pg_temp.expect(public.can_current_user_delete_recalled_media('chat-images', fpath), 'who may now delete it from Storage');
  perform pg_temp.root();

  -- Naming it again: the trigger never queues what is named, and a file named
  -- by two albums stays until both let go.
  insert into public.recalled_message_media (bucket_id, object_path, deleted_by) values ('chat-images', g1::text || '/a2.jpg', pg_temp.i('cat'));
  perform pg_temp.expect(not exists (select 1 from public.recalled_message_media where object_path = g1::text || '/a2.jpg'), 'a direct insert for a named file is dropped');
  insert into public.recalled_message_media (bucket_id, object_path, deleted_by) values ('chat-images', g1::text || '/unnamed.jpg', pg_temp.i('cat'));
  perform pg_temp.expect(exists (select 1 from public.recalled_message_media where object_path = g1::text || '/unnamed.jpg'), 'and one for a file nobody names is kept');
end $$;

do $$
declare
  g1 uuid := pg_temp.i('g1');
  second jsonb;
  second_id uuid;
  freed record;
  item_a uuid;
  rows_freed integer;
begin
  perform pg_temp.act(pg_temp.i('dan'));
  second := public.create_group_album(g1, 'Second');
  second_id := (second->>'id')::uuid;
  perform public.add_album_items_from_messages(second_id, array[pg_temp.i('m2')]);
  perform pg_temp.root();
  -- m2's picture is in album1 and in Second. Recall the message: kept.
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.recall_message(pg_temp.i('m2'));
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.recalled_message_media where object_path = g1::text || '/a2.jpg'), 'recalled but named twice: kept');
  perform pg_temp.act(pg_temp.i('dan'));
  select id into item_a from public.album_items where album_id = second_id;
  select count(*) into rows_freed from public.remove_album_item(item_a);
  perform pg_temp.expect(rows_freed = 0, 'leaving one album does not free a file the other still names');
  perform pg_temp.root();
  -- Deleting album1 frees the rest of its files (m2's now, the video stays: its message lives).
  perform pg_temp.act(pg_temp.i('ada'));
  select count(*) into rows_freed from public.delete_group_album(pg_temp.i('album1'));
  perform pg_temp.expect(rows_freed = 1, 'deleting an album frees only the files nothing else names (the recalled picture; the video''s message is still there)');
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.conversation_albums where id = pg_temp.i('album1')) and not exists (select 1 from public.album_items where album_id = pg_temp.i('album1')), 'the album and its entries are gone');
  perform pg_temp.expect(exists (select 1 from public.messages where id = pg_temp.i('mvideo') and attachment is not null), 'the chat''s own messages are untouched');
end $$;

-- ===================================== 5. uploads
do $$
declare
  g1 uuid := pg_temp.i('g1');
  alb uuid;
  item jsonb;
  good text;
begin
  good := g1::text || '/space/up1.jpg';
  perform pg_temp.act(pg_temp.i('bob'));
  alb := (public.create_group_album(g1, 'Uploads')->>'id')::uuid;
  perform pg_temp.root();

  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.add_album_upload(%L, ''chat-images'', %L, ''up1.jpg'', ''image/jpeg'', 5000)', alb, good)) = '22023', 'a file that is not in Storage yet is refused');
  perform pg_temp.root();
  insert into storage.objects (bucket_id, name, metadata) values
    ('chat-images', good, '{"size": 4321}'),
    ('chat-images', g1::text || '/up2.jpg', '{"size": 10}'),
    ('chat-images', pg_temp.i('g2')::text || '/space/x.jpg', '{"size": 10}'),
    ('chat-files', g1::text || '/space/clip.mp4', '{"size": 99000}'),
    ('chat-files', g1::text || '/space/doc.pdf', '{"size": 77000}');
  perform pg_temp.act(pg_temp.i('bob'));
  item := public.add_album_upload(alb, 'chat-images', good, 'up1.jpg', 'image/jpeg', 1, 640, 480, '  Lunch  ', null);
  perform pg_temp.expect(item->>'alt' = 'Lunch' and (item->>'size')::int = 4321 and (item->>'width')::int = 640 and not (item->>'from_chat')::boolean, 'an uploaded picture is stored with the size Storage knows');
  perform pg_temp.expect(pg_temp.state(format('select public.add_album_upload(%L, ''chat-images'', %L, ''up1.jpg'', ''image/jpeg'', 1)', alb, good)) = '22023', 'the same file twice is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_album_upload(%L, ''chat-images'', %L, ''up2.jpg'', ''image/jpeg'', 1)', alb, g1::text || '/up2.jpg')) = '22023', 'a file outside space/ is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_album_upload(%L, ''chat-images'', %L, ''x.jpg'', ''image/jpeg'', 1)', alb, pg_temp.i('g2')::text || '/space/x.jpg')) = '22023', 'and one in another chat''s folder');
  perform pg_temp.expect(pg_temp.state(format('select public.add_album_upload(%L, ''chat-images'', %L, ''x.jpg'', ''image/jpeg'', 1)', alb, g1::text || '/space/../../x.jpg')) = '22023', 'and a path that climbs out');
  item := public.add_album_upload(alb, 'chat-files', g1::text || '/space/clip.mp4', 'clip.mp4', 'video/mp4', 1);
  perform pg_temp.expect(item->>'kind' = 'video', 'a video goes in as a video');
  perform pg_temp.expect(pg_temp.state(format('select public.add_album_upload(%L, ''chat-files'', %L, ''doc.pdf'', ''application/pdf'', 1)', alb, g1::text || '/space/doc.pdf')) = '22023', 'a document is not a picture or a video');

  -- Description edits.
  perform pg_temp.expect(pg_temp.status(format('select public.set_album_item_alt(%L, ''A new description'')', (select id from public.album_items where path = good))) = 'ok', 'the adder rewrites the description');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_album_item_alt(%L, ''x'')', (select id from public.album_items where path = good))) = '42501', 'someone else cannot');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_album_item_alt(%L, ''x'')', (select id from public.album_items where path = g1::text || '/space/clip.mp4'))) = '22023', 'a video has none');

  -- Cover.
  perform pg_temp.expect(pg_temp.status(format('select public.set_group_album_cover(%L, %L)', alb, (select id from public.album_items where path = good))) = 'ok', 'the album''s owner picks a cover');
  perform pg_temp.expect((select a->'cover'->>'path' from public.list_group_albums(g1) a where a->>'name' = 'Uploads') = good, 'and the list shows it');
  perform pg_temp.expect(pg_temp.state(format('select public.set_group_album_cover(%L, %L)', alb, (select id from public.album_items where path = g1::text || '/space/clip.mp4'))) = '22023', 'a video cannot be the cover');
  insert into pg_temp.ids values ('upalbum', alb);
  perform pg_temp.root();
end $$;

-- ===================================== 6. folders
do $$
declare
  g1 uuid := pg_temp.i('g1');
  folder jsonb;
  fid uuid;
  result jsonb;
  listed jsonb;
  file_id uuid;
  freed integer;
begin
  perform pg_temp.act(pg_temp.i('cat'));
  folder := public.create_group_folder(g1, 'Handouts');
  fid := (folder->>'id')::uuid;
  insert into pg_temp.ids values ('folder1', fid);
  perform pg_temp.expect(pg_temp.state(format('select public.create_group_folder(%L, ''HANDOUTS'')', g1)) = '22023', 'a folder name is unique too');
  result := public.add_folder_files_from_messages(g1, fid, array[pg_temp.i('mfile'), pg_temp.i('mvideo'), pg_temp.i('m3'), pg_temp.i('mother'), pg_temp.i('mrecalled')]);
  perform pg_temp.expect((result->>'added')::int = 3 and (result->>'skipped')::int = 1, 'a file, a video and a picture are added; a deleted one is skipped; another chat''s is not looked at');
  result := public.add_folder_files_from_messages(g1, null, array[pg_temp.i('mfile')]);
  perform pg_temp.expect((result->>'added')::int = 1, 'the same file may sit at the top as well');
  result := public.add_folder_files_from_messages(g1, null, array[pg_temp.i('mfile')]);
  perform pg_temp.expect((result->>'added')::int = 0, 'but only once in a place');
  listed := public.list_group_folders(g1);
  perform pg_temp.expect((listed->>'root_count')::int = 1 and (listed->'folders'->0->>'file_count')::int = 3 and (listed->'folders'->0->>'can_manage')::boolean, 'the folders come with their counts');
  perform pg_temp.expect((select count(*) from public.list_folder_files(g1, fid) f where f->>'kind' = 'file' and f->>'name' = 'f1.pdf') = 1, 'a file keeps its name and kind');
  perform pg_temp.expect(pg_temp.state(format('select public.list_folder_files(%L, %L)', pg_temp.i('g2'), fid)) = '42501', 'another chat''s folder cannot be opened through a chat you are not in');
  perform pg_temp.expect(pg_temp.state(format('select public.list_folder_files(%L, %L)', g1, gen_random_uuid())) = '42501', 'or a folder that is not there');

  -- Uploads.
  perform pg_temp.root();
  insert into storage.objects (bucket_id, name, metadata) values ('chat-files', g1::text || '/space/notes.txt', '{"size": 12}'), ('chat-files', g1::text || '/space/pic.png', '{"size": 99}');
  perform pg_temp.act(pg_temp.i('cat'));
  result := public.add_folder_upload(g1, fid, 'chat-files', g1::text || '/space/notes.txt', 'notes.txt', 'text/plain', 1);
  perform pg_temp.expect(result->>'kind' = 'file' and (result->>'size')::int = 12, 'an upload is stored');
  result := public.add_folder_upload(g1, fid, 'chat-files', g1::text || '/space/pic.png', 'pic.png', 'image/png', 1);
  perform pg_temp.expect(result->>'kind' = 'image', 'a picture uploaded as a file is an image');
  perform pg_temp.expect(pg_temp.state(format('select public.add_folder_upload(%L, %L, ''chat-files'', %L, ''notes.txt'', ''text/plain'', 1)', g1, fid, g1::text || '/space/notes.txt')) = '22023', 'twice in one folder is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_folder_upload(%L, %L, ''chat-files'', %L, ''n.txt'', ''text/plain'', 1)', g1, fid, g1::text || '/notes.txt')) = '22023', 'outside space/ is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_folder_upload(%L, %L, ''chat-files'', %L, ''n.txt'', ''text/plain'', 1)', g1, fid, g1::text || '/space/missing.txt')) = '22023', 'and so is a file that was never uploaded');

  -- Move, rename, remove.
  select id into file_id from public.folder_files where path = g1::text || '/space/notes.txt';
  perform pg_temp.expect(pg_temp.status(format('select public.move_folder_file(%L, null)', file_id)) = 'ok', 'a file moves to the top');
  perform pg_temp.expect(pg_temp.state(format('select public.move_folder_file(%L, %L)', file_id, pg_temp.i('folder1'))) = 'ok', 'and back into a folder');
  perform pg_temp.expect(pg_temp.state(format('select public.move_folder_file(%L, %L)', file_id, (select id from public.conversation_folders limit 0))) in ('ok'), 'to the top again with a null folder');
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(pg_temp.state(format('select public.rename_folder_file(%L, ''x.txt'')', file_id)) = '42501', 'dan cannot rename cat''s upload');
  perform pg_temp.expect(pg_temp.state(format('select public.rename_group_folder(%L, ''x'')', fid)) = '42501', 'nor her folder');
  perform pg_temp.expect(pg_temp.state(format('select public.delete_group_folder(%L)', fid)) = '42501', 'nor delete it');
  perform pg_temp.act(pg_temp.i('fay'));
  perform pg_temp.expect(pg_temp.status(format('select public.rename_folder_file(%L, ''renamed.txt'')', file_id)) = 'ok', 'an admin can');
  perform pg_temp.act(pg_temp.i('cat'));
  select count(*) into freed from public.remove_folder_file(file_id);
  perform pg_temp.expect(freed = 1, 'removing an uploaded file frees it for deletion from Storage');
  perform pg_temp.expect((select count(*) from public.folder_files where path = g1::text || '/space/notes.txt') = 0, 'and takes the entry away');

  -- Deleting a folder takes its files; what is still a message stays in the chat.
  select count(*) into freed from public.delete_group_folder(fid);
  perform pg_temp.expect(freed = 1, 'deleting the folder frees the one upload (picture), not the files of live messages');
  perform pg_temp.expect(not exists (select 1 from public.folder_files where folder_id = fid), 'its files are gone');
  perform pg_temp.root();
end $$;

-- ===================================== 7. limits
do $$
declare
  g1 uuid := pg_temp.i('g1');
  n integer;
begin
  perform pg_temp.root();
  insert into public.conversation_albums (conversation_id, name, created_by)
  select g1, 'bulk ' || x, pg_temp.i('ada') from generate_series(1, 48) x;
  perform pg_temp.act(pg_temp.i('bob'));
  select count(*) into n from public.conversation_albums where conversation_id = g1;
  perform pg_temp.expect(pg_temp.status(format('select public.create_group_album(%L, ''the last'')', g1)) = 'ok' or n >= 50, 'up to 50 albums');
  perform pg_temp.expect(pg_temp.state(format('select public.create_group_album(%L, ''one too many'')', g1)) = '22023', 'the 51st is refused');
  perform pg_temp.root();
  delete from public.conversation_albums where name like 'bulk %' or name in ('the last');
  -- 2 GiB
  insert into public.album_items (album_id, conversation_id, bucket, path, kind, name, size, added_by)
  select pg_temp.i('upalbum'), g1, 'chat-images', g1::text || '/space/big' || x || '.jpg', 'image', 'big' || x, 104857600, pg_temp.i('ada')
  from generate_series(1, 21) x;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.msg(format('select public.add_album_items_from_messages(%L, %L)', pg_temp.i('upalbum'), array[pg_temp.i('m3')])) = 'The group space is full', 'a group cannot hold more than 2 GiB');
  perform pg_temp.root();
  delete from public.album_items where path like g1::text || '/space/big%';
end $$;

-- ===================================== 8. disappearing messages switch it off
do $$
declare
  g1 uuid := pg_temp.i('g1');
  info jsonb;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_disappearing_messages(g1, 86400);
  perform pg_temp.act(pg_temp.i('bob'));
  info := public.get_group_space(g1);
  perform pg_temp.expect(not (info->>'enabled')::boolean and not (info->>'can_add')::boolean and (info->>'can_tidy')::boolean, 'with the timer on the space is off for adding, still open for tidying');
  perform pg_temp.expect(pg_temp.state(format('select public.create_group_album(%L, ''New'')', g1)) = '22023', 'no new album');
  perform pg_temp.expect(pg_temp.state(format('select public.create_group_folder(%L, ''New'')', g1)) = '22023', 'no new folder');
  perform pg_temp.expect(pg_temp.state(format('select public.add_album_items_from_messages(%L, %L)', pg_temp.i('upalbum'), array[pg_temp.i('m3')])) = '22023', 'no adding to an album');
  perform pg_temp.expect(pg_temp.state(format('select public.add_folder_files_from_messages(%L, null, %L)', g1, array[pg_temp.i('m3')])) = '22023', 'no adding to the files');
  perform pg_temp.expect((select count(*) from public.list_group_albums(g1) a where a->>'name' = 'Uploads') = 1, 'what is there can still be read');
  perform pg_temp.expect(pg_temp.status(format('select * from public.remove_album_item(%L)', (select id from public.album_items where path = g1::text || '/space/clip.mp4'))) = 'ok', 'and tidied');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_disappearing_messages(g1, null);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.status(format('select 1 from (select pg_temp.act(%L)) x', pg_temp.i('bob'))) = 'ok', 'switching the timer off again');
  perform pg_temp.expect(pg_temp.status(format('select public.create_group_album(%L, ''Back'')', g1)) = 'ok', 'brings the space back');
  perform pg_temp.root();
end $$;

-- ===================================== 9. blocks and members who cannot send
do $$
declare
  g1 uuid := pg_temp.i('g1');
  alb uuid := pg_temp.i('upalbum');
begin
  perform pg_temp.root();
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('dan'), pg_temp.i('bob'));
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect((select count(*) from public.list_album_items(alb)) = 0, 'dan blocked bob: bob''s pictures do not show to dan');
  perform pg_temp.expect((select (a->>'item_count')::int from public.list_group_albums(g1) a where a->>'name' = 'Uploads') = 0, 'and are not counted');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect((select count(*) from public.list_album_items(alb)) >= 1, 'cat still sees them');
  perform pg_temp.root();
  delete from public.blocks where blocker_id = pg_temp.i('dan');

  -- A suspended account adds nothing and changes nothing (K1); reading is fine.
  insert into public.app_user_suspensions (user_id, reason) values (pg_temp.i('dan'), 'test');
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_group_album(%L, ''Sneaky'')', g1)) = '42501', 'a suspended account cannot make an album');
  perform pg_temp.expect(pg_temp.state(format('select public.add_album_items_from_messages(%L, %L)', alb, array[pg_temp.i('m3')])) = '42501', 'nor add to one');
  perform pg_temp.expect(pg_temp.state(format('select public.create_group_folder(%L, ''Sneaky'')', g1)) = '42501', 'nor make a folder');
  perform pg_temp.expect(pg_temp.state(format('select public.get_group_space(%L)', g1)) = 'ok', 'but can ask what the space allows');
  perform pg_temp.expect(not (public.get_group_space(g1)->>'can_add')::boolean, 'and is told it cannot add');
  perform pg_temp.expect((select count(*) from public.list_group_albums(g1)) >= 1, 'and can look');
  perform pg_temp.root();
  delete from public.app_user_suspensions where user_id = pg_temp.i('dan');

  -- Someone outside the group cannot upload into it either.
  insert into storage.objects (bucket_id, name, metadata) values ('chat-images', g1::text || '/space/eve.jpg', '{"size": 5}');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.add_album_upload(%L, ''chat-images'', %L, ''eve.jpg'', ''image/jpeg'', 5)', alb, g1::text || '/space/eve.jpg')) = '42501', 'an outsider cannot register an upload');
  perform pg_temp.root();
end $$;

-- ===================================== 10. the pictures of an event
do $$
declare
  g1 uuid := pg_temp.i('g1');
  ev jsonb;
  ev_id uuid;
  photo_path text;
  listed jsonb;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  ev := public.create_chat_event(g1, 'Summit', now() + interval '10 minutes', null, null, null, null, array[15], false, null);
  ev_id := (ev->>'id')::uuid;
  perform public.rsvp_chat_event(ev_id, 'going', null);
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.rsvp_chat_event(ev_id, 'going', null);
  perform pg_temp.root();
  photo_path := g1::text || '/events/summit1.jpg';
  insert into storage.objects (bucket_id, name) values ('chat-images', photo_path), ('chat-images', g1::text || '/events/summit2.jpg');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.add_event_photo('chat', ev_id, photo_path);
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.add_event_photo('chat', ev_id, g1::text || '/events/summit2.jpg');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect((select count(*) from public.list_group_albums(g1) a where a->>'kind' = 'event' and a->>'name' = 'Summit' and (a->>'item_count')::int = 2) = 1, 'an event with pictures is an album of the space');
  listed := (select jsonb_agg(x) from public.list_group_event_album(g1, ev_id) x);
  perform pg_temp.expect(jsonb_array_length(listed) = 2 and not (listed->0->>'can_delete')::boolean, 'its pictures are listed; cat may not delete them');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect((select bool_and((x->>'can_delete')::boolean) from public.list_group_event_album(g1, ev_id) x), 'the organiser may delete them (through the event)');
  perform pg_temp.expect(pg_temp.state(format('select public.list_group_event_album(%L, %L)', pg_temp.i('g2'), ev_id)) = '42501', 'another chat cannot ask for the event');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.list_group_event_album(%L, %L)', g1, ev_id)) = '42501', 'an outsider cannot');
  -- An event without pictures is not an album.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.create_chat_event(g1, 'Picnic', now() + interval '3 days', null, null, null, null, array[15], false, null);
  perform pg_temp.expect((select count(*) from public.list_group_albums(g1) a where a->>'name' = 'Picnic') = 0, 'an event with no pictures is not listed');
  -- Event pictures are not mixed into the normal albums and cannot be added to one twice.
  perform pg_temp.root();
end $$;

-- ===================================== 11. leaving, deleting an account, export
do $$
declare
  g1 uuid := pg_temp.i('g1');
  exported jsonb;
begin
  perform pg_temp.root();
  exported := public.export_my_group_space(pg_temp.i('bob'));
  perform pg_temp.expect(jsonb_array_length(exported->'albums') >= 2 and jsonb_array_length(exported->'items') >= 1, 'bob''s export holds the albums he made and what he added');
  perform pg_temp.expect((exported->'albums'->0->>'group') = 'Hike crew', 'with the group''s title while he is in it');
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(exported->'items') e where e->>'name' like 'other%'), 'and nothing of anybody else''s');
  exported := public.export_my_group_space(pg_temp.i('eve'));
  perform pg_temp.expect(exported = jsonb_build_object('albums', '[]'::jsonb, 'items', '[]'::jsonb, 'folders', '[]'::jsonb, 'files', '[]'::jsonb), 'a stranger''s export is empty');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.export_my_group_space(%L)', pg_temp.i('bob'))) = '42501', 'clients cannot call the export');
  perform pg_temp.root();
  perform pg_temp.expect(has_function_privilege('service_role', 'public.export_my_group_space(uuid)', 'execute'), 'the data-export function can');

  -- Leaving the group: the groups title leaves the export, the pictures stay in the space.
  delete from public.conversation_members where conversation_id = g1 and user_id = pg_temp.i('bob');
  exported := public.export_my_group_space(pg_temp.i('bob'));
  perform pg_temp.expect(exported->'albums'->0->>'group' is null, 'after leaving, the export does not name the group');
  perform pg_temp.expect(exists (select 1 from public.album_items where added_by = pg_temp.i('bob')) , 'and what bob added stays for the group');
  -- Deleting the account takes the name off, not the pictures.
  update public.profiles set deleted_at = now() where id = pg_temp.i('bob');
  perform pg_temp.expect(not exists (select 1 from public.album_items where added_by = pg_temp.i('bob')) and not exists (select 1 from public.conversation_albums where created_by = pg_temp.i('bob')), 'deleting an account takes the name off what was added');
  perform pg_temp.expect(exists (select 1 from public.album_items where conversation_id = g1) and exists (select 1 from public.conversation_albums where name = 'Uploads'), 'the group keeps its albums and pictures');
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect((select a->>'creator_name' from public.list_group_albums(g1) a where a->>'name' = 'Uploads') is null, 'with no creator named');
  perform pg_temp.expect((select count(*) from public.list_album_items(pg_temp.i('upalbum'))) >= 1, 'and still listed');
  perform pg_temp.root();
end $$;

\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'group space: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
