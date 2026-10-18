-- Attack and behaviour tests for the admin console (K1: migrations
-- 202610210110, 202610210120 and 202610210130). Run by
-- test/supabase/admin_console_test.dart against the local database inside a
-- transaction that is rolled back. Run from the repository root.
--
-- The script plays signed-in people who talk to the REST/RPC API with their
-- own token (`set local role authenticated` plus the JWT claims). Every
-- attack must fail; a failed defence is recorded and listed at the end. It
-- also walks an admin through the three report types, a user suspension,
-- and both ways of taking a circle down.
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

-- The text result of [query] (first column of first row), or 'ERR: ...'.
create function pg_temp.val(query text) returns text language plpgsql as $$
declare r text;
begin
  execute query into r;
  return r;
exception when others then
  return 'ERR: ' || sqlerrm;
end $$;

-- How many rows [statement] changes as the current role (0 when it raises).
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

-- Records a failure unless [statement] is refused.
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
-- Ada owns a public circle with Bob in it. Dee reports things; she joined
-- the circle from Discover. Eve is the person reported. Cy is nobody to
-- anybody. Gus is Ada's friend, outside the circle. Root is the platform
-- owner, Mia a moderator, Sam support staff.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '@adm.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee'),('e1','eve'),('f1','root'),('a2','mia'),('b2','sam'),('c2','gus')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '_adm', initcap(name)
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee'),('e1','eve'),('f1','root'),('a2','mia'),('b2','sam'),('c2','gus')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || n)::uuid
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee'),('e1','eve'),('f1','root'),('a2','mia'),('b2','sam'),('c2','gus')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(x.a, x.b), greatest(x.a, x.b)
from (values
  (pg_temp.i('ada'), pg_temp.i('bob')),
  (pg_temp.i('ada'), pg_temp.i('eve')),
  (pg_temp.i('ada'), pg_temp.i('gus')),
  (pg_temp.i('ada'), pg_temp.i('cy'))
) x(a, b);

-- The first owner is added by hand, as in production (never in a migration).
insert into public.app_admins (user_id, role)
values (pg_temp.i('root'), 'owner'), (pg_temp.i('mia'), 'moderator'), (pg_temp.i('sam'), 'support');

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'circle', public.create_circle('Adm circle', array[pg_temp.i('bob')]);
select public.set_circle_discovery(pg_temp.i('circle'), true, 'about the circle', 'other', 'en', '{}'::text[]);
insert into pg_temp.ids select 'post', public.create_circle_post(pg_temp.i('circle'), 'buy my pills post');
insert into pg_temp.ids select 'post2', public.create_circle_post(pg_temp.i('circle'), 'second post');
insert into pg_temp.ids select 'dm', public.get_or_create_direct_conversation(pg_temp.i('bob'));
select public.send_text_message(pg_temp.i('dm'), 'private dm secret');
insert into pg_temp.ids select 'dm_eve', public.get_or_create_direct_conversation(pg_temp.i('eve'));
select pg_temp.root();
insert into pg_temp.ids
select 'channel', cc.conversation_id from public.circle_channels cc
where cc.circle_id = pg_temp.i('circle') order by cc.position limit 1;

select pg_temp.act(pg_temp.i('ada'));
select public.send_text_message(pg_temp.i('channel'), 'circle chat secret');
select pg_temp.act(pg_temp.i('dee'));
select public.join_public_circle(pg_temp.i('circle'));
select pg_temp.root();

-- ===================================== 1. nobody but admins gets anywhere
do $$
declare
  who uuid;
  stmts text[];
  s text;
  post uuid := pg_temp.i('post');
  circle uuid := pg_temp.i('circle');
  eve uuid := pg_temp.i('eve');
  label text;
