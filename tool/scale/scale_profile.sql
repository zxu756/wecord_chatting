-- L6 scale test: where the time goes. For each hot call, prints the heaviest
-- statements it ran (including the ones inside functions and triggers), from
-- pg_stat_statements. Run with:
--   sh tool/scale/run_scale.sh full before tool/scale/scale_profile.sql
-- Statements other sessions run at the same time can show up too; ignore
-- the ones that do not touch the seeded data.
\set ON_ERROR_STOP on
\o /dev/null
select pg_temp.i('group') as group_id \gset
select pg_temp.i('circle') as circle_id \gset
select conversation_id as chan1_conv from public.circle_channels where id = pg_temp.i('chan1') \gset
select pg_temp.uid(1) as u1 \gset
select pg_temp.uid(2) as u2 \gset

-- A macro: reset the counters, become :who, run :stmt twice, snapshot.
-- (psql variables are set per probe below.)

select pg_stat_statements_reset() \gset
select pg_temp.act(:'u1') \gset
select pg_temp.bench('p', 'summaries u1', 'select * from public.list_conversation_summaries()', 2);
select pg_temp.root() \gset
select pg_temp.snapshot('list_conversation_summaries (busy user)');

select pg_stat_statements_reset() \gset
select pg_temp.act(:'u2') \gset
select pg_temp.bench('p', 'summaries u2', 'select * from public.list_conversation_summaries()', 2);
select pg_temp.root() \gset
select pg_temp.snapshot('list_conversation_summaries (member)');

select pg_stat_statements_reset() \gset
select pg_temp.act(:'u1') \gset
select pg_temp.bench('p', 'get_conversation_summary', format('select * from public.get_conversation_summary(%L)', :'group_id'), 2);
select pg_temp.root() \gset
select pg_temp.snapshot('get_conversation_summary (big group)');

select pg_stat_statements_reset() \gset
select pg_temp.act(:'u1') \gset
select pg_temp.bench('p', 'send group', format($q$select public.send_text_message(%L, 'bench message')$q$, :'group_id'), 3);
select pg_temp.root() \gset
select pg_temp.snapshot('send_text_message (big group)', 10);

select pg_stat_statements_reset() \gset
select pg_temp.act(:'u1') \gset
select pg_temp.bench('p', 'send channel', format($q$select public.send_text_message(%L, 'bench message')$q$, :'chan1_conv'), 3);
select pg_temp.root() \gset
select pg_temp.snapshot('send_text_message (circle channel)', 10);

select pg_stat_statements_reset() \gset
select pg_temp.act(:'u2') \gset
select pg_temp.bench('p', 'send newcomer', format($q$select public.send_text_message(%L, 'bench message')$q$, :'chan1_conv'), 3);
select pg_temp.root() \gset
select pg_temp.snapshot('send_text_message (member of a guarded circle)', 10);

select pg_stat_statements_reset() \gset
select pg_temp.act(:'u1') \gset
select pg_temp.bench('p', 'channel page', format($q$
  select m.*, public.is_pinned(m), public.sender_nickname(m), public.sender_circle_avatar(m),
    public.sender_role_color(m), public.thread_summary(m), public.poll_results(m)
  from public.messages m where m.conversation_id = %L
  order by m.created_at desc, m.id desc limit 50$q$, :'chan1_conv'), 3);
select pg_temp.root() \gset
select pg_temp.snapshot('latest 50 messages of a circle channel');

select pg_stat_statements_reset() \gset
select pg_temp.act(:'u1') \gset
select pg_temp.bench('p', 'circle detail', format('select public.get_circle_detail(%L)', :'circle_id'), 2);
select pg_temp.root() \gset
select pg_temp.snapshot('get_circle_detail');

select pg_stat_statements_reset() \gset
select pg_temp.act(:'u1') \gset
select pg_temp.bench('p', 'circle summaries', 'select * from public.list_circle_summaries()', 2);
select pg_temp.root() \gset
select pg_temp.snapshot('list_circle_summaries');

select pg_stat_statements_reset() \gset
select pg_temp.act(:'u1') \gset
select pg_temp.bench('p', 'search', $q$select * from public.search_messages('meeting')$q$, 2);
select pg_temp.root() \gset
select pg_temp.snapshot('search_messages(text)');

select pg_stat_statements_reset() \gset
select pg_temp.act(:'u1') \gset
select pg_temp.bench('p', 'search2', $q$select public.search_messages('meeting', '{}'::jsonb, '{}'::jsonb, 'newest', 25, null)$q$, 2);
select pg_temp.root() \gset
select pg_temp.snapshot('search_messages (advanced)');

-- The push claim.
select pg_temp.act(:'u1') \gset
select public.send_text_message(:'group_id', 'push bench 1') as push_msg_group \gset
select public.send_text_message(:'chan1_conv', 'push bench 2') as push_msg_chan \gset
select pg_temp.root() \gset
select pg_stat_statements_reset() \gset
select count(*) from public.claim_push_delivery(:'push_msg_group', :'u1') \gset
select pg_temp.snapshot('claim_push_delivery (big group)', 8);
select pg_stat_statements_reset() \gset
select count(*) from public.claim_push_delivery(:'push_msg_chan', :'u1') \gset
select pg_temp.snapshot('claim_push_delivery (circle channel)', 8);

\o
\pset format unaligned
\pset fieldsep ' | '
\pset tuples_only on
select label || ' | calls=' || calls || ' total=' || total_ms || 'ms mean=' || mean_ms || 'ms | ' || query
from pg_temp.profile_results order by seq;
