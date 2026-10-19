-- Behaviour checks for Favorites 2.0 (B3: migrations 202610250400 to
-- 202610250430). Run by test/supabase/favorites2_test.dart against the local
-- database: it applies every migration after the baseline in a transaction,
-- first builds a person with saved messages the way the first version kept
-- them, then applies these migrations, plays everyone through the RPCs and
-- rolls everything back. Run from the repository root.
--
-- What it walks through:
--   0. the old saved messages moving in (ids, done, the view older apps read);
--   1. keeping messages (who, recalled, expired, held, view-once);
--   2. keeping Moments and circle posts (friends, audience, membership);
--   3. links and notes (addresses, pictures, ownership of paths);
--   4. folders, tags, remarks, editing, done;
--   5. reading: what is no longer visible says so and shows nothing
--      (recall, expiry, guard, leaving, unfriending, hiding, blocking,
--      deleting, suspending);
--   6. older apps; 7. closed to clients; 8. search; 9. room (1000 and 50);
--   10. the pictures' bucket; 11. the export; 12. leaving WeCord.
\set ON_ERROR_STOP on

begin;

do $$ begin perform pg_advisory_xact_lock(20261017); end $$;
set local client_min_messages = warning;

-- Every migration after the local baseline (202610170001), in order, up to
-- the ones under test.
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
\i supabase/migrations/202610250200_ban_expiry.sql
\i supabase/migrations/202610250210_thread_lock.sql
\i supabase/migrations/202610250220_mod_notes.sql
\i supabase/migrations/202610250230_ban_appeals.sql
\i supabase/migrations/202610250240_member_filter_batch.sql
\i supabase/migrations/202610250250_raid_schema.sql
\i supabase/migrations/202610250260_raid_detect.sql
\i supabase/migrations/202610250270_raid_rpcs.sql
\i supabase/migrations/202610250280_moderation_push.sql
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
-- Ada keeps things. Bob is her friend and in her group and circle; Cy is her
-- friend too but nobody else's; Dee is a stranger to everyone.
create function pg_temp.uid(n text) returns uuid language sql immutable as $$
  select md5('favorites2:' || n)::uuid
$$;
grant execute on function pg_temp.uid(text) to public;

insert into auth.users (id, email, instance_id, aud, role)
select pg_temp.uid(n), n || '@fv.test', '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from unnest(array['ada', 'bob', 'cy', 'dee', 'eve']) n;
insert into public.profiles (id, username, display_name)
select pg_temp.uid(n), n || '_fv', initcap(n)
from unnest(array['ada', 'bob', 'cy', 'dee', 'eve']) n;
insert into pg_temp.ids
select n, pg_temp.uid(n) from unnest(array['ada', 'bob', 'cy', 'dee', 'eve']) n;

insert into public.friendships (user_low_id, user_high_id)
select least(x.a, x.b), greatest(x.a, x.b)
from (values
  (pg_temp.i('ada'), pg_temp.i('bob')),
  (pg_temp.i('ada'), pg_temp.i('cy')),
  (pg_temp.i('ada'), pg_temp.i('eve'))
) x(a, b);

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'group', public.create_group_conversation('Plan', array[pg_temp.i('bob'), pg_temp.i('eve')]);
insert into pg_temp.ids select 'circle', public.create_circle('Fav club', array[pg_temp.i('bob')]);
select pg_temp.root();

create function pg_temp.say(who text, conv uuid, body text) returns uuid language plpgsql as $$
declare mid uuid;
begin
  insert into public.messages (conversation_id, sender_id, type, body)
  values (conv, pg_temp.i(who), 'text', body)
  returning id into mid;
  return mid;
end $$;
grant execute on all functions in schema pg_temp to public;

insert into pg_temp.ids select 'm1', pg_temp.say('bob', pg_temp.i('group'), 'Bring the tripod on Saturday');
insert into pg_temp.ids select 'm2', pg_temp.say('bob', pg_temp.i('group'), 'Cabin booking confirmed');
insert into pg_temp.ids select 'm3', pg_temp.say('ada', pg_temp.i('group'), 'My own words about hiking');
insert into pg_temp.ids select 'm_old', pg_temp.say('bob', pg_temp.i('group'), 'Saved before the upgrade');

-- ===================================== 0. the old saved messages move in
-- Ada saved two messages the way the first version did (a table); one is
-- done, one lost its message.
insert into public.saved_messages (user_id, message_id, conversation_id, done_at, created_at)
values
  (pg_temp.i('ada'), pg_temp.i('m_old'), pg_temp.i('group'), now() - interval '1 day', now() - interval '3 days'),
  (pg_temp.i('ada'), null, pg_temp.i('group'), null, now() - interval '5 days');
create temp table old_rows as
  select id, user_id, message_id, conversation_id, created_at, done_at from public.saved_messages;
grant all on old_rows to public;

\i supabase/migrations/202610250400_saved_items_schema.sql
\i supabase/migrations/202610250410_saved_items_rpcs.sql
\i supabase/migrations/202610250420_saved_notes_bucket.sql
\i supabase/migrations/202610250430_export_my_saved_items.sql

do $$
begin
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from old_rows) = 2, 'move: two old rows to move');
  perform pg_temp.expect((select relkind from pg_class where oid = 'public.saved_messages'::regclass) = 'v', 'move: saved_messages is a view now');
  perform pg_temp.expect((select count(*) from public.saved_items where kind = 'message') = 2, 'move: both rows are message entries');
  perform pg_temp.expect(not exists (
    select 1 from old_rows o
    left join public.saved_items i on i.id = o.id and i.user_id = o.user_id
      and i.kind = 'message' and i.target_id is not distinct from o.message_id
      and i.conversation_id = o.conversation_id and i.created_at = o.created_at
      and i.done_at is not distinct from o.done_at
    where i.id is null
  ), 'move: ids, message, conversation, time and done are kept');
  perform pg_temp.expect((select count(*) from public.saved_messages) = 2, 'move: the view shows them as before');
  perform pg_temp.expect((select done_at is not null from public.saved_items where id = (select id from old_rows where message_id = pg_temp.i('m_old'))), 'move: mark done is kept');
end $$;

