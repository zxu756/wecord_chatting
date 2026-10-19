-- Behaviour checks for Task lists 2.0 (D7: migrations 202610250100 to
-- 202610250130). Run by test/supabase/tasks2_test.dart against the local
-- database: it applies every migration after the local baseline in a
-- transaction, plays people through the task functions, and rolls everything
-- back. Run from the repository root.
--
-- What it walks through: a list's own fields (number, single choice, link,
-- person) and what is refused; item values merging field by field and the
-- ones that do not fit being ignored; values that no longer fit after the
-- fields change; subtasks (one level, same list, at most 50, deleted with
-- their task); repeating tasks (the rule, the next task made once when one
-- is finished, how dates move across months and daylight saving time); the
-- person fields when an account is closed; and the data export.
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

-- Whether [statement] is refused (with [code] when given).
create function pg_temp.refused(statement text, code text default null) returns boolean language plpgsql as $$
begin
  execute statement;
  return false;
exception when others then
  return code is null or sqlstate = code;
end $$;

grant execute on all functions in schema pg_temp to public;

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create function pg_temp.i(n text) returns uuid language sql as $$ select id from pg_temp.ids where name = n $$;
grant execute on function pg_temp.i(text) to public;

-- ------------------------------------------------------------------ cast
-- ada made the list; bob and cat are in the group; dan is not.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@t2.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_t2', initcap(name)
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan')) v(n, name);

insert into public.conversations (type, title) values ('group', 'Crew') returning id \gset grp_
insert into pg_temp.ids values ('grp', :'grp_id');
insert into public.conversation_members (conversation_id, user_id, role) values
  (:'grp_id', pg_temp.i('ada'), 'owner'),
  (:'grp_id', pg_temp.i('bob'), 'member'),
  (:'grp_id', pg_temp.i('cat'), 'member');

-- ===================================== 1. the list's fields
do $$
declare
  ada uuid := pg_temp.i('ada');
  bob uuid := pg_temp.i('bob');
  dan uuid := pg_temp.i('dan');
  grp uuid := pg_temp.i('grp');
  lst jsonb;
  lid uuid;
  fields jsonb := '[
    {"id":"cost","name":"Cost","type":"number"},
    {"id":"area","name":"Area","type":"select","options":[{"id":"home","name":"Home"},{"id":"work","name":"Work"}]},
    {"id":"site","name":"Link","type":"link"},
    {"id":"who","name":"Owner","type":"person"}
  ]'::jsonb;
begin
  perform pg_temp.act(ada);
  lst := public.create_task_list(grp, 'Chores', null);
  lid := (lst->>'id')::uuid;
  perform pg_temp.expect(lst->'field_defs' = '[]'::jsonb, 'a new list has no fields');
  insert into pg_temp.ids values ('list', lid);

  lst := public.set_task_list_fields(lid, fields);
  perform pg_temp.expect(jsonb_array_length(lst->'field_defs') = 4, 'four fields are saved');
  perform pg_temp.expect(lst->'field_defs'->1->'options'->1->>'name' = 'Work', 'a choice keeps its options in order');
  perform pg_temp.expect(public.get_task_list(lid)->'list'->'field_defs' = lst->'field_defs', 'get_task_list shows the fields');

  perform pg_temp.expect(pg_temp.refused(format('select public.set_task_list_fields(%L, %L::jsonb)', lid,
    '[{"id":"x","name":"X","type":"date"}]'), '22023'), 'an unknown field type is refused');
  perform pg_temp.expect(pg_temp.refused(format('select public.set_task_list_fields(%L, %L::jsonb)', lid,
    '[{"id":"X!","name":"X","type":"number"}]'), '22023'), 'a bad field id is refused');
  perform pg_temp.expect(pg_temp.refused(format('select public.set_task_list_fields(%L, %L::jsonb)', lid,
    '[{"id":"a","name":"A","type":"number"},{"id":"a","name":"B","type":"number"}]'), '22023'), 'two fields with one id are refused');
  perform pg_temp.expect(pg_temp.refused(format('select public.set_task_list_fields(%L, %L::jsonb)', lid,
    '[{"id":"a","name":"A","type":"select"}]'), '22023'), 'a choice needs its options list');
  perform pg_temp.expect(pg_temp.refused(format('select public.set_task_list_fields(%L, %L::jsonb)', lid,
    (select jsonb_agg(jsonb_build_object('id', 'f' || n, 'name', 'F' || n, 'type', 'number'))::text from generate_series(1, 21) n)), '22023'),
    'more than 20 fields are refused');
  perform pg_temp.expect(pg_temp.refused(format('select public.set_task_list_fields(%L, %L::jsonb)', lid, '{"a":1}'), '22023'),
    'fields must be a list');

  perform pg_temp.act(dan);
  perform pg_temp.expect(pg_temp.refused(format('select public.set_task_list_fields(%L, %L::jsonb)', lid, '[]')),
    'someone outside the chat cannot change the fields');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused(format('select public.set_task_list_fields(%L, %L::jsonb)', lid, '[]')),
    'nobody signed in cannot either');
  perform pg_temp.act(bob);
  lst := public.set_task_list_fields(lid, fields);
  perform pg_temp.expect(jsonb_array_length(lst->'field_defs') = 4, 'a member who can edit the list may set the fields');
  perform pg_temp.root();
