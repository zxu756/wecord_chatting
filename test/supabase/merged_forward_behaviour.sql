-- Behaviour checks for merged forwards (migration 202610180070) and contact
-- cards (202610180071). Run by test/supabase/merged_forward_test.dart against
-- the local database: it applies the migrations the local database lacks in a
-- transaction, acts as several people, checks the rules and rolls back, so the
-- database is left as it was. Run from the repository root.
\set ON_ERROR_STOP on

begin;

-- One behaviour script at a time: they change the same tables, and test
-- files run in parallel.
do $$ begin perform pg_advisory_xact_lock(20261017); end $$;

\i supabase/migrations/202610140004_bans_and_timeouts.sql
\i supabase/migrations/202610170002_album_counts.sql
\i supabase/migrations/202610170003_album_summaries.sql
\i supabase/migrations/202610170004_album_push.sql
\i supabase/migrations/202610170005_push_language.sql
\i supabase/migrations/202610170020_disappearing_messages.sql
\i supabase/migrations/202610170021_view_once_media.sql
\i supabase/migrations/202610170023_poll_upgrade.sql
\i supabase/migrations/202610170024_profile_visibility.sql
\i supabase/migrations/202610170090_ai_guard.sql
\i supabase/migrations/202610170091_ai_guard_hidden.sql
\i supabase/migrations/202610170101_profile_visibility_enforced.sql
\i supabase/migrations/202610180070_merged_forward.sql
\i supabase/migrations/202610180071_contact_cards.sql

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a8', 'ada@mf.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b8', 'bob@mf.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c8', 'cy@mf.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d8', 'dee@mf.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e8', 'eve@mf.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000f8', 'fay@mf.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name, avatar_url)
values
  ('00000000-0000-4000-8000-0000000000a8', 'ada_mf', 'Ada', 'avatars/ada.png'),
  ('00000000-0000-4000-8000-0000000000b8', 'bob_mf', 'Bob', null),
  ('00000000-0000-4000-8000-0000000000c8', 'cy_mf', 'Cy', null),
  ('00000000-0000-4000-8000-0000000000d8', 'dee_mf', 'Dee', null),
  ('00000000-0000-4000-8000-0000000000e8', 'eve_mf', 'Eve', null),
  ('00000000-0000-4000-8000-0000000000f8', 'fay_mf', 'Fay', null);

-- Ada and Bob are friends. Cy only lets friends see his profile. Fay
-- blocked Ada.
insert into public.friendships (user_low_id, user_high_id)
values ('00000000-0000-4000-8000-0000000000a8', '00000000-0000-4000-8000-0000000000b8');
insert into public.user_privacy_settings (user_id, profile_visibility)
values ('00000000-0000-4000-8000-0000000000c8', 'friends')
on conflict (user_id) do update set profile_visibility = 'friends';
insert into public.blocks (blocker_id, blocked_id)
values ('00000000-0000-4000-8000-0000000000f8', '00000000-0000-4000-8000-0000000000a8');

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

create function pg_temp.as_user(user_id uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_id, 'role', 'authenticated')::text,
    true
  );
end $$;

-- Runs a one-number query as [user_id] with row level security on.
create function pg_temp.as_count(user_id uuid, q text) returns integer language plpgsql as $$
declare n integer;
begin
  perform pg_temp.as_user(user_id);
  execute 'set local role authenticated';
  execute q into n;
  execute 'reset role';
  return n;
exception when others then
  execute 'reset role';
  raise;
end $$;

-- Runs [q] as [user_id]; the error message it raises, or 'ok'.
create function pg_temp.attempt(user_id uuid, q text) returns text language plpgsql as $$
begin
  perform pg_temp.as_user(user_id);
  execute q;
  return 'ok';
exception when others then
  return sqlerrm;
end $$;

-- Deletes [msg] as [user_id] the way the app does.
create function pg_temp.recall_bundle(user_id uuid, msg uuid) returns void language plpgsql as $$
begin
  perform pg_temp.as_user(user_id);
  perform * from public.recall_message(msg);
