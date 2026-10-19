-- Behaviour checks for the profile and social extras (B4 status bubbles, B5
-- birthdays, A14 mutuals and add sources, J4 support links: migrations
-- 202610230600 to 202610230650). Run by test/supabase/profile_social_test.dart
-- against the local database: it applies the migrations it needs in a
-- transaction, plays people through them, and rolls everything back. Run from
-- the repository root.
--
-- What it walks through: who sees a status (everyone, friends, starred
-- friends, only me; blocked people; expiry; the closed raw columns), the
-- birthday (only month and day, who sees it, the leap day, the cards, the
-- 9 o'clock reminder per device zone and language, once a year, every reason
-- not to be told), the support-link allow list and who can read or write a
-- profile's and a circle's links, where a friendship came from (checked
-- claims, copied to the friendship), and the mutual friends, groups and
-- circles (names for friends only, numbers for strangers, blocks, profile
-- visibility, deleted accounts).
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
\i supabase/migrations/202610230300_circle_invite_tracking.sql
\i supabase/migrations/202610230310_circle_insights_data.sql
\i supabase/migrations/202610230320_circle_insights_rpc.sql
\i supabase/migrations/202610230600_status_visibility.sql
\i supabase/migrations/202610230610_profile_birthday.sql
\i supabase/migrations/202610230620_birthday_push.sql
\i supabase/migrations/202610230630_support_links.sql
\i supabase/migrations/202610230640_friend_source.sql
\i supabase/migrations/202610230650_mutuals.sql
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


-- Which hour it is for a device: a zone name (Etc/GMT+n) whose wall clock
-- shows [hour] right now.
create function pg_temp.zone_at(hour integer) returns text language plpgsql as $$
declare
  utc_hour integer := extract(hour from (now() at time zone 'UTC'))::integer;
  k integer := (((hour - utc_hour) + 12) % 24 + 24) % 24 - 12;
begin
  return case when k > 0 then 'Etc/GMT-' || k when k < 0 then 'Etc/GMT+' || (-k) else 'UTC' end;
end $$;
create function pg_temp.today_in(zone text) returns date language sql as $$
  select (now() at time zone zone)::date
$$;
create function pg_temp.befriend(a uuid, b uuid) returns void language sql as $$
  insert into public.friendships (user_low_id, user_high_id)
  values (least(a, b), greatest(a, b)) on conflict do nothing
$$;
create function pg_temp.status_of(owner uuid) returns text language sql security definer as $$
  select public.custom_status(p) ->> 'text' from public.profiles p where p.id = owner
$$;
create function pg_temp.extras(target uuid) returns jsonb language sql as $$
  select public.get_profile_extras(target)
$$;
create function pg_temp.due(recipient uuid, friend uuid) returns boolean language sql as $$
  select exists (select 1 from public.birthday_due_reminders() d where d.recipient_id = recipient and d.friend_id = friend)
$$;
grant execute on all functions in schema pg_temp to public;

-- ------------------------------------------------------------------ cast
-- ada is the person whose status, birthday and links are looked at. bob is
-- her friend and she starred him, cat is her friend (not starred), dan is a
-- stranger, eve is somebody she blocked, flo is somebody who blocked her
-- (both are strangers). robo is a bot. zed has deleted nothing yet.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@ps.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'flo'),(7,'robo'),(8,'gus'),(9,'hal'),(10,'ivy')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_ps', initcap(name)
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'flo'),(7,'robo'),(8,'gus'),(9,'hal'),(10,'ivy')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan'),(5,'eve'),(6,'flo'),(7,'robo'),(8,'gus'),(9,'hal'),(10,'ivy')) v(n, name);
update public.profiles set is_bot = true where id = pg_temp.i('robo');

select pg_temp.befriend(pg_temp.i('ada'), pg_temp.i('bob'));
select pg_temp.befriend(pg_temp.i('ada'), pg_temp.i('cat'));
select pg_temp.befriend(pg_temp.i('ada'), pg_temp.i('gus'));
insert into public.friend_stars (owner_id, friend_id) values (pg_temp.i('ada'), pg_temp.i('bob'));
insert into public.blocks (blocker_id, blocked_id) values
  (pg_temp.i('ada'), pg_temp.i('eve')),
  (pg_temp.i('flo'), pg_temp.i('ada'));