end $$;

-- ===================================== 2. values merge field by field
do $$
declare
  ada uuid := pg_temp.i('ada');
  bob uuid := pg_temp.i('bob');
  dan uuid := pg_temp.i('dan');
  lid uuid := pg_temp.i('list');
  item jsonb;
  item_id uuid := gen_random_uuid();
begin
  perform pg_temp.act(ada);
  item := public.upsert_task_item(lid, jsonb_build_object('id', item_id, 'title', 'Paint the fence',
    'custom', jsonb_build_object('cost', '12.50', 'area', 'home', 'site', 'https://example.com/paint', 'who', bob)));
  perform pg_temp.expect((item->'custom'->>'cost')::numeric = 12.5, 'a number typed as text is stored as a number');
  perform pg_temp.expect(item->'custom'->>'area' = 'home', 'a choice is stored');
  perform pg_temp.expect(item->'custom'->>'site' = 'https://example.com/paint', 'a link is stored');
  perform pg_temp.expect(item->'custom'->>'who' = bob::text, 'a person is stored');
  perform pg_temp.expect(item->'parent_id' = 'null'::jsonb and item->'recurrence' = 'null'::jsonb, 'no parent or repeat by default');

  -- Two people, two fields: nobody undoes the other.
  perform pg_temp.act(bob);
  item := public.upsert_task_item(lid, jsonb_build_object('id', item_id, 'custom', jsonb_build_object('cost', 40)));
  perform pg_temp.expect((item->'custom'->>'cost')::numeric = 40 and item->'custom'->>'area' = 'home', 'changing one field keeps the others');
  perform pg_temp.act(ada);
  item := public.upsert_task_item(lid, jsonb_build_object('id', item_id, 'custom', jsonb_build_object('area', 'work')));
  perform pg_temp.expect((item->'custom'->>'cost')::numeric = 40 and item->'custom'->>'area' = 'work', 'and the other way round');

  -- Values that do not fit are ignored, not errors.
  item := public.upsert_task_item(lid, jsonb_build_object('id', item_id, 'custom', jsonb_build_object(
    'cost', 'a lot', 'area', 'moon', 'site', 'javascript:alert(1)', 'who', dan, 'nope', 1)));
  perform pg_temp.expect((item->'custom'->>'cost')::numeric = 40, 'text in a number field is ignored');
  perform pg_temp.expect(item->'custom'->>'area' = 'work', 'an unknown choice is ignored');
  perform pg_temp.expect(item->'custom'->>'site' = 'https://example.com/paint', 'a link that is not http(s) is ignored');
  perform pg_temp.expect(item->'custom'->>'who' = bob::text, 'a person outside the chat is ignored');
  perform pg_temp.expect(not (item->'custom' ? 'nope'), 'a field the list does not have is ignored');
  perform pg_temp.expect(pg_temp.refused(format('select public.upsert_task_item(%L, %L::jsonb)', lid,
    jsonb_build_object('id', item_id, 'custom', '[1]')::text), '22023'), 'values must come as an object');

  -- null removes one value.
  item := public.upsert_task_item(lid, jsonb_build_object('id', item_id, 'custom', jsonb_build_object('who', null, 'cost', null)));
  perform pg_temp.expect(not (item->'custom' ? 'who') and not (item->'custom' ? 'cost') and item->'custom'->>'area' = 'work',
    'null clears a value and only that one');

  -- Patches that know nothing of 2.0 still work and change nothing in it.
  item := public.upsert_task_item(lid, jsonb_build_object('id', item_id, 'title', 'Paint the fence white'));
  perform pg_temp.expect(item->>'title' = 'Paint the fence white' and item->'custom'->>'area' = 'work', 'an old-style patch keeps the fields');

  -- Reading goes through the table too.
  perform pg_temp.expect((select custom->>'area' from public.task_items where id = item_id) = 'work', 'members read the values from the table');
  perform pg_temp.root();