begin
  stmts := array[
    'select public.admin_list_reports()',
    'select public.admin_list_reports(''user'', ''open'')',
    format('select public.admin_get_report(%L)', gen_random_uuid()),
    format('select public.admin_resolve_report(%L, ''dismissed'', ''no_violation'')', gen_random_uuid()),
    format('select public.admin_suspend_user(%L, null, ''x'')', eve),
    format('select public.admin_unsuspend_user(%L)', eve),
    format('select public.admin_disable_circle(%L, ''delist'', ''x'')', circle),
    format('select public.admin_disable_circle(%L, ''suspend'', ''x'')', circle),
    format('select public.admin_enable_circle(%L)', circle),
    format('select public.admin_delete_circle_post(%L, ''x'')', post),
    'select public.admin_list_audit_log()',
    'select public.admin_require(array[''owner'', ''moderator'', ''support''])',
    format('select public.admin_write_audit(''x'', ''user'', %L)', eve),
    format('select public.admin_close_report(%L, ''dismissed'', ''no_violation'')', gen_random_uuid()),
    format('select public.delete_all_user_sessions(%L)', eve),
    'select * from public.app_admins',
    format('insert into public.app_admins (user_id, role) values (%L, ''owner'')', eve),
    format('update public.app_admins set role = ''owner'' where user_id = %L', eve),
    'select * from public.admin_audit_log',
    'select * from public.app_user_suspensions',
    format('insert into public.app_user_suspensions (user_id) values (%L)', eve),
    format('update public.circles set disabled_at = now(), disabled_mode = ''suspend'' where id = %L', circle),
    format('update public.reports set status = ''dismissed'' where target_user_id = %L', eve),
    format('select public.is_user_suspended(%L)', eve)
  ];
  -- Cy (a normal user), Ada (a circle owner), Bob (a member) and nobody at all.
  foreach who in array array[pg_temp.i('cy'), pg_temp.i('ada'), pg_temp.i('bob'), null::uuid] loop
    perform pg_temp.act(who);
    label := coalesce((select name from pg_temp.ids where id = who), 'anon');
    foreach s in array stmts loop
      -- Reads that the grants allow but that must come back empty.
      if s like 'select * from public.%' then
        perform pg_temp.expect(
          pg_temp.refused(s) or pg_temp.cnt(s) = 0,
          format('%s: %s', label, s)
        );
      elsif s like 'update public.%' then
        perform pg_temp.expect(pg_temp.changed(s) = 0, format('%s: %s', label, s));
      else
        perform pg_temp.must_refuse(s, format('%s: %s', label, s));
      end if;
    end loop;
  end loop;
  perform pg_temp.root();
  -- Nothing changed.
  perform pg_temp.expect((select count(*) from public.app_admins) = 3, 'attack: app_admins changed');
  perform pg_temp.expect((select count(*) from public.app_user_suspensions) = 0, 'attack: a suspension was written');
  perform pg_temp.expect((select disabled_at is null from public.circles where id = circle), 'attack: the circle was taken down');
  perform pg_temp.expect((select count(*) from public.admin_audit_log) = 0, 'attack: an audit entry was written');
  perform pg_temp.expect(not exists (select 1 from public.reports where status <> 'open'), 'attack: a report was closed');
end $$;

-- A normal user is no admin.
do $$
begin
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(public.is_app_admin() = false, 'is_app_admin() is true for a normal user');
  perform pg_temp.expect(public.admin_my_role() is null, 'admin_my_role() is not null for a normal user');
  perform pg_temp.act(pg_temp.i('root'));
  perform pg_temp.expect(public.is_app_admin() = true, 'is_app_admin() is false for the owner');
  perform pg_temp.expect(public.admin_my_role() = 'owner', 'admin_my_role() is not owner');
  perform pg_temp.act(pg_temp.i('sam'));
  perform pg_temp.expect(public.admin_my_role() = 'support', 'admin_my_role() is not support');
  perform pg_temp.root();
end $$;

