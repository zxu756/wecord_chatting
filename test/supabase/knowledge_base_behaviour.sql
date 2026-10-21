-- Behaviour checks for the circle knowledge base (D6: migrations 202610270100
-- to 202610270130). Run by test/supabase/knowledge_base_test.dart against the
-- local database: it applies the migrations in a transaction, plays people
-- through them, and rolls everything back. Run from the repository root.
--
-- What it walks through: chat notes as they were; making pages (who may start
-- a top-level page and who one below another, safe to send again, limits);
-- reading and editing (members read, managers and holders of an edit role
-- write, outsiders and the signed out see nothing, chat-only features refuse
-- a page); pages limited to some roles (hidden with everything below, in the
-- list, the table, the blocks, search and presence); rank (a lower manager
-- cannot lift, change, move or delete what a higher one limited); moving
-- (order, cycles, depth, the hundred below one page); deleting (children move
-- up, pictures listed, the guide forgets the page); required reading in the
-- newcomer guide; search; the AI guard checking page titles; a circle an
-- admin delisted or suspended; leaving and deleting an account, and the data
-- export.
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
-- ada owns the circle. low and high are managers (manage_channels) with
-- ModLow below ModHigh. bob is an ordinary member. cat holds the Crew role
-- (an edit role in the tests), dan the Staff role (a view role). fay and gus
-- are members. eve has an account but is not in the circle. root is the
-- platform admin.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@kb.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'low'),(3,'high'),(4,'bob'),(5,'cat'),(6,'dan'),(7,'fay'),(8,'gus'),(9,'eve'),(10,'root')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_kb', initcap(name)
from (values (1,'ada'),(2,'low'),(3,'high'),(4,'bob'),(5,'cat'),(6,'dan'),(7,'fay'),(8,'gus'),(9,'eve'),(10,'root')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'low'),(3,'high'),(4,'bob'),(5,'cat'),(6,'dan'),(7,'fay'),(8,'gus'),(9,'eve'),(10,'root')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(pg_temp.i('ada'), pg_temp.i(n)), greatest(pg_temp.i('ada'), pg_temp.i(n))
from (values ('low'),('high'),('bob'),('cat'),('dan'),('fay'),('gus')) v(n);
insert into public.app_admins (user_id, role) values (pg_temp.i('root'), 'owner');

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'club', public.create_circle('Knowledge Club', array[
  pg_temp.i('low'), pg_temp.i('high'), pg_temp.i('bob'), pg_temp.i('cat'),
  pg_temp.i('dan'), pg_temp.i('fay'), pg_temp.i('gus')]);
-- A new role takes position 1 and pushes the others up: Staff 1, Crew 2,
-- ModLow 3, ModHigh 4.
insert into pg_temp.ids select 'role_high', public.create_circle_role(pg_temp.i('club'), 'ModHigh', null, 8);
insert into pg_temp.ids select 'role_low', public.create_circle_role(pg_temp.i('club'), 'ModLow', null, 8);
insert into pg_temp.ids select 'role_crew', public.create_circle_role(pg_temp.i('club'), 'Crew', null, 0);
insert into pg_temp.ids select 'role_staff', public.create_circle_role(pg_temp.i('club'), 'Staff', null, 0);
select public.set_member_roles(pg_temp.i('club'), pg_temp.i('low'), array[pg_temp.i('role_low')]);
select public.set_member_roles(pg_temp.i('club'), pg_temp.i('high'), array[pg_temp.i('role_high')]);
select public.set_member_roles(pg_temp.i('club'), pg_temp.i('cat'), array[pg_temp.i('role_crew')]);
select public.set_member_roles(pg_temp.i('club'), pg_temp.i('dan'), array[pg_temp.i('role_staff')]);
-- A second circle, for "a page of another circle".
insert into pg_temp.ids select 'other', public.create_circle('Other Club', array[pg_temp.i('bob')]);
select pg_temp.root();

-- A group chat with a chat note, to see that nothing changed for chat notes.
with c as (insert into public.conversations (type, title) values ('group', 'Chat group') returning id)
insert into pg_temp.ids select 'group', id from c;
insert into public.conversation_members (conversation_id, user_id, role)
select pg_temp.i('group'), pg_temp.i(n), r
from (values ('ada','owner'),('bob','member')) v(n, r);

-- ===================================== 1. chat notes are as they were
do $$
declare
  ada uuid := pg_temp.i('ada');
  bob uuid := pg_temp.i('bob');
  chat_note uuid;
  res jsonb;
begin
  perform pg_temp.act(ada);
  chat_note := (public.create_note(pg_temp.i('group'), 'Plan', null, null) ->> 'id')::uuid;
  insert into pg_temp.ids values ('chat_note', chat_note);
  res := public.get_note(chat_note);
  perform pg_temp.expect(res -> 'note' ->> 'conversation_id' = pg_temp.i('group')::text, 'a chat note still has its conversation');
  perform pg_temp.expect(not ((res -> 'note') ? 'circle_id'), 'and no circle keys');
  perform pg_temp.expect((res -> 'note' ->> 'can_edit')::boolean, 'a member can edit it');
  perform pg_temp.act(bob);
  perform pg_temp.expect(public.get_note(chat_note) -> 'note' ->> 'id' = chat_note::text, 'another member opens it');
  perform pg_temp.expect((select count(*) from public.list_notes(pg_temp.i('group'))) = 1, 'it is listed');
  perform pg_temp.expect(pg_temp.state(format('select public.update_note_meta(%L, ''{"pinned": true}'')', chat_note)) = '42501', 'a chat note is still pinned by managers only');
  perform pg_temp.act(ada);
  perform pg_temp.expect(pg_temp.state(format('select public.update_note_meta(%L, ''{"pinned": true}'')', chat_note)) = 'ok', 'and they can');
  perform pg_temp.act(bob);
  perform pg_temp.root();
  -- A note must have exactly one home.
  perform pg_temp.expect(pg_temp.state(format('insert into public.notes (circle_id, conversation_id) values (%L, %L)', pg_temp.i('club'), pg_temp.i('group'))) = '23514', 'a note cannot have a conversation and a circle');
  perform pg_temp.expect(pg_temp.state('insert into public.notes (title) values (''x'')') = '23514', 'nor neither');
  perform pg_temp.expect(pg_temp.state(format('update public.notes set parent_id = %L where id = %L', chat_note, chat_note)) = '23514', 'a chat note has no place in a tree');
