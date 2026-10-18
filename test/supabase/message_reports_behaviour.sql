-- Attack and behaviour tests for message reports (A1: migrations
-- 202610220110 and 202610220120) and the terms acceptance (G10:
-- 202610220130). Run by test/supabase/message_reports_test.dart against the
-- local database inside a transaction that is rolled back. Run from the
-- repository root.
--
-- The script plays signed-in people who talk to the REST/RPC API with their
-- own token (`set local role authenticated` plus the JWT claims). Every
-- attack must fail; a failed defence is recorded and listed at the end.
--
-- The local database may lack recent migrations, so the script rebuilds the
-- public schema from ALL migrations, in order, inside the transaction (and
-- throws it away at the end).
\set ON_ERROR_STOP on

begin;

-- Behaviour scripts that apply DDL take turns.
select pg_advisory_xact_lock(20261017);
set local client_min_messages = warning;

do $$
declare r record;
begin
  for r in
    select policyname, tablename, schemaname from pg_policies
    where schemaname in ('storage', 'realtime') and tablename in ('objects', 'messages')
  loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;
set local storage.allow_delete_query = 'true';
delete from storage.buckets;
drop schema public cascade;
create schema public;
grant usage on schema public to postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on functions to postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on sequences to postgres, anon, authenticated, service_role;

\i supabase/migrations/202605180001_private_chat.sql
\i supabase/migrations/202605180002_enable_chat_realtime.sql
\i supabase/migrations/202605180003_image_messages.sql
\i supabase/migrations/202605180004_recall_messages.sql
\i supabase/migrations/202605180005_social_chat_v2.sql
\i supabase/migrations/202605180006_social_chat_v2_fixes.sql
\i supabase/migrations/202605180007_notifications_mvp.sql
\i supabase/migrations/202605180008_social_chat_v3.sql
\i supabase/migrations/202605180009_fix_send_text_message_reply_param.sql
\i supabase/migrations/202605180010_daily_chat_polish_v3.sql
\i supabase/migrations/202605180011_daily_chat_polish_v3_security_fix.sql
\i supabase/migrations/202605190001_identity_safety_v4.sql
\i supabase/migrations/202605190002_fix_identity_safety_blocking.sql
\i supabase/migrations/202605190003_community_discovery_v1.sql
\i supabase/migrations/202605190004_group_announcement_polish.sql
\i supabase/migrations/202610130001_message_reactions.sql
\i supabase/migrations/202610130002_pinned_messages.sql
\i supabase/migrations/202610130003_circle_invites.sql
\i supabase/migrations/202610130004_circle_nicknames.sql
\i supabase/migrations/202610130005_circle_notification_settings.sql
\i supabase/migrations/202610130006_circle_unread_counts.sql
\i supabase/migrations/202610130007_channel_categories.sql
\i supabase/migrations/202610130008_fix_circle_role_checks.sql
\i supabase/migrations/202610130009_link_previews.sql
\i supabase/migrations/202610130010_custom_status.sql
\i supabase/migrations/202610130011_message_threads.sql
\i supabase/migrations/202610130012_circle_roles.sql
\i supabase/migrations/202610130013_kick_circle_member.sql
\i supabase/migrations/202610130014_channel_permission_overwrites.sql
\i supabase/migrations/202610130015_channel_slowmode.sql
\i supabase/migrations/202610130016_channel_permission_fixes.sql
\i supabase/migrations/202610130017_leave_circle.sql
\i supabase/migrations/202610130018_circle_audit_log.sql
\i supabase/migrations/202610130019_channel_management.sql
\i supabase/migrations/202610130020_forum_channels.sql
\i supabase/migrations/202610130021_forum_post_mentions.sql
\i supabase/migrations/202610130022_circle_events.sql
\i supabase/migrations/202610130023_polls.sql
\i supabase/migrations/202610130024_channel_webhooks.sql
\i supabase/migrations/202610130025_moderator_message_delete.sql
\i supabase/migrations/202610130026_circle_emojis.sql
\i supabase/migrations/202610130027_erase_recalled_content.sql
\i supabase/migrations/202610130028_voice_channels.sql
\i supabase/migrations/202610140001_inbox.sql
\i supabase/migrations/202610140002_default_voice_channel.sql
\i supabase/migrations/202610140003_backfill_voice_channels.sql
\i supabase/migrations/202610140004_bans_and_timeouts.sql
\i supabase/migrations/202610140005_delete_account.sql
\i supabase/migrations/202610140006_direct_calls.sql
\i supabase/migrations/202610140007_file_messages.sql
\i supabase/migrations/202610140008_push_notifications.sql
\i supabase/migrations/202610160001_presence_statuses.sql
\i supabase/migrations/202610160002_profile_extras.sql
\i supabase/migrations/202610160003_role_and_here_mentions.sql
\i supabase/migrations/202610160004_voice_moderation.sql
\i supabase/migrations/202610160005_voice_text_chat.sql
\i supabase/migrations/202610160014_live_circle_emojis.sql
\i supabase/migrations/202610160015_group_admin_pins.sql
\i supabase/migrations/202610160016_reactions_performance.sql
\i supabase/migrations/202610160017_deleted_channel_storage.sql
\i supabase/migrations/202610160018_stage_channels.sql
\i supabase/migrations/202610160019_soundboard.sql
\i supabase/migrations/202610160020_automod.sql
\i supabase/migrations/202610160021_member_onboarding.sql
\i supabase/migrations/202610160026_soundboard_cleanup.sql
\i supabase/migrations/202610160027_announcement_channels.sql
\i supabase/migrations/202610160028_circle_templates.sql
\i supabase/migrations/202610160029_circle_tags.sql
\i supabase/migrations/202610160030_bot_api.sql
\i supabase/migrations/202610160031_bot_accounts_via_auth_admin.sql
\i supabase/migrations/202610160032_push_delivery_recipients.sql
\i supabase/migrations/202610160033_file_previews.sql
\i supabase/migrations/202610160034_bots_are_not_friends.sql
\i supabase/migrations/202610160035_automod_quiet_sends.sql
\i supabase/migrations/202610160036_voice_needs_rules.sql
\i supabase/migrations/202610160037_announcement_webhooks.sql
\i supabase/migrations/202610160038_server_presence_for_here.sql
\i supabase/migrations/202610160039_soundboard_server_duration.sql
\i supabase/migrations/202610160040_public_circles.sql
\i supabase/migrations/202610160041_circle_discovery.sql
\i supabase/migrations/202610160042_report_public_circles.sql
\i supabase/migrations/202610160043_message_search_indexes.sql
\i supabase/migrations/202610160044_search_messages_rpc.sql
\i supabase/migrations/202610160045_search_filter_suggestions.sql
\i supabase/migrations/202610160046_message_pagination.sql
\i supabase/migrations/202610160047_message_client_id.sql
\i supabase/migrations/202610160050_summary_attachment_kind.sql
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

