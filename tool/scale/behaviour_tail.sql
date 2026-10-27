\o /dev/null

create temp table failures (msg text);
grant all on failures to public;
create temp table checked (msg text);
grant all on checked to public;

create function pg_temp.expect(ok boolean, msg text) returns void
language plpgsql security definer as $$
begin
  insert into pg_temp.checked values (msg);
  if not coalesce(ok, false) then
    insert into pg_temp.failures values (msg);
  end if;
end $$;

-- Becomes [user_id] (null: nobody signed in).
create function pg_temp.act(user_id uuid) returns void language plpgsql as $$
begin
  execute 'reset role';
  if user_id is null then
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    execute 'set local role anon';
  else
    perform set_config('request.jwt.claim.sub', user_id::text, true);
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', user_id, 'role', 'authenticated')::text,
      true
    );
    execute 'set local role authenticated';
  end if;
end $$;

create function pg_temp.root() returns void language plpgsql as $$
begin
  execute 'reset role';
end $$;

create function pg_temp.refused(statement text) returns boolean language plpgsql as $$
begin
  execute statement;
  return false;
exception when others then
  return true;
end $$;

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create function pg_temp.i(n text) returns uuid language sql as $$ select id from pg_temp.ids where name = n $$;

grant execute on all functions in schema pg_temp to public;

-- ------------------------------------------------------------------ cast
-- Ada owns the circle "Big" and the group "Plan"; Bob, Cy, Dee, Eli and Fay
-- are members of both (Fay only of the circle). Gus is nobody's member.
insert into auth.users (id, email, instance_id, aud, role)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '@l6.test',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from (values ('a1','ada'),('a2','bob'),('a3','cy'),('a4','dee'),('a5','eli'),('a6','fay'),('a7','gus')) v(n, name);
insert into public.profiles (id, username, display_name)
select ('00000000-0000-4000-8000-0000000000' || n)::uuid, name || '_l6', initcap(name)
from (values ('a1','ada'),('a2','bob'),('a3','cy'),('a4','dee'),('a5','eli'),('a6','fay'),('a7','gus')) v(n, name);
insert into pg_temp.ids
select name, ('00000000-0000-4000-8000-0000000000' || n)::uuid
from (values ('a1','ada'),('a2','bob'),('a3','cy'),('a4','dee'),('a5','eli'),('a6','fay'),('a7','gus')) v(n, name);

insert into public.friendships (user_low_id, user_high_id)
select least(pg_temp.i('ada'), pg_temp.i(n)), greatest(pg_temp.i('ada'), pg_temp.i(n))
from (values ('bob'), ('cy'), ('dee'), ('eli'), ('fay'), ('gus')) v(n);

select pg_temp.act(pg_temp.i('ada'));
insert into pg_temp.ids select 'group', public.create_group_conversation('Plan', array[pg_temp.i('bob'), pg_temp.i('cy'), pg_temp.i('dee'), pg_temp.i('eli')]);
insert into pg_temp.ids select 'circle', public.create_circle('Big', array[pg_temp.i('bob'), pg_temp.i('cy'), pg_temp.i('dee'), pg_temp.i('eli'), pg_temp.i('fay')]);
select pg_temp.root();
insert into pg_temp.ids
select 'channel', cc.conversation_id from public.circle_channels cc where cc.circle_id = pg_temp.i('circle') order by cc.created_at limit 1;
insert into public.conversation_members (conversation_id, user_id, role)
select pg_temp.i('channel'), cm.user_id, cm.role
from public.circle_members cm where cm.circle_id = pg_temp.i('circle')
on conflict do nothing;
-- Bob has a nickname in the circle; Cy joined the circle after the others.
update public.circle_members set nickname = 'Zed' where circle_id = pg_temp.i('circle') and user_id = pg_temp.i('bob');
update public.circle_members set role = 'admin' where circle_id = pg_temp.i('circle') and user_id = pg_temp.i('eli');