end $$;

-- ===================================== 2. making pages
do $$
declare
  club uuid := pg_temp.i('club');
  ada uuid := pg_temp.i('ada');
  low uuid := pg_temp.i('low');
  high uuid := pg_temp.i('high');
  bob uuid := pg_temp.i('bob');
  welcome uuid := gen_random_uuid();
  rules uuid := gen_random_uuid();
  faq uuid := gen_random_uuid();
  p jsonb;
begin
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.state(format('select public.kb_create_page(%L, null, ''Mine'')', club)) = '42501', 'a member cannot start a top-level page');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.kb_create_page(%L, null, ''Eve'')', club)) = '42501', 'an outsider cannot');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select public.kb_create_page(%L, null, ''Anon'')', club)) = '42501', 'nobody signed in cannot');

  perform pg_temp.act(low);
  p := public.kb_create_page(club, null, 'Welcome', null, welcome);
  insert into pg_temp.ids values ('welcome', welcome);
  perform pg_temp.expect(p ->> 'circle_id' = club::text and p ->> 'conversation_id' is null, 'a manager starts a top-level page');
  perform pg_temp.expect(p ->> 'icon' = E'\U0001F4C4', 'with the page icon');
  perform pg_temp.expect((p ->> 'can_edit')::boolean and (p ->> 'can_manage')::boolean, 'which the manager edits and manages');
  perform public.kb_create_page(club, null, 'Welcome', null, welcome);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.notes where id = welcome) = 1, 'sending it again makes no second page');
  perform pg_temp.expect((select count(*) from public.note_blocks where note_id = welcome) = 1, 'it starts with one empty block');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = club and action = 'kb_page_create' and target_id = welcome and target_label = 'Welcome') = 1, 'creating a page is audited with its title');

  perform pg_temp.act(high);
  perform pg_temp.expect(pg_temp.state(format('select public.kb_create_page(%L, null, ''Taken'', null, %L)', club, welcome)) = 'P0002', 'another person cannot reuse the id');

  perform pg_temp.act(ada);
  perform public.kb_create_page(club, null, 'Rules', null, rules);
  perform public.kb_create_page(club, rules, 'FAQ', E'❓', faq);
  insert into pg_temp.ids values ('rules', rules), ('faq', faq);
  perform pg_temp.expect((select (public.kb_create_page(club, null, 'x'||g, null) ->> 'id') is not null from generate_series(1,1) g), 'the owner starts pages too');
  perform pg_temp.root();
  delete from public.notes where title = 'x1' and circle_id = club;
  perform pg_temp.expect((select parent_id = rules and kb_position = 1 from public.notes where id = faq), 'a child sits below its parent');
  perform pg_temp.expect((select kb_position from public.notes where id = rules) = 2, 'top-level pages are numbered in order');

  perform pg_temp.act(ada);
  perform pg_temp.expect(pg_temp.state(format('select public.kb_create_page(%L, null, %L)', club, repeat('a', 201))) = '22023', 'a title is up to 200 characters');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_create_page(%L, %L, ''x'')', club, gen_random_uuid())) = 'P0002', 'the parent must exist');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_create_page(%L, %L, ''x'')', pg_temp.i('other'), rules)) = 'P0002', 'and belong to that circle');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_create_page(%L, %L, ''x'')', club, pg_temp.i('chat_note'))) = 'P0002', 'a chat note is not a parent');
end $$;

-- ===================================== 3. reading, and who edits
do $$
declare
  club uuid := pg_temp.i('club');
  low uuid := pg_temp.i('low');
  bob uuid := pg_temp.i('bob');
  eve uuid := pg_temp.i('eve');
  welcome uuid := pg_temp.i('welcome');
  b1 uuid;
  res jsonb;