-- ===================================== 2. reports of the three kinds
do $$
begin
  perform pg_temp.act(pg_temp.i('dee'));
  insert into pg_temp.ids select 'r_user', public.report_user(pg_temp.i('eve'), 'harassment', 'rude to me');
  insert into pg_temp.ids select 'r_circle', public.report_circle(pg_temp.i('circle'), 'spam', 'a spam circle');
  insert into pg_temp.ids select 'r_post', public.report_circle_post(pg_temp.i('post'), 'spam', 'pills');
  insert into pg_temp.ids select 'r_post_dup', public.report_circle_post(pg_temp.i('post'), 'spam', 'again');
  insert into pg_temp.ids select 'r_post2', public.report_circle_post(pg_temp.i('post2'), 'other', 'meh');
  perform pg_temp.root();
  -- The reporter sees only their own reports; nobody else's.
  perform pg_temp.expect((select snapshot->>'title' from public.reports where id = pg_temp.i('r_post')) = 'buy my pills post', 'snapshot: post title');
  perform pg_temp.expect((select snapshot->>'body' from public.reports where id = pg_temp.i('r_post')) = 'buy my pills post', 'snapshot: post body');
  perform pg_temp.expect((select snapshot->>'name' from public.reports where id = pg_temp.i('r_circle')) = 'Adm circle', 'snapshot: circle name');
  perform pg_temp.expect((select snapshot->>'username' from public.reports where id = pg_temp.i('r_user')) = 'eve_adm', 'snapshot: user name');
  -- An edit and a delete afterwards change nothing in the snapshot.
  update public.circle_posts set body = 'edited', deleted_at = now() where id = pg_temp.i('post2');
  update public.circles set name = 'Renamed circle' where id = pg_temp.i('circle');
  perform pg_temp.expect((select snapshot->>'body' from public.reports where id = pg_temp.i('r_post2')) = 'second post', 'snapshot: changes later on');
  perform pg_temp.expect((select snapshot->>'name' from public.reports where id = pg_temp.i('r_circle')) = 'Adm circle', 'snapshot: circle rename later on');
  update public.circles set name = 'Adm circle' where id = pg_temp.i('circle');
  update public.circle_posts set body = 'second post', deleted_at = null where id = pg_temp.i('post2');

  perform pg_temp.act(pg_temp.i('sam'));
  perform pg_temp.expect(jsonb_array_length(public.admin_list_reports()) = 5, 'support: list all open reports');
  perform pg_temp.expect(jsonb_array_length(public.admin_list_reports('user')) = 1, 'list: user kind');
  perform pg_temp.expect(jsonb_array_length(public.admin_list_reports('circle')) = 1, 'list: circle kind');
  perform pg_temp.expect(jsonb_array_length(public.admin_list_reports('post')) = 3, 'list: post kind');
  perform pg_temp.expect(jsonb_array_length(public.admin_list_reports(null, 'handled')) = 0, 'list: nothing handled yet');
  perform pg_temp.expect(pg_temp.refused('select public.admin_list_reports(''chat'')'), 'list: unknown kind');
  perform pg_temp.expect(pg_temp.refused('select public.admin_list_reports(null, ''weird'')'), 'list: unknown status');
  perform pg_temp.expect(jsonb_array_length(public.admin_list_reports(null, 'open', 2)) = 2, 'list: page size');
  perform pg_temp.expect(
    (select (e->>'repeat_count')::int from jsonb_array_elements(public.admin_list_reports('post')) e where (e->>'id')::uuid = pg_temp.i('r_post')) = 2,
    'list: two open reports of the same post');
  declare detail jsonb := public.admin_get_report(pg_temp.i('r_post'));
  begin
    perform pg_temp.expect(detail->'report'->'snapshot'->>'body' = 'buy my pills post', 'detail: snapshot body');
    perform pg_temp.expect(detail->'subject'->>'circle_name' = 'Adm circle', 'detail: context circle');
    perform pg_temp.expect(detail->'responsible_user'->>'username' = 'ada_adm', 'detail: the author answers for a post');
    perform pg_temp.expect(jsonb_array_length(detail->'history') = 1, 'detail: the other report of the post is history');
    perform pg_temp.expect(detail->'reporter_stats'->>'total' = '5', 'detail: reporter totals');
  end;
  -- Support closes reports, but not the ones that are not open any more.
  perform public.admin_resolve_report(pg_temp.i('r_post_dup'), 'dismissed', 'duplicate', 'same post');
  perform pg_temp.expect(pg_temp.refused(format('select public.admin_resolve_report(%L, ''dismissed'', ''no_violation'')', pg_temp.i('r_post_dup'))), 'resolve: twice');
  perform pg_temp.expect(pg_temp.refused(format('select public.admin_resolve_report(%L, ''open'', ''no_violation'')', pg_temp.i('r_post2'))), 'resolve: back to open');
  perform pg_temp.expect(pg_temp.refused(format('select public.admin_resolve_report(%L, ''reviewed'', ''because'')', pg_temp.i('r_post2'))), 'resolve: unknown resolution');
  perform public.admin_resolve_report(pg_temp.i('r_post2'), 'dismissed', 'no_violation', 'fine');
  perform pg_temp.expect(jsonb_array_length(public.admin_list_reports(null, 'handled')) = 2, 'list: handled');
  perform pg_temp.expect(jsonb_array_length(public.admin_list_reports(null, 'dismissed')) = 2, 'list: dismissed');
  perform pg_temp.root();
  perform pg_temp.expect((select handled_by from public.reports where id = pg_temp.i('r_post2')) = pg_temp.i('sam'), 'resolve: handled_by');
  perform pg_temp.expect((select handled_at is not null and resolution = 'no_violation' and status = 'dismissed' from public.reports where id = pg_temp.i('r_post2')), 'resolve: handled_at, resolution, status');

  -- Support cannot sanction anybody.
  perform pg_temp.act(pg_temp.i('sam'));
  perform pg_temp.must_refuse(format('select public.admin_suspend_user(%L, null, ''x'')', pg_temp.i('eve')), 'support: suspend');
  perform pg_temp.must_refuse(format('select public.admin_disable_circle(%L, ''delist'', ''x'')', pg_temp.i('circle')), 'support: disable circle');
  perform pg_temp.must_refuse(format('select public.admin_delete_circle_post(%L, ''x'')', pg_temp.i('post')), 'support: delete post');
  perform pg_temp.must_refuse(format('select public.admin_enable_circle(%L)', pg_temp.i('circle')), 'support: enable circle');
  perform pg_temp.root();