-- ===================================== 1. messages
do $$
declare
  saved_a uuid;
  again uuid;
  vo uuid;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  saved_a := public.save_message(pg_temp.i('m1'));
  again := public.save_message(pg_temp.i('m1'));
  perform pg_temp.expect(saved_a is not null and saved_a = again, 'message: saving twice keeps one entry');
  insert into pg_temp.ids values ('s_m1', saved_a);
  perform pg_temp.expect((select kind = 'message' and conversation_id = pg_temp.i('group') and target_id = pg_temp.i('m1') from public.saved_items where id = saved_a), 'message: the entry points at the message');
  perform pg_temp.expect(public.save_message(pg_temp.i('m_old')) = (select id from old_rows where message_id = pg_temp.i('m_old')), 'message: a message saved before is the same entry');

  -- Who may keep what.
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(pg_temp.state(format('select public.save_message(%L)', pg_temp.i('m1'))) = 'P0002', 'message: a stranger to the group cannot keep it');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused(format('select public.save_message(%L)', pg_temp.i('m1'))), 'message: nobody signed in cannot keep');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.save_message(%L)', gen_random_uuid())) = 'P0002', 'message: unknown message');

  -- Recalled, expired, held, view-once.
  perform pg_temp.root();
  update public.messages set recalled_at = now() where id = pg_temp.i('m2');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.save_message(%L)', pg_temp.i('m2'))) = 'P0002', 'message: a recalled message cannot be kept');

  perform pg_temp.root();
  insert into pg_temp.ids select 'm_exp', pg_temp.say('bob', pg_temp.i('group'), 'Gone soon');
  update public.messages set expires_at = now() + interval '1 hour' where id = pg_temp.i('m_exp');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.save_message(%L)', pg_temp.i('m_exp'))) = 'ok', 'message: a disappearing message can be kept while it is there');
  perform pg_temp.root();
  update public.messages set expires_at = now() - interval '1 minute' where id = pg_temp.i('m_exp');
  insert into pg_temp.ids select 'm_exp2', pg_temp.say('bob', pg_temp.i('group'), 'Already gone');
  update public.messages set expires_at = now() - interval '1 minute' where id = pg_temp.i('m_exp2');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.save_message(%L)', pg_temp.i('m_exp2'))) = 'P0002', 'message: an expired message cannot be kept');

  perform pg_temp.root();
  insert into pg_temp.ids select 'm_held', pg_temp.say('bob', pg_temp.i('group'), 'Held by the guard');
  update public.messages set review_state = 'held' where id = pg_temp.i('m_held');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.save_message(%L)', pg_temp.i('m_held'))) = 'P0002', 'message: a message held by the AI guard cannot be kept by an ordinary member');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.save_message(%L)', pg_temp.i('m_held'))) = 'ok', 'message: the group''s owner, who can see it, can');

  perform pg_temp.root();
  insert into pg_temp.ids select 'm_vo', pg_temp.say('bob', pg_temp.i('group'), 'View once');
  alter table public.messages disable trigger user;
  update public.messages set attachment = '{"kind":"image","view_once":true}'::jsonb where id = pg_temp.i('m_vo');
  alter table public.messages enable trigger user;
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.save_message(%L)', pg_temp.i('m_vo'))) = 'P0002', 'message: a view-once message cannot be kept');
end $$;

-- ===================================== 2. Moments and circle posts
select pg_temp.act(pg_temp.i('bob'));
select public.create_moment(gen_random_uuid(), 'Sunrise at the lake', '[]'::jsonb, null, null, null, 'friends') as id \gset mo1_
select public.create_moment(gen_random_uuid(), 'Private diary', '[]'::jsonb, null, null, null, 'private') as id \gset mo2_
select public.create_circle_post(pg_temp.i('circle'), 'Welcome to the club trip') as id \gset cp1_
select public.create_circle_post(pg_temp.i('circle'), 'Second post, soon deleted') as id \gset cp2_
select pg_temp.root();
insert into pg_temp.ids values ('mo1', :'mo1_id'), ('mo2', :'mo2_id'), ('cp1', :'cp1_id'), ('cp2', :'cp2_id');

do $$
declare
  a uuid;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  a := public.save_item('moment', pg_temp.i('mo1'));
  perform pg_temp.expect(a is not null and a = public.save_item('moment', pg_temp.i('mo1')), 'moment: a friend keeps it, once');
  insert into pg_temp.ids values ('s_mo1', a);
  perform pg_temp.expect(pg_temp.state(format('select public.save_item(%L, %L)', 'moment', pg_temp.i('mo2'))) = 'P0002', 'moment: a private one cannot be kept by a friend');
  perform pg_temp.expect(pg_temp.state(format('select public.save_item(%L, %L)', 'moment', gen_random_uuid())) = 'P0002', 'moment: unknown');
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(pg_temp.state(format('select public.save_item(%L, %L)', 'moment', pg_temp.i('mo1'))) = 'P0002', 'moment: not a friend of the author, not allowed');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.save_item(%L, %L)', 'moment', pg_temp.i('mo2'))) = 'ok', 'moment: the author keeps their own private one');
  perform pg_temp.act(pg_temp.i('ada'));
  a := public.save_item('circle_post', pg_temp.i('cp1'));
  perform pg_temp.expect(a is not null and a = public.save_item('circle_post', pg_temp.i('cp1')), 'post: a member keeps it, once');
  insert into pg_temp.ids values ('s_cp1', a);
  insert into pg_temp.ids values ('s_cp2', public.save_item('circle_post', pg_temp.i('cp2')));
  perform pg_temp.expect((select circle_id = pg_temp.i('circle') from public.saved_items where id = a), 'post: the entry remembers the circle');
  perform pg_temp.act(pg_temp.i('dee'));
  perform pg_temp.expect(pg_temp.state(format('select public.save_item(%L, %L)', 'circle_post', pg_temp.i('cp1'))) = 'P0002', 'post: a stranger to the circle cannot keep it');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.save_item(%L, %L)', 'link', pg_temp.i('cp1'))) = '22023', 'save_item: other kinds go another way');
  perform pg_temp.expect(public.save_item('message', pg_temp.i('m3')) is not null, 'save_item: a message goes through save_message');
  perform pg_temp.root();
  insert into pg_temp.ids select 's_m3', id from public.saved_items where target_id = pg_temp.i('m3') and user_id = pg_temp.i('ada');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused(format('select public.save_item(%L, %L)', 'moment', pg_temp.i('mo1'))), 'save_item: nobody signed in cannot');
end $$;

