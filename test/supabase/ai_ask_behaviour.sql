-- Behaviour checks for Ask AI (F1 stage 1: migration 202610250300). Run by
-- test/supabase/ai_ask_test.dart against the local database: it applies every
-- migration after the local baseline in a transaction, plays people through
-- the API and the service role, and rolls everything back. Run from the
-- repository root.
--
-- What it walks through: the scope check (who may ask where; the person's and
-- the circle's and the group's AI switches), the keyword search (groups of
-- words, Chinese runs, ranking, literal characters, limits) and the
-- visibility rules (recalled, expired, held, view-once, notices, assistant
-- replies, blocked senders either way, other people's chats, chats left,
-- suspended circles), the check of the sources after the model answered, and
-- who may call the functions.
\set ON_ERROR_STOP on

begin;

do $$ begin perform pg_advisory_xact_lock(20261017); end $$;
set local client_min_messages = warning;

-- Every migration after the local baseline (202610170001), in order.
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

-- ------------------------------------------------------------------ cast
-- Ada owns the group G ("Plan") and the circle; Bob and Cy are members of
-- both. Dee is nobody's member. Ada is friends with Bob, Cy and Dee; Bob and
-- Cy are friends.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '@ak.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from (values ('d1','ada'),('d2','bob'),('d3','cy'),('d4','dee')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '_ak', initcap(name)
from (values ('d1','ada'),('d2','bob'),('d3','cy'),('d4','dee')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || n)::uuid
from (values ('d1','ada'),('d2','bob'),('d3','cy'),('d4','dee')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(x.a, x.b), greatest(x.a, x.b)
from (values
  (pg_temp.i('ada'), pg_temp.i('bob')),
  (pg_temp.i('ada'), pg_temp.i('cy')),
  (pg_temp.i('ada'), pg_temp.i('dee')),
  (pg_temp.i('bob'), pg_temp.i('cy'))
) x(a, b);

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'group', public.create_group_conversation('Plan', array[pg_temp.i('bob'), pg_temp.i('cy')]);
insert into pg_temp.ids select 'group2', public.create_group_conversation('Trip', array[pg_temp.i('bob'), pg_temp.i('cy')]);
insert into pg_temp.ids select 'circle', public.create_circle('Ask club', array[pg_temp.i('bob'), pg_temp.i('cy')]);
select pg_temp.root();
insert into pg_temp.ids
select 'channel', cc.conversation_id from public.circle_channels cc where cc.circle_id = pg_temp.i('circle') order by cc.created_at limit 1;
insert into public.conversation_members (conversation_id, user_id, role)
select pg_temp.i('channel'), cm.user_id, cm.role
from public.circle_members cm where cm.circle_id = pg_temp.i('circle')
on conflict do nothing;

-- A message in [conv] from [who], [mins] minutes ago.
create function pg_temp.mk(who text, conv uuid, body text, mins integer default 30) returns uuid language plpgsql as $$
declare mid uuid;
begin
  insert into public.messages (conversation_id, sender_id, type, body, created_at)
  values (conv, pg_temp.i(who), 'text', body, now() - make_interval(mins => mins))
  returning id into mid;
  return mid;
end $$;
grant execute on function pg_temp.mk(text, uuid, text, integer) to public;

-- The bodies [who] finds with the groups [groups] (scope everywhere unless
-- given), best first, joined with " | ".
create function pg_temp.found(who text, groups text[], scope jsonb default '{"type":"everywhere"}', lim integer default 50) returns text language sql as $$
  select coalesce(string_agg(r.body, ' | ' order by r.score desc, r.created_at desc, r.message_id desc), '')
  from public.ai_ask_search(pg_temp.i(who), groups, scope, lim) r
$$;
grant execute on function pg_temp.found(text, text[], jsonb, integer) to public;

create function pg_temp.nfound(who text, groups text[], scope jsonb default '{"type":"everywhere"}') returns integer language sql as $$
  select count(*)::integer from public.ai_ask_search(pg_temp.i(who), groups, scope, 50)
$$;
grant execute on function pg_temp.nfound(text, text[], jsonb) to public;

create function pg_temp.scope_status(who text, scope jsonb) returns text language sql as $$
  select public.ai_ask_scope(pg_temp.i(who), scope)->>'status'
$$;
grant execute on function pg_temp.scope_status(text, jsonb) to public;

create function pg_temp.conv(id uuid) returns jsonb language sql as $$
  select jsonb_build_object('type', 'conversation', 'id', id)
$$;
grant execute on function pg_temp.conv(uuid) to public;

-- ===================================== 1. the scope check
do $$
declare g uuid := pg_temp.i('group'); ch uuid := pg_temp.i('channel'); circ uuid := pg_temp.i('circle'); n integer;
begin
  perform pg_temp.expect(pg_temp.scope_status('bob', '{"type":"everywhere"}') = 'ok', 'scope: a person may ask everywhere');
  perform pg_temp.expect(pg_temp.scope_status('bob', null) = 'ok', 'scope: no scope means everywhere');
  perform pg_temp.expect(pg_temp.scope_status('bob', pg_temp.conv(g)) = 'ok', 'scope: a member may ask in their group');
  perform pg_temp.expect(pg_temp.scope_status('bob', jsonb_build_object('type', 'circle', 'id', circ)) = 'ok', 'scope: and in their circle');
  perform pg_temp.expect((public.ai_ask_scope(pg_temp.i('bob'), pg_temp.conv(g))->>'conversations')::int = 1, 'scope: one conversation to search');
  perform pg_temp.expect((public.ai_ask_scope(pg_temp.i('bob'), '{"type":"everywhere"}')->>'conversations')::int >= 3, 'scope: everywhere is every chat Bob can read');

  perform pg_temp.expect(pg_temp.scope_status('dee', pg_temp.conv(g)) = 'not_found', 'scope: a stranger''s group is not found');
  perform pg_temp.expect(pg_temp.scope_status('dee', jsonb_build_object('type', 'circle', 'id', circ)) = 'not_found', 'scope: nor a stranger''s circle');
  perform pg_temp.expect(pg_temp.scope_status('bob', '{"type":"conversation"}') = 'not_found', 'scope: a conversation scope without an id is not found');
  perform pg_temp.expect(pg_temp.scope_status('bob', '{"type":"mars"}') = 'not_found', 'scope: an unknown kind is not found');
  perform pg_temp.expect(pg_temp.scope_status('bob', pg_temp.conv(gen_random_uuid())) = 'not_found', 'scope: a conversation that does not exist is not found');
  perform pg_temp.expect(pg_temp.scope_status('bob', '{"type":"everywhere","id":"x"}') = 'ok', 'scope: junk next to a valid kind does no harm');

  -- The person's own switch.
  insert into public.user_ai_settings (user_id, ai_enabled) values (pg_temp.i('bob'), false);
  perform pg_temp.expect(pg_temp.scope_status('bob', pg_temp.conv(g)) = 'user_off', 'scope: a person who turned AI off cannot ask');
  perform pg_temp.expect(pg_temp.scope_status('bob', '{"type":"everywhere"}') = 'user_off', 'scope: not anywhere');
  perform pg_temp.expect(pg_temp.scope_status('cy', pg_temp.conv(g)) = 'ok', 'scope: and it is theirs alone');
  update public.user_ai_settings set ai_enabled = true where user_id = pg_temp.i('bob');
  perform pg_temp.expect(pg_temp.scope_status('bob', pg_temp.conv(g)) = 'ok', 'scope: switched on again, they can');

  -- The group owner's switch.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_group_ai_assistant(g, false);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.scope_status('bob', pg_temp.conv(g)) = 'ai_off', 'scope: a group that turned WeCord AI off says ai_off');
  perform pg_temp.expect((public.ai_ask_scope(pg_temp.i('bob'), '{"type":"everywhere"}')->>'conversations')::int
    = cardinality(public.ai_ask_conversations(pg_temp.i('bob'), '{"type":"everywhere"}'))
    and not (g = any(public.ai_ask_conversations(pg_temp.i('bob'), '{"type":"everywhere"}')))
    and pg_temp.scope_status('bob', '{"type":"everywhere"}') = 'ok', 'scope: everywhere just leaves that group out');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_group_ai_assistant(g, true);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.scope_status('bob', pg_temp.conv(g)) = 'ok', 'scope: back on');

  -- The circle's switch.
  update public.circles set ai_enabled = false where id = circ;
  perform pg_temp.expect(pg_temp.scope_status('bob', pg_temp.conv(ch)) = 'ai_off', 'scope: a circle that turned AI off says ai_off for its channel');
  perform pg_temp.expect(pg_temp.scope_status('bob', jsonb_build_object('type', 'circle', 'id', circ)) = 'ai_off', 'scope: and for the circle');
  update public.circles set ai_enabled = true where id = circ;
  perform pg_temp.expect(pg_temp.scope_status('bob', jsonb_build_object('type', 'circle', 'id', circ)) = 'ok', 'scope: back on');

  -- A suspended circle cannot be read.
  update public.circles set disabled_mode = 'suspend', disabled_at = now() where id = circ;
  perform pg_temp.expect(pg_temp.scope_status('bob', pg_temp.conv(ch)) = 'not_found', 'scope: a suspended circle''s channel is not found');
  update public.circles set disabled_mode = null, disabled_at = null where id = circ;
  perform pg_temp.expect(pg_temp.scope_status('bob', pg_temp.conv(ch)) = 'ok', 'scope: restored');
