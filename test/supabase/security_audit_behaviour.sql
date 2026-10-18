-- Attack tests for the database changes of 2026-10-17 and 2026-10-18
-- (migrations 20261017* and 20261018*) and their fixes (20261019*). Run by
-- test/supabase/security_audit_test.dart against the local database inside a
-- transaction that is rolled back. Run from the repository root.
--
-- The script plays a signed-in person who talks to the REST/RPC API with
-- their own token: `set local role authenticated` plus the JWT claims. Each
-- attack must fail; a failed defence is recorded and listed at the end.
--
-- The local database may lack recent migrations, so the script rebuilds the
-- public schema from ALL migrations, in order, inside the transaction (and
-- throws it away at the end). With `-v apply_fixes=0` the fix migrations
-- (202610190010 and later) are left out, which shows the attacks working.
\set ON_ERROR_STOP on
\if :{?apply_fixes}
\else
  \set apply_fixes 1
\endif

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

\if :apply_fixes
\i supabase/migrations/202610190010_security_attachment_paths.sql
\i supabase/migrations/202610190011_security_hidden_messages.sql
\i supabase/migrations/202610190012_security_chains.sql
\i supabase/migrations/202610190013_security_deleted_content.sql
\endif
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

-- How many rows [query] returns, as the current role.
create function pg_temp.cnt(query text) returns integer language plpgsql as $$
declare n integer;
begin
  execute format('select count(*) from (%s) q', query) into n;
  return n;
end $$;

-- Whether running [statement] as the current role raises an error.
create function pg_temp.refused(statement text) returns boolean language plpgsql as $$
begin
  execute statement;
  return false;
exception when others then
  return true;
end $$;

-- Whether [statement] runs and changes or returns at least one row.
create function pg_temp.rows_changed(statement text) returns integer language plpgsql as $$
declare n integer;
begin
  execute statement;
  get diagnostics n = row_count;
  return n;
exception when others then
  return 0;
end $$;

-- The text result of [query] (first column of first row), or 'ERR: ...'.
create function pg_temp.val(query text) returns text language plpgsql as $$
declare r text;
begin
  execute query into r;
  return r;
exception when others then
  return 'ERR: ' || sqlerrm;
end $$;

grant execute on all functions in schema pg_temp to public;

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create function pg_temp.i(n text) returns uuid language sql as $$ select id from pg_temp.ids where name = n $$;
grant execute on function pg_temp.i(text) to public;

-- ------------------------------------------------------------------ cast
-- Ada owns everything. Bob and Dee are in her group and circle (Dee just
-- joined, so the AI guard holds her text). Cy knows nobody. Eve is blocked
-- by Ada. Fay left the group after having seen its pictures.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '@sec.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee'),('e1','eve'),('f1','fay'),('a2','gus')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '_sec', initcap(name)
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee'),('e1','eve'),('f1','fay'),('a2','gus')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || n)::uuid
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee'),('e1','eve'),('f1','fay'),('a2','gus')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(x.a, x.b), greatest(x.a, x.b)
from (values
  (pg_temp.i('ada'), pg_temp.i('bob')),
  (pg_temp.i('ada'), pg_temp.i('dee')),
  (pg_temp.i('ada'), pg_temp.i('fay')),
  (pg_temp.i('ada'), pg_temp.i('eve')),
  (pg_temp.i('bob'), pg_temp.i('eve'))
) x(a, b);

-- The group (Ada, Bob, Dee, Fay) and the direct chat of Ada and Bob.
insert into pg_temp.ids select 'group', gen_random_uuid();
insert into pg_temp.ids select 'direct', gen_random_uuid();
insert into public.conversations (id, type, title)
values (pg_temp.i('group'), 'group', 'Secret group'), (pg_temp.i('direct'), 'direct', null);
insert into public.conversation_members (conversation_id, user_id, role)
values
  (pg_temp.i('group'), pg_temp.i('ada'), 'owner'),
  (pg_temp.i('group'), pg_temp.i('bob'), 'member'),
  (pg_temp.i('group'), pg_temp.i('dee'), 'member'),
  (pg_temp.i('group'), pg_temp.i('fay'), 'member'),
  (pg_temp.i('direct'), pg_temp.i('ada'), 'member'),
  (pg_temp.i('direct'), pg_temp.i('bob'), 'member');

-- Ada's circle with Bob and Dee, the AI guard on.
select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'circle', public.create_circle('Sec circle', array[pg_temp.i('bob'), pg_temp.i('dee')]);
select pg_temp.root();
insert into pg_temp.ids
select 'channel', cc.conversation_id from public.circle_channels cc
where cc.circle_id = pg_temp.i('circle') order by cc.position limit 1;
update public.circles set ai_enabled = true where id = pg_temp.i('circle');
insert into public.circle_ai_guard (circle_id, enabled, new_rule, joined_days, message_count, action)
values (pg_temp.i('circle'), true, 'joined_days', 7, 5, 'hold');
-- Ada and Bob joined long ago; Dee is new.
update public.circle_members set created_at = now() - interval '60 days'
where circle_id = pg_temp.i('circle') and user_id in (pg_temp.i('ada'), pg_temp.i('bob'));

-- Gus is in the circle without being anybody's friend.
insert into public.circle_members (circle_id, user_id, role, created_at)
values (pg_temp.i('circle'), pg_temp.i('gus'), 'member', now() - interval '60 days');
insert into public.conversation_members (conversation_id, user_id, role)
select cc.conversation_id, pg_temp.i('gus'), 'member' from public.circle_channels cc
where cc.circle_id = pg_temp.i('circle') on conflict do nothing;

-- Ada's profile is for friends only and has a bio, a banner and pronouns.
update public.profiles set bio = 'ada secret bio', banner_url = 'banners/ada.png', pronouns = 'she/her'
where id = pg_temp.i('ada');
insert into public.user_privacy_settings (user_id, profile_visibility)
values (pg_temp.i('ada'), 'friends')
on conflict (user_id) do update set profile_visibility = 'friends';

-- Blocks: Ada blocked Eve.
select pg_temp.act(pg_temp.i('ada'));
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('ada'), pg_temp.i('eve'));
select pg_temp.root();

-- --------------------------------------------------------------- content
-- Messages are stored by the owner role (triggers still run).
insert into pg_temp.ids select 'm_text', gen_random_uuid();
insert into pg_temp.ids select 'm_img', gen_random_uuid();
insert into pg_temp.ids select 'm_vo', gen_random_uuid();
insert into pg_temp.ids select 'm_exp', gen_random_uuid();
insert into pg_temp.ids select 'm_exp_img', gen_random_uuid();
insert into pg_temp.ids select 'm_held', gen_random_uuid();
insert into pg_temp.ids select 'm_direct', gen_random_uuid();

insert into public.messages (id, conversation_id, sender_id, type, body, attachment)
values
  (pg_temp.i('m_text'), pg_temp.i('group'), pg_temp.i('ada'), 'text', 'group secret text', null),
  (pg_temp.i('m_img'), pg_temp.i('group'), pg_temp.i('ada'), 'image', '',
    jsonb_build_object('bucket', 'chat-images', 'path', pg_temp.i('group') || '/pic1.png', 'mime_type', 'image/png', 'size', 10)),
  (pg_temp.i('m_vo'), pg_temp.i('group'), pg_temp.i('ada'), 'image', '',
    jsonb_build_object('bucket', 'chat-images', 'path', pg_temp.i('group') || '/vo1.png', 'mime_type', 'image/png', 'size', 10, 'view_once', true)),
  (pg_temp.i('m_exp'), pg_temp.i('group'), pg_temp.i('ada'), 'text', 'expired secret text', null),
  (pg_temp.i('m_exp_img'), pg_temp.i('group'), pg_temp.i('ada'), 'image', '',
    jsonb_build_object('bucket', 'chat-images', 'path', pg_temp.i('group') || '/gone.png', 'mime_type', 'image/png', 'size', 10)),
  (pg_temp.i('m_direct'), pg_temp.i('direct'), pg_temp.i('ada'), 'text', 'direct secret text', null);
