-- Behaviour checks for circle join requests (C1: migrations 202610220600 to
-- 202610220630). Run by test/supabase/join_requests_test.dart against the
-- local database: it applies the migrations it needs in a transaction, plays
-- people through the RPCs, and rolls everything back. Run from the repository
-- root.
--
-- What it walks through: every join path in each join mode (accept_circle_invite
-- for links and the 7-day contact card, join_public_circle, invite_circle_members),
-- the "skip review" exemption and who may use it, the guard trigger that
-- refuses a forgotten path, approve and deny with the audit log and the push
-- claim, bans and take-downs still blocking, questions and answers, and who
-- can read what.
\set ON_ERROR_STOP on

begin;

do $$ begin perform pg_advisory_xact_lock(20261017); end $$;
set local client_min_messages = warning;

-- Every migration after the local baseline (202610140001), in order, so the
-- script runs on a freshly reset local database.
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
-- Ada owns the circle. Mia moderates (the Mod role has kick_members; every
-- member has create_invites from @everyone, so Mia has both and may skip
-- review). Bob is an ordinary member (create_invites only). Applicants:
-- cy, dee, eve, fay, gus, hal, ian, jay, kay, lee, ned, oli. Ada's friends:
-- bob, mia, gus, ian. Bob's friend: hal. Mia's friends: oli, kay.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '@jr.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from (values ('a1','ada'),('a2','mia'),('a3','bob'),('c1','cy'),('d1','dee'),('e1','eve'),('f1','fay'),
  ('a4','gus'),('b4','hal'),('c4','ian'),('d4','jay'),('e4','kay'),('f4','lee'),('a5','ned'),('b5','oli')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '_jr', initcap(name)
from (values ('a1','ada'),('a2','mia'),('a3','bob'),('c1','cy'),('d1','dee'),('e1','eve'),('f1','fay'),
  ('a4','gus'),('b4','hal'),('c4','ian'),('d4','jay'),('e4','kay'),('f4','lee'),('a5','ned'),('b5','oli')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || n)::uuid
from (values ('a1','ada'),('a2','mia'),('a3','bob'),('c1','cy'),('d1','dee'),('e1','eve'),('f1','fay'),
  ('a4','gus'),('b4','hal'),('c4','ian'),('d4','jay'),('e4','kay'),('f4','lee'),('a5','ned'),('b5','oli')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(x.a, x.b), greatest(x.a, x.b)
from (values
  (pg_temp.i('ada'), pg_temp.i('bob')),
  (pg_temp.i('ada'), pg_temp.i('mia')),
  (pg_temp.i('ada'), pg_temp.i('gus')),
  (pg_temp.i('ada'), pg_temp.i('ian')),
  (pg_temp.i('bob'), pg_temp.i('hal')),
  (pg_temp.i('bob'), pg_temp.i('ian')),
  (pg_temp.i('mia'), pg_temp.i('oli')),
  (pg_temp.i('mia'), pg_temp.i('kay')),
  (pg_temp.i('mia'), pg_temp.i('gus')),
  (pg_temp.i('mia'), pg_temp.i('lee'))
) x(a, b);

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'circle', public.create_circle('Join club', array[pg_temp.i('bob'), pg_temp.i('mia')]);
select public.set_circle_discovery(pg_temp.i('circle'), true, 'about the club', 'other', 'en', '{}'::text[]);
insert into pg_temp.ids select 'modrole', public.create_circle_role(pg_temp.i('circle'), 'Mod', null, 32, false);
select public.set_member_roles(pg_temp.i('circle'), pg_temp.i('mia'), array[pg_temp.i('modrole')]);
-- A private circle nobody can find.
insert into pg_temp.ids select 'secret', public.create_circle('Secret club', array[pg_temp.i('bob')]);
select pg_temp.root();

-- ===================================== 0. open mode: nothing changes
do $$
declare c uuid := pg_temp.i('circle'); inv text;
begin
  perform pg_temp.expect((select join_mode from public.circles where id = c) = 'open', 'a new circle is open');
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(public.join_public_circle(c) = c, 'open: join_public_circle returns the circle');
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('cy')), 'open: Discover joins at once');
  perform pg_temp.expect(pg_temp.in_channel(c, pg_temp.i('cy')), 'open: and the channels');
  perform pg_temp.act(pg_temp.i('bob'));
  inv := public.create_circle_invite(c, null, null);
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('dee'));
  perform pg_temp.expect(public.accept_circle_invite(inv) = c, 'open: accept_circle_invite returns the circle');
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('dee')), 'open: an invite joins at once');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.invite_circle_members(c, array[pg_temp.i('hal')]);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('hal')), 'open: a member invite adds at once');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.circle_join_requests') = 0, 'open: no request was made');
  -- Leave again so the same people can apply later.
  delete from public.conversation_members m using public.circle_channels cc
    where cc.circle_id = c and m.conversation_id = cc.conversation_id
      and m.user_id in (pg_temp.i('cy'), pg_temp.i('dee'), pg_temp.i('hal'));
  delete from public.circle_members where circle_id = c
    and user_id in (pg_temp.i('cy'), pg_temp.i('dee'), pg_temp.i('hal'));
  delete from public.circle_public_joins;
end $$;

