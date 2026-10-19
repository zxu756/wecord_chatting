-- Behaviour checks for urgent messages and announcements that need a
-- confirmation (A7: migrations 202610240400 to 202610240460). Run by
-- test/supabase/urgent_test.dart against the local database: it applies every
-- migration the database lacks (the local baseline is 202610170001) inside a
-- transaction, acts as several people, and rolls back, so the database is left
-- as it was. Run from the repository root.
--
-- What it walks through: who can make a message urgent and for whom (own
-- messages, members only, not blocked, not turned off, bots excluded, at most
-- 10 people and 5 times in 24 hours), what stops it (deleted, expired, held
-- for review, the note to self), the waiting list and confirmations, the
-- sender's view, the first push and the one second push 10 minutes later in
-- each device's language (breaking through Do Not Disturb and mutes, but not
-- blocks, turn-offs, leaving or a deleted message), and the group
-- announcement that asks for a confirmation: counts, names for managers only,
-- reminders with their limit, pushes, and what a new text clears.
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
-- a Ada owns the group "Team"; 9 Zed is an admin; b Bo, c Cy, d Di are
-- members; f Fy is a bot in it; e Ed is not in it.
select pg_temp.new_user('a', 'ada');
select pg_temp.new_user('b', 'bo');
select pg_temp.new_user('c', 'cy');
select pg_temp.new_user('d', 'di');
select pg_temp.new_user('e', 'ed');
select pg_temp.new_user('f', 'fy');
select pg_temp.new_user('9', 'zed');
update public.profiles set is_bot = true where id = pg_temp.u('f');

insert into public.conversations (type, title, announcement)
values ('group', 'Team', 'Be on time') returning id \gset team_
insert into ids values ('team', :'team_id');
insert into public.conversation_members (conversation_id, user_id, role)
select :'team_id', pg_temp.u(w),
  case w when 'a' then 'owner' when '9' then 'admin' else 'member' end
from unnest(array['a', 'b', 'c', 'd', 'f', '9']) as w;

insert into ids select 'm1', pg_temp.say('a', 'team', 'The meeting moved to 3 pm');
insert into ids select 'by_bo', pg_temp.say('b', 'team', 'I brought cake');

-- ================================================================== urgent

select pg_temp.act_as('a');
select pg_temp.check('the sender makes a message urgent for two people',
  public.send_message_urgent(pg_temp.mid('m1'), array[pg_temp.u('b'), pg_temp.u('c')]) = 2);
select pg_temp.act_as(null);
select pg_temp.check('one action and two people are recorded',
  pg_temp.n('select 1 from public.message_urgents') = 1
  and pg_temp.n('select 1 from public.message_urgent_targets') = 2);

select pg_temp.act_as('b');
select pg_temp.refused('someone else cannot make the sender''s message urgent',
  format('select public.send_message_urgent(%L, array[%L::uuid])', pg_temp.mid('m1'), pg_temp.u('c')),
  '42501');
select pg_temp.act_as('a');
select pg_temp.refused('not someone else''s message either',
  format('select public.send_message_urgent(%L, array[%L::uuid])', pg_temp.mid('by_bo'), pg_temp.u('c')),
  '42501');
select pg_temp.refused('a person outside the conversation cannot be made urgent',
  format('select public.send_message_urgent(%L, array[%L::uuid])', pg_temp.mid('m1'), pg_temp.u('e')),
  '42501');
select pg_temp.refused('nor mixed in with members',
  format('select public.send_message_urgent(%L, array[%L::uuid, %L::uuid])',
    pg_temp.mid('m1'), pg_temp.u('d'), pg_temp.u('e')),
  '42501');
select pg_temp.refused_with('nobody at all',
  format('select public.send_message_urgent(%L, array[]::uuid[])', pg_temp.mid('m1')),
  'nobody_to_urgent');
select pg_temp.refused_with('yourself is nobody',
  format('select public.send_message_urgent(%L, array[%L::uuid])', pg_temp.mid('m1'), pg_temp.u('a')),
  'nobody_to_urgent');
select pg_temp.refused_with('a bot can not be made urgent',
  format('select public.send_message_urgent(%L, array[%L::uuid])', pg_temp.mid('m1'), pg_temp.u('f')),
  'nobody_to_urgent');
select pg_temp.refused_with('people already made urgent are not made urgent again',
  format('select public.send_message_urgent(%L, array[%L::uuid, %L::uuid])',
    pg_temp.mid('m1'), pg_temp.u('b'), pg_temp.u('c')),
  'nobody_to_urgent');
select pg_temp.check('and that did not use up a quota slot', (select used from public.my_urgent_quota()) = 1);
select pg_temp.refused('more than 10 people at once is refused',
  format('select public.send_message_urgent(%L, (select array_agg(gen_random_uuid()) from generate_series(1, 11)))',
    pg_temp.mid('m1')),
  '22023');
