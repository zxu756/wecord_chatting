-- Behaviour checks for personal stickers (A11: migrations 202610220500 and
-- 202610220510). Run by test/supabase/user_stickers_test.dart against the
-- local database: it applies every migration after the local baseline
-- (202610170001) inside a transaction, acts as several people through
-- row-level security, and rolls back, so the database is left as it was.
-- Run from the repository root.
--
-- What it walks through: the owner-only table (RLS) and the 300 cap, the
-- private bucket (nobody else can list, read, write or delete the library's
-- files), and sending: the copy must live in the conversation's folder, the
-- sticker must be the sender's own, and the recipients read the copy, never
-- the original. In a direct chat, a group and a circle channel.
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

\i supabase/migrations/202610220500_user_stickers.sql
\i supabase/migrations/202610220510_send_personal_sticker.sql

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

-- Ada owns the library. Bob is her friend and in her group and her circle.
-- Eve is in the group only. Fay is nowhere.
insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@stickers.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@stickers.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve@stickers.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000f1', 'fay@stickers.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_stk', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_stk', 'Bob'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve_stk', 'Eve'),
  ('00000000-0000-4000-8000-0000000000f1', 'fay_stk', 'Fay');
insert into public.friendships (user_low_id, user_high_id)
values ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000b1');

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

create function pg_temp.mid(name text) returns uuid language sql stable as $$
  select id from ids where ids.name = mid.name;
$$;
grant execute on function pg_temp.mid(text) to public;

create function pg_temp.affected(stmt text) returns bigint language plpgsql as $$
declare n bigint;
begin
  execute stmt;
  get diagnostics n = row_count;
  return n;
end;
$$;
grant execute on function pg_temp.affected(text) to public;

-- Ada's folder in the sticker bucket.
create function pg_temp.lib_path(who text, n integer, ext text default 'png') returns text language sql immutable as $$
  select format('00000000-0000-4000-8000-0000000000%s1/%s.%s', who,
    '00000000-0000-4000-8000-' || lpad(n::text, 12, '0'), ext);
$$;
grant execute on function pg_temp.lib_path(text, integer, text) to public;

-- Uploads a file into the sticker bucket as one of the people, the way the
-- storage API does (row level security applies).
create function pg_temp.upload(who text, object_path text, bytes bigint default 2048) returns void language plpgsql as $$
begin
  perform pg_temp.act_as(who);
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values ('user-stickers', object_path,
    format('00000000-0000-4000-8000-0000000000%s1', who)::uuid,
    format('00000000-0000-4000-8000-0000000000%s1', who),
    jsonb_build_object('size', bytes, 'mimetype', 'image/png'));
  perform pg_temp.act_as(null);
end;
$$;
grant execute on function pg_temp.upload(text, text, bigint) to public;

-- ------------------------------------------------------------ the bucket

select pg_temp.check('the bucket is private, 1 MB, images only',
  (select not public and file_size_limit = 1048576
          and allowed_mime_types @> array['image/png', 'image/gif', 'image/webp']
          and cardinality(allowed_mime_types) = 3
   from storage.buckets where id = 'user-stickers'));

-- ---------------------------------------------------------- conversations

select pg_temp.act_as('a');
insert into ids select 'dm', public.get_or_create_direct_conversation('00000000-0000-4000-8000-0000000000b1');
select pg_temp.act_as(null);

insert into public.conversations (type, title) values ('group', 'Sticker group') returning id \gset grp_
insert into ids values ('grp', :'grp_id');
insert into public.conversation_members (conversation_id, user_id, role)
values
  (:'grp_id', '00000000-0000-4000-8000-0000000000a1', 'owner'),
  (:'grp_id', '00000000-0000-4000-8000-0000000000b1', 'member'),
  (:'grp_id', '00000000-0000-4000-8000-0000000000e1', 'member');

select pg_temp.act_as('a');
insert into ids select 'circle', public.create_circle('Sticker circle', array[]::uuid[]);
select pg_temp.act_as(null);
insert into ids
select 'channel', cc.conversation_id
from public.circle_channels cc
where cc.circle_id = pg_temp.mid('circle') and cc.position = 0;
insert into public.circle_members (circle_id, user_id, role)
values (pg_temp.mid('circle'), '00000000-0000-4000-8000-0000000000b1', 'member');
insert into public.conversation_members (conversation_id, user_id, role)
select pg_temp.mid('channel'), cm.user_id, cm.role
from public.circle_members cm where cm.circle_id = pg_temp.mid('circle')
on conflict do nothing;