-- ===================================== 3. links, notes
do $$
declare
  l uuid;
  n uuid;
  e uuid := gen_random_uuid();
  folder uuid;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  l := public.save_link('https://example.com/trails/north-lot', 'Trail map', null, array['#Hiking', 'maps'], 'for June');
  insert into pg_temp.ids values ('s_link', l);
  perform pg_temp.expect(l = public.save_link('https://example.com/trails/north-lot', 'Another title'), 'link: the same address is kept once');
  perform pg_temp.expect((select kind = 'link' and title = 'Trail map' and tags = array['Hiking', 'maps'] and note = 'for June' from public.saved_items where id = l), 'link: title, tidy tags and remark are stored');
  perform pg_temp.expect(pg_temp.state($q$select public.save_link('javascript:alert(1)')$q$) = '22023', 'link: only http and https');
  perform pg_temp.expect(pg_temp.state($q$select public.save_link('https://exa mple.com')$q$) = '22023', 'link: no spaces');
  perform pg_temp.expect(pg_temp.state($q$select public.save_link('')$q$) = '22023', 'link: not empty');
  perform pg_temp.expect(pg_temp.state(format('select public.save_link(%L)', 'https://example.com/' || repeat('a', 2000))) = '22023', 'link: not over 2000 characters');
  perform pg_temp.expect(pg_temp.state(format('select public.save_link(%L, null, %L)', 'https://example.org', gen_random_uuid())) = 'P0002', 'link: not into a folder that is not there');

  -- Notes.
  n := public.create_saved_note(null, 'Packing list', 'tent, stove, long lens', '[]'::jsonb, null, array['trip']);
  insert into pg_temp.ids values ('s_note', n);
  perform pg_temp.expect((select kind = 'note' from public.saved_items where id = n), 'note: a title makes a note');
  n := public.create_saved_note(null, null, 'Call the cabin about parking', '[]'::jsonb);
  insert into pg_temp.ids values ('s_text', n);
  perform pg_temp.expect((select kind = 'text' and title is null from public.saved_items where id = n), 'note: words alone make plain text');
  perform pg_temp.expect(pg_temp.state($q$select public.create_saved_note(null, '  ', '  ', '[]'::jsonb)$q$) = '22023', 'note: not empty');
  perform pg_temp.expect(pg_temp.state(format('select public.create_saved_note(%L, null, null, %L)', e, jsonb_build_array(jsonb_build_object('path', pg_temp.i('bob')::text || '/' || e::text || '-0.jpg')))) = '22023', 'note: a picture in somebody else''s folder is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.create_saved_note(%L, null, null, %L)', e, jsonb_build_array(jsonb_build_object('path', pg_temp.i('ada')::text || '/' || gen_random_uuid()::text || '-0.jpg')))) = '22023', 'note: a picture named for another entry is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.create_saved_note(%L, null, null, %L)', e, jsonb_build_array(jsonb_build_object('path', pg_temp.i('ada')::text || '/' || e::text || '-0.png')))) = '22023', 'note: only jpeg names');
  perform pg_temp.expect(pg_temp.state(format('select public.create_saved_note(null, null, null, %L)', jsonb_build_array(jsonb_build_object('path', pg_temp.i('ada')::text || '/' || e::text || '-0.jpg')))) = '22023', 'note: pictures need an id chosen by the app');
  perform pg_temp.expect(pg_temp.state(format(
    'select public.create_saved_note(%L, null, null, %L)', e,
    (select jsonb_agg(jsonb_build_object('path', pg_temp.i('ada')::text || '/' || e::text || '-' || (g % 4) || '.jpg')) from generate_series(1, 5) g)
  )) = '22023', 'note: at most four pictures');
  n := public.create_saved_note(e, null, null, jsonb_build_array(
    jsonb_build_object('path', pg_temp.i('ada')::text || '/' || e::text || '-0.jpg', 'w', 1200, 'h', 800),
    jsonb_build_object('path', pg_temp.i('ada')::text || '/' || e::text || '-1.jpg')
  ), null, '{}');
  insert into pg_temp.ids values ('s_pics', n);
  perform pg_temp.expect(n = e, 'note: the app chooses the id');
  perform pg_temp.expect((select kind = 'note' and jsonb_array_length(images) = 2 and (images->0->>'w')::int = 1200 from public.saved_items where id = n), 'note: pictures make a note');
  perform pg_temp.expect(pg_temp.state(format('select public.create_saved_note(%L, %L)', e, 'again')) = '23505', 'note: the same id twice is refused');
end $$;

-- ===================================== 4. folders and organizing
do $$
declare
  f uuid;
  removed text[];
  tags_before text[];
  big text[];