select pg_temp.act_as(null);
select pg_temp.refused('a signed-out caller is refused',
  format('select public.send_message_urgent(%L, array[%L::uuid])', pg_temp.mid('m1'), pg_temp.u('d')),
  '42501');

-- A third person on the same message later: only the new one is added.
select pg_temp.act_as('a');
select pg_temp.check('a new person can be added to the same message',
  public.send_message_urgent(pg_temp.mid('m1'), array[pg_temp.u('c'), pg_temp.u('d')]) = 1);
select pg_temp.act_as(null);
select pg_temp.check('Di is made urgent once; Cy was before',
  pg_temp.n('select 1 from public.message_urgent_targets where message_id = ' || quote_literal(pg_temp.mid('m1'))) = 3);

-- ------------------------------------------------- messages that can not be
insert into ids select 'recalled', pg_temp.say('a', 'team', 'oops');
update public.messages set recalled_at = now() where id = pg_temp.mid('recalled');
insert into ids select 'expired', pg_temp.say('a', 'team', 'gone');
update public.messages set expires_at = now() - interval '1 minute' where id = pg_temp.mid('expired');
insert into ids select 'review', pg_temp.say('a', 'team', 'checking');
update public.messages set review_state = 'checking' where id = pg_temp.mid('review');
select pg_temp.act_as('a');
select pg_temp.refused('a deleted message can not be made urgent',
  format('select public.send_message_urgent(%L, array[%L::uuid])', pg_temp.mid('recalled'), pg_temp.u('b')), '22023');
select pg_temp.refused('nor an expired one',
  format('select public.send_message_urgent(%L, array[%L::uuid])', pg_temp.mid('expired'), pg_temp.u('b')), '22023');
select pg_temp.refused('nor one waiting for review',
  format('select public.send_message_urgent(%L, array[%L::uuid])', pg_temp.mid('review'), pg_temp.u('b')), '22023');
select pg_temp.refused('no such message',
  format('select public.send_message_urgent(%L, array[%L::uuid])', gen_random_uuid(), pg_temp.u('b')), 'P0002');
select pg_temp.act_as(null);

-- The note to yourself has nobody else.
select pg_temp.act_as('a');
select public.get_note_to_self(true) as note_id \gset
select pg_temp.act_as(null);
insert into ids values ('note', :'note_id');
insert into ids select 'mine', pg_temp.say('a', 'note', 'remember');
select pg_temp.act_as('a');
select pg_temp.refused('the note to self has no one to make urgent',
  format('select public.send_message_urgent(%L, array[%L::uuid])', pg_temp.mid('mine'), pg_temp.u('b')), '22023');
select pg_temp.act_as(null);

-- ----------------------------------------------------- blocks and turn-offs
insert into ids select 'm2', pg_temp.say('a', 'team', 'second notice');
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.u('c'), pg_temp.u('a'));
select pg_temp.act_as('a');
select pg_temp.check('someone who blocked the sender is left out, quietly',
  public.send_message_urgent(pg_temp.mid('m2'), array[pg_temp.u('b'), pg_temp.u('c')]) = 1);
select pg_temp.act_as(null);
select pg_temp.check('they have no urgent row',
  pg_temp.n('select 1 from public.message_urgent_targets where user_id = ' || quote_literal(pg_temp.u('c'))
    || ' and message_id = ' || quote_literal(pg_temp.mid('m2'))) = 0);
delete from public.blocks;

insert into public.blocks (blocker_id, blocked_id) values (pg_temp.u('a'), pg_temp.u('d'));
insert into ids select 'm3', pg_temp.say('a', 'team', 'third notice');
select pg_temp.act_as('a');
select pg_temp.refused_with('the sender who blocked someone can not make a message urgent for them',
  format('select public.send_message_urgent(%L, array[%L::uuid])', pg_temp.mid('m3'), pg_temp.u('d')),
  'nobody_to_urgent');
select pg_temp.act_as(null);
delete from public.blocks;

-- A direct chat with a blocked person: it can not be used there.
insert into public.friendships (user_low_id, user_high_id)
values (least(pg_temp.u('a'), pg_temp.u('e')), greatest(pg_temp.u('a'), pg_temp.u('e')));
insert into public.conversations (type, title) values ('direct', null) returning id \gset dm_
insert into ids values ('dm', :'dm_id');
insert into public.conversation_members (conversation_id, user_id)
values (:'dm_id', pg_temp.u('a')), (:'dm_id', pg_temp.u('e'));
insert into ids select 'dm1', pg_temp.say('a', 'dm', 'call me');
select pg_temp.act_as('a');
select pg_temp.check('in a direct chat it works for a friend',
  public.send_message_urgent(pg_temp.mid('dm1'), array[pg_temp.u('e')]) = 1);
select pg_temp.act_as(null);
insert into ids select 'dm2', pg_temp.say('a', 'dm', 'call me please');
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.u('e'), pg_temp.u('a'));
select pg_temp.act_as('a');
select pg_temp.refused_with('in a direct chat with a blocking person it fails',
  format('select public.send_message_urgent(%L, array[%L::uuid])', pg_temp.mid('dm2'), pg_temp.u('e')),
  'nobody_to_urgent');