-- ===================================== 1. a circle's members, a page at a time
do $$
declare
  c uuid := pg_temp.i('circle');
  everyone jsonb;
  seen jsonb := '[]';
  page jsonb;
  last_row jsonb;
  n integer := 0;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  everyone := public.get_circle_detail(c)->'members';
  perform pg_temp.expect(jsonb_array_length(everyone) = 6, 'circle: the detail lists the six members');
  perform pg_temp.expect(public.get_circle_detail(c)->'circle' ? 'member_count' and (public.get_circle_detail(c)->'circle'->>'member_count')::int = 6,
    'circle: the detail says how many there are');

  loop
    select coalesce(jsonb_agg(r order by (r->>'sort_rank')::int, r->>'sort_name', r->'profile'->>'id'), '[]') into page
    from public.list_circle_members_page(
      c, 2,
      (last_row->>'sort_rank')::integer, last_row->>'sort_name', (last_row->'profile'->>'id')::uuid, null) r;
    exit when jsonb_array_length(page) = 0 or n > 10;
    seen := seen || page;
    last_row := page->(jsonb_array_length(page) - 1);
    n := n + 1;
  end loop;
  perform pg_temp.expect(n = 3, 'circle: six members in pages of two are three pages (got ' || n || ')');
  perform pg_temp.expect(
    (select jsonb_agg(m->'profile'->'id') from jsonb_array_elements(seen) m)
      = (select jsonb_agg(m->'profile'->'id') from jsonb_array_elements(everyone) m),
    'circle: the pages together are the detail''s list, in its order');
  perform pg_temp.expect(
    (select jsonb_agg(m - 'sort_rank' - 'sort_name' order by m->'profile'->>'id') from jsonb_array_elements(seen) m)
      = (select jsonb_agg(m order by m->'profile'->>'id') from jsonb_array_elements(everyone) m),
    'circle: a member in a page is written exactly as in the detail');
  perform pg_temp.expect(
    (seen->0->'profile'->>'id')::uuid = pg_temp.i('ada') and seen->0->>'role' = 'owner',
    'circle: the owner comes first');
  perform pg_temp.expect(seen->1->>'role' = 'admin', 'circle: then the admins');

  perform pg_temp.expect(
    (select count(*) from public.list_circle_members_page(c, 50, null, null, null, 'ZED')) = 1,
    'circle: a search finds a nickname, in any case');
  perform pg_temp.expect(
    (select r->'profile'->>'username' from public.list_circle_members_page(c, 50, null, null, null, 'zed') r) = 'bob_l6',
    'circle: and it is Bob');
  perform pg_temp.expect(
    (select count(*) from public.list_circle_members_page(c, 50, null, null, null, 'cy_l6')) = 1,
    'circle: a search finds a username');
  perform pg_temp.expect(
    (select count(*) from public.list_circle_members_page(c, 50, null, null, null, 'nobody like this')) = 0,
    'circle: a search with no match is empty');
  perform pg_temp.expect(
    (select count(*) from public.list_circle_members_page(c, 1000)) = 6
      and (select count(*) from public.list_circle_members_page(c, 0)) = 1,
    'circle: the page size is kept between 1 and 200');

  -- member_limit keeps the first of them and the caller.
  perform pg_temp.act(pg_temp.i('fay'));
  everyone := public.get_circle_detail(c, 2)->'members';
  perform pg_temp.expect(jsonb_array_length(everyone) = 3, 'circle: a limit of 2 gives 2 and the caller (got ' || jsonb_array_length(everyone) || ')');
  perform pg_temp.expect(exists (select 1 from jsonb_array_elements(everyone) m where (m->>'is_current_user')::boolean),
    'circle: the caller is in a limited list');
  perform pg_temp.expect((public.get_circle_detail(c, 2)->'circle'->>'member_count')::int = 6, 'circle: and the count is still all of them');
  perform pg_temp.expect(jsonb_array_length(public.get_circle_detail(c, 100)->'members') = 6, 'circle: a limit above the size gives everyone');
  perform pg_temp.expect(jsonb_array_length(public.get_circle_detail(c)->'members') = 6, 'circle: no limit is everyone');

  -- Strangers get nothing; the circle's members list is for members.
  perform pg_temp.act(pg_temp.i('gus'));
  perform pg_temp.expect((select count(*) from public.list_circle_members_page(c, 50)) = 0, 'circle: a stranger gets no page');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused(format('select * from public.list_circle_members_page(%L, 10)', c)), 'circle: nobody signed in is refused');

  -- A suspended circle shows nobody (as the detail).
  perform pg_temp.root();
  update public.circles set disabled_mode = 'suspend', disabled_at = now() where id = c;
  perform pg_temp.act(pg_temp.i('ada'));
  perform pg_temp.expect((select count(*) from public.list_circle_members_page(c, 50)) = 0, 'circle: a suspended circle gives no page');
  perform pg_temp.root();
  update public.circles set disabled_mode = null, disabled_at = null where id = c;
