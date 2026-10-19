-- Behaviour checks for feature flags and the minimum version (K4: migrations
-- 202610240600 and 202610240610), official notices (K6: 202610240620 and
-- 202610240630) and feedback (K7: 202610240640 to 202610240660). Run by
-- test/supabase/admin_ops_test.dart against the local database: it applies
-- every migration the database lacks (the local baseline is 202610170001)
-- inside a transaction, acts as several people through row-level security,
-- and rolls back, so the database is left as it was. Run from the repository
-- root.
--
-- What it walks through: who may read and write the tables (nobody, apart
-- from the admin functions, and those only for platform admins of the right
-- role), flag buckets that never change and only ever grow, the allow list,
-- the switch and the minimum version of a flag, version comparison, the
-- minimum version per platform, notices (read, dismiss, retract, older than
-- the account, one push a day, the push batches in each device's language),
-- feedback (rate limit, screenshots in a private folder, only the sender and
-- admins read) and replies that reach only the person who asked.
\set ON_ERROR_STOP on

begin;

-- One behaviour script at a time: they change the same tables, and test
-- files run in parallel.
do $$ begin perform pg_advisory_xact_lock(20261017); end $$;
set local client_min_messages = warning;

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
\i supabase/migrations/202610240600_feature_flags.sql
\i supabase/migrations/202610240610_feature_flags_admin.sql
\i supabase/migrations/202610240620_announcements.sql
\i supabase/migrations/202610240630_announcements_admin.sql
\i supabase/migrations/202610240640_user_feedback.sql
\i supabase/migrations/202610240650_feedback_admin.sql
\i supabase/migrations/202610240660_export_my_feedback.sql
\o /dev/null
set local storage.allow_delete_query = 'true';

-- ---------------------------------------------------------------- helpers
create function pg_temp.uid(who text) returns uuid language sql immutable as $$
  select ('00000000-0000-4000-8000-0000000000' || who)::uuid;
$$;

-- Becomes [who] (a1, b1, ...); null is a signed-out visitor.
create function pg_temp.act_as(who text) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  if who is null then
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    execute 'set local role anon';
  else
    perform set_config('request.jwt.claim.sub', pg_temp.uid(who)::text, true);
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', pg_temp.uid(who), 'role', 'authenticated')::text,
      true
    );
    execute 'set local role authenticated';
  end if;
end;
$$;

create function pg_temp.root() returns void language plpgsql as $$
begin
  reset role;
end;
$$;

create function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin
  if ok is distinct from true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok: %', label;
end;
$$;

-- Records that [stmt] must raise with SQLSTATE [code].
create function pg_temp.refused(label text, stmt text, code text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    if sqlstate <> code then
      raise exception 'FAILED: % (wanted %, got % %)', label, code, sqlstate, sqlerrm;
    end if;
    raise notice 'ok: %', label;
    return;
  end;
  raise exception 'FAILED: % (nothing was refused)', label;
end;
$$;

-- The text of the first column of [query], or 'ERR: ...'.
create function pg_temp.val(query text) returns text language plpgsql as $$
declare r text;
begin
  execute query into r;
  return r;
exception when others then
  return 'ERR: ' || sqlerrm;
end;
$$;

create function pg_temp.affected(stmt text) returns bigint language plpgsql as $$
declare n bigint;
begin
  execute stmt;
  get diagnostics n = row_count;
  return n;
end;
$$;

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create function pg_temp.i(n text) returns uuid language sql stable as $$
  select id from pg_temp.ids where name = n;
$$;

grant execute on all functions in schema pg_temp to public;

-- ------------------------------------------------------------------- cast
-- Ada, Bob, Cy (Do Not Disturb) and Dee are ordinary people. Root is the
-- platform owner, Mia a moderator, Sam support staff.
insert into auth.users (id, email, instance_id, aud, role)
select pg_temp.uid(v.n), v.name || '@ops.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee'),('f1','root'),('a2','mia'),('b2','sam')) v(n, name);
insert into public.profiles (id, username, display_name)
select pg_temp.uid(v.n), v.name || '_ops', initcap(v.name)
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('d1','dee'),('f1','root'),('a2','mia'),('b2','sam')) v(n, name);

-- The first owner is added by hand, as in production (never in a migration).
insert into public.app_admins (user_id, role)
values (pg_temp.uid('f1'), 'owner'), (pg_temp.uid('a2'), 'moderator'), (pg_temp.uid('b2'), 'support');

-- Dee joined three months ago.
update public.profiles set created_at = now() - interval '100 days' where id = pg_temp.uid('d1');

delete from public.push_subscriptions;

-- ============================================================ K4: tables
select pg_temp.act_as('a1');
select pg_temp.refused('Ada reads app_config', 'select * from public.app_config', '42501');
select pg_temp.refused('Ada reads feature_flags', 'select * from public.feature_flags', '42501');
select pg_temp.refused('Ada writes feature_flags',
  $q$insert into public.feature_flags (key, enabled) values ('sneaky_flag', true)$q$, '42501');
select pg_temp.refused('Ada writes app_config',
  $q$insert into public.app_config (key, value) values ('min_versions', '{"all":"99.0.0"}')$q$, '42501');
select pg_temp.refused('Ada lists flags', 'select public.admin_list_feature_flags()', '42501');
select pg_temp.refused('Ada sets a flag',
  $q$select public.admin_set_feature_flag('new_chat', '', true, 100)$q$, '42501');
