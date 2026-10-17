-- Behaviour checks for sending a location and sharing it live (migration
-- 202610180050). Run by test/supabase/location_test.dart against a local
-- database that has the earlier migrations; it applies the ones it lacks and
-- this one inside a transaction, acts as several people, checks what they can
-- send, see and listen to, and rolls back, so the database is left as it was.
-- Run from the repository root.
\set ON_ERROR_STOP on

begin;

-- One behaviour script at a time: they change the same tables, and test
-- files run in parallel.
do $$ begin perform pg_advisory_xact_lock(20261017); end $$;

\i supabase/migrations/202610170002_album_counts.sql
\i supabase/migrations/202610170003_album_summaries.sql
\i supabase/migrations/202610170004_album_push.sql
\i supabase/migrations/202610170005_push_language.sql
\i supabase/migrations/202610170020_disappearing_messages.sql
\i supabase/migrations/202610170021_view_once_media.sql
\i supabase/migrations/202610170090_ai_guard.sql
\i supabase/migrations/202610170091_ai_guard_hidden.sql
\i supabase/migrations/202610180050_location.sql

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@loc.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@loc.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@loc.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee@loc.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve@loc.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_loc', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_loc', 'Bob'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_loc', 'Cy'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee_loc', 'Dee'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve_loc', 'Eve');

-- Ada and Bob chat directly. Ada, Bob, Cy and Dee are a group. Eve is in
-- neither. A channel with a member (not a circle) stands for the rest.
with dm as (
  insert into public.conversations (type) values ('direct') returning id
), dm_members as (
  insert into public.conversation_members (conversation_id, user_id)
  select dm.id, member.id
  from dm, (values
    ('00000000-0000-4000-8000-0000000000a1'::uuid),
    ('00000000-0000-4000-8000-0000000000b1'::uuid)
  ) as member(id)
), grp as (
  insert into public.conversations (type, title) values ('group', 'Walkers') returning id
), grp_members as (
  insert into public.conversation_members (conversation_id, user_id)
  select grp.id, member.id
  from grp, (values
    ('00000000-0000-4000-8000-0000000000a1'::uuid),
    ('00000000-0000-4000-8000-0000000000b1'::uuid),
    ('00000000-0000-4000-8000-0000000000c1'::uuid),
    ('00000000-0000-4000-8000-0000000000d1'::uuid)
  ) as member(id)
), chan as (
  insert into public.conversations (type, title) values ('channel', 'general') returning id
), chan_members as (
  insert into public.conversation_members (conversation_id, user_id)
  select chan.id, '00000000-0000-4000-8000-0000000000a1'::uuid from chan
)
insert into ids
select 'dm', id from dm
union all select 'group', id from grp
union all select 'channel', id from chan;

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

create function pg_temp.id_of(n text) returns uuid language sql as $$
  select id from ids where name = n;
$$;
grant execute on function pg_temp.id_of(text) to public;

-- Who listens: the policy on realtime.messages for a share's topic, asked as
-- [who] (null: nobody signed in). [role_op] is 'listen' or 'send'.
create function pg_temp.topic_allows(who text, share uuid, role_op text)
returns boolean language plpgsql as $$
declare
  allowed boolean;
begin
  if who = 'anon' then
    perform pg_temp.act_as(null);
    execute 'set local role anon';
  else
    perform pg_temp.act_as(who);
  end if;
  perform set_config('realtime.topic', 'live-location:' || share, true);
  if role_op = 'listen' then
    begin
      select exists (select 1 from realtime.messages where topic = 'live-location:' || share)
      into allowed;
    exception when insufficient_privilege then
      allowed := false;
    end;
  else
    begin
      insert into realtime.messages (topic, extension, payload, event, private)
      values ('live-location:' || share, 'broadcast', '{"lat":1}', 'pos', true);
      allowed := true;
    exception when insufficient_privilege then
      allowed := false;
    end;
  end if;
  perform pg_temp.act_as(null);
  return allowed;
end;
$$;
grant execute on function pg_temp.topic_allows(text, uuid, text) to public;

-- A message in the channel positions table is needed for the listen check:
-- one broadcast row on a share's topic (written by the server).
create function pg_temp.seed_position(share uuid) returns void language plpgsql as $$
begin
  perform pg_temp.act_as(null);
  insert into realtime.messages (topic, extension, payload, event, private)
  values ('live-location:' || share, 'broadcast', '{"lat":1}', 'pos', true);
end;
$$;

-- A location card ------------------------------------------------------------

