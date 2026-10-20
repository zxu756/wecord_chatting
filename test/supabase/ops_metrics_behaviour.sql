-- Behaviour checks for product statistics (K2: migrations 202610260100 to
-- 202610260120), monitoring and alerts (K3: 202610260140 to 202610260170) and
-- the error grouping of error reports 2.0 (K5: 202610260130). Run by
-- test/supabase/ops_metrics_test.dart against the local database: it applies
-- every migration the database lacks (the local baseline is 202610170001)
-- inside a transaction, acts as several people through row-level security,
-- and rolls back, so the database is left as it was. Run from the repository
-- root.
--
-- What it walks through: that nobody but a platform admin reads the numbers,
-- the alerts or the checks and nobody at all reads the tables; the daily
-- numbers (messages by type, active and new people, retention, push outcome,
-- a day that never goes down); that people are kept only as salted keys; the
-- error groups (one bug with other lines is one group) and version health;
-- every check (the cron history, the wake-up calls, push failures, error
-- spikes, AI limits, version crashes, new kinds of error) with its alert,
-- the cards for owners and moderators, the push (once, in each device's
-- language, at most five an hour), recovery after two good runs, quiet
-- reopening, and acknowledging and closing by hand with the audit log.
-- pg_cron and pg_net are not in the local database, so the script makes
-- stand-ins for their history tables inside the transaction.
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
\i supabase/migrations/202610250100_task_lists2_schema.sql
\i supabase/migrations/202610250110_task_lists2_rpcs.sql
\i supabase/migrations/202610250120_task_lists2_triggers.sql
\i supabase/migrations/202610250130_task_lists2_export.sql
\i supabase/migrations/202610250200_ban_expiry.sql
\i supabase/migrations/202610250210_thread_lock.sql
\i supabase/migrations/202610250220_mod_notes.sql
\i supabase/migrations/202610250230_ban_appeals.sql
\i supabase/migrations/202610250240_member_filter_batch.sql
\i supabase/migrations/202610250250_raid_schema.sql
\i supabase/migrations/202610250260_raid_detect.sql
\i supabase/migrations/202610250270_raid_rpcs.sql
\i supabase/migrations/202610250280_moderation_push.sql
\i supabase/migrations/202610250300_ai_ask.sql
\i supabase/migrations/202610250400_saved_items_schema.sql
\i supabase/migrations/202610250410_saved_items_rpcs.sql
\i supabase/migrations/202610250420_saved_notes_bucket.sql
\i supabase/migrations/202610250430_export_my_saved_items.sql
\i supabase/migrations/202610250510_merged_forward_alt_text.sql
\i supabase/migrations/202610260100_ops_metrics_schema.sql
\i supabase/migrations/202610260110_ops_metrics_compute.sql
\i supabase/migrations/202610260120_ops_metrics_admin.sql
\i supabase/migrations/202610260130_error_groups.sql
\i supabase/migrations/202610260140_ops_alerts_schema.sql
\i supabase/migrations/202610260150_ops_health_checks.sql
\i supabase/migrations/202610260160_ops_alerts_admin.sql
\i supabase/migrations/202610260170_ops_alert_push.sql

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
-- Ada, Bob and Cy are ordinary people. Root is the platform owner, Mia a
-- moderator, Sam support staff. Five more people (p1 to p5) fill the AI
-- limit test.
insert into auth.users (id, email, instance_id, aud, role)
select pg_temp.uid(v.n), v.name || '@ops.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('f1','root'),('a2','mia'),('b2','sam'),
  ('01','p1'),('02','p2'),('03','p3'),('04','p4'),('05','p5')) v(n, name);
insert into public.profiles (id, username, display_name)
select pg_temp.uid(v.n), v.name || '_ops', initcap(v.name)
from (values ('a1','ada'),('b1','bob'),('c1','cy'),('f1','root'),('a2','mia'),('b2','sam'),
  ('01','p1'),('02','p2'),('03','p3'),('04','p4'),('05','p5')) v(n, name);

insert into public.app_admins (user_id, role)
values (pg_temp.uid('f1'), 'owner'), (pg_temp.uid('a2'), 'moderator'), (pg_temp.uid('b2'), 'support');

delete from public.push_subscriptions;

-- Days are UTC days. D is three days ago: Bob and Cy sign up on it.
create temp table cal as
select (now() at time zone 'utc')::date as today,
       (now() at time zone 'utc')::date - 3 as d;
grant all on cal to public;

-- The live cards of the alert of a check.
create function pg_temp.cards(key text) returns bigint language sql stable as $$
  select count(*) from public.announcements n
  join public.ops_alerts a on a.id = n.ops_alert_id
  where a.check_key = key and n.retracted_at is null;
$$;
grant execute on function pg_temp.cards(text) to public;

