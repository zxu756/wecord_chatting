-- Behaviour checks for the polls upgrade (migration 202610170023). Run by
-- test/supabase/poll_upgrade_test.dart against the local database: it
-- applies the migrations the local database lacks in a transaction, seeds
-- people and a group, checks the rules and rolls back, so the database is
-- left as it was. Run from the repository root.
\set ON_ERROR_STOP on

begin;

-- These scripts change the same tables; one at a time keeps them from
-- waiting on each other's locks when the tests run in parallel.
select pg_advisory_xact_lock(7770001);

\i supabase/migrations/202610170002_album_counts.sql
\i supabase/migrations/202610170003_album_summaries.sql
\i supabase/migrations/202610170004_album_push.sql
\i supabase/migrations/202610170020_disappearing_messages.sql
\i supabase/migrations/202610170021_view_once_media.sql
\i supabase/migrations/202610170023_poll_upgrade.sql

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@poll.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@poll.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@poll.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_poll', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_poll', 'Bob'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_poll', 'Cy');

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

with grp as (
  insert into public.conversations (type, title) values ('group', 'Poll group') returning id
), members as (
  insert into public.conversation_members (conversation_id, user_id, role)
  select grp.id, member.id, member.role
  from grp, (values
    ('00000000-0000-4000-8000-0000000000a1'::uuid, 'owner'),
    ('00000000-0000-4000-8000-0000000000b1'::uuid, 'member'),
    ('00000000-0000-4000-8000-0000000000c1'::uuid, 'member')
  ) as member(id, role)
)
insert into ids select 'group', id from grp;

create function pg_temp.as_user(user_id uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_id, 'role', 'authenticated')::text,
    true
  );
end $$;

create function pg_temp.as_count(user_id uuid, q text) returns integer language plpgsql as $$
declare n integer;
begin
  perform pg_temp.as_user(user_id);
  execute 'set local role authenticated';
  execute q into n;
  execute 'reset role';
  return n;
exception when others then
  execute 'reset role';
  raise;
end $$;

do $$
declare
  grp uuid := (select id from ids where name = 'group');
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  cy uuid := '00000000-0000-4000-8000-0000000000c1';
  quiz uuid;
  plain uuid;
  secret uuid;
  open_poll uuid;
  results jsonb;
  failed boolean;
  seen integer;
  new_option text;
  failures text := '';
