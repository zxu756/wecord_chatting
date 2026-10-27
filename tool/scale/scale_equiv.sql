-- L6 scale test: the rewritten functions must answer exactly what the old
-- ones did. Asks both (l6old = before, public = after) the same questions
-- about the seeded data and prints every difference. Run by run_scale.sh
-- (phase equiv). Prints "equiv: N checks, M differences".
\set ON_ERROR_STOP on
\o /dev/null
select set_config('l6.group', pg_temp.i('group')::text, false) \gset
select set_config('l6.circle', pg_temp.i('circle')::text, false) \gset
select set_config('l6.chan1', conversation_id::text, false) from public.circle_channels where id = pg_temp.i('chan1') \gset
select set_config('l6.staff', conversation_id::text, false) from public.circle_channels where id = pg_temp.i('staff') \gset
select set_config('l6.dm2', pg_temp.i('dm2')::text, false) \gset
select set_config('l6.small1', pg_temp.i('small1')::text, false) \gset
select set_config('l6.users', :'users', false) \gset

create temp table equiv_log (ok boolean, label text, detail text);
grant all on equiv_log to public;

-- Both statements return rows; their rows (as JSON, sorted) must match.
create function pg_temp.same(label text, old_stmt text, new_stmt text) returns void
language plpgsql as $$
declare a jsonb; b jsonb;
begin
  execute 'select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text), ''[]'') from (' || old_stmt || ') t' into a;
  execute 'select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text), ''[]'') from (' || new_stmt || ') t' into b;
  insert into pg_temp.equiv_log values (a = b, label,
    case when a = b then null else 'old=' || left(a::text, 300) || ' new=' || left(b::text, 300) end);
end $$;
grant execute on function pg_temp.same(text, text, text) to public;

-- A direct chat between two people one of whom blocked the other, and one
-- with a deleted account.
insert into public.conversations (id, type) values
  ('50000000-0000-4000-8000-000000000001', 'direct'),
  ('50000000-0000-4000-8000-000000000002', 'direct');
insert into public.conversation_members (conversation_id, user_id) values
  ('50000000-0000-4000-8000-000000000001', pg_temp.uid(100)),
  ('50000000-0000-4000-8000-000000000001', pg_temp.uid(101)),
  ('50000000-0000-4000-8000-000000000002', pg_temp.uid(110)),
  ('50000000-0000-4000-8000-000000000002', pg_temp.uid(111));
update public.profiles set deleted_at = now() where id = pg_temp.uid(111);

do $do$
declare
  u integer;
  target text;
begin
  foreach u in array array[1, 2, 3, 200, 100, 110] loop
    perform pg_temp.act(pg_temp.uid(u));
    perform pg_temp.same('list_conversation_summaries as ' || u,
      'select * from l6old.list_conversation_summaries()',
      'select * from public.list_conversation_summaries()');
    perform pg_temp.same('list_circle_summaries as ' || u,
      'select * from l6old.list_circle_summaries()',
      'select * from public.list_circle_summaries()');
    foreach target in array array[
      current_setting('l6.group'), current_setting('l6.dm2'), current_setting('l6.small1'),
      current_setting('l6.chan1'), current_setting('l6.staff'),
      '50000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000002'
    ] loop
      perform pg_temp.same('get_conversation_summary ' || left(target, 12) || ' as ' || u,
        format('select * from l6old.get_conversation_summary(%L)', target),
        format('select * from public.get_conversation_summary(%L)', target));
      perform pg_temp.same('blocked ' || left(target, 12) || ' as ' || u,
        format('select l6old.is_current_user_blocked_in_conversation(%L)', target),
        format('select public.is_current_user_blocked_in_conversation(%L)', target));
    end loop;
    foreach target in array array['meeting', 'rareword', 'hello project', 'zzzzz'] loop
      perform pg_temp.same('search_messages ' || target || ' as ' || u,
        format('select * from l6old.search_messages(%L)', target),
        format('select * from public.search_messages(%L)', target));
    end loop;
  end loop;
  perform pg_temp.act(pg_temp.uid(1));
  perform pg_temp.same('get_circle_detail',
    format('select l6old.get_circle_detail(%L)', current_setting('l6.circle')),
    format('select public.get_circle_detail(%L) #- ''{circle,member_count}'' as get_circle_detail', current_setting('l6.circle')));
  perform pg_temp.root();
end $do$;

-- ----------------------------------------------------- the push claim
-- Two identical messages: the old claim on one, the new on the other. The
-- same people get the same words.
select pg_temp.act(pg_temp.uid(1)) \gset
select public.send_text_message(current_setting('l6.group')::uuid, 'equiv push') as m1 \gset
select public.send_text_message(current_setting('l6.group')::uuid, 'equiv push') as m2 \gset
select public.send_text_message(current_setting('l6.chan1')::uuid, 'equiv push') as m3 \gset
select public.send_text_message(current_setting('l6.chan1')::uuid, 'equiv push') as m4 \gset
select pg_temp.root() \gset
select pg_temp.same('claim_push_delivery group',
  format('select subscription_id, endpoint, title, body from l6old.claim_push_delivery(%L, %L)', :'m1', pg_temp.uid(1)),
  format('select subscription_id, endpoint, title, body from public.claim_push_delivery(%L, %L)', :'m2', pg_temp.uid(1)));
