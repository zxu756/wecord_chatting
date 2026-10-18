-- Behaviour checks for the private Realtime channels and the storage limits
-- (migrations 202610190050 and 202610190051). Run by
-- test/supabase/realtime_private_test.dart against the local database inside
-- a transaction that is rolled back. Run from the repository root.
--
-- The policies on realtime.messages are asked for real: the script inserts
-- into (send) and selects from (listen) realtime.messages as each person, on
-- the topics the app uses, and checks the allowed or denied answer.
--
-- Cast: Ada owns a group with Bob and Cy, and a direct chat with Bob. Dee is
-- in neither (an outsider). Fay was in the group and left. Later Ada blocks
-- Bob.
--
-- The local database may lack recent migrations, so the script rebuilds the
-- public schema from ALL migrations, in order, inside the transaction (and
-- throws it away at the end).
\set ON_ERROR_STOP on

begin;

-- Behaviour scripts that apply DDL take turns.
select pg_advisory_xact_lock(20261017);
set local client_min_messages = warning;

-- A scratch copy of the schema: everything the migrations make is dropped
-- and made again from the files, so the result does not depend on how far
-- the local database got.
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
\o /dev/null

create temp table failures (msg text);
grant all on failures to public;

create function pg_temp.expect(ok boolean, msg text) returns void
language plpgsql security definer as $$
begin
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

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create function pg_temp.i(n text) returns uuid language sql as $$ select id from pg_temp.ids where name = n $$;

-- Whether [who] (null: nobody signed in) may do [op] ('listen' or 'send') on
-- the private channel [topic] with the [ext] ('broadcast' or 'presence')
-- extension: the policy on realtime.messages, asked as that person. Listening
-- is a select of realtime.messages, sending an insert. Realtime asks it the
-- same way when a channel is joined or a message is sent.
create function pg_temp.allowed(who uuid, topic text, ext text, op text)
returns boolean language plpgsql as $$
declare ok boolean;
begin
  perform pg_temp.root();
  -- Something to listen to, written by the server.
  insert into realtime.messages (topic, extension, payload, event, private)
  values (topic, ext, '{}', 'x', true);
  perform pg_temp.act(who);
  perform set_config('realtime.topic', topic, true);
  begin
    if op = 'listen' then
      select exists (
        select 1 from realtime.messages m where m.topic = allowed.topic and m.extension = ext
      ) into ok;
    else
      insert into realtime.messages (topic, extension, payload, event, private)
      values (topic, ext, '{}', 'y', true);
      ok := true;
    end if;
  exception when insufficient_privilege then
    ok := false;
  end;
  perform pg_temp.root();
  return ok;
end $$;

-- ------------------------------------------------------------------ cast
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '@rt.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee'),('f1','fay')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '_rt', initcap(name)
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee'),('f1','fay')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || n)::uuid
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee'),('f1','fay')) v(n, name);

insert into pg_temp.ids select 'group', gen_random_uuid();
insert into pg_temp.ids select 'direct', gen_random_uuid();
insert into pg_temp.ids select 'note', gen_random_uuid();
insert into pg_temp.ids select 'gone_note', gen_random_uuid();
insert into pg_temp.ids select 'dm_note', gen_random_uuid();
insert into public.conversations (id, type, title)
values (pg_temp.i('group'), 'group', 'Realtime group'), (pg_temp.i('direct'), 'direct', null);
insert into public.conversation_members (conversation_id, user_id, role)
values
  (pg_temp.i('group'), pg_temp.i('ada'), 'owner'),
  (pg_temp.i('group'), pg_temp.i('bob'), 'member'),
  (pg_temp.i('group'), pg_temp.i('cy'), 'member'),
  (pg_temp.i('group'), pg_temp.i('fay'), 'member'),
  (pg_temp.i('direct'), pg_temp.i('ada'), 'member'),
  (pg_temp.i('direct'), pg_temp.i('bob'), 'member');
insert into public.notes (id, conversation_id, title, created_by, deleted_at)
values
  (pg_temp.i('note'), pg_temp.i('group'), 'Plan', pg_temp.i('ada'), null),
  (pg_temp.i('gone_note'), pg_temp.i('group'), 'Old', pg_temp.i('ada'), now()),
  (pg_temp.i('dm_note'), pg_temp.i('direct'), 'Us', pg_temp.i('ada'), null);
-- Fay leaves the group.
delete from public.conversation_members
where conversation_id = pg_temp.i('group') and user_id = pg_temp.i('fay');

grant execute on all functions in schema pg_temp to public;

