-- Behaviour checks for the data export tables and rate limit (migration
-- 202610170053_data_export). Run by
-- test/supabase/data_export_behaviour_test.dart against the local
-- database inside a transaction that is rolled back. Run from the
-- repository root.
\set ON_ERROR_STOP on

begin;

-- The behaviour checks all run DDL and write the same tables; take turns so
-- they cannot deadlock when the test runner starts them together.
select pg_advisory_xact_lock(7771001);

\i supabase/migrations/202610170053_data_export.sql

create function pg_temp.act_as(who uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', who::text, true);
$$;

create function pg_temp.check_that(ok boolean, message text) returns void
language plpgsql as $$
begin
  if ok is not true then
    raise exception 'check failed: %', message;
  end if;
end $$;

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000f1', 'ada@export.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000f2', 'bob@export.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000f1', 'ada_export', 'Ada'),
  ('00000000-0000-4000-8000-0000000000f2', 'bob_export', 'Bob');

-- The bucket is private, with a size limit and ZIP only.
do $$
begin
  perform pg_temp.check_that(
    (select not public and allowed_mime_types = array['application/zip'] and file_size_limit > 0
       from storage.buckets where id = 'data-exports'),
    'the bucket is private, ZIP only'
  );
end $$;

-- The first request starts an export.
create temp table started (name text primary key, id uuid not null);
grant all on started to public;

do $$
declare
  first_try record;
begin
  select * into first_try
  from public.begin_data_export('00000000-0000-4000-8000-0000000000f1');
  perform pg_temp.check_that(first_try.started, 'the first request starts');
  perform pg_temp.check_that(first_try.status = 'working', 'and is working');
  insert into started values ('first', first_try.export_id);
  perform pg_temp.check_that(
    (select stage = 'queued' and progress = 0 from public.data_exports where id = first_try.export_id),
    'queued at 0'
  );
end $$;

-- A second request while it works is refused and points at it.
do $$
declare
  second_try record;
begin
  select * into second_try
  from public.begin_data_export('00000000-0000-4000-8000-0000000000f1');
  perform pg_temp.check_that(not second_try.started, 'a second request does not start');
  perform pg_temp.check_that(second_try.status = 'working', 'it says the export is working');
  perform pg_temp.check_that(
    second_try.export_id = (select id from started where name = 'first'),
    'and which one'
  );
  perform pg_temp.check_that(
    second_try.retry_after_seconds between 86000 and 86400,
    'about a day to wait'
  );
end $$;

-- Once ready it still counts for 24 hours.
update public.data_exports set status = 'ready', stage = 'ready', progress = 100,
  file_path = 'x/y.zip', completed_at = now(), expires_at = now() + interval '7 days'
where id = (select id from started where name = 'first');

do $$
declare
  third_try record;
begin
  select * into third_try
  from public.begin_data_export('00000000-0000-4000-8000-0000000000f1');
  perform pg_temp.check_that(not third_try.started and third_try.status = 'ready', 'a ready export blocks a new one');
end $$;

-- Others are not held up by it.
do $$
declare
  bob_try record;
begin
  select * into bob_try
  from public.begin_data_export('00000000-0000-4000-8000-0000000000f2');
  perform pg_temp.check_that(bob_try.started, 'another person can export');
end $$;

-- After 24 hours a new one starts.
update public.data_exports
set created_at = now() - interval '25 hours'
where id = (select id from started where name = 'first');
do $$
declare
  next_day record;
begin
  select * into next_day
  from public.begin_data_export('00000000-0000-4000-8000-0000000000f1');
  perform pg_temp.check_that(next_day.started, 'a day later a new export starts');
  insert into started values ('second', next_day.export_id);
end $$;

-- A failed attempt does not count against the limit...
update public.data_exports set status = 'failed', error = 'export_failed'
where id = (select id from started where name = 'second');
do $$
declare
  retry record;
begin
  select * into retry
  from public.begin_data_export('00000000-0000-4000-8000-0000000000f1');
  perform pg_temp.check_that(retry.started, 'after a failure one can try again');
  insert into started values ('third', retry.export_id);
end $$;

-- ...and an export stuck for 20 minutes is given up on.
update public.data_exports set created_at = now() - interval '21 minutes'
where id = (select id from started where name = 'third');
do $$
declare
  after_stuck record;
begin
  select * into after_stuck
  from public.begin_data_export('00000000-0000-4000-8000-0000000000f1');
  perform pg_temp.check_that(after_stuck.started, 'a stuck export does not block');
  perform pg_temp.check_that(
    (select status = 'failed' and error = 'timeout' from public.data_exports
       where id = (select id from started where name = 'third')),
    'the stuck one is marked failed'
  );
end $$;

-- People read their own rows and files, nothing else, and write nothing.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000f1');
set local role authenticated;
do $$
begin
  perform pg_temp.check_that(
    (select count(*) from public.data_exports) = (select count(*) from public.data_exports where user_id = '00000000-0000-4000-8000-0000000000f1'),
    'only own export rows are visible'
  );
  perform pg_temp.check_that(
    (select count(*) from public.data_exports) > 0,
    'own rows are visible'
  );
end $$;
reset role;

set local role authenticated;
do $$
begin
  begin
    perform public.begin_data_export('00000000-0000-4000-8000-0000000000f1');
    raise exception 'check failed: members must not start exports themselves';
  exception when insufficient_privilege then
    null;
  end;
  begin
    insert into public.data_exports (user_id) values ('00000000-0000-4000-8000-0000000000f1');
    raise exception 'check failed: members must not write export rows';
  exception when insufficient_privilege then
    null;
  end;
end $$;
reset role;

-- Storage: the owner reads their folder; others and anonymous do not; no
-- one writes through the API.
insert into storage.objects (bucket_id, name, owner_id)
values
  ('data-exports', '00000000-0000-4000-8000-0000000000f1/20261017T140309Z.zip', null),
  ('data-exports', '00000000-0000-4000-8000-0000000000f2/20261017T140309Z.zip', null);

select pg_temp.act_as('00000000-0000-4000-8000-0000000000f1');
set local role authenticated;
do $$
begin
  perform pg_temp.check_that(
    (select count(*) from storage.objects where bucket_id = 'data-exports') = 1
      and (select name from storage.objects where bucket_id = 'data-exports')
        = '00000000-0000-4000-8000-0000000000f1/20261017T140309Z.zip',
    'a person sees only their own export file'
  );
  begin
    insert into storage.objects (bucket_id, name)
    values ('data-exports', '00000000-0000-4000-8000-0000000000f1/own-upload.zip');
    raise exception 'check failed: uploads through the API must be refused';
  exception when others then
    if sqlerrm like 'check failed%' then
      raise;
    end if;
  end;
end $$;
reset role;

rollback;
