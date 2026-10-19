-- Behaviour checks for moderator tools 2.0 and raid protection (C5, C6:
-- migrations 202610250200 to 202610250280). Run by
-- test/supabase/mod_tools_test.dart against the local database: it applies
-- the migrations it needs in a transaction, plays people through the RPCs,
-- and rolls everything back. Run from the repository root.
--
-- What it walks through:
--   1. bans with an end: durations, who may ban, rank, the owner, the sweep,
--      the lazy lift on the join guard, the take-down check;
--   2. locking a thread: who may lock, who may still post, system notices,
--      the audit log;
--   3. moderator notes and warnings: permission, rank, privacy, deleting;
--   4. ban appeals: one per ban, who decides, the banner's rank rule, closing
--      when a ban is lifted, the push;
--   5. the member filter and batch actions: filters, what the caller may do
--      to each row, 50 at a time, refusals that do not stop the others;
--   6. raid protection: pausing invites on every invite path, the automatic
--      lockdown (members and requests, new accounts, thresholds, the young
--      circle and the off switch), the join mode being put back or left to
--      whoever changed it, the newcomers' links, the AI guard, C1 approvals
--      and the pushes.
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
\i supabase/migrations/202610240600_feature_flags.sql
\i supabase/migrations/202610240610_feature_flags_admin.sql
\i supabase/migrations/202610240620_announcements.sql
\i supabase/migrations/202610240630_announcements_admin.sql
\i supabase/migrations/202610240640_user_feedback.sql
\i supabase/migrations/202610240650_feedback_admin.sql
\i supabase/migrations/202610240660_export_my_feedback.sql
\i supabase/migrations/202610250200_ban_expiry.sql
\i supabase/migrations/202610250210_thread_lock.sql
\i supabase/migrations/202610250220_mod_notes.sql
\i supabase/migrations/202610250230_ban_appeals.sql
\i supabase/migrations/202610250240_member_filter_batch.sql
\i supabase/migrations/202610250250_raid_schema.sql
\i supabase/migrations/202610250260_raid_detect.sql
\i supabase/migrations/202610250270_raid_rpcs.sql
\i supabase/migrations/202610250280_moderation_push.sql
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

-- Whether [who] is a member of the circle [c].
create function pg_temp.is_member(c uuid, who uuid) returns boolean language sql as $$
  select exists (select 1 from public.circle_members cm where cm.circle_id = c and cm.user_id = who)
$$;
create function pg_temp.in_channel(c uuid, who uuid) returns boolean language sql as $$
  select exists (
    select 1 from public.conversation_members m
    join public.circle_channels cc on cc.conversation_id = m.conversation_id
    where cc.circle_id = c and m.user_id = who)
$$;
create function pg_temp.pending(c uuid, who uuid) returns integer language sql as $$
  select count(*)::integer from public.circle_join_requests r
  where r.circle_id = c and r.user_id = who and r.status = 'pending'
$$;
grant execute on all functions in schema pg_temp to public;


-- ------------------------------------------------------------------ cast
-- Ada owns the circle. Senior (sam) and Mod (mia) hold kick, ban, timeout and
-- manage-messages; Senior ranks above Mod. Kicker (kim) only holds kick_members.
-- Bob, cy, dee and hal are ordinary members; eve, fay and gus are outside.
-- The raiders (r01 ... r40) are outside too.
create function pg_temp.uid(n text) returns uuid language sql immutable as $$
  select md5('modtools:' || n)::uuid
$$;
grant execute on function pg_temp.uid(text) to public;

insert into auth.users (id, email, instance_id, aud, role)
select pg_temp.uid(n), n || '@mt.test', '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from unnest(array['ada','mia','sam','kim','bob','cy','dee','eve','fay','gus','hal','ivy']) n
union all
select pg_temp.uid('r' || lpad(g::text, 2, '0')), 'r' || g || '@mt.test', '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from generate_series(1, 40) g;
insert into public.profiles (id, username, display_name)
select pg_temp.uid(n), n || '_mt', initcap(n)
from unnest(array['ada','mia','sam','kim','bob','cy','dee','eve','fay','gus','hal','ivy']) n
union all
select pg_temp.uid('r' || lpad(g::text, 2, '0')), 'r' || lpad(g::text, 2, '0') || '_mt', 'Raider ' || g
from generate_series(1, 40) g;
insert into pg_temp.ids
select n, pg_temp.uid(n)
from unnest(array['ada','mia','sam','kim','bob','cy','dee','eve','fay','gus','hal','ivy']) n
union all
select 'r' || lpad(g::text, 2, '0'), pg_temp.uid('r' || lpad(g::text, 2, '0'))
from generate_series(1, 40) g;

-- Everyone who will matter is a friend of Ada (member invites need that) or
-- Bob.
insert into public.friendships (user_low_id, user_high_id)
select least(x.a, x.b), greatest(x.a, x.b)
from (values
  (pg_temp.i('ada'), pg_temp.i('bob')), (pg_temp.i('ada'), pg_temp.i('mia')),
  (pg_temp.i('ada'), pg_temp.i('sam')), (pg_temp.i('ada'), pg_temp.i('kim')),
  (pg_temp.i('ada'), pg_temp.i('cy')), (pg_temp.i('ada'), pg_temp.i('dee')),
  (pg_temp.i('ada'), pg_temp.i('hal')), (pg_temp.i('ada'), pg_temp.i('ivy')),
  (pg_temp.i('bob'), pg_temp.i('gus'))
) x(a, b);

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'circle', public.create_circle('Mod club',
  array[pg_temp.i('bob'), pg_temp.i('mia'), pg_temp.i('sam'), pg_temp.i('kim'),
        pg_temp.i('cy'), pg_temp.i('dee'), pg_temp.i('hal')]);
select public.set_circle_discovery(pg_temp.i('circle'), true, 'about the club', 'other', 'en', '{}'::text[]);
-- Created last, so it ranks lowest: Senior > Mod > Kicker.
insert into pg_temp.ids select 'senior', public.create_circle_role(pg_temp.i('circle'), 'Senior', null, 98340, false);
insert into pg_temp.ids select 'mod', public.create_circle_role(pg_temp.i('circle'), 'Mod', null, 98340, false);
insert into pg_temp.ids select 'kicker', public.create_circle_role(pg_temp.i('circle'), 'Kicker', null, 32, false);
select public.set_member_roles(pg_temp.i('circle'), pg_temp.i('sam'), array[pg_temp.i('senior')]);
select public.set_member_roles(pg_temp.i('circle'), pg_temp.i('mia'), array[pg_temp.i('mod')]);
select public.set_member_roles(pg_temp.i('circle'), pg_temp.i('kim'), array[pg_temp.i('kicker')]);
select pg_temp.root();

-- The circle is two days old, its members joined two days ago, so a burst of
-- newcomers stands out. A channel and a thread to lock.
update public.circles set created_at = now() - interval '2 days' where id = pg_temp.i('circle');
update public.circle_members set created_at = now() - interval '2 days' where circle_id = pg_temp.i('circle');
insert into pg_temp.ids select 'channel', (select conversation_id from public.circle_channels where circle_id = pg_temp.i('circle') order by position limit 1);
insert into pg_temp.ids select 'channel_id', (select id from public.circle_channels where circle_id = pg_temp.i('circle') order by position limit 1);
select pg_temp.act(pg_temp.i('bob'));
insert into pg_temp.ids select 'thread', (public.create_thread(pg_temp.i('channel'), null, 'Plans')->>'id')::uuid;
select pg_temp.root();
insert into pg_temp.ids select 'thread_conv', conversation_id from public.conversation_threads where id = pg_temp.i('thread');

create function pg_temp.audit_count(c uuid, act text) returns integer language sql as $$
  select count(*)::integer from public.circle_audit_log where circle_id = c and action = act
$$;
grant execute on all functions in schema pg_temp to public;

-- ===================================== 1. bans that end
do $$
declare
  c uuid := pg_temp.i('circle');
  until_at timestamptz;
begin
  -- Who may ban at all.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select * from public.ban_circle_member(%L, %L, null, 0, 3600)', c, pg_temp.i('cy'))) = '42501', 'ban: a member cannot');
  perform pg_temp.act(pg_temp.i('kim'));
  perform pg_temp.expect(pg_temp.state(format('select * from public.ban_circle_member(%L, %L, null, 0, 3600)', c, pg_temp.i('cy'))) = '42501', 'ban: a kicker without ban_members cannot');
  perform pg_temp.act(null);
  perform pg_temp.must_refuse(format('select * from public.ban_circle_member(%L, %L, null, 0, 3600)', c, pg_temp.i('cy')), 'ban: nobody signed in cannot');

  perform pg_temp.act(pg_temp.i('mia'));
  -- Rank, the owner, yourself, and a silly duration.
  perform pg_temp.expect(pg_temp.state(format('select * from public.ban_circle_member(%L, %L, null, 0, 3600)', c, pg_temp.i('sam'))) = '42501', 'ban: not someone ranked above');
  perform pg_temp.expect(pg_temp.state(format('select * from public.ban_circle_member(%L, %L, null, 0, 3600)', c, pg_temp.i('ada'))) = '42501', 'ban: not the owner');
  perform pg_temp.expect(pg_temp.state(format('select * from public.ban_circle_member(%L, %L, null, 0, 3600)', c, pg_temp.i('mia'))) = '22023', 'ban: not yourself');
  perform pg_temp.expect(pg_temp.state(format('select * from public.ban_circle_member(%L, %L, null, 0, 30)', c, pg_temp.i('cy'))) = '22023', 'ban: under a minute is refused');
  perform pg_temp.expect(pg_temp.state(format('select * from public.ban_circle_member(%L, %L, null, 0, 99999999)', c, pg_temp.i('cy'))) = '22023', 'ban: over a year is refused');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.circle_bans') = 0, 'ban: refused calls banned nobody');

  -- A one hour ban removes the member and ends on its own.
  perform public.ban_circle_member(c, pg_temp.i('cy'), 'spam', 0, 3600);
  perform pg_temp.root();
  select b.expires_at into until_at from public.circle_bans b where b.circle_id = c and b.user_id = pg_temp.i('cy');
  perform pg_temp.expect(until_at between now() + interval '59 minutes' and now() + interval '61 minutes', 'ban: it ends in an hour');
  perform pg_temp.expect(not pg_temp.is_member(c, pg_temp.i('cy')), 'ban: the member is out');
  perform pg_temp.expect((select (changes ->> 'until') is not null from public.circle_audit_log where circle_id = c and action = 'member_ban' order by created_at desc limit 1), 'ban: the audit entry says when it ends');

  -- The four-argument call (the report queue's) is still a permanent ban.
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.ban_circle_member(c, pg_temp.i('dee'), 'x', 0);
  perform pg_temp.root();
  perform pg_temp.expect((select expires_at is null from public.circle_bans where circle_id = c and user_id = pg_temp.i('dee')), 'ban: no duration is permanent');
  -- A person who is not a member can be banned in advance.
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.ban_circle_member(c, pg_temp.i('eve'), null, 0, 86400);
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.circle_bans where circle_id = c and user_id = pg_temp.i('eve')), 'ban: a non-member can be banned');

  -- The list shows when each ends.
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect((select count(*) from public.list_circle_bans(c)) = 3, 'list: three bans');
  perform pg_temp.expect((select expires_at is not null from public.list_circle_bans(c) where user_id = pg_temp.i('cy')), 'list: it shows the end');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select * from public.list_circle_bans(%L)', c)) = '42501', 'list: a member cannot');
  perform pg_temp.root();

