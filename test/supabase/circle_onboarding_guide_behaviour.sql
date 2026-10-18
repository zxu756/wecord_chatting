-- Behaviour checks for onboarding 2.0 (C2: migrations 202610230200 to
-- 202610230220). Run by test/supabase/circle_onboarding_guide_test.dart against
-- the local database: it applies the migrations it needs in a transaction,
-- plays people through the RPCs, and rolls everything back. Run from the
-- repository root.
--
-- What it walks through: which roles an answer may give (nothing beyond view,
-- send, invite and voice; nothing that outranks a management role; never
-- @everyone), that a role edited into a powerful one later is neither handed
-- out nor kept by the people who picked it, that a role an admin gave by hand
-- is never taken back, single and required questions, who may edit the guide,
-- the tasks and their progress, channels the member cannot see, a suspended
-- circle, and the greeting card for new members on every way in.
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
\i supabase/migrations/202610230200_onboarding_guide_schema.sql
\i supabase/migrations/202610230210_onboarding_guide_rpcs.sql
\i supabase/migrations/202610230220_onboarding_greeting.sql
\i supabase/migrations/202610230300_circle_invite_tracking.sql
\i supabase/migrations/202610230310_circle_insights_data.sql
\i supabase/migrations/202610230320_circle_insights_rpc.sql
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


create temp table codes (name text primary key, code text not null);
grant all on codes to public;
create function pg_temp.code(n text) returns text language sql as $$ select code from pg_temp.codes where name = n $$;

create function pg_temp.is_member(c uuid, who uuid) returns boolean language sql as $$
  select exists (select 1 from public.circle_members cm where cm.circle_id = c and cm.user_id = who)
$$;
-- Whether [who] holds the role in the circle, and whether they got it by an answer.
create function pg_temp.holds(c uuid, who uuid, r uuid) returns boolean language sql as $$
  select exists (select 1 from public.circle_member_roles mr where mr.circle_id = c and mr.user_id = who and mr.role_id = r)
$$;
create function pg_temp.via(c uuid, who uuid, r uuid) returns boolean language sql as $$
  select coalesce((select mr.via_onboarding from public.circle_member_roles mr where mr.circle_id = c and mr.user_id = who and mr.role_id = r), false)
$$;
create function pg_temp.guide(c uuid) returns jsonb language sql as $$ select public.get_circle_guide(c) $$;
create function pg_temp.cfg(c uuid) returns jsonb language sql as $$ select public.get_circle_guide_config(c) $$;
create function pg_temp.rp(c uuid, r uuid) returns text language sql as $$ select public.onboarding_role_problem(c, r) $$;
-- One option for the question list: {label, role_ids, channel_ids}.
create function pg_temp.opt(label text, roles uuid[] default '{}', channels uuid[] default '{}') returns jsonb language sql as $$
  select jsonb_build_object('label', label, 'role_ids', to_jsonb(roles), 'channel_ids', to_jsonb(channels))
$$;
create function pg_temp.q(title text, opts jsonb, required boolean default false, single boolean default false) returns jsonb language sql as $$
  select jsonb_build_object('title', title, 'required', required, 'single_select', single, 'options', opts)
$$;
create function pg_temp.audits(c uuid, a text) returns integer language sql as $$
  select count(*)::integer from public.circle_audit_log l where l.circle_id = c and l.action = a
$$;
create function pg_temp.greetings(conv uuid, who uuid) returns integer language sql as $$
  select count(*)::integer from public.messages m
  where m.conversation_id = conv and m.type = 'system' and m.attachment ->> 'kind' = 'newcomer' and m.attachment ->> 'user_id' = who::text
$$;
grant execute on all functions in schema pg_temp to public;

create function pg_temp.detail(statement text) returns text language plpgsql as $$
declare d text;
begin
  execute statement;
  return 'ok';
exception when others then
  get stacked diagnostics d = pg_exception_detail;
  return coalesce(d, '');
end $$;
create function pg_temp.hint(statement text) returns text language plpgsql as $$
declare d text;
begin
  execute statement;
  return 'ok';
exception when others then
  get stacked diagnostics d = pg_exception_hint;
  return coalesce(d, '');
end $$;
-- Saves one question with one option holding [roles].
create function pg_temp.save_one(c uuid, roles uuid[]) returns text language plpgsql as $$
begin
  return pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, %L::jsonb)$q$, c,
    jsonb_build_array(pg_temp.q('Q', jsonb_build_array(pg_temp.opt('A', roles))))));
end $$;
grant execute on all functions in schema pg_temp to public;

-- ------------------------------------------------------------------ cast
-- Ada owns the circle. Mgr holds manage_circle only; Rol manage_circle and
-- manage_roles. Bob and Cat are members. Dan owns another circle and is an
-- outsider here. Robo is a bot. n1..n8 come in later.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@og.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'mgr'),(3,'rol'),(4,'bob'),(5,'cat'),(6,'dan'),(7,'robo'),
  (8,'n1'),(9,'n2'),(10,'n3'),(11,'n4'),(12,'n5'),(13,'n6'),(14,'n7'),(15,'n8')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_og', initcap(name)
from (values (1,'ada'),(2,'mgr'),(3,'rol'),(4,'bob'),(5,'cat'),(6,'dan'),(7,'robo'),
  (8,'n1'),(9,'n2'),(10,'n3'),(11,'n4'),(12,'n5'),(13,'n6'),(14,'n7'),(15,'n8')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'mgr'),(3,'rol'),(4,'bob'),(5,'cat'),(6,'dan'),(7,'robo'),
  (8,'n1'),(9,'n2'),(10,'n3'),(11,'n4'),(12,'n5'),(13,'n6'),(14,'n7'),(15,'n8')) v(n, name);
update public.profiles set is_bot = true where id = pg_temp.i('robo');

insert into public.friendships (user_low_id, user_high_id)
select least(x.a, x.b), greatest(x.a, x.b)
from (values
  (pg_temp.i('ada'), pg_temp.i('mgr')),
  (pg_temp.i('ada'), pg_temp.i('rol')),
  (pg_temp.i('ada'), pg_temp.i('bob')),
  (pg_temp.i('ada'), pg_temp.i('cat'))
) x(a, b);

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'circle', public.create_circle('Guide club',
  array[pg_temp.i('mgr'), pg_temp.i('rol'), pg_temp.i('bob'), pg_temp.i('cat')]);