select pg_temp.refused('Ada deletes a flag',
  $q$select public.admin_delete_feature_flag('new_chat')$q$, '42501');
select pg_temp.refused('Ada reads the minimum versions', 'select public.admin_get_min_versions()', '42501');
select pg_temp.refused('Ada sets a minimum version',
  $q$select public.admin_set_min_version('all', '99.0.0')$q$, '42501');
select pg_temp.act_as(null);
select pg_temp.refused('a visitor lists flags', 'select public.admin_list_feature_flags()', '42501');
select pg_temp.refused('a visitor sets a flag',
  $q$select public.admin_set_feature_flag('new_chat', '', true, 100)$q$, '42501');
select pg_temp.refused('a visitor reads app_config', 'select * from public.app_config', '42501');

-- Moderators and support read the flags but cannot change anything.
select pg_temp.act_as('a2');
select pg_temp.check('a moderator lists flags',
  jsonb_typeof(public.admin_list_feature_flags()) = 'array');
select pg_temp.refused('a moderator sets a flag',
  $q$select public.admin_set_feature_flag('new_chat', '', true, 100)$q$, '42501');
select pg_temp.refused('a moderator sets a minimum version',
  $q$select public.admin_set_min_version('all', '99.0.0')$q$, '42501');
select pg_temp.act_as('b2');
select pg_temp.check('support reads the minimum versions',
  jsonb_typeof(public.admin_get_min_versions()) = 'object');
select pg_temp.refused('support sets a flag',
  $q$select public.admin_set_feature_flag('new_chat', '', true, 100)$q$, '42501');

-- ============================================================ K4: versions
select pg_temp.root();
select pg_temp.check('equal versions',
  public.version_at_least('1.2.3', '1.2.3'));
select pg_temp.check('an older patch is lower',
  not public.version_at_least('1.2.2', '1.2.3'));
select pg_temp.check('1.10.0 is higher than 1.9.0 (numbers, not text)',
  public.version_at_least('1.10.0', '1.9.0'));
select pg_temp.check('missing parts count as 0 and a leading v is fine',
  public.version_at_least('v1.2', '1.2.0'));
select pg_temp.check('a build number is ignored',
  public.version_at_least('1.2.3+45', '1.2.3'));
select pg_temp.check('a lower major is lower',
  not public.version_at_least('0.9.9', '1.0.0'));
select pg_temp.check('a development build is let through',
  public.version_at_least('dev', '1.0.0'));
select pg_temp.check('a minimum that is not a version asks for nothing',
  public.version_at_least('1.0.0', 'garbage'));
select pg_temp.check('no minimum asks for nothing',
  public.version_at_least('0.0.1', '') and public.version_at_least('0.0.1', null));
select pg_temp.check('no version is let through',
  public.version_at_least(null, '1.0.0'));

-- ============================================================ K4: buckets
select pg_temp.check('a bucket never changes',
  public.flag_bucket(pg_temp.uid('a1'), 'new_chat') = public.flag_bucket(pg_temp.uid('a1'), 'new_chat'));
select pg_temp.check('buckets are 0 to 99',
  (select min(public.flag_bucket(md5(g::text)::uuid, 'new_chat')) >= 0
      and max(public.flag_bucket(md5(g::text)::uuid, 'new_chat')) <= 99
   from generate_series(1, 2000) g));
select pg_temp.check('half the people are below 50',
  (select count(*) between 850 and 1150
   from generate_series(1, 2000) g
   where public.flag_bucket(md5(g::text)::uuid, 'new_chat') < 50));
select pg_temp.check('a flag key gives the same person another bucket',
  (select count(*) > 1000
   from generate_series(1, 2000) g
   where public.flag_bucket(md5(g::text)::uuid, 'new_chat')
     <> public.flag_bucket(md5(g::text)::uuid, 'other_flag')));
-- A fixed value, so a change to the formula cannot go unnoticed: clients and
-- tests elsewhere may rely on who is in a roll-out.
select pg_temp.check('the bucket formula is the documented one',
  public.flag_bucket('00000000-0000-4000-8000-0000000000a1', 'new_chat')
    = (('x' || substr(md5('new_chat:00000000-0000-4000-8000-0000000000a1'), 1, 8))::bit(32)::bigint % 100)::int);

-- ============================================================ K4: flags
select pg_temp.act_as('f1');
select public.admin_set_feature_flag('new_chat', 'The new chat', true, 50, array['ada_ops'], '');
select pg_temp.check('the owner lists the flag with the allow list as usernames',
  (select f->>'key' = 'new_chat' and f->'allow_usernames' = '["ada_ops"]'::jsonb
     and (f->>'rollout_percent')::int = 50
   from jsonb_array_elements(public.admin_list_feature_flags()) f));

-- Ada is on the allow list; Bob and Cy follow their bucket.
select pg_temp.act_as('a1');
select pg_temp.check('the allow list turns a flag on whatever the bucket',
  public.get_my_flags('web', '1.0.0') -> 'flags' ->> 'new_chat' = 'true');
select pg_temp.root();
create temp table bob_expect as
select public.flag_bucket(pg_temp.uid('b1'), 'new_chat') < 50 as on_for_bob;
grant select on bob_expect to public;
select pg_temp.act_as('b1');
select pg_temp.check('Bob gets what his bucket says',
  (public.get_my_flags('web', '1.0.0') -> 'flags' ->> 'new_chat')::boolean
    = (select on_for_bob from bob_expect));
