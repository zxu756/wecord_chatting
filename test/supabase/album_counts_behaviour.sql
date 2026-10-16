-- Behaviour checks for albums as one message (migrations 202610170002 to
-- 202610170004). Run by test/supabase/album_counts_behaviour_test.dart
-- against a local database that has the earlier migrations; it applies the
-- album migrations inside a transaction and rolls everything back, so the
-- database is left as it was. Run from the repository root.
\set ON_ERROR_STOP on

begin;

\i supabase/migrations/202610170002_album_counts.sql
\i supabase/migrations/202610170003_album_summaries.sql
\i supabase/migrations/202610170004_album_push.sql

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

-- Two people.
insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@album.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@album.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@album.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_album', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_album', 'Bob'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_album', 'Cy');

-- Ada has a group with Bob and Cy.
with conv as (
  insert into public.conversations (type, title) values ('group', 'Album group') returning id
), members as (
  insert into public.conversation_members (conversation_id, user_id, role)
  select conv.id, member.id, member.role
  from conv, (values
    ('00000000-0000-4000-8000-0000000000a1'::uuid, 'owner'),
    ('00000000-0000-4000-8000-0000000000b1'::uuid, 'member'),
    ('00000000-0000-4000-8000-0000000000c1'::uuid, 'member')
  ) as member(id, role)
)
insert into ids select 'group', id from conv;

-- A message helper: sends as Ada, one second after the last.
create function pg_temp.say(
  conv uuid,
  kind text,
  body text default '',
  grp uuid default null,
  attachment jsonb default null,
  at_offset integer default 0
) returns uuid language plpgsql as $$
declare
  new_id uuid;
begin
  insert into public.messages (
    conversation_id, sender_id, type, body, attachment, attachment_group_id, created_at
  ) values (
    conv, '00000000-0000-4000-8000-0000000000a1', kind, body, attachment, grp,
    timestamptz '2026-10-17 10:00:00+00' + make_interval(secs => at_offset)
  ) returning id into new_id;
  return new_id;
end $$;

do $$
declare
  conv uuid := (select id from ids where name = 'group');
  g1 uuid := gen_random_uuid();
  g2 uuid := gen_random_uuid();
  g3 uuid := gen_random_uuid();
  read_marker uuid;
  summary record;
  failures text := '';
begin
  -- Bob has read the first message.
  read_marker := pg_temp.say(conv, 'text', 'hello', null, null, 0);
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);
  perform public.mark_conversation_read(conv, read_marker);

  -- Then: one text, an album of 3 photos, a single photo, an album of
  -- 2 photos and a video.
  perform pg_temp.say(conv, 'text', 'look', null, null, 10);
  for i in 1..3 loop
    perform pg_temp.say(conv, 'image', '', g1,
      '{"kind":"image","mime_type":"image/jpeg"}'::jsonb, 20 + i);
  end loop;
  perform pg_temp.say(conv, 'image', '', null,
    '{"kind":"image","mime_type":"image/jpeg"}'::jsonb, 30);
  perform pg_temp.say(conv, 'image', '', g2,
    '{"kind":"image","mime_type":"image/jpeg"}'::jsonb, 41);
  perform pg_temp.say(conv, 'image', '', g2,
    '{"kind":"image","mime_type":"image/jpeg"}'::jsonb, 42);
  perform pg_temp.say(conv, 'file', '', g2,
    '{"kind":"video","mime_type":"video/mp4","name":"a.mp4"}'::jsonb, 43);

  select * into summary from public.list_conversation_summaries() where id = conv;

  -- 1 text + album of 3 + 1 photo + album of 3 = 4 messages to read.
  if summary.unread_count <> 4 then
    failures := failures || format(E'\nunread_count %s, expected 4', summary.unread_count);
  end if;
  if summary.last_message_album is distinct from
     '{"images":2,"videos":1,"files":0}'::jsonb then
    failures := failures || format(E'\nlast_message_album %s', summary.last_message_album);
  end if;

  -- An album of files shows as files; a deleted item leaves the others.
  for i in 1..4 loop
    perform pg_temp.say(conv, 'file', '', g3,
      '{"kind":"file","mime_type":"application/pdf","name":"a.pdf"}'::jsonb, 50 + i);
  end loop;
  select * into summary from public.list_conversation_summaries() where id = conv;
  if summary.last_message_album is distinct from
     '{"images":0,"videos":0,"files":4}'::jsonb then
    failures := failures || format(E'\nfiles album %s', summary.last_message_album);
  end if;
  if summary.unread_count <> 5 then
    failures := failures || format(E'\nunread_count %s, expected 5', summary.unread_count);
  end if;

  update public.messages
  set recalled_at = now()
  where attachment_group_id = g3
    and id in (
      select id from public.messages where attachment_group_id = g3
      order by created_at limit 2
    );
  select * into summary from public.list_conversation_summaries() where id = conv;
  if summary.last_message_album is distinct from
     '{"images":0,"videos":0,"files":2}'::jsonb then
    failures := failures || format(E'\nafter deleting %s', summary.last_message_album);
  end if;

  -- A single message that carries an album id (the rest not loaded or
  -- deleted) is a plain message in the preview.
  update public.messages set recalled_at = now()
  where attachment_group_id = g3
    and recalled_at is null
    and id <> (select id from public.messages where attachment_group_id = g3
               order by created_at desc limit 1);
  select * into summary from public.list_conversation_summaries() where id = conv;
  if summary.last_message_album is not null then
    failures := failures || format(E'\nalbum of one %s', summary.last_message_album);
  end if;

  if failures <> '' then
    raise exception 'album summary checks failed:%', failures;
  end if;
