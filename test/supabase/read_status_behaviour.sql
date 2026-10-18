-- Behaviour checks for the group read list and "remind unread" (migrations
-- 202610220300, 202610220310 and 202610220320). Run by
-- test/supabase/read_status_test.dart against the local database: it applies
-- every migration the database lacks (the local baseline is 202610170001)
-- inside a transaction, acts as several people, and rolls back, so the
-- database is left as it was. Run from the repository root.
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
\i supabase/migrations/202610220210_message_edit_history.sql
\i supabase/migrations/202610220220_edit_review.sql
\i supabase/migrations/202610220230_circle_edit_window.sql
\i supabase/migrations/202610220300_read_receipts_setting.sql
\i supabase/migrations/202610220310_message_read_status.sql
\i supabase/migrations/202610220320_remind_unread.sql

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@reads.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'mod@reads.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'newt@reads.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d1', 'olly@reads.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve@reads.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000f1', 'fay@reads.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-000000000091', 'zed@reads.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-000000000081', 'yan@reads.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_reads', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'mod_reads', 'Mo'),
  ('00000000-0000-4000-8000-0000000000c1', 'newt_reads', 'Newt'),
  ('00000000-0000-4000-8000-0000000000d1', 'olly_reads', 'Olly'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve_reads', 'Eve'),
  ('00000000-0000-4000-8000-0000000000f1', 'fay_reads', 'Fay'),
  ('00000000-0000-4000-8000-000000000091', 'zed_reads', 'Zed'),
  ('00000000-0000-4000-8000-000000000081', 'yan_reads', 'Yan');

-- Acts as one of the people (a..f, 9 is Zed, 8 is Yan), as PostgREST would.
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

-- Sends a text message as one of the people into the conversation called
-- [chat] in ids; null when AutoMod dropped it.
create function pg_temp.say(who text, chat text, text_body text, mention_of text default null)
returns uuid language plpgsql as $$
declare
  sent uuid;
  mentions jsonb := '[]'::jsonb;
begin
  perform pg_temp.act_as(who);
  if mention_of is not null then
    mentions := jsonb_build_array(jsonb_build_object(
      'kind', 'user',
      'user_id', format('00000000-0000-4000-8000-0000000000%s1', mention_of),
      'display_name', 'x', 'start', 0, 'end', 1
    ));
  end if;
  sent := public.send_text_message(
    (select id from ids where name = chat), text_body, null, null, mentions
  );
  perform pg_temp.act_as(null);
  return sent;
end;
$$;
grant execute on function pg_temp.say(text, text, text, text) to public;

create function pg_temp.mid(name text) returns uuid language sql stable as $$
  select id from ids where ids.name = mid.name;
$$;
grant execute on function pg_temp.mid(text) to public;



-- The people: a Ada (the sender), b Mo, c Newt, d Olly, e Eve, f Fay (not in
-- the group), 9 Zed, 8 Yan. (Lists come back in user id order: 8 9 a b c d e.)
create function pg_temp.u(who text) returns uuid language sql immutable as $$
  select format('00000000-0000-4000-8000-0000000000%s1', who)::uuid;
$$;
grant execute on function pg_temp.u(text) to public;

-- The read list of a message as one of the people asks for it: "who:status".
create function pg_temp.status_as(who text, msg text)
returns text language plpgsql as $$
declare
  result text;
begin
  perform pg_temp.act_as(who);
  select string_agg(substr(s.user_id::text, 35, 1) || ':' || s.status, ',' order by s.user_id)
  into result
  from public.get_message_read_status(pg_temp.mid(msg)) s;
  perform pg_temp.act_as(null);
  return coalesce(result, '');
exception when others then
  perform pg_temp.act_as(null);
  raise;
end;
$$;
grant execute on function pg_temp.status_as(text, text) to public;

-- The read positions one of the people may know of [chat]: "who:message".
create function pg_temp.markers_as(who text, chat text)
returns text language plpgsql as $$
declare
  result text;
begin
  perform pg_temp.act_as(who);
  select string_agg(
    substr(m.user_id::text, 35, 1) || ':' || coalesce(
      (select i.name from ids i where i.id = m.last_read_message_id), '-'),
    ',' order by m.user_id)
  into result
  from public.list_read_markers(pg_temp.mid(chat)) m;
  perform pg_temp.act_as(null);
  return coalesce(result, '');
exception when others then
  perform pg_temp.act_as(null);
  raise;
end;
$$;
grant execute on function pg_temp.markers_as(text, text) to public;

-- Reminds as one of the people; how many were reminded.
create function pg_temp.remind_as(who text, msg text)
returns integer language plpgsql as $$
declare
  reminded integer;
begin
  perform pg_temp.act_as(who);
  reminded := public.remind_unread(pg_temp.mid(msg));
  perform pg_temp.act_as(null);
  return reminded;
exception when others then
  perform pg_temp.act_as(null);
  raise;
end;
$$;
grant execute on function pg_temp.remind_as(text, text) to public;

-- The messages one of the people has a "Reminder" card for, by name.
create function pg_temp.cards_as(who text)
returns text language plpgsql as $$
declare
  result text;
begin
  perform pg_temp.act_as(who);
  select string_agg(coalesce((select i.name from ids i where i.id = n.message_id), '?'), ','
                    order by n.message_id)
  into result
  from public.list_read_reminder_notices() n;
  perform pg_temp.act_as(null);
  return coalesce(result, '');
exception when others then
  perform pg_temp.act_as(null);
  raise;
end;
$$;
grant execute on function pg_temp.cards_as(text) to public;

-- Where someone has read up to.
create function pg_temp.read_up_to(who text, chat text, msg text) returns void language sql as $$
  update public.conversation_members
  set last_read_message_id = case when msg is null then null else pg_temp.mid(msg) end
  where conversation_id = pg_temp.mid(chat) and user_id = pg_temp.u(who);
$$;
grant execute on function pg_temp.read_up_to(text, text, text) to public;

-- A message put straight into a chat (any kind of chat), [ago] old.
create function pg_temp.put(who text, chat text, ago interval default interval '1 hour')
returns uuid language sql as $$
  insert into public.messages (conversation_id, sender_id, body, created_at)
  values (pg_temp.mid(chat), pg_temp.u(who), 'x', now() - ago)
  returning id;
$$;
grant execute on function pg_temp.put(text, text, interval) to public;

-- ====================================================================== setup

-- Ada owns the group; Mo, Newt, Olly, Eve and Zed are members; Fay is not.
-- Yan joins after the messages were sent.
insert into public.conversations (type, title) values ('group', 'Readers') returning id \gset grp_
insert into ids values ('grp', :'grp_id');
insert into public.conversation_members (conversation_id, user_id, role, joined_at)
select :'grp_id', pg_temp.u(w), case w when 'a' then 'owner' else 'member' end,
       now() - interval '1 day'
from unnest(array['a', 'b', 'c', 'd', 'e', '9']) as w;
insert into public.conversation_members (conversation_id, user_id, role, joined_at)
values (:'grp_id', pg_temp.u('8'), 'member', now() + interval '1 minute');

-- m0 (Mo, 3h ago), m1 (Ada, 2h), m2 (Mo, 1h), m3 (Ada, 30 min).
insert into ids select 'm0', pg_temp.say('b', 'grp', 'earlier');
insert into ids select 'm1', pg_temp.say('a', 'grp', 'please read the notice');
insert into ids select 'm2', pg_temp.say('b', 'grp', 'a later reply');
insert into ids select 'm3', pg_temp.say('a', 'grp', 'one more thing');
update public.messages set created_at = now() - interval '3 hours' where id = pg_temp.mid('m0');
update public.messages set created_at = now() - interval '2 hours' where id = pg_temp.mid('m1');
update public.messages set created_at = now() - interval '1 hour' where id = pg_temp.mid('m2');
update public.messages set created_at = now() - interval '30 minutes' where id = pg_temp.mid('m3');

-- Mo read up to m2, Newt exactly to m1, Olly only to m0, Eve nothing, Zed to
-- m3, Ada to her own m3.
select pg_temp.read_up_to('b', 'grp', 'm2');
select pg_temp.read_up_to('c', 'grp', 'm1');
select pg_temp.read_up_to('d', 'grp', 'm0');
select pg_temp.read_up_to('e', 'grp', null);
select pg_temp.read_up_to('9', 'grp', 'm3');
select pg_temp.read_up_to('a', 'grp', 'm3');

-- ================================================= the switch and its default

select pg_temp.check('read receipts are on for someone who never chose',
  public.read_receipts_enabled(pg_temp.u('b')));
select pg_temp.check('the column defaults to on',
  (select column_default = 'true' from information_schema.columns
   where table_schema = 'public' and table_name = 'user_privacy_settings'
     and column_name = 'send_read_receipts'));
select pg_temp.refused('saving the switch needs a signed-in person',
  'select public.set_send_read_receipts(false)', '42501');
select pg_temp.act_as('9');
select pg_temp.refused('the switch needs a value',
  'select public.set_send_read_receipts(null)', '22023');
select public.set_send_read_receipts(false);
select pg_temp.act_as(null);
select pg_temp.check('Zed turned receipts off',
  not public.read_receipts_enabled(pg_temp.u('9')));
select pg_temp.check('the others are unaffected',
  public.read_receipts_enabled(pg_temp.u('b')));

-- ============================================================ the read list

select pg_temp.check(
  'the sender sees read, unread and unknown (receipts off); Yan joined later and is not listed',
  pg_temp.status_as('a', 'm1') = '9:unknown,b:read,c:read,d:unread,e:unread');
insert into ids select 'a0', pg_temp.put('a', 'grp', interval '4 hours');
select pg_temp.check('read means the last read message is as new as this one or newer',
  pg_temp.status_as('a', 'a0') = '9:unknown,b:read,c:read,d:read,e:unread');
select pg_temp.check('and not when it is older',
  pg_temp.status_as('a', 'm3') = '9:unknown,b:unread,c:unread,d:unread,e:unread');
select pg_temp.refused('someone else in the group cannot ask, even about a message they can see',
  $s$select pg_temp.status_as('b', 'm1')$s$, '42501');
select pg_temp.refused('the group owner cannot ask about someone else''s message',
  $s$select pg_temp.status_as('a', 'm2')$s$, '42501');
select pg_temp.refused('a person outside the chat finds no message',
  $s$select pg_temp.status_as('f', 'm1')$s$, 'P0002');
select pg_temp.refused('a signed-out caller is refused',
  $s$select pg_temp.status_as(null, 'm1')$s$, '42501');

-- Messages that have no list.
insert into ids select 'recalled', pg_temp.put('a', 'grp');
update public.messages set recalled_at = now() where id = pg_temp.mid('recalled');
insert into ids select 'expired', pg_temp.put('a', 'grp');
update public.messages set expires_at = now() - interval '1 minute' where id = pg_temp.mid('expired');
insert into ids select 'review', pg_temp.put('a', 'grp');
update public.messages set review_state = 'checking' where id = pg_temp.mid('review');
select pg_temp.refused('a deleted message has no list',
  $s$select pg_temp.status_as('a', 'recalled')$s$, '22023');
select pg_temp.refused('an expired message has none',
  $s$select pg_temp.status_as('a', 'expired')$s$, '22023');
select pg_temp.refused('a message waiting for review has none',
  $s$select pg_temp.status_as('a', 'review')$s$, '22023');

-- Not for a direct chat, a circle channel or the note to self.
insert into public.conversations (type, title) values ('direct', null) returning id \gset dm_
insert into ids values ('dm', :'dm_id');
insert into public.conversation_members (conversation_id, user_id)
values (:'dm_id', pg_temp.u('a')), (:'dm_id', pg_temp.u('b'));
insert into ids select 'dm1', pg_temp.put('a', 'dm');
select pg_temp.refused('a direct chat shows "Read", not a list',
  $s$select pg_temp.status_as('a', 'dm1')$s$, '22023');

insert into public.conversations (type, title) values ('channel', 'general') returning id \gset ch_
insert into ids values ('chan', :'ch_id');
insert into public.conversation_members (conversation_id, user_id)
values (:'ch_id', pg_temp.u('a')), (:'ch_id', pg_temp.u('b'));
insert into ids select 'ch1', pg_temp.put('a', 'chan');
select pg_temp.refused('a circle channel has no list',
  $s$select pg_temp.status_as('a', 'ch1')$s$, '22023');

select pg_temp.act_as('a');
select public.get_note_to_self(true) as note_id \gset
select pg_temp.act_as(null);
insert into ids values ('note', :'note_id');
insert into ids select 'note1', pg_temp.put('a', 'note');
select pg_temp.refused('the note to self has no list',
  $s$select pg_temp.status_as('a', 'note1')$s$, '22023');

-- ------------------------------------------------------ the 200 member cap

insert into auth.users (id, email, instance_id, aud, role)
select format('00000000-0000-4000-8001-%s', lpad(n::text, 12, '0'))::uuid,
       'big' || n || '@reads.test', '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated'
from generate_series(1, 200) n;
insert into public.profiles (id, username, display_name)
select format('00000000-0000-4000-8001-%s', lpad(n::text, 12, '0'))::uuid,
       'big_reads_' || n, 'Big ' || n
from generate_series(1, 200) n;
insert into public.conversations (type, title) values ('group', 'Big') returning id \gset big_
insert into ids values ('big', :'big_id');
insert into public.conversation_members (conversation_id, user_id, role)
values (:'big_id', pg_temp.u('a'), 'owner');
insert into public.conversation_members (conversation_id, user_id, joined_at)
select :'big_id', format('00000000-0000-4000-8001-%s', lpad(n::text, 12, '0'))::uuid,
       now() - interval '1 day'
from generate_series(1, 199) n;
insert into ids select 'big1', pg_temp.put('a', 'big');
select pg_temp.check('a group of exactly 200 has its list: the other 199',
  array_length(string_to_array(pg_temp.status_as('a', 'big1'), ','), 1) = 199);
insert into public.conversation_members (conversation_id, user_id)
values (:'big_id', format('00000000-0000-4000-8001-%s', lpad('200', 12, '0'))::uuid);
select pg_temp.refused('201 members: no list',
  $s$select pg_temp.status_as('a', 'big1')$s$, '22023');
select pg_temp.refused('and nobody can be reminded',
  $s$select pg_temp.remind_as('a', 'big1')$s$, '22023');

-- ------------------------------------------------------------ blocking

insert into public.blocks (blocker_id, blocked_id) values (pg_temp.u('a'), pg_temp.u('e'));
select pg_temp.check('someone the sender blocked is not listed',
  pg_temp.status_as('a', 'm1') = '9:unknown,b:read,c:read,d:unread');
delete from public.blocks;
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.u('c'), pg_temp.u('a'));
select pg_temp.check('someone who blocked the sender is not listed either',
  pg_temp.status_as('a', 'm1') = '9:unknown,b:read,d:unread,e:unread');
