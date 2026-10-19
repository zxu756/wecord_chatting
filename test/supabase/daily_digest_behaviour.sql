-- Behaviour checks for the daily digest (F3: migrations 202610230500 to
-- 202610230540). Run by test/supabase/daily_digest_test.dart against the local
-- database: it applies the migrations it needs in a transaction, plays people
-- through the API and the service role, and rolls everything back. Run from
-- the repository root.
--
-- What it walks through: following chats (members only, groups and circle
-- channels only, at most 10 a person for every writer), leaving a chat and
-- deleting an account or a chat, what counts as news (the visibility rules:
-- recalled, expired, held, view-once, blocked, not followed, AI switched off
-- by the circle or the group, suspended circles), the schedule (each person's
-- own time zone, once a day, no news means no wake-up of the model), the
-- claim's gates, what the model may read, handing in the card, the card the
-- app lists, the push, the sweep and the data export.
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
\i supabase/migrations/202610230300_circle_invite_tracking.sql
\i supabase/migrations/202610230310_circle_insights_data.sql
\i supabase/migrations/202610230320_circle_insights_rpc.sql
\i supabase/migrations/202610230400_ai_assistant_identity.sql
\i supabase/migrations/202610230410_ai_assistant_jobs.sql
\i supabase/migrations/202610230420_ai_assistant_rpcs.sql
\i supabase/migrations/202610230430_ai_reply_channel_send.sql
\i supabase/migrations/202610230500_ai_digest_schema.sql
\i supabase/migrations/202610230510_ai_digest_rpcs.sql
\i supabase/migrations/202610230520_ai_digest_run.sql
\i supabase/migrations/202610230530_ai_digest_push.sql
\i supabase/migrations/202610230540_export_my_ai_digest.sql
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
-- Ada owns the group G and the circle; Bob and Cy are members of both. Dee is
-- nobody's member. Ada is friends with Bob, Cy and Dee; Bob and Cy are friends.
-- Bob's devices are in Shanghai, Cy's in Los Angeles.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '@dg.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from (values ('d1','ada'),('d2','bob'),('d3','cy'),('d4','dee'),('d5','fay')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '_dg', initcap(name)
from (values ('d1','ada'),('d2','bob'),('d3','cy'),('d4','dee'),('d5','fay')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || n)::uuid
from (values ('d1','ada'),('d2','bob'),('d3','cy'),('d4','dee'),('d5','fay')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(x.a, x.b), greatest(x.a, x.b)
from (values
  (pg_temp.i('ada'), pg_temp.i('bob')),
  (pg_temp.i('ada'), pg_temp.i('cy')),
  (pg_temp.i('ada'), pg_temp.i('dee')),
  (pg_temp.i('bob'), pg_temp.i('cy'))
) x(a, b);

insert into public.user_notification_settings (user_id, timezone)
values (pg_temp.i('bob'), 'Asia/Shanghai'), (pg_temp.i('cy'), 'America/Los_Angeles');

-- Vault secrets the way the dispatcher has them, so the wake-up is posted.
select vault.create_secret('http://127.0.0.1:54321/functions/v1', 'wecord_functions_url');
select vault.create_secret('digest-test-secret', 'wecord_dispatch_secret');

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'group', public.create_group_conversation('Plan', array[pg_temp.i('bob'), pg_temp.i('cy')]);
insert into pg_temp.ids select 'group2', public.create_group_conversation('Trip', array[pg_temp.i('bob'), pg_temp.i('cy')]);
insert into pg_temp.ids select 'circle', public.create_circle('Digest club', array[pg_temp.i('bob'), pg_temp.i('cy')]);
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

-- Messages the person follows count as news in the last day.
create function pg_temp.news(who text) returns integer language sql as $$
  select public.ai_digest_news_count(pg_temp.i(who), now() - interval '24 hours', now())
$$;
grant execute on function pg_temp.news(text) to public;

-- The wake-ups for the digest action posted so far.
create function pg_temp.digest_wakes() returns integer language sql as $$
  select count(*)::integer from net.http_request_queue q
  where convert_from(q.body, 'UTF8')::jsonb->>'action' = 'digest'
$$;
grant execute on function pg_temp.digest_wakes() to public;

-- A delivery time that is [shift] from now on [who]'s clock (the same day).
create function pg_temp.deliver_at(who text, shift interval) returns time language plpgsql as $$
declare local_now timestamp; target timestamp;
begin
  local_now := now() at time zone public.notification_time_zone(pg_temp.i(who));
  target := local_now + shift;
  if target::date <> local_now::date then
    -- Midnight in the way: the nearest time still on the same day.
    return case when shift < interval '0' then time '00:00' else time '23:59' end;
  end if;
  return date_trunc('minute', target)::time;
end $$;
grant execute on function pg_temp.deliver_at(text, interval) to public;

-- ===================================== 1. following chats
do $$
declare g uuid := pg_temp.i('group'); ch uuid := pg_temp.i('channel'); s jsonb; n integer; dm uuid; me uuid;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  s := public.get_ai_digest_settings();
  perform pg_temp.expect((s->>'enabled')::boolean and s->>'deliver_at' = '08:00' and s->>'language' = 'en'
    and s->>'time_zone' = 'Asia/Shanghai' and (s->>'max_subscriptions')::int = 10 and s->'subscriptions' = '[]'::jsonb,
    'follow: the defaults, in the person''s own time zone, nothing followed');

  perform pg_temp.expect(public.set_ai_digest_subscription(g, true, 'zh') = 1, 'follow: a member follows a group');
  perform pg_temp.expect(public.set_ai_digest_subscription(g, true) = 1, 'follow: following twice is one subscription');
  perform pg_temp.expect(public.set_ai_digest_subscription(ch, true) = 2, 'follow: and a circle channel');
  s := public.get_ai_digest_settings();
  perform pg_temp.expect(s->>'language' = 'zh' and jsonb_array_length(s->'subscriptions') = 2, 'follow: the language the app sent is kept');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(s->'subscriptions') e where e->>'title' = 'Plan')
    and exists (select 1 from jsonb_array_elements(s->'subscriptions') e where e->>'circle_name' = 'Digest club'),
    'follow: names come back with the chats');

  -- Not a member, not a group.
  perform pg_temp.act(pg_temp.i('dee'));
  perform pg_temp.must_refuse(format('select public.set_ai_digest_subscription(%L, true)', g), 'follow: a stranger cannot follow a group');
  perform pg_temp.must_refuse(format('select public.set_ai_digest_subscription(%L, true)', ch), 'follow: a stranger cannot follow a circle channel');
  perform pg_temp.act(pg_temp.i('ada'));
  dm := public.get_note_to_self(true);
  perform pg_temp.must_refuse(format('select public.set_ai_digest_subscription(%L, true)', dm), 'follow: a note to self cannot be followed');
  insert into pg_temp.ids values ('note', dm);
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('ada'));
  dm := public.get_or_create_direct_conversation(pg_temp.i('bob'));
  perform pg_temp.must_refuse(format('select public.set_ai_digest_subscription(%L, true)', dm), 'follow: a private chat cannot be followed');
  perform pg_temp.must_refuse('select public.set_ai_digest_subscription(null, true)', 'follow: nothing is not a chat');

  -- Clients cannot write the tables themselves, nor read other people's.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.must_refuse(format('insert into public.ai_digest_subscriptions (user_id, conversation_id) values (%L, %L)', pg_temp.i('bob'), pg_temp.i('group2')),
    'follow: a client cannot insert a subscription itself');
  perform pg_temp.must_refuse('delete from public.ai_digest_subscriptions', 'follow: nor delete one');
  perform pg_temp.must_refuse(format('update public.ai_digest_settings set deliver_at = %L', '03:00'), 'follow: nor change the settings');
  perform pg_temp.must_refuse('select count(*) from public.ai_digests', 'follow: the digests table is closed');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.ai_digest_subscriptions') = 2, 'follow: a person reads their own subscriptions');
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.ai_digest_subscriptions') = 0, 'follow: and nobody else''s');

  -- Settings.
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.set_ai_digest_settings(null, '06:45:30', null);
  s := public.get_ai_digest_settings();
  perform pg_temp.expect(s->>'deliver_at' = '06:45' and (s->>'enabled')::boolean and s->>'language' = 'zh', 'settings: the time (whole minutes) is saved, the rest stays');
  perform public.set_ai_digest_settings(false, null, 'en');
  s := public.get_ai_digest_settings();
  perform pg_temp.expect(not (s->>'enabled')::boolean and s->>'language' = 'en' and s->>'deliver_at' = '06:45', 'settings: switched off, language changed');
  perform pg_temp.must_refuse($q$select public.set_ai_digest_settings(null, null, 'fr')$q$, 'settings: only English and Chinese');
  perform public.set_ai_digest_settings(true, null, null);

  perform pg_temp.act(null);
  perform pg_temp.must_refuse('select public.get_ai_digest_settings()', 'settings: nobody signed in reads nothing');
  perform pg_temp.must_refuse('select public.list_my_ai_digests()', 'settings: nor the cards');
