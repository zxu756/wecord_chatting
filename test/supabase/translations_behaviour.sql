-- Behaviour checks for auto-translate (migrations 202610220400 and
-- 202610220410): the translation cache, who reads it, that clients cannot
-- write it, that every way a message goes away or changes clears it, and the
-- per-chat and per-user choices. Run by test/supabase/translations_test.dart
-- against the local database inside a transaction that is rolled back, so the
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
\i supabase/migrations/202610220110_message_reports.sql
\i supabase/migrations/202610220120_message_reports_admin.sql
\i supabase/migrations/202610220130_terms_acceptance.sql
\i supabase/migrations/202610220210_message_edit_history.sql
\i supabase/migrations/202610220220_edit_review.sql
\i supabase/migrations/202610220230_circle_edit_window.sql
\i supabase/migrations/202610220400_message_translations.sql
\i supabase/migrations/202610220410_translation_prefs.sql

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


-- Writes a translation the way the ai function does (service role).
create function pg_temp.put(msg text, lang text, translated text, source text default 'en')
returns void language plpgsql as $$
begin
  perform pg_temp.act_as(null);
  execute 'set local role service_role';
  insert into public.message_translations (message_id, target_lang, text, source_lang, model)
  values (pg_temp.mid(msg), lang, translated, source, 'test-model')
  on conflict (message_id, target_lang) do update set text = excluded.text;
  reset role;
end;
$$;
grant execute on function pg_temp.put(text, text, text, text) to public;

-- The translations of a message as the signed-in person reads them.
create function pg_temp.translations_as(who text, msg text)
returns table (target_lang text, text text) language plpgsql as $$
begin
  perform pg_temp.act_as(who);
  return query
    select t.target_lang, t.text from public.message_translations t
    where t.message_id = pg_temp.mid(msg) order by t.target_lang;
  perform pg_temp.act_as(null);
end;
$$;
grant execute on function pg_temp.translations_as(text, text) to public;

create function pg_temp.stored(msg text) returns bigint language sql as $$
  select count(*) from public.message_translations where message_id = pg_temp.mid(msg);
$$;
grant execute on function pg_temp.stored(text) to public;

-- ===================================================== a group, no circle

-- Ada owns the group; Eve, Olly and Zed are members; Fay is not.
insert into public.conversations (type, title) values ('group', 'Translations') returning id \gset grp_
insert into ids values ('grp', :'grp_id');
insert into public.conversation_members (conversation_id, user_id, role)
values
  (:'grp_id', '00000000-0000-4000-8000-0000000000a1', 'owner'),
  (:'grp_id', '00000000-0000-4000-8000-0000000000e1', 'member'),
  (:'grp_id', '00000000-0000-4000-8000-0000000000d1', 'member'),
  (:'grp_id', '00000000-0000-4000-8000-000000000091', 'member'),
  (:'grp_id', '00000000-0000-4000-8000-000000000081', 'member');

-- ----------------------------------------------------------- who reads and writes

insert into ids select 'm1', pg_temp.say('a', 'grp', 'hello everyone');
select pg_temp.put('m1', 'zh', '大家好');
select pg_temp.put('m1', 'ja', 'みなさん、こんにちは');
select pg_temp.check('the service role stores a translation per language',
  pg_temp.stored('m1') = 2);
select pg_temp.put('m1', 'zh', '大家好！');
select pg_temp.check('a second write for the same language replaces it',
  pg_temp.stored('m1') = 2
  and (select text = '大家好！' from public.message_translations
       where message_id = pg_temp.mid('m1') and target_lang = 'zh'));
select pg_temp.check('a member reads the translations',
  (select count(*) = 2 from pg_temp.translations_as('e', 'm1')));
select pg_temp.check('so does the author',
  (select count(*) = 2 from pg_temp.translations_as('a', 'm1')));
select pg_temp.check('someone outside the chat reads nothing',
  (select count(*) = 0 from pg_temp.translations_as('f', 'm1')));