end $$;

-- ===================================== 3. admins read no chat
do $$
begin
  perform pg_temp.act(pg_temp.i('root'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.messages') = 0, 'admin: reads messages');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.conversations') = 0, 'admin: reads conversations');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.conversation_members') = 0, 'admin: reads conversation members');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.circle_posts') = 0, 'admin: reads circle posts');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.reports') = 0, 'admin: reads the reports table directly');
  perform pg_temp.expect(public.get_circle_detail(pg_temp.i('circle')) is null, 'admin: get_circle_detail of a circle they are not in');
  perform pg_temp.expect(pg_temp.refused(format('select public.send_text_message(%L, ''hi'')', pg_temp.i('dm'))), 'admin: sends into a private chat');
  -- What the admin RPCs return holds no message text.
  perform pg_temp.expect(
    position('private dm secret' in (public.admin_list_reports(null, 'all'))::text) = 0
    and position('circle chat secret' in (public.admin_list_reports(null, 'all'))::text) = 0
    and position('private dm secret' in (public.admin_get_report(pg_temp.i('r_user')))::text) = 0
    and position('circle chat secret' in (public.admin_get_report(pg_temp.i('r_circle')))::text) = 0
    and position('private dm secret' in (public.admin_list_audit_log())::text) = 0,
    'admin RPCs: chat text in a result');
  perform pg_temp.root();
end $$;

