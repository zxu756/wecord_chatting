-- Behaviour checks for notes 2.0 (D5: tables, comments, templates, pages on
-- the web, leaving and exporting; migrations 202610240300 to 202610240340).
-- Run by test/supabase/notes2_test.dart against the local database: it
-- applies the migrations it needs in a transaction, plays people through
-- them, and rolls everything back. Run from the repository root.
--
-- What it walks through: tables (what a block may hold, the scrub when a
-- note or block is deleted), comments (who can read, write, edit, delete,
-- resolve; members only; blocked people; a suspended circle; quotations that
-- must be in the block; mentions and who is told; replies), templates (only
-- the owner; pictures and mentions left out; checked blocks; safe to send
-- again), publishing (only editors; the token; withdrawing; a deleted note, a
-- suspended circle, a publisher who left; what the page holds and does not;
-- nobody but the service role asks by token) and the account (what goes when
-- an account is deleted, the export).
\set ON_ERROR_STOP on

begin;

do $$ begin perform pg_advisory_xact_lock(20261017); end $$;
set local client_min_messages = warning;

-- Every migration after the local baseline (202610170001), in order.
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
\i supabase/migrations/202610230300_circle_invite_tracking.sql
\i supabase/migrations/202610230310_circle_insights_data.sql
\i supabase/migrations/202610230320_circle_insights_rpc.sql
\i supabase/migrations/202610230600_status_visibility.sql
\i supabase/migrations/202610230610_profile_birthday.sql
\i supabase/migrations/202610230620_birthday_push.sql
\i supabase/migrations/202610230630_support_links.sql
\i supabase/migrations/202610230640_friend_source.sql
\i supabase/migrations/202610230650_mutuals.sql
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
\i supabase/migrations/202610240600_feature_flags.sql
\i supabase/migrations/202610240610_feature_flags_admin.sql
\i supabase/migrations/202610240620_announcements.sql
\i supabase/migrations/202610240630_announcements_admin.sql
\i supabase/migrations/202610240640_user_feedback.sql
\i supabase/migrations/202610240650_feedback_admin.sql
\i supabase/migrations/202610240660_export_my_feedback.sql
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
-- ada owns the group and writes the notes; bob and cat are members; dan is a
-- stranger; eve is a member whom ada blocked; gus is a member who will
-- leave; fay and hal are circle members; root is the platform admin.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@n2.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'gus'),(7,'fay'),(8,'hal'),(9,'root')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_n2', initcap(name)
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'gus'),(7,'fay'),(8,'hal'),(9,'root')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'gus'),(7,'fay'),(8,'hal'),(9,'root')) v(n, name);

with c as (insert into public.conversations (type, title) values ('group', 'Notes group') returning id)
insert into pg_temp.ids select 'group', id from c;
insert into public.conversation_members (conversation_id, user_id, role)
select pg_temp.i('group'), pg_temp.i(n), r
from (values ('ada','owner'),('bob','member'),('cat','member'),('eve','member'),('gus','member')) v(n, r);
with c as (insert into public.conversations (type, title) values ('group', 'Other group') returning id)
insert into pg_temp.ids select 'other', id from c;
insert into public.conversation_members (conversation_id, user_id, role)
select pg_temp.i('other'), pg_temp.i(n), r
from (values ('dan','owner')) v(n, r);

insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('ada'), pg_temp.i('eve'));
insert into public.app_admins (user_id, role) values (pg_temp.i('root'), 'owner');

