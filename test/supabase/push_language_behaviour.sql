-- Behaviour checks for push text in the recipient's language (migration
-- 202610170005). Run by test/supabase/push_language_behaviour_test.dart
-- against a local database that has the earlier migrations; it applies the
-- album and push migrations inside a transaction and rolls everything back,
-- so the database is left as it was. Run from the repository root.
\set ON_ERROR_STOP on

begin;

-- The behaviour scripts run side by side and apply DDL: take turns.
do $$ begin perform pg_advisory_xact_lock(20261017); end $$;

\i supabase/migrations/202610170002_album_counts.sql
\i supabase/migrations/202610170003_album_summaries.sql
\i supabase/migrations/202610170004_album_push.sql
\i supabase/migrations/202610170005_push_language.sql

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a2', 'ada@lang.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b2', 'bob@lang.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c2', 'cy@lang.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a2', 'ada_lang', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b2', 'bob_lang', 'Bob'),
  ('00000000-0000-4000-8000-0000000000c2', 'cy_lang', 'Cy');

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

-- Ada's group with Bob (English) and Cy (Chinese), and a direct chat with
-- Cy.
with conv as (
  insert into public.conversations (type, title) values ('group', 'Lang group') returning id
), members as (
  insert into public.conversation_members (conversation_id, user_id, role)
  select conv.id, member.id, member.role
  from conv, (values
    ('00000000-0000-4000-8000-0000000000a2'::uuid, 'owner'),
    ('00000000-0000-4000-8000-0000000000b2'::uuid, 'member'),
    ('00000000-0000-4000-8000-0000000000c2'::uuid, 'member')
  ) as member(id, role)
)
insert into ids select 'group', id from conv;

create function pg_temp.say(
  conv uuid,
  kind text,
  body text default '',
  grp uuid default null,
  attachment jsonb default null,
  at_offset integer default 0,
  sender uuid default '00000000-0000-4000-8000-0000000000a2'
) returns uuid language plpgsql as $$
declare
  new_id uuid;
begin
  insert into public.messages (
    conversation_id, sender_id, type, body, attachment, attachment_group_id, created_at
  ) values (
    conv, sender, kind, body, attachment, grp,
    timestamptz '2026-10-17 10:00:00+00' + make_interval(secs => at_offset)
  ) returning id into new_id;
  return new_id;
end $$;

-- The subscription language is saved by register_push_subscription, from
-- the caller, defaulting to English and ignoring anything but 'zh'.
do $$
declare
  failures text := '';
  lang text;
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b2', true);
  perform public.register_push_subscription(
    'https://push.test/bob', repeat('k', 60), repeat('a', 16), 'ua');
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c2', true);
  perform public.register_push_subscription(
    'https://push.test/cy', repeat('k', 60), repeat('a', 16), 'ua', 'zh');

  select s.language into lang from public.push_subscriptions s where s.endpoint = 'https://push.test/bob';
  if lang is distinct from 'en' then
    failures := failures || format(E'\nbob language %s', lang);
  end if;
  select s.language into lang from public.push_subscriptions s where s.endpoint = 'https://push.test/cy';
  if lang is distinct from 'zh' then
    failures := failures || format(E'\ncy language %s', lang);
  end if;

  -- Saving again with another language (the setting changed) updates it.
  perform public.register_push_subscription(
    'https://push.test/cy', repeat('k', 60), repeat('a', 16), 'ua', 'fr');
  select s.language into lang from public.push_subscriptions s where s.endpoint = 'https://push.test/cy';
  if lang is distinct from 'en' then
    failures := failures || format(E'\ncy language after unknown %s', lang);
  end if;
  perform public.register_push_subscription(
    'https://push.test/cy', repeat('k', 60), repeat('a', 16), 'ua', 'zh');

  begin
    insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
    values ('00000000-0000-4000-8000-0000000000c2', 'https://push.test/bad',
            repeat('k', 60), repeat('a', 16), 'fr');
    failures := failures || E'\nlanguage check missing';
  exception when check_violation then
    null;
  end;

  if failures <> '' then
    raise exception 'push language registration checks failed:%', failures;
  end if;
end $$;

-- Each recipient gets the text in their language.
do $$
declare
  conv uuid := (select id from ids where name = 'group');
  ada uuid := '00000000-0000-4000-8000-0000000000a2';
  g uuid := gen_random_uuid();
  msg uuid;
  last_id uuid;
  en record;
  zh record;
  n integer;
  failures text := '';