-- ===================================== 4. suspending a person
do $$
begin
  perform pg_temp.act(pg_temp.i('eve'));
  perform public.send_text_message(pg_temp.i('dm_eve'), 'hello before the ban');
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.must_refuse(format('select public.admin_suspend_user(%L, null, '''')', pg_temp.i('eve')), 'suspend: reason required');
  perform pg_temp.must_refuse(format('select public.admin_suspend_user(%L, now() - interval ''1 day'', ''x'')', pg_temp.i('eve')), 'suspend: until in the past');
  perform pg_temp.must_refuse(format('select public.admin_suspend_user(%L, null, ''x'')', pg_temp.i('mia')), 'suspend: yourself');
  perform pg_temp.must_refuse(format('select public.admin_suspend_user(%L, null, ''x'')', pg_temp.i('root')), 'suspend: an admin');
  perform pg_temp.must_refuse(format('select public.admin_suspend_user(%L, null, ''x'')', gen_random_uuid()), 'suspend: no such user');
  perform public.admin_suspend_user(pg_temp.i('eve'), null, 'harassment', pg_temp.i('r_user'));
  perform pg_temp.root();
  perform pg_temp.expect(public.is_user_suspended(pg_temp.i('eve')), 'suspend: not suspended');
  perform pg_temp.expect((select status = 'reviewed' and resolution = 'user_suspended' and handled_by = pg_temp.i('mia') from public.reports where id = pg_temp.i('r_user')), 'suspend: the report is closed');
  -- A token that still works cannot send, post or comment.
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.refused(format('select public.send_text_message(%L, ''still here'')', pg_temp.i('dm_eve'))), 'suspended user still sends');
  perform pg_temp.root();
  -- The person who answers is shown as suspended.
  perform pg_temp.act(pg_temp.i('sam'));
  perform pg_temp.expect((public.admin_get_report(pg_temp.i('r_user'))->'responsible_user'->>'is_suspended')::boolean, 'detail: suspended person');
  perform pg_temp.act(pg_temp.i('mia'));
  -- A later end date also counts only while it lies ahead.
  perform public.admin_unsuspend_user(pg_temp.i('eve'), 'sorry');
  perform pg_temp.root();
  perform pg_temp.expect(not public.is_user_suspended(pg_temp.i('eve')), 'unsuspend: still suspended');
  perform pg_temp.act(pg_temp.i('eve'));
  perform public.send_text_message(pg_temp.i('dm_eve'), 'back again');
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.admin_suspend_user(pg_temp.i('eve'), now() + interval '2 days', 'cooling off');
  perform pg_temp.root();
  perform pg_temp.expect(public.is_user_suspended(pg_temp.i('eve')), 'suspend: with an end date');
  update public.app_user_suspensions set until = now() - interval '1 minute' where user_id = pg_temp.i('eve');
  perform pg_temp.expect(not public.is_user_suspended(pg_temp.i('eve')), 'suspend: an end date in the past');
  delete from public.app_user_suspensions;
end $$;

-- ===================================== 5. delisting a circle
do $$
declare inv text; card_code text;
begin
  -- An invite and a contact card that exist before the take-down.
  perform pg_temp.act(pg_temp.i('ada'));
  inv := public.create_circle_invite(pg_temp.i('circle'), 24, null);
  insert into pg_temp.ids select 'dm_cy', public.get_or_create_direct_conversation(pg_temp.i('cy'));
  perform public.send_contact_card(pg_temp.i('dm_cy'), 'circle', pg_temp.i('circle'));
  select m.attachment->>'invite_code' into card_code from public.messages m where m.conversation_id = pg_temp.i('dm_cy') and m.attachment->>'card' = 'circle';
  perform pg_temp.expect(card_code is not null, 'contact card: has an invite code');
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.list_discoverable_circles(null, null, ''popular'', 20, 0)') = 1, 'discover: the circle is listed before');

  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.must_refuse(format('select public.admin_disable_circle(%L, ''gone'', ''x'')', pg_temp.i('circle')), 'disable: unknown mode');
  perform pg_temp.must_refuse(format('select public.admin_disable_circle(%L, ''delist'', '' '')', pg_temp.i('circle')), 'disable: reason required');
  perform public.admin_disable_circle(pg_temp.i('circle'), 'delist', 'misleading listing', pg_temp.i('r_circle'));
  perform pg_temp.root();
  perform pg_temp.expect((select disabled_mode = 'delist' and disabled_at is not null from public.circles where id = pg_temp.i('circle')), 'delist: columns');
  perform pg_temp.expect((select status = 'reviewed' and resolution = 'circle_delisted' from public.reports where id = pg_temp.i('r_circle')), 'delist: the report is closed');
  perform pg_temp.expect((select count(*) from public.circle_invites where circle_id = pg_temp.i('circle') and revoked_at is null) = 0, 'delist: invites are revoked');

  -- Hidden from Discover, closed to newcomers on every path.
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.list_discoverable_circles(null, null, ''popular'', 20, 0)') = 0, 'delist: still listed in Discover');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.list_discoverable_circles(''Adm'', null, ''relevance'', 20, 0)') = 0, 'delist: found by search in Discover');
  perform pg_temp.must_refuse(format('select public.discoverable_circle_preview(%L)', pg_temp.i('circle')), 'delist: preview in Discover');
  perform pg_temp.must_refuse(format('select public.join_public_circle(%L)', pg_temp.i('circle')), 'delist: public join');
  perform pg_temp.must_refuse(format('select public.accept_circle_invite(%L)', inv), 'delist: accept an invite link');
  perform pg_temp.must_refuse(format('select public.accept_circle_invite(%L)', card_code), 'delist: accept a contact-card invite');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.must_refuse(format('select public.create_circle_invite(%L, 24, null)', pg_temp.i('circle')), 'delist: a new invite');
  perform pg_temp.must_refuse(format('select public.invite_circle_members(%L, array[%L]::uuid[])', pg_temp.i('circle'), pg_temp.i('gus')), 'delist: invite a friend');
  perform pg_temp.must_refuse(format('select public.send_contact_card(%L, ''circle'', %L)', pg_temp.i('dm_cy'), pg_temp.i('circle')), 'delist: share the circle as a contact card');
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.circle_members where circle_id = pg_temp.i('circle') and user_id in (pg_temp.i('cy'), pg_temp.i('gus'))), 'delist: someone got in');

  -- Members keep using it.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.messages where conversation_id = %L', pg_temp.i('channel'))) >= 1, 'delist: a member cannot read');
  perform public.send_text_message(pg_temp.i('channel'), 'still talking');
  perform pg_temp.expect(public.get_circle_detail(pg_temp.i('circle')) is not null, 'delist: a member loses the circle detail');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.circle_posts') >= 1, 'delist: a member cannot read posts');
  perform pg_temp.expect((select count(*) from public.my_circle_takedowns() where mode = 'delist') = 1, 'delist: my_circle_takedowns');

  -- Lifting it.
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.admin_enable_circle(pg_temp.i('circle'), 'fixed the listing');
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.list_discoverable_circles(null, null, ''popular'', 20, 0)') = 1, 'enable: back in Discover');
  perform public.join_public_circle(pg_temp.i('circle'));
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.circle_members where circle_id = pg_temp.i('circle') and user_id = pg_temp.i('cy')), 'enable: joining works again');
  delete from public.circle_members where circle_id = pg_temp.i('circle') and user_id = pg_temp.i('cy');
end $$;

-- ===================================== 6. suspending a circle
do $$
declare ch_count integer;
begin
  -- A picture of a post, in the circle's folder.
  insert into storage.objects (bucket_id, name, owner)
  values ('chat-media', pg_temp.i('circle')::text || '/post.png', pg_temp.i('ada'));
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from storage.objects where bucket_id = ''chat-media''') = 1, 'storage: a member sees the picture before');
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.admin_disable_circle(pg_temp.i('circle'), 'suspend', 'illegal content');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from storage.objects where bucket_id = ''chat-media''') = 0, 'suspend: a member opens a picture of a post');
  perform pg_temp.root();

  -- Nobody gets in.
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.must_refuse(format('select public.join_public_circle(%L)', pg_temp.i('circle')), 'suspend: public join');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.list_discoverable_circles(null, null, ''popular'', 20, 0)') = 0, 'suspend: listed in Discover');

  -- Members read nothing and write nothing.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.messages where conversation_id = %L', pg_temp.i('channel'))) = 0, 'suspend: a member reads the circle''s messages');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.messages where body like ''%circle chat secret%''') = 0, 'suspend: a member finds a circle message');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.circle_posts') = 0, 'suspend: a member reads posts');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.circle_post_comments') = 0, 'suspend: a member reads comments');
  perform pg_temp.expect(public.get_circle_detail(pg_temp.i('circle')) is null, 'suspend: get_circle_detail answers');
  perform pg_temp.expect(pg_temp.refused(format('select public.send_text_message(%L, ''hello?'')', pg_temp.i('channel'))), 'suspend: a member sends');
  perform pg_temp.expect(pg_temp.refused(format('select public.create_circle_post(%L, ''hello?'')', pg_temp.i('circle'))), 'suspend: a member posts');
  perform pg_temp.expect(pg_temp.refused(format('insert into public.messages (conversation_id, sender_id, body, type) values (%L, %L, ''x'', ''text'')', pg_temp.i('channel'), pg_temp.i('bob'))), 'suspend: a member inserts a message directly');
  perform pg_temp.expect(pg_temp.val(format('select public.is_current_user_conversation_member(%L)', pg_temp.i('channel'))) = 'false', 'suspend: a member of the channel');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.current_user_readable_conversation_ids() id where id in (select conversation_id from public.circle_channels)') = 0, 'suspend: readable channels');
  perform pg_temp.expect((select count(*) from public.my_circle_takedowns() where mode = 'suspend') = 1, 'suspend: my_circle_takedowns tells the member');
  -- Their other chats are untouched.
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.messages where conversation_id = %L', pg_temp.i('dm'))) = 1, 'suspend: a private chat of the member went away');
  perform public.send_text_message(pg_temp.i('dm'), 'still can talk to Ada');
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect((select count(*) from public.my_circle_takedowns()) = 0, 'suspend: my_circle_takedowns shows others'' circles');

  -- Members can still leave.
  perform pg_temp.act(pg_temp.i('dee'));
  perform public.leave_circle(pg_temp.i('circle'));
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.circle_members where circle_id = pg_temp.i('circle') and user_id = pg_temp.i('dee')), 'suspend: a member cannot leave');

  -- The admin changes their mind to a delist, and later lifts it.
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.admin_disable_circle(pg_temp.i('circle'), 'delist', 'only a delist after all');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.messages where conversation_id = %L', pg_temp.i('channel'))) >= 1, 'suspend -> delist: a member reads again');
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.admin_disable_circle(pg_temp.i('circle'), 'suspend', 'back to suspend');
  perform public.admin_enable_circle(pg_temp.i('circle'), 'cleared');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.messages where conversation_id = %L', pg_temp.i('channel'))) >= 1, 'enable: a member reads again');
  perform public.send_text_message(pg_temp.i('channel'), 'we are back');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.circle_posts') >= 1, 'enable: posts again');
  perform pg_temp.expect(pg_temp.cnt('select 1 from storage.objects where bucket_id = ''chat-media''') = 1, 'enable: the picture again');
  perform pg_temp.root();
