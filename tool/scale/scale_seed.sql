-- L6 scale test, part 1: the data. Included by tool/scale/run_scale.sh inside
-- a transaction that is always rolled back, so nothing stays in the local
-- database. Expects the psql variables below (the shell script sets them):
--
--   users            people in total
--   group_members    members of the one big group
--   circle_members   members of the one big circle (at most users)
--   circle_channels  text channels of the big circle
--   group_msgs       messages in the big group
--   channel_msgs     messages per circle channel
--   dm_count         friends of the main user (one direct chat each)
--   small_groups     small groups the main user is also in
--
-- Cast (all derived from a number, see pg_temp.uid):
--   user 1   the main user "Mia": owner of the circle and the big group,
--            in 100+ chats
--   user 2   an ordinary member of everything (never read anything)
--   user 3   a moderator of the circle
\set ON_ERROR_STOP on

create temp table failures (msg text);
create temp table ids (name text primary key, id uuid not null);
create temp table bench_results (
  seq serial, area text, label text, runs int, min_ms numeric, median_ms numeric, max_ms numeric
);
grant all on failures, ids, bench_results to public;
grant usage on sequence bench_results_seq_seq to public;

create function pg_temp.uid(n integer) returns uuid language sql immutable as $$
  select ('10000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
$$;
create function pg_temp.i(n text) returns uuid language sql as $$
  select id from pg_temp.ids where name = n
$$;
create function pg_temp.act(user_id uuid) returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_id, 'role', 'authenticated')::text,
    true
  );
  execute 'set local role authenticated';
end $$;
create function pg_temp.root() returns void language plpgsql as $$
begin
  execute 'reset role';
end $$;

-- Runs a statement `runs` times and records how long each took.
create function pg_temp.bench(area text, label text, stmt text, runs integer default 5)
returns void language plpgsql as $$
declare
  t0 timestamptz; i integer; times numeric[] := '{}';
begin
  for i in 1..runs loop
    t0 := clock_timestamp();
    execute stmt;
    times := times || (extract(epoch from clock_timestamp() - t0) * 1000)::numeric;
  end loop;
  insert into pg_temp.bench_results (area, label, runs, min_ms, median_ms, max_ms)
  select area, label, runs, round(min(t), 2),
    round((percentile_cont(0.5) within group (order by t))::numeric, 2), round(max(t), 2)
  from unnest(times) t;
end $$;
grant execute on function pg_temp.bench(text, text, text, integer) to public;
grant execute on all functions in schema pg_temp to public;

\o /dev/null
-- ------------------------------------------------------------------ people
\echo seeding people
insert into auth.users (id, email, instance_id, aud, role)
select pg_temp.uid(n), 'scale' || n || '@l6.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from generate_series(1, :users) n;

insert into public.profiles (id, username, display_name)
select pg_temp.uid(n), 'scale_' || n, 'Scale User ' || n
from generate_series(1, :users) n;

-- One push subscription each, two for every fifth person; half read Chinese.
insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
select pg_temp.uid(n), 'https://push.example/l6/' || n || '/' || k, repeat('p', 50), repeat('a', 20),
  case when n % 2 = 0 then 'zh' else 'en' end
from generate_series(1, :users) n, generate_series(1, 2) k
where k = 1 or n % 5 = 0;

insert into public.friendships (user_low_id, user_high_id)
select pg_temp.uid(1), pg_temp.uid(n) from generate_series(2, :dm_count + 1) n;

-- A few people have blocked each other, so the block checks have rows.
insert into public.blocks (blocker_id, blocked_id)
select pg_temp.uid(n), pg_temp.uid(n + 1) from generate_series(100, 300, 2) n;

-- ------------------------------------------------------------ the circle
-- Through the real functions (triggers on), then the members in bulk.
select pg_temp.act(pg_temp.uid(1));
insert into pg_temp.ids select 'circle', public.create_circle('Scale Circle', array[]::uuid[]);
insert into pg_temp.ids
select 'role_mod', public.create_circle_role(pg_temp.i('circle'), 'Mod', null, 4);
insert into pg_temp.ids
select 'chan' || n, public.create_circle_channel(pg_temp.i('circle'), 'chan-' || n, null, 'text')
from generate_series(1, :circle_channels) n;
insert into pg_temp.ids
select 'staff', public.create_circle_channel(pg_temp.i('circle'), 'staff', null, 'text');
select pg_temp.root();

