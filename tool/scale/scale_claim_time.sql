-- L6 scale test: the push claim timed on warm caches. Four messages in the
-- big group, four in a circle channel; each claimed in one go (the old way,
-- the 2-argument call) or in batches of 500 people. Run with:
--   sh tool/scale/run_scale.sh full after tool/scale/scale_claim_time.sql
\set ON_ERROR_STOP on
\o /dev/null
create temp table msgs (n integer, id uuid);
grant all on msgs to public;

create function pg_temp.claim_all(msg uuid, who uuid) returns numeric language plpgsql as $$
declare t0 timestamptz := clock_timestamp(); n integer;
begin
  select count(*) into n from public.claim_push_delivery(msg, who);
  return round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
end $$;
create function pg_temp.claim_paged(msg uuid, who uuid, size integer) returns numeric language plpgsql as $$
declare t0 timestamptz := clock_timestamp(); last_user uuid; people integer;
begin
  loop
    select count(distinct recipient_id), (array_agg(recipient_id order by recipient_id desc))[1]
      into people, last_user
    from public.claim_push_delivery(msg, who, last_user, size);
    exit when people < size;
  end loop;
  return round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
end $$;
grant execute on function pg_temp.claim_all(uuid, uuid) to public;
grant execute on function pg_temp.claim_paged(uuid, uuid, integer) to public;

do $do$
declare
  who uuid := pg_temp.uid(1);
  g uuid := pg_temp.i('group');
  c uuid := (select conversation_id from public.circle_channels where id = pg_temp.i('chan1'));
  i integer;
begin
  perform pg_temp.act(who);
  for i in 1..8 loop
    insert into pg_temp.msgs values (i, public.send_text_message(case when i <= 4 then g else c end, 'claim time ' || i));
  end loop;
  perform pg_temp.root();
end $do$;
\o

select
  (select pg_temp.claim_paged(id, pg_temp.uid(1), 500) from pg_temp.msgs where n = 1) as group_paged_1,
  (select pg_temp.claim_all(id, pg_temp.uid(1)) from pg_temp.msgs where n = 2) as group_all_1,
  (select pg_temp.claim_paged(id, pg_temp.uid(1), 500) from pg_temp.msgs where n = 3) as group_paged_2,
  (select pg_temp.claim_all(id, pg_temp.uid(1)) from pg_temp.msgs where n = 4) as group_all_2,
  (select pg_temp.claim_paged(id, pg_temp.uid(1), 500) from pg_temp.msgs where n = 5) as chan_paged_1,
  (select pg_temp.claim_all(id, pg_temp.uid(1)) from pg_temp.msgs where n = 6) as chan_all_1,
  (select pg_temp.claim_paged(id, pg_temp.uid(1), 500) from pg_temp.msgs where n = 7) as chan_paged_2,
  (select pg_temp.claim_all(id, pg_temp.uid(1)) from pg_temp.msgs where n = 8) as chan_all_2;