-- Two notes: "plan" (ada's, everyone may edit) and "locked" (managers only).
select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'plan', (public.create_note(pg_temp.i('group'), 'Plan', null, null) ->> 'id')::uuid;
insert into pg_temp.ids select 'locked', (public.create_note(pg_temp.i('group'), 'Locked', null, null) ->> 'id')::uuid;
select public.update_note_meta(pg_temp.i('locked'), '{"managers_only": true}'::jsonb);
select pg_temp.root();
insert into pg_temp.ids
select 'plan_b1', b.id from public.note_blocks b where b.note_id = pg_temp.i('plan');
insert into pg_temp.ids
select 'locked_b1', b.id from public.note_blocks b where b.note_id = pg_temp.i('locked');

-- ===================================== 1. tables
do $$
declare
  ada uuid := pg_temp.i('ada');
  note uuid := pg_temp.i('plan');
  b1 uuid := pg_temp.i('plan_b1');
  tid uuid := '00000000-0000-4000-8000-00000000aa01';
  res jsonb;
  good jsonb := '{"header": true, "cols": ["c1", "c2"], "rows": [{"id": "r1", "c": {"c1": "Name", "c2": "Day"}}, {"id": "r2", "c": {"c1": "Ada"}}]}';
begin
  perform pg_temp.act(ada);
  res := public.note_apply_ops(note, jsonb_build_array(
    jsonb_build_object('op', 'put', 'id', b1, 'base_rev', 1, 'pos', 'V', 'kind', 'paragraph',
      'text', 'Hello plan world', 'marks', '[[0, 5, "b"], [6, 10, "m:00000000-0000-4000-8000-000000000002"]]'::jsonb, 'props', '{}'::jsonb),
    jsonb_build_object('op', 'put', 'id', tid, 'base_rev', null, 'pos', 'W', 'kind', 'table',
      'text', '', 'marks', '[]'::jsonb, 'props', good)));
  perform pg_temp.expect(res -> 0 ->> 'status' = 'ok', 'a paragraph is still accepted');
  perform pg_temp.expect(res -> 1 ->> 'status' = 'ok', 'a table is accepted');
  perform pg_temp.root();
  perform pg_temp.expect((select props = good from public.note_blocks where id = tid), 'the table keeps its cells');

  perform pg_temp.act(ada);
  res := public.note_apply_ops(note, jsonb_build_array(
    jsonb_build_object('op', 'put', 'id', gen_random_uuid(), 'base_rev', null, 'pos', 'X', 'kind', 'table',
      'text', '', 'marks', '[]'::jsonb, 'props', '{"cols": [], "rows": []}'::jsonb),
    jsonb_build_object('op', 'put', 'id', gen_random_uuid(), 'base_rev', null, 'pos', 'X', 'kind', 'table',
      'text', '', 'marks', '[]'::jsonb, 'props', '{}'::jsonb),
    jsonb_build_object('op', 'put', 'id', gen_random_uuid(), 'base_rev', null, 'pos', 'X', 'kind', 'table',
      'text', '', 'marks', '[]'::jsonb, 'props', jsonb_build_object('cols', (select jsonb_agg('c' || g) from generate_series(1, 13) g), 'rows', '[{"id": "r1", "c": {}}]'::jsonb)),
    jsonb_build_object('op', 'put', 'id', gen_random_uuid(), 'base_rev', null, 'pos', 'X', 'kind', 'table',
      'text', '', 'marks', '[]'::jsonb, 'props', jsonb_build_object('cols', '["c1"]'::jsonb, 'rows', jsonb_build_array(jsonb_build_object('id', 'r1', 'c', jsonb_build_object('c1', repeat('x', 1001)))))),
    jsonb_build_object('op', 'put', 'id', gen_random_uuid(), 'base_rev', null, 'pos', 'X', 'kind', 'table',
      'text', '', 'marks', '[]'::jsonb, 'props', '{"cols": ["c1"], "rows": [{"id": "r1", "c": {"c1": 5}}]}'::jsonb),
    jsonb_build_object('op', 'put', 'id', gen_random_uuid(), 'base_rev', null, 'pos', 'X', 'kind', 'table',
      'text', '', 'marks', '[]'::jsonb, 'props', jsonb_build_object('cols', '["c1"]'::jsonb, 'rows', (select jsonb_agg(jsonb_build_object('id', 'r' || g, 'c', '{}'::jsonb)) from generate_series(1, 201) g))),
    jsonb_build_object('op', 'put', 'id', gen_random_uuid(), 'base_rev', null, 'pos', 'X', 'kind', 'bogus',
      'text', '', 'marks', '[]'::jsonb, 'props', '{}'::jsonb),
    jsonb_build_object('op', 'put', 'id', gen_random_uuid(), 'base_rev', null, 'pos', 'X', 'kind', 'paragraph',
      'text', '', 'marks', '[]'::jsonb, 'props', jsonb_build_object('x', repeat('y', 4001))),
    jsonb_build_object('op', 'put', 'id', gen_random_uuid(), 'base_rev', null, 'pos', 'bad pos!', 'kind', 'paragraph',
      'text', '', 'marks', '[]'::jsonb, 'props', '{}'::jsonb)));
  perform pg_temp.expect(res -> 0 ->> 'status' = 'rejected', 'a table needs a column and a row');
  perform pg_temp.expect(res -> 1 ->> 'status' = 'rejected', 'a table without cols and rows is refused');
  perform pg_temp.expect(res -> 2 ->> 'status' = 'rejected', 'a table of 13 columns is refused');
  perform pg_temp.expect(res -> 3 ->> 'status' = 'rejected', 'a cell of 1001 characters is refused');
  perform pg_temp.expect(res -> 4 ->> 'status' = 'rejected', 'a cell that is not text is refused');
  perform pg_temp.expect(res -> 5 ->> 'status' = 'rejected', 'a table of 201 rows is refused');
  perform pg_temp.expect(res -> 6 ->> 'status' = 'rejected', 'an unknown kind is refused');
  perform pg_temp.expect(res -> 7 ->> 'status' = 'rejected', 'other blocks keep the 4000 character limit on props');
  perform pg_temp.expect(res -> 8 ->> 'status' = 'rejected', 'a bad position is refused');

  -- Deleting a table block empties its cells.
  res := public.note_apply_ops(note, jsonb_build_array(jsonb_build_object('op', 'del', 'id', tid)));
  perform pg_temp.root();
  perform pg_temp.expect((select props = '{}'::jsonb and deleted from public.note_blocks where id = tid),
    'a deleted table block loses its cells');
end $$;

-- A deleted note loses the cells of its tables, as well as its text.
do $$
declare
  ada uuid := pg_temp.i('ada');
  n uuid;
  tid uuid := gen_random_uuid();
begin
  perform pg_temp.act(ada);
  n := (public.create_note(pg_temp.i('group'), 'To delete', null, null) ->> 'id')::uuid;
  perform public.note_apply_ops(n, jsonb_build_array(
    jsonb_build_object('op', 'put', 'id', tid, 'base_rev', null, 'pos', 'W', 'kind', 'table', 'text', '',
      'marks', '[]'::jsonb, 'props', '{"cols": ["c1"], "rows": [{"id": "r1", "c": {"c1": "secret cell"}}]}'::jsonb)));
  perform public.delete_note(n);
  perform pg_temp.root();
  perform pg_temp.expect((select props = '{}'::jsonb from public.note_blocks where id = tid), 'a deleted note: the cells of its table are gone');
end $$;

-- ===================================== 2. comments
do $$
declare
  ada uuid := pg_temp.i('ada');
  bob uuid := pg_temp.i('bob');
  cat uuid := pg_temp.i('cat');
  dan uuid := pg_temp.i('dan');
  eve uuid := pg_temp.i('eve');
  note uuid := pg_temp.i('plan');
  b1 uuid := pg_temp.i('plan_b1');
  c jsonb;
  c1 uuid;
  r1 uuid;
  bobs uuid;
  n integer;
begin
  -- Words of the block ("Hello plan world", "plan" is 6..10).
  perform pg_temp.act(bob);
  c := public.add_note_comment(note, 'Is this the final plan?', b1, 6, 10, 'plan', null, array[ada, dan, bob, eve]);
  c1 := (c ->> 'id')::uuid;
  perform pg_temp.expect(c ->> 'anchor_text' = 'plan' and (c ->> 'anchor_start')::int = 6, 'a comment on words of a block');
  perform pg_temp.expect(c ->> 'author_name' = 'Bob' and (c ->> 'can_delete')::boolean and (c ->> 'can_edit')::boolean, 'it knows its author and what bob may do');
  perform pg_temp.expect(pg_temp.state(format('select public.add_note_comment(%L, ''x'', %L, 6, 10, ''nonsense'')', note, b1)) = '22023', 'a made-up quotation is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_note_comment(%L, ''x'', %L, 6, null, ''plan'')', note, b1)) = '22023', 'an anchor needs both ends');
  perform pg_temp.expect(pg_temp.state(format('select public.add_note_comment(%L, ''x'', %L, 10, 6, ''plan'')', note, b1)) = '22023', 'and an end after the start');
  perform pg_temp.expect(pg_temp.state(format('select public.add_note_comment(%L, ''x'', %L, null, null, ''plan'')', note, gen_random_uuid())) = '22023', 'a block that is not in the note is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_note_comment(%L, ''   '')', note)) = '22023', 'an empty comment is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_note_comment(%L, %L)', note, repeat('x', 2001))) = '22023', 'a comment of 2001 characters is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_note_comment(%L, ''x'', null, 1, 2, null)', note)) = '22023', 'an anchor without a block is refused');
  perform pg_temp.expect(public.add_note_comment(note, 'On the whole note') ->> 'block_id' is null, 'a comment on the whole note');
  perform pg_temp.expect((public.add_note_comment(note, 'On the block', b1) ->> 'anchor_start') is null, 'a comment on a whole block');

  -- Safe to send again.
  bobs := gen_random_uuid();
  perform public.add_note_comment(note, 'Once', null, null, null, null, null, '{}', bobs);
  perform public.add_note_comment(note, 'Once', null, null, null, null, null, '{}', bobs);
  perform pg_temp.expect((select count(*) from public.note_comments where id = bobs) = 1, 'sending a comment twice makes one');
  perform pg_temp.expect(pg_temp.state(format('select public.add_note_comment(%L, ''Once'', null, null, null, null, null, ''{}'', %L)', note, bobs)) = 'ok', 'and answers the same');

  -- Who is told: members who can see it, not dan (a stranger), not eve (ada blocked her but bob did not: she is told), not bob himself.
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.note_comment_notifications where comment_id = c1 and user_id = ada and kind = 'mention') = 1, 'a mentioned member is told');
  perform pg_temp.expect((select count(*) from public.note_comment_notifications where comment_id = c1 and user_id = dan) = 0, 'a stranger is not told');
  perform pg_temp.expect((select count(*) from public.note_comment_notifications where comment_id = c1 and user_id = bob) = 0, 'the author is not told of their own comment');
  perform pg_temp.expect((select count(*) from public.note_comment_notifications where comment_id = c1 and user_id = eve) = 1, 'someone the author did not block is told');
  perform pg_temp.expect((select cardinality(mentions) from public.note_comments where id = c1) = 2, 'only the people who were told are kept');

  -- Reading: members only.
  perform pg_temp.act(cat);
  perform pg_temp.expect((select count(*) from public.list_note_comments(note)) >= 4, 'a member reads the comments');
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.note_comments where note_id = %L', note)) >= 4, 'and through the table');
  perform pg_temp.act(dan);
  perform pg_temp.expect(pg_temp.state(format('select public.list_note_comments(%L)', note)) = 'P0002', 'a stranger cannot list them');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.note_comments') = 0, 'a stranger reads none from the table');
  perform pg_temp.expect(pg_temp.state(format('select public.add_note_comment(%L, ''hi'')', note)) = 'P0002', 'a stranger cannot comment');
  perform pg_temp.expect(pg_temp.state(format('select public.resolve_note_comment(%L)', c1)) = 'P0002', 'or resolve');
  perform pg_temp.expect(pg_temp.state(format('select public.delete_note_comment(%L)', c1)) = 'P0002', 'or delete');
  perform pg_temp.expect(pg_temp.state(format('select public.edit_note_comment(%L, ''hi'')', c1)) = 'P0002', 'or edit');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused(format('select public.list_note_comments(%L)', note)), 'signed out: no list');
  perform pg_temp.expect(pg_temp.refused('select 1 from public.note_comments'), 'signed out: no table');
  perform pg_temp.expect(pg_temp.refused(format('select public.add_note_comment(%L, ''hi'')', note)), 'signed out: no comment');
  perform pg_temp.act(cat);
  perform pg_temp.expect(pg_temp.refused('insert into public.note_comments (note_id, author_id, body) select note_id, author_id, ''forged'' from public.note_comments limit 1'), 'members cannot write the table directly');
  perform pg_temp.expect(pg_temp.refused('update public.note_comments set body = ''x'''), 'or update it');
  perform pg_temp.expect(pg_temp.refused('delete from public.note_comments'), 'or delete from it');

  -- Replies.
  perform pg_temp.act(cat);
  c := public.add_note_comment(note, 'Not yet, I think', b1, 0, 5, 'Hello', null, '{}');
  perform pg_temp.act(ada);
  r1 := (public.add_note_comment(note, 'It is', null, null, null, null, c1, array[cat]) ->> 'id')::uuid;
  perform pg_temp.expect((select block_id is null and anchor_text is null from public.note_comments where id = r1), 'a reply has no anchor');
  perform pg_temp.expect(pg_temp.state(format('select public.add_note_comment(%L, ''x'', null, null, null, null, %L)', note, r1)) = 'P0002', 'a reply to a reply is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.add_note_comment(%L, ''x'', null, null, null, null, %L)', pg_temp.i('locked'), c1)) = 'P0002', 'a reply under a comment of another note is refused');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.note_comment_notifications where comment_id = r1 and user_id = bob and kind = 'reply') = 1, 'the author of the comment is told of a reply');
  perform pg_temp.expect((select count(*) from public.note_comment_notifications where comment_id = r1 and user_id = cat and kind = 'mention') = 1, 'and a mention in it');

  -- The notifications list.
  perform pg_temp.act(bob);
  perform pg_temp.expect((select count(*) from public.list_note_comment_notifications()) = 1, 'bob sees his notification');
  perform pg_temp.expect((select is_unread and snippet = 'It is' and note_title = 'Plan' and actor_name = 'Ada' from public.list_note_comment_notifications()), 'with the words, the note and who');
  perform public.mark_note_comment_notifications_read(null);
  perform pg_temp.expect((select not is_unread from public.list_note_comment_notifications()), 'and marks it read');
  perform pg_temp.act(dan);
  perform pg_temp.expect((select count(*) from public.list_note_comment_notifications()) = 0, 'a stranger has none');

  -- Blocked people.
  perform pg_temp.act(eve);
  c := public.add_note_comment(note, 'Eve here', b1);
  perform pg_temp.act(ada);
  perform pg_temp.expect((select count(*) from public.list_note_comments(note) j where j ->> 'author_name' = 'Eve') = 0, 'ada does not see the comments of someone she blocked');
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.note_comments where author_id = %L', eve)) = 0, 'not through the table either');
  perform pg_temp.act(eve);
  perform pg_temp.expect((select count(*) from public.list_note_comments(note) j where j ->> 'author_name' = 'Ada') = 0, 'a block works both ways: eve does not read ada either');
  perform pg_temp.act(bob);
  perform pg_temp.expect((select count(*) from public.list_note_comments(note) j where j ->> 'author_name' = 'Eve') = 1, 'bob sees eve''s comment');
  -- eve replies under ada's thread; ada does not see it.
  perform pg_temp.act(eve);
  perform public.add_note_comment(note, 'Reply from eve', null, null, null, null, c1);
  perform pg_temp.act(ada);
  perform pg_temp.expect((select count(*) from public.list_note_comments(note) j where j ->> 'body' = 'Reply from eve') = 0, 'nor her reply under ada''s thread');
  -- ada mentioning eve (blocked) tells nobody.
  perform public.add_note_comment(note, 'Hey eve', null, null, null, null, null, array[eve]);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.note_comment_notifications where user_id = eve and actor_id = ada) = 0, 'a mention of someone you blocked tells them nothing');
  -- eve replying to ada's comment does not notify ada.
  perform pg_temp.expect((select count(*) from public.note_comment_notifications where user_id = ada and actor_id = eve) = 0, 'a blocked person''s reply tells ada nothing');

  -- Editing, deleting, resolving.
  perform pg_temp.act(cat);
  perform pg_temp.expect(pg_temp.state(format('select public.edit_note_comment(%L, ''hijack'')', c1)) = 'P0002', 'only the author edits');
  perform pg_temp.expect(pg_temp.state(format('select public.delete_note_comment(%L)', c1)) = '42501', 'a member cannot delete another''s comment');
  perform pg_temp.act(bob);
  c := public.edit_note_comment(c1, 'Is this the plan?');
  perform pg_temp.expect(c ->> 'body' = 'Is this the plan?' and c ->> 'edited_at' is not null, 'the author edits');
  perform pg_temp.act(cat);
  c := public.resolve_note_comment(c1);
  perform pg_temp.expect(c ->> 'resolved_at' is not null and c ->> 'resolved_by_name' = 'Cat', 'anybody who can comment resolves');
  perform pg_temp.expect(pg_temp.state(format('select public.resolve_note_comment(%L)', r1)) = 'P0002', 'a reply is not resolved on its own');
  c := public.resolve_note_comment(c1, false);
  perform pg_temp.expect(c ->> 'resolved_at' is null, 'and opens it again');
  perform pg_temp.act(ada);
  perform public.delete_note_comment(r1);
  perform pg_temp.expect((select count(*) from public.note_comments where id = r1) = 0, 'a manager deletes a reply');
  perform pg_temp.act(bob);
  perform public.delete_note_comment(c1);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.note_comments where id = c1 or parent_id = c1) = 0, 'deleting a comment takes its replies');
  perform pg_temp.expect((select count(*) from public.note_comment_notifications where comment_id = c1) = 0, 'and its notifications');
