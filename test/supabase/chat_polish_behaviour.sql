-- Behaviour checks for the chat polish batch (A9 quoting part of a message and
-- sending without a push, E6 voice channel status: migrations 202610240500 and
-- 202610240510). Run by test/supabase/chat_polish_test.dart against the local
-- database: it applies the migrations it needs in a transaction, plays people
-- through them, and rolls everything back. Run from the repository root.
--
-- What it walks through: a quote that is in the original and one that is not
-- (also in a recalled, expired, other-conversation or under-review message),
-- what is kept of a quote, how a recall blanks it, the silent flag on text
-- sent with and without mentions and on direct inserts (and that it cannot be
-- changed afterwards), which messages the push functions are told are silent,
-- and the voice status: who may set it, the length limit, the one-line rule,
-- who sees it, an empty channel showing nothing and the first person in
-- starting clean.
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
\i supabase/migrations/202610240500_quote_and_silent.sql
\i supabase/migrations/202610240510_voice_channel_status.sql
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


create function pg_temp.msg_row(mid uuid) returns public.messages language sql security definer as $$
  select m from public.messages m where m.id = mid
$$;
create function pg_temp.is_silent(mid uuid) returns boolean language sql security definer as $$
  select m.silent from public.messages m where m.id = mid
$$;
grant execute on all functions in schema pg_temp to public;

-- ------------------------------------------------------------------ cast
-- ada, bob and cat talk in a group; dan is in none of it. In the circle, ada
-- owns it, bob and cat are members.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '@cp.test',
  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated'
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid, name || '_cp', initcap(name)
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || lpad(to_hex(n), 2, '0'))::uuid
from (values (1,'ada'),(2,'bob'),(3,'cat'),(4,'dan')) v(n, name);

insert into public.conversations (type, title) values ('group', 'Talk') returning id \gset grp_
insert into public.conversations (type, title) values ('group', 'Other') returning id \gset oth_
insert into pg_temp.ids values ('grp', :'grp_id'), ('oth', :'oth_id');
insert into public.conversation_members (conversation_id, user_id, role)
values (:'grp_id', pg_temp.i('ada'), 'owner');
insert into public.conversation_members (conversation_id, user_id, role)
values (:'grp_id', pg_temp.i('bob'), 'member'), (:'grp_id', pg_temp.i('cat'), 'member');
insert into public.conversation_members (conversation_id, user_id, role)
values (:'oth_id', pg_temp.i('ada'), 'owner'), (:'oth_id', pg_temp.i('bob'), 'member');

-- ===================================== 1. quoting part of a message (A9)
do $$
declare
  ada uuid := pg_temp.i('ada');
  bob uuid := pg_temp.i('bob');
  grp uuid := pg_temp.i('grp');
  oth uuid := pg_temp.i('oth');
  original uuid;
  other_original uuid;
  reply uuid;
  second_reply uuid;
  secret uuid;
  p jsonb;