-- Created top to bottom: a new role takes the lowest position.
insert into pg_temp.ids select 'elder', public.create_circle_role(pg_temp.i('circle'), 'Elder', null, 0, false);
insert into pg_temp.ids select 'modlow', public.create_circle_role(pg_temp.i('circle'), 'ModLow', null, 4, false);
insert into pg_temp.ids select 'mentioner', public.create_circle_role(pg_temp.i('circle'), 'Mentioner', null, 256, false);
insert into pg_temp.ids select 'adminr', public.create_circle_role(pg_temp.i('circle'), 'AdminR', null, 16384, false);
insert into pg_temp.ids select 'circlemgr', public.create_circle_role(pg_temp.i('circle'), 'CircleMgr', null, 1 << 20, false);
insert into pg_temp.ids select 'rolemgr', public.create_circle_role(pg_temp.i('circle'), 'RoleMgr', null, 16 | (1 << 20), false);
insert into pg_temp.ids select 'gamer', public.create_circle_role(pg_temp.i('circle'), 'Gamer', null, 0, false);
insert into pg_temp.ids select 'writer', public.create_circle_role(pg_temp.i('circle'), 'Writer', null, 3, false);
insert into pg_temp.ids select 'voice', public.create_circle_role(pg_temp.i('circle'), 'Voice', null, 8259, false);
select public.set_member_roles(pg_temp.i('circle'), pg_temp.i('mgr'), array[pg_temp.i('circlemgr')]);
select public.set_member_roles(pg_temp.i('circle'), pg_temp.i('rol'), array[pg_temp.i('rolemgr')]);
insert into pg_temp.ids select 'intro', public.create_circle_channel(pg_temp.i('circle'), 'intro');
insert into pg_temp.ids select 'games', public.create_circle_channel(pg_temp.i('circle'), 'games');
insert into pg_temp.ids select 'secret', public.create_circle_channel(pg_temp.i('circle'), 'secret');
insert into pg_temp.ids select 'welcome', public.create_circle_channel(pg_temp.i('circle'), 'welcome');
insert into pg_temp.ids select 'lounge', public.create_circle_channel(pg_temp.i('circle'), 'lounge', null, 'voice');
select pg_temp.root();
-- #secret is hidden from everyone.
insert into public.circle_channel_overwrites (circle_id, channel_id, role_id, allow, deny)
select pg_temp.i('circle'), pg_temp.i('secret'), r.id, 0, 1
from public.circle_roles r where r.circle_id = pg_temp.i('circle') and r.is_default;
-- A sticker for the greeting.
insert into public.circle_emojis (circle_id, name, kind, storage_path, mime_type)
values (pg_temp.i('circle'), 'wave', 'sticker', 'og/wave.png', 'image/png');
insert into pg_temp.ids select 'sticker', id from public.circle_emojis where storage_path = 'og/wave.png';
-- A second circle with a role, a channel and a sticker of its own.
select pg_temp.act(pg_temp.i('dan'));
insert into pg_temp.ids select 'other', public.create_circle('Other club', array[]::uuid[]);
insert into pg_temp.ids select 'other_role', public.create_circle_role(pg_temp.i('other'), 'Foreign', null, 0, false);
insert into pg_temp.ids select 'other_channel', public.create_circle_channel(pg_temp.i('other'), 'elsewhere');
select pg_temp.root();
insert into public.circle_emojis (circle_id, name, kind, storage_path, mime_type)
values (pg_temp.i('other'), 'foreign', 'sticker', 'og/foreign.png', 'image/png');
insert into pg_temp.ids select 'other_sticker', id from public.circle_emojis where storage_path = 'og/foreign.png';

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.codes select 'inv', public.create_circle_invite(pg_temp.i('circle'), null, null);
select pg_temp.root();

-- ===================================== 1. which roles an answer may give
do $$
declare c uuid := pg_temp.i('circle');
begin
  perform pg_temp.expect(pg_temp.rp(c, pg_temp.i('gamer')) is null, 'role rule: a plain role with no permission can be given');
  perform pg_temp.expect(pg_temp.rp(c, pg_temp.i('writer')) is null, 'role rule: view and send are fine');
  perform pg_temp.expect(pg_temp.rp(c, pg_temp.i('voice')) is null, 'role rule: view, send, invite and voice are fine');
  perform pg_temp.expect(pg_temp.rp(c, pg_temp.i('modlow')) = 'permissions', 'role rule: manage_messages is management');
  perform pg_temp.expect(pg_temp.rp(c, pg_temp.i('mentioner')) = 'permissions', 'role rule: even mention_everyone is refused');
  perform pg_temp.expect(pg_temp.rp(c, pg_temp.i('adminr')) = 'permissions', 'role rule: administrator is refused');
  perform pg_temp.expect(pg_temp.rp(c, pg_temp.i('circlemgr')) = 'permissions', 'role rule: manage_circle is refused');
  perform pg_temp.expect(pg_temp.rp(c, pg_temp.i('rolemgr')) = 'permissions', 'role rule: manage_roles is refused');
  perform pg_temp.expect(pg_temp.rp(c, pg_temp.i('elder')) = 'rank', 'role rule: a plain role above a management role is refused');
  perform pg_temp.expect(pg_temp.rp(c, (select r.id from public.circle_roles r where r.circle_id = c and r.is_default)) = 'default',
    'role rule: @everyone is refused');
  perform pg_temp.expect(pg_temp.rp(c, pg_temp.i('other_role')) = 'missing', 'role rule: a role of another circle is refused');
  perform pg_temp.expect(pg_temp.rp(c, gen_random_uuid()) = 'missing', 'role rule: an unknown role is refused');
  perform pg_temp.expect(public.onboarding_safe_permissions() = 8259, 'the safe set is view, send, invite and voice');
end $$;