select pg_temp.act_as('e');
select pg_temp.refused('a member cannot add a translation',
  format('insert into public.message_translations (message_id, target_lang, text, model) values (%L, ''fr'', ''x'', ''m'')', pg_temp.mid('m1')), '42501');
select pg_temp.refused('a member cannot change one',
  format('update public.message_translations set text = ''x'' where message_id = %L', pg_temp.mid('m1')), '42501');
select pg_temp.refused('a member cannot delete one',
  format('delete from public.message_translations where message_id = %L', pg_temp.mid('m1')), '42501');
select pg_temp.act_as('a');
select pg_temp.refused('neither can the author of the message',
  format('update public.message_translations set text = ''x'' where message_id = %L', pg_temp.mid('m1')), '42501');
select pg_temp.act_as(null);
set local role anon;
select pg_temp.refused('anonymous callers cannot read the cache',
  'select count(*) from public.message_translations', '42501');
reset role;
select pg_temp.check('the cache is unchanged after the refused writes',
  pg_temp.stored('m1') = 2
  and (select text = '大家好！' from public.message_translations
       where message_id = pg_temp.mid('m1') and target_lang = 'zh'));
select pg_temp.refused('a language outside the six is not stored',
  format('insert into public.message_translations (message_id, target_lang, text, model) values (%L, ''xx'', ''x'', ''m'')', pg_temp.mid('m1')), '23514');

-- ------------------------------------------------------------------------ edits

select pg_temp.edit('a', 'm1', 'hello everyone');
select pg_temp.check('saving the same text again keeps the translations',
  pg_temp.stored('m1') = 2);
select pg_temp.edit('a', 'm1', 'hello again, everyone');
select pg_temp.check('editing the text clears every translation of it',
  pg_temp.stored('m1') = 0);
select pg_temp.check('and nobody reads the old ones',
  (select count(*) = 0 from pg_temp.translations_as('e', 'm1')));
select pg_temp.put('m1', 'zh', '大家好，再说一次');
select pg_temp.check('the new text can be translated again',
  (select count(*) = 1 from pg_temp.translations_as('e', 'm1')));

-- ------------------------------------------- how the function stores (the race)

create function pg_temp.store(msg text, lang text, translated text, source_text text)
returns integer language plpgsql as $$
declare n integer;
begin
  perform pg_temp.act_as(null);
  execute 'set local role service_role';
  select public.store_message_translations(jsonb_build_array(jsonb_build_object(
    'message_id', pg_temp.mid(msg), 'target_lang', lang, 'text', translated,
    'source_lang', 'en', 'model', 'test-model', 'source_text', source_text))) into n;
  reset role;
  return n;
end;
$$;
grant execute on function pg_temp.store(text, text, text, text) to public;

select pg_temp.check('storing a translation of the text that is there works',
  pg_temp.store('m1', 'ko', '여러분 안녕', 'hello again, everyone') = 1
  and (select count(*) = 2 from pg_temp.translations_as('e', 'm1')));
select pg_temp.check('storing a translation of text that has since been edited is refused',
  pg_temp.store('m1', 'fr', 'bonjour', 'hello everyone') = 0
  and not exists (select 1 from public.message_translations
                  where message_id = pg_temp.mid('m1') and target_lang = 'fr'));
select pg_temp.act_as('e');
select pg_temp.refused('a member cannot call it',
  format('select public.store_message_translations(%L::jsonb)', '[]'), '42501');
select pg_temp.act_as(null);
set local role anon;
select pg_temp.refused('nor can anonymous callers',
  'select public.store_message_translations(''[]''::jsonb)', '42501');
reset role;

-- ---------------------------------------------------------------------- recall

insert into ids select 'm2', pg_temp.say('a', 'grp', 'recall me');
select pg_temp.put('m2', 'zh', '撤回我');
select pg_temp.put('m2', 'es', 'retiradme');
select pg_temp.act_as('a');
select public.recall_message(pg_temp.mid('m2'));
select pg_temp.act_as(null);
select pg_temp.check('recalling a message deletes its translations',
  (select recalled_at is not null from public.messages where id = pg_temp.mid('m2'))
  and pg_temp.stored('m2') = 0);