begin
  perform pg_temp.act(ada);
  original := public.send_text_message(grp, 'First line. The meeting moved to Friday at noon. Last line.');
  other_original := public.send_text_message(oth, 'Elsewhere: the meeting moved to Friday');
  perform pg_temp.root();

  -- A quote that is in the message goes through, through the RPC.
  perform pg_temp.act(bob);
  reply := public.send_text_message(grp, 'Friday is bad for me', original,
    jsonb_build_object('sender_name', 'Ada', 'body', 'First line.',
      'quote', jsonb_build_object('text', 'moved to Friday at noon', 'start', 22, 'end', 44, 'junk', 1)));
  perform pg_temp.root();
  p := (pg_temp.msg_row(reply)).reply_preview;
  perform pg_temp.expect(p -> 'quote' ->> 'text' = 'moved to Friday at noon', 'a quote that is in the original is stored');
  perform pg_temp.expect((p -> 'quote' ->> 'start')::int = 22 and (p -> 'quote' ->> 'end')::int = 44, 'with its offsets');
  perform pg_temp.expect(not (p -> 'quote' ? 'junk'), 'and nothing else the client put in it');
  perform pg_temp.expect(p ->> 'sender_name' = 'Ada', 'the rest of the preview is untouched');

  -- Wrong offsets are dropped, the text is what counts.
  perform pg_temp.act(bob);
  second_reply := public.send_text_message(grp, 'ok', original,
    jsonb_build_object('body', 'x', 'quote', jsonb_build_object('text', 'Last line.', 'start', 9, 'end', 3)));
  perform pg_temp.root();
  p := (pg_temp.msg_row(second_reply)).reply_preview;
  perform pg_temp.expect(p -> 'quote' ->> 'text' = 'Last line.' and not (p -> 'quote' ? 'start'), 'offsets that make no sense are dropped');

  -- A forged quote is refused, whichever way it is sent.
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.state(format($q$select public.send_text_message(%L, 'no', %L, '{"body":"x","quote":{"text":"Ada said she hates Fridays"}}'::jsonb)$q$, grp, original)) = '22023',
    'a quote that is not in the original is refused (RPC)');
  perform pg_temp.expect(pg_temp.state(format($q$insert into public.messages (conversation_id, sender_id, type, body, reply_to_message_id, reply_preview) values (%L, %L, 'text', 'no', %L, '{"body":"x","quote":{"text":"Ada said she hates Fridays"}}'::jsonb)$q$, grp, bob, original)) = '22023',
    'a quote that is not in the original is refused (direct insert)');
  perform pg_temp.expect(pg_temp.state(format($q$select public.send_text_message(%L, 'no', %L, '{"body":"x","quote":{"text":"moved to friday"}}'::jsonb)$q$, grp, original)) = '22023',
    'the match is exact: another case is a different text');
  perform pg_temp.expect(pg_temp.state(format($q$select public.send_text_message(%L, 'no', null, '{"body":"x","quote":{"text":"Last line."}}'::jsonb)$q$, grp)) = '22023',
    'a quote needs the message it answers');
  perform pg_temp.expect(pg_temp.state(format($q$select public.send_text_message(%L, 'no', %L, '{"body":"x","quote":{"text":""}}'::jsonb)$q$, grp, original)) = '22023',
    'an empty quote is refused');
  perform pg_temp.expect(pg_temp.state(format($q$select public.send_text_message(%L, 'no', %L, '{"body":"x","quote":"moved"}'::jsonb)$q$, grp, original)) = '22023',
    'a quote that is not an object is refused');
  perform pg_temp.expect(pg_temp.state(format($q$select public.send_text_message(%L, 'no', %L, jsonb_build_object('body','x','quote',jsonb_build_object('text', repeat('a', 501))))$q$, grp, original)) = '22023',
    'a quote of more than 500 characters is refused');
  -- A message of another conversation is no source (it is refused as a
  -- reply to begin with).
  perform pg_temp.expect(pg_temp.refused(format($q$select public.send_text_message(%L, 'no', %L, '{"body":"x","quote":{"text":"the meeting moved to Friday"}}'::jsonb)$q$, grp, other_original)),
    'a message of another conversation cannot be quoted here');
  perform pg_temp.root();

  -- Quote text only a hidden, recalled or expired message holds.
  perform pg_temp.act(ada);
  secret := public.send_text_message(grp, 'A secret plan: bring cake');
  perform pg_temp.root();
  update public.messages set review_state = 'checking' where id = secret;
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.refused(format($q$select public.send_text_message(%L, 'no', %L, '{"body":"x","quote":{"text":"bring cake"}}'::jsonb)$q$, grp, secret)),
    'a message under review cannot be quoted by those who cannot see it (no probing for its words)');
  perform pg_temp.root();
  update public.messages set review_state = null where id = secret;

  perform pg_temp.act(bob);
  reply := public.send_text_message(grp, 'I quote the cake', secret,
    '{"body":"A secret plan: bring cake","quote":{"text":"bring cake"}}'::jsonb);
  perform pg_temp.root();
  perform pg_temp.expect((pg_temp.msg_row(reply)).reply_preview -> 'quote' ->> 'text' = 'bring cake', 'once released it can be quoted');

  -- Recall: the original's author deletes it; the quote in the replies goes.
  perform pg_temp.act(ada);
  perform public.recall_message(secret);
  perform pg_temp.root();
  p := (pg_temp.msg_row(reply)).reply_preview;
  perform pg_temp.expect(p ->> 'body' = '' and not (p ? 'quote'), 'a recalled message leaves no quote behind in its replies');

  -- Expired messages are no source.
  perform pg_temp.act(ada);
  secret := public.send_text_message(grp, 'This one will vanish quickly');
  perform pg_temp.root();
  update public.messages set expires_at = now() - interval '1 minute' where id = secret;
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.refused(format($q$select public.send_text_message(%L, 'no', %L, '{"body":"x","quote":{"text":"vanish"}}'::jsonb)$q$, grp, secret)),
    'an expired message cannot be quoted');
  perform pg_temp.root();

  -- Changing the quote of a stored reply afterwards is checked as well.
  perform pg_temp.expect(pg_temp.state(format($q$update public.messages set reply_preview = '{"body":"x","quote":{"text":"never said"}}'::jsonb where id = %L$q$, second_reply)) = '22023',
    'a stored reply cannot be given a forged quote later');

  -- Plain replies (no quote) are as before.
  perform pg_temp.act(bob);
  reply := public.send_text_message(grp, 'plain', original, '{"body":"First line.","sender_name":"Ada"}'::jsonb);
  perform pg_temp.root();
  perform pg_temp.expect(not ((pg_temp.msg_row(reply)).reply_preview ? 'quote'), 'a reply without a quote has none');