end $$;

-- ===================================== 2. the search itself
do $$
declare g uuid := pg_temp.i('group'); ch uuid := pg_temp.i('channel'); g2 uuid := pg_temp.i('group2'); r text; rows record;
begin
  perform pg_temp.mk('cy', g, 'The team dinner is at Haidilao on Friday', 50);
  perform pg_temp.mk('ada', g, 'Dinner at 7pm, bring cash', 40);
  perform pg_temp.mk('cy', g, 'Lunch is sushi on Monday', 30);
  perform pg_temp.mk('ada', g, '周五聚餐地点定在海底捞', 20);
  perform pg_temp.mk('bob', g, 'I cannot make Friday', 10);
  perform pg_temp.mk('ada', ch, 'Haidilao has a new menu', 5);
  perform pg_temp.mk('cy', g2, 'Trip budget is 500 dollars', 5);

  -- One group: every word must be there.
  r := pg_temp.found('bob', array['dinner haidilao']);
  perform pg_temp.expect(r = 'The team dinner is at Haidilao on Friday', 'search: all the words of a group must be in the message (got ' || r || ')');
  perform pg_temp.expect(pg_temp.nfound('bob', array['dinner sushi']) = 0, 'search: words that never share a message find nothing');
  perform pg_temp.expect(pg_temp.nfound('bob', array['DINNER']) = 2, 'search: case does not matter');
  perform pg_temp.expect(pg_temp.nfound('bob', array['di']) = 0, 'search: a word has to be whole under three characters');
  perform pg_temp.expect(pg_temp.nfound('bob', array['innere']) = 0 and pg_temp.nfound('bob', array['inner']) = 2, 'search: from three characters a word matches inside another');

  -- Several groups: any of them; the message that matches more groups first.
  r := pg_temp.found('bob', array['dinner haidilao', 'friday']);
  perform pg_temp.expect(split_part(r, ' | ', 1) = 'The team dinner is at Haidilao on Friday', 'search: matching two groups ranks first (got ' || r || ')');
  perform pg_temp.expect(pg_temp.nfound('bob', array['dinner haidilao', 'friday']) = 2, 'search: groups are alternatives (dinner+haidilao, or friday)');
  perform pg_temp.expect(pg_temp.nfound('bob', array['sushi', 'budget', 'cash']) = 3, 'search: three groups');
  perform pg_temp.expect(pg_temp.nfound('bob', array['sushi', 'budget', 'cash', 'haidilao']) = 3, 'search: a fourth group is ignored');
  perform pg_temp.expect(pg_temp.nfound('bob', array['alpha beta gamma delta epsilon zeta dinner']) = 0
    and pg_temp.nfound('bob', array['dinner dinner dinner dinner dinner dinner nothing']) = 2, 'search: only the first six words of a group are read');

  -- Chinese: a run of characters, in a phrase.
  r := pg_temp.found('bob', array['聚餐 地点']);
  perform pg_temp.expect(r = '周五聚餐地点定在海底捞', 'search: Chinese words find the message (got ' || r || ')');
  perform pg_temp.expect(pg_temp.nfound('bob', array['海底捞']) = 1, 'search: a Chinese name');
  perform pg_temp.expect(pg_temp.nfound('bob', array['地点聚餐']) = 0, 'search: but not in the wrong order');

  -- Nothing to look for.
  perform pg_temp.expect(pg_temp.nfound('bob', array[]::text[]) = 0, 'search: no groups, no results');
  perform pg_temp.expect(pg_temp.nfound('bob', null) = 0, 'search: null groups, no results');
  perform pg_temp.expect(pg_temp.nfound('bob', array['', '   ', '!!!']) = 0, 'search: empty or punctuation groups, no results');
  perform pg_temp.expect(pg_temp.nfound('bob', array['', 'sushi']) = 1, 'search: an empty group beside a real one is skipped');

  -- Literal characters.
  perform pg_temp.mk('cy', g, 'Everything is 50% off', 4);
  perform pg_temp.mk('cy', g, 'Code 5_x is secret', 4);
  perform pg_temp.expect(pg_temp.nfound('bob', array['50%']) = 1, 'literal: a percent sign is just a percent sign');
  perform pg_temp.expect(pg_temp.nfound('bob', array['%%%']) = 0, 'literal: and not a wildcard');
  perform pg_temp.expect(pg_temp.nfound('bob', array['5_x']) = 1, 'literal: an underscore is found as itself');
  perform pg_temp.expect(pg_temp.nfound('bob', array[$q$'; drop table public.messages; --$q$]) = 0
    and to_regclass('public.messages') is not null, 'literal: a quote and SQL in a word do nothing');
  perform pg_temp.expect(pg_temp.nfound('bob', array[$q$"x" or 1=1 --$q$, '\']) = 0, 'literal: double quotes and a backslash are words, not syntax');

  -- The limit.
  perform pg_temp.expect((select count(*) from public.ai_ask_search(pg_temp.i('bob'), array['friday', 'dinner', 'sushi'], '{"type":"everywhere"}', 2)) = 2, 'limit: the number asked for');
  perform pg_temp.expect((select count(*) from public.ai_ask_search(pg_temp.i('bob'), array['is'], '{"type":"everywhere"}', 1000)) <= 50, 'limit: never more than 50');
  perform pg_temp.expect((select count(*) from public.ai_ask_search(pg_temp.i('bob'), array['friday'], '{"type":"everywhere"}', 0)) = 1, 'limit: zero is read as one');

  -- Scope narrows.
  perform pg_temp.expect(pg_temp.nfound('bob', array['haidilao'], pg_temp.conv(g)) = 1, 'scope: one group finds only its own');
  perform pg_temp.expect(pg_temp.nfound('bob', array['haidilao'], pg_temp.conv(ch)) = 1 and pg_temp.found('bob', array['haidilao'], pg_temp.conv(ch)) = 'Haidilao has a new menu', 'scope: one channel finds only its own');
  perform pg_temp.expect(pg_temp.nfound('bob', array['haidilao'], jsonb_build_object('type', 'circle', 'id', pg_temp.i('circle'))) = 1, 'scope: a circle finds its channels');
  perform pg_temp.expect(pg_temp.nfound('bob', array['haidilao']) = 2, 'scope: everywhere finds both');
  perform pg_temp.expect(pg_temp.nfound('bob', array['budget'], pg_temp.conv(g)) = 0 and pg_temp.nfound('bob', array['budget'], pg_temp.conv(g2)) = 1, 'scope: a message of another group is not in this group''s scope');
  perform pg_temp.expect(pg_temp.nfound('bob', array['haidilao'], pg_temp.conv(gen_random_uuid())) = 0, 'scope: an unknown conversation finds nothing');

  -- What a result carries.
  select * into rows from public.ai_ask_search(pg_temp.i('bob'), array['haidilao'], pg_temp.conv(ch), 5);
  perform pg_temp.expect(rows.sender_name = 'Ada' and rows.type = 'text' and rows.conversation_id = ch and rows.sender_id = pg_temp.i('ada'), 'result: the sender''s name and ids');
  perform pg_temp.expect(rows.place->>'id' = ch::text and rows.place->>'type' = 'channel' and rows.place->>'circle_name' = 'Ask club', 'result: where it was said, with the circle');
  select * into rows from public.ai_ask_search(pg_temp.i('bob'), array['sushi'], pg_temp.conv(g), 5);
  perform pg_temp.expect(rows.place->>'title' = 'Plan' and rows.place->>'type' = 'group', 'result: a group''s name');

  -- A remark name is how the asker sees someone.
  insert into public.contact_aliases (owner_id, friend_id, alias) values (pg_temp.i('bob'), pg_temp.i('cy'), 'Cy from work');
  select * into rows from public.ai_ask_search(pg_temp.i('bob'), array['sushi'], pg_temp.conv(g), 5);
  perform pg_temp.expect(rows.sender_name = 'Cy from work', 'result: the asker''s own remark name for the sender');
  select * into rows from public.ai_ask_search(pg_temp.i('ada'), array['sushi'], pg_temp.conv(g), 5);
  perform pg_temp.expect(rows.sender_name = 'Cy', 'result: and nobody else''s');
  delete from public.contact_aliases;

  -- Files are found by name, polls by option.
  insert into public.messages (conversation_id, sender_id, type, body, attachment, created_at)
  values (g, pg_temp.i('cy'), 'file', '', '{"kind":"file","name":"itinerary.pdf"}', now() - interval '3 minutes');
  select * into rows from public.ai_ask_search(pg_temp.i('bob'), array['itinerary'], pg_temp.conv(g), 5);
  perform pg_temp.expect(rows.type = 'file' and rows.attachment_name = 'itinerary.pdf' and rows.body = '', 'result: a file is found by its name and carries it');
end $$;

-- ===================================== 3. what may be read
do $$
declare g uuid := pg_temp.i('group'); ch uuid := pg_temp.i('channel'); m uuid; dm uuid; note uuid; sec text := 'secretword';
begin
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 0, 'visible: nothing yet');

  -- The asker's own words are theirs to ask about.
  perform pg_temp.mk('bob', g, 'my own secretword');
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 1, 'visible: your own messages are found');
  perform pg_temp.expect(pg_temp.nfound('cy', array[sec]) = 1, 'visible: and a friend finds them in the group');
  delete from public.messages where body = 'my own secretword';

  m := pg_temp.mk('cy', g, 'plain secretword');
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 1, 'visible: another member''s message is');

  update public.messages set recalled_at = now() where id = m;
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 0, 'visible: a recalled message is not');
  update public.messages set recalled_at = null where id = m;
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 1, 'visible: restored for the test');

  update public.messages set expires_at = now() - interval '1 minute' where id = m;
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 0, 'visible: an expired (disappearing) message is not');
  update public.messages set expires_at = now() + interval '1 hour' where id = m;
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 1, 'visible: a disappearing message that has not expired is');
  update public.messages set expires_at = null where id = m;

  update public.messages set review_state = 'checking' where id = m;
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 0, 'visible: a message the AI guard is checking is not');
  update public.messages set review_state = 'held' where id = m;
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 0, 'visible: nor one it holds');
  perform pg_temp.expect(pg_temp.nfound('cy', array[sec]) = 0, 'visible: not even for the sender');
  update public.messages set review_state = null where id = m;
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 1, 'visible: released, it is');

  -- Notices, view-once, assistant replies.
  insert into public.messages (conversation_id, sender_id, type, body, created_at)
    values (g, pg_temp.i('cy'), 'system', 'secretword joined', now() - interval '10 minutes');
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 1, 'visible: notices are not');
  insert into public.messages (conversation_id, sender_id, type, body, attachment, created_at)
    values (g, pg_temp.i('cy'), 'image', 'look secretword', '{"kind":"image","view_once":true}', now() - interval '10 minutes');
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 1, 'visible: a view-once picture is not, even with a caption');
  insert into public.messages (conversation_id, sender_id, type, body, attachment, created_at)
    values (g, pg_temp.i('cy'), 'image', 'normal secretword picture', '{"kind":"image"}', now() - interval '10 minutes');
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 2, 'visible: an ordinary picture''s caption is');
  insert into public.messages (conversation_id, sender_id, type, body, created_at, ai_reply)
    values (g, pg_temp.i('ada'), 'text', 'an AI answer with secretword', now() - interval '10 minutes', '{"kind":"answer"}');
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 2, 'visible: replies of the assistant are not');
  delete from public.messages where body like '%secretword%' and id <> m;

  -- Blocked either way.
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.block_user(pg_temp.i('cy'));
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 0, 'blocked: a sender Bob blocked is not found');
  perform pg_temp.expect(pg_temp.nfound('cy', array[sec]) = 1, 'blocked: Cy still finds their own message');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.unblock_user(pg_temp.i('cy'));
  perform pg_temp.act(pg_temp.i('cy'));
  perform public.block_user(pg_temp.i('bob'));
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 0, 'blocked: nor one who blocked Bob');
  perform pg_temp.act(pg_temp.i('cy'));
  perform public.unblock_user(pg_temp.i('bob'));
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 1, 'blocked: unblocked, found again');

  -- Not a member; left; AI off for the person, the group, the circle.
  perform pg_temp.expect(pg_temp.nfound('dee', array[sec]) = 0 and pg_temp.nfound('dee', array[sec], pg_temp.conv(g)) = 0, 'visible: a stranger finds nothing of the group');
  perform pg_temp.mk('ada', ch, 'channel secretword');
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 2, 'visible: a circle channel the person can read is');
  perform pg_temp.expect(pg_temp.nfound('dee', array[sec]) = 0, 'visible: not a stranger''s');

  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_group_ai_assistant(g, false);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 1, 'ai off: a group that turned WeCord AI off is not searched');
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec], pg_temp.conv(g)) = 0, 'ai off: not even when asked for by name');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_group_ai_assistant(g, true);
  perform pg_temp.root();

  update public.circles set ai_enabled = false where id = pg_temp.i('circle');
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 1, 'ai off: nor a circle that turned AI off');
  update public.circles set ai_enabled = true where id = pg_temp.i('circle');

  update public.circles set disabled_mode = 'suspend', disabled_at = now() where id = pg_temp.i('circle');
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 1, 'visible: nor a suspended circle');
  update public.circles set disabled_mode = null, disabled_at = null where id = pg_temp.i('circle');
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 2, 'visible: restored, it is');

  insert into public.user_ai_settings (user_id, ai_enabled) values (pg_temp.i('bob'), false)
    on conflict (user_id) do update set ai_enabled = false;
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 0, 'ai off: a person who turned AI off finds nothing');
  perform pg_temp.expect(pg_temp.nfound('cy', array[sec]) = 2, 'ai off: others are not affected');
  update public.user_ai_settings set ai_enabled = true where user_id = pg_temp.i('bob');

  delete from public.conversation_members where conversation_id = ch and user_id = pg_temp.i('bob');
  perform pg_temp.expect(pg_temp.nfound('bob', array[sec]) = 1, 'visible: a channel the person left is not');
  insert into public.conversation_members (conversation_id, user_id) values (ch, pg_temp.i('bob'));

  -- Private chats: only the two in them. The note to self: only its owner.
  perform pg_temp.act(pg_temp.i('ada'));
  dm := public.get_or_create_direct_conversation(pg_temp.i('bob'));
  note := public.get_note_to_self(true);
  perform pg_temp.root();
  perform pg_temp.mk('ada', dm, 'private secretword for bob');
  perform pg_temp.mk('ada', note, 'reminder secretword for me');
  perform pg_temp.expect(pg_temp.nfound('bob', array['private secretword']) = 1, 'private: a private chat is found by its two people');
  perform pg_temp.expect(pg_temp.nfound('ada', array['private secretword']) = 1, 'private: both');
  perform pg_temp.expect(pg_temp.nfound('cy', array['private secretword']) = 0 and pg_temp.nfound('dee', array['private secretword']) = 0, 'private: and nobody else');
  perform pg_temp.expect(pg_temp.nfound('ada', array['reminder secretword']) = 1, 'private: the owner finds their note to self');
  perform pg_temp.expect(pg_temp.nfound('bob', array['reminder secretword']) = 0, 'private: nobody else does');
  perform pg_temp.expect(pg_temp.nfound('bob', array['private secretword'], pg_temp.conv(dm)) = 1, 'private: a private chat can be the scope');
  perform pg_temp.expect(pg_temp.nfound('cy', array['private secretword'], pg_temp.conv(dm)) = 0, 'private: not for a third person');
