-- Behaviour checks for QR codes, pat-pat and the note to self (migrations
-- 202610180030 to 202610180034). Run by test/supabase/qr_pat_note_test.dart
-- against the local database inside a transaction that is rolled back, so the
-- database is left as it was. It applies the earlier migrations it lacks,
-- then these five, plays several people and checks what they can do, see and
-- get pushed. Run from the repository root.
\set ON_ERROR_STOP on

begin;

-- One behaviour script at a time: they change the same tables.
do $$ begin perform pg_advisory_xact_lock(20261017); end $$;

\i supabase/migrations/202610170002_album_counts.sql
\i supabase/migrations/202610170003_album_summaries.sql
\i supabase/migrations/202610170004_album_push.sql
\i supabase/migrations/202610170005_push_language.sql
\i supabase/migrations/202610170020_disappearing_messages.sql
\i supabase/migrations/202610170021_view_once_media.sql
\i supabase/migrations/202610170090_ai_guard.sql
\i supabase/migrations/202610170091_ai_guard_hidden.sql
\i supabase/migrations/202610180030_user_qr_codes.sql
\i supabase/migrations/202610180031_group_qr_codes.sql
\i supabase/migrations/202610180032_pat.sql
\i supabase/migrations/202610180033_note_to_self.sql
\i supabase/migrations/202610180034_chat_list_pat_note.sql

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create temp table codes (name text primary key, code text not null);
grant all on codes to public;
create temp table group_codes (name text primary key, code text not null, expires_at timestamptz);
grant all on group_codes to public;
create temp table pat_ids (name text primary key, id uuid not null);
grant all on pat_ids to public;

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@qrpat.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bart@qrpat.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@qrpat.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d1', 'di@qrpat.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve@qrpat.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_qp', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bart_qp', 'Bart'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_qp', 'Cy'),
  ('00000000-0000-4000-8000-0000000000d1', 'di_qp', 'Di'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve_qp', 'Eve');

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

-- Runs [stmt] and fails unless it raises SQLSTATE [code].
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

-- ----------------------------------------------------------------- user QR

select pg_temp.act_as('a');
insert into codes select 'ada', public.get_my_qr_code();
select pg_temp.check('a code has 16 symbols and is not the user id',
  (select char_length(code) = 16 and code !~ '-' and code <> '00000000-0000-4000-8000-0000000000a1'
   from codes where name = 'ada'));
select pg_temp.check('asking again gives the same code',
  public.get_my_qr_code() = (select code from codes where name = 'ada'));
select pg_temp.act_as('b');
insert into codes select 'bart', public.get_my_qr_code();
select pg_temp.check('everyone has their own code',
  (select count(distinct code) = 2 from codes));

-- Scanning: the profile it leads to, in any case, nothing for junk.
select pg_temp.check('Bart resolves Ada''s code',
  (select count(*) = 1 and bool_and(user_id = '00000000-0000-4000-8000-0000000000a1' and username = 'ada_qp')
   from public.resolve_user_qr_code((select code from codes where name = 'ada'))));
select pg_temp.check('the code is read in upper case and with spaces',
  exists (select 1 from public.resolve_user_qr_code(' ' || upper((select code from codes where name = 'ada')) || ' ')));
select pg_temp.check('an unknown code leads nowhere',
  not exists (select 1 from public.resolve_user_qr_code('aaaaaaaaaaaaaaaa')));
select pg_temp.check('the user id is not a code',
  not exists (select 1 from public.resolve_user_qr_code('00000000-0000-4000-8000-0000000000a1')));
select pg_temp.act_as('a');
select pg_temp.check('Ada can scan her own code',
  exists (select 1 from public.resolve_user_qr_code((select code from codes where name = 'ada'))));

-- The tables are closed.
select pg_temp.refused('the codes cannot be read directly',
  'select * from public.user_qr_codes', '42501');
select pg_temp.refused('the codes cannot be written directly',
  $q$update public.user_qr_codes set code = 'mine'$q$, '42501');
select pg_temp.act_as(null);
select pg_temp.refused('signed-out callers cannot make a code',
  'select public.get_my_qr_code()', '42501');

-- Reset: the old code stops working at once.
select pg_temp.act_as('a');
insert into codes select 'ada_new', public.reset_my_qr_code();
select pg_temp.check('reset gives a different code',
  (select a.code <> n.code and char_length(n.code) = 16
   from codes a, codes n where a.name = 'ada' and n.name = 'ada_new'));
select pg_temp.check('get returns the new code from now on',
  public.get_my_qr_code() = (select code from codes where name = 'ada_new'));
select pg_temp.act_as('b');
select pg_temp.check('the old code is dead',
  not exists (select 1 from public.resolve_user_qr_code((select code from codes where name = 'ada'))));
select pg_temp.check('the new code works',
  exists (select 1 from public.resolve_user_qr_code((select code from codes where name = 'ada_new'))));

-- Blocks and deleted accounts look like "no such code".
select pg_temp.act_as(null);
insert into public.blocks (blocker_id, blocked_id)
values ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000b1');
select pg_temp.act_as('b');
select pg_temp.check('a blocked person cannot resolve the code',
  not exists (select 1 from public.resolve_user_qr_code((select code from codes where name = 'ada_new'))));
select pg_temp.act_as('a');
select pg_temp.check('the blocker cannot resolve the blocked person''s code either',
  not exists (select 1 from public.resolve_user_qr_code((select code from codes where name = 'bart'))));
select pg_temp.act_as(null);
delete from public.blocks;
update public.profiles set deleted_at = now() where id = '00000000-0000-4000-8000-0000000000e1';
select pg_temp.act_as('e');
insert into codes select 'eve', public.get_my_qr_code();
select pg_temp.act_as('a');
select pg_temp.check('a deleted account''s code leads nowhere',
  not exists (select 1 from public.resolve_user_qr_code((select code from codes where name = 'eve'))));
select pg_temp.act_as(null);
update public.profiles set deleted_at = null where id = '00000000-0000-4000-8000-0000000000e1';

-- ---------------------------------------------------------------- group QR

-- A group: Ada owns it, Bart is an admin, Cy a member. Di and Eve are outside.
insert into public.conversations (type, title) values ('group', 'Climbers');
insert into ids select 'group', id from public.conversations where title = 'Climbers';
insert into public.conversation_members (conversation_id, user_id, role)
select (select id from ids where name = 'group'), u.id, u.role
from (values
  ('00000000-0000-4000-8000-0000000000a1'::uuid, 'owner'),
  ('00000000-0000-4000-8000-0000000000b1'::uuid, 'admin'),
  ('00000000-0000-4000-8000-0000000000c1'::uuid, 'member')
) as u(id, role);
insert into public.conversations (type) values ('direct');
insert into ids select 'dm_ab', id from public.conversations where type = 'direct' and title is null;
insert into public.conversation_members (conversation_id, user_id)
select (select id from ids where name = 'dm_ab'), u.id
from (values ('00000000-0000-4000-8000-0000000000a1'::uuid), ('00000000-0000-4000-8000-0000000000b1'::uuid)) as u(id);

select pg_temp.act_as('c');
select pg_temp.refused('a plain member cannot make the group code',
  format('select public.get_group_qr(%L)', (select id from ids where name = 'group')), '42501');
select pg_temp.act_as('d');
select pg_temp.refused('an outsider cannot make the group code',
  format('select public.get_group_qr(%L)', (select id from ids where name = 'group')), '42501');
select pg_temp.act_as('a');
select pg_temp.refused('a direct chat has no group code',
  format('select public.get_group_qr(%L)', (select id from ids where name = 'dm_ab')), '42501');
insert into group_codes
select 'first', g->>'code', (g->>'expires_at')::timestamptz
from (select public.get_group_qr((select id from ids where name = 'group')) as g) q;
select pg_temp.check('the group code works for 7 days',
  (select char_length(code) = 16
     and expires_at > now() + interval '6 days 23 hours'
     and expires_at <= now() + interval '7 days 1 minute'
   from group_codes where name = 'first'));
select pg_temp.check('asking again returns the same code',
  public.get_group_qr((select id from ids where name = 'group'))->>'code'
    = (select code from group_codes where name = 'first'));
select pg_temp.act_as('b');
select pg_temp.check('an admin gets the same code',
  public.get_group_qr((select id from ids where name = 'group'))->>'code'
    = (select code from group_codes where name = 'first'));
select pg_temp.act_as('d');
select pg_temp.refused('the code table is closed',
  'select * from public.group_qr_codes', '42501');

-- Preview and join.
select pg_temp.check('Di sees the group before joining',
  (select p->>'state' = 'ok' and p->>'title' = 'Climbers'
     and (p->>'member_count')::int = 3 and (p->>'is_member')::boolean = false
   from (select public.preview_group_qr((select code from group_codes where name = 'first')) as p) q));
select pg_temp.check('an unknown group code is not found',
  public.preview_group_qr('zzzzzzzzzzzzzzzz')->>'state' = 'not_found'
  and public.preview_group_qr('zzzzzzzzzzzzzzzz')->>'title' is null);
select pg_temp.check('Di joins',
  public.join_group_by_qr((select code from group_codes where name = 'first'))->>'state' = 'joined');
select pg_temp.act_as(null);
select pg_temp.check('and is a plain member',
  exists (select 1 from public.conversation_members
          where conversation_id = (select id from ids where name = 'group')
            and user_id = '00000000-0000-4000-8000-0000000000d1' and role = 'member'));
select pg_temp.act_as('d');
select pg_temp.check('joining twice says so',
  public.join_group_by_qr((select code from group_codes where name = 'first'))->>'state' = 'already_member');
select pg_temp.check('a member who previews can still see the group',
  public.preview_group_qr((select code from group_codes where name = 'first'))->>'is_member' = 'true');

-- Refresh replaces the code; the old one is dead.
select pg_temp.act_as('a');
insert into group_codes
select 'second', g->>'code', (g->>'expires_at')::timestamptz
from (select public.get_group_qr((select id from ids where name = 'group'), true) as g) q;
select pg_temp.check('refresh gives a new code',
  (select a.code <> b.code from group_codes a, group_codes b where a.name = 'first' and b.name = 'second'));
select pg_temp.act_as('e');
select pg_temp.check('the old code leads nowhere',
  public.preview_group_qr((select code from group_codes where name = 'first'))->>'state' = 'not_found');
select pg_temp.check('the old code does not let Eve in',
  public.join_group_by_qr((select code from group_codes where name = 'first'))->>'state' = 'not_found');
select pg_temp.check('the new code does',
  public.preview_group_qr((select code from group_codes where name = 'second'))->>'state' = 'ok');

-- Blocks: the person who made the code blocked Eve.
select pg_temp.act_as(null);
insert into public.blocks (blocker_id, blocked_id)
values ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000e1');
select pg_temp.act_as('e');
select pg_temp.check('a blocked person finds nothing',
  public.preview_group_qr((select code from group_codes where name = 'second'))->>'state' = 'not_found'
  and public.join_group_by_qr((select code from group_codes where name = 'second'))->>'state' = 'not_found');
select pg_temp.act_as(null);
delete from public.blocks;

-- Expiry.
update public.group_qr_codes set expires_at = now() - interval '1 minute';
select pg_temp.act_as('e');
select pg_temp.check('an expired code says so and shows nothing',
  public.preview_group_qr((select code from group_codes where name = 'second'))->>'state' = 'expired'
  and public.preview_group_qr((select code from group_codes where name = 'second'))->>'title' is null);
select pg_temp.check('an expired code does not let anybody in',
  public.join_group_by_qr((select code from group_codes where name = 'second'))->>'state' = 'expired');
select pg_temp.act_as('b');
insert into group_codes
select 'third', g->>'code', (g->>'expires_at')::timestamptz
from (select public.get_group_qr((select id from ids where name = 'group')) as g) q;
select pg_temp.check('an admin asking again makes a fresh code',
  (select a.code <> b.code and b.expires_at > now() + interval '6 days'
   from group_codes a, group_codes b where a.name = 'second' and b.name = 'third'));

-- The code lasts only while the person who made it may add members.
select pg_temp.act_as(null);
update public.conversation_members set role = 'member'
where conversation_id = (select id from ids where name = 'group')
  and user_id = '00000000-0000-4000-8000-0000000000b1';
select pg_temp.act_as('e');
select pg_temp.check('a code made by a demoted admin stops working',
  public.preview_group_qr((select code from group_codes where name = 'third'))->>'state' = 'expired');
select pg_temp.act_as('a');
select pg_temp.check('the owner gets a new code instead',
  public.get_group_qr((select id from ids where name = 'group'))->>'code'
    <> (select code from group_codes where name = 'third'));

-- ------------------------------------------------------------------- pat-pat

-- A direct chat of Ada and Bart (Ada and Bart are friends in this world).
select pg_temp.act_as(null);
update public.conversation_members set role = 'admin'
where conversation_id = (select id from ids where name = 'group')
  and user_id = '00000000-0000-4000-8000-0000000000b1';
insert into public.push_subscriptions (user_id, endpoint, p256dh, auth)
values
  ('00000000-0000-4000-8000-0000000000a1', 'https://push.example/ada', repeat('p', 60), repeat('a', 20)),
  ('00000000-0000-4000-8000-0000000000b1', 'https://push.example/bart', repeat('p', 60), repeat('a', 20)),
  ('00000000-0000-4000-8000-0000000000c1', 'https://push.example/cy', repeat('p', 60), repeat('a', 20));

-- A text to start with, so there is an unread message and a latest message.
select pg_temp.act_as('a');
insert into ids select 'hello', public.send_text_message((select id from ids where name = 'dm_ab'), 'hello Bart');
select pg_temp.act_as(null);

-- Bart sets a suffix; it is trimmed, kept short and free of line breaks.
select pg_temp.act_as('b');
select pg_temp.check('the suffix starts empty', public.get_my_pat_suffix() = '');
select pg_temp.refused('a suffix of 21 characters is too long',
  $q$select public.set_my_pat_suffix(repeat('x', 21))$q$, '22023');
select pg_temp.check('line breaks go and the text is trimmed',
  public.set_my_pat_suffix(E'  ''s\nshoulder  ') = '''sshoulder');
select pg_temp.check('a suffix can be set',
  public.set_my_pat_suffix('''s shoulder') = '''s shoulder');
select pg_temp.check('and is read back',
  public.get_my_pat_suffix() = '''s shoulder');
select pg_temp.act_as('a');
select pg_temp.check('suffixes are private to their owners',
  public.get_my_pat_suffix() = '');
select pg_temp.refused('the suffix table is closed',
  'select * from public.pat_settings', '42501');

-- The first pat.
insert into pat_ids select 'p1', (p->>'message_id')::uuid
from (select public.pat_user((select id from ids where name = 'dm_ab'),
  '00000000-0000-4000-8000-0000000000b1') as p) q;
select pg_temp.act_as(null);
select pg_temp.check('the pat is a system line with the target''s suffix',
  (select m.type = 'system' and m.attachment->>'kind' = 'pat'
     and m.attachment->>'suffix' = '''s shoulder'
     and m.attachment->>'actor_id' = '00000000-0000-4000-8000-0000000000a1'
     and m.attachment->>'target_id' = '00000000-0000-4000-8000-0000000000b1'
     and m.attachment->>'target_name' = 'Bart'
     and m.body = 'Ada patted Bart''s shoulder'
   from public.messages m where m.id = (select id from pat_ids where name = 'p1')));

-- It is quiet: not unread, not the latest message, never pushed.
select pg_temp.act_as('b');
select pg_temp.check('Bart has one unread message, not two',
  (select s.unread_count = 1 from public.list_conversation_summaries() s
   where s.id = (select id from ids where name = 'dm_ab')));
select pg_temp.check('the latest message is still the text',
  (select s.last_message_body = 'hello Bart' from public.list_conversation_summaries() s
   where s.id = (select id from ids where name = 'dm_ab')));
select pg_temp.act_as(null);
select pg_temp.check('no push for a pat, for anyone',
  not exists (select 1 from public.claim_push_delivery(
    (select id from pat_ids where name = 'p1'),
    '00000000-0000-4000-8000-0000000000a1')));
select pg_temp.check('the text is still pushed to Bart',
  exists (select 1 from public.claim_push_delivery(
    (select id from ids where name = 'hello'),
    '00000000-0000-4000-8000-0000000000a1')));

-- Rate limits.
select pg_temp.act_as('a');
select pg_temp.refused('a second pat within 10 seconds is refused',
  format('select public.pat_user(%L, %L)', (select id from ids where name = 'dm_ab'), '00000000-0000-4000-8000-0000000000b1'),
  '53400');
select pg_temp.act_as(null);
update public.chat_pats set created_at = created_at - interval '30 seconds';
select pg_temp.act_as('a');
select pg_temp.check('after 10 seconds it works again',
  public.pat_user((select id from ids where name = 'dm_ab'), '00000000-0000-4000-8000-0000000000b1') is not null);
select pg_temp.act_as(null);
-- 18 more in the last hour, all older than 10 seconds: 20 in all.
insert into public.chat_pats (conversation_id, actor_id, target_id, created_at)
select (select id from ids where name = 'dm_ab'),
  '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000b1',
  now() - interval '5 minutes' - n * interval '1 second'
from generate_series(1, 18) n;
select pg_temp.act_as('a');
select pg_temp.refused('20 pats an hour for one person is the limit',
  format('select public.pat_user(%L, %L)', (select id from ids where name = 'dm_ab'), '00000000-0000-4000-8000-0000000000b1'),
  '53400');
select pg_temp.act_as(null);
delete from public.chat_pats where message_id is null;
update public.chat_pats set created_at = created_at - interval '2 hours';
select pg_temp.act_as('a');
select pg_temp.check('an hour later the allowance is back',
  public.pat_user((select id from ids where name = 'dm_ab'), '00000000-0000-4000-8000-0000000000b1') is not null);

-- Who can be patted where.
select pg_temp.refused('you cannot pat yourself',
  format('select public.pat_user(%L, %L)', (select id from ids where name = 'dm_ab'), '00000000-0000-4000-8000-0000000000a1'),
  '22023');
select pg_temp.refused('you cannot pat someone who is not in the chat',
  format('select public.pat_user(%L, %L)', (select id from ids where name = 'dm_ab'), '00000000-0000-4000-8000-0000000000c1'),
  '42501');
select pg_temp.act_as('c');
select pg_temp.refused('you cannot pat in a chat you are not in',
  format('select public.pat_user(%L, %L)', (select id from ids where name = 'dm_ab'), '00000000-0000-4000-8000-0000000000a1'),
  '42501');
select pg_temp.act_as('a');
select pg_temp.check('in a group the line is for everybody',
  public.pat_user((select id from ids where name = 'group'), '00000000-0000-4000-8000-0000000000c1') is not null);

-- Pats and circle channels do not mix.
select pg_temp.act_as('a');
insert into ids select 'circle', public.create_circle('Pat circle', array[]::uuid[]);
select pg_temp.act_as(null);
insert into ids
select 'channel', cc.conversation_id
from public.circle_channels cc
where cc.circle_id = (select id from ids where name = 'circle') and cc.position = 0;
select pg_temp.act_as('a');
select pg_temp.refused('circle channels have no pats',
  format('select public.pat_user(%L, %L)', (select id from ids where name = 'channel'), '00000000-0000-4000-8000-0000000000a1'),
  '22023');

-- Blocks.
select pg_temp.act_as(null);
update public.chat_pats set created_at = created_at - interval '1 minute';
insert into public.blocks (blocker_id, blocked_id)
values ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1');
select pg_temp.act_as('a');
select pg_temp.refused('a blocked person cannot pat',
  format('select public.pat_user(%L, %L)', (select id from ids where name = 'dm_ab'), '00000000-0000-4000-8000-0000000000b1'),
  '42501');
select pg_temp.act_as('b');
select pg_temp.refused('and the blocker cannot pat the blocked',
  format('select public.pat_user(%L, %L)', (select id from ids where name = 'dm_ab'), '00000000-0000-4000-8000-0000000000a1'),
  '42501');
select pg_temp.act_as(null);
delete from public.blocks;

-- Undo.
update public.chat_pats set created_at = created_at - interval '1 minute';
select pg_temp.act_as('b');
select pg_temp.refused('only the patter can take a pat back',
  format('select public.undo_pat(%L)', (select id from pat_ids where name = 'p1')), '42501');
select pg_temp.act_as('a');
insert into pat_ids select 'p2', (p->>'message_id')::uuid
from (select public.pat_user((select id from ids where name = 'dm_ab'),
  '00000000-0000-4000-8000-0000000000b1') as p) q;
select public.undo_pat((select id from pat_ids where name = 'p2'));
select pg_temp.act_as('b');
select pg_temp.check('the line now says it was taken back, for Bart too',
  (select m.attachment->>'undone' = 'true' and m.body = 'Ada took back a pat'
     and m.attachment->>'kind' = 'pat'
   from public.messages m where m.id = (select id from pat_ids where name = 'p2')));
select pg_temp.act_as('a');
select public.undo_pat((select id from pat_ids where name = 'p2'));
select pg_temp.check('taking it back twice is harmless', true);
select pg_temp.act_as(null);
update public.messages set created_at = now() - interval '3 minutes'
where id = (select id from pat_ids where name = 'p1');
select pg_temp.act_as('a');
select pg_temp.refused('after 2 minutes it is too late',
  format('select public.undo_pat(%L)', (select id from pat_ids where name = 'p1')), '22023');
select pg_temp.act_as(null);
select pg_temp.check('an undone pat still counts for the limits',
  (select count(*) from public.chat_pats where message_id = (select id from pat_ids where name = 'p2')) = 1);
select pg_temp.act_as('a');
select pg_temp.refused('text messages cannot be taken back as pats',
  format('select public.undo_pat(%L)', (select id from ids where name = 'hello')), '42501');

-- A pat cannot be forged by a client.
select pg_temp.refused('a client cannot insert a system line',
  format($q$insert into public.messages (conversation_id, sender_id, type, body, attachment)
    values (%L, auth.uid(), 'system', 'Ada patted Bart', '{"kind":"pat"}')$q$,
    (select id from ids where name = 'dm_ab')),
  '42501');

-- ------------------------------------------------------------- note to self

select pg_temp.act_as('a');
select pg_temp.check('there is no note to self until it is asked for',
  public.get_note_to_self(false) is null);
insert into ids select 'ada_note', public.get_note_to_self();
select pg_temp.check('asking again returns the same chat',
  public.get_note_to_self() = (select id from ids where name = 'ada_note')
  and public.get_note_to_self(false) = (select id from ids where name = 'ada_note'));
select pg_temp.act_as('b');
insert into ids select 'bart_note', public.get_note_to_self();
select pg_temp.check('everyone has their own',
  (select count(distinct id) = 2 from ids where name in ('ada_note', 'bart_note')));
select pg_temp.act_as(null);
select pg_temp.check('it is a direct chat with one member, its owner',
  (select c.type = 'direct'
     and (select count(*) from public.conversation_members cm where cm.conversation_id = c.id) = 1
     and exists (select 1 from public.conversation_members cm
                 where cm.conversation_id = c.id
                   and cm.user_id = '00000000-0000-4000-8000-0000000000a1')
   from public.conversations c where c.id = (select id from ids where name = 'ada_note')));
select pg_temp.refused('nobody else can be added',
  format($q$insert into public.conversation_members (conversation_id, user_id)
    values (%L, '00000000-0000-4000-8000-0000000000b1')$q$, (select id from ids where name = 'ada_note')),
  '42501');
select pg_temp.act_as('a');
select pg_temp.refused('nor through the group function',
  format($q$select public.add_group_members(%L, array['00000000-0000-4000-8000-0000000000b1'::uuid])$q$,
    (select id from ids where name = 'ada_note')),
  '42501');

-- Sending works like anywhere.
insert into ids select 'note_text', public.send_text_message((select id from ids where name = 'ada_note'), 'link for my laptop');
insert into public.messages (conversation_id, sender_id, type, body, attachment)
values ((select id from ids where name = 'ada_note'), auth.uid(), 'file', 'report.pdf',
  jsonb_build_object('kind', 'file', 'name', 'report.pdf',
    'path', (select id from ids where name = 'ada_note')::text || '/report.pdf', 'size', 10, 'mime_type', 'application/pdf'));
select pg_temp.check('Ada reads her notes',
  (select count(*) = 2 from public.messages m where m.conversation_id = (select id from ids where name = 'ada_note')));
select pg_temp.check('the blocked-check does not trip on a chat with nobody else',
  not public.is_current_user_blocked_in_conversation((select id from ids where name = 'ada_note')));

-- The list: first, flagged, never unread.
select pg_temp.act_as(null);
update public.conversation_members set pinned_at = now() + interval '1 hour'
where conversation_id = (select id from ids where name = 'dm_ab')
  and user_id = '00000000-0000-4000-8000-0000000000a1';
select pg_temp.act_as('a');
select pg_temp.check('the note to self is the first row, above a chat pinned later',
  (select s.id = (select id from ids where name = 'ada_note') and s.is_note_to_self
   from public.list_conversation_summaries() s limit 1));
select pg_temp.check('other chats are not flagged',
  (select count(*) = 1 from public.list_conversation_summaries() s where s.is_note_to_self));
select pg_temp.check('it never counts as unread, even before anything was read',
  (select s.unread_count = 0 and s.member_count = 1
   from public.list_conversation_summaries() s where s.id = (select id from ids where name = 'ada_note')));
select pg_temp.check('the title is Note to self',
  (select s.title = 'Note to self'
   from public.list_conversation_summaries() s where s.id = (select id from ids where name = 'ada_note')));
select pg_temp.act_as('b');
select pg_temp.check('Bart does not see Ada''s note, nor its messages',
  not exists (select 1 from public.list_conversation_summaries() s where s.id = (select id from ids where name = 'ada_note'))
  and not exists (select 1 from public.messages m where m.conversation_id = (select id from ids where name = 'ada_note')));
select pg_temp.refused('Bart cannot write in it',
  format($q$select public.send_text_message(%L, 'hi')$q$, (select id from ids where name = 'ada_note')), '42501');
select pg_temp.refused('nor insert into it',
  format($q$insert into public.messages (conversation_id, sender_id, type, body)
    values (%L, auth.uid(), 'text', 'hi')$q$, (select id from ids where name = 'ada_note')), '42501');
select pg_temp.refused('nor pat in it',
  format($q$select public.pat_user(%L, '00000000-0000-4000-8000-0000000000a1')$q$,
    (select id from ids where name = 'ada_note')), '42501');
select pg_temp.act_as('a');
select pg_temp.refused('nor can Ada pat herself there',
  format($q$select public.pat_user(%L, '00000000-0000-4000-8000-0000000000a1')$q$,
    (select id from ids where name = 'ada_note')), '22023');

-- No push, to anybody (not even Ada's other devices: pushes do not know the
-- device).
select pg_temp.act_as(null);
select pg_temp.check('a note to self is never pushed',
  not exists (select 1 from public.claim_push_delivery(
    (select id from ids where name = 'note_text'),
    '00000000-0000-4000-8000-0000000000a1')));

-- A note to self survives the chat list's other rules: hiding and reading.
select pg_temp.act_as('a');
select pg_temp.check('reading it moves nothing and counts nothing',
  (select s.unread_count = 0 from public.list_conversation_summaries() s
   where s.id = (select id from ids where name = 'ada_note')));

rollback;
