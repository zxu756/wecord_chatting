-- Behaviour checks for circle insights and invite tracking (C3 and C4:
-- migrations 202610230300 to 202610230320). Run by
-- test/supabase/circle_insights_test.dart against the local database: it
-- applies the migrations it needs in a transaction, plays people through the
-- join paths and the insights RPC, and rolls everything back. Run from the
-- repository root.
--
-- What it walks through: who a join is credited to on every path (invite
-- link, a friend added by a member, a request an invite made and a moderator
-- approved, skip-review links, Discover, invite-only circles, leaving and
-- coming back), the per-invite "brought / still here" numbers, the daily
-- aggregation (what counts as a message and as active, idempotence), the
-- join, leave and voice counters, who may read insights, the "<5" masking,
-- the small-circle rule, retention ratios, and that no invite code and no
-- per-person row ever leaves the database.
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
\i supabase/migrations/202610220600_join_requests_schema.sql
\i supabase/migrations/202610220610_join_requests_paths.sql
\i supabase/migrations/202610220620_join_request_rpcs.sql
\i supabase/migrations/202610220630_join_request_push.sql
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
create function pg_temp.pending(c uuid, who uuid) returns integer language sql as $$
  select count(*)::integer from public.circle_join_requests r
  where r.circle_id = c and r.user_id = who and r.status = 'pending'
$$;
-- The invite a member joined with, and the member behind it.
create function pg_temp.via(c uuid, who uuid) returns text language sql as $$
  select cm.joined_via_invite from public.circle_members cm where cm.circle_id = c and cm.user_id = who
$$;
create function pg_temp.by(c uuid, who uuid) returns uuid language sql as $$
  select cm.invited_by from public.circle_members cm where cm.circle_id = c and cm.user_id = who
$$;
-- How many joinings of [who] the invite log holds.
create function pg_temp.joins(c uuid, who uuid) returns integer language sql as $$
  select count(*)::integer from public.circle_invite_joins j where j.circle_id = c and j.user_id = who
$$;
create function pg_temp.ins(c uuid, days integer default 30, tz integer default 0) returns jsonb language sql as $$
  select public.get_circle_insights(c, days, tz)
$$;
create function pg_temp.today() returns date language sql as $$ select public.insights_today() $$;
grant execute on all functions in schema pg_temp to public;

-- ------------------------------------------------------------------ cast
-- Ada owns the circle. Mia moderates (kick_members: she can approve requests
-- and skip review, but cannot read insights). Bob is an ordinary member.
-- Vic holds view_audit_log, Mgr manage_circle, Adm administrator. Zed is an
-- outsider. j1..j20 come and go. Bob's friends: j3, j4, j6. Mia's: j7.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@ci.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'mia'),(3,'bob'),(4,'vic'),(5,'mgr'),(6,'adm'),(7,'zed'),(8,'robo')) v(n, name)
union all
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(16 + g), 2, '0'))::uuid, 'j' || g || '@ci.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from generate_series(1, 20) g;
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_ci', initcap(name)
from (values (1,'ada'),(2,'mia'),(3,'bob'),(4,'vic'),(5,'mgr'),(6,'adm'),(7,'zed'),(8,'robo')) v(n, name)
union all
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(16 + g), 2, '0'))::uuid, 'j' || g || '_ci', 'J' || g
from generate_series(1, 20) g;
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'mia'),(3,'bob'),(4,'vic'),(5,'mgr'),(6,'adm'),(7,'zed'),(8,'robo')) v(n, name)
union all
select 'j' || g, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(16 + g), 2, '0'))::uuid
from generate_series(1, 20) g;
update public.profiles set is_bot = true where id = pg_temp.i('robo');

insert into public.friendships (user_low_id, user_high_id)
select least(x.a, x.b), greatest(x.a, x.b)
from (values
  (pg_temp.i('ada'), pg_temp.i('bob')),
  (pg_temp.i('ada'), pg_temp.i('mia')),
  (pg_temp.i('ada'), pg_temp.i('vic')),
  (pg_temp.i('ada'), pg_temp.i('mgr')),
  (pg_temp.i('ada'), pg_temp.i('adm')),
  (pg_temp.i('bob'), pg_temp.i('j3')),
  (pg_temp.i('bob'), pg_temp.i('j4')),
  (pg_temp.i('bob'), pg_temp.i('j6')),
  (pg_temp.i('mia'), pg_temp.i('j7'))
) x(a, b);

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'circle', public.create_circle('Insights club',
  array[pg_temp.i('bob'), pg_temp.i('mia'), pg_temp.i('vic'), pg_temp.i('mgr'), pg_temp.i('adm')]);