-- ------------------------------------------------------ the library table

-- A row needs its file.
select pg_temp.act_as('a');
select pg_temp.refused('a row for a file that was never uploaded is refused',
  format('insert into public.user_stickers (owner_id, path, width, height) values (%L, %L, 256, 256)',
    '00000000-0000-4000-8000-0000000000a1', pg_temp.lib_path('a', 1)), '22023');
select pg_temp.act_as(null);

select pg_temp.upload('a', pg_temp.lib_path('a', 1));
select pg_temp.upload('a', pg_temp.lib_path('a', 2, 'gif'), 900000);
select pg_temp.upload('a', pg_temp.lib_path('a', 3, 'webp'), 1000000);
select pg_temp.upload('b', pg_temp.lib_path('b', 1));

select pg_temp.act_as('a');
insert into public.user_stickers (owner_id, path, width, height)
values ('00000000-0000-4000-8000-0000000000a1', pg_temp.lib_path('a', 1), 256, 256);
select pg_temp.act_as(null);
select pg_temp.act_as('a');
insert into public.user_stickers (owner_id, path, width, height, animated)
values ('00000000-0000-4000-8000-0000000000a1', pg_temp.lib_path('a', 2, 'gif'), 200, 200, true);
select pg_temp.act_as(null);
select pg_temp.check('the owner adds stickers; the newest sits first',
  (select count(*) = 2 and (array_agg(path order by sort_key))[1] = pg_temp.lib_path('a', 2, 'gif')
   from public.user_stickers where owner_id = '00000000-0000-4000-8000-0000000000a1'));
insert into ids select 'ada_png', id from public.user_stickers where path = pg_temp.lib_path('a', 1);
insert into ids select 'ada_gif', id from public.user_stickers where path = pg_temp.lib_path('a', 2, 'gif');

select pg_temp.act_as('a');
select pg_temp.refused('a row cannot name a file in somebody else''s folder',
  format('insert into public.user_stickers (owner_id, path, width, height) values (%L, %L, 256, 256)',
    '00000000-0000-4000-8000-0000000000a1', pg_temp.lib_path('b', 1)), '42501');
select pg_temp.refused('a row cannot be made for somebody else',
  format('insert into public.user_stickers (owner_id, path, width, height) values (%L, %L, 256, 256)',
    '00000000-0000-4000-8000-0000000000b1', pg_temp.lib_path('b', 1)), '42501');
select pg_temp.act_as(null);
-- (Written as the server would; a person cannot put such a file there.)
insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
values ('user-stickers', '00000000-0000-4000-8000-0000000000a1/evil.exe', '00000000-0000-4000-8000-0000000000a1',
  '00000000-0000-4000-8000-0000000000a1', '{"size": 10}');
select pg_temp.act_as('a');
select pg_temp.refused('a path must look like <owner>/<uuid>.<png|gif|webp>',
  format('insert into public.user_stickers (owner_id, path, width, height) values (%L, %L, 256, 256)',
    '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a1/evil.exe'), '23514');
select pg_temp.refused('a still format cannot be marked as animated',
  format('insert into public.user_stickers (owner_id, path, width, height, animated) values (%L, %L, 256, 256, true)',
    '00000000-0000-4000-8000-0000000000a1', pg_temp.lib_path('a', 1)), '23514');
select pg_temp.act_as(null);

-- Only the order may be changed by hand.
select pg_temp.act_as('a');
select pg_temp.refused('the path of a row cannot be changed',
  format('update public.user_stickers set path = %L where id = %L', pg_temp.lib_path('b', 1), pg_temp.mid('ada_png')), '42501');
select pg_temp.refused('nor its owner',
  format('update public.user_stickers set owner_id = %L where id = %L', '00000000-0000-4000-8000-0000000000b1', pg_temp.mid('ada_png')), '42501');
select pg_temp.act_as(null);

-- Owner only.
select pg_temp.act_as('b');
select pg_temp.check('another person sees none of the library',
  (select count(*) = 0 from public.user_stickers));
select pg_temp.check('and cannot delete from it',
  pg_temp.affected(format('delete from public.user_stickers where id = %L', pg_temp.mid('ada_png'))) = 0);
