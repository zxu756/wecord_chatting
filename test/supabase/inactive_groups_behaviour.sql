-- Behaviour checks for the group clean-up list (migration
-- 202610170052_inactive_groups). Run by
-- test/supabase/inactive_groups_behaviour_test.dart against the local
-- database: it applies the migration inside a transaction, seeds groups of
-- different ages and rolls everything back. Run from the repository root.
\set ON_ERROR_STOP on

begin;

-- The behaviour checks all run DDL and write the same tables; take turns so
-- they cannot deadlock when the test runner starts them together.
select pg_advisory_xact_lock(7771001);

\i supabase/migrations/202610170052_inactive_groups.sql

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
  ('00000000-0000-4000-8000-0000000000e1', 'ada@cleanup.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e2', 'bob@cleanup.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000e1', 'ada_cleanup', 'Ada'),
  ('00000000-0000-4000-8000-0000000000e2', 'bob_cleanup', 'Bob');

-- Ada's chats. Ages are of the last message (or of the group when nobody
-- wrote). Bob owns most; Ada owns the last two.
insert into public.conversations (id, type, title, last_message_at, created_at)
values
  ('00000000-0000-4000-8000-00000000f101', 'group', 'Fresh', now() - interval '3 days', now() - interval '400 days'),
  ('00000000-0000-4000-8000-00000000f102', 'group', 'Forty days', now() - interval '40 days', now() - interval '400 days'),
  ('00000000-0000-4000-8000-00000000f103', 'group', 'Hundred days', now() - interval '100 days', now() - interval '400 days'),
  ('00000000-0000-4000-8000-00000000f104', 'group', 'Year old', now() - interval '365 days', now() - interval '400 days'),
  ('00000000-0000-4000-8000-00000000f105', 'group', 'Never used', null, now() - interval '120 days'),
  ('00000000-0000-4000-8000-00000000f106', 'group', 'Just made', null, now() - interval '2 days'),
  ('00000000-0000-4000-8000-00000000f107', 'direct', null, now() - interval '300 days', now() - interval '400 days'),
  ('00000000-0000-4000-8000-00000000f108', 'group', 'Not mine', now() - interval '300 days', now() - interval '400 days'),
  ('00000000-0000-4000-8000-00000000f109', 'group', 'Ada owns, Bob in it', now() - interval '200 days', now() - interval '400 days'),
  ('00000000-0000-4000-8000-00000000f10a', 'group', 'Ada alone', now() - interval '200 days', now() - interval '400 days');

insert into public.conversation_members (conversation_id, user_id, role, pinned_at)
values
  ('00000000-0000-4000-8000-00000000f101', '00000000-0000-4000-8000-0000000000e1', 'member', null),
  ('00000000-0000-4000-8000-00000000f101', '00000000-0000-4000-8000-0000000000e2', 'owner', null),
  ('00000000-0000-4000-8000-00000000f102', '00000000-0000-4000-8000-0000000000e1', 'member', null),
  ('00000000-0000-4000-8000-00000000f102', '00000000-0000-4000-8000-0000000000e2', 'owner', null),
  ('00000000-0000-4000-8000-00000000f103', '00000000-0000-4000-8000-0000000000e1', 'member', now()),
  ('00000000-0000-4000-8000-00000000f103', '00000000-0000-4000-8000-0000000000e2', 'owner', null),
  ('00000000-0000-4000-8000-00000000f104', '00000000-0000-4000-8000-0000000000e1', 'admin', null),
  ('00000000-0000-4000-8000-00000000f104', '00000000-0000-4000-8000-0000000000e2', 'owner', null),
  ('00000000-0000-4000-8000-00000000f105', '00000000-0000-4000-8000-0000000000e1', 'member', null),
  ('00000000-0000-4000-8000-00000000f105', '00000000-0000-4000-8000-0000000000e2', 'owner', null),
  ('00000000-0000-4000-8000-00000000f106', '00000000-0000-4000-8000-0000000000e1', 'member', null),
  ('00000000-0000-4000-8000-00000000f106', '00000000-0000-4000-8000-0000000000e2', 'owner', null),
  ('00000000-0000-4000-8000-00000000f107', '00000000-0000-4000-8000-0000000000e1', 'member', null),
  ('00000000-0000-4000-8000-00000000f107', '00000000-0000-4000-8000-0000000000e2', 'member', null),
  ('00000000-0000-4000-8000-00000000f108', '00000000-0000-4000-8000-0000000000e2', 'owner', null),
  ('00000000-0000-4000-8000-00000000f109', '00000000-0000-4000-8000-0000000000e1', 'owner', null),
  ('00000000-0000-4000-8000-00000000f109', '00000000-0000-4000-8000-0000000000e2', 'member', null),
  ('00000000-0000-4000-8000-00000000f10a', '00000000-0000-4000-8000-0000000000e1', 'owner', null);

