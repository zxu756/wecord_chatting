-- Behaviour checks for forms and collection sheets (migrations 202610230100,
-- 202610230110, 202610230120 and 202610230130). Run by
-- test/supabase/forms_test.dart against the local database: it applies every
-- migration the database lacks (the local baseline is 202610170001) inside a
-- transaction, acts as several people, and rolls back, so the database is
-- left as it was. Run from the repository root.
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


create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create temp table failures (message text);
grant all on failures to public;

-- Ada makes the forms. Bob, Cy and Eve answer them. Dan is outside every
-- chat. Mo joins the circle just now (the AI guard treats him as new).
insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@forms.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@forms.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@forms.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d1', 'dan@forms.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve@forms.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000f1', 'mo@forms.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_forms', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_forms', 'Bob'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_forms', 'Cy'),
  ('00000000-0000-4000-8000-0000000000d1', 'dan_forms', 'Dan'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve_forms', 'Eve'),
  ('00000000-0000-4000-8000-0000000000f1', 'mo_forms', 'Mo');

create function pg_temp.as_user(uid text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', uid, true);
$$;

create function pg_temp.fail(msg text) returns void language sql as $$
  insert into failures values (msg);
$$;

-- Runs [stmt] and records a failure unless it raised with [code] (and, when
-- given, the message [text_wanted]).
create function pg_temp.refused(label text, stmt text, code text, text_wanted text default null)
returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    if sqlstate <> code or (text_wanted is not null and sqlerrm <> text_wanted) then
      insert into failures values (format('%s: wanted %s %s, got %s %s', label, code, coalesce(text_wanted, ''), sqlstate, sqlerrm));
    end if;
    return;
  end;
  insert into failures values (label || ': nothing was refused');
end;
$$;

-- The questions of the main form: one of each of the 8 types.
create function pg_temp.fields() returns jsonb language sql as $$
  select jsonb_build_array(
    jsonb_build_object('id', 'name', 'type', 'short_text', 'label', 'Your name', 'required', true),
    jsonb_build_object('id', 'story', 'type', 'long_text', 'label', 'Anything to add?'),
    jsonb_build_object('id', 'age', 'type', 'number', 'label', 'Age', 'integer', true, 'min', 1, 'max', 120),
    jsonb_build_object('id', 'size', 'type', 'single_choice', 'label', 'T-shirt size', 'required', true,
      'options', jsonb_build_array(
        jsonb_build_object('id', 's', 'label', 'S'),
        jsonb_build_object('id', 'm', 'label', 'M'),
        jsonb_build_object('id', 'l', 'label', 'L'))),
    jsonb_build_object('id', 'food', 'type', 'multiple_choice', 'label', 'Food',
      'options', jsonb_build_array(
        jsonb_build_object('id', 'veg', 'label', 'Veg'),
        jsonb_build_object('id', 'fish', 'label', 'Fish'))),
    jsonb_build_object('id', 'day', 'type', 'date', 'label', 'Day'),
    jsonb_build_object('id', 'photo', 'type', 'image', 'label', 'A photo'),
    jsonb_build_object('id', 'buddy', 'type', 'member', 'label', 'Buddy')
  );
$$;

do $$
declare
  ada text := '00000000-0000-4000-8000-0000000000a1';
  bob text := '00000000-0000-4000-8000-0000000000b1';
  cy text := '00000000-0000-4000-8000-0000000000c1';
  eve text := '00000000-0000-4000-8000-0000000000e1';
begin
  with g as (
    insert into public.conversations (type, title) values ('group', 'Hike group') returning id
  )
  insert into ids select 'group', id from g;
  insert into public.conversation_members (conversation_id, user_id, role)
  select (select id from ids where name = 'group'), u.id::uuid, u.role
  from (values (ada, 'owner'), (bob, 'member'), (cy, 'member'), (eve, 'member')) as u(id, role);
  with d as (
    insert into public.conversations (type) values ('direct') returning id
  )
  insert into ids select 'direct', id from d;
  insert into public.conversation_members (conversation_id, user_id, role)
  select (select id from ids where name = 'direct'), u::uuid, 'member'
  from unnest(array[ada, bob]) u;
  with g as (
    insert into public.conversations (type, title) values ('group', 'Other group') returning id
  )
  insert into ids select 'other', id from g;
  insert into public.conversation_members (conversation_id, user_id, role)
  select (select id from ids where name = 'other'), u::uuid, 'owner'
  from unnest(array[bob]) u;
end $$;

do $$
declare
  ada text := '00000000-0000-4000-8000-0000000000a1';
  bob text := '00000000-0000-4000-8000-0000000000b1';
  cy text := '00000000-0000-4000-8000-0000000000c1';
  dan text := '00000000-0000-4000-8000-0000000000d1';
  eve text := '00000000-0000-4000-8000-0000000000e1';
  grp uuid := (select id from ids where name = 'group');
  dm uuid := (select id from ids where name = 'direct');
  other uuid := (select id from ids where name = 'other');
  made jsonb;
  the_form uuid;
  card uuid;
  got jsonb;
  res jsonb;
  photo_path text;
  n integer;
begin
  -- ------------------------------------------------------ where, who, what --
  perform pg_temp.as_user(ada);
  -- Not in a direct chat (and so not in the note to self).
  perform pg_temp.refused('a form in a direct chat',
    format('select public.create_form(%L, ''Hi'', null, pg_temp.fields(), null)', dm),
    '22023', 'form_not_allowed');
  perform pg_temp.as_user(dan);
  perform pg_temp.refused('Dan creating where he is no member',
    format('select public.create_form(%L, ''Hi'', null, pg_temp.fields(), null)', grp),
    'P0002', 'Conversation not found');

  perform pg_temp.as_user(ada);
  perform pg_temp.refused('no title',
    format('select public.create_form(%L, ''  '', null, pg_temp.fields(), null)', grp),
    '22023', 'form_title_invalid');
  perform pg_temp.refused('no questions',
    format('select public.create_form(%L, ''T'', null, ''[]''::jsonb, null)', grp),
    '22023', 'form_fields_invalid');
  perform pg_temp.refused('an unknown type',
    format($q$select public.create_form(%L, 'T', null, '[{"id":"a","type":"video","label":"x"}]'::jsonb, null)$q$, grp),
    '22023', 'form_fields_invalid');
  perform pg_temp.refused('two questions with one id',
    format($q$select public.create_form(%L, 'T', null, '[{"id":"a","type":"short_text","label":"x"},{"id":"a","type":"date","label":"y"}]'::jsonb, null)$q$, grp),
    '22023', 'form_fields_invalid');
  perform pg_temp.refused('a choice with one option',
    format($q$select public.create_form(%L, 'T', null, '[{"id":"a","type":"single_choice","label":"x","options":[{"id":"o","label":"O"}]}]'::jsonb, null)$q$, grp),
    '22023', 'form_fields_invalid');
  perform pg_temp.refused('a number range backwards',
    format($q$select public.create_form(%L, 'T', null, '[{"id":"a","type":"number","label":"x","min":5,"max":1}]'::jsonb, null)$q$, grp),
    '22023', 'form_fields_invalid');
  perform pg_temp.refused('a bad results setting',
    format($q$select public.create_form(%L, 'T', null, pg_temp.fields(), '{"results":"nobody"}'::jsonb)$q$, grp),
    '22023', 'form_settings_invalid');
  perform pg_temp.refused('a deadline in the past',
    format($q$select public.create_form(%L, 'T', null, pg_temp.fields(), jsonb_build_object('deadline', (now() - interval '1 day')::text))$q$, grp),
    '22023', 'form_deadline_invalid');
  perform pg_temp.refused('a cap of zero',
    format($q$select public.create_form(%L, 'T', null, pg_temp.fields(), '{"max_responses":0}'::jsonb)$q$, grp),
    '22023', 'form_max_invalid');

  -- -------------------------------------------------------- the main form --
  made := public.create_form(
    grp, '  Hike sign-up  ', 'Bring water.', pg_temp.fields(),
    jsonb_build_object('deadline', (now() + interval '2 days')::text, 'max_responses', 2)
  );
  the_form := (made->>'form_id')::uuid;
  card := (made->>'message_id')::uuid;
  insert into ids values ('form', the_form), ('card', card);
  if (select title from public.forms where id = the_form) <> 'Hike sign-up' then
    perform pg_temp.fail('the title was not trimmed');
  end if;
  if (select jsonb_array_length(fields) from public.forms where id = the_form) <> 8 then
    perform pg_temp.fail('the form did not keep its 8 questions');
  end if;
  if (select settings->>'one_per_person' from public.forms where id = the_form) <> 'true'
    or (select settings->>'editable' from public.forms where id = the_form) <> 'true'
    or (select settings->>'results' from public.forms where id = the_form) <> 'creator'
    or (select settings->>'anonymous' from public.forms where id = the_form) <> 'false'
  then
    perform pg_temp.fail('the settings were not filled in with defaults');
  end if;
  if not exists (
    select 1 from public.messages m
    where m.id = card and m.conversation_id = grp and m.sender_id = ada::uuid
      and m.attachment->>'kind' = 'form' and m.attachment->>'form_id' = the_form::text
      and m.body = E'\U0001F4DD Hike sign-up'
  ) then
    perform pg_temp.fail('the card message is not there');
  end if;

  -- Reading: members see the form; strangers do not.
  perform pg_temp.as_user(bob);
  got := public.get_form(the_form);
  if got->>'title' <> 'Hike sign-up' or (got->>'can_manage')::boolean
    or (got->>'can_view_results')::boolean or got->>'creator_name' <> 'Ada'
    or got->'my_response' <> 'null'::jsonb
  then
    perform pg_temp.fail('get_form for a member: ' || got::text);
  end if;
  if jsonb_array_length(public.get_forms(array[the_form, gen_random_uuid()])) <> 1 then
    perform pg_temp.fail('get_forms did not answer for exactly the form it can see');
  end if;
  perform pg_temp.as_user(dan);
  perform pg_temp.refused('Dan reading the form',
    format('select public.get_form(%L)', the_form), 'P0002', 'Form not found');
  if jsonb_array_length(public.get_forms(array[the_form])) <> 0 then
    perform pg_temp.fail('get_forms answered for a stranger');
  end if;
  perform pg_temp.refused('Dan answering',
    format($q$select public.submit_form_response(%L, '{}'::jsonb)$q$, the_form),
    'P0002', 'Form not found');

  -- ------------------------------------------------------------- answers --
  perform pg_temp.as_user(bob);
  photo_path := grp::text || '/forms/' || the_form::text || '/pic-1.jpg';
  perform pg_temp.refused('a missing required answer',
    format($q$select public.submit_form_response(%L, '{"size":"m"}'::jsonb)$q$, the_form),
    '22023', 'form_answer_required');
  perform pg_temp.refused('a size that is no option',
    format($q$select public.submit_form_response(%L, '{"name":"Bob","size":"xl"}'::jsonb)$q$, the_form),
    '22023', 'form_answer_invalid');
  perform pg_temp.refused('an unknown question',
    format($q$select public.submit_form_response(%L, '{"name":"Bob","size":"m","other":"x"}'::jsonb)$q$, the_form),
    '22023', 'form_unknown_field');
  perform pg_temp.refused('a number out of range',
    format($q$select public.submit_form_response(%L, '{"name":"Bob","size":"m","age":200}'::jsonb)$q$, the_form),
    '22023', 'form_answer_invalid');
  perform pg_temp.refused('a fraction for an integer',
    format($q$select public.submit_form_response(%L, '{"name":"Bob","size":"m","age":3.5}'::jsonb)$q$, the_form),
    '22023', 'form_answer_invalid');
  perform pg_temp.refused('a number as text',
    format($q$select public.submit_form_response(%L, '{"name":"Bob","size":"m","age":"30"}'::jsonb)$q$, the_form),
    '22023', 'form_answer_invalid');
  perform pg_temp.refused('a date that does not exist',
    format($q$select public.submit_form_response(%L, '{"name":"Bob","size":"m","day":"2026-02-31"}'::jsonb)$q$, the_form),
    '22023', 'form_answer_invalid');
  perform pg_temp.refused('a food that is no option',
    format($q$select public.submit_form_response(%L, '{"name":"Bob","size":"m","food":["veg","beef"]}'::jsonb)$q$, the_form),
    '22023', 'form_answer_invalid');
  perform pg_temp.refused('a food twice',
    format($q$select public.submit_form_response(%L, '{"name":"Bob","size":"m","food":["veg","veg"]}'::jsonb)$q$, the_form),
    '22023', 'form_answer_invalid');
  perform pg_temp.refused('a buddy outside the chat',
    format($q$select public.submit_form_response(%L, jsonb_build_object('name','Bob','size','m','buddy', %L))$q$, the_form, dan),
    '22023', 'form_answer_invalid');
  perform pg_temp.refused('a short text that is too long',
    format($q$select public.submit_form_response(%L, jsonb_build_object('name', repeat('x', 201), 'size', 'm'))$q$, the_form),
    '22023', 'form_answer_invalid');

  -- Pictures: a file of this form's folder that the caller uploaded.
  perform pg_temp.refused('a picture that was never uploaded',
    format($q$select public.submit_form_response(%L, jsonb_build_object('name','Bob','size','m','photo', jsonb_build_object('bucket','chat-images','path', %L)))$q$, the_form, photo_path),
    '22023', 'form_answer_invalid');
  insert into storage.objects (bucket_id, name, owner, owner_id)
  values ('chat-images', photo_path, bob::uuid, bob);
  insert into storage.objects (bucket_id, name, owner, owner_id)
  values
    ('chat-images', other::text || '/forms/' || the_form::text || '/pic-2.jpg', bob::uuid, bob),
    ('chat-images', grp::text || '/forms/' || the_form::text || '/pic-3.jpg', cy::uuid, cy),
    ('chat-images', grp::text || '/pic-4.jpg', bob::uuid, bob),
    ('chat-files', grp::text || '/forms/' || the_form::text || '/pic-5.jpg', bob::uuid, bob);
  perform pg_temp.refused('a picture of another chat''s folder',
    format($q$select public.submit_form_response(%L, jsonb_build_object('name','Bob','size','m','photo', jsonb_build_object('bucket','chat-images','path', %L)))$q$, the_form, other::text || '/forms/' || the_form::text || '/pic-2.jpg'),
    '22023', 'form_answer_invalid');
  perform pg_temp.refused('somebody else''s picture',
    format($q$select public.submit_form_response(%L, jsonb_build_object('name','Bob','size','m','photo', jsonb_build_object('bucket','chat-images','path', %L)))$q$, the_form, grp::text || '/forms/' || the_form::text || '/pic-3.jpg'),
    '22023', 'form_answer_invalid');
  perform pg_temp.refused('a picture outside the form''s folder',
    format($q$select public.submit_form_response(%L, jsonb_build_object('name','Bob','size','m','photo', jsonb_build_object('bucket','chat-images','path', %L)))$q$, the_form, grp::text || '/pic-4.jpg'),
    '22023', 'form_answer_invalid');
  perform pg_temp.refused('a picture in the wrong bucket',
    format($q$select public.submit_form_response(%L, jsonb_build_object('name','Bob','size','m','photo', jsonb_build_object('bucket','chat-files','path', %L)))$q$, the_form, grp::text || '/forms/' || the_form::text || '/pic-5.jpg'),
    '22023', 'form_answer_invalid');
  perform pg_temp.refused('a path that climbs out',
    format($q$select public.submit_form_response(%L, jsonb_build_object('name','Bob','size','m','photo', jsonb_build_object('bucket','chat-images','path', %L)))$q$, the_form, grp::text || '/forms/' || the_form::text || '/../x.jpg'),
    '22023', 'form_answer_invalid');

  -- A good sheet with all 8 types.
  res := public.submit_form_response(the_form, jsonb_build_object(
    'name', '  Bob  ', 'story', 'Ready!', 'age', 31, 'size', 'm',
    'food', jsonb_build_array('veg', 'fish'), 'day', '2026-11-02',
    'photo', jsonb_build_object('bucket', 'chat-images', 'path', photo_path, 'junk', 1),
    'buddy', upper(cy), 'empty', null
  ) - 'empty');
  if (res->>'updated')::boolean or (res->>'text_held')::boolean then
    perform pg_temp.fail('a first answer: ' || res::text);
  end if;
  got := (select answers from public.form_responses where id = (res->>'response_id')::uuid);
  if got->>'name' <> 'Bob' or (got->>'age')::int <> 31 or got->>'size' <> 'm'
    or got->'food' <> '["veg","fish"]'::jsonb or got->>'day' <> '2026-11-02'
    or got->'photo' <> jsonb_build_object('bucket', 'chat-images', 'path', photo_path)
    or got->>'buddy' <> cy
  then
    perform pg_temp.fail('the cleaned answers: ' || got::text);
  end if;
  if (select response_count from public.forms where id = the_form) <> 1 then
    perform pg_temp.fail('the response count did not follow');
  end if;
  got := public.get_form(the_form);
  if got->'my_response'->'answers'->>'name' <> 'Bob' or (got->>'response_count')::int <> 1 then
    perform pg_temp.fail('get_form does not show my answer: ' || got::text);
  end if;

  -- One sheet per person; editing is allowed (the default).
  res := public.submit_form_response(the_form, '{"name":"Bobby","size":"l"}'::jsonb);
  if not (res->>'updated')::boolean
    or (select count(*) from public.form_responses r where r.form_id = the_form and r.user_id = bob::uuid) <> 1
  then
    perform pg_temp.fail('editing made a second sheet');
  end if;
end $$;

-- ------------------------------------------- caps, deadline, one per person --
do $$
declare
  ada text := '00000000-0000-4000-8000-0000000000a1';
  bob text := '00000000-0000-4000-8000-0000000000b1';
  cy text := '00000000-0000-4000-8000-0000000000c1';
  eve text := '00000000-0000-4000-8000-0000000000e1';
  grp uuid := (select id from ids where name = 'group');
  the_form uuid := (select id from ids where name = 'form');
  made jsonb;
  f2 uuid;
  f3 uuid;
  res jsonb;
begin
  -- The main form takes two answers (max_responses = 2): Bob has one.
  perform pg_temp.as_user(cy);
  perform public.submit_form_response(the_form, '{"name":"Cyrus-secret","size":"s"}'::jsonb);
  perform pg_temp.as_user(eve);
  perform pg_temp.refused('an answer over the cap',
    format($q$select public.submit_form_response(%L, '{"name":"Eve","size":"s"}'::jsonb)$q$, the_form),
    'P0001', 'form_full');
  -- Somebody who already answered may still edit at the cap.
  perform pg_temp.as_user(cy);
  res := public.submit_form_response(the_form, '{"name":"Cyrus-secret","size":"m"}'::jsonb);
  if not (res->>'updated')::boolean then
    perform pg_temp.fail('an edit at the cap was refused');
  end if;

  -- The deadline passes: closed for everybody.
  update public.forms
  set settings = settings || jsonb_build_object('deadline', (now() - interval '1 minute')::text)
  where id = the_form;
  perform pg_temp.as_user(cy);
  perform pg_temp.refused('an answer after the deadline',
    format($q$select public.submit_form_response(%L, '{"name":"Cy","size":"m"}'::jsonb)$q$, the_form),
    'P0001', 'form_closed');
  if not (public.get_form(the_form)->>'closed')::boolean then
    perform pg_temp.fail('a form past its deadline is not closed');
  end if;
  update public.forms
  set settings = settings || jsonb_build_object('deadline', (now() + interval '2 days')::text)
  where id = the_form;
  perform public.submit_form_response(the_form, '{"name":"Cyrus-secret","size":"l"}'::jsonb);

  -- One answer per person and no editing.
  perform pg_temp.as_user(ada);
  made := public.create_form(grp, 'Once only', null, pg_temp.fields(),
    '{"editable": false}'::jsonb);
  f2 := (made->>'form_id')::uuid;
  insert into ids values ('once', f2);
  perform pg_temp.as_user(bob);
  perform public.submit_form_response(f2, '{"name":"Bob","size":"s"}'::jsonb);
  perform pg_temp.refused('an edit of a form that cannot be edited',
    format($q$select public.submit_form_response(%L, '{"name":"Bob","size":"m"}'::jsonb)$q$, f2),
    '23505', 'form_already_submitted');

  -- Without one-per-person a person sends as many sheets as they like.
  perform pg_temp.as_user(ada);
  made := public.create_form(grp, 'As many as you like', null, pg_temp.fields(),
    '{"one_per_person": false, "editable": true}'::jsonb);
  f3 := (made->>'form_id')::uuid;
  insert into ids values ('many', f3);
  if (select settings->>'editable' from public.forms where id = f3) <> 'false' then
    perform pg_temp.fail('editing stayed on without one-per-person');
  end if;
  perform pg_temp.as_user(bob);
  perform public.submit_form_response(f3, '{"name":"Bob","size":"s"}'::jsonb);
  perform public.submit_form_response(f3, '{"name":"Bob","size":"m"}'::jsonb);
  if (select count(*) from public.form_responses r where r.form_id = f3) <> 2
    or (public.get_form(f3)->>'my_response_count')::int <> 2
  then
    perform pg_temp.fail('two sheets by one person were not both kept');
  end if;
end $$;

-- ------------------------------------------------ who may read the results --
do $$
declare
  ada text := '00000000-0000-4000-8000-0000000000a1';
  bob text := '00000000-0000-4000-8000-0000000000b1';
  cy text := '00000000-0000-4000-8000-0000000000c1';
  dan text := '00000000-0000-4000-8000-0000000000d1';
  eve text := '00000000-0000-4000-8000-0000000000e1';
  the_form uuid := (select id from ids where name = 'form');
  res jsonb;
begin
  perform pg_temp.as_user(bob);
  perform pg_temp.refused('Bob reading creator-only results',
    format('select public.get_form_results(%L)', the_form), '42501', 'form_results_hidden');

  perform pg_temp.as_user(ada);
  res := public.get_form_results(the_form);
  if jsonb_array_length(res->'responses') <> 2
    or not (res->'responses'->0 ? 'user_id')
    or res->'responses'->0->>'user_id' <> bob
    or (res->>'anonymous')::boolean
  then
    perform pg_temp.fail('the creator does not see who answered: ' || res::text);
  end if;
  -- Bob picked Cy as his buddy in the first sheet; the edit dropped it.
  if res->'people' ? cy is not true or res->'people' ? bob is not true then
    perform pg_temp.fail('the results do not name the people: ' || (res->'people')::text);
  end if;
  -- Unfilled: Eve only (not Ada the creator, not Dan who is outside).
  if res->'unfilled' is null or jsonb_array_length(res->'unfilled') <> 1
    or res->'unfilled'->0->>'user_id' <> eve
  then
    perform pg_temp.fail('the unfilled list: ' || coalesce((res->'unfilled')::text, 'null'));
  end if;
  if (res->>'member_total')::int <> 4 then
    perform pg_temp.fail('member_total ' || (res->>'member_total'));
  end if;

  -- after_submit: those who answered.
  update public.forms set settings = settings || '{"results":"after_submit"}' where id = the_form;
  perform pg_temp.as_user(bob);
  res := public.get_form_results(the_form);
  if jsonb_array_length(res->'responses') <> 2 or res->'unfilled' <> 'null'::jsonb then
    perform pg_temp.fail('after_submit results for an answerer: ' || res::text);
  end if;
  if not (public.get_form(the_form)->>'can_view_results')::boolean then
    perform pg_temp.fail('can_view_results is false for an answerer');
  end if;
  perform pg_temp.as_user(eve);
  perform pg_temp.refused('Eve reading after_submit results before answering',
    format('select public.get_form_results(%L)', the_form), '42501', 'form_results_hidden');

  -- everyone.
  update public.forms set settings = settings || '{"results":"everyone"}' where id = the_form;
  res := public.get_form_results(the_form);
  if jsonb_array_length(res->'responses') <> 2 then
    perform pg_temp.fail('everyone-results for Eve');
  end if;
  perform pg_temp.as_user(dan);
  perform pg_temp.refused('Dan reading everyone-results',
    format('select public.get_form_results(%L)', the_form), 'P0002', 'Form not found');
  update public.forms set settings = settings || '{"results":"creator"}' where id = the_form;
end $$;

-- --------------------------------------------------------------- anonymous --
do $$
declare
  ada text := '00000000-0000-4000-8000-0000000000a1';
  bob text := '00000000-0000-4000-8000-0000000000b1';
  cy text := '00000000-0000-4000-8000-0000000000c1';
  eve text := '00000000-0000-4000-8000-0000000000e1';
  grp uuid := (select id from ids where name = 'group');
  anon uuid;
  made jsonb;
  res jsonb;
  seen text;
  n integer;
begin
  perform pg_temp.as_user(ada);
  made := public.create_form(grp, 'Honest feedback', null,
    '[{"id":"say","type":"long_text","label":"What would you change?","required":true},
      {"id":"who","type":"member","label":"Who helped most?"}]'::jsonb,
    '{"anonymous": true, "results": "creator"}'::jsonb);
  anon := (made->>'form_id')::uuid;
  insert into ids values ('anon', anon);
  perform pg_temp.as_user(bob);
  perform public.submit_form_response(anon, jsonb_build_object('say', 'More snacks', 'who', cy));
  perform pg_temp.as_user(cy);
  perform public.submit_form_response(anon, '{"say":"Earlier start"}'::jsonb);

  perform pg_temp.as_user(ada);
  res := public.get_form_results(anon);
  if not (res->>'anonymous')::boolean or jsonb_array_length(res->'responses') <> 2 then
    perform pg_temp.fail('the anonymous results: ' || res::text);
  end if;
  if exists (
    select 1
    from jsonb_array_elements(res->'responses') r, jsonb_object_keys(r) k
    where k not in ('id', 'answers')
  ) then
    perform pg_temp.fail('an anonymous response carries more than id and answers: ' || res::text);
  end if;
  -- Nobody who answered appears anywhere in what the creator gets, except
  -- Cy, who was picked as the one who helped most.
  seen := res::text || public.get_form(anon)::text;
  if seen like '%' || bob || '%' then
    perform pg_temp.fail('Bob''s id is in the creator''s anonymous results');
  end if;
  if res->'unfilled' <> 'null'::jsonb then
    perform pg_temp.fail('an anonymous form lists who has not answered');
  end if;
  if res->'people' ? cy is not true or res->'people' ? bob then
    perform pg_temp.fail('people of an anonymous form: ' || (res->'people')::text);
  end if;

  -- The table lets Ada read nothing of other people's sheets, not even by
  -- asking directly; each person reads their own.
  reset role;
  perform set_config('request.jwt.claim.sub', ada, true);
  execute 'set local role authenticated';
  select count(*) into n from public.form_responses;
  if n <> 0 then perform pg_temp.fail('Ada reads ' || n || ' response rows'); end if;
  reset role;
  perform set_config('request.jwt.claim.sub', bob, true);
  execute 'set local role authenticated';
  select count(*) into n from public.form_responses where form_id = anon;
  if n <> 1 then perform pg_temp.fail('Bob reads ' || n || ' of his own rows'); end if;
  select count(*) into n from public.form_responses where user_id <> bob::uuid;
  if n <> 0 then perform pg_temp.fail('Bob reads other people''s rows'); end if;
  reset role;

  -- Bob may still change his own sheet; the creator cannot tell whose it is.
  perform pg_temp.as_user(bob);
  if not (public.submit_form_response(anon, '{"say":"Even more snacks"}'::jsonb)->>'updated')::boolean then
    perform pg_temp.fail('editing an anonymous sheet');
  end if;

  -- Reminding an anonymous form: only the number comes back (Eve).
  perform pg_temp.as_user(ada);
  if public.remind_form_unfilled(anon) <> 1 then
    perform pg_temp.fail('reminding an anonymous form');
  end if;
end $$;

-- ------------------------------------------------------- close and reopen --
do $$
declare
  ada text := '00000000-0000-4000-8000-0000000000a1';
  bob text := '00000000-0000-4000-8000-0000000000b1';
  eve text := '00000000-0000-4000-8000-0000000000e1';
  grp uuid := (select id from ids where name = 'group');
  f4 uuid;
  made jsonb;
begin
  perform pg_temp.as_user(ada);
  made := public.create_form(grp, 'Lunch', null,
    '[{"id":"pick","type":"single_choice","label":"Pick","options":[{"id":"a","label":"A"},{"id":"b","label":"B"}]}]'::jsonb,
    jsonb_build_object('deadline', (now() + interval '1 day')::text));
  f4 := (made->>'form_id')::uuid;
  insert into ids values ('lunch', f4);

  perform pg_temp.as_user(bob);
  perform pg_temp.refused('Bob closing a form',
    format('select public.set_form_closed(%L, true)', f4), '42501');
  perform pg_temp.as_user(ada);
  perform public.set_form_closed(f4, true);
  perform pg_temp.as_user(bob);
  if not (public.get_form(f4)->>'closed')::boolean then
    perform pg_temp.fail('a closed form is not closed');
  end if;
  perform pg_temp.refused('an answer to a closed form',
    format($q$select public.submit_form_response(%L, '{"pick":"a"}'::jsonb)$q$, f4),
    'P0001', 'form_closed');
  perform pg_temp.as_user(ada);
  perform pg_temp.refused('a reminder for a closed form',
    format('select public.remind_form_unfilled(%L)', f4), 'P0001', 'form_closed');

  -- Reopening drops a deadline that has passed, and answers work again.
  update public.forms set settings = settings || jsonb_build_object('deadline', (now() - interval '1 hour')::text) where id = f4;
  perform public.set_form_closed(f4, false);
  if (select settings ? 'deadline' from public.forms where id = f4) then
    perform pg_temp.fail('reopening kept a deadline that has passed');
  end if;
  perform pg_temp.as_user(bob);
  perform public.submit_form_response(f4, '{"pick":"b"}'::jsonb);
  if (public.get_form(f4)->>'closed')::boolean then
    perform pg_temp.fail('a reopened form is closed');
  end if;
end $$;

-- ------------------------------------------------------------------ remind --
do $$
declare
  ada text := '00000000-0000-4000-8000-0000000000a1';
  bob text := '00000000-0000-4000-8000-0000000000b1';
  cy text := '00000000-0000-4000-8000-0000000000c1';
  eve text := '00000000-0000-4000-8000-0000000000e1';
  grp uuid := (select id from ids where name = 'group');
  f5 uuid;
  card5 uuid;
  made jsonb;
  n integer;
begin
  perform pg_temp.as_user(ada);
  made := public.create_form(grp, 'Shirt sizes', null,
    '[{"id":"size","type":"short_text","label":"Size","required":true}]'::jsonb, null);
  f5 := (made->>'form_id')::uuid;
  card5 := (made->>'message_id')::uuid;
  insert into ids values ('shirts', f5), ('shirts-card', card5);
  perform pg_temp.as_user(bob);
  perform public.submit_form_response(f5, '{"size":"M"}'::jsonb);

  perform pg_temp.refused('Bob reminding for Ada''s form',
    format('select public.remind_form_unfilled(%L)', f5), '42501');
  perform pg_temp.as_user(ada);
  -- Cy and Eve have not answered (Bob has, Ada made it, Dan is outside).
  if public.remind_form_unfilled(f5) <> 2 then
    perform pg_temp.fail('the first reminder did not reach the 2 people');
  end if;
  if (select count(*) from public.read_reminder_notices where message_id = card5) <> 2
    or exists (select 1 from public.read_reminder_notices where message_id = card5 and recipient_id in (bob::uuid, ada::uuid))
  then
    perform pg_temp.fail('the reminder notices are not for Cy and Eve');
  end if;
  perform pg_temp.refused('a second reminder at once',
    format('select public.remind_form_unfilled(%L)', f5), 'P0001', 'remind_too_soon');

  -- Eve has read past the card: the reminder still stands while she has not
  -- answered, and goes when she does.
  update public.conversation_members set last_read_message_id = card5
  where conversation_id = grp and user_id = eve::uuid;
  perform pg_temp.as_user(eve);
  select count(*) into n from public.list_read_reminder_notices() where message_id = card5;
  if n <> 1 then perform pg_temp.fail('Eve''s reminder card is gone after reading: ' || n); end if;
  perform public.submit_form_response(f5, '{"size":"S"}'::jsonb);
  select count(*) into n from public.list_read_reminder_notices() where message_id = card5;
  if n <> 0 then perform pg_temp.fail('Eve''s reminder card stays after answering: ' || n); end if;
  perform pg_temp.as_user(cy);
  select count(*) into n from public.list_read_reminder_notices() where message_id = card5;
  if n <> 1 then perform pg_temp.fail('Cy''s reminder card is missing: ' || n); end if;

  -- Three reminders at most, six hours apart.
  update public.form_reminders set created_at = now() - interval '7 hours' where form_id = f5;
  perform pg_temp.as_user(ada);
  if public.remind_form_unfilled(f5) <> 1 then
    perform pg_temp.fail('the second reminder (after 6 hours) did not reach Cy only');
  end if;
  update public.form_reminders set created_at = now() - interval '7 hours' where form_id = f5;
  perform public.remind_form_unfilled(f5);
  update public.form_reminders set created_at = now() - interval '7 hours' where form_id = f5;
  perform pg_temp.refused('a fourth reminder',
    format('select public.remind_form_unfilled(%L)', f5), 'P0001', 'remind_limit');

  -- When everybody answered there is nobody to remind.
  perform pg_temp.as_user(cy);
  perform public.submit_form_response(f5, '{"size":"L"}'::jsonb);
  perform pg_temp.as_user(ada);
  delete from public.form_reminders where form_id = f5;
  perform pg_temp.refused('a reminder with nobody to remind',
    format('select public.remind_form_unfilled(%L)', f5), 'P0001', 'nobody_to_remind');
end $$;

-- ------------------------------------------------------- tables and grants --
do $$
declare
  ada text := '00000000-0000-4000-8000-0000000000a1';
  cy text := '00000000-0000-4000-8000-0000000000c1';
  dan text := '00000000-0000-4000-8000-0000000000d1';
  grp uuid := (select id from ids where name = 'group');
  the_form uuid := (select id from ids where name = 'form');
  n integer;
begin
  reset role;
  perform set_config('request.jwt.claim.sub', cy, true);
  execute 'set local role authenticated';
  begin
    insert into public.forms (conversation_id, creator_id, title, fields)
    values (grp, cy::uuid, 'sneaky', '[]'::jsonb);
    perform pg_temp.fail('a direct insert into forms');
  exception when insufficient_privilege then null; end;
  begin
    insert into public.form_responses (form_id, user_id, answers)
    values (the_form, cy::uuid, '{}'::jsonb);
    perform pg_temp.fail('a direct insert into form_responses');
  exception when insufficient_privilege then null; end;
  begin
    update public.forms set title = 'hacked' where id = the_form;
    perform pg_temp.fail('a direct update of forms');
  exception when insufficient_privilege then null; end;
  begin
    update public.form_responses set answers = '{}'::jsonb;
    perform pg_temp.fail('a direct update of form_responses');
  exception when insufficient_privilege then null; end;
  begin
    perform 1 from public.form_reminders;
    perform pg_temp.fail('form_reminders is readable');
  exception when insufficient_privilege then null; end;
  select count(*) into n from public.forms;
  if n < 4 then perform pg_temp.fail('Cy cannot select her forms ' || n); end if;
  select count(*) into n from public.form_responses where user_id <> cy::uuid;
  if n <> 0 then perform pg_temp.fail('Cy reads other people''s answers'); end if;
  reset role;

  perform set_config('request.jwt.claim.sub', dan, true);
  execute 'set local role authenticated';
  select count(*) into n from public.forms;
  if n <> 0 then perform pg_temp.fail('Dan sees ' || n || ' forms'); end if;
  select count(*) into n from public.form_responses;
  if n <> 0 then perform pg_temp.fail('Dan sees ' || n || ' responses'); end if;
  reset role;

  -- Only signed-in people may call the functions.
  if has_function_privilege('anon', 'public.create_form(uuid,text,text,jsonb,jsonb)', 'execute')
    or has_function_privilege('anon', 'public.submit_form_response(uuid,jsonb)', 'execute')
    or has_function_privilege('anon', 'public.get_form_results(uuid)', 'execute')
    or has_function_privilege('authenticated', 'public.export_my_forms(uuid)', 'execute')
    or has_function_privilege('authenticated', 'public.form_clean_answers(public.forms,jsonb,uuid)', 'execute')
  then
    perform pg_temp.fail('a form function is open to people who must not call it');
  end if;
  if not has_function_privilege('authenticated', 'public.remind_form_unfilled(uuid)', 'execute') then
    perform pg_temp.fail('signed-in people cannot remind');
  end if;
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and tablename = 'forms'
    )
  then
    perform pg_temp.fail('forms is not in the realtime publication');
  end if;