-- ===================================== 1. status visibility (B4)
do $$
declare ada uuid := pg_temp.i('ada');
begin
  perform pg_temp.act(ada);
  perform public.set_custom_status('🎯', 'Focusing', now() + interval '2 hours');
  perform pg_temp.root();

  -- The default is the way it always was: everyone.
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(pg_temp.status_of(ada) = 'Focusing', 'default: a stranger still sees the status');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.status_of(ada) is null, 'even for everyone: a person ada blocked sees nothing');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('flo'));
  perform pg_temp.expect(pg_temp.status_of(ada) = 'Focusing', 'a person who blocked ada can still see what she shares with everyone (it is ada''s block that hides)');
  perform pg_temp.root();

  -- friends
  perform pg_temp.act(ada);
  perform pg_temp.expect(public.set_status_visibility('friends') = 'friends', 'ada chooses friends');
  perform pg_temp.expect(public.get_my_status_visibility() = 'friends', 'and reads her choice back');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.status_of(ada) = 'Focusing', 'friends: a friend sees it');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(pg_temp.status_of(ada) is null, 'friends: a stranger does not');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.status_of(ada) is null, 'friends: a blocked person does not');
  perform pg_temp.root();

  -- starred
  perform pg_temp.act(ada);
  perform public.set_status_visibility('starred');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.status_of(ada) = 'Focusing', 'starred: the starred friend sees it');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.status_of(ada) is null, 'starred: an unstarred friend does not');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(pg_temp.status_of(ada) is null, 'starred: a stranger does not');
  perform pg_temp.root();
  -- A star the other way round (bob starred ada) does not count.
  insert into public.friend_stars (owner_id, friend_id) values (pg_temp.i('cat'), ada);
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.status_of(ada) is null, 'starred: it is ada''s star that counts, not the friend''s');
  perform pg_temp.root();

  -- list_friend_statuses: bob is told, cat is not
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt('select * from public.list_friend_statuses() where user_id = ' || quote_literal(ada)) = 1,
    'the bubble list has ada for the starred friend');
  perform pg_temp.expect((select emoji from public.list_friend_statuses() where user_id = ada) = '🎯', 'with her emoji');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.cnt('select * from public.list_friend_statuses() where user_id = ' || quote_literal(ada)) = 0,
    'the bubble list leaves her out for the unstarred friend');
  perform pg_temp.root();

  -- self
  perform pg_temp.act(ada);
  perform public.set_status_visibility('self');
  perform pg_temp.expect(pg_temp.status_of(ada) = 'Focusing', 'only me: ada still sees her own');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.status_of(ada) is null, 'only me: not even the starred friend');
  perform pg_temp.root();

  -- profile summary and circle details carry the same rule (they use custom_status)
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect((select custom_status from public.get_profile_summary(ada)) is null,
    'get_profile_summary shows no status that is hidden');
  perform pg_temp.root();
  perform pg_temp.act(ada);
  perform public.set_status_visibility('everyone');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect((select custom_status ->> 'text' from public.get_profile_summary(ada)) = 'Focusing',
    'and shows it again for everyone');
  perform pg_temp.root();

  -- expiry
  update public.profiles set status_expires_at = now() - interval '1 minute' where id = ada;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.status_of(ada) is null, 'an expired status is gone');
  perform pg_temp.expect(pg_temp.cnt('select * from public.list_friend_statuses()') = 0, 'and out of the bubble list');
  perform pg_temp.root();
  update public.profiles set status_expires_at = now() + interval '1 hour' where id = ada;

  -- bots and deleted friends have no bubbles
  perform pg_temp.act(pg_temp.i('gus'));
  perform public.set_custom_status('🍵', 'Tea', null);
  perform pg_temp.root();
  perform pg_temp.act(ada);
  perform pg_temp.expect(pg_temp.cnt('select * from public.list_friend_statuses() where user_id = ' || quote_literal(pg_temp.i('gus'))) = 1,
    'a friend with a status is in the list');
  perform pg_temp.root();
  update public.profiles set deleted_at = now() where id = pg_temp.i('gus');
  perform pg_temp.act(ada);
  perform pg_temp.expect(pg_temp.cnt('select * from public.list_friend_statuses() where user_id = ' || quote_literal(pg_temp.i('gus'))) = 0,
    'a deleted account is not');
  perform pg_temp.root();
  update public.profiles set deleted_at = null where id = pg_temp.i('gus');

  -- the raw columns are closed
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.must_refuse('select status_text from public.profiles', 'the raw status columns cannot be read');
  perform pg_temp.must_refuse('select status_emoji, status_expires_at from public.profiles', 'neither emoji nor expiry');
  perform pg_temp.expect(pg_temp.cnt('select id, username, display_name, avatar_url from public.profiles') >= 9,
    'while names and avatars still can');
  perform pg_temp.expect(pg_temp.state('select public.set_status_visibility(''nobody'')') = '22023', 'a made-up choice is a 22023');
  perform pg_temp.root();
  perform pg_temp.act(null);
  perform pg_temp.must_refuse('select * from public.list_friend_statuses()', 'signed-out callers cannot list statuses');
  perform pg_temp.root();
end $$;