end $$;

-- Circles: the rail counts an album once, channel and thread alike.
do $$
declare
  circle uuid;
  channel_conv uuid;
  g uuid := gen_random_uuid();
  read_marker uuid;
  rail record;
  failures text := '';
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);
  circle := public.create_circle('Album circle', array[]::uuid[]);
  insert into public.circle_members (circle_id, user_id, role)
  values (circle, '00000000-0000-4000-8000-0000000000b1', 'member');
  select cc.conversation_id into channel_conv
  from public.circle_channels cc where cc.circle_id = circle order by cc.position limit 1;
  insert into public.conversation_members (conversation_id, user_id)
  values (channel_conv, '00000000-0000-4000-8000-0000000000b1')
  on conflict do nothing;

  read_marker := pg_temp.say(channel_conv, 'text', 'hi', null, null, 0);
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);
  perform public.mark_conversation_read(channel_conv, read_marker);

  perform pg_temp.say(channel_conv, 'text', 'two', null, null, 5);
  for i in 1..6 loop
    perform pg_temp.say(channel_conv, 'image', '', g,
      '{"kind":"image","mime_type":"image/jpeg"}'::jsonb, 10 + i);
  end loop;

  select * into rail from public.list_circle_summaries() where id = circle;
  if rail.unread_count <> 2 then
    failures := failures || format(E'\ncircle unread %s, expected 2', rail.unread_count);
  end if;

  if failures <> '' then
    raise exception 'album circle checks failed:%', failures;
  end if;
end $$;

-- Pushes: one per album, saying what it holds.
do $$
declare
  conv uuid := (select id from ids where name = 'group');
  g uuid := gen_random_uuid();
  first_id uuid;
  second_id uuid;
  single_id uuid;
  claimed record;
  n integer;
  failures text := '';
begin
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth)
  values ('00000000-0000-4000-8000-0000000000b1', 'https://push.test/bob', repeat('k', 60), repeat('a', 16));

  first_id := pg_temp.say(conv, 'image', 'caption', g,
    '{"kind":"image","mime_type":"image/jpeg"}'::jsonb, 100);
  second_id := pg_temp.say(conv, 'image', '', g,
    '{"kind":"image","mime_type":"image/jpeg"}'::jsonb, 101);
  perform pg_temp.say(conv, 'file', '', g,
    '{"kind":"video","mime_type":"video/mp4","name":"a.mp4"}'::jsonb, 102);

  select * into claimed
  from public.claim_push_delivery(second_id, '00000000-0000-4000-8000-0000000000a1');
  if claimed.body is distinct from 'sent 2 photos, 1 video' then
    failures := failures || format(E'\nalbum push body %s', claimed.body);
  end if;
  if claimed.title is distinct from 'Ada (Album group)' then
    failures := failures || format(E'\nalbum push title %s', claimed.title);
  end if;

  -- The other items of the album do not push again.
  select count(*) into n
  from public.claim_push_delivery(first_id, '00000000-0000-4000-8000-0000000000a1');
  if n <> 0 then
    failures := failures || format(E'\nsecond claim of the album sent %s', n);
  end if;

  -- A message on its own reads as before.
  single_id := pg_temp.say(conv, 'image', '', null,
    '{"kind":"image","mime_type":"image/jpeg"}'::jsonb, 110);
  select * into claimed
  from public.claim_push_delivery(single_id, '00000000-0000-4000-8000-0000000000a1');
  if claimed.body is distinct from '[Image]' then
    failures := failures || format(E'\nsingle push body %s', claimed.body);
  end if;

  if failures <> '' then
    raise exception 'album push checks failed:%', failures;
  end if;
end $$;

-- The inbox lists an album once.
do $$
declare
  conv uuid := (select id from ids where name = 'group');
  g uuid := gen_random_uuid();
  a uuid;
  b uuid;
  n integer;
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);
  -- Bob wrote a message; Ada replies with an album, each item a reply.
  insert into public.messages (conversation_id, sender_id, type, body, created_at)
  values (conv, '00000000-0000-4000-8000-0000000000b1', 'text', 'question',
          timestamptz '2026-10-17 11:00:00+00')
  returning id into a;
  for i in 1..3 loop
    insert into public.messages (
      conversation_id, sender_id, type, attachment, attachment_group_id,
      reply_to_message_id, created_at
    ) values (
      conv, '00000000-0000-4000-8000-0000000000a1', 'image',
      '{"kind":"image","mime_type":"image/jpeg"}'::jsonb, g, a,
      timestamptz '2026-10-17 11:00:00+00' + make_interval(secs => i)
    );
  end loop;
  select count(*) into n from public.list_inbox(50) where sender_id = '00000000-0000-4000-8000-0000000000a1';
  if n <> 1 then
    raise exception 'inbox listed the album % times', n;
  end if;
end $$;

rollback;