update public.profiles set created_at = ((select d from pg_temp.cal) - 7)::timestamp at time zone 'utc' + interval '12 hours'
where id = pg_temp.uid('a1');
update public.profiles set created_at = ((select d from pg_temp.cal))::timestamp at time zone 'utc' + interval '12 hours'
where id in (pg_temp.uid('b1'), pg_temp.uid('c1'));

-- ============================================== K2: closed to every client
select pg_temp.act_as('a1');
select pg_temp.refused('Ada reads ops_daily_metrics', 'select * from public.ops_daily_metrics', '42501');
select pg_temp.refused('Ada reads ops_active_days', 'select * from public.ops_active_days', '42501');
select pg_temp.refused('Ada reads ops_settings (the salt)', 'select * from public.ops_settings', '42501');
select pg_temp.refused('Ada reads ops_push_stats', 'select * from public.ops_push_stats', '42501');
select pg_temp.refused('Ada reads ops_checks', 'select * from public.ops_checks', '42501');
select pg_temp.refused('Ada reads ops_alerts', 'select * from public.ops_alerts', '42501');
select pg_temp.refused('Ada reads ops_error_groups', 'select * from public.ops_error_groups', '42501');
select pg_temp.refused('Ada writes ops_alerts',
  $q$insert into public.ops_alerts (check_key, severity) values ('x', 'fail')$q$, '42501');
select pg_temp.refused('Ada reads the metrics', 'select public.admin_ops_metrics(30)', '42501');
select pg_temp.refused('Ada lists the error groups', 'select public.admin_ops_error_groups(24, 10)', '42501');
select pg_temp.refused('Ada lists the checks', 'select public.admin_list_ops_checks()', '42501');
select pg_temp.refused('Ada lists the alerts', 'select public.admin_list_ops_alerts()', '42501');
select pg_temp.refused('Ada runs the tick', 'select public.ops_tick()', '42501');
select pg_temp.refused('Ada runs the health check', 'select public.ops_health_check()', '42501');
select pg_temp.refused('Ada raises an alert',
  $q$select public.ops_raise_alert('x', 'state', 'fail', 'a', 'b', 'c', 'd', '{}')$q$, '42501');
select pg_temp.refused('Ada reports push counts', 'select public.ops_record_push(1, 0, 0)', '42501');
select pg_temp.refused('Ada computes a user key', 'select public.ops_user_key(auth.uid())', '42501');
select pg_temp.refused('Ada claims the alert pushes', 'select * from public.claim_ops_alert_pushes()', '42501');
select pg_temp.act_as(null);
select pg_temp.refused('a visitor reads the metrics', 'select public.admin_ops_metrics(30)', '42501');
select pg_temp.refused('a visitor lists the alerts', 'select public.admin_list_ops_alerts()', '42501');
select pg_temp.root();
select pg_temp.check('only the service role may report push counts',
  has_function_privilege('service_role', 'public.ops_record_push(integer,integer,integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.ops_record_push(integer,integer,integer)', 'execute')
  and not has_function_privilege('anon', 'public.ops_record_push(integer,integer,integer)', 'execute'));
select pg_temp.check('only the service role may claim the alert pushes',
  has_function_privilege('service_role', 'public.claim_ops_alert_pushes()', 'execute')
  and not has_function_privilege('authenticated', 'public.claim_ops_alert_pushes()', 'execute'));

-- Every role of admin may read the numbers.
select pg_temp.act_as('b2');
select pg_temp.check('support reads the metrics',
  jsonb_typeof(public.admin_ops_metrics(30)) = 'object');
select pg_temp.check('support lists the alerts',
  jsonb_typeof(public.admin_list_ops_alerts()) = 'array');
select pg_temp.check('support lists the checks',
  jsonb_typeof(public.admin_list_ops_checks()) = 'object');
select pg_temp.refused('support cannot close an alert',
  $q$select public.admin_resolve_ops_alert(gen_random_uuid())$q$, '42501');
select pg_temp.refused('support cannot acknowledge an alert',
  $q$select public.admin_ack_ops_alert(gen_random_uuid())$q$, '42501');

-- ===================================================== K2: users stay hidden
select pg_temp.root();
select pg_temp.check('a user key is a salted hash, not the id',
  public.ops_user_key(pg_temp.uid('a1')) ~ '^[0-9a-f]{32}$'
  and public.ops_user_key(pg_temp.uid('a1')) <> substr(md5(pg_temp.uid('a1')::text), 1, 32)
  and public.ops_user_key(pg_temp.uid('a1')) <> public.ops_user_key(pg_temp.uid('b1'))
  and public.ops_user_key(pg_temp.uid('a1')) = public.ops_user_key(pg_temp.uid('a1')));

-- ======================================================= K2: daily numbers
-- A direct chat. On D+1: Bob sends two texts and a voice message, Ada one
-- text. Cy does nothing; Cy never comes back.
insert into public.conversations (id, type, title)
values ('00000000-0000-4000-8000-0000000000c1', 'direct', null);
insert into public.conversation_members (conversation_id, user_id)
values ('00000000-0000-4000-8000-0000000000c1', pg_temp.uid('a1')),
       ('00000000-0000-4000-8000-0000000000c1', pg_temp.uid('b1'));