end $$;

-- Source group: Ada, Bob, Cy. Target direct chat: Ada and Dee. Target group:
-- Ada, Dee and Eve. A direct chat with Fay, who blocked Ada.
with src as (
  insert into public.conversations (type, title) values ('group', 'Source group') returning id
), src_members as (
  insert into public.conversation_members (conversation_id, user_id, role)
  select src.id, m.id, m.role
  from src, (values
    ('00000000-0000-4000-8000-0000000000a8'::uuid, 'owner'),
    ('00000000-0000-4000-8000-0000000000b8'::uuid, 'member'),
    ('00000000-0000-4000-8000-0000000000c8'::uuid, 'member')
  ) as m(id, role)
), dm as (
  insert into public.conversations (type) values ('direct') returning id
), dm_members as (
  insert into public.conversation_members (conversation_id, user_id)
  select dm.id, m.id from dm, (values
    ('00000000-0000-4000-8000-0000000000a8'::uuid),
    ('00000000-0000-4000-8000-0000000000d8'::uuid)
  ) as m(id)
), tgt as (
  insert into public.conversations (type, title) values ('group', 'Target group') returning id
), tgt_members as (
  insert into public.conversation_members (conversation_id, user_id, role)
  select tgt.id, m.id, m.role
  from tgt, (values
    ('00000000-0000-4000-8000-0000000000a8'::uuid, 'owner'),
    ('00000000-0000-4000-8000-0000000000d8'::uuid, 'member'),
    ('00000000-0000-4000-8000-0000000000e8'::uuid, 'member')
  ) as m(id, role)
), blocked as (
  insert into public.conversations (type) values ('direct') returning id
), blocked_members as (
  insert into public.conversation_members (conversation_id, user_id)
  select blocked.id, m.id from blocked, (values
    ('00000000-0000-4000-8000-0000000000a8'::uuid),
    ('00000000-0000-4000-8000-0000000000f8'::uuid)
  ) as m(id)
)
insert into ids
select 'src', id from src
union all select 'dm', id from dm
union all select 'tgt', id from tgt
union all select 'blocked', id from blocked;

-- Ada's circle, with a channel; Bob is a member.
select pg_temp.as_user('00000000-0000-4000-8000-0000000000a8');
insert into ids select 'circle', public.create_circle('Mf circle', array[]::uuid[]);
insert into public.circle_members (circle_id, user_id, role)
values ((select id from ids where name = 'circle'), '00000000-0000-4000-8000-0000000000b8', 'member');
insert into ids
select 'channel', cc.conversation_id
from public.circle_channels cc
where cc.circle_id = (select id from ids where name = 'circle')
limit 1;
insert into public.conversation_members (conversation_id, user_id, role)
select (select id from ids where name = 'channel'), '00000000-0000-4000-8000-0000000000b8', 'member'
on conflict do nothing;

-- Files in the source group.
insert into storage.objects (bucket_id, name)
select 'chat-images', (select id from ids where name = 'src') || '/pic.png'
union all
select 'chat-files', (select id from ids where name = 'src') || '/doc.pdf'
union all
select 'voice-messages', (select id from ids where name = 'src') || '/hi.m4a'
union all
select 'chat-images', (select id from ids where name = 'src') || '/once.png'
union all
select 'chat-images', (select id from ids where name = 'src') || '/other.png';