end $$;

-- ===================================== 3. the fields change under existing values
do $$
declare
  ada uuid := pg_temp.i('ada');
  bob uuid := pg_temp.i('bob');
  lid uuid := pg_temp.i('list');
  item jsonb;
  item_id uuid := gen_random_uuid();
begin
  perform pg_temp.act(ada);
  item := public.upsert_task_item(lid, jsonb_build_object('id', item_id, 'title', 'Tidy', 'custom',
    jsonb_build_object('cost', 5, 'area', 'home', 'site', 'https://example.com', 'who', bob)));

  -- A choice loses an option: items that held it lose the value.
  perform public.set_task_list_fields(lid, '[
    {"id":"cost","name":"Cost","type":"number"},
    {"id":"area","name":"Area","type":"select","options":[{"id":"work","name":"Work"}]},
    {"id":"site","name":"Link","type":"link"},
    {"id":"who","name":"Owner","type":"person"}
  ]'::jsonb);
  perform pg_temp.expect((select custom ? 'cost' and not custom ? 'area' from public.task_items where id = item_id),
    'a removed option takes its values with it, the rest stays');

  -- A field changes type: values that do not fit the new type go.
  perform public.set_task_list_fields(lid, '[
    {"id":"cost","name":"Cost","type":"link"},
    {"id":"area","name":"Area","type":"select","options":[{"id":"work","name":"Work"}]},
    {"id":"site","name":"Link","type":"link"},
    {"id":"who","name":"Owner","type":"person"}
  ]'::jsonb);
  perform pg_temp.expect((select not custom ? 'cost' and custom ? 'site' and custom ? 'who' from public.task_items where id = item_id),
    'a changed type drops the values that no longer fit');

  -- A removed field takes its values.
  perform public.set_task_list_fields(lid, '[{"id":"who","name":"Owner","type":"person"}]'::jsonb);
  perform pg_temp.expect((select custom = jsonb_build_object('who', bob) from public.task_items where id = item_id),
    'a removed field takes its values and the others keep theirs');

  -- A patch queued before the field went is ignored, not refused.
  item := public.upsert_task_item(lid, jsonb_build_object('id', item_id, 'priority', 2, 'custom', jsonb_build_object('area', 'work')));
  perform pg_temp.expect((item->>'priority')::int = 2 and not (item->'custom' ? 'area'), 'a queued patch for a gone field still saves the rest');

  -- Back to a small set for what follows.
  perform public.set_task_list_fields(lid, '[
    {"id":"cost","name":"Cost","type":"number"},
    {"id":"who","name":"Owner","type":"person"}
  ]'::jsonb);
  perform pg_temp.root();
end $$;

-- ===================================== 4. subtasks
do $$
declare
  ada uuid := pg_temp.i('ada');
  bob uuid := pg_temp.i('bob');
  grp uuid := pg_temp.i('grp');
  lid uuid := pg_temp.i('list');
  other_list uuid;
  p_task uuid := gen_random_uuid();
  p_sub uuid := gen_random_uuid();
  p_other uuid := gen_random_uuid();
  item jsonb;
  n integer;