-- ===================================== 1. who sets the mode and the questions
do $$
declare c uuid := pg_temp.i('circle'); q jsonb;
begin
  q := jsonb_build_array(
    jsonb_build_object('kind', 'text', 'prompt', 'Why do you want to join?', 'required', true),
    jsonb_build_object('kind', 'choice', 'prompt', 'How did you find us?', 'options', jsonb_build_array('Friend', 'Search'), 'required', false));

  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_join_settings(%L, ''apply'', %L)', c, q)) = '42501', 'settings: a member cannot');
  perform pg_temp.expect(pg_temp.state(format('select public.get_circle_join_settings(%L)', c)) = '42501', 'settings: a member cannot read them');
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_join_settings(%L, ''apply'', %L)', c, q)) = '42501', 'settings: a moderator without manage_circle cannot');
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_join_settings(%L, ''apply'', %L)', c, q)) = '42501', 'settings: an outsider cannot');
  perform pg_temp.act(null);
  perform pg_temp.must_refuse(format('select public.set_circle_join_settings(%L, ''apply'', %L)', c, q), 'settings: nobody signed in cannot');
  perform pg_temp.must_refuse(format('select public.get_circle_join_state(%L)', c), 'state: nobody signed in cannot');

  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_join_settings(%L, ''closed'', ''[]'')', c)) = '22023', 'settings: unknown mode');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_join_settings(%L, ''apply'', %L)', c,
    (select jsonb_agg(jsonb_build_object('kind', 'text', 'prompt', 'q' || g)) from generate_series(1, 6) g))) = '22023', 'settings: at most 5 questions');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_join_settings(%L, ''apply'', %L)', c,
    jsonb_build_array(jsonb_build_object('kind', 'choice', 'prompt', 'x', 'options', jsonb_build_array('only one'))))) = '22023', 'settings: a choice needs two options');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_join_settings(%L, ''apply'', %L)', c,
    jsonb_build_array(jsonb_build_object('kind', 'essay', 'prompt', 'x')))) = '22023', 'settings: unknown question type');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_join_settings(%L, ''apply'', %L)', c,
    jsonb_build_array(jsonb_build_object('kind', 'text', 'prompt', '   ')))) = '22023', 'settings: an empty question');
  perform pg_temp.expect((select join_mode from public.circles where id = c) = 'open', 'settings: refused calls changed nothing');

  perform public.set_circle_join_settings(c, 'apply', q);
  perform pg_temp.root();
  perform pg_temp.expect((select join_mode from public.circles where id = c) = 'apply', 'settings: the mode is saved');
  perform pg_temp.expect((select count(*) from public.circle_join_questions where circle_id = c) = 2, 'settings: both questions are saved');
  perform pg_temp.expect(
    (select action from public.circle_audit_log where circle_id = c and action = 'join_settings_update') = 'join_settings_update',
    'settings: audited');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(jsonb_array_length(public.get_circle_join_settings(c) -> 'questions') = 2, 'settings: a manager reads them');
  -- No change, no second audit entry.
  perform public.set_circle_join_settings(c, 'apply', public.get_circle_join_settings(c) -> 'questions');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = c and action = 'join_settings_update') = 1,
    'settings: saving the same thing is not logged again');
  insert into pg_temp.ids select 'q_text', (public.circle_join_questions_json(c) -> 0 ->> 'id')::uuid;
  insert into pg_temp.ids select 'q_choice', (public.circle_join_questions_json(c) -> 1 ->> 'id')::uuid;
end $$;

-- ===================================== 2. Discover (join_public_circle) in apply mode
do $$
declare c uuid := pg_temp.i('circle'); answers jsonb; stored jsonb;
begin
  perform pg_temp.act(pg_temp.i('dee'));
  -- The state tells the app what to ask.
  perform pg_temp.expect(public.get_circle_join_state(c) ->> 'join_mode' = 'apply', 'state: apply');
  perform pg_temp.expect(jsonb_array_length(public.get_circle_join_state(c) -> 'questions') = 2, 'state: the questions are shown to an applicant');
  perform pg_temp.expect(pg_temp.state(format('select public.join_public_circle(%L)', c)) = '22023', 'public: a required question left unanswered');
  perform pg_temp.expect(pg_temp.state(format('select public.join_public_circle(%L, %L)', c,
    jsonb_build_array(jsonb_build_object('question_id', pg_temp.i('q_text'), 'answer', 'x'),
      jsonb_build_object('question_id', pg_temp.i('q_choice'), 'answer', 'Billboard')))) = '22023', 'public: a choice outside the options');
  perform pg_temp.expect(pg_temp.state(format('select public.join_public_circle(%L, %L)', c,
    jsonb_build_array(jsonb_build_object('question_id', pg_temp.i('q_text'), 'answer', repeat('x', 501))))) = '22023', 'public: an answer over 500 characters');
  answers := jsonb_build_array(
    jsonb_build_object('question_id', pg_temp.i('q_text'), 'answer', '  I like clubs  '),
    jsonb_build_object('question_id', gen_random_uuid(), 'answer', 'ignored'));
  perform pg_temp.expect(public.join_public_circle(c, answers) = c, 'public: returns the circle id');
  perform pg_temp.root();
  perform pg_temp.expect(not pg_temp.is_member(c, pg_temp.i('dee')), 'public: not a member');
  perform pg_temp.expect(not pg_temp.in_channel(c, pg_temp.i('dee')), 'public: not in a channel');
  perform pg_temp.expect(pg_temp.pending(c, pg_temp.i('dee')) = 1, 'public: a request waits');
  select r.answers into stored from public.circle_join_requests r where r.user_id = pg_temp.i('dee');
  perform pg_temp.expect(jsonb_array_length(stored) = 1 and stored -> 0 ->> 'answer' = 'I like clubs'
    and stored -> 0 ->> 'prompt' = 'Why do you want to join?', 'public: the answer is kept with its question, trimmed, and stray answers dropped');
  perform pg_temp.act(pg_temp.i('dee'));
  perform pg_temp.expect(public.join_public_circle(c, answers) = c, 'public: asking again is fine');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.pending(c, pg_temp.i('dee')) = 1, 'public: still one request');
  perform pg_temp.act(pg_temp.i('dee'));
  perform pg_temp.expect(public.get_circle_join_state(c) -> 'request' ->> 'status' = 'pending', 'state: pending');
  perform pg_temp.expect(not (public.get_circle_join_state(c) ->> 'is_member')::boolean, 'state: not a member');
  perform pg_temp.root();
  -- The application costs a join of the hourly allowance? No: only real joins count.
  perform pg_temp.expect((select count(*) from public.circle_public_joins where user_id = pg_temp.i('dee')) = 0, 'public: a request is not a join');