begin
  perform pg_temp.act(pg_temp.i('ada'));
  f := public.create_saved_folder('  Trips  ');
  insert into pg_temp.ids values ('f_trips', f);
  perform pg_temp.expect(f = public.create_saved_folder('trips'), 'folder: the same name again returns the folder (any case)');
  perform pg_temp.expect((select name from public.saved_folders where id = f) = 'Trips', 'folder: the name is trimmed');
  insert into pg_temp.ids select 'f_work', public.create_saved_folder('Work');
  perform pg_temp.expect(pg_temp.state($q$select public.create_saved_folder('   ')$q$) = '22023', 'folder: not blank');
  perform pg_temp.expect(pg_temp.state(format('select public.create_saved_folder(%L)', repeat('x', 41))) = '22023', 'folder: not over 40 characters');
  perform pg_temp.expect(pg_temp.state(format('select public.rename_saved_folder(%L, %L)', pg_temp.i('f_work'), 'TRIPS')) = '23505', 'folder: renaming onto another folder is refused');
  perform public.rename_saved_folder(pg_temp.i('f_work'), 'Office');
  perform pg_temp.expect((select name from public.saved_folders where id = pg_temp.i('f_work')) = 'Office', 'folder: renamed');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.rename_saved_folder(%L, %L)', pg_temp.i('f_work'), 'Mine')) = 'P0002', 'folder: not somebody else''s');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.saved_folders') = 0, 'folder: Bob sees none of Ada''s');
  perform pg_temp.act(pg_temp.i('ada'));

  -- Filing.
  perform public.update_saved_item(pg_temp.i('s_m1'), jsonb_build_object('folder_id', pg_temp.i('f_trips')));
  perform public.update_saved_item(pg_temp.i('s_link'), jsonb_build_object('folder_id', pg_temp.i('f_trips'), 'note', 'check the dates'));
  perform pg_temp.expect((select folder_id = pg_temp.i('f_trips') from public.saved_items where id = pg_temp.i('s_m1')), 'file: an entry goes into a folder');
  perform pg_temp.expect((select note = 'check the dates' from public.saved_items where id = pg_temp.i('s_link')), 'file: a remark');
  perform public.update_saved_item(pg_temp.i('s_m1'), '{"folder_id": null}'::jsonb);
  perform pg_temp.expect((select folder_id is null from public.saved_items where id = pg_temp.i('s_m1')), 'file: out of the folder again');
  perform public.update_saved_item(pg_temp.i('s_m1'), jsonb_build_object('folder_id', pg_temp.i('f_trips')));
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.root();
  insert into pg_temp.ids select 'f_bob', public.create_saved_folder('Bob stuff');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.update_saved_item(%L, %L)', pg_temp.i('s_m1'), jsonb_build_object('folder_id', pg_temp.i('f_bob'))::text)) = 'P0002', 'file: not into somebody else''s folder');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.update_saved_item(%L, %L)', pg_temp.i('s_m1'), '{"note": "mine now"}')) = 'P0002', 'file: not somebody else''s entry');
  perform pg_temp.act(pg_temp.i('ada'));

  -- Tags.
  perform public.update_saved_item(pg_temp.i('s_m1'), '{"tags": ["#Work", "work", "  Big   idea ", "", "#", "a-very-long-tag-name-that-goes-on-and-on"]}'::jsonb);
  perform pg_temp.expect((select tags = array['Work', 'Big idea', left('a-very-long-tag-name-that', 24)] from public.saved_items where id = pg_temp.i('s_m1')),
    'tags: # dropped, spaces folded, repeats (any case) and blanks dropped, 24 characters: ' || (select tags::text from public.saved_items where id = pg_temp.i('s_m1')));
  big := array(select 'tag' || g from generate_series(1, 14) g);
  perform public.update_saved_item(pg_temp.i('s_m1'), jsonb_build_object('tags', to_jsonb(big)));
  perform pg_temp.expect((select cardinality(tags) = 10 from public.saved_items where id = pg_temp.i('s_m1')), 'tags: at most ten');
  perform public.update_saved_item(pg_temp.i('s_m1'), '{"tags": ["Work", "Trip"]}'::jsonb);
  perform pg_temp.expect(pg_temp.state(format('select public.update_saved_item(%L, %L)', pg_temp.i('s_m1'), '{"tags": "work"}')) = '22023', 'tags: a list');
  perform public.update_saved_item(pg_temp.i('s_note'), '{"tags": ["Work"]}'::jsonb);
  perform pg_temp.expect(public.rename_saved_tag('#work', 'Office') = 2, 'tags: renamed on both entries');
  perform pg_temp.expect((select tags = array['Office', 'Trip'] from public.saved_items where id = pg_temp.i('s_m1')), 'tags: the order is kept');
  perform pg_temp.expect(public.rename_saved_tag('office', '') = 2, 'tags: a blank name removes it');
  perform pg_temp.expect((select tags = array['Trip'] from public.saved_items where id = pg_temp.i('s_m1')), 'tags: removed');
  perform pg_temp.expect(public.rename_saved_tag('nothing', 'x') = 0, 'tags: an unknown tag changes nothing');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(public.rename_saved_tag('trip', 'x') = 0, 'tags: only the caller''s entries change');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.update_saved_item(pg_temp.i('s_m1'), '{"tags": ["Trip"]}'::jsonb);

  -- What may be edited.
  perform pg_temp.expect(pg_temp.state(format('select public.update_saved_item(%L, %L)', pg_temp.i('s_m1'), '{"title": "x"}')) = '22023', 'edit: a message has no title');
  perform pg_temp.expect(pg_temp.state(format('select public.update_saved_item(%L, %L)', pg_temp.i('s_mo1'), '{"body": "x"}')) = '22023', 'edit: a Moment''s words are not editable');
  perform pg_temp.expect(pg_temp.state(format('select public.update_saved_item(%L, %L)', pg_temp.i('s_link'), '{"images": []}')) = '22023', 'edit: a link has no pictures');
  perform public.update_saved_item(pg_temp.i('s_note'), '{"title": "Packing", "body": "tent, stove"}'::jsonb);
  perform pg_temp.expect((select title = 'Packing' and body = 'tent, stove' from public.saved_items where id = pg_temp.i('s_note')), 'edit: a note''s title and words');
  perform public.update_saved_item(pg_temp.i('s_link'), '{"title": "Trail map (north)"}'::jsonb);
  perform pg_temp.expect((select title = 'Trail map (north)' from public.saved_items where id = pg_temp.i('s_link')), 'edit: a link''s title');
  perform pg_temp.expect(pg_temp.state(format('select public.update_saved_item(%L, %L)', pg_temp.i('s_text'), '{"body": "  "}')) = '23514', 'edit: plain text cannot be emptied');
  perform pg_temp.expect(pg_temp.state(format('select public.update_saved_item(%L, %L)', pg_temp.i('s_text'), '{}')) = 'ok', 'edit: an empty patch changes nothing');
  perform pg_temp.expect(pg_temp.state(format('select public.update_saved_item(%L, null)', pg_temp.i('s_text'))) = '22023', 'edit: a patch is needed');
  -- Pictures: dropping one returns its file for the app to remove.
  removed := public.update_saved_item(pg_temp.i('s_pics'), jsonb_build_object('images', jsonb_build_array(
    jsonb_build_object('path', pg_temp.i('ada')::text || '/' || pg_temp.i('s_pics')::text || '-1.jpg')
  )));
  perform pg_temp.expect(removed = array[pg_temp.i('ada')::text || '/' || pg_temp.i('s_pics')::text || '-0.jpg'], 'pictures: the dropped file is returned');
  perform pg_temp.expect(pg_temp.state(format('select public.update_saved_item(%L, %L)', pg_temp.i('s_pics'), '{"images": []}')) = '23514', 'pictures: a note with nothing left is refused');

  -- Done, for any kind.
  perform public.set_saved_message_done(pg_temp.i('s_link'), true);
  perform pg_temp.expect((select done_at is not null from public.saved_items where id = pg_temp.i('s_link')), 'done: a link can be marked done');
  perform public.set_saved_message_done(pg_temp.i('s_link'), false);
  perform pg_temp.expect((select done_at is null from public.saved_items where id = pg_temp.i('s_link')), 'done: and active again');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.set_saved_message_done(pg_temp.i('s_link'), true);
  perform pg_temp.root();
  perform pg_temp.expect((select done_at is null from public.saved_items where id = pg_temp.i('s_link')), 'done: only the owner');
  perform pg_temp.act(pg_temp.i('ada'));

  -- Deleting a folder keeps its entries.
  perform pg_temp.act(pg_temp.i('bob'));
  delete from public.saved_folders where id = pg_temp.i('f_trips');
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.saved_folders where id = pg_temp.i('f_trips')), 'folder: somebody else cannot delete it');
  perform pg_temp.act(pg_temp.i('ada'));
  insert into pg_temp.ids select 'f_tmp', public.create_saved_folder('Temporary');
  perform public.update_saved_item(pg_temp.i('s_text'), jsonb_build_object('folder_id', pg_temp.i('f_tmp')));
  delete from public.saved_folders where id = pg_temp.i('f_tmp');
  perform pg_temp.expect((select folder_id is null from public.saved_items where id = pg_temp.i('s_text')), 'folder: deleting it keeps the entries, without a folder');