begin
  perform pg_temp.act(ada);
  other_list := (public.create_task_list(grp, 'Other', null)->>'id')::uuid;
  perform public.upsert_task_item(lid, jsonb_build_object('id', p_task, 'title', 'Clean the house'));
  item := public.upsert_task_item(lid, jsonb_build_object('id', p_sub, 'title', 'Kitchen', 'parent_id', p_task));
  perform pg_temp.expect((item->>'parent_id')::uuid = p_task, 'a subtask knows its task');
  perform pg_temp.expect(pg_temp.refused(format('select public.upsert_task_item(%L, %L::jsonb)', lid,
    jsonb_build_object('id', gen_random_uuid(), 'title', 'Sink', 'parent_id', p_sub)::text), '22023'),
    'a subtask cannot have subtasks');
  perform pg_temp.expect(pg_temp.refused(format('select public.upsert_task_item(%L, %L::jsonb)', lid,
    jsonb_build_object('id', p_task, 'parent_id', p_sub)::text), '22023'),
    'a task with subtasks cannot become a subtask');
  perform pg_temp.expect(pg_temp.refused(format('select public.upsert_task_item(%L, %L::jsonb)', lid,
    jsonb_build_object('id', p_task, 'parent_id', p_task)::text), '22023'),
    'a task cannot be its own subtask');
  perform public.upsert_task_item(other_list, jsonb_build_object('id', p_other, 'title', 'Elsewhere'));
  perform pg_temp.expect(pg_temp.refused(format('select public.upsert_task_item(%L, %L::jsonb)', lid,
    jsonb_build_object('id', gen_random_uuid(), 'title', 'x', 'parent_id', p_other)::text), 'P0002'),
    'the task must be in the same list');
  perform pg_temp.expect(pg_temp.refused(format('select public.upsert_task_item(%L, %L::jsonb)', lid,
    jsonb_build_object('id', gen_random_uuid(), 'title', 'x', 'parent_id', gen_random_uuid())::text), 'P0002'),
    'and exist');
  perform pg_temp.expect(pg_temp.refused(format('select public.upsert_task_item(%L, %L::jsonb)', other_list,
    jsonb_build_object('id', p_sub, 'title', 'x')::text), '22023'),
    'a subtask stays in its list');

  -- At most 50.
  for n in 1..49 loop
    perform public.upsert_task_item(lid, jsonb_build_object('id', gen_random_uuid(), 'title', 'Step ' || n, 'parent_id', p_task));
  end loop;
  perform pg_temp.expect(pg_temp.refused(format('select public.upsert_task_item(%L, %L::jsonb)', lid,
    jsonb_build_object('id', gen_random_uuid(), 'title', 'one too many', 'parent_id', p_task)::text), '22023'),
    'a task has at most 50 subtasks');

  -- A subtask can be finished on its own, or become a task again.
  item := public.set_task_item_done(p_sub, true);
  perform pg_temp.expect(item->>'completed_at' is not null, 'a subtask can be checked off');
  perform pg_temp.expect((select completed_at is null from public.task_items where id = p_task), 'which does not finish its task');
  item := public.upsert_task_item(lid, jsonb_build_object('id', p_sub, 'parent_id', null));
  perform pg_temp.expect(item->'parent_id' = 'null'::jsonb, 'a subtask can become a task again');
  perform public.upsert_task_item(lid, jsonb_build_object('id', p_sub, 'parent_id', p_task,
    'custom', jsonb_build_object('who', bob)));

  -- Deleting the task deletes its subtasks.
  perform public.delete_task_item(p_task);
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.task_items t where t.parent_id = p_task and t.deleted_at is null),
    'deleting a task deletes its subtasks');
  perform pg_temp.expect((select custom = '{}'::jsonb from public.task_items where id = p_sub), 'a deleted subtask forgets its fields');
  perform pg_temp.expect((select count(*) from public.task_items t where t.parent_id = p_task) = 50, 'but the rows are kept');
end $$;

-- ===================================== 5. dates that repeat
do $$
declare
  rule jsonb;