select pg_temp.act_as('a');
insert into ids
select 'card', public.send_location(
  pg_temp.id_of('dm'), 51.5007, -0.1246, 'Big Ben', 'Westminster, London'
);
select pg_temp.act_as(null);

select pg_temp.check(
  'a location is a text message with a readable body and the place in its attachment',
  exists (
    select 1 from public.messages m
    where m.id = pg_temp.id_of('card')
      and m.type = 'text'
      and m.body = '📍 Big Ben · Westminster, London'
      and m.attachment->>'kind' = 'location'
      and (m.attachment->>'lat')::double precision = 51.5007
      and (m.attachment->>'lng')::double precision = -0.1246
      and m.attachment->>'name' = 'Big Ben'
      and m.attachment->>'address' = 'Westminster, London'
      and m.sender_id = '00000000-0000-4000-8000-0000000000a1'
  )
);

select pg_temp.act_as('b');
select pg_temp.check(
  'the other member sees the card',
  exists (select 1 from public.messages where id = pg_temp.id_of('card'))
);
select pg_temp.act_as('e');
select pg_temp.check(
  'someone outside the chat does not',
  not exists (select 1 from public.messages where id = pg_temp.id_of('card'))
);
select pg_temp.act_as(null);

select pg_temp.act_as('a');
insert into ids select 'bare', public.send_location(pg_temp.id_of('group'), 10, 20);
select pg_temp.check(
  'a place without a name is shown by its coordinates',
  exists (
    select 1 from public.messages m
    where m.id = pg_temp.id_of('bare') and m.body = '📍 10.00000, 20.00000'
  )
);
select pg_temp.refused(
  'a latitude off the globe is refused',
  format('select public.send_location(%L, 91, 0)', pg_temp.id_of('dm')),
  '22023'
);
select pg_temp.refused(
  'a longitude off the globe is refused',
  format('select public.send_location(%L, 0, 181)', pg_temp.id_of('dm')),
  '22023'
);
select pg_temp.act_as('e');
select pg_temp.refused(
  'someone outside the chat cannot send a location into it',
  format('select public.send_location(%L, 1, 2, %L)', pg_temp.id_of('dm'), 'x'),
  '42501'
);
select pg_temp.act_as(null);

-- Live sharing: starting ------------------------------------------------------

select pg_temp.act_as('b');
insert into ids
select 'share', s.share_id from public.start_live_location(pg_temp.id_of('group'), 15, false) s;
insert into ids
select 'share_card', s.message_id
from public.live_location_shares s where s.id = pg_temp.id_of('share');
select pg_temp.act_as(null);

select pg_temp.check(
  'a share runs for the time asked, from now',
  exists (
    select 1 from public.live_location_shares s
    where s.id = pg_temp.id_of('share')
      and s.user_id = '00000000-0000-4000-8000-0000000000b1'
      and s.conversation_id = pg_temp.id_of('group')
      and s.stopped_at is null
      and not s.precise
      and s.ends_at between now() + interval '14 minutes' and now() + interval '16 minutes'
  )
);
select pg_temp.check(
  'the card names the share and no position is stored anywhere in it',
  exists (
    select 1 from public.messages m
    where m.id = pg_temp.id_of('share_card')
      and m.attachment->>'kind' = 'live_location'
      and (m.attachment->>'share_id')::uuid = pg_temp.id_of('share')
      and not (m.attachment ? 'lat')
      and m.body = '📍 Live location'
  )
);
select pg_temp.check(
  'the table has no column for a position',
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'live_location_shares'
      and column_name in ('lat', 'lng', 'latitude', 'longitude', 'position', 'location')
  )
);

select pg_temp.act_as('b');
select pg_temp.refused(
  'sharing for no time is refused',
  format('select public.start_live_location(%L, 0)', pg_temp.id_of('group')),
  '22023'
);
select pg_temp.refused(
  'sharing for more than 8 hours is refused',
  format('select public.start_live_location(%L, 481)', pg_temp.id_of('group')),
  '22023'
);
select pg_temp.act_as('a');
select pg_temp.refused(
  'live sharing is not offered in channels',
  format('select public.start_live_location(%L, 15)', pg_temp.id_of('channel')),
  '22023'
);
select pg_temp.act_as('e');
select pg_temp.refused(
  'someone outside the chat cannot start sharing in it',
  format('select public.start_live_location(%L, 15)', pg_temp.id_of('group')),
  '42501'
);
select pg_temp.refused(
  'clients cannot write shares directly',
  format(
    'insert into public.live_location_shares (conversation_id, user_id, ends_at) values (%L, %L, now() + interval ''1 hour'')',
    pg_temp.id_of('group'), '00000000-0000-4000-8000-0000000000e1'
  ),
  '42501'
);
select pg_temp.act_as(null);