end $$;

-- ===================================== 2. at most ten chats a person
do $$
declare gs uuid[] := '{}'; gid uuid; n integer; st text;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  for n in 1..10 loop
    gs := gs || public.create_group_conversation('Extra ' || n, array[pg_temp.i('bob'), pg_temp.i('cy')]);
  end loop;
  perform pg_temp.root();

  -- Bob follows two already; eight more fill the ten.
  perform pg_temp.act(pg_temp.i('bob'));
  for n in 1..8 loop
    perform public.set_ai_digest_subscription(gs[n], true);
  end loop;
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.ai_digest_subscriptions') = 10, 'limit: ten chats followed');
  st := pg_temp.state(format('select public.set_ai_digest_subscription(%L, true)', gs[9]));
  perform pg_temp.expect(st = '54000', 'limit: the eleventh is refused with SQLSTATE 54000 (got ' || st || ')');
  perform pg_temp.expect(pg_temp.msg(format('select public.set_ai_digest_subscription(%L, true)', gs[9])) like 'digest_limit%',
    'limit: and says digest_limit');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.ai_digest_subscriptions') = 10, 'limit: still ten');
  perform pg_temp.expect(public.set_ai_digest_subscription(pg_temp.i('group'), true) = 10, 'limit: following one already followed is fine at ten');

  -- The service role is held to it too, whoever writes.
  perform pg_temp.root();
  st := pg_temp.state(format('insert into public.ai_digest_subscriptions (user_id, conversation_id) values (%L, %L)', pg_temp.i('bob'), gs[9]));
  perform pg_temp.expect(st = '54000', 'limit: a direct insert (service role) is refused too');

  -- Another person has their own ten.
  perform pg_temp.act(pg_temp.i('cy'));
  for n in 1..10 loop
    perform public.set_ai_digest_subscription(gs[n], true);
  end loop;
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.ai_digest_subscriptions') = 10, 'limit: the limit is per person');

  -- Unfollowing makes room.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(public.set_ai_digest_subscription(gs[1], false) = 9, 'limit: unfollowing frees a place');
  perform pg_temp.expect(public.set_ai_digest_subscription(gs[9], true) = 10, 'limit: and the place can be used');
  perform pg_temp.root();
  insert into pg_temp.ids values ('extra1', gs[1]), ('extra9', gs[9]), ('extra2', gs[2]);

  -- Back to a small, known set for the rest: Bob follows Plan and the channel.
  delete from public.ai_digest_subscriptions where user_id in (pg_temp.i('bob'), pg_temp.i('cy'));
  insert into public.ai_digest_subscriptions (user_id, conversation_id)
  values (pg_temp.i('bob'), pg_temp.i('group')), (pg_temp.i('bob'), pg_temp.i('channel')),
         (pg_temp.i('cy'), pg_temp.i('group'));
end $$;