begin
  -- Days, weeks, months, years.
  perform pg_temp.expect(public.task_next_due('2027-03-01 10:00+00', true, '{"freq":"daily","interval":1}', '2027-03-01 10:00+00')
    = '2027-03-02 10:00+00', 'daily');
  perform pg_temp.expect(public.task_next_due('2027-03-01 10:00+00', true, '{"freq":"daily","interval":3}', '2027-03-01 10:00+00')
    = '2027-03-04 10:00+00', 'every three days');
  perform pg_temp.expect(public.task_next_due('2027-03-01 10:00+00', true, '{"freq":"weekly","interval":2}', '2027-03-01 10:00+00')
    = '2027-03-15 10:00+00', 'every second week');
  perform pg_temp.expect(public.task_next_due('2027-01-31 10:00+00', true, '{"freq":"monthly","interval":1}', '2027-01-31 10:00+00')
    = '2027-02-28 10:00+00', 'monthly: the 31st becomes the last day of a short month');
  perform pg_temp.expect(public.task_next_due('2027-02-28 10:00+00', true, '{"freq":"monthly","interval":1,"anchor_day":31}', '2027-02-28 10:00+00')
    = '2027-03-31 10:00+00', 'and goes back to the 31st');
  perform pg_temp.expect(public.task_next_due('2028-02-29 10:00+00', true, '{"freq":"yearly","interval":1}', '2028-02-29 10:00+00')
    = '2029-02-28 10:00+00', 'yearly: a leap day moves to the 28th');
  -- Late: skips the dates that passed.
  perform pg_temp.expect(public.task_next_due('2027-03-01 10:00+00', true, '{"freq":"daily","interval":1}', '2027-03-10 12:00+00')
    = '2027-03-11 10:00+00', 'finished late: the next date after now');
  perform pg_temp.expect(public.task_next_due('2027-03-01 10:00+00', true, '{"freq":"weekly","interval":1}', '2027-03-01 09:00+00')
    = '2027-03-08 10:00+00', 'finished early: still the next date of the rule');
  -- All day stays at the end of the local day: +08:00.
  perform pg_temp.expect(public.task_next_due('2027-03-01 15:59+00', false, '{"freq":"daily","interval":1,"tz_offset":480}', '2027-03-01 15:59+00')
    = '2027-03-02 15:59+00', 'all day in a fixed offset stays at 23:59 local');
  -- Across the start of daylight saving time in New York (2027-03-14).
  perform pg_temp.expect(public.task_next_due('2027-03-14 04:59+00', false, '{"freq":"daily","interval":1}', '2027-03-14 04:59+00', 'America/New_York')
    = '2027-03-15 03:59+00', 'all day across daylight saving time stays at 23:59 local');
  perform pg_temp.expect(public.task_next_due('2027-03-13 14:00+00', true, '{"freq":"weekly","interval":1}', '2027-03-13 14:00+00', 'America/New_York')
    = '2027-03-20 13:00+00', 'a time of day keeps its local hour across daylight saving time');

  -- The rule is checked.
  rule := public.normalize_task_recurrence('{"freq":"weekly","interval":"2","junk":1,"tz_offset":-300}');
  perform pg_temp.expect(rule = '{"freq":"weekly","interval":2,"tz_offset":-300}'::jsonb, 'the rule keeps only what it needs');
  perform pg_temp.expect(pg_temp.refused($q$select public.normalize_task_recurrence('{"freq":"hourly"}')$q$, '22023'), 'an unknown unit is refused');
  perform pg_temp.expect(pg_temp.refused($q$select public.normalize_task_recurrence('{"freq":"daily","interval":0}')$q$, '22023'), 'every 0 days is refused');
  perform pg_temp.expect(pg_temp.refused($q$select public.normalize_task_recurrence('{"freq":"daily","interval":100}')$q$, '22023'), 'every 100 days is refused');
  perform pg_temp.expect(pg_temp.refused($q$select public.normalize_task_recurrence('[1]')$q$, '22023'), 'a rule is an object');
end $$;

-- ===================================== 6. finishing a repeating task
do $$
declare
  ada uuid := pg_temp.i('ada');
  bob uuid := pg_temp.i('bob');
  grp uuid := pg_temp.i('grp');
  lid uuid;
  water_id uuid := gen_random_uuid();
  step_id uuid := gen_random_uuid();
  bins_id uuid := gen_random_uuid();
  wash_id uuid := gen_random_uuid();
  once_id uuid := gen_random_uuid();
  item jsonb;
  next_row public.task_items%rowtype;
  n integer;