begin
  perform pg_temp.root();
  select id into b1 from public.note_blocks where note_id = welcome;
  insert into pg_temp.ids values ('welcome_b1', b1);

  perform pg_temp.act(bob);
  perform pg_temp.expect((select count(*) from public.kb_list_pages(club)) = 3, 'a member lists the pages of the circle');
  perform pg_temp.expect((select count(*) from public.kb_list_pages(club) where can_edit) = 0, 'and edits none by default');
  perform pg_temp.expect((select not restricted and not required and not read from public.kb_list_pages(club) where id = welcome), 'no limits, not required, not read');
  perform pg_temp.expect((select title from public.kb_list_pages(club) where id = welcome) = 'Welcome', 'with the title');
  res := public.get_note(welcome);
  perform pg_temp.expect(res -> 'note' ->> 'circle_id' = club::text, 'a member opens a page with get_note');
  perform pg_temp.expect(not (res -> 'note' ->> 'can_edit')::boolean and not (res -> 'note' ->> 'can_manage')::boolean, 'read only');
  perform pg_temp.expect(jsonb_array_length(res -> 'blocks') = 1, 'with its blocks');
  perform pg_temp.expect((select count(*) from public.notes where circle_id = club) = 3, 'the table shows it by row level security');
  perform pg_temp.expect((select count(*) from public.note_blocks where note_id = welcome) = 1, 'and its blocks');
  perform pg_temp.expect(pg_temp.state(format('select public.update_note_meta(%L, ''{"title": "Mine"}'')', welcome)) = '42501', 'a member cannot rename it');
  perform pg_temp.expect(pg_temp.state(format('select public.note_apply_ops(%L, %L)', welcome,
    jsonb_build_array(jsonb_build_object('op','put','id',b1,'base_rev',1,'pos','V','kind','paragraph','text','hacked','marks','[]'::jsonb,'props','{}'::jsonb)))) = '42501', 'or write in it');
  perform pg_temp.expect(pg_temp.state(format('update public.notes set title = ''x'' where id = %L', welcome)) = '42501', 'nor write the table');
  perform pg_temp.root();
  perform pg_temp.expect((select title from public.notes where id = welcome) = 'Welcome', 'the page is unchanged');

  perform pg_temp.act(eve);
  perform pg_temp.expect(pg_temp.state(format('select * from public.kb_list_pages(%L)', club)) = '42501', 'an outsider cannot list');
  perform pg_temp.expect(pg_temp.state(format('select public.get_note(%L)', welcome)) = 'P0002', 'nor open a page');
  perform pg_temp.expect((select count(*) from public.notes where circle_id = club) = 0, 'nor see the rows');
  perform pg_temp.expect((select count(*) from public.note_blocks where note_id = welcome) = 0, 'nor its blocks');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_mark_read(%L)', welcome)) = 'P0002', 'nor mark it read');
  perform pg_temp.expect(not public.can_use_note_presence(welcome), 'nor join its presence');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select * from public.kb_list_pages(%L)', club)) = '42501', 'nobody signed in sees nothing');

  perform pg_temp.act(low);
  perform pg_temp.expect(public.can_use_note_presence(welcome), 'a manager joins the presence');
  perform pg_temp.expect(pg_temp.state(format('select public.update_note_meta(%L, ''{"pinned": true}'')', welcome)) = '22023', 'a page cannot be pinned');
  perform pg_temp.expect(pg_temp.state(format('select public.update_note_meta(%L, ''{"managers_only": true}'')', welcome)) = '22023', 'nor locked to managers');
  perform pg_temp.expect(public.update_note_meta(welcome, '{"title": "Welcome!", "icon": "👋"}') ->> 'title' = 'Welcome!', 'a manager renames it');
  res := public.note_apply_ops(welcome, jsonb_build_array(jsonb_build_object('op','put','id',b1,'base_rev',1,'pos','V','kind','paragraph','text','Read the rules, then say hello. Quarterly budget policy.','marks','[]'::jsonb,'props','{}'::jsonb)));
  perform pg_temp.expect(res -> 0 ->> 'status' = 'ok', 'and writes in it');
  perform pg_temp.root();
  perform pg_temp.expect((select title from public.notes where id = welcome) = 'Welcome!', 'saved');

  perform pg_temp.act(low);
  perform pg_temp.expect(pg_temp.state(format('select * from public.delete_note(%L)', welcome)) = 'P0002', 'the old note delete does not touch a page');
  perform pg_temp.expect(pg_temp.state(format('select public.publish_note(%L)', welcome)) = 'P0002', 'a page cannot be published on the web');
  perform pg_temp.expect(pg_temp.state(format('select public.add_note_comment(%L, ''hi'')', welcome)) <> 'ok', 'nor commented on');
  perform pg_temp.expect(pg_temp.state(format('select public.share_note(%L, %L)', welcome, pg_temp.i('group'))) <> 'ok', 'nor shared into a chat');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.share_note(%L, %L)', welcome, pg_temp.i('group'))) = 'P0002', 'even by someone in both');
  perform pg_temp.expect(pg_temp.state(format('select public.publish_note(%L)', welcome)) = 'P0002', 'or the owner');
end $$;

-- ===================================== 4. an edit role, history, timeouts
do $$
declare
  club uuid := pg_temp.i('club');
  ada uuid := pg_temp.i('ada');
  low uuid := pg_temp.i('low');
  high uuid := pg_temp.i('high');
  bob uuid := pg_temp.i('bob');
  cat uuid := pg_temp.i('cat');
  welcome uuid := pg_temp.i('welcome');
  rules uuid := pg_temp.i('rules');
  b1 uuid := pg_temp.i('welcome_b1');
  crew uuid := pg_temp.i('role_crew');
  staff uuid := pg_temp.i('role_staff');
  child uuid := gen_random_uuid();
  res jsonb;
  version_id uuid;
begin
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.state(format('select public.kb_set_page_access(%L, ''{}'', %L)', welcome, array[crew])) = '42501', 'a member cannot set who edits');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_get_page_access(%L)', welcome)) = '42501', 'nor look at the settings');
  perform pg_temp.act(cat);
  perform pg_temp.expect(pg_temp.state(format('select public.kb_set_page_access(%L, ''{}'', %L)', welcome, array[crew])) = '42501', 'an editor cannot widen it either');

  perform pg_temp.act(low);
  perform pg_temp.expect(pg_temp.state(format('select public.kb_set_page_access(%L, ''{}'', %L)', welcome, array[gen_random_uuid()])) = '22023', 'a role must be a role of the circle');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_set_page_access(%L, ''{}'', %L)', welcome, array[(select id from public.circle_roles where circle_id = club and is_default)])) = '22023', 'and not @everyone');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_set_page_access(%L, %L, ''{}'')', welcome, (select array_agg(gen_random_uuid()) from generate_series(1, 11)))) = '22023', 'up to 10 roles');
  res := public.kb_get_page_access(welcome);
  perform pg_temp.expect(jsonb_array_length(res -> 'roles') = 4 and not (res ->> 'locked')::boolean, 'a manager lists the roles to choose from');
  res := public.kb_set_page_access(welcome, '{}', array[crew]);
  perform pg_temp.expect((res ->> 'restricted')::boolean, 'a page with an edit role is marked');
  perform pg_temp.root();
  perform pg_temp.expect((select edit_role_ids = array[crew] and restrict_rank = 3 from public.notes where id = welcome), 'it records the setter''s rank');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = club and action = 'kb_page_access' and target_label is null) = 1, 'the audit entry of a limited page leaves the title out');

  perform pg_temp.act(cat);
  perform pg_temp.expect((select can_edit from public.kb_list_pages(club) where id = welcome), 'the editor can edit it');
  perform pg_temp.expect(not (select can_edit from public.kb_list_pages(club) where id = rules), 'but not other pages');
  res := public.note_apply_ops(welcome, jsonb_build_array(jsonb_build_object('op','put','id',b1,'base_rev',2,'pos','V','kind','paragraph','text','Edited by Cat. Quarterly budget policy.','marks','[]'::jsonb,'props','{}'::jsonb)));
  perform pg_temp.expect(res -> 0 ->> 'status' = 'ok', 'the editor writes in it');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_create_page(%L, null, ''Top'')', club)) = '42501', 'but cannot start a top-level page');
  perform public.kb_create_page(club, welcome, 'Cat''s page', null, child);
  insert into pg_temp.ids values ('child', child);
  perform pg_temp.expect((select can_edit from public.kb_list_pages(club) where id = child), 'she can add one below it, and edit that');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_delete_page(%L)', child)) = '42501', 'but not delete it');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_move_page(%L, null)', child)) = '42501', 'nor move it');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_create_page(%L, %L, ''No'')', club, rules)) = '42501', 'nor add one below a page she cannot edit');

  perform pg_temp.act(bob);
  perform pg_temp.expect(not (select can_edit from public.kb_list_pages(club) where id = child), 'others cannot edit the page below an editor''s page');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_create_page(%L, %L, ''No'')', club, welcome)) = '42501', 'nor add below it');

  -- History works for a page.
  perform pg_temp.act(low);
  version_id := public.create_note_version(welcome, 'First');
  perform pg_temp.expect(version_id is not null, 'a manager keeps a version of a page');
  perform pg_temp.act(bob);
  perform pg_temp.expect((select count(*) from public.list_note_versions(welcome)) >= 1, 'a member sees the history');
  perform pg_temp.expect(pg_temp.state(format('select public.restore_note_version(%L)', version_id)) = '42501', 'but cannot restore it');
  perform pg_temp.act(cat);
  perform public.note_apply_ops(welcome, jsonb_build_array(jsonb_build_object('op','put','id',b1,'base_rev',3,'pos','V','kind','paragraph','text','Changed again','marks','[]'::jsonb,'props','{}'::jsonb)));
  perform public.restore_note_version(version_id);
  perform pg_temp.root();
  perform pg_temp.expect((select text from public.note_blocks where id = b1) like 'Edited by Cat%', 'an editor restores it');

  -- A timed-out editor can only read.
  perform pg_temp.act(ada);
  perform public.timeout_circle_member(club, cat, 600);
  perform pg_temp.act(cat);
  perform pg_temp.expect(not (select can_edit from public.kb_list_pages(club) where id = welcome), 'a timed-out editor cannot edit');
  perform pg_temp.expect(pg_temp.state(format('select public.note_apply_ops(%L, %L)', welcome,
    jsonb_build_array(jsonb_build_object('op','put','id',b1,'base_rev',5,'pos','V','kind','paragraph','text','x','marks','[]'::jsonb,'props','{}'::jsonb)))) = '42501', 'nor write');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_create_page(%L, %L, ''x'')', club, welcome)) = '42501', 'nor add pages');
  perform pg_temp.expect(public.get_note(welcome) -> 'note' ->> 'id' = welcome::text, 'but still reads');
  perform pg_temp.act(ada);
  perform public.timeout_circle_member(club, cat, 0);
  perform pg_temp.act(cat);
  perform pg_temp.expect((select can_edit from public.kb_list_pages(club) where id = welcome), 'and edits again after it');