begin
  perform pg_temp.as_user(ada);

  -- The old five-argument call still works.
  plain := public.create_poll(grp, 'Lunch?', array['Pizza', 'Sushi'], false, 24);
  if plain is null then failures := failures || E'\nthe plain poll was not created'; end if;

  -- Quiz: needs a right answer, takes one answer, cannot be multi.
  failed := false;
  begin
    perform public.create_poll(grp, 'Capital?', array['Paris', 'Rome'], false, null, 3);
  exception when invalid_parameter_value then failed := true; end;
  if not failed then failures := failures || E'\na quiz with a missing right answer was accepted'; end if;
  failed := false;
  begin
    perform public.create_poll(grp, 'Capital?', array['Paris', 'Rome'], true, null, 1);
  exception when invalid_parameter_value then failed := true; end;
  if not failed then failures := failures || E'\na multiple choice quiz was accepted'; end if;

  quiz := public.create_poll(
    grp, 'Capital of France?', array['Rome', 'Paris', 'Oslo'], false, null,
    2, 'Paris has been the capital since 987.'
  );

  -- Nobody can read the answer from the tables.
  failed := false;
  begin
    perform pg_temp.as_count(bob, 'select count(*) from public.poll_quiz_answers');
  exception when insufficient_privilege then failed := true; end;
  if not failed then failures := failures || E'\na member read the quiz answers'; end if;

  -- Before voting, Bob sees no answer; the author does.
  perform pg_temp.as_user(bob);
  results := public.poll_results((select m from public.messages m where m.id = quiz));
  if results ? 'correct' or results ? 'explanation' then
    failures := failures || E'\nthe answer showed before voting';
  end if;
  perform pg_temp.as_user(ada);
  results := public.poll_results((select m from public.messages m where m.id = quiz));
  if results->>'correct' <> 'o2' then
    failures := failures || E'\nthe author does not see the answer';
  end if;

  -- Bob votes wrong; the answer shows; the vote is final.
  perform pg_temp.as_user(bob);
  perform public.vote_poll(quiz, array['o1']);
  results := public.poll_results((select m from public.messages m where m.id = quiz));
  if results->>'correct' <> 'o2' or results->>'explanation' <> 'Paris has been the capital since 987.' then
    failures := failures || format(E'\nafter voting: %s', results);
  end if;
  failed := false;
  begin
    perform public.vote_poll(quiz, array['o2']);
  exception when invalid_parameter_value then failed := true; end;
  if not failed then failures := failures || E'\na quiz answer was changed'; end if;
  failed := false;
  begin
    perform public.vote_poll(quiz, array[]::text[]);
  exception when invalid_parameter_value then failed := true; end;
  if not failed then failures := failures || E'\na quiz answer was withdrawn'; end if;

  -- Cy has not voted and sees nothing until the poll closes.
  perform pg_temp.as_user(cy);
  results := public.poll_results((select m from public.messages m where m.id = quiz));
  if results ? 'correct' then failures := failures || E'\nCy saw the answer'; end if;
  perform pg_temp.as_user(ada);
  perform public.end_poll(quiz);
  perform pg_temp.as_user(cy);
  results := public.poll_results((select m from public.messages m where m.id = quiz));
  if results->>'correct' <> 'o2' then failures := failures || E'\nclosed quiz does not show the answer'; end if;

  -- Anonymous: counts, but no voters and no vote rows of others.
  perform pg_temp.as_user(ada);
  secret := public.create_poll(grp, 'Who is late?', array['Me', 'You'], false, null, null, null, true);
  perform pg_temp.as_user(bob);
  perform public.vote_poll(secret, array['o1']);
  perform pg_temp.as_user(cy);
  perform public.vote_poll(secret, array['o1']);
  results := public.poll_results((select m from public.messages m where m.id = secret));
  if (results->'counts'->>'o1')::int <> 2 then failures := failures || E'\nanonymous counts are wrong'; end if;
  if exists (select 1 from public.list_poll_voters(secret, 'o1')) then
    failures := failures || E'\nan anonymous poll listed its voters';
  end if;
  seen := pg_temp.as_count(cy, format('select count(*) from public.message_poll_votes where message_id = %L', secret));
  if seen <> 1 then failures := failures || format(E'\nCy sees %s vote rows of an anonymous poll, expected 1', seen); end if;
  seen := pg_temp.as_count(ada, format('select count(*) from public.message_poll_votes where message_id = %L', secret));
  if seen <> 0 then failures := failures || format(E'\nthe author sees %s vote rows of an anonymous poll', seen); end if;
  -- Visible polls still list voters.
  perform pg_temp.as_user(bob);
  perform public.vote_poll(plain, array['o1']);
  if not exists (select 1 from public.list_poll_voters(plain, 'o1')) then
    failures := failures || E'\na visible poll lost its voter list';
  end if;

  -- Members add options, when allowed, up to ten.
  perform pg_temp.as_user(ada);
  open_poll := public.create_poll(grp, 'Where to?', array['Park', 'Beach'], false, null, null, null, false, true);
  perform pg_temp.as_user(cy);
  new_option := public.add_poll_option(open_poll, 'Museum');
  if new_option <> 'o3' then failures := failures || format(E'\nnew option id %s', new_option); end if;
  if jsonb_array_length((select attachment->'options' from public.messages where id = open_poll)) <> 3 then
    failures := failures || E'\nthe option was not added';
  end if;
  failed := false;
  begin perform public.add_poll_option(open_poll, 'museum');
  exception when invalid_parameter_value then failed := true; end;
  if not failed then failures := failures || E'\na duplicate option was added'; end if;
  perform public.vote_poll(open_poll, array['o3']);

  failed := false;
  begin perform public.add_poll_option(plain, 'Burgers');
  exception when invalid_parameter_value then failed := true; end;
  if not failed then failures := failures || E'\nan option was added to a poll that does not allow it'; end if;

  for i in 4..10 loop
    perform public.add_poll_option(open_poll, 'Place ' || i);
  end loop;
  failed := false;
  begin perform public.add_poll_option(open_poll, 'One too many');
  exception when invalid_parameter_value then failed := true; end;
  if not failed then failures := failures || E'\nan eleventh option was added'; end if;

  -- A quiz takes no added options.
  perform pg_temp.as_user(ada);
  failed := false;
  begin perform public.create_poll(grp, 'q', array['a', 'b'], false, null, 1, null, false, true);
  exception when invalid_parameter_value then failed := true; end;
  if not failed then failures := failures || E'\na quiz that takes new options was created'; end if;

  -- A closing time: up to 30 days ahead.
  failed := false;
  begin perform public.create_poll(grp, 'Late', array['a', 'b'], false, null, null, null, false, false, now() + interval '31 days');
  exception when invalid_parameter_value then failed := true; end;
  if not failed then failures := failures || E'\na deadline 31 days out was accepted'; end if;
  failed := false;
  begin perform public.create_poll(grp, 'Past', array['a', 'b'], false, null, null, null, false, false, now() - interval '1 hour');
  exception when invalid_parameter_value then failed := true; end;
  if not failed then failures := failures || E'\na deadline in the past was accepted'; end if;
  open_poll := public.create_poll(grp, 'Soon', array['a', 'b'], false, 48, null, null, false, false, now() + interval '2 hours');
  if (select (attachment->>'ends_at')::timestamptz from public.messages where id = open_poll)
     > now() + interval '3 hours' then
    failures := failures || E'\nclosing time did not win over the duration';
  end if;

  if failures <> '' then
    raise exception 'poll checks failed:%', failures;
  end if;
end $$;

rollback;