-- ===================================== 2. birthday (B5)
do $$
declare ada uuid := pg_temp.i('ada'); r jsonb;
begin
  perform pg_temp.expect(not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name ilike '%birth%year%'),
    'no birth year is stored anywhere');

  perform pg_temp.act(ada);
  perform pg_temp.expect(pg_temp.state('select public.set_my_birthday(2, 30)') = '22023', 'February 30 does not exist');
  perform pg_temp.expect(pg_temp.state('select public.set_my_birthday(13, 1)') = '22023', 'neither does month 13');
  perform pg_temp.expect(pg_temp.state('select public.set_my_birthday(4, 31)') = '22023', 'April 31 neither');
  perform pg_temp.expect(pg_temp.state('select public.set_my_birthday(5, null)') = '22023', 'a month without a day is refused');
  perform pg_temp.expect(pg_temp.state('select public.set_my_birthday(5, 5, ''everyone'')') = '22023', 'the only choices are friends and only me');
  r := public.set_my_birthday(10, 18);
  perform pg_temp.expect((r ->> 'month')::int = 10 and (r ->> 'day')::int = 18, 'a birthday is saved');
  perform pg_temp.expect(r ->> 'visibility' = 'friends', 'and private to friends by default');
  perform pg_temp.expect(public.get_my_profile_extras() -> 'birthday' ->> 'day' = '18', 'ada reads it back');
  perform pg_temp.root();

  -- the columns are closed
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.must_refuse('select birthday_month from public.profiles', 'the birthday columns cannot be read');
  perform pg_temp.must_refuse('select birthday_day, birthday_visibility from public.profiles', 'whatever the combination');
  update public.profiles set birthday_month = 1, birthday_day = 1;
  perform pg_temp.root();
  perform pg_temp.expect((select birthday_month from public.profiles where id = ada) = 10, 'and cannot be written (no update policy)');
  perform pg_temp.act(pg_temp.i('bob'));

  -- who sees it
  perform pg_temp.expect(pg_temp.extras(ada) -> 'birthday' ->> 'month' = '10', 'a friend sees the birthday');
  perform pg_temp.expect(not ((pg_temp.extras(ada) -> 'birthday') ? 'year'), 'and no year');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(pg_temp.extras(ada) -> 'birthday' = 'null'::jsonb, 'a stranger does not');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('flo'));
  perform pg_temp.expect(pg_temp.extras(ada) -> 'birthday' = 'null'::jsonb, 'nor the person who blocked her');
  perform pg_temp.root();

  -- a friend who then blocks ada loses it
  perform pg_temp.act(pg_temp.i('cat'));
  perform pg_temp.expect(pg_temp.extras(ada) -> 'birthday' ->> 'day' = '18', 'cat sees it as a friend');
  perform public.block_user(ada);
  perform pg_temp.expect(pg_temp.extras(ada) -> 'birthday' = 'null'::jsonb, 'and not after blocking ada');
  perform pg_temp.root();
  perform pg_temp.befriend(ada, pg_temp.i('cat'));
  delete from public.blocks where blocker_id = pg_temp.i('cat');

  -- only me
  perform pg_temp.act(ada);
  perform public.set_my_birthday(10, 18, 'self');
  perform pg_temp.expect(pg_temp.extras(ada) -> 'birthday' ->> 'day' = '18', 'ada always sees her own');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.extras(ada) -> 'birthday' = 'null'::jsonb, 'only me: friends do not see it');
  perform pg_temp.root();
  perform pg_temp.act(ada);
  perform public.set_my_birthday(10, 18, 'friends');
  perform pg_temp.root();

  -- a leap day is kept on the 28th in other years
  perform pg_temp.expect(public.birthday_falls_on(2::smallint, 29::smallint, date '2027-02-28'), 'February 29 is celebrated on the 28th of a normal year');
  perform pg_temp.expect(not public.birthday_falls_on(2::smallint, 29::smallint, date '2028-02-28'), 'but not on the 28th of a leap year');
  perform pg_temp.expect(public.birthday_falls_on(2::smallint, 29::smallint, date '2028-02-29'), 'it is on the 29th');
  perform pg_temp.expect(not public.birthday_falls_on(3::smallint, 1::smallint, date '2027-02-28'), 'March 1 is not February 28');
  perform pg_temp.expect(public.birthday_falls_on(10::smallint, 18::smallint, date '2026-10-18'), 'an ordinary day matches');
  perform pg_temp.expect(not public.birthday_falls_on(null, null, date '2026-10-18'), 'no birthday matches nothing');

  -- the cards: list_birthdays_today with the reader's own date
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt('select * from public.list_birthdays_today(date ''2026-10-18'')') = 1, 'bob is shown ada on her day');
  perform pg_temp.expect(pg_temp.cnt('select * from public.list_birthdays_today(date ''2026-10-19'')') = 0, 'and not on another');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(pg_temp.cnt('select * from public.list_birthdays_today(date ''2026-10-18'')') = 0, 'a stranger is shown nothing');
  perform pg_temp.root();
  insert into public.contact_aliases (owner_id, friend_id, alias) values (pg_temp.i('bob'), ada, 'Ada Lovelace');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect((select display_name from public.list_birthdays_today(date '2026-10-18')) = 'Ada Lovelace', 'the name is the one bob gave her');
  perform pg_temp.root();
  update public.profiles set birthday_reminders = false where id = pg_temp.i('bob');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt('select * from public.list_birthdays_today(date ''2026-10-18'')') = 0, 'reminders off: no card');
  perform pg_temp.root();
  update public.profiles set birthday_reminders = true where id = pg_temp.i('bob');

  -- deleting the account removes the birthday
  update public.profiles set birthday_month = 3, birthday_day = 4 where id = pg_temp.i('ivy');
  update public.profiles set deleted_at = now() where id = pg_temp.i('ivy');
  perform pg_temp.expect((select birthday_month from public.profiles where id = pg_temp.i('ivy')) is null, 'a deleted account keeps no birthday');