-- Who sees the share -------------------------------------------------------------

select pg_temp.act_as('c');
select pg_temp.check(
  'another member sees who is sharing',
  (select count(*) from public.list_live_location_shares(pg_temp.id_of('group'))) = 1
  and (select display_name from public.list_live_location_shares(pg_temp.id_of('group'))) = 'Bob'
  and (select count(*) from public.live_location_shares) = 1
);
select pg_temp.act_as('e');
select pg_temp.check(
  'someone outside the chat sees nothing',
  (select count(*) from public.list_live_location_shares(pg_temp.id_of('group'))) = 0
  and (select count(*) from public.live_location_shares) = 0
);
select pg_temp.act_as(null);

-- The channel of positions ---------------------------------------------------------

select pg_temp.seed_position(pg_temp.id_of('share'));
select pg_temp.check('the sharer may send on the share''s channel', pg_temp.topic_allows('b', pg_temp.id_of('share'), 'send'));
select pg_temp.check('another member may not send on it', not pg_temp.topic_allows('c', pg_temp.id_of('share'), 'send'));
select pg_temp.check('someone outside the chat may not send on it', not pg_temp.topic_allows('e', pg_temp.id_of('share'), 'send'));
select pg_temp.check('a member may listen', pg_temp.topic_allows('c', pg_temp.id_of('share'), 'listen'));
select pg_temp.check('the sharer may listen', pg_temp.topic_allows('b', pg_temp.id_of('share'), 'listen'));
select pg_temp.check('someone outside the chat may not listen', not pg_temp.topic_allows('e', pg_temp.id_of('share'), 'listen'));
select pg_temp.check('someone not signed in may not listen', not pg_temp.topic_allows('anon', pg_temp.id_of('share'), 'listen'));

-- Blocks (either way) -------------------------------------------------------------

insert into public.blocks (blocker_id, blocked_id)
values ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000b1');
select pg_temp.act_as('d');
select pg_temp.check(
  'someone who blocked the sharer sees no share',
  (select count(*) from public.list_live_location_shares(pg_temp.id_of('group'))) = 0
  and (select count(*) from public.live_location_shares) = 0
);
select pg_temp.check('and cannot listen', not pg_temp.topic_allows('d', pg_temp.id_of('share'), 'listen'));
select pg_temp.act_as('b');
select pg_temp.check(
  'the sharer still sees their own share',
  (select count(*) from public.list_live_location_shares(pg_temp.id_of('group'))) = 1
);
select pg_temp.act_as(null);
delete from public.blocks;
insert into public.blocks (blocker_id, blocked_id)
values ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000c1');
select pg_temp.check('someone the sharer blocked cannot listen', not pg_temp.topic_allows('c', pg_temp.id_of('share'), 'listen'));
select pg_temp.act_as('c');
select pg_temp.check(
  'and sees no share',
  (select count(*) from public.list_live_location_shares(pg_temp.id_of('group'))) = 0
);
select pg_temp.act_as(null);
delete from public.blocks;
select pg_temp.check('unblocked, they listen again', pg_temp.topic_allows('c', pg_temp.id_of('share'), 'listen'));

-- The AI guard / deleted card ------------------------------------------------------

update public.messages set review_state = 'held' where id = pg_temp.id_of('share_card');
select pg_temp.check('a card waiting for review hides the share from members', not pg_temp.topic_allows('c', pg_temp.id_of('share'), 'listen'));
select pg_temp.act_as('c');
select pg_temp.check(
  'and from the list',
  (select count(*) from public.list_live_location_shares(pg_temp.id_of('group'))) = 0
);
select pg_temp.act_as(null);
select pg_temp.check('the sharer can still send', pg_temp.topic_allows('b', pg_temp.id_of('share'), 'send'));
update public.messages set review_state = null where id = pg_temp.id_of('share_card');
select pg_temp.check('released, members listen again', pg_temp.topic_allows('c', pg_temp.id_of('share'), 'listen'));
update public.messages set recalled_at = now(), recalled_by = '00000000-0000-4000-8000-0000000000b1'
where id = pg_temp.id_of('share_card');
select pg_temp.check('a deleted card hides the share', not pg_temp.topic_allows('c', pg_temp.id_of('share'), 'listen'));
update public.messages set recalled_at = null, recalled_by = null where id = pg_temp.id_of('share_card');

-- Stopping --------------------------------------------------------------------------