end $$;

-- A deleted note takes its comments.
do $$
declare
  ada uuid := pg_temp.i('ada');
  n uuid;
begin
  perform pg_temp.act(ada);
  n := (public.create_note(pg_temp.i('group'), 'Short lived', null, null) ->> 'id')::uuid;
  perform public.add_note_comment(n, 'doomed');
  perform public.delete_note(n);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.note_comments where note_id = n) = 0, 'a deleted note loses its comments');
end $$;

-- ===================================== 3. templates
do $$
declare
  ada uuid := pg_temp.i('ada');
  bob uuid := pg_temp.i('bob');
  dan uuid := pg_temp.i('dan');
  note uuid := pg_temp.i('plan');
  t jsonb;
  tid uuid;
  made jsonb;
  made_id uuid := gen_random_uuid();
  img uuid := gen_random_uuid();
  n integer;
begin
  perform pg_temp.act(ada);
  -- A picture and a mention in the note stay out of the template.
  perform public.note_apply_ops(note, jsonb_build_array(
    jsonb_build_object('op', 'put', 'id', img, 'base_rev', null, 'pos', 'Y', 'kind', 'image', 'text', '', 'marks', '[]'::jsonb,
      'props', jsonb_build_object('path', note::text || '/pic.png', 'name', 'pic.png')),
    jsonb_build_object('op', 'put', 'id', gen_random_uuid(), 'base_rev', null, 'pos', 'Z', 'kind', 'table', 'text', '', 'marks', '[]'::jsonb,
      'props', '{"cols": ["c1"], "rows": [{"id": "r1", "c": {"c1": "kept"}}]}'::jsonb)));
  t := public.save_note_template(note, 'Weekly');
  tid := (t ->> 'id')::uuid;
  perform pg_temp.expect(t ->> 'name' = 'Weekly' and t ->> 'title' = 'Plan', 'a template is made of a note');
  perform pg_temp.root();
  perform pg_temp.expect((select not exists (select 1 from jsonb_array_elements(blocks) b where b ->> 'kind' = 'image') from public.note_templates where id = tid), 'pictures stay out');
  perform pg_temp.expect((select not (blocks::text like '%m:0000%') from public.note_templates where id = tid), 'and mentions of people');
  perform pg_temp.expect((select blocks::text like '%"kept"%' from public.note_templates where id = tid), 'a table stays');
  perform pg_temp.expect((select blocks::text like '%Hello plan world%' from public.note_templates where id = tid), 'and the words');

  perform pg_temp.act(bob);
  perform pg_temp.expect((select count(*) from public.list_note_templates()) = 0, 'templates are private to their owner');
  perform pg_temp.expect(pg_temp.state(format('select public.get_note_template(%L)', tid)) = 'P0002', 'another person cannot read one');
  perform public.delete_note_template(tid);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.note_templates where id = tid) = 1, 'nor delete it');
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.refused('select 1 from public.note_templates'), 'nor read the table');
  perform pg_temp.act(dan);
  perform pg_temp.expect(pg_temp.state(format('select public.save_note_template(%L, ''Mine'')', note)) = 'P0002', 'a stranger cannot make a template of the note');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused('select public.list_note_templates()'), 'signed out: no templates');

  perform pg_temp.act(ada);
  perform pg_temp.expect((select count(*) from public.list_note_templates()) = 1, 'the owner lists theirs');
  perform pg_temp.expect(jsonb_array_length(public.get_note_template(tid) -> 'blocks') >= 2, 'and reads it');
  perform pg_temp.expect(pg_temp.state(format('select public.save_note_template(%L, '' '')', note)) = '22023', 'a template needs a name');
  for n in 1..29 loop
    perform public.save_note_template(note, 'T' || n);
  end loop;
  perform pg_temp.expect(pg_temp.state(format('select public.save_note_template(%L, ''One too many'')', note)) = '22023', 'at most 30 templates');
  perform public.delete_note_template(tid);
  perform pg_temp.expect((select count(*) from public.list_note_templates()) = 29, 'the owner deletes one');

  -- Starting a note from blocks.
  made := public.create_note_from_blocks(
    pg_temp.i('group'), 'Meeting', E'\U0001F4CB',
    jsonb_build_array(
      jsonb_build_object('kind', 'h2', 'text', 'Agenda'),
      jsonb_build_object('kind', 'todo', 'text', 'First', 'props', '{"checked": false}'::jsonb),
      jsonb_build_object('kind', 'table', 'text', '', 'props', '{"cols": ["c1", "c2"], "rows": [{"id": "r1", "c": {"c1": "a"}}]}'::jsonb),
      jsonb_build_object('kind', 'paragraph', 'text', 'Hi @bob', 'marks', '[[3, 7, "m:00000000-0000-4000-8000-000000000002"], [0, 2, "b"]]'::jsonb)),
    made_id);
  perform pg_temp.expect((made ->> 'id')::uuid = made_id and made ->> 'title' = 'Meeting', 'a note starts from a template');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.note_blocks where note_id = made_id) = 4, 'with its blocks (and not the empty one)');
  perform pg_temp.expect((select string_agg(kind, ',' order by pos) from public.note_blocks where note_id = made_id) = 'h2,todo,table,paragraph', 'in order');
  perform pg_temp.expect((select count(*) from public.note_blocks where note_id = made_id and pos !~ '0$') = 4, 'with keys that never end in 0');
  perform pg_temp.expect((select marks::text not like '%m:0000%' and marks::text like '%"b"%' from public.note_blocks where note_id = made_id and kind = 'paragraph'), 'mentions are dropped from the marks, formatting stays');
  perform pg_temp.act(ada);
  perform public.create_note_from_blocks(pg_temp.i('group'), 'Meeting', null, '[{"kind": "h2", "text": "Again"}]'::jsonb, made_id);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.note_blocks where note_id = made_id) = 4, 'sending it again changes nothing');
  perform pg_temp.act(ada);
  perform pg_temp.expect(pg_temp.state(format('select public.create_note_from_blocks(%L, ''x'', null, ''[{"kind": "bogus"}]''::jsonb)', pg_temp.i('group'))) = '22023', 'a bad block is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.create_note_from_blocks(%L, ''x'', null, ''[{"kind": "image", "props": {"path": "a/b.png"}}]''::jsonb)', pg_temp.i('group'))) = '22023', 'so is a picture of another note');
  perform pg_temp.expect(pg_temp.state(format('select public.create_note_from_blocks(%L, ''x'', null, ''[{"kind": "table", "props": {}}]''::jsonb)', pg_temp.i('group'))) = '22023', 'and a table that is not a table');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.notes where title = 'x') = 0, 'and leaves no note behind');
  perform pg_temp.act(dan);
  perform pg_temp.expect(pg_temp.state(format('select public.create_note_from_blocks(%L, ''x'', null, ''[]''::jsonb)', pg_temp.i('group'))) = '42501', 'a stranger cannot start a note in the group');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused(format('select public.create_note_from_blocks(%L, ''x'', null, ''[]''::jsonb)', pg_temp.i('group'))), 'signed out: no notes');
