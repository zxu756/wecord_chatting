-- Behaviour checks for public circle web pages (C8: migrations 202610260500
-- and 202610260510). Run by test/supabase/public_circle_test.dart against the
-- local database: it applies the migrations in a transaction, plays people
-- (and the anon role the web page uses) through the functions, and rolls
-- everything back. Run from the repository root.
--
-- What it walks through: who may set a circle's short name and what a valid
-- one is (format, reserved words, taken names, the hourly allowance, the
-- audit entry); opening /c/<slug> in the app; the public card for a slug and
-- for an invite as anon, which shows only public fields, hides the member
-- count below 5 and rounds it to a level above that, and answers exactly the
-- same "unavailable" for a private circle, a delisted or suspended one, a
-- revoked, expired, used-up or paused invite, a missing code and any odd
-- input; and what anon cannot touch.
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
\i supabase/migrations/202610250100_task_lists2_schema.sql
\i supabase/migrations/202610250110_task_lists2_rpcs.sql
\i supabase/migrations/202610250120_task_lists2_triggers.sql
\i supabase/migrations/202610250130_task_lists2_export.sql
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
\i supabase/migrations/202610250400_saved_items_schema.sql
\i supabase/migrations/202610250410_saved_items_rpcs.sql
\i supabase/migrations/202610250420_saved_notes_bucket.sql
\i supabase/migrations/202610250430_export_my_saved_items.sql
\i supabase/migrations/202610250510_merged_forward_alt_text.sql
\i supabase/migrations/202610260500_circle_slug.sql
\i supabase/migrations/202610260510_public_circle_card.sql
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

-- Becomes [user_id] (null: nobody signed in, the anon role the web page uses).
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

create function pg_temp.root() returns void language plpgsql as $$
begin
  execute 'reset role';
end $$;

-- The SQLSTATE a statement raises, or 'ok'.
create function pg_temp.state(statement text) returns text language plpgsql as $$
begin
  execute statement;
  return 'ok';
exception when others then
  return sqlstate;
end $$;

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create function pg_temp.i(n text) returns uuid language sql as $$ select id from pg_temp.ids where name = n $$;

-- Shorthands for what the web page asks.
create function pg_temp.card(s text) returns jsonb language sql as $$
  select public.get_public_circle_card(s)
$$;
create function pg_temp.icard(s text) returns jsonb language sql as $$
  select public.get_public_invite_card(s)
$$;
create function pg_temp.fill(c uuid, extra integer) returns void language plpgsql as $$
begin
  -- Extra members, made as the table owner so the cast stays small.
  with u as (
    insert into auth.users (id, email, instance_id, aud, role)
    select gen_random_uuid(), 'pcx_' || gen_random_uuid() || '@pc.test',
      '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
    from generate_series(1, extra)
    returning id
  ), p as (
    insert into public.profiles (id, username, display_name)
    select id, 'pcx_' || substr(replace(id::text, '-', ''), 1, 12), 'Filler' from u
    returning id
  )
  insert into public.circle_members (circle_id, user_id, role)
  select c, id, 'member' from p;
end $$;
grant execute on all functions in schema pg_temp to public;