select pg_temp.act_as(null);
delete from public.blocks;

-- Turning urgent messages off for one sender.
select pg_temp.act_as('d');
select pg_temp.refused('you can not turn off yourself',
  format('select public.set_urgent_from_sender(%L, false)', pg_temp.u('d')), '22023');
select public.set_urgent_from_sender(pg_temp.u('a'), false);
select pg_temp.check('Di sees Ada in the list of turned-off senders',
  (select count(*) from public.list_urgent_muted_senders() where sender_id = pg_temp.u('a')) = 1);
select pg_temp.act_as(null);
select pg_temp.check('what was waiting from Ada is confirmed with it',
  pg_temp.n('select 1 from public.message_urgent_targets where user_id = ' || quote_literal(pg_temp.u('d'))
    || ' and acked_at is null') = 0);
insert into ids select 'm4', pg_temp.say('a', 'team', 'fourth notice');
select pg_temp.act_as('a');
select pg_temp.refused_with('Ada can not make a message urgent for Di now',
  format('select public.send_message_urgent(%L, array[%L::uuid])', pg_temp.mid('m4'), pg_temp.u('d')),
  'nobody_to_urgent');
select pg_temp.check('and it is not told apart from the others: a mixed call just skips Di',
  public.send_message_urgent(pg_temp.mid('m4'), array[pg_temp.u('d'), pg_temp.u('b')]) = 1);
select pg_temp.act_as('d');
select public.set_urgent_from_sender(pg_temp.u('a'), true);
select pg_temp.check('allowing again empties the list',
  (select count(*) from public.list_urgent_muted_senders()) = 0);
select pg_temp.act_as(null);

-- ---------------------------------------------------- the daily limit of 5
-- Ada did m1, m2, m1 (Di), dm1, m4 = 5 actions so far, minus none refused.
select pg_temp.act_as('a');
select pg_temp.check('five actions are used', (select used from public.my_urgent_quota()) = 5);
select pg_temp.act_as(null);
insert into ids select 'm5', pg_temp.say('a', 'team', 'fifth notice');
select pg_temp.act_as('a');
select pg_temp.refused('a sixth in 24 hours is refused',
  format('select public.send_message_urgent(%L, array[%L::uuid])', pg_temp.mid('m5'), pg_temp.u('b')),
  '53400');
select pg_temp.act_as(null);
update public.message_urgents set created_at = now() - interval '25 hours'
where id = (select id from public.message_urgents where sender_id = pg_temp.u('a') order by created_at limit 1);
select pg_temp.act_as('a');
select pg_temp.check('when one is more than a day old, there is room again',
  public.send_message_urgent(pg_temp.mid('m5'), array[pg_temp.u('b')]) = 1);
select pg_temp.check('the quota counts only the last 24 hours', (select used from public.my_urgent_quota()) = 5);
select pg_temp.act_as('b');
select pg_temp.check('another person has their own quota', (select used from public.my_urgent_quota()) = 0);
select pg_temp.act_as(null);

-- A member who can no longer send in the chat can not use it.
select pg_temp.act_as('9');
insert into ids select 'z1', pg_temp.say('9', 'team', 'admin note');
select pg_temp.act_as(null);
delete from public.conversation_members where conversation_id = pg_temp.mid('team') and user_id = pg_temp.u('9');
select pg_temp.act_as('9');
select pg_temp.refused('someone who left can not make their old message urgent',
  format('select public.send_message_urgent(%L, array[%L::uuid])', pg_temp.mid('z1'), pg_temp.u('b')),
  '42501');
select pg_temp.act_as(null);
insert into public.conversation_members (conversation_id, user_id, role)
values (pg_temp.mid('team'), pg_temp.u('9'), 'admin');

-- ============================================================ the banner
select pg_temp.act_as('b');
select pg_temp.check('Bo has urgent messages waiting: m1, m2, m4, m5',
  (select count(*) from public.list_my_pending_urgents()) = 4);
select pg_temp.check('they can be narrowed to a conversation',
  (select count(*) from public.list_my_pending_urgents(pg_temp.mid('team'))) = 4
  and (select count(*) from public.list_my_pending_urgents(pg_temp.mid('dm'))) = 0);
select pg_temp.check('the row names the sender and carries the text',
  (select sender_display_name = 'Ada' and body = 'The meeting moved to 3 pm' and sender_id = pg_temp.u('a')
   from public.list_my_pending_urgents() where message_id = pg_temp.mid('m1')));
select pg_temp.check('Bo confirms m1', public.ack_message_urgent(pg_temp.mid('m1')) = 1);
select pg_temp.check('confirming twice changes nothing', public.ack_message_urgent(pg_temp.mid('m1')) = 0);
select pg_temp.check('it is gone from the list',
  (select count(*) from public.list_my_pending_urgents() where message_id = pg_temp.mid('m1')) = 0);