insert into public.messages (conversation_id, sender_id, type, body, attachment, created_at)
select '00000000-0000-4000-8000-0000000000c1', pg_temp.uid(s.who), s.type, s.body, null,
  ((select d + 1 from pg_temp.cal))::timestamp at time zone 'utc' + s.at
from (values
  ('b1', 'text', 'hi', interval '10 hours'),
  ('b1', 'text', 'there', interval '11 hours'),
  ('b1', 'voice', '', interval '12 hours'),
  ('a1', 'text', 'hello', interval '13 hours')
) s(who, type, body, at);

select public.ops_record_activity_day((select d + 1 from pg_temp.cal));
select public.ops_compute_day((select d + 1 from pg_temp.cal));
select public.ops_compute_day((select d from pg_temp.cal));
-- (The first days were worked out when the migration ran, with nobody there:
-- start retention over.)
update public.ops_daily_metrics set d1_retained = null, d7_retained = null, d30_retained = null;
select public.ops_finalize_retention((select today from pg_temp.cal));

select pg_temp.check('the day counts its messages by type',
  (select m.messages_total = 4
     and (m.messages_by_type->>'text')::int = 3
     and (m.messages_by_type->>'voice')::int = 1
   from public.ops_daily_metrics m where m.day = (select d + 1 from pg_temp.cal)));
select pg_temp.check('the day counts the people who were active (Ada and Bob)',
  (select m.active_users = 2 from public.ops_daily_metrics m where m.day = (select d + 1 from pg_temp.cal)));
select pg_temp.check('the sign-up day counts its new people',
  (select m.new_users = 2 from public.ops_daily_metrics m where m.day = (select d from pg_temp.cal)));
select pg_temp.check('one of the two new people came back the next day (D1)',
  (select m.d1_retained = 1 from public.ops_daily_metrics m where m.day = (select d from pg_temp.cal)));
select pg_temp.check('D7 and D30 stay empty until those days are over',
  (select m.d7_retained is null and m.d30_retained is null
   from public.ops_daily_metrics m where m.day = (select d from pg_temp.cal)));
select pg_temp.check('the table holds salted keys only, never an id',
  not exists (
    select 1 from public.ops_active_days a
    where a.user_key in (select replace(id::text, '-', '') from public.profiles)
  ) and (select count(*) from public.ops_active_days) > 0);

-- A message that disappears does not make the day smaller.
delete from public.messages where body = 'hello';
select public.ops_compute_day((select d + 1 from pg_temp.cal));
select pg_temp.check('a recomputed day never goes down',
  (select m.messages_total = 4 and (m.messages_by_type->>'text')::int = 3
   from public.ops_daily_metrics m where m.day = (select d + 1 from pg_temp.cal)));

-- The activity tick: a registered session says which platform and version.
insert into auth.sessions (id, user_id) values ('00000000-0000-4000-8000-0000000000e1', pg_temp.uid('a1'));
insert into public.user_devices (session_id, user_id, device_name, platform, app_version, last_active_at)
values ('00000000-0000-4000-8000-0000000000e1', pg_temp.uid('a1'), 'Phone', 'iOS', '1.4.0', now());
select public.ops_tick();
select pg_temp.check('the tick notes the session with its platform and version',
  exists (
    select 1 from public.ops_active_days a
    where a.user_key = public.ops_user_key(pg_temp.uid('a1'))
      and a.platform = 'ios' and a.app_version = '1.4.0'
  ));
select pg_temp.check('the tick makes today a row',
  exists (select 1 from public.ops_daily_metrics m where m.day = (select today from pg_temp.cal)));

-- Push counts come in as numbers only.
select public.ops_record_push(10, 2, 1);
select public.ops_record_push(5, 0, 0);
select public.ops_compute_day((select today from pg_temp.cal));
select pg_temp.check('push outcomes are summed per hour and per day',
  (select s.sent = 15 and s.failed = 2 and s.gone = 1 from public.ops_push_stats s)
  and (select m.push_sent = 15 and m.push_failed = 2 from public.ops_daily_metrics m
       where m.day = (select today from pg_temp.cal)));

-- The close finishes yesterday and tidies up.
select public.ops_daily_close();
insert into public.ops_active_days (day, user_key)
values ((select today from pg_temp.cal) - 60, repeat('a', 32));
select public.ops_daily_close();
select pg_temp.check('the close deletes activity older than 45 days',
  not exists (select 1 from public.ops_active_days a where a.day < (select today from pg_temp.cal) - 45));