-- ======================================== 1. typing and presence in a chat
do $$
declare
  g text := 'chat-activity-' || pg_temp.i('group');
  d text := 'chat-activity-' || pg_temp.i('direct');
  who text; ext text; op text;
begin
  foreach who in array array['ada', 'bob', 'cy'] loop
    foreach ext in array array['broadcast', 'presence'] loop
      foreach op in array array['listen', 'send'] loop
        perform pg_temp.expect(
          pg_temp.allowed(pg_temp.i(who), g, ext, op),
          format('chat activity: a member (%s) can not %s %s', who, op, ext));
      end loop;
    end loop;
  end loop;

  foreach who in array array['dee', 'fay'] loop
    foreach ext in array array['broadcast', 'presence'] loop
      foreach op in array array['listen', 'send'] loop
        perform pg_temp.expect(
          not pg_temp.allowed(pg_temp.i(who), g, ext, op),
          format('chat activity: %s can %s %s',
            case who when 'dee' then 'an outsider' else 'an ex-member' end, op, ext));
      end loop;
    end loop;
  end loop;
  foreach ext in array array['broadcast', 'presence'] loop
    foreach op in array array['listen', 'send'] loop
      perform pg_temp.expect(
        not pg_temp.allowed(null, g, ext, op),
        format('chat activity: nobody signed in can %s %s', op, ext));
    end loop;
  end loop;

  -- The direct chat: its two people, nobody else.
  perform pg_temp.expect(pg_temp.allowed(pg_temp.i('ada'), d, 'broadcast', 'send'), 'direct chat: Ada can not send typing');
  perform pg_temp.expect(pg_temp.allowed(pg_temp.i('bob'), d, 'broadcast', 'listen'), 'direct chat: Bob can not listen to typing');
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('cy'), d, 'broadcast', 'listen'), 'direct chat: a member of another chat can listen');
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('cy'), d, 'presence', 'send'), 'direct chat: a member of another chat can track');

  -- Topics that are not exactly a chat's.
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('ada'), 'chat-activity-', 'broadcast', 'listen'), 'chat activity: empty id');
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('ada'), 'chat-activity-not-a-uuid', 'broadcast', 'send'), 'chat activity: not a uuid');
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('ada'), g || 'x', 'broadcast', 'listen'), 'chat activity: id with a suffix');
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('ada'), 'x' || g, 'broadcast', 'listen'), 'chat activity: id with a prefix');
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('ada'), upper(g), 'broadcast', 'listen'), 'chat activity: upper case topic');
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('ada'), 'chat-activity-' || gen_random_uuid(), 'broadcast', 'listen'), 'chat activity: a chat that does not exist');
  -- A message extension the channel does not use.
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('ada'), g, 'postgres_changes', 'listen'), 'chat activity: another extension');
end $$;

-- Ada blocks Bob: the direct chat goes quiet for both, the group does not.
insert into public.blocks (blocker_id, blocked_id)
values (pg_temp.i('ada'), pg_temp.i('bob'));
do $$
declare
  g text := 'chat-activity-' || pg_temp.i('group');
  d text := 'chat-activity-' || pg_temp.i('direct');
begin
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('bob'), d, 'broadcast', 'send'), 'blocked: the blocked person can still send typing in the direct chat');
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('bob'), d, 'presence', 'listen'), 'blocked: the blocked person can still see presence in the direct chat');
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('ada'), d, 'broadcast', 'listen'), 'blocked: the blocker still hears typing in the direct chat');
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('ada'), d, 'presence', 'send'), 'blocked: the blocker still tracks in the direct chat');
  perform pg_temp.expect(pg_temp.allowed(pg_temp.i('bob'), g, 'broadcast', 'send'), 'blocked: a block must not break a shared group');
end $$;

-- ===================================================== 2. who is in a note
do $$
declare
  n text := 'note-presence-' || pg_temp.i('note');
  gone text := 'note-presence-' || pg_temp.i('gone_note');
  dm text := 'note-presence-' || pg_temp.i('dm_note');
  who text; op text;