end $$;

-- A card that is deleted takes the form with it (as a chain's does).
do $$
declare
  ada text := '00000000-0000-4000-8000-0000000000a1';
  bob text := '00000000-0000-4000-8000-0000000000b1';
  grp uuid := (select id from ids where name = 'group');
  gone uuid;
  gone_card uuid;
  made jsonb;
begin
  perform pg_temp.as_user(ada);
  made := public.create_form(grp, 'Oops', null,
    '[{"id":"a","type":"short_text","label":"A"}]'::jsonb, null);
  gone := (made->>'form_id')::uuid;
  gone_card := (made->>'message_id')::uuid;
  update public.messages set recalled_at = now() where id = gone_card;
  perform pg_temp.as_user(bob);
  perform pg_temp.refused('reading a form whose card was deleted',
    format('select public.get_form(%L)', gone), 'P0002', 'Form not found');
  perform pg_temp.refused('answering a form whose card was deleted',
    format($q$select public.submit_form_response(%L, '{"a":"x"}'::jsonb)$q$, gone),
    'P0002', 'Form not found');
  perform pg_temp.as_user(ada);
  perform pg_temp.refused('the creator reading a form whose card was deleted',
    format('select public.get_form_results(%L)', gone), 'P0002', 'Form not found');
end $$;

-- --------------------------------------------------------------- the AI guard --
do $$
declare
  ada text := '00000000-0000-4000-8000-0000000000a1';
  mo text := '00000000-0000-4000-8000-0000000000f1';
  the_circle uuid;
  conv uuid;
  cform uuid;
  made jsonb;
  res jsonb;
begin
  perform pg_temp.as_user(ada);
  the_circle := public.create_circle('Forms circle');
  select cc.conversation_id into conv
  from public.circle_channels cc
  where cc.circle_id = the_circle and cc.kind = 'text'
  order by cc.created_at limit 1;
  insert into public.circle_members (circle_id, user_id, role)
  values (the_circle, mo::uuid, 'member');
  insert into public.conversation_members (conversation_id, user_id, role)
  select cc.conversation_id, mo::uuid, 'member'
  from public.circle_channels cc
  where cc.circle_id = the_circle;

  -- A circle channel takes forms.
  made := public.create_form(conv, 'Channel poll', null,
    '[{"id":"t","type":"short_text","label":"Say","required":true},
      {"id":"c","type":"single_choice","label":"Pick","options":[{"id":"a","label":"A"},{"id":"b","label":"B"}]}]'::jsonb,
    null);
  cform := (made->>'form_id')::uuid;

  update public.circles set ai_enabled = true where id = the_circle;
  insert into public.circle_ai_guard (circle_id, enabled, new_rule, joined_days, action)
  values (the_circle, true, 'joined_days', 7, 'hold');

  -- Mo joined just now: his free text is not let through, his choice is.
  perform pg_temp.as_user(mo);
  res := public.submit_form_response(cform, '{"t":"buy my coins","c":"b"}'::jsonb);
  if not (res->>'text_held')::boolean
    or (select answers from public.form_responses where id = (res->>'response_id')::uuid)
      <> '{"c":"b"}'::jsonb
  then
    perform pg_temp.fail('a new member''s text got through the guard: ' || res::text);
  end if;
  -- He cannot start a form with free text nobody reviewed.
  perform pg_temp.refused('a held member starting a form',
    format($q$select public.create_form(%L, 'Hi', 'buy', '[{"id":"a","type":"short_text","label":"A"}]'::jsonb, null)$q$, conv),
    '42501', 'form_held');
  -- The owner is never held; with the guard off nobody is.
  perform pg_temp.as_user(ada);
  if (public.submit_form_response(cform, '{"t":"owner text"}'::jsonb)->>'text_held')::boolean then
    perform pg_temp.fail('the owner was held');
  end if;
  update public.circle_ai_guard set enabled = false where circle_id = the_circle;
  perform pg_temp.as_user(mo);
  res := public.submit_form_response(cform, '{"t":"fine now","c":"a"}'::jsonb);
  if (res->>'text_held')::boolean then
    perform pg_temp.fail('text held with the guard off');
  end if;