update public.messages set expires_at = now() - interval '5 minutes'
where id in (pg_temp.i('m_exp'), pg_temp.i('m_exp_img'));

-- Dee, new in the circle, writes in its channel; the guard (no Edge
-- Function here) lets it pass, so the message is put on hold by hand.
insert into public.messages (id, conversation_id, sender_id, type, body)
values (pg_temp.i('m_held'), pg_temp.i('channel'), pg_temp.i('dee'), 'text', 'held secret text');
update public.messages set review_state = 'held' where id = pg_temp.i('m_held');
update public.message_reviews set state = 'held', verdict = 'spam' where message_id = pg_temp.i('m_held');
insert into public.message_reviews (message_id, circle_id, conversation_id, sender_id, mode, state, verdict)
select pg_temp.i('m_held'), pg_temp.i('circle'), pg_temp.i('channel'), pg_temp.i('dee'), 'hold', 'held', 'spam'
where not exists (select 1 from public.message_reviews where message_id = pg_temp.i('m_held'));

-- The files behind the pictures (the real ones are made by Storage).
insert into storage.objects (bucket_id, name, owner_id, metadata)
select 'chat-images', n, null, '{}'::jsonb
from (values
  (pg_temp.i('group') || '/pic1.png'),
  (pg_temp.i('group') || '/vo1.png'),
  (pg_temp.i('group') || '/gone.png'),
  (pg_temp.i('direct') || '/direct1.png')
) v(n);

-- Features, made the way the app makes them.
select pg_temp.act(pg_temp.i('ada'));

-- A note and a task list in the group; a deleted note.
insert into pg_temp.ids select 'note', (public.create_note(pg_temp.i('group'), 'Secret note', null, null)->>'id')::uuid;
select public.note_apply_ops(pg_temp.i('note'), jsonb_build_array(jsonb_build_object(
  'op', 'put', 'id', gen_random_uuid(), 'base_rev', null, 'pos', 'W', 'kind', 'paragraph',
  'text', 'note secret text', 'marks', '[]'::jsonb, 'props', '{}'::jsonb)));
insert into pg_temp.ids select 'note_deleted', (public.create_note(pg_temp.i('group'), 'Deleted note', null, null)->>'id')::uuid;
select public.note_apply_ops(pg_temp.i('note_deleted'), jsonb_build_array(jsonb_build_object(
  'op', 'put', 'id', gen_random_uuid(), 'base_rev', null, 'pos', 'W', 'kind', 'paragraph',
  'text', 'deleted note secret', 'marks', '[]'::jsonb, 'props', '{}'::jsonb)));
select public.delete_note(pg_temp.i('note_deleted'));
insert into pg_temp.ids select 'tasks', (public.create_task_list(pg_temp.i('group'), 'Secret tasks', null, null, null, 'list')->>'id')::uuid;
select public.upsert_task_item(pg_temp.i('tasks'), jsonb_build_object('id', gen_random_uuid(), 'title', 'task secret title'));

-- A chain in the group.
insert into pg_temp.ids select 'chain', (public.create_chain(pg_temp.i('group'), 'chain secret title', 'chain secret description', null, null, null)->>'chain_id')::uuid;

-- Live location in the group, a location card, a contact card.
insert into pg_temp.ids select 'share', share_id from public.start_live_location(pg_temp.i('group'), 60, true);
select public.send_location(pg_temp.i('group'), 52.5, 13.4, 'secret place', null);

-- A merged forward of three group messages into the direct chat with Bob.
insert into pg_temp.ids select 'bundle_msg', public.forward_messages_merged(array[pg_temp.i('m_text'), pg_temp.i('m_img')], pg_temp.i('direct'), 'Bundle');

-- A moment, a wallpaper, a call link, QR codes, a pat, a reminder, a save.
insert into pg_temp.ids select 'moment', gen_random_uuid();
select public.create_moment(pg_temp.i('moment'), 'moment secret text', '[]'::jsonb, null, null, null, 'friends', null, null);
select public.set_chat_wallpaper(pg_temp.i('group'), 'preset', 'dusk', null, 0.4, false, 0.5, 0.5);
select public.create_call_link(pg_temp.i('group'), null, 'week');
select public.get_my_qr_code();
select public.get_group_qr(pg_temp.i('group'), false);
select public.pat_user(pg_temp.i('group'), pg_temp.i('bob'));
select public.set_my_pat_suffix('secret suffix');
select public.save_message(pg_temp.i('m_text'));
select public.set_message_reminder(pg_temp.i('m_text'), now() + interval '1 day');
select public.register_device('Ada phone', 'ios', '1.0');
select public.create_chat_event(pg_temp.i('group'), 'event secret title', now() + interval '1 day', null, 'event secret description', null, null, null, false);
select public.create_poll(pg_temp.i('group'), 'poll secret question', array['yes','no'], false, null, null, null, true, false, null);
select pg_temp.root();

-- =========================================================== 1. outsiders
-- Cy knows nobody and is in no chat: no table may show him anything of the
-- others' (profiles and link previews are public by design; every
-- discovery listing needs a public circle).
do $$
declare
  t record;
  n integer;
  attacker text;
begin
  foreach attacker in array array['cy', 'eve'] loop
    perform pg_temp.act(pg_temp.i(attacker));
    for t in
      select c.relname
      from pg_class c
      where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
        and has_table_privilege('authenticated', c.oid, 'select')
        and c.relname not in ('profiles', 'link_previews', 'user_privacy_settings')
        and not (attacker = 'eve' and c.relname in ('friendships', 'friend_requests'))
      order by 1
    loop
      begin
        n := pg_temp.cnt(format('select 1 from public.%I', t.relname));
      exception when others then
        n := 0;
      end;
      perform pg_temp.expect(n = 0, format('%s reads %s rows of public.%s', attacker, n, t.relname));
    end loop;
  end loop;
end $$;

-- Columns granted one by one: profiles. Hidden fields are not readable.
do $$
begin
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(pg_temp.refused('select bio from public.profiles'), 'profiles.bio is readable');
  perform pg_temp.expect(pg_temp.refused('select banner_url from public.profiles'), 'profiles.banner_url is readable');
  perform pg_temp.expect(pg_temp.refused('select pronouns from public.profiles'), 'profiles.pronouns is readable');
  perform pg_temp.expect(pg_temp.refused('select audience from public.moments_posts'), 'moments_posts.audience is readable');
  perform pg_temp.expect(pg_temp.refused('select * from public.profiles'), 'select * on profiles works (a column that should be hidden is granted)');
  perform pg_temp.expect(pg_temp.refused('select * from public.moments_posts'), 'select * on moments_posts works');
end $$;

-- ================================================== 2. outsiders via RPC
-- Cy calls every reading function with the ids of Ada's group. Each must
-- refuse or return nothing.
create function pg_temp.leak(label text, q text) returns void language plpgsql as $$
declare r text;
begin
  begin
    execute 'select (' || q || ')::text' into r;
  exception when others then
    return;
  end;
  if r is not null and r not in ('[]', '{}', '', 'false', '0') then
    insert into pg_temp.failures values (label || ' returned: ' || left(r, 80));
  end if;
end $$;
create function pg_temp.leak_rows(label text, q text) returns void language plpgsql as $$
declare n integer;
begin
  begin
    execute format('select count(*) from (%s) x', q) into n;
  exception when others then
    return;
  end;
  if n > 0 then
    insert into pg_temp.failures values (label || ' returned ' || n || ' rows');
  end if;
end $$;
grant execute on function pg_temp.leak(text, text), pg_temp.leak_rows(text, text) to public;

do $$
declare
  g text := pg_temp.i('group')::text;