select pg_temp.check('and the same again a moment later',
  public.get_my_flags('web', '1.0.0') = public.get_my_flags('web', '1.0.0'));
select pg_temp.act_as(null);
select pg_temp.check('a visitor is not in a partial roll-out',
  public.get_my_flags('web', '1.0.0') -> 'flags' ->> 'new_chat' = 'false');
select pg_temp.root();

-- Raising the percentage only adds people.
insert into public.feature_flags (key, enabled, rollout_percent) values ('rollout_test', true, 30);
create temp table on30 as
select g as n
from generate_series(1, 500) g, public.feature_flags f
where f.key = 'rollout_test' and public.flag_is_on(f, md5(g::text)::uuid, null);
update public.feature_flags set rollout_percent = 60 where key = 'rollout_test';
create temp table on60 as
select g as n
from generate_series(1, 500) g, public.feature_flags f
where f.key = 'rollout_test' and public.flag_is_on(f, md5(g::text)::uuid, null);
select pg_temp.check('everybody in at 30 percent is still in at 60',
  not exists (select 1 from on30 where n not in (select n from on60)));
select pg_temp.check('and more people are in at 60',
  (select count(*) from on60) > (select count(*) from on30));

-- The master switch beats the allow list and the percentage.
select pg_temp.act_as('f1');
select public.admin_set_feature_flag('new_chat', 'The new chat', false, 100, array['ada_ops'], '');
select pg_temp.act_as('a1');
select pg_temp.check('a flag that is off is off for the people on its allow list',
  public.get_my_flags('web', '1.0.0') -> 'flags' ->> 'new_chat' = 'false');
select pg_temp.act_as('b1');
select pg_temp.check('and for everybody else',
  public.get_my_flags('web', '1.0.0') -> 'flags' ->> 'new_chat' = 'false');

-- The version a flag needs.
select pg_temp.act_as('f1');
select public.admin_set_feature_flag('new_chat', 'The new chat', true, 100, '{}', '2.0.0');
select pg_temp.act_as('b1');
select pg_temp.check('an old app does not get a flag that needs 2.0.0',
  public.get_my_flags('web', '1.9.0') -> 'flags' ->> 'new_chat' = 'false');
select pg_temp.check('a new app does',
  public.get_my_flags('web', '2.0.0') -> 'flags' ->> 'new_chat' = 'true');
select pg_temp.check('an app that does not say its version does',
  public.get_my_flags('web', null) -> 'flags' ->> 'new_chat' = 'true');
select pg_temp.act_as(null);
select pg_temp.check('a flag for everybody is on for a visitor too',
  public.get_my_flags('web', '2.0.0') -> 'flags' ->> 'new_chat' = 'true');

-- Bad input.
select pg_temp.act_as('f1');
select pg_temp.refused('a flag key with a space',
  $q$select public.admin_set_feature_flag('bad key', '', true, 10)$q$, '22023');
select pg_temp.refused('a flag key that starts with a digit',
  $q$select public.admin_set_feature_flag('1flag', '', true, 10)$q$, '22023');
select pg_temp.refused('a roll-out over 100',
  $q$select public.admin_set_feature_flag('new_chat', '', true, 101)$q$, '22023');
select pg_temp.refused('an allow list with a name nobody has',
  $q$select public.admin_set_feature_flag('new_chat', '', true, 10, array['nobody_here'])$q$, '22023');
select pg_temp.refused('a version that is not one',
  $q$select public.admin_set_feature_flag('new_chat', '', true, 10, '{}', 'abc')$q$, '22023');

select pg_temp.act_as('a2');
select pg_temp.refused('a moderator deletes a flag',
  $q$select public.admin_delete_feature_flag('new_chat')$q$, '42501');
select pg_temp.act_as('f1');
select public.admin_delete_feature_flag('new_chat');
select pg_temp.check('a deleted flag is gone',
  not (public.get_my_flags('web', '2.0.0') -> 'flags' ? 'new_chat'));
select pg_temp.refused('deleting it twice',
  $q$select public.admin_delete_feature_flag('new_chat')$q$, 'P0002');

-- ====================================================== K4: min version
select pg_temp.act_as('f1');
select public.admin_set_min_version('web', '1.2.0');
select pg_temp.act_as('b1');
select pg_temp.check('web is asked for 1.2.0',
  public.get_my_flags('web', '1.0.0') ->> 'min_version' = '1.2.0');
select pg_temp.check('another platform is asked for nothing',
  public.get_my_flags('ios', '1.0.0') ->> 'min_version' = '');
select pg_temp.act_as('f1');
select public.admin_set_min_version('all', '0.9.0');
select pg_temp.act_as(null);
select pg_temp.check('a visitor sees the web minimum',
  public.get_my_flags('web', '1.0.0') ->> 'min_version' = '1.2.0');
select pg_temp.check('and the one for all platforms on the others',
  public.get_my_flags('ios', '1.0.0') ->> 'min_version' = '0.9.0');
select pg_temp.check('the platform name is not case sensitive',
  public.get_my_flags('WEB', '1.0.0') ->> 'min_version' = '1.2.0');
select pg_temp.check('an app that does not say its platform gets the one for all',
  public.get_my_flags(null, null) ->> 'min_version' = '0.9.0');
select pg_temp.act_as('f1');
select pg_temp.refused('an unknown platform',
  $q$select public.admin_set_min_version('toaster', '1.0.0')$q$, '22023');