select pg_temp.act_as('c');
select public.stop_live_location(pg_temp.id_of('share'));
select pg_temp.act_as(null);
select pg_temp.check(
  'only the sharer can stop a share',
  (select stopped_at is null from public.live_location_shares where id = pg_temp.id_of('share'))
);

select pg_temp.act_as('b');
select public.stop_live_location(pg_temp.id_of('share'));
select pg_temp.act_as(null);
select pg_temp.check(
  'the sharer stops it',
  (select stopped_at is not null from public.live_location_shares where id = pg_temp.id_of('share'))
);
select pg_temp.check('nobody listens after it', not pg_temp.topic_allows('c', pg_temp.id_of('share'), 'listen'));
select pg_temp.check('and the sharer cannot send', not pg_temp.topic_allows('b', pg_temp.id_of('share'), 'send'));
select pg_temp.act_as('c');
select pg_temp.check(
  'it is gone from the list but members can still see it ended',
  (select count(*) from public.list_live_location_shares(pg_temp.id_of('group'))) = 0
  and (select count(*) from public.live_location_shares) = 1
);
select pg_temp.act_as(null);

-- Starting again replaces; time running out ends it ---------------------------------

select pg_temp.act_as('b');
insert into ids select 'share2', s.share_id from public.start_live_location(pg_temp.id_of('group'), 60, true) s;
insert into ids select 'share3', s.share_id from public.start_live_location(pg_temp.id_of('group'), 480, false) s;
select pg_temp.act_as(null);
select pg_temp.check(
  'a new share replaces the running one in that chat',
  (select count(*) from public.live_location_shares
   where user_id = '00000000-0000-4000-8000-0000000000b1' and stopped_at is null) = 1
  and (select stopped_at is not null from public.live_location_shares where id = pg_temp.id_of('share2'))
  and (select ends_at > now() + interval '7 hours' from public.live_location_shares where id = pg_temp.id_of('share3'))
);
select pg_temp.check(
  'the precise choice is kept',
  (select precise from public.live_location_shares where id = pg_temp.id_of('share2'))
);

update public.live_location_shares set ends_at = now() - interval '1 second', started_at = now() - interval '1 hour'
where id = pg_temp.id_of('share3');
select pg_temp.check('when the time runs out, nobody listens', not pg_temp.topic_allows('c', pg_temp.id_of('share3'), 'listen'));
select pg_temp.check('and the sharer cannot send', not pg_temp.topic_allows('b', pg_temp.id_of('share3'), 'send'));
select pg_temp.act_as('c');
select pg_temp.check(
  'and the list does not show it',
  (select count(*) from public.list_live_location_shares(pg_temp.id_of('group'))) = 0
);
select pg_temp.act_as(null);

-- Leaving and signing out ------------------------------------------------------------

select pg_temp.act_as('b');
insert into ids select 'share4', s.share_id from public.start_live_location(pg_temp.id_of('dm'), 15, false) s;
insert into ids select 'share5', s.share_id from public.start_live_location(pg_temp.id_of('group'), 15, false) s;
select pg_temp.act_as(null);
select pg_temp.act_as('b');
select pg_temp.check(
  'the sharer finds their running shares again (a restarted app)',
  (select count(*) from public.list_my_live_location_shares()) = 2
);
select pg_temp.act_as('c');
select pg_temp.check(
  'and nobody else sees them',
  (select count(*) from public.list_my_live_location_shares()) = 0
);
select pg_temp.act_as(null);

delete from public.conversation_members
where conversation_id = pg_temp.id_of('group') and user_id = '00000000-0000-4000-8000-0000000000b1';
select pg_temp.check(
  'leaving the chat ends the share there and only there',
  (select stopped_at is not null from public.live_location_shares where id = pg_temp.id_of('share5'))
  and (select stopped_at is null from public.live_location_shares where id = pg_temp.id_of('share4'))
);

select pg_temp.act_as('b');
select pg_temp.check('signing out stops all running shares', public.stop_my_live_locations() = 1);
select pg_temp.act_as(null);
select pg_temp.check(
  'none is left running',
  not exists (select 1 from public.live_location_shares where stopped_at is null)
);

-- A direct chat: the other person is blocked ------------------------------------------

insert into public.blocks (blocker_id, blocked_id)
values ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000b1');
select pg_temp.act_as('b');
select pg_temp.refused(
  'a blocked person cannot start sharing in a direct chat',
  format('select public.start_live_location(%L, 15)', pg_temp.id_of('dm')),
  '42501'
);
select pg_temp.refused(
  'or send a location there',
  format('select public.send_location(%L, 1, 2, %L)', pg_temp.id_of('dm'), 'x'),
  '42501'
);
select pg_temp.act_as(null);

rollback;
