-- Behaviour checks for view-once media (migration 202610170021). Run by
-- test/supabase/view_once_test.dart against the local database: it applies
-- the migrations the local database lacks in a transaction, seeds people
-- and chats, checks the rules and rolls back, so the database is left as it
-- was. Run from the repository root.
\set ON_ERROR_STOP on

begin;

-- These scripts change the same tables; one at a time keeps them from
-- waiting on each other's locks when the tests run in parallel.
do $$ begin perform pg_advisory_xact_lock(20261017); end $$;

\i supabase/migrations/202610170002_album_counts.sql
\i supabase/migrations/202610170003_album_summaries.sql
\i supabase/migrations/202610170004_album_push.sql
\i supabase/migrations/202610170020_disappearing_messages.sql
\i supabase/migrations/202610170021_view_once_media.sql

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@once.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@once.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@once.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee@once.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_once', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_once', 'Bob'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_once', 'Cy'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee_once', 'Dee');

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

-- Ada and Bob chat directly; Ada, Bob and Cy share a group; Dee is in
-- neither.
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
  insert into public.conversations (type, title) values ('group', 'Once group') returning id
), grp_members as (
  insert into public.conversation_members (conversation_id, user_id, role)
  select grp.id, member.id, member.role
  from grp, (values
    ('00000000-0000-4000-8000-0000000000a1'::uuid, 'owner'),
    ('00000000-0000-4000-8000-0000000000b1'::uuid, 'member'),
    ('00000000-0000-4000-8000-0000000000c1'::uuid, 'member')
  ) as member(id, role)
)
insert into ids select 'dm', id from dm union all select 'group', id from grp;

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

-- Sends as [user_id] through the insert policy; returns the new id or
-- raises what the database raises.
create function pg_temp.send_as(user_id uuid, conv uuid, kind text, attachment jsonb, extra text default '')
returns uuid language plpgsql as $$
declare new_id uuid;
begin
  perform pg_temp.as_user(user_id);
  execute 'set local role authenticated';
  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (conv, user_id, kind, extra, attachment)
  returning id into new_id;
  execute 'reset role';
  return new_id;
exception when others then
  execute 'reset role';
  raise;
end $$;

do $$
declare
  dm uuid := (select id from ids where name = 'dm');
  grp uuid := (select id from ids where name = 'group');
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  cy uuid := '00000000-0000-4000-8000-0000000000c1';
  dee uuid := '00000000-0000-4000-8000-0000000000d1';
  once_id uuid;
  plain_id uuid;
  group_once uuid;
  opened jsonb;
  failed boolean;
  seen integer;
  failures text := '';