end $$;

-- ===================================== 3. the reminder at 9 in the morning
do $$
declare
  ada uuid := pg_temp.i('ada'); bob uuid := pg_temp.i('bob'); cat uuid := pg_temp.i('cat');
  dan uuid := pg_temp.i('dan'); gus uuid := pg_temp.i('gus');
  at10 text := pg_temp.zone_at(10); at07 text := pg_temp.zone_at(7); at22 text := pg_temp.zone_at(22);
  yr integer; n integer; t text;
begin
  -- It is ada's birthday "today" where bob's phone is (10:00), and cat's
  -- phone is still asleep (07:00); dan, a stranger, has a phone at 10:00.
  update public.profiles set birthday_month = extract(month from pg_temp.today_in(at10)),
    birthday_day = extract(day from pg_temp.today_in(at10)) where id = ada;
  yr := extract(year from pg_temp.today_in(at10))::integer;
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language, time_zone) values
    (bob, 'https://push.test/bob-en', repeat('p', 60), repeat('a', 20), 'en', at10),
    (bob, 'https://push.test/bob-zh', repeat('q', 60), repeat('b', 20), 'zh', at10),
    (cat, 'https://push.test/cat', repeat('r', 60), repeat('c', 20), 'en', at07),
    (dan, 'https://push.test/dan', repeat('s', 60), repeat('d', 20), 'en', at10);

  perform pg_temp.expect(pg_temp.due(bob, ada), 'a friend at 10:00 on the day is due');
  perform pg_temp.expect(not pg_temp.due(cat, ada), 'a friend at 07:00 is not yet');
  perform pg_temp.expect(not pg_temp.due(dan, ada), 'a stranger is not');
  perform pg_temp.expect(public.birthday_pushes_waiting(), 'the dispatcher sees something waiting');

  -- 22:00 is too late for a first reminder
  update public.push_subscriptions set time_zone = at22 where endpoint = 'https://push.test/cat';
  perform pg_temp.expect(not pg_temp.due(cat, ada), 'a friend at 22:00 is not told late at night');
  update public.push_subscriptions set time_zone = at10 where endpoint = 'https://push.test/cat';
  perform pg_temp.expect(pg_temp.due(cat, ada), 'cat is due at 10:00');
  update public.push_subscriptions set time_zone = 'Not/AZone' where endpoint = 'https://push.test/cat';
  perform pg_temp.expect(public.local_time_in_zone('Not/AZone') is not null, 'an unknown zone does not break the clock');
  update public.push_subscriptions set time_zone = at07 where endpoint = 'https://push.test/cat';

  -- reasons not to be told
  update public.profiles set birthday_visibility = 'self' where id = ada;
  perform pg_temp.expect(not pg_temp.due(bob, ada), 'only me: nobody is told');
  update public.profiles set birthday_visibility = 'friends' where id = ada;
  update public.profiles set birthday_reminders = false where id = bob;
  perform pg_temp.expect(not pg_temp.due(bob, ada), 'reminders off: bob is not told');
  update public.profiles set birthday_reminders = true where id = bob;
  insert into public.user_privacy_settings (user_id, presence_status) values (bob, 'dnd')
    on conflict (user_id) do update set presence_status = 'dnd';
  perform pg_temp.expect(not pg_temp.due(bob, ada), 'Do Not Disturb: bob is not told');
  update public.user_privacy_settings set presence_status = 'online' where user_id = bob;
  perform pg_temp.expect(pg_temp.due(bob, ada), 'and is again when he is back');
  update public.profiles set deleted_at = now() where id = ada;
  perform pg_temp.expect(not pg_temp.due(bob, ada), 'a deleted account is not celebrated');
  update public.profiles set deleted_at = null, birthday_month = extract(month from pg_temp.today_in(at10)),
    birthday_day = extract(day from pg_temp.today_in(at10)) where id = ada;
  insert into public.blocks (blocker_id, blocked_id) values (bob, ada);
  perform pg_temp.expect(not pg_temp.due(bob, ada), 'a block silences it');
  delete from public.blocks where blocker_id = bob and blocked_id = ada;

  -- the claim
  select count(*) into n from public.claim_birthday_pushes();
  perform pg_temp.expect(n = 2, 'one push per device of bob: ' || n);
  perform pg_temp.expect(not pg_temp.due(bob, ada), 'bob is told once');
  perform pg_temp.expect((select count(*) from public.claim_birthday_pushes()) = 0, 'a second tick sends nothing');
  perform pg_temp.expect(not public.birthday_pushes_waiting(), 'and nothing waits any more');
  perform pg_temp.expect(exists (select 1 from public.birthday_reminder_log where recipient_id = bob and friend_id = ada and year = yr),
    'the log remembers');

  -- wording, per device
  delete from public.birthday_reminder_log;
  insert into public.contact_aliases (owner_id, friend_id, alias) values (bob, ada, 'Ada <b>ee</b>')
    on conflict (owner_id, friend_id) do update set alias = excluded.alias;
  select title into t from public.claim_birthday_pushes() where endpoint = 'https://push.test/bob-zh';
  perform pg_temp.expect(t like '%今天是%的生日', 'a Chinese device gets Chinese: ' || coalesce(t, 'null'));
  perform pg_temp.expect(t not like '%<%' and t not like '%>%', 'an alias cannot pass for a time token');
  delete from public.birthday_reminder_log;
  select title into t from public.claim_birthday_pushes() where endpoint = 'https://push.test/bob-en';
  perform pg_temp.expect(t like '%birthday today%', 'an English device gets English: ' || coalesce(t, 'null'));
  delete from public.contact_aliases where owner_id = bob and friend_id = ada;

  -- the next year it rings again
  perform pg_temp.expect(not exists (select 1 from public.birthday_reminder_log where year <> yr), 'only this year is logged');

  -- the dispatcher still runs, wakes nothing here, and fails nowhere
  delete from public.birthday_reminder_log;
  perform pg_temp.expect(pg_temp.state('select public.run_later_dispatch()') = 'ok', 'run_later_dispatch runs with birthdays waiting');

  -- clients cannot call any of it
  perform pg_temp.act(bob);
  perform pg_temp.must_refuse('select * from public.claim_birthday_pushes()', 'clients cannot claim pushes');
  perform pg_temp.must_refuse('select * from public.birthday_due_reminders()', 'or list who is due');
  perform pg_temp.must_refuse('select public.birthday_pushes_waiting()', 'or ask whether any wait');
  perform pg_temp.root();
  delete from public.push_subscriptions;