-- ===================================== 3. leaving and deleting
do $$
declare t uuid; u uuid := '00000000-0000-4000-8000-0000000000e1'; g uuid;
begin
  -- Leaving a chat ends the subscription; the others stay.
  insert into public.ai_digest_subscriptions (user_id, conversation_id)
  values (pg_temp.i('bob'), pg_temp.i('group2'));
  delete from public.conversation_members where conversation_id = pg_temp.i('group2') and user_id = pg_temp.i('bob');
  perform pg_temp.expect(not exists (select 1 from public.ai_digest_subscriptions where user_id = pg_temp.i('bob') and conversation_id = pg_temp.i('group2')),
    'leave: leaving a group ends the subscription');
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.ai_digest_subscriptions where user_id = %L', pg_temp.i('bob'))) = 2,
    'leave: Bob''s other subscriptions stay');
  perform pg_temp.expect(exists (select 1 from public.ai_digest_subscriptions where user_id = pg_temp.i('cy')),
    'leave: and other people''s');

  -- Deleting the account takes everything with it.
  insert into auth.users (id, email, instance_id, aud, role) values (u, 'gone@dg.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
  insert into public.profiles (id, username, display_name) values (u, 'gone_dg', 'Gone');
  insert into public.conversation_members (conversation_id, user_id) values (pg_temp.i('group'), u);
  insert into public.ai_digest_settings (user_id) values (u);
  insert into public.ai_digest_subscriptions (user_id, conversation_id) values (u, pg_temp.i('group'));
  insert into public.ai_digests (user_id, local_date, window_start, window_end, status, items)
  values (u, current_date, now() - interval '1 day', now(), 'done', '[]');
  delete from public.profiles where id = u;
  perform pg_temp.expect(not exists (select 1 from public.ai_digest_settings where user_id = u)
    and not exists (select 1 from public.ai_digest_subscriptions where user_id = u)
    and not exists (select 1 from public.ai_digests where user_id = u),
    'delete: deleting the account removes the settings, subscriptions and digests');

  -- Deleting a chat removes its subscriptions.
  perform pg_temp.act(pg_temp.i('ada'));
  g := public.create_group_conversation('Short lived', array[pg_temp.i('bob'), pg_temp.i('cy')]);
  perform pg_temp.root();
  insert into public.ai_digest_subscriptions (user_id, conversation_id) values (pg_temp.i('cy'), g);
  delete from public.conversations where id = g;
  perform pg_temp.expect(not exists (select 1 from public.ai_digest_subscriptions where conversation_id = g), 'delete: deleting a chat removes its subscriptions');
end $$;

-- ===================================== 4. what counts as news (the visibility rules)
do $$
declare
  g uuid := pg_temp.i('group'); ch uuid := pg_temp.i('channel'); m uuid; dm uuid; w uuid;
begin
  perform pg_temp.expect(pg_temp.news('bob') = 0, 'news: nothing said, no news');

  -- Bob's own message is not news to Bob.
  perform pg_temp.mk('bob', g, 'my own words');
  perform pg_temp.expect(pg_temp.news('bob') = 0, 'news: your own messages are not news');

  m := pg_temp.mk('cy', g, 'lunch at noon?');
  perform pg_temp.expect(pg_temp.news('bob') = 1, 'news: another member''s message is');
  perform pg_temp.expect(pg_temp.news('cy') = 1, 'news: Cy sees Bob''s message, not their own');

  -- Recalled, expired, held by the guard or an edit review.
  update public.messages set recalled_at = now() where id = m;
  perform pg_temp.expect(pg_temp.news('bob') = 0, 'news: a recalled message is not');
  update public.messages set recalled_at = null, expires_at = now() - interval '1 minute' where id = m;
  perform pg_temp.expect(pg_temp.news('bob') = 0, 'news: an expired (disappearing) message is not');
  update public.messages set expires_at = now() + interval '1 hour' where id = m;
  perform pg_temp.expect(pg_temp.news('bob') = 1, 'news: a disappearing message that has not expired is');
  update public.messages set expires_at = null, review_state = 'checking' where id = m;
  perform pg_temp.expect(pg_temp.news('bob') = 0, 'news: a message the AI guard is checking is not');
  update public.messages set review_state = 'held' where id = m;
  perform pg_temp.expect(pg_temp.news('bob') = 0, 'news: nor one it holds');
  update public.messages set review_state = null where id = m;
  perform pg_temp.expect(pg_temp.news('bob') = 1, 'news: released, it is');

  -- Notices, view-once pictures, AI replies, silent messages.
  insert into public.messages (conversation_id, sender_id, type, body, created_at)
    values (g, pg_temp.i('cy'), 'system', 'Cy joined', now() - interval '10 minutes');
  perform pg_temp.expect(pg_temp.news('bob') = 1, 'news: notices are not');
  insert into public.messages (conversation_id, sender_id, type, body, attachment, created_at)
    values (g, pg_temp.i('cy'), 'image', 'look', '{"kind":"image","view_once":true}', now() - interval '10 minutes');
  perform pg_temp.expect(pg_temp.news('bob') = 1, 'news: a view-once picture is not, even with a caption');
  insert into public.messages (conversation_id, sender_id, type, body, attachment, created_at)
    values (g, pg_temp.i('cy'), 'image', '', '{"kind":"image"}', now() - interval '10 minutes');
  perform pg_temp.expect(pg_temp.news('bob') = 1, 'news: a picture without words is not');
  insert into public.messages (conversation_id, sender_id, type, body, attachment, created_at)
    values (g, pg_temp.i('cy'), 'file', '', '{"kind":"file","name":"plan.pdf"}', now() - interval '10 minutes');
  perform pg_temp.expect(pg_temp.news('bob') = 2, 'news: a file is');
  insert into public.messages (conversation_id, sender_id, type, body, created_at, ai_reply)
    values (g, pg_temp.i('ada'), 'text', 'an AI answer', now() - interval '10 minutes', '{"kind":"answer"}');
  perform pg_temp.expect(pg_temp.news('bob') = 2, 'news: replies of the assistant are not');

  -- The window.
  perform pg_temp.mk('cy', g, 'two days ago', 60 * 48);
  perform pg_temp.expect(pg_temp.news('bob') = 2, 'news: older than the window is not');
  perform pg_temp.expect(public.ai_digest_news_count(pg_temp.i('bob'), now() - interval '5 minutes', now()) = 0, 'news: the window''s start is respected');
  insert into public.messages (conversation_id, sender_id, type, body, created_at)
    values (g, pg_temp.i('cy'), 'text', 'after the window', now() + interval '5 minutes');
  perform pg_temp.expect(pg_temp.news('bob') = 2, 'news: after the window''s end is not');
  delete from public.messages where body in ('two days ago', 'after the window', 'an AI answer');

  -- A sender blocked either way.
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.block_user(pg_temp.i('cy'));
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.news('bob') = 0, 'news: a sender Bob blocked is not');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.unblock_user(pg_temp.i('cy'));
  perform pg_temp.act(pg_temp.i('cy'));
  perform public.block_user(pg_temp.i('bob'));
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.news('bob') = 0, 'news: nor one who blocked Bob');
  perform pg_temp.act(pg_temp.i('cy'));
  perform public.unblock_user(pg_temp.i('bob'));
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.news('bob') = 2, 'news: unblocked, they are again');

  -- Not followed, not a member.
  perform pg_temp.mk('cy', pg_temp.i('extra2'), 'a chat Bob does not follow');
  perform pg_temp.expect(pg_temp.news('bob') = 2, 'news: a chat that is not followed is not');
  perform pg_temp.mk('ada', ch, 'news in the channel');
  perform pg_temp.expect(pg_temp.news('bob') = 3, 'news: a circle channel the person can read is');

  -- The group owner turns the assistant off in the group: no AI there.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_group_ai_assistant(g, false);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.news('bob') = 1, 'news: a group that turned WeCord AI off is not');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_group_ai_assistant(g, true);
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.news('bob') = 3, 'news: back on, it is');

  -- The circle turns AI off: no AI in its channels.
  update public.circles set ai_enabled = false where id = pg_temp.i('circle');
  perform pg_temp.expect(pg_temp.news('bob') = 2, 'news: a circle that turned AI off is not');
  update public.circles set ai_enabled = true where id = pg_temp.i('circle');
  perform pg_temp.expect(pg_temp.news('bob') = 3, 'news: back on, it is');

  -- A suspended circle cannot be read at all.
  update public.circles set disabled_mode = 'suspend', disabled_at = now() where id = pg_temp.i('circle');
  perform pg_temp.expect(pg_temp.news('bob') = 2, 'news: a circle taken down (suspended) is not');
  update public.circles set disabled_mode = null, disabled_at = null where id = pg_temp.i('circle');
  perform pg_temp.expect(pg_temp.news('bob') = 3, 'news: restored, it is');

  -- Not a member any more (the row is gone; so is the subscription).
  delete from public.conversation_members where conversation_id = ch and user_id = pg_temp.i('bob');
  perform pg_temp.expect(pg_temp.news('bob') = 2, 'news: a chat the person left is not');
  insert into public.conversation_members (conversation_id, user_id) values (ch, pg_temp.i('bob'));
  insert into public.ai_digest_subscriptions (user_id, conversation_id) values (pg_temp.i('bob'), ch);
  perform pg_temp.expect(pg_temp.news('bob') = 3, 'news: back in the chat and following it, it is');

  -- Messages were all made by hand; keep them for the next steps.
  perform pg_temp.expect((select count(*) from public.ai_digest_messages(pg_temp.i('bob'), now() - interval '24 hours', now())
    where conversation_id = ch) = 1, 'news: the channel message is attributed to the channel');