delete from public.blocks;

-- ----------------------------------- receipts off, both ways: the list

select pg_temp.act_as('a');
select public.set_send_read_receipts(false);
select pg_temp.refused('with receipts off the sender cannot see the list either',
  $s$select * from public.get_message_read_status(pg_temp.mid('m1'))$s$, 'P0001');
select pg_temp.refused('nor remind',
  $s$select public.remind_unread(pg_temp.mid('m1'))$s$, 'P0001');
select pg_temp.act_as(null);
select pg_temp.check('and nothing was used up',
  not exists (select 1 from public.message_read_reminders));

-- Ada's own switch is off now: she sees nobody's position in the group.
select pg_temp.check('with receipts off, Ada sees nobody else''s position',
  pg_temp.markers_as('a', 'grp') = '8:-,9:-,a:m3,b:-,c:-,d:-,e:-');
select pg_temp.check('and the others see no position of hers',
  pg_temp.markers_as('b', 'grp') = '8:-,9:-,a:-,b:m2,c:m1,d:m0,e:-');
select pg_temp.act_as('a');
select public.set_send_read_receipts(true);
select pg_temp.act_as(null);

-- ------------------------------------- read positions, as each may know them

select pg_temp.check('in a group everyone sees the positions of those who share them',
  pg_temp.markers_as('b', 'grp') = '8:-,9:-,a:m3,b:m2,c:m1,d:m0,e:-');