select pg_temp.refused('a minimum that is not a version',
  $q$select public.admin_set_min_version('web', 'soon')$q$, '22023');
select public.admin_set_min_version('web', '');
select pg_temp.check('an empty minimum takes the requirement away',
  public.get_my_flags('web', '1.0.0') ->> 'min_version' = '0.9.0');
select pg_temp.check('the owner reads all of them',
  public.admin_get_min_versions() = '{"all": "0.9.0"}'::jsonb);

-- The audit log.
select pg_temp.check('flags and the minimum version are in the audit log',
  (select array_agg(distinct e->>'action' order by e->>'action')
     @> array['delete_feature_flag', 'set_feature_flag', 'set_min_version']
   from jsonb_array_elements(public.admin_list_audit_log(100)) e));
select pg_temp.check('with the kinds of target they have',
  (select array_agg(distinct e->>'target_type' order by e->>'target_type')
     @> array['config', 'flag']
   from jsonb_array_elements(public.admin_list_audit_log(100)) e));

-- =========================================================== K6: notices
select pg_temp.act_as('a1');
select pg_temp.refused('Ada reads announcements', 'select * from public.announcements', '42501');
select pg_temp.refused('Ada reads announcement_states', 'select * from public.announcement_states', '42501');
select pg_temp.refused('Ada publishes a notice',
  $q$select public.admin_publish_announcement('Hi', '', '', '')$q$, '42501');
select pg_temp.refused('Ada lists the notices of the team', 'select public.admin_list_announcements()', '42501');
select pg_temp.refused('Ada cannot claim pushes', 'select * from public.claim_announcement_pushes()', '42501');
select pg_temp.act_as('b2');
select pg_temp.refused('support cannot publish a notice',
  $q$select public.admin_publish_announcement('Hi', '', '', '')$q$, '42501');
select pg_temp.check('support reads the list',
  jsonb_typeof(public.admin_list_announcements()) = 'array');

select pg_temp.act_as('a2');
select pg_temp.refused('a notice needs a title',
  $q$select public.admin_publish_announcement('', '  ', 'text', 'text')$q$, '22023');
