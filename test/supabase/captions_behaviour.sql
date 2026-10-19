-- Behaviour checks for call captions (E1: migration 202610240100). Run by
-- test/supabase/captions_test.dart against the local database: it applies the
-- migrations it needs in a transaction, plays people through them, and rolls
-- everything back. Run from the repository root.
--
-- What it walks through: who may turn captions on (livekit-token puts the
-- answer in the signed token): in a circle's voice channel and stage only
-- people who may mute members (not plain members, not strangers, not text
-- channels); in a one-to-one call either person; in a group call the person
-- who started it and the group's owner and admins, not other members, not a
-- stranger, not once the call has ended; nothing for nobody signed in or for
-- a request that names neither.
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

grant execute on all functions in schema pg_temp to public;

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create function pg_temp.i(n text) returns uuid language sql as $$ select id from pg_temp.ids where name = n $$;
grant execute on function pg_temp.i(text) to public;

-- ------------------------------------------------------------------ cast
-- ada owns the circle and the group; bob, cat are members; eve is a group
-- admin; dan is in none of it. zoe and yan are the two of a direct chat.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@cap.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'zoe'),(7,'yan')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_cap', initcap(name)
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'zoe'),(7,'yan')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'zoe'),(7,'yan')) v(n, name);

insert into public.conversations (type, title) values ('group', 'Crew') returning id \gset grp_
insert into public.conversations (type) values ('direct') returning id \gset dm_
insert into pg_temp.ids values ('grp', :'grp_id'), ('dm', :'dm_id');
insert into public.conversation_members (conversation_id, user_id, role) values
  (:'grp_id', pg_temp.i('ada'), 'owner'),
  (:'grp_id', pg_temp.i('eve'), 'admin'),
  (:'grp_id', pg_temp.i('bob'), 'member'),
  (:'grp_id', pg_temp.i('cat'), 'member');
insert into public.conversation_members (conversation_id, user_id, role) values
  (:'dm_id', pg_temp.i('zoe'), 'member'),
  (:'dm_id', pg_temp.i('yan'), 'member');

-- ===================================== 1. voice channels and stages
insert into public.friendships (user_low_id, user_high_id)
select least(pg_temp.i('ada'), pg_temp.i(n)), greatest(pg_temp.i('ada'), pg_temp.i(n))
from (values ('bob'), ('cat')) v(n);
do $$
declare
  ada uuid := pg_temp.i('ada');
  bob uuid := pg_temp.i('bob');
  cat uuid := pg_temp.i('cat');
  dan uuid := pg_temp.i('dan');
  circle uuid;
  vc uuid;
  stage uuid;
  text_channel uuid;
  moderator_role uuid;
begin
  perform pg_temp.act(ada);
  circle := public.create_circle('Captions club', array[bob, cat]);
  vc := public.create_circle_channel(circle, 'lounge', null, 'voice');
  stage := public.create_circle_channel(circle, 'town hall', null, 'stage');
  perform pg_temp.root();
  select cc.id into text_channel from public.circle_channels cc
    where cc.circle_id = circle and cc.kind = 'text' limit 1;

  perform pg_temp.act(ada);
  perform pg_temp.expect(public.can_current_user_host_captions(vc, null), 'the circle owner may start captions in a voice channel');
  perform pg_temp.expect(public.can_current_user_host_captions(stage, null), 'and on a stage');
  perform pg_temp.expect(not public.can_current_user_host_captions(text_channel, null), 'not in a text channel');
  perform pg_temp.root();

  perform pg_temp.act(bob);
  perform pg_temp.expect(not public.can_current_user_host_captions(vc, null), 'a plain member may not');
  perform pg_temp.expect(not public.can_current_user_host_captions(stage, null), 'not on a stage either');
  perform pg_temp.root();

  -- A role that may mute members can.
  insert into public.circle_roles (circle_id, name, permissions, position)
  select circle, 'Moderator', 131072::bigint, coalesce(max(position), 0) + 1
  from public.circle_roles where circle_id = circle
  returning id into moderator_role;
  insert into public.circle_member_roles (circle_id, user_id, role_id)
  values (circle, bob, moderator_role);
  perform pg_temp.act(bob);
  perform pg_temp.expect(public.can_current_user_host_captions(vc, null), 'a member with the mute members permission may');
  perform pg_temp.root();
  perform pg_temp.act(cat);
  perform pg_temp.expect(not public.can_current_user_host_captions(vc, null), 'someone else still may not');
  perform pg_temp.root();

  perform pg_temp.act(dan);
  perform pg_temp.expect(not public.can_current_user_host_captions(vc, null), 'a stranger to the circle may not');
  perform pg_temp.root();

  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused('select public.can_current_user_host_captions(null, null)'), 'nobody signed in cannot even ask');
  perform pg_temp.root();

  perform pg_temp.act(ada);
  perform pg_temp.expect(not public.can_current_user_host_captions(null, null), 'a request that names nothing is a no');
  perform pg_temp.expect(not public.can_current_user_host_captions(gen_random_uuid(), null), 'an unknown channel is a no');
  perform pg_temp.expect(not public.can_current_user_host_captions(null, gen_random_uuid()), 'an unknown call is a no');
  perform pg_temp.root();