end $$;

-- ===================================== 5. pages limited to some roles
do $$
declare
  club uuid := pg_temp.i('club');
  ada uuid := pg_temp.i('ada');
  low uuid := pg_temp.i('low');
  high uuid := pg_temp.i('high');
  bob uuid := pg_temp.i('bob');
  cat uuid := pg_temp.i('cat');
  dan uuid := pg_temp.i('dan');
  rules uuid := pg_temp.i('rules');
  faq uuid := pg_temp.i('faq');
  crew uuid := pg_temp.i('role_crew');
  staff uuid := pg_temp.i('role_staff');
  rb uuid;
begin
  perform pg_temp.root();
  select id into rb from public.note_blocks where note_id = rules;
  perform pg_temp.act(low);
  perform public.note_apply_ops(rules, jsonb_build_array(jsonb_build_object('op','put','id',rb,'base_rev',1,'pos','V','kind','paragraph','text','Staff only: be kind. Secret handbook.','marks','[]'::jsonb,'props','{}'::jsonb)));
  perform public.kb_set_page_access(rules, array[staff], '{}');

  perform pg_temp.act(bob);
  perform pg_temp.expect((select count(*) from public.kb_list_pages(club)) = 2 and not exists (select 1 from public.kb_list_pages(club) where id in (rules, faq)), 'a limited page and everything below it are hidden');
  perform pg_temp.expect(pg_temp.state(format('select public.get_note(%L)', rules)) = 'P0002', 'it cannot be opened');
  perform pg_temp.expect(pg_temp.state(format('select public.get_note(%L)', faq)) = 'P0002', 'nor can the page below it');
  perform pg_temp.expect((select count(*) from public.notes where id in (rules, faq)) = 0, 'row level security hides the rows');
  perform pg_temp.expect((select count(*) from public.note_blocks where note_id in (rules, faq)) = 0, 'and the blocks');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_mark_read(%L)', rules)) = 'P0002', 'it cannot be marked read');
  perform pg_temp.expect(not public.can_use_note_presence(rules), 'nor joined in presence');
  perform pg_temp.expect((select count(*) from public.kb_search(club, 'secret handbook')) = 0, 'a search does not find it');
  perform pg_temp.expect(not public.can_current_user_view_note(faq), 'the view check says no');

  perform pg_temp.act(cat);
  perform pg_temp.expect(not exists (select 1 from public.kb_list_pages(club) where id = rules), 'a holder of another role does not see it');

  perform pg_temp.act(dan);
  perform pg_temp.expect(exists (select 1 from public.kb_list_pages(club) where id = rules) and exists (select 1 from public.kb_list_pages(club) where id = faq), 'a holder of the role sees it and what is below');
  perform pg_temp.expect(not (select can_edit from public.kb_list_pages(club) where id = rules), 'but cannot edit it');
  perform pg_temp.expect(public.get_note(rules) -> 'note' ->> 'id' = rules::text, 'and opens it');
  perform pg_temp.expect((select count(*) from public.note_blocks where note_id = rules) = 1, 'and reads the blocks');
  perform pg_temp.expect(public.can_use_note_presence(rules), 'and joins the presence');
  perform pg_temp.expect((select count(*) from public.kb_search(club, 'secret handbook')) = 1, 'and finds it by its words');
  perform public.kb_mark_read(rules);

  -- Edit rights count as view rights.
  perform pg_temp.act(low);
  perform public.kb_set_page_access(rules, array[staff], array[crew]);
  perform pg_temp.act(cat);
  perform pg_temp.expect((select can_edit from public.kb_list_pages(club) where id = rules), 'a holder of an edit role sees and edits the page');
  perform pg_temp.expect((select can_edit from public.kb_list_pages(club) where id = faq), 'and the pages below');
  perform pg_temp.act(bob);
  perform pg_temp.expect(not exists (select 1 from public.kb_list_pages(club) where id = rules), 'others still do not see it');

  -- Lifting the limit.
  perform pg_temp.act(low);
  perform public.kb_set_page_access(rules, '{}', '{}');
  perform pg_temp.root();
  perform pg_temp.expect((select restrict_rank = 0 from public.notes where id = rules), 'lifting a limit clears the rank');
  perform pg_temp.act(bob);
  perform pg_temp.expect(exists (select 1 from public.kb_list_pages(club) where id = rules), 'then everyone sees the page again');