select pg_temp.check('confirming a message that was not urgent for you changes nothing',
  public.ack_message_urgent(pg_temp.mid('by_bo')) = 0);
select pg_temp.act_as('c');
select pg_temp.check('Cy still has m1 waiting: confirmations are per person',
  (select count(*) from public.list_my_pending_urgents() where message_id = pg_temp.mid('m1')) = 1);
select pg_temp.act_as(null);

-- It follows the message, the chat and the blocks.
update public.messages set recalled_at = now() where id = pg_temp.mid('m2');
select pg_temp.act_as('b');
select pg_temp.check('a deleted message is no longer waiting',
  (select count(*) from public.list_my_pending_urgents() where message_id = pg_temp.mid('m2')) = 0);
select pg_temp.act_as(null);
update public.messages set recalled_at = null, expires_at = now() - interval '1 second' where id = pg_temp.mid('m4');
select pg_temp.act_as('b');
select pg_temp.check('an expired message is not either',
  (select count(*) from public.list_my_pending_urgents() where message_id = pg_temp.mid('m4')) = 0);
select pg_temp.act_as(null);
update public.messages set expires_at = null, review_state = 'checking' where id = pg_temp.mid('m4');
select pg_temp.act_as('b');
select pg_temp.check('one held for review is not either',
  (select count(*) from public.list_my_pending_urgents() where message_id = pg_temp.mid('m4')) = 0);
select pg_temp.act_as(null);
update public.messages set review_state = null where id = pg_temp.mid('m4');
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.u('b'), pg_temp.u('a'));
select pg_temp.act_as('b');
select pg_temp.check('blocking the sender takes their urgent messages off the list',
  (select count(*) from public.list_my_pending_urgents()) = 0);
select pg_temp.act_as(null);
delete from public.blocks;
update public.message_urgent_targets set created_at = now() - interval '8 days'
where message_id = pg_temp.mid('m5');
select pg_temp.act_as('b');
select pg_temp.check('after 7 days it is not waiting any more',
  (select count(*) from public.list_my_pending_urgents() where message_id = pg_temp.mid('m5')) = 0);
select pg_temp.check('and m4 is back',
  (select count(*) from public.list_my_pending_urgents() where message_id = pg_temp.mid('m4')) = 1);
select pg_temp.act_as(null);
delete from public.conversation_members where conversation_id = pg_temp.mid('team') and user_id = pg_temp.u('b');
select pg_temp.act_as('b');
select pg_temp.check('someone who left the group sees nothing of it',
  (select count(*) from public.list_my_pending_urgents()) = 0);
select pg_temp.act_as(null);
insert into public.conversation_members (conversation_id, user_id) values (pg_temp.mid('team'), pg_temp.u('b'));

-- The sender's view.
select pg_temp.act_as('a');
select pg_temp.same('the sender sees who confirmed',
  (select string_agg(substr(s.user_id::text, 35, 1) || case when s.acked_at is null then '-' else '+' end,
                    ',' order by s.user_id)
   from public.get_message_urgent_status(pg_temp.mid('m1')) s), 'b+,c-,d+');
select pg_temp.act_as('b');
select pg_temp.refused('nobody else does',
  format('select * from public.get_message_urgent_status(%L)', pg_temp.mid('m1')), '42501');
select pg_temp.check('a person reads only their own rows',
  (select count(*) from public.message_urgent_targets) = (
    select count(*) from public.message_urgent_targets where user_id = pg_temp.u('b')));
select pg_temp.refused('and can not write to the table',
  format('update public.message_urgent_targets set acked_at = null where user_id = %L', pg_temp.u('b')),
  '42501');
select pg_temp.refused('nor read the senders'' quota rows of others',
  'insert into public.message_urgents (message_id, conversation_id, sender_id) select message_id, conversation_id, sender_id from public.message_urgents',
  '42501');
select pg_temp.act_as(null);

-- =============================================================== the pushes
-- Bo has a Chinese device, Cy an English one and two devices, Di an English one.
insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
values
  (pg_temp.u('9'), 'https://push.test/zed', repeat('p', 50), repeat('a', 20), 'zh'),
  (pg_temp.u('b'), 'https://push.test/bo', repeat('p', 50), repeat('a', 20), 'zh'),
  (pg_temp.u('c'), 'https://push.test/cy1', repeat('p', 50), repeat('a', 20), 'en'),
  (pg_temp.u('c'), 'https://push.test/cy2', repeat('p', 50), repeat('a', 20), 'en'),
  (pg_temp.u('d'), 'https://push.test/di', repeat('p', 50), repeat('a', 20), 'en');

-- A fresh start for the push tests: everything so far was never pushed, and
-- is closed (it is "too late to be news" or has been claimed).
update public.message_urgent_targets set push_claimed_at = now(), repush_claimed_at = now();
-- The push tests make many urgent messages; Ada's day is emptied before each.
create function pg_temp.new_day() returns void language sql as $$
  update public.message_urgents set created_at = now() - interval '3 days';
