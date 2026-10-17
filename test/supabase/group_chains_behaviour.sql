-- Behaviour checks for group chains (migration 202610180060). Run by
-- test/supabase/group_chains_behaviour_test.dart against a local database that
-- has the earlier migrations; it applies the ones it lacks (the AI guard's) and
-- the chain migration inside a transaction, acts as several people, and rolls
-- back, so the database is left as it was. Run from the repository root.
\set ON_ERROR_STOP on

begin;

-- One behaviour script at a time: they change the same tables, and test
-- files run in parallel.
do $$ begin perform pg_advisory_xact_lock(20261017); end $$;

\i supabase/migrations/202610170002_album_counts.sql
\i supabase/migrations/202610170003_album_summaries.sql
\i supabase/migrations/202610170004_album_push.sql
\i supabase/migrations/202610170005_push_language.sql
\i supabase/migrations/202610170020_disappearing_messages.sql
\i supabase/migrations/202610170021_view_once_media.sql
\i supabase/migrations/202610170090_ai_guard.sql
\i supabase/migrations/202610170091_ai_guard_hidden.sql
\i supabase/migrations/202610180060_group_chains.sql

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;
create temp table failures (message text);
grant all on failures to public;

-- Ada owns a circle with a channel; Bob and Cy are members (Cy may not send),
-- Mo moderates the channel (manage_messages), Dan is outside, Eve joined the
-- circle just now like Bob (the guard treats new members) while Ada is the
-- owner.
insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@chain.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@chain.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@chain.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d1', 'dan@chain.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e1', 'mo@chain.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_chain', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_chain', 'Bob'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_chain', 'Cy'),
  ('00000000-0000-4000-8000-0000000000d1', 'dan_chain', 'Dan'),
  ('00000000-0000-4000-8000-0000000000e1', 'mo_chain', 'Mo');

create function pg_temp.as_user(uid text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', uid, true);
$$;

create function pg_temp.fail(msg text) returns void language sql as $$
  insert into failures values (msg);
$$;

do $$
declare
  ada text := '00000000-0000-4000-8000-0000000000a1';
  bob text := '00000000-0000-4000-8000-0000000000b1';
  cy text := '00000000-0000-4000-8000-0000000000c1';
  mo text := '00000000-0000-4000-8000-0000000000e1';
  the_circle uuid;
  the_channel uuid;
  conv uuid;
begin
  perform pg_temp.as_user(ada);
  the_circle := public.create_circle('Chain circle');
  select cc.id, cc.conversation_id into the_channel, conv
  from public.circle_channels cc
  where cc.circle_id = the_circle and cc.kind = 'text'
  order by cc.created_at limit 1;
  insert into public.circle_members (circle_id, user_id, role)
  select the_circle, u::uuid, 'member' from unnest(array[bob, cy, mo]) u;
  insert into public.conversation_members (conversation_id, user_id, role)
  select cc.conversation_id, u::uuid, 'member'
  from public.circle_channels cc, unnest(array[bob, cy, mo]) u
  where cc.circle_id = the_circle;
  insert into public.circle_channel_overwrites (circle_id, channel_id, user_id, deny)
  values (the_circle, the_channel, cy::uuid, public.circle_permission_bits(array['send_messages']));
  insert into public.circle_channel_overwrites (circle_id, channel_id, user_id, allow)
  values (the_circle, the_channel, mo::uuid, public.circle_permission_bits(array['manage_messages']));

  insert into ids values ('circle', the_circle), ('channel', conv);

  -- A group (Ada owns it) and a direct chat of Ada and Bob.
  with g as (
    insert into public.conversations (type, title) values ('group', 'Hike group') returning id
  )
  insert into ids select 'group', id from g;
  insert into public.conversation_members (conversation_id, user_id, role)
  select (select id from ids where name = 'group'), u.id::uuid, u.role
  from (values (ada, 'owner'), (bob, 'member'), (cy, 'member')) as u(id, role);
  with d as (
    insert into public.conversations (type) values ('direct') returning id
  )
  insert into ids select 'direct', id from d;
  insert into public.conversation_members (conversation_id, user_id, role)
  select (select id from ids where name = 'direct'), u::uuid, 'member'
  from unnest(array[ada, bob]) u;
end $$;

do $$
declare
  ada text := '00000000-0000-4000-8000-0000000000a1';
  bob text := '00000000-0000-4000-8000-0000000000b1';
  cy text := '00000000-0000-4000-8000-0000000000c1';
  dan text := '00000000-0000-4000-8000-0000000000d1';
  mo text := '00000000-0000-4000-8000-0000000000e1';
  grp uuid := (select id from ids where name = 'group');
  direct uuid := (select id from ids where name = 'direct');
  chan uuid := (select id from ids where name = 'channel');
  the_circle uuid := (select id from ids where name = 'circle');
  made jsonb;
  cid uuid;
  card_id uuid;
  got jsonb;
  joined jsonb;
  small_chain uuid;
  late_chain uuid;
  channel_chain uuid;
  bob_entry uuid;
  before_touch timestamptz;
  n integer;
begin
  -- ----------------------------------------------------------- creating --
  perform pg_temp.as_user(ada);
  made := public.create_chain(
    grp, '  Saturday hike sign-up ', 'Meet at the gate at 8.', '1. Ada +1', null, null
  );
  cid := (made->>'chain_id')::uuid;
  card_id := (made->>'message_id')::uuid;
  if not exists (
    select 1 from public.messages m
    where m.id = card_id
      and m.conversation_id = grp
      and m.type = 'text'
      and m.sender_id = ada::uuid
      and m.body = E'\U0001F517 Saturday hike sign-up'
      and m.attachment->>'kind' = 'chain'
      and (m.attachment->>'chain_id')::uuid = cid
  ) then
    perform pg_temp.fail('the card message is wrong');
  end if;
  if (select chains.message_id from public.chains where id = cid) is distinct from card_id then
    perform pg_temp.fail('the chain does not point at its card');
  end if;

  -- Not in direct chats.
  begin
    perform public.create_chain(direct, 'Nope');
    perform pg_temp.fail('a chain in a direct chat');
  exception when invalid_parameter_value then null; end;
  -- A title is needed, a deadline must lie ahead, a cap is 1..500.
  begin
    perform public.create_chain(grp, '   ');
    perform pg_temp.fail('a blank title');
  exception when invalid_parameter_value then null; end;
  begin
    perform public.create_chain(grp, 'Late', null, null, now() - interval '1 hour');
    perform pg_temp.fail('a deadline in the past');
  exception when invalid_parameter_value then null; end;
  begin
    perform public.create_chain(grp, 'Big', null, null, null, 501);
    perform pg_temp.fail('a cap of 501');
  exception when invalid_parameter_value then null; end;

  -- Outsiders cannot create, read or join; Cy (no send permission in the
  -- channel) cannot create there.
  perform pg_temp.as_user(dan);
  begin
    perform public.create_chain(grp, 'Intruder');
    perform pg_temp.fail('Dan created a chain');
  exception when others then null; end;
  begin
    perform public.get_chain(cid);
    perform pg_temp.fail('Dan read a chain');
  exception when others then null; end;
  begin
    perform public.join_chain(cid, 'me');
    perform pg_temp.fail('Dan joined a chain');
  exception when others then null; end;
  perform pg_temp.as_user(cy);
  begin
    perform public.create_chain(chan, 'Muted');
    perform pg_temp.fail('Cy created a chain where she cannot send');
  exception when insufficient_privilege then null; end;

  -- ------------------------------------------------------------- joining --
  perform pg_temp.as_user(bob);
  before_touch := (select updated_at from public.chains where id = cid);
  perform pg_sleep(0.01);
  joined := public.join_chain(cid, '  bring snacks ');
  bob_entry := (joined->>'entry_id')::uuid;
  if (joined->>'note_held')::boolean then
    perform pg_temp.fail('a note was held in a group');
  end if;
  begin
    perform public.join_chain(cid, 'again');
    perform pg_temp.fail('Bob joined twice');
  exception when unique_violation then null; end;
  if (select updated_at from public.chains where id = cid) <= before_touch then
    perform pg_temp.fail('a join did not touch the chain (Realtime would stay silent)');
  end if;

  perform pg_temp.as_user(ada);
  perform public.join_chain(cid, '');
  perform pg_temp.as_user(cy);
  perform public.join_chain(cid, 'vegetarian');

  got := public.get_chain(cid);
  if got->>'title' <> 'Saturday hike sign-up'
    or got->>'description' <> 'Meet at the gate at 8.'
    or got->>'example' <> '1. Ada +1'
    or (got->>'entry_count')::int <> 3
    or jsonb_array_length(got->'entries') <> 3
    or got->'entries'->0->>'name' <> 'Bob'
    or got->'entries'->0->>'note' <> 'bring snacks'
    or got->'entries'->1->>'name' <> 'Ada'
    or got->'entries'->2->>'name' <> 'Cy'
    or (got->>'closed')::boolean
    or (got->>'can_manage')::boolean
    or got->>'my_entry_id' is null
    or got->>'creator_name' <> 'Ada'
  then
    perform pg_temp.fail('get_chain as Cy ' || got::text);
  end if;

  -- Editing and removing your own line.
  perform pg_temp.as_user(bob);
  perform public.update_chain_entry(cid, 'bring snacks and water');
  if (select note from public.chain_entries where id = bob_entry) <> 'bring snacks and water' then
    perform pg_temp.fail('Bob could not edit his line');
  end if;
  if (select count(*) from public.chain_entries where chain_entries.chain_id = cid) <> 3 then
    perform pg_temp.fail('an edit changed the count');
  end if;
  perform pg_temp.as_user(mo);
  -- Mo is a member of the circle, not of the group: nothing to see.
  begin
    perform public.update_chain_entry(cid, 'x');
    perform pg_temp.fail('Mo edited in a group he is not in');
  exception when others then null; end;
  perform pg_temp.as_user(cy);
  perform public.leave_chain(cid);
  got := public.get_chain(cid);
  if (got->>'entry_count')::int <> 2 or got->>'my_entry_id' is not null then
    perform pg_temp.fail('Cy leaving ' || got::text);
  end if;
  begin
    perform public.update_chain_entry(cid, 'back');
    perform pg_temp.fail('Cy edited a line she does not have');
  exception when no_data_found then null; end;
  -- Joining again after leaving puts the line at the end.
  perform public.join_chain(cid, 'changed my mind');
  if (public.get_chain(cid)->'entries'->2->>'name') <> 'Cy' then
    perform pg_temp.fail('a rejoined line is not last');
  end if;

  -- Only the creator and moderators remove other lines: Bob cannot remove
  -- Cy's, Ada (creator and owner) can.
  perform pg_temp.as_user(bob);
  begin
    perform public.remove_chain_entry(
      (select id from public.chain_entries where chain_entries.chain_id = cid and user_id = cy::uuid)
    );
    perform pg_temp.fail('Bob removed Cy''s line');
  exception when insufficient_privilege then null; end;
  begin
    perform public.set_chain_closed(cid, true);
    perform pg_temp.fail('Bob closed the chain');
  exception when insufficient_privilege then null; end;
  perform pg_temp.as_user(ada);
  perform public.remove_chain_entry(
    (select id from public.chain_entries where chain_entries.chain_id = cid and user_id = cy::uuid)
  );
  if (public.get_chain(cid)->>'entry_count')::int <> 2 then
    perform pg_temp.fail('Ada removing Cy''s line');
  end if;
  if not (public.get_chain(cid)->>'can_manage')::boolean then
    perform pg_temp.fail('the creator cannot manage');
  end if;

  -- ------------------------------------------------------------- closing --
  perform public.set_chain_closed(cid, true);
  if not (public.get_chain(cid)->>'closed')::boolean then
    perform pg_temp.fail('the chain did not close');
  end if;
  perform pg_temp.as_user(cy);
  begin
    perform public.join_chain(cid, 'late');
    perform pg_temp.fail('joined a closed chain');
  exception when others then
    if sqlerrm <> 'chain_closed' then perform pg_temp.fail('closed error: ' || sqlerrm); end if;
  end;
  perform pg_temp.as_user(bob);
  begin
    perform public.update_chain_entry(cid, 'late edit');
    perform pg_temp.fail('edited a closed chain');
  exception when others then
    if sqlerrm <> 'chain_closed' then perform pg_temp.fail('closed edit error: ' || sqlerrm); end if;
  end;
  begin
    perform public.leave_chain(cid);
    perform pg_temp.fail('left a closed chain');
  exception when others then
    if sqlerrm <> 'chain_closed' then perform pg_temp.fail('closed leave error: ' || sqlerrm); end if;
  end;
  perform pg_temp.as_user(ada);
  -- The owner may still tidy the closed list.
  perform public.remove_chain_entry(bob_entry);
  perform public.set_chain_closed(cid, false);
  perform pg_temp.as_user(bob);
  perform public.join_chain(cid, 'back in');
  if (public.get_chain(cid)->>'entry_count')::int <> 2 then
    perform pg_temp.fail('reopened chain entries');
  end if;

  -- --------------------------------------------------------------- limits --
  perform pg_temp.as_user(ada);
  small_chain := (public.create_chain(grp, 'Two seats', null, null, null, 2)->>'chain_id')::uuid;
  perform public.join_chain(small_chain, '');
  perform pg_temp.as_user(bob);
  perform public.join_chain(small_chain, '');
  perform pg_temp.as_user(cy);
  begin
    perform public.join_chain(small_chain, '');
    perform pg_temp.fail('joined a full chain');
  exception when others then
    if sqlerrm <> 'chain_full' then perform pg_temp.fail('full error: ' || sqlerrm); end if;
  end;
  begin
    perform public.join_chain(cid, repeat('x', 201));
    perform pg_temp.fail('a 201 character note');
  exception when invalid_parameter_value then null; end;
  -- A seat frees up when somebody leaves.
  perform pg_temp.as_user(bob);
  perform public.leave_chain(small_chain);
  perform pg_temp.as_user(cy);
  perform public.join_chain(small_chain, '');

  -- A deadline: open until it passes, then closed for everybody.
  perform pg_temp.as_user(ada);
  late_chain := (public.create_chain(
    grp, 'By tonight', null, null, now() + interval '1 day', null
  )->>'chain_id')::uuid;
  perform pg_temp.as_user(bob);
  perform public.join_chain(late_chain, '');
  update public.chains set deadline = now() - interval '1 second' where id = late_chain;
  perform pg_temp.as_user(cy);
  if not (public.get_chain(late_chain)->>'closed')::boolean then
    perform pg_temp.fail('a chain past its deadline is not closed');
  end if;
  begin
    perform public.join_chain(late_chain, '');
    perform pg_temp.fail('joined after the deadline');
  exception when others then
    if sqlerrm <> 'chain_closed' then perform pg_temp.fail('deadline error: ' || sqlerrm); end if;
  end;
  -- Reopening drops the passed deadline.
  perform pg_temp.as_user(ada);
  perform public.set_chain_closed(late_chain, false);
  if (public.get_chain(late_chain)->>'closed')::boolean
    or (public.get_chain(late_chain)->>'deadline') is not null
  then
    perform pg_temp.fail('reopening kept an expired deadline');
  end if;

  -- ------------------------------------------------------ circle channel --
  perform pg_temp.as_user(bob);
  channel_chain := (public.create_chain(chan, 'Raid night')->>'chain_id')::uuid;
  perform public.join_chain(channel_chain, 'tank');
  perform pg_temp.as_user(cy);
  begin
    perform public.join_chain(channel_chain, '');
    perform pg_temp.fail('Cy joined where she cannot send');
  exception when insufficient_privilege then null; end;
  -- Cy still reads it.
  if (public.get_chain(channel_chain)->>'entry_count')::int <> 1 then
    perform pg_temp.fail('Cy cannot read the channel chain');
  end if;
  perform pg_temp.as_user(mo);
  perform public.join_chain(channel_chain, 'healer');
  if not (public.get_chain(channel_chain)->>'can_manage')::boolean then
    perform pg_temp.fail('a moderator cannot manage');
  end if;
  perform public.remove_chain_entry(
    (select id from public.chain_entries where chain_entries.chain_id = channel_chain and user_id = bob::uuid)
  );
  perform public.set_chain_closed(channel_chain, true);
  perform pg_temp.as_user(ada);
  perform public.set_chain_closed(channel_chain, false);

  -- -------------------------------------------------------------- the AI --
  -- Guard on for the circle: a member who joined just now keeps the line but
  -- not the free text; the owner is never held.
  update public.circles set ai_enabled = true where id = the_circle;
  insert into public.circle_ai_guard (circle_id, enabled, new_rule, joined_days, action)
  values (the_circle, true, 'joined_days', 7, 'hold');
  perform pg_temp.as_user(bob);
  perform public.leave_chain(channel_chain);
  joined := public.join_chain(channel_chain, 'buy my coins');
  if not (joined->>'note_held')::boolean
    or (select note from public.chain_entries where id = (joined->>'entry_id')::uuid) <> ''
  then
    perform pg_temp.fail('a new member''s note got through the guard ' || joined::text);
  end if;
  joined := public.update_chain_entry(channel_chain, 'still selling');
  if not (joined->>'note_held')::boolean
    or (select note from public.chain_entries where chain_entries.chain_id = channel_chain and user_id = bob::uuid) <> ''
  then
    perform pg_temp.fail('an edit got through the guard');
  end if;
  -- Without a note there is nothing to hold.
  joined := public.update_chain_entry(channel_chain, '');
  if (joined->>'note_held')::boolean then
    perform pg_temp.fail('an empty note was held');
  end if;
  perform pg_temp.as_user(ada);
  joined := public.join_chain(channel_chain, 'owner note');
  if (joined->>'note_held')::boolean then
    perform pg_temp.fail('the owner was held');
  end if;
  -- Guard off again: notes are free.
  update public.circle_ai_guard set enabled = false where circle_id = the_circle;
  perform pg_temp.as_user(bob);
  joined := public.update_chain_entry(channel_chain, 'tank again');
  if (joined->>'note_held')::boolean then
    perform pg_temp.fail('a note was held with the guard off');
  end if;
  -- Groups never hold.
  update public.circle_ai_guard set enabled = true where circle_id = the_circle;
  perform public.update_chain_entry(cid, 'in a group');
  if (select note from public.chain_entries where chain_entries.chain_id = cid and user_id = bob::uuid) <> 'in a group' then
    perform pg_temp.fail('a group note was held');
  end if;

  -- ------------------------------------------------------ table security --
  -- Clients cannot write the tables, and read only their conversations'.
  reset role;
  perform set_config('request.jwt.claim.sub', cy, true);
  execute 'set local role authenticated';
  begin
    insert into public.chain_entries (chain_id, user_id, note)
    values (cid, cy::uuid, 'sneaky');
    perform pg_temp.fail('a direct insert into chain_entries');
  exception when insufficient_privilege then null; end;
  begin
    update public.chains set title = 'hacked' where id = cid;
    perform pg_temp.fail('a direct update of chains');
  exception when insufficient_privilege then null; end;
  select count(*) into n from public.chains;
  if n < 3 then perform pg_temp.fail('Cy cannot select her chains ' || n); end if;
  reset role;
  perform set_config('request.jwt.claim.sub', dan, true);
  execute 'set local role authenticated';
  select count(*) into n from public.chains;
  if n <> 0 then perform pg_temp.fail('Dan sees ' || n || ' chains'); end if;
  select count(*) into n from public.chain_entries;
  if n <> 0 then perform pg_temp.fail('Dan sees ' || n || ' entries'); end if;
  reset role;
end $$;

do $$
declare
  all_failures text;
begin
  select string_agg(message, E'\n') into all_failures from failures;
  if all_failures is not null then
    raise exception E'Group chain checks failed:\n%', all_failures;
  end if;
end $$;

rollback;