end $$;

do $$
declare
  c uuid := pg_temp.i('circle');
  code text;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  code := public.create_circle_invite(c, null, null);
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(pg_temp.state(format('select public.accept_circle_invite(%L)', code)) = '42501', 'ban: a running ban keeps the person out');
  perform pg_temp.root();

  -- The ban runs out. The guard on circle_members lifts it right then.
  update public.circle_bans set created_at = now() - interval '2 hours', expires_at = now() - interval '1 minute'
  where circle_id = c and user_id = pg_temp.i('cy');
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(pg_temp.state(format('select public.accept_circle_invite(%L)', code)) = 'ok', 'ban: an ended ban no longer keeps the person out');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('cy')), 'ban: cy is back');
  perform pg_temp.expect(not exists (select 1 from public.circle_bans where circle_id = c and user_id = pg_temp.i('cy')), 'ban: and the row is gone');
  -- Leave again; tidy.
  perform pg_temp.act(pg_temp.i('cy'));
  perform public.leave_circle(c);
  perform pg_temp.root();

  -- The sweep lifts ended bans, with an audit entry nobody signed.
  update public.circle_bans set created_at = now() - interval '2 hours', expires_at = now() - interval '1 second'
  where circle_id = c and user_id = pg_temp.i('eve');
  perform public.run_circle_safety_sweep();
  perform pg_temp.expect(not exists (select 1 from public.circle_bans where circle_id = c and user_id = pg_temp.i('eve')), 'sweep: the ended ban is lifted');
  perform pg_temp.expect(exists (select 1 from public.circle_bans where circle_id = c and user_id = pg_temp.i('dee')), 'sweep: a permanent ban stays');
  perform pg_temp.expect((select actor_id is null from public.circle_audit_log where circle_id = c and action = 'member_unban_auto' limit 1), 'sweep: the audit entry has no actor');
  perform pg_temp.expect(pg_temp.audit_count(c, 'member_unban_auto') = 1, 'sweep: one audit entry');
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.state('select public.expire_circle_bans()') = '42501', 'sweep: not callable by a member');
  perform pg_temp.expect(pg_temp.state('select public.run_circle_safety_sweep()') = '42501', 'sweep: neither the whole sweep');
  perform pg_temp.root();

  -- A circle a platform admin has down refuses the new ban.
  update public.circles set disabled_at = now(), disabled_mode = 'delist' where id = c;
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.state(format('select * from public.ban_circle_member(%L, %L, null, 0, 3600)', c, pg_temp.i('hal'))) = '42501', 'ban: refused while the circle is down');
  perform pg_temp.root();
  update public.circles set disabled_at = null, disabled_mode = null where id = c;
  perform pg_temp.expect(not exists (select 1 from public.circle_bans where circle_id = c and user_id = pg_temp.i('hal')), 'ban: nothing was banned while down');
end $$;

-- ===================================== 2. locking a thread
create function pg_temp.say(conv uuid, who uuid, txt text) returns text language plpgsql as $$
begin
  return pg_temp.state(format(
    'insert into public.messages (conversation_id, sender_id, type, body) values (%L, %L, ''text'', %L)',
    conv, who, txt));
end $$;
grant execute on function pg_temp.say(uuid, uuid, text) to public;

do $$
declare
  c uuid := pg_temp.i('circle');
  t uuid := pg_temp.i('thread');
  tc uuid := pg_temp.i('thread_conv');
begin
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.say(tc, pg_temp.i('bob'), 'first') = 'ok', 'thread: members post in an open thread');
  perform pg_temp.expect((public.get_thread_lock_state(tc) ->> 'locked')::boolean = false, 'thread: not locked');
  perform pg_temp.expect((public.get_thread_lock_state(tc) ->> 'can_lock')::boolean = false, 'thread: a member cannot lock it');

  -- Who may lock: manage_messages in the channel. Not the thread's own
  -- creator, not a kicker, not an outsider, not nobody.
  perform pg_temp.expect(pg_temp.state(format('select public.set_thread_locked(%L, true)', t)) = '42501', 'thread: its creator cannot lock it');
  perform pg_temp.act(pg_temp.i('kim'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_thread_locked(%L, true)', t)) = '42501', 'thread: a kicker cannot lock it');
  perform pg_temp.act(pg_temp.i('gus'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_thread_locked(%L, true)', t)) = '42501', 'thread: an outsider cannot lock it');
  perform pg_temp.expect(public.get_thread_lock_state(tc) is null, 'thread: an outsider reads nothing about it');
  perform pg_temp.act(null);
  perform pg_temp.must_refuse(format('select public.set_thread_locked(%L, true)', t), 'thread: nobody signed in cannot lock it');
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_thread_locked(%L, true)', gen_random_uuid())) = 'P0002', 'thread: an unknown thread');
  perform pg_temp.expect((public.get_thread_lock_state(tc) ->> 'can_lock')::boolean, 'thread: a moderator is offered the lock');

  -- Down circles are left alone.
  perform pg_temp.root();
  update public.circles set disabled_at = now(), disabled_mode = 'delist' where id = c;
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_thread_locked(%L, true)', t)) = '42501', 'thread: refused while the circle is down');
  perform pg_temp.root();
  update public.circles set disabled_at = null, disabled_mode = null where id = c;

  perform pg_temp.act(pg_temp.i('mia'));
  perform public.set_thread_locked(t, true);
  perform pg_temp.root();
  perform pg_temp.expect((select locked_at is not null and locked_by = pg_temp.i('mia') from public.conversation_threads where id = t), 'thread: locked by Mia');
  perform pg_temp.expect(pg_temp.audit_count(c, 'thread_lock') = 1, 'thread: the lock is audited');

  -- Locking twice changes nothing and logs nothing more.
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.set_thread_locked(t, true);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.audit_count(c, 'thread_lock') = 1, 'thread: locking again is not logged again');

  -- Posting: members cannot, moderators can, notices pass; reading is open.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.say(tc, pg_temp.i('bob'), 'second') = '42501', 'thread: a member cannot post in a locked thread');
  perform pg_temp.expect((public.get_thread_lock_state(tc) ->> 'locked')::boolean, 'thread: they see it is locked');
  perform pg_temp.expect(not (public.get_thread_lock_state(tc) ->> 'can_post')::boolean, 'thread: and cannot post');
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.messages where conversation_id = %L', tc)) = 1, 'thread: they still read it');
  perform pg_temp.act(pg_temp.i('kim'));
  perform pg_temp.expect(pg_temp.say(tc, pg_temp.i('kim'), 'third') = '42501', 'thread: a kicker cannot post either');
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.say(tc, pg_temp.i('mia'), 'moderator note') = 'ok', 'thread: a moderator can post');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.say(tc, pg_temp.i('ada'), 'owner note') = 'ok', 'thread: the owner can post');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.state(format(
    'insert into public.messages (conversation_id, sender_id, type, body) values (%L, %L, ''system'', ''notice'')',
    tc, pg_temp.i('bob'))) = 'ok', 'thread: a system notice still passes');

  -- Unlocking.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_thread_locked(%L, false)', t)) = '42501', 'thread: a member cannot unlock');
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.set_thread_locked(t, false);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.audit_count(c, 'thread_unlock') = 1, 'thread: the unlock is audited');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.say(tc, pg_temp.i('bob'), 'after unlock') = 'ok', 'thread: members post again');
  perform pg_temp.root();
end $$;

-- ===================================== 3. moderator notes and warnings
do $$
declare
  c uuid := pg_temp.i('circle');
  note_id uuid;
  warn_id uuid;