begin
  perform pg_temp.act(ada);
  lid := (public.create_task_list(grp, 'Weekly', null)->>'id')::uuid;
  perform public.set_task_list_fields(lid, '[{"id":"cost","name":"Cost","type":"number"}]'::jsonb);

  -- No date, no repeat.
  item := public.upsert_task_item(lid, jsonb_build_object('id', bins_id, 'title', 'Bins',
    'recurrence', jsonb_build_object('freq', 'weekly', 'interval', 1)));
  perform pg_temp.expect(item->'recurrence' = 'null'::jsonb, 'a repeat without a date is dropped');
  item := public.upsert_task_item(lid, jsonb_build_object('id', bins_id,
    'due_at', (now() - interval '2 days')::text, 'due_has_time', true,
    'recurrence', jsonb_build_object('freq', 'daily', 'interval', 1, 'tz_offset', 0),
    'assignees', jsonb_build_array(bob), 'priority', 3, 'custom', jsonb_build_object('cost', 9)));
  perform pg_temp.expect(item->'recurrence'->>'freq' = 'daily', 'with a date the rule is kept');
  perform public.upsert_task_item(lid, jsonb_build_object('id', step_id, 'title', 'Take out the glass', 'parent_id', bins_id));
  perform public.upsert_task_item(lid, jsonb_build_object('id', wash_id, 'title', 'Wash', 'parent_id', bins_id));
  perform public.set_task_item_done(wash_id, true);

  perform public.set_task_item_done(bins_id, true);
  perform pg_temp.root();
  select count(*) into n from public.task_items i where i.list_id = lid and i.title = 'Bins' and i.deleted_at is null;
  perform pg_temp.expect(n = 2, 'finishing a repeating task makes the next one');
  select * into next_row from public.task_items i
    where i.list_id = lid and i.title = 'Bins' and i.completed_at is null;
  perform pg_temp.expect(next_row.due_at > now() and next_row.due_at <= now() + interval '25 hours',
    'it is due on the first date after now, not on a date that already passed');
  perform pg_temp.expect(next_row.status = 'todo' and next_row.priority = 3 and (next_row.custom->>'cost')::numeric = 9,
    'it starts open and keeps the priority and the fields');
  perform pg_temp.expect(next_row.recurrence->>'freq' = 'daily', 'and the rule');
  perform pg_temp.expect((select next_item_id from public.task_items where id = bins_id) = next_row.id, 'the finished task points to its next one');
  perform pg_temp.expect((select array_agg(user_id) from public.task_item_assignees where item_id = next_row.id) = array[bob],
    'the same people are on it');
  perform pg_temp.expect(not exists (select 1 from public.task_notifications where item_id = next_row.id and kind = 'assigned'),
    'who are not told of an assignment');
  perform pg_temp.expect((select count(*) from public.task_items c where c.parent_id = next_row.id and c.deleted_at is null and c.completed_at is null and c.status = 'todo') = 2,
    'its steps start over, open');
  perform pg_temp.expect((select count(*) from public.task_items c where c.parent_id = bins_id) = 2, 'the finished task keeps its steps');

  -- Checking it off again does not make a second copy.
  perform pg_temp.act(ada);
  perform public.set_task_item_done(bins_id, false);
  perform public.set_task_item_done(bins_id, true);
  perform pg_temp.root();
  select count(*) into n from public.task_items i where i.list_id = lid and i.title = 'Bins' and i.deleted_at is null;
  perform pg_temp.expect(n = 2, 'checking it off a second time makes no more copies');

  -- The next one repeats in turn.
  perform pg_temp.act(ada);
  perform public.set_task_item_done(next_row.id, true);
  perform pg_temp.root();
  select count(*) into n from public.task_items i where i.list_id = lid and i.title = 'Bins' and i.deleted_at is null;
  perform pg_temp.expect(n = 3, 'and so on');

  -- A subtask never repeats; a task without a rule makes nothing.
  perform pg_temp.act(ada);
  item := public.upsert_task_item(lid, jsonb_build_object('id', wash_id,
    'due_at', (now() + interval '1 day')::text, 'recurrence', jsonb_build_object('freq', 'daily', 'interval', 1)));
  perform pg_temp.expect(item->'recurrence' = 'null'::jsonb, 'a subtask cannot repeat');
  perform public.upsert_task_item(lid, jsonb_build_object('id', once_id, 'title', 'Once', 'due_at', (now() + interval '1 day')::text));
  perform pg_temp.root();
  select count(*) into n from public.task_items i where i.list_id = lid;
  perform pg_temp.act(ada);
  perform public.set_task_item_done(once_id, true);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.task_items i where i.list_id = lid) = n,
    'a task with no rule makes nothing when it is finished');

  -- Moving it with a patch (the board) works the same as the check box.
  perform pg_temp.act(ada);
  perform public.upsert_task_item(lid, jsonb_build_object('id', water_id, 'title', 'Water the plants',
    'due_at', (now() + interval '3 days')::text, 'due_has_time', true,
    'recurrence', jsonb_build_object('freq', 'weekly', 'interval', 1, 'tz_offset', 0)));
  perform public.upsert_task_item(lid, jsonb_build_object('id', water_id, 'status', 'done'));
  perform pg_temp.root();
  select * into next_row from public.task_items i
    where i.list_id = lid and i.title = 'Water the plants' and i.completed_at is null;
  perform pg_temp.expect(next_row.id is not null and next_row.due_at > now() + interval '9 days' and next_row.due_has_time,
    'finished early, the next one is a week after the one it replaces');