-- ===================================== 2. who may edit the guide
do $$
declare c uuid := pg_temp.i('circle');
begin
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.refused('select 1 from public.circle_onboarding_prompts'), 'tables: prompts are closed to members');
  perform pg_temp.expect(pg_temp.refused('select 1 from public.circle_onboarding_options'), 'tables: options are closed');
  perform pg_temp.expect(pg_temp.refused('select 1 from public.circle_onboarding_option_roles'), 'tables: option roles are closed');
  perform pg_temp.expect(pg_temp.refused('select 1 from public.circle_onboarding_option_channels'), 'tables: option channels are closed');
  perform pg_temp.expect(pg_temp.refused('select 1 from public.circle_guide_tasks'), 'tables: tasks are closed');
  perform pg_temp.expect(pg_temp.refused('select 1 from public.circle_guide_settings'), 'tables: settings are closed');
  perform pg_temp.expect(pg_temp.refused('select 1 from public.circle_member_onboarding'), 'tables: progress is closed');
  perform pg_temp.expect(pg_temp.refused('select 1 from public.circle_member_onboarding_answers'), 'tables: answers are closed');
  perform pg_temp.expect(pg_temp.refused('select 1 from public.circle_member_guide_tasks'), 'tables: task progress is closed');
  perform pg_temp.expect(pg_temp.refused(format(
    'insert into public.circle_member_roles (circle_id, user_id, role_id, via_onboarding) values (%L, %L, %L, true)',
    c, pg_temp.i('bob'), pg_temp.i('gamer'))), 'tables: a member cannot give themselves a role');

  perform pg_temp.expect(pg_temp.state(format('select public.get_circle_guide_config(%L)', c)) = '42501', 'edit: a member cannot read the config');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, '[]'::jsonb)$q$, c)) = '42501', 'edit: a member cannot set questions');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_tasks(%L, '[]'::jsonb)$q$, c)) = '42501', 'edit: a member cannot set tasks');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_greeting(%L, %L, null)', c, pg_temp.i('welcome'))) = '42501', 'edit: a member cannot set the greeting');
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, '[]'::jsonb)$q$, c)) = '42501', 'edit: an outsider cannot set questions');
  perform pg_temp.expect(pg_temp.state(format('select public.get_circle_guide(%L)', c)) = '42501', 'read: an outsider cannot read the guide');
  perform pg_temp.expect(pg_temp.state(format('select public.complete_onboarding_prompts(%L, %L)', c, '{}'::uuid[])) = '42501', 'answer: an outsider cannot answer');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select public.get_circle_guide(%L)', c)) = '42501', 'read: nobody signed in is refused');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, '[]'::jsonb)$q$, c)) = '42501', 'edit: nobody signed in is refused');
  perform pg_temp.expect(pg_temp.state(format('select public.complete_onboarding_prompts(%L, %L)', c, '{}'::uuid[])) = '42501', 'answer: nobody signed in is refused');

  -- Mgr (manage_circle, no manage_roles): questions without roles, no new role.
  perform pg_temp.act(pg_temp.i('mgr'));
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, %L::jsonb)$q$, c,
    jsonb_build_array(pg_temp.q('What do you play?', jsonb_build_array(pg_temp.opt('Chess'), pg_temp.opt('Go')))))) = 'ok',
    'edit: manage_circle alone can set questions without roles');
  perform pg_temp.expect(pg_temp.save_one(c, array[pg_temp.i('gamer')]) = '42501', 'edit: attaching a role needs manage_roles');
  perform pg_temp.expect(jsonb_array_length(pg_temp.cfg(c) -> 'prompts') = 1
    and (pg_temp.cfg(c) -> 'prompts' -> 0 ->> 'title') = 'What do you play?', 'edit: the refused call changed nothing');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_tasks(%L, %L::jsonb)$q$, c,
    '[{"title":"Read the rules","action":"read_rules"}]')) = 'ok', 'edit: manage_circle can set tasks');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_greeting(%L, %L, %L)', c, pg_temp.i('welcome'), pg_temp.i('sticker'))) = 'ok',
    'edit: manage_circle can set the greeting');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.audits(c, 'onboarding_update') >= 3, 'edit: each change is audited');

  -- A role with a management permission is refused, with the reason.
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.save_one(c, array[pg_temp.i('modlow')]) = '22023', 'attach: manage_messages is refused');
  perform pg_temp.expect(pg_temp.detail(format($q$select public.set_circle_guide_prompts(%L, %L::jsonb)$q$, c,
    jsonb_build_array(pg_temp.q('Q', jsonb_build_array(pg_temp.opt('A', array[pg_temp.i('modlow')])))))) = 'role_permissions', 'attach: and says why');
  perform pg_temp.expect(pg_temp.hint(format($q$select public.set_circle_guide_prompts(%L, %L::jsonb)$q$, c,
    jsonb_build_array(pg_temp.q('Q', jsonb_build_array(pg_temp.opt('A', array[pg_temp.i('modlow')])))))) = pg_temp.i('modlow')::text, 'attach: and which role');
  perform pg_temp.expect(pg_temp.save_one(c, array[pg_temp.i('mentioner')]) = '22023', 'attach: mention_everyone is refused');
  perform pg_temp.expect(pg_temp.save_one(c, array[pg_temp.i('adminr')]) = '22023', 'attach: administrator is refused');
  perform pg_temp.expect(pg_temp.save_one(c, array[pg_temp.i('circlemgr')]) = '22023', 'attach: manage_circle is refused');
  perform pg_temp.expect(pg_temp.save_one(c, array[pg_temp.i('rolemgr')]) = '22023', 'attach: manage_roles is refused');
  perform pg_temp.expect(pg_temp.save_one(c, array[pg_temp.i('elder')]) = '22023', 'attach: a role above a management role is refused');
  perform pg_temp.expect(pg_temp.detail(format($q$select public.set_circle_guide_prompts(%L, %L::jsonb)$q$, c,
    jsonb_build_array(pg_temp.q('Q', jsonb_build_array(pg_temp.opt('A', array[pg_temp.i('elder')])))))) = 'role_rank', 'attach: with the rank reason');
  perform pg_temp.expect(pg_temp.save_one(c, array[(select r.id from public.circle_roles r where r.circle_id = c and r.is_default)]) = '22023',
    'attach: @everyone is refused');
  perform pg_temp.expect(pg_temp.save_one(c, array[pg_temp.i('other_role')]) = '22023', 'attach: a role of another circle is refused');
  perform pg_temp.expect(pg_temp.save_one(c, array[pg_temp.i('gamer'), pg_temp.i('modlow')]) = '22023', 'attach: one bad role refuses the whole save');
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.circle_onboarding_option_roles), 'attach: nothing was linked by the refused saves');
  -- The trigger holds for any writer, not just the RPC.
  perform pg_temp.expect(pg_temp.refused(format(
    'insert into public.circle_onboarding_option_roles (option_id, circle_id, role_id) select o.id, o.circle_id, %L from public.circle_onboarding_options o limit 1',
    pg_temp.i('modlow'))), 'attach: even the table owner cannot link a management role');
  perform pg_temp.expect(pg_temp.refused(format(
    'insert into public.circle_onboarding_option_roles (option_id, circle_id, role_id) select o.id, o.circle_id, %L from public.circle_onboarding_options o limit 1',
    pg_temp.i('adminr'))), 'attach: nor administrator');
end $$;

-- ===================================== 3. the questions: save, limits, keep ids
do $$
declare
  c uuid := pg_temp.i('circle');
  cfg jsonb;
  p1 uuid; p2 uuid; o_chess uuid; o_go uuid; o_music uuid; o_pc uuid; o_mobile uuid;
  items jsonb;