select pg_temp.same('claim_push_delivery channel',
  format('select subscription_id, endpoint, title, body from l6old.claim_push_delivery(%L, %L)', :'m3', pg_temp.uid(1)),
  format('select subscription_id, endpoint, title, body from public.claim_push_delivery(%L, %L)', :'m4', pg_temp.uid(1)));

-- ------------------------------------------------------ the push batches
-- The same message twice: the old claim in one go, the new one in batches of
-- 37 people. Together the batches are the old answer, each person once.
select pg_temp.act(pg_temp.uid(1)) \gset
select public.send_text_message(current_setting('l6.group')::uuid, 'equiv pages') as p1 \gset
select public.send_text_message(current_setting('l6.group')::uuid, 'equiv pages') as p2 \gset
select public.send_text_message(current_setting('l6.chan1')::uuid, 'equiv pages') as p3 \gset
select public.send_text_message(current_setting('l6.chan1')::uuid, 'equiv pages') as p4 \gset
select pg_temp.root() \gset
select set_config('l6.p1', :'p1', false), set_config('l6.p2', :'p2', false),
       set_config('l6.p3', :'p3', false), set_config('l6.p4', :'p4', false) \gset
create temp table equiv_batches (message text, recipient uuid, subscription_id uuid, title text, body text);
do $do$
declare
  old_message uuid;
  new_message uuid;
  last_user uuid;
  got integer;
  pages integer;
  label text;
  i integer;
begin
  for i in 1..2 loop
    if i = 1 then
      old_message := current_setting('l6.p1')::uuid; new_message := current_setting('l6.p2')::uuid; label := 'group';
    else
      old_message := current_setting('l6.p3')::uuid; new_message := current_setting('l6.p4')::uuid; label := 'channel';
    end if;
    last_user := null; pages := 0;
    loop
      create temp table if not exists equiv_page (recipient uuid, subscription_id uuid, title text, body text) on commit drop;
      truncate equiv_page;
      insert into pg_temp.equiv_page
      select recipient_id, subscription_id, title, body
      from public.claim_push_delivery(new_message, pg_temp.uid(1), last_user, 37);
      insert into pg_temp.equiv_batches
      select label, recipient, subscription_id, title, body from pg_temp.equiv_page;
      select count(distinct recipient), (array_agg(recipient order by recipient desc))[1]
        into got, last_user from pg_temp.equiv_page;
      pages := pages + 1;
      exit when got < 37;
    end loop;
    insert into pg_temp.equiv_log
    select
      (select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text), '[]') from (
        select subscription_id, title, body from pg_temp.equiv_batches where message = label
      ) t) = (select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text), '[]') from (
        select subscription_id, title, body from l6old.claim_push_delivery(old_message, pg_temp.uid(1))
      ) t),
      'claim_push_delivery batches ' || label || ' (' || pages || ' batches)', null;
  end loop;
end $do$;
-- A batch after the first of a message nobody claimed gives nothing.
select pg_temp.same('claim_push_delivery unclaimed',
  'select 1 where false',
  format('select * from public.claim_push_delivery(%L, %L, %L, 10)',
    gen_random_uuid(), pg_temp.uid(1), pg_temp.uid(5)));

-- ------------------------------------------------ the member pages (1210)
create function pg_temp.verify(label text, ok boolean, detail text default null) returns void
language sql as $$ insert into pg_temp.equiv_log values (ok, label, detail) $$;
grant execute on function pg_temp.verify(text, boolean, text) to public;

do $do$
declare
  circle uuid := current_setting('l6.circle')::uuid;
  u integer;
  everyone jsonb;
  limited jsonb;
  pages jsonb;
  page jsonb;
  cursor_row jsonb;
  n integer;
  expected_ids jsonb;