end $$;

-- ===================================== 4. publishing
do $$
declare
  ada uuid := pg_temp.i('ada');
  bob uuid := pg_temp.i('bob');
  cat uuid := pg_temp.i('cat');
  dan uuid := pg_temp.i('dan');
  gus uuid := pg_temp.i('gus');
  note uuid := pg_temp.i('plan');
  locked uuid := pg_temp.i('locked');
  p jsonb;
  tok text;
  tok2 text;
  page jsonb;
begin
  -- Only people who can edit.
  perform pg_temp.act(dan);
  perform pg_temp.expect(pg_temp.state(format('select public.publish_note(%L)', note)) = 'P0002', 'a stranger cannot publish');
  perform pg_temp.expect(pg_temp.state(format('select public.get_note_publication(%L)', note)) = 'P0002', 'or look');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused(format('select public.publish_note(%L)', note)), 'signed out: no publishing');
  perform pg_temp.act(cat);
  perform pg_temp.expect(pg_temp.state(format('select public.publish_note(%L)', locked)) = '42501', 'a member cannot publish a note locked to managers');
  perform pg_temp.act(ada);
  p := public.get_note_publication(note);
  perform pg_temp.expect(p ->> 'published' = 'false' and (p ->> 'can_publish')::boolean, 'nothing is published by default');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.note_publications) = 0, 'no row until someone publishes');

  perform pg_temp.act(bob);
  p := public.publish_note(note);
  tok := p ->> 'token';
  perform pg_temp.expect(tok ~ '^[0-9a-f]{48}$', 'a member who can edit publishes: a 192-bit token');
  perform pg_temp.expect(p ->> 'published' = 'true' and (p ->> 'allow_indexing')::boolean = false and p ->> 'published_by_name' = 'Bob', 'not for search engines by default');
  perform pg_temp.act(cat);
  p := public.get_note_publication(note);
  perform pg_temp.expect(p ->> 'published' = 'true' and p ->> 'token' = tok, 'another editor sees the link');
  perform pg_temp.act(ada);
  perform pg_temp.expect(public.publish_note(note) ->> 'token' = tok, 'publishing again keeps the link');
  perform pg_temp.expect((public.publish_note(note, true) ->> 'allow_indexing')::boolean and public.publish_note(note, true) ->> 'token' = tok, 'and takes the search engine choice');
  perform pg_temp.expect(not (public.publish_note(note, false) ->> 'allow_indexing')::boolean, 'which can be taken back');

  -- Nobody lists tokens.
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.refused('select token from public.note_publications'), 'members cannot read the table');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused('select token from public.note_publications'), 'nor can anybody signed out');
  perform pg_temp.expect(pg_temp.refused(format('select public.public_note_by_token(%L)', tok)), 'nor ask by token without the service role');
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.refused(format('select public.public_note_by_token(%L)', tok)), 'a member cannot either');

  -- The page.
  perform pg_temp.root();
  page := public.public_note_by_token(tok);
  perform pg_temp.expect(page ->> 'status' = 'ok' and page ->> 'title' = 'Plan', 'the service role gets the page');
  perform pg_temp.expect(jsonb_array_length(page -> 'blocks') >= 3, 'with its blocks');
  perform pg_temp.expect(not (page::text like '%m:0000%'), 'mentions of people are taken out');
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(page -> 'blocks') b where b -> 'props' ? 'secret'), 'and only the props of each kind');
  perform pg_temp.expect(not (page ? 'created_by') and not (page::text like '%0000000000%'), 'no ids of people');
  perform pg_temp.expect(not (page::text like '%Is this%') and not (page::text like '%comment%'), 'no comments');
  perform pg_temp.expect(public.public_note_by_token('0' || substr(tok, 2)) ->> 'status' = 'invalid', 'a nearly right token is not');
  perform pg_temp.expect(public.public_note_by_token(upper(tok)) ->> 'status' = 'invalid' or upper(tok) = tok, 'case counts');
  perform pg_temp.expect(public.public_note_by_token('abc') ->> 'status' = 'invalid', 'a short token is not');
  perform pg_temp.expect(public.public_note_by_token('') ->> 'status' = 'invalid' and public.public_note_by_token(null) ->> 'status' = 'invalid', 'nor an empty one');
  perform pg_temp.expect(public.public_note_by_token(repeat('0', 48)) ->> 'status' = 'invalid', 'nor an unknown one');
  perform pg_temp.expect(public.public_note_by_token(tok || 'x') ->> 'status' = 'invalid', 'nor a longer one');
  perform pg_temp.expect(public.public_note_by_token(tok || ' OR 1=1') ->> 'status' = 'invalid', 'nor an injection');

  -- A picture's props: only its path, name and size.
  perform pg_temp.act(ada);
  perform public.note_apply_ops(note, jsonb_build_array(jsonb_build_object('op', 'put', 'id', gen_random_uuid(), 'base_rev', null, 'pos', 'a', 'kind', 'image', 'text', '', 'marks', '[]'::jsonb,
    'props', jsonb_build_object('path', note::text || '/x.png', 'name', 'x.png', 'secret', 'hunter2', 'width', 10))));
  perform pg_temp.root();
  page := public.public_note_by_token(tok);
  perform pg_temp.expect(not (page::text like '%hunter2%'), 'a picture''s other props stay home');
  perform pg_temp.expect(page::text like '%x.png%', 'but its name and path go to the page');

  -- Withdrawing.
  perform pg_temp.act(cat);
  perform public.unpublish_note(note);
  perform pg_temp.root();
  perform pg_temp.expect(public.public_note_by_token(tok) ->> 'status' = 'invalid', 'withdrawn: the link stops at once');
  perform pg_temp.act(ada);
  tok2 := public.publish_note(note) ->> 'token';
  perform pg_temp.expect(tok2 <> tok, 'publishing again makes a new link');
  perform pg_temp.root();
  perform pg_temp.expect(public.public_note_by_token(tok) ->> 'status' = 'invalid' and public.public_note_by_token(tok2) ->> 'status' = 'ok', 'the old one stays dead');
  perform pg_temp.act(dan);
  perform pg_temp.expect(pg_temp.state(format('select public.unpublish_note(%L)', note)) = 'P0002', 'a stranger cannot withdraw');
  perform pg_temp.root();
  perform pg_temp.expect(public.public_note_by_token(tok2) ->> 'status' = 'ok', 'and it stands');

  -- A note that is deleted.
  perform pg_temp.act(ada);
  perform public.delete_note(note);
  perform pg_temp.root();
  perform pg_temp.expect(public.public_note_by_token(tok2) ->> 'status' = 'invalid', 'a deleted note: the link is dead');
  perform pg_temp.expect((select count(*) from public.note_publications where note_id = note) = 0, 'and the row is gone');