-- The staff channel hides itself from @everyone and shows itself to Mod.
insert into public.circle_channel_overwrites (circle_id, channel_id, role_id, allow, deny)
select pg_temp.i('circle'), pg_temp.i('staff'), r.id, 0, 1
from public.circle_roles r where r.circle_id = pg_temp.i('circle') and r.is_default;
insert into public.circle_channel_overwrites (circle_id, channel_id, role_id, allow, deny)
values (pg_temp.i('circle'), pg_temp.i('staff'), pg_temp.i('role_mod'), 1, 0);

set session_replication_role = replica;

insert into public.circle_members (circle_id, user_id, role)
select pg_temp.i('circle'), pg_temp.uid(n), 'member'
from generate_series(2, :circle_members) n
on conflict do nothing;

-- 300 moderators.
insert into public.circle_member_roles (circle_id, user_id, role_id)
select pg_temp.i('circle'), pg_temp.uid(n), pg_temp.i('role_mod')
from generate_series(3, 302) n;

-- Everyone is in every public channel's conversation; only moderators in staff.
insert into public.conversation_members (conversation_id, user_id, role)
select cc.conversation_id, cm.user_id, 'member'
from public.circle_channels cc
join public.circle_members cm on cm.circle_id = cc.circle_id
where cc.circle_id = pg_temp.i('circle')
  and cc.id <> pg_temp.i('staff')
on conflict do nothing;
insert into public.conversation_members (conversation_id, user_id, role)
select cc.conversation_id, mr.user_id, 'member'
from public.circle_channels cc
join public.circle_member_roles mr on mr.circle_id = cc.circle_id
where cc.id = pg_temp.i('staff')
on conflict do nothing;

-- ------------------------------------------------------------- the group
insert into pg_temp.ids values ('group', '20000000-0000-4000-8000-000000000001');
insert into public.conversations (id, type, title)
values (pg_temp.i('group'), 'group', 'Scale Group');
insert into public.conversation_members (conversation_id, user_id, role)
select pg_temp.i('group'), pg_temp.uid(n), case when n = 1 then 'owner' when n <= 20 then 'admin' else 'member' end
from generate_series(1, :group_members) n;

