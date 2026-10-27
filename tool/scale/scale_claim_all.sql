-- L6 scale test: the 2-argument push claim (everyone in one go) timed on warm
-- caches, for a fair before/after comparison (works before and after the L6
-- migrations). Three messages in the big group, three in a circle channel.
--   sh tool/scale/run_scale.sh full before tool/scale/scale_claim_all.sql
--   sh tool/scale/run_scale.sh full after tool/scale/scale_claim_all.sql
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
grant execute on function pg_temp.claim_all(uuid, uuid) to public;

do $do$
declare
  who uuid := pg_temp.uid(1);
  g uuid := pg_temp.i('group');
  c uuid := (select conversation_id from public.circle_channels where id = pg_temp.i('chan1'));
  i integer;
begin
  perform pg_temp.act(who);
  for i in 1..6 loop
    insert into pg_temp.msgs values (i, public.send_text_message(case when i <= 3 then g else c end, 'claim time ' || i));
  end loop;
  perform pg_temp.root();
end $do$;
\o

select
  (select pg_temp.claim_all(id, pg_temp.uid(1)) from pg_temp.msgs where n = 1) as group_1,
  (select pg_temp.claim_all(id, pg_temp.uid(1)) from pg_temp.msgs where n = 2) as group_2,
  (select pg_temp.claim_all(id, pg_temp.uid(1)) from pg_temp.msgs where n = 3) as group_3,
  (select pg_temp.claim_all(id, pg_temp.uid(1)) from pg_temp.msgs where n = 4) as channel_1,
  (select pg_temp.claim_all(id, pg_temp.uid(1)) from pg_temp.msgs where n = 5) as channel_2,
  (select pg_temp.claim_all(id, pg_temp.uid(1)) from pg_temp.msgs where n = 6) as channel_3;