end $$;

-- ===================================== 5. the schedule: time zones, once a day
do $$
declare
  g uuid := pg_temp.i('group'); started integer; d public.ai_digests; wakes_before integer; prev_sub text;
  la timestamp := now() at time zone 'America/Los_Angeles';
begin
  -- Bob (Shanghai) wants it five minutes ago on his clock. Cy (Los Angeles)
  -- has the same wall-clock time, which is not now for Cy.
  update public.ai_digest_settings
  set language = 'zh', enabled = true, deliver_at = pg_temp.deliver_at('bob', interval '-5 minutes')
  where user_id = pg_temp.i('bob');
  update public.ai_digest_settings
  set language = 'en', enabled = true, deliver_at = pg_temp.deliver_at('bob', interval '-5 minutes')
  where user_id = pg_temp.i('cy');
  perform pg_temp.expect(pg_temp.news('cy') >= 1, 'tick: Cy has news too, so only the time zone keeps Cy out');

  prev_sub := current_setting('request.jwt.claim.sub', true);
  wakes_before := pg_temp.digest_wakes();
  started := public.ai_digest_tick();
  perform pg_temp.expect(started = 1, 'tick: one digest starts, Bob''s, at his own time (got ' || started || ')');
  select * into d from public.ai_digests where user_id = pg_temp.i('bob');
  perform pg_temp.expect(d.id is not null and d.status = 'queued' and d.language = 'zh'
    and d.local_date = (now() at time zone 'Asia/Shanghai')::date, 'tick: queued for Bob''s own date, in his language');
  perform pg_temp.expect(d.window_end = now() and d.window_start = now() - interval '24 hours',
    'tick: the first window is the last 24 hours');
  perform pg_temp.expect(not exists (select 1 from public.ai_digests where user_id = pg_temp.i('cy')),
    'tick: Cy''s clock has not reached that time: nothing for Cy');
  perform pg_temp.expect(pg_temp.digest_wakes() = wakes_before + 1 and exists (
      select 1 from net.http_request_queue q
      where q.url = 'http://127.0.0.1:54321/functions/v1/ai'
        and q.headers->>'Authorization' = 'Bearer digest-test-secret'
        and convert_from(q.body, 'UTF8')::jsonb->>'action' = 'digest'
        and convert_from(q.body, 'UTF8')::jsonb->>'digest_id' = d.id::text),
    'tick: the ai function is woken with the shared secret');
  perform pg_temp.expect(coalesce(current_setting('request.jwt.claim.sub', true), '') = coalesce(prev_sub, ''),
    'tick: the person it borrowed to check visibility is put back');
  insert into pg_temp.ids values ('digest_bob', d.id);

  -- Once a day.
  wakes_before := pg_temp.digest_wakes();
  perform pg_temp.expect(public.ai_digest_tick() = 0 and pg_temp.digest_wakes() = wakes_before,
    'tick: a second tick the same day starts nothing and wakes nothing');
  perform pg_temp.expect((select count(*) from public.ai_digests where user_id = pg_temp.i('bob')) = 1,
    'tick: one digest per person per day');

  -- Cy's time comes: Cy's own clock decides.
  update public.ai_digest_settings set deliver_at = pg_temp.deliver_at('cy', interval '-5 minutes') where user_id = pg_temp.i('cy');
  perform pg_temp.expect(public.ai_digest_tick() = 1, 'tick: at Cy''s time on Cy''s clock, Cy''s digest starts');
  perform pg_temp.expect((select local_date from public.ai_digests where user_id = pg_temp.i('cy')) = (now() at time zone 'America/Los_Angeles')::date,
    'tick: and carries Cy''s date');

  -- Not due yet.
  delete from public.ai_digests where user_id = pg_temp.i('cy');
  update public.ai_digest_settings set deliver_at = pg_temp.deliver_at('cy', interval '3 hours') where user_id = pg_temp.i('cy');
  perform pg_temp.expect(public.ai_digest_tick() = 0, 'tick: before the time, nothing');

  -- More than six hours late (an outage): wait for tomorrow.
  if la::time >= time '07:30' then
    update public.ai_digest_settings set deliver_at = pg_temp.deliver_at('cy', interval '-7 hours') where user_id = pg_temp.i('cy');
    perform pg_temp.expect(public.ai_digest_tick() = 0, 'tick: more than six hours late waits for tomorrow');
    update public.ai_digest_settings set deliver_at = pg_temp.deliver_at('cy', interval '-5 hours') where user_id = pg_temp.i('cy');
    perform pg_temp.expect(public.ai_digest_tick() = 1, 'tick: within the six hours it still goes');
    delete from public.ai_digests where user_id = pg_temp.i('cy');
  end if;

  -- Switched off, or nothing followed.
  update public.ai_digest_settings set deliver_at = pg_temp.deliver_at('cy', interval '-5 minutes'), enabled = false where user_id = pg_temp.i('cy');
  perform pg_temp.expect(public.ai_digest_tick() = 0, 'tick: switched off, nothing');
  update public.ai_digest_settings set enabled = true where user_id = pg_temp.i('cy');
  delete from public.ai_digest_subscriptions where user_id = pg_temp.i('cy');
  perform pg_temp.expect(public.ai_digest_tick() = 0 and not exists (select 1 from public.ai_digests where user_id = pg_temp.i('cy')),
    'tick: no chats followed, nothing');

  -- A zone nobody knows counts as UTC instead of breaking the tick.
  update public.user_notification_settings set timezone = 'Mars/Olympus' where user_id = pg_temp.i('cy');
  insert into public.ai_digest_subscriptions (user_id, conversation_id) values (pg_temp.i('cy'), g);
  perform public.ai_digest_tick();
  perform pg_temp.expect(true, 'tick: an unknown time zone does not stop the tick');
  update public.user_notification_settings set timezone = 'America/Los_Angeles' where user_id = pg_temp.i('cy');
  delete from public.ai_digests where user_id = pg_temp.i('cy');