-- A person leaving or being removed does not matter for the cache, but a
-- stray row for a recalled message is still unreadable.
select pg_temp.put('m2', 'fr', 'rappelez-moi');
select pg_temp.check('a translation of a recalled message that slipped in is cleared by the next change',
  pg_temp.stored('m2') = 1);
update public.messages set body = '' where id = pg_temp.mid('m2');
select pg_temp.check('a body change on a recalled message clears it',
  pg_temp.stored('m2') = 0);

-- ------------------------------------------------------- disappearing messages

select pg_temp.act_as('a');
select public.set_disappearing_messages(pg_temp.mid('grp'), 86400);
select pg_temp.act_as(null);
insert into ids select 'm3', pg_temp.say('a', 'grp', 'this will disappear');
select pg_temp.put('m3', 'zh', '这会消失');
select pg_temp.check('a disappearing message is translated while it lasts',
  (select m.expires_at is not null from public.messages m where m.id = pg_temp.mid('m3'))
  and (select count(*) = 1 from pg_temp.translations_as('e', 'm3')));
insert into ids select 'm3b', pg_temp.say('a', 'grp', 'also disappearing');
select pg_temp.put('m3b', 'zh', '也会消失');
-- The clock reaches the expiry without any update of the translation: reads
-- already skip the message, and so its translations.
update public.messages set expires_at = now() - interval '1 minute' where id = pg_temp.mid('m3');
select pg_temp.check('moving the expiry into the past clears the translations',
  pg_temp.stored('m3') = 0);
select pg_temp.put('m3', 'zh', '这会消失');
select pg_temp.check('an expired message''s translations are unreadable for everyone before the purge',
  (select count(*) = 0 from pg_temp.translations_as('e', 'm3'))
  and (select count(*) = 0 from pg_temp.translations_as('a', 'm3'))
  and pg_temp.stored('m3') = 1);
select public.purge_expired_messages(500) as purged \gset
select pg_temp.check('the purge deletes the message',
  :purged >= 1 and not exists (select 1 from public.messages where id = pg_temp.mid('m3')));
select pg_temp.check('and takes the translations with it',
  pg_temp.stored('m3') = 0);
select pg_temp.check('a message that has not expired keeps its translation',
  pg_temp.stored('m3b') = 1
  and (select count(*) = 1 from pg_temp.translations_as('e', 'm3b')));
select pg_temp.act_as('a');
select public.set_disappearing_messages(pg_temp.mid('grp'), null);
select pg_temp.act_as(null);

-- ----------------------------------------------------------- deleting an account

insert into ids select 'm4', pg_temp.say('9', 'grp', 'zed was here');
select pg_temp.put('m4', 'zh', '泽德来过');
insert into ids select 'm5', pg_temp.say('8', 'grp', 'yan says');
select pg_temp.put('m5', 'zh', '阿燕说');
delete from public.profiles where id = '00000000-0000-4000-8000-000000000081';
select pg_temp.check('removing a profile removes its messages and their translations',
  not exists (select 1 from public.messages where id = pg_temp.mid('m5'))
  and pg_temp.stored('m5') = 0);

-- =================================================================== the circle

select pg_temp.act_as('a');
insert into ids select 'circle', public.create_circle('Translated circle', array[]::uuid[]);
select pg_temp.act_as(null);

insert into ids
select 'channel', cc.conversation_id
from public.circle_channels cc
where cc.circle_id = pg_temp.mid('circle') and cc.position = 0;