do $$
declare
  src uuid := (select id from ids where name = 'src');
  dm uuid := (select id from ids where name = 'dm');
  tgt uuid := (select id from ids where name = 'tgt');
  blocked uuid := (select id from ids where name = 'blocked');
  channel uuid := (select id from ids where name = 'channel');
  circle uuid := (select id from ids where name = 'circle');
  ada uuid := '00000000-0000-4000-8000-0000000000a8';
  bob uuid := '00000000-0000-4000-8000-0000000000b8';
  cy uuid := '00000000-0000-4000-8000-0000000000c8';
  dee uuid := '00000000-0000-4000-8000-0000000000d8';
  eve uuid := '00000000-0000-4000-8000-0000000000e8';
  fay uuid := '00000000-0000-4000-8000-0000000000f8';
  m_text uuid;
  m_text2 uuid;
  m_img uuid;
  m_file uuid;
  m_voice uuid;
  m_once uuid;
  m_poll uuid;
  m_sys uuid;
  m_gone uuid;
  m_expired uuid;
  m_held uuid;
  m_other_chat uuid;
  bundle_msg uuid;
  bundle2_msg uuid;
  bundle3_msg uuid;
  dm_text uuid;
  card jsonb;
  items jsonb;
  failures text := '';
  outcome text;
  n integer;