create function pg_temp.val(query text) returns text language plpgsql as $$
declare r text;
begin
  execute query into r;
  return r;
exception when others then
  return 'ERR: ' || sqlerrm;
end $$;

create function pg_temp.changed(statement text) returns integer language plpgsql as $$
declare n integer;
begin
  execute statement;
  get diagnostics n = row_count;
  return n;
exception when others then
  return 0;
end $$;

-- The SQLSTATE a statement raises, or 'ok'.
create function pg_temp.state(statement text) returns text language plpgsql as $$
begin
  execute statement;
  return 'ok';
exception when others then
  return sqlstate;
end $$;

create function pg_temp.must_refuse(statement text, msg text) returns void language plpgsql as $$
begin
  perform pg_temp.expect(pg_temp.refused(statement), msg);
end $$;

-- Refused with exactly this SQLSTATE.
create function pg_temp.must_state(statement text, wanted text, msg text) returns void language plpgsql as $$
declare got text;
begin
  got := pg_temp.state(statement);
  perform pg_temp.expect(got = wanted, msg || ' (got ' || got || ', wanted ' || wanted || ')');
end $$;

grant execute on all functions in schema pg_temp to public;

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create function pg_temp.i(n text) returns uuid language sql as $$ select id from pg_temp.ids where name = n $$;
grant execute on function pg_temp.i(text) to public;

create temp sequence clock_seq;
-- A message sent by [sender] into [conv], one second after the one before.
create function pg_temp.say(conv uuid, sender uuid, body text) returns uuid language plpgsql as $$
declare mid uuid;
begin
  insert into public.messages (conversation_id, sender_id, type, body, created_at)
  values (conv, sender, 'text', body,
    now() - interval '2 hours' + nextval('pg_temp.clock_seq') * interval '1 second')
  returning id into mid;
  return mid;
end $$;
grant execute on function pg_temp.say(uuid, uuid, text) to public;