$$;
grant execute on function pg_temp.new_day() to public;
select pg_temp.new_day();

select pg_temp.new_day();
insert into ids select 'p1', pg_temp.say('a', 'team', 'Hand in the forms today');
update public.messages set created_at = now() - interval '1 minute' where id = pg_temp.mid('p1');
select pg_temp.act_as('a');
select public.send_message_urgent(pg_temp.mid('p1'), array[pg_temp.u('b'), pg_temp.u('c'), pg_temp.u('d')]);
select pg_temp.act_as(null);

create temp table first_push as select * from public.claim_urgent_pushes();
grant all on first_push to public;
select pg_temp.check('every device of the three people is pushed: 4',
  (select count(*) from first_push) = 4);
select pg_temp.check('Bo gets it in Chinese, with the group',
  (select title = 'Ada 加急了一条消息 (Team)' and body = 'Hand in the forms today'
   from first_push where endpoint = 'https://push.test/bo'));
select pg_temp.check('Di gets it in English',
  (select title = 'Ada marked a message urgent (Team)' and body = 'Hand in the forms today'
   from first_push where endpoint = 'https://push.test/di'));
select pg_temp.check('one tag per message, so the second push replaces the first',
  (select count(distinct tag) = 1 and min(tag) = 'urgent-' || pg_temp.mid('p1') from first_push));
select pg_temp.check('the push opens the conversation',
  (select bool_and(conversation_id = pg_temp.mid('team') and circle_id is null) from first_push));
select pg_temp.check('a second call hands out nothing: a push is claimed once',
  (select count(*) from public.claim_urgent_pushes()) = 0);

-- 10 minutes without a confirmation: one more push, only to who did not confirm.
select pg_temp.act_as('c');
select public.ack_message_urgent(pg_temp.mid('p1'));
select pg_temp.act_as(null);
select pg_temp.check('before 10 minutes there is no second push',
  (select count(*) from public.claim_urgent_pushes()) = 0);
update public.message_urgent_targets set push_claimed_at = now() - interval '11 minutes'
where message_id = pg_temp.mid('p1');
create temp table second_push as select * from public.claim_urgent_pushes();
grant all on second_push to public;
select pg_temp.check('after 10 minutes, Bo and Di are pushed once more; Cy confirmed',
  (select count(*) = 2 and bool_and(endpoint in ('https://push.test/bo', 'https://push.test/di')) from second_push));
select pg_temp.check('the second push says it is not confirmed yet, in the device language',
  (select title = '加急消息未确认：Ada (Team)' from second_push where endpoint = 'https://push.test/bo')
  and (select title = 'Urgent, not confirmed yet: Ada (Team)' from second_push where endpoint = 'https://push.test/di'));
select pg_temp.check('with the same tag, so it replaces the first',
  (select min(tag) = 'urgent-' || pg_temp.mid('p1') from second_push));
update public.message_urgent_targets set push_claimed_at = now() - interval '30 minutes'
where message_id = pg_temp.mid('p1');
select pg_temp.check('and never a third push',
  (select count(*) from public.claim_urgent_pushes()) = 0);

-- Breaking through: Do Not Disturb, a muted conversation, the circle level.
select pg_temp.new_day();
insert into ids select 'p2', pg_temp.say('a', 'team', 'Fire drill at 10');
insert into public.user_privacy_settings (user_id, presence_status) values (pg_temp.u('b'), 'dnd')
on conflict (user_id) do update set presence_status = 'dnd';
update public.conversation_members set muted_until = now() + interval '1 day'
where conversation_id = pg_temp.mid('team') and user_id = pg_temp.u('d');
select pg_temp.act_as('a');
select public.send_message_urgent(pg_temp.mid('p2'), array[pg_temp.u('b'), pg_temp.u('d')]);
select pg_temp.act_as(null);
select pg_temp.check('Do Not Disturb and a muted chat do not stop an urgent push',
  (select count(*) from public.claim_urgent_pushes()) = 2);
select pg_temp.check('while an ordinary message to the same people is held back by both',
  (select count(*) from public.claim_push_delivery(
     pg_temp.mid('p2'), pg_temp.u('a')) where endpoint in ('https://push.test/bo', 'https://push.test/di')) = 0);
update public.user_privacy_settings set presence_status = 'online' where user_id = pg_temp.u('b');
update public.conversation_members set muted_until = null
where conversation_id = pg_temp.mid('team') and user_id = pg_temp.u('d');

-- Blocks, turn-offs, leaving, deleted: checked again when the push is claimed.
select pg_temp.new_day();
insert into ids select 'p3', pg_temp.say('a', 'team', 'Bring your ID');
select pg_temp.act_as('a');
select public.send_message_urgent(pg_temp.mid('p3'), array[pg_temp.u('b'), pg_temp.u('c'), pg_temp.u('d')]);
select pg_temp.act_as(null);
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.u('b'), pg_temp.u('a'));
select pg_temp.act_as('c');
select public.set_urgent_from_sender(pg_temp.u('a'), false);
select pg_temp.act_as(null);
delete from public.conversation_members where conversation_id = pg_temp.mid('team') and user_id = pg_temp.u('d');
select pg_temp.check('blocked after the call, turned off, or gone: nobody is pushed',
  (select count(*) from public.claim_urgent_pushes()) = 0);