end $$;

-- ===================================== 6. rank
do $$
declare
  club uuid := pg_temp.i('club');
  ada uuid := pg_temp.i('ada');
  low uuid := pg_temp.i('low');
  high uuid := pg_temp.i('high');
  bob uuid := pg_temp.i('bob');
  rules uuid := pg_temp.i('rules');
  faq uuid := pg_temp.i('faq');
  welcome uuid := pg_temp.i('welcome');
  staff uuid := pg_temp.i('role_staff');
  crew uuid := pg_temp.i('role_crew');
  rb uuid;
begin
  perform pg_temp.act(high);
  perform public.kb_set_page_access(rules, array[staff], '{}');
  perform pg_temp.root();
  perform pg_temp.expect((select restrict_rank = 4 from public.notes where id = rules), 'the higher manager''s rank is recorded');

  perform pg_temp.act(low);
  perform pg_temp.expect((public.kb_get_page_access(rules) ->> 'locked')::boolean, 'the lower manager sees the page as locked');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_set_page_access(%L, ''{}'', ''{}'')', rules)) = '42501', 'cannot lift the limit');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_set_page_access(%L, %L, ''{}'')', rules, array[crew])) = '42501', 'nor change it');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_delete_page(%L)', rules)) = '42501', 'nor delete the page');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_move_page(%L, null, %L)', rules, welcome)) = '42501', 'nor move it');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_move_page(%L, null)', faq)) = '42501', 'nor take a page below it out');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_delete_page(%L)', faq)) = '42501', 'nor delete a page below it');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_set_page_access(%L, %L, ''{}'')', faq, array[crew])) = '42501', 'nor change the limits below it');
  select id into rb from public.note_blocks where note_id = rules;
  perform pg_temp.expect(public.note_apply_ops(rules, jsonb_build_array(jsonb_build_object('op','put','id',rb,'base_rev',2,'pos','V','kind','paragraph','text','Low edits the words','marks','[]'::jsonb,'props','{}'::jsonb))) -> 0 ->> 'status' = 'ok', 'but may still edit the words');

  perform pg_temp.act(high);
  perform pg_temp.expect(not (public.kb_get_page_access(rules) ->> 'locked')::boolean, 'the one who set it can change it');
  perform pg_temp.act(ada);
  perform public.kb_set_page_access(rules, array[staff], array[crew]);
  perform pg_temp.root();
  perform pg_temp.expect((select restrict_rank = 2147483647 from public.notes where id = rules), 'the owner outranks everyone');
  perform pg_temp.act(high);
  perform pg_temp.expect(pg_temp.state(format('select public.kb_set_page_access(%L, ''{}'', ''{}'')', rules)) = '42501', 'even the higher manager cannot undo the owner');
  perform pg_temp.act(ada);
  perform public.kb_set_page_access(rules, '{}', '{}');
  perform pg_temp.act(low);
  perform pg_temp.expect(pg_temp.state(format('select public.kb_set_page_access(%L, ''{}'', ''{}'')', rules)) = 'ok', 'once lifted, anyone with the right may set it');
end $$;

-- ===================================== 7. moving pages
do $$
declare
  club uuid := pg_temp.i('club');
  ada uuid := pg_temp.i('ada');
  low uuid := pg_temp.i('low');
  bob uuid := pg_temp.i('bob');
  welcome uuid := pg_temp.i('welcome');
  rules uuid := pg_temp.i('rules');
  faq uuid := pg_temp.i('faq');
  child uuid := pg_temp.i('child');
  a1 uuid := gen_random_uuid();
  a2 uuid := gen_random_uuid();
  a3 uuid := gen_random_uuid();
  a4 uuid := gen_random_uuid();
  a5 uuid := gen_random_uuid();
  order_of text;