select public.set_circle_discovery(pg_temp.i('circle'), true, 'about the club', 'other', 'en', '{}'::text[]);
insert into pg_temp.ids select 'modrole', public.create_circle_role(pg_temp.i('circle'), 'Mod', null, 32, false);
insert into pg_temp.ids select 'auditrole', public.create_circle_role(pg_temp.i('circle'), 'Auditor', null, 4096, false);
insert into pg_temp.ids select 'mgrrole', public.create_circle_role(pg_temp.i('circle'), 'Manager', null, 1 << 20, false);
insert into pg_temp.ids select 'adminrole', public.create_circle_role(pg_temp.i('circle'), 'Admin', null, 16384, false);
select public.set_member_roles(pg_temp.i('circle'), pg_temp.i('mia'), array[pg_temp.i('modrole')]);
select public.set_member_roles(pg_temp.i('circle'), pg_temp.i('vic'), array[pg_temp.i('auditrole')]);
select public.set_member_roles(pg_temp.i('circle'), pg_temp.i('mgr'), array[pg_temp.i('mgrrole')]);
select public.set_member_roles(pg_temp.i('circle'), pg_temp.i('adm'), array[pg_temp.i('adminrole')]);
insert into pg_temp.ids select 'dev', public.create_circle_channel(pg_temp.i('circle'), 'dev');
insert into pg_temp.ids select 'lounge', public.create_circle_channel(pg_temp.i('circle'), 'lounge', null, 'voice');
select pg_temp.root();

