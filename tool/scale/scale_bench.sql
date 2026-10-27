-- L6 scale test, part 2: the measurements. Included by run_scale.sh after
-- scale_seed.sql, inside the same rolled-back transaction. Prints a table of
-- timings (milliseconds per call: fastest, median, slowest of N runs) and,
-- when the psql variable `plans` is 1, the EXPLAIN (ANALYZE, BUFFERS) of the
-- statements that deserve a look.
\set ON_ERROR_STOP on
\o
\pset format aligned
\pset tuples_only off


\echo
\echo === sizes
select
  (select count(*) from public.messages) as messages,
  (select count(*) from public.conversation_members) as conversation_members,
  (select count(*) from public.circle_members) as circle_members,
  (select count(*) from public.conversations) as conversations,
  (select count(*) from public.message_search_entries) as search_entries,
  (select count(*) from public.push_subscriptions) as push_subscriptions;

select pg_temp.i('group') as group_id \gset
select pg_temp.i('circle') as circle_id \gset
select pg_temp.i('chan1') as chan1_id \gset
select conversation_id as chan1_conv from public.circle_channels where id = pg_temp.i('chan1') \gset
select conversation_id as staff_conv from public.circle_channels where id = pg_temp.i('staff') \gset
select pg_temp.uid(1) as u1 \gset
select pg_temp.uid(2) as u2 \gset
select pg_temp.uid(3) as u3 \gset
select id as group_last from public.messages where conversation_id = pg_temp.i('group') order by created_at desc, id desc limit 1 \gset
select created_at as group_cursor_at, id as group_cursor_id from public.messages
  where conversation_id = pg_temp.i('group') order by created_at desc, id desc
  offset (select count(*) / 3 from public.messages where conversation_id = pg_temp.i('group')) limit 1 \gset

\o /dev/null
-- ------------------------------------------------------------ chat list
select pg_temp.act(:'u1') \gset
select pg_temp.bench('chat list', 'list_conversation_summaries (busy user, 180 chats)', 'select * from public.list_conversation_summaries()');
select pg_temp.act(:'u2') \gset
select pg_temp.bench('chat list', 'list_conversation_summaries (member, 10 chats, no read marks)', 'select * from public.list_conversation_summaries()');
select pg_temp.bench('chat list', 'get_conversation_summary (big group)', format('select * from public.get_conversation_summary(%L)', :'group_id'));
select pg_temp.bench('chat list', 'current_user_readable_conversation_ids', 'select count(*) from public.current_user_readable_conversation_ids()');

-- ------------------------------------------------------------- messages
select pg_temp.act(:'u1') \gset
select pg_temp.bench('messages', 'latest 50 of the big group (client query, with computed columns)', format($q$
  select m.*, public.is_pinned(m), public.sender_nickname(m), public.sender_circle_avatar(m),
    public.sender_role_color(m), public.thread_summary(m), public.poll_results(m)
  from public.messages m where m.conversation_id = %L
  order by m.created_at desc, m.id desc limit 50$q$, :'group_id'));
select pg_temp.bench('messages', 'older page 50 (cursor deep in history)', format($q$
  select m.*, public.is_pinned(m), public.sender_nickname(m)
  from public.messages m where m.conversation_id = %L
    and m.created_at <= %L and (m.created_at < %L or m.id < %L)
  order by m.created_at desc, m.id desc limit 50$q$, :'group_id', :'group_cursor_at', :'group_cursor_at', :'group_cursor_id'));
select pg_temp.bench('messages', 'latest 50 of a circle channel', format($q$
  select m.*, public.is_pinned(m), public.sender_nickname(m), public.sender_circle_avatar(m),
    public.sender_role_color(m), public.thread_summary(m), public.poll_results(m)
  from public.messages m where m.conversation_id = %L
  order by m.created_at desc, m.id desc limit 50$q$, :'chan1_conv'));
select pg_temp.bench('messages', 'list_conversation_reactions (whole big group)', format('select * from public.list_conversation_reactions(%L)', :'group_id'));
select pg_temp.bench('messages', 'latest_message_id (order by created_at desc limit 1)', format('select id from public.messages where conversation_id = %L order by created_at desc limit 1', :'group_id'));