begin
  foreach u in array array[1, 9, 900] loop
    perform pg_temp.act(pg_temp.uid(u));
    everyone := l6old.get_circle_detail(circle)->'members';
    expected_ids := (select jsonb_agg(m->'profile'->'id') from jsonb_array_elements(everyone) m);
    -- 1. get_circle_detail with member_limit: the first 50 and the caller,
    -- the same circle otherwise, and the number of members.
    limited := public.get_circle_detail(circle, 50);
    perform pg_temp.verify('get_circle_detail(limit) members as ' || u,
      (select count(*) from jsonb_array_elements(limited->'members')) <= 51
      and (select bool_or((m->>'is_current_user')::boolean) from jsonb_array_elements(limited->'members') m)
      and not exists (
        select 1 from jsonb_array_elements(limited->'members') m
        where not (everyone @> jsonb_build_array(m))
      ),
      'limited count ' || (select count(*) from jsonb_array_elements(limited->'members')));
    perform pg_temp.verify('get_circle_detail(limit) member_count as ' || u,
      (limited->'circle'->>'member_count')::integer = jsonb_array_length(everyone));
    perform pg_temp.verify('get_circle_detail(limit) rest as ' || u,
      (limited - 'members' #- '{circle,member_count}') = (l6old.get_circle_detail(circle) - 'members'));
    perform pg_temp.verify('get_circle_detail() unchanged as ' || u,
      (public.get_circle_detail(circle) #- '{circle,member_count}') = l6old.get_circle_detail(circle));
    -- 2. All the pages of list_circle_members_page, one after the other, are
    -- the old member list in the old order.
    pages := '[]'; cursor_row := null; n := 0;
    loop
      select coalesce(jsonb_agg(r order by (r->>'sort_rank')::int, r->>'sort_name', r->'profile'->>'id'), '[]')
        into page
      from public.list_circle_members_page(
        circle, 97,
        (cursor_row->>'sort_rank')::integer, cursor_row->>'sort_name',
        (cursor_row->'profile'->>'id')::uuid, null
      ) r;
      exit when jsonb_array_length(page) = 0;
      pages := pages || page;
      cursor_row := page->(jsonb_array_length(page) - 1);
      n := n + 1;
      exit when n > 400;
    end loop;
    perform pg_temp.verify('list_circle_members_page all pages as ' || u,
      (select coalesce(jsonb_agg(m->'profile'->'id'), '[]') from jsonb_array_elements(pages) m)
        = coalesce(expected_ids, '[]'),
      n || ' pages, ' || jsonb_array_length(pages) || ' of ' || jsonb_array_length(everyone));
    perform pg_temp.verify('list_circle_members_page row shape as ' || u,
      (select coalesce(jsonb_agg(m - 'sort_rank' - 'sort_name' order by m->'profile'->>'id'), '[]') from jsonb_array_elements(pages) m)
        = (select coalesce(jsonb_agg(m order by m->'profile'->>'id'), '[]') from jsonb_array_elements(everyone) m));
    -- 3. A search finds the same people as filtering the full list.
    perform pg_temp.verify('list_circle_members_page search as ' || u,
      (select coalesce(jsonb_agg(r->'profile'->'id' order by r->'profile'->>'id'), '[]')
        from public.list_circle_members_page(circle, 200, null, null, null, 'scale user 12') r)
      = (select coalesce(jsonb_agg(m->'profile'->'id' order by m->'profile'->>'id'), '[]')
        from jsonb_array_elements(everyone) m
        where position('scale user 12' in lower(coalesce(m->>'nickname', ''))) > 0
           or position('scale user 12' in lower(m->'profile'->>'display_name')) > 0
           or position('scale user 12' in lower(m->'profile'->>'username')) > 0
        limit 200));
  end loop;
  -- A stranger to the circle gets nothing.
  perform pg_temp.act(pg_temp.uid(current_setting('l6.users')::integer));
  perform pg_temp.verify('list_circle_members_page stranger',
    (select count(*) from public.list_circle_members_page(circle, 50)) = 0
    or exists (select 1 from public.circle_members where circle_id = circle and user_id = pg_temp.uid(current_setting('l6.users')::integer)));
  perform pg_temp.root();
end $do$;

-- The pages of a conversation's members are what the policy shows a member.
do $do$
declare
  target text;
  u integer;
  seen uuid[];
  expected uuid[];
  cursor_joined timestamptz;
  cursor_user uuid;
  page jsonb;
  n integer;
  shown integer;
begin
  foreach u in array array[1, 2, 900, current_setting('l6.users')::integer] loop
    perform pg_temp.act(pg_temp.uid(u));
    foreach target in array array[current_setting('l6.group'), current_setting('l6.chan1'), current_setting('l6.staff'), current_setting('l6.small1')] loop
      expected := (select coalesce(array_agg(user_id order by user_id), '{}') from public.conversation_members where conversation_id = target::uuid);
      seen := '{}'; cursor_joined := null; cursor_user := null; n := 0;
      loop
        select coalesce(jsonb_agg(r), '[]') into page
        from public.list_conversation_members_page(target::uuid, 211, cursor_joined, cursor_user, null) r;
        exit when jsonb_array_length(page) = 0 or n > 100;
        seen := seen || (select array_agg((r->'profile'->>'id')::uuid) from jsonb_array_elements(page) r);
        select (cm.joined_at), cm.user_id into cursor_joined, cursor_user
        from public.conversation_members cm
        where cm.conversation_id = target::uuid
          and cm.user_id = (page->(jsonb_array_length(page) - 1)->'profile'->>'id')::uuid;
        n := n + 1;
      end loop;
      perform pg_temp.verify('list_conversation_members_page ' || left(target, 12) || ' as ' || u,
        (select coalesce(array_agg(x order by x), '{}') from unnest(seen) x) = expected,
        'pages ' || n || ' seen ' || coalesce(cardinality(seen), 0) || ' expected ' || cardinality(expected));
    end loop;
  end loop;
  perform pg_temp.root();
end $do$;

\o
select 'equiv: ' || count(*) || ' checks, ' || count(*) filter (where not ok) || ' differences' as result from pg_temp.equiv_log;
select label, detail from pg_temp.equiv_log where not ok order by label limit 20;