begin
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.leak('outsider get_note', format('public.get_note(%L)', pg_temp.i('note')));
  perform pg_temp.leak_rows('outsider list_notes', format('select * from public.list_notes(%L)', g));
  perform pg_temp.leak('outsider get_pinned_note', format('public.get_pinned_note(%L)', g));
  perform pg_temp.leak('outsider get_task_list', format('public.get_task_list(%L)', pg_temp.i('tasks')));
  perform pg_temp.leak_rows('outsider list_task_lists', format('select * from public.list_task_lists(%L)', g));
  perform pg_temp.leak('outsider get_conversation_workspace', format('public.get_conversation_workspace(%L)', g));
  perform pg_temp.leak('outsider get_chain', format('public.get_chain(%L)', pg_temp.i('chain')));
  perform pg_temp.leak_rows('outsider list_live_location_shares', format('select * from public.list_live_location_shares(%L)', g));
  perform pg_temp.leak_rows('outsider list_chat_events', format('select * from public.list_chat_events(%L, true)', g));
  perform pg_temp.leak_rows('outsider list_conversation_media', format('select * from public.list_conversation_media(%L)', g));
  perform pg_temp.leak_rows('outsider list_pinned_messages', format('select * from public.list_pinned_messages(%L)', g));
  perform pg_temp.leak('outsider search_message_context', format('(public.search_message_context(%L, 5, 5)->''before'') || (public.search_message_context(%L, 5, 5)->''after'')', pg_temp.i('m_img'), pg_temp.i('m_img')));
  perform pg_temp.leak('outsider search_messages', $q$public.search_messages('secret', '{}'::jsonb, '{"type":"everywhere"}'::jsonb, 'newest', 20, null)->'results'$q$);
  perform pg_temp.leak('outsider forward_message', format('public.forward_message(%L, %L)', pg_temp.i('m_text'), g));
  perform pg_temp.leak('outsider forward_messages_merged', format('public.forward_messages_merged(array[%L::uuid], %L, null)', pg_temp.i('m_text'), g));
  perform pg_temp.leak('outsider create_task_from_message', format('public.create_task_from_message(%L, null, null, null)', pg_temp.i('m_text')));
  perform pg_temp.leak('outsider save_message', format('public.save_message(%L)', pg_temp.i('m_text')));
  perform pg_temp.leak('outsider set_message_reminder', format('public.set_message_reminder(%L, now() + interval ''1 day'')', pg_temp.i('m_text')));
  perform pg_temp.leak('outsider pin_message', format('public.pin_message(%L)', pg_temp.i('m_text')));
  perform pg_temp.leak('outsider toggle_message_reaction', format('public.toggle_message_reaction(%L, ''x'')', pg_temp.i('m_text')));
  perform pg_temp.leak_rows('outsider list_message_reactors', format('select * from public.list_message_reactors(%L, ''x'')', pg_temp.i('m_text')));
  perform pg_temp.leak('outsider open_view_once', format('public.open_view_once(%L)', pg_temp.i('m_vo')));
  perform pg_temp.leak('outsider pat_user', format('public.pat_user(%L, %L)', g, pg_temp.i('bob')));
  perform pg_temp.leak('outsider send_contact_card', format('public.send_contact_card(%L, ''user'', %L)', g, pg_temp.i('bob')));
  perform pg_temp.leak('outsider send_location', format('public.send_location(%L, 1, 1, ''x'', null)', g));
  perform pg_temp.leak('outsider join_chain', format('public.join_chain(%L, ''hi'')', pg_temp.i('chain')));
  perform pg_temp.leak('outsider create_chain', format('public.create_chain(%L, ''t'', null, null, null, null)', g));
  perform pg_temp.leak('outsider start_live_location', format('(select count(*) from public.start_live_location(%L, 5, false))', g));
  perform pg_temp.leak('outsider share_note', format('public.share_note(%L, %L)', pg_temp.i('note'), g));
  perform pg_temp.leak('outsider note_apply_ops', format('public.note_apply_ops(%L, ''[]''::jsonb)', pg_temp.i('note')));
  perform pg_temp.leak('outsider create_note', format('public.create_note(%L, ''x'', null, null)', g));
  perform pg_temp.leak('outsider list_note_versions', format('(select count(*) from public.list_note_versions(%L))', pg_temp.i('note')));
  perform pg_temp.leak('outsider set_chat_wallpaper', format('public.set_chat_wallpaper(%L, ''preset'', ''dusk'', null, 0.4, false, 0.5, 0.5)', g));
  perform pg_temp.leak('outsider create_call_link', format('public.create_call_link(%L, null, ''week'')', g));
  perform pg_temp.leak('outsider set_disappearing', format('public.set_disappearing_messages(%L, 86400)', g));
  perform pg_temp.leak('outsider get_group_qr', format('public.get_group_qr(%L, true)', g));
  perform pg_temp.leak('outsider create_chat_event', format('public.create_chat_event(%L, ''e'', now() + interval ''1 day'', null, null, null, null, null, false)', g));
  perform pg_temp.leak('outsider create_poll', format('public.create_poll(%L, ''q'', array[''a'',''b''], false, null, null, null, false, false, null)', g));
  perform pg_temp.leak('outsider send_text_message', format('public.send_text_message(%L, ''hi'')', g));
  perform pg_temp.leak('outsider list_poll_voters', format('(select count(*) from public.list_poll_voters(%L, ''o1''))', pg_temp.i('m_text')));
  perform pg_temp.leak('outsider moments_feed', 'coalesce((select count(*) from public.moments_feed(50, null, null, null, null)), 0)');
  perform pg_temp.leak('outsider get_moments_profile', format('(select count(*) from public.get_moments_profile(%L))', pg_temp.i('ada')));
  -- Direct inserts.
  perform pg_temp.expect(pg_temp.refused(format('insert into public.messages (conversation_id, sender_id, type, body) values (%L, %L, ''text'', ''hi'')', g, pg_temp.i('cy'))), 'outsider inserts a message into the group');
  perform pg_temp.expect(pg_temp.refused(format('insert into public.conversation_members (conversation_id, user_id) values (%L, %L)', g, pg_temp.i('cy'))), 'outsider adds himself to the group');
  perform pg_temp.expect(pg_temp.refused(format('insert into public.message_reactions (message_id, user_id, emoji, conversation_id) values (%L, %L, ''x'', %L)', pg_temp.i('m_text'), pg_temp.i('cy'), g)), 'outsider reacts');
  perform pg_temp.expect(pg_temp.rows_changed(format('update public.messages set body = ''pwned'' where id = %L', pg_temp.i('m_text'))) = 0, 'outsider updates a message');
  perform pg_temp.expect(pg_temp.rows_changed(format('delete from public.messages where id = %L', pg_temp.i('m_text'))) = 0, 'outsider deletes a message');
  perform pg_temp.expect(pg_temp.rows_changed(format('update public.conversations set title = ''pwned'' where id = %L', g)) = 0, 'outsider renames the group');
  perform pg_temp.expect(pg_temp.rows_changed(format('update public.notes set title = ''pwned'' where id = %L', pg_temp.i('note'))) = 0, 'outsider edits a note');
  perform pg_temp.expect(pg_temp.rows_changed(format('update public.chains set title = ''pwned'' where id = %L', pg_temp.i('chain'))) = 0, 'outsider edits a chain');
  perform pg_temp.root();
end $$;

-- Writes: Cy has no data of his own anywhere, so no statement of his may
-- touch a single row of any table he is granted to change.
do $$
declare t record; col text; n integer;
begin
  perform pg_temp.act(pg_temp.i('cy'));
  for t in
    select c.relname, c.oid
    from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
      and (has_table_privilege('authenticated', c.oid, 'delete') or has_table_privilege('authenticated', c.oid, 'update'))
      and c.relname <> 'profiles'
    order by 1
  loop
    if has_table_privilege('authenticated', t.oid, 'delete') then
      n := pg_temp.rows_changed(format('delete from public.%I', t.relname));
      perform pg_temp.expect(n = 0, format('outsider deletes %s rows of public.%s', n, t.relname));
    end if;
    if has_table_privilege('authenticated', t.oid, 'update') then
      select a.attname into col from pg_attribute a
      where a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped
        and has_column_privilege('authenticated', t.oid, a.attnum, 'update')
      order by a.attnum limit 1;
      if col is not null then
        n := pg_temp.rows_changed(format('update public.%I set %I = %I', t.relname, col, col));
        perform pg_temp.expect(n = 0, format('outsider updates %s rows of public.%s', n, t.relname));
      end if;
    end if;
  end loop;
  perform pg_temp.expect(pg_temp.rows_changed(format('update public.profiles set display_name = ''pwned'' where id = %L', pg_temp.i('ada'))) = 0, 'outsider renames Ada');
  perform pg_temp.root();