-- -------------------------------------------------------------- members
select pg_temp.bench('members', 'group members (client query: all 5000 with profiles)', format($q$
  select cm.role, public.circle_nickname(cm), p.id, p.username, p.display_name, p.avatar_url
  from public.conversation_members cm join public.profiles p on p.id = cm.user_id
  where cm.conversation_id = %L order by cm.joined_at$q$, :'group_id'), 3);
select pg_temp.bench('members', 'group members through RLS (select * from conversation_members)', format($q$
  select * from public.conversation_members cm where cm.conversation_id = %L$q$, :'group_id'), 3);
select pg_temp.bench('members', 'list_read_markers (big group)', format('select * from public.list_read_markers(%L)', :'group_id'));
select pg_temp.bench('members', 'get_circle_detail (10000 members, all of them returned)', format('select public.get_circle_detail(%L)', :'circle_id'), 3);
select pg_temp.bench('members', 'list_circle_summaries', 'select * from public.list_circle_summaries()');

-- ---------------------------------------------------------------- unread
select pg_temp.bench('unread', 'mark_conversation_read (big group)', format('select public.mark_conversation_read(%L, %L)', :'group_id', :'group_last'));
select pg_temp.bench('unread', 'is_current_user_conversation_member (big group)', format('select public.is_current_user_conversation_member(%L)', :'group_id'));
select pg_temp.bench('unread', 'is_current_user_conversation_member (circle channel)', format('select public.is_current_user_conversation_member(%L)', :'chan1_conv'));

-- ---------------------------------------------------------------- search
select pg_temp.bench('search', 'search_messages: a rare word', $q$select * from public.search_messages('rareword')$q$);
select pg_temp.bench('search', 'search_messages: a common word', $q$select * from public.search_messages('meeting')$q$);
select pg_temp.bench('search', 'search_messages (advanced): a common word', $q$select public.search_messages('meeting', '{}'::jsonb, '{}'::jsonb, 'newest', 25, null)$q$);
select pg_temp.bench('search', 'search_messages (advanced): a rare word', $q$select public.search_messages('rareword', '{}'::jsonb, '{}'::jsonb, 'newest', 25, null)$q$);