begin
  -- Who may write: moderate_members, about members ranked below.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.add_circle_mod_note(%L, %L, ''note'', ''hi'')', c, pg_temp.i('hal'))) = '42501', 'notes: a member cannot');
  perform pg_temp.expect(pg_temp.state(format('select * from public.list_circle_mod_notes(%L, %L)', c, pg_temp.i('hal'))) = '42501', 'notes: a member cannot read');
  perform pg_temp.act(pg_temp.i('kim'));
  perform pg_temp.expect(pg_temp.state(format('select public.add_circle_mod_note(%L, %L, ''note'', ''hi'')', c, pg_temp.i('hal'))) = '42501', 'notes: a kicker without moderate_members cannot');
  perform pg_temp.act(null);
  perform pg_temp.must_refuse(format('select public.add_circle_mod_note(%L, %L, ''note'', ''hi'')', c, pg_temp.i('hal')), 'notes: nobody signed in cannot');

  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.state(format('select public.add_circle_mod_note(%L, %L, ''note'', ''hi'')', c, pg_temp.i('sam'))) = '42501', 'notes: not about someone ranked above');
  perform pg_temp.expect(pg_temp.state(format('select public.add_circle_mod_note(%L, %L, ''note'', ''hi'')', c, pg_temp.i('ada'))) = '42501', 'notes: not about the owner');
  perform pg_temp.expect(pg_temp.state(format('select public.add_circle_mod_note(%L, %L, ''note'', ''hi'')', c, pg_temp.i('mia'))) = '22023', 'notes: not about yourself');
  perform pg_temp.expect(pg_temp.state(format('select public.add_circle_mod_note(%L, %L, ''note'', ''hi'')', c, pg_temp.i('gus'))) = 'P0002', 'notes: not about an outsider');
  perform pg_temp.expect(pg_temp.state(format('select public.add_circle_mod_note(%L, %L, ''shout'', ''hi'')', c, pg_temp.i('hal'))) = '22023', 'notes: an unknown kind');
  perform pg_temp.expect(pg_temp.state(format('select public.add_circle_mod_note(%L, %L, ''note'', ''   '')', c, pg_temp.i('hal'))) = '22023', 'notes: an empty note');
  perform pg_temp.expect(pg_temp.state(format('select public.add_circle_mod_note(%L, %L, ''note'', %L)', c, pg_temp.i('hal'), repeat('x', 1001))) = '22023', 'notes: a note over 1000 characters');
  perform pg_temp.expect(pg_temp.state(format('select * from public.list_circle_mod_notes(%L, %L)', c, pg_temp.i('sam'))) = '42501', 'notes: not read about someone ranked above');

  note_id := public.add_circle_mod_note(c, pg_temp.i('hal'), 'note', 'asked to stop posting links');
  warn_id := public.add_circle_mod_note(c, pg_temp.i('hal'), 'warning', 'second link today');
  perform public.add_circle_mod_note(c, pg_temp.i('hal'), 'warning', 'third link');
  perform pg_temp.expect((select count(*) from public.list_circle_mod_notes(c, pg_temp.i('hal'))) = 3, 'notes: Mia reads the three');
  perform pg_temp.expect((select count(*) from public.list_circle_mod_notes(c, pg_temp.i('hal')) where kind = 'warning') = 2, 'notes: two are warnings');
  perform pg_temp.expect((select can_delete from public.list_circle_mod_notes(c, pg_temp.i('hal')) where id = note_id), 'notes: the author may delete');

  -- Another moderator reads them too, but cannot delete Mia's.
  perform pg_temp.act(pg_temp.i('sam'));
  perform pg_temp.expect((select count(*) from public.list_circle_mod_notes(c, pg_temp.i('hal'))) = 3, 'notes: a higher moderator reads them');
  perform pg_temp.expect(not (select can_delete from public.list_circle_mod_notes(c, pg_temp.i('hal')) where id = note_id), 'notes: but may not delete another moderator''s');
  perform pg_temp.expect(pg_temp.state(format('select public.delete_circle_mod_note(%L)', note_id)) = '42501', 'notes: deleting another''s is refused');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.delete_circle_mod_note(%L)', note_id)) = '42501', 'notes: a member cannot delete');
  perform pg_temp.root();

  -- The audit log never holds the words.
  perform pg_temp.expect(pg_temp.audit_count(c, 'mod_warn') = 2, 'notes: warnings are audited');
  perform pg_temp.expect(pg_temp.audit_count(c, 'mod_note_add') = 1, 'notes: notes are audited');
  perform pg_temp.expect(not exists (select 1 from public.circle_audit_log where circle_id = c and changes::text like '%links%'), 'notes: the audit log has no note text');
  perform pg_temp.expect((select (changes ->> 'warnings')::integer from public.circle_audit_log where circle_id = c and action = 'mod_warn' order by created_at desc limit 1) = 2, 'notes: the audit entry counts warnings');

  -- Nobody but moderators can read the table.
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.state('select * from public.circle_mod_notes') = '42501', 'notes: the table is closed to clients');
  perform pg_temp.expect(pg_temp.state(format('select public.delete_circle_mod_note(%L)', warn_id)) = 'ok', 'notes: the author deletes');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.delete_circle_mod_note(%L)', note_id)) = 'ok', 'notes: the owner (manage_circle) deletes anyone''s');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.audit_count(c, 'mod_note_delete') = 2, 'notes: deleting is audited');
  perform pg_temp.expect((select count(*) from public.circle_mod_notes where user_id = pg_temp.i('hal')) = 1, 'notes: one warning is left');

  -- A down circle takes no new notes.
  update public.circles set disabled_at = now(), disabled_mode = 'suspend' where id = c;
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.state(format('select public.add_circle_mod_note(%L, %L, ''note'', ''hi'')', c, pg_temp.i('hal'))) = '42501', 'notes: refused while the circle is down');
  perform pg_temp.root();
  update public.circles set disabled_at = null, disabled_mode = null where id = c;

  -- Leaving removes nothing, but a deleted profile takes its notes along.
  perform pg_temp.expect(exists (select 1 from information_schema.table_constraints where table_name = 'circle_mod_notes' and constraint_type = 'FOREIGN KEY'), 'notes: they hang on real members');
end $$;

-- ===================================== 4. ban appeals
do $$
declare
  c uuid := pg_temp.i('circle');
  appeal uuid;
  appeal2 uuid;
begin
  -- Eve, Fay and Gus are outside. Mia bans Eve; Sam bans Fay (above Mia).
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.ban_circle_member(c, pg_temp.i('eve'), 'rude', 0, null);
  perform pg_temp.act(pg_temp.i('sam'));
  perform public.ban_circle_member(c, pg_temp.i('fay'), 'worse', 0, null);

  -- Nobody can appeal a ban they are not under, or an empty one.
  perform pg_temp.act(pg_temp.i('gus'));
  perform pg_temp.expect(pg_temp.state(format('select public.submit_ban_appeal(%L, ''please'')', c)) = 'P0002', 'appeal: not banned, nothing to appeal');
  perform pg_temp.expect((select count(*) from public.my_circle_bans()) = 0, 'appeal: my bans is empty for the unbanned');
  perform pg_temp.act(null);
  perform pg_temp.must_refuse(format('select public.submit_ban_appeal(%L, ''please'')', c), 'appeal: nobody signed in cannot');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(pg_temp.state(format('select public.submit_ban_appeal(%L, ''   '')', c)) = '22023', 'appeal: an empty message');
  perform pg_temp.expect(pg_temp.state(format('select public.submit_ban_appeal(%L, %L)', c, repeat('x', 1001))) = '22023', 'appeal: over 1000 characters');
  perform pg_temp.expect((select count(*) from public.my_circle_bans()) = 1, 'appeal: Eve sees her ban');
  perform pg_temp.expect((select appeal_status is null and expires_at is null from public.my_circle_bans() where circle_id = c), 'appeal: permanent, not yet appealed');
  perform pg_temp.expect(not exists (select 1 from public.my_circle_bans() t where to_jsonb(t) ? 'reason'), 'appeal: the moderators'' reason is not shown to her');

  appeal := public.submit_ban_appeal(c, 'I am sorry');
  perform pg_temp.expect(pg_temp.state(format('select public.submit_ban_appeal(%L, ''again'')', c)) = '23505', 'appeal: one appeal per ban');
  perform pg_temp.expect((select appeal_status from public.my_circle_bans() where circle_id = c) = 'pending', 'appeal: pending');
  perform pg_temp.act(pg_temp.i('fay'));
  appeal2 := public.submit_ban_appeal(c, 'unfair');

  -- The queue.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(public.count_ban_appeals(c) = 0, 'appeal: a member counts none');
  perform pg_temp.expect(pg_temp.state(format('select * from public.list_ban_appeals(%L)', c)) = '42501', 'appeal: a member cannot list');
  perform pg_temp.expect(pg_temp.state(format('select public.decide_ban_appeal(%L, true)', appeal)) = '42501', 'appeal: a member cannot decide');
  perform pg_temp.act(pg_temp.i('kim'));
  perform pg_temp.expect(public.count_ban_appeals(c) = 0, 'appeal: a kicker counts none');
  perform pg_temp.expect(pg_temp.state(format('select public.decide_ban_appeal(%L, true)', appeal)) = '42501', 'appeal: a kicker cannot decide');
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(public.count_ban_appeals(c) = 2, 'appeal: Mia counts two');
  perform pg_temp.expect((select count(*) from public.list_ban_appeals(c)) = 2, 'appeal: and lists two');
  perform pg_temp.expect((select message from public.list_ban_appeals(c) where id = appeal) = 'I am sorry', 'appeal: with the message');
  perform pg_temp.expect((select ban_reason from public.list_ban_appeals(c) where id = appeal) = 'rude', 'appeal: and the ban''s reason, for moderators');
  perform pg_temp.expect((select appeal_status from public.list_circle_bans(c) where user_id = pg_temp.i('eve')) = 'pending', 'appeal: the ban list marks it');

  -- Sam's ban is Sam's to overturn: Mia ranks lower.
  perform pg_temp.expect(pg_temp.state(format('select public.decide_ban_appeal(%L, true)', appeal2)) = '42501', 'appeal: cannot overturn a ban by someone above');
  perform pg_temp.expect(exists (select 1 from public.circle_bans where circle_id = c and user_id = pg_temp.i('fay')), 'appeal: the ban stands');
  perform pg_temp.expect(pg_temp.state(format('select public.decide_ban_appeal(%L, false, ''no'')', appeal2)) = 'ok', 'appeal: but may turn the appeal down');
  perform pg_temp.expect(pg_temp.state(format('select public.decide_ban_appeal(%L, true)', appeal2)) = '55000', 'appeal: decided once');

  -- Deny Eve with a note she can read.
  perform public.decide_ban_appeal(appeal, false, 'not yet');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect((select appeal_status || ':' || appeal_note from public.my_circle_bans() where circle_id = c) = 'denied:not yet', 'appeal: Eve reads the answer');
  perform pg_temp.expect(pg_temp.state(format('select public.submit_ban_appeal(%L, ''once more'')', c)) = '23505', 'appeal: no second go for the same ban');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.audit_count(c, 'ban_appeal_deny') = 2, 'appeal: denials are audited');
  perform pg_temp.expect(pg_temp.audit_count(c, 'ban_appeal_submit') = 2, 'appeal: submissions are audited');

  -- A new ban is a new ban: Eve may appeal it, and this time Mia lifts it.
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.ban_circle_member(c, pg_temp.i('eve'), 'again', 0, 7200);
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect((select appeal_status from public.my_circle_bans() where circle_id = c) is null, 'appeal: a new ban starts clean');
  appeal := public.submit_ban_appeal(c, 'second ban, second appeal');
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.decide_ban_appeal(appeal, true, null);
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.circle_bans where circle_id = c and user_id = pg_temp.i('eve')), 'appeal: approving lifts the ban');
  perform pg_temp.expect(pg_temp.audit_count(c, 'ban_appeal_approve') = 1, 'appeal: approval is audited');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect((select count(*) from public.my_circle_bans()) = 0, 'appeal: Eve is no longer banned');
  perform pg_temp.root();

  -- Lifting a ban any other way closes the appeal waiting on it, and so does
  -- banning again over a pending one.
  perform pg_temp.act(pg_temp.i('sam'));
  perform public.ban_circle_member(c, pg_temp.i('gus'), null, 0, null);
  perform pg_temp.act(pg_temp.i('gus'));
  appeal := public.submit_ban_appeal(c, 'please');
  perform pg_temp.act(pg_temp.i('sam'));
  perform public.unban_circle_member(c, pg_temp.i('gus'));
  perform pg_temp.root();
  perform pg_temp.expect((select status from public.circle_ban_appeals where id = appeal) = 'closed', 'appeal: an unban closes the appeal');
  perform pg_temp.act(pg_temp.i('sam'));
  perform public.ban_circle_member(c, pg_temp.i('gus'), null, 0, null);
  perform pg_temp.act(pg_temp.i('gus'));
  appeal := public.submit_ban_appeal(c, 'please again');
  perform pg_temp.act(pg_temp.i('sam'));
  perform pg_temp.expect(pg_temp.state(format('select * from public.ban_circle_member(%L, %L, ''renewed'', 0, null)', c, pg_temp.i('gus'))) = 'ok', 'appeal: banning again is allowed');
  perform pg_temp.root();
  perform pg_temp.expect((select status from public.circle_ban_appeals where id = appeal) = 'closed', 'appeal: a renewed ban closes the old appeal');
  perform pg_temp.expect(public.count_ban_appeals(c) is not null, 'appeal: counts run as root');

  -- A down circle refuses appeals and decisions.
  perform pg_temp.act(pg_temp.i('hal'));
  perform pg_temp.root();
  update public.circles set disabled_at = now(), disabled_mode = 'delist' where id = c;
  perform pg_temp.act(pg_temp.i('gus'));
  perform pg_temp.expect(pg_temp.state(format('select public.submit_ban_appeal(%L, ''hello'')', c)) = '42501', 'appeal: refused while the circle is down');
  perform pg_temp.expect((select count(*) from public.my_circle_bans()) = 0, 'appeal: and my bans hides a down circle');
  perform pg_temp.root();
  update public.circles set disabled_at = null, disabled_mode = null where id = c;
  -- Tidy: lift the bans so later sections start from nothing.
  delete from public.circle_bans where circle_id = c;