-- ------------------------------------------------------------------ cast
-- Ada owns a circle. Mo moderates it (manage messages and time out members,
-- but cannot ban). Dee and Eve are members; Dee reports, Eve is reported.
-- Cy is nobody. Root is the platform owner, Sam support staff. Dee and Eve
-- are friends, so are Dee and Sam.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '@mr.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from (values ('a1','ada'),('b1','mo'),('c1','cy'),('d1','dee'),('e1','eve'),('f1','root'),('b2','sam'),('c2','fay')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '_mr', initcap(name)
from (values ('a1','ada'),('b1','mo'),('c1','cy'),('d1','dee'),('e1','eve'),('f1','root'),('b2','sam'),('c2','fay')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || n)::uuid
from (values ('a1','ada'),('b1','mo'),('c1','cy'),('d1','dee'),('e1','eve'),('f1','root'),('b2','sam'),('c2','fay')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(x.a, x.b), greatest(x.a, x.b)
from (values
  (pg_temp.i('dee'), pg_temp.i('eve')),
  (pg_temp.i('dee'), pg_temp.i('sam')),
  (pg_temp.i('dee'), pg_temp.i('fay'))
) x(a, b);

insert into public.app_admins (user_id, role)
values (pg_temp.i('root'), 'owner'), (pg_temp.i('sam'), 'support');

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'circle', public.create_circle('Reports circle', array[]::uuid[]);
select pg_temp.root();
insert into pg_temp.ids
select 'channel', cc.conversation_id from public.circle_channels cc
where cc.circle_id = pg_temp.i('circle') and cc.position = 0;

insert into public.circle_members (circle_id, user_id, role)
select pg_temp.i('circle'), pg_temp.i(n), 'member' from unnest(array['mo','dee','eve']) n;
insert into public.conversation_members (conversation_id, user_id, role)
select pg_temp.i('channel'), cm.user_id, cm.role
from public.circle_members cm where cm.circle_id = pg_temp.i('circle')
on conflict do nothing;

with role as (
  insert into public.circle_roles (circle_id, name, position, permissions)
  values (pg_temp.i('circle'), 'Mods', 1, public.circle_default_role_permissions() | 4 | 65536)
  returning id
)
insert into public.circle_member_roles (circle_id, user_id, role_id)
select pg_temp.i('circle'), pg_temp.i('mo'), role.id from role;

-- Chats: a direct chat and a group, outside any circle.
select pg_temp.act(pg_temp.i('dee'));
insert into pg_temp.ids select 'dm', public.get_or_create_direct_conversation(pg_temp.i('eve'));
insert into pg_temp.ids select 'dm_sam', public.get_or_create_direct_conversation(pg_temp.i('sam'));
insert into pg_temp.ids select 'group',
  public.create_group_conversation('Reports group', array[pg_temp.i('eve'), pg_temp.i('fay')]);
select pg_temp.root();

-- Channel messages: 6 before, the reported one, 6 after. One of the
-- neighbours is held by the AI guard (Dee must not see it) and one is old
-- news from Dee herself.
insert into pg_temp.ids select 'c0', pg_temp.say(pg_temp.i('channel'), pg_temp.i('ada'), 'channel zero');
insert into pg_temp.ids select 'c1', pg_temp.say(pg_temp.i('channel'), pg_temp.i('ada'), 'channel one');
insert into pg_temp.ids select 'c2', pg_temp.say(pg_temp.i('channel'), pg_temp.i('eve'), 'channel two');
insert into pg_temp.ids select 'c3', pg_temp.say(pg_temp.i('channel'), pg_temp.i('dee'), 'channel three');
insert into pg_temp.ids select 'c4', pg_temp.say(pg_temp.i('channel'), pg_temp.i('eve'), 'channel four held');
insert into pg_temp.ids select 'c5', pg_temp.say(pg_temp.i('channel'), pg_temp.i('eve'), 'channel five');
insert into pg_temp.ids select 'c6', pg_temp.say(pg_temp.i('channel'), pg_temp.i('ada'), 'channel six');
insert into pg_temp.ids select 'bad', pg_temp.say(pg_temp.i('channel'), pg_temp.i('eve'), 'buy my pills at evil.example');
insert into pg_temp.ids select 'a1', pg_temp.say(pg_temp.i('channel'), pg_temp.i('dee'), 'after one');
insert into pg_temp.ids select 'a2', pg_temp.say(pg_temp.i('channel'), pg_temp.i('eve'), 'after two');
insert into pg_temp.ids select 'a3', pg_temp.say(pg_temp.i('channel'), pg_temp.i('eve'), 'after three');
insert into pg_temp.ids select 'a4', pg_temp.say(pg_temp.i('channel'), pg_temp.i('ada'), 'after four');
insert into pg_temp.ids select 'a5', pg_temp.say(pg_temp.i('channel'), pg_temp.i('eve'), 'after five');
insert into pg_temp.ids select 'a6', pg_temp.say(pg_temp.i('channel'), pg_temp.i('eve'), 'after six');
update public.messages set review_state = 'held' where id = pg_temp.i('c4');
-- A message of Mo's, for the moderator-is-reported case.
insert into pg_temp.ids select 'mo_msg', pg_temp.say(pg_temp.i('channel'), pg_temp.i('mo'), 'moderator says something');
-- Messages for the daily limit.
insert into pg_temp.ids
select 'bulk' || g, pg_temp.say(pg_temp.i('channel'), pg_temp.i('eve'), 'bulk ' || g)
from generate_series(1, 22) g;

-- Direct chat and group messages.
insert into pg_temp.ids select 'dm_bad', pg_temp.say(pg_temp.i('dm'), pg_temp.i('eve'), 'private insult in a dm');
insert into pg_temp.ids select 'dm_mine', pg_temp.say(pg_temp.i('dm'), pg_temp.i('dee'), 'my own dm message');
insert into pg_temp.ids select 'group_bad', pg_temp.say(pg_temp.i('group'), pg_temp.i('eve'), 'group spam');
insert into pg_temp.ids select 'group_fay', pg_temp.say(pg_temp.i('group'), pg_temp.i('fay'), 'fay in the group');
insert into pg_temp.ids select 'sam_msg', pg_temp.say(pg_temp.i('dm_sam'), pg_temp.i('sam'), 'an admin says something');
insert into pg_temp.ids select 'dm_eve2', pg_temp.say(pg_temp.i('dm'), pg_temp.i('eve'), 'second dm to delete');
insert into pg_temp.ids select 'dm_eve3', pg_temp.say(pg_temp.i('dm'), pg_temp.i('eve'), 'third dm to suspend over');
-- View-once photo in the dm.
insert into public.messages (id, conversation_id, sender_id, type, body, attachment, created_at)
values (gen_random_uuid(), pg_temp.i('dm'), pg_temp.i('eve'), 'image', '',
  jsonb_build_object('bucket', 'chat-images', 'path', pg_temp.i('dm')::text || '/secret.jpg',
    'mime_type', 'image/jpeg', 'size', 1234, 'view_once', true),
  now() - interval '1 hour');
insert into pg_temp.ids select 'dm_once', id from public.messages where attachment->>'view_once' = 'true';
-- A normal photo in the dm.
insert into public.messages (id, conversation_id, sender_id, type, body, attachment, created_at)
values (gen_random_uuid(), pg_temp.i('dm'), pg_temp.i('eve'), 'image', 'look',
  jsonb_build_object('bucket', 'chat-images', 'path', pg_temp.i('dm')::text || '/photo.jpg',
    'mime_type', 'image/jpeg', 'size', 4321, 'width', 800, 'height', 600),
  now() - interval '59 minutes');
insert into pg_temp.ids select 'dm_photo', id from public.messages where attachment->>'path' like '%/photo.jpg';

-- Messages Dee cannot report: expired, recalled, in a chat she is not in.
insert into pg_temp.ids select 'expired', pg_temp.say(pg_temp.i('dm'), pg_temp.i('eve'), 'already expired');
update public.messages set expires_at = now() - interval '1 minute' where id = pg_temp.i('expired');
insert into pg_temp.ids select 'recalled', pg_temp.say(pg_temp.i('dm'), pg_temp.i('eve'), 'taken back');
update public.messages set recalled_at = now(), body = '' where id = pg_temp.i('recalled');


-- ===================================== 1. who can report what
do $$
declare
  rid uuid;
begin
  -- Nobody signed in.
  perform pg_temp.act(null);
  perform pg_temp.must_refuse(
    format('select public.report_message(%L, ''spam'')', pg_temp.i('bad')),
    'anon reports a message');

  -- Cy is not in the circle: the message does not exist for him.
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.must_state(
    format('select public.report_message(%L, ''spam'')', pg_temp.i('bad')), 'P0002',
    'an outsider reports a circle message');
  perform pg_temp.must_state(
    format('select public.report_message(%L, ''spam'')', pg_temp.i('dm_bad')), 'P0002',
    'an outsider reports a direct message');
  perform pg_temp.must_state(
    format('select public.report_message(%L, ''spam'')', gen_random_uuid()), 'P0002',
    'a message that does not exist');

  perform pg_temp.act(pg_temp.i('dee'));
  -- Her own message.
  perform pg_temp.must_state(
    format('select public.report_message(%L, ''spam'')', pg_temp.i('dm_mine')), '22023',
    'reporting your own message');
  perform pg_temp.must_state(
    format('select public.report_message(%L, ''spam'')', pg_temp.i('c3')), '22023',
    'reporting your own channel message');
  -- A message held by the AI guard is invisible to her.
  perform pg_temp.must_state(
    format('select public.report_message(%L, ''spam'')', pg_temp.i('c4')), 'P0002',
    'reporting a message held for review');
  -- Expired and recalled messages have nothing left to report.
  perform pg_temp.must_state(
    format('select public.report_message(%L, ''spam'')', pg_temp.i('expired')), 'P0002',
    'reporting an expired message');
  perform pg_temp.must_state(
    format('select public.report_message(%L, ''spam'')', pg_temp.i('recalled')), 'P0002',
    'reporting a recalled message');
  -- A bad reason.
  perform pg_temp.must_state(
    format('select public.report_message(%L, ''because'')', pg_temp.i('bad')), '22023',
    'an unknown reason');
  perform pg_temp.must_state(
    format('select public.report_message(%L, null)', pg_temp.i('bad')), '22023',
    'no reason');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.message_reports) = 0,
    'attack: a refused report was stored');
  perform pg_temp.expect((select count(*) from public.blocks) = 0,
    'attack: a refused report blocked somebody');

  -- Eve reports a held message of hers? Her own: refused. A held message of
  -- somebody else is invisible to Mo only if he cannot moderate: he can, so
  -- he sees it and may report it.
  perform pg_temp.act(pg_temp.i('mo'));
  rid := public.report_message(pg_temp.i('c4'), 'other', 'held one');
  perform pg_temp.expect(rid is not null, 'a moderator reports a held message he can see');
  perform pg_temp.root();
  delete from public.message_reports;