-- ===================================================== K5: error grouping
select pg_temp.act_as('a1');
select public.report_client_errors(jsonb_build_array(
  jsonb_build_object('kind', 'flutter_error', 'fingerprint', 'aaaaaaaa11111111',
    'platform', 'iOS', 'app_version', '1.4.0', 'message', 'Bad state: No element 12',
    'stack', E'#0      List.first (dart:core-patch/growable_array.dart:100:5)\n#1      _ChatState.build (package:wecord/features/chats/chat.dart:120:7)\n#2      StatelessElement.build (package:flutter/src/widgets/framework.dart:5000:12)'),
  jsonb_build_object('kind', 'flutter_error', 'fingerprint', 'aaaaaaaa22222222',
    'platform', 'iOS', 'app_version', '1.4.0', 'message', 'Bad state: No element 99',
    'stack', E'#0      List.first (dart:core-patch/growable_array.dart:100:5)\n#1      _ChatState.build (package:wecord/features/chats/chat.dart:188:9)\n#2      StatelessElement.build (package:flutter/src/widgets/framework.dart:5000:12)'),
  jsonb_build_object('kind', 'flutter_error', 'fingerprint', 'aaaaaaaa33333333',
    'platform', 'iOS', 'app_version', '1.4.0', 'message', 'Bad state: No element 7',
    'stack', E'#0      List.first (dart:core-patch/growable_array.dart:100:5)\n#1      _ChatState.build (package:wecord/features/chats/chat.dart:300:1)'),
  jsonb_build_object('kind', 'flutter_error', 'fingerprint', 'bbbbbbbb11111111',
    'platform', 'iOS', 'app_version', '1.4.0', 'message', 'Bad state: No element 7',
    'stack', E'#0      List.first (dart:core-patch/growable_array.dart:100:5)\n#1      _ProfileState.build (package:wecord/features/profile/p.dart:20:1)'),
  jsonb_build_object('kind', 'platform_error', 'fingerprint', 'cccccccc11111111',
    'platform', 'iOS', 'app_version', '1.4.0', 'message', 'Null check operator used on a null value',
    'stack', E'*** *** ***\nbuild_id: ''abcdef0123456789''\n#00 abs 000000b6d4fea4b3 virt 00000000009d54b3 _kDartIsolateSnapshotInstructions+0x1234')
));
select pg_temp.root();
select pg_temp.check('one bug with three lines and callers is one group',
  (select count(distinct group_key) = 1 from public.client_errors
   where fingerprint in ('aaaaaaaa11111111', 'aaaaaaaa22222222', 'aaaaaaaa33333333')));
select pg_temp.check('another first app frame is another group',
  (select count(distinct group_key) = 2 from public.client_errors
   where fingerprint in ('aaaaaaaa11111111', 'bbbbbbbb11111111')));
select pg_temp.check('the label names the type and the first app frame',
  exists (select 1 from public.ops_error_groups g
          where g.label = 'flutter_error | Bad state: No element N | _ChatState.build @ package:wecord/features/chats/chat.dart'));
select pg_temp.check('a stack with no names is grouped by its message',
  exists (select 1 from public.ops_error_groups g
          where g.label = 'platform_error | Null check operator used on a null value | Null check operator used on a null value'));
select pg_temp.check('the group counts its reports and remembers the first version',
  (select g.reports = 3 and g.first_version = '1.4.0' and g.alerted_at is null
   from public.ops_error_groups g where g.label like '%ChatState.build%'));
select pg_temp.check('the digits of a message do not split a group',
  (select count(*) = 3 from public.ops_error_groups));

select pg_temp.act_as('b2');
select pg_temp.check('the console lists the biggest group first',
  (public.admin_ops_error_groups(24, 10)->0->>'reports')::int = 3
  and (public.admin_ops_error_groups(24, 10)->0->>'people')::int = 1
  and (public.admin_ops_error_groups(24, 10)->0->>'is_new')::boolean);

-- Version health: Ada runs 1.4.0 on iOS and had a crash there.
select pg_temp.check('the stats read per version and platform',
  (select (v->>'active_users')::int = 1 and (v->>'crash_users')::int = 1
   from jsonb_array_elements(public.admin_ops_metrics(30)->'versions') v
   where v->>'app_version' = '1.4.0' and v->>'platform' = 'ios'));
select pg_temp.check('the summary counts distinct people over a week and a month',
  (public.admin_ops_metrics(30)->'summary'->>'wau')::int >= 2
  and (public.admin_ops_metrics(30)->'summary'->>'mau')::int >= 2);
select pg_temp.check('a range is at least 7 days and the days come oldest first',
  (select (d->>'day')::date <= (select today from pg_temp.cal)
   from jsonb_array_elements(public.admin_ops_metrics(1)->'days') d limit 1)
  and (public.admin_ops_metrics(7)->'days'->0->>'day')::date
      < (public.admin_ops_metrics(7)->'days'->-1->>'day')::date);