end $$;

-- ============================================= 3. held and expired messages
-- Bob is an ordinary member. Dee's text in the channel waits for the AI guard
-- (held); Ada's m_exp / m_exp_img have run out but the purge has not run yet
-- (it runs every minute, and not at all when pg_cron is missing).
select pg_temp.root();
update public.conversations set last_message_id = null, last_message_at = now() - interval '1 hour'
where id = pg_temp.i('channel');
-- Dee's chain in the channel, its card held.
select pg_temp.act(pg_temp.i('dee'));
insert into pg_temp.ids select 'chain_held', (public.create_chain(pg_temp.i('channel'), 'held chain title', 'held chain description', null, null, null)->>'chain_id')::uuid;
select pg_temp.root();
update public.messages set review_state = 'held'
where id = (select message_id from public.chains where id = pg_temp.i('chain_held'));
update public.message_reviews set state = 'held', verdict = 'spam'
where message_id = (select message_id from public.chains where id = pg_temp.i('chain_held'));
update public.conversations set last_message_id = null where id = pg_temp.i('channel');

do $$
declare
  bob uuid := pg_temp.i('bob');
  held uuid := pg_temp.i('m_held');
  gone uuid := pg_temp.i('m_exp');
begin
  perform pg_temp.act(bob);
  -- Held text.
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.messages where id = %L', held)) = 0, 'held: member reads the message row');
  perform pg_temp.leak('held: create_task_from_message copies it', format('public.create_task_from_message(%L, null, null, null)', held));
  perform pg_temp.leak('held: forward_message', format('public.forward_message(%L, %L)', held, pg_temp.i('group')));
  perform pg_temp.leak('held: save_message', format('public.save_message(%L)', held));
  perform pg_temp.leak('held: set_message_reminder', format('public.set_message_reminder(%L, now() + interval ''1 day'')', held));
  perform pg_temp.leak('held: toggle_message_reaction', format('public.toggle_message_reaction(%L, ''x'')', held));
  perform pg_temp.leak('held: pin_message', format('public.pin_message(%L)', held));
  perform pg_temp.leak('held: search_message_context', format('(public.search_message_context(%L, 5, 5)->''before'')', held));
  perform pg_temp.leak('held: search', $q$public.search_messages('held secret', '{}'::jsonb, '{"type":"everywhere"}'::jsonb, 'newest', 20, null)->'results'$q$);
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.message_reviews') = 0, 'held: member reads message_reviews');
  -- Its chain card.
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.chains where id = %L', pg_temp.i('chain_held'))) = 0,
    'held: member reads the chain whose card waits for review (title, description)');
  perform pg_temp.leak('held: get_chain of a held card', format('public.get_chain(%L)', pg_temp.i('chain_held')));
  perform pg_temp.leak('held: join_chain of a held card', format('public.join_chain(%L, ''me'')', pg_temp.i('chain_held')));
  -- Expired text.
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.messages where id = %L', gone)) = 0, 'expired: member reads the message row');
  perform pg_temp.leak('expired: forward_message copies it', format('public.forward_message(%L, %L)', gone, pg_temp.i('group')));
  perform pg_temp.leak('expired: create_task_from_message copies it', format('public.create_task_from_message(%L, null, null, null)', gone));
  perform pg_temp.leak('expired: search finds it', $q$public.search_messages('expired secret', '{}'::jsonb, '{"type":"everywhere"}'::jsonb, 'newest', 20, null)->'results'$q$);
  perform pg_temp.leak('expired: search_message_context', format('(public.search_message_context(%L, 5, 5)->''before'') || (public.search_message_context(%L, 5, 5)->''after'')', gone, gone));
  perform pg_temp.leak('expired: save_message', format('public.save_message(%L)', gone));
  perform pg_temp.leak('expired: set_message_reminder', format('public.set_message_reminder(%L, now() + interval ''1 day'')', gone));
  perform pg_temp.root();
end $$;

-- The chat list shows the latest message: held and expired ones must not be it.
update public.conversations set last_message_id = pg_temp.i('m_exp'), last_message_at = now() where id = pg_temp.i('group');
update public.conversations set last_message_id = pg_temp.i('m_held'), last_message_at = now() where id = pg_temp.i('channel');
do $$
begin
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(
    (select count(*) from public.list_conversation_summaries() s
     where s.last_message_body in ('expired secret text', 'held secret text')) = 0,
    'chat list: the latest message shown is an expired or held one');
  perform pg_temp.root();
end $$;

-- A thread may not be started on a message the member cannot read.
do $$
declare r text;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  r := pg_temp.val(format('select public.create_thread(%L, %L, null)::text', pg_temp.i('channel'), pg_temp.i('m_held')));
  perform pg_temp.expect(r like 'ERR:%' or r not like '%held secret%', 'held: create_thread shows the held text: ' || left(r, 80));
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.conversation_threads where title like '%held secret%'), 'held: thread titled with the held text');
  perform pg_temp.act(pg_temp.i('bob'));
  r := pg_temp.val(format('select public.create_thread(%L, %L, null)::text', pg_temp.i('group'), pg_temp.i('m_exp')));
  perform pg_temp.expect(r like 'ERR:%' or r not like '%expired secret%', 'expired: create_thread shows the expired text: ' || left(r, 80));
  perform pg_temp.root();
end $$;

-- =============================================== 4. files and view-once media
create function pg_temp.reads(bucket text, object text) returns boolean language plpgsql as $$
begin
  return pg_temp.cnt(format('select 1 from storage.objects where bucket_id = %L and name = %L', bucket, object)) = 1;
end $$;
grant execute on function pg_temp.reads(text, text) to public;

select pg_temp.root();
-- Fay's own group with Bob; Fay left Ada's group but remembers its file paths.
insert into pg_temp.ids select 'fay_group', gen_random_uuid();
insert into public.conversations (id, type, title) values (pg_temp.i('fay_group'), 'group', 'Fay and Bob');
insert into public.conversation_members (conversation_id, user_id, role)
values (pg_temp.i('fay_group'), pg_temp.i('fay'), 'owner'), (pg_temp.i('fay_group'), pg_temp.i('bob'), 'member');
delete from public.conversation_members where conversation_id = pg_temp.i('group') and user_id = pg_temp.i('fay');

do $$
declare
  fay uuid := pg_temp.i('fay');
  pic text := pg_temp.i('group') || '/pic1.png';
  forged uuid := gen_random_uuid();
  copy_id uuid;
begin
  perform pg_temp.act(fay);
  perform pg_temp.expect(not pg_temp.reads('chat-images', pic), 'ex-member reads the group picture straight away');
  -- 1. A message of her own that points to the picture, then forwarded.
  begin
    insert into public.messages (id, conversation_id, sender_id, type, body, attachment)
    values (forged, pg_temp.i('fay_group'), fay, 'image', '',
      jsonb_build_object('bucket', 'chat-images', 'path', pic, 'mime_type', 'image/png', 'size', 10));
    copy_id := public.forward_message(forged, pg_temp.i('fay_group'));
  exception when others then null;
  end;
  perform pg_temp.expect(not pg_temp.reads('chat-images', pic),
    'ex-member regains the group picture: forged attachment path + forward_message');
  -- 2. The same through merged forward.
  begin
    perform public.forward_messages_merged(array[forged], pg_temp.i('fay_group'), 'x');
  exception when others then null;
  end;
  perform pg_temp.expect(not pg_temp.reads('chat-images', pic),
    'ex-member regains the group picture: forged attachment path + forward_messages_merged');
  -- Not even a plain message with the path gives the file.
  perform pg_temp.root();