begin
  -- Text is the same in both languages.
  msg := pg_temp.say(conv, 'text', 'hello   there', null, null, 0);
  create temp table claimed_text on commit drop as
    select * from public.claim_push_delivery(msg, ada);
  select * into en from claimed_text where endpoint = 'https://push.test/bob';
  select * into zh from claimed_text where endpoint = 'https://push.test/cy';
  if en.body is distinct from 'hello there' or en.title is distinct from 'Ada (Lang group)' then
    failures := failures || format(E'\ntext en %s / %s', en.title, en.body);
  end if;
  if zh.body is distinct from 'hello there' then
    failures := failures || format(E'\ntext zh %s', zh.body);
  end if;

  -- One claim returns every subscription, each in its own language.
  msg := pg_temp.say(conv, 'image', '', null,
    '{"kind":"image","mime_type":"image/jpeg"}'::jsonb, 10);
  create temp table claimed_image on commit drop as
    select * from public.claim_push_delivery(msg, ada);
  select * into en from claimed_image where endpoint = 'https://push.test/bob';
  select * into zh from claimed_image where endpoint = 'https://push.test/cy';
  if en.body is distinct from '[Image]' then
    failures := failures || format(E'\nimage en %s', en.body);
  end if;
  if zh.body is distinct from '[图片]' then
    failures := failures || format(E'\nimage zh %s', zh.body);
  end if;
  if zh.title is distinct from 'Ada (Lang group)' then
    failures := failures || format(E'\nimage zh title %s', zh.title);
  end if;

  -- Other kinds.
  msg := pg_temp.say(conv, 'voice', '', null, '{"kind":"voice"}'::jsonb, 11);
  create temp table claimed_voice on commit drop as
    select * from public.claim_push_delivery(msg, ada);
  if (select body from claimed_voice where endpoint = 'https://push.test/cy') is distinct from '[语音消息]'
     or (select body from claimed_voice where endpoint = 'https://push.test/bob') is distinct from '[Voice message]' then
    failures := failures || E'\nvoice';
  end if;

  msg := pg_temp.say(conv, 'file', '', null,
    '{"kind":"video","mime_type":"video/mp4"}'::jsonb, 12);
  create temp table claimed_video on commit drop as
    select * from public.claim_push_delivery(msg, ada);
  if (select body from claimed_video where endpoint = 'https://push.test/cy') is distinct from '[视频]' then
    failures := failures || E'\nvideo zh';
  end if;

  msg := pg_temp.say(conv, 'file', '', null,
    '{"kind":"file","mime_type":"application/pdf"}'::jsonb, 13);
  create temp table claimed_file on commit drop as
    select * from public.claim_push_delivery(msg, ada);
  if (select body from claimed_file where endpoint = 'https://push.test/cy') is distinct from '[文件]'
     or (select body from claimed_file where endpoint = 'https://push.test/bob') is distinct from '[File]' then
    failures := failures || E'\nfile';
  end if;

  -- Albums.
  perform pg_temp.say(conv, 'image', 'caption', g,
    '{"kind":"image","mime_type":"image/jpeg"}'::jsonb, 20);
  perform pg_temp.say(conv, 'image', '', g,
    '{"kind":"image","mime_type":"image/jpeg"}'::jsonb, 21);
  last_id := pg_temp.say(conv, 'image', '', g,
    '{"kind":"image","mime_type":"image/jpeg"}'::jsonb, 22);
  create temp table claimed_album on commit drop as
    select * from public.claim_push_delivery(last_id, ada);
  if (select body from claimed_album where endpoint = 'https://push.test/cy') is distinct from '发来 3 张照片'
     or (select body from claimed_album where endpoint = 'https://push.test/bob') is distinct from 'sent 3 photos' then
    failures := failures || format(E'\nalbum photos: %s',
      (select string_agg(endpoint || '=' || body, '; ') from claimed_album));
  end if;

  g := gen_random_uuid();
  perform pg_temp.say(conv, 'image', '', g,
    '{"kind":"image","mime_type":"image/jpeg"}'::jsonb, 30);
  perform pg_temp.say(conv, 'image', '', g,
    '{"kind":"image","mime_type":"image/jpeg"}'::jsonb, 31);
  last_id := pg_temp.say(conv, 'file', '', g,
    '{"kind":"video","mime_type":"video/mp4"}'::jsonb, 32);
  create temp table claimed_mixed on commit drop as
    select * from public.claim_push_delivery(last_id, ada);
  if (select body from claimed_mixed where endpoint = 'https://push.test/cy') is distinct from '发来 2 张照片、1 个视频'
     or (select body from claimed_mixed where endpoint = 'https://push.test/bob') is distinct from 'sent 2 photos, 1 video' then
    failures := failures || format(E'\nalbum mixed: %s',
      (select string_agg(endpoint || '=' || body, '; ') from claimed_mixed));
  end if;

  g := gen_random_uuid();
  perform pg_temp.say(conv, 'file', '', g,
    '{"kind":"file","mime_type":"application/pdf"}'::jsonb, 40);
  last_id := pg_temp.say(conv, 'file', '', g,
    '{"kind":"file","mime_type":"application/pdf"}'::jsonb, 41);
  create temp table claimed_files on commit drop as
    select * from public.claim_push_delivery(last_id, ada);
  if (select body from claimed_files where endpoint = 'https://push.test/cy') is distinct from '发来 2 个文件' then
    failures := failures || format(E'\nalbum files: %s',
      (select string_agg(endpoint || '=' || body, '; ') from claimed_files));
  end if;

  -- A call notice: "Ada started a call." for English, 发起了通话 for Chinese.
  msg := pg_temp.say(conv, 'system', 'Ada started a call.', null,
    '{"kind":"call"}'::jsonb, 50);
  create temp table claimed_call on commit drop as
    select * from public.claim_push_delivery(msg, ada);
  if (select body from claimed_call where endpoint = 'https://push.test/bob') is distinct from 'Ada started a call.'
     or (select body from claimed_call where endpoint = 'https://push.test/cy') is distinct from 'Ada 发起了通话' then
    failures := failures || format(E'\ncall: %s',
      (select string_agg(endpoint || '=' || body, '; ') from claimed_call));
  end if;

  if failures <> '' then
    raise exception 'push language checks failed:%', failures;
  end if;
end $$;

rollback;