-- ===================================== 1. who a join is credited to
do $$
declare c uuid := pg_temp.i('circle'); inv text;
begin
  perform pg_temp.expect(pg_temp.via(c, pg_temp.i('ada')) is null and pg_temp.by(c, pg_temp.i('ada')) is null,
    'creating the circle credits nobody');
  perform pg_temp.expect(pg_temp.joins(c, pg_temp.i('ada')) = 0, 'and logs nothing');

  -- a. an invite link, circle open
  perform pg_temp.act(pg_temp.i('bob'));
  inv := public.create_circle_invite(c, null, null);
  insert into pg_temp.codes values ('inv_bob', inv);
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('j1'));
  perform public.accept_circle_invite(inv);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.via(c, pg_temp.i('j1')) = inv, 'link: the member remembers the link');
  perform pg_temp.expect(pg_temp.by(c, pg_temp.i('j1')) = pg_temp.i('bob'), 'link: and the member who made it');
  perform pg_temp.expect(pg_temp.joins(c, pg_temp.i('j1')) = 1, 'link: the join is logged');
  perform pg_temp.act(pg_temp.i('j1'));
  perform public.accept_circle_invite(inv);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.joins(c, pg_temp.i('j1')) = 1, 'link: following it again as a member credits nothing more');
  perform pg_temp.expect((select use_count from public.circle_invites where code = inv) = 1, 'link: and spends nothing');

  -- b. Discover
  perform pg_temp.act(pg_temp.i('j2'));
  perform public.join_public_circle(c);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('j2')), 'discover: joined');
  perform pg_temp.expect(pg_temp.via(c, pg_temp.i('j2')) is null and pg_temp.by(c, pg_temp.i('j2')) is null,
    'discover: nobody is credited');
  perform pg_temp.expect(pg_temp.joins(c, pg_temp.i('j2')) = 0, 'discover: nothing is logged');

  -- c. a member adds friends
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.invite_circle_members(c, array[pg_temp.i('j3'), pg_temp.i('j4')]);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.by(c, pg_temp.i('j3')) = pg_temp.i('bob') and pg_temp.by(c, pg_temp.i('j4')) = pg_temp.i('bob'),
    'friends: the member who added them is credited');
  perform pg_temp.expect(pg_temp.via(c, pg_temp.i('j3')) is null, 'friends: with no link');
  perform pg_temp.expect(pg_temp.joins(c, pg_temp.i('j3')) = 1 and pg_temp.joins(c, pg_temp.i('j4')) = 1, 'friends: and logged');
  perform pg_temp.expect(pg_temp.by(c, pg_temp.i('bob')) is null, 'friends: the member who added is not credited to themselves');

  -- d. apply mode: an invite link makes a request, a moderator approves
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_join_settings(c, 'apply', '[]'::jsonb);
  perform pg_temp.act(pg_temp.i('j5'));
  perform public.accept_circle_invite(inv);
  perform pg_temp.root();
  perform pg_temp.expect(not pg_temp.is_member(c, pg_temp.i('j5')) and pg_temp.pending(c, pg_temp.i('j5')) = 1,
    'apply link: a request, not a member');
  perform pg_temp.expect((select invite_code from public.circle_join_requests where circle_id = c and user_id = pg_temp.i('j5')) = inv,
    'apply link: the request remembers the link');
  perform pg_temp.expect(pg_temp.joins(c, pg_temp.i('j5')) = 0, 'apply link: nothing is logged before approval');
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.decide_join_request(
    (select id from public.circle_join_requests where circle_id = c and user_id = pg_temp.i('j5') and status = 'pending'),
    true);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.via(c, pg_temp.i('j5')) = inv, 'apply link: approved, the member remembers the link');
  perform pg_temp.expect(pg_temp.by(c, pg_temp.i('j5')) = pg_temp.i('bob'), 'apply link: and the link''s creator, not the moderator');
  perform pg_temp.expect(pg_temp.joins(c, pg_temp.i('j5')) = 1, 'apply link: logged once approved');

  -- e. apply mode: a member adds a friend, a request, approved
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.invite_circle_members(c, array[pg_temp.i('j6')]);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.pending(c, pg_temp.i('j6')) = 1, 'apply friend: a request');
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.decide_join_request(
    (select id from public.circle_join_requests where circle_id = c and user_id = pg_temp.i('j6') and status = 'pending'),
    true);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.by(c, pg_temp.i('j6')) = pg_temp.i('bob'), 'apply friend: approved, the member who added is credited');
  perform pg_temp.expect(pg_temp.via(c, pg_temp.i('j6')) is null, 'apply friend: with no link');
  perform pg_temp.expect(pg_temp.joins(c, pg_temp.i('j6')) = 1, 'apply friend: logged');

  -- f. a link that skips review
  perform pg_temp.act(pg_temp.i('mia'));
  inv := public.create_circle_invite_v2(c, null, null, true);
  insert into pg_temp.codes values ('inv_mia', inv);
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('j7'));
  perform public.accept_circle_invite(inv);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('j7')), 'skip review: joins at once');
  perform pg_temp.expect(pg_temp.via(c, pg_temp.i('j7')) = inv and pg_temp.by(c, pg_temp.i('j7')) = pg_temp.i('mia'),
    'skip review: credited to the link and to Mia');

  -- g. Discover in apply mode, approved: nobody is credited, not the moderator
  perform pg_temp.act(pg_temp.i('j8'));
  perform public.join_public_circle(c);
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.decide_join_request(
    (select id from public.circle_join_requests where circle_id = c and user_id = pg_temp.i('j8') and status = 'pending'),
    true);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('j8')), 'apply discover: approved');
  perform pg_temp.expect(pg_temp.via(c, pg_temp.i('j8')) is null and pg_temp.by(c, pg_temp.i('j8')) is null,
    'apply discover: nobody is credited, the moderator who approved included');
  perform pg_temp.expect(pg_temp.joins(c, pg_temp.i('j8')) = 0, 'apply discover: nothing logged');

  -- h. a request an invite made and a moderator denied brings nobody
  perform pg_temp.act(pg_temp.i('j9'));
  perform public.accept_circle_invite(pg_temp.code('inv_bob'));
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.decide_join_request(
    (select id from public.circle_join_requests where circle_id = c and user_id = pg_temp.i('j9') and status = 'pending'),
    false);
  perform pg_temp.root();
  perform pg_temp.expect(not pg_temp.is_member(c, pg_temp.i('j9')) and pg_temp.joins(c, pg_temp.i('j9')) = 0,
    'denied: not a member, not counted as brought');

  -- i. invite only: the link is the way in
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_join_settings(c, 'invite_only', '[]'::jsonb);
  perform pg_temp.act(pg_temp.i('j10'));
  perform public.accept_circle_invite(pg_temp.code('inv_bob'));
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.via(c, pg_temp.i('j10')) = pg_temp.code('inv_bob') and pg_temp.by(c, pg_temp.i('j10')) = pg_temp.i('bob'),
    'invite only: the link is credited');
  perform pg_temp.act(pg_temp.i('j11'));
  perform public.accept_circle_invite(pg_temp.code('inv_bob'));
  perform pg_temp.act(pg_temp.i('j12'));
  perform public.accept_circle_invite(pg_temp.code('inv_bob'));
  perform pg_temp.act(pg_temp.i('j13'));
  perform public.accept_circle_invite(pg_temp.code('inv_bob'));
  perform pg_temp.act(pg_temp.i('j14'));
  perform public.accept_circle_invite(pg_temp.code('inv_bob'));
  perform pg_temp.act(pg_temp.i('j15'));
  perform public.accept_circle_invite(pg_temp.code('inv_bob'));
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_members where circle_id = c and joined_via_invite = pg_temp.code('inv_bob')) = 8,
    'invite only: eight members now joined with Bob''s link');