end $$;

-- A publisher who leaves; a suspended circle.
do $$
declare
  ada uuid := pg_temp.i('ada');
  gus uuid := pg_temp.i('gus');
  fay uuid := pg_temp.i('fay');
  n uuid;
  tok text;
  tok2 text;
  circle uuid;
  channel uuid;
  cnote uuid;
  ctok text;
begin
  perform pg_temp.act(ada);
  n := (public.create_note(pg_temp.i('group'), 'Gus writes', null, null) ->> 'id')::uuid;
  perform pg_temp.act(gus);
  tok := public.publish_note(n) ->> 'token';
  perform pg_temp.root();
  perform pg_temp.expect(public.public_note_by_token(tok) ->> 'status' = 'ok', 'a published note by gus is up');
  delete from public.conversation_members where conversation_id = pg_temp.i('group') and user_id = gus;
  perform pg_temp.expect(public.public_note_by_token(tok) ->> 'status' = 'invalid', 'the person who published it left: the link is dead');
  perform pg_temp.act(ada);
  perform pg_temp.expect(public.get_note_publication(n) ->> 'published' = 'false', 'it shows as not published');
  tok2 := public.publish_note(n) ->> 'token';
  perform pg_temp.expect(tok2 <> tok, 'and another editor publishes it again with a new link');
  perform pg_temp.root();
  perform pg_temp.expect(public.public_note_by_token(tok2) ->> 'status' = 'ok' and public.public_note_by_token(tok) ->> 'status' = 'invalid', 'the new link works, the old one does not');

  -- A circle channel.
  perform pg_temp.act(ada);
  circle := public.create_circle('N2 circle');
  perform pg_temp.root();
  select cc.conversation_id into channel from public.circle_channels cc where cc.circle_id = circle and cc.kind = 'text' order by cc.position limit 1;
  insert into public.circle_members (circle_id, user_id, role) values (circle, fay, 'member');
  insert into public.conversation_members (conversation_id, user_id, role)
  select cc.conversation_id, fay, 'member' from public.circle_channels cc where cc.circle_id = circle;
  perform pg_temp.act(ada);
  cnote := (public.create_note(channel, 'Circle note', null, null) ->> 'id')::uuid;
  ctok := public.publish_note(cnote) ->> 'token';
  perform public.add_note_comment(cnote, 'before the take-down');
  perform pg_temp.act(fay);
  perform pg_temp.expect(public.add_note_comment(cnote, 'a member comments in the channel') ->> 'body' is not null, 'a circle member comments');
  perform pg_temp.expect((select count(*) from public.list_note_comments(cnote)) = 2, 'and reads');
  perform pg_temp.root();
  perform pg_temp.expect(public.public_note_by_token(ctok) ->> 'status' = 'ok', 'the circle''s page is up');
  perform pg_temp.act(pg_temp.i('root'));
  perform public.admin_disable_circle(circle, 'delist', 'x');
  perform pg_temp.root();
  perform pg_temp.expect(public.public_note_by_token(ctok) ->> 'status' = 'ok', 'a delisted circle keeps its page');
  perform pg_temp.act(pg_temp.i('root'));
  perform public.admin_disable_circle(circle, 'suspend', 'x');
  perform pg_temp.root();
  perform pg_temp.expect(public.public_note_by_token(ctok) ->> 'status' = 'invalid', 'a suspended circle: the page is gone');
  perform pg_temp.act(fay);
  perform pg_temp.expect(pg_temp.state(format('select public.list_note_comments(%L)', cnote)) = 'P0002', 'and nobody reads the comments');
  perform pg_temp.expect(pg_temp.state(format('select public.add_note_comment(%L, ''still?'')', cnote)) = 'P0002', 'or writes one');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.note_comments') = 0, 'not through the table either');
  perform pg_temp.act(ada);
  perform pg_temp.expect(pg_temp.state(format('select public.publish_note(%L)', cnote)) = 'P0002', 'nor publishes the note');
  perform pg_temp.act(pg_temp.i('root'));
  perform public.admin_enable_circle(circle, 'cleared');
  perform pg_temp.root();
  perform pg_temp.expect(public.public_note_by_token(ctok) ->> 'status' = 'ok', 'lifted: the page is back');