end $$;

-- ===================================== 7. closing an account
do $$
declare
  ada uuid := pg_temp.i('ada');
  cat uuid := pg_temp.i('cat');
  lid uuid := pg_temp.i('list');
  item_id uuid := gen_random_uuid();
begin
  perform pg_temp.act(ada);
  perform public.upsert_task_item(lid, jsonb_build_object('id', item_id, 'title', 'Owned by cat',
    'custom', jsonb_build_object('who', cat, 'cost', 3)));
  perform pg_temp.expect((select custom->>'who' from public.task_items where id = item_id) = cat::text, 'a person is in the field');
  perform pg_temp.root();
  update public.profiles set deleted_at = now() where id = cat;
  perform pg_temp.expect((select custom = jsonb_build_object('cost', 3) from public.task_items where id = item_id),
    'closing an account takes the person out of person fields and leaves the rest');
end $$;

-- ===================================== 8. the data export
do $$
declare
  ada uuid := pg_temp.i('ada');
  bob uuid := pg_temp.i('bob');
  lid uuid := pg_temp.i('list');
  result jsonb;
  item_id uuid := gen_random_uuid();
begin
  perform pg_temp.act(ada);
  perform public.set_task_list_fields(lid, '[
    {"id":"cost","name":"Cost","type":"number"},
    {"id":"area","name":"Area","type":"select","options":[{"id":"home","name":"Home"}]},
    {"id":"who","name":"Owner","type":"person"}
  ]'::jsonb);
  perform public.upsert_task_item(lid, jsonb_build_object('id', item_id, 'title', 'Exported',
    'custom', jsonb_build_object('cost', 7, 'area', 'home', 'who', bob)));
  perform pg_temp.expect(pg_temp.refused(format('select public.export_my_task_extras(%L)', ada)), 'signed-in people cannot call the export');
  perform pg_temp.root();
  result := public.export_my_task_extras(ada);
  perform pg_temp.expect(jsonb_array_length(result->'lists') >= 1, 'the export lists my task lists');
  perform pg_temp.expect(exists (
    select 1
    from jsonb_array_elements(result->'lists') l, jsonb_array_elements(l->'items') i, jsonb_array_elements(i->'values') v
    where i->>'title' = 'Exported' and v->>'field' = 'Area' and v->>'value' = 'Home'
  ), 'a choice is exported by its name');
  perform pg_temp.expect(exists (
    select 1
    from jsonb_array_elements(result->'lists') l, jsonb_array_elements(l->'items') i, jsonb_array_elements(i->'values') v
    where i->>'title' = 'Exported' and v->>'field' = 'Owner' and v->'value'->>'username' = 'bob_t2'
  ), 'a person is exported by name');
  perform pg_temp.expect(exists (
    select 1 from jsonb_array_elements(result->'lists') l where l->>'title' = 'Chores' and jsonb_array_length(l->'fields') = 3
  ), 'and the fields of lists I made');
  perform pg_temp.expect(pg_temp.refused($q$select public.export_my_task_extras(null)$q$, '22023'), 'a user is required');
end $$;
\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'tasks2: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