end $$;

-- ===================================== 7. deleting a post
do $$
begin
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.must_refuse(format('select public.admin_delete_circle_post(%L, '' '')', pg_temp.i('post')), 'delete post: reason required');
  perform public.admin_delete_circle_post(pg_temp.i('post'), 'pills', pg_temp.i('r_post'));
  perform pg_temp.must_refuse(format('select public.admin_delete_circle_post(%L, ''again'')', pg_temp.i('post')), 'delete post: twice');
  perform pg_temp.root();
  perform pg_temp.expect((select deleted_at is not null from public.circle_posts where id = pg_temp.i('post')), 'delete post: not deleted');
  perform pg_temp.expect((select status = 'reviewed' and resolution = 'content_removed' from public.reports where id = pg_temp.i('r_post')), 'delete post: the report is closed');
  -- Closing a report that is already handled through an action is refused,
  -- and the action is rolled back with it.
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.must_refuse(format('select public.admin_delete_circle_post(%L, ''x'', %L)', pg_temp.i('post2'), pg_temp.i('r_post')), 'delete post: report already handled');
  perform pg_temp.root();
  perform pg_temp.expect((select deleted_at is null from public.circle_posts where id = pg_temp.i('post2')), 'delete post: a refused call changed the post');
end $$;

-- ===================================== 8. every action is in the audit log
do $$
declare entries jsonb;
begin
  perform pg_temp.act(pg_temp.i('sam'));
  entries := public.admin_list_audit_log(100);
  perform pg_temp.expect(
    (select array_agg(distinct e->>'action' order by e->>'action') from jsonb_array_elements(entries) e)
      = array['delete_circle_post', 'disable_circle', 'enable_circle', 'resolve_report', 'suspend_user', 'unsuspend_user'],
    'audit: the actions that were taken');
  perform pg_temp.expect((select count(*) from jsonb_array_elements(entries) e where e->>'action' = 'suspend_user') = 2, 'audit: both suspensions');
  perform pg_temp.expect((select count(*) from jsonb_array_elements(entries) e where e->>'action' = 'disable_circle') = 4, 'audit: the take-downs');
  perform pg_temp.expect((select count(*) from jsonb_array_elements(entries) e where e->>'action' = 'resolve_report') = 5, 'audit: the closed reports');
  perform pg_temp.expect((select count(*) from jsonb_array_elements(entries) e where e->>'actor_username' = 'mia_adm') >= 8, 'audit: the actor is named');
  perform pg_temp.expect((select count(*) from jsonb_array_elements(entries) e where e->>'actor_role' = 'support') = 2, 'audit: the actor''s role is kept');
  perform pg_temp.expect(jsonb_array_length(public.admin_list_audit_log(3)) = 3, 'audit: page size');
  perform pg_temp.expect(
    jsonb_array_length(public.admin_list_audit_log(50, null, 'user', pg_temp.i('eve'))) = 3,
    'audit: filter by subject');
  perform pg_temp.root();
  -- Entries cannot be changed or removed through the API.
  perform pg_temp.act(pg_temp.i('root'));
  perform pg_temp.must_refuse('delete from public.admin_audit_log', 'audit: an owner deletes entries');
  perform pg_temp.must_refuse('update public.admin_audit_log set action = ''x''', 'audit: an owner edits entries');
  perform pg_temp.root();
end $$;
\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "ATTACK SUCCEEDED / DEFENCE MISSING" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'admin console: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