end $$;

-- A member breaks the others' view of a picture by posting a "view once"
-- message that names its path (the restriction is looked up by path).
do $$
declare bob uuid := pg_temp.i('bob'); pic text := pg_temp.i('group') || '/pic1.png';
begin
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.reads('chat-images', pic), 'setup: Ada reads her picture');
  perform pg_temp.act(bob);
  begin
    insert into public.messages (conversation_id, sender_id, type, body, attachment)
    values (pg_temp.i('group'), bob, 'image', '',
      jsonb_build_object('bucket', 'chat-images', 'path', pic, 'mime_type', 'image/png', 'size', 10, 'view_once', true));
  exception when others then null;
  end;
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.reads('chat-images', pic), 'a member locks the others out of a picture with a fake view-once message');
  perform pg_temp.root();
end $$;

-- View-once as it should work.
do $$
declare
  vo text := pg_temp.i('group') || '/vo1.png';
  opened jsonb;
begin
  perform pg_temp.root();
  delete from public.messages where attachment->>'view_once' = 'true' and sender_id = pg_temp.i('bob');
  perform pg_temp.act(pg_temp.i('dee'));
  perform pg_temp.expect(not pg_temp.reads('chat-images', vo), 'view once: a recipient reads the file before opening');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(not pg_temp.reads('chat-images', vo), 'view once: Bob reads the file before opening');
  perform pg_temp.expect(pg_temp.refused(format('select public.forward_message(%L, %L)', pg_temp.i('m_vo'), pg_temp.i('direct'))), 'view once: forwarded');
  perform pg_temp.expect(pg_temp.refused(format('select public.forward_messages_merged(array[%L::uuid], %L, null)', pg_temp.i('m_vo'), pg_temp.i('direct'))), 'view once: merged forward');
  perform pg_temp.expect(pg_temp.refused(format('select public.open_view_once(%L)', pg_temp.i('m_vo')))= false, 'setup: Bob can open');
  perform pg_temp.expect(pg_temp.reads('chat-images', vo), 'view once: Bob cannot read right after opening');
  perform pg_temp.expect(pg_temp.refused(format('select public.open_view_once(%L)', pg_temp.i('m_vo'))), 'view once: opened twice');
  perform pg_temp.act(pg_temp.i('dee'));
  perform pg_temp.expect(not pg_temp.reads('chat-images', vo), 'view once: Bob opening it opens it for Dee');
  perform pg_temp.root();
  update public.message_view_once_opens set opened_at = now() - interval '3 minutes';
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(not pg_temp.reads('chat-images', vo), 'view once: readable more than two minutes after opening');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.reads('chat-images', vo), 'view once: the sender cannot read her own file');
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(not pg_temp.reads('chat-images', vo), 'view once: outsider reads the file');
  perform pg_temp.root();
end $$;

-- ====================================================== 5. storage buckets
select pg_temp.root();
insert into storage.objects (bucket_id, name, owner_id, metadata)
select b, n, null, '{}'::jsonb from (values
  ('chat-files', pg_temp.i('group') || '/f1.pdf'),
  ('voice-messages', pg_temp.i('group') || '/v1.m4a'),
  ('group-avatars', pg_temp.i('group') || '/a.png'),
  ('profile-avatars', pg_temp.i('ada') || '/a.png'),
  ('profile-banners', pg_temp.i('ada') || '/b.png'),
  ('note-files', pg_temp.i('note') || '/n.png'),
  ('wallpapers', pg_temp.i('ada') || '/' || gen_random_uuid() || '.jpg'),
  ('moments', pg_temp.i('ada') || '/' || pg_temp.i('moment') || '-0.jpg'),
  ('moments', pg_temp.i('ada') || '/cover-' || gen_random_uuid() || '.jpg'),
  ('data-exports', pg_temp.i('ada') || '/1.zip'),
  ('circle-emojis', pg_temp.i('circle') || '/' || gen_random_uuid() || '.png'),
  ('circle-sounds', pg_temp.i('circle') || '/' || gen_random_uuid() || '.mp3'),
  ('chat-media', pg_temp.i('circle') || '/m.png'),
  ('file-previews', pg_temp.i('m_text') || '/p.pdf')
) v(b, n);

-- Ada (a member / the owner) must read what is hers: the baseline.
do $$
declare
  o record;
  attacker text;
  readable integer;
begin
  -- Outsider and a member who is not the owner of the folder.
  foreach attacker in array array['cy', 'eve'] loop
    perform pg_temp.root();
    for o in
      select bucket_id, name from storage.objects
      where bucket_id <> 'profile-avatars'
        and not (bucket_id = 'chat-images' and name like pg_temp.i('direct')::text || '/%')
    loop
      perform pg_temp.act(pg_temp.i(attacker));
      perform pg_temp.expect(not pg_temp.reads(o.bucket_id, o.name), format('%s reads %s/%s', attacker, o.bucket_id, o.name));
    end loop;
  end loop;
  perform pg_temp.root();
end $$;

-- Writes by someone who should not: every bucket, other people's folders,
-- path tricks, overwriting and deleting.
do $$
declare
  cy uuid := pg_temp.i('cy');
  bob uuid := pg_temp.i('bob');
  g text := pg_temp.i('group')::text;
  ada text := pg_temp.i('ada')::text;
  b record;
  uu text := gen_random_uuid()::text;
begin
  perform pg_temp.act(cy);
  for b in select * from (values
    ('chat-images', g || '/x.png'), ('chat-files', g || '/x.pdf'), ('voice-messages', g || '/x.m4a'),
    ('group-avatars', g || '/x.png'), ('profile-avatars', ada || '/x.png'), ('profile-banners', ada || '/x.png'),
    ('note-files', pg_temp.i('note') || '/x.png'), ('wallpapers', ada || '/' || uu || '.jpg'),
    ('moments', ada || '/' || uu || '-0.jpg'), ('data-exports', cy || '/x.zip'), ('data-exports', ada || '/x.zip'),
    ('circle-emojis', pg_temp.i('circle') || '/' || uu || '.png'), ('circle-sounds', pg_temp.i('circle') || '/' || uu || '.mp3'),
    ('chat-media', pg_temp.i('circle') || '/x.png'), ('file-previews', pg_temp.i('m_text') || '/x.pdf'),
    ('chat-images', '/' || g || '/x.png'), ('chat-images', g || '//x.png'), ('chat-images', upper(g) || '/x.png'),
    ('chat-images', 'x.png'), ('profile-avatars', 'x.png'),
    ('no-such-bucket', cy || '/x.png')
  ) v(bucket, name)
  loop
    perform pg_temp.expect(
      pg_temp.refused(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', b.bucket, b.name, cy)),
      format('outsider uploads %s/%s', b.bucket, b.name));
  end loop;
  -- Update (overwrite) and delete of anything, as outsider and as a member.
  for b in select unnest(array[cy, bob]) as who loop
    perform pg_temp.act(b.who);
    perform pg_temp.expect(pg_temp.rows_changed('update storage.objects set metadata = ''{"x":1}''::jsonb where bucket_id <> ''wallpapers''') = 0,
      'someone overwrites objects through UPDATE');
  end loop;
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from storage.objects) >= 14, 'objects were deleted through the API');
  -- Bob is a member of the group and a friend of Ada.
  perform pg_temp.act(bob);
  foreach uu in array array['chat-files', 'voice-messages', 'group-avatars'] loop
    perform pg_temp.expect(pg_temp.cnt(format('select 1 from storage.objects where bucket_id = %L', uu)) = 1, 'setup: member reads ' || uu);
  end loop;
  perform pg_temp.expect(pg_temp.refused(format('insert into storage.objects (bucket_id, name, owner_id) values (''group-avatars'', %L, %L)', g || '/new.png', bob)),
    'a plain member sets the group avatar');
  perform pg_temp.expect(pg_temp.cnt('select 1 from storage.objects where bucket_id in (''wallpapers'', ''data-exports'')') = 0, 'a member reads wallpapers or exports of Ada');
  perform pg_temp.expect(pg_temp.cnt('select 1 from storage.objects where bucket_id = ''chat-images'' and name like ''%vo1%''') = 0, 'a member lists the view-once file');
  perform pg_temp.root();