end $$;

-- ===================================== 2. silent sending (A9)
do $$
declare
  ada uuid := pg_temp.i('ada');
  bob uuid := pg_temp.i('bob');
  grp uuid := pg_temp.i('grp');
  m1 uuid;
  m2 uuid;
  m3 uuid;
  m4 uuid;
  m5 uuid;
  ids uuid[];
begin
  perform pg_temp.act(ada);
  m1 := public.send_silent_text_message(grp, 'Sleep well');
  m2 := public.send_text_message(grp, 'Good morning');
  m3 := public.send_silent_text_message(grp, 'psst @Bob', null, null,
    jsonb_build_array(jsonb_build_object('kind', 'user', 'user_id', bob, 'label', 'Bob')));
  insert into public.messages (conversation_id, sender_id, type, body, silent)
  values (grp, ada, 'text', 'direct and silent', true) returning id into m4;
  insert into public.messages (conversation_id, sender_id, type, body)
  values (grp, ada, 'text', 'direct and loud') returning id into m5;
  perform pg_temp.root();

  perform pg_temp.expect(pg_temp.is_silent(m1), 'send_silent_text_message stores a silent message');
  perform pg_temp.expect(not pg_temp.is_silent(m2), 'send_text_message is as loud as before, also right after a silent one');
  perform pg_temp.expect(pg_temp.is_silent(m3), 'silent also with a mention');
  perform pg_temp.expect(pg_temp.is_silent(m4) and not pg_temp.is_silent(m5), 'a direct insert may say silent too');
  perform pg_temp.expect(coalesce(current_setting('wecord.send_silent', true), 'off') <> 'on', 'the silent switch is off again after the send');

  -- Bob sees all of them, the silent ones too.
  perform pg_temp.act(bob);
  perform pg_temp.expect(pg_temp.cnt(format('select 1 from public.messages where id in (%L, %L, %L)', m1, m3, m4)) = 3, 'the others still see silent messages');
  perform pg_temp.root();

  -- It is decided once.
  perform pg_temp.act(ada);
  update public.messages set silent = false where id = m1;
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.is_silent(m1), 'silent cannot be switched off afterwards');
  update public.messages set silent = true where id = m2;
  perform pg_temp.expect(not pg_temp.is_silent(m2), 'nor on');

  -- What the push functions ask.
  ids := array(select * from public.silent_message_ids(array[m1, m2, m3, m4, m5]));
  perform pg_temp.expect(ids @> array[m1, m3, m4] and cardinality(ids) = 3, 'silent_message_ids names exactly the silent ones');
  perform pg_temp.act(ada);
  perform pg_temp.must_refuse(format('select public.silent_message_ids(array[%L]::uuid[])', m1), 'a signed-in person cannot ask');
  perform pg_temp.root();

  -- Signed out / not a member.
  perform pg_temp.act(null);
  perform pg_temp.must_refuse(format('select public.send_silent_text_message(%L, ''x'')', grp), 'signed out: no silent send');
  perform pg_temp.root();
  perform pg_temp.act(pg_temp.i('dan'));
  perform pg_temp.must_refuse(format('select public.send_silent_text_message(%L, ''x'')', grp), 'a stranger cannot send, silent or not');
  perform pg_temp.root();
end $$;

-- ===================================== 3. voice channel status (E6)
insert into public.friendships (user_low_id, user_high_id)
select least(pg_temp.i('ada'), pg_temp.i(n)), greatest(pg_temp.i('ada'), pg_temp.i(n))
from (values ('bob'), ('cat')) v(n);
do $$
declare
  ada uuid := pg_temp.i('ada');
  bob uuid := pg_temp.i('bob');
  cat uuid := pg_temp.i('cat');
  dan uuid := pg_temp.i('dan');
  circle uuid;
  vc uuid;
  other_vc uuid;
  text_channel uuid;
  st jsonb;