begin
  -- Rol (manage_circle + manage_roles) attaches roles below their rank.
  perform pg_temp.act(pg_temp.i('rol'));
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, %L::jsonb)$q$, c,
    jsonb_build_array(
      pg_temp.q('Pick your games', jsonb_build_array(
        pg_temp.opt('Chess', array[pg_temp.i('gamer')], array[pg_temp.i('games')]),
        pg_temp.opt('Go', array[pg_temp.i('writer')], array[pg_temp.i('games'), pg_temp.i('secret')]),
        pg_temp.opt('Music'))),
      pg_temp.q('Where do you play?', jsonb_build_array(
        pg_temp.opt('PC', array[pg_temp.i('voice')]),
        pg_temp.opt('Mobile')), true, true)))) = 'ok', 'save: manage_roles can attach plain roles');
  perform pg_temp.root();

  cfg := pg_temp.cfg(c);
  perform pg_temp.expect(jsonb_array_length(cfg -> 'prompts') = 2, 'save: both questions are there');
  perform pg_temp.expect((cfg -> 'prompts' -> 0 ->> 'title') = 'Pick your games' and (cfg -> 'prompts' -> 1 ->> 'title') = 'Where do you play?', 'save: in order');
  perform pg_temp.expect((cfg -> 'prompts' -> 1 ->> 'required')::boolean and (cfg -> 'prompts' -> 1 ->> 'single_select')::boolean, 'save: required and single are kept');
  p1 := (cfg -> 'prompts' -> 0 ->> 'id')::uuid;
  p2 := (cfg -> 'prompts' -> 1 ->> 'id')::uuid;
  o_chess := (cfg -> 'prompts' -> 0 -> 'options' -> 0 ->> 'id')::uuid;
  o_go := (cfg -> 'prompts' -> 0 -> 'options' -> 1 ->> 'id')::uuid;
  o_music := (cfg -> 'prompts' -> 0 -> 'options' -> 2 ->> 'id')::uuid;
  o_pc := (cfg -> 'prompts' -> 1 -> 'options' -> 0 ->> 'id')::uuid;
  o_mobile := (cfg -> 'prompts' -> 1 -> 'options' -> 1 ->> 'id')::uuid;
  insert into pg_temp.ids values ('p1', p1), ('p2', p2), ('o_chess', o_chess), ('o_go', o_go), ('o_music', o_music), ('o_pc', o_pc), ('o_mobile', o_mobile);
  perform pg_temp.expect((cfg -> 'prompts' -> 0 -> 'options' -> 0 -> 'role_ids') = to_jsonb(array[pg_temp.i('gamer')]), 'save: the role is linked');
  perform pg_temp.expect(jsonb_array_length(cfg -> 'prompts' -> 0 -> 'options' -> 1 -> 'channel_ids') = 2, 'save: channels are linked');
  perform pg_temp.expect((cfg ->> 'greeting_channel_id')::uuid = pg_temp.i('welcome') and (cfg ->> 'greeting_sticker_id')::uuid = pg_temp.i('sticker'), 'save: the greeting is in the config');
  perform pg_temp.expect((cfg -> 'assignable_role_ids') @> to_jsonb(array[pg_temp.i('gamer'), pg_temp.i('writer'), pg_temp.i('voice')])
    and not ((cfg -> 'assignable_role_ids') @> to_jsonb(array[pg_temp.i('modlow')]))
    and not ((cfg -> 'assignable_role_ids') @> to_jsonb(array[pg_temp.i('elder')])), 'save: the editor is offered only roles that can be given');

  -- Mgr resaves the same config (no manage_roles): existing links are not new links.
  perform pg_temp.act(pg_temp.i('mgr'));
  items := (select jsonb_agg(p) from public.get_circle_guide_config(c) cfgs, jsonb_array_elements(cfgs -> 'prompts') p);
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, %L::jsonb)$q$, c, items)) = 'ok',
    'resave: manage_circle alone can edit a config that already has roles');
  -- ...and renaming keeps ids.
  items := jsonb_set(items, '{0,title}', '"Pick your games!"');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, %L::jsonb)$q$, c, items)) = 'ok', 'resave: rename');
  perform pg_temp.root();
  cfg := pg_temp.cfg(c);
  perform pg_temp.expect((cfg -> 'prompts' -> 0 ->> 'title') = 'Pick your games!' and (cfg -> 'prompts' -> 0 ->> 'id')::uuid = p1
    and (cfg -> 'prompts' -> 0 -> 'options' -> 0 ->> 'id')::uuid = o_chess, 'resave: ids stay');
  perform pg_temp.expect((cfg -> 'prompts' -> 0 -> 'options' -> 0 -> 'role_ids') = to_jsonb(array[pg_temp.i('gamer')]), 'resave: roles stay');

  -- Limits and bad input.
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, %L::jsonb)$q$, c,
    (select jsonb_agg(pg_temp.q('Q' || g, jsonb_build_array(pg_temp.opt('a')))) from generate_series(1, 6) g))) = '22023', 'limits: 6 questions are too many');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, %L::jsonb)$q$, c,
    (select jsonb_build_array(pg_temp.q('Q', jsonb_agg(pg_temp.opt('o' || g)))) from generate_series(1, 13) g))) = '22023', 'limits: 13 options are too many');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, %L::jsonb)$q$, c,
    jsonb_build_array(pg_temp.q('Q', jsonb_build_array(pg_temp.opt('a', array[pg_temp.i('gamer'), pg_temp.i('writer'), pg_temp.i('voice'), gen_random_uuid(), gen_random_uuid(), gen_random_uuid()])))))) = '22023', 'limits: 6 roles are too many');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, %L::jsonb)$q$, c,
    jsonb_build_array(pg_temp.q(repeat('x', 101), jsonb_build_array(pg_temp.opt('a')))))) = '22023', 'limits: a long title');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, %L::jsonb)$q$, c,
    jsonb_build_array(pg_temp.q('Q', jsonb_build_array(pg_temp.opt(repeat('x', 61))))))) = '22023', 'limits: a long label');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, %L::jsonb)$q$, c,
    jsonb_build_array(pg_temp.q('  ', jsonb_build_array(pg_temp.opt('a')))))) = '22023', 'limits: an empty title');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, %L::jsonb)$q$, c,
    jsonb_build_array(pg_temp.q('Q', '[]'::jsonb)))) = '22023', 'limits: a question needs an option');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, '{}'::jsonb)$q$, c)) = '22023', 'limits: not a list');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, %L::jsonb)$q$, c,
    jsonb_build_array(pg_temp.q('Q', jsonb_build_array(pg_temp.opt('a', '{}', array[pg_temp.i('other_channel')])))))) = '22023', 'limits: a channel of another circle');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, %L::jsonb)$q$, c,
    jsonb_build_array(jsonb_set(pg_temp.q('Q', jsonb_build_array(pg_temp.opt('a'))), '{id}', to_jsonb(gen_random_uuid()::text))))) = '22023', 'limits: an unknown question id');
  perform pg_temp.root();
  perform pg_temp.expect(jsonb_array_length(pg_temp.cfg(c) -> 'prompts') = 2, 'limits: the config is as it was after all of those');
end $$;

-- ===================================== 4. answering
do $$
declare
  c uuid := pg_temp.i('circle');
  r jsonb;
  g jsonb;
