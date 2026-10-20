-- Behaviour checks for AI guard 2.0 and the link-safety column (migrations
-- 202610260200, 202610260210 and 202610260220). Run by
-- test/supabase/guard2_test.dart against the local database: it applies every
-- migration after the local baseline (202610170001) in a transaction, plays
-- people through the API and the service role, and rolls everything back.
-- Run from the repository root.
--
-- What it walks through: the scope settings (who may change them, the audit),
-- polls and pictures waiting for the check (and pictures never held without
-- vision), what the function reads, what moderators see in the queue, the
-- checks of notes, events and tasks and their queue, the throttle on edits,
-- the sweep and its own cron job, and that nothing is recorded when the scope,
-- the circle's AI or the sign-in says no.
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
\i supabase/migrations/202610260200_guard2_scope.sql
\i supabase/migrations/202610260210_guard2_items.sql
\i supabase/migrations/202610260220_link_preview_final_url.sql
\i supabase/migrations/202610260500_circle_slug.sql
\i supabase/migrations/202610260510_public_circle_card.sql

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@guard2.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'mod@guard2.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'newt@guard2.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d1', 'olly@guard2.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve@guard2.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_guard2', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'mod_guard2', 'Mo'),
  ('00000000-0000-4000-8000-0000000000c1', 'newt_guard2', 'Newt'),
  ('00000000-0000-4000-8000-0000000000d1', 'olly_guard2', 'Olly'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve_guard2', 'Eve');

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

-- Signed in as one of the people but with the owner's database access, for
-- writing rows the API would not let a member write (the triggers still see
-- who is signed in).
create function pg_temp.claim_as(who text) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  if who is not null then
    perform set_config(
      'request.jwt.claim.sub',
      format('00000000-0000-4000-8000-0000000000%s1', who),
      true
    );
  end if;
end;
$$;

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

create function pg_temp.say(who text, text_body text) returns uuid language plpgsql as $$
declare
  sent uuid;
begin
  perform pg_temp.act_as(who);
  sent := public.send_text_message(
    (select id from ids where name = 'channel'), text_body, null, null, '[]'::jsonb
  );
  perform pg_temp.act_as(null);
  return sent;
end;
$$;
grant execute on function pg_temp.say(text, text) to public;

create function pg_temp.poll(who text, question text) returns uuid language plpgsql as $$
declare
  sent uuid;
begin
  perform pg_temp.act_as(who);
  sent := public.create_poll(
    (select id from ids where name = 'channel'), question, array['Cash', 'Pills']
  );
  perform pg_temp.act_as(null);
  return sent;
end;
$$;
grant execute on function pg_temp.poll(text, text) to public;

-- A picture message the way the app sends one (a file under the chat's
-- folder), as one of the people.
create function pg_temp.picture(who text, extra jsonb default '{}'::jsonb) returns uuid language plpgsql as $$
declare
  sent uuid;
  conv uuid := (select id from ids where name = 'channel');
begin
  perform pg_temp.act_as(who);
  insert into public.messages (conversation_id, sender_id, type, attachment)
  values (
    conv,
    format('00000000-0000-4000-8000-0000000000%s1', who)::uuid,
    'image',
    jsonb_build_object(
      'kind', 'image', 'bucket', 'chat-images',
      'path', conv::text || '/' || gen_random_uuid()::text || '.png',
      'mime_type', 'image/png', 'size', 1234, 'width', 100, 'height', 100
    ) || extra
  )
  returning id into sent;
  perform pg_temp.act_as(null);
  return sent;
end;
$$;
grant execute on function pg_temp.picture(text, jsonb) to public;

-- Ada's circle: Mo moderates, Newt joined just now, Olly ten days ago, Eve
-- is a reader.
select pg_temp.act_as('a');
insert into ids select 'circle', public.create_circle('Guarded circle', array[]::uuid[]);
select pg_temp.act_as(null);

insert into ids
select 'channel', cc.conversation_id
from public.circle_channels cc
where cc.circle_id = (select id from ids where name = 'circle') and cc.position = 0;

insert into public.circle_members (circle_id, user_id, role, created_at)
select (select id from ids where name = 'circle'), u.id, 'member',
  case when u.id = '00000000-0000-4000-8000-0000000000d1' then now() - interval '10 days' else now() end
from (values
  ('00000000-0000-4000-8000-0000000000b1'::uuid),
  ('00000000-0000-4000-8000-0000000000c1'::uuid),
  ('00000000-0000-4000-8000-0000000000d1'::uuid),
  ('00000000-0000-4000-8000-0000000000e1'::uuid)
) u(id);
insert into public.conversation_members (conversation_id, user_id, role)
select (select id from ids where name = 'channel'), cm.user_id, cm.role
from public.circle_members cm
where cm.circle_id = (select id from ids where name = 'circle')
on conflict do nothing;

-- Mo has a role with manage messages.
with role as (
  insert into public.circle_roles (circle_id, name, position, permissions)
  values (
    (select id from ids where name = 'circle'), 'Mods', 1,
    public.circle_default_role_permissions() | 4
  )
  returning id
)
insert into public.circle_member_roles (circle_id, user_id, role_id)
select (select id from ids where name = 'circle'), '00000000-0000-4000-8000-0000000000b1', role.id
from role;

-- ----------------------------------------------------------- scope settings

select pg_temp.act_as('a');
select pg_temp.check(
  'by default polls and titles are checked and pictures are not',
  (select (s->>'check_polls')::boolean and (s->>'check_items')::boolean
     and not (s->>'check_images')::boolean
     and not (s->>'vision_available')::boolean
   from (select public.get_circle_ai_guard_scope((select id from ids where name = 'circle')) s) x)
);
select pg_temp.act_as('c');
select pg_temp.refused('a member cannot read the scope',
  format('select public.get_circle_ai_guard_scope(%L)', (select id from ids where name = 'circle')), '42501');
select pg_temp.refused('a member cannot change the scope',
  format('select public.set_circle_ai_guard_scope(%L, true, true, true)', (select id from ids where name = 'circle')), '42501');
select pg_temp.act_as('b');
select pg_temp.refused('a moderator without manage circle cannot change the scope',
  format('select public.set_circle_ai_guard_scope(%L, true, true, true)', (select id from ids where name = 'circle')), '42501');
select pg_temp.act_as('a');
select pg_temp.refused('a scope needs all three answers',
  format('select public.set_circle_ai_guard_scope(%L, true, null, true)', (select id from ids where name = 'circle')), '22023');
select public.set_circle_ai_guard_scope((select id from ids where name = 'circle'), true, true, false);
select pg_temp.act_as(null);
select pg_temp.check(
  'an unchanged scope writes no audit entry',
  not exists (select 1 from public.circle_audit_log where action = 'guard_update')
);
select pg_temp.act_as('a');
select public.set_circle_ai_guard_scope((select id from ids where name = 'circle'), true, true, true);
select pg_temp.act_as(null);
select pg_temp.check(
  'changing the scope is audited with what changed',
  exists (
    select 1 from public.circle_audit_log
    where action = 'guard_update' and actor_id = '00000000-0000-4000-8000-0000000000a1'
      and changes->'check_images'->>'new' = 'true'
      and not changes ? 'check_polls'
  )
);

-- The guard itself is configured the old way.
select pg_temp.act_as('a');
select public.set_circle_ai_guard((select id from ids where name = 'circle'), true, 'joined_days', 3, 10, 'hold');
select pg_temp.act_as(null);

-- Nothing here changes who can call the service functions.
select pg_temp.act_as('c');
select pg_temp.refused('a member cannot set a runtime flag',
  'select public.ai_set_runtime_flag(''vision'', true)', '42501');
select pg_temp.refused('a member cannot read the vision usage',
  format('select * from public.ai_consume_circle_vision_request(%L, 5)', (select id from ids where name = 'circle')), '42501');
select pg_temp.refused('a member cannot read a message the function claimed',
  format('select * from public.ai_guard_message_info(%L)', gen_random_uuid()), '42501');
select pg_temp.refused('a member cannot claim an item',
  format('select * from public.ai_guard_item_claim(%L)', gen_random_uuid()), '42501');
select pg_temp.act_as(null);

-- ------------------------------------------------------------ fail open

-- No way to wake the function yet (no Vault secrets): an item is recorded and
-- released at once, not checked.
select pg_temp.act_as('c');
insert into ids select 'note_unwakeable', (public.create_note((select id from ids where name = 'channel'), 'Hello team')->>'id')::uuid;
select pg_temp.act_as(null);
select pg_temp.check(
  'when the check of an item cannot start it is released, not checked',
  (select r.state = 'released' and r.verdict = 'not_checked' and r.unchecked_reason = 'unavailable'
   from public.guard_item_reviews r where r.item_id = (select id from ids where name = 'note_unwakeable'))
);
delete from public.guard_item_reviews;

select vault.create_secret('http://127.0.0.1:54321/functions/v1', 'wecord_functions_url');
select vault.create_secret('guard2-test-secret', 'wecord_dispatch_secret');

-- -------------------------------------------------------------------- polls

insert into ids select 'poll_new', pg_temp.poll('c', 'Win cheap pills now');
select pg_temp.check(
  'a poll of a member the guard checks waits for the check',
  (select m.review_state = 'checking' and m.type = 'poll'
   from public.messages m where m.id = (select id from ids where name = 'poll_new'))
  and (select r.state = 'checking' and r.mode = 'hold'
       from public.message_reviews r where r.message_id = (select id from ids where name = 'poll_new'))
);
select pg_temp.check(
  'the database woke the ai function for it',
  exists (
    select 1 from net.http_request_queue q
    where q.url = 'http://127.0.0.1:54321/functions/v1/ai'
      and q.headers->>'Authorization' = 'Bearer guard2-test-secret'
      and convert_from(q.body, 'UTF8')::jsonb->>'action' = 'guard'
      and convert_from(q.body, 'UTF8')::jsonb->>'message_id' = (select id::text from ids where name = 'poll_new')
  )
);
insert into ids select 'poll_old', pg_temp.poll('d', 'Lunch?');
insert into ids select 'poll_mod', pg_temp.poll('b', 'Meeting time?');
select pg_temp.check(
  'an old member''s and a moderator''s polls are not held',
  (select count(*) = 2 from public.messages
   where id in ((select id from ids where name = 'poll_old'), (select id from ids where name = 'poll_mod'))
     and review_state is null)
);
select pg_temp.act_as('e');
select pg_temp.check('others do not see the waiting poll',
  (select count(*) = 0 from public.messages where id = (select id from ids where name = 'poll_new')));
select pg_temp.act_as('c');
select pg_temp.check('its author does',
  (select count(*) = 1 from public.messages where id = (select id from ids where name = 'poll_new')));
select pg_temp.act_as(null);

-- The function reads the question and the options.
select pg_temp.check(
  'the function reads the poll''s question and options',
  (select i.type = 'poll' and i.body = 'Win cheap pills now'
     and (select array_agg(o->>'text' order by o->>'text') from jsonb_array_elements(i.attachment->'options') o)
         = array['Cash', 'Pills']
   from public.ai_guard_message_info((select id from ids where name = 'poll_new')) i)
);
select pg_temp.check(
  'nothing is handed out once the check is over',
  (select count(*) = 0 from public.ai_guard_message_info((select id from ids where name = 'poll_old')))
);

-- The AI flags it: it is held and moderators see it with its options.
select pg_temp.check(
  'a flagged poll is held',
  public.finish_message_review((select id from ids where name = 'poll_new'), 'spam', 'Junk', null, 'spam') = 'held'
);
select pg_temp.act_as('b');
select pg_temp.check(
  'a moderator sees the poll''s options in the queue',
  (select count(*) = 1 and bool_and(m.type = 'poll' and m.media->'options' = '["Cash", "Pills"]'::jsonb)
   from public.list_message_review_media((select id from ids where name = 'circle')) m)
  and (select count(*) = 1 and bool_and(r.body = 'Win cheap pills now')
       from public.list_message_reviews((select id from ids where name = 'circle')) r)
);
select pg_temp.act_as('e');
select pg_temp.check(
  'an ordinary member gets no media from the queue',
  (select count(*) = 0 from public.list_message_review_media((select id from ids where name = 'circle')))
);
select pg_temp.act_as('b');
select public.decide_message_review((select id from ids where name = 'poll_new'), 'approve');
select pg_temp.act_as('e');
select pg_temp.check('an approved poll is visible',
  (select count(*) = 1 from public.messages where id = (select id from ids where name = 'poll_new')));
select pg_temp.act_as(null);

-- Polls can be left out.
select pg_temp.act_as('a');
select public.set_circle_ai_guard_scope((select id from ids where name = 'circle'), false, true, true);
select pg_temp.act_as(null);
insert into ids select 'poll_off', pg_temp.poll('c', 'Another one');
select pg_temp.check('with polls off a new member''s poll is not held',
  (select review_state is null from public.messages where id = (select id from ids where name = 'poll_off')));
select pg_temp.act_as('a');
select public.set_circle_ai_guard_scope((select id from ids where name = 'circle'), true, true, true);
select pg_temp.act_as(null);

-- ----------------------------------------------------------------- pictures

-- Scope on, but the server cannot read pictures: they go out as usual.
insert into ids select 'pic_novision', pg_temp.picture('c');
select pg_temp.check(
  'without vision a picture is never held',
  (select review_state is null from public.messages where id = (select id from ids where name = 'pic_novision'))
  and not exists (select 1 from public.message_reviews where message_id = (select id from ids where name = 'pic_novision'))
);

select public.ai_set_runtime_flag('vision', true);
select pg_temp.check('the flag is stored', public.ai_runtime_flag('vision'));
select pg_temp.act_as('a');
select pg_temp.check('managers see that vision is available',
  (select (public.get_circle_ai_guard_scope((select id from ids where name = 'circle'))->>'vision_available')::boolean));
select pg_temp.act_as(null);

insert into ids select 'pic_new', pg_temp.picture('c');
select pg_temp.check(
  'with vision on a new member''s picture waits for the check',
  (select review_state = 'checking' from public.messages where id = (select id from ids where name = 'pic_new'))
  and exists (select 1 from public.message_reviews where message_id = (select id from ids where name = 'pic_new') and state = 'checking')
);
insert into ids select 'pic_old', pg_temp.picture('d');
select pg_temp.check(
  'an old member''s picture is not checked',
  (select review_state is null from public.messages where id = (select id from ids where name = 'pic_old'))
);
select pg_temp.act_as('c');
insert into public.messages (conversation_id, sender_id, type, attachment)
values (
  (select id from ids where name = 'channel'), '00000000-0000-4000-8000-0000000000c1', 'image',
  jsonb_build_object('kind', 'video', 'bucket', 'chat-images',
    'path', (select id from ids where name = 'channel')::text || '/clip.mp4', 'mime_type', 'video/mp4')
) returning id \gset notimage_
select pg_temp.act_as(null);
select pg_temp.check('an attachment that is not a picture is not checked',
  (select review_state is null from public.messages where id = :'notimage_id'));

select pg_temp.check(
  'the function reads the picture''s file',
  (select i.type = 'image' and i.attachment->>'bucket' = 'chat-images' and i.attachment->>'mime_type' = 'image/png'
   from public.ai_guard_message_info((select id from ids where name = 'pic_new')) i)
);

-- Held picture: the moderator gets the file to open with their own access.
select pg_temp.check(
  'a flagged picture is held',
  public.finish_message_review((select id from ids where name = 'pic_new'), 'sexual', 'Nudity', null, '裸露') = 'held'
);
select pg_temp.act_as('b');
select pg_temp.check(
  'a moderator gets the picture''s file from the queue',
  (select count(*) = 1 and bool_and(m.type = 'image' and m.media->>'bucket' = 'chat-images'
     and m.media->>'path' like (select id::text from ids where name = 'channel') || '/%')
   from public.list_message_review_media((select id from ids where name = 'circle')) m)
);
select pg_temp.act_as(null);

-- The ways a picture ends unchecked are all accepted.
insert into ids select 'pic_a', pg_temp.picture('c');
insert into ids select 'pic_b', pg_temp.picture('c');
insert into ids select 'pic_c', pg_temp.picture('c');
select pg_temp.check('vision_off is a reason',
  public.finish_message_review((select id from ids where name = 'pic_a'), 'not_checked', null, 'vision_off') = 'released');
select pg_temp.check('vision_unsupported is a reason',
  public.finish_message_review((select id from ids where name = 'pic_b'), 'not_checked', null, 'vision_unsupported') = 'released');
select pg_temp.check('image_unreadable is a reason',
  public.finish_message_review((select id from ids where name = 'pic_c'), 'not_checked', null, 'image_unreadable') = 'released');
select pg_temp.check('the reasons are kept',
  (select array_agg(r.unchecked_reason order by r.unchecked_reason)
   from public.message_reviews r
   where r.message_id in ((select id from ids where name = 'pic_a'), (select id from ids where name = 'pic_b'), (select id from ids where name = 'pic_c')))
  = array['image_unreadable', 'vision_off', 'vision_unsupported']);

-- Turning the scope off, or vision off, stops the holding.
select pg_temp.act_as('a');
select public.set_circle_ai_guard_scope((select id from ids where name = 'circle'), true, true, false);
select pg_temp.act_as(null);
insert into ids select 'pic_scope_off', pg_temp.picture('c');
select pg_temp.check('with pictures left out of the scope nothing is held',
  (select review_state is null from public.messages where id = (select id from ids where name = 'pic_scope_off')));
select pg_temp.act_as('a');
select public.set_circle_ai_guard_scope((select id from ids where name = 'circle'), true, true, true);
select pg_temp.act_as(null);
select public.ai_set_runtime_flag('vision', false);
insert into ids select 'pic_flag_off', pg_temp.picture('c');
select pg_temp.check('with vision turned off again nothing is held',
  (select review_state is null from public.messages where id = (select id from ids where name = 'pic_flag_off')));
select public.ai_set_runtime_flag('vision', true);

-- Pictures are counted apart from text, per circle and day.
select pg_temp.check(
  'pictures are counted per circle with their own limit',
  (select allowed and used = 1 from public.ai_consume_circle_vision_request((select id from ids where name = 'circle'), 2))
  and (select allowed and used = 2 from public.ai_consume_circle_vision_request((select id from ids where name = 'circle'), 2))
  and (select not allowed and used = 2 from public.ai_consume_circle_vision_request((select id from ids where name = 'circle'), 2))
);
select public.ai_refund_circle_vision_request((select id from ids where name = 'circle'));
select pg_temp.check('a refund gives one back',
  (select allowed and used = 2 from public.ai_consume_circle_vision_request((select id from ids where name = 'circle'), 2)));
select pg_temp.check('the text counter is untouched',
  not exists (select 1 from public.ai_circle_usage));

-- Text still behaves as before.
insert into ids select 'text_new', pg_temp.say('c', 'hello from a new member');
select pg_temp.check('a new member''s text still waits',
  (select review_state = 'checking' from public.messages where id = (select id from ids where name = 'text_new')));
select public.finish_message_review((select id from ids where name = 'text_new'), 'allow');

-- A burst's newcomers are checked for polls and pictures too, whatever the
-- guard's own rule says about who is new.
insert into public.circle_security (circle_id, lockdown_until, lockdown_started_at, lockdown_window_from, lockdown_source)
values ((select id from ids where name = 'circle'), now() + interval '1 hour', now(), now() - interval '11 days', 'manual');
insert into ids select 'poll_raid', pg_temp.poll('d', 'Old but arrived in the burst');
select pg_temp.check('a raid newcomer''s poll is checked',
  (select review_state = 'checking' from public.messages where id = (select id from ids where name = 'poll_raid')));
insert into ids select 'pic_raid', pg_temp.picture('d');
select pg_temp.check('a raid newcomer''s picture is checked',
  (select review_state = 'checking' from public.messages where id = (select id from ids where name = 'pic_raid')));
delete from public.circle_security where circle_id = (select id from ids where name = 'circle');
select public.finish_message_review((select id from ids where name = 'poll_raid'), 'allow');
select public.finish_message_review((select id from ids where name = 'pic_raid'), 'allow');

-- The circle's AI switch turns it all off.
update public.circles set ai_enabled = false where id = (select id from ids where name = 'circle');
insert into ids select 'poll_ai_off', pg_temp.poll('c', 'While AI is off');
insert into ids select 'pic_ai_off', pg_temp.picture('c');
select pg_temp.check('with the circle''s AI off nothing is held',
  (select count(*) = 2 from public.messages
   where id in ((select id from ids where name = 'poll_ai_off'), (select id from ids where name = 'pic_ai_off'))
     and review_state is null));
update public.circles set ai_enabled = true where id = (select id from ids where name = 'circle');

-- -------------------------------------------------------------------- items

-- A note by a new member is checked after it is made, and shown meanwhile.
select pg_temp.act_as('c');
insert into ids select 'note', (public.create_note((select id from ids where name = 'channel'), 'Win a free prize')->>'id')::uuid;
select pg_temp.act_as(null);
select pg_temp.check(
  'a new member''s note is recorded for the check, and stays visible',
  (select r.state = 'checking' and r.item_type = 'note'
     and r.circle_id = (select id from ids where name = 'circle')
     and r.actor_id = '00000000-0000-4000-8000-0000000000c1'
   from public.guard_item_reviews r where r.item_id = (select id from ids where name = 'note'))
  and exists (select 1 from public.notes n where n.id = (select id from ids where name = 'note') and n.deleted_at is null)
);
select pg_temp.check(
  'the database woke the ai function for the item',
  exists (
    select 1 from net.http_request_queue q
    where q.url = 'http://127.0.0.1:54321/functions/v1/ai'
      and convert_from(q.body, 'UTF8')::jsonb->>'action' = 'guard_item'
      and convert_from(q.body, 'UTF8')::jsonb->>'review_id' =
        (select r.id::text from public.guard_item_reviews r where r.item_id = (select id from ids where name = 'note'))
  )
);

insert into ids select 'note_review', r.id from public.guard_item_reviews r
where r.item_id = (select id from ids where name = 'note');

select pg_temp.act_as('d');
insert into ids select 'note_old', (public.create_note((select id from ids where name = 'channel'), 'Meeting notes')->>'id')::uuid;
select pg_temp.act_as('b');
insert into ids select 'note_mod', (public.create_note((select id from ids where name = 'channel'), 'Rules')->>'id')::uuid;
select pg_temp.act_as(null);
select pg_temp.check('an old member''s and a moderator''s notes are not checked',
  not exists (select 1 from public.guard_item_reviews
              where item_id in ((select id from ids where name = 'note_old'), (select id from ids where name = 'note_mod'))));

-- A circle event, a task list and a task.
select pg_temp.claim_as('c');
insert into public.circle_events (circle_id, title, description, location_type, location_text, starts_at, created_by)
values ((select id from ids where name = 'circle'), 'Prize night', 'Join http://scam.example', 'external', 'online', now() + interval '1 day',
        '00000000-0000-4000-8000-0000000000c1')
returning id \gset event_
select pg_temp.act_as(null);
select pg_temp.check('a new member''s event is recorded for the check',
  exists (select 1 from public.guard_item_reviews r where r.item_type = 'circle_event' and r.item_id = :'event_id' and r.state = 'checking'));

select pg_temp.act_as('c');
insert into ids select 'tasks', (public.create_task_list((select id from ids where name = 'channel'), 'Chores')->>'id')::uuid;
select public.upsert_task_item((select id from ids where name = 'tasks'), '{"title": "Send me your password"}'::jsonb) as item \gset task_
select pg_temp.act_as(null);
select pg_temp.check('a new member''s task list and task are recorded for the check',
  exists (select 1 from public.guard_item_reviews r where r.item_type = 'task_list' and r.item_id = (select id from ids where name = 'tasks'))
  and exists (select 1 from public.guard_item_reviews r
              where r.item_type = 'task_item' and r.item_id = (:'task_item'::jsonb->>'id')::uuid));

-- The function claims what to read: the live text, once.
select pg_temp.check(
  'the function claims the text of an item',
  (select count(*) = 1 and bool_and(c.title = 'Win a free prize' and c.item_type = 'note' and c.ai_enabled
     and c.circle_id = (select id from ids where name = 'circle'))
   from public.ai_guard_item_claim(
     (select id from ids where name = 'note_review')) c)
);
select pg_temp.check(
  'a second claim right after gets nothing',
  (select count(*) = 0 from public.ai_guard_item_claim(
     (select id from ids where name = 'note_review')))
);
select pg_temp.check(
  'a task is read with its details',
  (select count(*) = 1 and bool_and(c.title = 'Send me your password' and c.detail = '')
   from public.ai_guard_item_claim(
     (select r.id from public.guard_item_reviews r where r.item_type = 'task_item')) c)
);

-- The AI flags the note.
select pg_temp.check(
  'a flagged item goes to the queue as flagged, not hidden',
  public.finish_guard_item_review(
    (select id from ids where name = 'note_review'),
    'scam', 'Fake prize', '虚假奖品') = 'flagged'
);
select pg_temp.check('the AI''s flag is audited without an actor',
  exists (select 1 from public.circle_audit_log
          where action = 'guard_item_flag' and actor_id is null
            and changes->>'item_type' = 'note' and changes->>'verdict' = 'scam'
            and changes->>'title' = 'Win a free prize'));
select pg_temp.check('answering twice does nothing',
  public.finish_guard_item_review(
    (select id from ids where name = 'note_review'),
    'allow') is null);

select pg_temp.act_as('b');
select pg_temp.check(
  'a moderator lists it with the live title, the author and the reason',
  (select count(*) = 1 and bool_and(l.item_type = 'note' and l.title = 'Win a free prize'
     and l.actor_name = 'Newt' and l.verdict = 'scam' and l.reason = 'Fake prize' and l.reason_zh = '虚假奖品'
     and l.channel_id is not null)
   from public.list_guard_item_reviews((select id from ids where name = 'circle')) l)
  and public.count_guard_item_reviews((select id from ids where name = 'circle')) = 1
);
select pg_temp.act_as('e');
select pg_temp.refused('a member cannot list the queue',
  format('select * from public.list_guard_item_reviews(%L)', (select id from ids where name = 'circle')), '42501');
select pg_temp.check('nor count it',
  public.count_guard_item_reviews((select id from ids where name = 'circle')) = 0);
select pg_temp.refused('nor dismiss a card',
  format('select public.dismiss_guard_item_review(%L)',
    (select id from ids where name = 'note_review')), '42501');
select pg_temp.act_as(null);

-- A deleted item drops out of the queue.
select pg_temp.check('the queue follows the item',
  (select count(*) = 1 from (
     select 1 from public.guard_item_reviews r
     cross join lateral public.guard_item_text(r.item_type, r.item_id) t
     where r.state = 'flagged') x));
update public.notes set deleted_at = now() where id = (select id from ids where name = 'note');
select pg_temp.act_as('b');
select pg_temp.check('a deleted note leaves the queue',
  (select count(*) = 0 from public.list_guard_item_reviews((select id from ids where name = 'circle')))
  and public.count_guard_item_reviews((select id from ids where name = 'circle')) = 0);
select pg_temp.act_as(null);
update public.notes set deleted_at = null where id = (select id from ids where name = 'note');

select pg_temp.act_as('b');
select pg_temp.check('a moderator dismisses the card',
  public.dismiss_guard_item_review(
    (select id from ids where name = 'note_review')) = 'dismissed');
select pg_temp.refused('and it is closed for good',
  format('select public.dismiss_guard_item_review(%L)',
    (select id from ids where name = 'note_review')), 'P0002');
select pg_temp.act_as(null);
select pg_temp.check('the dismissal is audited',
  exists (select 1 from public.circle_audit_log
          where action = 'guard_item_dismiss' and actor_id = '00000000-0000-4000-8000-0000000000b1'));

-- Editing again checks again, but not within a minute.
select pg_temp.act_as('c');
select public.update_note_meta((select id from ids where name = 'note'), '{"title": "Another prize"}'::jsonb);
select pg_temp.act_as(null);
select pg_temp.check('an edit within a minute of the last check does not start another',
  (select r.state = 'dismissed' from public.guard_item_reviews r where r.item_id = (select id from ids where name = 'note')));
update public.guard_item_reviews set created_at = now() - interval '2 minutes'
where item_id = (select id from ids where name = 'note');
select pg_temp.act_as('c');
select public.update_note_meta((select id from ids where name = 'note'), '{"title": "Yet another prize"}'::jsonb);
select pg_temp.act_as(null);
select pg_temp.check('an edit after a minute does',
  (select r.state = 'checking' and r.verdict is null and r.decided_at is null
   from public.guard_item_reviews r where r.item_id = (select id from ids where name = 'note')));

-- A note that is gone by the time the function looks ends the check.
update public.notes set deleted_at = now() where id = (select id from ids where name = 'note');
select pg_temp.check('the claim of a deleted item gets nothing',
  (select count(*) = 0 from public.ai_guard_item_claim(
     (select id from ids where name = 'note_review'))));
select pg_temp.check('and ends the check',
  (select r.state = 'released' and r.unchecked_reason = 'gone'
   from public.guard_item_reviews r where r.item_id = (select id from ids where name = 'note')));

-- The sweep ends checks that never came back, and tidies.
update public.guard_item_reviews set created_at = now() - interval '2 minutes'
where item_type = 'circle_event';
select public.run_ai_guard_item_sweep();
select pg_temp.check('the sweep releases a check that never came back',
  (select r.state = 'released' and r.unchecked_reason = 'timeout'
   from public.guard_item_reviews r where r.item_type = 'circle_event'));
update public.guard_item_reviews set checked_at = now() - interval '4 days' where state = 'released';
select public.run_ai_guard_item_sweep();
select pg_temp.check('old released rows are tidied',
  not exists (select 1 from public.guard_item_reviews where state = 'released'));

-- A person's items are not checked without end: ten in ten minutes.
delete from public.guard_item_reviews where actor_id = '00000000-0000-4000-8000-0000000000c1';
select pg_temp.act_as('c');
select public.create_note((select id from ids where name = 'channel'), 'Bulk ' || n)
from generate_series(1, 14) n;
select pg_temp.act_as(null);
select pg_temp.check('only the first ten items of a burst are checked',
  (select count(*) = 10 from public.guard_item_reviews
   where actor_id = '00000000-0000-4000-8000-0000000000c1'));
delete from public.guard_item_reviews where actor_id = '00000000-0000-4000-8000-0000000000c1';

-- Items can be left out of the scope, and need the circle's AI.
select pg_temp.act_as('a');
select public.set_circle_ai_guard_scope((select id from ids where name = 'circle'), true, false, true);
select pg_temp.act_as('c');
insert into ids select 'note_scope_off', (public.create_note((select id from ids where name = 'channel'), 'Prize again')->>'id')::uuid;
select pg_temp.act_as(null);
select pg_temp.check('with titles left out of the scope nothing is recorded',
  not exists (select 1 from public.guard_item_reviews where item_id = (select id from ids where name = 'note_scope_off')));
select pg_temp.act_as('a');
select public.set_circle_ai_guard_scope((select id from ids where name = 'circle'), true, true, true);
select pg_temp.act_as(null);
update public.circles set ai_enabled = false where id = (select id from ids where name = 'circle');
select pg_temp.act_as('c');
insert into ids select 'note_ai_off', (public.create_note((select id from ids where name = 'channel'), 'Prize third')->>'id')::uuid;
select pg_temp.act_as(null);
select pg_temp.check('with the circle''s AI off nothing is recorded',
  not exists (select 1 from public.guard_item_reviews where item_id = (select id from ids where name = 'note_ai_off')));
update public.circles set ai_enabled = true where id = (select id from ids where name = 'circle');

-- Nothing is recorded outside circles or without a signed-in person.
select pg_temp.act_as(null);
select pg_temp.claim_as(null);
insert into public.notes (conversation_id, title, created_by)
values ((select id from ids where name = 'channel'), 'Server made', '00000000-0000-4000-8000-0000000000c1')
returning id \gset server_note_
select pg_temp.check('a row written without a signed-in person is left alone',
  not exists (select 1 from public.guard_item_reviews where item_id = :'server_note_id'));

-- The sweep has its own cron job and the dispatcher is not involved.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if not exists (select 1 from cron.job where jobname = 'wecord-ai-guard-item-sweep') then
      raise exception 'FAILED: the item sweep is not scheduled';
    end if;
    if exists (select 1 from cron.job where jobname = 'wecord-ai-guard-item-sweep' and command like '%run_later_dispatch%') then
      raise exception 'FAILED: the item sweep must not run through the dispatcher';
    end if;
    raise notice 'ok: the item sweep has its own cron job';
  else
    raise notice 'skipped: pg_cron is not installed here';
  end if;
end;
$$;

rollback;