insert into public.circle_members (circle_id, user_id, role, created_at)
select pg_temp.mid('circle'), u.id, 'member', now()
from (values
  ('00000000-0000-4000-8000-0000000000b1'::uuid),
  ('00000000-0000-4000-8000-0000000000c1'::uuid),
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

-- ------------------------------------------------------------ moderator delete

insert into ids select 'c1', pg_temp.say('c', 'channel', 'a post a moderator will remove');
select pg_temp.put('c1', 'zh', '版主会删除的帖子');
select pg_temp.check('a circle message is translated for its members',
  (select count(*) = 1 from pg_temp.translations_as('e', 'c1')));
select pg_temp.act_as('b');
select public.recall_message(pg_temp.mid('c1'));
select pg_temp.act_as(null);
select pg_temp.check('a moderator deleting the message clears its translations',
  (select recalled_at is not null from public.messages where id = pg_temp.mid('c1'))
  and pg_temp.stored('c1') = 0);

-- ------------------------------------------------------------- the AI guard

insert into ids select 'c2', pg_temp.say('c', 'channel', 'a post the guard will hold');
select pg_temp.put('c2', 'zh', '守护会扣下的帖子');
update public.messages set review_state = 'held' where id = pg_temp.mid('c2');
select pg_temp.check('a message the guard holds loses its translations',
  pg_temp.stored('c2') = 0);
-- A row that slipped in for a held message is hidden like the message.
select pg_temp.put('c2', 'zh', '守护会扣下的帖子');
select pg_temp.check('other members cannot read a held message''s translation',
  (select count(*) = 0 from pg_temp.translations_as('e', 'c2')));
select pg_temp.check('its author and a moderator still see their own',
  (select count(*) = 1 from pg_temp.translations_as('c', 'c2'))
  and (select count(*) = 1 from pg_temp.translations_as('b', 'c2')));
update public.messages set review_state = 'removed' where id = pg_temp.mid('c2');
select pg_temp.check('a message the moderators remove loses them',
  pg_temp.stored('c2') = 0);

select pg_temp.check('a translation for a message the moderators removed is refused',
  pg_temp.store('c2', 'ja', 'x', 'a post the guard will hold') = 0);
select pg_temp.check('and so is one for a recalled message',
  pg_temp.store('c1', 'ja', 'x', 'a post a moderator will remove') = 0
  and pg_temp.store('m2', 'ja', 'x', 'recall me') = 0);
select pg_temp.check('a message that has not expired takes one',
  pg_temp.store('m3b', 'ja', 'x', 'also disappearing') = 1);
update public.messages set expires_at = now() - interval '1 minute' where id = pg_temp.mid('m3b');
select pg_temp.check('once it has expired, no more are taken',
  pg_temp.store('m3b', 'ko', 'x', 'also disappearing') = 0);

-- A message waiting for the check is hidden, translation and all.
insert into ids select 'c3', pg_temp.say('c', 'channel', 'checking');
update public.messages set review_state = 'checking' where id = pg_temp.mid('c3');
select pg_temp.put('c3', 'zh', '检查中');
select pg_temp.check('a message waiting for the check cannot be read by the others',
  (select count(*) = 0 from pg_temp.translations_as('e', 'c3')));
update public.messages set review_state = null where id = pg_temp.mid('c3');
select pg_temp.check('once released it is readable for everyone again',
  (select count(*) = 1 from pg_temp.translations_as('e', 'c3')));

-- ================================================================= the choices

-- ------------------------------------------------------ conversation choices

select pg_temp.act_as('e');
insert into public.conversation_translation_prefs (user_id, conversation_id, auto, target_lang)
values ('00000000-0000-4000-8000-0000000000e1', pg_temp.mid('grp'), true, 'ja');
select pg_temp.check('a member turns auto-translate on for a chat they are in',
  (select auto and target_lang = 'ja' from public.conversation_translation_prefs
   where conversation_id = pg_temp.mid('grp')));
update public.conversation_translation_prefs set auto = false, target_lang = null
where conversation_id = pg_temp.mid('grp');
select pg_temp.check('and changes it',
  (select not auto and target_lang is null from public.conversation_translation_prefs
   where conversation_id = pg_temp.mid('grp')));
select pg_temp.refused('a language outside the six is refused',
  format('update public.conversation_translation_prefs set target_lang = ''de'' where conversation_id = %L', pg_temp.mid('grp')), '23514');
select pg_temp.refused('a choice cannot be made for someone else',
  format('insert into public.conversation_translation_prefs (user_id, conversation_id, auto) values (%L, %L, true)',
    '00000000-0000-4000-8000-0000000000d1', pg_temp.mid('grp')), '42501');
select pg_temp.act_as('f');
select pg_temp.refused('an outsider cannot make a choice for the group',
  format('insert into public.conversation_translation_prefs (user_id, conversation_id, auto) values (%L, %L, true)',
    '00000000-0000-4000-8000-0000000000f1', pg_temp.mid('grp')), '42501');
select pg_temp.act_as('a');
insert into public.conversation_translation_prefs (user_id, conversation_id, auto)
values ('00000000-0000-4000-8000-0000000000a1', pg_temp.mid('grp'), true);
select pg_temp.check('Ada sees only her own choice',
  (select count(*) = 1 and bool_and(user_id = '00000000-0000-4000-8000-0000000000a1')
   from public.conversation_translation_prefs));
update public.conversation_translation_prefs set auto = false
where user_id = '00000000-0000-4000-8000-0000000000e1';
select pg_temp.act_as('e');
select pg_temp.check('and cannot change Eve''s',
  (select count(*) = 1 and bool_and(not auto) from public.conversation_translation_prefs));
delete from public.conversation_translation_prefs
where user_id = '00000000-0000-4000-8000-0000000000a1';
select pg_temp.check('or delete Ada''s',
  (select count(*) = 1 from public.conversation_translation_prefs where user_id = '00000000-0000-4000-8000-0000000000e1'));
select pg_temp.act_as(null);
select pg_temp.check('Ada''s choice is still there',
  (select count(*) = 1 from public.conversation_translation_prefs
   where user_id = '00000000-0000-4000-8000-0000000000a1' and auto));
set local role anon;
select pg_temp.refused('anonymous callers cannot read choices',
  'select count(*) from public.conversation_translation_prefs', '42501');
reset role;

select pg_temp.act_as('d');
insert into public.conversation_translation_prefs (user_id, conversation_id, auto)
values ('00000000-0000-4000-8000-0000000000d1', pg_temp.mid('grp'), true);
select public.leave_group_conversation(pg_temp.mid('grp'));
select pg_temp.act_as(null);
select pg_temp.check('leaving a chat takes the choice for it along',
  not exists (select 1 from public.conversation_translation_prefs
              where user_id = '00000000-0000-4000-8000-0000000000d1'));

-- ---------------------------------------------------------------- user defaults

select pg_temp.act_as('e');
insert into public.user_ai_settings (user_id, translate_target, no_translate_langs)
values ('00000000-0000-4000-8000-0000000000e1', 'ko', array['zh', 'en', 'zh']);
select pg_temp.check('a person keeps a target language and a list of languages not to translate, tidied',
  (select translate_target = 'ko' and no_translate_langs = array['en', 'zh']
   from public.user_ai_settings));
update public.user_ai_settings set translate_target = null, no_translate_langs = '{}';
select pg_temp.check('they can follow the app''s language again and clear the list',
  (select translate_target is null and no_translate_langs = '{}' from public.user_ai_settings));
select pg_temp.refused('an unknown language is refused',
  'update public.user_ai_settings set translate_target = ''de''', '23514');
select pg_temp.refused('so is an unknown language in the list',
  'update public.user_ai_settings set no_translate_langs = array[''en'', ''de'']', '23514');
select pg_temp.refused('a row cannot be made for someone else',
  format('insert into public.user_ai_settings (user_id) values (%L)', '00000000-0000-4000-8000-0000000000a1'), '42501');
select pg_temp.act_as('a');
select pg_temp.check('nobody else reads it',
  (select count(*) = 0 from public.user_ai_settings));
select pg_temp.refused('and nobody else can delete it (there is no delete)',
  'delete from public.user_ai_settings', '42501');
select pg_temp.act_as(null);
set local role anon;
select pg_temp.refused('anonymous callers cannot read it',
  'select count(*) from public.user_ai_settings', '42501');
reset role;

rollback;