select pg_temp.check('or change its order',
  pg_temp.affected(format('update public.user_stickers set sort_key = 1 where id = %L', pg_temp.mid('ada_png'))) = 0);
select pg_temp.act_as(null);
select pg_temp.check('the row is still there',
  exists (select 1 from public.user_stickers where id = pg_temp.mid('ada_png')));
set local role anon;
select pg_temp.refused('anonymous callers read nothing', 'select count(*) from public.user_stickers', '42501');
reset role;
select pg_temp.refused('anonymous callers cannot reorder', 'select public.reorder_user_stickers(array[]::uuid[])', '42501');

-- ------------------------------------------------------ the private bucket

select pg_temp.act_as('a');
select pg_temp.check('the owner lists their own files',
  (select count(*) = 4 from storage.objects where bucket_id = 'user-stickers'));
select pg_temp.act_as('b');
select pg_temp.check('Bob lists only his own folder: nothing of Ada''s',
  (select count(*) = 1 and bool_and(name like '00000000-0000-4000-8000-0000000000b1/%')
   from storage.objects where bucket_id = 'user-stickers'));
select pg_temp.check('Bob cannot read Ada''s file by its name',
  (select count(*) = 0 from storage.objects where bucket_id = 'user-stickers' and name = pg_temp.lib_path('a', 1)));
select pg_temp.act_as('f');
select pg_temp.check('somebody in none of her chats reads nothing either',
  (select count(*) = 0 from storage.objects where bucket_id = 'user-stickers'));
select pg_temp.act_as('b');
select pg_temp.refused('Bob cannot write into Ada''s folder',
  format('insert into storage.objects (bucket_id, name, owner, owner_id, metadata) values (''user-stickers'', %L, %L, %L, ''{"size": 10}'')',
    pg_temp.lib_path('a', 9), '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b1'), '42501');
select pg_temp.refused('nor under a made-up name in his own folder',
  format('insert into storage.objects (bucket_id, name, owner, owner_id, metadata) values (''user-stickers'', %L, %L, %L, ''{"size": 10}'')',
    '00000000-0000-4000-8000-0000000000b1/notes.txt', '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b1'), '42501');
-- (Deleting objects is only possible through the Storage API, which applies the
-- delete policy checked further down.)
select pg_temp.check('Bob cannot rename it into his folder',
  pg_temp.affected(format('update storage.objects set name = ''00000000-0000-4000-8000-0000000000b1/stolen.png'' where bucket_id = ''user-stickers'' and name = %L', pg_temp.lib_path('a', 1))) = 0);
select pg_temp.act_as(null);
select pg_temp.check('Ada''s files are all still there',
  (select count(*) = 4 from storage.objects where bucket_id = 'user-stickers' and name like '00000000-0000-4000-8000-0000000000a1/%'));
set local role anon;
select pg_temp.check('anonymous callers read none of the bucket',
  (select count(*) = 0 from storage.objects where bucket_id = 'user-stickers'));
reset role;

-- A sticker was sent to Bob, Eve and the others: still not readable by them,
-- see the sending part below.

-- The animated ceiling.
select pg_temp.upload('a', pg_temp.lib_path('a', 4, 'gif'), 2000000);
select pg_temp.act_as('a');
select pg_temp.refused('an animated sticker over 1 MB is refused',
  format('insert into public.user_stickers (owner_id, path, width, height, animated) values (%L, %L, 256, 256, true)',
    '00000000-0000-4000-8000-0000000000a1', pg_temp.lib_path('a', 4, 'gif')), '22023');
select pg_temp.act_as(null);

-- ------------------------------------------------------------- reordering

select pg_temp.act_as('a');
insert into public.user_stickers (owner_id, path, width, height, animated)
values ('00000000-0000-4000-8000-0000000000a1', pg_temp.lib_path('a', 3, 'webp'), 128, 128, true);
insert into ids select 'ada_webp', id from public.user_stickers where path = pg_temp.lib_path('a', 3, 'webp');
select pg_temp.check('the newest is first',
  (select (array_agg(id order by sort_key))[1] = pg_temp.mid('ada_webp') from public.user_stickers));
select public.reorder_user_stickers(array[pg_temp.mid('ada_png'), pg_temp.mid('ada_webp'), pg_temp.mid('ada_gif')]);
select pg_temp.check('the list follows the order given',
  (select array_agg(id order by sort_key) = array[pg_temp.mid('ada_png'), pg_temp.mid('ada_webp'), pg_temp.mid('ada_gif')]
   from public.user_stickers));