-- ------------------------------------------------------------------ cast
-- Ada owns the circles. Bob is an ordinary member of the first. Cy is an
-- outsider with an account.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '@pc.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from (values ('a1','ada'),('a3','bob'),('c1','cy')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '_pc', initcap(name)
from (values ('a1','ada'),('a3','bob'),('c1','cy')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || n)::uuid
from (values ('a1','ada'),('a3','bob'),('c1','cy')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(pg_temp.i('ada'), pg_temp.i('bob')), greatest(pg_temp.i('ada'), pg_temp.i('bob'));

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'pub', public.create_circle('Pixel Club', array[pg_temp.i('bob')]);
select public.set_circle_discovery(pg_temp.i('pub'), true, 'Pixel art, palettes and weekly challenges.', 'art', 'en', array['pixel art', 'palettes']);
insert into pg_temp.ids select 'priv', public.create_circle('Secret Club', array[pg_temp.i('bob')]);
insert into pg_temp.ids select 'down', public.create_circle('Delisted Club', array[pg_temp.i('bob')]);
select public.set_circle_discovery(pg_temp.i('down'), true, 'About to be taken down.', 'other', 'en', '{}'::text[]);
insert into pg_temp.ids select 'other', public.create_circle('Other Club', array[pg_temp.i('bob')]);
select public.set_circle_discovery(pg_temp.i('other'), true, 'Another public circle.', 'other', 'en', '{}'::text[]);
select pg_temp.root();

-- ===================================== 1. the short name: who, what, how often
do $$
declare p uuid := pg_temp.i('pub');
begin
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_slug(%L, ''pixel-club'')', p)) = '42501', 'slug: a member cannot set it');
  perform pg_temp.expect(pg_temp.state(format('select public.get_circle_slug(%L)', p)) = '42501', 'slug: a member cannot read it');
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_slug(%L, ''pixel-club'')', p)) = '42501', 'slug: an outsider cannot set it');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_slug(%L, ''pixel-club'')', p)) = '42501', 'slug: nobody signed in cannot set it (no grant)');
  perform pg_temp.expect(pg_temp.state(format('select public.get_circle_slug(%L)', p)) = '42501', 'slug: nobody signed in cannot read it');
  perform pg_temp.expect(pg_temp.state('select public.resolve_circle_slug(''pixel-club'')') = '42501', 'slug: nobody signed in cannot resolve it');

  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_slug(%L, ''ab'')', p)) = '22023', 'slug: two characters is too short');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_slug(%L, %L)', p, repeat('a', 33))) = '22023', 'slug: 33 characters is too long');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_slug(%L, ''a--b'')', p)) = '22023', 'slug: no double hyphen');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_slug(%L, ''-abc'')', p)) = '22023', 'slug: no leading hyphen');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_slug(%L, ''abc-'')', p)) = '22023', 'slug: no trailing hyphen');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_slug(%L, ''has space'')', p)) = '22023', 'slug: no spaces');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_slug(%L, ''pixel_club'')', p)) = '22023', 'slug: no underscores');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_slug(%L, %L)', p, 'caf' || chr(233) || 'club')) = '22023', 'slug: ASCII only');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_slug(%L, ''<script>x</script>'')', p)) = '22023', 'slug: markup is not a name');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_slug(%L, ''admin'')', p)) = '22023', 'slug: reserved word');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_slug(%L, ''Invite'')', p)) = '22023', 'slug: reserved word, any case');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_slug(%L, ''wecord'')', p)) = '22023', 'slug: the product name is reserved');
  perform pg_temp.root();
  perform pg_temp.expect((select slug from public.circles where id = p) is null, 'slug: refused calls changed nothing');
  perform pg_temp.expect(pg_temp.state(format('update public.circles set slug = ''ADMIN'' where id = %L', p)) <> 'ok', 'slug: the table itself refuses an unformatted one');
  perform pg_temp.expect(pg_temp.state(format('update public.circles set slug = ''admin'' where id = %L', p)) <> 'ok', 'slug: the table itself refuses a reserved one');

  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(public.set_circle_slug(p, '  Pixel-Club ') ->> 'slug' = 'pixel-club', 'slug: trimmed and lower-cased');
  perform pg_temp.expect(public.get_circle_slug(p) ->> 'slug' = 'pixel-club', 'slug: a manager reads it');
  perform pg_temp.root();
  perform pg_temp.expect((select slug from public.circles where id = p) = 'pixel-club', 'slug: saved');
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = p and action = 'slug_update') = 1, 'slug: audited');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_slug(p, 'pixel-club');
  perform pg_temp.root();
  perform pg_temp.expect((select count(*) from public.circle_audit_log where circle_id = p and action = 'slug_update') = 1, 'slug: saving the same name is not logged again');

  -- Taken by another circle (also with different case).
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_slug(%L, ''Pixel-Club'')', pg_temp.i('other'))) = '23505', 'slug: taken names are refused');
  perform pg_temp.root();
  perform pg_temp.expect(pg_temp.state(format('update public.circles set slug = ''pixel-club'' where id = %L', pg_temp.i('other'))) = '23505', 'slug: the index backs it up');

  -- Clearing, and the hourly allowance (10 changes).
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_slug(p, null);
  perform pg_temp.root();
  perform pg_temp.expect((select slug from public.circles where id = p) is null, 'slug: null clears it');
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_slug(p, 'pixel-1');
  perform public.set_circle_slug(p, 'pixel-2');
  perform public.set_circle_slug(p, 'pixel-3');
  perform public.set_circle_slug(p, 'pixel-4');
  perform public.set_circle_slug(p, 'pixel-5');
  perform public.set_circle_slug(p, 'pixel-6');
  perform public.set_circle_slug(p, 'pixel-7');
  perform public.set_circle_slug(p, 'pixel-8');
  perform pg_temp.expect(pg_temp.state(format('select public.set_circle_slug(%L, ''pixel-9'')', p)) = 'PB429', 'slug: at most 10 changes an hour');
  perform pg_temp.root();
  delete from public.circle_audit_log where circle_id = p and action = 'slug_update';
  perform pg_temp.act(pg_temp.i('ada'));
  perform public.set_circle_slug(p, 'pixel-club');
  perform public.set_circle_slug(pg_temp.i('priv'), 'secret-club');
  perform public.set_circle_slug(pg_temp.i('down'), 'delisted-club');
  perform public.set_circle_slug(pg_temp.i('other'), 'other-club');
  perform pg_temp.root();