-- ============================================== K3: nothing to look at yet
-- Without pg_cron and pg_net (as in local development, where an earlier
-- migration may have switched them on for this transaction) the checks say
-- "unknown" and raise nothing for them.
select pg_temp.root();
drop extension if exists pg_cron cascade;
drop extension if exists pg_net cascade;
select public.ops_health_check();
select pg_temp.check('a check that cannot look is unknown, not failed',
  (select c.status = 'unknown' from public.ops_checks c where c.key = 'cron_dispatch')
  and (select c.status = 'unknown' from public.ops_checks c where c.key = 'cron_failures')
  and (select c.status = 'unknown' from public.ops_checks c where c.key = 'edge_wakes'));
select pg_temp.check('the heartbeat is written on every run',
  exists (select 1 from public.ops_checks c where c.key = 'heartbeat' and c.status = 'ok'));
select pg_temp.check('the only alert is the new kind of error with three reports',
  (select count(*) = 1 and min(kind) = 'event' and min(severity) = 'warn' from public.ops_alerts)
  and (select a.title_en = 'New kind of error: flutter_error'
          and a.title_zh = '出现新的错误类型：flutter_error'
          and a.body_en like '%_ChatState.build%First seen in version 1.4.0, 3 reports so far.'
       from public.ops_alerts a));

-- The console reads the heartbeat.
select pg_temp.act_as('b2');
select pg_temp.check('the console gets the heartbeat and no heartbeat row among the checks',
  (public.admin_list_ops_checks()->>'heartbeat_at') is not null
  and not exists (
    select 1 from jsonb_array_elements(public.admin_list_ops_checks()->'checks') c
    where c->>'key' = 'heartbeat'));
select pg_temp.root();

-- ======================================================= K3: the cron job
create schema cron;
create table cron.job (jobid bigint primary key, jobname text);
create table cron.job_run_details (
  runid bigserial primary key, jobid bigint, status text,
  start_time timestamptz, end_time timestamptz, return_message text
);
grant usage on schema cron to public;
insert into cron.job values (1, 'wecord-later-dispatch'), (2, 'wecord-other');
insert into cron.job_run_details (jobid, status, start_time, end_time)
values (1, 'succeeded', now() - interval '13 minutes', now() - interval '13 minutes');

insert into public.push_subscriptions (id, user_id, endpoint, p256dh, auth, language)
values
  ('00000000-0000-4000-8000-000000000501', pg_temp.uid('f1'), 'https://push.example.com/root', repeat('k', 60), repeat('a', 20), 'zh'),
  ('00000000-0000-4000-8000-000000000502', pg_temp.uid('a2'), 'https://push.example.com/mia', repeat('k', 60), repeat('a', 20), 'en'),
  ('00000000-0000-4000-8000-000000000503', pg_temp.uid('b2'), 'https://push.example.com/sam', repeat('k', 60), repeat('a', 20), 'en'),
  ('00000000-0000-4000-8000-000000000504', pg_temp.uid('a1'), 'https://push.example.com/ada', repeat('k', 60), repeat('a', 20), 'en');

select public.ops_check_cron();
select pg_temp.check('a dispatcher that has not succeeded for 13 minutes fails',
  (select c.status = 'fail' from public.ops_checks c where c.key = 'cron_dispatch'));
select pg_temp.check('a failure opens one alert',
  (select count(*) = 1 and min(severity) = 'fail' and min(kind) = 'state'
   from public.ops_alerts where check_key = 'cron_dispatch' and resolved_at is null));
select pg_temp.check('the alert has an English and a Chinese text',
  (select title_en = 'Scheduled tasks have stopped' and title_zh = '定时任务停了'
      and body_zh like '%13 分钟%' and body_en like '%13 minutes%'
   from public.ops_alerts where check_key = 'cron_dispatch'));
select pg_temp.check('an owner and a moderator get an official card, support and Ada do not',
  pg_temp.cards('cron_dispatch') = 2
  and exists (select 1 from public.announcements n join public.ops_alerts a on a.id = n.ops_alert_id
              where a.check_key = 'cron_dispatch' and n.audience_user_id = pg_temp.uid('f1'))
  and exists (select 1 from public.announcements n join public.ops_alerts a on a.id = n.ops_alert_id
              where a.check_key = 'cron_dispatch' and n.audience_user_id = pg_temp.uid('a2'))
  and not exists (select 1 from public.announcements n join public.ops_alerts a on a.id = n.ops_alert_id
              where a.check_key = 'cron_dispatch' and n.audience_user_id in (pg_temp.uid('b2'), pg_temp.uid('a1'))));

select public.ops_check_cron();
select pg_temp.check('running the check again does not open a second alert or card',
  (select count(*) = 1 from public.ops_alerts where check_key = 'cron_dispatch')
  and pg_temp.cards('cron_dispatch') = 2);

-- The card as the person sees it.
select pg_temp.act_as('a2');
select pg_temp.check('the moderator sees the alert in Notifications as an ops_alert notice',
  exists (
    select 1 from jsonb_array_elements(public.list_my_announcements()) n
    where n->>'kind' = 'ops_alert' and n->>'title_zh' = '定时任务停了'));