-- ----------------------------------------------- the main user's other chats
insert into pg_temp.ids
select 'dm' || n, ('30000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
from generate_series(2, :dm_count + 1) n;
insert into public.conversations (id, type)
select pg_temp.i('dm' || n), 'direct' from generate_series(2, :dm_count + 1) n;
insert into public.conversation_members (conversation_id, user_id)
select pg_temp.i('dm' || n), pg_temp.uid(u)
from generate_series(2, :dm_count + 1) n, lateral (values (1), (n)) v(u);

insert into pg_temp.ids
select 'small' || n, ('40000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
from generate_series(1, :small_groups) n;
insert into public.conversations (id, type, title)
select pg_temp.i('small' || n), 'group', 'Small group ' || n from generate_series(1, :small_groups) n;
insert into public.conversation_members (conversation_id, user_id, role)
select pg_temp.i('small' || n), pg_temp.uid(u), case when u = 1 then 'owner' else 'member' end
from generate_series(1, :small_groups) n, generate_series(1, 20) u;

-- --------------------------------------------------------------- messages
\echo seeding messages
create temp table words (n int, w text);
insert into words
select n, (array['hello','project','meeting','lunch','release','deploy','review','coffee','weekend','budget',
  'design','server','bug','fix','plan','travel','music','movie','game','study'])[1 + n % 20]
from generate_series(0, 999) n;

-- seed_messages(conversation, members to pick senders from, count, days)
create function pg_temp.seed_messages(conv uuid, sender_pool integer, total integer, days integer)
returns void language sql as $$
  insert into public.messages (id, conversation_id, sender_id, type, body, created_at)
  select gen_random_uuid(), conv, pg_temp.uid(1 + (g * 7919) % sender_pool), 'text',
    'msg ' || g || ' ' || w1.w || ' ' || w2.w || case when g % 5000 = 0 then ' rareword' else '' end,
    now() - make_interval(secs => (total - g) * (days * 86400.0 / total))
  from generate_series(1, total) g
  join words w1 on w1.n = g % 1000
  join words w2 on w2.n = (g * 31) % 1000
$$;

select pg_temp.seed_messages(pg_temp.i('group'), :group_members, :group_msgs, 90);
select pg_temp.seed_messages(cc.conversation_id,
  :circle_members, case when cc.id = pg_temp.i('staff') then :channel_msgs / 10 else :channel_msgs end, 60)
from public.circle_channels cc where cc.circle_id = pg_temp.i('circle');
select pg_temp.seed_messages(pg_temp.i('dm' || n), 2, 30, 30) from generate_series(2, :dm_count + 1) n;
select pg_temp.seed_messages(pg_temp.i('small' || n), 20, 200, 30) from generate_series(1, :small_groups) n;

-- A few people are mentioned (@everyone style bursts excluded).
insert into public.message_mentions (message_id, conversation_id, user_id, kind)
select m.id, m.conversation_id, pg_temp.uid(1), 'user'
from public.messages m
where m.conversation_id = pg_temp.i('group') and m.body like 'msg %0 %'
limit 500;

-- The search index the insert trigger would have filled.
insert into public.message_search_entries (message_id, conversation_id, sender_id, created_at, document, vector, kinds)
select m.id, m.conversation_id, m.sender_id, m.created_at,
  public.message_search_document(m.type, m.body, m.attachment),
  public.message_search_vector(m.type, m.body, m.attachment),
  public.message_search_kinds(m.type, m.body, m.attachment)
from public.messages m;

-- What the touch trigger would have done: the latest message of each chat.
update public.conversations c
set last_message_id = l.id, last_message_at = l.created_at, updated_at = l.created_at
from (
  select distinct on (conversation_id) conversation_id, id, created_at
  from public.messages order by conversation_id, created_at desc, id desc
) l
where l.conversation_id = c.id;

-- Read markers: the main user is behind by about 2000 messages in the big
-- group and by about 300 in each channel, caught up in the rest. Everyone
-- else has read nothing (a null marker counts every message).
update public.conversation_members cm
set last_read_message_id = (
  select m.id from public.messages m
  where m.conversation_id = cm.conversation_id
  order by m.created_at desc, m.id desc
  offset case when cm.conversation_id = pg_temp.i('group') then 2000 else 300 end limit 1
)
where cm.user_id = pg_temp.uid(1)
  and (cm.conversation_id = pg_temp.i('group')
    or cm.conversation_id in (select conversation_id from public.circle_channels where circle_id = pg_temp.i('circle')));
update public.conversation_members cm
set last_read_message_id = c.last_message_id
from public.conversations c
where c.id = cm.conversation_id and cm.user_id = pg_temp.uid(1) and cm.last_read_message_id is null;

-- Half of the group has read up to about 1000 messages ago.
update public.conversation_members cm
set last_read_message_id = (
  select m.id from public.messages m
  where m.conversation_id = cm.conversation_id
  order by m.created_at desc, m.id desc offset 1000 limit 1
)
where cm.conversation_id = pg_temp.i('group') and cm.user_id > pg_temp.uid(2500) and cm.user_id <> pg_temp.uid(1);

-- The AI guard watches the circle: new members' messages are checked.
insert into public.circle_ai_guard (circle_id, enabled, new_rule, joined_days, message_count, action)
values (pg_temp.i('circle'), true, 'joined_days', 7, 5, 'hold')
on conflict (circle_id) do update set enabled = true;

set session_replication_role = origin;
\echo analyzing
analyze public.messages;
analyze public.conversation_members;
analyze public.conversations;
analyze public.circle_members;
analyze public.circle_member_roles;
analyze public.message_search_entries;
analyze public.message_mentions;
analyze public.profiles;
analyze public.push_subscriptions;
analyze public.circle_channels;
analyze public.blocks;
\o

-- Statement statistics for the profile runs: pg_stat_statements can be told
-- to count the statements inside functions too (it is only a session setting).
set pg_stat_statements.track = 'all';
create temp table profile_results (
  seq serial, label text, calls bigint, total_ms numeric, mean_ms numeric, query text
);
grant all on profile_results to public;
grant usage on sequence profile_results_seq_seq to public;
-- Keeps the heaviest statements seen since the last reset (call as the owner).
create function pg_temp.snapshot(label text, top integer default 6) returns void language sql as $$
  insert into pg_temp.profile_results (label, calls, total_ms, mean_ms, query)
  select label, calls, round(total_exec_time::numeric, 1), round(mean_exec_time::numeric, 2),
    left(regexp_replace(query, '\s+', ' ', 'g'), 230)
  from pg_stat_statements
  where dbid = (select oid from pg_database where datname = current_database())
    and query not like '%pg_stat_statements%'
    and query not like '%pg_temp%'
  order by total_exec_time desc limit top
$$;
grant execute on function pg_temp.snapshot(text, integer) to public;