select pg_temp.check('Zed (receipts off) keeps his own position, and sees nobody else''s',
  pg_temp.markers_as('9', 'grp') = '8:-,9:m3,a:-,b:-,c:-,d:-,e:-');
select pg_temp.refused('a person outside the chat gets no positions',
  $s$select pg_temp.markers_as('f', 'grp')$s$, '42501');
select pg_temp.check('the note to self shows only its owner''s row',
  pg_temp.markers_as('a', 'note') = 'a:-');
select pg_temp.check('a circle channel shows only the caller''s own row',
  pg_temp.markers_as('a', 'chan') = 'a:-');
select pg_temp.check('a group of 201 shows only the caller''s own row',
  pg_temp.markers_as('a', 'big') = 'a:-');

-- A direct chat: "Read" follows the same two rules.
select pg_temp.read_up_to('b', 'dm', 'dm1');
select pg_temp.check('a direct chat shows the peer''s position',
  pg_temp.markers_as('a', 'dm') = 'a:-,b:dm1');
select pg_temp.act_as('b');
select public.set_send_read_receipts(false);
select pg_temp.act_as(null);
select pg_temp.check('the peer turned receipts off: Ada sees no "Read"',
  pg_temp.markers_as('a', 'dm') = 'a:-,b:-');
select pg_temp.check('and Mo still sees his own position',
  pg_temp.markers_as('b', 'dm') = 'a:-,b:dm1');