end $$;

-- ===================================== 5. reading: what they point to
create view pg_temp.mine with (security_invoker = true) as
  select * from public.list_saved_items(1000);
grant select on pg_temp.mine to public;

do $$
declare
  r record;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_m1');
  perform pg_temp.expect(r.available and r.content_body = 'Bring the tripod on Saturday' and r.sender_display_name = 'Bob' and r.content_type = 'text', 'list: a message with its sender');
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_mo1');
  perform pg_temp.expect(r.available and r.kind = 'moment' and r.content_body = 'Sunrise at the lake' and r.sender_display_name = 'Bob' and r.extra->>'moment_kind' = 'text', 'list: a Moment');
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_cp1');
  perform pg_temp.expect(r.available and r.content_body = 'Welcome to the club trip' and r.extra->>'circle_name' = 'Fav club' and r.circle_id = pg_temp.i('circle'), 'list: a post, with its circle');
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_link');
  perform pg_temp.expect(r.available and r.url = 'https://example.com/trails/north-lot' and r.title = 'Trail map (north)', 'list: a link');
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_pics');
  perform pg_temp.expect(r.available and jsonb_array_length(r.images) = 1, 'list: a note with its picture');

  -- Recalled.
  perform pg_temp.root();
  update public.messages set recalled_at = now() where id = pg_temp.i('m1');
  perform pg_temp.act(pg_temp.i('ada'));
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_m1');
  perform pg_temp.expect(not r.available and r.content_body is null and r.sender_id is null and r.sender_display_name is null and r.content_type is null, 'list: a recalled message is unavailable and shows nothing');
  perform pg_temp.expect(r.tags = array['Trip'] and r.folder_id = pg_temp.i('f_trips'), 'list: but the folder and tags stay');
  perform pg_temp.root();
  update public.messages set recalled_at = null where id = pg_temp.i('m1');

  -- Expired, held, view-once after the fact.
  insert into pg_temp.ids select 'm_late', pg_temp.say('bob', pg_temp.i('group'), 'Soon expired');
  perform pg_temp.act(pg_temp.i('ada'));
  insert into pg_temp.ids select 's_late', public.save_message(pg_temp.i('m_late'));
  perform pg_temp.root();
  update public.messages set expires_at = now() - interval '1 minute' where id = pg_temp.i('m_late');
  perform pg_temp.act(pg_temp.i('ada'));
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_late');
  perform pg_temp.expect(not r.available and r.content_body is null, 'list: an expired message no longer shows');
  perform pg_temp.root();
  insert into pg_temp.ids select 'm_h', pg_temp.say('bob', pg_temp.i('group'), 'Soon held');
  perform pg_temp.act(pg_temp.i('eve'));
  insert into pg_temp.ids select 's_h', public.save_message(pg_temp.i('m_h'));
  perform pg_temp.root();
  update public.messages set review_state = 'held' where id = pg_temp.i('m_h');
  insert into public.saved_items (user_id, kind, target_id, conversation_id)
  values (pg_temp.i('ada'), 'message', pg_temp.i('m_vo'), pg_temp.i('group'));
  perform pg_temp.act(pg_temp.i('eve'));
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_h');
  perform pg_temp.expect(not r.available and r.content_body is null, 'list: a message held by the AI guard no longer shows');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect((select not l.available and l.content_body is null from public.list_saved_items(1000) l where l.target_id = pg_temp.i('m_vo')), 'list: a view-once message saved before shows nothing');

  -- Removed from the conversation.
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.root();
  delete from public.conversation_members where conversation_id = pg_temp.i('group') and user_id = pg_temp.i('ada');
  perform pg_temp.act(pg_temp.i('ada'));
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_m1');
  perform pg_temp.expect(not r.available and r.content_body is null, 'list: leaving the conversation hides what was saved from it');
  perform pg_temp.root();
  insert into public.conversation_members (conversation_id, user_id, role) values (pg_temp.i('group'), pg_temp.i('ada'), 'owner');
  perform pg_temp.act(pg_temp.i('ada'));
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_m1');
  perform pg_temp.expect(r.available, 'list: and it is back when she is');

  -- Moments: unfriend, then block, then deleted.
  perform pg_temp.root();
  delete from public.friendships where user_low_id = least(pg_temp.i('ada'), pg_temp.i('bob')) and user_high_id = greatest(pg_temp.i('ada'), pg_temp.i('bob'));
  perform pg_temp.act(pg_temp.i('ada'));
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_mo1');
  perform pg_temp.expect(not r.available and r.content_body is null, 'list: unfriended, the Moment is no longer visible');
  perform pg_temp.root();
  insert into public.friendships (user_low_id, user_high_id) values (least(pg_temp.i('ada'), pg_temp.i('bob')), greatest(pg_temp.i('ada'), pg_temp.i('bob')));
  perform pg_temp.act(pg_temp.i('ada'));
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_mo1');
  perform pg_temp.expect(r.available, 'list: friends again, it is back');
  perform pg_temp.root();
  update public.moments_posts set visibility = 'private' where id = pg_temp.i('mo1');
  perform pg_temp.act(pg_temp.i('ada'));
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_mo1');
  perform pg_temp.expect(not r.available, 'list: made private, the Moment is no longer visible');
  perform pg_temp.root();
  update public.moments_posts set visibility = 'friends' where id = pg_temp.i('mo1');
  insert into public.moments_friend_prefs (owner_id, friend_id, hide_mine) values (pg_temp.i('bob'), pg_temp.i('ada'), true);
  perform pg_temp.act(pg_temp.i('ada'));
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_mo1');
  perform pg_temp.expect(not r.available, 'list: hidden from her by the author, the Moment is no longer visible');
  perform pg_temp.root();
  delete from public.moments_friend_prefs where owner_id = pg_temp.i('bob');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.block_user(pg_temp.i('ada'));
  perform pg_temp.act(pg_temp.i('ada'));
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_mo1');
  perform pg_temp.expect(not r.available, 'list: blocked, the Moment is no longer visible');
  perform pg_temp.root();
  delete from public.blocks where blocker_id = pg_temp.i('bob');
  insert into public.friendships (user_low_id, user_high_id) values (least(pg_temp.i('ada'), pg_temp.i('bob')), greatest(pg_temp.i('ada'), pg_temp.i('bob'))) on conflict do nothing;
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.delete_moment(pg_temp.i('mo1'));
  perform pg_temp.act(pg_temp.i('ada'));
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_mo1');
  perform pg_temp.expect(not r.available and r.content_body is null, 'list: a deleted Moment is no longer visible, but the entry stays');

  -- Posts: deleted, left, suspended.
  perform pg_temp.root();
  update public.circle_posts set deleted_at = now() where id = pg_temp.i('cp2');
  perform pg_temp.act(pg_temp.i('ada'));
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_cp2');
  perform pg_temp.expect(not r.available and r.content_body is null, 'list: a deleted post is no longer visible');
  perform pg_temp.root();
  update public.circles set disabled_at = now(), disabled_mode = 'suspend' where id = pg_temp.i('circle');
  perform pg_temp.act(pg_temp.i('ada'));
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_cp1');
  perform pg_temp.expect(not r.available and r.content_body is null, 'list: a suspended circle''s post is not visible');
  perform pg_temp.expect(pg_temp.state(format('select public.save_item(%L, %L)', 'circle_post', pg_temp.i('cp1'))) <> 'ok', 'post: and cannot be kept either');
  perform pg_temp.root();
  update public.circles set disabled_at = null, disabled_mode = null where id = pg_temp.i('circle');
  perform pg_temp.act(pg_temp.i('ada'));
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_cp1');
  perform pg_temp.expect(r.available, 'list: reinstated, it is back');
  perform pg_temp.root();
  delete from public.circle_members where circle_id = pg_temp.i('circle') and user_id = pg_temp.i('ada');
  perform pg_temp.act(pg_temp.i('ada'));
  select * into r from pg_temp.mine where saved_id = pg_temp.i('s_cp1');
  perform pg_temp.expect(not r.available, 'list: leaving the circle hides its post');
  perform pg_temp.root();
  insert into public.circle_members (circle_id, user_id, role) values (pg_temp.i('circle'), pg_temp.i('ada'), 'owner');

  -- Only your own.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.list_saved_items(1000)') = 1, 'list: Bob sees only his own entry');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.saved_items') = 1, 'list: nor more in the table');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.list_saved_items(3)') = 3, 'list: the limit is honoured');
  perform pg_temp.expect((select saved_at from public.list_saved_items(1000) limit 1) >= (select max(saved_at) from public.list_saved_items(1000)) - interval '1 second', 'list: newest first');
  perform pg_temp.act(null);
  perform pg_temp.must_refuse('select 1 from public.list_saved_items(1000)', 'list: nobody signed in cannot list');