select pg_temp.refused('a title of 121 characters',
  format('select public.admin_publish_announcement(%L, '''', '''', '''')', repeat('x', 121)), '22023');
insert into pg_temp.ids
select 'ann1', public.admin_publish_announcement(
  'Maintenance tonight', '今晚维护', 'We pause at 22:00.', '22:00 暂停服务。');

select pg_temp.act_as('a1');
select pg_temp.check('Ada sees the notice, unread, in both languages',
  (select jsonb_array_length(n) = 1
     and n->0->>'title_en' = 'Maintenance tonight'
     and n->0->>'title_zh' = '今晚维护'
     and n->0->>'kind' = 'announcement'
     and (n->0->>'read')::boolean = false
   from (select public.list_my_announcements() n) x));
select public.mark_announcement_read(pg_temp.i('ann1'));
select pg_temp.check('and reads it',
  (select (public.list_my_announcements()->0->>'read')::boolean));
select pg_temp.act_as('b1');
select pg_temp.check('Bob has it unread',
  not (public.list_my_announcements()->0->>'read')::boolean);
select public.dismiss_announcement(pg_temp.i('ann1'));
select pg_temp.check('Bob dismisses it and it leaves his list',
  jsonb_array_length(public.list_my_announcements()) = 0);
select pg_temp.act_as('a1');
select pg_temp.check('Ada still has it',
  jsonb_array_length(public.list_my_announcements()) = 1);
select pg_temp.act_as(null);
select pg_temp.refused('a visitor lists notices', 'select public.list_my_announcements()', '42501');

-- Somebody who joined later or a long time ago.
select pg_temp.root();
insert into public.announcements (kind, title_en, published_at, created_by)
values ('announcement', 'Old news', now() - interval '40 days', pg_temp.uid('a2')),
       ('announcement', 'Last week', now() - interval '7 days', pg_temp.uid('a2'));
select pg_temp.act_as('d1');
select pg_temp.check('Dee (joined 100 days ago) sees last week''s notice, not the one of 40 days ago',
  (select array_agg(e->>'title_en' order by e->>'title_en')
   from jsonb_array_elements(public.list_my_announcements()) e) = array['Last week', 'Maintenance tonight']);
select pg_temp.act_as('a1');
select pg_temp.check('Ada, who joined today, sees nothing from before she did',
  (select array_agg(e->>'title_en') from jsonb_array_elements(public.list_my_announcements()) e)
    = array['Maintenance tonight']);

-- Taking a notice back.
select pg_temp.act_as('b2');
select pg_temp.refused('support cannot retract a notice',
  format('select public.admin_retract_announcement(%L)', pg_temp.i('ann1')), '42501');
select pg_temp.act_as('a2');
select public.admin_retract_announcement(pg_temp.i('ann1'));
select pg_temp.refused('retracting twice',
  format('select public.admin_retract_announcement(%L)', pg_temp.i('ann1')), 'P0002');
select pg_temp.act_as('a1');
select pg_temp.check('a retracted notice leaves every inbox',
  jsonb_array_length(public.list_my_announcements()) = 0);
select pg_temp.act_as('a2');
select pg_temp.check('and the list of the team says so, with how many read it',
  (select (e->>'retracted_at') is not null
     and (e->>'read_count')::int = 2 and (e->>'dismissed_count')::int = 1
   from jsonb_array_elements(public.admin_list_announcements()) e
   where e->>'title_en' = 'Maintenance tonight'));

-- Somebody cannot touch a notice that is not theirs.
select pg_temp.root();
insert into public.announcements (id, kind, title_en, body_en, audience_user_id, created_by)
values ('00000000-0000-4000-8000-00000000f001', 'feedback_reply', 'A private note', 'for Bob',
  pg_temp.uid('b1'), pg_temp.uid('a2'));
select pg_temp.act_as('a1');
select public.mark_announcement_read('00000000-0000-4000-8000-00000000f001');
select public.dismiss_announcement('00000000-0000-4000-8000-00000000f001');
select pg_temp.root();
select pg_temp.check('Ada cannot read or dismiss a notice meant for Bob',
  (select count(*) = 0 from public.announcement_states
   where announcement_id = '00000000-0000-4000-8000-00000000f001'));
select pg_temp.act_as('b1');
select pg_temp.check('Bob sees it',
  (select count(*) = 1 from jsonb_array_elements(public.list_my_announcements()) e
   where e->>'title_en' = 'A private note'));
select pg_temp.act_as('a1');
select pg_temp.check('Ada does not',
  (select count(*) = 0 from jsonb_array_elements(public.list_my_announcements()) e
   where e->>'title_en' = 'A private note'));
select pg_temp.root();
select pg_temp.refused('a notice for one person must be a reply',
  $q$insert into public.announcements (kind, title_en, audience_user_id) values ('announcement', 'x', '00000000-0000-4000-8000-0000000000a1')$q$, '23514');
select pg_temp.refused('a reply must name its person',
  $q$insert into public.announcements (kind, title_en) values ('feedback_reply', 'x')$q$, '23514');
select pg_temp.refused('only a notice for everybody can ask for a push',
  $q$insert into public.announcements (kind, title_en, audience_user_id, push) values ('feedback_reply', 'x', '00000000-0000-4000-8000-0000000000a1', true)$q$, '23514');
delete from public.announcements where id = '00000000-0000-4000-8000-00000000f001';

-- ============================================================ K6: the push
select pg_temp.act_as('a2');
insert into pg_temp.ids
select 'push1', public.admin_publish_announcement(
  'Big <b>news</b>', '重要消息', 'Open the app <t:1:f>.', '打开应用。', true);
select pg_temp.refused('a second push inside 24 hours',
  $q$select public.admin_publish_announcement('More', '', '', '', true)$q$, '53400');
select pg_temp.check('a notice without a push is fine meanwhile',
  public.admin_publish_announcement('Another', '', '', '', false) is not null);

select pg_temp.root();
insert into public.push_subscriptions (id, user_id, endpoint, p256dh, auth, language)
select ('00000000-0000-4000-8000-00000000050' || n)::uuid, pg_temp.uid(u), 'https://push.example.com/' || n,
  repeat('k', 60), repeat('a', 20), lang
from (values (1, 'a1', 'en'), (2, 'b1', 'zh'), (3, 'c1', 'en'), (4, 'a2', 'zh')) v(n, u, lang);
insert into public.user_privacy_settings (user_id, presence_status)
values (pg_temp.uid('c1'), 'dnd')
on conflict (user_id) do update set presence_status = 'dnd';

-- Batches of two devices, in the order of their ids.
create temp table batch1 as select * from public.claim_announcement_pushes(2);
select pg_temp.check('the first batch is the first two devices',
  (select count(*) = 2 from batch1)
  and (select count(*) = 1 from batch1 where subscription_id::text like '%0501')
  and (select count(*) = 1 from batch1 where subscription_id::text like '%0502'));
select pg_temp.check('an English device gets the English title, without angle brackets',
  (select title = 'Big bnews/b' from batch1 where subscription_id::text like '%0501'));
select pg_temp.check('a Chinese device gets the Chinese one',
  (select title = '重要消息' and body = '打开应用。' from batch1 where subscription_id::text like '%0502'));
select pg_temp.check('the push opens Notifications, one tag for the notice',
  (select count(*) = 2 from batch1
   where url = '/#/notifications' and tag = 'announcement-' || pg_temp.i('push1')::text));
select pg_temp.check('the text cannot pass for a time token',
  (select count(*) = 0 from batch1 where title like '%<%' or body like '%<%'));
select pg_temp.check('the notice is not done yet',
  (select push_done_at is null from public.announcements where id = pg_temp.i('push1')));
create temp table batch2 as select * from public.claim_announcement_pushes(2);
select pg_temp.check('Do Not Disturb is left out, the cursor moves on',
  (select count(*) = 1 from batch2 where subscription_id::text like '%0504')
  and (select count(*) = 0 from batch2 where subscription_id::text like '%0503'));
create temp table batch3 as select * from public.claim_announcement_pushes(2);
select pg_temp.check('then nothing is left and the notice is done',
  (select count(*) = 0 from batch3)
  and (select push_done_at is not null from public.announcements where id = pg_temp.i('push1')));
select pg_temp.check('a done notice is never pushed again',
  (select count(*) = 0 from public.claim_announcement_pushes(10)));

-- Taken back before it went out; too old to be news.
update public.announcements set published_at = now() - interval '3 days' where id = pg_temp.i('push1');
select pg_temp.act_as('a2');
insert into pg_temp.ids select 'push2', public.admin_publish_announcement('Oops', '', 'typo', '', true);
select public.admin_retract_announcement(pg_temp.i('push2'));
select pg_temp.root();
create temp table taken_back as select * from public.claim_announcement_pushes(10);
select pg_temp.check('a notice taken back before it went out is not pushed',
  (select count(*) = 0 from taken_back)
  and (select push_done_at is not null from public.announcements where id = pg_temp.i('push2')));
select pg_temp.act_as('a2');
select pg_temp.check('and does not count against the daily push',
  public.admin_publish_announcement('Fixed', '', '', '', true) is not null);
select pg_temp.root();
update public.announcements set published_at = now() - interval '3 hours'
where title_en = 'Fixed';
create temp table stale as select * from public.claim_announcement_pushes(10);
select pg_temp.check('a push more than two hours old is dropped',
  (select count(*) = 0 from stale)
  and (select push_done_at is not null from public.announcements where title_en = 'Fixed'));

-- ========================================================== K7: feedback
select pg_temp.act_as('a1');
select pg_temp.refused('Ada reads user_feedback', 'select * from public.user_feedback', '42501');
select pg_temp.refused('Ada writes user_feedback',
  $q$insert into public.user_feedback (user_id, message) values ('00000000-0000-4000-8000-0000000000a1', 'x')$q$, '42501');
select pg_temp.refused('an empty message', $q$select public.submit_feedback('   ', 'web', '1.0.0')$q$, '22023');
select pg_temp.refused('a message of 2001 characters',
  format('select public.submit_feedback(%L, ''web'', ''1.0.0'')', repeat('x', 2001)), '22023');
select pg_temp.refused('a screenshot in somebody else''s folder',
  $q$select public.submit_feedback('hi', 'web', '1.0.0', '00000000-0000-4000-8000-0000000000b1/00000000-0000-4000-8000-000000000001.jpg')$q$, '22023');
select pg_temp.refused('a screenshot that was never uploaded',
  $q$select public.submit_feedback('hi', 'web', '1.0.0', '00000000-0000-4000-8000-0000000000a1/00000000-0000-4000-8000-000000000001.jpg')$q$, '22023');
select pg_temp.act_as(null);
select pg_temp.refused('a visitor sends feedback', $q$select public.submit_feedback('hi', 'web', '1.0.0')$q$, '42501');

-- Uploading screenshots (as the Storage API does, so policies apply).
create function pg_temp.upload(who text, object_path text) returns void language plpgsql as $$
begin
  perform pg_temp.act_as(who);
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values ('feedback-screenshots', object_path, pg_temp.uid(who), pg_temp.uid(who)::text,
    jsonb_build_object('size', 2048, 'mimetype', 'image/jpeg'));
  perform pg_temp.act_as(null);
end;
$$;
grant execute on function pg_temp.upload(text, text) to public;

select pg_temp.act_as('a1');
select pg_temp.upload('a1', '00000000-0000-4000-8000-0000000000a1/00000000-0000-4000-8000-000000000001.jpg');
select pg_temp.act_as('a1');
insert into pg_temp.ids
select 'fb1', public.submit_feedback('The send button is hidden', 'web', '1.4.0',
  '00000000-0000-4000-8000-0000000000a1/00000000-0000-4000-8000-000000000001.jpg');
select pg_temp.check('Ada sent feedback with a screenshot', pg_temp.i('fb1') is not null);
select public.submit_feedback('Second', 'ios', '1.4.0');
select public.submit_feedback('Third', 'ios', '1.4.0');
select public.submit_feedback('Fourth', 'ios', '1.4.0');
select public.submit_feedback('Fifth', 'ios', '1.4.0');
select pg_temp.refused('a sixth message inside the hour',
  $q$select public.submit_feedback('Sixth', 'ios', '1.4.0')$q$, 'PB429');
select pg_temp.act_as('b1');
select pg_temp.check('somebody else is not held up by it',
  public.submit_feedback('Bob here', 'android', '1.3.0') is not null);
select pg_temp.root();
select pg_temp.check('the version and platform are kept, and nothing else',
  (select app_version = '1.4.0' and platform = 'web'
     and user_id = pg_temp.uid('a1') and status = 'open'
   from public.user_feedback where id = pg_temp.i('fb1')));
-- After an hour she may write again.
update public.user_feedback set created_at = now() - interval '2 hours' where user_id = pg_temp.uid('a1');
select pg_temp.act_as('a1');
select pg_temp.check('an hour later Ada may send more',
  public.submit_feedback('Back again', 'web', '1.4.0') is not null);

-- The private bucket.
select pg_temp.act_as('b1');
select pg_temp.refused('Bob writes into Ada''s folder',
  $q$insert into storage.objects (bucket_id, name, owner, owner_id, metadata) values ('feedback-screenshots', '00000000-0000-4000-8000-0000000000a1/00000000-0000-4000-8000-000000000009.jpg', '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b1', '{"size": 10}')$q$, '42501');
select pg_temp.refused('nor a file that is not a picture name in his own',
  $q$insert into storage.objects (bucket_id, name, owner, owner_id, metadata) values ('feedback-screenshots', '00000000-0000-4000-8000-0000000000b1/notes.txt', '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b1', '{"size": 10}')$q$, '42501');
select pg_temp.check('Bob cannot read Ada''s screenshot',
  (select count(*) = 0 from storage.objects where bucket_id = 'feedback-screenshots'));
select pg_temp.upload('b1', '00000000-0000-4000-8000-0000000000b1/00000000-0000-4000-8000-000000000002.png');
select pg_temp.act_as('b1');
select pg_temp.check('Bob reads his own',
  (select count(*) = 1 from storage.objects where bucket_id = 'feedback-screenshots'));
select pg_temp.check('Bob cannot delete Ada''s',
  pg_temp.affected($q$delete from storage.objects where bucket_id = 'feedback-screenshots' and name like '00000000-0000-4000-8000-0000000000a1/%'$q$) = 0);
select pg_temp.check('nor rename his into her folder',
  pg_temp.affected($q$update storage.objects set name = '00000000-0000-4000-8000-0000000000a1/00000000-0000-4000-8000-000000000003.png' where bucket_id = 'feedback-screenshots'$q$) = 0);
select pg_temp.act_as('c1');
select pg_temp.check('a stranger reads none',
  (select count(*) = 0 from storage.objects where bucket_id = 'feedback-screenshots'));
select pg_temp.act_as(null);
select pg_temp.check('a visitor reads none',
  (select count(*) = 0 from storage.objects where bucket_id = 'feedback-screenshots'));
select pg_temp.act_as('b2');
select pg_temp.check('support reads every screenshot',
  (select count(*) = 2 from storage.objects where bucket_id = 'feedback-screenshots'));
select pg_temp.refused('but cannot add one to somebody''s folder',
  $q$insert into storage.objects (bucket_id, name, owner, owner_id, metadata) values ('feedback-screenshots', '00000000-0000-4000-8000-0000000000a1/00000000-0000-4000-8000-000000000008.jpg', '00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-0000000000b2', '{"size": 10}')$q$, '42501');
select pg_temp.act_as('a1');
select pg_temp.check('Ada may delete her own',
  pg_temp.affected($q$delete from storage.objects where bucket_id = 'feedback-screenshots' and name like '00000000-0000-4000-8000-0000000000a1/%'$q$) = 1);
-- (Put it back for the checks below.)
select pg_temp.upload('a1', '00000000-0000-4000-8000-0000000000a1/00000000-0000-4000-8000-000000000001.jpg');

-- At most 20 files in a folder.
select pg_temp.root();
insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
select 'feedback-screenshots', '00000000-0000-4000-8000-0000000000d1/00000000-0000-4000-8000-' || lpad(g::text, 12, '0') || '.jpg',
  pg_temp.uid('d1'), pg_temp.uid('d1')::text, '{"size": 10}'
from generate_series(1, 19) g;
select pg_temp.upload('d1', '00000000-0000-4000-8000-0000000000d1/00000000-0000-4000-8000-000000000100.jpg');
select pg_temp.act_as('d1');
select pg_temp.refused('a 21st file in a folder',
  $q$insert into storage.objects (bucket_id, name, owner, owner_id, metadata) values ('feedback-screenshots', '00000000-0000-4000-8000-0000000000d1/00000000-0000-4000-8000-000000000101.jpg', '00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000d1', '{"size": 10}')$q$, '42501');

-- Admins: reading and answering.
select pg_temp.act_as('b1');
select pg_temp.refused('Bob lists feedback', 'select public.admin_list_feedback()', '42501');
select pg_temp.refused('Bob reads feedback',
  format('select public.admin_get_feedback(%L)', pg_temp.i('fb1')), '42501');
select pg_temp.refused('Bob replies',
  format('select public.admin_reply_feedback(%L, ''hi'')', pg_temp.i('fb1')), '42501');
select pg_temp.refused('Bob closes feedback',
  format('select public.admin_close_feedback(%L)', pg_temp.i('fb1')), '42501');
select pg_temp.act_as(null);
select pg_temp.refused('a visitor lists feedback', 'select public.admin_list_feedback()', '42501');

select pg_temp.act_as('b2');
select pg_temp.check('support lists the open feedback with the people who wrote it',
  (select count(*) = 7 and bool_and(e ? 'username' and e ? 'message')
   from jsonb_array_elements(public.admin_list_feedback('open', 50)) e));
select pg_temp.check('a page is at most the size asked for',
  jsonb_array_length(public.admin_list_feedback('open', 3)) = 3);
select pg_temp.refused('an unknown status',
  $q$select public.admin_list_feedback('weird')$q$, '22023');
select pg_temp.check('support reads one piece of feedback with its screenshot path',
  (select g->>'username' = 'ada_ops' and g->>'message' = 'The send button is hidden'
     and g->>'screenshot_path' like '00000000-0000-4000-8000-0000000000a1/%'
     and g->>'app_version' = '1.4.0' and jsonb_array_length(g->'replies') = 0
   from (select public.admin_get_feedback(pg_temp.i('fb1')) g) x));
select pg_temp.refused('a reply with nothing in it',
  format('select public.admin_reply_feedback(%L, ''  '')', pg_temp.i('fb1')), '22023');
select pg_temp.refused('a reply to feedback that is not there',
  $q$select public.admin_reply_feedback('00000000-0000-4000-8000-0000000000ff', 'hi')$q$, 'P0002');
insert into pg_temp.ids
select 'reply1', public.admin_reply_feedback(pg_temp.i('fb1'), 'Thanks, fixed in 1.4.1.');

select pg_temp.act_as('a1');
select pg_temp.check('Ada gets the reply as an official notice, in both languages',
  (select count(*) = 1 from jsonb_array_elements(public.list_my_announcements()) e
   where e->>'kind' = 'feedback_reply' and e->>'body_en' = 'Thanks, fixed in 1.4.1.'
     and e->>'title_zh' = '对你反馈的回复' and e->>'title_en' = 'Reply to your feedback'));
select pg_temp.act_as('b1');
select pg_temp.check('Bob does not get it',
  (select count(*) = 0 from jsonb_array_elements(public.list_my_announcements()) e
   where e->>'kind' = 'feedback_reply' and e->>'body_en' like 'Thanks%'));
select pg_temp.act_as('c1');
select pg_temp.check('nor does Cy',
  (select count(*) = 0 from jsonb_array_elements(public.list_my_announcements()) e
   where e->>'kind' = 'feedback_reply'));
select pg_temp.act_as('b1');
select public.mark_announcement_read(pg_temp.i('reply1'));
select public.dismiss_announcement(pg_temp.i('reply1'));
select pg_temp.root();
select pg_temp.check('Bob cannot mark or dismiss the reply',
  (select count(*) = 0 from public.announcement_states where announcement_id = pg_temp.i('reply1')));
select pg_temp.check('answering closed the feedback and kept the time',
  (select status = 'closed' and replied_at is not null and closed_by = pg_temp.uid('b2')
   from public.user_feedback where id = pg_temp.i('fb1')));
select pg_temp.check('a reply is never pushed',
  (select count(*) = 0 from public.claim_announcement_pushes(10)));

select pg_temp.act_as('b2');
select pg_temp.check('the closed feedback is off the open list',
  (select count(*) = 0 from jsonb_array_elements(public.admin_list_feedback('open', 50)) e
   where e->>'id' = pg_temp.i('fb1')::text));
select pg_temp.check('and on the closed list',
  (select count(*) = 1 from jsonb_array_elements(public.admin_list_feedback('closed', 50)) e
   where e->>'id' = pg_temp.i('fb1')::text and e->>'replied_at' is not null));
select pg_temp.check('its replies are shown to the admin',
  jsonb_array_length(public.admin_get_feedback(pg_temp.i('fb1'))->'replies') = 1);
select public.admin_close_feedback(pg_temp.i('fb1'), false);
select pg_temp.check('support opens it again',
  public.admin_get_feedback(pg_temp.i('fb1'))->>'status' = 'open');
select pg_temp.act_as('a2');
select public.admin_reply_feedback(pg_temp.i('fb1'), 'One more thing.', false);
select pg_temp.check('a reply can leave it open',
  public.admin_get_feedback(pg_temp.i('fb1'))->>'status' = 'open'
  and jsonb_array_length(public.admin_get_feedback(pg_temp.i('fb1'))->'replies') = 2);
select pg_temp.act_as('f1');
select pg_temp.check('answers are in the audit log, naming the person and not the text',
  (select count(*) = 3 and bool_and(e->'details'->>'title' = '@ada_ops')
   from jsonb_array_elements(public.admin_list_audit_log(100)) e
   where e->>'action' in ('reply_feedback', 'reopen_feedback')));
select pg_temp.check('with the target kind feedback',
  (select count(*) >= 3 from jsonb_array_elements(public.admin_list_audit_log(100)) e
   where e->>'target_type' = 'feedback'));
select pg_temp.check('and nothing of what anybody wrote',
  not public.admin_list_audit_log(200)::text like '%fixed in 1.4.1%'
  and not public.admin_list_audit_log(200)::text like '%send button%');

-- ============================================================ K7: export
select pg_temp.act_as('a1');
select pg_temp.refused('Ada cannot call the export function',
  format('select public.export_my_feedback(%L)', pg_temp.uid('a1')), '42501');
select pg_temp.root();
select pg_temp.check('the export has Ada''s own feedback, her screenshot and the replies she got',
  (select jsonb_array_length(x) = 6
     and exists (select 1 from jsonb_array_elements(x) f
       where f->>'message' = 'The send button is hidden'
         and f->>'screenshot_bucket' = 'feedback-screenshots'
         and f->>'screenshot_path' like '00000000-0000-4000-8000-0000000000a1/%'
         and jsonb_array_length(f->'replies') = 2)
   from (select public.export_my_feedback(pg_temp.uid('a1')) x) y));
select pg_temp.check('Bob''s export holds only Bob''s',
  (select jsonb_array_length(x) = 1 and x::text like '%Bob here%' and x::text not like '%send button%'
     and x::text not like '%fixed in 1.4.1%'
   from (select public.export_my_feedback(pg_temp.uid('b1')) x) y));

-- ====================================================== K7: the account
-- (An account is deleted by prepare_account_deletion; the profile stays as
-- "Deleted User", so a trigger on deleted_at erases the feedback.)
insert into public.feature_flags (key, enabled, allow_user_ids)
values ('allow_ada', true, array[pg_temp.uid('a1'), pg_temp.uid('b1')]);
select pg_temp.act_as('a1');
select public.prepare_account_deletion();
select pg_temp.root();
select pg_temp.check('deleting an account takes the feedback, the replies and the states with it',
  (select count(*) = 0 from public.user_feedback where user_id = pg_temp.uid('a1'))
  and (select count(*) = 0 from public.announcements where audience_user_id = pg_temp.uid('a1'))
  and (select count(*) = 0 from public.announcement_states where user_id = pg_temp.uid('a1')));
select pg_temp.check('and her place on an allow list',
  (select allow_user_ids = array[pg_temp.uid('b1')] from public.feature_flags where key = 'allow_ada'));
select pg_temp.check('and nobody else''s',
  (select count(*) = 1 from public.user_feedback where user_id = pg_temp.uid('b1')));

\o
rollback;