end $$;

-- ===================================== 2. a conversation's members
do $$
declare
  g uuid := pg_temp.i('group');
  ch uuid := pg_temp.i('channel');
  u text;
  conv uuid;
  seen uuid[];
  expected uuid[];
  last_joined timestamptz;
  last_user uuid;
  page jsonb;
  n integer;
begin
  -- Cy may not see the channel (an overwrite on @everyone and Cy).
  perform pg_temp.root();
  insert into public.circle_channel_overwrites (channel_id, circle_id, user_id, allow, deny)
  select cc.id, cc.circle_id, pg_temp.i('cy'), 0, public.circle_permission_bits(array['view_channel'])
  from public.circle_channels cc where cc.conversation_id = ch;

  foreach u in array array['ada', 'bob', 'cy', 'gus'] loop
    foreach conv in array array[g, ch] loop
      perform pg_temp.act(pg_temp.i(u));
      -- What the policy lets this person read of the members.
      expected := (select coalesce(array_agg(user_id order by user_id), '{}') from public.conversation_members where conversation_id = conv);
      seen := '{}'; last_joined := null; last_user := null; n := 0;
      loop
        select coalesce(jsonb_agg(r), '[]') into page
        from public.list_conversation_members_page(conv, 2, last_joined, last_user, null) r;
        exit when jsonb_array_length(page) = 0 or n > 20;
        seen := seen || (select array_agg((r->'profile'->>'id')::uuid) from jsonb_array_elements(page) r);
        select cm.joined_at, cm.user_id into last_joined, last_user
        from public.conversation_members cm
        where cm.conversation_id = conv
          and cm.user_id = (page->(jsonb_array_length(page) - 1)->'profile'->>'id')::uuid;
        n := n + 1;
      end loop;
      perform pg_temp.expect(
        (select coalesce(array_agg(x order by x), '{}') from unnest(seen) x) = expected,
        'members: pages as ' || u || ' in ' || (case when conv = g then 'the group' else 'the channel' end) || ' are what the policy shows ('
          || coalesce(cardinality(seen), 0) || ' of ' || cardinality(expected) || ')');
    end loop;
  end loop;

  -- The ones the policy shows a member of the group: all five, and for Gus nobody.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect((select count(*) from public.list_conversation_members_page(g, 50)) = 5, 'members: a member sees the five');
  perform pg_temp.expect((select r->>'role' from public.list_conversation_members_page(g, 1) r) = 'owner', 'members: oldest first, and the owner joined first');
  perform pg_temp.expect(
    (select count(*) from public.list_conversation_members_page(g, 50, null, null, 'DEE')) = 1,
    'members: a search finds a name');
  perform pg_temp.act(pg_temp.i('gus'));
  perform pg_temp.expect((select count(*) from public.list_conversation_members_page(g, 50)) = 0, 'members: a stranger gets nobody');
  -- Cy cannot see the channel: nobody but his own row.
  perform pg_temp.act(pg_temp.i('cy'));
  perform pg_temp.expect((select count(*) from public.list_conversation_members_page(ch, 50)) <= 1, 'members: someone who cannot see the channel gets at most their own row');
  -- And the others do not see Cy there.
  perform pg_temp.act(pg_temp.i('bob'));
  perform pg_temp.expect(not exists (
    select 1 from public.list_conversation_members_page(ch, 50) r where (r->'profile'->>'id')::uuid = pg_temp.i('cy')),
    'members: others do not see someone who cannot see the channel');
  perform pg_temp.act(null);
  perform pg_temp.expect(pg_temp.refused(format('select * from public.list_conversation_members_page(%L, 10)', g)), 'members: nobody signed in is refused');
  perform pg_temp.root();