delete from public.blocks;
insert into public.conversation_members (conversation_id, user_id) values (pg_temp.mid('team'), pg_temp.u('d'));
select pg_temp.act_as('c');
select public.set_urgent_from_sender(pg_temp.u('a'), true);
select pg_temp.act_as(null);

select pg_temp.new_day();
insert into ids select 'p4', pg_temp.say('a', 'team', 'Bring a pen');
select pg_temp.act_as('a');
select public.send_message_urgent(pg_temp.mid('p4'), array[pg_temp.u('b')]);
select pg_temp.act_as(null);
update public.messages set recalled_at = now() where id = pg_temp.mid('p4');
select pg_temp.check('a message deleted before the push is not pushed',
  (select count(*) from public.claim_urgent_pushes()) = 0);

select pg_temp.new_day();
insert into ids select 'p5', pg_temp.say('a', 'team', 'Bring a ruler');
select pg_temp.act_as('a');
select public.send_message_urgent(pg_temp.mid('p5'), array[pg_temp.u('b')]);
select pg_temp.act_as(null);
update public.messages set review_state = 'checking' where id = pg_temp.mid('p5');
select pg_temp.check('nor one held for review',
  (select count(*) from public.claim_urgent_pushes()) = 0);
update public.messages set review_state = null where id = pg_temp.mid('p5');

-- Too late to be news: an outage ends in no burst.
select pg_temp.new_day();
insert into ids select 'p6', pg_temp.say('a', 'team', 'Bring a book');
select pg_temp.act_as('a');
select public.send_message_urgent(pg_temp.mid('p6'), array[pg_temp.u('b')]);
select pg_temp.act_as(null);
update public.message_urgent_targets set created_at = now() - interval '20 minutes'
where message_id = pg_temp.mid('p6');
select pg_temp.check('a first push 20 minutes late is closed without sending',
  (select count(*) from public.claim_urgent_pushes()) = 0
  and pg_temp.n('select 1 from public.message_urgent_targets where message_id = '
    || quote_literal(pg_temp.mid('p6')) || ' and push_claimed_at is not null and repush_claimed_at is not null') = 1);

-- Not a member any more at the second push.
select pg_temp.new_day();
insert into ids select 'p7', pg_temp.say('a', 'team', 'Bring a snack');
select pg_temp.act_as('a');
select public.send_message_urgent(pg_temp.mid('p7'), array[pg_temp.u('b')]);
select pg_temp.act_as(null);
select count(*) from public.claim_urgent_pushes();
update public.message_urgent_targets set push_claimed_at = now() - interval '11 minutes'
where message_id = pg_temp.mid('p7');
delete from public.conversation_members where conversation_id = pg_temp.mid('team') and user_id = pg_temp.u('b');
select pg_temp.check('someone who left before the second push is not pushed',
  (select count(*) from public.claim_urgent_pushes()) = 0);
insert into public.conversation_members (conversation_id, user_id) values (pg_temp.mid('team'), pg_temp.u('b'));

-- A device that is not the person's is never pushed: only their own devices.
select pg_temp.check('the claim functions are private to the server',
  not has_function_privilege('authenticated', 'public.claim_urgent_pushes()', 'execute')
  and not has_function_privilege('anon', 'public.claim_urgent_pushes()', 'execute')
  and has_function_privilege('service_role', 'public.claim_urgent_pushes()', 'execute')
  and not has_function_privilege('authenticated', 'public.claim_announcement_ack_pushes()', 'execute'));

-- The dispatcher runs (no Vault or pg_net here: it just does not wake anyone).
select public.run_later_dispatch();
select pg_temp.check('run_later_dispatch runs with urgent rows waiting', true);

-- ===================================================== announcements to confirm
-- Team's announcement is "Be on time". Zed (admin) and Ada (owner) manage.
select pg_temp.act_as('b');
select pg_temp.refused('a member can not ask for confirmations',
  format('select public.set_announcement_requires_ack(%L, true)', pg_temp.mid('team')), '42501');
select pg_temp.act_as('e');
select pg_temp.refused('nor can someone outside the group',
  format('select public.set_announcement_requires_ack(%L, true)', pg_temp.mid('team')), '42501');
select pg_temp.refused('or read the state',
  format('select * from public.get_announcement_ack_state(%L)', pg_temp.mid('team')), '42501');
select pg_temp.act_as('b');
select pg_temp.check('before anyone asks, the state says no confirmation is needed',
  (select not requires_ack and total = 0 and acked = 0 and not i_acked and not can_manage
   from public.get_announcement_ack_state(pg_temp.mid('team'))));