end $$;

-- ====================================================== 6. hidden profile
-- Ada's profile is for friends only. Cy and Gus (same circle, no
-- friendship) must not get her bio, banner or pronouns by any road; Eve
-- (blocked by Ada) neither.
do $$
declare who text; r record; n integer;
begin
  foreach who in array array['cy', 'gus', 'eve'] loop
    perform pg_temp.act(pg_temp.i(who));
    select * into r from public.get_profile_summary(pg_temp.i('ada'));
    perform pg_temp.expect(coalesce(r.bio, '') = '' and r.banner_url is null and r.pronouns is null,
      who || ' reads bio/banner/pronouns from get_profile_summary');
    perform pg_temp.expect(pg_temp.refused('select bio from public.profiles'), who || ' selects profiles.bio');
    perform pg_temp.expect(not pg_temp.reads('profile-banners', pg_temp.i('ada') || '/b.png'), who || ' reads the banner file');
    perform pg_temp.leak(who || ' get_moments_profile', format('(select count(*) from public.get_moments_profile(%L))', pg_temp.i('ada')));
    perform pg_temp.leak(who || ' resolve_user_qr_code gives bio', format('(select bio from (select * from public.get_profile_summary(%L)) x)', pg_temp.i('ada')));
  end loop;
  -- A friend does read them (the baseline).
  perform pg_temp.act(pg_temp.i('bob'));
  select * into r from public.get_profile_summary(pg_temp.i('ada'));
  perform pg_temp.expect(r.bio = 'ada secret bio' and r.pronouns = 'she/her', 'setup: a friend reads the bio');
  perform pg_temp.root();
end $$;

-- Other doors to a profile: voters, reactors, circle members, forum authors.
do $$
declare ada_poll uuid; n integer;
begin
  perform pg_temp.root();
  select id into ada_poll from public.messages where type = 'poll' and conversation_id = pg_temp.i('group') limit 1;
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.vote_poll(ada_poll, array['o1']);
  -- (a not anonymous poll is needed: the one in the fixture is anonymous)
  perform pg_temp.root();
end $$;
do $$
declare r record; leaked boolean := false;
begin
  perform pg_temp.act(pg_temp.i('gus'));
  for r in select * from public.get_circle_detail(pg_temp.i('circle')) loop
    if r::text like '%ada secret bio%' or r::text like '%she/her%' or r::text like '%banners/ada%' then leaked := true; end if;
  end loop;
  perform pg_temp.expect(not leaked, 'get_circle_detail shows the bio or banner of a friends-only profile to a circle member');
  perform pg_temp.root();
end $$;

-- ============================================================= 7. blocked
-- Ada blocked Eve but they are still friends in the table (blocking in the
-- app also unfriends, but nothing here may rely on that).
select pg_temp.root();
insert into pg_temp.ids select 'eve_bob', gen_random_uuid();
insert into public.conversations (id, type) values (pg_temp.i('eve_bob'), 'direct');
insert into public.conversation_members (conversation_id, user_id, role)
values (pg_temp.i('eve_bob'), pg_temp.i('eve'), 'member'), (pg_temp.i('eve_bob'), pg_temp.i('bob'), 'member');

do $$
declare ada_code text; gcode text; r jsonb;
begin
  select code into ada_code from public.user_qr_codes where user_id = pg_temp.i('ada');
  select code into gcode from public.group_qr_codes limit 1;
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.resolve_user_qr_code(%L)', ada_code)) = 0, 'blocked: Eve resolves Ada''s QR code');
  perform pg_temp.leak('blocked: Eve reads Ada''s moments', 'coalesce((select count(*) from public.moments_feed(50, null, null, null, null)), 0)');
  perform pg_temp.leak('blocked: Eve reads Ada''s moments page', format('(select count(*) from public.moments_feed(50, null, null, %L, null))', pg_temp.i('ada')));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.moments_posts') = 0, 'blocked: Eve selects Ada''s moments');
  perform pg_temp.expect(not pg_temp.reads('moments', pg_temp.i('ada') || '/' || pg_temp.i('moment') || '-0.jpg'), 'blocked: Eve reads a moments photo');
  perform pg_temp.leak('blocked: Eve sends Ada''s contact card', format('public.send_contact_card(%L, ''user'', %L)', pg_temp.i('eve_bob'), pg_temp.i('ada')));
  perform pg_temp.leak('blocked: Eve friend request to Ada', format('public.send_friend_request(%L)', pg_temp.i('ada')));
  perform pg_temp.expect(public.join_group_by_qr(gcode)->>'state' = 'not_found', 'blocked: Eve joins Ada''s group by QR');
  perform pg_temp.expect(public.preview_group_qr(gcode)->>'state' = 'not_found', 'blocked: Eve previews Ada''s group QR');
  perform pg_temp.expect(pg_temp.refused(format('insert into public.moments_likes (post_id, user_id) values (%L, %L)', pg_temp.i('moment'), pg_temp.i('eve'))), 'blocked: Eve likes Ada''s moment');
  perform pg_temp.expect(pg_temp.refused(format('insert into public.moments_comments (post_id, author_id, body) values (%L, %L, ''hi'')', pg_temp.i('moment'), pg_temp.i('eve'))), 'blocked: Eve comments on Ada''s moment');
  perform pg_temp.root();
end $$;

-- Ada blocked Bob in the direct chat: Bob cannot write or call there; but
-- also Ada's QR/live location/pat/contact card for him.
do $$
begin
  perform pg_temp.act(pg_temp.i('ada'));
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('ada'), pg_temp.i('bob'));
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.leak('blocked: Bob sends a text in the direct chat', format('public.send_text_message(%L, ''hi'')', pg_temp.i('direct')));
  perform pg_temp.leak('blocked: Bob sends a location in the direct chat', format('public.send_location(%L, 1, 1, null, null)', pg_temp.i('direct')));
  perform pg_temp.leak('blocked: Bob pats Ada in the direct chat', format('public.pat_user(%L, %L)', pg_temp.i('direct'), pg_temp.i('ada')));
  perform pg_temp.leak('blocked: Bob starts a live location in the direct chat', format('(select count(*) from public.start_live_location(%L, 5, false))', pg_temp.i('direct')));
  perform pg_temp.leak('blocked: Bob makes a chain/note/task in the direct chat', format('public.create_note(%L, ''x'', null, null)', pg_temp.i('direct')));
  perform pg_temp.leak('blocked: Bob forwards into the direct chat', format('public.forward_message(%L, %L)', pg_temp.i('m_text'), pg_temp.i('direct')));
  perform pg_temp.leak('blocked: Bob merged-forwards into the direct chat', format('public.forward_messages_merged(array[%L::uuid], %L, null)', pg_temp.i('m_text'), pg_temp.i('direct')));
  perform pg_temp.leak('blocked: Bob sends a contact card in the direct chat', format('public.send_contact_card(%L, ''user'', %L)', pg_temp.i('direct'), pg_temp.i('dee')));
  perform pg_temp.leak('blocked: Bob creates a call link in the direct chat', format('public.create_call_link(%L, null, ''week'')', pg_temp.i('direct')));
  perform pg_temp.leak('blocked: Bob creates a chat event', format('public.create_chat_event(%L, ''e'', now() + interval ''1 day'', null, null, null, null, null, false)', pg_temp.i('direct')));
  perform pg_temp.leak('blocked: Bob creates a poll', format('public.create_poll(%L, ''q'', array[''a'',''b''], false, null, null, null, false, false, null)', pg_temp.i('direct')));
  perform pg_temp.expect(pg_temp.refused(format('insert into public.messages (conversation_id, sender_id, type, body) values (%L, %L, ''text'', ''hi'')', pg_temp.i('direct'), pg_temp.i('bob'))), 'blocked: Bob inserts a message directly');
  perform pg_temp.root();
  delete from public.blocks where blocker_id = pg_temp.i('ada') and blocked_id = pg_temp.i('bob');
