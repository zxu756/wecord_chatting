-- Behaviour checks for the @WeCord AI assistant (F2: migrations 202610230400
-- to 202610230430) and what the `ai` function reads for it. Run by
-- test/supabase/ai_assistant_test.dart against the local database: it applies
-- the migrations it needs in a transaction, plays people through the API and
-- the service role, and rolls everything back. Run from the repository root.
--
-- What it walks through: which texts count as a mention and which context
-- range they ask for; that only visible messages queue a job (held ones queue
-- when released, not after an edit, not for bots); the rate limit; who can read
-- the job queue; the gates the claim checks (circle, group owner, requester's
-- switch, membership, stale, recalled); that the context holds only what the
-- requester can see and respects the range; the assistant's identity; and
-- posting, marking and reporting an AI reply.
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
\i supabase/migrations/202610230400_ai_assistant_identity.sql
\i supabase/migrations/202610230410_ai_assistant_jobs.sql
\i supabase/migrations/202610230420_ai_assistant_rpcs.sql
\i supabase/migrations/202610230430_ai_reply_channel_send.sql
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
-- nobody's member. Ada is friends with Bob, Cy and Dee.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '@aa.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from (values ('a1','ada'),('a2','bob'),('a3','cy'),('a4','dee')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '_aa', initcap(name)
from (values ('a1','ada'),('a2','bob'),('a3','cy'),('a4','dee')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || n)::uuid
from (values ('a1','ada'),('a2','bob'),('a3','cy'),('a4','dee')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(x.a, x.b), greatest(x.a, x.b)
from (values
  (pg_temp.i('ada'), pg_temp.i('bob')),
  (pg_temp.i('ada'), pg_temp.i('cy')),
  (pg_temp.i('ada'), pg_temp.i('dee'))
) x(a, b);

-- Vault secrets the way the dispatcher has them, so the wake-up is posted.
select vault.create_secret('http://127.0.0.1:54321/functions/v1', 'wecord_functions_url');
select vault.create_secret('assistant-test-secret', 'wecord_dispatch_secret');

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'group', public.create_group_conversation('Plan', array[pg_temp.i('bob'), pg_temp.i('cy')]);
insert into pg_temp.ids select 'circle', public.create_circle('AI club', array[pg_temp.i('bob'), pg_temp.i('cy')]);
select pg_temp.root();
insert into pg_temp.ids
select 'channel', cc.conversation_id from public.circle_channels cc where cc.circle_id = pg_temp.i('circle') order by cc.created_at limit 1;
insert into public.conversation_members (conversation_id, user_id, role)
select pg_temp.i('channel'), cm.user_id, cm.role
from public.circle_members cm where cm.circle_id = pg_temp.i('circle')
on conflict do nothing;

-- Sends [body] in [conv] as [who]; the message id.
-- Messages sent in one transaction would share a created_at, so the time is
-- set apart; and the person's earlier jobs are moved out of the rate limit's
-- minute unless [keep] (the rate limit test).
create function pg_temp.say(who text, conv uuid, body text, reply uuid default null, keep boolean default false) returns uuid language plpgsql as $$
declare mid uuid;
begin
  if not keep then
    update public.ai_jobs set created_at = created_at - interval '2 minutes'
    where requester_id = pg_temp.i(who) and created_at > now() - interval '1 minute';
  end if;
  perform pg_temp.act(pg_temp.i(who));
  mid := public.send_text_message(conv, body, reply, null, '[]'::jsonb, null);
  perform pg_temp.root();
  update public.messages set created_at = clock_timestamp() where id = mid;
  return mid;
end $$;
grant execute on function pg_temp.say(text, uuid, text, uuid, boolean) to public;

create function pg_temp.job(mid uuid) returns public.ai_jobs language sql as $$
  select * from public.ai_jobs where message_id = mid
$$;
grant execute on function pg_temp.job(uuid) to public;

-- ===================================== 0. what counts as a mention
do $$
begin
  perform pg_temp.expect(public.ai_assistant_mention('@WeCord AI summarize') = 0, 'mention: the plain mention asks for no history');
  perform pg_temp.expect(public.ai_assistant_mention('@wecord ai hello') = 0, 'mention: any case');
  perform pg_temp.expect(public.ai_assistant_mention('@wecord_ai hello') = 0, 'mention: the underscore form');
  perform pg_temp.expect(public.ai_assistant_mention('hey @WeCord AI, what now?') = 0, 'mention: inside a sentence');
  perform pg_temp.expect(public.ai_assistant_mention('@WeCord AI /20 what did we decide') = 20, 'mention: /20');
  perform pg_temp.expect(public.ai_assistant_mention('@WeCord AI /100') = 100, 'mention: /100');
  perform pg_temp.expect(public.ai_assistant_mention('@WeCord AI   /20 x') = 20, 'mention: spaces before the range');
  perform pg_temp.expect(public.ai_assistant_mention('@WeCord AI总结一下') = 0, 'mention: Chinese right after it');
  perform pg_temp.expect(public.ai_assistant_mention('@WeCord AI /50 x') = 0, 'mention: other ranges are text, not a range');
  perform pg_temp.expect(public.ai_assistant_mention('@WeCord AI /200 x') = 0, 'mention: /200 is not /20');
  perform pg_temp.expect(public.ai_assistant_mention('see me@wecord ai.example') is null, 'mention: not inside an address');
  perform pg_temp.expect(public.ai_assistant_mention('@WeCord AIs rule') is null, 'mention: not a longer name');
  perform pg_temp.expect(public.ai_assistant_mention('WeCord AI is great') is null, 'mention: no @, no mention');
  perform pg_temp.expect(public.ai_assistant_mention('@everyone') is null, 'mention: other mentions');
  perform pg_temp.expect(public.ai_assistant_mention(null) is null, 'mention: null');
end $$;

-- ===================================== 1. the trigger queues only on a mention
do $$
declare g uuid := pg_temp.i('group'); m1 uuid; m2 uuid; m3 uuid; m4 uuid; j public.ai_jobs;
begin
  perform pg_temp.say('bob', g, 'good morning');
  perform pg_temp.say('cy', g, 'we should talk about the trip @everyone');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.ai_jobs') = 0, 'queue: ordinary messages queue nothing');

  m1 := pg_temp.say('ada', g, '@WeCord AI summarize the plan');
  j := pg_temp.job(m1);
  perform pg_temp.expect(j.id is not null and j.status = 'queued', 'queue: a mention queues a job');
  perform pg_temp.expect(j.requester_id = pg_temp.i('ada') and j.conversation_id = g and j.context_count = 0,
    'queue: the job names the requester, the chat and no history');
  perform pg_temp.expect(exists (
      select 1 from net.http_request_queue q
      where q.url = 'http://127.0.0.1:54321/functions/v1/ai'
        and q.headers->>'Authorization' = 'Bearer assistant-test-secret'
        and convert_from(q.body, 'UTF8')::jsonb->>'action' = 'assistant'
        and convert_from(q.body, 'UTF8')::jsonb->>'job_id' = j.id::text),
    'queue: the database woke the ai function with the shared secret');
  insert into pg_temp.ids values ('m1', m1);

  m2 := pg_temp.say('bob', g, 'Hi @wecord_ai /100 list the to-dos');
  perform pg_temp.expect((pg_temp.job(m2)).context_count = 100, 'queue: the range is read from the text');
  m3 := pg_temp.say('cy', g, 'what about @WeCord AI /20 this?');
  perform pg_temp.expect((pg_temp.job(m3)).context_count = 20 and (pg_temp.job(m3)).requester_id = pg_temp.i('cy'), 'queue: anybody can ask, /20');

  -- Not text, not queued.
  insert into public.messages (conversation_id, sender_id, type, body)
    values (g, pg_temp.i('ada'), 'system', '@WeCord AI joined');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.ai_jobs') = 3, 'queue: notices never queue');

  -- A bot does not queue either.
  insert into auth.users (id, email, instance_id, aud, role, raw_app_meta_data)
    values ('00000000-0000-4000-8000-0000000000b0', 'bot0@aa.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"provider":"bot"}');
  insert into public.profiles (id, username, display_name, is_bot)
    values ('00000000-0000-4000-8000-0000000000b0', 'bot0_aa', 'Bot Zero', true);
  insert into public.conversation_members (conversation_id, user_id) values (g, '00000000-0000-4000-8000-0000000000b0');
  insert into public.messages (conversation_id, sender_id, type, body)
    values (g, '00000000-0000-4000-8000-0000000000b0', 'text', '@WeCord AI loop loop loop');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.ai_jobs') = 3, 'queue: a bot cannot start the assistant (no loops)');

  -- Editing a message into a mention does not queue; only sending does.
  m4 := pg_temp.say('bob', g, 'nothing here');
  perform pg_temp.act(pg_temp.i('bob'));
  perform public.edit_message(m4, '@WeCord AI after the fact');
  perform pg_temp.root();
  perform pg_temp.expect((pg_temp.job(m4)).id is null, 'queue: an edit does not start the assistant');
end $$;

-- ===================================== 2. the rate limit
do $$
declare g uuid := pg_temp.i('group'); m uuid; n integer;
begin
  -- Five fit in a minute, the sixth is skipped.
  for n in 1..6 loop
    m := pg_temp.say('bob', g, '@WeCord AI again ' || n, null, true);
  end loop;
  perform pg_temp.expect((select count(*) from public.ai_jobs where requester_id = pg_temp.i('bob') and status = 'queued' and created_at > now() - interval '1 minute') = 5,
    'rate: five queued per minute');
  perform pg_temp.expect((pg_temp.job(m)).status = 'skipped' and (pg_temp.job(m)).reason = 'rate_limited',
    'rate: the sixth is skipped as rate_limited');
  perform pg_temp.expect(not exists (
      select 1 from net.http_request_queue q
      where convert_from(q.body, 'UTF8')::jsonb->>'job_id' = (pg_temp.job(m)).id::text),
    'rate: a skipped job wakes nobody');
  -- Another person is not affected.
  perform pg_temp.expect((pg_temp.job(pg_temp.say('cy', g, '@WeCord AI cy asks again', null, true))).status = 'queued', 'rate: the limit is per person');
end $$;

-- ===================================== 3. held messages
do $$
declare c uuid := pg_temp.i('circle'); ch uuid := pg_temp.i('channel'); held uuid; spam uuid; j public.ai_jobs;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_ai_guard(c, true, 'joined_days', 3, 10, 'hold');
  perform pg_temp.root();
  held := pg_temp.say('cy', ch, '@WeCord AI /20 what is going on here');
  perform pg_temp.expect((select review_state from public.messages where id = held) = 'checking', 'held: the guard holds the new member''s message');
  perform pg_temp.expect((pg_temp.job(held)).id is null, 'held: a held message queues nothing');
  insert into pg_temp.ids values ('held', held);

  perform public.finish_message_review(held, 'allow', null, null);
  j := pg_temp.job(held);
  perform pg_temp.expect((select review_state from public.messages where id = held) is null and j.id is not null and j.status = 'queued',
    'held: it queues when the guard releases it');
  perform pg_temp.expect(j.context_count = 20, 'held: with the range it asked for');

  -- A message the guard keeps held stays unasked.
  spam := pg_temp.say('cy', ch, '@WeCord AI win cheap pills');
  perform public.finish_message_review(spam, 'spam', 'junk', null);
  perform pg_temp.expect((select review_state from public.messages where id = spam) = 'held' and (pg_temp.job(spam)).id is null,
    'held: a message the guard keeps held never queues');
  insert into pg_temp.ids values ('spam', spam);

  -- A moderator's later release queues it when it is recent.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.decide_message_review(spam, 'approve');
  perform pg_temp.root();
  perform pg_temp.expect((pg_temp.job(spam)).status = 'queued', 'held: a moderator''s release queues it');

  -- Turn the guard off again for the rest of the script.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_ai_guard(c, false, 'joined_days', 3, 10, 'hold');
  perform pg_temp.root();
end $$;

-- ===================================== 4. the job queue is the requester's to read
do $$
declare ada_jobs integer; any_job uuid;
begin
  select count(*) into ada_jobs from public.ai_jobs where requester_id = pg_temp.i('ada');
  select id into any_job from public.ai_jobs where requester_id = pg_temp.i('bob') limit 1;

  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.ai_jobs') = ada_jobs and ada_jobs >= 1,
    'jobs: a requester reads only their own jobs');
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.ai_jobs where id = %L', any_job)) = 0,
    'jobs: not somebody else''s');
  perform pg_temp.expect(pg_temp.state('select attempts from public.ai_jobs') = '42501', 'jobs: internals are not readable');
  perform pg_temp.expect(pg_temp.state('select id, status, reason from public.ai_jobs') = 'ok', 'jobs: status and reason are');
  perform pg_temp.must_refuse(format('insert into public.ai_jobs (message_id, conversation_id, requester_id) values (%L, %L, %L)',
    pg_temp.i('m1'), pg_temp.i('group'), pg_temp.i('ada')), 'jobs: nobody queues a job by hand');
  perform pg_temp.must_refuse(format('update public.ai_jobs set status = ''done'' where requester_id = %L', pg_temp.i('ada')), 'jobs: nobody edits a job');
  perform pg_temp.must_refuse('delete from public.ai_jobs', 'jobs: nobody deletes a job');
  perform pg_temp.act(pg_temp.i('dee'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.ai_jobs') = 0, 'jobs: an outsider reads none');
  perform pg_temp.act(null);
  perform pg_temp.must_refuse('select 1 from public.ai_jobs', 'jobs: nobody signed in reads none');
  perform pg_temp.root();
end $$;

-- ===================================== 5. the server-only functions
do $$
declare
  fn text;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  foreach fn in array array[
    'select public.ai_assistant_claim(gen_random_uuid())',
    'select public.ai_assistant_context(gen_random_uuid())',
    'select public.ai_assistant_reply(gen_random_uuid(), ''x'', ''answer'', null)',
    'select public.ai_assistant_finish(gen_random_uuid(), ''failed'', ''x'')',
    'select public.register_ai_assistant(gen_random_uuid())',
    'select public.run_ai_assistant_sweep()',
    'select public.ai_assistant_enqueue(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 0::smallint)',
    'select public.ai_assistant_close(gen_random_uuid(), ''failed'', ''x'')',
    'select public.conversation_ai_assistant_allowed(gen_random_uuid())'
  ] loop
    perform pg_temp.must_refuse(fn, 'server only: a signed-in user cannot call ' || fn);
  end loop;
  perform pg_temp.act(null);
  perform pg_temp.must_refuse('select public.ai_assistant_claim(gen_random_uuid())', 'server only: anon cannot claim');
  perform pg_temp.root();
end $$;

-- ===================================== 6. the claim checks every reason not to answer
create function pg_temp.reset_job(mid uuid) returns uuid language plpgsql as $$
declare jid uuid;
begin
  update public.ai_jobs set status = 'queued', reason = null, finished_at = null, started_at = null, attempts = 0
  where message_id = mid returning id into jid;
  return jid;
end $$;
grant execute on function pg_temp.reset_job(uuid) to public;

do $$
declare
  g uuid := pg_temp.i('group'); c uuid := pg_temp.i('circle'); ch uuid := pg_temp.i('channel');
  jid uuid; claim jsonb; mid uuid;
begin
  -- The good case.
  jid := (pg_temp.job(pg_temp.i('m1'))).id;
  claim := public.ai_assistant_claim(jid);
  perform pg_temp.expect(claim ->> 'requester_id' = pg_temp.i('ada')::text and claim ->> 'body' = '@WeCord AI summarize the plan'
    and (claim ->> 'context_count')::int = 0 and claim ->> 'requester_name' = 'Ada' and claim ->> 'time_zone' is not null,
    'claim: a good job comes back with what the function needs');
  perform pg_temp.expect((pg_temp.job(pg_temp.i('m1'))).status = 'running' and (pg_temp.job(pg_temp.i('m1'))).attempts = 1,
    'claim: and is running');
  perform pg_temp.expect(public.ai_assistant_claim(jid) is null, 'claim: a running job is not handed out twice');
  perform pg_temp.expect(public.ai_assistant_claim(gen_random_uuid()) is null, 'claim: an unknown job is nothing');
  -- A worker that went quiet: handed out again after 90 seconds, at most three tries.
  update public.ai_jobs set started_at = now() - interval '2 minutes' where id = jid;
  perform pg_temp.expect(public.ai_assistant_claim(jid) is not null and (pg_temp.job(pg_temp.i('m1'))).attempts = 2,
    'claim: a quiet worker''s job is handed out again');
  update public.ai_jobs set started_at = now() - interval '2 minutes', attempts = 3 where id = jid;
  perform pg_temp.expect(public.ai_assistant_claim(jid) is null, 'claim: but not a fourth time');
  update public.ai_jobs set started_at = now(), attempts = 1 where id = jid;

  -- The group owner's switch.
  mid := pg_temp.say('ada', g, '@WeCord AI group switch test');
  jid := (pg_temp.job(mid)).id;
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_group_ai_assistant(%L, false)', g)) = '42501', 'group switch: a member cannot turn it off');
  perform pg_temp.expect(public.get_group_ai_assistant(g) = true, 'group switch: on by default, any member reads it');
  perform pg_temp.act(pg_temp.i('dee'));
  perform pg_temp.expect(pg_temp.state(format('select public.get_group_ai_assistant(%L)', g)) = '42501', 'group switch: an outsider cannot read it');
  perform pg_temp.expect(pg_temp.state(format('select public.set_group_ai_assistant(%L, false)', g)) = '42501', 'group switch: nor change it');
  perform pg_temp.must_refuse(format('insert into public.group_ai_settings (conversation_id, assistant_enabled) values (%L, false)', g), 'group switch: no direct writes');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(public.set_group_ai_assistant(g, false) = false, 'group switch: the owner turns it off');
  perform pg_temp.expect(pg_temp.state(format('select public.set_group_ai_assistant(%L, false)', c)) = '42501', 'group switch: only for groups');
  perform pg_temp.root();
  perform pg_temp.expect(public.ai_assistant_claim(jid) ->> 'skipped' = 'group_off', 'claim: no answer when the group owner turned it off');
  perform pg_temp.expect((select status from public.ai_jobs where id = jid) = 'skipped' and (select reason from public.ai_jobs where id = jid) = 'group_off',
    'claim: the job records why');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_group_ai_assistant(g, true);
  perform pg_temp.root();
  perform pg_temp.expect(public.ai_assistant_claim(pg_temp.reset_job(mid)) ->> 'skipped' is null, 'claim: answers again once it is back on');
  update public.ai_jobs set status = 'done' where message_id = mid;

  -- The circle's switch (the channel's job is cy's, from the held message test).
  jid := (pg_temp.job(pg_temp.i('spam'))).id;
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_ai_enabled(c, false);
  perform pg_temp.root();
  perform pg_temp.expect(public.ai_assistant_claim(jid) ->> 'skipped' = 'circle_off', 'claim: no answer when the circle turned AI off');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_ai_enabled(c, true);
  perform pg_temp.root();
  perform pg_temp.expect(public.ai_assistant_claim(pg_temp.reset_job(pg_temp.i('spam'))) ->> 'skipped' is null, 'claim: answers again once the circle turned it on');
  update public.ai_jobs set status = 'done' where message_id = pg_temp.i('spam');

  -- The requester's own switch.
  mid := (select message_id from public.ai_jobs where requester_id = pg_temp.i('bob') and status = 'queued' order by created_at limit 1);
  insert into public.user_ai_settings (user_id, ai_enabled) values (pg_temp.i('bob'), false);
  perform pg_temp.expect(public.ai_assistant_claim((pg_temp.job(mid)).id) ->> 'skipped' = 'user_off', 'claim: no answer when the requester turned AI off');
  update public.user_ai_settings set ai_enabled = null where user_id = pg_temp.i('bob');
  perform pg_temp.expect(public.ai_assistant_claim(pg_temp.reset_job(mid)) ->> 'skipped' is null, 'claim: not copied yet counts as on');
  update public.ai_jobs set status = 'done' where message_id = mid;
  delete from public.user_ai_settings where user_id = pg_temp.i('bob');

  -- Somebody else's switch does not matter.
  insert into public.user_ai_settings (user_id, ai_enabled) values (pg_temp.i('dee'), false);
  mid := pg_temp.say('ada', g, '@WeCord AI dee has AI off, I do not');
  perform pg_temp.expect(public.ai_assistant_claim((pg_temp.job(mid)).id) ->> 'skipped' is null, 'claim: another member''s switch is not the requester''s');
  update public.ai_jobs set status = 'done' where message_id = mid;
  delete from public.user_ai_settings where user_id = pg_temp.i('dee');

  -- Old, recalled, expired and gone messages.
  mid := pg_temp.say('ada', g, '@WeCord AI this one is old');
  update public.messages set created_at = now() - interval '7 hours' where id = mid;
  perform pg_temp.expect(public.ai_assistant_claim((pg_temp.job(mid)).id) ->> 'skipped' = 'stale', 'claim: a message more than six hours old is stale');

  mid := pg_temp.say('ada', g, '@WeCord AI never mind');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.recall_message(mid);
  perform pg_temp.root();
  perform pg_temp.expect(public.ai_assistant_claim((pg_temp.job(mid)).id) ->> 'skipped' = 'message_gone', 'claim: a recalled message is not answered');

  mid := pg_temp.say('ada', g, '@WeCord AI vanishing');
  update public.messages set expires_at = now() - interval '1 second' where id = mid;
  perform pg_temp.expect(public.ai_assistant_claim((pg_temp.job(mid)).id) ->> 'skipped' = 'message_gone', 'claim: an expired message is not answered');

  -- The requester left.
  mid := pg_temp.say('cy', g, '@WeCord AI I am leaving');
  delete from public.conversation_members where conversation_id = g and user_id = pg_temp.i('cy');
  perform pg_temp.expect(public.ai_assistant_claim((pg_temp.job(mid)).id) ->> 'skipped' = 'not_member', 'claim: a requester who left gets no answer');
  insert into public.conversation_members (conversation_id, user_id) values (g, pg_temp.i('cy'));

  -- Direct chats have no group owner; only the personal switch applies.
  perform pg_temp.act(pg_temp.i('ada'));
  insert into pg_temp.ids select 'dm', public.get_or_create_direct_conversation(pg_temp.i('dee'));
  perform pg_temp.root();
  mid := pg_temp.say('ada', pg_temp.i('dm'), '@WeCord AI what is a good gift');
  perform pg_temp.expect(public.ai_assistant_claim((pg_temp.job(mid)).id) ->> 'skipped' is null, 'claim: a direct chat is fine');
  update public.ai_jobs set status = 'done' where message_id = mid;
end $$;

-- ===================================== 7. what the model may read
do $$
declare
  g uuid := pg_temp.i('group'); ch uuid := pg_temp.i('channel'); g2 uuid;
  r1 uuid; r2 uuid; r3 uuid; r4 uuid; trig uuid; after_id uuid; jid uuid; ctx jsonb; n integer; last_before uuid;
begin
  -- A fresh group so the count is easy: Ada owns it, Dee is in it.
  perform pg_temp.act(pg_temp.i('ada'));
  g2 := public.create_group_conversation('Trip', array[pg_temp.i('dee'), pg_temp.i('cy')]);
  insert into pg_temp.ids values ('g2', g2);
  perform pg_temp.root();

  r1 := pg_temp.say('ada', g2, 'we meet at 7pm at the station');
  r2 := pg_temp.say('dee', g2, 'I bring snacks');
  r3 := pg_temp.say('ada', g2, 'this one gets recalled');
  r4 := pg_temp.say('dee', g2, 'this one expires');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.recall_message(r3);
  perform pg_temp.root();
  update public.messages set expires_at = now() - interval '1 second' where id = r4;
  -- 25 more, so the ranges have something to cut.
  for n in 1..25 loop
    last_before := pg_temp.say(case when n % 2 = 0 then 'ada' else 'dee' end, g2, 'filler ' || n);
  end loop;

  -- Dee asks about Ada's first message with the last 20.
  trig := pg_temp.say('dee', g2, '@WeCord AI /20 list the todos', r1);
  after_id := pg_temp.say('ada', g2, 'a message after the question');
  jid := (pg_temp.job(trig)).id;
  perform pg_temp.expect(public.ai_assistant_context(jid) is null, 'context: nothing before the job is claimed');
  perform public.ai_assistant_claim(jid);
  ctx := public.ai_assistant_context(jid);
  perform pg_temp.expect(ctx -> 'trigger' ->> 'id' = trig::text and ctx -> 'trigger' ->> 'body' = '@WeCord AI /20 list the todos' and ctx -> 'trigger' ->> 'sender' = 'Dee',
    'context: the asking message');
  perform pg_temp.expect(ctx -> 'replied' ->> 'id' = r1::text and ctx -> 'replied' ->> 'body' = 'we meet at 7pm at the station' and ctx -> 'replied' ->> 'sender' = 'Ada',
    'context: the message it replies to');
  perform pg_temp.expect(jsonb_array_length(ctx -> 'recent') = 20, 'context: /20 gives exactly 20 messages');
  perform pg_temp.expect(ctx -> 'recent' -> 19 ->> 'id' = last_before::text, 'context: the newest before the question, in order');
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(ctx -> 'recent') e where e ->> 'id' in (trig::text, after_id::text)),
    'context: neither the question itself nor anything after it');
  perform pg_temp.expect(
    (ctx -> 'recent' -> 0 ->> 'created_at')::timestamptz <= (ctx -> 'recent' -> 19 ->> 'created_at')::timestamptz,
    'context: oldest first');
  perform pg_temp.expect(jsonb_array_length(ctx -> 'members') = 3 and exists (select 1 from jsonb_array_elements(ctx -> 'members') e where e ->> 'id' = pg_temp.i('ada')::text and e ->> 'name' = 'Ada'),
    'context: the members, for the assignees');
  update public.ai_jobs set status = 'done' where id = jid;

  -- /100 reaches the recalled and expired ones, which are still left out.
  trig := pg_temp.say('ada', g2, '@WeCord AI /100 everything please');
  jid := (pg_temp.job(trig)).id;
  perform public.ai_assistant_claim(jid);
  ctx := public.ai_assistant_context(jid);
  perform pg_temp.expect(jsonb_array_length(ctx -> 'recent') >= 28, 'context: /100 reads all there is');
  perform pg_temp.expect(not exists (select 1 from jsonb_array_elements(ctx -> 'recent') e where e ->> 'id' in (r3::text, r4::text)),
    'context: recalled and expired messages are never included');
  perform pg_temp.expect(ctx -> 'replied' = 'null'::jsonb, 'context: no reply target, no replied message');
  update public.ai_jobs set status = 'done' where id = jid;

  -- No range: the message and what it replies to, nothing else.
  trig := pg_temp.say('dee', g2, '@WeCord AI explain this', r2);
  jid := (pg_temp.job(trig)).id;
  perform public.ai_assistant_claim(jid);
  ctx := public.ai_assistant_context(jid);
  perform pg_temp.expect(ctx -> 'recent' = '[]'::jsonb and ctx -> 'replied' ->> 'id' = r2::text, 'context: no range reads only the message and its reply target');
  update public.ai_jobs set status = 'done' where id = jid;

  -- A reply target that was recalled is left out.
  trig := pg_temp.say('dee', g2, '@WeCord AI and this one?', r3);
  jid := (pg_temp.job(trig)).id;
  perform public.ai_assistant_claim(jid);
  ctx := public.ai_assistant_context(jid);
  perform pg_temp.expect(ctx -> 'replied' = 'null'::jsonb, 'context: a recalled reply target is left out');
  update public.ai_jobs set status = 'done' where id = jid;

  -- The requester left the chat after the claim: nothing is readable.
  trig := pg_temp.say('dee', g2, '@WeCord AI /20 last one');
  jid := (pg_temp.job(trig)).id;
  perform public.ai_assistant_claim(jid);
  delete from public.conversation_members where conversation_id = g2 and user_id = pg_temp.i('dee');
  perform pg_temp.expect(public.ai_assistant_context(jid) is null, 'context: a requester who left reads nothing');
  update public.ai_jobs set status = 'done' where id = jid;

  -- Held by the AI guard: not even a moderator's question carries it along.
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_ai_guard(pg_temp.i('circle'), true, 'joined_days', 3, 10, 'hold');
  perform pg_temp.root();
  perform pg_temp.say('ada', ch, 'a normal line from the owner');
  perform pg_temp.say('bob', ch, 'SECRET HELD TEXT');
  perform pg_temp.expect((select review_state from public.messages where body = 'SECRET HELD TEXT') = 'checking', 'context: the line is held');
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.messages where body = ''SECRET HELD TEXT''') = 1, 'context: the moderator could see it');
  perform pg_temp.root();
  trig := pg_temp.say('ada', ch, '@WeCord AI /20 what is going on');
  jid := (pg_temp.job(trig)).id;
  perform public.ai_assistant_claim(jid);
  ctx := public.ai_assistant_context(jid);
  perform pg_temp.expect(ctx::text not like '%SECRET HELD TEXT%', 'context: but the model never sees a held message');
  perform pg_temp.expect(ctx::text like '%a normal line from the owner%', 'context: while the rest of the channel is there');
  update public.ai_jobs set status = 'done' where id = jid;
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_ai_guard(pg_temp.i('circle'), false, 'joined_days', 3, 10, 'hold');
  perform pg_temp.root();
end $$;

-- ===================================== 8. the identity
do $$
declare
  trig uuid; jid uuid; assistant uuid; second uuid; again uuid;
  g uuid := pg_temp.i('group');
begin
  perform pg_temp.expect(public.ai_assistant_user_id() is null, 'identity: nothing exists before the function creates it');
  trig := pg_temp.say('ada', g, '@WeCord AI first answer');
  jid := (pg_temp.job(trig)).id;
  perform public.ai_assistant_claim(jid);
  perform pg_temp.expect(pg_temp.state(format('select public.ai_assistant_reply(%L, ''hi'', ''answer'', null)', jid)) = '22023',
    'identity: no reply without the account');

  -- A login that is not a bot's, a stranger's and an old one are all refused.
  insert into auth.users (id, email, instance_id, aud, role)
    values ('00000000-0000-4000-8000-0000000000c1', 'plain@aa.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
  perform pg_temp.expect(pg_temp.state('select public.register_ai_assistant(''00000000-0000-4000-8000-0000000000c1'')') = '22023', 'identity: an ordinary login is refused');
  perform pg_temp.expect(pg_temp.state('select public.register_ai_assistant(gen_random_uuid())') = '22023', 'identity: an unknown login is refused');
  perform pg_temp.expect(pg_temp.state('select public.register_ai_assistant(null)') = '22023', 'identity: null is refused');
  insert into auth.users (id, email, instance_id, aud, role, raw_app_meta_data, created_at)
    values ('00000000-0000-4000-8000-0000000000c2', 'oldbot@aa.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"provider":"bot"}', now() - interval '1 day');
  perform pg_temp.expect(pg_temp.state('select public.register_ai_assistant(''00000000-0000-4000-8000-0000000000c2'')') = '22023', 'identity: a login that is not new is refused');

  insert into auth.users (id, email, instance_id, aud, role, raw_app_meta_data, created_at)
    values ('00000000-0000-4000-8000-0000000000c3', 'wecord-ai@bots.aa.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"provider":"bot"}', now());
  assistant := public.register_ai_assistant('00000000-0000-4000-8000-0000000000c3');
  perform pg_temp.expect(assistant = '00000000-0000-4000-8000-0000000000c3'::uuid, 'identity: the new bot login becomes the assistant');
  perform pg_temp.expect((select is_bot and display_name = 'WeCord AI' and username = 'wecord_ai' from public.profiles where id = assistant),
    'identity: a bot profile called WeCord AI');
  perform pg_temp.expect(public.ai_assistant_user_id() = assistant, 'identity: and it is found by key');

  insert into auth.users (id, email, instance_id, aud, role, raw_app_meta_data, created_at)
    values ('00000000-0000-4000-8000-0000000000c4', 'wecord-ai2@bots.aa.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"provider":"bot"}', now());
  again := public.register_ai_assistant('00000000-0000-4000-8000-0000000000c4');
  perform pg_temp.expect(again = assistant and not exists (select 1 from public.profiles where id = '00000000-0000-4000-8000-0000000000c4'),
    'identity: registering twice is idempotent and keeps the first');
  perform pg_temp.expect((select count(*) from public.system_bots) = 1, 'identity: one row');

  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(public.ai_assistant_user_id() = assistant, 'identity: any signed-in user can look it up');
  perform pg_temp.expect(pg_temp.cnt('select 1 from public.system_bots') = 1, 'identity: and read the table');
  perform pg_temp.must_refuse('delete from public.system_bots', 'identity: but not change it');
  perform pg_temp.state(format('update public.profiles set is_bot = false, display_name = ''Mallory'' where id = %L', assistant));
  perform pg_temp.root();
  perform pg_temp.expect((select is_bot and display_name = 'WeCord AI' from public.profiles where id = assistant), 'identity: nobody can edit the assistant''s profile');
  perform pg_temp.expect(not exists (select 1 from public.conversation_members where user_id = assistant), 'identity: it is a member of no chat');
end $$;

-- ===================================== 9. posting an answer
do $$
declare
  g uuid := pg_temp.i('group'); assistant uuid := public.ai_assistant_user_id();
  trig uuid := pg_temp.i('m1'); jid uuid; reply uuid; bad text; rid uuid;
begin
  jid := (pg_temp.job(trig)).id;
  update public.ai_jobs set status = 'running', started_at = now() where id = jid;
  reply := public.ai_assistant_reply(jid, E'Here are the to-dos:\n- Book the train', 'todos',
    '[{"title":"Book the train","assignee":null,"due":null,"kind":"task"}]'::jsonb);
  perform pg_temp.expect(reply is not null, 'reply: the answer is posted');
  perform pg_temp.expect((select sender_id = assistant and conversation_id = g and reply_to_message_id = trig and type = 'text'
      and ai_reply ->> 'kind' = 'todos' and ai_reply ->> 'requester_id' = pg_temp.i('ada')::text
      and ai_reply ->> 'requester_name' = 'Ada' and jsonb_array_length(ai_reply -> 'items') = 1
      and reply_preview ->> 'message_id' = trig::text
    from public.messages where id = reply), 'reply: from the assistant, to the question, marked with who asked and the items');
  perform pg_temp.expect((select status = 'done' and reply_message_id = reply and finished_at is not null from public.ai_jobs where id = jid), 'reply: the job is done');
  perform pg_temp.expect((select last_message_id = reply from public.conversations where id = g), 'reply: it is the chat''s latest message');
  perform pg_temp.expect(public.ai_assistant_reply(jid, 'again', 'answer', null) is null, 'reply: a finished job posts nothing more');

  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.messages where id = %L', reply)) = 1, 'reply: every member reads it');
  perform pg_temp.expect((select p.is_bot and p.display_name = 'WeCord AI' from public.profiles p where p.id = assistant), 'reply: its profile is a bot');
  perform pg_temp.act(pg_temp.i('dee'));
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.messages where id = %L', reply)) = 0, 'reply: an outsider does not');
  perform pg_temp.root();

  -- Bad input.
  update public.ai_jobs set status = 'running' where id = jid;
  perform pg_temp.expect(pg_temp.state(format('select public.ai_assistant_reply(%L, ''x'', ''poem'', null)', jid)) = '22023', 'reply: an unknown kind');
  perform pg_temp.expect(pg_temp.state(format('select public.ai_assistant_reply(%L, %L, ''answer'', null)', jid, repeat('x', 4001))) = '22023', 'reply: too long');
  perform pg_temp.expect(pg_temp.state(format('select public.ai_assistant_reply(%L, ''   '', ''answer'', null)', jid)) = '22023', 'reply: empty');
  perform pg_temp.expect(pg_temp.state(format('select public.ai_assistant_reply(%L, ''x'', ''todos'', ''{"a":1}'')', jid)) = '22023', 'reply: items must be a list');
  update public.ai_jobs set status = 'done' where id = jid;

  -- A question recalled while the answer was being written gets none.
  trig := pg_temp.say('ada', g, '@WeCord AI quick one');
  jid := (pg_temp.job(trig)).id;
  perform public.ai_assistant_claim(jid);
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.recall_message(trig);
  perform pg_temp.root();
  perform pg_temp.expect(public.ai_assistant_reply(jid, 'too late', 'answer', null) is null, 'reply: nothing is posted for a recalled question');
  perform pg_temp.expect((select status from public.ai_jobs where id = jid) = 'skipped'
    and (select reason from public.ai_jobs where id = jid) = 'message_gone', 'reply: and the job says why');

  -- finish.
  trig := pg_temp.say('ada', g, '@WeCord AI will fail');
  jid := (pg_temp.job(trig)).id;
  perform public.ai_assistant_claim(jid);
  perform public.ai_assistant_finish(jid, 'limited', 'limit');
  perform pg_temp.expect((select status = 'limited' and reason = 'limit' from public.ai_jobs where id = jid), 'finish: limited, with the reason');
  perform pg_temp.expect(pg_temp.state(format('select public.ai_assistant_finish(%L, ''done'', ''x'')', jid)) = '22023', 'finish: only skipped, failed or limited');

  -- Nobody can dress a message up as an AI answer.
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.must_refuse(format('insert into public.messages (conversation_id, sender_id, type, body, ai_reply) values (%L, %L, ''text'', ''fake'', ''{"kind":"answer"}'')', g, pg_temp.i('ada')),
    'forgery: a client cannot insert an ai_reply');
  rid := public.send_text_message(g, 'a plain message', null, null, '[]'::jsonb, null);
  perform pg_temp.state(format('update public.messages set ai_reply = ''{"kind":"answer"}'' where id = %L', rid));
  perform pg_temp.state(format('update public.messages set ai_reply = null where id = %L', reply));
  perform pg_temp.root();
  perform pg_temp.expect((select ai_reply is null from public.messages where id = rid), 'forgery: a message cannot be dressed up afterwards');
  perform pg_temp.expect((select ai_reply is not null from public.messages where id = reply), 'forgery: nor can the mark be taken off an answer');
end $$;

-- ===================================== 10. the answer can be reported
do $$
declare
  g uuid := pg_temp.i('group'); c uuid := pg_temp.i('circle'); ch uuid := pg_temp.i('channel');
  assistant uuid := public.ai_assistant_user_id(); reply uuid; jid uuid; report uuid; trig uuid;
begin
  reply := (select reply_message_id from public.ai_jobs where message_id = pg_temp.i('m1'));
  perform pg_temp.act(pg_temp.i('bob'));
  report := public.report_message(reply, 'unsafe_content', 'wrong and rude', true, false);
  perform pg_temp.root();
  perform pg_temp.expect(report is not null and (select reported_user_id from public.message_reports where id = report) = assistant,
    'report: a member can report the AI''s answer in a group');
  perform pg_temp.expect((select (snapshot ->> 'body') like 'Here are the to-dos%' from public.message_reports where id = report), 'report: with the text as evidence');

  -- Same in a circle channel, where the moderators handle it.
  trig := pg_temp.i('spam');
  jid := (pg_temp.job(trig)).id;
  update public.ai_jobs set status = 'running', started_at = now() where id = jid;
  reply := public.ai_assistant_reply(jid, 'An answer in the channel', 'answer', null);
  perform pg_temp.expect(reply is not null, 'report: the assistant answers in a circle channel');
  perform pg_temp.act(pg_temp.i('cy'));
  report := public.report_message(reply, 'spam', '', false, false);
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(jsonb_array_length(public.list_circle_message_reports(c, 'open', 20)) >= 1
    and public.list_circle_message_reports(c, 'open', 20)::text like '%An answer in the channel%',
    'report: and the circle''s moderators see it in their queue');
  perform pg_temp.root();
end $$;

-- ===================================== 11. the sweep
do $$
declare lost uuid; dead uuid; stuck uuid; old uuid; before_wakes integer;
begin
  select id into lost from public.ai_jobs where status = 'queued' order by created_at limit 1;
  select id into dead from public.ai_jobs where status = 'queued' and id <> lost order by created_at limit 1;
  select id into stuck from public.ai_jobs where status = 'queued' and id not in (lost, dead) order by created_at limit 1;
  select id into old from public.ai_jobs where status = 'done' order by created_at limit 1;

  update public.ai_jobs set woken_at = now() - interval '2 minutes' where id = lost;
  update public.ai_jobs set woken_at = now() - interval '2 minutes', wake_count = 3 where id = dead;
  update public.ai_jobs set status = 'running', started_at = now() - interval '4 minutes' where id = stuck;
  update public.ai_jobs set finished_at = now() - interval '15 days' where id = old;
  select count(*) into before_wakes from net.http_request_queue q where convert_from(q.body, 'UTF8')::jsonb->>'job_id' = lost::text;

  perform public.run_ai_assistant_sweep();

  perform pg_temp.expect((select wake_count = 2 from public.ai_jobs where id = lost)
    and (select count(*) from net.http_request_queue q where convert_from(q.body, 'UTF8')::jsonb->>'job_id' = lost::text) = before_wakes + 1,
    'sweep: a lost wake-up is sent again');
  perform pg_temp.expect((select status = 'failed' and reason = 'timeout' from public.ai_jobs where id = dead), 'sweep: three wake-ups and still nothing: failed');
  perform pg_temp.expect((select status = 'failed' and reason = 'timeout' from public.ai_jobs where id = stuck), 'sweep: a worker that never came back: failed');
  perform pg_temp.expect(not exists (select 1 from public.ai_jobs where id = old), 'sweep: old finished jobs are removed');
  perform pg_temp.expect((select status from public.ai_jobs where id = lost) = 'queued', 'sweep: the re-woken job stays queued');
end $$;

-- ===================================== 12. what goes away with a message or a chat
do $$
declare mid uuid := pg_temp.i('m1');
begin
  perform pg_temp.expect(exists (select 1 from public.ai_jobs where message_id = mid), 'cleanup: the job exists');
  delete from public.messages where reply_to_message_id = mid;
  delete from public.messages where id = mid;
  perform pg_temp.expect(not exists (select 1 from public.ai_jobs where message_id = mid), 'cleanup: deleting the message deletes its job');
end $$;
\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'ai assistant: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