end $$;

-- ===================================== 2. a circle report, with context
do $$
declare
  rid uuid;
  again uuid;
  r public.message_reports%rowtype;
  ctx jsonb;
begin
  perform pg_temp.act(pg_temp.i('dee'));
  rid := public.report_message(pg_temp.i('bad'), 'spam', ' sells pills ', true, false);
  insert into pg_temp.ids values ('report', rid);
  again := public.report_message(pg_temp.i('bad'), 'harassment', 'again', true, false);
  perform pg_temp.expect(again = rid, 'reporting the same message twice returns the first report');
  perform pg_temp.root();

  select * into r from public.message_reports where id = rid;
  perform pg_temp.expect((select count(*) from public.message_reports) = 1, 'one report is stored');
  perform pg_temp.expect(r.circle_id = pg_temp.i('circle'), 'the report belongs to the circle');
  perform pg_temp.expect(r.conversation_id = pg_temp.i('channel'), 'the report keeps the conversation');
  perform pg_temp.expect(r.reported_user_id = pg_temp.i('eve'), 'the report knows the sender');
  perform pg_temp.expect(r.reason = 'spam' and r.details = 'sells pills', 'reason and trimmed details');
  perform pg_temp.expect(r.status = 'open' and r.handled_at is null, 'the report starts open');
  perform pg_temp.expect(r.snapshot->>'body' = 'buy my pills at evil.example', 'the snapshot has the text');
  perform pg_temp.expect(r.snapshot->>'sender_username' = 'eve_mr', 'the snapshot names the sender');
  perform pg_temp.expect(r.snapshot->>'circle_name' = 'Reports circle', 'the snapshot names the circle');
  perform pg_temp.expect(r.snapshot->>'title' = 'buy my pills at evil.example', 'the snapshot has a title');

  ctx := r.context;
  perform pg_temp.expect(jsonb_array_length(ctx) = 10, 'context: five before and five after (got ' || jsonb_array_length(ctx) || ')');
  perform pg_temp.expect(not exists (
      select 1 from jsonb_array_elements(ctx) e where e->>'id' = pg_temp.i('c4')::text),
    'context: leaves out the message held for review');
  perform pg_temp.expect(not exists (
      select 1 from jsonb_array_elements(ctx) e where e->>'id' = pg_temp.i('c4')::text),
    'context: nothing the reporter cannot see');
  perform pg_temp.expect(exists (
      select 1 from jsonb_array_elements(ctx) e where e->>'body' = 'channel three' and e->>'position' = 'before'),
    'context: messages before are marked');
  perform pg_temp.expect(exists (
      select 1 from jsonb_array_elements(ctx) e where e->>'body' = 'after five' and e->>'position' = 'after'),
    'context: messages after are marked');
  perform pg_temp.expect(not exists (
      select 1 from jsonb_array_elements(ctx) e where e->>'body' in ('after six', 'channel zero')),
    'context: no more than five on each side');
  perform pg_temp.expect((ctx->0->>'created_at')::timestamptz <= (ctx->9->>'created_at')::timestamptz,
    'context: oldest first');
end $$;

-- Without "include context" nothing around the message is stored; the flag
-- also blocks.
do $$
declare
  rid uuid;
begin
  perform pg_temp.act(pg_temp.i('dee'));
  rid := public.report_message(pg_temp.i('a3'), 'harassment', '', false, true);
  perform pg_temp.root();
  perform pg_temp.expect((select context is null from public.message_reports where id = rid),
    'no context unless asked for');
  perform pg_temp.expect(exists (
      select 1 from public.blocks where blocker_id = pg_temp.i('dee') and blocked_id = pg_temp.i('eve')),
    'also_block blocks the sender');
  perform pg_temp.root();
  delete from public.message_reports where id = rid;
  delete from public.blocks;
end $$;

-- ===================================== 3. who reads it
do $$
declare
  rid uuid := pg_temp.i('report');
  who uuid;
  label text;
  s text;