end $$;

-- ===================================== 8. who may call what (grants)
do $$
declare f record; who text;
begin
  perform pg_temp.root();
  -- Functions for the server only.
  for f in
    select p.oid::regprocedure::text as sig, p.proname
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
      and (
        p.proname ~ '^(claim_|ai_|finish_|purge_|run_|install_|dispatch_|due_|deliver_|begin_data_export|delete_user_session|bot_api_|stale_file_previews|generate_)'
      )
      and p.proname not in ('claim_local_reminders', 'ai_guard_wake_dummy')
  loop
    foreach who in array array['anon', 'authenticated'] loop
      perform pg_temp.expect(not has_function_privilege(who, f.sig, 'execute'),
        format('%s may call the server-only function %s', who, f.sig));
    end loop;
  end loop;
  -- Helpers that take a viewer or a user id from the caller.
  for f in
    select p.oid::regprocedure::text as sig
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
      and p.proname in ('moments_are_friends', 'moments_post_visible_to', 'moments_interaction_visible',
        'note_json', 'task_item_json', 'task_list_json', 'chat_event_json', 'merged_forward_item',
        'merged_forward_attachment', 'group_qr_state', 'chain_can_manage', 'chain_note_needs_review',
        'chain_conversation_allowed', 'snapshot_note', 'forget_friend_tags_and_stars', 'forget_moments_friend_prefs')
  loop
    foreach who in array array['anon', 'authenticated'] loop
      perform pg_temp.expect(not has_function_privilege(who, f.sig, 'execute'),
        format('%s may call the internal helper %s', who, f.sig));
    end loop;
  end loop;
  -- Anonymous callers: only the old functions, and they must give nothing.
  perform pg_temp.act(null);
  perform pg_temp.leak('anon list_conversation_media', format('(select count(*) from public.list_conversation_media(%L))', pg_temp.i('group')));
  perform pg_temp.leak('anon list_pinned_messages', format('(select count(*) from public.list_pinned_messages(%L))', pg_temp.i('group')));
  perform pg_temp.leak('anon list_circle_summaries', '(select count(*) from public.list_circle_summaries())');
  perform pg_temp.leak('anon list_poll_voters', format('(select count(*) from public.list_poll_voters(%L, ''o1''))', pg_temp.i('m_text')));
  perform pg_temp.leak('anon vote_poll', format('public.vote_poll(%L, array[''o1''])', pg_temp.i('m_text')));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.messages') = 0 or pg_temp.refused('select 1 from public.messages'), 'anon reads messages');
  perform pg_temp.root();
  -- No anonymous access to the new tables or the profiles.
  perform pg_temp.act(null);
  for f in
    select c.relname from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
      and has_table_privilege('anon', c.oid, 'select')
  loop
    perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.%I', f.relname)) = 0,
      'anon reads rows of public.' || f.relname);
  end loop;
  perform pg_temp.root();
end $$;

-- =================================================== 9. realtime
-- Which tables stream, and who may listen to the live location channel.
do $$
declare f record; share uuid := pg_temp.i('share');
  topic text := 'live-location:' || pg_temp.i('share');
begin
  perform pg_temp.root();
  for f in
    select pt.tablename from pg_publication_tables pt
    where pt.pubname = 'supabase_realtime' and pt.schemaname = 'public'
  loop
    perform pg_temp.expect((select c.relrowsecurity from pg_class c where c.oid = format('public.%I', f.tablename)::regclass),
      'published without row level security: ' || f.tablename);
    perform pg_temp.expect(has_table_privilege('authenticated', format('public.%I', f.tablename)::regclass, 'select'),
      'published, yet select is granted by column only: ' || f.tablename);
  end loop;
  perform pg_temp.expect(not exists (
    select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename in
      ('moments_posts', 'profiles', 'user_qr_codes', 'group_qr_codes', 'chat_pats', 'pat_settings', 'message_bundles',
       'user_devices', 'saved_messages', 'message_reminders', 'scheduled_messages', 'data_exports', 'push_subscriptions',
       'friend_tags', 'friend_tag_members', 'friend_stars', 'moments_notifications', 'ai_usage', 'call_links', 'poll_quiz_answers')),
    'a private table is in the realtime publication');

  -- Live location channel (private broadcast): policy checks.
  perform pg_temp.act(pg_temp.i('bob'));
  perform set_config('realtime.topic', topic, true);
  perform pg_temp.expect(public.can_receive_live_location(public.live_location_topic_share(topic)), 'setup: a member listens');
  perform pg_temp.expect(not public.can_send_live_location(public.live_location_topic_share(topic)), 'a listener sends positions on the share of someone else');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(public.can_send_live_location(public.live_location_topic_share(topic)), 'setup: the sharer sends');
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(not public.can_receive_live_location(share), 'outsider listens to the live location');
  perform pg_temp.expect(not public.can_send_live_location(share), 'outsider sends on the live location channel');
  perform pg_temp.act(pg_temp.i('fay'));
  perform pg_temp.expect(not public.can_receive_live_location(share), 'ex-member listens to the live location');
  perform pg_temp.root();
  -- A member who blocked the sharer does not listen; a stopped share is silent.
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('dee'), pg_temp.i('ada'));
  perform pg_temp.act(pg_temp.i('dee'));
  perform pg_temp.expect(not public.can_receive_live_location(share), 'a member who blocked the sharer still listens');
  perform pg_temp.root();
  delete from public.blocks where blocker_id = pg_temp.i('dee');
  -- The card is gone (deleted or expired): no more positions to anyone.
  update public.messages set recalled_at = now() where id = (select message_id from public.live_location_shares where id = share);
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(not public.can_receive_live_location(share), 'a deleted live location card still streams');
  perform pg_temp.root();
  update public.messages set recalled_at = null, expires_at = now() - interval '1 minute'
  where id = (select message_id from public.live_location_shares where id = share);
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(not public.can_receive_live_location(share), 'an expired (disappearing) live location card still streams');
  perform pg_temp.root();
  update public.messages set expires_at = null where id = (select message_id from public.live_location_shares where id = share);
  update public.live_location_shares set stopped_at = now() where id = share;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(not public.can_receive_live_location(share), 'a stopped share still streams');
  perform pg_temp.root();
  update public.live_location_shares set stopped_at = null where id = share;
end $$;

