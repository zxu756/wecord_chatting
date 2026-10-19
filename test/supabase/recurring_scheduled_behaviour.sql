-- Behaviour checks for repeating scheduled messages (D4: migrations
-- 202610240440 and 202610240450). Run by
-- test/supabase/recurring_scheduled_test.dart against the local database: it
-- applies every migration the database lacks (the local baseline is
-- 202610170001) inside a transaction, acts as several people, and rolls back,
-- so the database is left as it was. Run from the repository root.
--
-- What it walks through: the rule on the wall clock (daily, weekdays, weekly,
-- monthly with the last-day rule for months without the day, the end date,
-- daylight saving in New York, Berlin and Sydney: a skipped hour, a repeated
-- hour, 9:00 staying 9:00), what the guard works out and refuses, sending
-- followed by exactly one next send (retries, a crash after the message was
-- stored, failed sends, "Send now", late sends, a stopped series), long
-- chains across months and clock changes, and the next send in My agenda.
\set ON_ERROR_STOP on

begin;

-- One behaviour script at a time: they change the same tables, and test
-- files run in parallel.
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
\i supabase/migrations/202610240400_urgent_schema.sql
\i supabase/migrations/202610240410_urgent_rpcs.sql
\i supabase/migrations/202610240420_announcement_ack_rpcs.sql
\i supabase/migrations/202610240430_urgent_pushes.sql
\i supabase/migrations/202610240440_scheduled_recurrence_schema.sql
\i supabase/migrations/202610240450_scheduled_recurrence_next.sql
\i supabase/migrations/202610240460_dispatch_urgent.sql
\o /dev/null

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

-- Acts as one of the people (as PostgREST would): the first character of
-- the id suffix, e.g. 'a' is ...0000000000a1. Null: nobody, as the table
-- owner.
create function pg_temp.act_as(who text) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  if who is not null then
    perform set_config(
      'request.jwt.claim.sub',
      format('00000000-0000-4000-8000-0000000000%s1', who),
      true
    );
    perform set_config(
      'request.jwt.claims',
      json_build_object(
        'sub', format('00000000-0000-4000-8000-0000000000%s1', who),
        'role', 'authenticated'
      )::text,
      true
    );
    execute 'set local role authenticated';
  end if;
end;
$$;
grant execute on function pg_temp.act_as(text) to public;

create function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin
  if ok is distinct from true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok: %', label;
end;
$$;

-- The statement must fail with exactly this SQLSTATE (as the current role).
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
grant execute on function pg_temp.refused(text, text, text) to public;