end $$;

-- ===================================== 3. invite links in apply mode
do $$
declare c uuid := pg_temp.i('circle'); inv text; uses integer;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  inv := public.create_circle_invite(c, null, 5);
  perform pg_temp.root();
  perform set_config('wecord.test_code', inv, true);

  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(public.get_circle_join_state(c, inv) ->> 'join_mode' = 'apply', 'invite: the state is readable with the code');
  perform pg_temp.expect(pg_temp.state(format('select public.accept_circle_invite(%L)', inv)) = '22023', 'invite: required question unanswered');
  perform pg_temp.expect(public.accept_circle_invite(inv,
    jsonb_build_array(jsonb_build_object('question_id', pg_temp.i('q_text'), 'answer', 'a friend sent me'),
      jsonb_build_object('question_id', pg_temp.i('q_choice'), 'answer', 'Friend'))) = c, 'invite: returns the circle');
  perform pg_temp.root();
  perform pg_temp.expect(not pg_temp.is_member(c, pg_temp.i('eve')), 'invite: not a member');
  perform pg_temp.expect(not pg_temp.in_channel(c, pg_temp.i('eve')), 'invite: not in a channel');
  perform pg_temp.expect(pg_temp.pending(c, pg_temp.i('eve')) = 1, 'invite: a request waits');
  select use_count into uses from public.circle_invites where circle_invites.code = current_setting('wecord.test_code');
  perform pg_temp.expect(uses = 1, 'invite: the use is spent for the request');
  perform pg_temp.act(pg_temp.i('eve'));
  perform public.accept_circle_invite(inv);
  perform pg_temp.root();
  select use_count into uses from public.circle_invites where circle_invites.code = current_setting('wecord.test_code');
  perform pg_temp.expect(uses = 1, 'invite: a second try does not spend another use');
  perform pg_temp.expect((select jsonb_array_length(answers) from public.circle_join_requests where user_id = pg_temp.i('eve')) = 2, 'invite: both answers kept');

  -- An invite that no longer works is still invalid in apply mode.
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.revoke_circle_invite(inv);
  perform pg_temp.act(pg_temp.i('fay'));
  perform pg_temp.expect(pg_temp.state(format('select public.accept_circle_invite(%L)', inv)) = '22023', 'invite: a revoked invite is still refused');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.pending(c, pg_temp.i('fay')) = 0, 'invite: and makes no request');
end $$;

-- ===================================== 4. the 7-day contact card
do $$
declare c uuid := pg_temp.i('circle'); dm uuid; message uuid; inv text; skip boolean;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  dm := public.get_or_create_direct_conversation(pg_temp.i('gus'));
  message := public.send_contact_card(dm, 'circle', c);
  perform pg_temp.root();
  select m.attachment ->> 'invite_code' into inv from public.messages m where m.id = message;
  perform pg_temp.expect(inv is not null, 'card: carries an invite code');
  perform pg_temp.expect((select not skip_review from public.circle_invites where circle_invites.code = inv), 'card: the invite does not skip review');
  perform pg_temp.act(pg_temp.i('gus'));
  perform public.accept_circle_invite(inv, jsonb_build_array(jsonb_build_object('question_id', pg_temp.i('q_text'), 'answer', 'from the card')));
  perform pg_temp.root();
  perform pg_temp.expect(not pg_temp.is_member(c, pg_temp.i('gus')), 'card: following it does not join');
  perform pg_temp.expect(pg_temp.pending(c, pg_temp.i('gus')) = 1, 'card: it makes a request');
end $$;

-- ===================================== 5. member invites in apply mode
do $$
declare c uuid := pg_temp.i('circle'); adds_before integer;
begin
  -- Bob: create_invites only, so his friend becomes a request.
  select count(*) into adds_before from public.circle_audit_log where circle_id = c and action = 'member_add';
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.invite_circle_members(c, array[pg_temp.i('hal')]);
  perform pg_temp.root();
  perform pg_temp.expect(not pg_temp.is_member(c, pg_temp.i('hal')), 'member invite: a plain member only requests');
  perform pg_temp.expect(pg_temp.pending(c, pg_temp.i('hal')) = 1, 'member invite: the friend has a request');
  perform pg_temp.expect((select invited_by from public.circle_join_requests where user_id = pg_temp.i('hal')) = pg_temp.i('bob'), 'member invite: it names who invited');
  perform pg_temp.expect(not pg_temp.in_channel(c, pg_temp.i('hal')), 'member invite: not in a channel');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = c and action = 'member_add') = adds_before, 'member invite: no member_add entry for a request');
  -- Twice is the same request.
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.invite_circle_members(c, array[pg_temp.i('hal')]);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.pending(c, pg_temp.i('hal')) = 1, 'member invite: asking twice keeps one request');
  -- Not a friend: still refused as before.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.invite_circle_members(%L, array[%L::uuid])', c, pg_temp.i('lee'))) = '42501', 'member invite: a stranger is refused as before');
  perform pg_temp.root();

  -- Mia (create_invites + kick_members): in at once. So does the owner.
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.invite_circle_members(c, array[pg_temp.i('oli')]);
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.invite_circle_members(c, array[pg_temp.i('ian')]);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('oli')) and pg_temp.in_channel(c, pg_temp.i('oli')), 'member invite: a moderator who may skip review adds directly');
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('ian')) and pg_temp.in_channel(c, pg_temp.i('ian')), 'member invite: so does the owner');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = c and action = 'member_add') = adds_before + 2, 'member invite: those are audited as before');
  perform pg_temp.expect(pg_temp.pending(c, pg_temp.i('oli')) = 0, 'member invite: no request for them');