begin
  -- Ada sends a view-once photo (and a caption that is dropped), and an
  -- ordinary one.
  once_id := pg_temp.send_as(
    ada, dm, 'image',
    jsonb_build_object('kind', 'image', 'bucket', 'chat-images', 'path', dm || '/once.jpg', 'mime_type', 'image/jpeg', 'view_once', true),
    'secret caption'
  );
  plain_id := pg_temp.send_as(
    ada, dm, 'image',
    jsonb_build_object('kind', 'image', 'bucket', 'chat-images', 'path', dm || '/plain.jpg', 'mime_type', 'image/jpeg')
  );
  if (select body from public.messages where id = once_id) <> '' then
    failures := failures || E'\nthe caption of a view-once photo was kept';
  end if;

  -- Only single photos and videos in direct chats and groups.
  failed := false;
  begin
    perform pg_temp.send_as(ada, dm, 'text', '{"view_once": true}', 'hello');
  exception when invalid_parameter_value then failed := true;
  end;
  if not failed then failures := failures || E'\ntext sent as view once'; end if;

  failed := false;
  begin
    perform pg_temp.send_as(ada, dm, 'file', jsonb_build_object('kind', 'file', 'view_once', true, 'bucket', 'chat-files', 'path', dm || '/doc.pdf'));
  exception when invalid_parameter_value then failed := true;
  end;
  if not failed then failures := failures || E'\na document sent as view once'; end if;

  -- A video is fine.
  perform pg_temp.send_as(
    ada, dm, 'file',
    jsonb_build_object('kind', 'video', 'bucket', 'chat-files', 'path', dm || '/once.mp4', 'view_once', true)
  );

  -- Not in an album.
  failed := false;
  begin
    perform pg_temp.as_user(ada);
    execute 'set local role authenticated';
    insert into public.messages (conversation_id, sender_id, type, body, attachment, attachment_group_id)
    values (dm, ada, 'image', '', '{"kind":"image","view_once": true}', gen_random_uuid());
    execute 'reset role';
  exception when invalid_parameter_value then
    execute 'reset role';
    failed := true;
  end;
  if not failed then failures := failures || E'\nan album item sent as view once'; end if;

  -- The sender, an outsider and a message that is not view-once cannot open.
  perform pg_temp.as_user(ada);
  failed := false;
  begin perform public.open_view_once(once_id);
  exception when insufficient_privilege then failed := true; end;
  if not failed then failures := failures || E'\nthe sender opened their own view-once photo'; end if;

  perform pg_temp.as_user(dee);
  failed := false;
  begin perform public.open_view_once(once_id);
  exception when insufficient_privilege then failed := true; end;
  if not failed then failures := failures || E'\nan outsider opened a view-once photo'; end if;

  perform pg_temp.as_user(bob);
  failed := false;
  begin perform public.open_view_once(plain_id);
  exception when insufficient_privilege then failed := true; end;
  if not failed then failures := failures || E'\nopen_view_once opened an ordinary photo'; end if;

  -- Storage: a file of each kind.
  insert into storage.objects (bucket_id, name, owner, metadata)
  values
    ('chat-images', dm || '/once.jpg', ada, '{}'),
    ('chat-images', dm || '/plain.jpg', ada, '{}');

  -- Before opening, Bob cannot read the view-once file but can read the
  -- ordinary one; Ada can read both.
  seen := pg_temp.as_count(bob, format($q$select count(*) from storage.objects where bucket_id = 'chat-images' and name = %L$q$, dm || '/once.jpg'));
  if seen <> 0 then failures := failures || E'\nthe file was readable before opening'; end if;
  seen := pg_temp.as_count(bob, format($q$select count(*) from storage.objects where bucket_id = 'chat-images' and name = %L$q$, dm || '/plain.jpg'));
  if seen <> 1 then failures := failures || E'\nan ordinary photo is no longer readable'; end if;
  seen := pg_temp.as_count(ada, format($q$select count(*) from storage.objects where bucket_id = 'chat-images' and name = %L$q$, dm || '/once.jpg'));
  if seen <> 1 then failures := failures || E'\nthe sender cannot read their own file'; end if;

  -- Bob opens it: he gets the file once.
  perform pg_temp.as_user(bob);
  opened := public.open_view_once(once_id);
  if opened->>'path' <> dm || '/once.jpg' or opened->>'bucket' <> 'chat-images' then
    failures := failures || format(E'\nopened %s', opened);
  end if;
  seen := pg_temp.as_count(bob, format($q$select count(*) from storage.objects where bucket_id = 'chat-images' and name = %L$q$, dm || '/once.jpg'));
  if seen <> 1 then failures := failures || E'\nthe file is not readable right after opening'; end if;

  failed := false;
  begin perform public.open_view_once(once_id);
  exception when others then
    failed := sqlerrm = 'view_once_already_opened';
  end;
  if not failed then failures := failures || E'\na second open was allowed'; end if;

  -- The window closes.
  update public.message_view_once_opens
  set opened_at = now() - interval '3 minutes'
  where message_id = once_id and user_id = bob;
  seen := pg_temp.as_count(bob, format($q$select count(*) from storage.objects where bucket_id = 'chat-images' and name = %L$q$, dm || '/once.jpg'));
  if seen <> 0 then failures := failures || E'\nthe file stayed readable after the window'; end if;

  -- Who sees the opens: the sender all, Bob his own.
  seen := pg_temp.as_count(ada, format('select count(*) from public.message_view_once_opens where message_id = %L', once_id));
  if seen <> 1 then failures := failures || format(E'\nsender sees %s opens', seen); end if;
  seen := pg_temp.as_count(bob, format('select count(*) from public.message_view_once_opens where message_id = %L', once_id));
  if seen <> 1 then failures := failures || format(E'\nBob sees %s opens', seen); end if;
  seen := pg_temp.as_count(dee, format('select count(*) from public.message_view_once_opens where message_id = %L', once_id));
  if seen <> 0 then failures := failures || format(E'\nan outsider sees %s opens', seen); end if;
  -- A client cannot write opens.
  failed := false;
  begin
    perform pg_temp.as_user(cy);
    execute 'set local role authenticated';
    insert into public.message_view_once_opens (message_id, user_id, conversation_id)
    values (once_id, cy, dm);
    execute 'reset role';
  exception when others then
    execute 'reset role';
    failed := true;
  end;
  if not failed then failures := failures || E'\na client wrote an open'; end if;

  -- In a group each member opens once, independently.
  group_once := pg_temp.send_as(
    ada, grp, 'image',
    jsonb_build_object('kind', 'image', 'bucket', 'chat-images', 'path', grp || '/once.jpg', 'view_once', true)
  );
  perform pg_temp.as_user(bob);
  perform public.open_view_once(group_once);
  perform pg_temp.as_user(cy);
  perform public.open_view_once(group_once);
  seen := pg_temp.as_count(ada, format('select count(*) from public.message_view_once_opens where message_id = %L', group_once));
  if seen <> 2 then failures := failures || format(E'\ngroup opens %s, expected 2', seen); end if;

  -- No forwarding.
  failed := false;
  begin
    perform pg_temp.as_user(bob);
    perform public.forward_message(group_once, dm);
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then failures := failures || E'\nview-once media was forwarded'; end if;

  -- The shared media list leaves it out.
  perform pg_temp.as_user(bob);
  if exists (select 1 from public.list_conversation_media(dm) where message_id = once_id) then
    failures := failures || E'\nthe media list shows view-once media';
  end if;
  if not exists (select 1 from public.list_conversation_media(dm) where message_id = plain_id) then
    failures := failures || E'\nthe media list lost an ordinary photo';
  end if;

  if failures <> '' then
    raise exception 'view-once checks failed:%', failures;
  end if;
end $$;

rollback;