-- The same, and the message must contain [fragment].
create function pg_temp.refused_with(label text, stmt text, fragment text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    if position(fragment in sqlerrm) = 0 then
      raise exception 'FAILED: % (wanted "%", got % %)', label, fragment, sqlstate, sqlerrm;
    end if;
    raise notice 'ok: %', label;
    return;
  end;
  raise exception 'FAILED: % (nothing was refused)', label;
end;
$$;
grant execute on function pg_temp.refused_with(text, text, text) to public;

create function pg_temp.u(who text) returns uuid language sql immutable as $$
  select format('00000000-0000-4000-8000-0000000000%s1', who)::uuid;
$$;
grant execute on function pg_temp.u(text) to public;

create function pg_temp.mid(name text) returns uuid language sql stable as $$
  select id from ids where ids.name = mid.name;
$$;
grant execute on function pg_temp.mid(text) to public;

-- Sends a text message as one of the people into the conversation called
-- [chat] in ids.
create function pg_temp.say(who text, chat text, text_body text)
returns uuid language plpgsql as $$
declare
  sent uuid;
begin
  perform pg_temp.act_as(who);
  sent := public.send_text_message(
    (select id from ids where name = chat), text_body, null, null, '[]'::jsonb
  );
  perform pg_temp.act_as(null);
  return sent;
end;
$$;
grant execute on function pg_temp.say(text, text, text) to public;

-- A count of rows, as the table owner.
create function pg_temp.n(query text) returns integer language plpgsql as $$
declare
  result integer;
begin
  execute format('select count(*) from (%s) q', query) into result;
  return result;
end;
$$;
grant execute on function pg_temp.n(text) to public;

create function pg_temp.new_user(code text, handle text) returns void language plpgsql as $$
begin
  insert into auth.users (id, email, instance_id, aud, role)
  values (pg_temp.u(code), handle || '@test.test',
    '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
  insert into public.profiles (id, username, display_name)
  values (pg_temp.u(code), handle || '_t', initcap(handle));
end;
$$;
grant execute on function pg_temp.new_user(text, text) to public;

-- Compares a text result with what was expected, and shows both when not.
create function pg_temp.same(label text, actual text, expected text) returns void language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'FAILED: % (wanted "%", got "%")', label, expected, actual;
  end if;
  raise notice 'ok: %', label;
end;
$$;
grant execute on function pg_temp.same(text, text, text) to public;

-- ===================================================================== cast
-- a Ada schedules messages; b Bo is in the group "Ops" with her; c Cy is her
-- friend in a direct chat.
select pg_temp.new_user('a', 'ada');
select pg_temp.new_user('b', 'bo');
select pg_temp.new_user('c', 'cy');
select pg_temp.new_user('d', 'di');

insert into public.conversations (type, title) values ('group', 'Ops') returning id \gset ops_
insert into ids values ('ops', :'ops_id');
insert into public.conversation_members (conversation_id, user_id, role)
values (:'ops_id', pg_temp.u('a'), 'owner'), (:'ops_id', pg_temp.u('b'), 'member');

insert into public.friendships (user_low_id, user_high_id)
values (least(pg_temp.u('a'), pg_temp.u('c')), greatest(pg_temp.u('a'), pg_temp.u('c')));
insert into public.conversations (type, title) values ('direct', null) returning id \gset dm_
insert into ids values ('dm', :'dm_id');
insert into public.conversation_members (conversation_id, user_id)
values (:'dm_id', pg_temp.u('a')), (:'dm_id', pg_temp.u('c'));

-- The wall clock of an instant in a zone, as text: "2030-03-10 03:30".
create function pg_temp.wall(at timestamptz, zone text) returns text language sql stable as $$
  select to_char(at at time zone zone, 'YYYY-MM-DD HH24:MI');
$$;
grant execute on function pg_temp.wall(timestamptz, text) to public;

-- The next send of a rule after a local moment: its wall clock, or 'none'.
create function pg_temp.nxt(kind text, day integer, at_time time, zone text,
                            after_local timestamp, until_date date default null)
returns text language sql stable as $$
  select coalesce(
    pg_temp.wall(public.recurrence_next(kind, day, at_time, zone, after_local at time zone zone, until_date), zone),
    'none');
$$;
grant execute on function pg_temp.nxt(text, integer, time, text, timestamp, date) to public;

-- ============================================== the rule, on the wall clock

select pg_temp.same('daily: the next 9:00 in Shanghai',
  pg_temp.nxt('daily', null, '09:00', 'Asia/Shanghai', '2030-05-06 08:00'), '2030-05-06 09:00');
select pg_temp.same('daily: after 9:00 it is tomorrow',
  pg_temp.nxt('daily', null, '09:00', 'Asia/Shanghai', '2030-05-06 09:00'), '2030-05-07 09:00');
select pg_temp.same('daily: a send 40 seconds late does not repeat the same day',
  pg_temp.nxt('daily', null, '09:00', 'Asia/Shanghai', '2030-05-06 09:00:40'), '2030-05-07 09:00');
select pg_temp.same('daily: the instant is 01:00 UTC for Shanghai (no daylight saving)',
  to_char(public.recurrence_next('daily', null, '09:00', 'Asia/Shanghai', '2030-05-06 00:00+00') at time zone 'UTC', 'YYYY-MM-DD HH24:MI'),
  '2030-05-06 01:00');
select pg_temp.same('daily: Kolkata is 5:30 ahead',
  to_char(public.recurrence_next('daily', null, '09:00', 'Asia/Kolkata', '2030-05-06 00:00+00') at time zone 'UTC', 'YYYY-MM-DD HH24:MI'),
  '2030-05-06 03:30');

-- 2030-05-10 is a Friday.
select pg_temp.same('weekdays: Friday after 9:00 is Monday',
  pg_temp.nxt('weekdays', null, '09:00', 'Europe/Berlin', '2030-05-10 09:00'), '2030-05-13 09:00');
select pg_temp.same('weekdays: Saturday goes to Monday too',
  pg_temp.nxt('weekdays', null, '09:00', 'Europe/Berlin', '2030-05-11 12:00'), '2030-05-13 09:00');
select pg_temp.same('weekdays: Monday morning is the same day',
  pg_temp.nxt('weekdays', null, '09:00', 'Europe/Berlin', '2030-05-13 08:00'), '2030-05-13 09:00');
select pg_temp.same('weekly: every Wednesday (3)',
  pg_temp.nxt('weekly', 3, '18:30', 'America/Los_Angeles', '2030-05-10 00:00'), '2030-05-15 18:30');
select pg_temp.same('weekly: on the day, after the time, is next week',
  pg_temp.nxt('weekly', 3, '18:30', 'America/Los_Angeles', '2030-05-15 18:30'), '2030-05-22 18:30');
select pg_temp.same('weekly: Sunday (7)',
  pg_temp.nxt('weekly', 7, '08:00', 'UTC', '2030-05-10 00:00'), '2030-05-12 08:00');

-- Months without the day: the last day of that month.
select pg_temp.same('monthly: the 15th',
  pg_temp.nxt('monthly', 15, '10:00', 'UTC', '2030-01-20 00:00'), '2030-02-15 10:00');
select pg_temp.same('monthly: the 31st after January is the 28th of February',
  pg_temp.nxt('monthly', 31, '10:00', 'UTC', '2030-01-31 10:00'), '2030-02-28 10:00');
select pg_temp.same('monthly: and goes back to the 31st in March',
  pg_temp.nxt('monthly', 31, '10:00', 'UTC', '2030-02-28 10:00'), '2030-03-31 10:00');
select pg_temp.same('monthly: the 31st of March to April is the 30th',
  pg_temp.nxt('monthly', 31, '10:00', 'UTC', '2030-03-31 10:00'), '2030-04-30 10:00');
select pg_temp.same('monthly: and April to May is the 31st',
  pg_temp.nxt('monthly', 31, '10:00', 'UTC', '2030-04-30 10:00'), '2030-05-31 10:00');
select pg_temp.same('monthly: the 30th in February is the 28th',
  pg_temp.nxt('monthly', 30, '10:00', 'UTC', '2030-01-30 10:00'), '2030-02-28 10:00');
select pg_temp.same('monthly: the 29th in a common February is the 28th',
  pg_temp.nxt('monthly', 29, '10:00', 'UTC', '2030-01-29 10:00'), '2030-02-28 10:00');
select pg_temp.same('monthly: the 29th in a leap February is the 29th (2032)',
  pg_temp.nxt('monthly', 29, '10:00', 'UTC', '2032-01-29 10:00'), '2032-02-29 10:00');
select pg_temp.same('monthly: the 31st in a leap February is the 29th',
  pg_temp.nxt('monthly', 31, '10:00', 'UTC', '2032-01-31 10:00'), '2032-02-29 10:00');
select pg_temp.same('monthly: the 31st on the 28th of February (still before the 28th at 10:00) stays in February',
  pg_temp.nxt('monthly', 31, '10:00', 'UTC', '2030-02-28 09:00'), '2030-02-28 10:00');
select pg_temp.same('monthly: the 1st over a year end',
  pg_temp.nxt('monthly', 1, '10:00', 'UTC', '2030-12-01 10:00'), '2031-01-01 10:00');

-- The end date is the last local date, inclusive.
select pg_temp.same('until: on the end date is still sent',
  pg_temp.nxt('daily', null, '09:00', 'UTC', '2030-05-06 09:00', date '2030-05-07'), '2030-05-07 09:00');
select pg_temp.same('until: after the end date there is none',
  pg_temp.nxt('daily', null, '09:00', 'UTC', '2030-05-07 09:00', date '2030-05-07'), 'none');
select pg_temp.same('until: the end date is the sender''s local date (Shanghai is ahead of UTC)',
  pg_temp.nxt('daily', null, '07:00', 'Asia/Shanghai', '2030-05-06 07:00', date '2030-05-07'), '2030-05-07 07:00');
select pg_temp.same('until: a weekly rule whose next day is past the end',
  pg_temp.nxt('weekly', 1, '09:00', 'UTC', '2030-05-13 09:00', date '2030-05-19'), 'none');

-- Daylight saving. 2030: the US clocks go forward on 10 March and back on 3
-- November; the EU's on 31 March and 27 October.
select pg_temp.same('New York: 9:00 stays 9:00 on the clock after the change (weekly Monday)',
  pg_temp.wall(public.recurrence_next('weekly', 1, '09:00', 'America/New_York', '2030-03-04 15:00+00'), 'America/New_York'),
  '2030-03-11 09:00');
select pg_temp.same('New York: and it is 13:00 UTC in summer, 14:00 UTC in winter',
  to_char(public.recurrence_next('weekly', 1, '09:00', 'America/New_York', '2030-03-04 15:00+00') at time zone 'UTC', 'YYYY-MM-DD HH24:MI'),
  '2030-03-11 13:00');
select pg_temp.same('New York: the winter Monday is 14:00 UTC',
  to_char(public.recurrence_next('weekly', 1, '09:00', 'America/New_York', '2030-02-25 15:00+00') at time zone 'UTC', 'YYYY-MM-DD HH24:MI'),
  '2030-03-04 14:00');
select pg_temp.same('New York: a time inside the skipped hour goes to the time after the gap (02:30 becomes 03:30)',
  pg_temp.nxt('daily', null, '02:30', 'America/New_York', '2030-03-09 02:30'), '2030-03-10 03:30');
select pg_temp.same('New York: and the next day it is 02:30 again',
  pg_temp.nxt('daily', null, '02:30', 'America/New_York', '2030-03-10 03:30'), '2030-03-11 02:30');
select pg_temp.same('New York: a time in the repeated hour is sent once, at the second 01:30',
  to_char(public.recurrence_next('daily', null, '01:30', 'America/New_York', '2030-11-02 12:00+00') at time zone 'UTC', 'YYYY-MM-DD HH24:MI'),
  '2030-11-03 06:30');
select pg_temp.same('New York: after that, the next day',
  to_char(public.recurrence_next('daily', null, '01:30', 'America/New_York', '2030-11-03 06:30:01+00') at time zone 'UTC', 'YYYY-MM-DD HH24:MI'),
  '2030-11-04 06:30');
select pg_temp.same('Berlin: 02:30 on the night the clocks go forward becomes 03:30',
  pg_temp.nxt('daily', null, '02:30', 'Europe/Berlin', '2030-03-30 02:30'), '2030-03-31 03:30');
select pg_temp.same('Berlin: and is a single send on the night they go back',
  to_char(public.recurrence_next('daily', null, '02:30', 'Europe/Berlin', '2030-10-26 12:00+00') at time zone 'UTC', 'YYYY-MM-DD HH24:MI'),
  '2030-10-27 01:30');
select pg_temp.same('Berlin: and the next one is the next day',
  to_char(public.recurrence_next('daily', null, '02:30', 'Europe/Berlin', '2030-10-27 01:30:01+00') at time zone 'UTC', 'YYYY-MM-DD HH24:MI'),
  '2030-10-28 01:30');
select pg_temp.same('Southern hemisphere: Sydney''s clocks go back in April',
  pg_temp.wall(public.recurrence_next('daily', null, '09:00', 'Australia/Sydney', '2030-04-06 08:00+00'), 'Australia/Sydney'),
  '2030-04-07 09:00');

select pg_temp.same('an unknown zone counts as UTC',
  to_char(public.recurrence_next('daily', null, '09:00', 'Mars/Olympus', '2030-05-06 00:00+00') at time zone 'UTC', 'YYYY-MM-DD HH24:MI'),
  '2030-05-06 09:00');
select pg_temp.check('an unknown kind or a missing time is nobody''s rule',
  public.recurrence_next('hourly', null, '09:00', 'UTC', now()) is null
  and public.recurrence_next('daily', null, null, 'UTC', now()) is null
  and public.recurrence_next('weekly', null, '09:00', 'UTC', now()) is null);
select pg_temp.check('the rule is a pure function: signed-in people may call it, signed-out ones may not',
  has_function_privilege('authenticated', 'public.recurrence_next(text, integer, time, text, timestamptz, date)', 'execute')
  and not has_function_privilege('anon', 'public.recurrence_next(text, integer, time, text, timestamptz, date)', 'execute'));

-- ============================================================== the guard

-- The next local date after today (in [zone]) that falls on ISO weekday [dow],
-- at [at_time], as an instant: always in the future.
create function pg_temp.next_dow(zone text, dow integer, at_time time) returns timestamptz
language sql stable as $$
  select ((d + at_time) at time zone zone)
  from (
    select ((now() at time zone zone)::date + g) as d
    from generate_series(2, 9) g
  ) x
  where extract(isodow from d)::integer = dow
  order by d limit 1;
$$;
grant execute on function pg_temp.next_dow(text, integer, time) to public;

-- The next date (a month or more ahead) with this day of the month.
create function pg_temp.next_dom(zone text, dom integer, at_time time) returns timestamptz
language sql stable as $$
  select ((d + at_time) at time zone zone)
  from (
    select ((now() at time zone zone)::date + g) as d
    from generate_series(2, 200) g
  ) x
  where extract(day from d)::integer = dom
  order by d limit 1;
$$;
grant execute on function pg_temp.next_dom(text, integer, time) to public;

create function pg_temp.sched(who text, chat text, at timestamptz, extra text default '')
returns uuid language plpgsql as $$
declare
  new_id uuid;
begin
  perform pg_temp.act_as(who);
  execute format(
    'insert into public.scheduled_messages (owner_id, conversation_id, body, send_at%s) values (%L, %L, %L, %L%s) returning id',
    case when extra = '' then '' else ', ' || split_part(extra, '|', 1) end,
    pg_temp.u(who), pg_temp.mid(chat), 'Weekly report', at,
    case when extra = '' then '' else ', ' || split_part(extra, '|', 2) end
  ) into new_id;
  perform pg_temp.act_as(null);
  return new_id;
exception when others then
  perform pg_temp.act_as(null);
  raise;
end;
$$;
grant execute on function pg_temp.sched(text, text, timestamptz, text) to public;

-- A plain message is unchanged.
insert into ids select 'once', pg_temp.sched('a', 'ops', now() + interval '2 days');
select pg_temp.check('a message without a repeat has no rule',
  (select recurrence is null and recurrence_day is null and recurrence_time is null
     and recurrence_tz is null and recurrence_until is null
   from public.scheduled_messages where id = pg_temp.mid('once')));

-- Weekly: the rule takes the weekday and time of the first send.
insert into ids select 'weekly', pg_temp.sched('a', 'ops',
  pg_temp.next_dow('Asia/Shanghai', 1, '09:00'),
  $x$recurrence, recurrence_tz|'weekly', 'Asia/Shanghai'$x$);
select pg_temp.check('weekly on a Monday at 9:00 in Shanghai',
  (select recurrence = 'weekly' and recurrence_day = 1 and recurrence_time = '09:00'
     and recurrence_tz = 'Asia/Shanghai' and status = 'pending'
   from public.scheduled_messages where id = pg_temp.mid('weekly')));

insert into ids select 'daily', pg_temp.sched('a', 'ops',
  now() + interval '1 day', $x$recurrence, recurrence_tz|'daily', 'America/New_York'$x$);
select pg_temp.check('daily has no day',
  (select recurrence_day is null and recurrence_time is not null and recurrence_tz = 'America/New_York'
   from public.scheduled_messages where id = pg_temp.mid('daily')));
select pg_temp.check('the time of day is the first send''s wall clock, to the minute',
  (select recurrence_time = date_trunc('minute', send_at at time zone 'America/New_York')::time
     and extract(second from recurrence_time) = 0
   from public.scheduled_messages where id = pg_temp.mid('daily')));

insert into ids select 'monthly', pg_temp.sched('a', 'ops',
  pg_temp.next_dom('Asia/Shanghai', 31, '08:15'),
  $x$recurrence, recurrence_tz|'monthly', 'Asia/Shanghai'$x$);
select pg_temp.check('monthly takes the day of the month: the 31st',
  (select recurrence = 'monthly' and recurrence_day = 31 and recurrence_time = '08:15'
   from public.scheduled_messages where id = pg_temp.mid('monthly')));

-- Weekdays set for a weekend goes out on the Monday.
insert into ids select 'weekdays', pg_temp.sched('a', 'ops',
  pg_temp.next_dow('UTC', 6, '10:00'),
  $x$recurrence, recurrence_tz|'weekdays', 'UTC'$x$);
select pg_temp.check('a weekdays message first set for Saturday goes out on Monday',
  (select extract(isodow from send_at at time zone 'UTC') = 1 and recurrence_time = '10:00'
   from public.scheduled_messages where id = pg_temp.mid('weekdays')));

-- No zone from the app: the person's notification zone, else UTC.
select pg_temp.act_as('a');
update public.scheduled_messages set recurrence = 'daily', recurrence_tz = null
where id = pg_temp.mid('once');
select pg_temp.act_as(null);
select pg_temp.check('without a zone, UTC',
  (select recurrence_tz = 'UTC' from public.scheduled_messages where id = pg_temp.mid('once')));
select pg_temp.act_as('a');
update public.scheduled_messages set recurrence = null where id = pg_temp.mid('once');
update public.scheduled_messages set recurrence = 'daily', recurrence_tz = 'Mars/Olympus'
where id = pg_temp.mid('once');
select pg_temp.act_as(null);
select pg_temp.check('an unknown zone name also falls back',
  (select recurrence_tz = 'UTC' from public.scheduled_messages where id = pg_temp.mid('once')));
insert into public.user_notification_settings (user_id, timezone) values (pg_temp.u('a'), 'Europe/Paris')
on conflict (user_id) do update set timezone = 'Europe/Paris';
select pg_temp.act_as('a');
update public.scheduled_messages set recurrence = 'daily', recurrence_tz = null
where id = pg_temp.mid('once');
select pg_temp.act_as(null);
select pg_temp.check('with a notification zone, that zone',
  (select recurrence_tz = 'Europe/Paris' from public.scheduled_messages where id = pg_temp.mid('once')));

-- Stopping the repeat clears the rule.
select pg_temp.act_as('a');
update public.scheduled_messages set recurrence = null, recurrence_until = null where id = pg_temp.mid('once');
select pg_temp.act_as(null);
select pg_temp.check('clearing the repeat clears everything with it',
  (select recurrence is null and recurrence_day is null and recurrence_time is null and recurrence_tz is null
   from public.scheduled_messages where id = pg_temp.mid('once')));

-- What the client can not do.
select pg_temp.act_as('a');
select pg_temp.refused('an unknown repeat is refused',
  format($s$update public.scheduled_messages set recurrence = 'hourly' where id = %L$s$, pg_temp.mid('once')), '22023');
select pg_temp.refused('an end before the first send is refused',
  format($s$update public.scheduled_messages set recurrence = 'daily', recurrence_until = current_date - 3 where id = %L$s$, pg_temp.mid('once')), '22023');
select pg_temp.refused('an end more than two years away is refused',
  format($s$update public.scheduled_messages set recurrence = 'daily', recurrence_until = current_date + 900 where id = %L$s$, pg_temp.mid('once')), '22023');
select pg_temp.refused('the parent link is read only',
  format('update public.scheduled_messages set recurrence_parent_id = %L where id = %L', pg_temp.mid('weekly'), pg_temp.mid('once')), '42501');
select pg_temp.refused('a client can not make itself a sent message',
  format($s$update public.scheduled_messages set sent_at = now() where id = %L$s$, pg_temp.mid('once')), '42501');
select pg_temp.act_as(null);

-- Another person's messages are not theirs to touch.
select pg_temp.act_as('b');
select pg_temp.check('Bo sees none of Ada''s scheduled messages',
  (select count(*) from public.scheduled_messages) = 0);
select pg_temp.act_as(null);

-- An end date that fits keeps; the first send on the end date is fine.
select pg_temp.act_as('a');
update public.scheduled_messages
set recurrence = 'daily', recurrence_tz = 'UTC', recurrence_until = (send_at at time zone 'UTC')::date
where id = pg_temp.mid('once');
select pg_temp.act_as(null);
select pg_temp.check('an end on the day of the first send is allowed',
  (select recurrence_until = (send_at at time zone 'UTC')::date from public.scheduled_messages where id = pg_temp.mid('once')));
delete from public.scheduled_messages where id = pg_temp.mid('once');

-- At most 20 repeating messages wait at once.
insert into public.scheduled_messages (owner_id, conversation_id, body, send_at,
  recurrence, recurrence_day, recurrence_time, recurrence_tz)
select pg_temp.u('b'), pg_temp.mid('ops'), 'r' || g, now() + interval '3 days',
  'daily', null, '09:00', 'UTC'
from generate_series(1, 20) g;
select pg_temp.act_as('b');
select pg_temp.refused('a 21st repeating message is refused',
  format($s$insert into public.scheduled_messages (owner_id, conversation_id, body, send_at, recurrence)
            values (%L, %L, 'one more', now() + interval '3 days', 'daily')$s$, pg_temp.u('b'), pg_temp.mid('ops')),
  '53400');
insert into public.scheduled_messages (owner_id, conversation_id, body, send_at)
values (pg_temp.u('b'), pg_temp.mid('ops'), 'a plain one', now() + interval '3 days');
select pg_temp.check('while a plain one still goes',
  (select count(*) from public.scheduled_messages where body = 'a plain one') = 1);
select pg_temp.act_as(null);
delete from public.scheduled_messages where owner_id = pg_temp.u('b');

-- ===================================================== sending, then the next

-- A due repeating message: put in as the owner, then made due by the server
-- (the guard keeps clients from scheduling in the past).
create function pg_temp.make_due(msg text, ago interval default interval '1 minute') returns void
language sql as $$
  update public.scheduled_messages set send_at = now() - ago where id = pg_temp.mid(msg);
$$;
grant execute on function pg_temp.make_due(text, interval) to public;

create function pg_temp.sent_count(msg text) returns integer language sql as $$
  select count(*)::integer from public.messages where sender_id = (
    select owner_id from public.scheduled_messages where id = pg_temp.mid(msg)
  ) and client_id = pg_temp.mid(msg);
$$;
grant execute on function pg_temp.sent_count(text) to public;

create function pg_temp.children(msg text) returns integer language sql as $$
  select count(*)::integer from public.scheduled_messages where recurrence_parent_id = pg_temp.mid(msg);
$$;
grant execute on function pg_temp.children(text) to public;

-- Daily at 09:00 UTC, first due now.
insert into ids select 'd1', pg_temp.sched('a', 'ops', now() + interval '1 day',
  $x$recurrence, recurrence_tz, mentions|'daily', 'UTC', '[{"kind":"user","user_id":"00000000-0000-4000-8000-0000000000b1","display_name":"Bo","start":0,"end":3}]'$x$);
select pg_temp.make_due('d1');
select pg_temp.check('dispatch sends the due message', public.dispatch_due_scheduled_messages() = 1);
select pg_temp.check('exactly one message was sent, as the owner, with the row''s id as client id',
  pg_temp.sent_count('d1') = 1);
select pg_temp.check('the row is sent and has exactly one next send',
  (select status = 'sent' from public.scheduled_messages where id = pg_temp.mid('d1'))
  and pg_temp.children('d1') = 1);
select pg_temp.check('the next send keeps the text, mentions and rule',
  (select c.status = 'pending' and c.body = p.body and c.mentions = p.mentions
     and c.recurrence = 'daily' and c.recurrence_tz = 'UTC' and c.recurrence_time = p.recurrence_time
     and c.owner_id = p.owner_id and c.conversation_id = p.conversation_id and c.attempts = 0
     and c.id <> p.id and c.sent_message_id is null
   from public.scheduled_messages p
   join public.scheduled_messages c on c.recurrence_parent_id = p.id
   where p.id = pg_temp.mid('d1')));
select pg_temp.check('and is on the next 9:00-ish moment after now, within a day',
  (select c.send_at > now() and c.send_at <= now() + interval '1 day' + interval '1 minute'
     and (c.send_at at time zone 'UTC')::time = p.recurrence_time
   from public.scheduled_messages p
   join public.scheduled_messages c on c.recurrence_parent_id = p.id
   where p.id = pg_temp.mid('d1')));
select pg_temp.check('another dispatch sends nothing more', public.dispatch_due_scheduled_messages() = 0);
select pg_temp.check('and does not make a second next send', pg_temp.children('d1') = 1);

-- A retry after a crash: the message went out but the row still says pending.
update public.scheduled_messages set status = 'pending', sent_message_id = null, sent_at = null where id = pg_temp.mid('d1');
select pg_temp.check('retrying a row whose message was already sent sends nothing new',
  public.deliver_scheduled_message(pg_temp.mid('d1')) is not null and pg_temp.sent_count('d1') = 1);
select pg_temp.check('and does not make a second next send either', pg_temp.children('d1') = 1);
select pg_temp.check('the row is sent again, pointing at the one message',
  (select status = 'sent' and sent_message_id = (
     select id from public.messages where client_id = pg_temp.mid('d1')) from public.scheduled_messages
   where id = pg_temp.mid('d1')));
select pg_temp.check('a sent row is not sent again',
  public.deliver_scheduled_message(pg_temp.mid('d1')) is null and pg_temp.sent_count('d1') = 1);

-- The same, when the message was stored by an earlier try that the row never
-- heard of (the real crash case): the row is pending, the message exists.
insert into ids select 'd2', pg_temp.sched('a', 'ops', now() + interval '1 day',
  $x$recurrence, recurrence_tz|'daily', 'UTC'$x$);
select pg_temp.act_as('a');
select public.send_text_message(pg_temp.mid('ops'), 'Weekly report', null, null, '[]'::jsonb, pg_temp.mid('d2')) as earlier \gset
select pg_temp.act_as(null);
select pg_temp.make_due('d2');
select pg_temp.check('delivery finds the stored message and does not send a second',
  public.deliver_scheduled_message(pg_temp.mid('d2')) = :'earlier'::uuid and pg_temp.sent_count('d2') = 1);
select pg_temp.check('the series goes on: one next send', pg_temp.children('d2') = 1);

-- A late send: the missed days are not sent one after another.
insert into ids select 'late', pg_temp.sched('a', 'ops', now() + interval '1 day',
  $x$recurrence, recurrence_tz|'daily', 'UTC'$x$);
select pg_temp.make_due('late', interval '3 days 5 minutes');
select pg_temp.check('a send three days late goes out once', public.dispatch_due_scheduled_messages() = 1);
select pg_temp.check('and the next one is the first on the rule after now, not three days ago plus one',
  (select c.send_at > now() from public.scheduled_messages c where c.recurrence_parent_id = pg_temp.mid('late')));
-- Clear the queue of the sends made so far.
delete from public.scheduled_messages where status = 'pending';

-- The end date: no next send past it.
insert into ids select 'end', pg_temp.sched('a', 'ops', now() + interval '1 day',
  $x$recurrence, recurrence_tz, recurrence_until|'daily', 'UTC', (now() at time zone 'UTC')::date + 1$x$);
select pg_temp.make_due('end');
select pg_temp.check('the last day is sent', public.dispatch_due_scheduled_messages() = 1);
select pg_temp.check('and the next one is on the end date or earlier',
  (select c.send_at < ((now() at time zone 'UTC')::date + 2)::timestamp at time zone 'UTC'
   from public.scheduled_messages c where c.recurrence_parent_id = pg_temp.mid('end')));
select pg_temp.check('and after that one, nothing follows: the rule has no day left before the end',
  (select public.recurrence_next(c.recurrence, c.recurrence_day, c.recurrence_time, c.recurrence_tz,
                                 c.send_at, c.recurrence_until) is null
   from public.scheduled_messages c where c.recurrence_parent_id = pg_temp.mid('end')));
delete from public.scheduled_messages where status = 'pending';
insert into ids select 'end0', pg_temp.sched('a', 'ops', now() + interval '1 day',
  $x$recurrence, recurrence_tz, recurrence_until|'daily', 'UTC', (now() at time zone 'UTC')::date + 1$x$);
update public.scheduled_messages set recurrence_until = (now() at time zone 'UTC')::date - 1 where id = pg_temp.mid('end0');
select pg_temp.make_due('end0');
select pg_temp.check('with the end date already past, the last send is the last',
  public.dispatch_due_scheduled_messages() = 1 and pg_temp.children('end0') = 0);

-- A failed send still goes on: Cy blocked Ada, so the direct chat refuses.
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.u('c'), pg_temp.u('a'));
insert into ids select 'fail', pg_temp.sched('a', 'dm', now() + interval '1 day',
  $x$recurrence, recurrence_tz|'daily', 'UTC'$x$);
select pg_temp.make_due('fail');
select pg_temp.check('a send that cannot be made is not delivered', public.dispatch_due_scheduled_messages() = 0);
select pg_temp.check('it is marked failed, with the reason',
  (select status = 'failed' and last_error is not null from public.scheduled_messages where id = pg_temp.mid('fail')));
select pg_temp.check('nothing was sent', pg_temp.sent_count('fail') = 0);
select pg_temp.check('and the series goes on: the next send waits',
  pg_temp.children('fail') = 1
  and (select status = 'pending' from public.scheduled_messages where recurrence_parent_id = pg_temp.mid('fail')));
delete from public.blocks;
-- Trying a failed one again does not double the next send.
select pg_temp.act_as('a');
select pg_temp.check('trying again after the block is gone sends it',
  public.send_scheduled_message_now(pg_temp.mid('fail')) is not null);
select pg_temp.act_as(null);
select pg_temp.check('and there is still one next send', pg_temp.children('fail') = 1);
delete from public.scheduled_messages where status = 'pending';

-- Someone who left the group: the failed send ends the series.
insert into ids select 'left', pg_temp.sched('a', 'ops', now() + interval '1 day',
  $x$recurrence, recurrence_tz|'daily', 'UTC'$x$);
delete from public.conversation_members where conversation_id = pg_temp.mid('ops') and user_id = pg_temp.u('a');
select pg_temp.make_due('left');
select pg_temp.check('a member who left can not send', public.dispatch_due_scheduled_messages() = 0);
select pg_temp.check('the send failed and no next send was made',
  (select status = 'failed' from public.scheduled_messages where id = pg_temp.mid('left'))
  and pg_temp.children('left') = 0);
insert into public.conversation_members (conversation_id, user_id, role)
values (pg_temp.mid('ops'), pg_temp.u('a'), 'owner');

-- "Send now" on a repeating message: sent now, the series goes on after.
insert into ids select 'now', pg_temp.sched('a', 'ops', now() + interval '2 days',
  $x$recurrence, recurrence_tz|'daily', 'UTC'$x$);
select pg_temp.act_as('a');
select pg_temp.check('send now sends it', public.send_scheduled_message_now(pg_temp.mid('now')) is not null);
select pg_temp.act_as(null);
select pg_temp.check('the next send is after the occurrence it replaced (it was two days away)',
  (select c.send_at > now() + interval '2 days' from public.scheduled_messages c
   where c.recurrence_parent_id = pg_temp.mid('now')));
delete from public.scheduled_messages where status = 'pending';

-- Deleting the next send stops the series, and nothing brings it back.
insert into ids select 'stop', pg_temp.sched('a', 'ops', now() + interval '1 day',
  $x$recurrence, recurrence_tz|'daily', 'UTC'$x$);
select pg_temp.make_due('stop');
select public.dispatch_due_scheduled_messages();
select pg_temp.act_as('a');
delete from public.scheduled_messages where status = 'pending';
select pg_temp.act_as(null);
select pg_temp.check('with the next send deleted, dispatch finds nothing and makes nothing',
  public.dispatch_due_scheduled_messages() = 0
  and pg_temp.n('select 1 from public.scheduled_messages where status = ''pending''') = 0);

-- Editing a repeating message to a one-off: it sends once and ends.
insert into ids select 'oneoff', pg_temp.sched('a', 'ops', now() + interval '1 day',
  $x$recurrence, recurrence_tz|'daily', 'UTC'$x$);
select pg_temp.act_as('a');
update public.scheduled_messages set recurrence = null where id = pg_temp.mid('oneoff');
select pg_temp.act_as(null);
select pg_temp.make_due('oneoff');
select public.dispatch_due_scheduled_messages();
select pg_temp.check('a message turned into a one-off leaves no next send',
  pg_temp.children('oneoff') = 0 and pg_temp.sent_count('oneoff') = 1);

-- ----------------------------------------- the chain, across months and clocks
-- Rows made by the server (the guard is for clients): a message on the 31st at
-- 10:00 in 2090, sent, then each next one sent in turn.
create function pg_temp.chain(zone text, kind text, day integer, at_time time, first_local timestamp, steps integer)
returns text language plpgsql as $$
declare
  current_id uuid;
  next_id uuid;
  trail text := '';
  i integer;
  s timestamptz;
begin
  insert into public.scheduled_messages (owner_id, conversation_id, body, send_at, recurrence, recurrence_day, recurrence_time, recurrence_tz)
  values (pg_temp.u('a'), pg_temp.mid('ops'), 'chain', first_local at time zone zone, kind, day, at_time, zone)
  returning id into current_id;
  for i in 1..steps loop
    update public.scheduled_messages set status = 'sent', sent_at = send_at, sent_message_id = null where id = current_id;
    select c.id, c.send_at into next_id, s from public.scheduled_messages c where c.recurrence_parent_id = current_id;
    exit when next_id is null;
    trail := trail || case when trail = '' then '' else ' > ' end || pg_temp.wall(s, zone);
    current_id := next_id;
  end loop;
  return trail;
end;
$$;
grant execute on function pg_temp.chain(text, text, integer, time, timestamp, integer) to public;

select pg_temp.same('a monthly 31st: Jan 31, Feb 28, Mar 31, Apr 30, May 31 (2090)',
  pg_temp.chain('Asia/Shanghai', 'monthly', 31, '10:00', '2090-01-31 10:00', 4),
  '2090-02-28 10:00 > 2090-03-31 10:00 > 2090-04-30 10:00 > 2090-05-31 10:00');
select pg_temp.same('a monthly 30th passes February on the 28th and is back on the 30th',
  pg_temp.chain('UTC', 'monthly', 30, '07:00', '2090-01-30 07:00', 3),
  '2090-02-28 07:00 > 2090-03-30 07:00 > 2090-04-30 07:00');
select pg_temp.same('a daily 02:30 in New York over the change: 02:30, 03:30 on the day, 02:30 again',
  pg_temp.chain('America/New_York', 'daily', null, '02:30', '2030-03-09 02:30', 3),
  '2030-03-10 03:30 > 2030-03-11 02:30 > 2030-03-12 02:30');
select pg_temp.same('a weekly Monday 9:00 in New York keeps 9:00 over both changes',
  pg_temp.chain('America/New_York', 'weekly', 1, '09:00', '2030-03-04 09:00', 3),
  '2030-03-11 09:00 > 2030-03-18 09:00 > 2030-03-25 09:00');
select pg_temp.same('and back in autumn',
  pg_temp.chain('America/New_York', 'weekly', 1, '09:00', '2030-10-28 09:00', 2),
  '2030-11-04 09:00 > 2030-11-11 09:00');
select pg_temp.same('a weekday series skips the weekend',
  pg_temp.chain('Europe/Berlin', 'weekdays', null, '08:30', '2030-05-09 08:30', 3),
  '2030-05-10 08:30 > 2030-05-13 08:30 > 2030-05-14 08:30');
select pg_temp.same('a weekly series Sunday 18:00 in Sydney across their autumn change',
  pg_temp.chain('Australia/Sydney', 'weekly', 7, '18:00', '2030-03-31 18:00', 3),
  '2030-04-07 18:00 > 2030-04-14 18:00 > 2030-04-21 18:00');
delete from public.scheduled_messages where body = 'chain';

-- ------------------------------------------------- the agenda and clean-up
insert into ids select 'ag', pg_temp.sched('a', 'ops', now() + interval '1 day',
  $x$recurrence, recurrence_tz|'weekly', 'UTC'$x$);
select pg_temp.make_due('ag');
select public.dispatch_due_scheduled_messages();
select pg_temp.act_as('a');
select pg_temp.check('the next send of a repeating message is in My agenda, once',
  (select count(*) from public.get_my_agenda(now(), now() + interval '9 days')
   where kind = 'scheduled_message' and title = 'Weekly report') = 1);
select pg_temp.act_as(null);

-- Sent rows are pruned after three days; the next send does not mind.
update public.scheduled_messages set sent_at = now() - interval '4 days'
where id = pg_temp.mid('ag');
select public.dispatch_due_scheduled_messages();
select pg_temp.check('the old sent row is gone',
  not exists (select 1 from public.scheduled_messages where id = pg_temp.mid('ag')));
select pg_temp.check('the next send stays, its parent link cleared',
  (select count(*) from public.scheduled_messages where status = 'pending' and recurrence = 'weekly'
     and recurrence_parent_id is null) = 1);

-- The conversation going away takes the series with it.
delete from public.conversations where id = pg_temp.mid('ops');
select pg_temp.check('deleting the conversation removes its scheduled messages',
  pg_temp.n('select 1 from public.scheduled_messages where conversation_id = ' || quote_literal(pg_temp.mid('ops'))) = 0);

rollback;