end $$;

-- ===================================== 5. the member filter and batch actions
do $$
declare
  c uuid := pg_temp.i('circle');
  r jsonb;
  total bigint;
begin
  -- Dee was banned in section 1: she is let back in. Members now: ada, bob,
  -- mia, sam, kim, dee, hal. Give people a history to filter on.
  insert into public.circle_members (circle_id, user_id, role) values (c, pg_temp.i('dee'), 'member');
  insert into public.conversation_members (conversation_id, user_id, role)
    select cc.conversation_id, pg_temp.i('dee'), 'member' from public.circle_channels cc where cc.circle_id = c;
  update public.circle_members set created_at = now() - interval '60 days'
    where circle_id = c and user_id in (pg_temp.i('bob'), pg_temp.i('dee'));
  update public.circle_members set created_at = now() - interval '3 days'
    where circle_id = c and user_id = pg_temp.i('hal');
  update public.profiles set created_at = now() - interval '400 days'
    where id in (pg_temp.i('bob'), pg_temp.i('dee'), pg_temp.i('mia'), pg_temp.i('sam'), pg_temp.i('kim'), pg_temp.i('ada'));
  insert into public.messages (conversation_id, sender_id, type, body)
    select pg_temp.i('channel'), pg_temp.i('dee'), 'text', 'm' || g from generate_series(1, 7) g;
  insert into public.messages (conversation_id, sender_id, type, body)
    values (pg_temp.i('channel'), pg_temp.i('bob'), 'text', 'only one');

  -- Only people who moderate may use it.
  perform pg_temp.act(pg_temp.i('hal'));
  perform pg_temp.expect(pg_temp.state(format('select * from public.list_circle_members_for_moderation(%L)', c)) = '42501', 'filter: a member cannot');
  perform pg_temp.act(null);
  perform pg_temp.must_refuse(format('select * from public.list_circle_members_for_moderation(%L)', c), 'filter: nobody signed in cannot');

  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect((select count(*) from public.list_circle_members_for_moderation(c)) = (select count(*) from public.circle_members where circle_id = c), 'filter: everyone with no filters');
  perform pg_temp.expect((select count(*) from public.list_circle_members_for_moderation(c, joined_within_days => 7)) = 5, 'filter: joined in the last week (hal, plus Ada''s 2-day-old members, not bob or dee)'
    );
  perform pg_temp.expect((select count(*) from public.list_circle_members_for_moderation(c, joined_before_days => 30)) = 2, 'filter: joined more than 30 days ago');
  perform pg_temp.expect((select count(*) from public.list_circle_members_for_moderation(c, account_within_days => 30)) = 1, 'filter: accounts under 30 days old (hal)');
  perform pg_temp.expect((select count(*) from public.list_circle_members_for_moderation(c, min_messages => 5)) = 1, 'filter: at least 5 messages');
  perform pg_temp.expect((select user_id from public.list_circle_members_for_moderation(c, min_messages => 5)) = pg_temp.i('dee'), 'filter: that is dee');
  perform pg_temp.expect((select message_count from public.list_circle_members_for_moderation(c, name_query => 'dee')) = 7, 'filter: the count is shown');
  perform pg_temp.expect((select count(*) from public.list_circle_members_for_moderation(c, max_messages => 1) where message_count <= 1) >= 1, 'filter: at most one message');
  perform pg_temp.expect((select count(*) from public.list_circle_members_for_moderation(c, filter_role_id => pg_temp.i('kicker'))) = 1, 'filter: by role');
  perform pg_temp.expect((select user_id from public.list_circle_members_for_moderation(c, filter_role_id => pg_temp.i('kicker'))) = pg_temp.i('kim'), 'filter: kim holds it');
  perform pg_temp.expect((select count(*) from public.list_circle_members_for_moderation(c, name_query => 'KIM')) = 1, 'filter: by name, any case');
  perform pg_temp.expect((select count(*) from public.list_circle_members_for_moderation(c, name_query => '%')) >= 0, 'filter: a wildcard is not a wildcard');
  perform pg_temp.expect((select count(*) from public.list_circle_members_for_moderation(c, only_flagged => true)) = 1, 'filter: only Hal, who kept a warning from section 3, is flagged');

  -- Flagged: a warning, an open report, or a held message.
  perform pg_temp.expect((select user_id from public.list_circle_members_for_moderation(c, only_flagged => true)) = pg_temp.i('hal'), 'filter: a warning flags');
  perform public.add_circle_mod_note(c, pg_temp.i('hal'), 'warning', 'links');
  perform pg_temp.expect((select warning_count from public.list_circle_members_for_moderation(c, name_query => 'hal')) = 2, 'filter: and is counted');
  perform pg_temp.root();
  insert into public.message_reports (reporter_id, message_id, conversation_id, circle_id, reported_user_id, reason)
    values (pg_temp.i('bob'), null, pg_temp.i('channel'), c, pg_temp.i('dee'), 'spam');
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect((select count(*) from public.list_circle_members_for_moderation(c, only_flagged => true)) = 2, 'filter: an open report flags too');

  -- What the caller may do to each row.
  perform pg_temp.expect((select can_timeout and can_kick and can_ban from public.list_circle_members_for_moderation(c, name_query => 'bob')), 'rows: Mia may act on Bob');
  perform pg_temp.expect((select not (can_timeout or can_kick or can_ban) from public.list_circle_members_for_moderation(c, name_query => 'sam')), 'rows: not on Sam above her');
  perform pg_temp.expect((select not (can_timeout or can_kick or can_ban) from public.list_circle_members_for_moderation(c, name_query => 'ada')), 'rows: not on the owner');
  perform pg_temp.expect((select not (can_timeout or can_kick or can_ban) from public.list_circle_members_for_moderation(c, name_query => 'mia')), 'rows: not on herself');
  perform pg_temp.act(pg_temp.i('kim'));
  perform pg_temp.expect(pg_temp.state(format('select * from public.list_circle_members_for_moderation(%L)', c)) = 'ok', 'rows: a kicker may filter');
  perform pg_temp.expect((select can_kick and not can_ban and not can_timeout from public.list_circle_members_for_moderation(c, name_query => 'bob')), 'rows: Kim may only kick');
  perform pg_temp.act(pg_temp.i('mia'));
  -- Paging.
  perform pg_temp.expect((select count(*) from public.list_circle_members_for_moderation(c, result_limit => 2)) = 2, 'page: a limit');
  perform pg_temp.expect((select max(total_count) from public.list_circle_members_for_moderation(c, result_limit => 2)) = (select count(*) from public.circle_members where circle_id = c), 'page: the total');
  perform pg_temp.expect((select count(*) from public.list_circle_members_for_moderation(c, result_limit => 2, result_offset => 100)) = 0, 'page: past the end');
  perform pg_temp.root();
end $$;

do $$
declare
  c uuid := pg_temp.i('circle');
  r jsonb;
  extra uuid[];