end $$;

-- ===================================== 4. the sources are checked again
do $$
declare g uuid := pg_temp.i('group'); m1 uuid; m2 uuid; m3 uuid; seen uuid[];
begin
  m1 := pg_temp.mk('cy', g, 'source one');
  m2 := pg_temp.mk('cy', g, 'source two');
  m3 := pg_temp.mk('ada', pg_temp.i('group2'), 'source three');

  seen := public.ai_ask_visible(pg_temp.i('bob'), array[m1, m2, m3]);
  perform pg_temp.expect(seen @> array[m1, m2, m3] and cardinality(seen) = 3, 'sources: messages the asker can read stay');
  seen := public.ai_ask_visible(pg_temp.i('dee'), array[m1, m2, m3]);
  perform pg_temp.expect(cardinality(seen) = 0, 'sources: a stranger keeps none');
  perform pg_temp.expect(cardinality(public.ai_ask_visible(pg_temp.i('bob'), array[gen_random_uuid()])) = 0, 'sources: an id that is no message is dropped');
  perform pg_temp.expect(cardinality(public.ai_ask_visible(pg_temp.i('bob'), '{}')) = 0 and cardinality(public.ai_ask_visible(pg_temp.i('bob'), null)) = 0, 'sources: nothing in, nothing out');

  update public.messages set recalled_at = now() where id = m1;
  update public.messages set expires_at = now() - interval '1 second' where id = m2;
  seen := public.ai_ask_visible(pg_temp.i('bob'), array[m1, m2, m3]);
  perform pg_temp.expect(seen = array[m3], 'sources: a message recalled or expired while the model thought is dropped');
  update public.messages set recalled_at = null, expires_at = null where id in (m1, m2);

  update public.messages set review_state = 'held' where id = m1;
  perform pg_temp.expect(not (m1 = any(public.ai_ask_visible(pg_temp.i('bob'), array[m1]))), 'sources: a held message is dropped');
  update public.messages set review_state = null where id = m1;

  update public.messages set attachment = '{"kind":"image","view_once":true}' where id = m2;
  perform pg_temp.expect(not (m2 = any(public.ai_ask_visible(pg_temp.i('bob'), array[m2]))), 'sources: a view-once message is dropped');
  update public.messages set attachment = null where id = m2;

  perform pg_temp.act(pg_temp.i('bob'));
  perform public.block_user(pg_temp.i('cy'));
  perform pg_temp.root();
  perform pg_temp.expect(not (m1 = any(public.ai_ask_visible(pg_temp.i('bob'), array[m1]))) and m3 = any(public.ai_ask_visible(pg_temp.i('bob'), array[m1, m3])), 'sources: a blocked sender''s message is dropped, others stay');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.unblock_user(pg_temp.i('cy'));
  perform pg_temp.root();

  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_group_ai_assistant(g, false);
  perform pg_temp.root();
  perform pg_temp.expect(not (m1 = any(public.ai_ask_visible(pg_temp.i('bob'), array[m1]))), 'sources: a group that turned AI off meanwhile is dropped');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_group_ai_assistant(g, true);
  perform pg_temp.root();

  insert into public.user_ai_settings (user_id, ai_enabled) values (pg_temp.i('bob'), false)
    on conflict (user_id) do update set ai_enabled = false;
  perform pg_temp.expect(cardinality(public.ai_ask_visible(pg_temp.i('bob'), array[m1, m3])) = 0, 'sources: a person who turned AI off keeps none');
  update public.user_ai_settings set ai_enabled = true where user_id = pg_temp.i('bob');

  delete from public.conversation_members where conversation_id = g and user_id = pg_temp.i('bob');
  perform pg_temp.expect(cardinality(public.ai_ask_visible(pg_temp.i('bob'), array[m1])) = 0, 'sources: a chat the person left is dropped');
  insert into public.conversation_members (conversation_id, user_id) values (g, pg_temp.i('bob'));