begin
  -- The plain columns, for the reporter only.
  perform pg_temp.act(pg_temp.i('dee'));
  perform pg_temp.expect(pg_temp.cnt('select id, reason, status from public.message_reports') = 1,
    'the reporter sees their own report');
  foreach s in array array[
    'select snapshot from public.message_reports',
    'select context from public.message_reports',
    'select details from public.message_reports',
    'select reported_user_id from public.message_reports',
    'select * from public.message_reports',
    'update public.message_reports set status = ''dismissed''',
    'delete from public.message_reports',
    'insert into public.message_reports (reporter_id, reason) values (auth.uid(), ''spam'')'
  ] loop
    perform pg_temp.expect(pg_temp.refused(s) or pg_temp.changed(s) = 0,
      'reporter: ' || s);
  end loop;
  perform pg_temp.must_state(
    format('select public.list_circle_message_reports(%L)', pg_temp.i('circle')), '42501',
    'the reporter lists the circle reports');
  perform pg_temp.must_state(
    format('select public.resolve_message_report(%L, ''dismiss'')', rid), 'P0002',
    'the reporter resolves their own report');

  -- The reported person, an outsider, a plain member and nobody.
  foreach who in array array[pg_temp.i('eve'), pg_temp.i('cy'), pg_temp.i('fay'), null::uuid] loop
    perform pg_temp.act(who);
    label := coalesce((select name from pg_temp.ids where id = who), 'anon');
    perform pg_temp.expect(
      pg_temp.refused('select id from public.message_reports')
        or pg_temp.cnt('select id from public.message_reports') = 0,
      label || ' reads reports');
    perform pg_temp.expect(
      pg_temp.refused('select snapshot from public.message_reports')
        or pg_temp.cnt('select snapshot from public.message_reports') = 0,
      label || ' reads snapshots');
    perform pg_temp.must_refuse(
      format('select public.list_circle_message_reports(%L)', pg_temp.i('circle')),
      label || ' lists the circle reports');
    perform pg_temp.must_refuse(
      format('select public.resolve_message_report(%L, ''dismiss'')', rid),
      label || ' resolves a report');
    perform pg_temp.must_refuse('select public.admin_list_message_reports()',
      label || ' lists platform message reports');
    perform pg_temp.must_refuse(format('select public.admin_get_message_report(%L)', rid),
      label || ' reads a platform message report');
    perform pg_temp.must_refuse(
      format('select public.admin_resolve_message_report(%L, ''dismiss'')', rid),
      label || ' resolves as admin');
    perform pg_temp.must_refuse(format('select public.admin_erase_message(%L)', pg_temp.i('bad')),
      label || ' erases a message as admin');
    perform pg_temp.must_refuse(format('select public.report_message_snapshot(m) from public.messages m where m.id = %L', pg_temp.i('bad')),
      label || ' builds a snapshot');
    perform pg_temp.must_refuse('select public.purge_old_message_report_data()',
      label || ' purges report data');
  end loop;

  -- Eve is told nothing: no counts either.
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(public.count_message_reviews(pg_temp.i('circle')) = 0,
    'the reported person sees no badge');

  -- Mo moderates: he reads the circle's reports through the function and the
  -- plain columns through the table, never the snapshot through the table.
  perform pg_temp.act(pg_temp.i('mo'));
  perform pg_temp.expect(jsonb_array_length(public.list_circle_message_reports(pg_temp.i('circle'))) = 1,
    'the moderator lists the report');
  perform pg_temp.expect(
    public.list_circle_message_reports(pg_temp.i('circle'))->0->'snapshot'->>'body' = 'buy my pills at evil.example',
    'the moderator reads the snapshot');
  perform pg_temp.expect(
    jsonb_array_length(public.list_circle_message_reports(pg_temp.i('circle'))->0->'context') = 10,
    'the moderator reads the context');
  perform pg_temp.expect(
    public.list_circle_message_reports(pg_temp.i('circle'))->0->'reporter'->>'name' = 'Dee',
    'the moderator sees who reported');
  perform pg_temp.expect(pg_temp.cnt('select id from public.message_reports') = 1,
    'the moderator sees the plain columns');
  perform pg_temp.expect(pg_temp.refused('select snapshot from public.message_reports'),
    'the moderator cannot read snapshots through the table');
  perform pg_temp.expect(pg_temp.refused('select details from public.message_reports'),
    'the moderator cannot read details through the table');
  perform pg_temp.expect(public.count_message_reviews(pg_temp.i('circle')) = 1,
    'the badge counts the open report');
  perform pg_temp.must_state(
    format('select public.list_circle_message_reports(%L, ''never'')', pg_temp.i('circle')), '22023',
    'an unknown status filter');
  -- But not another circle's.
  perform pg_temp.root();
end $$;

-- ===================================== 4. a moderator who is reported
do $$
declare
  rid uuid;
begin
  perform pg_temp.act(pg_temp.i('dee'));
  rid := public.report_message(pg_temp.i('mo_msg'), 'harassment', '', true, false);
  insert into pg_temp.ids values ('mo_report', rid);

  perform pg_temp.act(pg_temp.i('mo'));
  perform pg_temp.expect(jsonb_array_length(public.list_circle_message_reports(pg_temp.i('circle'))) = 1,
    'the reported moderator does not see the report about himself');
  perform pg_temp.expect(public.count_message_reviews(pg_temp.i('circle')) = 1,
    'the reported moderator does not count it');
  perform pg_temp.expect(pg_temp.cnt('select id from public.message_reports') = 1,
    'the reported moderator does not read it through the table');
  perform pg_temp.must_state(format('select public.resolve_message_report(%L, ''dismiss'')', rid), 'P0002',
    'the reported moderator dismisses the report about himself');

  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(jsonb_array_length(public.list_circle_message_reports(pg_temp.i('circle'))) = 2,
    'the owner sees both reports');
  perform pg_temp.root();
end $$;

-- ===================================== 5. resolving in the circle
do $$
declare
  rid uuid := pg_temp.i('report');
  second uuid;
  result jsonb;
begin
  -- A second reporter of the same message, to be settled together.
  perform pg_temp.act(pg_temp.i('fay'));
  perform pg_temp.root();
  insert into public.circle_members (circle_id, user_id, role) values (pg_temp.i('circle'), pg_temp.i('fay'), 'member');
  insert into public.conversation_members (conversation_id, user_id, role) values (pg_temp.i('channel'), pg_temp.i('fay'), 'member');
  perform pg_temp.act(pg_temp.i('fay'));
  second := public.report_message(pg_temp.i('bad'), 'spam', '', false, false);
  perform pg_temp.root();

  -- Mo cannot ban (no ban_members): the report stays open.
  perform pg_temp.act(pg_temp.i('mo'));
  perform pg_temp.must_state(format('select public.resolve_message_report(%L, ''ban'')', rid), '42501',
    'a moderator without ban_members bans');
  perform pg_temp.must_state(format('select public.resolve_message_report(%L, ''explode'')', rid), '22023',
    'an unknown action');
  perform pg_temp.root();
  perform pg_temp.expect((select status = 'open' from public.message_reports where id = rid),
    'a refused action leaves the report open');
  perform pg_temp.expect(not exists (select 1 from public.circle_bans),
    'a refused ban banned nobody');

  -- Time out.
  perform pg_temp.act(pg_temp.i('mo'));
  result := public.resolve_message_report(second, 'timeout', 600);
  perform pg_temp.expect(result->>'status' = 'actioned' and result->>'resolution' = 'user_timed_out',
    'timeout: the result');
  perform pg_temp.root();
  perform pg_temp.expect(
    (select timed_out_until > now() + interval '9 minutes' and timed_out_until < now() + interval '11 minutes'
       from public.circle_members where circle_id = pg_temp.i('circle') and user_id = pg_temp.i('eve')),
    'timeout: Eve is timed out for the asked time');
  perform pg_temp.expect(
    (select status = 'actioned' and handled_by = pg_temp.i('mo') and resolution = 'user_timed_out'
       from public.message_reports where id = rid),
    'timeout: the other report of the same message is settled with it');
  perform pg_temp.expect(exists (
      select 1 from public.circle_audit_log
      where circle_id = pg_temp.i('circle') and action = 'member_timeout' and actor_id = pg_temp.i('mo')),
    'timeout: the circle audit log has the timeout');
  perform pg_temp.expect(exists (
      select 1 from public.circle_audit_log
      where circle_id = pg_temp.i('circle') and action = 'report_resolve' and actor_id = pg_temp.i('mo')
        and changes->>'action' = 'timeout' and target_id = pg_temp.i('bad')),
    'timeout: the circle audit log has the report entry');

  perform pg_temp.act(pg_temp.i('mo'));
  perform pg_temp.must_state(format('select public.resolve_message_report(%L, ''dismiss'')', rid), 'P0002',
    'a handled report is handled once');
  perform pg_temp.expect(jsonb_array_length(public.list_circle_message_reports(pg_temp.i('circle'))) = 0,
    'handled reports leave the open list');
  perform pg_temp.expect(jsonb_array_length(public.list_circle_message_reports(pg_temp.i('circle'), 'handled')) = 2,
    'handled reports are in the handled list');
  perform pg_temp.root();