begin
  -- Targets: bob, dee, hal (below Mia), sam (above), ada (owner).
  perform pg_temp.act(pg_temp.i('hal'));
  perform pg_temp.expect(pg_temp.state(format('select public.batch_moderate_circle_members(%L, %L, ''timeout'', 600)', c, array[pg_temp.i('bob')])) = '42501', 'batch: a member cannot');
  perform pg_temp.act(pg_temp.i('kim'));
  perform pg_temp.expect(pg_temp.state(format('select public.batch_moderate_circle_members(%L, %L, ''timeout'', 600)', c, array[pg_temp.i('bob')])) = '42501', 'batch: a kicker cannot time out');
  perform pg_temp.expect(pg_temp.state(format('select public.batch_moderate_circle_members(%L, %L, ''ban'', null)', c, array[pg_temp.i('bob')])) = '42501', 'batch: a kicker cannot ban');
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.state(format('select public.batch_moderate_circle_members(%L, %L, ''dance'', 600)', c, array[pg_temp.i('bob')])) = '22023', 'batch: an unknown action');
  perform pg_temp.expect(pg_temp.state(format('select public.batch_moderate_circle_members(%L, %L, ''timeout'', 600)', c, '{}'::uuid[])) = '22023', 'batch: nobody chosen');
  perform pg_temp.expect(pg_temp.state(format('select public.batch_moderate_circle_members(%L, %L, ''timeout'', null)', c, array[pg_temp.i('bob')])) = '22023', 'batch: a timeout needs a length');
  select array_agg(pg_temp.uid('r' || lpad(g::text, 2, '0'))) into extra from generate_series(1, 51) g;
  perform pg_temp.expect(pg_temp.state(format('select public.batch_moderate_circle_members(%L, %L, ''timeout'', 600)', c, extra)) = '22023', 'batch: 51 people are too many');

  -- A mixed selection: the ones below Mia work, Sam and Ada do not, and the
  -- duplicate counts once.
  r := public.batch_moderate_circle_members(c,
    array[pg_temp.i('bob'), pg_temp.i('dee'), pg_temp.i('sam'), pg_temp.i('ada'), pg_temp.i('bob'), pg_temp.i('mia')],
    'timeout', 600);
  perform pg_temp.expect((r ->> 'done')::integer = 2, 'batch: two were timed out');
  perform pg_temp.expect(jsonb_array_length(r -> 'results') = 5, 'batch: five distinct people answered');
  perform pg_temp.expect((select count(*) from jsonb_array_elements(r -> 'results') e where e ->> 'ok' = 'false' and e ->> 'code' = '42501') = 2, 'batch: Sam and Ada were refused by rank');
  perform pg_temp.expect((select (e ->> 'ok')::boolean = false and e ->> 'code' = '22023' from jsonb_array_elements(r -> 'results') e where e ->> 'user_id' = pg_temp.i('mia')::text), 'batch: and Mia herself');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_members where circle_id = c and timed_out_until > now()) = 2, 'batch: exactly two are timed out');
  perform pg_temp.expect(pg_temp.audit_count(c, 'member_batch_action') = 1, 'batch: one summary entry');
  perform pg_temp.expect((select (changes ->> 'done')::integer || '/' || (changes ->> 'requested') from public.circle_audit_log where circle_id = c and action = 'member_batch_action') = '2/5', 'batch: it says 2 of 5');
  perform pg_temp.expect(pg_temp.audit_count(c, 'member_timeout') >= 2, 'batch: each timeout has its own entry');

  -- Ending timeouts.
  perform pg_temp.act(pg_temp.i('mia'));
  r := public.batch_moderate_circle_members(c, array[pg_temp.i('bob'), pg_temp.i('dee')], 'untimeout');
  perform pg_temp.expect((r ->> 'done')::integer = 2, 'batch: both timeouts end');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_members where circle_id = c and timed_out_until > now()) = 0, 'batch: nobody is timed out');

  -- Kick: Kim may, below her; Mia's rank is above Kim's.
  perform pg_temp.act(pg_temp.i('kim'));
  r := public.batch_moderate_circle_members(c, array[pg_temp.i('hal'), pg_temp.i('mia')], 'kick');
  perform pg_temp.expect((r ->> 'done')::integer = 1, 'batch: Kim kicks Hal, not Mia');
  perform pg_temp.root();
  perform pg_temp.expect(not pg_temp.is_member(c, pg_temp.i('hal')) and pg_temp.is_member(c, pg_temp.i('mia')), 'batch: the kick took the right one');

  -- Ban: with a duration, and nobody outranking is touched.
  perform pg_temp.act(pg_temp.i('mia'));
  r := public.batch_moderate_circle_members(c, array[pg_temp.i('dee'), pg_temp.i('sam'), pg_temp.i('gus')], 'ban', 3600, 'raid', 24);
  perform pg_temp.expect((r ->> 'done')::integer = 2, 'batch: two banned (dee, and gus who is outside)');
  perform pg_temp.expect(jsonb_typeof(r -> 'media') = 'array', 'batch: the files to remove are listed');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_bans where circle_id = c and expires_at is not null) = 2, 'batch: both bans end');
  perform pg_temp.expect(not exists (select 1 from public.circle_bans where circle_id = c and user_id = pg_temp.i('sam')), 'batch: Sam was not banned');
  delete from public.circle_bans where circle_id = c;

  -- A down circle takes no batch.
  update public.circles set disabled_at = now(), disabled_mode = 'delist' where id = c;
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.state(format('select public.batch_moderate_circle_members(%L, %L, ''timeout'', 600)', c, array[pg_temp.i('bob')])) = '42501', 'batch: refused while the circle is down');
  perform pg_temp.root();
  update public.circles set disabled_at = null, disabled_mode = null where id = c;
end $$;

-- ===================================== 6. raid protection: invites and settings
-- The people who will raid (r01 ... r30) have old accounts; r31 ... r40 are new.
update public.profiles set created_at = now() - interval '30 days'
where id in (select pg_temp.uid('r' || lpad(g::text, 2, '0')) from generate_series(1, 30) g);
update public.profiles set created_at = now() - interval '30 days' where id = pg_temp.i('ivy');

do $$
declare
  c uuid := pg_temp.i('circle');
  inv_code text;
  paused timestamptz;
  s jsonb;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  inv_code := public.create_circle_invite(c, null, null);

  -- Who may see the state, pause, resume.
  perform pg_temp.expect(pg_temp.state(format('select public.get_circle_security(%L)', c)) = '42501', 'security: a member cannot read it');
  perform pg_temp.expect(pg_temp.state(format('select public.pause_circle_invites(%L, 1)', c)) = '42501', 'pause: a member cannot');
  perform pg_temp.expect(pg_temp.state(format('select public.resume_circle_invites(%L)', c)) = '42501', 'resume: a member cannot');
  perform pg_temp.expect(pg_temp.state(format('select public.start_circle_lockdown(%L, 1)', c)) = '42501', 'lockdown: a member cannot');
  perform pg_temp.expect(pg_temp.state(format('select public.end_circle_lockdown(%L)', c)) = '42501', 'lockdown: a member cannot end it');
  perform pg_temp.act(pg_temp.i('gus'));
  perform pg_temp.expect(pg_temp.state(format('select public.pause_circle_invites(%L, 1)', c)) = '42501', 'pause: an outsider cannot');
  perform pg_temp.act(null);
  perform pg_temp.must_refuse(format('select public.pause_circle_invites(%L, 1)', c), 'pause: nobody signed in cannot');

  perform pg_temp.act(pg_temp.i('mia'));
  s := public.get_circle_security(c);
  perform pg_temp.expect((s ->> 'raid_enabled')::boolean and (s ->> 'raid_threshold')::integer = 20 and (s ->> 'raid_lock_hours')::integer = 1, 'security: the defaults without a row');
  perform pg_temp.expect(s -> 'lockdown' = 'null'::jsonb and s -> 'invites_paused_until' = 'null'::jsonb, 'security: nothing is on');
  perform pg_temp.expect(not (s ->> 'can_manage')::boolean, 'security: Mia cannot change the settings');
  perform pg_temp.expect(pg_temp.state(format('select public.pause_circle_invites(%L, 5)', c)) = '22023', 'pause: only 1 or 24 hours');
  perform pg_temp.expect(pg_temp.state(format('select public.start_circle_lockdown(%L, 3)', c)) = '22023', 'lockdown: only 1 or 24 hours');

  -- Pausing stops every invite path.
  paused := public.pause_circle_invites(c, 1);
  perform pg_temp.expect(paused between now() + interval '59 minutes' and now() + interval '61 minutes', 'pause: an hour');
  perform pg_temp.expect(public.get_circle_security(c) -> 'invites_paused_until' <> 'null'::jsonb, 'pause: the state shows it');
  perform pg_temp.expect(public.get_circle_security(c) ->> 'join_mode' = 'open', 'pause: the join mode is untouched');
  perform pg_temp.act(pg_temp.i('ivy'));
  perform pg_temp.expect(pg_temp.msg(format('select public.accept_circle_invite(%L)', inv_code)) = 'Invite is paused', 'pause: an existing link says paused');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_circle_invite(%L, null, null)', c)) = '42501', 'pause: no new link');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.msg(format('select public.invite_circle_members(%L, %L)', c, array[pg_temp.i('ivy')])) = 'Invites to this circle are paused', 'pause: no adding friends');
  perform pg_temp.root();
  perform pg_temp.expect(not pg_temp.is_member(c, pg_temp.i('ivy')), 'pause: Ivy stayed out');
  perform pg_temp.expect(pg_temp.audit_count(c, 'invites_pause') = 1, 'pause: audited');
  perform pg_temp.expect(public.circle_invite_invalid_reason((select ci from public.circle_invites ci where ci.code = inv_code)) = 'paused', 'pause: the invalid reason is paused');

  -- Discover is not an invite: it still works while only invites are paused.
  perform pg_temp.act(pg_temp.i('r30'));
  perform pg_temp.expect(pg_temp.state(format('select public.join_public_circle(%L)', c)) = 'ok', 'pause: Discover still joins');
  perform pg_temp.root();
  delete from public.circle_members where circle_id = c and user_id = pg_temp.i('r30');
  delete from public.conversation_members m using public.circle_channels cc
    where cc.circle_id = c and m.conversation_id = cc.conversation_id and m.user_id = pg_temp.i('r30');
  delete from public.circle_public_joins;

  -- A longer pause is never shortened; resuming opens them again.
  perform pg_temp.act(pg_temp.i('kim'));
  perform public.pause_circle_invites(c, 24);
  perform public.pause_circle_invites(c, 1);
  perform pg_temp.root();
  perform pg_temp.expect((select invites_paused_until > now() + interval '23 hours' from public.circle_security where circle_id = c), 'pause: 24 hours stands over a later 1 hour');
  update public.circles set disabled_at = now(), disabled_mode = 'delist' where id = c;
  perform pg_temp.act(pg_temp.i('kim'));
  perform pg_temp.expect(pg_temp.state(format('select public.resume_circle_invites(%L)', c)) = '42501', 'resume: refused while the circle is down');
  perform pg_temp.expect(pg_temp.state(format('select public.pause_circle_invites(%L, 1)', c)) = '42501', 'pause: refused while the circle is down');
  perform pg_temp.root();
  update public.circles set disabled_at = null, disabled_mode = null where id = c;
  perform pg_temp.act(pg_temp.i('kim'));
  perform public.resume_circle_invites(c);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.audit_count(c, 'invites_resume') = 1, 'resume: audited');
  perform pg_temp.act(pg_temp.i('ivy'));
  perform pg_temp.expect(pg_temp.state(format('select public.accept_circle_invite(%L)', inv_code)) = 'ok', 'resume: the link works again');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('ivy')), 'resume: Ivy joined');
  perform pg_temp.act(pg_temp.i('ivy'));
  perform public.leave_circle(c);
  perform pg_temp.root();
  -- Resuming nothing is not an error and not logged.
  perform pg_temp.act(pg_temp.i('kim'));
  perform public.resume_circle_invites(c);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.audit_count(c, 'invites_resume') = 1, 'resume: nothing to resume is not logged');
  -- Revoke the old link so it cannot confuse later sections.
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.revoke_circle_invite(inv_code);
  perform pg_temp.root();