select pg_temp.act_as('a1');
select pg_temp.check('an ordinary person sees none',
  not exists (
    select 1 from jsonb_array_elements(public.list_my_announcements()) n
    where n->>'kind' = 'ops_alert'));
select pg_temp.root();

-- The push: a failure pushes the owners' and moderators' devices once, in
-- their language.
select pg_temp.check('the push goes to the owner (Chinese) and the moderator (English) only',
  (select count(*) = 2
      and bool_or(subscription_id = '00000000-0000-4000-8000-000000000501' and title = '定时任务停了')
      and bool_or(subscription_id = '00000000-0000-4000-8000-000000000502' and title = 'Scheduled tasks have stopped')
      and bool_and(url = '/#/admin')
   from public.claim_ops_alert_pushes()));
select pg_temp.check('an alert is pushed once',
  (select count(*) = 0 from public.claim_ops_alert_pushes()));

-- It recovers: closes after two good runs, and the cards go with it.
insert into cron.job_run_details (jobid, status, start_time, end_time)
values (1, 'succeeded', now() - interval '30 seconds', now() - interval '30 seconds');
select public.ops_check_cron();
select pg_temp.check('one good run does not close it yet',
  (select count(*) = 1 from public.ops_alerts where check_key = 'cron_dispatch' and resolved_at is null));
select public.ops_check_cron();
select pg_temp.check('two good runs close it by itself and take the cards back',
  (select resolution = 'auto' and resolved_at is not null from public.ops_alerts where check_key = 'cron_dispatch')
  and pg_temp.cards('cron_dispatch') = 0);

-- It comes back within the hour: the same alert, quietly.
delete from cron.job_run_details where jobid = 1;
insert into cron.job_run_details (jobid, status, start_time, end_time)
values (1, 'succeeded', now() - interval '6 minutes', now() - interval '6 minutes');
select public.ops_check_cron();
select pg_temp.check('a warning at 6 minutes reopens the same alert as a warning',
  (select count(*) = 1 and min(severity) = 'warn' and min(reopen_count) = 1 and bool_and(resolved_at is null)
   from public.ops_alerts where check_key = 'cron_dispatch'));
select pg_temp.check('a reopened alert brings its cards back, none new',
  pg_temp.cards('cron_dispatch') = 2
  and (select count(*) = 2 from public.announcements n join public.ops_alerts a on a.id = n.ops_alert_id
       where a.check_key = 'cron_dispatch'));
select pg_temp.check('a warning is not pushed',
  (select count(*) = 0 from public.claim_ops_alert_pushes()));
delete from cron.job_run_details where jobid = 1;
select public.ops_check_cron();
select pg_temp.check('a warning that turns into a failure is pushed',
  (select count(*) = 2 from public.claim_ops_alert_pushes())
  and (select severity = 'fail' from public.ops_alerts where check_key = 'cron_dispatch'));
select pg_temp.check('with no run on record the alert says so',
  (select body_en like '%no successful run%' and body_zh like '%没有成功运行的记录%'
   from public.ops_alerts where check_key = 'cron_dispatch'));

-- Failures of any job.
insert into cron.job_run_details (jobid, status, start_time, end_time)
select 2, 'failed', now() - interval '5 minutes', now() - interval '5 minutes' from generate_series(1, 2);
select public.ops_check_cron();
select pg_temp.check('two failed runs in 30 minutes warn',
  (select c.status = 'warn' from public.ops_checks c where c.key = 'cron_failures'));
insert into cron.job_run_details (jobid, status, start_time, end_time)
select 2, 'failed', now() - interval '4 minutes', now() - interval '4 minutes' from generate_series(1, 3);
select public.ops_check_cron();
select pg_temp.check('five failed runs of one job fail and name the job',
  (select c.status = 'fail' and c.detail->'jobs'->0->>'job' = 'wecord-other' and (c.detail->'jobs'->0->>'failed')::int = 5
   from public.ops_checks c where c.key = 'cron_failures'));
select pg_temp.check('the failure alert names the job in both languages',
  (select body_en like '%wecord-other (5)%' and body_zh like '%wecord-other (5)%'
   from public.ops_alerts where check_key = 'cron_failures'));

-- ======================================================= K3: wake-up calls
create schema net;
create table net._http_response (
  id bigserial primary key, status_code integer, timed_out boolean, error_msg text,
  created timestamptz default now()
);
grant usage on schema net to public;
insert into net._http_response (status_code, created) values (200, now() - interval '2 minutes'), (500, now() - interval '2 minutes');
select public.ops_check_wakes();
select pg_temp.check('a few calls are never enough to judge',
  (select c.status = 'ok' from public.ops_checks c where c.key = 'edge_wakes'));