begin
  -- Bob, Cat and the newcomers see the guide; bob joined before the questions.
  perform pg_temp.act(pg_temp.i('bob'));
  g := pg_temp.guide(c);
  perform pg_temp.expect((g ->> 'enabled')::boolean, 'guide: enabled when there are questions');
  perform pg_temp.expect(jsonb_array_length(g -> 'prompts') = 2, 'guide: both questions');
  perform pg_temp.expect(not (g ->> 'needs_answers')::boolean, 'guide: a member from before the questions is not asked on their own');
  perform pg_temp.expect(not (g ->> 'new_member')::boolean, 'guide: and is not a new member of it');
  perform pg_temp.expect(not (g ->> 'answered')::boolean, 'guide: not answered yet');
  perform pg_temp.expect((g -> 'prompts' -> 0 -> 'options' -> 0 -> 'roles' -> 0 ->> 'name') = 'Gamer', 'guide: names the role an option gives');
  perform pg_temp.expect(jsonb_array_length(g -> 'prompts' -> 0 -> 'options' -> 1 -> 'channels') = 1
    and (g -> 'prompts' -> 0 -> 'options' -> 1 -> 'channels' -> 0 ->> 'name') = 'games', 'guide: and only the channels bob can see');
  perform pg_temp.root();

  -- Refusals.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.detail(format('select public.complete_onboarding_prompts(%L, %L)', c, array[pg_temp.i('o_chess')])) = 'required_prompt',
    'answer: a required question must be answered');
  perform pg_temp.expect(pg_temp.detail(format('select public.complete_onboarding_prompts(%L, %L)', c, array[pg_temp.i('o_pc'), pg_temp.i('o_mobile')])) = 'single_select',
    'answer: a single-choice question takes one option');
  perform pg_temp.expect(pg_temp.state(format('select public.complete_onboarding_prompts(%L, %L)', c, array[pg_temp.i('o_pc'), gen_random_uuid()])) = '22023',
    'answer: an unknown option is refused');
  perform pg_temp.root();
  perform pg_temp.expect(not pg_temp.holds(c, pg_temp.i('bob'), pg_temp.i('gamer')), 'answer: the refused ones gave nothing');

  -- A real answer.
  perform pg_temp.act(pg_temp.i('bob'));
  r := public.complete_onboarding_prompts(c, array[pg_temp.i('o_chess'), pg_temp.i('o_go'), pg_temp.i('o_pc'), null]);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.holds(c, pg_temp.i('bob'), pg_temp.i('gamer')) and pg_temp.holds(c, pg_temp.i('bob'), pg_temp.i('writer'))
    and pg_temp.holds(c, pg_temp.i('bob'), pg_temp.i('voice')), 'answer: the roles of the options picked are given');
  perform pg_temp.expect(pg_temp.via(c, pg_temp.i('bob'), pg_temp.i('gamer')), 'answer: and marked as given by an answer');
  perform pg_temp.expect(jsonb_array_length(r -> 'added') = 3 and jsonb_array_length(r -> 'removed') = 0, 'answer: the result lists what was added');
  perform pg_temp.expect(pg_temp.audits(c, 'onboarding_roles') = 1, 'answer: the grant is in the audit log');
  perform pg_temp.expect((select l.actor_id = pg_temp.i('bob') and l.target_id = pg_temp.i('bob') and l.changes ->> 'source' = 'onboarding'
      and jsonb_array_length(l.changes -> 'added') = 3
    from public.circle_audit_log l where l.circle_id = c and l.action = 'onboarding_roles'), 'answer: saying who, what, and that it came from onboarding');
  perform pg_temp.expect((select (public.circle_member_permissions(c, pg_temp.i('bob')) & ~public.onboarding_safe_permissions()) = 0), 'answer: bob gained no management permission');
  perform pg_temp.expect((select cm.role from public.circle_members cm where cm.circle_id = c and cm.user_id = pg_temp.i('bob')) = 'member', 'answer: bob is still a plain member');
  perform pg_temp.act(pg_temp.i('bob'));
  g := pg_temp.guide(c);
  perform pg_temp.root();
  perform pg_temp.expect((g ->> 'answered')::boolean, 'answer: the guide knows bob answered');
  perform pg_temp.expect((g -> 'prompts' -> 0 -> 'options' -> 0 ->> 'selected')::boolean and not (g -> 'prompts' -> 0 -> 'options' -> 2 ->> 'selected')::boolean, 'answer: and which options');

  -- Changing their mind takes back only what an answer gave.
  -- Cat: the admin gives Writer by hand first, then Cat picks Go (Writer) and later drops it.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_member_roles(c, pg_temp.i('cat'), array[pg_temp.i('writer')]);
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.complete_onboarding_prompts(c, array[pg_temp.i('o_go'), pg_temp.i('o_chess'), pg_temp.i('o_mobile')]);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.holds(c, pg_temp.i('cat'), pg_temp.i('writer')) and not pg_temp.via(c, pg_temp.i('cat'), pg_temp.i('writer')),
    'by hand: a role the admin gave stays marked as by hand when an answer also names it');
  perform pg_temp.expect(pg_temp.holds(c, pg_temp.i('cat'), pg_temp.i('gamer')) and pg_temp.via(c, pg_temp.i('cat'), pg_temp.i('gamer')), 'by hand: the new one is by answer');
  perform pg_temp.act(pg_temp.i('cat'));
  r := public.complete_onboarding_prompts(c, array[pg_temp.i('o_music'), pg_temp.i('o_mobile')]);
  perform pg_temp.root();
  perform pg_temp.expect(not pg_temp.holds(c, pg_temp.i('cat'), pg_temp.i('gamer')), 'change: dropping the option takes its role back');
  perform pg_temp.expect(pg_temp.holds(c, pg_temp.i('cat'), pg_temp.i('writer')), 'change: but not the role the admin gave by hand');
  perform pg_temp.expect(jsonb_array_length(r -> 'removed') = 1 and (r -> 'removed' -> 0 ->> 'name') = 'Gamer', 'change: the result lists what was removed');
  perform pg_temp.expect(pg_temp.audits(c, 'onboarding_roles') = 3, 'change: both changes are audited');
  perform pg_temp.act(pg_temp.i('cat'));
  perform public.complete_onboarding_prompts(c, array[pg_temp.i('o_music'), pg_temp.i('o_mobile')]);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.audits(c, 'onboarding_roles') = 3, 'change: answering the same again audits nothing');

  -- Bob changes only one answer: the others are kept.
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.complete_onboarding_prompts(c, array[pg_temp.i('o_chess'), pg_temp.i('o_pc')]);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.holds(c, pg_temp.i('bob'), pg_temp.i('gamer')) and pg_temp.holds(c, pg_temp.i('bob'), pg_temp.i('voice')),
    'change: bob keeps what he still picks');
  perform pg_temp.expect(not pg_temp.holds(c, pg_temp.i('bob'), pg_temp.i('writer')), 'change: and loses the one he dropped');
end $$;

-- ===================================== 5. a role that turns powerful later
do $$
declare
  c uuid := pg_temp.i('circle');
  items jsonb;
  stale uuid;