end $$;

do $$
declare
  c uuid := pg_temp.i('circle');
begin
  -- The automatic protection's settings: manage_circle only.
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_raid_settings(%L, true, 8, 1)', c)) = '42501', 'settings: a moderator without manage_circle cannot');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_raid_settings(%L, true, 8, 1)', c)) = '42501', 'settings: a member cannot');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect((public.get_circle_security(c) ->> 'can_manage')::boolean, 'settings: the owner may');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_raid_settings(%L, true, 2, 1)', c)) = '22023', 'settings: a threshold under 3');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_raid_settings(%L, true, 501, 1)', c)) = '22023', 'settings: a threshold over 500');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_raid_settings(%L, true, 8, 6)', c)) = '22023', 'settings: 1 or 24 hours');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_raid_settings(%L, null, 8, 1)', c)) = '22023', 'settings: a missing switch');
  perform public.set_circle_raid_settings(c, true, 8, 1);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.audit_count(c, 'raid_settings_update') = 1, 'settings: audited');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_raid_settings(c, true, 8, 1);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.audit_count(c, 'raid_settings_update') = 1, 'settings: saving the same thing is not logged again');
  perform pg_temp.expect((select raid_threshold from public.circle_security where circle_id = c) = 8, 'settings: saved');
  update public.circles set disabled_at = now(), disabled_mode = 'suspend' where id = c;
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_raid_settings(%L, true, 9, 1)', c)) = '42501', 'settings: refused while the circle is down');
  perform pg_temp.root();
  update public.circles set disabled_at = null, disabled_mode = null where id = c;
  perform pg_temp.expect(pg_temp.state(format('select * from public.circle_security')) = 'ok', 'settings: the table is readable here as root');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state('select * from public.circle_security') = '42501', 'settings: and closed to clients');
  perform pg_temp.expect(pg_temp.state('select * from public.circle_raid_events') = '42501', 'settings: so are the events');
  perform pg_temp.root();
end $$;

-- ===================================== 7. raid protection: the lockdown
-- Triggers that wait for COMMIT run at once from here on.
set constraints all immediate;

-- AutoMod has an alert channel, so the lockdown can post a card there.
insert into public.circle_automod_rules (circle_id, name, kind, mention_limit, block_message, alert_channel_id)
values (pg_temp.i('circle'), 'Mentions', 'mention_spam', 5, false, pg_temp.i('channel_id'));

-- A join through Discover as a raider. Returns 'ok' or the SQLSTATE.
create function pg_temp.raid_join(who text) returns text language plpgsql as $$
declare r text;
begin
  perform pg_temp.act(pg_temp.i(who));
  r := pg_temp.state(format('select public.join_public_circle(%L)', pg_temp.i('circle')));
  perform pg_temp.root();
  return r;
end $$;
grant execute on function pg_temp.raid_join(text) to public;

do $$
declare
  c uuid := pg_temp.i('circle');
  g integer;
  sec public.circle_security%rowtype;
  alert_count integer;
begin
  -- Seven people in ten minutes (threshold 8): nothing yet.
  for g in 1..7 loop
    perform pg_temp.expect(pg_temp.raid_join('r' || lpad(g::text, 2, '0')) = 'ok', 'raid: r0' || g || ' joins');
  end loop;
  select * into sec from public.circle_security where circle_id = c;
  perform pg_temp.expect(sec.lockdown_until is null, 'raid: seven joins are not a raid');
  perform pg_temp.expect((select join_mode from public.circles where id = c) = 'open', 'raid: the circle is still open');

  -- The eighth tips it.
  perform pg_temp.expect(pg_temp.raid_join('r08') = 'ok', 'raid: r08 joins');
  select * into sec from public.circle_security where circle_id = c;
  perform pg_temp.expect(sec.lockdown_until between now() + interval '59 minutes' and now() + interval '61 minutes', 'raid: locked down for an hour');
  perform pg_temp.expect(sec.lockdown_source = 'auto' and sec.lockdown_joins = 8 and sec.lockdown_new_accounts = 0, 'raid: the numbers are kept');
  perform pg_temp.expect(sec.lockdown_prev_mode = 'open', 'raid: it remembers the circle was open');
  perform pg_temp.expect((select join_mode from public.circles where id = c) = 'apply', 'raid: the circle now reviews who joins');
  perform pg_temp.expect(sec.invites_paused_until >= sec.lockdown_until, 'raid: invites are paused');
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('r08')), 'raid: nobody was removed');
  perform pg_temp.expect((select count(*) from public.circle_members where circle_id = c and user_id in (select pg_temp.uid('r0' || n) from generate_series(1, 8) n)) = 8, 'raid: all eight are still members');
  perform pg_temp.expect(pg_temp.audit_count(c, 'raid_lockdown') = 1, 'raid: audited');
  perform pg_temp.expect((select actor_id is null and changes ->> 'source' = 'auto' and (changes ->> 'join_mode_switched')::boolean from public.circle_audit_log where circle_id = c and action = 'raid_lockdown'), 'raid: the entry has no actor and says why');
  perform pg_temp.expect((select count(*) from public.circle_raid_events where circle_id = c and kind = 'lockdown' and source = 'auto' and push_claimed_at is null) = 1, 'raid: one push waits');

  -- The alert card in the AutoMod alert channel.
  select count(*) into alert_count from public.messages m
  where m.conversation_id = pg_temp.i('channel') and m.type = 'system' and m.attachment ->> 'kind' = 'raid_alert';
  perform pg_temp.expect(alert_count = 1, 'raid: one alert card in the alert channel');
  perform pg_temp.expect((select (attachment ->> 'joins')::integer = 8 and (attachment ->> 'hours')::integer = 1 from public.messages where conversation_id = pg_temp.i('channel') and attachment ->> 'kind' = 'raid_alert'), 'raid: the card carries the numbers');

  -- Later arrivals ask instead of joining (C1), invites are dead (C4/C1 paths).
  perform pg_temp.expect(pg_temp.raid_join('r09') = 'ok', 'raid: r09 asks');
  perform pg_temp.expect(not pg_temp.is_member(c, pg_temp.i('r09')) and pg_temp.pending(c, pg_temp.i('r09')) = 1, 'raid: r09 is waiting, not a member');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_circle_invite(%L, null, null)', c)) = '42501', 'raid: no new invites');
  perform pg_temp.root();
  -- The check does not fire twice for one lockdown.
  perform pg_temp.expect(pg_temp.raid_join('r10') = 'ok', 'raid: r10 asks');
  perform pg_temp.expect(pg_temp.audit_count(c, 'raid_lockdown') = 1, 'raid: still one lockdown');
  perform pg_temp.expect((select count(*) from public.circle_raid_events where circle_id = c and kind = 'lockdown') = 1, 'raid: still one event');

  -- The state as the moderators see it.
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect((public.get_circle_security(c) -> 'lockdown' ->> 'joins')::integer = 8, 'raid: Mia sees the lockdown');
  perform pg_temp.expect((public.get_circle_security(c) ->> 'join_mode') = 'apply', 'raid: and the mode');
  perform pg_temp.expect(pg_temp.state(format('select public.resume_circle_invites(%L)', c)) = '55000', 'raid: invites cannot be resumed on their own');
  perform pg_temp.root();
end $$;

-- Newcomers of the burst, the AI guard, onboarding and C1 approvals.
do $$
declare
  c uuid := pg_temp.i('circle');
  m uuid;
  req uuid;