end $$;

-- ===================================== 4. support links (J4)
do $$
declare
  ada uuid := pg_temp.i('ada'); r jsonb; circle uuid; long_url text := 'https://ko-fi.com/' || repeat('a', 300);
begin
  -- the allow list
  perform pg_temp.expect(public.normalize_support_url('https://ko-fi.com/ada') = 'https://ko-fi.com/ada', 'ko-fi is allowed');
  perform pg_temp.expect(public.normalize_support_url('  https://www.patreon.com/ada  ') = 'https://www.patreon.com/ada', 'a subdomain is allowed and spaces are trimmed');
  perform pg_temp.expect(public.normalize_support_url('https://KO-FI.com/Ada') = 'https://ko-fi.com/Ada', 'the host is lowercased, the path kept');
  perform pg_temp.expect(public.normalize_support_url('https://afdian.net/a/ada') is not null, '爱发电 is allowed');
  perform pg_temp.expect(public.normalize_support_url('https://ifdian.net/a/ada') is not null, 'ifdian is allowed');
  perform pg_temp.expect(public.normalize_support_url('https://github.com/sponsors/ada') is not null, 'GitHub Sponsors is allowed');
  perform pg_temp.expect(public.normalize_support_url('https://github.com/ada') is null, 'but not the rest of GitHub');
  perform pg_temp.expect(public.normalize_support_url('http://ko-fi.com/ada') is null, 'plain http is refused');
  perform pg_temp.expect(public.normalize_support_url('https://patreon.com.evil.example/ada') is null, 'a look-alike host is refused');
  perform pg_temp.expect(public.normalize_support_url('https://notpatreon.com/ada') is null, 'so is a longer name');
  perform pg_temp.expect(public.normalize_support_url('https://evil.example/?u=https://ko-fi.com/ada') is null, 'a page that merely mentions an allowed link is refused');
  perform pg_temp.expect(public.normalize_support_url('https://ko-fi.com@evil.example/') is null, 'a user name in the address is refused');
  perform pg_temp.expect(public.normalize_support_url('https://evil.example@ko-fi.com/') is null, 'in either order');
  perform pg_temp.expect(public.normalize_support_url('https://ko-fi.com:8443/ada') is null, 'a port is refused');
  perform pg_temp.expect(public.normalize_support_url('javascript:alert(1)') is null, 'javascript: is refused');
  perform pg_temp.expect(public.normalize_support_url('https://127.0.0.1/ada') is null, 'an IP address is refused');
  perform pg_temp.expect(public.normalize_support_url('https://ko-fi.com/a b') is null, 'spaces in the address are refused');
  perform pg_temp.expect(public.normalize_support_url('https://ko-fi.com/"x') is null, 'quotes are refused');
  perform pg_temp.expect(public.normalize_support_url(long_url) is null, 'over 300 characters is refused');
  perform pg_temp.expect(public.normalize_support_url(null) is null and public.normalize_support_url('') is null, 'nothing is nothing');

  -- my links
  perform pg_temp.act(ada);
  r := public.set_my_links('[{"url":"https://ko-fi.com/ada","label":"Ko-fi"},{"url":"https://KO-FI.com/ada"},{"url":"https://patreon.com/ada"}]'::jsonb);
  perform pg_temp.expect(jsonb_array_length(r) = 2, 'a duplicate is dropped');
  perform pg_temp.expect(r -> 0 ->> 'label' = 'Ko-fi', 'with its label');
  perform pg_temp.expect(pg_temp.state('select public.set_my_links(''[{"url":"https://evil.example/x"}]''::jsonb)') = '22023', 'a link outside the list is refused');
  perform pg_temp.expect(pg_temp.state('select public.set_my_links(''[1]''::jsonb)') = '22023', 'a link that is not an object is refused');
  perform pg_temp.expect(pg_temp.state('select public.set_my_links(''{}''::jsonb)') = '22023', 'not a list is refused');
  perform pg_temp.expect(pg_temp.state('select public.set_my_links(''[{"url":"https://ko-fi.com/a1"},{"url":"https://ko-fi.com/a2"},{"url":"https://ko-fi.com/a3"},{"url":"https://ko-fi.com/a4"},{"url":"https://ko-fi.com/a5"},{"url":"https://ko-fi.com/a6"}]''::jsonb)') = '22023',
    'more than 5 are refused');
  perform pg_temp.expect(pg_temp.state('select public.set_my_links(''[{"url":"https://ko-fi.com/a1","label":"' || repeat('x', 31) || '"}]''::jsonb)') = '22023', 'a long label is refused');
  perform pg_temp.expect(jsonb_array_length(public.get_my_profile_extras() -> 'links') = 2, 'a refused save changes nothing');
  perform pg_temp.root();

  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.must_refuse('select links from public.profiles', 'the links column cannot be read');
  perform pg_temp.expect(jsonb_array_length(pg_temp.extras(ada) -> 'links') = 2, 'a friend sees the links through the profile extras');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(jsonb_array_length(pg_temp.extras(ada) -> 'links') = 2, 'a stranger too when the profile is open');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(jsonb_array_length(pg_temp.extras(ada) -> 'links') = 0, 'but not a person ada blocked');
  perform pg_temp.root();
  perform pg_temp.act(ada);
  perform public.set_profile_visibility('friends');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(jsonb_array_length(pg_temp.extras(ada) -> 'links') = 0, 'friends only: a stranger gets none');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(jsonb_array_length(pg_temp.extras(ada) -> 'links') = 2, 'friends only: a friend still gets them');
  perform pg_temp.root();
  perform pg_temp.act(ada);
  perform public.set_profile_visibility('everyone');
  perform pg_temp.expect(jsonb_array_length(public.set_my_links('[]'::jsonb)) = 0, 'an empty list removes them');
  perform public.set_my_links('[{"url":"https://ko-fi.com/ada"}]'::jsonb);
  perform pg_temp.root();
  update public.profiles set links = '[{"url":"https://ko-fi.com/ivy"}]'::jsonb, deleted_at = null where id = pg_temp.i('ivy');
  update public.profiles set deleted_at = now() where id = pg_temp.i('ivy');
  perform pg_temp.expect((select links from public.profiles where id = pg_temp.i('ivy')) = '[]'::jsonb, 'a deleted account keeps no links');

  -- a circle
  perform pg_temp.act(ada);
  circle := public.create_circle('Support club', array[pg_temp.i('bob')]);
  perform pg_temp.expect(public.set_circle_support_url(circle, 'https://afdian.net/a/club') = 'https://afdian.net/a/club', 'the owner sets the circle link');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_support_url(%L, %L)', circle, 'https://evil.example/pay')) = '22023', 'a link outside the list is refused');
  perform pg_temp.expect(public.get_circle_support_url(circle) = 'https://afdian.net/a/club', 'the owner reads it');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(public.get_circle_support_url(circle) = 'https://afdian.net/a/club', 'a member reads it');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_support_url(%L, %L)', circle, 'https://ko-fi.com/club')) = '42501', 'a plain member cannot change it');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.expect(public.get_circle_support_url(circle) is null, 'an outsider reads nothing');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_support_url(%L, %L)', circle, 'https://ko-fi.com/club')) = '42501', 'an outsider cannot change it');
  perform pg_temp.root();
  perform pg_temp.act(ada);
  perform pg_temp.expect(public.set_circle_support_url(circle, '  ') is null, 'a blank link removes it');
  perform pg_temp.expect(public.get_circle_support_url(circle) is null, 'and it is gone');
  perform pg_temp.root();
