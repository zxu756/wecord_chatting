-- Behaviour checks for Notes and Lists (migrations 202610170060 to
-- 202610170065). Run by test/supabase/notes_lists_behaviour_test.dart against
-- a local database that has the earlier migrations; it applies these
-- migrations inside a transaction and rolls everything back, so the database
-- is left as it was. Run from the repository root.
\set ON_ERROR_STOP on

begin;

-- The behaviour scripts run side by side (flutter test runs files in
-- parallel) and each applies DDL: take turns so they cannot deadlock.
do $$ begin perform pg_advisory_xact_lock(20261017); end $$;

\i supabase/migrations/202610170060_notes.sql
\i supabase/migrations/202610170061_note_versions_files.sql
\i supabase/migrations/202610170062_task_lists.sql
\i supabase/migrations/202610170063_task_notifications.sql
\i supabase/migrations/202610170064_tasks_from_messages.sql
\i supabase/migrations/202610170065_conversation_workspace.sql

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create temp table failures (message text);
grant all on failures to public;

-- Ada owns a circle with a channel; Bob and Cy are members, Cy may not send
-- (a member overwrite denies send_messages), Mo moderates the channel
-- (manage_messages), Dan is not in the circle.
insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@notes.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@notes.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@notes.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d1', 'dan@notes.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e1', 'mo@notes.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_notes', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_notes', 'Bob'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_notes', 'Cy'),
  ('00000000-0000-4000-8000-0000000000d1', 'dan_notes', 'Dan'),
  ('00000000-0000-4000-8000-0000000000e1', 'mo_notes', 'Mo');