end $$;

-- ===================================== 3. the push claim in batches
-- Everyone has a device (Bob two). Cy muted the group, Dee set Do Not Disturb,
-- Eli blocked Ada: they hear nothing. So Bob (2 devices) is the only one.
-- Then they are let back one at a time.
insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language)
select pg_temp.i(n), 'https://push.example/l6/' || n || '/' || k, repeat('p', 50), repeat('a', 20), 'en'
from (values ('ada'), ('bob'), ('cy'), ('dee'), ('eli')) v(n), generate_series(1, 2) k
where k = 1 or n = 'bob';

create function pg_temp.say(conv uuid, body text) returns uuid language plpgsql as $$
declare mid uuid;
begin
  perform pg_temp.act(pg_temp.i('ada'));
  mid := public.send_text_message(conv, body);
  perform pg_temp.root();
  return mid;
end $$;
grant execute on function pg_temp.say(uuid, text) to public;

-- The people (and devices) a claim hands out, all in one go.
create function pg_temp.claimed(msg uuid, sender text) returns text language sql as $$
  select coalesce(string_agg(recipient || ':' || devices, ',' order by recipient), '')
  from (
    select p.username as recipient, count(*) as devices
    from public.claim_push_delivery(msg, pg_temp.i(sender)) c
    join public.push_subscriptions s on s.id = c.subscription_id
    join public.profiles p on p.id = s.user_id
    group by p.username
  ) t
$$;
grant execute on function pg_temp.claimed(uuid, text) to public;

-- The same, in batches of [size] people.
create function pg_temp.claimed_in_batches(msg uuid, sender text, size integer) returns text language plpgsql as $$
declare
  cursor_user uuid;
  batch_people integer;
  batches integer := 0;
  result text := '';
  sizes text := '';
begin
  loop
    select count(distinct c.recipient_id), (array_agg(c.recipient_id order by c.recipient_id desc))[1]
    into batch_people, cursor_user
    from public.claim_push_delivery(msg, pg_temp.i(sender), cursor_user, size) c;
    exit when batch_people = 0 or batches > 20;
    batches := batches + 1;
    sizes := sizes || batch_people || ' ';
    exit when batch_people < size;
  end loop;
  return sizes;
end $$;
grant execute on function pg_temp.claimed_in_batches(uuid, text, integer) to public;

-- The rows of each batch put together (the first call claims the message).
create function pg_temp.batches(msg uuid, sender text, size integer) returns text language plpgsql as $$
declare
  cursor_user uuid;
  batch_people integer;
  n integer := 0;
  collected text[] := '{}';
  piece text;
begin
  loop
    create temp table if not exists pg_temp.batch_rows (recipient_id uuid, subscription_id uuid) on commit drop;
    truncate pg_temp.batch_rows;
    insert into pg_temp.batch_rows
    select c.recipient_id, c.subscription_id from public.claim_push_delivery(msg, pg_temp.i(sender), cursor_user, size) c;
    select count(distinct recipient_id), (array_agg(recipient_id order by recipient_id desc))[1] into batch_people, cursor_user from pg_temp.batch_rows;
    select string_agg(p.username || ':' || b.n, ',' order by p.username) into piece
    from (select recipient_id, count(*) as n from pg_temp.batch_rows group by recipient_id) b
    join public.profiles p on p.id = b.recipient_id;
    collected := collected || coalesce(piece, '');
    n := n + 1;
    exit when batch_people < size or n > 20;
  end loop;
  return array_to_string(array_remove(collected, ''), ',');
end $$;
grant execute on function pg_temp.batches(uuid, text, integer) to public;

do $$
declare
  g uuid := pg_temp.i('group');
  m1 uuid; m2 uuid; m3 uuid; m4 uuid;
  whole text;