begin
  -- Links: refused for the burst's newcomers, fine for everybody else.
  perform pg_temp.act(pg_temp.i('r01'));
  perform pg_temp.expect(pg_temp.say(pg_temp.i('channel'), pg_temp.i('r01'), 'see https://spam.example') = '42501', 'newcomers: no link in the first hour');
  perform pg_temp.expect(pg_temp.msg(format('insert into public.messages (conversation_id, sender_id, type, body) values (%L, %L, ''text'', ''www.spam.example'')', pg_temp.i('channel'), pg_temp.i('r01'))) = 'New members cannot post links while the circle is locked down', 'newcomers: www too, with a clear message');
  perform pg_temp.expect(pg_temp.say(pg_temp.i('channel'), pg_temp.i('r01'), 'hello everyone') = 'ok', 'newcomers: ordinary talk is fine');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.say(pg_temp.i('channel'), pg_temp.i('bob'), 'docs at https://example.org') = 'ok', 'newcomers: an old member may post links');
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.say(pg_temp.i('channel'), pg_temp.i('mia'), 'rules https://example.org/rules') = 'ok', 'newcomers: a moderator may too');
  perform pg_temp.root();
  -- Webhook posts and notices are not touched.
  perform pg_temp.expect(pg_temp.state(format('insert into public.messages (conversation_id, sender_id, type, body) values (%L, %L, ''system'', ''https://x.example'')', pg_temp.i('channel'), pg_temp.i('r01'))) = 'ok', 'newcomers: a system notice with a link passes');

  -- The AI guard (message_count rule: one visible message makes you trusted).
  -- r02 already has a visible message, so the guard alone would let r02 pass.
  insert into public.messages (conversation_id, sender_id, type, body) values (pg_temp.i('channel'), pg_temp.i('r02'), 'text', 'my first message');
  insert into public.circle_ai_guard (circle_id, enabled, new_rule, message_count, action)
    values (c, true, 'message_count', 1, 'hold');
  update public.circles set ai_enabled = true where id = c;
  update public.messages set review_state = null where sender_id = pg_temp.i('r02');
  perform pg_temp.act(pg_temp.i('r02'));
  perform pg_temp.say(pg_temp.i('channel'), pg_temp.i('r02'), 'second one');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.say(pg_temp.i('channel'), pg_temp.i('bob'), 'ordinary talk from an old member');
  perform pg_temp.root();
  perform pg_temp.expect(exists (select 1 from public.message_reviews r where r.sender_id = pg_temp.i('r02') and r.circle_id = c), 'guard: the burst''s newcomer is checked by the AI guard although the guard''s own rule trusts them');
  perform pg_temp.expect(not exists (select 1 from public.message_reviews r where r.sender_id = pg_temp.i('bob')), 'guard: an old member is not');
  delete from public.circle_ai_guard where circle_id = c;
  update public.circles set ai_enabled = false where id = c;

  -- Without the guard nothing is held: only links are refused.
  perform pg_temp.act(pg_temp.i('r03'));
  perform pg_temp.say(pg_temp.i('channel'), pg_temp.i('r03'), 'hi from r03');
  perform pg_temp.root();
  perform pg_temp.expect(not exists (select 1 from public.message_reviews r where r.sender_id = pg_temp.i('r03')), 'guard: no guard, no check');

  -- C1: a moderator approves a waiting request during the lockdown. The
  -- approval works; the person who comes in is one of the burst's newcomers.
  select r.id into req from public.circle_join_requests r where r.circle_id = c and r.user_id = pg_temp.i('r09');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.decide_join_request(%L, true)', req)) = 'P0002', 'C1: a member cannot approve (the request is hidden from them)');
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.decide_join_request(req, true, null);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('r09')), 'C1: Mia approved r09 during the lockdown');
  -- C2: onboarding goes on now (everyone inside counts as accepted); r10 is
  -- approved after it, so must accept the rules first.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_onboarding(c, true, array['Be kind'], 'Welcome');
  perform pg_temp.root();
  select r.id into req from public.circle_join_requests r where r.circle_id = c and r.user_id = pg_temp.i('r10');
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.decide_join_request(req, true, null);
  perform pg_temp.act(pg_temp.i('r10'));
  perform pg_temp.expect(pg_temp.say(pg_temp.i('channel'), pg_temp.i('r10'), 'before the rules') = '42501', 'C2: rules first, lockdown or not');
  perform pg_temp.expect(pg_temp.msg(format('insert into public.messages (conversation_id, sender_id, type, body) values (%L, %L, ''text'', ''https://x.example'')', pg_temp.i('channel'), pg_temp.i('r10'))) <> 'ok', 'C2: and no link either');
  perform public.accept_circle_rules(c);
  perform pg_temp.expect(pg_temp.say(pg_temp.i('channel'), pg_temp.i('r10'), 'after the rules') = 'ok', 'C2: after the rules, plain talk');
  perform pg_temp.expect(pg_temp.say(pg_temp.i('channel'), pg_temp.i('r10'), 'now https://x.example') = '42501', 'C2: links still wait for the lockdown to end');
  perform pg_temp.root();
  -- Onboarding off again.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_onboarding(c, false, array['Be kind'], 'Welcome');
  perform pg_temp.root();
end $$;

-- Ending it.
do $$
declare
  c uuid := pg_temp.i('circle');
  sec public.circle_security%rowtype;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.end_circle_lockdown(%L)', c)) = '42501', 'release: a member cannot');
  perform pg_temp.root();
  -- The burst was a few minutes ago.
  update public.circle_members set created_at = now() - interval '5 minutes'
    where circle_id = c and user_id in (select pg_temp.uid('r' || lpad(n::text, 2, '0')) from generate_series(1, 8) n);
  update public.circle_join_requests set created_at = now() - interval '5 minutes' where circle_id = c;
  update public.circle_members set created_at = now() - interval '4 minutes' where circle_id = c and user_id in (pg_temp.i('r09'), pg_temp.i('r10'));
  perform pg_temp.act(pg_temp.i('kim'));
  perform pg_temp.expect(public.end_circle_lockdown(c), 'release: Kim (kick_members) ends it');
  perform pg_temp.expect(not public.end_circle_lockdown(c), 'release: ending it again does nothing');
  perform pg_temp.root();
  select * into sec from public.circle_security where circle_id = c;
  perform pg_temp.expect(sec.lockdown_until is null and sec.lockdown_prev_mode is null, 'release: the lockdown is cleared');
  perform pg_temp.expect(sec.invites_paused_until is null, 'release: invites are open again');
  perform pg_temp.expect((select join_mode from public.circles where id = c) = 'open', 'release: the circle is open again, as it was');
  perform pg_temp.expect(pg_temp.audit_count(c, 'raid_release') = 1, 'release: audited');
  perform pg_temp.expect((select actor_id = pg_temp.i('kim') and changes ->> 'source' = 'manual' and (changes ->> 'join_mode_restored')::boolean from public.circle_audit_log where circle_id = c and action = 'raid_release'), 'release: by Kim, restoring the mode');
  perform pg_temp.expect((select count(*) from public.circle_raid_events where circle_id = c and kind = 'release') = 1, 'release: an event');
  -- Newcomers can post links again.
  perform pg_temp.act(pg_temp.i('r01'));
  perform pg_temp.expect(pg_temp.say(pg_temp.i('channel'), pg_temp.i('r01'), 'see https://ok.example') = 'ok', 'release: links are allowed again');
  perform pg_temp.root();
  -- The same people are not counted again: one more join is just one join.
  perform pg_temp.expect(pg_temp.raid_join('r11') = 'ok', 'release: r11 joins');
  perform pg_temp.expect((select lockdown_until is null from public.circle_security where circle_id = c), 'release: the old burst does not lock the circle again');
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('r11')), 'release: Discover joins directly again');
end $$;

-- ===================================== 8. more lockdowns
do $$
declare
  c uuid := pg_temp.i('circle');
  sec public.circle_security%rowtype;
  g integer;
begin
  -- r11 joined a few minutes ago.
  update public.circle_members set created_at = now() - interval '5 minutes'
    where circle_id = c and user_id = pg_temp.i('r11');
  -- A moderator's lockdown: the same effects, no alert card, no push.
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.start_circle_lockdown(c, 1);
  perform pg_temp.root();
  select * into sec from public.circle_security where circle_id = c;
  perform pg_temp.expect(sec.lockdown_source = 'manual' and sec.lockdown_prev_mode = 'open', 'manual: locked, remembering the mode');
  perform pg_temp.expect((select join_mode from public.circles where id = c) = 'apply', 'manual: the circle reviews who joins');
  perform pg_temp.expect(sec.lockdown_window_from >= now() - interval '1 second', 'manual: the window starts now, so earlier joiners are not newcomers');
  perform pg_temp.expect((select actor_id = pg_temp.i('mia') from public.circle_audit_log where circle_id = c and action = 'raid_lockdown' order by created_at desc limit 1), 'manual: audited as Mia');
  perform pg_temp.expect((select count(*) from public.messages where conversation_id = pg_temp.i('channel') and attachment ->> 'kind' = 'raid_alert') = 1, 'manual: no second alert card');
  perform pg_temp.expect((select count(*) from public.circle_raid_events where circle_id = c and kind = 'lockdown' and source = 'manual' and push_claimed_at is null) = 1, 'manual: its event is never pushed (claimed later does not matter)');
  perform pg_temp.act(pg_temp.i('r11'));
  perform pg_temp.expect(pg_temp.say(pg_temp.i('channel'), pg_temp.i('r11'), 'a link https://fine.example') = 'ok', 'manual: someone who joined before is no newcomer');
  -- Starting again while locked down changes nothing.
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.start_circle_lockdown(c, 24);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.audit_count(c, 'raid_lockdown') = 2, 'manual: a second start is not a second lockdown');

  -- Somebody changes the join mode meanwhile: their choice wins.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_join_settings(c, 'invite_only', '[]'::jsonb);
  perform pg_temp.root();
  perform pg_temp.expect((select lockdown_prev_mode is null from public.circle_security where circle_id = c), 'takeover: the lockdown lets go of the mode');
  perform pg_temp.act(pg_temp.i('kim'));
  perform public.end_circle_lockdown(c);
  perform pg_temp.root();
  perform pg_temp.expect((select join_mode from public.circles where id = c) = 'invite_only', 'takeover: ending the lockdown leaves invite-only alone');
  perform pg_temp.expect((select (changes ->> 'join_mode_restored')::boolean from public.circle_audit_log where circle_id = c and action = 'raid_release' order by created_at desc limit 1) = false, 'takeover: and says it did not restore');

  -- An invite-only circle: the lockdown leaves the mode as it is.
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.start_circle_lockdown(c, 1);
  perform pg_temp.expect(public.end_circle_lockdown(c), 'invite-only: ended');
  perform pg_temp.root();
  perform pg_temp.expect((select join_mode from public.circles where id = c) = 'invite_only', 'invite-only: still invite-only');

  -- A circle that already asks people to apply stays that way.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_join_settings(c, 'apply', '[]'::jsonb);
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.start_circle_lockdown(c, 1);
  perform pg_temp.root();
  perform pg_temp.expect((select lockdown_prev_mode is null from public.circle_security where circle_id = c), 'apply: nothing to remember');
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.end_circle_lockdown(c);
  perform pg_temp.root();
  perform pg_temp.expect((select join_mode from public.circles where id = c) = 'apply', 'apply: still apply after it');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_join_settings(c, 'open', '[]'::jsonb);
  perform pg_temp.root();

  -- Running out by itself: the sweep lets go, with nobody to sign the entry.
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.start_circle_lockdown(c, 1);
  perform pg_temp.root();
  perform pg_temp.expect((select join_mode from public.circles where id = c) = 'apply', 'expiry: locked');
  update public.circle_security set lockdown_until = now() - interval '1 second' where circle_id = c;
  perform public.run_circle_safety_sweep();
  perform pg_temp.expect((select lockdown_until is null from public.circle_security where circle_id = c), 'expiry: the sweep ended it');
  perform pg_temp.expect((select join_mode from public.circles where id = c) = 'open', 'expiry: and put the mode back');
  perform pg_temp.expect((select actor_id is null and changes ->> 'source' = 'expired' from public.circle_audit_log where circle_id = c and action = 'raid_release' order by created_at desc limit 1), 'expiry: audited without an actor');
  perform pg_temp.expect((select count(*) from public.circle_raid_events where circle_id = c and kind = 'release' and source = 'expired') = 1, 'expiry: an event');

  -- A burst of requests in a circle that reviews who joins.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_join_settings(c, 'apply', '[]'::jsonb);
  perform pg_temp.root();
  for g in 12..19 loop
    perform pg_temp.raid_join('r' || lpad(g::text, 2, '0'));
  end loop;
  select * into sec from public.circle_security where circle_id = c;
  perform pg_temp.expect(sec.lockdown_until is not null and sec.lockdown_source = 'auto' and sec.lockdown_joins = 8, 'requests: eight requests also trigger it');
  perform pg_temp.expect(sec.lockdown_prev_mode is null, 'requests: the circle already reviewed, so nothing to put back');
  perform pg_temp.expect((select count(*) from public.circle_join_requests where circle_id = c and status = 'pending' and user_id in (select pg_temp.uid('r' || n) from generate_series(12, 19) n)) = 8, 'requests: all eight wait for a moderator');
  perform pg_temp.act(pg_temp.i('kim'));
  perform public.end_circle_lockdown(c);
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_join_settings(c, 'open', '[]'::jsonb);
  perform pg_temp.root();
  update public.circle_join_requests set created_at = now() - interval '5 minutes' where circle_id = c;
  update public.circle_members set created_at = now() - interval '5 minutes' where circle_id = c and created_at > now() - interval '4 minutes' and role <> 'owner';