end $$;

-- ===================================== 6. no news, no model
do $$
declare
  started integer; wakes_before integer; d public.ai_digests; claimed jsonb; empty uuid;
begin
  -- Cy follows only a chat where nothing was said (Trip).
  delete from public.ai_digest_subscriptions where user_id = pg_temp.i('cy');
  insert into public.ai_digest_subscriptions (user_id, conversation_id) values (pg_temp.i('cy'), pg_temp.i('group2'));
  update public.ai_digest_settings set deliver_at = pg_temp.deliver_at('cy', interval '-5 minutes'), enabled = true where user_id = pg_temp.i('cy');
  perform pg_temp.expect(pg_temp.news('cy') = 0, 'quiet: nothing was said in Cy''s chats');

  wakes_before := pg_temp.digest_wakes();
  started := public.ai_digest_tick();
  select * into d from public.ai_digests where user_id = pg_temp.i('cy');
  perform pg_temp.expect(started = 0 and d.status = 'skipped' and d.reason = 'no_news' and d.finished_at is not null,
    'quiet: the day is recorded as skipped (no_news)');
  perform pg_temp.expect(pg_temp.digest_wakes() = wakes_before,
    'quiet: the ai function is NOT woken, so the model is never asked');
  perform pg_temp.expect(public.ai_digest_claim(d.id) is null, 'quiet: nothing to claim');
  perform pg_temp.expect(public.ai_digest_tick() = 0, 'quiet: the same day does not try again');

  -- The next day's window starts where the quiet day's ended.
  update public.ai_digests
  set local_date = local_date - 1, window_start = now() - interval '26 hours', window_end = now() - interval '2 hours'
  where id = d.id;
  perform pg_temp.mk('bob', pg_temp.i('group2'), 'Trip news from Bob');
  perform pg_temp.expect(public.ai_digest_tick() = 1, 'quiet: news arrives, the next day a digest starts');
  perform pg_temp.expect((select window_start from public.ai_digests where user_id = pg_temp.i('cy') and status = 'queued') = now() - interval '2 hours',
    'quiet: its window starts where the last one ended');
  delete from public.ai_digests where user_id = pg_temp.i('cy');
  delete from public.messages where body = 'Trip news from Bob';

  -- The claim checks again: the news is gone by the time the function runs.
  insert into public.ai_digests (user_id, local_date, window_start, window_end, status)
  values (pg_temp.i('cy'), current_date + 30, now() - interval '24 hours', now(), 'queued')
  returning id into empty;
  claimed := public.ai_digest_claim(empty);
  perform pg_temp.expect(claimed->>'skipped' = 'no_news' and (select status from public.ai_digests where id = empty) = 'skipped',
    'quiet: the claim finds no news and closes the digest without a model call');
end $$;

-- ===================================== 7. the claim's gates
do $$
declare
  q uuid; c jsonb;
begin
  -- Switched off in the meantime.
  insert into public.ai_digests (user_id, local_date, window_start, window_end, status)
  values (pg_temp.i('bob'), current_date + 41, now() - interval '24 hours', now(), 'queued') returning id into q;
  update public.ai_digest_settings set enabled = false where user_id = pg_temp.i('bob');
  c := public.ai_digest_claim(q);
  perform pg_temp.expect(c->>'skipped' = 'off', 'gate: switched off since it was queued: skipped');
  update public.ai_digest_settings set enabled = true where user_id = pg_temp.i('bob');

  -- The person turned AI off.
  insert into public.ai_digests (user_id, local_date, window_start, window_end, status)
  values (pg_temp.i('bob'), current_date + 42, now() - interval '24 hours', now(), 'queued') returning id into q;
  insert into public.user_ai_settings (user_id, ai_enabled) values (pg_temp.i('bob'), false);
  c := public.ai_digest_claim(q);
  perform pg_temp.expect(c->>'skipped' = 'user_off', 'gate: the person turned AI off: skipped');
  update public.user_ai_settings set ai_enabled = true where user_id = pg_temp.i('bob');

  -- Every followed chat turned AI off.
  insert into public.ai_digests (user_id, local_date, window_start, window_end, status)
  values (pg_temp.i('bob'), current_date + 43, now() - interval '24 hours', now(), 'queued') returning id into q;
  update public.circles set ai_enabled = false where id = pg_temp.i('circle');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_group_ai_assistant(pg_temp.i('group'), false);
  perform pg_temp.root();
  c := public.ai_digest_claim(q);
  perform pg_temp.expect(c->>'skipped' = 'no_news', 'gate: the circle and the group turned AI off: nothing to read, skipped');
  update public.circles set ai_enabled = true where id = pg_temp.i('circle');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_group_ai_assistant(pg_temp.i('group'), true);
  perform pg_temp.root();

  -- Nothing followed any more.
  insert into public.ai_digests (user_id, local_date, window_start, window_end, status)
  values (pg_temp.i('bob'), current_date + 44, now() - interval '24 hours', now(), 'queued') returning id into q;
  create temp table kept_subs on commit drop as
    select * from public.ai_digest_subscriptions where user_id = pg_temp.i('bob');
  delete from public.ai_digest_subscriptions where user_id = pg_temp.i('bob');
  c := public.ai_digest_claim(q);
  perform pg_temp.expect(c->>'skipped' = 'no_subscriptions', 'gate: no chats followed: skipped');
  insert into public.ai_digest_subscriptions select * from kept_subs;

  perform pg_temp.expect((select count(*) from public.ai_digests
    where user_id = pg_temp.i('bob') and local_date between current_date + 41 and current_date + 44 and status = 'skipped') = 4,
    'gate: every skipped digest is closed');