end $$;

-- ===================================== 5. the account and the export
do $$
declare
  ada uuid := pg_temp.i('ada');
  bob uuid := pg_temp.i('bob');
  cat uuid := pg_temp.i('cat');
  n uuid;
  tok text;
  x jsonb;
  keep uuid;
begin
  perform pg_temp.act(ada);
  n := (public.create_note(pg_temp.i('group'), 'Bob''s page', null, null) ->> 'id')::uuid;
  perform pg_temp.act(bob);
  tok := public.publish_note(n) ->> 'token';
  perform public.add_note_comment(n, 'bob says hi', null, null, null, null, null, array[cat]);
  perform public.save_note_template(n, 'Bob''s template');
  perform pg_temp.act(cat);
  keep := (public.add_note_comment(n, 'cat answers') ->> 'id')::uuid;
  perform pg_temp.root();
  x := public.export_my_note_extras(bob);
  perform pg_temp.expect(jsonb_array_length(x -> 'comments') >= 1 and x::text like '%bob says hi%', 'the export has my comments');
  perform pg_temp.expect(jsonb_array_length(x -> 'templates') = 1, 'and my templates');
  perform pg_temp.expect(jsonb_array_length(x -> 'published') = 1 and not (x::text like '%' || tok || '%'), 'and my pages, without the link');
  perform pg_temp.expect(not (x::text like '%cat answers%'), 'but not what others wrote');
  perform pg_temp.act(cat);
  perform pg_temp.expect(pg_temp.refused(format('select public.export_my_note_extras(%L)', bob)), 'others cannot ask for it');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused(format('select public.export_my_note_extras(%L)', bob)), 'nor anyone signed out');

  perform pg_temp.root();
  update public.profiles set deleted_at = now() where id = bob;
  perform pg_temp.expect((select count(*) from public.note_comments where author_id = bob) = 0, 'a deleted account: its comments are erased');
  perform pg_temp.expect((select count(*) from public.note_templates where owner_id = bob) = 0, 'its templates');
  perform pg_temp.expect((select count(*) from public.note_publications where published_by = bob) = 0, 'its pages');
  perform pg_temp.expect(public.public_note_by_token(tok) ->> 'status' = 'invalid', 'and the link is dead');
  perform pg_temp.expect((select count(*) from public.note_comments where id = keep) = 1, 'what others wrote stays');
end $$;
\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'notes 2.0: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