begin
  perform pg_temp.act(ada);
  circle := public.create_circle('Voice club', array[bob, cat]);
  vc := public.create_circle_channel(circle, 'lounge', null, 'voice');
  other_vc := public.create_circle_channel(circle, 'booth', null, 'voice');
  perform pg_temp.root();
  select cc.id into text_channel from public.circle_channels cc where cc.circle_id = circle and cc.kind = 'text' limit 1;

  -- Nobody in the channel: nobody sets a status.
  perform pg_temp.act(ada);
  perform pg_temp.must_refuse(format('select public.set_voice_channel_status(%L, %L)', vc, 'Ranked'), 'not in the channel: no status');
  perform public.join_voice_state(vc);
  perform pg_temp.expect(public.set_voice_channel_status(vc, '  Playing   ranked  ') = 'Playing ranked', 'in the channel: a status, white space tidied');
  perform pg_temp.expect(public.set_voice_channel_status(vc, E'Line one\nline two') = 'Line one line two', 'line breaks become spaces');
  perform pg_temp.expect(pg_temp.state(format('select public.set_voice_channel_status(%L, repeat(''x'', 61))', vc)) = '22023', 'more than 60 characters is refused');
  perform pg_temp.expect(length(public.set_voice_channel_status(vc, repeat('x', 60))) = 60, 'exactly 60 is fine');
  perform pg_temp.expect(public.set_voice_channel_status(vc, '🎮 Valorant night') = '🎮 Valorant night', 'emoji are fine');
  perform pg_temp.must_refuse(format('select public.set_voice_channel_status(%L, %L)', other_vc, 'Elsewhere'), 'being in one channel does not allow another');
  perform pg_temp.root();

  -- Read by members.
  perform pg_temp.act(bob);
  st := public.list_voice_channel_statuses(circle);
  perform pg_temp.expect(st ->> vc::text = '🎮 Valorant night', 'a member reads the status in the list');
  perform pg_temp.expect(not (st ? other_vc::text), 'channels without a status are not listed');
  perform pg_temp.must_refuse(format('select public.set_voice_channel_status(%L, %L)', vc, 'Hijack'), 'a member outside the call cannot change it');
  perform pg_temp.root();
  perform pg_temp.act(dan);
  perform pg_temp.must_refuse(format('select public.list_voice_channel_statuses(%L)', circle), 'a stranger cannot read the list');
  perform pg_temp.must_refuse(format('select public.set_voice_channel_status(%L, %L)', vc, 'Hijack'), 'nor set a status');
  perform pg_temp.root();
  perform pg_temp.act(null);
  perform pg_temp.must_refuse(format('select public.list_voice_channel_statuses(%L)', circle), 'signed out: no list');
  perform pg_temp.must_refuse(format('select public.set_voice_channel_status(%L, %L)', vc, 'x'), 'signed out: no status');
  perform pg_temp.root();

  -- Somebody else in the channel may change it.
  perform pg_temp.act(bob);
  perform public.join_voice_state(vc);
  perform pg_temp.expect(public.set_voice_channel_status(vc, 'Chatting about the trip') = 'Chatting about the trip', 'everyone in the channel can change it');
  perform pg_temp.expect(public.set_voice_channel_status(vc, '   ') is null, 'blank clears it');
  perform pg_temp.expect(not (public.list_voice_channel_statuses(circle) ? vc::text), 'and the list no longer has it');
  perform public.set_voice_channel_status(vc, 'Movie time');
  perform pg_temp.root();

  -- A status left in an empty channel shows nothing and the next first
  -- person starts clean.
  perform pg_temp.act(ada);
  perform public.leave_voice_state();
  perform pg_temp.root();
  perform pg_temp.act(bob);
  perform public.leave_voice_state();
  perform pg_temp.expect(not (public.list_voice_channel_statuses(circle) ? vc::text), 'an empty channel shows no status');
  perform pg_temp.root();
  perform pg_temp.expect((select voice_status from public.circle_channels where id = vc) = 'Movie time', 'although the old one is still stored');
  perform pg_temp.act(cat);
  perform public.join_voice_state(vc);
  perform pg_temp.root();
  perform pg_temp.expect((select voice_status from public.circle_channels where id = vc) is null, 'the first one in starts without it');

  -- A person whose heartbeat ran out cannot set one.
  update public.voice_states set last_seen_at = now() - interval '5 minutes' where user_id = cat;
  perform pg_temp.act(cat);
  perform pg_temp.must_refuse(format('select public.set_voice_channel_status(%L, %L)', vc, 'ghost'), 'a stale voice state cannot set a status');
  perform pg_temp.root();

  -- A text channel has no voice status.
  perform pg_temp.act(ada);
  perform pg_temp.must_refuse(format('select public.set_voice_channel_status(%L, %L)', text_channel, 'x'), 'text channels have none');
  perform pg_temp.root();

  -- The raw column keeps its limits, whoever writes it.
  perform pg_temp.expect(pg_temp.state(format($q$update public.circle_channels set voice_status = 'a%sb' where id = %L$q$, E'\n', vc)) = '23514', 'a line break cannot be written around the function');
  perform pg_temp.expect(pg_temp.state(format($q$update public.circle_channels set voice_status = repeat('y', 61) where id = %L$q$, vc)) = '23514', 'nor a long text');
end $$;
\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'chat polish: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