begin
  perform pg_temp.expect(pg_temp.rp(c, pg_temp.i('gamer')) is null, 'later: Gamer is plain to begin with');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.update_circle_role(pg_temp.i('gamer'), 'Gamer', null, 4, false);
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.circle_onboarding_option_roles where role_id = pg_temp.i('gamer')),
    'later: the role is unlinked from every option the moment it gains a management permission');
  perform pg_temp.expect(not pg_temp.holds(c, pg_temp.i('bob'), pg_temp.i('gamer')), 'later: and taken back from the people who picked it');
  perform pg_temp.expect(pg_temp.holds(c, pg_temp.i('bob'), pg_temp.i('voice')), 'later: their other roles stay');
  perform pg_temp.expect((select (public.circle_member_permissions(c, pg_temp.i('bob')) & ~public.onboarding_safe_permissions()) = 0), 'later: bob has no management permission');
  perform pg_temp.expect(exists (select 1 from public.circle_audit_log l where l.circle_id = c and l.action = 'onboarding_update' and l.changes ->> 'role_detached' = 'true'),
    'later: and the audit log says so');
  -- A role an admin gave by hand stays with them.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_member_roles(c, pg_temp.i('cat'), array[pg_temp.i('writer'), pg_temp.i('gamer')]);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.holds(c, pg_temp.i('cat'), pg_temp.i('gamer')), 'later: a role given by hand is the admin''s call and stays');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.update_circle_role(pg_temp.i('gamer'), 'Gamer', null, 0, false);
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.circle_onboarding_option_roles where role_id = pg_temp.i('gamer')),
    'later: making it plain again does not link it back');

  -- A stale link (the trigger off) is still not handed out when someone answers.
  perform pg_temp.act(pg_temp.i('ada'));
  items := (pg_temp.cfg(c) -> 'prompts') || jsonb_build_array(pg_temp.q('Stale', jsonb_build_array(pg_temp.opt('V', array[pg_temp.i('writer')]))));
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, %L::jsonb)$q$, c, items)) = 'ok', 'stale: a question with Writer');
  perform pg_temp.root();
  select o.id into stale from public.circle_onboarding_options o where o.circle_id = c and o.label = 'V';
  insert into pg_temp.ids values ('o_stale', stale);
  alter table public.circle_roles disable trigger circle_roles_detach_onboarding;
  update public.circle_roles set permissions = 3 | 4 where id = pg_temp.i('writer');
  alter table public.circle_roles enable trigger circle_roles_detach_onboarding;
  perform pg_temp.expect(exists (select 1 from public.circle_onboarding_option_roles where role_id = pg_temp.i('writer')), 'stale: the link is still there');
  perform pg_temp.act(pg_temp.i('n1'));
  perform pg_temp.expect(pg_temp.state(format('select public.complete_onboarding_prompts(%L, %L)', c, array[pg_temp.i('o_stale')])) = '42501',
    'stale: not a member yet, so nothing');
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.complete_onboarding_prompts(%L, %L)', c, array[pg_temp.i('o_stale'), pg_temp.i('o_pc')])) = 'ok',
    'stale: answering still works');
  perform pg_temp.root();
  perform pg_temp.expect(not pg_temp.holds(c, pg_temp.i('bob'), pg_temp.i('writer')), 'stale: but the role that is not plain any more is not given');
  -- Same for a role that now outranks a management role.
  update public.circle_roles set permissions = 3 where id = pg_temp.i('writer');
  perform pg_temp.expect(pg_temp.rp(c, pg_temp.i('writer')) is null, 'stale: Writer is plain again');
  update public.circle_roles set position = position + 100 where id = pg_temp.i('writer');
  perform pg_temp.expect(pg_temp.rp(c, pg_temp.i('writer')) = 'rank', 'stale: moved above a management role it is refused');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.complete_onboarding_prompts(c, array[pg_temp.i('o_stale'), pg_temp.i('o_pc')]);
  perform pg_temp.root();
  perform pg_temp.expect(not pg_temp.holds(c, pg_temp.i('bob'), pg_temp.i('writer')), 'stale: and not given either');
  update public.circle_roles set position = position - 100 where id = pg_temp.i('writer');
  perform pg_temp.expect(pg_temp.rp(c, pg_temp.i('writer')) is null, 'stale: put back, it is plain');
end $$;