begin
  foreach who in array array['ada', 'bob', 'cy'] loop
    foreach op in array array['listen', 'send'] loop
      perform pg_temp.expect(
        pg_temp.allowed(pg_temp.i(who), n, 'presence', op),
        format('note presence: a member (%s) can not %s', who, op));
    end loop;
  end loop;
  foreach who in array array['dee', 'fay'] loop
    foreach op in array array['listen', 'send'] loop
      perform pg_temp.expect(
        not pg_temp.allowed(pg_temp.i(who), n, 'presence', op),
        format('note presence: %s (outsider or ex-member) can %s', who, op));
    end loop;
  end loop;
  foreach op in array array['listen', 'send'] loop
    perform pg_temp.expect(not pg_temp.allowed(null, n, 'presence', op), format('note presence: nobody signed in can %s', op));
    -- Presence only: nobody broadcasts on a note's channel.
    perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('ada'), n, 'broadcast', op), format('note presence: a member can %s a broadcast', op));
    -- A deleted note.
    perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('ada'), gone, 'presence', op), format('note presence: a deleted note can be used to %s', op));
    -- A note of a direct chat whose people block each other.
    perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('ada'), dm, 'presence', op), format('note presence: Ada, who blocked Bob, can %s in their note', op));
    perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('bob'), dm, 'presence', op), format('note presence: Bob, blocked by Ada, can %s in their note', op));
  end loop;
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('ada'), 'note-presence-not-a-uuid', 'presence', 'listen'), 'note presence: not a uuid');
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('ada'), 'note-presence-' || gen_random_uuid(), 'presence', 'listen'), 'note presence: a note that does not exist');
  -- A chat's id is not a note's.
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('ada'), 'note-presence-' || pg_temp.i('group'), 'presence', 'listen'), 'note presence: a chat id');
end $$;

-- Unblocked, the direct chat works again (the block was the reason).
delete from public.blocks;
do $$
begin
  perform pg_temp.expect(pg_temp.allowed(pg_temp.i('bob'), 'chat-activity-' || pg_temp.i('direct'), 'broadcast', 'send'), 'unblocked: typing in the direct chat is still refused');
  perform pg_temp.expect(pg_temp.allowed(pg_temp.i('bob'), 'note-presence-' || pg_temp.i('dm_note'), 'presence', 'listen'), 'unblocked: the direct chat note is still refused');
end $$;

-- ================================================ 3. who is online (global)
do $$
declare op text;
begin
  foreach op in array array['listen', 'send'] loop
    perform pg_temp.expect(pg_temp.allowed(pg_temp.i('dee'), 'online-users', 'presence', op), format('online-users: a signed-in person can not %s', op));
    perform pg_temp.expect(not pg_temp.allowed(null, 'online-users', 'presence', op), format('online-users: nobody signed in can %s', op));
    perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('dee'), 'online-users', 'broadcast', op), format('online-users: a broadcast can be used to %s', op));
    perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('dee'), 'online-users-2', 'presence', op), format('online-users-2: a near topic can be used to %s', op));
    perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('dee'), 'Online-Users', 'presence', op), format('Online-Users: another case can be used to %s', op));
  end loop;
end $$;

-- ===================================== 4. nothing else on a private channel
do $$
declare t text; op text; ext text;
begin
  foreach t in array array[
    'room-1', 'public', 'voice-states', 'typing', '',
    'live-location:' || gen_random_uuid(), 'moments:' || pg_temp.i('dee')
  ] loop
    foreach op in array array['listen', 'send'] loop
      foreach ext in array array['broadcast', 'presence'] loop
        perform pg_temp.expect(
          not pg_temp.allowed(pg_temp.i('ada'), t, ext, op),
          format('topic %L: a signed-in person can %s %s', t, op, ext));
      end loop;
    end loop;
  end loop;
  -- Another person's Moments topic: only to listen on one's own.
  perform pg_temp.expect(not pg_temp.allowed(pg_temp.i('ada'), 'moments:' || pg_temp.i('dee'), 'broadcast', 'listen'), 'moments: listening to another person''s topic');
  perform pg_temp.expect(pg_temp.allowed(pg_temp.i('dee'), 'moments:' || pg_temp.i('dee'), 'broadcast', 'listen'), 'moments: not listening to one''s own topic');
end $$;

-- ================================================== 5. the helper functions
do $$
begin
  perform pg_temp.root();
  perform pg_temp.expect(public.realtime_topic_uuid('chat-activity-' || pg_temp.i('group'), 'chat-activity-') = pg_temp.i('group'), 'topic uuid: parse');
  perform pg_temp.expect(public.realtime_topic_uuid('chat-activity-zz', 'chat-activity-') is null, 'topic uuid: junk is null');
  perform pg_temp.expect(public.realtime_topic_uuid('other-' || pg_temp.i('group'), 'chat-activity-') is null, 'topic uuid: another prefix is null');
  -- Not callable by signed-out callers.
  perform pg_temp.act(null);
  perform pg_temp.expect(
    (select count(*) = 0 from information_schema.routine_privileges
      where routine_schema = 'public'
        and routine_name in ('can_use_chat_activity', 'can_use_note_presence', 'realtime_topic_uuid')
        and grantee in ('anon', 'PUBLIC')),
    'the helpers are executable by anon or public');
  perform pg_temp.root();