select pg_temp.act_as('b');
select public.set_send_read_receipts(true);
select pg_temp.act_as('a');
select public.set_send_read_receipts(false);
select pg_temp.act_as(null);
select pg_temp.read_up_to('a', 'dm', 'dm1');
select pg_temp.check('Ada turned hers off: she sees no "Read" for Mo',
  pg_temp.markers_as('a', 'dm') = 'a:dm1,b:-');
select pg_temp.check('and Mo sees no position for her',
  pg_temp.markers_as('b', 'dm') = 'a:-,b:dm1');
select pg_temp.act_as('a');
select public.set_send_read_receipts(true);
select pg_temp.act_as(null);
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.u('b'), pg_temp.u('a'));
select pg_temp.check('blocking hides the position too',
  pg_temp.markers_as('a', 'dm') = 'a:dm1,b:-');
delete from public.blocks;

-- ============================================================ remind unread

select pg_temp.refused('only the sender can remind',
  $s$select pg_temp.remind_as('b', 'm1')$s$, '42501');
select pg_temp.refused('a person outside the chat finds no message to remind about',
  $s$select pg_temp.remind_as('f', 'm1')$s$, 'P0002');
select pg_temp.refused('a deleted message cannot be reminded about',
  $s$select pg_temp.remind_as('a', 'recalled')$s$, '22023');