end $$;

-- ===================================== 2. opening /c/<slug> in the app
do $$
begin
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect((public.resolve_circle_slug('pixel-club') ->> 'circle_id')::uuid = pg_temp.i('pub'), 'resolve: a public circle opens for anyone signed in');
  perform pg_temp.expect((public.resolve_circle_slug('PIXEL-CLUB') ->> 'is_member')::boolean = false, 'resolve: not a member yet');
  perform pg_temp.expect(public.resolve_circle_slug('secret-club') is null, 'resolve: a private circle says nothing to outsiders');
  perform pg_temp.expect(public.resolve_circle_slug('no-such-club') is null, 'resolve: and neither does a missing one');
  perform pg_temp.expect(public.resolve_circle_slug('''; drop table circles; --') is null, 'resolve: odd input is just null');
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect((public.resolve_circle_slug('secret-club') ->> 'is_member')::boolean, 'resolve: a member opens their private circle');
  perform pg_temp.root();
end $$;

-- ===================================== 3. the public card, as the web page asks
do $$
declare p uuid := pg_temp.i('pub'); c jsonb;
begin
  perform pg_temp.act(null);
  c := pg_temp.card('pixel-club');
  perform pg_temp.expect((c ->> 'available')::boolean, 'card: a public circle is available to anon');
  perform pg_temp.expect(c ->> 'name' = 'Pixel Club', 'card: the name');
  perform pg_temp.expect(c ->> 'description' = 'Pixel art, palettes and weekly challenges.', 'card: the description');
  perform pg_temp.expect(c ->> 'category' = 'art' and c ->> 'language' = 'en' and c ->> 'join_mode' = 'open', 'card: category, language and join mode');
  perform pg_temp.expect(c -> 'tags' = '["pixel art", "palettes"]'::jsonb, 'card: the tags');
  perform pg_temp.expect(c ->> 'slug' = 'pixel-club', 'card: the slug');
  perform pg_temp.expect(
    (select array_agg(k order by k) from jsonb_object_keys(c) k)
      = array['available','category','description','icon_url','join_mode','language','member_level','name','slug','tags'],
    'card: exactly the public fields, no id and no member list');
  perform pg_temp.expect(c -> 'member_level' = 'null'::jsonb, 'card: 2 members is hidden (<5)');
  perform pg_temp.expect(position(p::text in c::text) = 0 and position('ada' in lower(c::text)) = 0, 'card: no circle id and no member name anywhere in it');
  perform pg_temp.expect(pg_temp.card(' PIXEL-club ') = c, 'card: case and spaces do not matter');

  -- The level, not the count.
  perform pg_temp.root();
  perform pg_temp.expect(public.public_circle_member_level(0) is null and public.public_circle_member_level(4) is null, 'level: under 5 is null');
  perform pg_temp.expect(public.public_circle_member_level(5) = 5 and public.public_circle_member_level(9) = 5, 'level: 5 to 9 is 5');
  perform pg_temp.expect(public.public_circle_member_level(10) = 10 and public.public_circle_member_level(24) = 10, 'level: 10 to 24 is 10');
  perform pg_temp.expect(public.public_circle_member_level(25) = 25 and public.public_circle_member_level(49) = 25, 'level: 25 to 49 is 25');
  perform pg_temp.expect(public.public_circle_member_level(50) = 50 and public.public_circle_member_level(99) = 50, 'level: 50 to 99 is 50');
  perform pg_temp.expect(public.public_circle_member_level(100) = 100 and public.public_circle_member_level(249) = 100, 'level: 100 to 249 is 100');
  perform pg_temp.expect(public.public_circle_member_level(999) = 500 and public.public_circle_member_level(1000) = 1000, 'level: 500 and 1000');
  perform pg_temp.expect(public.public_circle_member_level(99999) = 10000, 'level: capped at 10000');
  perform pg_temp.fill(p, 4);
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.card('pixel-club') -> 'member_level' = '5'::jsonb, 'card: 6 members is level 5, not 6');
  perform pg_temp.root();
  perform pg_temp.fill(p, 7);
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.card('pixel-club') -> 'member_level' = '10'::jsonb, 'card: 13 members is level 10, not 13');

  -- Everything that must look exactly like "no such page".
  perform pg_temp.expect(pg_temp.card('no-such-club') = '{"available": false}'::jsonb, 'card: a missing slug is unavailable');
  perform pg_temp.expect(pg_temp.card('secret-club') = pg_temp.card('no-such-club'), 'card: a private circle looks exactly like a missing one');
  perform pg_temp.expect(pg_temp.card('') = pg_temp.card('no-such-club'), 'card: empty slug');
  perform pg_temp.expect(pg_temp.card(null) = pg_temp.card('no-such-club'), 'card: null slug');
  perform pg_temp.expect(pg_temp.card('x') = pg_temp.card('no-such-club'), 'card: one character');
  perform pg_temp.expect(pg_temp.card(repeat('a', 5000)) = pg_temp.card('no-such-club'), 'card: a very long slug');
  perform pg_temp.expect(pg_temp.card('''; select 1; --') = pg_temp.card('no-such-club'), 'card: SQL in the slug is just unavailable');
  perform pg_temp.expect(pg_temp.card('pixel-club%') = pg_temp.card('no-such-club'), 'card: no pattern matching');
  perform pg_temp.expect(pg_temp.card('pixel_club') = pg_temp.card('no-such-club'), 'card: underscore is not a wildcard');

  -- Taken down: delisted or suspended, then back.
  perform pg_temp.expect((pg_temp.card('delisted-club') ->> 'available')::boolean, 'down: public before the take-down');
  perform pg_temp.root();
  update public.circles set disabled_at = now(), disabled_mode = 'delist', disabled_reason = 'test' where id = pg_temp.i('down');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.card('delisted-club') = pg_temp.card('no-such-club'), 'down: a delisted circle is unavailable');
  perform pg_temp.root();
  update public.circles set disabled_mode = 'suspend' where id = pg_temp.i('down');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.card('delisted-club') = pg_temp.card('no-such-club'), 'down: and a suspended one');
  perform pg_temp.root();
  update public.circles set disabled_at = null, disabled_mode = null, disabled_reason = null where id = pg_temp.i('down');
  perform pg_temp.act(null);
  perform pg_temp.expect((pg_temp.card('delisted-club') ->> 'available')::boolean, 'down: back when the take-down is lifted');

  -- A circle that stops being public disappears at once.
  perform pg_temp.root();
  update public.circles set is_public = false where id = pg_temp.i('other');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.card('other-club') = pg_temp.card('no-such-club'), 'private: turning public off hides the page');
  perform pg_temp.root();
  update public.circles set is_public = true where id = pg_temp.i('other');

  -- The picture: only a plain https address.
  update public.circles set avatar_url = 'https://img.example/a/pixel.png?x=1' where id = p;
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.card('pixel-club') ->> 'icon_url' = 'https://img.example/a/pixel.png?x=1', 'icon: an https address passes');
  perform pg_temp.root();
  update public.circles set avatar_url = 'http://img.example/a.png' where id = p;
  perform pg_temp.expect(pg_temp.card('pixel-club') -> 'icon_url' = 'null'::jsonb, 'icon: http is dropped');
  update public.circles set avatar_url = 'javascript:alert(1)' where id = p;
  perform pg_temp.expect(pg_temp.card('pixel-club') -> 'icon_url' = 'null'::jsonb, 'icon: javascript: is dropped');
  update public.circles set avatar_url = 'https://img.example/"><script>alert(1)</script>' where id = p;
  perform pg_temp.expect(pg_temp.card('pixel-club') -> 'icon_url' = 'null'::jsonb, 'icon: markup in an address is dropped');
  update public.circles set avatar_url = 'https://img.example/a b.png' where id = p;
  perform pg_temp.expect(pg_temp.card('pixel-club') -> 'icon_url' = 'null'::jsonb, 'icon: a space is dropped');
  update public.circles set avatar_url = null where id = p;

  -- Join mode shows, nothing else about the review.
  update public.circles set join_mode = 'apply' where id = p;
  perform pg_temp.expect(pg_temp.card('pixel-club') ->> 'join_mode' = 'apply', 'card: apply mode shows as apply');
  update public.circles set join_mode = 'open' where id = p;