end $$;

-- ------------------------------------------------------------------ export --
do $$
declare
  ada text := '00000000-0000-4000-8000-0000000000a1';
  bob text := '00000000-0000-4000-8000-0000000000b1';
  the_form uuid := (select id from ids where name = 'form');
  mine jsonb;
  theirs jsonb;
  one jsonb;
begin
  mine := public.export_my_forms(bob::uuid);
  select f into one from jsonb_array_elements(mine) f where f->>'id' = the_form::text;
  if one is null
    or (one->>'created_by_me')::boolean
    or one->'settings' <> 'null'::jsonb
    or one->'description' <> 'null'::jsonb
    or jsonb_array_length(one->'my_responses') <> 1
    or jsonb_array_length(one->'questions') <> 8
  then
    perform pg_temp.fail('Bob''s export of a form he answered: ' || coalesce(one::text, 'null'));
  end if;
  if mine::text like '%Cyrus-secret%' then
    perform pg_temp.fail('Bob''s export carries Cy''s answers');
  end if;
  -- Bob's answer to the anonymous form is his own.
  if not exists (
    select 1 from jsonb_array_elements(mine) f
    where f->>'title' = 'Honest feedback'
      and f->'my_responses'->0->'answers'->>'say' = 'Even more snacks'
  ) then
    perform pg_temp.fail('Bob''s export misses his anonymous answer');
  end if;

  theirs := public.export_my_forms(ada::uuid);
  select f into one from jsonb_array_elements(theirs) f where f->>'id' = the_form::text;
  if one is null or not (one->>'created_by_me')::boolean
    or one->'settings' = 'null'::jsonb
    or jsonb_array_length(one->'my_responses') <> 0
    or (one->>'response_count')::int <> 2
  then
    perform pg_temp.fail('Ada''s export of her form: ' || coalesce(one::text, 'null'));
  end if;
  if theirs::text like '%Cyrus-secret%' or theirs::text like '%Bobby%' or theirs::text like '%Even more snacks%' then
    perform pg_temp.fail('Ada''s export carries other people''s answers');
  end if;
end $$;

do $$
declare
  all_failures text;
begin
  select string_agg(message, E'\n') into all_failures from failures;
  if all_failures is not null then
    raise exception E'Form checks failed:\n%', all_failures;
  end if;
end $$;

rollback;