create function pg_temp.as_user(uid text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', uid, true);
$$;

create function pg_temp.fail(msg text) returns void language sql as $$
  insert into failures values (msg);
$$;

do $$
declare
  ada text := '00000000-0000-4000-8000-0000000000a1';
  bob text := '00000000-0000-4000-8000-0000000000b1';
  cy text := '00000000-0000-4000-8000-0000000000c1';
  dan text := '00000000-0000-4000-8000-0000000000d1';
  mo text := '00000000-0000-4000-8000-0000000000e1';
  the_circle uuid;
  the_channel uuid;
  conv uuid;
  thread_conv uuid;
begin
  perform pg_temp.as_user(ada);
  the_circle := public.create_circle('Notes circle');
  select cc.id, cc.conversation_id into the_channel, conv
  from public.circle_channels cc
  where cc.circle_id = the_circle and cc.kind = 'text'
  order by cc.created_at limit 1;

  insert into public.circle_members (circle_id, user_id, role)
  select the_circle, u::uuid, 'member' from unnest(array[bob, cy, mo]) u;
  insert into public.conversation_members (conversation_id, user_id, role)
  select cc.conversation_id, u::uuid, 'member'
  from public.circle_channels cc, unnest(array[bob, cy, mo]) u
  where cc.circle_id = the_circle;

  insert into public.circle_channel_overwrites (circle_id, channel_id, user_id, deny)
  values (the_circle, the_channel, cy::uuid, public.circle_permission_bits(array['send_messages']));
  insert into public.circle_channel_overwrites (circle_id, channel_id, user_id, allow)
  values (the_circle, the_channel, mo::uuid, public.circle_permission_bits(array['manage_messages']));

  -- A group of Bob, Cy and Ada.
  insert into ids select 'channel', conv;
  with g as (
    insert into public.conversations (type, title) values ('group', 'Docs group') returning id
  )
  insert into ids select 'group', id from g;
  insert into public.conversation_members (conversation_id, user_id, role)
  select (select id from ids where name = 'group'), u.id::uuid, u.role
  from (values (ada, 'owner'), (bob, 'member'), (cy, 'member')) as u(id, role);
end $$;

-- ---------------------------------------------------------------- notes ---
do $$
declare
  ada text := '00000000-0000-4000-8000-0000000000a1';
  bob text := '00000000-0000-4000-8000-0000000000b1';
  cy text := '00000000-0000-4000-8000-0000000000c1';
  dan text := '00000000-0000-4000-8000-0000000000d1';
  mo text := '00000000-0000-4000-8000-0000000000e1';
  conv uuid := (select id from ids where name = 'channel');
  grp uuid := (select id from ids where name = 'group');
  note jsonb;
  note_id uuid;
  second_note uuid;
  block_a uuid := gen_random_uuid();
  block_b uuid := gen_random_uuid();
  results jsonb;
  got jsonb;
  n integer;
  version_id uuid;
  first_block uuid;
begin
  -- Bob creates a note in the channel.
  perform pg_temp.as_user(bob);
  note := public.create_note(conv, 'Roadmap', null);
  note_id := (note->>'id')::uuid;
  if note->>'title' <> 'Roadmap' or (note->>'can_edit')::boolean is not true then
    perform pg_temp.fail('create_note result ' || note::text);
  end if;
  -- Creating again with the same id returns the same note (a repeat send).
  if (public.create_note(conv, 'Roadmap', null, note_id)->>'id')::uuid <> note_id then
    perform pg_temp.fail('create_note is not repeatable');
  end if;

  -- Cy can read but not create or edit.
  perform pg_temp.as_user(cy);
  select count(*) into n from public.list_notes(conv);
  if n <> 1 then perform pg_temp.fail('Cy should see 1 note, saw ' || n); end if;
  begin
    perform public.create_note(conv, 'Nope', null);
    perform pg_temp.fail('Cy created a note');
  exception when insufficient_privilege then null; end;
  begin
    perform public.note_apply_ops(note_id, '[]'::jsonb);
    perform pg_temp.fail('Cy applied ops');
  exception when insufficient_privilege then null; end;
  got := public.get_note(note_id);
  if (got->'note'->>'can_edit')::boolean then
    perform pg_temp.fail('Cy can_edit is true');
  end if;

  -- Dan, outside the circle, sees nothing.
  perform pg_temp.as_user(dan);
  begin
    perform public.get_note(note_id);
    perform pg_temp.fail('Dan read the note');
  exception when others then null; end;
  begin
    perform public.list_notes(conv);
    perform pg_temp.fail('Dan listed notes');
  exception when others then null; end;
  if exists (select 1 from public.search_notes('road')) then
    perform pg_temp.fail('Dan found the note by title');
  end if;

  -- Blocks: Ada and Bob edit different blocks at once, both stick.
  perform pg_temp.as_user(bob);
  select (b->>'id')::uuid into first_block
  from jsonb_array_elements(public.get_note(note_id)->'blocks') b limit 1;
  results := public.note_apply_ops(note_id, jsonb_build_array(
    jsonb_build_object('op', 'put', 'id', block_a, 'pos', 'a', 'kind', 'h1', 'text', 'Plan'),
    jsonb_build_object('op', 'put', 'id', block_b, 'pos', 'b', 'kind', 'bullet', 'text', 'one',
      'marks', '[[0,3,"b"]]'::jsonb)
  ));
  if results->0->>'status' <> 'ok' or results->1->>'status' <> 'ok' then
    perform pg_temp.fail('create blocks ' || results::text);
  end if;
  perform pg_temp.as_user(ada);
  results := public.note_apply_ops(note_id, jsonb_build_array(
    jsonb_build_object('op', 'put', 'id', block_a, 'base_rev', 1, 'pos', 'a', 'kind', 'h1', 'text', 'Plan 2027')
  ));
  if results->0->>'status' <> 'ok' or (results->0->>'rev')::int <> 2 then
    perform pg_temp.fail('Ada edit ' || results::text);
  end if;
  perform pg_temp.as_user(bob);
  -- Bob still thinks block_a is at revision 1: a conflict that carries the
  -- current block, and nothing is overwritten.
  results := public.note_apply_ops(note_id, jsonb_build_array(
    jsonb_build_object('op', 'put', 'id', block_a, 'base_rev', 1, 'pos', 'a', 'kind', 'h1', 'text', 'Plan!'),
    jsonb_build_object('op', 'put', 'id', block_b, 'base_rev', 1, 'pos', 'b', 'kind', 'bullet', 'text', 'one two')
  ));
  if results->0->>'status' <> 'conflict'
    or results->0->'block'->>'text' <> 'Plan 2027'
    or (results->0->'block'->>'rev')::int <> 2
  then
    perform pg_temp.fail('expected a conflict, got ' || results::text);
  end if;
  if results->1->>'status' <> 'ok' then
    perform pg_temp.fail('independent block should apply ' || results::text);
  end if;
  if (select text from public.note_blocks where id = block_a) <> 'Plan 2027' then
    perform pg_temp.fail('conflicting edit overwrote the block');
  end if;
  -- Merged and sent again on the current revision.
  results := public.note_apply_ops(note_id, jsonb_build_array(
    jsonb_build_object('op', 'put', 'id', block_a, 'base_rev', 2, 'pos', 'a', 'kind', 'h1', 'text', 'Plan 2027!')
  ));
  if results->0->>'status' <> 'ok' then perform pg_temp.fail('merged resend ' || results::text); end if;
  -- A repeat of the same send (lost answer) is ok and changes nothing.
  results := public.note_apply_ops(note_id, jsonb_build_array(
    jsonb_build_object('op', 'put', 'id', block_a, 'base_rev', 2, 'pos', 'a', 'kind', 'h1', 'text', 'Plan 2027!')
  ));
  if results->0->>'status' <> 'ok' or (results->0->>'rev')::int <> 3 then
    perform pg_temp.fail('repeat ' || results::text);
  end if;
  -- Creating a block that exists with other content conflicts.
  results := public.note_apply_ops(note_id, jsonb_build_array(
    jsonb_build_object('op', 'put', 'id', block_a, 'pos', 'a', 'kind', 'paragraph', 'text', 'other')
  ));
  if results->0->>'status' <> 'conflict' then
    perform pg_temp.fail('create over existing ' || results::text);
  end if;
  -- Invalid blocks are rejected, not stored.
  results := public.note_apply_ops(note_id, jsonb_build_array(
    jsonb_build_object('op', 'put', 'id', gen_random_uuid(), 'pos', 'bad pos!', 'kind', 'paragraph'),
    jsonb_build_object('op', 'put', 'id', gen_random_uuid(), 'pos', 'c', 'kind', 'banner')
  ));
  if results->0->>'status' <> 'rejected' or results->1->>'status' <> 'rejected' then
    perform pg_temp.fail('invalid blocks ' || results::text);
  end if;
  -- Order: by pos, ties by id.
  got := public.get_note(note_id);
  if (select string_agg(b->>'text', '|' order by ordinality)
      from jsonb_array_elements(got->'blocks') with ordinality t(b, ordinality)
      where b->>'text' <> '') <> 'Plan 2027!|one two' then
    perform pg_temp.fail('block order ' || got::text);
  end if;
  -- A delete wins, and a late edit of the deleted block conflicts.
  perform public.note_apply_ops(note_id, jsonb_build_array(
    jsonb_build_object('op', 'del', 'id', block_b)));
  results := public.note_apply_ops(note_id, jsonb_build_array(
    jsonb_build_object('op', 'put', 'id', block_b, 'base_rev', 2, 'pos', 'b', 'kind', 'bullet', 'text', 'late')
  ));
  if results->0->>'status' <> 'conflict' or (results->0->'block'->>'deleted')::boolean is not true then
    perform pg_temp.fail('late edit of deleted block ' || results::text);
  end if;

  -- Pinning and locking need a manager.
  perform pg_temp.as_user(bob);
  begin
    perform public.update_note_meta(note_id, '{"pinned": true}'::jsonb);
    perform pg_temp.fail('Bob pinned');
  exception when insufficient_privilege then null; end;
  begin
    perform public.update_note_meta(note_id, '{"managers_only": true}'::jsonb);
    perform pg_temp.fail('Bob locked');
  exception when insufficient_privilege then null; end;
  perform public.update_note_meta(note_id, '{"title": "Roadmap 2027", "icon": "R"}'::jsonb);
  perform pg_temp.as_user(mo);
  perform public.update_note_meta(note_id, '{"pinned": true, "managers_only": true}'::jsonb);
  got := public.get_pinned_note(conv);
  if got->>'id' <> note_id::text or got->>'title' <> 'Roadmap 2027' then
    perform pg_temp.fail('pinned note ' || coalesce(got::text, 'null'));
  end if;
  -- A second pin replaces the first.
  second_note := (public.create_note(conv, 'Standup', null)->>'id')::uuid;
  perform public.update_note_meta(second_note, '{"pinned": true}'::jsonb);
  if (public.get_pinned_note(conv)->>'id')::uuid <> second_note
    or (select pinned from public.notes where id = note_id)
  then
    perform pg_temp.fail('second pin did not replace the first');
  end if;
  -- Locked: Bob can no longer edit, Mo (a manager) still can.
  perform pg_temp.as_user(bob);
  begin
    perform public.note_apply_ops(note_id, jsonb_build_array(
      jsonb_build_object('op', 'put', 'id', block_a, 'base_rev', 3, 'pos', 'a', 'kind', 'h1', 'text', 'x')));
    perform pg_temp.fail('Bob edited a locked note');
  exception when insufficient_privilege then null; end;
  begin
    perform public.update_note_meta(note_id, '{"title": "x"}'::jsonb);
    perform pg_temp.fail('Bob retitled a locked note');
  exception when insufficient_privilege then null; end;
  perform pg_temp.as_user(mo);
  results := public.note_apply_ops(note_id, jsonb_build_array(
    jsonb_build_object('op', 'put', 'id', block_a, 'base_rev', 3, 'pos', 'a', 'kind', 'h1', 'text', 'Plan 2027!!')));
  if results->0->>'status' <> 'ok' then perform pg_temp.fail('Mo edit ' || results::text); end if;
  -- Locks are about editing, not reading.
  perform pg_temp.as_user(cy);
  perform public.get_note(note_id);

  -- Versions: on demand, list, restore.
  perform pg_temp.as_user(mo);
  version_id := public.create_note_version(note_id, 'Before the rewrite');
  perform public.note_apply_ops(note_id, jsonb_build_array(
    jsonb_build_object('op', 'put', 'id', block_a, 'base_rev', 4, 'pos', 'a', 'kind', 'h1', 'text', 'Rewritten'),
    jsonb_build_object('op', 'put', 'id', gen_random_uuid(), 'pos', 'z', 'kind', 'paragraph', 'text', 'extra')));
  select count(*) into n from public.list_note_versions(note_id);
  if n <> 1 then perform pg_temp.fail('versions ' || n); end if;
  perform pg_temp.as_user(cy);
  got := public.get_note_version(version_id);
  if jsonb_array_length(got->'blocks') < 2 then perform pg_temp.fail('version blocks ' || got::text); end if;
  begin
    perform public.restore_note_version(version_id);
    perform pg_temp.fail('Cy restored');
  exception when insufficient_privilege then null; end;
  perform pg_temp.as_user(mo);
  perform public.restore_note_version(version_id);
  got := public.get_note(note_id);
  if (select string_agg(b->>'text', '|' order by ordinality)
      from jsonb_array_elements(got->'blocks') with ordinality t(b, ordinality)
      where b->>'text' <> '') <> 'Plan 2027!!' then
    perform pg_temp.fail('restore ' || got::text);
  end if;
  -- The restore snapshotted what it replaced.
  if not exists (select 1 from public.list_note_versions(note_id) where kind = 'restore') then
    perform pg_temp.fail('restore left no snapshot');
  end if;

  -- An automatic snapshot opens a new burst of work after a quiet spell.
  update public.notes set updated_at = now() - interval '2 hours',
    last_snapshot_at = now() - interval '3 hours' where id = second_note;
  perform pg_temp.as_user(mo);
  perform public.note_apply_ops(second_note, jsonb_build_array(
    jsonb_build_object('op', 'put', 'id', gen_random_uuid(), 'pos', 'a', 'kind', 'paragraph', 'text', 'late')));
  if not exists (select 1 from public.list_note_versions(second_note) where kind = 'auto') then
    perform pg_temp.fail('no automatic snapshot');
  end if;
  -- ...but not within the same burst.
  perform public.note_apply_ops(second_note, jsonb_build_array(
    jsonb_build_object('op', 'put', 'id', gen_random_uuid(), 'pos', 'b', 'kind', 'paragraph', 'text', 'again')));
  select count(*) into n from public.list_note_versions(second_note) where kind = 'auto';
  if n <> 1 then perform pg_temp.fail('automatic snapshots ' || n); end if;

  -- Sharing a note as a card, and where.
  perform pg_temp.as_user(bob);
  perform public.share_note(second_note, conv);
  if not exists (
    select 1 from public.messages m
    where m.conversation_id = conv and m.attachment->>'kind' = 'note'
      and m.attachment->>'note_id' = second_note::text and m.body like '% Standup'
  ) then
    perform pg_temp.fail('shared note card missing');
  end if;
  begin
    perform public.share_note(second_note, grp);
    perform pg_temp.fail('shared a note into another conversation');
  exception when invalid_parameter_value then null; end;
  perform pg_temp.as_user(cy);
  begin
    perform public.share_note(second_note, conv);
    perform pg_temp.fail('Cy shared a note');
  exception when insufficient_privilege then null; end;

  -- Title search across conversations the caller can see.
  perform pg_temp.as_user(cy);
  select count(*) into n from public.search_notes('STAND');
  if n <> 1 then perform pg_temp.fail('search_notes found ' || n); end if;
  select count(*) into n from public.search_notes('100%');
  if n <> 0 then perform pg_temp.fail('search_notes wildcard ' || n); end if;

  -- Groups and direct chats have notes too; any member may edit.
  perform pg_temp.as_user(cy);
  note := public.create_note(grp, 'Trip', null);
  if (note->>'can_manage')::boolean then perform pg_temp.fail('group member can manage'); end if;

  -- Deleting: the author or a manager.
  perform pg_temp.as_user(bob);
  begin
    perform public.delete_note(second_note);
    -- Bob created the note? No, Mo did.
    perform pg_temp.fail('Bob deleted Mo''s note');
  exception when insufficient_privilege then null; end;
  perform pg_temp.as_user(mo);
  perform public.delete_note(second_note);
  select count(*) into n from public.list_notes(conv);
  if n <> 1 then perform pg_temp.fail('notes after delete ' || n); end if;
end $$;

-- Clients cannot write the tables directly.
do $$
declare
  target uuid := (select id from public.notes where title = 'Roadmap 2027');
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);
  set local role authenticated;
  begin
    insert into public.note_blocks (id, note_id, pos) values (gen_random_uuid(), target, 'q');
    reset role;
    perform pg_temp.fail('direct insert into note_blocks worked');
  exception when insufficient_privilege then reset role; end;
  set local role authenticated;
  begin
    update public.notes set title = 'hacked' where id = target;
    reset role;
    perform pg_temp.fail('direct update of notes worked');
  exception when insufficient_privilege then reset role; end;
  -- RLS: members read, outsiders do not.
  set local role authenticated;
  if (select count(*) from public.note_blocks where note_id = target) = 0 then
    reset role;
    perform pg_temp.fail('member cannot read blocks');
  end if;
  reset role;
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d1', true);
  set local role authenticated;
  if (select count(*) from public.note_blocks) <> 0 or (select count(*) from public.notes) <> 0 then
    reset role;
    perform pg_temp.fail('outsider reads notes');
  end if;
  reset role;
  -- Not callable anonymously.
  set local role anon;
  begin
    perform public.list_notes(gen_random_uuid());
    reset role;
    perform pg_temp.fail('anon called list_notes');
  exception when insufficient_privilege then reset role; end;