end $$;

-- ===================================== 4. the invite card
do $$
declare p uuid := pg_temp.i('pub'); good text; spent text; gone text; later text; priv_code text; down_code text; paused_code text;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  good := public.create_circle_invite(p, null, null);
  spent := public.create_circle_invite(p, null, 1);
  gone := public.create_circle_invite(p, null, null);
  later := public.create_circle_invite(p, 1, null);
  priv_code := public.create_circle_invite(pg_temp.i('priv'), null, null);
  down_code := public.create_circle_invite(pg_temp.i('down'), null, null);
  paused_code := public.create_circle_invite(pg_temp.i('other'), null, null);
  perform public.revoke_circle_invite(gone);
  perform pg_temp.root();
  update public.circle_invites set use_count = max_uses where code = spent;
  update public.circle_invites set expires_at = now() - interval '1 minute' where code = later;

  perform pg_temp.act(null);
  perform pg_temp.expect((pg_temp.icard(good) ->> 'available')::boolean, 'invite: a valid invite to a public circle');
  perform pg_temp.expect(pg_temp.icard(good) ->> 'name' = 'Pixel Club', 'invite: shows the circle');
  perform pg_temp.expect(pg_temp.icard(upper(good)) = pg_temp.icard(good), 'invite: the code is case-insensitive');
  perform pg_temp.expect(
    (select array_agg(k order by k) from jsonb_object_keys(pg_temp.icard(good)) k)
      = array['available','category','description','icon_url','join_mode','language','member_level','name','slug','tags'],
    'invite: the same public fields as the slug card, nothing about the invite');
  perform pg_temp.expect(pg_temp.icard(good) ->> 'slug' = 'pixel-club', 'invite: the slug rides along (for the link to the circle page)');
  perform pg_temp.expect(position(good in pg_temp.icard(good)::text) = 0, 'invite: the code is not echoed');

  perform pg_temp.expect(pg_temp.icard('aaaaaaaaaa') = '{"available": false}'::jsonb, 'invite: an unknown code is unavailable');
  perform pg_temp.expect(pg_temp.icard(spent) = pg_temp.icard('aaaaaaaaaa'), 'invite: a used-up invite looks like a missing one');
  perform pg_temp.expect(pg_temp.icard(gone) = pg_temp.icard('aaaaaaaaaa'), 'invite: a revoked invite looks like a missing one');
  perform pg_temp.expect(pg_temp.icard(later) = pg_temp.icard('aaaaaaaaaa'), 'invite: an expired invite looks like a missing one');
  perform pg_temp.expect(pg_temp.icard(priv_code) = pg_temp.icard('aaaaaaaaaa'), 'invite: a valid invite to a private circle looks like a missing one');
  perform pg_temp.expect(pg_temp.icard('') = pg_temp.icard('aaaaaaaaaa') and pg_temp.icard(null) = pg_temp.icard('aaaaaaaaaa'), 'invite: empty and null');
  perform pg_temp.expect(pg_temp.icard('too-short') = pg_temp.icard('aaaaaaaaaa'), 'invite: the wrong shape');
  perform pg_temp.expect(pg_temp.icard(repeat('a', 5000)) = pg_temp.icard('aaaaaaaaaa'), 'invite: a very long code');
  perform pg_temp.expect(pg_temp.icard('a'' or ''1''=''1') = pg_temp.icard('aaaaaaaaaa'), 'invite: SQL in the code');
  perform pg_temp.expect(pg_temp.icard('aaaaaaaaa_') = pg_temp.icard('aaaaaaaaaa'), 'invite: no wildcards');

  perform pg_temp.root();
  update public.circles set disabled_at = now(), disabled_mode = 'delist', disabled_reason = 'test' where id = pg_temp.i('down');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.icard(down_code) = pg_temp.icard('aaaaaaaaaa'), 'invite: a delisted circle is unavailable');
  perform pg_temp.root();
  update public.circles set disabled_mode = 'suspend' where id = pg_temp.i('down');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.icard(down_code) = pg_temp.icard('aaaaaaaaaa'), 'invite: and a suspended one');
  perform pg_temp.root();
  update public.circles set disabled_at = null, disabled_mode = null, disabled_reason = null where id = pg_temp.i('down');
  perform pg_temp.act(null);
  perform pg_temp.expect((pg_temp.icard(down_code) ->> 'available')::boolean, 'invite: back when the take-down is lifted');

  -- Raid protection paused the circle's invites.
  perform pg_temp.root();
  insert into public.circle_security (circle_id, invites_paused_until)
  values (pg_temp.i('other'), now() + interval '1 hour')
  on conflict (circle_id) do update set invites_paused_until = excluded.invites_paused_until;
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.icard(paused_code) = pg_temp.icard('aaaaaaaaaa'), 'invite: paused invites are unavailable');
  perform pg_temp.root();
  update public.circle_security set invites_paused_until = null where circle_id = pg_temp.i('other');
  perform pg_temp.act(null);
  perform pg_temp.expect((pg_temp.icard(paused_code) ->> 'available')::boolean, 'invite: and available again');

  -- Making the card did not use the invite up.
  perform pg_temp.root();
  perform pg_temp.expect((select use_count from public.circle_invites where code = good) = 0, 'invite: looking does not count as a use');