select pg_temp.refused('there is nothing to confirm yet',
  format('select public.ack_announcement(%L)', pg_temp.mid('team')), '22023');

-- A group with no announcement can not ask.
select pg_temp.act_as(null);
insert into public.conversations (type, title) values ('group', 'Quiet') returning id \gset quiet_
insert into ids values ('quiet', :'quiet_id');
insert into public.conversation_members (conversation_id, user_id, role)
values (:'quiet_id', pg_temp.u('a'), 'owner'), (:'quiet_id', pg_temp.u('b'), 'member');
select pg_temp.act_as('a');
select pg_temp.refused_with('an empty announcement can not be confirmed',
  format('select public.set_announcement_requires_ack(%L, true)', pg_temp.mid('quiet')),
  'empty_announcement');
select pg_temp.refused('a direct chat has no announcement',
  format('select public.set_announcement_requires_ack(%L, true)', pg_temp.mid('dm')), '42501');

-- Ada asks the members to confirm.
select public.set_announcement_requires_ack(pg_temp.mid('team'), true);
select pg_temp.check('the state counts the five people, not the bot; the owner already confirmed',
  (select requires_ack and total = 5 and acked = 1 and i_acked and can_manage
   from public.get_announcement_ack_state(pg_temp.mid('team'))));
select pg_temp.act_as('b');
select pg_temp.check('a member sees the count and their own state, not the managers'' tools',
  (select requires_ack and total = 5 and acked = 1 and not i_acked and not can_manage and next_reminder_at is null
   from public.get_announcement_ack_state(pg_temp.mid('team'))));
select pg_temp.refused('a member does not get the list of names',
  format('select * from public.list_announcement_ack_members(%L)', pg_temp.mid('team')), '42501');
select pg_temp.check('Bo has a card waiting',
  (select count(*) = 1 and min(announcement) = 'Be on time' and min(title) = 'Team'
   from public.list_my_pending_announcement_acks()));
select public.ack_announcement(pg_temp.mid('team'));
select public.ack_announcement(pg_temp.mid('team'));
select pg_temp.check('Bo confirms (twice is the same as once)',
  (select acked = 2 and i_acked from public.get_announcement_ack_state(pg_temp.mid('team'))));
select pg_temp.check('and the card is gone',
  (select count(*) from public.list_my_pending_announcement_acks()) = 0);
select pg_temp.act_as('a');
select pg_temp.check('the owner sees who confirmed and who did not: Ada and Bo, then Cy, Di, Zed',
  (select string_agg(substr(m.user_id::text, 35, 1) || case when m.acked_at is null then '-' else '+' end,
                    ',' order by (m.acked_at is not null) desc, m.user_id)
   from public.list_announcement_ack_members(pg_temp.mid('team')) m) in ('a+,b+,9-,c-,d-', 'b+,a+,9-,c-,d-'));
select pg_temp.act_as('9');
select pg_temp.check('an admin sees it too',
  (select count(*) from public.list_announcement_ack_members(pg_temp.mid('team'))) = 5);
select pg_temp.act_as(null);

-- Asking turned the request on and asked everybody once.
select pg_temp.check('turning it on asked the 4 members who had not confirmed yet',
  pg_temp.n('select 1 from public.announcement_ack_reminders where conversation_id = '
    || quote_literal(pg_temp.mid('team'))) = 4);
create temp table ack_push as select * from public.claim_announcement_ack_pushes();
grant all on ack_push to public;
select pg_temp.check('they are pushed once per device: Zed, Cy twice, Di; Bo confirmed in between',
  (select count(*) = 4 and not bool_or(endpoint like '%bo') from ack_push));
select pg_temp.check('the Chinese text asks to confirm the announcement',
  (select title = '请确认群公告 (Team)' and body = 'Be on time' and conversation_id = pg_temp.mid('team')
   from ack_push where endpoint = 'https://push.test/zed'));
select pg_temp.check('the English text too',
  (select bool_and(title = 'Please confirm the announcement (Team)') from ack_push where endpoint like '%cy%'));
select pg_temp.check('a second claim hands out nothing',
  (select count(*) from public.claim_announcement_ack_pushes()) = 0);

-- The limit on reminders.
select pg_temp.act_as('a');
select pg_temp.refused('a reminder right after asking is too soon',
  format('select public.remind_announcement_unacked(%L)', pg_temp.mid('team')), '53400');
select pg_temp.check('the state says when the next one is allowed',
  (select next_reminder_at > now() + interval '5 hours' from public.get_announcement_ack_state(pg_temp.mid('team'))));
select pg_temp.act_as('b');
select pg_temp.refused('a member can not remind',
  format('select public.remind_announcement_unacked(%L)', pg_temp.mid('team')), '42501');
select pg_temp.act_as(null);
update public.conversations set announcement_ack_reminded_at = now() - interval '7 hours'
where id = pg_temp.mid('team');
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.u('c'), pg_temp.u('a'));
select pg_temp.act_as('a');
select pg_temp.check('after 6 hours Ada can remind: Di and Zed, not Cy who blocked her, not Bo who confirmed',
  public.remind_announcement_unacked(pg_temp.mid('team')) = 2);