end $$;

do $$
declare
  c uuid := pg_temp.i('circle');
  g integer;
  sec public.circle_security%rowtype;
begin
  -- New accounts count double: with a threshold of 12, six brand-new accounts
  -- (half of it, and at least 5) are enough.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_raid_settings(c, true, 12, 24);
  perform pg_temp.root();
  for g in 31..35 loop
    perform pg_temp.raid_join('r' || g);
  end loop;
  perform pg_temp.expect((select lockdown_until is null from public.circle_security where circle_id = c), 'accounts: five new accounts are not enough');
  perform pg_temp.raid_join('r36');
  select * into sec from public.circle_security where circle_id = c;
  perform pg_temp.expect(sec.lockdown_until is not null and sec.lockdown_new_accounts = 6 and sec.lockdown_joins = 6, 'accounts: six new accounts lock the circle');
  perform pg_temp.expect(sec.lockdown_until > now() + interval '23 hours', 'accounts: for the 24 hours the circle chose');
  perform pg_temp.act(pg_temp.i('kim'));
  perform public.end_circle_lockdown(c);
  perform pg_temp.root();
  update public.circle_members set created_at = now() - interval '5 minutes' where circle_id = c and created_at >= now() and role <> 'owner';

  -- Switched off: a flood of joins is just a flood.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_raid_settings(c, false, 5, 1);
  perform pg_temp.root();
  for g in 20..29 loop
    perform pg_temp.raid_join('r' || lpad(g::text, 2, '0'));
  end loop;
  for g in 37..40 loop
    perform pg_temp.raid_join('r' || g);
  end loop;
  perform pg_temp.expect((select lockdown_until is null from public.circle_security where circle_id = c), 'off: fourteen joins, no lockdown');
  perform pg_temp.expect((select join_mode from public.circles where id = c) = 'open', 'off: still open');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_raid_settings(c, true, 20, 1);
  perform pg_temp.root();

  -- A circle under an hour old is left alone: creating one adds people in a
  -- burst. After the hour the same numbers count.
  perform pg_temp.act(pg_temp.i('ada'));
  insert into pg_temp.ids select 'young', public.create_circle('Young club', array[pg_temp.i('bob'), pg_temp.i('mia'), pg_temp.i('sam'), pg_temp.i('kim'), pg_temp.i('cy'), pg_temp.i('dee')]);
  perform public.set_circle_discovery(pg_temp.i('young'), true, 'young', 'other', 'en', '{}'::text[]);
  perform pg_temp.root();
  perform public.ensure_circle_security(pg_temp.i('young'));
  update public.circle_security set raid_threshold = 3 where circle_id = pg_temp.i('young');
  for g in 1..4 loop
    perform pg_temp.act(pg_temp.uid('r' || lpad(g::text, 2, '0')));
    perform public.join_public_circle(pg_temp.i('young'));
  end loop;
  perform pg_temp.root();
  perform pg_temp.expect((select lockdown_until is null from public.circle_security where circle_id = pg_temp.i('young')), 'young: a circle under an hour old is not locked down');
  update public.circles set created_at = now() - interval '2 hours' where id = pg_temp.i('young');
  perform pg_temp.act(pg_temp.uid('r05'));
  perform public.join_public_circle(pg_temp.i('young'));
  perform pg_temp.root();
  perform pg_temp.expect((select lockdown_until is not null from public.circle_security where circle_id = pg_temp.i('young')), 'young: an hour later the same flood counts');

  -- A circle a platform admin took down is not locked by a burst.
  perform pg_temp.root();
  perform pg_temp.expect(not public.circle_raid_check(pg_temp.i('circle')), 'check: nothing to lock again');
  update public.circles set disabled_at = now(), disabled_mode = 'delist' where id = pg_temp.i('young');
  update public.circle_security set lockdown_until = null, lockdown_prev_mode = null where circle_id = pg_temp.i('young');
  perform pg_temp.expect(not public.circle_raid_check(pg_temp.i('young')), 'check: a taken-down circle is left alone');
  update public.circles set disabled_at = null, disabled_mode = null where id = pg_temp.i('young');
end $$;

-- ===================================== 9. pushes
do $$
declare
  c uuid := pg_temp.i('circle');
  n integer;
  who text;
begin
  -- Devices: Ada, Mia, Kim and Bob for the moderators' alert, Eve for her appeals.
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
  select pg_temp.i(w), 'https://push.example/' || w, repeat('p', 60), repeat('a', 20), case when w = 'mia' then 'zh' else 'en' end
  from unnest(array['ada', 'mia', 'kim', 'bob', 'eve', 'sam']) w;

  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.state('select * from public.claim_moderation_pushes()') = '42501', 'push: not callable by a member');
  perform pg_temp.root();

  -- Alerts: automatic lockdowns only (three of them so far in the main circle
  -- and one in the young circle); to the owner and the members whose roles can
  -- review members (Mia, Sam and Kim), not to Bob.
  create temp table claimed on commit drop as select * from public.claim_moderation_pushes();
  perform pg_temp.expect((select count(*) from claimed where tag like 'raid-%' and url = '/#/circles/' || c::text) = 3 * 4, 'push: three alerts for four devices (Ada, Mia, Sam, Kim) in the main circle');
  perform pg_temp.expect(not exists (select 1 from claimed cl join public.push_subscriptions s on s.id = cl.subscription_id where cl.tag like 'raid-%' and s.user_id = pg_temp.i('bob')), 'push: a plain member hears nothing');
  perform pg_temp.expect((select count(*) from claimed where tag like 'raid-%' and url = '/#/circles/' || pg_temp.i('young')::text) = 1, 'push: the young circle''s alert goes to its owner only');
  perform pg_temp.expect(exists (select 1 from claimed cl join public.push_subscriptions s on s.id = cl.subscription_id where cl.tag like 'raid-%' and s.user_id = pg_temp.i('mia') and cl.title = '突袭防护已启动'), 'push: in the device''s language');
  perform pg_temp.expect(exists (select 1 from claimed cl join public.push_subscriptions s on s.id = cl.subscription_id where cl.tag like 'raid-%' and s.user_id = pg_temp.i('kim') and cl.title = 'Raid protection is on' and cl.body like 'Mod club had 8 people%'), 'push: and the English one says how many');
  -- Appeals: the two denials and the approval, to Eve (two of them) and Fay,
  -- who has no device here.
  perform pg_temp.expect((select count(*) from claimed cl join public.push_subscriptions s on s.id = cl.subscription_id where cl.tag like 'ban-appeal-%' and s.user_id = pg_temp.i('eve')) = 2, 'push: Eve hears about both of her appeals');
  perform pg_temp.expect(exists (select 1 from claimed where title = 'Ban appeal approved') and exists (select 1 from claimed where title = 'Ban appeal declined' and body like '%not yet%'), 'push: approved and declined, with the note');
  perform pg_temp.expect(not exists (select 1 from claimed where tag like 'raid-%' and url <> '/#/circles/' || c::text and url <> '/#/circles/' || pg_temp.i('young')::text), 'push: alerts open the circle');
  -- Claimed once.
  select count(*) into n from public.claim_moderation_pushes();
  perform pg_temp.expect(n = 0, 'push: nothing is pushed twice');
  perform pg_temp.expect(not exists (select 1 from public.circle_raid_events where kind = 'lockdown' and source = 'auto' and push_claimed_at is null), 'push: every automatic lockdown is claimed');
  perform pg_temp.expect(exists (select 1 from public.circle_raid_events where kind = 'lockdown' and source = 'manual' and push_claimed_at is null), 'push: manual lockdowns are not pushed');
end $$;

-- ===================================== 10. the check waits for the commit
do $$
declare
  d uuid;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  d := public.create_circle('Deferred club', array[pg_temp.i('bob')]);
  perform pg_temp.root();
  update public.circles set created_at = now() - interval '2 hours' where id = d;
  update public.circle_members set created_at = now() - interval '2 hours' where circle_id = d;
  perform public.ensure_circle_security(d);
  update public.circle_security set raid_threshold = 3 where circle_id = d;
  insert into pg_temp.ids values ('deferred', d);
end $$;

-- Like a real request: the triggers wait for COMMIT. Four friends are added by
-- one call; none is turned away halfway, and then the circle locks.
set constraints all deferred;
do $$
declare
  d uuid := pg_temp.i('deferred');
begin
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.invite_circle_members(d, array[pg_temp.i('ivy'), pg_temp.i('hal'), pg_temp.i('cy'), pg_temp.i('dee')]);
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_members where circle_id = d and user_id in (pg_temp.i('ivy'), pg_temp.i('hal'), pg_temp.i('cy'), pg_temp.i('dee'))) = 4, 'deferred: all four friends came in');
  perform pg_temp.expect((select lockdown_until is null from public.circle_security where circle_id = d), 'deferred: nothing locked before the commit');
  perform pg_temp.expect((select join_mode from public.circles where id = d) = 'open', 'deferred: still open');
end $$;
set constraints all immediate;
do $$
declare
  d uuid := pg_temp.i('deferred');
begin
  perform pg_temp.expect((select lockdown_until is not null and lockdown_joins = 4 from public.circle_security where circle_id = d), 'deferred: at the commit the four count and the circle locks');
  perform pg_temp.expect((select join_mode from public.circles where id = d) = 'apply', 'deferred: and now reviews who joins');
end $$;
\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'mod tools: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