end $$;

-- ---------------------------------------------------------------- lists ---
do $$
declare
  ada text := '00000000-0000-4000-8000-0000000000a1';
  bob text := '00000000-0000-4000-8000-0000000000b1';
  cy text := '00000000-0000-4000-8000-0000000000c1';
  dan text := '00000000-0000-4000-8000-0000000000d1';
  mo text := '00000000-0000-4000-8000-0000000000e1';
  conv uuid := (select id from ids where name = 'channel');
  grp uuid := (select id from ids where name = 'group');
  lst jsonb;
  list_id uuid;
  item jsonb;
  item_id uuid := gen_random_uuid();
  other_item uuid := gen_random_uuid();
  n integer;
  rows record;
  msg uuid;
  from_msg jsonb;
begin
  perform pg_temp.as_user(bob);
  lst := public.create_task_list(conv, 'Launch', null);
  list_id := (lst->>'id')::uuid;
  if jsonb_array_length(lst->'statuses') <> 3 then perform pg_temp.fail('default statuses'); end if;

  -- Items: create, patch, move, complete.
  item := public.upsert_task_item(list_id, jsonb_build_object(
    'id', item_id, 'title', 'Write copy', 'priority', 2, 'pos', 'a'));
  if item->>'status' <> 'todo' or item->>'completed_at' is not null then
    perform pg_temp.fail('new item ' || item::text);
  end if;
  item := public.upsert_task_item(list_id, jsonb_build_object('id', item_id, 'status', 'doing', 'pos', 'b'));
  if item->>'title' <> 'Write copy' or item->>'status' <> 'doing' or item->>'pos' <> 'b' then
    perform pg_temp.fail('patch keeps other fields ' || item::text);
  end if;
  item := public.upsert_task_item(list_id, jsonb_build_object('id', item_id, 'status', 'done'));
  if item->>'completed_at' is null then perform pg_temp.fail('done sets completed_at'); end if;
  item := public.set_task_item_done(item_id, false);
  if item->>'status' <> 'todo' or item->>'completed_at' is not null then
    perform pg_temp.fail('undone ' || item::text);
  end if;
  begin
    perform public.upsert_task_item(list_id, jsonb_build_object('id', item_id, 'status', 'nope'));
    perform pg_temp.fail('unknown status accepted');
  exception when invalid_parameter_value then null; end;
  begin
    perform public.upsert_task_item(list_id, jsonb_build_object('id', gen_random_uuid(), 'title', '  '));
    perform pg_temp.fail('blank title accepted');
  exception when invalid_parameter_value then null; end;

  -- Board moves: two items in one column order by pos.
  perform public.upsert_task_item(list_id, jsonb_build_object(
    'id', other_item, 'title', 'Design', 'status', 'todo', 'pos', 'a0'));
  perform public.upsert_task_item(list_id, jsonb_build_object('id', item_id, 'status', 'todo', 'pos', 'a'));
  if (select string_agg(i->>'title', '|' order by ordinality)
      from jsonb_array_elements(public.get_task_list(list_id)->'items') with ordinality t(i, ordinality)
      where i->>'status' = 'todo') <> 'Write copy|Design' then
    perform pg_temp.fail('column order');
  end if;
  perform public.upsert_task_item(list_id, jsonb_build_object('id', other_item, 'pos', '9'));
  if (select string_agg(i->>'title', '|' order by ordinality)
      from jsonb_array_elements(public.get_task_list(list_id)->'items') with ordinality t(i, ordinality)
      where i->>'status' = 'todo') <> 'Design|Write copy' then
    perform pg_temp.fail('column order after drag');
  end if;

  -- Assignment: only people of the conversation; notifies the assignee.
  begin
    perform public.upsert_task_item(list_id, jsonb_build_object('id', item_id, 'assignees', jsonb_build_array(dan)));
    perform pg_temp.fail('assigned an outsider');
  exception when invalid_parameter_value then null; end;
  perform public.upsert_task_item(list_id, jsonb_build_object(
    'id', item_id, 'assignees', jsonb_build_array(bob, cy), 'due_at', (now() + interval '30 minutes')::text,
    'due_has_time', true));
  -- Cy (read only) may be assigned; Bob assigning himself makes no notice.
  select count(*) into n from public.task_notifications where kind = 'assigned';
  if n <> 1 then perform pg_temp.fail('assignment notices ' || n); end if;
  perform pg_temp.as_user(cy);
  select count(*) into n from public.list_task_notifications();
  if n <> 1 then perform pg_temp.fail('Cy sees ' || n || ' task notices'); end if;
  select * into rows from public.list_task_notifications() limit 1;
  if rows.kind <> 'assigned' or rows.title <> 'Write copy' or rows.actor_name <> 'Bob' or not rows.is_unread then
    perform pg_temp.fail('task notice ' || row_to_json(rows)::text);
  end if;
  perform public.mark_task_notifications_read(null);
  if (select is_unread from public.list_task_notifications() limit 1) then
    perform pg_temp.fail('notice not marked read');
  end if;
  -- Cy cannot change items; Dan cannot see lists.
  begin
    perform public.upsert_task_item(list_id, jsonb_build_object('id', item_id, 'title', 'x'));
    perform pg_temp.fail('Cy edited an item');
  exception when insufficient_privilege then null; end;
  perform pg_temp.as_user(dan);
  begin
    perform public.get_task_list(list_id);
    perform pg_temp.fail('Dan read a list');
  exception when others then null; end;

  -- Assignment push: claimed once, for the assigner, with a subscription.
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth)
  values (cy::uuid, 'https://push.example/cy', repeat('p', 60), repeat('a', 20));
  select count(*) into n from public.claim_task_assignment_push(item_id, bob::uuid);
  if n <> 1 then perform pg_temp.fail('assignment push rows ' || n); end if;
  select count(*) into n from public.claim_task_assignment_push(item_id, bob::uuid);
  if n <> 0 then perform pg_temp.fail('assignment push repeated ' || n); end if;
  select count(*) into n from public.claim_task_assignment_push(item_id, ada::uuid);
  if n <> 0 then perform pg_temp.fail('assignment push for the wrong caller'); end if;

  -- Due reminders: Bob and Cy are due in 30 minutes; each is told once.
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth)
  values (bob::uuid, 'https://push.example/bob', repeat('p', 60), repeat('a', 20));
  select count(*) into n from public.due_list_item_reminders();
  if n <> 2 then perform pg_temp.fail('reminder pushes ' || n); end if;
  select count(*) into n from public.due_list_item_reminders();
  if n <> 0 then perform pg_temp.fail('reminders repeated ' || n); end if;
  perform pg_temp.as_user(cy);
  if not exists (select 1 from public.list_task_notifications() where kind = 'due_soon') then
    perform pg_temp.fail('no due_soon notice in the inbox');
  end if;
  -- A new due date, already past, reminds again as overdue.
  perform pg_temp.as_user(bob);
  perform public.upsert_task_item(list_id, jsonb_build_object('id', item_id, 'due_at', (now() - interval '5 minutes')::text));
  select count(*) into n from public.due_list_item_reminders();
  if n <> 2 then perform pg_temp.fail('overdue pushes ' || n); end if;
  -- Done items are not reminded.
  perform public.set_task_item_done(item_id, true);
  perform public.upsert_task_item(list_id, jsonb_build_object('id', item_id, 'due_at', (now() + interval '10 minutes')::text));
  select count(*) into n from public.due_list_item_reminders();
  if n <> 0 then perform pg_temp.fail('done item reminded ' || n); end if;
  -- Not callable by clients.
  begin
    set local role authenticated;
    perform public.due_list_item_reminders();
    reset role;
    perform pg_temp.fail('a client ran the reminders');
  exception when insufficient_privilege then reset role; end;

  -- A person in do-not-disturb gets the inbox entry but no push.
  insert into public.user_privacy_settings (user_id, presence_status)
  values (cy::uuid, 'dnd') on conflict (user_id) do update set presence_status = 'dnd';
  perform public.upsert_task_item(list_id, jsonb_build_object(
    'id', other_item, 'assignees', jsonb_build_array(cy), 'status', 'todo',
    'due_at', (now() + interval '20 minutes')::text, 'due_has_time', true));
  select count(*) into n from public.due_list_item_reminders() where user_id = cy::uuid;
  if n <> 0 then perform pg_temp.fail('DND got a push'); end if;
  if not exists (
    select 1 from public.task_notifications t
    where t.user_id = cy::uuid and t.item_id = other_item and t.kind = 'due_soon'
  ) then
    perform pg_temp.fail('DND lost the inbox entry');
  end if;

  -- Custom statuses; removing one moves its items.
  lst := public.update_task_list(list_id, jsonb_build_object(
    'statuses', '[{"id":"todo","name":"Backlog","kind":"todo"},{"id":"review","name":"Review","kind":"active"},{"id":"done","name":"Shipped","kind":"done"}]'::jsonb,
    'status_moves', '{"doing": "review"}'::jsonb));
  if lst->'statuses'->0->>'name' <> 'Backlog' then perform pg_temp.fail('custom statuses'); end if;
  begin
    perform public.update_task_list(list_id, '{"statuses": [{"id":"a","name":"A","kind":"todo"}]}'::jsonb);
    perform pg_temp.fail('statuses without a done kind accepted');
  exception when invalid_parameter_value then null; end;

  -- Create task from a message; it links back, and repeats are safe.
  insert into public.messages (conversation_id, sender_id, type, body)
  values (grp, ada::uuid, 'text', E'Book the venue\nbefore Friday')
  returning id into msg;
  perform pg_temp.as_user(bob);
  from_msg := public.create_task_from_message(msg, null, null, item_id);
  perform pg_temp.as_user(ada);
  from_msg := public.create_task_from_message(msg);
  if from_msg->>'title' <> 'Book the venue' or from_msg->>'source_message_id' <> msg::text then
    perform pg_temp.fail('task from message ' || from_msg::text);
  end if;
  if (select count(*) from public.task_lists where conversation_id = grp) <> 1 then
    perform pg_temp.fail('Tasks list not made once');
  end if;
  if not exists (select 1 from public.list_message_tasks(grp) where message_id = msg) then
    perform pg_temp.fail('list_message_tasks');
  end if;
  begin
    perform pg_temp.as_user(dan);
    perform public.create_task_from_message(msg);
    perform pg_temp.fail('Dan made a task from a message');
  exception when others then null; end;

  -- Sharing a task and a list as cards.
  perform pg_temp.as_user(ada);
  perform public.share_task_item((from_msg->>'id')::uuid, grp);
  perform public.share_task_list(list_id, conv);
  if (select count(*) from public.messages where attachment->>'kind' in ('task', 'list')) <> 2 then
    perform pg_temp.fail('task cards');
  end if;
  begin
    perform public.share_task_list(list_id, grp);
    perform pg_temp.fail('shared a list into another conversation');
  exception when invalid_parameter_value then null; end;

  -- Workspace summary.
  perform pg_temp.as_user(bob);
  lst := public.get_conversation_workspace(conv);
  if (lst->>'notes')::int <> 1 or (lst->>'lists')::int <> 1 or (lst->>'can_create')::boolean is not true then
    perform pg_temp.fail('workspace ' || lst::text);
  end if;
  perform pg_temp.as_user(cy);
  if (public.get_conversation_workspace(conv)->>'can_create')::boolean then
    perform pg_temp.fail('Cy can_create');
  end if;

  -- Deleting items and lists.
  perform pg_temp.as_user(cy);
  begin
    perform public.delete_task_list(list_id);
    perform pg_temp.fail('Cy deleted a list');
  exception when insufficient_privilege then null; end;
  perform pg_temp.as_user(mo);
  perform public.delete_task_list(list_id);
  select count(*) into n from public.list_task_lists(conv);
  if n <> 0 then perform pg_temp.fail('lists after delete ' || n); end if;
end $$;

do $$
declare
  all_failures text;
begin
  select string_agg(message, E'\n') into all_failures from failures;
  if all_failures is not null then
    raise exception E'Notes and lists checks failed:\n%', all_failures;
  end if;
end $$;

rollback;