end $$;

-- ===================================== 6. invites that skip review
do $$
declare c uuid := pg_temp.i('circle'); inv text; plain text; dm uuid; message uuid; card_code text;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.create_circle_invite(%L, null, null, true)', c)) = '42501',
    'skip review: a member with create_invites only cannot');
  plain := public.create_circle_invite(c, null, null, false);
  perform pg_temp.expect((select not skip_review from public.circle_invites where circle_invites.code = plain), 'skip review: false is an ordinary invite');
  perform pg_temp.expect(public.list_circle_invites_skipping_review(c) = '{}', 'skip review: nothing listed yet');
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.must_refuse(format('select public.create_circle_invite(%L, null, null, true)', c), 'skip review: an outsider cannot');
  perform pg_temp.act(pg_temp.i('mia'));
  inv := public.create_circle_invite(c, 168, null, true);
  perform pg_temp.expect(public.list_circle_invites_skipping_review(c) = array[inv], 'skip review: listed');
  perform pg_temp.root();
  perform pg_temp.expect((select skip_review from public.circle_invites where circle_invites.code = inv), 'skip review: marked');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = c and action = 'invite_skip_review') = 1, 'skip review: audited');

  -- Jay arrives by Mia's invite: straight in, no questions.
  perform pg_temp.act(pg_temp.i('jay'));
  perform pg_temp.expect(public.get_circle_join_state(c, inv) ->> 'skip_review' = 'true', 'skip review: the state says so');
  perform pg_temp.expect(jsonb_array_length(public.get_circle_join_state(c, inv) -> 'questions') = 0, 'skip review: no questions');
  perform public.accept_circle_invite(inv);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('jay')) and pg_temp.in_channel(c, pg_temp.i('jay')), 'skip review: joined with the channels');
  perform pg_temp.expect(pg_temp.pending(c, pg_temp.i('jay')) = 0, 'skip review: no request');
  perform pg_temp.expect((select use_count from public.circle_invites where circle_invites.code = inv) = 1, 'skip review: the use is spent');

  -- Mia's contact card must not reuse her skip-review invite.
  perform pg_temp.act(pg_temp.i('mia'));
  dm := public.get_or_create_direct_conversation(pg_temp.i('kay'));
  message := public.send_contact_card(dm, 'circle', c);
  perform pg_temp.root();
  select m.attachment ->> 'invite_code' into card_code from public.messages m where m.id = message;
  perform pg_temp.expect(card_code is not null and card_code <> inv, 'skip review: a card never reuses it');
  perform pg_temp.expect((select not skip_review from public.circle_invites where circle_invites.code = card_code), 'skip review: the card invite reviews');
  perform pg_temp.act(pg_temp.i('kay'));
  perform public.accept_circle_invite(card_code, jsonb_build_array(jsonb_build_object('question_id', pg_temp.i('q_text'), 'answer', 'card')));
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.pending(c, pg_temp.i('kay')) = 1 and not pg_temp.is_member(c, pg_temp.i('kay')), 'skip review: so the card makes a request');

  -- The exemption ends when the creator loses a permission.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_member_roles(c, pg_temp.i('mia'), array[]::uuid[]);
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('lee'));
  perform pg_temp.expect(public.get_circle_join_state(c, inv) ->> 'skip_review' = 'false', 'skip review: the state follows the creator''s permissions');
  perform public.accept_circle_invite(inv, jsonb_build_array(jsonb_build_object('question_id', pg_temp.i('q_text'), 'answer', 'late')));
  perform pg_temp.root();
  perform pg_temp.expect(not pg_temp.is_member(c, pg_temp.i('lee')) and pg_temp.pending(c, pg_temp.i('lee')) = 1,
    'skip review: an invite whose creator lost kick_members now reviews');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_member_roles(c, pg_temp.i('mia'), array[pg_temp.i('modrole')]);
  perform pg_temp.root();
end $$;

