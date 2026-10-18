-- Behaviour checks for edit history and re-review after edits (migrations
-- 202610220210 and 202610220220). Run by test/supabase/edit_history_test.dart
-- against the local database: it applies every migration the database lacks
-- (the local baseline is 202610140001) inside a transaction, acts as several
-- people, checks what they can read and what the AI guard does with an edit,
-- and rolls back, so the database is left as it was. Run from the repository
-- root.
\set ON_ERROR_STOP on

begin;

-- One behaviour script at a time: they change the same tables, and test
-- files run in parallel.
do $$ begin perform pg_advisory_xact_lock(20261017); end $$;
set local client_min_messages = warning;

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
\i supabase/migrations/202610220210_message_edit_history.sql
\i supabase/migrations/202610220220_edit_review.sql

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@edits.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'mod@edits.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'newt@edits.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d1', 'olly@edits.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve@edits.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000f1', 'fay@edits.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-000000000091', 'zed@edits.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-000000000081', 'yan@edits.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_edits', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'mod_edits', 'Mo'),
  ('00000000-0000-4000-8000-0000000000c1', 'newt_edits', 'Newt'),
  ('00000000-0000-4000-8000-0000000000d1', 'olly_edits', 'Olly'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve_edits', 'Eve'),
  ('00000000-0000-4000-8000-0000000000f1', 'fay_edits', 'Fay'),
  ('00000000-0000-4000-8000-000000000091', 'zed_edits', 'Zed'),
  ('00000000-0000-4000-8000-000000000081', 'yan_edits', 'Yan');

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

-- Edits through the app's own function, as one of the people.
create function pg_temp.edit(who text, msg text, new_body text) returns void language plpgsql as $$
begin
  perform pg_temp.act_as(who);
  perform public.edit_message(pg_temp.mid(msg), new_body);
  perform pg_temp.act_as(null);
end;
$$;
grant execute on function pg_temp.edit(text, text, text) to public;

-- The history of a message as the signed-in person reads it.
create function pg_temp.history_as(who text, msg text)
returns table (version integer, body text) language plpgsql as $$
begin
  perform pg_temp.act_as(who);
  return query
    select e.version, e.body from public.message_edits e
    where e.message_id = pg_temp.mid(msg) order by e.version;
  perform pg_temp.act_as(null);
end;
$$;
grant execute on function pg_temp.history_as(text, text) to public;

-- ===================================================== a group, no circle

-- Ada owns the group; Eve, Olly and Zed are members; Fay is not.
insert into public.conversations (type, title) values ('group', 'Edits') returning id \gset grp_
insert into ids values ('grp', :'grp_id');
insert into public.conversation_members (conversation_id, user_id, role)
values
  (:'grp_id', '00000000-0000-4000-8000-0000000000a1', 'owner'),
  (:'grp_id', '00000000-0000-4000-8000-0000000000e1', 'member'),
  (:'grp_id', '00000000-0000-4000-8000-0000000000d1', 'member'),
  (:'grp_id', '00000000-0000-4000-8000-000000000091', 'member'),
  (:'grp_id', '00000000-0000-4000-8000-000000000081', 'member');

-- ------------------------------------------------------------ keeping versions

insert into ids select 'm1', pg_temp.say('a', 'grp', 'first draft', 'e');
update public.messages set created_at = now() - interval '1 day' where id = pg_temp.mid('m1');
select pg_temp.check('a message that was never edited has no history',
  not exists (select 1 from public.message_edits where message_id = pg_temp.mid('m1')));
select pg_temp.edit('a', 'm1', 'second draft');
select pg_temp.edit('a', 'm1', 'third draft');
select pg_temp.check('the message shows the latest text',
  (select m.body = 'third draft' and m.edited_at is not null from public.messages m where m.id = pg_temp.mid('m1')));
select pg_temp.check('every earlier version is kept, oldest first',
  (select array_agg(e.body order by e.version) = array['first draft', 'second draft']
          and array_agg(e.version order by e.version) = array[1, 2]
   from public.message_edits e where e.message_id = pg_temp.mid('m1')));
select pg_temp.check('the first version is dated by when the message was sent',
  (select e.edited_at = (select created_at from public.messages where id = pg_temp.mid('m1'))
   from public.message_edits e where e.message_id = pg_temp.mid('m1') and e.version = 1));
select pg_temp.check('a version keeps its mentions',
  (select jsonb_array_length(e.mentions) = 1 and e.mentions->0->>'user_id' = '00000000-0000-4000-8000-0000000000e1'
   from public.message_edits e where e.message_id = pg_temp.mid('m1') and e.version = 1));
select pg_temp.edit('a', 'm1', 'third draft');
select pg_temp.check('saving the same text again adds no version',
  (select count(*) = 2 from public.message_edits where message_id = pg_temp.mid('m1')));

-- ---------------------------------------------------------------- who reads it

select pg_temp.check('a member reads the history',
  (select count(*) = 2 and bool_and(h.body in ('first draft', 'second draft')) from pg_temp.history_as('e', 'm1') h));
select pg_temp.check('so does the author',
  (select count(*) = 2 from pg_temp.history_as('a', 'm1') h));
select pg_temp.check('someone outside the chat reads nothing',
  (select count(*) = 0 from pg_temp.history_as('f', 'm1') h));
select pg_temp.act_as('f');
select pg_temp.check('and cannot find the message either',
  (select count(*) = 0 from public.messages where id = pg_temp.mid('m1')));
select pg_temp.act_as('e');
select pg_temp.refused('a member cannot add a version',
  format('insert into public.message_edits (message_id, version, body, edited_at) values (%L, 9, ''x'', now())', pg_temp.mid('m1')), '42501');
select pg_temp.refused('a member cannot change a version',
  format('update public.message_edits set body = ''x'' where message_id = %L', pg_temp.mid('m1')), '42501');
select pg_temp.refused('a member cannot delete a version',
  format('delete from public.message_edits where message_id = %L', pg_temp.mid('m1')), '42501');
select pg_temp.refused('a member cannot edit someone else''s message',
  format('select public.edit_message(%L, ''hijacked'')', pg_temp.mid('m1')), '42501');
select pg_temp.act_as(null);
set local role anon;
select pg_temp.refused('anonymous callers cannot read it',
  'select count(*) from public.message_edits', '42501');
reset role;
select pg_temp.check('a refused edit leaves the history as it was',
  (select count(*) = 2 from public.message_edits where message_id = pg_temp.mid('m1')));

-- Search keeps only the latest version.
select pg_temp.act_as('e');
select pg_temp.check('search finds the latest text and not the old ones',
  (select count(*) = 1 from public.search_messages('third'))
  and (select count(*) = 0 from public.search_messages('first'))
  and (select count(*) = 0 from public.search_messages('second')));
select pg_temp.act_as(null);

-- ---------------------------------------------------------------------- recall

insert into ids select 'm2', pg_temp.say('a', 'grp', 'recall me');
select pg_temp.edit('a', 'm2', 'recall me, edited');
select pg_temp.check('it has a version', (select count(*) = 1 from public.message_edits where message_id = pg_temp.mid('m2')));
select pg_temp.act_as('a');
select public.recall_message(pg_temp.mid('m2'));
select pg_temp.act_as(null);
select pg_temp.check('recalling the message deletes its history, and the blanked body is not kept',
  (select recalled_at is not null from public.messages where id = pg_temp.mid('m2'))
  and (select count(*) = 0 from public.message_edits where message_id = pg_temp.mid('m2')));
select pg_temp.check('nobody can read what it used to say',
  (select count(*) = 0 from pg_temp.history_as('e', 'm2') h));

-- ------------------------------------------------------- disappearing messages

select pg_temp.act_as('a');
select public.set_disappearing_messages(pg_temp.mid('grp'), 86400);
select pg_temp.act_as(null);
insert into ids select 'm3', pg_temp.say('a', 'grp', 'this will disappear');
select pg_temp.edit('a', 'm3', 'this will disappear soon');
select pg_temp.check('a disappearing message has a history while it lasts',
  (select m.expires_at is not null from public.messages m where m.id = pg_temp.mid('m3'))
  and (select count(*) = 1 from pg_temp.history_as('e', 'm3') h));
update public.messages set expires_at = now() - interval '1 minute' where id = pg_temp.mid('m3');
select pg_temp.check('once it expires its history is unreadable even before the purge',
  (select count(*) = 0 from pg_temp.history_as('e', 'm3') h)
  and (select count(*) = 0 from pg_temp.history_as('a', 'm3') h)
  and (select count(*) = 1 from public.message_edits where message_id = pg_temp.mid('m3')));
select public.purge_expired_messages(500) as purged \gset
select pg_temp.check('the purge deletes the message',
  :purged >= 1 and not exists (select 1 from public.messages where id = pg_temp.mid('m3')));
select pg_temp.check('and the purge takes the history with it',
  not exists (select 1 from public.message_edits where message_id = pg_temp.mid('m3')));
select pg_temp.act_as('a');
select public.set_disappearing_messages(pg_temp.mid('grp'), null);
select pg_temp.act_as(null);

-- ------------------------------------------------------------------- view once

insert into ids select 'once', gen_random_uuid();
insert into public.messages (id, conversation_id, sender_id, type, body, attachment)
values (pg_temp.mid('once'), pg_temp.mid('grp'), '00000000-0000-4000-8000-0000000000a1', 'image', '',
  jsonb_build_object('kind', 'image', 'bucket', 'chat-images',
    'path', pg_temp.mid('grp')::text || '/once.jpg', 'mime_type', 'image/jpeg', 'view_once', true));
select pg_temp.act_as('a');
select pg_temp.refused('a view-once photo cannot be edited',
  format('select public.edit_message(%L, ''a caption'')', pg_temp.mid('once')), '42501');
select pg_temp.act_as(null);
update public.messages set body = 'caption forced in' where id = pg_temp.mid('once');
select pg_temp.check('and even a forced change of its text keeps no history',
  not exists (select 1 from public.message_edits where message_id = pg_temp.mid('once')));
-- A view-once photo that somehow had a history loses it when it is deleted.
insert into public.message_edits (message_id, version, body, edited_at)
values (pg_temp.mid('once'), 1, 'stray', now());
update public.messages set recalled_at = now(), body = '', attachment = null where id = pg_temp.mid('once');
select pg_temp.check('deleting a view-once message clears any history',
  not exists (select 1 from public.message_edits where message_id = pg_temp.mid('once')));

-- ----------------------------------------------------------- deleting an account

insert into ids select 'm4', pg_temp.say('9', 'grp', 'zed was here');
select pg_temp.edit('9', 'm4', 'zed was here, edited');
select pg_temp.check('Zed''s message has a history',
  (select count(*) = 1 from public.message_edits where message_id = pg_temp.mid('m4')));
insert into ids select 'm5', pg_temp.say('9', 'grp', 'zed again');
select pg_temp.edit('9', 'm5', 'zed again, edited');
select pg_temp.act_as('9');
select * from public.prepare_account_deletion();
select pg_temp.act_as(null);
select pg_temp.check('deleting the account clears the history of all their messages',
  (select count(*) = 0 from public.message_edits where message_id in (pg_temp.mid('m4'), pg_temp.mid('m5'))));
select pg_temp.check('while the messages stay in the chat',
  (select count(*) = 2 from public.messages where id in (pg_temp.mid('m4'), pg_temp.mid('m5'))));
-- A profile that is really removed takes its messages and history along.
insert into ids select 'm6', pg_temp.say('8', 'grp', 'yan says');
select pg_temp.edit('8', 'm6', 'yan says, edited');
delete from public.profiles where id = '00000000-0000-4000-8000-000000000081';
select pg_temp.check('removing the profile removes the messages and their history',
  not exists (select 1 from public.messages where id = pg_temp.mid('m6'))
  and not exists (select 1 from public.message_edits where message_id = pg_temp.mid('m6')));

-- =================================================================== the circle

select pg_temp.act_as('a');
insert into ids select 'circle', public.create_circle('Edited circle', array[]::uuid[]);
select pg_temp.act_as(null);

insert into ids
select 'channel', cc.conversation_id
from public.circle_channels cc
where cc.circle_id = pg_temp.mid('circle') and cc.position = 0;

insert into public.circle_members (circle_id, user_id, role, created_at)
select pg_temp.mid('circle'), u.id, 'member',
  case when u.id = '00000000-0000-4000-8000-0000000000d1' then now() - interval '10 days' else now() end
from (values
  ('00000000-0000-4000-8000-0000000000b1'::uuid),
  ('00000000-0000-4000-8000-0000000000c1'::uuid),
  ('00000000-0000-4000-8000-0000000000d1'::uuid),
  ('00000000-0000-4000-8000-0000000000e1'::uuid)
) u(id);
insert into public.conversation_members (conversation_id, user_id, role)
select pg_temp.mid('channel'), cm.user_id, cm.role
from public.circle_members cm where cm.circle_id = pg_temp.mid('circle')
on conflict do nothing;

with role as (
  insert into public.circle_roles (circle_id, name, position, permissions)
  values (pg_temp.mid('circle'), 'Mods', 1, public.circle_default_role_permissions() | 4)
  returning id
)
insert into public.circle_member_roles (circle_id, user_id, role_id)
select pg_temp.mid('circle'), '00000000-0000-4000-8000-0000000000b1', role.id from role;

-- ------------------------------------------------- guard off: edits are free

insert into ids select 'c1', pg_temp.say('c', 'channel', 'hello there');
select pg_temp.edit('c', 'c1', 'hello again');
select pg_temp.check('with the guard off an edit is not checked',
  (select review_state is null from public.messages where id = pg_temp.mid('c1'))
  and not exists (select 1 from public.message_reviews where message_id = pg_temp.mid('c1'))
  and (select count(*) = 1 from public.message_edits where message_id = pg_temp.mid('c1')));

select pg_temp.act_as('a');
select public.set_circle_ai_guard(pg_temp.mid('circle'), true, 'joined_days', 3, 10, 'hold');
select pg_temp.act_as(null);

-- Nothing can wake the function yet (no Vault secrets): an edit is released at
-- once, not checked, in its place and without a push.
insert into ids select 'u1', pg_temp.say('c', 'channel', 'sent before the edit');
update public.messages set created_at = now() - interval '2 hours' where id = pg_temp.mid('u1');
select pg_temp.edit('c', 'u1', 'edited with no way to wake the AI');
select pg_temp.check('when the check cannot start an edit is released, not checked',
  (select m.review_state is null and m.body = 'edited with no way to wake the AI' from public.messages m where m.id = pg_temp.mid('u1'))
  and (select r.state = 'released' and r.verdict = 'not_checked' and r.unchecked_reason = 'unavailable'
              and r.after_edit and not r.push_pending
       from public.message_reviews r where r.message_id = pg_temp.mid('u1')));
select pg_temp.check('and it keeps its place in the chat',
  (select m.created_at < now() - interval '1 hour' from public.messages m where m.id = pg_temp.mid('u1')));

select vault.create_secret('http://127.0.0.1:54321/functions/v1', 'wecord_functions_url');
select vault.create_secret('edits-test-secret', 'wecord_dispatch_secret');

-- ------------------------------------------------ a new member's edit is checked

insert into ids select 'n1', pg_temp.say('c', 'channel', 'a friendly hello');
select public.finish_message_review(pg_temp.mid('n1'), 'allow');
update public.messages set created_at = now() - interval '2 hours' where id = pg_temp.mid('n1');
select pg_temp.check('the sent message was released',
  (select review_state is null from public.messages where id = pg_temp.mid('n1')));
select pg_temp.edit('c', 'n1', 'buy cheap pills here');

select pg_temp.check('the edit puts the message back to checking',
  (select m.review_state = 'checking' and m.body = 'buy cheap pills here' from public.messages m where m.id = pg_temp.mid('n1')));
select pg_temp.check('its review starts over, marked as an edit, with no push',
  (select r.state = 'checking' and r.verdict is null and r.reason is null and r.after_edit
          and not r.push_pending and r.check_started_at is null and r.released_at is null
          and r.mode = 'hold'
   from public.message_reviews r where r.message_id = pg_temp.mid('n1')));
select pg_temp.check('the database woke the ai function for the edit, with the shared secret',
  (select count(*) = 2 from net.http_request_queue q
    where q.url = 'http://127.0.0.1:54321/functions/v1/ai'
      and q.headers->>'Authorization' = 'Bearer edits-test-secret'
      and convert_from(q.body, 'UTF8')::jsonb->>'action' = 'guard'
      and convert_from(q.body, 'UTF8')::jsonb->>'message_id' = pg_temp.mid('n1')::text));
select pg_temp.check('the earlier version was kept',
  (select count(*) = 1 and bool_and(e.body = 'a friendly hello') from public.message_edits e where e.message_id = pg_temp.mid('n1')));

select pg_temp.act_as('e');
select pg_temp.check('other members cannot see the message while it waits',
  (select count(*) = 0 from public.messages where id = pg_temp.mid('n1')));
select pg_temp.check('nor its history',
  (select count(*) = 0 from public.message_edits where message_id = pg_temp.mid('n1')));
select pg_temp.check('nor find it by search, old or new text',
  (select count(*) = 0 from public.search_messages('pills')) and (select count(*) = 0 from public.search_messages('friendly')));
select pg_temp.act_as('c');
select pg_temp.check('the author sees the message and the history',
  (select count(*) = 1 from public.messages where id = pg_temp.mid('n1'))
  and (select count(*) = 1 from public.message_edits where message_id = pg_temp.mid('n1')));
select pg_temp.refused('the author cannot edit it again while it waits',
  format('select public.edit_message(%L, ''harmless now'')', pg_temp.mid('n1')), '42501');
select pg_temp.act_as('b');
select pg_temp.check('a moderator sees the message and its history',
  (select count(*) = 1 from public.messages where id = pg_temp.mid('n1'))
  and (select count(*) = 1 from public.message_edits where message_id = pg_temp.mid('n1')));
select pg_temp.act_as(null);
select pg_temp.check('the history still holds one version after the refused edit',
  (select count(*) = 1 from public.message_edits where message_id = pg_temp.mid('n1')));
select pg_temp.check('the function is given the new text to check',
  (select count(*) = 1 and bool_and(c.body = 'buy cheap pills here' and c.ai_enabled)
   from public.ai_guard_claim(pg_temp.mid('n1')) c));

-- Allowed: the message comes back, where it was, with no push.
select pg_temp.check('an allowed edit is released',
  public.finish_message_review(pg_temp.mid('n1'), 'allow') = 'released');
select pg_temp.act_as('e');
select pg_temp.check('everyone sees the edited message again, and its history',
  (select count(*) = 1 from public.messages where id = pg_temp.mid('n1') and body = 'buy cheap pills here' and review_state is null)
  and (select count(*) = 1 from public.message_edits where message_id = pg_temp.mid('n1')));
select pg_temp.check('search has only the new text',
  (select count(*) = 1 from public.search_messages('pills')) and (select count(*) = 0 from public.search_messages('friendly')));
select pg_temp.act_as(null);
select pg_temp.check('it kept its place in the chat',
  (select m.created_at < now() - interval '1 hour' from public.messages m where m.id = pg_temp.mid('n1')));
select pg_temp.check('and nobody is pushed for an edit',
  (select not r.push_pending and r.state = 'released' from public.message_reviews r where r.message_id = pg_temp.mid('n1'))
  and (select count(*) = 0 from public.claim_released_message_pushes() p where p.message_id = pg_temp.mid('n1')));

-- Flagged in hold mode: held, then a moderator decides.
select pg_temp.edit('c', 'n1', 'now an advert for pills');
select pg_temp.check('a second edit is checked again',
  (select review_state = 'checking' from public.messages where id = pg_temp.mid('n1'))
  and (select count(*) = 2 from public.message_edits where message_id = pg_temp.mid('n1'))
  and (select count(*) = 3 from net.http_request_queue q
        where convert_from(q.body, 'UTF8')::jsonb->>'message_id' = pg_temp.mid('n1')::text
          and convert_from(q.body, 'UTF8')::jsonb->>'action' = 'guard'));
select pg_temp.check('a flagged edit is held',
  public.finish_message_review(pg_temp.mid('n1'), 'spam', 'An advert', null, 'zh advert') = 'held');
select pg_temp.act_as('e');
select pg_temp.check('a held edit hides the message from the others',
  (select count(*) = 0 from public.messages where id = pg_temp.mid('n1'))
  and (select count(*) = 0 from public.message_edits where message_id = pg_temp.mid('n1')));
select pg_temp.act_as('b');
select pg_temp.check('the moderators find it in the queue',
  (select count(*) = 1 and bool_and(q.body = 'now an advert for pills' and q.reason_zh = 'zh advert')
   from public.list_message_reviews(pg_temp.mid('circle')) q));
select pg_temp.check('approving it releases it',
  public.decide_message_review(pg_temp.mid('n1'), 'approve') = 'approved');
select pg_temp.act_as('e');
select pg_temp.check('visible again with both earlier versions',
  (select count(*) = 1 from public.messages where id = pg_temp.mid('n1') and review_state is null)
  and (select count(*) = 2 from public.message_edits where message_id = pg_temp.mid('n1')));
select pg_temp.act_as(null);
select pg_temp.check('approving an edit keeps its place and pushes nobody',
  (select m.created_at < now() - interval '1 hour' from public.messages m where m.id = pg_temp.mid('n1'))
  and (select not push_pending and state = 'approved' from public.message_reviews where message_id = pg_temp.mid('n1')));

-- A moderator removes a held edit: the message and its history go.
select pg_temp.edit('c', 'n1', 'even worse advert');
select public.finish_message_review(pg_temp.mid('n1'), 'scam', 'Worse');
select pg_temp.act_as('b');
select pg_temp.check('removing a held edit removes the message',
  public.decide_message_review(pg_temp.mid('n1'), 'remove') = 'removed');
select pg_temp.act_as(null);
select pg_temp.check('and its history goes with it',
  (select recalled_at is not null and review_state = 'removed' from public.messages where id = pg_temp.mid('n1'))
  and not exists (select 1 from public.message_edits where message_id = pg_temp.mid('n1')));

-- Flag mode: the edit is released with a flag.
select pg_temp.act_as('a');
select public.set_circle_ai_guard(pg_temp.mid('circle'), true, 'joined_days', 3, 10, 'flag');
select pg_temp.act_as(null);
insert into ids select 'n2', pg_temp.say('c', 'channel', 'plain words');
select public.finish_message_review(pg_temp.mid('n2'), 'allow');
select pg_temp.edit('c', 'n2', 'send me your password');
select pg_temp.check('in flag mode the edit is checked too',
  (select review_state = 'checking' from public.messages where id = pg_temp.mid('n2'))
  and (select mode = 'flag' from public.message_reviews where message_id = pg_temp.mid('n2')));
select pg_temp.check('and a flagged edit is released with a flag',
  public.finish_message_review(pg_temp.mid('n2'), 'scam', 'Asks for a password') = 'flagged');
select pg_temp.act_as('e');
select pg_temp.check('everyone sees it',
  (select count(*) = 1 from public.messages where id = pg_temp.mid('n2') and review_state is null));
select pg_temp.act_as('b');
select pg_temp.check('the moderators find it flagged in the queue',
  (select count(*) = 1 and bool_and(q.state = 'flagged') from public.list_message_reviews(pg_temp.mid('circle')) q));
select pg_temp.act_as(null);
select pg_temp.check('with no push for the edit',
  (select not push_pending from public.message_reviews where message_id = pg_temp.mid('n2')));
select pg_temp.act_as('a');
select public.set_circle_ai_guard(pg_temp.mid('circle'), true, 'joined_days', 3, 10, 'hold');
select pg_temp.act_as(null);

-- A check that never comes back is released by the sweep.
insert into ids select 'n3', pg_temp.say('c', 'channel', 'another harmless one');
select public.finish_message_review(pg_temp.mid('n3'), 'allow');
select pg_temp.edit('c', 'n3', 'the AI never answers this edit');
update public.message_reviews set created_at = now() - interval '2 minutes' where message_id = pg_temp.mid('n3');
select public.run_ai_guard_sweep();
select pg_temp.check('the sweep releases an edit that was never checked',
  (select review_state is null from public.messages where id = pg_temp.mid('n3'))
  and (select state = 'released' and verdict = 'not_checked' and unchecked_reason = 'timeout' and not push_pending
      from public.message_reviews where message_id = pg_temp.mid('n3')));
select pg_temp.check('with its history',
  (select count(*) = 1 from public.message_edits where message_id = pg_temp.mid('n3')));

-- ------------------------------------------------ whose edits are not checked

insert into ids select 'o1', pg_temp.say('d', 'channel', 'old member message');
select pg_temp.edit('d', 'o1', 'old member edit');
select pg_temp.check('an old member''s edit is not checked',
  (select review_state is null from public.messages where id = pg_temp.mid('o1'))
  and not exists (select 1 from public.message_reviews where message_id = pg_temp.mid('o1'))
  and (select count(*) = 1 from public.message_edits where message_id = pg_temp.mid('o1')));

insert into ids select 'a1', pg_temp.say('a', 'channel', 'owner message');
select pg_temp.edit('a', 'a1', 'owner edit');
select pg_temp.check('the owner''s edit is not checked',
  (select review_state is null from public.messages where id = pg_temp.mid('a1')));

update public.circle_members set created_at = now() where user_id = '00000000-0000-4000-8000-0000000000b1';
insert into ids select 'b1', pg_temp.say('b', 'channel', 'moderator message');
select pg_temp.edit('b', 'b1', 'moderator edit');
select pg_temp.check('a new moderator''s edit is not checked',
  (select review_state is null from public.messages where id = pg_temp.mid('b1')));

-- A moderator deleting a message deletes its history.
select pg_temp.act_as('b');
select public.recall_message(pg_temp.mid('o1'));
select pg_temp.act_as(null);
select pg_temp.check('a moderator deleting the message deletes the history',
  (select recalled_at is not null from public.messages where id = pg_temp.mid('o1'))
  and not exists (select 1 from public.message_edits where message_id = pg_temp.mid('o1')));

-- Switch the AI off for the circle, then the guard itself.
insert into ids select 'n4', pg_temp.say('c', 'channel', 'fourth harmless message');
select public.finish_message_review(pg_temp.mid('n4'), 'allow');
update public.circles set ai_enabled = false where id = pg_temp.mid('circle');
select pg_temp.edit('c', 'n4', 'edit while the circle AI is off');
select pg_temp.check('with the circle''s AI off an edit is not checked',
  (select review_state is null from public.messages where id = pg_temp.mid('n4')));
update public.circles set ai_enabled = true where id = pg_temp.mid('circle');
select pg_temp.act_as('a');
select public.set_circle_ai_guard(pg_temp.mid('circle'), false, 'joined_days', 3, 10, 'hold');
select pg_temp.act_as(null);
select pg_temp.edit('c', 'n4', 'edit while the guard is off');
select pg_temp.check('with the guard off an edit is not checked',
  (select review_state is null from public.messages where id = pg_temp.mid('n4')));

-- ------------------------------------------- the message-count rule at its edge

-- Newt's other visible messages in the circle.
select count(*) as others
from public.messages m
where m.sender_id = '00000000-0000-4000-8000-0000000000c1'
  and m.id <> (select id from ids where name = 'n4')
  and m.recalled_at is null and m.review_state is null
  and m.conversation_id = (select id from ids where name = 'channel') \gset
select pg_temp.check('Newt has some other visible messages', :others >= 3);

-- N equal to the others: not new any more. The message itself does not count.
select pg_temp.act_as('a');
select public.set_circle_ai_guard(pg_temp.mid('circle'), true, 'message_count', 3, least(:others, 200), 'hold');
select pg_temp.act_as(null);
select pg_temp.edit('c', 'n4', 'edit once N messages are behind him');
select pg_temp.check('at N other visible messages the sender is no longer new',
  (select review_state is null from public.messages where id = pg_temp.mid('n4')));
select pg_temp.act_as('a');
select public.set_circle_ai_guard(pg_temp.mid('circle'), true, 'message_count', 3, least(:others + 1, 200), 'hold');
select pg_temp.act_as(null);
select pg_temp.edit('c', 'n4', 'edit one short of N');
select pg_temp.check('one short of N the sender is still new, so the edit is checked',
  (select review_state = 'checking' from public.messages where id = pg_temp.mid('n4')));

rollback;