end $$;

-- ===================================== 6. older apps
do $$
begin
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.list_saved_messages(500)') = (select count(*)::int from public.saved_items where kind = 'message'), 'old: list_saved_messages lists the messages only');
  perform pg_temp.expect(not exists (select 1 from public.list_saved_messages(500) where saved_id in (pg_temp.i('s_link'), pg_temp.i('s_mo1'))), 'old: no links or Moments there');
  perform pg_temp.expect((select message_id is not null from public.list_saved_messages(500) where saved_id = pg_temp.i('s_m3')), 'old: the old column names');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.saved_messages') = (select count(*)::int from public.saved_items where kind = 'message'), 'old: the view lists the messages');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.saved_messages') = 0, 'old: and only your own');
  perform pg_temp.act(pg_temp.i('ada'));
  delete from public.saved_messages where id = pg_temp.i('s_m3');
  perform pg_temp.expect(not exists (select 1 from public.saved_items where id = pg_temp.i('s_m3')), 'old: an older app can remove a saved message');
  perform pg_temp.act(pg_temp.i('bob'));
  delete from public.saved_messages where id in (select id from old_rows);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.saved_items where id in (select id from old_rows)) = 2, 'old: and not somebody else''s');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.refused('insert into public.saved_messages (user_id, message_id, conversation_id) values (null, null, null)'), 'old: no writes through the view');
  perform pg_temp.expect(public.save_message(pg_temp.i('m3')) is not null, 'old: save_message still works');
  perform pg_temp.root();
  insert into pg_temp.ids values ('s_m3b', (select id from public.saved_items where target_id = pg_temp.i('m3') and user_id = pg_temp.i('ada')));
end $$;

-- ===================================== 7. closed to clients
do $$
begin
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.must_refuse(format('insert into public.saved_items (user_id, kind, url) values (%L, %L, %L)', pg_temp.i('ada'), 'link', 'https://x.test'), 'closed: no direct insert');
  perform pg_temp.must_refuse(format('update public.saved_items set note = %L where user_id = %L', 'x', pg_temp.i('ada')), 'closed: no direct update');
  perform pg_temp.must_refuse(format('insert into public.saved_folders (user_id, name) values (%L, %L)', pg_temp.i('ada'), 'x'), 'closed: no direct folder insert');
  perform pg_temp.must_refuse(format('update public.saved_folders set name = %L', 'x'), 'closed: no direct folder update');
  perform pg_temp.act(null);
  perform pg_temp.must_refuse('select 1 from public.saved_items', 'closed: anon cannot read the entries');
  perform pg_temp.must_refuse('select 1 from public.saved_folders', 'closed: anon cannot read the folders');
  perform pg_temp.must_refuse('select public.save_link(''https://a.test'')', 'closed: anon cannot save a link');
  perform pg_temp.must_refuse('select public.create_saved_folder(''x'')', 'closed: anon cannot make a folder');
  perform pg_temp.must_refuse('select * from public.search_saved_items(''x'')', 'closed: anon cannot search');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.must_refuse(format('select public.assert_saved_room(%L)', pg_temp.i('ada')), 'closed: internals are not callable');
  perform pg_temp.must_refuse(format('select public.export_my_saved_items(%L)', pg_temp.i('ada')), 'closed: the export is for the service role');
  perform pg_temp.root();
  perform pg_temp.expect(not has_function_privilege('anon', 'public.save_item(text, uuid)', 'execute'), 'closed: anon has no save_item');
  perform pg_temp.expect(not has_function_privilege('authenticated', 'public.export_my_saved_items(uuid)', 'execute'), 'closed: nor the export');
  perform pg_temp.expect((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and p.proname in ('save_message', 'save_item', 'save_link', 'create_saved_note', 'update_saved_item', 'set_saved_message_done',
                        'create_saved_folder', 'rename_saved_folder', 'rename_saved_tag', 'export_my_saved_items', 'erase_favorites_of_deleted_account')
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c = 'search_path=public')) = 0, 'closed: every definer pins its search path');
  perform pg_temp.expect((select not prosecdef from pg_proc where proname = 'list_saved_items' and pronamespace = 'public'::regnamespace), 'closed: listing runs as the caller');
  perform pg_temp.expect((select not prosecdef from pg_proc where proname = 'search_saved_items' and pronamespace = 'public'::regnamespace), 'closed: and so does search');