begin
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.state(format('select public.kb_move_page(%L, null)', faq)) = '42501', 'a member cannot move a page');
  perform pg_temp.expect(pg_temp.state(format('update public.notes set parent_id = null where id = %L', faq)) <> 'ok', 'nor write the table');

  perform pg_temp.act(low);
  perform public.kb_move_page(rules, null, welcome);
  select string_agg(title, ',' order by kb_position) into order_of from public.kb_list_pages(club) where parent_id is null;
  perform pg_temp.expect(order_of = 'Rules,Welcome!', 'a page can be put before another');
  perform public.kb_move_page(rules, null, null);
  select string_agg(title, ',' order by kb_position) into order_of from public.kb_list_pages(club) where parent_id is null;
  perform pg_temp.expect(order_of = 'Welcome!,Rules', 'or last');
  perform public.kb_move_page(faq, welcome, child);
  select string_agg(title, ',' order by kb_position) into order_of from public.kb_list_pages(club) where parent_id = welcome;
  perform pg_temp.expect(order_of = 'FAQ,Cat''s page', 'moving to another parent puts it before a sibling');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_move_page(%L, %L, %L)', faq, rules, child)) = 'P0002', 'the page it goes before must be a sibling there');
  perform public.kb_move_page(faq, rules);
  perform pg_temp.root();
  perform pg_temp.expect((select parent_id = rules from public.notes where id = faq), 'and back');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = club and action = 'kb_page_move') = 2, 'a change of parent is audited, a reorder is not');

  perform pg_temp.act(low);
  perform pg_temp.expect(pg_temp.state(format('select public.kb_move_page(%L, %L)', rules, rules)) = '22023', 'a page is not put inside itself');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_move_page(%L, %L)', rules, faq)) = '22023', 'nor inside its own child');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_move_page(%L, %L)', rules, pg_temp.i('chat_note'))) = 'P0002', 'nor inside a chat note');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_move_page(%L, %L)', rules, gen_random_uuid())) = 'P0002', 'nor inside nothing');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.state(format('update public.notes set parent_id = id where id = %L', rules)) = '22023', 'the table itself refuses a page in itself');
  perform pg_temp.expect(pg_temp.state(format('update public.notes set parent_id = %L where id = %L', welcome, pg_temp.i('chat_note'))) = '23514', 'and a chat note in the tree');
  perform pg_temp.act(low);

  -- Five levels deep at most.
  perform public.kb_create_page(club, null, 'L1', null, a1);
  perform public.kb_create_page(club, a1, 'L2', null, a2);
  perform public.kb_create_page(club, a2, 'L3', null, a3);
  perform public.kb_create_page(club, a3, 'L4', null, a4);
  perform public.kb_create_page(club, a4, 'L5', null, a5);
  perform pg_temp.expect(pg_temp.state(format('select public.kb_create_page(%L, %L, ''L6'')', club, a5)) = '22023', 'pages nest five levels');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_move_page(%L, %L)', a1, faq)) = '22023', 'moving a branch counts its depth');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_move_page(%L, %L)', a2, rules)) = 'ok', 'a branch that fits can move');
  insert into pg_temp.ids values ('a1', a1), ('a2', a2), ('a3', a3);

  -- A hundred pages at most below one.
  perform pg_temp.root();
  insert into public.notes (circle_id, parent_id, title, kb_position)
  select club, a1, 'filler ' || g, g + 10 from generate_series(1, 100) g;
  perform pg_temp.act(low);
  perform pg_temp.expect(pg_temp.state(format('select public.kb_create_page(%L, %L, ''too many'')', club, a1)) = '22023', 'a hundred pages at most below one');
  perform pg_temp.root();
  delete from public.notes where title like 'filler %' and circle_id = club;
end $$;

-- ===================================== 8. deleting pages
do $$
declare
  club uuid := pg_temp.i('club');
  ada uuid := pg_temp.i('ada');
  low uuid := pg_temp.i('low');
  bob uuid := pg_temp.i('bob');
  a1 uuid := pg_temp.i('a1');
  a2 uuid := pg_temp.i('a2');
  a3 uuid := pg_temp.i('a3');
  rules uuid := pg_temp.i('rules');
  img uuid := gen_random_uuid();
  paths text[];
begin
  perform pg_temp.act(low);
  perform public.note_apply_ops(a2, jsonb_build_array(jsonb_build_object('op','put','id',img,'base_rev',null,'pos','W','kind','image','text','','marks','[]'::jsonb,'props', jsonb_build_object('path', a2::text || '/pic.jpg'))));
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.state(format('select * from public.kb_delete_page(%L)', a2)) = '42501', 'a member cannot delete a page');
  perform pg_temp.act(low);
  select array_agg(object_path) into paths from public.kb_delete_page(a2);
  perform pg_temp.expect(paths = array[a2::text || '/pic.jpg'], 'deleting a page lists its pictures for removal');
  perform pg_temp.root();
  perform pg_temp.expect((select deleted_at is not null and title = '' from public.notes where id = a2), 'it is deleted and scrubbed');
  perform pg_temp.expect((select parent_id = rules from public.notes where id = a3), 'the pages inside move up one level (here, to where a2 was)');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = club and action = 'kb_page_delete') = 1, 'deleting is audited');
  perform pg_temp.act(bob);
  perform pg_temp.expect(not exists (select 1 from public.kb_list_pages(club) where id = a2) and exists (select 1 from public.kb_list_pages(club) where id = a3), 'the list has the children, not the page');
  perform pg_temp.expect(pg_temp.state(format('select public.get_note(%L)', a2)) = 'P0002', 'a deleted page cannot be opened');
  perform pg_temp.act(low);
  perform pg_temp.expect(pg_temp.state(format('select * from public.kb_delete_page(%L)', a2)) = 'P0002', 'or deleted twice');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_move_page(%L, null)', a2)) = 'P0002', 'or moved');
  perform pg_temp.expect(pg_temp.state(format('select public.note_apply_ops(%L, ''[]'')', a2)) = 'P0002', 'or written');
  -- The author or a manager removes the pictures; a stranger does not.
  perform pg_temp.expect(public.can_current_user_delete_note_files(a2), 'a manager may remove the pictures of a deleted page');
  perform pg_temp.act(bob);
  perform pg_temp.expect(not public.can_current_user_delete_note_files(a2), 'a member may not');
end $$;

-- ===================================== 9. required reading in the guide
do $$
declare
  club uuid := pg_temp.i('club');
  ada uuid := pg_temp.i('ada');
  low uuid := pg_temp.i('low');
  bob uuid := pg_temp.i('bob');
  dan uuid := pg_temp.i('dan');
  welcome uuid := pg_temp.i('welcome');
  rules uuid := pg_temp.i('rules');
  staff uuid := pg_temp.i('role_staff');
  tmp uuid := gen_random_uuid();
  g jsonb;
  tasks jsonb;