-- =============================================== 10. overrides
-- The LAST definition of a function that several migrations redefine must
-- still hold every earlier rule.
do $$
declare def text;
begin
  perform pg_temp.root();
  select pg_get_expr(p.polqual, p.polrelid) into def from pg_policy p
  where p.polrelid = 'public.messages'::regclass and p.polname = 'messages_select_member';
  perform pg_temp.expect(def like '%expires_at%' and def like '%review_state%' and def like '%current_user_readable_conversation_ids%',
    'messages_select_member lost the expiry, review or channel rule');
  select pg_get_functiondef('public.list_conversation_summaries()'::regprocedure) into def;
  perform pg_temp.expect(def like '%review_state%' and def like '%attachment_group_id%' and def like '%note_to_self%' and def like '%view_channel%' and def like '%expires_at%',
    'list_conversation_summaries lost a rule (review, album, note to self, channel view, expiry)');
  select pg_get_functiondef('public.touch_conversation_from_message()'::regprocedure) into def;
  perform pg_temp.expect(def like '%review_state%' and def like '%pat%', 'touch_conversation_from_message lost the review or pat rule');
  select pg_get_functiondef('public.claim_push_delivery(uuid,uuid)'::regprocedure) into def;
  perform pg_temp.expect(def like '%review_state%' and def like '%attachment_group_id%' and def like '%view_channel%' and def like '%are_users_blocked%' and def like '%recalled_at%' and def like '%dnd%',
    'claim_push_delivery lost a rule');
  select pg_get_functiondef('public.forward_message(uuid,uuid)'::regprocedure) into def;
  perform pg_temp.expect(def like '%review_state%' and def like '%recalled_at%' and def like '%expires_at%', 'forward_message lost the review or expiry rule');
  select pg_get_functiondef('public.can_current_user_delete_recalled_media(text,text)'::regprocedure) into def;
  perform pg_temp.expect(def like '%message_bundle_files%', 'media deletion forgot the bundles');
  select pg_get_functiondef('public.claim_expired_media(integer)'::regprocedure) into def;
  perform pg_temp.expect(def like '%message_bundle_files%', 'expired media claim forgot the bundles');
  select pg_get_functiondef('public.list_conversation_media(uuid)'::regprocedure) into def;
  perform pg_temp.expect(def like '%expires_at%' and def like '%view_once%', 'list_conversation_media lost the expiry or view-once rule');
  select pg_get_functiondef('public.search_messages(text, jsonb, jsonb, text, integer, jsonb)'::regprocedure) into def;
  perform pg_temp.expect(def like '%expires_at%', 'search_messages shows expired messages');
  for def in select unnest(array['chat_images_select_member', 'chat_files_select_member', 'voice_messages_select_member']) loop
    perform pg_temp.expect((select pg_get_expr(p.polqual, p.polrelid) from pg_policy p where p.polrelid = 'storage.objects'::regclass and p.polname = def) like '%can_current_user_read_bundled_object%',
      def || ' forgot the bundled files');
  end loop;
  perform pg_temp.expect(exists (select 1 from pg_policy p where p.polrelid = 'storage.objects'::regclass and p.polname = 'view_once_media_restrict' and not p.polpermissive),
    'the view-once restriction on files is gone');
end $$;

-- ================================================= 11. rate limits
do $$
declare ok integer := 0; i integer;
begin
  perform pg_temp.root();
  delete from public.chat_pats;
  perform pg_temp.act(pg_temp.i('bob'));
  -- Bob pats Ada: first goes, the next within 10 seconds is refused.
  perform public.pat_user(pg_temp.i('group'), pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.refused(format('select public.pat_user(%L, %L)', pg_temp.i('group'), pg_temp.i('ada'))), 'pat: twice within 10 seconds');
  perform pg_temp.root();
  -- 20 an hour per pair, 100 an hour in all.
  insert into public.chat_pats (conversation_id, actor_id, target_id, created_at)
  select pg_temp.i('group'), pg_temp.i('bob'), pg_temp.i('ada'), now() - interval '30 seconds' - (g || ' seconds')::interval
  from generate_series(1, 19) g;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.refused(format('select public.pat_user(%L, %L)', pg_temp.i('group'), pg_temp.i('ada'))), 'pat: more than 20 an hour for one person');
  perform pg_temp.root();
  delete from public.chat_pats;
  insert into public.chat_pats (conversation_id, actor_id, target_id, created_at)
  select pg_temp.i('group'), pg_temp.i('bob'), (array[pg_temp.i('ada'), pg_temp.i('dee')])[1 + g % 2], now() - interval '30 seconds' - (g || ' seconds')::interval
  from generate_series(1, 100) g;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.refused(format('select public.pat_user(%L, %L)', pg_temp.i('group'), pg_temp.i('dee'))), 'pat: more than 100 an hour in all');
  -- Patting someone who is not in the chat, or from outside.
  perform pg_temp.expect(pg_temp.refused(format('select public.pat_user(%L, %L)', pg_temp.i('group'), pg_temp.i('cy'))), 'pat: someone who is not a member');
  perform pg_temp.root();
  -- QR codes: unguessable (80 bits) and resolving is only for people signed in.
  perform pg_temp.expect((select length(code) from public.user_qr_codes limit 1) >= 16, 'user QR code is too short');
  perform pg_temp.expect((select length(code) from public.group_qr_codes limit 1) >= 16, 'group QR code is too short');
  perform pg_temp.expect((select length(code) from public.call_links limit 1) >= 12, 'call link code is too short');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused('select * from public.resolve_user_qr_code(''aaaaaaaaaaaaaaaa'')'), 'anon resolves QR codes');
  perform pg_temp.root();
end $$;

-- ============================================ 12. deleted notes and tasks
do $$
declare ver uuid; nb integer;
begin
  perform pg_temp.root();
  -- (the note was deleted in the fixture: bring it back, give it a version
  -- history, and delete it again)
  update public.notes set deleted_at = null where id = pg_temp.i('note_deleted');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.note_apply_ops(pg_temp.i('note_deleted'), jsonb_build_array(jsonb_build_object(
    'op', 'put', 'id', gen_random_uuid(), 'base_rev', null, 'pos', 'X', 'kind', 'paragraph',
    'text', 'second deleted note secret', 'marks', '[]'::jsonb, 'props', '{}'::jsonb)));
  perform public.create_note_version(pg_temp.i('note_deleted'), 'v2');
  perform public.delete_note(pg_temp.i('note_deleted'));
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.note_blocks where note_id = %L and text like ''%%secret%%''', pg_temp.i('note_deleted'))) = 0,
    'deleted note: its text is still readable in note_blocks');
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.notes where id = %L and title <> ''''', pg_temp.i('note_deleted'))) = 0,
    'deleted note: its title is still readable');
  perform pg_temp.leak('deleted note: version history readable', format('(select count(*) from public.list_note_versions(%L))', pg_temp.i('note_deleted')));
  -- A deleted block of a living note.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.note_apply_ops(pg_temp.i('note'), jsonb_build_array(jsonb_build_object(
    'op', 'put', 'id', '11111111-1111-4111-8111-111111111111', 'base_rev', null, 'pos', 'Y', 'kind', 'paragraph',
    'text', 'block to delete secret', 'marks', '[]'::jsonb, 'props', '{}'::jsonb)));
  perform public.note_apply_ops(pg_temp.i('note'), jsonb_build_array(jsonb_build_object('op', 'del', 'id', '11111111-1111-4111-8111-111111111111')));
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.note_blocks where text like ''%block to delete%''') = 0, 'deleted block: text is still readable');
  -- A deleted task.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.delete_task_item((select id from public.task_items where title = 'task secret title' limit 1));
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.task_items where title like ''%task secret%''') = 0, 'deleted task: title is still readable');
  perform pg_temp.root();
end $$;

-- ================================================ 13. chains and their card
do $$
declare ch uuid; r jsonb;
begin
  perform pg_temp.act(pg_temp.i('dee'));
  -- A new member's chain: the description does not get past the guard either.
  select (public.create_chain(pg_temp.i('channel'), 'new member chain', 'spam description', 'spam example', null, null)->>'chain_id')::uuid into ch;
  perform pg_temp.root();
  perform pg_temp.expect((select description || example from public.chains where id = ch) = '', 'chain: a new member''s description or example passes the AI guard');
  -- Ada deletes the card of her chain: the chain is gone for everybody else.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.recall_message((select message_id from public.chains where id = pg_temp.i('chain')));
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.chains where id = %L', pg_temp.i('chain'))) = 0, 'chain: still readable after its card was deleted');
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.chain_entries where chain_id = %L', pg_temp.i('chain'))) = 0, 'chain: lines still readable after its card was deleted');
  perform pg_temp.leak('chain: get_chain after its card was deleted', format('public.get_chain(%L)', pg_temp.i('chain')));
  perform pg_temp.leak('chain: join_chain after its card was deleted', format('public.join_chain(%L, ''x'')', pg_temp.i('chain')));
  perform pg_temp.root();
end $$;
\o

select pg_temp.root();
select msg as "ATTACK SUCCEEDED / DEFENCE MISSING" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'security audit: % attack(s) succeeded', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