insert into net._http_response (status_code, created)
select 401, now() - interval '1 minute' from generate_series(1, 5);
select public.ops_check_wakes();
select pg_temp.check('most calls failing fails the check',
  (select c.status = 'fail' and (c.detail->>'calls')::int = 7 and (c.detail->>'failed')::int = 6
   from public.ops_checks c where c.key = 'edge_wakes'));
insert into net._http_response (status_code, created)
select 200, now() - interval '1 minute' from generate_series(1, 30);
select public.ops_check_wakes();
select pg_temp.check('a healthy majority is fine again',
  (select c.status = 'ok' from public.ops_checks c where c.key = 'edge_wakes'));

-- ===================================================== K3: push failures
select public.ops_check_push();
select pg_temp.check('15 pushes sent and 2 failed is fine',
  (select c.status = 'ok' from public.ops_checks c where c.key = 'push_failures'));
select public.ops_record_push(0, 40, 0);
select public.ops_check_push();
select pg_temp.check('a high share of failed pushes fails (dead subscriptions do not count)',
  (select c.status = 'fail' and (c.detail->>'failed')::int = 42 from public.ops_checks c where c.key = 'push_failures'));

-- ======================================================= K3: error spike
select public.ops_check_error_spike();
select pg_temp.check('a handful of reports is not a spike',
  (select c.status = 'ok' from public.ops_checks c where c.key = 'error_spike'));
insert into public.client_errors (kind, fingerprint, message, app_version, platform)
select 'rpc_error', lpad(to_hex(g), 16, '0'), 'status=500', '1.4.0', 'iOS' from generate_series(1, 40) g;
select public.ops_check_error_spike();
select pg_temp.check('forty-five reports in an hour warn',
  (select c.status = 'warn' from public.ops_checks c where c.key = 'error_spike'));
insert into public.client_errors (kind, fingerprint, message, app_version, platform)
select 'rpc_error', lpad(to_hex(1000 + g), 16, '0'), 'status=500', '1.4.0', 'iOS' from generate_series(1, 70) g;
select public.ops_check_error_spike();
select pg_temp.check('over a hundred reports in an hour fail',
  (select c.status = 'fail' from public.ops_checks c where c.key = 'error_spike'));

-- ============================================================ K3: AI use
select public.ops_check_ai();
select pg_temp.check('no AI use is fine',
  (select c.status = 'ok' from public.ops_checks c where c.key = 'ai_quota'));
insert into public.ai_usage (user_id, day, requests)
select pg_temp.uid(n), (now() at time zone 'utc')::date, 50 from (values ('01'),('02'),('03'),('04')) v(n);
select public.ops_check_ai();
select pg_temp.check('four people at their limit is normal',
  (select c.status = 'ok' from public.ops_checks c where c.key = 'ai_quota'));
insert into public.ai_usage (user_id, day, requests)
values (pg_temp.uid('05'), (now() at time zone 'utc')::date, 50);
select public.ops_check_ai();
select pg_temp.check('five people at their limit warn',
  (select c.status = 'warn' from public.ops_checks c where c.key = 'ai_quota'));
insert into public.circles (id, name, owner_id)
values ('00000000-0000-4000-8000-0000000000b1', 'Guarded', pg_temp.uid('a1'));
insert into public.ai_circle_usage (circle_id, day, requests)
values ('00000000-0000-4000-8000-0000000000b1', (now() at time zone 'utc')::date, 500);
select public.ops_check_ai();
select pg_temp.check('a circle whose AI guard used up the day fails',
  (select c.status = 'fail' and (c.detail->>'circles_at_limit')::int = 1 from public.ops_checks c where c.key = 'ai_quota'));
select pg_temp.check('a setting that is not there falls back to the default',
  public.ops_setting_int('ai_guard_circle_limit', 500) = 500
  and public.ops_setting_int('nothing_here', 7) = 7);
insert into public.ops_settings (key, value) values ('ai_guard_circle_limit', '1000'::jsonb);
select public.ops_check_ai();
select pg_temp.check('with a limit of 1000 the circle is only at half',
  (select c.status <> 'fail' from public.ops_checks c where c.key = 'ai_quota'));

-- ==================================================== K3/K5: version health
select public.ops_check_versions();
select pg_temp.check('a version with too few people is not judged',
  (select c.status = 'ok' from public.ops_checks c where c.key = 'version_health'));
insert into public.ops_settings (key, value) values ('version_health_min_users', '1'::jsonb);
select public.ops_check_versions();
select pg_temp.check('one of one person crashing on 1.4.0 fails the version',
  (select c.status = 'fail' and c.detail->>'app_version' = '1.4.0' and c.detail->>'platform' = 'ios'
   from public.ops_checks c where c.key = 'version_health'));
select pg_temp.check('the alert names the version in Chinese',
  (select title_zh = '版本 1.4.0 在崩溃' from public.ops_alerts where check_key = 'version_health'));