select public.reorder_user_stickers(array[pg_temp.mid('ada_gif')]);
select pg_temp.check('one left out keeps its place after the listed ones',
  (select array_agg(id order by sort_key) = array[pg_temp.mid('ada_gif'), pg_temp.mid('ada_png'), pg_temp.mid('ada_webp')]
   from public.user_stickers));
select public.reorder_user_stickers(array[pg_temp.mid('ada_webp'), pg_temp.mid('ada_png'), pg_temp.mid('ada_gif')]);
select pg_temp.act_as('b');
select public.reorder_user_stickers(array[pg_temp.mid('ada_gif')]);
select pg_temp.act_as(null);
select pg_temp.check('another person''s reorder leaves the list alone',
  (select array_agg(id order by sort_key) = array[pg_temp.mid('ada_webp'), pg_temp.mid('ada_png'), pg_temp.mid('ada_gif')]
   from public.user_stickers where owner_id = '00000000-0000-4000-8000-0000000000a1'));

-- ----------------------------------------------------- sending: the copy

-- The app copies the library file into the conversation's folder in
-- chat-images (the storage API does this as the sender) and then sends.
create function pg_temp.copy_into_chat(who text, chat text, file_name text, bytes bigint default 2048) returns text language plpgsql as $$
declare
  object_path text := pg_temp.mid(chat)::text || '/' || file_name;
begin
  perform pg_temp.act_as(who);
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values ('chat-images', object_path,
    format('00000000-0000-4000-8000-0000000000%s1', who)::uuid,
    format('00000000-0000-4000-8000-0000000000%s1', who),
    jsonb_build_object('size', bytes, 'mimetype', 'image/png'));
  perform pg_temp.act_as(null);
  return object_path;
end;
$$;
grant execute on function pg_temp.copy_into_chat(text, text, text, bigint) to public;

-- A direct chat, a group and a circle channel each take a copy.
select pg_temp.copy_into_chat('a', 'dm', 'sticker-1.png') as dm_copy \gset
select pg_temp.copy_into_chat('a', 'grp', 'sticker-2.png') as grp_copy \gset
select pg_temp.copy_into_chat('a', 'channel', 'sticker-3.png') as channel_copy \gset

select pg_temp.act_as('a');
insert into ids select 'm_dm', public.send_personal_sticker(pg_temp.mid('dm'), pg_temp.mid('ada_png'), :'dm_copy');
insert into ids select 'm_grp', public.send_personal_sticker(pg_temp.mid('grp'), pg_temp.mid('ada_png'), :'grp_copy');
insert into ids select 'm_channel', public.send_personal_sticker(pg_temp.mid('channel'), pg_temp.mid('ada_png'), :'channel_copy');
select pg_temp.act_as(null);

select pg_temp.check('a personal sticker goes into a direct chat, a group and a channel',
  (select count(*) = 3 and bool_and(type = 'sticker' and sender_id = '00000000-0000-4000-8000-0000000000a1')
   from public.messages where id in (pg_temp.mid('m_dm'), pg_temp.mid('m_grp'), pg_temp.mid('m_channel'))));
select pg_temp.check('the message names the copy in chat-images, never the library',
  (select attachment->>'bucket' = 'chat-images' and attachment->>'path' = :'grp_copy'
          and (attachment->>'personal')::boolean and attachment->>'kind' = 'sticker'
          and attachment->>'mime_type' = 'image/png'
          and (attachment->>'width')::int = 256 and (attachment->>'animated')::boolean = false
          and attachment::text not like '%user-stickers%' and attachment::text not like '%0000000000a1/%'
   from public.messages where id = pg_temp.mid('m_grp')));

-- The recipients read the copy and not the original.
select pg_temp.act_as('b');
select pg_temp.check('Bob reads the copy in the direct chat',
  (select count(*) = 1 from storage.objects where bucket_id = 'chat-images' and name = :'dm_copy'));
select pg_temp.check('and the one in the group and the channel',
  (select count(*) = 2 from storage.objects where bucket_id = 'chat-images' and name in (:'grp_copy', :'channel_copy')));