select pg_temp.act_as('00000000-0000-4000-8000-0000000000e1');

do $$
declare
  titles text[];
begin
  -- 30 days: everything quiet for a month, oldest first. Not the fresh
  -- ones, the direct chat or the group Ada is not in.
  select array_agg(title order by last_activity_at, title) into titles
  from public.list_inactive_groups(30);
  perform pg_temp.check_that(
    titles = array['Year old', 'Ada alone', 'Ada owns, Bob in it', 'Never used', 'Hundred days', 'Forty days'],
    format('30 days lists the quiet groups, oldest first (got %s)', titles)
  );

  select array_agg(title order by last_activity_at, title) into titles
  from public.list_inactive_groups(90);
  perform pg_temp.check_that(
    titles = array['Year old', 'Ada alone', 'Ada owns, Bob in it', 'Never used', 'Hundred days'],
    format('90 days drops the 40 day old group (got %s)', titles)
  );

  select array_agg(title order by last_activity_at, title) into titles
  from public.list_inactive_groups(180);
  perform pg_temp.check_that(
    titles = array['Year old', 'Ada alone', 'Ada owns, Bob in it'],
    format('180 days keeps only the oldest (got %s)', titles)
  );

  -- A group nobody wrote in is as old as the group.
  perform pg_temp.check_that(
    (select last_activity_at from public.list_inactive_groups(90) where title = 'Never used')
      < now() - interval '119 days',
    'a group without messages counts from its creation'
  );

  -- Roles, pins and whether leaving works.
  perform pg_temp.check_that(
    (select my_role from public.list_inactive_groups(30) where title = 'Year old') = 'admin',
    'my role is reported'
  );
  perform pg_temp.check_that(
    (select is_pinned from public.list_inactive_groups(30) where title = 'Hundred days'),
    'pinned groups are marked'
  );
  perform pg_temp.check_that(
    (select member_count from public.list_inactive_groups(30) where title = 'Ada owns, Bob in it') = 2,
    'member counts'
  );
  perform pg_temp.check_that(
    not (select can_leave from public.list_inactive_groups(30) where title = 'Ada owns, Bob in it'),
    'the only owner of a group with others cannot leave'
  );
  perform pg_temp.check_that(
    (select can_leave from public.list_inactive_groups(30) where title = 'Ada alone'),
    'the last person in a group can leave'
  );
  perform pg_temp.check_that(
    (select can_leave from public.list_inactive_groups(30) where title = 'Forty days'),
    'members can leave'
  );

  -- Out-of-range choices are clamped, not errors.
  perform pg_temp.check_that(
    (select count(*) from public.list_inactive_groups(0)) = (select count(*) from public.list_inactive_groups(1)),
    '0 days behaves as 1'
  );
  perform pg_temp.check_that(
    (select count(*) from public.list_inactive_groups(null)) = (select count(*) from public.list_inactive_groups(90)),
    'no choice means 90 days'
  );
end $$;

-- The list agrees with what leaving can do.
do $$
begin
  perform public.leave_group_conversation('00000000-0000-4000-8000-00000000f102');
  perform public.leave_group_conversation('00000000-0000-4000-8000-00000000f10a');
  perform pg_temp.check_that(
    (select count(*) from public.list_inactive_groups(30) where title in ('Forty days', 'Ada alone')) = 0,
    'left groups drop off the list'
  );
  begin
    perform public.leave_group_conversation('00000000-0000-4000-8000-00000000f109');
    raise exception 'check failed: the sole owner should not be able to leave';
  exception when insufficient_privilege then
    null;
  end;
end $$;

-- Signed-out callers and other people see their own lists only.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000e2');
do $$
begin
  perform pg_temp.check_that(
    (select array_agg(title order by title) from public.list_inactive_groups(30))
      = array['Ada owns, Bob in it', 'Forty days', 'Hundred days', 'Never used', 'Not mine', 'Year old'],
    'each person sees their own groups'
  );
end $$;

rollback;
