-- Behaviour checks for chat folders (migration 202610210200). Run by
-- test/supabase/chat_folders_test.dart against the local database inside a
-- transaction that is rolled back, so the database is left as it was. Run
-- from the repository root.
\set ON_ERROR_STOP on

begin;

-- Behaviour scripts that apply DDL take turns.
select pg_advisory_xact_lock(20261017);

\i supabase/migrations/202610210200_chat_folders.sql

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a2', 'ada@folders.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b2', 'bob@folders.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a2', 'ada_folders', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b2', 'bob_folders', 'Bob');

create function pg_temp.as_user(user_id uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_id, 'role', 'authenticated')::text,
    true
  );
end $$;

-- Rows: own only, shape rules, owner never changes.
do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a2';
  bob uuid := '00000000-0000-4000-8000-0000000000b2';
  chat uuid := '00000000-0000-4000-8000-000000000c01';
  work uuid;
  seen integer;
  failed boolean;
  failures text := '';
begin
  -- Ada makes a folder with rules.
  perform pg_temp.as_user(ada);
  execute 'set local role authenticated';
  insert into public.chat_folders (user_id, name, icon, sort_key, include_types, include_ids, only_unread, exclude_muted)
  values (ada, 'Work', 'work', 1, array['group'], array[chat], true, true)
  returning id into work;
  select count(*) into seen from public.chat_folders;
  execute 'reset role';
  if seen <> 1 then
    failures := failures || format(E'\nAda sees %s of her 1 folder', seen);
  end if;
  if not exists (
    select 1 from public.chat_folders
    where id = work and user_id = ada and include_types = array['group']
      and include_ids = array[chat] and only_unread and exclude_muted
      and not only_muted and not folded and exclude_ids = '{}'
  ) then
    failures := failures || E'\nthe rules were not stored as given';
  end if;

  -- Bob sees none of it and cannot change it.
  perform pg_temp.as_user(bob);
  execute 'set local role authenticated';
  select count(*) into seen from public.chat_folders;
  update public.chat_folders set name = 'Mine now' where id = work;
  delete from public.chat_folders where id = work;
  failed := false;
  begin
    insert into public.chat_folders (user_id, name) values (ada, 'Planted');
  exception when insufficient_privilege then failed := true;
  end;
  execute 'reset role';
  if seen <> 0 then
    failures := failures || format(E'\nBob sees %s of Ada''s folders', seen);
  end if;
  if (select name from public.chat_folders where id = work) <> 'Work' then
    failures := failures || E'\nBob renamed or deleted Ada''s folder';
  end if;
  if not failed then
    failures := failures || E'\nBob planted a folder in Ada''s list';
  end if;

  -- The owner cannot be handed over.
  perform pg_temp.as_user(ada);
  execute 'set local role authenticated';
  begin
    update public.chat_folders set user_id = bob where id = work;
  exception when insufficient_privilege then null;
  end;
  execute 'reset role';
  if (select user_id from public.chat_folders where id = work) <> ada then
    failures := failures || E'\nAda gave her folder to Bob';
  end if;

  -- Anonymous callers have no access.
  execute 'set local role anon';
  failed := false;
  begin
    perform count(*) from public.chat_folders;
  exception when insufficient_privilege then failed := true;
  end;
  execute 'reset role';
  if not failed then
    failures := failures || E'\nanon can read chat_folders';
  end if;

  -- Shape rules.
  perform pg_temp.as_user(ada);
  execute 'set local role authenticated';
  failed := false;
  begin
    insert into public.chat_folders (user_id, name) values (ada, '   ');
  exception when check_violation then failed := true;
  end;
  if not failed then failures := failures || E'\na blank name was accepted'; end if;

  failed := false;
  begin
    insert into public.chat_folders (user_id, name) values (ada, repeat('x', 31));
  exception when check_violation then failed := true;
  end;
  if not failed then failures := failures || E'\na 31 character name was accepted'; end if;

  failed := false;
  begin
    insert into public.chat_folders (user_id, name, include_types) values (ada, 'Odd', array['thread']);
  exception when check_violation then failed := true;
  end;
  if not failed then failures := failures || E'\na thread type was accepted'; end if;

  failed := false;
  begin
    insert into public.chat_folders (user_id, name, exclude_muted, only_muted) values (ada, 'Both', true, true);
  exception when check_violation then failed := true;
  end;
  if not failed then failures := failures || E'\nexclude and only muted together were accepted'; end if;

  failed := false;
  begin
    insert into public.chat_folders (user_id, name, icon) values (ada, 'Loud', 'Not An Icon!');
  exception when check_violation then failed := true;
  end;
  if not failed then failures := failures || E'\na free-form icon was accepted'; end if;

  failed := false;
  begin
    insert into public.chat_folders (user_id, name, include_ids)
    values (ada, 'Huge', (select array_agg(gen_random_uuid()) from generate_series(1, 501)));
  exception when check_violation then failed := true;
  end;
  if not failed then failures := failures || E'\n501 included chats were accepted'; end if;

  -- One folded folder per person.
  insert into public.chat_folders (user_id, name, folded) values (ada, 'Folded group chats', true);
  failed := false;
  begin
    insert into public.chat_folders (user_id, name, folded) values (ada, 'Second fold', true);
  exception when unique_violation then failed := true;
  end;
  if not failed then failures := failures || E'\na second folded folder was accepted'; end if;
  execute 'reset role';

  if failures <> '' then
    raise exception 'row checks failed:%', failures;
  end if;