end $$;

-- ===================================== 8. search
do $$
declare
  ids uuid[];
begin
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.update_saved_item(pg_temp.i('s_text'), '{"body": "Call the cabin about parking 山上的小屋", "note": "urgent-ish"}'::jsonb);
  perform public.update_saved_item(pg_temp.i('s_link'), '{"tags": ["maps", "Hiking"]}'::jsonb);

  perform pg_temp.expect((select array_agg(saved_id) from public.search_saved_items('tripod')) = array[pg_temp.i('s_m1')], 'search: through the text of a message, read live');
  perform pg_temp.expect((select array_agg(saved_id) from public.search_saved_items('TRIPOD sat')) = array[pg_temp.i('s_m1')], 'search: any case, several words together');
  perform pg_temp.expect((select count(*) from public.search_saved_items('tripod cabin')) = 0, 'search: every word must match one entry');
  perform pg_temp.expect((select array_agg(saved_id) from public.search_saved_items('packing')) = array[pg_temp.i('s_note')], 'search: a note''s title');
  perform pg_temp.expect((select array_agg(saved_id) from public.search_saved_items('stove')) = array[pg_temp.i('s_note')], 'search: a note''s words');
  perform pg_temp.expect(pg_temp.cnt($q$select 1 from public.search_saved_items('cabin') where saved_id = pg_temp.i('s_text')$q$) = 1, 'search: a word of plain text');
  perform pg_temp.expect(pg_temp.cnt($q$select 1 from public.search_saved_items('小屋')$q$) = 1, 'search: Chinese, any run of characters');
  perform pg_temp.expect(pg_temp.cnt($q$select 1 from public.search_saved_items('屋小')$q$) = 0, 'search: but in order');
  perform pg_temp.expect((select array_agg(saved_id) from public.search_saved_items('urgent')) = array[pg_temp.i('s_text')], 'search: the remark');
  perform pg_temp.expect(pg_temp.cnt($q$select 1 from public.search_saved_items('hiking') where saved_id = pg_temp.i('s_link')$q$) = 1, 'search: a tag');
  perform pg_temp.expect(pg_temp.cnt($q$select 1 from public.search_saved_items('example.com')$q$) = 1, 'search: a link''s address');
  perform pg_temp.expect(pg_temp.cnt($q$select 1 from public.search_saved_items('pod')$q$) >= 1, 'search: inside a word');
  perform pg_temp.expect(pg_temp.cnt($q$select 1 from public.search_saved_items('sunrise')$q$) = 0, 'search: the text of a deleted Moment is not searched');
  perform pg_temp.expect(pg_temp.cnt($q$select 1 from public.search_saved_items('club trip')$q$) = 1, 'search: a post in the circle');
  perform pg_temp.expect(pg_temp.cnt($q$select 1 from public.search_saved_items('fav club')$q$) = 1, 'search: the circle''s name');
  perform pg_temp.expect(pg_temp.cnt($q$select 1 from public.search_saved_items('   ')$q$) = 0, 'search: blank finds nothing');
  perform pg_temp.expect(pg_temp.cnt($q$select 1 from public.search_saved_items('zebra')$q$) = 0, 'search: no match');
  perform pg_temp.expect(pg_temp.cnt($q$select 1 from public.search_saved_items('tripod bring the on saturday tripod tripod tripod zzz')$q$) = 1, 'search: only eight words are used');
  -- Recalled messages are not searched by what they said.
  perform pg_temp.root();
  update public.messages set recalled_at = now() where id = pg_temp.i('m1');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.cnt($q$select 1 from public.search_saved_items('tripod')$q$) = 0, 'search: a recalled message''s words are not found');
  perform pg_temp.root();
  update public.messages set recalled_at = null where id = pg_temp.i('m1');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt($q$select 1 from public.search_saved_items('packing')$q$) = 0, 'search: Bob finds none of Ada''s entries');
  perform pg_temp.root();
  perform pg_temp.expect((select search_vector @@ phraseto_tsquery('simple', 'packing') from public.saved_items where id = pg_temp.i('s_note')), 'search: the vector holds the title');
  perform pg_temp.expect((select search_vector @@ phraseto_tsquery('simple', public.search_split_cjk('小屋')) from public.saved_items where id = pg_temp.i('s_text')), 'search: and the CJK characters one by one');
  perform pg_temp.expect(not exists (select 1 from public.saved_items where kind in ('message', 'moment', 'circle_post') and (title is not null or body is not null)), 'search: nothing of other people''s words is stored');
end $$;

-- ===================================== 9. room
do $$
declare
  have integer;
begin
  perform pg_temp.root();
  select count(*) into have from public.saved_items where user_id = pg_temp.i('ada');
  insert into public.saved_items (user_id, kind, body)
  select pg_temp.i('ada'), 'text', 'filler ' || g from generate_series(1, 1000 - have) g;
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.root();
  insert into pg_temp.ids select 'm_room', pg_temp.say('bob', pg_temp.i('group'), 'One more');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.save_message(%L)', pg_temp.i('m_room'))) = '53400', 'room: 1000 entries is the most (messages)');
  perform pg_temp.expect(pg_temp.state(format('select public.save_item(%L, %L)', 'circle_post', pg_temp.i('cp1'))) = 'ok', 'room: but one already kept is returned');
  perform pg_temp.expect(pg_temp.state($q$select public.save_link('https://new.example.com')$q$) = '53400', 'room: links too');
  perform pg_temp.expect(pg_temp.state($q$select public.create_saved_note(null, 'one more')$q$) = '53400', 'room: notes too');
  perform pg_temp.expect(pg_temp.state($q$select public.save_link('https://example.com/trails/north-lot')$q$) = 'ok', 'room: a link already kept is returned');
  perform pg_temp.expect((select count(*) from public.list_saved_items(1000)) = 1000, 'room: listing returns up to 1000');
  perform pg_temp.root();
  delete from public.saved_items where user_id = pg_temp.i('ada') and body like 'filler %';
  perform pg_temp.act(pg_temp.i('ada'));
  -- Folders: 50 at most.
  insert into pg_temp.ids select 'f_' || g, public.create_saved_folder('Folder ' || g) from generate_series(1, 48) g;
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.saved_folders') = 50, 'room: fifty folders');
  perform pg_temp.expect(pg_temp.state($q$select public.create_saved_folder('One too many')$q$) = '53400', 'room: not a 51st');
  perform pg_temp.expect(pg_temp.state($q$select public.create_saved_folder('folder 1')$q$) = 'ok', 'room: but a name that exists is returned');