select pg_temp.check('but not one original of Ada''s library',
  (select count(*) = 0 from storage.objects where bucket_id = 'user-stickers' and name like '00000000-0000-4000-8000-0000000000a1/%'));
select pg_temp.check('he sees the sticker message',
  (select count(*) = 3 from public.messages where id in (pg_temp.mid('m_dm'), pg_temp.mid('m_grp'), pg_temp.mid('m_channel'))));
select pg_temp.act_as('e');
select pg_temp.check('Eve reads the group copy only',
  (select count(*) = 1 from storage.objects where bucket_id = 'chat-images' and name in (:'dm_copy', :'grp_copy', :'channel_copy')));
select pg_temp.act_as('f');
select pg_temp.check('Fay reads none of it',
  (select count(*) = 0 from storage.objects where bucket_id in ('chat-images', 'user-stickers')
     and name in (:'dm_copy', :'grp_copy', :'channel_copy', pg_temp.lib_path('a', 1))));
select pg_temp.act_as(null);

-- ------------------------------------------------- sending: what is refused

select pg_temp.copy_into_chat('a', 'grp', 'sticker-4.png') as grp_copy_2 \gset
select pg_temp.copy_into_chat('b', 'grp', 'sticker-5.png') as bob_copy \gset

select pg_temp.act_as('b');
select pg_temp.refused('Bob cannot send Ada''s sticker',
  format('select public.send_personal_sticker(%L, %L, %L)', pg_temp.mid('grp'), pg_temp.mid('ada_png'), :'bob_copy'), '42501');
select pg_temp.act_as('f');
select pg_temp.refused('nobody outside the chat can send into it',
  format('select public.send_personal_sticker(%L, %L, %L)', pg_temp.mid('grp'), pg_temp.mid('ada_png'), :'grp_copy_2'), '42501');
select pg_temp.act_as(null);

select pg_temp.act_as('a');
select pg_temp.refused('the copy must be in this conversation''s folder',
  format('select public.send_personal_sticker(%L, %L, %L)', pg_temp.mid('grp'), pg_temp.mid('ada_png'), :'dm_copy'), '42501');
select pg_temp.refused('not the library file',
  format('select public.send_personal_sticker(%L, %L, %L)', pg_temp.mid('grp'), pg_temp.mid('ada_png'), pg_temp.lib_path('a', 1)), '42501');
select pg_temp.refused('not a path in a subfolder',
  format('select public.send_personal_sticker(%L, %L, %L)', pg_temp.mid('grp'), pg_temp.mid('ada_png'), pg_temp.mid('grp')::text || '/x/y.png'), '42501');
select pg_temp.refused('not a file type that is not an image',
  format('select public.send_personal_sticker(%L, %L, %L)', pg_temp.mid('grp'), pg_temp.mid('ada_png'), pg_temp.mid('grp')::text || '/sticker-4.exe'), '42501');
select pg_temp.refused('a copy that was never made',
  format('select public.send_personal_sticker(%L, %L, %L)', pg_temp.mid('grp'), pg_temp.mid('ada_png'), pg_temp.mid('grp')::text || '/sticker-nope.png'), '22023');
select pg_temp.refused('a file somebody else put in the chat is not hers to send',
  format('select public.send_personal_sticker(%L, %L, %L)', pg_temp.mid('grp'), pg_temp.mid('ada_png'), :'bob_copy'), '42501');
select pg_temp.refused('a sticker that is not in the library',
  format('select public.send_personal_sticker(%L, %L, %L)', pg_temp.mid('grp'), gen_random_uuid(), :'grp_copy_2'), '42501');
select pg_temp.act_as(null);
select pg_temp.refused('nobody signed in cannot send',
  format('select public.send_personal_sticker(%L, %L, %L)', pg_temp.mid('grp'), pg_temp.mid('ada_png'), :'grp_copy_2'), '42501');
set local role anon;
select pg_temp.refused('anonymous callers cannot call it',
  format('select public.send_personal_sticker(%L, %L, %L)', pg_temp.mid('grp'), pg_temp.mid('ada_png'), :'grp_copy_2'), '42501');
reset role;