end $$;

-- ===================================== 5. what anon can and cannot do
do $$
begin
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.state('select count(*) from public.circles') <> 'ok'
    or (select count(*) from public.circles) = 0, 'anon: cannot read circles');
  perform pg_temp.expect(pg_temp.state('select count(*) from public.circle_invites') <> 'ok'
    or (select count(*) from public.circle_invites) = 0, 'anon: cannot read invites');
  perform pg_temp.expect(pg_temp.state('select count(*) from public.circle_members') <> 'ok'
    or (select count(*) from public.circle_members) = 0, 'anon: cannot read members');
  perform pg_temp.expect(pg_temp.state(format('select public.public_circle_card_json(c) from public.circles c where id = %L', pg_temp.i('pub'))) <> 'ok', 'anon: cannot call the card builder');
  perform pg_temp.expect(pg_temp.state('select public.public_circle_member_level(50)') <> 'ok', 'anon: cannot call the level helper');
  perform pg_temp.expect(pg_temp.state('select public.get_circle_invite_preview(''aaaaaaaaaa'')') <> 'ok', 'anon: the signed-in invite preview is still closed to anon');
  perform pg_temp.expect(pg_temp.state('select public.get_public_circle_card(''pixel-club'')') = 'ok', 'anon: the card is open');
  perform pg_temp.expect(pg_temp.state('select public.get_public_invite_card(''aaaaaaaaaa'')') = 'ok', 'anon: the invite card is open');
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect(pg_temp.state('select public.get_public_circle_card(''pixel-club'')') = 'ok', 'signed in: the card is open too');
  perform pg_temp.root();
  perform pg_temp.expect(
    (select bool_and(p.prosecdef and p.proconfig::text like '%search_path=public%')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('get_public_circle_card', 'get_public_invite_card', 'public_circle_card_json',
         'set_circle_slug', 'get_circle_slug', 'resolve_circle_slug')),
    'all: security definer with a fixed search_path');
end $$;
\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'public circle pages: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