end $$;

-- ===================================== 8. what the model may read
do $$
declare
  bid uuid := pg_temp.i('digest_bob'); c jsonb; ctx jsonb; grp jsonb; chn jsonb; ok boolean; held uuid;
  wakes integer;
begin
  perform pg_temp.expect(public.ai_digest_context(bid) is null, 'context: nothing before the digest is claimed');
  c := public.ai_digest_claim(bid);
  perform pg_temp.expect(c->>'digest_id' = bid::text and c->>'language' = 'zh' and c->>'time_zone' = 'Asia/Shanghai'
    and c->>'user_id' = pg_temp.i('bob')::text, 'claim: the digest, its language and the person''s zone');
  perform pg_temp.expect((select status from public.ai_digests where id = bid) = 'running', 'claim: it is running now');
  perform pg_temp.expect(public.ai_digest_claim(bid) is null, 'claim: nobody else takes it');

  -- Things that become invisible before the model reads: held, recalled.
  held := pg_temp.mk('cy', pg_temp.i('group'), 'held for review', 20);
  update public.messages set review_state = 'held' where id = held;
  perform pg_temp.mk('cy', pg_temp.i('group'), 'something to recall', 20);
  update public.messages set recalled_at = now() where body = 'something to recall';

  ctx := public.ai_digest_context(bid);
  perform pg_temp.expect(jsonb_array_length(ctx->'conversations') = 2, 'context: the two followed chats with news');
  select e into grp from jsonb_array_elements(ctx->'conversations') e where e->>'conversation_id' = pg_temp.i('group')::text;
  select e into chn from jsonb_array_elements(ctx->'conversations') e where e->>'conversation_id' = pg_temp.i('channel')::text;
  perform pg_temp.expect(grp->>'title' = 'Plan' and (grp->>'total')::int = 2 and jsonb_array_length(grp->'messages') = 2,
    'context: the group, its name and the two visible messages (got ' || coalesce(grp->>'total', 'none') || ')');
  perform pg_temp.expect(chn->>'circle_name' = 'Digest club' and jsonb_array_length(chn->'messages') = 1 and (chn->>'total')::int = 1,
    'context: the circle channel with its circle');
  perform pg_temp.expect(grp::text not like '%held for review%' and grp::text not like '%something to recall%' and grp::text not like '%my own words%',
    'context: no held, no recalled, nothing Bob wrote himself');
  perform pg_temp.expect(grp->'messages'->0->>'sender' = 'Cy' and grp->'messages'->0->>'body' = 'lunch at noon?'
    and grp->'messages'->1->'attachment'->>'name' = 'plan.pdf' and grp->'messages'->1->>'type' = 'file',
    'context: oldest first, names, a file as its name');
  perform pg_temp.expect(ctx::text not like '%a chat Bob does not follow%', 'context: nothing from a chat Bob does not follow');

  -- A person who may no longer read a chat gets nothing from it.
  update public.circles set disabled_mode = 'suspend', disabled_at = now() where id = pg_temp.i('circle');
  perform pg_temp.expect(jsonb_array_length(public.ai_digest_context(bid)->'conversations') = 1, 'context: a suspended circle is out');
  update public.circles set disabled_mode = null, disabled_at = null where id = pg_temp.i('circle');

  -- Handing in the card.
  select count(*) into wakes from net.http_request_queue q where q.url = 'http://127.0.0.1:54321/functions/v1/scheduled-dispatch';
  ok := public.ai_digest_finish(bid, jsonb_build_array(
    jsonb_build_object('conversation_id', pg_temp.i('group'), 'summary', E'- Cy asks about lunch\n- A plan was shared', 'message_count', 2),
    jsonb_build_object('conversation_id', pg_temp.i('channel'), 'summary', '- News in the channel', 'message_count', 1),
    jsonb_build_object('conversation_id', pg_temp.i('extra2'), 'summary', 'a chat Bob does not follow', 'message_count', 1),
    jsonb_build_object('conversation_id', pg_temp.i('group2'), 'summary', '', 'message_count', 1),
    jsonb_build_object('conversation_id', 'not-a-uuid', 'summary', 'x', 'message_count', 1)
  ));
  perform pg_temp.expect(ok and (select status = 'done' and jsonb_array_length(items) = 2 and finished_at is not null from public.ai_digests where id = bid),
    'finish: done, keeping only followed chats with a summary');
  perform pg_temp.expect((select count(*) from net.http_request_queue q where q.url = 'http://127.0.0.1:54321/functions/v1/scheduled-dispatch') > wakes,
    'finish: the push function is woken');
  perform pg_temp.expect(not public.ai_digest_finish(bid, '[]'), 'finish: a digest that is not running cannot be finished again');

  -- A hand-in with nothing usable closes the digest as failed.
  insert into public.ai_digests (user_id, local_date, window_start, window_end, status, started_at)
  values (pg_temp.i('bob'), current_date + 50, now() - interval '24 hours', now(), 'running', now()) returning id into held;
  perform pg_temp.expect(not public.ai_digest_finish(held, jsonb_build_array(jsonb_build_object('conversation_id', pg_temp.i('extra2'), 'summary', 'x'))),
    'finish: nothing for a followed chat is a failure');
  perform pg_temp.expect((select status || reason from public.ai_digests where id = held) = 'failederror', 'finish: recorded as failed');
  insert into public.ai_digests (user_id, local_date, window_start, window_end, status, started_at)
  values (pg_temp.i('bob'), current_date + 51, now() - interval '24 hours', now(), 'running', now()) returning id into held;
  perform pg_temp.must_refuse(format('select public.ai_digest_finish(%L, %L::jsonb)', held, '{"a":1}'), 'finish: items must be a list');
  perform pg_temp.expect(public.ai_digest_finish(held, jsonb_build_array(jsonb_build_object('conversation_id', pg_temp.i('group'), 'summary', repeat('x', 2001)))) = false,
    'finish: a summary over 2000 characters is dropped');

  -- Closing without a card.
  insert into public.ai_digests (user_id, local_date, window_start, window_end, status, started_at)
  values (pg_temp.i('bob'), current_date + 52, now() - interval '24 hours', now(), 'running', now()) returning id into held;
  perform public.ai_digest_close(held, 'limited', 'limit');
  perform pg_temp.expect((select status || reason from public.ai_digests where id = held) = 'limitedlimit', 'close: limited, with its reason');
  perform pg_temp.must_refuse(format('select public.ai_digest_close(%L, %L, %L)', held, 'done', 'x'), 'close: not a way to write a card');
end $$;