-- ===================================== 7. the guard refuses a forgotten path
do $$
declare c uuid := pg_temp.i('circle'); bot uuid := gen_random_uuid(); s text;
begin
  -- A signed-in person's statement, as a SECURITY DEFINER function sees it.
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.root();
  s := format('insert into public.circle_members (circle_id, user_id, role) values (%L, %L, ''member'')', c, pg_temp.i('cy'));
  perform pg_temp.expect(pg_temp.msg(s) = 'This circle reviews who joins', 'guard: a path that forgot the mode is refused');
  perform pg_temp.expect(not pg_temp.is_member(c, pg_temp.i('cy')), 'guard: nothing was added');
  -- The flag is for one circle only.
  perform public.allow_circle_join(pg_temp.i('secret'));
  perform pg_temp.expect(pg_temp.msg(s) = 'This circle reviews who joins', 'guard: the bypass is for one circle only');
  perform public.close_circle_join();
  -- A bot added by a manager is not held back.
  insert into auth.users (id, email, instance_id, aud, role) values (bot, 'bot@jr.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
  insert into public.profiles (id, username, display_name, is_bot) values (bot, 'bot_jr_test', 'Bot', true);
  perform pg_temp.expect(pg_temp.state(format('insert into public.circle_members (circle_id, user_id, role, rules_accepted_at) values (%L, %L, ''member'', now())', c, bot)) = 'ok',
    'guard: bots are not held back');
  -- No signed-in person (service role, migrations): not held back.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  perform pg_temp.expect(pg_temp.state(format('insert into public.circle_members (circle_id, user_id, role) values (%L, %L, ''member'')', c, pg_temp.i('cy'))) = 'ok',
    'guard: statements without a signed-in person are not held back');
  delete from public.circle_members where circle_id = c and user_id in (pg_temp.i('cy'), bot);
  -- A client cannot write the table at all.
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.must_refuse(format('insert into public.circle_members (circle_id, user_id, role) values (%L, %L, ''member'')', c, pg_temp.i('cy')), 'guard: no direct insert by a client');
  perform pg_temp.must_refuse('select public.allow_circle_join(' || quote_literal(c) || ')', 'guard: the bypass is not a client function');
  perform pg_temp.must_refuse('select public.circle_members_require_join_review()', 'guard: the trigger function is not a client function');
  perform pg_temp.must_refuse('select public.submit_circle_join_request(' || quote_literal(c) || ', ' || quote_literal(pg_temp.i('cy')) || ')', 'guard: submit is not a client function');
  perform pg_temp.root();
end $$;

-- ===================================== 8. invite only
do $$
declare c uuid := pg_temp.i('circle'); inv text;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_join_settings(c, 'invite_only', '[]'::jsonb);
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(pg_temp.msg(format('select public.join_public_circle(%L)', c)) = 'This circle is invite only', 'invite only: Discover is closed');
  perform pg_temp.expect(public.get_circle_join_state(c) ->> 'join_mode' = 'invite_only', 'invite only: the state says so');
  perform pg_temp.root();
  perform pg_temp.expect(not pg_temp.is_member(c, pg_temp.i('cy')) and pg_temp.pending(c, pg_temp.i('cy')) = 0, 'invite only: nothing happened');
  perform pg_temp.act(pg_temp.i('bob'));
  inv := public.create_circle_invite(c, null, null);
  perform pg_temp.act(pg_temp.i('cy'));
  perform public.accept_circle_invite(inv);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('cy')) and pg_temp.in_channel(c, pg_temp.i('cy')), 'invite only: an invite link is the way in');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.invite_circle_members(c, array[pg_temp.i('hal')]);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('hal')) and pg_temp.in_channel(c, pg_temp.i('hal')), 'invite only: so is a member invite');
  -- Hal's request from before stays in the queue; clean up for later.
  update public.circle_join_requests set status = 'denied', decided_at = now() - interval '3 days', decided_by = pg_temp.i('ada')
    where user_id = pg_temp.i('hal');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_join_settings(c, 'apply', jsonb_build_array(
    jsonb_build_object('id', pg_temp.i('q_text'), 'kind', 'text', 'prompt', 'Why do you want to join?', 'required', true)));
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_join_questions where circle_id = c) = 1, 'settings: dropping a question');
  -- Cy leaves again.
  delete from public.conversation_members m using public.circle_channels cc
    where cc.circle_id = c and m.conversation_id = cc.conversation_id and m.user_id = pg_temp.i('cy');
  delete from public.circle_members where circle_id = c and user_id = pg_temp.i('cy');
end $$;