select pg_temp.refused('and only once in 6 hours',
  format('select public.remind_announcement_unacked(%L)', pg_temp.mid('team')), '53400');
select pg_temp.act_as(null);
delete from public.blocks;
select pg_temp.check('the reminder goes to Zed and Di only',
  (select count(*) = 2 and bool_and(endpoint in ('https://push.test/zed', 'https://push.test/di'))
   from public.claim_announcement_ack_pushes()));

-- Pushes respect Do Not Disturb, a muted chat, a confirmation in between.
update public.conversations set announcement_ack_reminded_at = now() - interval '7 hours'
where id = pg_temp.mid('team');
insert into public.user_privacy_settings (user_id, presence_status) values (pg_temp.u('d'), 'dnd')
on conflict (user_id) do update set presence_status = 'dnd';
select pg_temp.act_as('a');
select public.remind_announcement_unacked(pg_temp.mid('team'));
select pg_temp.act_as('c');
select public.ack_announcement(pg_temp.mid('team'));
select pg_temp.act_as(null);
select pg_temp.check('a reminder is not pushed to Di in Do Not Disturb or to Cy who confirmed meanwhile; Zed gets it',
  (select count(*) = 1 and min(endpoint) = 'https://push.test/zed' from public.claim_announcement_ack_pushes()));
update public.user_privacy_settings set presence_status = 'online' where user_id = pg_temp.u('d');

-- A new text clears the confirmations; the request stays.
select pg_temp.act_as('a');
select public.update_group_profile(pg_temp.mid('team'), 'Team', null, 'Be on time');
select pg_temp.check('saving the same text keeps the confirmations',
  (select acked = 3 from public.get_announcement_ack_state(pg_temp.mid('team'))));
select public.update_group_profile(pg_temp.mid('team'), 'Team', null, 'Be on time, 9 sharp');
select pg_temp.check('a new text clears them, and the request stays on',
  (select requires_ack and acked = 0 and not i_acked from public.get_announcement_ack_state(pg_temp.mid('team'))));
select pg_temp.act_as('b');
select pg_temp.check('everybody has a card again',
  (select count(*) = 1 and min(announcement) = 'Be on time, 9 sharp' from public.list_my_pending_announcement_acks()));
select pg_temp.act_as('b');
select pg_temp.refused('a member can not turn the request off',
  format('select public.set_announcement_requires_ack(%L, false)', pg_temp.mid('team')), '42501');
select pg_temp.act_as('a');
select public.set_announcement_requires_ack(pg_temp.mid('team'), false);
select pg_temp.check('turning it off',
  (select not requires_ack and total = 0 and acked = 0 from public.get_announcement_ack_state(pg_temp.mid('team'))));
select pg_temp.act_as('b');
select pg_temp.check('and the cards go',
  (select count(*) from public.list_my_pending_announcement_acks()) = 0);
select pg_temp.act_as('a');
select public.set_announcement_requires_ack(pg_temp.mid('team'), true);
select pg_temp.check('turning it on again starts fresh: only the owner has confirmed',
  (select acked = 1 from public.get_announcement_ack_state(pg_temp.mid('team'))));
select pg_temp.act_as(null);

-- Someone who left is not counted; a closed-down group has nothing waiting.
delete from public.conversation_members where conversation_id = pg_temp.mid('team') and user_id = pg_temp.u('d');
select pg_temp.act_as('a');
select pg_temp.check('the count follows the members: four now',
  (select total = 4 from public.get_announcement_ack_state(pg_temp.mid('team'))));
select pg_temp.act_as(null);

-- Rows follow the message, the chat and the account.
delete from public.messages where id = pg_temp.mid('m1');
select pg_temp.check('deleting a message removes its urgent rows',
  pg_temp.n('select 1 from public.message_urgents where message_id = ' || quote_literal(pg_temp.mid('m1'))) = 0
  and pg_temp.n('select 1 from public.message_urgent_targets where message_id = ' || quote_literal(pg_temp.mid('m1'))) = 0);
delete from public.profiles where id = pg_temp.u('b');
select pg_temp.check('deleting an account removes what was about them',
  pg_temp.n('select 1 from public.message_urgent_targets where user_id = ' || quote_literal(pg_temp.u('b'))) = 0
  and pg_temp.n('select 1 from public.announcement_acks where user_id = ' || quote_literal(pg_temp.u('b'))) = 0);
delete from public.conversations where id = pg_temp.mid('team');
select pg_temp.check('deleting the group removes its confirmations and reminders',
  pg_temp.n('select 1 from public.announcement_acks where conversation_id = ' || quote_literal(pg_temp.mid('team'))) = 0
  and pg_temp.n('select 1 from public.announcement_ack_reminders where conversation_id = ' || quote_literal(pg_temp.mid('team'))) = 0);

rollback;