end $$;

-- Delete the message, dismiss, ban (as the owner).
do $$
declare
  r1 uuid;
  r2 uuid;
  r3 uuid;
begin
  perform pg_temp.act(pg_temp.i('dee'));
  r1 := public.report_message(pg_temp.i('a2'), 'unsafe_content', '', true, false);
  r2 := public.report_message(pg_temp.i('a5'), 'other', '', true, false);
  r3 := public.report_message(pg_temp.i('a6'), 'harassment', '', true, false);
  perform pg_temp.act(pg_temp.i('mo'));
  perform pg_temp.expect(public.count_message_reviews(pg_temp.i('circle')) = 3,
    'the badge counts the open reports, not the one about the moderator (got ' || public.count_message_reviews(pg_temp.i('circle')) || ')');

  perform public.resolve_message_report(r1, 'delete_message');
  perform pg_temp.root();
  perform pg_temp.expect((select recalled_at is not null and recalled_by = pg_temp.i('mo') and body = ''
       from public.messages where id = pg_temp.i('a2')),
    'delete: the message is gone for everyone');
  perform pg_temp.expect((select status = 'actioned' and resolution = 'message_deleted'
       from public.message_reports where id = r1), 'delete: the report is actioned');
  perform pg_temp.expect((select snapshot->>'body' = 'after two' from public.message_reports where id = r1),
    'delete: the snapshot keeps the text for the handler');
  perform pg_temp.expect(exists (
      select 1 from public.circle_audit_log where action = 'message_delete' and actor_id = pg_temp.i('mo')
        and target_id = pg_temp.i('a2')),
    'delete: the circle audit log has the deletion');

  -- A message recalled by someone else before the moderator acts.
  update public.messages set recalled_at = now(), body = '' where id = pg_temp.i('a5');
  perform pg_temp.act(pg_temp.i('mo'));
  perform pg_temp.expect(public.resolve_message_report(r2, 'delete_message')->>'status' = 'actioned',
    'delete: a message that is already gone still settles the report');

  perform pg_temp.act(pg_temp.i('mo'));
  perform pg_temp.expect(public.resolve_message_report(r3, 'dismiss')->>'status' = 'dismissed', 'dismiss: the result');
  perform pg_temp.root();
  perform pg_temp.expect(exists (
      select 1 from public.circle_audit_log where action = 'report_dismiss' and actor_id = pg_temp.i('mo')
        and target_id = pg_temp.i('a6')),
    'dismiss: the circle audit log has it');
  perform pg_temp.expect((select resolution = 'dismissed' and handled_by = pg_temp.i('mo') from public.message_reports where id = r3),
    'dismiss: who and how');
end $$;

do $$
declare
  rid uuid;
begin
  -- The owner bans.
  perform pg_temp.act(pg_temp.i('dee'));
  rid := public.report_message(pg_temp.i('bulk1'), 'harassment', '', false, false);
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(public.resolve_message_report(rid, 'ban')->>'resolution' = 'user_banned', 'ban: the result');
  perform pg_temp.root();
  perform pg_temp.expect(exists (
      select 1 from public.circle_bans where circle_id = pg_temp.i('circle') and user_id = pg_temp.i('eve')),
    'ban: Eve is banned');
  perform pg_temp.expect(not exists (
      select 1 from public.circle_members where circle_id = pg_temp.i('circle') and user_id = pg_temp.i('eve')),
    'ban: Eve left the circle');
  perform pg_temp.expect(exists (
      select 1 from public.circle_audit_log where action = 'report_resolve' and changes->>'action' = 'ban'),
    'ban: the circle audit log has it');

  -- Eve's channel messages stay reportable for people who can still see them.
  delete from public.message_reports where id = rid;
end $$;

-- ===================================== 6. the daily limit
do $$
declare
  n integer;
  rid uuid;
begin
  perform pg_temp.root();
  delete from public.message_reports where reporter_id = pg_temp.i('dee');
  perform pg_temp.act(pg_temp.i('dee'));
  for n in 2..21 loop
    rid := public.report_message(pg_temp.i('bulk' || n), 'spam', '', false, false);
  end loop;
  perform pg_temp.expect((select count(*) from public.message_reports where reporter_id = pg_temp.i('dee')) = 20,
    'limit: twenty reports are allowed');
  perform pg_temp.must_state(
    format('select public.report_message(%L, ''spam'')', pg_temp.i('bulk22')), '54000',
    'limit: the twenty-first report in a day');
  -- A report already filed can be filed again (it returns the first one).
  perform pg_temp.expect(public.report_message(pg_temp.i('bulk2'), 'spam') is not null,
    'limit: an old report is still returned');
  perform pg_temp.root();
  -- A day later she can report again.
  update public.message_reports set created_at = now() - interval '25 hours' where reporter_id = pg_temp.i('dee');
  perform pg_temp.act(pg_temp.i('dee'));
  perform pg_temp.expect(public.report_message(pg_temp.i('bulk22'), 'spam') is not null,
    'limit: reporting works again after a day');
  perform pg_temp.root();
  delete from public.message_reports;
end $$;

-- ===================================== 7. direct chats and groups go to the platform
do $$
declare
  rdm uuid;
  rgroup uuid;
  rphoto uuid;
  ronce uuid;
  rsam uuid;
  r public.message_reports%rowtype;
  detail jsonb;
