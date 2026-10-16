-- Behaviour checks for disappearing messages (migration 202610170020). Run
-- by test/supabase/disappearing_messages_behaviour_test.dart against the
-- local database: it applies the migrations the local database lacks in a
-- transaction, seeds people and chats, checks the rules and rolls back, so
-- the database is left as it was. Run from the repository root.
\set ON_ERROR_STOP on

begin;

\i supabase/migrations/202610170002_album_counts.sql
\i supabase/migrations/202610170003_album_summaries.sql
\i supabase/migrations/202610170004_album_push.sql
\i supabase/migrations/202610170020_disappearing_messages.sql

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@gone.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@gone.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@gone.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_gone', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_gone', 'Bob'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_gone', 'Cy');

-- Ada owns the group, Bob is an admin, Cy a member; Ada and Cy also chat
-- directly.
with grp as (
  insert into public.conversations (type, title) values ('group', 'Gone group') returning id
), members as (
  insert into public.conversation_members (conversation_id, user_id, role)
  select grp.id, member.id, member.role
  from grp, (values
    ('00000000-0000-4000-8000-0000000000a1'::uuid, 'owner'),
    ('00000000-0000-4000-8000-0000000000b1'::uuid, 'admin'),
    ('00000000-0000-4000-8000-0000000000c1'::uuid, 'member')
  ) as member(id, role)
), dm as (
  insert into public.conversations (type) values ('direct') returning id
), dm_members as (
  insert into public.conversation_members (conversation_id, user_id)
  select dm.id, member.id
  from dm, (values
    ('00000000-0000-4000-8000-0000000000a1'::uuid),
    ('00000000-0000-4000-8000-0000000000c1'::uuid)
  ) as member(id)
)
insert into ids select 'group', id from grp union all select 'dm', id from dm;

create function pg_temp.as_user(user_id uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_id, 'role', 'authenticated')::text,
    true
  );
end $$;

do $$
declare
  grp uuid := (select id from ids where name = 'group');
  dm uuid := (select id from ids where name = 'dm');
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  cy uuid := '00000000-0000-4000-8000-0000000000c1';
  failed boolean;
  value timestamptz;
  announcements integer;
  failures text := '';