end $$;

-- ===================================== 2. leaving and coming back
do $$
declare c uuid := pg_temp.i('circle');
begin
  -- Make j1's first joining two days old, so the log can tell two joinings
  -- apart (a real second joining is in another transaction).
  update public.circle_members set created_at = created_at - interval '2 days'
    where circle_id = c and user_id = pg_temp.i('j1');
  update public.circle_invite_joins set joined_at = joined_at - interval '2 days'
    where circle_id = c and user_id = pg_temp.i('j1');

  delete from public.conversation_members m using public.circle_channels cc
    where cc.circle_id = c and m.conversation_id = cc.conversation_id and m.user_id = pg_temp.i('j1');
  delete from public.circle_members where circle_id = c and user_id = pg_temp.i('j1');

  perform pg_temp.act(pg_temp.i('j1'));
  perform public.accept_circle_invite(pg_temp.code('inv_mia'));
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.via(c, pg_temp.i('j1')) = pg_temp.code('inv_mia') and pg_temp.by(c, pg_temp.i('j1')) = pg_temp.i('mia'),
    'rejoin: credited to the new link');
  perform pg_temp.expect(pg_temp.joins(c, pg_temp.i('j1')) = 2, 'rejoin: both joinings are in the log');
  perform pg_temp.expect((select count(*) from public.circle_invite_joins where circle_id = c and invite_code = pg_temp.code('inv_bob') and user_id = pg_temp.i('j1')) = 1,
    'rejoin: the first link still remembers bringing j1');
end $$;

-- ===================================== 3. brought and still here, per invite
do $$
declare c uuid := pg_temp.i('circle');
begin
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(
    (select brought from public.get_circle_invite_stats(c) where code = pg_temp.code('inv_bob')) = 8,
    'stats: Bob''s link brought 8 (j1 before they left, j5, j10 to j15)');
  perform pg_temp.expect(
    (select remaining from public.get_circle_invite_stats(c) where code = pg_temp.code('inv_bob')) = 7,
    'stats: 7 are still here (j1 left that joining)');
  perform pg_temp.expect((select count(*) from public.get_circle_invite_stats(c)) = 1, 'stats: a member sees their own links only');
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(
    (select brought from public.get_circle_invite_stats(c) where code = pg_temp.code('inv_mia')) = 2
    and (select remaining from public.get_circle_invite_stats(c) where code = pg_temp.code('inv_mia')) = 2,
    'stats: Mia''s skip-review link brought 2, both here');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect((select count(*) from public.get_circle_invite_stats(c)) = 2, 'stats: the owner sees every link');
  perform pg_temp.act(pg_temp.i('zed'));
  perform pg_temp.expect((select count(*) from public.get_circle_invite_stats(c)) = 0, 'stats: an outsider sees nothing');
  perform pg_temp.act(null);
  perform pg_temp.must_refuse(format('select * from public.get_circle_invite_stats(%L)', c), 'stats: nobody signed in is refused');
  perform pg_temp.root();
end $$;

-- ===================================== 4. the counters and the aggregation
do $$
declare
  c uuid := pg_temp.i('circle');
  d date := pg_temp.today() - 2;
  general uuid;
  general_conv uuid;
  dev_conv uuid;
  hook uuid;
  members_total integer;
  s public.circle_daily_stats%rowtype;