-- ===================================== 6. the task list and its progress
do $$
declare
  c uuid := pg_temp.i('circle');
  welcome_conv uuid;
  g jsonb;
  inv text := pg_temp.code('inv');
  t_read uuid; t_visit uuid; t_send uuid; t_avatar uuid; t_secret uuid;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_onboarding(c, true, array['Be kind'], null);

  -- Bad input.
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_tasks(%L, %L::jsonb)$q$, c,
    '[{"title":"Go","action":"visit_channel"}]')) = '22023', 'tasks: visiting needs a channel');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_tasks(%L, %L::jsonb)$q$, c,
    '[{"title":"Go","action":"dance"}]')) = '22023', 'tasks: an unknown kind');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_tasks(%L, %L::jsonb)$q$, c,
    jsonb_build_array(jsonb_build_object('title', 'Go', 'action', 'visit_channel', 'channel_id', pg_temp.i('other_channel'))))) = '22023',
    'tasks: a channel of another circle');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_tasks(%L, %L::jsonb)$q$, c,
    (select jsonb_agg(jsonb_build_object('title', 'T' || n, 'action', 'set_avatar')) from generate_series(1, 11) gs(n)))) = '22023', 'tasks: 11 are too many');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_tasks(%L, %L::jsonb)$q$, c,
    jsonb_build_array(jsonb_build_object('title', repeat('x', 81), 'action', 'set_avatar')))) = '22023', 'tasks: a long title');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_tasks(%L, %L::jsonb)$q$, c,
    jsonb_build_array(jsonb_build_object('title', 'x', 'action', 'set_avatar', 'id', gen_random_uuid())))) = '22023', 'tasks: an unknown id');

  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_tasks(%L, %L::jsonb)$q$, c,
    jsonb_build_array(
      jsonb_build_object('title', 'Read the rules', 'action', 'read_rules', 'channel_id', pg_temp.i('games')),
      jsonb_build_object('title', 'Visit #games', 'action', 'visit_channel', 'channel_id', pg_temp.i('games')),
      jsonb_build_object('title', 'Say hi in #intro', 'action', 'send_message', 'channel_id', pg_temp.i('intro')),
      jsonb_build_object('title', 'Set an avatar', 'action', 'set_avatar'),
      jsonb_build_object('title', 'Peek at #secret', 'action', 'visit_channel', 'channel_id', pg_temp.i('secret'))))) = 'ok', 'tasks: five tasks saved');
  perform pg_temp.root();
  perform pg_temp.expect((select channel_id is null from public.circle_guide_tasks where circle_id = c and action = 'read_rules'), 'tasks: reading the rules has no channel');
  select id into t_read from public.circle_guide_tasks where circle_id = c and action = 'read_rules';
  select id into t_visit from public.circle_guide_tasks where circle_id = c and title = 'Visit #games';
  select id into t_send from public.circle_guide_tasks where circle_id = c and action = 'send_message';
  select id into t_avatar from public.circle_guide_tasks where circle_id = c and action = 'set_avatar';
  select id into t_secret from public.circle_guide_tasks where circle_id = c and title = 'Peek at #secret';

  -- A newcomer.
  select conversation_id into welcome_conv from public.circle_channels where id = pg_temp.i('welcome');
  perform pg_temp.act(pg_temp.i('n1'));
  perform public.accept_circle_invite(inv);
  perform pg_temp.root();
  update public.circle_members set created_at = clock_timestamp() where circle_id = c and user_id = pg_temp.i('n1');
  perform pg_temp.act(pg_temp.i('n1'));
  g := pg_temp.guide(c);
  perform pg_temp.root();
  perform pg_temp.expect((g ->> 'needs_answers')::boolean, 'newcomer: is asked the questions');
  perform pg_temp.expect((g ->> 'new_member')::boolean, 'newcomer: and is a new member of the guide');
  perform pg_temp.expect(jsonb_array_length(g -> 'tasks') = 4, 'newcomer: the task about a channel they cannot see is left out');
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(g -> 'tasks') t where (t ->> 'done')::boolean), 'newcomer: nothing is done yet');
  perform pg_temp.expect((g -> 'tasks' -> 1 ->> 'channel_name') = 'games', 'newcomer: a visit task names its channel');

  -- Visiting.
  perform pg_temp.act(pg_temp.i('n1'));
  perform pg_temp.expect(pg_temp.state(format('select public.complete_guide_task(%L, %L)', c, t_send)) = '22023', 'visit: only visit tasks are ticked by the app');
  perform pg_temp.expect(pg_temp.state(format('select public.complete_guide_task(%L, %L)', c, t_read)) = '22023', 'visit: not reading the rules either');
  perform pg_temp.expect(pg_temp.state(format('select public.complete_guide_task(%L, %L)', c, t_secret)) = '42501', 'visit: a channel they cannot see');
  perform pg_temp.expect(pg_temp.state(format('select public.complete_guide_task(%L, %L)', c, gen_random_uuid())) = 'P0002', 'visit: an unknown task');
  perform pg_temp.expect(pg_temp.state(format('select public.complete_guide_task(%L, %L)', pg_temp.i('other'), t_visit)) = '42501', 'visit: not a member of that circle');
  perform pg_temp.expect(pg_temp.state(format('select public.complete_guide_task(%L, %L)', c, t_visit)) = 'ok', 'visit: a visit is ticked off');
  perform pg_temp.expect(pg_temp.state(format('select public.complete_guide_task(%L, %L)', c, t_visit)) = 'ok', 'visit: twice is fine');
  g := pg_temp.guide(c);
  perform pg_temp.expect((g -> 'tasks' -> 1 ->> 'done')::boolean and not (g -> 'tasks' -> 0 ->> 'done')::boolean, 'visit: only that one is done');
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(pg_temp.state(format('select public.complete_guide_task(%L, %L)', c, t_visit)) = '42501', 'visit: an outsider cannot tick it');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_member_guide_tasks) = 1, 'visit: one row of progress');

  -- The rules, an avatar, a message.
  perform pg_temp.act(pg_temp.i('n1'));
  perform public.accept_circle_rules(c);
  g := pg_temp.guide(c);
  perform pg_temp.expect((g -> 'tasks' -> 0 ->> 'done')::boolean, 'rules: accepting them completes the task');
  perform pg_temp.expect(not (g -> 'tasks' -> 3 ->> 'done')::boolean, 'avatar: not yet');
  perform pg_temp.root();
  update public.profiles set avatar_url = 'https://example.test/a.png' where id = pg_temp.i('n1');
  perform pg_temp.act(pg_temp.i('n1'));
  g := pg_temp.guide(c);
  perform pg_temp.expect((g -> 'tasks' -> 3 ->> 'done')::boolean, 'avatar: setting one completes the task');
  -- A message elsewhere does not count; one in #intro does.
  insert into public.messages (conversation_id, sender_id, type, body)
  select cc.conversation_id, pg_temp.i('n1'), 'text', 'hello games' from public.circle_channels cc where cc.id = pg_temp.i('games');
  g := pg_temp.guide(c);
  perform pg_temp.expect(not (g -> 'tasks' -> 2 ->> 'done')::boolean, 'message: one in another channel does not count');
  insert into public.messages (conversation_id, sender_id, type, body)
  select cc.conversation_id, pg_temp.i('n1'), 'text', 'hello intro' from public.circle_channels cc where cc.id = pg_temp.i('intro');
  g := pg_temp.guide(c);
  perform pg_temp.expect((g -> 'tasks' -> 2 ->> 'done')::boolean, 'message: one in the channel does');
  perform pg_temp.root();
  -- Recalling it takes the progress back (it is the member's state, not a log).
  update public.messages set recalled_at = now() where body = 'hello intro';
  perform pg_temp.act(pg_temp.i('n1'));
  g := pg_temp.guide(c);
  perform pg_temp.expect(not (g -> 'tasks' -> 2 ->> 'done')::boolean, 'message: a recalled message does not count');
  perform pg_temp.root();
  update public.messages set recalled_at = null where body = 'hello intro';
  update public.messages set review_state = 'held' where body = 'hello intro';
  perform pg_temp.act(pg_temp.i('n1'));
  g := pg_temp.guide(c);
  perform pg_temp.expect(not (g -> 'tasks' -> 2 ->> 'done')::boolean, 'message: nor one the AI guard holds');
  perform pg_temp.root();
  update public.messages set review_state = null where body = 'hello intro';

  -- Ada sees every task, including the one about #secret.
  perform pg_temp.act(pg_temp.i('ada'));
  g := pg_temp.guide(c);
  perform pg_temp.root();
  perform pg_temp.expect(jsonb_array_length(g -> 'tasks') = 5, 'owner: sees every task');

  -- Putting the card away and back.
  perform pg_temp.act(pg_temp.i('n1'));
  perform public.dismiss_circle_guide(c);
  perform pg_temp.expect((pg_temp.guide(c) ->> 'dismissed')::boolean, 'dismiss: put away');
  perform public.dismiss_circle_guide(c, false);
  perform pg_temp.expect(not (pg_temp.guide(c) ->> 'dismissed')::boolean, 'dismiss: and back');
  perform pg_temp.expect(pg_temp.state(format('select public.dismiss_circle_guide(%L)', pg_temp.i('other'))) = '42501', 'dismiss: not for another circle');
  perform pg_temp.root();

  -- Answering after the rules: needs_answers goes away.
  perform pg_temp.act(pg_temp.i('n1'));
  perform public.complete_onboarding_prompts(c, array[pg_temp.i('o_music'), pg_temp.i('o_mobile')]);
  g := pg_temp.guide(c);
  perform pg_temp.root();
  perform pg_temp.expect(not (g ->> 'needs_answers')::boolean and (g ->> 'answered')::boolean, 'newcomer: answered, so not asked again');

  -- Removing a task or a question removes the progress with it.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_guide_tasks(c, jsonb_build_array(jsonb_build_object('title', 'Set an avatar', 'action', 'set_avatar', 'id', t_avatar)));
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_guide_tasks where circle_id = c) = 1, 'tasks: whatever is missing is deleted');
  perform pg_temp.expect(not exists (select 1 from public.circle_member_guide_tasks), 'tasks: and so is its progress');
end $$;

-- ===================================== 7. a circle that is taken down
do $$
declare c uuid := pg_temp.i('circle'); g jsonb;
begin
  update public.circles set disabled_at = now(), disabled_mode = 'delist' where id = c;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect((pg_temp.guide(c) ->> 'enabled')::boolean, 'delisted: the guide still works for members');
  perform pg_temp.expect(pg_temp.state(format('select public.complete_onboarding_prompts(%L, %L)', c, array[pg_temp.i('o_music'), pg_temp.i('o_mobile')])) = 'ok',
    'delisted: and so does answering');
  perform pg_temp.root();

  update public.circles set disabled_mode = 'suspend' where id = c;
  perform pg_temp.act(pg_temp.i('bob'));
  g := pg_temp.guide(c);
  perform pg_temp.expect(not (g ->> 'enabled')::boolean and jsonb_array_length(g -> 'prompts') = 0 and jsonb_array_length(g -> 'tasks') = 0, 'suspended: the guide is empty');
  perform pg_temp.expect(pg_temp.state(format('select public.complete_onboarding_prompts(%L, %L)', c, array[pg_temp.i('o_music'), pg_temp.i('o_mobile')])) = '42501', 'suspended: no answering');
  perform pg_temp.expect(pg_temp.state(format('select public.complete_guide_task(%L, %L)', c, gen_random_uuid())) = '42501', 'suspended: no ticking tasks');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_prompts(%L, '[]'::jsonb)$q$, c)) = '42501', 'suspended: no editing questions');
  perform pg_temp.expect(pg_temp.state(format($q$select public.set_circle_guide_tasks(%L, '[]'::jsonb)$q$, c)) = '42501', 'suspended: no editing tasks');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_greeting(%L, null, null)', c)) = '42501', 'suspended: no editing the greeting');
  perform pg_temp.root();
  update public.circles set disabled_at = null, disabled_mode = null where id = c;
end $$;

-- ===================================== 8. the greeting for new members
do $$
declare
  c uuid := pg_temp.i('circle');
  inv text := pg_temp.code('inv');
  welcome_conv uuid;
  msg public.messages%rowtype;