-- ===================================== 9. the card in Notifications
do $$
declare cards jsonb; id1 uuid := pg_temp.i('digest_bob');
begin
  perform pg_temp.act(pg_temp.i('bob'));
  select jsonb_agg(to_jsonb(x)) into cards from public.list_my_ai_digests() x;
  perform pg_temp.expect(jsonb_array_length(cards) = 1 and cards->0->>'id' = id1::text and cards->0->>'read_at' is null,
    'card: Bob''s finished digest, unread (the failed, skipped and limited ones are not listed)');
  perform pg_temp.expect(jsonb_array_length(cards->0->'items') = 2 and cards->0->'items'->0->>'title' is not null
    and cards->0->'items'->0->>'summary' like '- Cy asks about lunch%' and (cards->0->'items'->0->>'message_count')::int = 2,
    'card: both chats, with name, summary and count');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(cards->0->'items') e where e->>'circle_name' = 'Digest club'),
    'card: the circle''s name is on its channel');

  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.list_my_ai_digests()') = 0, 'card: nobody else sees it');
  perform public.mark_ai_digests_read(array[id1]);
  perform pg_temp.root();
  perform pg_temp.expect((select read_at is null from public.ai_digests where id = id1), 'card: nobody else can mark it read');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.mark_ai_digests_read(array[id1]);
  perform pg_temp.root();
  perform pg_temp.expect((select read_at is not null from public.ai_digests where id = id1), 'card: Bob marks it read');

  -- Leaving a chat takes its part out of the card.
  delete from public.conversation_members where conversation_id = pg_temp.i('channel') and user_id = pg_temp.i('bob');
  perform pg_temp.act(pg_temp.i('bob'));
  select jsonb_agg(to_jsonb(x)) into cards from public.list_my_ai_digests() x;
  perform pg_temp.expect(jsonb_array_length(cards->0->'items') = 1, 'card: the chat Bob left is gone from the card');
  perform pg_temp.root();
  delete from public.conversation_members where conversation_id = pg_temp.i('group') and user_id = pg_temp.i('bob');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.list_my_ai_digests()') = 0, 'card: nothing left, no card');
  perform pg_temp.root();
  insert into public.conversation_members (conversation_id, user_id) values (pg_temp.i('group'), pg_temp.i('bob')), (pg_temp.i('channel'), pg_temp.i('bob'));
  insert into public.ai_digest_subscriptions (user_id, conversation_id) values (pg_temp.i('bob'), pg_temp.i('group')), (pg_temp.i('bob'), pg_temp.i('channel'));
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.list_my_ai_digests()') = 1, 'card: back in the chats, the card is back');

  -- A suspended circle's channel is hidden from the card too.
  perform pg_temp.root();
  update public.circles set disabled_mode = 'suspend', disabled_at = now() where id = pg_temp.i('circle');
  perform pg_temp.act(pg_temp.i('bob'));
  select jsonb_agg(to_jsonb(x)) into cards from public.list_my_ai_digests() x;
  perform pg_temp.expect(jsonb_array_length(cards->0->'items') = 1, 'card: a chat Bob may not read is not in the card');
  perform pg_temp.root();
  update public.circles set disabled_mode = null, disabled_at = null where id = pg_temp.i('circle');

  -- Old cards go.
  update public.ai_digests set finished_at = now() - interval '8 days' where id = id1;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.list_my_ai_digests()') = 0, 'card: after a week it is not listed');
  perform pg_temp.root();
  update public.ai_digests set finished_at = now() where id = id1;
end $$;

-- ===================================== 10. the push
do $$
declare rows_ jsonb; id1 uuid := pg_temp.i('digest_bob'); old_id uuid; dnd_id uuid; n integer;
begin
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
  values (pg_temp.i('bob'), 'https://push.test/bob-zh', repeat('k', 60), repeat('a', 16), 'zh'),
         (pg_temp.i('bob'), 'https://push.test/bob-en', repeat('k', 60), repeat('a', 16), 'en');

  select jsonb_agg(to_jsonb(x) order by x.endpoint) into rows_ from public.claim_digest_pushes() x;
  perform pg_temp.expect(jsonb_array_length(rows_) = 2, 'push: one push per device');
  perform pg_temp.expect(rows_->0->>'title' = 'Your daily digest is ready' and rows_->0->>'body' = '2 chats have news. Open WeCord to catch up.'
    and rows_->1->>'title' = '今日速览已就绪' and rows_->1->>'body' = '2 个聊天有新动态，点开看看。', 'push: in each device''s language');
  perform pg_temp.expect(rows_->0->>'tag' = 'ai-digest-' || id1::text and rows_->0->>'url' = '/#/notifications', 'push: tagged per digest, opens Notifications');
  perform pg_temp.expect(rows_::text not like '%lunch%' and rows_::text not like '%Cy%' and rows_::text not like '%Plan%',
    'push: no chat content on the lock screen');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.claim_digest_pushes()') = 0, 'push: each digest is pushed once');

  -- Too old: closed without a push. Do Not Disturb: closed without a push.
  insert into public.ai_digests (user_id, local_date, window_start, window_end, status, items, finished_at)
  values (pg_temp.i('bob'), current_date + 60, now() - interval '2 days', now() - interval '1 day', 'done',
    jsonb_build_array(jsonb_build_object('conversation_id', pg_temp.i('group'), 'summary', 'x', 'message_count', 1)),
    now() - interval '20 minutes') returning id into old_id;
  n := pg_temp.cnt('select 1 from public.claim_digest_pushes()');
  perform pg_temp.expect(n = 0 and (select push_claimed_at is not null from public.ai_digests where id = old_id),
    'push: a digest older than 15 minutes is closed without a push');
  insert into public.ai_digests (user_id, local_date, window_start, window_end, status, items, finished_at)
  values (pg_temp.i('bob'), current_date + 61, now() - interval '2 days', now() - interval '1 day', 'done',
    jsonb_build_array(jsonb_build_object('conversation_id', pg_temp.i('group'), 'summary', 'x', 'message_count', 1)),
    now()) returning id into dnd_id;
  insert into public.user_privacy_settings (user_id, presence_status) values (pg_temp.i('bob'), 'dnd')
  on conflict (user_id) do update set presence_status = 'dnd';
  n := pg_temp.cnt('select 1 from public.claim_digest_pushes()');
  perform pg_temp.expect(n = 0 and (select push_claimed_at is not null from public.ai_digests where id = dnd_id),
    'push: Do Not Disturb: no push (the card still waits)');
  update public.user_privacy_settings set presence_status = 'online' where user_id = pg_temp.i('bob');

  -- A digest that is not done is never pushed.
  insert into public.ai_digests (user_id, local_date, window_start, window_end, status, finished_at)
  values (pg_temp.i('bob'), current_date + 62, now() - interval '2 days', now() - interval '1 day', 'skipped', now());
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.claim_digest_pushes()') = 0, 'push: a skipped day is not pushed');
  delete from public.ai_digests where local_date >= current_date + 60 and user_id = pg_temp.i('bob');