select pg_temp.refused('a direct chat message cannot either',
  $s$select pg_temp.remind_as('a', 'dm1')$s$, '22023');
select pg_temp.refused('nor a note to self',
  $s$select pg_temp.remind_as('a', 'note1')$s$, '22023');

-- Subscriptions: Olly (en), Eve (zh), Mo (en), Zed (en).
insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
values
  (pg_temp.u('d'), 'https://push.test/olly', repeat('p', 60), repeat('a', 20), 'en'),
  (pg_temp.u('e'), 'https://push.test/eve', repeat('p', 60), repeat('b', 20), 'zh'),
  (pg_temp.u('b'), 'https://push.test/mo', repeat('p', 60), repeat('c', 20), 'en'),
  (pg_temp.u('9'), 'https://push.test/zed', repeat('p', 60), repeat('d', 20), 'en');

-- Blocking an unread member leaves them out of the reminder too.
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.u('a'), pg_temp.u('e'));
select pg_temp.check('a blocked member is not among those reminded: only Olly is unread',
  pg_temp.status_as('a', 'm1') = '9:unknown,b:read,c:read,d:unread');
delete from public.blocks;

select pg_temp.check('Ada reminds the two who have not read it (Zed is unknown and left alone)',
  pg_temp.remind_as('a', 'm1') = 2);
select pg_temp.check('a reminder is recorded once for the message',
  (select count(*) = 1 and bool_and(recipient_count = 2 and sender_id = pg_temp.u('a'))
   from public.message_read_reminders where message_id = pg_temp.mid('m1')));