begin
  perform pg_temp.act(pg_temp.i('dee'));
  rdm := public.report_message(pg_temp.i('dm_bad'), 'harassment', 'insulting me', true, false);
  rgroup := public.report_message(pg_temp.i('group_bad'), 'spam', '', true, false);
  rphoto := public.report_message(pg_temp.i('dm_photo'), 'unsafe_content', '', false, false);
  ronce := public.report_message(pg_temp.i('dm_once'), 'unsafe_content', '', false, false);
  rsam := public.report_message(pg_temp.i('sam_msg'), 'other', '', false, false);
  insert into pg_temp.ids values ('r_dm', rdm), ('r_group', rgroup), ('r_photo', rphoto), ('r_once', ronce), ('r_sam', rsam);
  perform pg_temp.root();

  perform pg_temp.expect((select count(*) from public.message_reports where circle_id is null) = 5,
    'platform: direct and group reports have no circle');
  perform pg_temp.expect((select snapshot->>'conversation_type' = 'direct' from public.message_reports where id = rdm),
    'platform: the snapshot knows it was a direct chat');
  perform pg_temp.expect((select snapshot->>'conversation_type' = 'group' and snapshot->>'conversation_title' = 'Reports group'
       from public.message_reports where id = rgroup), 'platform: and a group');
  perform pg_temp.expect((select jsonb_array_length(context) >= 3 from public.message_reports where id = rdm),
    'platform: context of the direct chat');
  perform pg_temp.expect(not exists (
      select 1 from jsonb_array_elements((select context from public.message_reports where id = rdm)) e
      where e->>'body' in ('already expired', 'taken back')),
    'platform: context leaves out expired and recalled messages');

  -- Attachments: metadata only, no paths; view-once is a placeholder.
  select * into r from public.message_reports where id = rphoto;
  perform pg_temp.expect(r.snapshot->'attachment'->>'mime_type' = 'image/jpeg'
      and (r.snapshot->'attachment'->>'width')::int = 800, 'attachment: the metadata is kept');
  perform pg_temp.expect(r.snapshot->'attachment' ? 'path' = false and r.snapshot->'attachment' ? 'bucket' = false,
    'attachment: no storage path is kept');
  select * into r from public.message_reports where id = ronce;
  perform pg_temp.expect(r.snapshot->'attachment' = '{"kind": "view_once", "view_once": true}'::jsonb,
    'view once: the snapshot has a placeholder only');
  perform pg_temp.expect(position('secret.jpg' in r.snapshot::text) = 0 and position('secret.jpg' in coalesce(r.context::text, '')) = 0,
    'view once: the file name is nowhere');
  perform pg_temp.expect(position('secret.jpg' in (select context::text from public.message_reports where id = rdm)) = 0,
    'view once: the context has no file name either');

  -- The circle's moderators and owner read nothing of it.
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.cnt('select id from public.message_reports where circle_id is null') = 0,
    'platform: a circle owner does not read direct-chat reports');
  perform pg_temp.expect(public.count_message_reviews(pg_temp.i('circle')) = 0,
    'platform: and they are not in the circle badge');
  perform pg_temp.act(pg_temp.i('mo'));
  perform pg_temp.expect(pg_temp.cnt('select id from public.message_reports where circle_id is null') = 0,
    'platform: nor a moderator');
  perform pg_temp.must_state(format('select public.resolve_message_report(%L, ''dismiss'')', rdm), 'P0002',
    'platform: nor can a moderator resolve one');

  -- Admins: support reads and dismisses; the owner deletes and suspends.
  perform pg_temp.act(pg_temp.i('sam'));
  perform pg_temp.expect(jsonb_array_length(public.admin_list_message_reports()) = 4,
    'admin: support lists the reports (not the one about themselves)');
  perform pg_temp.expect(public.admin_list_message_reports()->0->>'kind' = 'message',
    'admin: the rows are message reports');
  perform pg_temp.expect(jsonb_array_length(public.admin_list_message_reports('all')) = 4, 'admin: all');
  detail := public.admin_get_message_report(rdm);
  perform pg_temp.expect(detail->'report'->'snapshot'->>'body' = 'private insult in a dm', 'admin: reads the snapshot');
  perform pg_temp.expect(jsonb_array_length(detail->'report'->'snapshot'->'context') >= 3, 'admin: reads the context');
  perform pg_temp.expect(detail->'responsible_user'->>'username' = 'eve_mr', 'admin: the sender is the responsible person');
  perform pg_temp.expect(detail->'report'->'reporter'->>'username' = 'dee_mr', 'admin: knows the reporter');
  perform pg_temp.must_state(format('select public.admin_get_message_report(%L)', rsam), 'P0002',
    'admin: a report about the admin is hidden from them');
  perform pg_temp.must_state(format('select public.admin_resolve_message_report(%L, ''dismiss'')', rsam), 'P0002',
    'admin: and cannot be handled by them');
  perform pg_temp.must_state(format('select public.admin_get_message_report(%L)', pg_temp.i('report')), 'P0002',
    'admin: circle reports are not here');
  perform pg_temp.expect(pg_temp.cnt('select id from public.message_reports where circle_id is not null') = 0,
    'admin: nor in the table');

  perform pg_temp.must_state(format('select public.admin_resolve_message_report(%L, ''delete_message'')', rdm), '42501',
    'admin: support cannot delete messages');
  perform pg_temp.must_state(format('select public.admin_resolve_message_report(%L, ''suspend'')', rdm), '42501',
    'admin: support cannot suspend');
  perform pg_temp.must_state(format('select public.admin_resolve_message_report(%L, ''explode'')', rdm), '22023',
    'admin: unknown action');
  perform pg_temp.expect(public.admin_resolve_message_report(rphoto, 'dismiss')->>'status' = 'dismissed',
    'admin: support dismisses');

  perform pg_temp.act(pg_temp.i('root'));
  -- Suspension must have happened first.
  perform pg_temp.must_state(format('select public.admin_resolve_message_report(%L, ''suspend'')', rdm), '22023',
    'admin: closing as suspended needs a suspension');
  perform pg_temp.expect(public.admin_resolve_message_report(rdm, 'delete_message', 'insult')->>'resolution' = 'message_deleted',
    'admin: the owner deletes the message');
  perform pg_temp.root();
  perform pg_temp.expect((select recalled_at is not null and body = '' and recalled_by = pg_temp.i('root')
       from public.messages where id = pg_temp.i('dm_bad')), 'admin: the message is gone');
  perform pg_temp.expect((select snapshot->>'body' = 'private insult in a dm' from public.message_reports where id = rdm),
    'admin: the report keeps the text');
  perform pg_temp.expect((select body from public.messages where id = pg_temp.i('group_fay')) = 'fay in the group',
    'admin: other messages are untouched');
  perform pg_temp.expect(exists (
      select 1 from public.admin_audit_log
      where action = 'resolve_message_report' and report_id = rdm and target_type = 'message'
        and target_id = pg_temp.i('dm_bad') and details->>'action' = 'delete_message'),
    'admin: the audit log has the deletion');
  perform pg_temp.expect(exists (
      select 1 from public.admin_audit_log where action = 'resolve_message_report' and details->>'action' = 'dismiss'
        and actor_role = 'support'),
    'admin: and the dismissal by support');

  -- Suspend through the admin path, then close the group report.
  perform pg_temp.act(pg_temp.i('root'));
  perform public.admin_suspend_user(pg_temp.i('eve'), null, 'spam in groups');
  perform pg_temp.expect(public.admin_resolve_message_report(rgroup, 'suspend')->>'resolution' = 'user_suspended',
    'admin: closing as suspended works once they are');
  perform pg_temp.expect(public.admin_resolve_message_report(ronce, 'dismiss')->>'resolution' = 'no_violation', 'admin: dismiss');
  perform pg_temp.must_state(format('select public.admin_resolve_message_report(%L, ''dismiss'')', rdm), 'P0002',
    'admin: handled once');
  perform pg_temp.expect(jsonb_array_length(public.admin_list_message_reports()) = 1
      and public.admin_list_message_reports()->0->>'id' = rsam::text, 'admin: only the report about the support admin is left, for the owner');
  perform pg_temp.expect(jsonb_array_length(public.admin_list_message_reports('handled')) = 4, 'admin: handled list');
  perform pg_temp.expect(public.admin_list_message_reports('reviewed')->0->>'status' = 'reviewed', 'admin: actioned reads as reviewed');
  perform pg_temp.root();