end $$;

-- The cap: 20 per person, counted per person, freed by deleting.
do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a2';
  bob uuid := '00000000-0000-4000-8000-0000000000b2';
  failed boolean;
  message text;
  failures text := '';
begin
  perform pg_temp.as_user(ada);
  execute 'set local role authenticated';
  -- Ada already has 2 (Work, Folded group chats).
  for i in 1..18 loop
    insert into public.chat_folders (user_id, name, sort_key) values (ada, 'Folder ' || i, 10 + i);
  end loop;
  if (select count(*) from public.chat_folders) <> 20 then
    failures := failures || format(E'\nAda has %s folders, expected 20', (select count(*) from public.chat_folders));
  end if;
  failed := false;
  begin
    insert into public.chat_folders (user_id, name) values (ada, 'One too many');
  exception when check_violation then
    failed := true;
    get stacked diagnostics message = message_text;
  end;
  if not failed then
    failures := failures || E'\nthe 21st folder was accepted';
  elsif message not like '%at most 20%' then
    failures := failures || format(E'\nthe cap says "%s"', message);
  end if;

  -- Deleting one frees a place.
  delete from public.chat_folders where name = 'Folder 1';
  insert into public.chat_folders (user_id, name) values (ada, 'Back to 20');
  execute 'reset role';

  -- The cap is hers alone.
  perform pg_temp.as_user(bob);
  execute 'set local role authenticated';
  insert into public.chat_folders (user_id, name, sort_key) values (bob, 'Bob''s first', 1);
  execute 'reset role';
  if (select count(*) from public.chat_folders where user_id = bob) <> 1 then
    failures := failures || E'\nAda''s folders count against Bob';
  end if;

  if failures <> '' then
    raise exception 'cap checks failed:%', failures;
  end if;
end $$;

-- Reordering: own folders in the given order, others untouched.
do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a2';
  bob uuid := '00000000-0000-4000-8000-0000000000b2';
  first_id uuid;
  second_id uuid;
  third_id uuid;
  bobs uuid;
  failures text := '';
begin
  select id into first_id from public.chat_folders where user_id = ada and name = 'Folder 2';
  select id into second_id from public.chat_folders where user_id = ada and name = 'Folder 3';
  select id into third_id from public.chat_folders where user_id = ada and name = 'Folder 4';
  select id into bobs from public.chat_folders where user_id = bob;

  perform pg_temp.as_user(ada);
  execute 'set local role authenticated';
  -- Ada also lists Bob's folder; it must not move.
  perform public.reorder_chat_folders(array[third_id, bobs, first_id, second_id]);
  execute 'reset role';
  if (select sort_key from public.chat_folders where id = third_id) <> 1
     or (select sort_key from public.chat_folders where id = first_id) <> 3
     or (select sort_key from public.chat_folders where id = second_id) <> 4 then
    failures := failures || E'\nthe folders were not put in the given order';
  end if;
  if (select sort_key from public.chat_folders where id = bobs) <> 1 then
    failures := failures || E'\nAda moved Bob''s folder';
  end if;

  -- Not signed in: refused.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role authenticated';
  begin
    perform public.reorder_chat_folders(array[first_id]);
    failures := failures || E'\nreordering without a user was accepted';
  exception when others then null;
  end;
  execute 'reset role';

  if failures <> '' then
    raise exception 'reorder checks failed:%', failures;
  end if;
end $$;

-- Realtime carries the table, so other devices hear about changes.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat_folders'
  ) then
    raise exception 'chat_folders is not in the realtime publication';
  end if;
end $$;

rollback;