end $$;

-- ================================================== 6. the bucket limits
do $$
declare
  b record;
  voice text[]; picture text[];
begin
  perform pg_temp.root();
  -- Every bucket people upload to has a size limit.
  for b in
    select id, file_size_limit from storage.buckets
    where id in ('chat-images', 'chat-files', 'voice-messages', 'profile-avatars',
      'profile-banners', 'group-avatars', 'chat-media')
  loop
    perform pg_temp.expect(b.file_size_limit is not null and b.file_size_limit > 0,
      format('bucket %s has no size limit', b.id));
  end loop;
  perform pg_temp.expect((select count(*) from storage.buckets where id in
    ('chat-images', 'chat-files', 'voice-messages', 'profile-avatars',
     'profile-banners', 'group-avatars', 'chat-media')) = 7, 'a bucket is missing');

  -- The ceilings the app enforces (maxChatFileBytes = 50 MiB) are allowed.
  perform pg_temp.expect((select file_size_limit from storage.buckets where id = 'chat-files') = 50 * 1024 * 1024, 'chat-files: limit is not 50 MiB');
  perform pg_temp.expect((select file_size_limit from storage.buckets where id = 'chat-images') >= 50 * 1024 * 1024, 'chat-images: smaller than the 50 MiB the tray allows');
  perform pg_temp.expect((select file_size_limit from storage.buckets where id = 'voice-messages') >= 50 * 1024 * 1024, 'voice-messages: smaller than 50 MiB');
  perform pg_temp.expect((select file_size_limit from storage.buckets where id = 'profile-avatars') = 20 * 1024 * 1024, 'profile-avatars: limit is not 20 MiB');
  perform pg_temp.expect((select file_size_limit from storage.buckets where id = 'profile-banners') = 20 * 1024 * 1024, 'profile-banners: limit is not 20 MiB');
  -- And nothing is unbounded above 50 MiB (the project's global limit).
  perform pg_temp.expect((select max(file_size_limit) from storage.buckets where id in
    ('chat-images', 'chat-files', 'voice-messages', 'profile-avatars', 'profile-banners', 'group-avatars', 'chat-media')) <= 50 * 1024 * 1024, 'a bucket allows more than 50 MiB');

  -- chat-files takes any type (files, videos, SVG, unknown).
  perform pg_temp.expect((select allowed_mime_types is null from storage.buckets where id = 'chat-files'), 'chat-files: has a type list');

  -- Pictures: every type the app sends to a picture bucket.
  select allowed_mime_types into picture from storage.buckets where id = 'chat-images';
  perform pg_temp.expect(picture @> array['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/heic', 'image/heif', 'image/avif', 'image/bmp'], 'chat-images: lacks a picture type the app sends');
  perform pg_temp.expect(not picture && array['image/svg+xml', 'text/html', 'application/octet-stream', 'video/mp4', 'application/pdf'], 'chat-images: takes a type that is not a picture the app sends');
  perform pg_temp.expect((select allowed_mime_types from storage.buckets where id = 'chat-media') = picture, 'chat-media differs from chat-images');
  for b in select id, allowed_mime_types a from storage.buckets where id in ('profile-avatars', 'profile-banners', 'group-avatars') loop
    perform pg_temp.expect(b.a @> array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic', 'image/heif'], format('%s: lacks a picture type', b.id));
    perform pg_temp.expect(not b.a && array['image/svg+xml', 'text/html', 'application/octet-stream', 'video/mp4'], format('%s: takes a type that is not a picture', b.id));
  end loop;

  -- Voice: the recorder writes WAV; the player also knows the others.
  select allowed_mime_types into voice from storage.buckets where id = 'voice-messages';
  perform pg_temp.expect(voice @> array['audio/wav', 'audio/mpeg', 'audio/mp4', 'audio/ogg', 'audio/webm', 'audio/aac'], 'voice-messages: lacks an audio type');
  perform pg_temp.expect(not voice && array['image/jpeg', 'video/mp4', 'text/html', 'application/octet-stream'], 'voice-messages: takes a type that is not audio');

  -- Buckets other migrations limit are left as they were.
  perform pg_temp.expect((select file_size_limit from storage.buckets where id = 'moments') = 52428800, 'moments: limit changed');
  perform pg_temp.expect((select file_size_limit from storage.buckets where id = 'circle-emojis') = 262144, 'circle-emojis: limit changed');
end $$;

\o
select pg_temp.root();
select msg as "REALTIME / STORAGE DEFENCE MISSING" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'realtime private: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