end $$;

-- ===================================== 10. the pictures' bucket
do $$
declare
  ada text := pg_temp.i('ada')::text;
  bob text := pg_temp.i('bob')::text;
  e text := gen_random_uuid()::text;
begin
  perform pg_temp.root();
  perform pg_temp.expect((select not public and file_size_limit = 5242880 and allowed_mime_types = array['image/jpeg'] from storage.buckets where id = 'saved-notes'), 'bucket: private, 5 MB, jpeg');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format($q$insert into storage.objects (bucket_id, name, owner) values ('saved-notes', %L, %L)$q$, ada || '/' || e || '-0.jpg', ada)) = 'ok', 'bucket: Ada writes in her folder');
  perform pg_temp.expect(pg_temp.state(format($q$insert into storage.objects (bucket_id, name, owner) values ('saved-notes', %L, %L)$q$, bob || '/' || e || '-0.jpg', ada)) <> 'ok', 'bucket: not in Bob''s');
  perform pg_temp.expect(pg_temp.state(format($q$insert into storage.objects (bucket_id, name, owner) values ('saved-notes', %L, %L)$q$, ada || '/' || e || '-9.jpg', ada)) <> 'ok', 'bucket: only picture numbers 0 to 3');
  perform pg_temp.expect(pg_temp.state(format($q$insert into storage.objects (bucket_id, name, owner) values ('saved-notes', %L, %L)$q$, ada || '/notes.jpg', ada)) <> 'ok', 'bucket: named for an entry');
  perform pg_temp.expect(pg_temp.state(format($q$insert into storage.objects (bucket_id, name, owner) values ('saved-notes', %L, %L)$q$, ada || '/' || e || '-1.png', ada)) <> 'ok', 'bucket: jpg names only');
  perform pg_temp.expect(pg_temp.cnt($q$select 1 from storage.objects where bucket_id = 'saved-notes'$q$) = 1, 'bucket: Ada reads her file');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt($q$select 1 from storage.objects where bucket_id = 'saved-notes'$q$) = 0, 'bucket: Bob reads nothing of hers');
  perform pg_temp.state($q$delete from storage.objects where bucket_id = 'saved-notes'$q$);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from storage.objects where bucket_id = 'saved-notes') = 1, 'bucket: Bob removes nothing of hers');
  perform pg_temp.expect(exists (select 1 from pg_policies where tablename = 'objects' and policyname = 'saved_notes_delete_owner' and cmd = 'DELETE'), 'bucket: the owner may remove her files');
end $$;

-- ===================================== 11. taking the data
do $$
declare
  export jsonb;
  item jsonb;
begin
  perform pg_temp.root();
  export := public.export_my_saved_items(pg_temp.i('ada'));
  perform pg_temp.expect(jsonb_array_length(export->'folders') = 50, 'export: the folders');
  perform pg_temp.expect(jsonb_array_length(export->'items') = (select count(*) from public.saved_items where user_id = pg_temp.i('ada')), 'export: every entry');
  select i into item from jsonb_array_elements(export->'items') i where i->>'id' = pg_temp.i('s_link')::text;
  perform pg_temp.expect(item->>'url' = 'https://example.com/trails/north-lot' and item->>'title' = 'Trail map (north)' and item->'tags' = '["maps","Hiking"]'::jsonb, 'export: a link whole, with its tags');
  select i into item from jsonb_array_elements(export->'items') i where i->>'id' = pg_temp.i('s_m1')::text;
  perform pg_temp.expect(item->>'folder' = 'Trips' and not (item ? 'text') and (item->>'from_you')::boolean = false, 'export: a message by someone else carries no words, only where it is filed');
  select i into item from jsonb_array_elements(export->'items') i where i->>'id' = pg_temp.i('s_m3b')::text;
  perform pg_temp.expect(item->>'text' = 'My own words about hiking' and (item->>'from_you')::boolean, 'export: a message she wrote carries its words');
  select i into item from jsonb_array_elements(export->'items') i where i->>'id' = pg_temp.i('s_cp1')::text;
  perform pg_temp.expect(not (item ? 'text'), 'export: a post by someone else carries no words');
  select i into item from jsonb_array_elements(export->'items') i where i->>'id' = pg_temp.i('s_pics')::text;
  perform pg_temp.expect(item->'images'->0->>'bucket' = 'saved-notes' and item->'images'->0->>'path' like pg_temp.i('ada')::text || '/%', 'export: note pictures are named by bucket and path');
  perform pg_temp.expect(public.export_my_saved_items(pg_temp.i('dee')) = '{"folders": [], "items": []}'::jsonb, 'export: nothing kept, nothing listed');
  perform pg_temp.expect(pg_temp.state(format('select public.export_my_saved_items(null)')) = '22023', 'export: a user is needed');
  -- The first export (saved messages) still works through the view.
  perform pg_temp.expect(jsonb_typeof(public.export_my_extras(pg_temp.i('ada'))->'saved_messages') = 'array', 'export: saved_messages.json still comes from export_my_extras');
  perform pg_temp.expect(jsonb_array_length(public.export_my_extras(pg_temp.i('ada'))->'saved_messages') = (select count(*) from public.saved_items where user_id = pg_temp.i('ada') and kind = 'message'), 'export: with the message entries');
end $$;

-- ===================================== 12. leaving WeCord
do $$
begin
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.saved_items where user_id = pg_temp.i('ada')) > 0, 'delete: she has entries before');
  update public.profiles set deleted_at = now() where id = pg_temp.i('ada');
  perform pg_temp.expect((select count(*) from public.saved_items where user_id = pg_temp.i('ada')) = 0, 'delete: her entries are erased when the account goes');
  perform pg_temp.expect((select count(*) from public.saved_folders where user_id = pg_temp.i('ada')) = 0, 'delete: and her folders');
  perform pg_temp.expect((select count(*) from public.saved_items where user_id = pg_temp.i('bob')) = 1, 'delete: nobody else''s were touched');
end $$;
\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'favorites 2.0: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