begin
  -- The source messages.
  insert into public.messages (conversation_id, sender_id, type, body)
  values (src, ada, 'text', 'Meet at 7?') returning id into m_text;
  insert into public.messages (conversation_id, sender_id, type, body)
  values (src, bob, 'text', 'Works for me') returning id into m_text2;
  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (src, ada, 'image', '', jsonb_build_object('kind', 'image', 'bucket', 'chat-images',
    'path', src || '/pic.png', 'mime_type', 'image/png', 'size', 10, 'width', 4, 'height', 3,
    'secret', 'dropped')) returning id into m_img;
  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (src, bob, 'file', '', jsonb_build_object('kind', 'file', 'bucket', 'chat-files',
    'path', src || '/doc.pdf', 'name', 'plan.pdf', 'mime_type', 'application/pdf', 'size', 20))
  returning id into m_file;
  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (src, ada, 'voice', '', jsonb_build_object('kind', 'voice', 'bucket', 'voice-messages',
    'path', src || '/hi.m4a', 'mime_type', 'audio/mp4', 'size', 30, 'duration_ms', 1500))
  returning id into m_voice;
  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (src, ada, 'image', '', jsonb_build_object('kind', 'image', 'bucket', 'chat-images',
    'path', src || '/once.png', 'mime_type', 'image/png', 'size', 10, 'view_once', true))
  returning id into m_once;
  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (src, ada, 'poll', 'Poll?', jsonb_build_object('kind', 'poll'))
  returning id into m_poll;
  insert into public.messages (conversation_id, sender_id, type, body)
  values (src, ada, 'system', 'Ada did something') returning id into m_sys;
  insert into public.messages (conversation_id, sender_id, type, body)
  values (src, ada, 'text', 'to be deleted') returning id into m_gone;
  update public.messages set recalled_at = now(), recalled_by = ada, body = '' where id = m_gone;
  insert into public.messages (conversation_id, sender_id, type, body)
  values (src, ada, 'text', 'old news') returning id into m_expired;
  update public.messages set expires_at = now() - interval '1 minute' where id = m_expired;
  insert into public.messages (conversation_id, sender_id, type, body)
  values (src, ada, 'text', 'waiting for review') returning id into m_held;
  update public.messages set review_state = 'held' where id = m_held;
  insert into public.messages (conversation_id, sender_id, type, body)
  values (dm, ada, 'text', 'from another chat') returning id into m_other_chat;

  -- Messages sent in one transaction share a time: space them out.
  update public.messages
  set created_at = now() - interval '1 hour' + (
    array_position(array[m_text, m_text2, m_img, m_file, m_voice], id) * interval '1 minute'
  )
  where id in (m_text, m_text2, m_img, m_file, m_voice);

  -- Before any forward, Dee (not in the source group) reads nothing there.
  n := pg_temp.as_count(dee, format($q$select count(*) from storage.objects
    where bucket_id = 'chat-images' and name = %L$q$, src || '/pic.png'));
  if n <> 0 then failures := failures || E'\nDee read a file of a chat she is not in'; end if;

  -- 1. Bob forwards five messages of the group (a mix) to Ada and Dee's
  -- direct chat? He is not a member there. Ada forwards instead.
  perform pg_temp.as_user(ada);
  bundle_msg := public.forward_messages_merged(
    array[m_voice, m_text, m_img, m_file, m_text2], dm, 'Source group');
  if bundle_msg is null then failures := failures || E'\nthe merged forward returned no message'; end if;

  select attachment into card from public.messages where id = bundle_msg;
  if card->>'kind' <> 'chat_history' or (card->>'count')::int <> 5
    or jsonb_array_length(card->'preview') <> 4
    or card->>'title' <> 'Source group' then
    failures := failures || format(E'\nthe card is %s', card);
  end if;
  if (select body from public.messages where id = bundle_msg) <> 'Chat history: Source group' then
    failures := failures || E'\nthe fallback text is wrong';
  end if;
  if (card->'preview'->0->>'text') <> 'Meet at 7?' or (card->'preview'->0->>'name') <> 'Ada' then
    failures := failures || E'\nthe preview does not start with the first message (oldest first)';
  end if;

  -- The recipient, who is not in the source group, reads the items.
  n := pg_temp.as_count(dee, format('select count(*) from public.message_bundles where message_id = %L', bundle_msg));
  if n <> 1 then failures := failures || E'\nDee cannot read the bundle'; end if;
  perform pg_temp.as_user(dee);
  select b.items into items from public.message_bundles b where b.message_id = bundle_msg;
  if jsonb_array_length(items) <> 5 then failures := failures || E'\nthe bundle has the wrong number of items'; end if;
  if items->0->>'sender_name' <> 'Ada' or items->0->>'sender_avatar' <> 'avatars/ada.png' then
    failures := failures || format(E'\nsnapshot of the sender is wrong: %s', items->0);
  end if;
  if (select count(*) from jsonb_array_elements(items) i where i->'attachment' ? 'secret') <> 0 then
    failures := failures || E'\nan attachment key outside the allow-list was copied';
  end if;
  if (select i->'attachment'->>'name' from jsonb_array_elements(items) i where i->>'type' = 'file') <> 'plan.pdf' then
    failures := failures || E'\nfile metadata was not copied';
  end if;

  -- Eve is in neither chat: she reads no bundle.
  n := pg_temp.as_count(eve, format('select count(*) from public.message_bundles where message_id = %L', bundle_msg));
  if n <> 0 then failures := failures || E'\nEve read a bundle of a chat she is not in'; end if;

  -- Files: the recipient reads the three bundled objects, not the others.
  n := pg_temp.as_count(dee, format($q$select count(*) from storage.objects
    where name in (%L, %L, %L)$q$, src || '/pic.png', src || '/doc.pdf', src || '/hi.m4a'));
  if n <> 3 then failures := failures || format(E'\nDee reads %s of the 3 bundled files', n); end if;
  n := pg_temp.as_count(dee, format($q$select count(*) from storage.objects where name = %L$q$, src || '/other.png'));
  if n <> 0 then failures := failures || E'\nDee read a file nobody bundled'; end if;
  n := pg_temp.as_count(eve, format($q$select count(*) from storage.objects where name = %L$q$, src || '/pic.png'));
  if n <> 0 then failures := failures || E'\nEve read a bundled file of a chat she is not in'; end if;
  n := pg_temp.as_count(cy, format($q$select count(*) from storage.objects where name = %L$q$, src || '/pic.png'));
  if n <> 1 then failures := failures || E'\na member of the source chat lost access'; end if;

  -- 2. What a forward refuses, each refusing the whole forward.
  outcome := pg_temp.attempt(ada, format('select public.forward_messages_merged(array[%L::uuid, %L::uuid], %L::uuid, ''x'')', m_text, m_once, dm));
  if outcome not like '%cannot be forwarded%' then failures := failures || format(E'\nview-once: %s', outcome); end if;
  outcome := pg_temp.attempt(ada, format('select public.forward_messages_merged(array[%L::uuid, %L::uuid], %L::uuid, ''x'')', m_text, m_poll, dm));
  if outcome not like '%cannot be forwarded%' then failures := failures || format(E'\npoll: %s', outcome); end if;
  outcome := pg_temp.attempt(ada, format('select public.forward_messages_merged(array[%L::uuid, %L::uuid], %L::uuid, ''x'')', m_text, m_sys, dm));
  if outcome not like '%cannot be forwarded%' then failures := failures || format(E'\nsystem line: %s', outcome); end if;
  outcome := pg_temp.attempt(ada, format('select public.forward_messages_merged(array[%L::uuid, %L::uuid], %L::uuid, ''x'')', m_text, m_gone, dm));
  if outcome not like '%cannot be forwarded%' then failures := failures || format(E'\ndeleted: %s', outcome); end if;
  outcome := pg_temp.attempt(ada, format('select public.forward_messages_merged(array[%L::uuid, %L::uuid], %L::uuid, ''x'')', m_text, m_expired, dm));
  if outcome not like '%cannot be forwarded%' then failures := failures || format(E'\nexpired: %s', outcome); end if;
  outcome := pg_temp.attempt(ada, format('select public.forward_messages_merged(array[%L::uuid, %L::uuid], %L::uuid, ''x'')', m_text, m_held, dm));
  if outcome not like '%cannot be forwarded%' then failures := failures || format(E'\nwaiting for review: %s', outcome); end if;
  outcome := pg_temp.attempt(ada, format('select public.forward_messages_merged(array[%L::uuid, %L::uuid], %L::uuid, ''x'')', m_text, m_other_chat, tgt));
  if outcome not like '%cannot be forwarded%' then failures := failures || format(E'\ntwo chats: %s', outcome); end if;
  -- Dee is not a member of the source group: she cannot forward from it.
  outcome := pg_temp.attempt(dee, format('select public.forward_messages_merged(array[%L::uuid], %L::uuid, ''x'')', m_text, tgt));
  if outcome not like '%cannot be forwarded%' then failures := failures || format(E'\nnon-member forwarder: %s', outcome); end if;
  -- Target rules: a circle channel, a chat the forwarder is not in, a chat
  -- with someone who blocked her.
  outcome := pg_temp.attempt(bob, format('select public.forward_messages_merged(array[%L::uuid], %L::uuid, ''x'')', m_text, channel));
  if outcome not like '%direct chats and groups%' then failures := failures || format(E'\nchannel target: %s', outcome); end if;
  outcome := pg_temp.attempt(bob, format('select public.forward_messages_merged(array[%L::uuid], %L::uuid, ''x'')', m_text, tgt));
  if outcome not like '%cannot be forwarded%' then failures := failures || format(E'\nforeign target: %s', outcome); end if;
  outcome := pg_temp.attempt(ada, format('select public.forward_messages_merged(array[%L::uuid], %L::uuid, ''x'')', m_text, blocked));
  if outcome not like '%cannot be forwarded%' then failures := failures || format(E'\nblocked target: %s', outcome); end if;
  -- Counts: none, and 101.
  outcome := pg_temp.attempt(ada, format('select public.forward_messages_merged(array[]::uuid[], %L::uuid, ''x'')', dm));
  if outcome not like '%between 1 and 100%' then failures := failures || format(E'\nno messages: %s', outcome); end if;
  outcome := pg_temp.attempt(ada, format('select public.forward_messages_merged(array(select gen_random_uuid() from generate_series(1, 101)), %L::uuid, ''x'')', dm));
  if outcome not like '%between 1 and 100%' then failures := failures || format(E'\n101 messages: %s', outcome); end if;

  -- 100 is fine.
  insert into public.messages (conversation_id, sender_id, type, body)
  select src, ada, 'text', 'bulk ' || g from generate_series(1, 100) g;
  perform pg_temp.as_user(ada);
  if public.forward_messages_merged(
    array(select id from public.messages where conversation_id = src and body like 'bulk %'), tgt, 'Bulk')
    is null then
    failures := failures || E'\n100 messages were refused';
  end if;

  -- 3. A merged forward inside a merged forward: one level deep.
  insert into public.messages (conversation_id, sender_id, type, body)
  values (dm, ada, 'text', 'what do you think?') returning id into dm_text;
  update public.messages set created_at = now() + interval '1 minute' where id = dm_text;
  perform pg_temp.as_user(ada);
  bundle2_msg := public.forward_messages_merged(array[bundle_msg, dm_text], tgt, 'Ada and Dee');
  select b.items into items from public.message_bundles b where b.message_id = bundle2_msg;
  if items->0->'nested'->>'count' is distinct from '5'
    or jsonb_array_length(items->0->'nested'->'items') <> 5 then
    failures := failures || format(E'\nthe nested history was not kept: %s', items->0);
  end if;
  if items->0->'attachment'->>'kind' <> 'chat_history' then
    failures := failures || E'\nthe nested card has no marker line';
  end if;
  -- Eve (in the target group, not in the source or direct chat) reads the
  -- nested files too.
  n := pg_temp.as_count(eve, format($q$select count(*) from storage.objects where name = %L$q$, src || '/pic.png'));
  if n <> 1 then failures := failures || E'\nthe nested bundle did not carry the file access'; end if;
  -- A third level is flattened to a line.
  insert into public.messages (conversation_id, sender_id, type, body)
  values (tgt, ada, 'text', 'and then') returning id into m_text;
  update public.messages set created_at = now() + interval '2 minutes' where id = m_text;
  perform pg_temp.as_user(ada);
  bundle3_msg := public.forward_messages_merged(array[bundle2_msg, m_text], dm, 'Deep');
  select b.items into items from public.message_bundles b where b.message_id = bundle3_msg;
  if exists (
    select 1 from jsonb_array_elements(items->0->'nested'->'items') i where i ? 'nested'
  ) then
    failures := failures || E'\nthree levels of nesting were kept';
  end if;

  -- 4. Files stay with the bundle, and leave with the last bundle.
  -- Ada deletes the picture's own message: it is queued for removal, but
  -- the chat histories still show it.
  perform pg_temp.recall_bundle(ada, m_img);
  perform pg_temp.as_user(ada);
  if public.can_current_user_delete_recalled_media('chat-images', src || '/pic.png') then
    failures := failures || E'\na file a chat history still shows can be deleted';
  end if;

  -- Ada deletes the first chat history: its items go; the second one holds
  -- the same files in its nested history.
  perform pg_temp.recall_bundle(ada, bundle_msg);
  n := (select count(*) from public.message_bundles where message_id = bundle_msg);
  if n <> 0 then failures := failures || E'\na deleted chat history kept its items'; end if;
  n := pg_temp.as_count(dee, format($q$select count(*) from storage.objects where name = %L$q$, src || '/doc.pdf'));
  if n <> 1 then
    failures := failures || E'\nnested bundles lost the file after the outer one was deleted';
  end if;

  perform pg_temp.recall_bundle(ada, bundle2_msg);
  perform pg_temp.recall_bundle(ada, bundle3_msg);
  if (select expired from public.recalled_message_media where object_path = src || '/pic.png') then
    null;
  else
    failures := failures || E'\nthe file was not queued for removal after the last chat history went';
  end if;
  n := pg_temp.as_count(eve, format($q$select count(*) from storage.objects where name = %L$q$, src || '/pic.png'));
  if n <> 0 then failures := failures || E'\nthe file stayed readable after the last chat history was deleted'; end if;
  perform pg_temp.as_user(ada);
  if not public.can_current_user_delete_recalled_media('chat-images', src || '/pic.png') then
    failures := failures || E'\nthe file could not be deleted after the last chat history went';
  end if;

  -- 5. Contact cards: people.
  perform pg_temp.as_user(ada);
  declare card_id uuid; begin
    card_id := public.send_contact_card(tgt, 'user', bob);
    select attachment into card from public.messages where id = card_id;
    if card->>'card' <> 'user' or card->>'user_id' <> bob::text or card->>'name' <> 'Bob'
      or card->>'username' <> 'bob_mf' then
      failures := failures || format(E'\nthe user card is %s', card);
    end if;
    if (select body from public.messages where id = card_id) <> 'Contact card: Bob' then
      failures := failures || E'\nthe contact card fallback text is wrong';
    end if;
  end;
  -- Cy lets only friends see his profile: Ada is not one.
  outcome := pg_temp.attempt(ada, format('select public.send_contact_card(%L::uuid, ''user'', %L::uuid)', tgt, cy));
  if outcome not like '%cannot be shared%' then failures := failures || format(E'\nhidden profile was shared: %s', outcome); end if;
  -- Fay blocked Ada.
  outcome := pg_temp.attempt(ada, format('select public.send_contact_card(%L::uuid, ''user'', %L::uuid)', tgt, fay));
  if outcome not like '%cannot be shared%' then failures := failures || format(E'\nblocked person was shared: %s', outcome); end if;
  -- Kinds, targets and rooms the sender is not in.
  outcome := pg_temp.attempt(ada, format('select public.send_contact_card(%L::uuid, ''pet'', %L::uuid)', tgt, bob));
  if outcome not like '%Unknown contact card%' then failures := failures || format(E'\nunknown kind: %s', outcome); end if;
  outcome := pg_temp.attempt(bob, format('select public.send_contact_card(%L::uuid, ''user'', %L::uuid)', tgt, ada));
  if outcome not like '%cannot send%' then failures := failures || format(E'\nsent to a chat the sender is not in: %s', outcome); end if;
  outcome := pg_temp.attempt(ada, format('select public.send_contact_card(%L::uuid, ''user'', %L::uuid)', blocked, bob));
  if outcome not like '%Cannot send%' then failures := failures || format(E'\nsent where blocked: %s', outcome); end if;

  -- 6. Contact cards: circles.
  perform pg_temp.as_user(ada);
  declare first_id uuid; second_id uuid; code1 text; code2 text; begin
    first_id := public.send_contact_card(tgt, 'circle', circle);
    select attachment into card from public.messages where id = first_id;
    code1 := card->>'invite_code';
    if card->>'card' <> 'circle' or card->>'name' <> 'Mf circle'
      or (card->>'member_count')::int <> 2 or code1 !~ '^[a-z2-9]{10}$' then
      failures := failures || format(E'\nthe circle card is %s', card);
    end if;
    if not exists (select 1 from public.circle_invites where code = code1 and circle_id = circle and expires_at > now()) then
      failures := failures || E'\nthe card has no live invite';
    end if;
    second_id := public.send_contact_card(tgt, 'circle', circle);
    select attachment->>'invite_code' into code2 from public.messages where id = second_id;
    if code2 <> code1 then failures := failures || E'\nthe invite was not reused'; end if;
  end;
  -- Members can share while the circle lets everyone invite; not once it
  -- takes Create invites away; strangers never.
  outcome := pg_temp.attempt(bob, format('select public.send_contact_card(%L::uuid, ''circle'', %L::uuid)',
    (select id from ids where name = 'channel'), circle));
  if outcome <> 'ok' then failures := failures || format(E'\na member who may invite could not share: %s', outcome); end if;
  update public.circle_roles
  set permissions = permissions & ~public.circle_permission_bits(array['create_invites'])
  where circle_id = circle and is_default;
  outcome := pg_temp.attempt(bob, format('select public.send_contact_card(%L::uuid, ''circle'', %L::uuid)',
    (select id from ids where name = 'channel'), circle));
  if outcome not like '%cannot be shared%' then failures := failures || format(E'\na member without Create invites shared the circle: %s', outcome); end if;
  outcome := pg_temp.attempt(dee, format('select public.send_contact_card(%L::uuid, ''circle'', %L::uuid)', tgt, circle));
  if outcome not like '%cannot be shared%' then failures := failures || format(E'\na stranger shared the circle: %s', outcome); end if;

  if failures <> '' then
    raise exception 'merged forward checks failed:%', failures;
  end if;
end $$;

rollback;