begin
  -- Joins and leaves are counted as they happen (today).
  select * into s from public.circle_daily_stats where circle_id = c and day = pg_temp.today();
  perform pg_temp.expect(s.joined = 6 + 15 and s.left_members = 1,
    'counters: 6 at creation, 15 joinings after (j1 twice), and one leave');

  -- From here the members joined three days ago.
  update public.circle_members set created_at = created_at - interval '3 days' where circle_id = c;
  update public.circle_invite_joins set joined_at = joined_at - interval '3 days' where circle_id = c;
  select count(*) into members_total from public.circle_members where circle_id = c;
  perform pg_temp.expect(members_total = 6 + 14, 'there are 20 members');

  select cc.conversation_id into general_conv from public.circle_channels cc
    where cc.circle_id = c order by cc.position, cc.created_at limit 1;
  select cc.conversation_id into dev_conv from public.circle_channels cc where cc.id = pg_temp.i('dev');

  insert into public.circle_webhooks (circle_id, channel_id, name, token_hash, created_by)
  values (c, (select id from public.circle_channels where conversation_id = general_conv), 'hook', repeat('0', 64), pg_temp.i('ada'))
  returning id into hook;

  alter table public.messages disable trigger user;
  insert into public.messages (conversation_id, sender_id, type, body, created_at, recalled_at, review_state, webhook_id)
  select conv, who, 'text', 'm', (d::timestamp at time zone 'UTC') + at_time, recalled, review, hk
  from (values
    -- counted: Ada 6 (one on the stroke of midnight), Bob 3, j1 1
    (general_conv, pg_temp.i('ada'), interval '0', null::timestamptz, null::text, null::uuid),
    (general_conv, pg_temp.i('ada'), interval '9 hours', null, null, null),
    (general_conv, pg_temp.i('ada'), interval '9 hours 10 minutes', null, null, null),
    (general_conv, pg_temp.i('ada'), interval '9 hours 20 minutes', null, null, null),
    (general_conv, pg_temp.i('ada'), interval '9 hours 40 minutes', null, null, null),
    (general_conv, pg_temp.i('ada'), interval '9 hours 50 minutes', null, null, null),
    (general_conv, pg_temp.i('bob'), interval '9 hours 30 minutes', null, null, null),
    (general_conv, pg_temp.i('bob'), interval '10 hours', null, null, null),
    (dev_conv, pg_temp.i('bob'), interval '14 hours 5 minutes', null, null, null),
    (dev_conv, pg_temp.i('j1'), interval '23 hours 59 minutes', null, null, null),
    -- not counted
    (general_conv, pg_temp.i('bob'), interval '9 hours 45 minutes', now(), null, null),
    (general_conv, pg_temp.i('mia'), interval '11 hours', null, 'held', null),
    (general_conv, pg_temp.i('j3'), interval '11 hours 5 minutes', null, 'removed', null),
    (general_conv, pg_temp.i('robo'), interval '12 hours', null, null, null),
    (general_conv, pg_temp.i('ada'), interval '12 hours 10 minutes', null, null, hook),
    (general_conv, pg_temp.i('ada'), interval '-1 second', null, null, null),
    (general_conv, pg_temp.i('ada'), interval '1 day', null, null, null)
  ) v(conv, who, at_time, recalled, review, hk);
  alter table public.messages enable trigger user;

  perform pg_temp.expect(public.aggregate_circle_insights(d) >= 1, 'aggregate: writes a row for the circle');
  select * into s from public.circle_daily_stats where circle_id = c and day = d;
  perform pg_temp.expect(s.messages = 10, 'aggregate: 10 messages (recalled, held, removed, bot, webhook and other days left out)');
  perform pg_temp.expect(s.active_members = 3, 'aggregate: 3 people spoke');
  perform pg_temp.expect(s.members_total = members_total, 'aggregate: members at the end of the day');
  perform pg_temp.expect(s.joined = 0, 'aggregate: the day''s joins come from the counters, none that day');
  perform pg_temp.expect(s.hourly[1] = 1 and s.hourly[10] = 6 and s.hourly[11] = 1 and s.hourly[15] = 1 and s.hourly[24] = 1
    and (select sum(x) from unnest(s.hourly) x) = 10, 'aggregate: messages per UTC hour');
  perform pg_temp.expect(jsonb_array_length(s.top_channels) = 2
    and (s.top_channels -> 0 ->> 'count')::integer = 8 and (s.top_channels -> 1 ->> 'count')::integer = 2
    and (s.top_channels -> 1 ->> 'channel_id')::uuid = pg_temp.i('dev'),
    'aggregate: busiest channels, most first');
  perform pg_temp.expect((select count(*) from public.circle_member_daily where circle_id = c and day = d) = 3,
    'aggregate: only whether each person was active');
  perform pg_temp.expect(not exists (
    select 1 from public.circle_member_daily where circle_id = c and day = d and user_id = pg_temp.i('robo')),
    'aggregate: a bot is not an active member');

  perform public.aggregate_circle_insights(d);
  perform pg_temp.expect((select messages from public.circle_daily_stats where circle_id = c and day = d) = 10
    and (select count(*) from public.circle_daily_stats where circle_id = c and day = d) = 1
    and (select count(*) from public.circle_member_daily where circle_id = c and day = d) = 3,
    'aggregate: running a day again changes nothing');

  -- Voice time is added when a person leaves the channel.
  insert into public.voice_states (channel_id, user_id, circle_id, joined_at)
  select cc.id, pg_temp.i('bob'), c, now() - interval '95 minutes'
  from public.circle_channels cc where cc.id = pg_temp.i('lounge');
  insert into public.voice_states (channel_id, user_id, circle_id, joined_at)
  select cc.id, pg_temp.i('j2'), c, now() - interval '20 hours'
  from public.circle_channels cc where cc.id = pg_temp.i('lounge');
  delete from public.voice_states where circle_id = c;
  perform pg_temp.expect((select voice_minutes from public.circle_daily_stats where circle_id = c and day = pg_temp.today()) = 95 + 720,
    'voice: minutes are added on leaving, 12 hours at most per session');
  perform pg_temp.expect((select count(*) from public.circle_member_daily where circle_id = c and day = pg_temp.today()) = 2,
    'voice: and the two people count as active that day');

  -- The nightly run.
  perform pg_temp.expect(public.run_circle_insights() >= 3, 'nightly: runs for the days before today');
  perform pg_temp.expect((select messages from public.circle_daily_stats where circle_id = c and day = d) = 10,
    'nightly: and does not disturb a day already written');

  -- Clients cannot call or read any of it.
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.must_refuse(format('select public.aggregate_circle_insights(%L)', d), 'a member cannot run the aggregation');
  perform pg_temp.must_refuse('select public.run_circle_insights()', 'a member cannot run the nightly job');
  perform pg_temp.must_refuse('select * from public.circle_daily_stats', 'the daily stats are closed to clients');
  perform pg_temp.must_refuse('select * from public.circle_member_daily', 'who was active is closed to clients');
  perform pg_temp.must_refuse('select * from public.circle_invite_joins', 'the invite log is closed to clients');
  perform pg_temp.root();