end $$;

-- ===================================== 5. who may call
do $$
declare f text;
begin
  perform pg_temp.root();
  foreach f in array array[
    'public.ai_ask_conversations(uuid, jsonb)',
    'public.ai_ask_scope(uuid, jsonb)',
    'public.ai_ask_search(uuid, text[], jsonb, integer)',
    'public.ai_ask_visible(uuid, uuid[])'
  ] loop
    perform pg_temp.expect(has_function_privilege('service_role', f, 'execute'), 'permissions: the service role can call ' || f);
    perform pg_temp.expect(not has_function_privilege('authenticated', f, 'execute'), 'permissions: a signed-in person cannot call ' || f);
    perform pg_temp.expect(not has_function_privilege('anon', f, 'execute'), 'permissions: nor anon ' || f);
  end loop;

  -- A signed-in person cannot ask for somebody else's chats by calling it.
  perform pg_temp.act(pg_temp.i('dee'));
  perform pg_temp.must_refuse(format('select * from public.ai_ask_search(%L, array[%L], %L, 5)', pg_temp.i('bob'), 'dinner', '{"type":"everywhere"}'),
    'permissions: Dee cannot run a search as Bob');
  perform pg_temp.must_refuse(format('select public.ai_ask_scope(%L, null)', pg_temp.i('bob')), 'permissions: nor check Bob''s scope');
  perform pg_temp.must_refuse(format('select public.ai_ask_visible(%L, array[gen_random_uuid()])', pg_temp.i('bob')), 'permissions: nor Bob''s sources');
  perform pg_temp.act(null);
  perform pg_temp.must_refuse(format('select * from public.ai_ask_search(%L, array[%L], %L, 5)', pg_temp.i('bob'), 'dinner', '{"type":"everywhere"}'),
    'permissions: nobody signed in cannot either');
  perform pg_temp.root();
end $$;

\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'ask ai: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