begin
  -- A member cannot change a group's timer; an admin can.
  perform pg_temp.as_user(cy);
  failed := false;
  begin
    perform public.set_disappearing_messages(grp, 86400);
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then
    failures := failures || E'\na member changed the group timer';
  end if;

  perform pg_temp.as_user(bob);
  perform public.set_disappearing_messages(grp, 86400);
  if (select disappear_after_seconds from public.conversations where id = grp) <> 86400 then
    failures := failures || E'\nthe admin could not set 24 hours';
  end if;
  select count(*) into announcements
  from public.messages
  where conversation_id = grp and type = 'system'
    and attachment->>'kind' = 'disappearing' and (attachment->>'seconds')::int = 86400;
  if announcements <> 1 then
    failures := failures || format(E'\n%s announcements, expected 1', announcements);
  end if;

  -- The same value again says nothing.
  perform public.set_disappearing_messages(grp, 86400);
  select count(*) into announcements
  from public.messages where conversation_id = grp and attachment->>'kind' = 'disappearing';
  if announcements <> 1 then
    failures := failures || E'\nan unchanged timer was announced again';
  end if;

  -- Only 24 hours, 7 days and 90 days are allowed.
  failed := false;
  begin
    perform public.set_disappearing_messages(grp, 3600);
  exception when invalid_parameter_value then failed := true;
  end;
  if not failed then
    failures := failures || E'\n1 hour was accepted';
  end if;

  -- Either person in a direct chat can set it.
  perform pg_temp.as_user(cy);
  perform public.set_disappearing_messages(dm, 604800);
  if (select disappear_after_seconds from public.conversations where id = dm) <> 604800 then
    failures := failures || E'\ndirect chat timer not set';
  end if;

  -- A stranger cannot.
  insert into auth.users (id, email, instance_id, aud, role)
  values ('00000000-0000-4000-8000-0000000000d1', 'dee@gone.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
  insert into public.profiles (id, username, display_name)
  values ('00000000-0000-4000-8000-0000000000d1', 'dee_gone', 'Dee');
  perform pg_temp.as_user('00000000-0000-4000-8000-0000000000d1');
  failed := false;
  begin
    perform public.set_disappearing_messages(dm, null);
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then
    failures := failures || E'\na stranger changed a direct chat timer';
  end if;

  -- New messages get an expiry; the client cannot choose it; system lines
  -- never expire.
  perform pg_temp.as_user(ada);
  execute 'set local role authenticated';
  insert into public.messages (conversation_id, sender_id, type, body, expires_at)
  values (grp, ada, 'text', 'soon gone', now() + interval '10 years');
  execute 'reset role';
  select expires_at into value from public.messages where body = 'soon gone';
  if value is null or value > now() + interval '25 hours' or value < now() + interval '23 hours' then
    failures := failures || format(E'\nexpires_at is %s', value);
  end if;
  if exists (
    select 1 from public.messages where type = 'system' and expires_at is not null
  ) then
    failures := failures || E'\na system line expires';
  end if;

  if failures <> '' then
    raise exception 'timer checks failed:%', failures;
  end if;
end $$;

-- Expired messages are hidden at once, deleted by the purge, and the purge
-- tidies up after itself.
do $$
declare
  grp uuid := (select id from ids where name = 'group');
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  old_id uuid;
  kept_id uuid;
  reply_id uuid;
  image_id uuid;
  copy_id uuid;
  seen integer;
  purged integer;
  claimed integer;
  failed boolean;
  last_id uuid;
  marker uuid;
  failures text := '';
begin
  insert into public.messages (id, conversation_id, sender_id, type, body, created_at)
  values (gen_random_uuid(), grp, ada, 'text', 'old one', now() - interval '3 days')
  returning id into old_id;
  insert into public.messages (conversation_id, sender_id, type, body, created_at)
  values (grp, ada, 'text', 'kept', now() - interval '2 days')
  returning id into kept_id;
  -- The image and a forwarded copy of the same file; the copy stays.
  insert into public.messages (conversation_id, sender_id, type, body, attachment, created_at)
  values (grp, ada, 'image', '', '{"kind":"image","bucket":"chat-images","path":"c/gone.jpg"}', now() - interval '3 days')
  returning id into image_id;
  insert into public.messages (conversation_id, sender_id, type, body, attachment, created_at)
  values (grp, ada, 'image', '', '{"kind":"image","bucket":"chat-images","path":"c/shared.jpg"}', now() - interval '3 days')
  returning id into copy_id;
  insert into public.messages (conversation_id, sender_id, type, body, attachment, created_at)
  values (grp, ada, 'image', '', '{"kind":"image","bucket":"chat-images","path":"c/shared.jpg"}', now() - interval '3 days');
  -- A reply that outlives what it answers.
  insert into public.messages (conversation_id, sender_id, type, body, reply_to_message_id, reply_preview, created_at)
  values (grp, ada, 'text', 'replying', old_id, '{"body":"old one"}', now() - interval '2 days')
  returning id into reply_id;
  -- Bob read up to the old message.
  update public.conversation_members set last_read_message_id = old_id
  where conversation_id = grp and user_id = bob;

  update public.messages set expires_at = now() - interval '1 minute'
  where id in (old_id, image_id, copy_id);
  update public.messages set expires_at = now() + interval '1 hour' where id = kept_id;

  -- Hidden from readers before anything is deleted.
  perform pg_temp.as_user(bob);
  execute 'set local role authenticated';
  select count(*) into seen from public.messages where id in (old_id, image_id);
  execute 'reset role';
  if seen <> 0 then
    failures := failures || E'\nexpired messages were still readable';
  end if;
  perform pg_temp.as_user(bob);
  execute 'set local role authenticated';
  select count(*) into seen from public.messages where id = kept_id;
  execute 'reset role';
  if seen <> 1 then
    failures := failures || E'\na live message was hidden';
  end if;

  -- Readers cannot run the purge.
  execute 'set local role authenticated';
  failed := false;
  begin
    perform public.purge_expired_messages();
  exception when insufficient_privilege then failed := true;
  end;
  execute 'reset role';
  if not failed then
    failures := failures || E'\nauthenticated could purge';
  end if;

  purged := public.purge_expired_messages();
  if purged <> 3 then
    failures := failures || format(E'\npurged %s, expected 3', purged);
  end if;
  if exists (select 1 from public.messages where id in (old_id, image_id, copy_id)) then
    failures := failures || E'\nexpired rows are still there';
  end if;
  if not exists (select 1 from public.messages where id = kept_id) then
    failures := failures || E'\nthe purge removed a live message';
  end if;
  if (select reply_preview from public.messages where id = reply_id) is not null then
    failures := failures || E'\nthe reply kept a copy of the purged message';
  end if;

  -- Bob's read marker moved to the newest message before the gap (none
  -- here, so it is empty), not to a stale id.
  select last_read_message_id into marker
  from public.conversation_members where conversation_id = grp and user_id = bob;
  if marker = old_id then
    failures := failures || E'\nread marker still points at a purged message';
  end if;

  -- Files: gone.jpg is queued, shared.jpg is still used by the copy.
  select count(*) into claimed from public.claim_expired_media(100);
  if claimed <> 1 or not exists (
    select 1 from public.claim_expired_media(100) where object_path = 'c/gone.jpg'
  ) then
    failures := failures || format(E'\nclaimed %s files', claimed);
  end if;
  perform public.finish_expired_media(array['chat-images'], array['c/gone.jpg']);
  if exists (select 1 from public.claim_expired_media(100)) then
    failures := failures || E'\nfinished files were claimed again';
  end if;

  -- The conversation points at a message that still exists.
  select last_message_id into last_id from public.conversations where id = grp;
  if last_id is null or not exists (select 1 from public.messages where id = last_id) then
    failures := failures || E'\nlast_message_id points nowhere';
  end if;

  -- Nothing left to purge.
  if public.purge_expired_messages() <> 0 then
    failures := failures || E'\na second purge deleted something';
  end if;

  -- Turning it off stops new expiry.
  perform pg_temp.as_user(ada);
  perform public.set_disappearing_messages(grp, null);
  insert into public.messages (conversation_id, sender_id, type, body)
  values (grp, ada, 'text', 'stays');
  if (select expires_at from public.messages where body = 'stays') is not null then
    failures := failures || E'\nmessages still expire after turning it off';
  end if;

  if failures <> '' then
    raise exception 'purge checks failed:%', failures;
  end if;
end $$;

rollback;