begin
  select conversation_id into welcome_conv from public.circle_channels where id = pg_temp.i('welcome');

  perform pg_temp.expect(pg_temp.greetings(welcome_conv, pg_temp.i('n1')) = 1, 'greeting: n1 was announced when they joined');
  select * into msg from public.messages m where m.conversation_id = welcome_conv and m.attachment ->> 'user_id' = pg_temp.i('n1')::text;
  perform pg_temp.expect(msg.type = 'system' and msg.sender_id = pg_temp.i('n1') and msg.body = 'N1 joined the circle', 'greeting: a system message from the newcomer');
  perform pg_temp.expect(msg.attachment ->> 'kind' = 'newcomer' and msg.attachment ->> 'user_label' = 'N1'
    and (msg.attachment ->> 'sticker_id')::uuid = pg_temp.i('sticker') and (msg.attachment ->> 'circle_id')::uuid = c, 'greeting: with the card''s facts');
  perform pg_temp.expect(pg_temp.greetings(welcome_conv, pg_temp.i('ada')) = 0, 'greeting: the owner was not announced');

  -- Leaving and coming back within the week: once.
  perform pg_temp.act(pg_temp.i('n1'));
  perform public.leave_circle(c);
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.circle_member_onboarding where circle_id = c and user_id = pg_temp.i('n1'))
    and not exists (select 1 from public.circle_member_onboarding_answers where circle_id = c and user_id = pg_temp.i('n1'))
    and not exists (select 1 from public.circle_member_guide_tasks where circle_id = c and user_id = pg_temp.i('n1')), 'leave: the member''s progress goes with them');
  perform pg_temp.act(pg_temp.i('n1'));
  perform public.accept_circle_invite(inv);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('n1')) and pg_temp.greetings(welcome_conv, pg_temp.i('n1')) = 1, 'greeting: coming back within a week is not announced again');
  perform pg_temp.expect(not exists (select 1 from public.circle_member_roles where circle_id = c and user_id = pg_temp.i('n1')), 'leave: and comes back with no roles');
  update public.messages set created_at = now() - interval '8 days' where conversation_id = welcome_conv and attachment ->> 'user_id' = pg_temp.i('n1')::text;
  perform pg_temp.act(pg_temp.i('n1'));
  perform public.leave_circle(c);
  perform public.accept_circle_invite(inv);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.greetings(welcome_conv, pg_temp.i('n1')) = 2, 'greeting: after a week, again');

  -- A bot is not announced.
  insert into public.circle_members (circle_id, user_id) values (c, pg_temp.i('robo'));
  perform pg_temp.expect(pg_temp.greetings(welcome_conv, pg_temp.i('robo')) = 0, 'greeting: a bot is not announced');

  -- Other ways in: a member adds a friend.
  insert into public.friendships (user_low_id, user_high_id) values (least(pg_temp.i('bob'), pg_temp.i('n2')), greatest(pg_temp.i('bob'), pg_temp.i('n2')));
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.invite_circle_members(c, array[pg_temp.i('n2')]);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.greetings(welcome_conv, pg_temp.i('n2')) = 1, 'greeting: a friend added by a member is announced');

  -- Greeting off: nobody is announced.
  perform pg_temp.act(pg_temp.i('mgr'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_greeting(%L, %L, null)', c, pg_temp.i('lounge'))) = '22023', 'settings: a voice channel is no place for it');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_greeting(%L, %L, null)', c, pg_temp.i('other_channel'))) = '22023', 'settings: nor a channel of another circle');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_greeting(%L, %L, %L)', c, pg_temp.i('welcome'), pg_temp.i('other_sticker'))) = '22023', 'settings: nor a sticker of another circle');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_greeting(%L, null, %L)', c, pg_temp.i('sticker'))) = 'ok', 'settings: turning it off');
  perform pg_temp.root();
  perform pg_temp.expect((select greeting_channel_id is null and greeting_sticker_id is null from public.circle_guide_settings where circle_id = c), 'settings: off drops the sticker too');
  perform pg_temp.act(pg_temp.i('n3'));
  perform public.accept_circle_invite(inv);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('n3')) and pg_temp.greetings(welcome_conv, pg_temp.i('n3')) = 0, 'greeting: off, nobody is announced');

  -- On again, without a sticker; and a greeting that fails never stops the join.
  perform pg_temp.act(pg_temp.i('mgr'));
  perform public.set_circle_greeting(c, pg_temp.i('welcome'), null);
  perform pg_temp.root();
  create function pg_temp.refuse_greeting() returns trigger language plpgsql as $f$
  begin
    if new.attachment ->> 'kind' = 'newcomer' then raise exception 'no greeting'; end if;
    return new;
  end $f$;
  create trigger zz_refuse_greeting before insert on public.messages for each row execute function pg_temp.refuse_greeting();
  perform pg_temp.act(pg_temp.i('n4'));
  perform public.accept_circle_invite(inv);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('n4')) and pg_temp.greetings(welcome_conv, pg_temp.i('n4')) = 0, 'greeting: one that cannot be written does not stop the join');
  drop trigger zz_refuse_greeting on public.messages;
  perform pg_temp.act(pg_temp.i('n5'));
  perform public.accept_circle_invite(inv);
  perform pg_temp.root();
  select * into msg from public.messages m where m.conversation_id = welcome_conv and m.attachment ->> 'user_id' = pg_temp.i('n5')::text;
  perform pg_temp.expect(msg.attachment ->> 'sticker_id' is null, 'greeting: with no sticker set, none is named');

  -- Suspended circles announce nobody (the join itself is refused there too).
  update public.circles set disabled_at = now(), disabled_mode = 'suspend' where id = c;
  perform pg_temp.act(pg_temp.i('n6'));
  perform pg_temp.expect(pg_temp.refused(format('select public.accept_circle_invite(%L)', inv)), 'suspended: nobody can join');
  perform pg_temp.root();
  update public.circles set disabled_at = null, disabled_mode = null where id = c;
  perform pg_temp.expect(pg_temp.greetings(welcome_conv, pg_temp.i('n6')) = 0, 'suspended: and nobody is announced');

  -- A deleted greeting channel turns the greeting off.
  delete from public.circle_channels where id = pg_temp.i('welcome');
  perform pg_temp.expect((select greeting_channel_id is null from public.circle_guide_settings where circle_id = c), 'settings: deleting the channel turns the greeting off');

  -- A deleted role is gone from the options and from the members.
  delete from public.circle_roles where id = pg_temp.i('voice');
  perform pg_temp.expect(not exists (select 1 from public.circle_onboarding_option_roles where role_id = pg_temp.i('voice')), 'cleanup: a deleted role leaves the options');
  -- A deleted circle takes it all with it.
  delete from public.circles where id = c;
  perform pg_temp.expect(not exists (select 1 from public.circle_onboarding_prompts where circle_id = c)
    and not exists (select 1 from public.circle_guide_tasks where circle_id = c)
    and not exists (select 1 from public.circle_guide_settings where circle_id = c)
    and not exists (select 1 from public.circle_member_onboarding where circle_id = c), 'cleanup: deleting the circle deletes the guide');
end $$;
\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'onboarding guide: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