end $$;

-- ===================================== 5. who may read insights
do $$
declare c uuid := pg_temp.i('circle'); who text;
begin
  foreach who in array array['ada', 'vic', 'mgr', 'adm'] loop
    perform pg_temp.act(pg_temp.i(who));
    perform pg_temp.expect(pg_temp.state(format('select public.get_circle_insights(%L, 30, 0)', c)) = 'ok',
      'permission: ' || who || ' can read insights');
  end loop;
  foreach who in array array['mia', 'bob', 'zed', 'j5'] loop
    perform pg_temp.act(pg_temp.i(who));
    perform pg_temp.expect(pg_temp.state(format('select public.get_circle_insights(%L, 30, 0)', c)) = '42501',
      'permission: ' || who || ' cannot (a moderator, a member, an outsider)');
  end loop;
  perform pg_temp.act(null);
  perform pg_temp.must_refuse(format('select public.get_circle_insights(%L, 30, 0)', c), 'permission: nobody signed in cannot');
  perform pg_temp.root();
end $$;

-- ===================================== 6. masking
do $$
declare
  c uuid := pg_temp.i('circle');
  t date := pg_temp.today();
  r jsonb;
  dow integer;
  wanted record;
begin
  -- Controlled days next to the aggregated one (today - 2):
  --   t-3: 3 messages, 4 active   t-4: 7 messages, 5 active   t-5: 20 joined (and the nightly run gave t-3 the 20 who joined that day)
  -- (the nightly run above already wrote t-3 and t-1: overwrite t-3)
  insert into public.circle_daily_stats (circle_id, day, members_total, messages, active_members) values
    (c, t - 3, 22, 3, 4), (c, t - 4, 21, 7, 5)
  on conflict (circle_id, day) do update
  set members_total = excluded.members_total, messages = excluded.messages, active_members = excluded.active_members;
  insert into public.circle_daily_stats (circle_id, day, members_total, joined) values (c, t - 5, 3, 20);
  insert into public.circle_member_daily (circle_id, day, user_id)
    select c, t - 4, pg_temp.i(x) from unnest(array['j3','j4','j5','j6','j7']) x;
  -- People active between 14 and 8 days ago: 8, of whom 7 were active last week.
  insert into public.circle_member_daily (circle_id, day, user_id)
    select c, t - 10, pg_temp.i(x) from unnest(array['ada','bob','j1','j3','j4','j5','j6','mgr']) x;

  perform pg_temp.act(pg_temp.i('ada'));
  r := pg_temp.ins(c, 30, 0);
  perform pg_temp.root();

  perform pg_temp.expect((r ->> 'small')::boolean = false, 'mask: a circle of 20 is not small');
  perform pg_temp.expect((r ->> 'members_now')::integer = 20, 'mask: members now');
  perform pg_temp.expect(jsonb_array_length(r -> 'series') = 30, 'mask: one entry per day of the range');
  perform pg_temp.expect((r -> 'series' -> 29 ->> 'day')::date = t - 1, 'mask: the range ends yesterday');
  perform pg_temp.expect((select (e ->> 'messages')::integer from jsonb_array_elements(r -> 'series') e where (e ->> 'day')::date = t - 2) = 10,
    'mask: 10 messages are shown');
  perform pg_temp.expect((select (e ->> 'active')::integer from jsonb_array_elements(r -> 'series') e where (e ->> 'day')::date = t - 2) = -1,
    'mask: 3 active members show as <5');
  perform pg_temp.expect((select (e ->> 'messages')::integer from jsonb_array_elements(r -> 'series') e where (e ->> 'day')::date = t - 3) = -1,
    'mask: 3 messages show as <5');
  perform pg_temp.expect((select (e ->> 'active')::integer from jsonb_array_elements(r -> 'series') e where (e ->> 'day')::date = t - 3) = -1,
    'mask: 4 active members show as <5');
  perform pg_temp.expect((select (e ->> 'messages')::integer from jsonb_array_elements(r -> 'series') e where (e ->> 'day')::date = t - 4) = 7
    and (select (e ->> 'active')::integer from jsonb_array_elements(r -> 'series') e where (e ->> 'day')::date = t - 4) = 5,
    'mask: 7 and 5 are shown');
  perform pg_temp.expect((select (e ->> 'messages')::integer from jsonb_array_elements(r -> 'series') e where (e ->> 'day')::date = t - 20) = 0,
    'mask: a day with nothing is 0, not <5');
  perform pg_temp.expect((select (e ->> 'members')::integer from jsonb_array_elements(r -> 'series') e where (e ->> 'day')::date = t - 5) = -1,
    'mask: a member total of 3 shows as <5');
  perform pg_temp.expect((r -> 'totals' ->> 'messages')::integer = 21, 'totals: messages add up (10 + 3 + 7, and 1 just after midnight)');
  perform pg_temp.expect((r -> 'totals' ->> 'active')::integer = 9, 'totals: distinct people active over the range');
  perform pg_temp.expect((r -> 'totals' ->> 'voice_minutes')::integer = 0, 'totals: no voice before today');

  -- The weekday by hour map: 6 messages at 09 UTC on the weekday of t - 2.
  dow := extract(dow from t - 2)::integer;
  perform pg_temp.expect((r -> 'heatmap' ->> 'weekday_start')::integer = 0 and jsonb_array_length(r -> 'heatmap' -> 'rows') = 7
    and jsonb_array_length(r -> 'heatmap' -> 'rows' -> 0) = 24, 'heatmap: 7 weekdays by 24 hours');
  perform pg_temp.expect((r -> 'heatmap' -> 'rows' -> dow ->> 9)::integer = 6, 'heatmap: 6 at 09:00 shows');
  perform pg_temp.expect((r -> 'heatmap' -> 'rows' -> dow ->> 0)::integer = -1, 'heatmap: 1 message at 00:00 shows as <5');
  perform pg_temp.expect((r -> 'heatmap' -> 'rows' -> dow ->> 3)::integer = 0, 'heatmap: an empty hour is 0');
  perform pg_temp.act(pg_temp.i('ada'));
  r := pg_temp.ins(c, 30, 120);
  perform pg_temp.expect((r -> 'heatmap' -> 'rows' -> dow ->> 11)::integer = 6 and (r -> 'heatmap' -> 'rows' -> dow ->> 9)::integer = 0,
    'heatmap: UTC+2 moves the cell to 11:00');
  r := pg_temp.ins(c, 30, -600);
  perform pg_temp.expect((r -> 'heatmap' -> 'rows' -> ((dow + 6) % 7) ->> 23)::integer = 6,
    'heatmap: UTC-10 moves it to 23:00 the day before');
  r := pg_temp.ins(c, 30, 0);
  perform pg_temp.root();

  -- Channels: names and masking.
  perform pg_temp.expect(jsonb_array_length(r -> 'channels') = 2
    and (r -> 'channels' -> 0 ->> 'messages')::integer = 10
    and (r -> 'channels' -> 1 ->> 'name') = 'dev' and (r -> 'channels' -> 1 ->> 'messages')::integer = -1,
    'channels: the busiest first, 2 messages shown as <5');

  -- Invites: by who made the link, never by code.
  perform pg_temp.expect(jsonb_array_length(r -> 'invites') = 2
    and (r -> 'invites' -> 0 ->> 'brought')::integer = 8 and (r -> 'invites' -> 0 ->> 'remaining')::integer = 7
    and (r -> 'invites' -> 0 ->> 'created_by_name') = 'Bob'
    and (r -> 'invites' -> 1 ->> 'brought')::integer = -1 and (r -> 'invites' -> 1 ->> 'remaining')::integer = -1,
    'invites: Bob''s link brought 8 and 7 are here; Mia''s numbers are <5');
  perform pg_temp.expect(position(pg_temp.code('inv_bob') in r::text) = 0 and position(pg_temp.code('inv_mia') in r::text) = 0,
    'invites: no invite code is in the answer');
  perform pg_temp.expect((r -> 'inviters' -> 0 ->> 'name') = 'Bob' and (r -> 'inviters' -> 0 ->> 'brought')::integer = 11
    and (r -> 'inviters' -> 0 ->> 'remaining')::integer = 10,
    'inviters: Bob brought 11 (8 by link, 3 friends), 10 are here');
  perform pg_temp.expect(position('"user_id"' in r::text) = 0, 'no per-person row is in the answer');

  -- Retention: ratios, and only with enough people behind them.
  perform pg_temp.expect((r -> 'retention' ->> 'joined_kept')::numeric = 0.5, 'retention: 20 of the 40 who joined in the range are still here');
  perform pg_temp.expect((r -> 'retention' ->> 'active_returning')::numeric = 0.88, 'retention: 7 of 8 came back');

  delete from public.circle_member_daily where circle_id = c and day = t - 10 and user_id in (pg_temp.i('ada'), pg_temp.i('bob'), pg_temp.i('j1'), pg_temp.i('j3'));
  update public.circle_daily_stats set joined = 0 where circle_id = c;
  perform pg_temp.act(pg_temp.i('ada'));
  r := pg_temp.ins(c, 30, 0);
  perform pg_temp.root();
  perform pg_temp.expect(r -> 'retention' ->> 'active_returning' is null and r -> 'retention' ->> 'joined_kept' is null,
    'retention: no ratio when fewer than 5 people stand behind it');

  -- A shorter range sees fewer days.
  perform pg_temp.act(pg_temp.i('ada'));
  r := pg_temp.ins(c, 7, 0);
  perform pg_temp.root();
  perform pg_temp.expect(jsonb_array_length(r -> 'series') = 7 and (r -> 'totals' ->> 'messages')::integer = 21,
    'range: 7 days still holds the three busy days');
  perform pg_temp.act(pg_temp.i('ada'));
  r := pg_temp.ins(c, 3, 0);
  perform pg_temp.root();
  perform pg_temp.expect(jsonb_array_length(r -> 'series') = 3 and (r -> 'totals' ->> 'messages')::integer = 14,
    'range: 3 days holds the 10, the 3 and the 1');