end $$;

-- ===================================== 5. where a friendship came from, and the mutuals (A14)
do $$
declare
  ada uuid := pg_temp.i('ada'); bob uuid := pg_temp.i('bob'); cat uuid := pg_temp.i('cat');
  dan uuid := pg_temp.i('dan'); eve uuid := pg_temp.i('eve'); flo uuid := pg_temp.i('flo');
  gus uuid := pg_temp.i('gus'); hal uuid := pg_temp.i('hal');
  req uuid; grp uuid; circle uuid; m jsonb; x jsonb;
begin
  -- dan asks ada by scanning her code
  perform pg_temp.act(dan);
  req := public.send_friend_request(ada);
  perform public.set_friend_request_source(ada, 'qr');
  perform pg_temp.root();
  perform pg_temp.expect((select source from public.friend_requests where id = req) = 'qr', 'the request remembers where it came from');
  perform pg_temp.act(ada);
  perform pg_temp.expect(pg_temp.extras(dan) ->> 'source' = 'qr', 'the receiver sees the source of a waiting request');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('hal'));
  perform pg_temp.expect(pg_temp.extras(dan) ->> 'source' is null, 'a third person sees none');
  perform pg_temp.root();
  perform pg_temp.act(ada);
  perform public.accept_friend_request(req);
  perform pg_temp.expect(pg_temp.extras(dan) ->> 'source' = 'qr', 'the friendship keeps it');
  perform pg_temp.root();
  perform pg_temp.expect((select source from public.friendships where user_low_id = least(ada, dan) and user_high_id = greatest(ada, dan)) = 'qr',
    'the source is copied to the friendship');
  perform pg_temp.act(dan);
  perform pg_temp.expect(pg_temp.extras(ada) ->> 'source' = 'qr', 'and the sender sees it too');
  perform pg_temp.root();

  -- claims that can be checked are
  perform pg_temp.act(hal);
  req := public.send_friend_request(ada);
  perform public.set_friend_request_source(ada, 'group');
  perform pg_temp.expect((select source from public.friend_requests where id = req) is null, 'a group claim without a shared group is dropped');
  perform public.set_friend_request_source(ada, 'circle');
  perform pg_temp.expect((select source from public.friend_requests where id = req) is null, 'a circle claim without a shared circle is dropped');
  perform public.set_friend_request_source(ada, 'rumour');
  perform pg_temp.expect((select source from public.friend_requests where id = req) is null, 'an unknown source is ignored');
  perform pg_temp.root();
  grp := gen_random_uuid();
  insert into public.conversations (id, type, title) values (grp, 'group', 'Study group');
  insert into public.conversation_members (conversation_id, user_id) values (grp, hal), (grp, ada), (grp, bob);
  perform pg_temp.act(hal);
  perform public.set_friend_request_source(ada, 'group');
  perform pg_temp.expect((select source from public.friend_requests where id = req) = 'group', 'with a shared group the claim holds');
  perform pg_temp.expect(pg_temp.state('select public.set_friend_request_source(null, ''qr'')') = 'ok', 'a missing person is ignored');
  perform pg_temp.root();
  perform pg_temp.act(ada);
  perform public.accept_friend_request(req);
  perform pg_temp.root();
  perform pg_temp.expect((select source from public.friendships where user_low_id = least(ada, hal) and user_high_id = greatest(ada, hal)) = 'group',
    'the friendship says group');
  perform pg_temp.expect((select source from public.friendships where user_low_id = least(ada, bob) and user_high_id = greatest(ada, bob)) is null,
    'an old friendship has no source');

  -- mutuals. ada's friends: bob, cat, gus, dan, hal. dan's: ada, bob, cat. So dan and ada share bob and cat
  -- (but dan is ada's friend now). A stranger, eve, is a friend of bob and cat only.
  perform pg_temp.befriend(dan, bob);
  perform pg_temp.befriend(dan, cat);
  perform pg_temp.befriend(eve, bob);
  perform pg_temp.befriend(eve, cat);
  perform pg_temp.befriend(flo, bob);
  delete from public.blocks where blocker_id = ada and blocked_id = eve;
  delete from public.blocks where blocker_id = flo;
  perform pg_temp.act(ada);
  circle := public.create_circle('Mutual circle', array[dan]);
  perform pg_temp.root();
  insert into public.circle_members (circle_id, user_id, role) values (circle, eve, 'member');
  insert into public.conversation_members (conversation_id, user_id) values (grp, dan), (grp, eve);

  -- a friend: names and numbers
  perform pg_temp.act(ada);
  m := public.get_mutuals(dan);
  perform pg_temp.expect((m ->> 'friend_count')::int = 2, 'ada and dan share two friends: ' || (m ->> 'friend_count'));
  perform pg_temp.expect(jsonb_array_length(m -> 'friends') = 2, 'and the two are named');
  perform pg_temp.expect((m ->> 'group_count')::int = 1 and jsonb_array_length(m -> 'groups') = 1, 'one shared group, named');
  perform pg_temp.expect(m -> 'groups' -> 0 ->> 'title' = 'Study group', 'with its title');
  perform pg_temp.expect((m ->> 'circle_count')::int = 1 and m -> 'circles' -> 0 ->> 'name' = 'Mutual circle', 'one shared circle, named');
  perform pg_temp.expect((m ->> 'is_friend')::boolean, 'and a friend');
  perform pg_temp.expect(not (m::text like '%gus%'), 'a friend only ada has is not listed');
  perform pg_temp.root();

  -- a stranger: numbers only
  perform pg_temp.act(ada);
  m := public.get_mutuals(eve);
  perform pg_temp.expect((m ->> 'friend_count')::int = 2, 'a stranger: the number of mutual friends');
  perform pg_temp.expect(jsonb_array_length(m -> 'friends') = 0, 'but no names');
  perform pg_temp.expect((m ->> 'group_count')::int = 1 and jsonb_array_length(m -> 'groups') = 0, 'the group count without the group');
  perform pg_temp.expect((m ->> 'circle_count')::int = 1 and jsonb_array_length(m -> 'circles') = 0, 'the circle count without the circle');
  perform pg_temp.expect(not (m::text like '%Study group%' or m::text like '%Mutual circle%'), 'no title leaks');
  perform pg_temp.root();

  -- a friend of only one of them is not mutual
  perform pg_temp.act(ada);
  m := public.get_mutuals(flo);
  perform pg_temp.expect((m ->> 'friend_count')::int = 1, 'flo shares only bob with ada');
  perform pg_temp.root();

  -- deleted accounts and bots are not mutual friends
  update public.profiles set deleted_at = now() where id = cat;
  perform pg_temp.act(ada);
  perform pg_temp.expect((public.get_mutuals(dan) ->> 'friend_count')::int = 1, 'a deleted friend is not counted');
  perform pg_temp.root();
  update public.profiles set deleted_at = null where id = cat;

  -- blocks and profile visibility hide it all
  insert into public.blocks (blocker_id, blocked_id) values (eve, ada);
  perform pg_temp.act(ada);
  perform pg_temp.expect((public.get_mutuals(eve) ->> 'friend_count')::int = 0, 'a block (either way) shows no mutuals');
  perform pg_temp.root();
  delete from public.blocks where blocker_id = eve and blocked_id = ada;
  insert into public.user_privacy_settings (user_id, profile_visibility) values (flo, 'friends')
    on conflict (user_id) do update set profile_visibility = 'friends';
  perform pg_temp.act(ada);
  perform pg_temp.expect((public.get_mutuals(flo) ->> 'friend_count')::int = 0, 'a profile kept for friends shows no mutuals to a stranger');
  perform pg_temp.expect((public.get_mutuals(ada) ->> 'friend_count')::int = 0, 'nobody has mutuals with themselves');
  perform pg_temp.expect((public.get_mutuals(pg_temp.i('robo')) ->> 'friend_count')::int = 0, 'a bot has none');
  perform pg_temp.root();

  -- counts for request cards
  perform pg_temp.act(ada);
  perform pg_temp.expect((select friend_count from public.get_mutual_counts(array[eve, dan, ada]) where user_id = eve) = 2, 'counts: eve');
  perform pg_temp.expect(pg_temp.cnt(format('select * from public.get_mutual_counts(array[%L::uuid, %L::uuid])', ada, flo)) = 0,
    'counts: nobody for herself or a hidden profile');
  perform pg_temp.expect(pg_temp.state(format('select * from public.get_mutual_counts(array(select gen_random_uuid() from generate_series(1, 51)))')) = '22023',
    'counts: at most 50 at a time');
  perform pg_temp.root();

  -- the extras in one call
  perform pg_temp.act(ada);
  x := pg_temp.extras(dan);
  perform pg_temp.expect(x ? 'mutuals' and x ? 'links' and x ? 'birthday' and x ? 'source', 'get_profile_extras has all four parts');
  perform pg_temp.expect((x -> 'mutuals' ->> 'friend_count')::int = 2, 'and the mutuals inside');
  perform pg_temp.root();

  -- signed-out callers
  perform pg_temp.act(null);
  perform pg_temp.must_refuse(format('select public.get_mutuals(%L)', ada), 'signed out: no mutuals');
  perform pg_temp.must_refuse(format('select public.get_profile_extras(%L)', ada), 'signed out: no extras');
  perform pg_temp.must_refuse(format('select public.set_my_links(''[]''::jsonb)'), 'signed out: no links');
  perform pg_temp.must_refuse(format('select public.set_my_birthday(1, 1)'), 'signed out: no birthday');
  perform pg_temp.root();
end $$;
\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'profile social: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