-- ===================================== 9. who may read and decide
do $$
declare c uuid := pg_temp.i('circle'); listed jsonb;
begin
  -- Waiting: dee, eve, gus, kay, lee.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(public.count_join_requests(c) = 0, 'queue: a member without kick_members sees a count of 0');
  perform pg_temp.expect(pg_temp.state(format('select public.list_join_requests(%L)', c)) = '42501', 'queue: and cannot list');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.circle_join_requests') = 0, 'queue: nor read the table');
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(public.count_join_requests(c) = 0, 'queue: an outsider sees 0');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.circle_join_requests') = 0, 'queue: an outsider reads no requests');
  perform pg_temp.act(pg_temp.i('dee'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.circle_join_requests') = 1, 'queue: an applicant reads only their own');
  perform pg_temp.must_refuse(format('select public.decide_join_request(%L, true)', (select id from public.circle_join_requests where user_id = pg_temp.i('dee'))), 'queue: an applicant cannot approve themself');
  perform pg_temp.must_refuse(format('select public.decide_join_request(%L, false)', (select id from public.circle_join_requests where user_id = pg_temp.i('eve'))), 'queue: or anyone else''s');
  perform pg_temp.must_refuse('update public.circle_join_requests set status = ''approved''', 'queue: a client cannot write the table');
  perform pg_temp.must_refuse('delete from public.circle_join_requests', 'queue: or delete from it');
  perform pg_temp.must_refuse('insert into public.circle_join_requests (circle_id, user_id) values (' || quote_literal(c) || ', ' || quote_literal(pg_temp.i('dee')) || ')', 'queue: or insert');
  perform pg_temp.must_refuse('select 1 from public.circle_join_questions', 'queue: questions are read through the RPCs only');
  perform pg_temp.act(null);
  perform pg_temp.must_refuse(format('select public.count_join_requests(%L)', c), 'queue: nobody signed in');
  perform pg_temp.must_refuse(format('select public.decide_join_request(%L, true)', gen_random_uuid()), 'queue: nobody signed in cannot decide');

  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(public.count_join_requests(c) = 5, 'queue: a moderator counts the waiting requests');
  listed := public.list_join_requests(c);
  perform pg_temp.expect(jsonb_array_length(listed) = 5, 'queue: and lists them');
  perform pg_temp.expect((select count(*) from jsonb_array_elements(listed) e where e -> 'answers' -> 0 ->> 'answer' is not null) >= 3, 'queue: with their answers');
  perform pg_temp.expect((select e ->> 'username' from jsonb_array_elements(listed) e where e ->> 'username' = 'dee_jr') = 'dee_jr', 'queue: and who they are');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.circle_join_requests where status = ''pending''') = 5, 'queue: a moderator reads the table');
  perform pg_temp.root();

  -- A request in another circle does not leak.
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(public.get_circle_join_state(pg_temp.i('secret')) is null, 'state: a private circle is invisible to a stranger');
  perform pg_temp.root();
end $$;

-- ===================================== 10. approve and deny
do $$
declare c uuid := pg_temp.i('circle'); r_dee uuid; r_eve uuid; r_gus uuid; welcome jsonb; n integer; res jsonb;
begin
  select id into r_dee from public.circle_join_requests where user_id = pg_temp.i('dee') and status = 'pending';
  select id into r_eve from public.circle_join_requests where user_id = pg_temp.i('eve') and status = 'pending';
  select id into r_gus from public.circle_join_requests where user_id = pg_temp.i('gus') and status = 'pending';

  -- Onboarding: rules to accept and a welcome.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_onboarding(c, true, array['Be kind'], 'Welcome to the club');
  perform pg_temp.root();

  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.decide_join_request(%L, true)', r_dee)) = 'P0002', 'decide: a member without kick_members cannot approve');
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.state(format('select public.decide_join_request(%L, true, %L)', r_dee, repeat('n', 501))) = '22023', 'decide: a note is up to 500 characters');
  perform public.decide_join_request(r_dee, true);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('dee')), 'approve: the person is a member');
  perform pg_temp.expect(pg_temp.in_channel(c, pg_temp.i('dee')), 'approve: in the channels');
  perform pg_temp.expect((select role from public.circle_members where circle_id = c and user_id = pg_temp.i('dee')) = 'member', 'approve: an ordinary member');
  perform pg_temp.expect((select rules_accepted_at is null from public.circle_members where circle_id = c and user_id = pg_temp.i('dee')), 'approve: the rules are still to accept');
  perform pg_temp.expect(public.circle_member_needs_rules(c, pg_temp.i('dee')), 'approve: onboarding applies');
  perform pg_temp.expect((select created_at > now() - interval '1 minute' from public.circle_members where circle_id = c and user_id = pg_temp.i('dee')), 'approve: the membership starts now (the AI guard''s new member window)');
  perform pg_temp.expect((select status = 'approved' and decided_by = pg_temp.i('mia') and decided_at is not null from public.circle_join_requests where id = r_dee), 'approve: who and when');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = c and action = 'join_request_approve' and target_id = pg_temp.i('dee') and actor_id = pg_temp.i('mia')) = 1, 'approve: audited');
  perform pg_temp.act(pg_temp.i('dee'));
  welcome := public.accept_circle_rules(c);
  perform pg_temp.root();
  perform pg_temp.expect(welcome::text like '%Welcome to the club%', 'approve: then the rules, then the welcome message');
  perform pg_temp.expect(not public.circle_member_needs_rules(c, pg_temp.i('dee')), 'approve: and they can take part');
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.state(format('select public.decide_join_request(%L, false)', r_dee)) = '22023', 'decide: a request is decided once');

  -- Deny with a note.
  perform public.decide_join_request(r_eve, false, '  Not this time  ');
  perform pg_temp.root();
  perform pg_temp.expect(not pg_temp.is_member(c, pg_temp.i('eve')) and not pg_temp.in_channel(c, pg_temp.i('eve')), 'deny: not a member');
  perform pg_temp.expect((select status = 'denied' and note = 'Not this time' and decided_by = pg_temp.i('mia') from public.circle_join_requests where id = r_eve), 'deny: the note is kept');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = c and action = 'join_request_deny' and target_id = pg_temp.i('eve')) = 1, 'deny: audited');
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(public.count_join_requests(c) = 3, 'queue: the count went down');
  perform pg_temp.act(pg_temp.i('eve'));
  perform pg_temp.expect(public.get_circle_join_state(c) -> 'request' ->> 'status' = 'denied', 'state: denied');
  perform pg_temp.expect(public.get_circle_join_state(c) -> 'request' ->> 'note' = 'Not this time', 'state: the applicant reads the note');
  perform pg_temp.expect(public.get_circle_join_state(c) ->> 'retry_at' is not null, 'state: and when they can apply again');
  perform pg_temp.expect(pg_temp.state(format('select public.join_public_circle(%L, %L)', c,
    jsonb_build_array(jsonb_build_object('question_id', pg_temp.i('q_text'), 'answer', 'again')))) = 'PB429', 'deny: applying again the same day waits');
  perform pg_temp.root();
  update public.circle_join_requests set decided_at = now() - interval '25 hours' where id = r_eve;
  perform pg_temp.act(pg_temp.i('eve'));
  perform public.join_public_circle(c, jsonb_build_array(jsonb_build_object('question_id', pg_temp.i('q_text'), 'answer', 'again')));
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.pending(c, pg_temp.i('eve')) = 1, 'deny: after a day a new request is possible');

  -- A moderator cannot decide a request of another circle: Mia moderates
  -- Join club only.
  insert into public.circle_join_requests (circle_id, user_id) values (pg_temp.i('secret'), pg_temp.i('lee'));
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.state(format('select public.decide_join_request(%L, true)',
    (select id from public.circle_join_requests where circle_id = pg_temp.i('secret')))) = 'P0002', 'decide: not in another circle');
  perform pg_temp.root();
  delete from public.circle_join_requests where circle_id = pg_temp.i('secret');
end $$;

-- ===================================== 11. notifications: inbox and push
do $$
declare c uuid := pg_temp.i('circle'); rows_ jsonb; n integer; p record;
begin
  perform pg_temp.act(pg_temp.i('dee'));
  rows_ := public.list_my_join_requests();
  perform pg_temp.expect(jsonb_array_length(rows_) = 1 and rows_ -> 0 ->> 'status' = 'approved' and rows_ -> 0 ->> 'circle_name' = 'Join club', 'inbox: the applicant sees the approval');
  perform pg_temp.act(pg_temp.i('eve'));
  rows_ := public.list_my_join_requests();
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(rows_) e where e ->> 'status' = 'pending'), 'inbox: and a waiting request');
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(jsonb_array_length(public.list_my_join_requests()) = 0, 'inbox: others see nothing');
  perform pg_temp.root();

  -- Push: dee reads Chinese, eve English; fay has no device.
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
  values (pg_temp.i('dee'), 'https://push.test/dee', repeat('p', 60), repeat('a', 20), 'zh'),
         (pg_temp.i('eve'), 'https://push.test/eve', repeat('p', 60), repeat('a', 20), 'en'),
         (pg_temp.i('mia'), 'https://push.test/mia', repeat('p', 60), repeat('a', 20), 'en');
  -- Dee's approval was decided before the devices existed in this script; the
  -- claim still pays out for the subscriptions that exist now. Eve's first
  -- denial is what is left unclaimed (her second request is pending).
  select count(*) into n from public.claim_join_request_pushes() cl where cl.subscription_id is not null;
  perform pg_temp.expect(n = 1, 'push: one row per subscription of an applicant with a fresh decision (dee''s approval; the rest are older than 15 minutes and are closed without a push)');
  -- Claimed once.
  perform pg_temp.expect((select count(*) from public.claim_join_request_pushes()) = 0, 'push: claimed once');

  -- A fresh decision.
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.decide_join_request((select id from public.circle_join_requests where user_id = pg_temp.i('eve') and status = 'pending'), true);
  perform pg_temp.root();
  create temp table pushes_en on commit drop as select * from public.claim_join_request_pushes();
  perform pg_temp.expect((select count(*) from pg_temp.pushes_en) = 1, 'push: one device was told');
  for p in select * from pg_temp.pushes_en loop
    perform pg_temp.expect(p.endpoint = 'https://push.test/eve', 'push: only the applicant''s device');
    perform pg_temp.expect(p.title = 'Join request approved', 'push: English title');
    perform pg_temp.expect(p.body like 'You are in Join club, <t:%:f>.%', 'push: English body with a time token for the device''s zone');
    perform pg_temp.expect(p.url = '/#/circles/' || c::text, 'push: approval opens the circle');
    perform pg_temp.expect(p.tag like 'join-request-%', 'push: tagged per request');
  end loop;

  -- Chinese, with the note, and a circle name that tries to be a token.
  update public.circles set name = 'Join <t:1:f>club' where id = c;
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.decide_join_request((select id from public.circle_join_requests where user_id = pg_temp.i('gus') and status = 'pending'), false, 'Not enough detail');
  perform pg_temp.root();
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
  values (pg_temp.i('gus'), 'https://push.test/gus', repeat('p', 60), repeat('a', 20), 'zh');
  create temp table pushes_zh on commit drop as select * from public.claim_join_request_pushes();
  perform pg_temp.expect((select count(*) from pg_temp.pushes_zh) = 1, 'push: one Chinese device was told');
  for p in select * from pg_temp.pushes_zh loop
    perform pg_temp.expect(p.title = '入圈申请未通过', 'push: Chinese title');
    perform pg_temp.expect(p.body like '「Join t:1:fclub」没有通过你的申请，<t:%:f>。理由：Not enough detail', 'push: Chinese body, the note, and no stray time token from the name');
    perform pg_temp.expect(p.url = '/#/notifications', 'push: a denial opens Notifications');
  end loop;
  update public.circles set name = 'Join club' where id = c;

  -- Old decisions are closed without a push.
  update public.circle_join_requests set push_claimed_at = null, decided_at = now() - interval '1 hour'
    where user_id = pg_temp.i('dee');
  perform pg_temp.expect((select count(*) from public.claim_join_request_pushes()) = 0, 'push: a decision from an hour ago is not pushed');
  perform pg_temp.expect((select push_claimed_at is not null from public.circle_join_requests where user_id = pg_temp.i('dee')), 'push: and is closed');

  -- Only the service role may claim.
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.must_refuse('select * from public.claim_join_request_pushes()', 'push: a client cannot claim pushes');
  perform pg_temp.root();

  -- Dismissing a result.
  perform pg_temp.act(pg_temp.i('dee'));
  perform public.dismiss_join_request_result((select id from public.circle_join_requests where user_id = pg_temp.i('dee')));
  perform pg_temp.expect(jsonb_array_length(public.list_my_join_requests()) = 0, 'inbox: dismissed results go away');
  perform pg_temp.act(pg_temp.i('eve'));
  perform public.dismiss_join_request_result((select id from public.circle_join_requests where user_id = pg_temp.i('gus')));
  perform pg_temp.root();
  perform pg_temp.expect((select seen_at is null from public.circle_join_requests where user_id = pg_temp.i('gus')), 'inbox: nobody dismisses someone else''s');
end $$;

-- ===================================== 12. bans and take-downs still block
do $$
declare c uuid := pg_temp.i('circle'); r uuid; ban_code text; bob_code text; late uuid := pg_temp.i('lee');
begin
  -- Cancel.
  perform pg_temp.act(pg_temp.i('lee'));
  perform public.cancel_join_request(c);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.pending(c, pg_temp.i('lee')) = 0, 'cancel: the applicant can withdraw');

  -- Ned applies, is banned, and cannot be approved or apply again.
  perform pg_temp.act(pg_temp.i('ned'));
  perform public.join_public_circle(c, jsonb_build_array(jsonb_build_object('question_id', pg_temp.i('q_text'), 'answer', 'hi')));
  perform pg_temp.root();
  select id into r from public.circle_join_requests where user_id = pg_temp.i('ned') and status = 'pending';
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.ban_circle_member(c, pg_temp.i('ned'), 'spam', 0);
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.msg(format('select public.decide_join_request(%L, true)', r)) = 'Banned from this circle', 'ban: approving a banned person is refused');
  perform pg_temp.root();
  perform pg_temp.expect(not pg_temp.is_member(c, pg_temp.i('ned')), 'ban: and they are not in');
  perform pg_temp.expect((select status from public.circle_join_requests where id = r) = 'pending', 'ban: the request stays open for a moderator to deny');
  perform pg_temp.act(pg_temp.i('mia'));
  perform public.decide_join_request(r, false);
  perform pg_temp.act(pg_temp.i('ned'));
  perform pg_temp.expect(pg_temp.msg(format('select public.join_public_circle(%L, ''[]'')', c)) = 'Banned from this circle', 'ban: join_public_circle in apply mode says banned');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.val(format('select public.create_circle_invite(%L, null, null)', c)) not like 'ERR%', 'ban: (setup) invite');
  perform pg_temp.root();
  select circle_invites.code into ban_code from public.circle_invites where circle_id = c order by created_at desc limit 1;
  perform pg_temp.act(pg_temp.i('ned'));
  perform pg_temp.expect(pg_temp.msg(format('select public.accept_circle_invite(%L, ''[]'')', ban_code)) = 'Banned from this circle', 'ban: an invite in apply mode says banned');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.pending(c, pg_temp.i('ned')) = 0, 'ban: no new request');

  -- Take-down (delist): no requests and no approvals.
  perform pg_temp.act(pg_temp.i('oli'));
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('fay'));
  perform public.join_public_circle(c, jsonb_build_array(jsonb_build_object('question_id', pg_temp.i('q_text'), 'answer', 'before')));
  perform pg_temp.root();
  update public.circles set disabled_at = now(), disabled_mode = 'delist' where id = c;
  perform pg_temp.act(late);
  perform pg_temp.expect(pg_temp.msg(format('select public.join_public_circle(%L, %L)', c,
    jsonb_build_array(jsonb_build_object('question_id', pg_temp.i('q_text'), 'answer', 'x')))) = 'This circle is not accepting new members', 'take-down: no new request from Discover');
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(pg_temp.msg(format('select public.decide_join_request(%L, true)',
    (select id from public.circle_join_requests where user_id = pg_temp.i('fay') and status = 'pending'))) = 'This circle is not accepting new members', 'take-down: no approval');
  perform pg_temp.root();
  perform pg_temp.expect(not pg_temp.is_member(c, pg_temp.i('fay')), 'take-down: nobody got in');
  perform pg_temp.expect(pg_temp.pending(c, late) = 0, 'take-down: and no request was made');
  update public.circles set disabled_at = null, disabled_mode = null where id = c;

  -- Blocked users: an invite from someone who blocked you is not found.
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('bob'), pg_temp.i('hal'));
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.root();
  select circle_invites.code into bob_code from public.circle_invites where circle_id = c and created_by = pg_temp.i('bob') order by created_at desc limit 1;
  perform pg_temp.act(pg_temp.i('hal'));
  perform pg_temp.expect(bob_code is not null and pg_temp.state(format('select public.accept_circle_invite(%L, ''[]'')', bob_code)) = 'P0002',
    'blocks: a blocked person''s invite code is not found');
  perform pg_temp.root();
  delete from public.blocks;

  -- A member cannot be pushed through the queue twice and a member's own
  -- invite does nothing in apply mode.
  perform pg_temp.act(pg_temp.i('dee'));
  perform pg_temp.expect(public.join_public_circle(c, '[]') = c, 'member: joining a circle you are in just returns it');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.pending(c, pg_temp.i('dee')) = 0, 'member: and makes no request');
end $$;

-- ===================================== 13. back to open
do $$
declare c uuid := pg_temp.i('circle');
begin
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_join_settings(c, 'open', '[]'::jsonb);
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('hal'));
  perform public.join_public_circle(c);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.is_member(c, pg_temp.i('hal')), 'open again: Discover joins at once');
  perform pg_temp.act(pg_temp.i('mia'));
  perform pg_temp.expect(public.get_circle_join_state(c) ->> 'join_mode' = 'open', 'open again: the state');
  perform pg_temp.root();
  -- Pending requests survive and can still be decided.
  perform pg_temp.expect(exists (select 1 from public.circle_join_requests where status = 'pending' and circle_id = c), 'open again: leftovers are still in the queue');
  -- Settings kept the audit trail.
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = c and action = 'join_settings_update') >= 4, 'audit: every settings change is logged');
end $$;
\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'join requests: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