select pg_temp.check('Olly and Eve each got a notice, nobody else',
  (select array_agg(recipient_id order by recipient_id) = array[pg_temp.u('d'), pg_temp.u('e')]
   from public.read_reminder_notices where message_id = pg_temp.mid('m1')));
select pg_temp.refused('a message can be reminded about only once',
  $s$select pg_temp.remind_as('a', 'm1')$s$, 'P0001');

-- The "Reminder" cards.
select pg_temp.check('Olly has a card for the message', pg_temp.cards_as('d') = 'm1');
select pg_temp.check('so does Eve', pg_temp.cards_as('e') = 'm1');
select pg_temp.check('Mo, who had read it, has none', pg_temp.cards_as('b') = '');
select pg_temp.check('nor has Zed, whose receipts are off', pg_temp.cards_as('9') = '');
select pg_temp.check('nor has Ada', pg_temp.cards_as('a') = '');
select pg_temp.act_as('d');
select pg_temp.refused('the notice table is not readable directly',
  'select * from public.read_reminder_notices', '42501');
select pg_temp.check('Olly cannot see that Ada reminded (only the sender can)',
  (select count(*) = 0 from public.message_read_reminders));
select pg_temp.act_as('a');
select pg_temp.check('Ada can see that she did',
  (select count(*) = 1 from public.message_read_reminders));
select pg_temp.act_as(null);

-- Blocking the sender hides the card; unblocking brings it back.
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.u('e'), pg_temp.u('a'));
select pg_temp.check('Eve blocked Ada: her card is gone', pg_temp.cards_as('e') = '');
delete from public.blocks;
select pg_temp.check('and back when unblocked', pg_temp.cards_as('e') = 'm1');
-- Reading the message answers the reminder.
select pg_temp.read_up_to('d', 'grp', 'm3');
select pg_temp.check('Olly read up to m3: his card is gone', pg_temp.cards_as('d') = '');
select pg_temp.act_as('e');
select public.mark_read_reminder_notices_read(null);
select pg_temp.act_as(null);
select pg_temp.check('Eve dismissed hers', pg_temp.cards_as('e') = '');

-- The push: claimed once, in each device's language.
select pg_temp.check('someone else cannot claim the push',
  (select count(*) = 0 from public.claim_read_reminder_pushes(pg_temp.mid('m1'), pg_temp.u('b'))));
select pg_temp.check('the sender claims it for Olly and Eve',
  (select count(*) = 2 from public.claim_read_reminder_pushes(pg_temp.mid('m1'), pg_temp.u('a'))));
select pg_temp.check('and only once',
  (select count(*) = 0 from public.claim_read_reminder_pushes(pg_temp.mid('m1'), pg_temp.u('a'))));
-- (re-arm to look at the words)
update public.read_reminder_notices set pushed_at = null where message_id = pg_temp.mid('m1');
select pg_temp.check('Olly''s push is in English with the message time as a token',
  (select p.title = 'Reminder: Ada (Readers)'
     and p.body ~ '^Sent <t:[0-9]+:t> · please read the notice$'
   from public.claim_read_reminder_pushes(pg_temp.mid('m1'), pg_temp.u('a')) p
   join public.push_subscriptions s on s.id = p.subscription_id
   where s.user_id = pg_temp.u('d')));
update public.read_reminder_notices set pushed_at = null where message_id = pg_temp.mid('m1');
select pg_temp.check('Eve''s is in Chinese, same token',
  (select p.title = '提醒：Ada (Readers)'
     and p.body ~ '^发送于 <t:[0-9]+:t> · please read the notice$'
   from public.claim_read_reminder_pushes(pg_temp.mid('m1'), pg_temp.u('a')) p
   join public.push_subscriptions s on s.id = p.subscription_id
   where s.user_id = pg_temp.u('e')));

-- Do Not Disturb and people who left are not pushed; the card stays. Newt
-- gets a device too.
insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
values (pg_temp.u('c'), 'https://push.test/newt', repeat('p', 60), repeat('e', 20), 'en');
select pg_temp.check('Ada reminds about m3: Mo, Newt and Eve are unread (Olly has read it)',
  pg_temp.remind_as('a', 'm3') = 3);