-- ------------------------------------------------------------------ send
-- Sending as the owner in the big group, as the owner in a channel, and as
-- a new member (the AI guard holds newcomers' messages).
select pg_temp.act(:'u1') \gset
select pg_temp.bench('send', 'send_text_message: big group', format($q$select public.send_text_message(%L, 'bench message')$q$, :'group_id'), 10);
select pg_temp.bench('send', 'send_text_message: circle channel (10000 members)', format($q$select public.send_text_message(%L, 'bench message')$q$, :'chan1_conv'), 10);
select pg_temp.act(:'u2') \gset
select pg_temp.bench('send', 'send_text_message: newcomer in a guarded circle', format($q$select public.send_text_message(%L, 'bench message')$q$, :'chan1_conv'), 10);
select pg_temp.bench('send', 'send_text_message: direct chat', format($q$select public.send_text_message(%L, 'bench message')$q$, pg_temp.i('dm2')), 1);

-- ----------------------------------------------------------------- push
-- The server-side claim for one message: who gets a push. Run as the table
-- owner (the Edge Function uses the service role).
select pg_temp.root() \gset
select pg_temp.act(:'u1') \gset
select public.send_text_message(:'group_id', 'push bench 1') as push_msg_group \gset
select public.send_text_message(:'chan1_conv', 'push bench 2') as push_msg_chan \gset
select pg_temp.root() \gset
\o
\echo
\echo === push claim (rows returned, then milliseconds)
select clock_timestamp() as t0 \gset
select count(*) as claimed_group from public.claim_push_delivery(:'push_msg_group', :'u1') \gset
select round(extract(epoch from clock_timestamp() - :'t0'::timestamptz) * 1000, 1) as claim_group_ms \gset
select clock_timestamp() as t0 \gset
select count(*) as claimed_channel from public.claim_push_delivery(:'push_msg_chan', :'u1') \gset
select round(extract(epoch from clock_timestamp() - :'t0'::timestamptz) * 1000, 1) as claim_channel_ms \gset
select :claimed_group as rows_group, :claim_group_ms as ms_group, :claimed_channel as rows_channel, :claim_channel_ms as ms_channel;
insert into pg_temp.bench_results (area, label, runs, min_ms, median_ms, max_ms)
values ('push', 'claim_push_delivery: big group (' || :claimed_group || ' rows)', 1, :claim_group_ms, :claim_group_ms, :claim_group_ms),
  ('push', 'claim_push_delivery: circle channel (' || :claimed_channel || ' rows)', 1, :claim_channel_ms, :claim_channel_ms, :claim_channel_ms);

-- ------------------------------------------- pages (only after the L6 migrations)
select exists (select 1 from pg_proc where proname = 'list_circle_members_page') as has_pages \gset
\if :has_pages
\o /dev/null
select pg_temp.act(:'u1') \gset
select pg_temp.bench('pages', 'get_circle_detail(circle, 50): the first 50 members', format('select public.get_circle_detail(%L, 50)', :'circle_id'), 5);
select pg_temp.bench('pages', 'list_circle_members_page: first 100', format('select * from public.list_circle_members_page(%L, 100)', :'circle_id'), 5);
select pg_temp.bench('pages', 'list_circle_members_page: search "scale user 77"', format($q$select * from public.list_circle_members_page(%L, 30, null, null, null, 'scale user 77')$q$, :'circle_id'), 3);
select pg_temp.bench('pages', 'list_conversation_members_page: first 100 of the group', format('select * from public.list_conversation_members_page(%L, 100)', :'group_id'), 5);
select pg_temp.bench('pages', 'list_conversation_members_page: mention search "scale user 4"', format($q$select * from public.list_conversation_members_page(%L, 8, null, null, 'scale user 4')$q$, :'group_id'), 5);
select pg_temp.bench('pages', 'list_conversation_members_page: first 100 of a circle channel', format('select * from public.list_conversation_members_page(%L, 100)', :'chan1_conv'), 3);
select public.send_text_message(:'group_id', 'push bench 3') as push_msg_paged \gset
select pg_temp.root() \gset
select clock_timestamp() as t0 \gset
select count(*) as paged_rows, (array_agg(recipient_id order by recipient_id desc))[1] as paged_cursor
  from public.claim_push_delivery(:'push_msg_paged', :'u1', null, 500) \gset
select round(extract(epoch from clock_timestamp() - :'t0'::timestamptz) * 1000, 1) as paged_first_ms \gset
select clock_timestamp() as t0 \gset
select count(*) as paged_rows2 from public.claim_push_delivery(:'push_msg_paged', :'u1', :'paged_cursor', 500) \gset
select round(extract(epoch from clock_timestamp() - :'t0'::timestamptz) * 1000, 1) as paged_next_ms \gset
insert into pg_temp.bench_results (area, label, runs, min_ms, median_ms, max_ms)
values ('pages', 'claim_push_delivery batch of 500 people, first (' || :paged_rows || ' rows)', 1, :paged_first_ms, :paged_first_ms, :paged_first_ms),
  ('pages', 'claim_push_delivery batch of 500 people, next (' || :paged_rows2 || ' rows)', 1, :paged_next_ms, :paged_next_ms, :paged_next_ms);
\endif

\o /dev/null
-- ----------------------------------------------------- membership changes
select pg_temp.root() \gset
select pg_temp.bench('membership', 'add one member to the big group', format($q$
  insert into public.conversation_members (conversation_id, user_id) values (%L, pg_temp.uid(%s + 1 + (extract(microseconds from clock_timestamp())::int %% (%s - %s))))
  on conflict do nothing$q$, :'group_id', :group_members, :users, :group_members), 5);

\o
\echo
\echo === timings (ms per call)
select area, label, runs, min_ms, median_ms, max_ms from pg_temp.bench_results order by seq;

\if :{?plans}
\echo
\echo === plans
select pg_temp.act(:'u1') \gset
\echo --- list_conversation_summaries
explain (analyze, buffers, costs off, timing on) select * from public.list_conversation_summaries();
\echo --- insert into messages (trigger times show where a send spends it)
select pg_temp.root() \gset
explain (analyze, buffers, costs off, timing on)
insert into public.messages (conversation_id, sender_id, type, body)
values (:'chan1_conv', :'u1', 'text', 'explain me');
explain (analyze, buffers, costs off, timing on)
insert into public.messages (conversation_id, sender_id, type, body)
values (:'group_id', :'u1', 'text', 'explain me');
\endif