begin
  perform pg_temp.act(ada);
  perform public.kb_set_page_access(rules, array[staff], '{}');
  perform public.set_circle_guide_tasks(club, jsonb_build_array(
    jsonb_build_object('title', 'Read the welcome page', 'action', 'read_page', 'page_id', welcome),
    jsonb_build_object('title', 'Read the staff rules', 'action', 'read_page', 'page_id', rules, 'channel_id', null),
    jsonb_build_object('title', 'Say hi', 'action', 'send_message', 'page_id', welcome)));
  tasks := public.get_circle_guide_config(club) -> 'tasks';
  perform pg_temp.expect(jsonb_array_length(tasks) = 3, 'the editor lists the tasks');
  perform pg_temp.expect(tasks -> 0 ->> 'page_id' = welcome::text and tasks -> 0 ->> 'page_title' = 'Welcome!', 'with the page and its title');
  perform pg_temp.expect(tasks -> 2 ->> 'page_id' is null, 'a page given to another kind of task is dropped');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_guide_tasks where action = 'read_page' and circle_id = club) = 2, 'two tasks read a page');

  perform pg_temp.act(ada);
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_guide_tasks(%L, %L)', club, jsonb_build_array(jsonb_build_object('title', 't', 'action', 'read_page')))) = '22023', 'a reading task needs a page');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_guide_tasks(%L, %L)', club, jsonb_build_array(jsonb_build_object('title', 't', 'action', 'read_page', 'page_id', gen_random_uuid())))) = '22023', 'which exists');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_guide_tasks(%L, %L)', club, jsonb_build_array(jsonb_build_object('title', 't', 'action', 'read_page', 'page_id', pg_temp.i('chat_note'))))) = '22023', 'is not a chat note');
  perform pg_temp.root();
  insert into public.notes (id, circle_id, title) values (tmp, pg_temp.i('other'), 'Elsewhere');
  perform pg_temp.act(ada);
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_guide_tasks(%L, %L)', club, jsonb_build_array(jsonb_build_object('title', 't', 'action', 'read_page', 'page_id', tmp)))) = '22023', 'and belongs to the circle');
  perform pg_temp.root();
  delete from public.notes where id = tmp;
  perform pg_temp.expect((select count(*) from public.circle_guide_tasks where action = 'read_page' and circle_id = club) = 2, 'refused calls changed nothing');

  perform pg_temp.act(bob);
  g := public.get_circle_guide(club);
  perform pg_temp.expect(jsonb_array_length(g -> 'tasks') = 2, 'a member who cannot read the staff page does not see its task');
  perform pg_temp.expect(g -> 'tasks' -> 0 ->> 'action' = 'read_page' and g -> 'tasks' -> 0 ->> 'page_title' = 'Welcome!' and not (g -> 'tasks' -> 0 ->> 'done')::boolean, 'the task names the page and is open');
  perform pg_temp.expect((select required and not read from public.kb_list_pages(club) where id = welcome), 'the page is marked required, not read');
  perform pg_temp.expect(pg_temp.state(format('select public.complete_guide_task(%L, %L)', club, (g -> 'tasks' -> 0 ->> 'id')::uuid)) = '22023', 'a reading task completes itself');
  perform public.kb_mark_read(welcome);
  perform public.kb_mark_read(welcome);
  g := public.get_circle_guide(club);
  perform pg_temp.expect((g -> 'tasks' -> 0 ->> 'done')::boolean, 'opening the page ticks it off');
  perform pg_temp.expect((select read from public.kb_list_pages(club) where id = welcome), 'the list says it is read');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_kb_reads where user_id = bob) = 1, 'once, however often');

  perform pg_temp.act(dan);
  g := public.get_circle_guide(club);
  perform pg_temp.expect(jsonb_array_length(g -> 'tasks') = 3, 'a member who can read the staff page sees both');
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.state('select count(*) from public.circle_kb_reads') = '42501', 'the reads table is closed to clients');

  -- A deleted page leaves the guide.
  perform pg_temp.act(low);
  perform public.kb_create_page(club, null, 'Soon gone', null, tmp);
  perform pg_temp.act(ada);
  perform public.set_circle_guide_tasks(club, jsonb_build_array(
    jsonb_build_object('title', 'Soon gone', 'action', 'read_page', 'page_id', tmp)));
  perform pg_temp.expect(jsonb_array_length(public.get_circle_guide_config(club) -> 'tasks') = 1, 'a new task list');
  perform pg_temp.act(low);
  perform public.kb_delete_page(tmp);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_guide_tasks where circle_id = club) = 0, 'deleting the page removes its task');
  -- Put the tasks back for the later checks.
  perform pg_temp.act(ada);
  perform public.set_circle_guide_tasks(club, jsonb_build_array(
    jsonb_build_object('title', 'Read the welcome page', 'action', 'read_page', 'page_id', welcome)));
end $$;

-- ===================================== 10. searching
do $$
declare
  club uuid := pg_temp.i('club');
  bob uuid := pg_temp.i('bob');
  dan uuid := pg_temp.i('dan');
  welcome uuid := pg_temp.i('welcome');
  rules uuid := pg_temp.i('rules');
  staff uuid := pg_temp.i('role_staff');
begin
  perform pg_temp.act(bob);
  perform pg_temp.expect((select count(*) from public.kb_search(club, 'budget')) = 1 and (select snippet like '%budget%' from public.kb_search(club, 'budget')), 'a search finds a page by its words, with a snippet');
  perform pg_temp.expect((select count(*) from public.kb_search(club, 'WELCOME')) = 1, 'by its title, in any case');
  perform pg_temp.expect((select count(*) from public.kb_search(club, 'w')) = 0, 'a single letter finds nothing');
  perform pg_temp.expect((select count(*) from public.kb_search(club, '%%')) = 0, 'wildcards are plain characters');
  perform pg_temp.expect((select count(*) from public.kb_search(club, 'nothing like this')) = 0, 'no match, no rows');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.kb_set_page_access(rules, array[staff], '{}');
  perform pg_temp.act(bob);
  perform pg_temp.expect((select count(*) from public.kb_search(club, 'Low edits')) = 0, 'a limited page is not found by a member who cannot read it');
  perform pg_temp.act(dan);
  perform pg_temp.expect((select count(*) from public.kb_search(club, 'Low edits')) = 1, 'but is by one who can');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select * from public.kb_search(%L, ''budget'')', club)) = '42501', 'an outsider cannot search');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.kb_set_page_access(rules, '{}', '{}');
end $$;

-- ===================================== 11. the AI guard checks page titles
do $$
declare
  club uuid := pg_temp.i('club');
  ada uuid := pg_temp.i('ada');
  cat uuid := pg_temp.i('cat');
  welcome uuid := pg_temp.i('welcome');
  page uuid := gen_random_uuid();
  review public.guard_item_reviews%rowtype;
