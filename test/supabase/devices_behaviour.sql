-- Behaviour checks for device sessions (migration 202610170022). Run by
-- test/supabase/devices_test.dart against the local database inside a
-- transaction that is rolled back. Run from the repository root.
\set ON_ERROR_STOP on

begin;

-- These scripts change the same tables; one at a time keeps them from
-- waiting on each other's locks when the tests run in parallel.
select pg_advisory_xact_lock(7770001);

\i supabase/migrations/202610170022_device_sessions.sql

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@dev.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@dev.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');

insert into auth.sessions (id, user_id, created_at, updated_at, user_agent)
values
  ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000a1', now() - interval '3 days', now() - interval '3 days', 'Mozilla/5.0 (Macintosh) Safari/605'),
  ('00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-0000000000a1', now() - interval '1 day', now() - interval '1 hour', 'WeCord/1.0 (iPhone)'),
  ('00000000-0000-4000-8000-0000000000f3', '00000000-0000-4000-8000-0000000000b1', now() - interval '1 day', now() - interval '1 hour', 'Bob browser');

create function pg_temp.as_session(user_id uuid, session_id uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_id, 'role', 'authenticated', 'session_id', session_id)::text,
    true
  );
end $$;

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  mac uuid := '00000000-0000-4000-8000-0000000000f1';
  phone uuid := '00000000-0000-4000-8000-0000000000f2';
  bobs uuid := '00000000-0000-4000-8000-0000000000f3';
  rows integer;
  first_row record;
  failed boolean;
  failures text := '';
begin
  -- The Mac registers itself.
  perform pg_temp.as_session(ada, mac);
  perform public.register_device('Ada MacBook', 'macOS', '1.2.3');
  -- A session that is not the caller's, or does not exist, records nothing.
  perform pg_temp.as_session(ada, bobs);
  perform public.register_device('Not mine', 'macOS', '1');
  if exists (select 1 from public.user_devices where session_id = bobs) then
    failures := failures || E'\nrecorded a device for someone else''s session';
  end if;

  -- The list: own sessions only, current first, with what was recorded.
  perform pg_temp.as_session(ada, mac);
  select count(*) into rows from public.list_my_sessions();
  if rows <> 2 then failures := failures || format(E'\nlisted %s sessions, expected 2', rows); end if;
  select * into first_row from public.list_my_sessions() limit 1;
  if first_row.session_id <> mac or not first_row.is_current
     or first_row.device_name <> 'Ada MacBook' or first_row.platform <> 'macOS'
     or first_row.app_version <> '1.2.3' then
    failures := failures || format(E'\nfirst row %s', first_row);
  end if;
  if (select count(*) from public.list_my_sessions() where is_current) <> 1 then
    failures := failures || E'\nmore than one current session';
  end if;
  if exists (select 1 from public.list_my_sessions() where session_id = bobs) then
    failures := failures || E'\nlisted someone else''s session';
  end if;

  -- Bob sees only his.
  perform pg_temp.as_session(bob, bobs);
  select count(*) into rows from public.list_my_sessions();
  if rows <> 1 then failures := failures || format(E'\nBob lists %s sessions', rows); end if;

  -- Clients cannot end sessions; the service role can, only the owner's.
  perform pg_temp.as_session(ada, mac);
  execute 'set local role authenticated';
  failed := false;
  begin
    perform public.delete_user_session(phone, ada);
  exception when insufficient_privilege then failed := true; end;
  execute 'reset role';
  if not failed then failures := failures || E'\na client ended a session'; end if;

  execute 'set local role service_role';
  if public.delete_user_session(phone, bob) then
    failures := failures || E'\nended a session of someone who does not own it';
  end if;
  if not public.delete_user_session(phone, ada) then
    failures := failures || E'\nthe owner''s session was not ended';
  end if;
  execute 'reset role';
  perform pg_temp.as_session(ada, mac);
  select count(*) into rows from public.list_my_sessions();
  if rows <> 1 then failures := failures || format(E'\nafter ending: %s sessions', rows); end if;

  -- The device record goes with its session.
  delete from auth.sessions where id = mac;
  if exists (select 1 from public.user_devices where session_id = mac) then
    failures := failures || E'\nthe device record outlived its session';
  end if;

  if failures <> '' then
    raise exception 'device checks failed:%', failures;
  end if;
end $$;

rollback;