insert into public.user_privacy_settings (user_id, presence_status)
values (pg_temp.u('b'), 'dnd')
on conflict (user_id) do update set presence_status = 'dnd';
delete from public.conversation_members
where conversation_id = pg_temp.mid('grp') and user_id = pg_temp.u('e');
select pg_temp.check('Newt is pushed; Mo (Do Not Disturb) and Eve (left) are not',
  (select count(*) = 1 and bool_and(s.user_id = pg_temp.u('c'))
   from public.claim_read_reminder_pushes(pg_temp.mid('m3'), pg_temp.u('a')) p
   join public.push_subscriptions s on s.id = p.subscription_id));
select pg_temp.check('Mo still has his card', pg_temp.cards_as('b') = 'm3');
select pg_temp.check('Eve left: no card', pg_temp.cards_as('e') = '');

-- Quiet hours: the push functions hold the push back; a reminder is not a
-- message, so nothing breaks through for it, not even a VIP.
insert into public.user_notification_settings
  (user_id, quiet_enabled, vip_user_ids, allow_starred)
values (pg_temp.u('b'), true, array[pg_temp.u('a')], true)
on conflict (user_id) do update
  set quiet_enabled = true, vip_user_ids = array[pg_temp.u('a')];
select pg_temp.check('Mo has quiet hours on and Ada is his VIP; her reminder does not break through',
  (select count(*) = 1 and bool_and(not r.breaks_through)
   from public.quiet_hours_recipients(
     (select array_agg(id) from public.push_subscriptions where user_id = pg_temp.u('b')), null) r));
select pg_temp.check('(her chat message would)',
  (select count(*) = 1 and bool_and(r.breaks_through)
   from public.quiet_hours_recipients(
     (select array_agg(id) from public.push_subscriptions where user_id = pg_temp.u('b')),
     pg_temp.mid('m3')) r));

-- ------------------------------------------ nothing to remind, then the limit

insert into public.conversations (type, title) values ('group', 'Pair') returning id \gset pair_
insert into ids values ('pair', :'pair_id');
insert into public.conversation_members (conversation_id, user_id, role, joined_at)
values (:'pair_id', pg_temp.u('a'), 'owner', now() - interval '1 day'),
       (:'pair_id', pg_temp.u('b'), 'member', now() - interval '1 day');
insert into ids select 'p1', pg_temp.put('a', 'pair', interval '2 hours');
insert into ids select 'p2', pg_temp.put('b', 'pair', interval '1 hour');
select pg_temp.read_up_to('b', 'pair', 'p2');
select pg_temp.refused('everyone has read it: nobody to remind',
  $s$select pg_temp.remind_as('a', 'p1')$s$, 'P0001');
select pg_temp.check('and the one reminder of the message is not used up',
  not exists (select 1 from public.message_read_reminders where message_id = pg_temp.mid('p1')));
select pg_temp.read_up_to('b', 'pair', null);
select pg_temp.check('once Mo has not read it, it works', pg_temp.remind_as('a', 'p1') = 1);

-- 30 reminders a day: Ada has done 3 (m1, m3, p1); 27 more fill the day.
insert into ids select 'f' || n, pg_temp.put('a', 'pair', interval '90 minutes')
from generate_series(1, 27) n;
insert into public.message_read_reminders (message_id, sender_id, recipient_count)
select id, pg_temp.u('a'), 1 from ids where name ~ '^f[0-9]+$';
insert into ids select 'p3', pg_temp.put('a', 'pair', interval '30 minutes');
select pg_temp.refused('after 30 in a day, no more',
  $s$select pg_temp.remind_as('a', 'p3')$s$, '53400');
update public.message_read_reminders set created_at = now() - interval '2 days'
where message_id = pg_temp.mid('f1');
select pg_temp.check('one drops out of the day and there is room again',
  pg_temp.remind_as('a', 'p3') = 1);

-- ------------------------------------------------------------ clean-up

delete from public.messages where id = pg_temp.mid('m1');
select pg_temp.check('deleting the message removes the reminder and its notices',
  not exists (select 1 from public.message_read_reminders where message_id = pg_temp.mid('m1'))
  and not exists (select 1 from public.read_reminder_notices where message_id = pg_temp.mid('m1')));

rollback;