-- ================================================ K5: a new kind of error
select public.ops_check_new_errors();
select pg_temp.check('the big new group of rpc errors is a second event alert, once',
  (select count(*) = 2 from public.ops_alerts where kind = 'event' and resolved_at is null));
select public.ops_check_new_errors();
select pg_temp.check('the same group is not announced twice',
  (select count(*) = 2 from public.ops_alerts where kind = 'event'));
select pg_temp.check('an event alert is not pushed',
  (select bool_and(push_claimed_at is null) from public.ops_alerts where kind = 'event'));
select pg_temp.check('a group below three reports stays quiet',
  (select count(*) = 2 from public.ops_error_groups g where g.alerted_at is null));

-- An event is news for a day.
update public.ops_alerts set opened_at = now() - interval '25 hours' where kind = 'event';
select public.ops_health_check();
select pg_temp.check('event alerts close by themselves after a day',
  (select count(*) = 2 and bool_and(resolution = 'auto') from public.ops_alerts where kind = 'event'));

-- ============================================================ push budget
-- Six failures at once: at most five pushes in an hour in all.
select public.ops_raise_alert('budget_' || g, 'state', 'fail', 'Trouble ' || g, '麻烦 ' || g, 'x', '乙', '{}')
from generate_series(1, 6) g;
select count(*) from public.claim_ops_alert_pushes();
select pg_temp.check('a night of failures is limited to five alert pushes an hour',
  (select count(*) = 5 from public.ops_alerts where severity = 'fail' and push_claimed_at > now() - interval '1 hour'));
select pg_temp.check('the rest wait for the next hour',
  (select count(*) = 0 from public.claim_ops_alert_pushes())
  and (select count(*) >= 1 from public.ops_alerts
       where severity = 'fail' and resolved_at is null and push_claimed_at is null));

-- ======================================================= K3: admin actions
select pg_temp.root();
select id as cron_alert from public.ops_alerts where check_key = 'cron_dispatch' \gset
select pg_temp.act_as('a2');
select pg_temp.check('a moderator lists the open alerts',
  (select count(*) >= 5 from jsonb_array_elements(public.admin_list_ops_alerts('open', 50, null))));
select pg_temp.check('the list carries the texts in both languages',
  exists (
    select 1 from jsonb_array_elements(public.admin_list_ops_alerts('open', 50, null)) a
    where a->>'check_key' = 'cron_dispatch' and a->>'title_zh' = '定时任务停了'));
select public.admin_ack_ops_alert(:'cron_alert');
select pg_temp.root();
select pg_temp.check('acknowledging marks who and when, and keeps the alert open',
  (select acknowledged_by = pg_temp.uid('a2') and acknowledged_at is not null and resolved_at is null
   from public.ops_alerts where check_key = 'cron_dispatch'));
select pg_temp.check('the audit log has it',
  exists (select 1 from public.admin_audit_log l
          where l.action = 'ack_ops_alert' and l.actor_id = pg_temp.uid('a2')));
select pg_temp.act_as('a2');
select pg_temp.refused('an alert that is not there cannot be acknowledged',
  $q$select public.admin_ack_ops_alert(gen_random_uuid())$q$, 'P0002');
select pg_temp.act_as('f1');
select public.admin_resolve_ops_alert(:'cron_alert');
select pg_temp.refused('a closed alert cannot be closed again',
  format('select public.admin_resolve_ops_alert(%L)', :'cron_alert'), 'P0002');
select pg_temp.check('the resolved list has it, who closed it, and how',
  exists (
    select 1 from jsonb_array_elements(public.admin_list_ops_alerts('resolved', 50, null)) a
    where a->>'check_key' = 'cron_dispatch' and a->>'resolution' = 'manual' and a->>'resolved_by' = 'root_ops'));
select pg_temp.root();
select pg_temp.check('the owner closed it by hand and its cards went',
  (select resolution = 'manual' and resolved_by = pg_temp.uid('f1') from public.ops_alerts where check_key = 'cron_dispatch')
  and pg_temp.cards('cron_dispatch') = 0);
select pg_temp.check('the audit log has the close too',
  exists (select 1 from public.admin_audit_log l
          where l.action = 'resolve_ops_alert' and l.actor_id = pg_temp.uid('f1')
            and l.target_type = 'config'));

-- An event alert is closed by acknowledging it.
select public.ops_raise_alert('new_error_zzzzzzzzzzzzzzzz', 'event', 'warn', 'New kind of error: x', '出现新的错误类型：x', 'b', '乙', '{}');
select id as event_alert from public.ops_alerts where check_key = 'new_error_zzzzzzzzzzzzzzzz' \gset
select pg_temp.act_as('a2');
select public.admin_ack_ops_alert(:'event_alert');
select pg_temp.root();
select pg_temp.check('acknowledging an event closes it',
  (select resolution = 'manual' from public.ops_alerts where check_key = 'new_error_zzzzzzzzzzzzzzzz'));

\o
rollback;