begin
  perform pg_temp.act(ada);
  perform public.set_circle_ai_guard(club, true, 'joined_days', 3, 10, 'hold');
  perform public.set_circle_ai_guard_scope(club, true, true, true);
  perform pg_temp.act(cat);
  perform public.kb_create_page(club, welcome, 'Win a free prize', null, page);
  perform pg_temp.root();
  select * into review from public.guard_item_reviews where item_id = page;
  perform pg_temp.expect(review.id is not null and review.item_type = 'note' and review.circle_id = club and review.conversation_id is null and review.actor_id = cat, 'a new member''s page title is recorded for the AI guard');
  perform pg_temp.expect(review.state = 'released' and review.unchecked_reason = 'unavailable', 'and, with no way to wake the function, released unchecked');
  update public.notes set title = 'Free prize inside' where id = page;
  perform pg_temp.expect((select count(*) from public.guard_item_reviews where item_id = page) = 1, 'a new title checks again (at most once a minute)');
  perform pg_temp.act(ada);
  perform public.kb_create_page(club, null, 'Owner page');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.guard_item_reviews where item_type = 'note' and actor_id = ada) = 0, 'the owner''s page is not checked');
  delete from public.guard_item_reviews;
end $$;

-- ===================================== 12. a taken-down circle
do $$
declare
  club uuid := pg_temp.i('club');
  root uuid := pg_temp.i('root');
  bob uuid := pg_temp.i('bob');
  low uuid := pg_temp.i('low');
  welcome uuid := pg_temp.i('welcome');
  b1 uuid := pg_temp.i('welcome_b1');
  page uuid := gen_random_uuid();
begin
  perform pg_temp.act(root);
  perform public.admin_disable_circle(club, 'delist', 'x');
  perform pg_temp.act(bob);
  perform pg_temp.expect((select count(*) from public.kb_list_pages(club)) > 0, 'a delisted circle still shows its pages');
  perform pg_temp.act(low);
  perform pg_temp.expect(public.kb_create_page(club, null, 'While delisted', null, page) ->> 'id' = page::text, 'and takes writes');
  perform pg_temp.act(root);
  perform public.admin_enable_circle(club, 'x');
  perform public.admin_disable_circle(club, 'suspend', 'x');

  perform pg_temp.act(bob);
  perform pg_temp.expect((select count(*) from public.kb_list_pages(club)) = 0, 'a suspended circle lists nothing');
  perform pg_temp.expect(pg_temp.state(format('select public.get_note(%L)', welcome)) = 'P0002', 'opens nothing');
  perform pg_temp.expect((select count(*) from public.notes where circle_id = club) = 0, 'and shows no rows');
  perform pg_temp.expect((select count(*) from public.note_blocks where note_id = welcome) = 0, 'or blocks');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_mark_read(%L)', welcome)) = 'P0002', 'or records a read');
  perform pg_temp.act(low);
  perform pg_temp.expect(pg_temp.state(format('select public.kb_create_page(%L, null, ''No'')', club)) = '42501', 'refuses a new page');
  perform pg_temp.expect(pg_temp.state(format('select public.note_apply_ops(%L, %L)', welcome,
    jsonb_build_array(jsonb_build_object('op','put','id',b1,'base_rev',1,'pos','V','kind','paragraph','text','x','marks','[]'::jsonb,'props','{}'::jsonb)))) = 'P0002', 'and a change of words');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_move_page(%L, null)', welcome)) = 'P0002', 'and a move');
  perform pg_temp.expect(pg_temp.state(format('select * from public.kb_delete_page(%L)', welcome)) = 'P0002', 'and a delete');
  perform pg_temp.expect(pg_temp.state(format('select public.kb_set_page_access(%L, ''{}'', ''{}'')', welcome)) = 'P0002', 'and a change of limits');
  perform pg_temp.expect(not public.kb_is_manager(club, low), 'nobody manages it');

  perform pg_temp.act(root);
  perform public.admin_enable_circle(club, 'x');
  perform pg_temp.act(bob);
  perform pg_temp.expect((select count(*) from public.kb_list_pages(club)) > 0, 'a circle that is back shows its pages');
  perform pg_temp.root();
  delete from public.notes where id = page;
end $$;

-- ===================================== 13. leaving, and the account
do $$
declare
  club uuid := pg_temp.i('club');
  bob uuid := pg_temp.i('bob');
  cat uuid := pg_temp.i('cat');
  gus uuid := pg_temp.i('gus');
  welcome uuid := pg_temp.i('welcome');
  x jsonb;
begin
  perform pg_temp.act(gus);
  perform public.kb_mark_read(welcome);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_kb_reads where user_id = gus) = 1, 'gus read a page');
  delete from public.circle_members where circle_id = club and user_id = gus;
  perform pg_temp.expect((select count(*) from public.circle_kb_reads where user_id = gus) = 0, 'leaving the circle forgets what was read');
  perform pg_temp.expect(public.kb_user_access(welcome, gus) = 0, 'and the access');

  perform pg_temp.expect(public.kb_user_access(welcome, bob) = 1 and public.kb_user_access(welcome, cat) = 2, 'access: read for a member, edit for an editor');
  perform pg_temp.expect(public.kb_user_access(welcome, pg_temp.i('eve')) = 0 and public.kb_user_access(welcome, null) = 0, 'none for strangers');

  x := public.export_my_knowledge(bob);
  perform pg_temp.expect(jsonb_array_length(x -> 'pages_read') = 1 and x -> 'pages_read' -> 0 ->> 'title' = 'Welcome!', 'the export has what I read');
  perform pg_temp.expect(jsonb_array_length(x -> 'pages_made') = 0, 'and nothing I made, as I made none');
  x := public.export_my_knowledge(cat);
  perform pg_temp.expect(jsonb_array_length(x -> 'pages_made') >= 1 and x::text like '%Cat''s page%', 'the pages I made, with their circle');
  perform pg_temp.expect(x::text like '%Knowledge Club%', 'named');
  perform pg_temp.act(cat);
  perform pg_temp.expect(pg_temp.state(format('select public.export_my_knowledge(%L)', cat)) = '42501', 'only the service role asks for it');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select public.export_my_knowledge(%L)', cat)) = '42501', 'not even the signed out');

  perform pg_temp.root();
  update public.profiles set deleted_at = now() where id = bob;
  perform pg_temp.expect((select count(*) from public.circle_kb_reads where user_id = bob) = 0, 'a deleted account: what it read is erased');
  perform pg_temp.expect((select count(*) from public.notes where circle_id = club and deleted_at is null) > 0, 'the pages stay');
end $$;
\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'knowledge base: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