end $$;

-- ===================================== 11. the sweep
do $$
declare lost uuid; dead uuid; stuck uuid; old uuid; keep uuid; before_wakes integer;
begin
  insert into public.ai_digests (user_id, local_date, window_start, window_end, status, woken_at, wake_count)
  values (pg_temp.i('ada'), current_date + 70, now() - interval '1 day', now(), 'queued', now() - interval '2 minutes', 1) returning id into lost;
  insert into public.ai_digests (user_id, local_date, window_start, window_end, status, woken_at, wake_count)
  values (pg_temp.i('ada'), current_date + 71, now() - interval '1 day', now(), 'queued', now() - interval '2 minutes', 3) returning id into dead;
  insert into public.ai_digests (user_id, local_date, window_start, window_end, status, started_at)
  values (pg_temp.i('ada'), current_date + 72, now() - interval '1 day', now(), 'running', now() - interval '5 minutes') returning id into stuck;
  insert into public.ai_digests (user_id, local_date, window_start, window_end, status, finished_at)
  values (pg_temp.i('ada'), current_date + 73, now() - interval '1 day', now(), 'skipped', now() - interval '15 days') returning id into old;
  insert into public.ai_digests (user_id, local_date, window_start, window_end, status, started_at)
  values (pg_temp.i('ada'), current_date + 74, now() - interval '1 day', now(), 'running', now() - interval '1 minute') returning id into keep;
  select count(*) into before_wakes from net.http_request_queue q where convert_from(q.body, 'UTF8')::jsonb->>'digest_id' = lost::text;

  perform public.ai_digest_tick();

  perform pg_temp.expect((select wake_count = 2 from public.ai_digests where id = lost)
    and (select count(*) from net.http_request_queue q where convert_from(q.body, 'UTF8')::jsonb->>'digest_id' = lost::text) = before_wakes + 1,
    'sweep: a lost wake-up is sent again');
  perform pg_temp.expect((select status = 'failed' and reason = 'timeout' from public.ai_digests where id = dead), 'sweep: three wake-ups and still nothing: failed');
  perform pg_temp.expect((select status = 'failed' and reason = 'timeout' from public.ai_digests where id = stuck), 'sweep: a run that never came back: failed');
  perform pg_temp.expect(not exists (select 1 from public.ai_digests where id = old), 'sweep: old digests are removed');
  perform pg_temp.expect((select status from public.ai_digests where id = keep) = 'running', 'sweep: a run in progress is left alone');
  perform pg_temp.expect((select status from public.ai_digests where id = lost) = 'queued', 'sweep: the re-woken digest stays queued');
  delete from public.ai_digests where user_id = pg_temp.i('ada');
end $$;

-- ===================================== 12. the data export
do $$
declare e jsonb;
begin
  e := public.export_my_ai_digest(pg_temp.i('bob'));
  perform pg_temp.expect((e->>'enabled')::boolean and e->>'language' = 'zh' and e->>'time_zone' = 'Asia/Shanghai'
    and e->>'deliver_at' ~ '^[0-9]{2}:[0-9]{2}$' and jsonb_array_length(e->'subscriptions') = 2,
    'export: the switch, time, language, zone and the two chats');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(e->'subscriptions') s where s->>'name' = 'Plan')
    and exists (select 1 from jsonb_array_elements(e->'subscriptions') s where s->>'circle' = 'Digest club'),
    'export: the chats by name');
  perform pg_temp.expect(e::text not like '%lunch%', 'export: no digest text (other people''s words) in it');
  e := public.export_my_ai_digest(pg_temp.i('dee'));
  perform pg_temp.expect(not (e->>'enabled')::boolean and e->'subscriptions' = '[]'::jsonb, 'export: a person who never used it: off, nothing followed');
  perform pg_temp.must_refuse('select public.export_my_ai_digest(null)', 'export: a user is required');
end $$;

-- ===================================== 13. who may call what
do $$
declare f text;
begin
  perform pg_temp.act(pg_temp.i('bob'));
  foreach f in array array[
    'select public.ai_digest_tick()',
    format('select public.ai_digest_claim(%L)', gen_random_uuid()),
    format('select public.ai_digest_context(%L)', gen_random_uuid()),
    format('select public.ai_digest_finish(%L, %L::jsonb)', gen_random_uuid(), '[]'),
    format('select public.ai_digest_close(%L, %L, %L)', gen_random_uuid(), 'failed', 'x'),
    format('select * from public.ai_digest_messages(%L, now() - interval %L, now())', pg_temp.i('cy'), '1 day'),
    format('select public.ai_digest_news_count(%L, now() - interval %L, now())', pg_temp.i('cy'), '1 day'),
    'select * from public.claim_digest_pushes()',
    format('select public.export_my_ai_digest(%L)', pg_temp.i('cy')),
    'select public.install_ai_digest_schedule()'
  ] loop
    perform pg_temp.must_refuse(f, 'permissions: a signed-in person cannot call ' || left(f, 48));
  end loop;
  perform pg_temp.act(null);
  perform pg_temp.must_refuse('select public.get_ai_digest_settings()', 'permissions: nobody signed in has no settings');
  perform pg_temp.must_refuse(format('select public.set_ai_digest_subscription(%L, true)', pg_temp.i('group')), 'permissions: nor follows');
  perform pg_temp.root();
  perform pg_temp.expect(has_function_privilege('service_role', 'public.ai_digest_tick()', 'execute')
    and has_function_privilege('service_role', 'public.claim_digest_pushes()', 'execute')
    and has_function_privilege('service_role', 'public.ai_digest_claim(uuid)', 'execute')
    and has_function_privilege('service_role', 'public.export_my_ai_digest(uuid)', 'execute'),
    'permissions: the service role can');
  perform pg_temp.expect(not has_table_privilege('authenticated', 'public.ai_digests', 'select')
    and not has_table_privilege('authenticated', 'public.ai_digest_subscriptions', 'insert')
    and not has_table_privilege('authenticated', 'public.ai_digest_settings', 'update'),
    'permissions: the tables are closed to writes, the digests to reads');
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform pg_temp.expect(exists (select 1 from cron.job where jobname = 'wecord-ai-digest-tick'), 'schedule: the tick is scheduled every minute');
  end if;
end $$;

\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'daily digest: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