-- A client cannot write sticker messages itself, with or without a path.
select pg_temp.act_as('a');
select pg_temp.refused('a sticker message cannot be inserted directly',
  format('insert into public.messages (conversation_id, sender_id, type, body, attachment) values (%L, %L, ''sticker'', '''', %L)',
    pg_temp.mid('grp'), '00000000-0000-4000-8000-0000000000a1',
    jsonb_build_object('kind', 'sticker', 'personal', true, 'bucket', 'chat-images', 'path', :'grp_copy_2')::text), '42501');
select pg_temp.act_as(null);
select pg_temp.check('the refused sends left no stray messages',
  (select count(*) = 3 from public.messages where type = 'sticker'));

-- Sending twice reuses nothing: each message has its own copy, and recalling
-- one erases only its own.
select pg_temp.act_as('a');
insert into ids select 'm_grp_2', public.send_personal_sticker(pg_temp.mid('grp'), pg_temp.mid('ada_png'), :'grp_copy_2');
select pg_temp.act_as(null);
select pg_temp.check('the same sticker can be sent again with a new copy',
  (select count(*) = 2 from public.messages where conversation_id = pg_temp.mid('grp') and type = 'sticker'));

-- The path rule of 202610190010 still stands for any other attachment.
select pg_temp.act_as('a');
select pg_temp.refused('an image attachment naming a file of a chat Ada is not in is still refused',
  format('insert into public.messages (conversation_id, sender_id, type, body, attachment) values (%L, %L, ''image'', '''', %L)',
    pg_temp.mid('grp'), '00000000-0000-4000-8000-0000000000a1',
    jsonb_build_object('kind', 'image', 'bucket', 'chat-images', 'path', gen_random_uuid()::text || '/x.png', 'mime_type', 'image/png', 'size', 5)::text), '42501');
select pg_temp.act_as(null);

-- ----------------------------------------------------------------- deleting

select pg_temp.act_as('a');
select pg_temp.check('the owner deletes a row',
  pg_temp.affected(format('delete from public.user_stickers where id = %L', pg_temp.mid('ada_gif'))) = 1);
select pg_temp.act_as(null);
-- (Storage refuses SQL deletes of objects; the app removes the file through
-- the Storage API, which the owner's delete policy allows and nobody else's.)
select pg_temp.check('only the owner has a delete policy on the bucket',
  (select count(*) = 1 from pg_policies
   where schemaname = 'storage' and tablename = 'objects' and cmd = 'DELETE'
     and policyname = 'user_stickers_storage_delete_owner'
     and qual like '%user-stickers%' and qual like '%auth.uid()%'));
select pg_temp.act_as(null);
select pg_temp.check('a sticker already sent keeps working after the original is deleted',
  (select count(*) = 1 from storage.objects where bucket_id = 'chat-images' and name = :'grp_copy'));

-- ------------------------------------------------------------- the 300 cap

-- Ada has two left (png, webp). 298 more make 300.
insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
select 'user-stickers', pg_temp.lib_path('a', 1000 + n), '00000000-0000-4000-8000-0000000000a1'::uuid,
  '00000000-0000-4000-8000-0000000000a1', '{"size": 100}'::jsonb
from generate_series(1, 299) n;
select pg_temp.act_as('a');
insert into public.user_stickers (owner_id, path, width, height)
select '00000000-0000-4000-8000-0000000000a1', pg_temp.lib_path('a', 1000 + n), 64, 64
from generate_series(1, 298) n;
select pg_temp.check('300 stickers fit',
  (select count(*) = 300 from public.user_stickers));
select pg_temp.refused('the 301st is refused',
  format('insert into public.user_stickers (owner_id, path, width, height) values (%L, %L, 64, 64)',
    '00000000-0000-4000-8000-0000000000a1', pg_temp.lib_path('a', 1299)), '54000');
select pg_temp.check('still 300',
  (select count(*) = 300 from public.user_stickers));
select pg_temp.check('after a delete there is room again',
  pg_temp.affected(format('delete from public.user_stickers where path = %L', pg_temp.lib_path('a', 1001))) = 1);
insert into public.user_stickers (owner_id, path, width, height)
values ('00000000-0000-4000-8000-0000000000a1', pg_temp.lib_path('a', 1299), 64, 64);
select pg_temp.act_as('b');
insert into public.user_stickers (owner_id, path, width, height)
values ('00000000-0000-4000-8000-0000000000b1', pg_temp.lib_path('b', 1), 64, 64);
select pg_temp.check('the cap is per person: Bob still adds his own',
  (select count(*) = 1 from public.user_stickers));
select pg_temp.act_as(null);

rollback;