begin
  perform pg_temp.root();
  -- Cy muted the group, Dee is on Do Not Disturb, Eli blocked Ada.
  update public.conversation_members set muted_until = now() + interval '1 day' where conversation_id = g and user_id = pg_temp.i('cy');
  insert into public.user_privacy_settings (user_id, presence_status) values (pg_temp.i('dee'), 'dnd')
  on conflict (user_id) do update set presence_status = 'dnd';
  insert into public.blocks (blocker_id, blocked_id) values (pg_temp.i('eli'), pg_temp.i('ada'));

  m1 := pg_temp.say(g, 'one');
  whole := pg_temp.claimed(m1, 'ada');
  perform pg_temp.expect(whole = 'bob_l6:2', 'claim: muted, Do Not Disturb and blocked people hear nothing, the sender neither (got ' || whole || ')');
  perform pg_temp.expect(pg_temp.claimed(m1, 'ada') = '', 'claim: a message is claimed once');

  -- A claim for someone who did not send it gives nothing, in any batch.
  m2 := pg_temp.say(g, 'two');
  perform pg_temp.expect(pg_temp.claimed(m2, 'bob') = '', 'claim: not for someone else''s message');
  perform pg_temp.expect(pg_temp.claimed(m2, 'ada') = 'bob_l6:2', 'claim: and it can still be claimed by the sender after');

  -- Let Cy and Dee back, unblock Eli: four people hear, Bob with two devices.
  update public.conversation_members set muted_until = null where conversation_id = g and user_id = pg_temp.i('cy');
  update public.user_privacy_settings set presence_status = 'online' where user_id = pg_temp.i('dee');
  delete from public.blocks where blocker_id = pg_temp.i('eli');

  m1 := pg_temp.say(g, 'three');
  whole := pg_temp.claimed(m1, 'ada');
  perform pg_temp.expect(whole = 'bob_l6:2,cy_l6:1,dee_l6:1,eli_l6:1', 'claim: everyone else hears, once per device (got ' || whole || ')');

  m3 := pg_temp.say(g, 'four');
  perform pg_temp.expect(pg_temp.batches(m3, 'ada', 1) = whole, 'claim: batches of one person put together are the whole claim (got ' || pg_temp.batches(m3, 'ada', 1) || ')');
  m4 := pg_temp.say(g, 'five');
  perform pg_temp.expect(pg_temp.batches(m4, 'ada', 3) = whole, 'claim: and batches of three');
  perform pg_temp.expect(pg_temp.batches(pg_temp.say(g, 'six'), 'ada', 4) = whole, 'claim: and a batch of exactly the number of people');
  perform pg_temp.expect(pg_temp.batches(pg_temp.say(g, 'seven'), 'ada', 100) = whole, 'claim: and one batch for all');

  m1 := pg_temp.say(g, 'eight');
  perform pg_temp.expect(pg_temp.claimed_in_batches(m1, 'ada', 3) = '3 1 ', 'claim: four people in batches of three are 3 then 1');

  -- A later batch of a message nobody claimed gives nothing; the first batch claims it.
  m2 := pg_temp.say(g, 'nine');
  perform pg_temp.expect(
    (select count(*) from public.claim_push_delivery(m2, pg_temp.i('ada'), pg_temp.i('bob'), 10)) = 0,
    'claim: a batch after the first of an unclaimed message is empty');
  perform pg_temp.expect(pg_temp.claimed(m2, 'ada') = whole, 'claim: and the message could still be claimed after');

  -- The old two-argument call is still there (the app's Edge Functions of before).
  perform pg_temp.expect(has_function_privilege('service_role', 'public.claim_push_delivery(uuid, uuid, uuid, integer)', 'execute'), 'claim: the service role can call it');
  perform pg_temp.expect(not has_function_privilege('authenticated', 'public.claim_push_delivery(uuid, uuid, uuid, integer)', 'execute'), 'claim: a signed-in person cannot');
  perform pg_temp.expect(not has_function_privilege('anon', 'public.claim_push_delivery(uuid, uuid, uuid, integer)', 'execute'), 'claim: nor anon');
  perform pg_temp.expect(not exists (select 1 from pg_proc where proname = 'claim_push_delivery' and pronargs = 2), 'claim: there is one function, not two');
end $$;

\o

select pg_temp.root();
select count(*) as "checks run" from pg_temp.checked;
select msg as "CHECK FAILED" from pg_temp.failures order by msg;
do $$
begin
  if exists (select 1 from pg_temp.failures) then
    raise exception 'scale pages: % check(s) failed', (select count(*) from pg_temp.failures);
  end if;
end $$;
rollback;