end $$;

-- ===================================== 7. a small circle shows nothing
do $$
declare t uuid; r jsonb;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  t := public.create_circle('Tiny', array[pg_temp.i('bob')]);
  perform pg_temp.root();
  insert into public.circle_daily_stats (circle_id, day, members_total, messages, active_members, voice_minutes, hourly)
  values (t, pg_temp.today() - 1, 2, 50, 2, 90, array[50,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]);
  insert into public.circle_member_daily (circle_id, day, user_id)
    select t, pg_temp.today() - g, pg_temp.i('bob') from generate_series(8, 14) g;
  perform pg_temp.act(pg_temp.i('ada'));
  r := pg_temp.ins(t, 30, 0);
  perform pg_temp.root();
  perform pg_temp.expect((r ->> 'small')::boolean and (r ->> 'members_now')::integer = -1, 'small: 2 members show as <5');
  perform pg_temp.expect((select (e ->> 'messages')::integer from jsonb_array_elements(r -> 'series') e where (e ->> 'day')::date = pg_temp.today() - 1) = -1,
    'small: 50 messages are hidden too, with so few people any number is somebody');
  perform pg_temp.expect((select (e ->> 'messages')::integer from jsonb_array_elements(r -> 'series') e where (e ->> 'day')::date = pg_temp.today() - 3) = -1,
    'small: even an empty day is hidden');
  perform pg_temp.expect((r -> 'totals' ->> 'messages')::integer = -1 and (r -> 'totals' ->> 'voice_minutes')::integer = -1
    and (r -> 'totals' ->> 'active')::integer = -1, 'small: the totals are hidden');
  perform pg_temp.expect(not exists (
    select 1 from jsonb_array_elements(r -> 'heatmap' -> 'rows') rw, jsonb_array_elements(rw) cell where cell::text <> '-1'),
    'small: every cell of the map is hidden');
  perform pg_temp.expect(r -> 'retention' ->> 'active_returning' is null and r -> 'retention' ->> 'joined_kept' is null, 'small: no retention');

  -- A circle going away takes its members and the counters with it.
  perform pg_temp.expect(pg_temp.state(format('delete from public.circles where id = %L', t)) = 'ok',
    'a circle can still be deleted with its counters');
end $$;
\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'circle insights: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