end $$;

-- ===================================== 8. retention
do $$
declare
  open_report uuid;
  old_report uuid;
  fresh_report uuid;
begin
  perform pg_temp.root();
  delete from public.message_reports;
  perform pg_temp.act(pg_temp.i('dee'));
  open_report := public.report_message(pg_temp.i('group_fay'), 'spam', '', true, false);
  old_report := public.report_message(pg_temp.i('bulk3'), 'spam', '', true, false);
  fresh_report := public.report_message(pg_temp.i('bulk4'), 'spam', '', true, false);
  perform pg_temp.root();
  update public.message_reports set status = 'dismissed', handled_at = now() - interval '91 days', resolution = 'dismissed'
    where id = old_report;
  update public.message_reports set status = 'dismissed', handled_at = now() - interval '89 days', resolution = 'dismissed'
    where id = fresh_report;
  perform pg_temp.expect(public.purge_old_message_report_data() = 1, 'retention: one report is old enough');
  perform pg_temp.expect((select snapshot is null and context is null and status = 'dismissed' from public.message_reports where id = old_report),
    'retention: snapshot and context are cleared 90 days after handling, the report stays');
  perform pg_temp.expect((select snapshot is not null and context is not null from public.message_reports where id = fresh_report),
    'retention: a report handled 89 days ago keeps its copy');
  perform pg_temp.expect((select snapshot is not null from public.message_reports where id = open_report),
    'retention: an open report keeps its copy');
  -- The daily job that is already scheduled does it.
  update public.message_reports set handled_at = now() - interval '100 days' where id = fresh_report;
  perform public.purge_old_client_errors();
  perform pg_temp.expect((select snapshot is null from public.message_reports where id = fresh_report),
    'retention: the existing daily purge clears it too');
  -- Old reports of a purged message: the message may be gone, the report stays.
  delete from public.messages where id = pg_temp.i('group_fay');
  perform pg_temp.expect((select message_id is null and snapshot is not null from public.message_reports where id = open_report),
    'a purged message leaves the report with its copy');
end $$;

-- ===================================== 9. terms and age
do $$
declare
  fresh uuid := '00000000-0000-4000-8000-0000000000f9';
  old uuid := '00000000-0000-4000-8000-0000000000f8';
  status jsonb;
begin
  perform pg_temp.root();
  insert into auth.users (id, email, instance_id, aud, role)
  values (fresh, 'new@mr.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
         (old, 'old@mr.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');

  -- Signing up inserts the profile as the new person, with a made-up time.
  perform pg_temp.act(fresh);
  insert into public.profiles (id, username, display_name, accepted_terms_at, age_confirmed_at)
  values (fresh, 'new_mr', 'New', '2001-01-01', '2001-01-01');
  status := public.get_my_terms_status();
  perform pg_temp.expect((status->>'accepted_terms_at')::timestamptz > now() - interval '1 minute', 'terms: the time is the server''s');
  perform pg_temp.expect((status->>'age_confirmed_at')::timestamptz > now() - interval '1 minute', 'terms: and the age confirmation''s');
  perform pg_temp.expect(pg_temp.refused('select accepted_terms_at from public.profiles'), 'terms: the column is not readable');
  perform pg_temp.expect(pg_temp.refused('select age_confirmed_at from public.profiles'), 'terms: nor the age column');
  perform pg_temp.expect(pg_temp.changed(format('update public.profiles set accepted_terms_at = null where id = %L', fresh)) = 0,
    'terms: the person cannot unset it through the table');
  perform pg_temp.expect(pg_temp.changed(format('update public.profiles set accepted_terms_at = now() where id = %L', fresh)) = 0,
    'terms: nor set it');

  -- Somebody who signed up before: nothing recorded, then accepted once.
  perform pg_temp.act(old);
  insert into public.profiles (id, username, display_name) values (old, 'old_mr', 'Old');
  status := public.get_my_terms_status();
  perform pg_temp.expect(status->>'accepted_terms_at' is null and status->>'age_confirmed_at' is null, 'terms: an old account has none');
  status := public.accept_terms();
  perform pg_temp.expect(status->>'accepted_terms_at' is not null and status->>'age_confirmed_at' is not null, 'terms: accepting records both');
  perform pg_temp.root();
  update public.profiles set accepted_terms_at = '2020-01-01', age_confirmed_at = '2020-01-01' where id = old;
  perform pg_temp.act(old);
  status := public.accept_terms();
  perform pg_temp.expect((status->>'accepted_terms_at')::timestamptz < '2021-01-01', 'terms: accepting again keeps the first time');

  -- Others cannot read them; nobody signed in cannot accept.
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(public.get_my_terms_status()->>'accepted_terms_at' is null, 'terms: you only get your own');
  perform pg_temp.act(null);
  perform pg_temp.must_refuse('select public.accept_terms()', 'terms: anon accepts');
  perform pg_temp.must_refuse('select public.get_my_terms_status()', 'terms: anon reads');
  perform pg_temp.root();
end $$;
\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "ATTACK SUCCEEDED / DEFENCE MISSING" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'message reports: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