end $$;

-- ===================================== 2. one-to-one and group calls
do $$
declare
  ada uuid := pg_temp.i('ada');
  bob uuid := pg_temp.i('bob');
  cat uuid := pg_temp.i('cat');
  dan uuid := pg_temp.i('dan');
  eve uuid := pg_temp.i('eve');
  zoe uuid := pg_temp.i('zoe');
  yan uuid := pg_temp.i('yan');
  dm_call uuid;
  group_call uuid;
begin
  -- One-to-one: either person, nobody else.
  perform pg_temp.act(zoe);
  dm_call := public.start_direct_call(pg_temp.i('dm'));
  perform pg_temp.root();
  perform pg_temp.act(zoe);
  perform pg_temp.expect(public.can_current_user_host_captions(null, dm_call), 'one-to-one: the caller may');
  perform pg_temp.root();
  perform pg_temp.act(yan);
  perform pg_temp.expect(public.can_current_user_host_captions(null, dm_call), 'one-to-one: so may the other person');
  perform pg_temp.root();
  perform pg_temp.act(dan);
  perform pg_temp.expect(not public.can_current_user_host_captions(null, dm_call), 'one-to-one: a stranger may not');
  perform pg_temp.root();

  -- Group: the starter and the owner / admins.
  perform pg_temp.act(bob);
  group_call := public.start_direct_call(pg_temp.i('grp'));
  perform pg_temp.root();
  perform pg_temp.act(bob);
  perform pg_temp.expect(public.can_current_user_host_captions(null, group_call), 'group: the person who started the call may');
  perform pg_temp.root();
  perform pg_temp.act(ada);
  perform pg_temp.expect(public.can_current_user_host_captions(null, group_call), 'group: the owner may');
  perform pg_temp.root();
  perform pg_temp.act(eve);
  perform pg_temp.expect(public.can_current_user_host_captions(null, group_call), 'group: an admin may');
  perform pg_temp.root();
  perform pg_temp.act(cat);
  perform pg_temp.expect(not public.can_current_user_host_captions(null, group_call), 'group: another member may not');
  perform pg_temp.root();
  perform pg_temp.act(dan);
  perform pg_temp.expect(not public.can_current_user_host_captions(null, group_call), 'group: a stranger may not');
  perform pg_temp.root();

  -- Once the call has ended nobody can.
  update public.direct_calls set ended_at = now() where id = group_call;
  perform pg_temp.act(bob);
  perform pg_temp.expect(not public.can_current_user_host_captions(null, group_call), 'an ended call: nobody');
  perform pg_temp.root();
end $$;

-- ===================================== 3. nothing is stored
do $$
begin
  perform pg_temp.expect(
    not exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and (column_name ilike '%caption%' or column_name ilike '%transcript%')
    ),
    'no table keeps captions or transcripts');
end $$;
\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'captions: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
