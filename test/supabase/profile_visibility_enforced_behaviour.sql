-- Behaviour checks for the profile visibility rule on every read path
-- (migration 202610170101). Run by
-- test/supabase/profile_visibility_enforced_test.dart against the local
-- database: it applies the migrations the local database lacks in a
-- transaction, acts as several people, checks what each path shows of Ada's
-- bio under each setting and rolls back. Run from the repository root.
\set ON_ERROR_STOP on

begin;

-- One behaviour script at a time: they change the same tables, and test
-- files run in parallel.
do $$ begin perform pg_advisory_xact_lock(20261017); end $$;
-- The scripts that apply the same earlier migrations take these.

-- The latest definitions of the functions the migration patches.
\i supabase/migrations/202610140004_bans_and_timeouts.sql
\i supabase/migrations/202610170002_album_counts.sql
\i supabase/migrations/202610170003_album_summaries.sql
\i supabase/migrations/202610170004_album_push.sql
\i supabase/migrations/202610170005_push_language.sql
\i supabase/migrations/202610170020_disappearing_messages.sql
\i supabase/migrations/202610170021_view_once_media.sql
\i supabase/migrations/202610170023_poll_upgrade.sql
\i supabase/migrations/202610170024_profile_visibility.sql
\i supabase/migrations/202610170090_ai_guard.sql
\i supabase/migrations/202610170091_ai_guard_hidden.sql
\i supabase/migrations/202610170101_profile_visibility_enforced.sql

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a7', 'ada@enf.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b7', 'bob@enf.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c7', 'cy@enf.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d7', 'dee@enf.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e7', 'eve@enf.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name, bio, pronouns, banner_url)
values
  ('00000000-0000-4000-8000-0000000000a7', 'ada_enf', 'Ada', 'Ada secret bio', 'she/her', 'profile-banners/00000000-0000-4000-8000-0000000000a7/b.png'),
  ('00000000-0000-4000-8000-0000000000b7', 'bob_enf', 'Bob', 'Bob bio', null, null),
  ('00000000-0000-4000-8000-0000000000c7', 'cy_enf', 'Cy', 'Cy bio', null, null),
  ('00000000-0000-4000-8000-0000000000d7', 'dee_enf', 'Dee', 'Dee bio', null, null),
  ('00000000-0000-4000-8000-0000000000e7', 'eve_enf', 'Eve', 'Eve bio', null, null);

-- Bob is Ada's friend, Cy shares a circle with her, Dee is a stranger and Eve
-- is someone Ada blocked. All of them are in Ada's group chat.
insert into public.friendships (user_low_id, user_high_id)
values ('00000000-0000-4000-8000-0000000000a7', '00000000-0000-4000-8000-0000000000b7');
insert into public.blocks (blocker_id, blocked_id)
values ('00000000-0000-4000-8000-0000000000a7', '00000000-0000-4000-8000-0000000000e7');

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

create function pg_temp.as_user(user_id uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_id, 'role', 'authenticated')::text,
    true
  );
end $$;

with grp as (
  insert into public.conversations (type, title) values ('group', 'Visibility group') returning id
), members as (
  insert into public.conversation_members (conversation_id, user_id, role)
  select grp.id, member.id, member.role
  from grp, (values
    ('00000000-0000-4000-8000-0000000000a7'::uuid, 'owner'),
    ('00000000-0000-4000-8000-0000000000b7'::uuid, 'member'),
    ('00000000-0000-4000-8000-0000000000c7'::uuid, 'member'),
    ('00000000-0000-4000-8000-0000000000d7'::uuid, 'member'),
    ('00000000-0000-4000-8000-0000000000e7'::uuid, 'member')
  ) as member(id, role)
)
insert into ids select 'group', id from grp;

-- Ada's circle with Bob and Cy.
select pg_temp.as_user('00000000-0000-4000-8000-0000000000a7');
insert into ids select 'circle', public.create_circle('Visibility circle', array[]::uuid[]);
insert into public.circle_members (circle_id, user_id, role)
select (select id from ids where name = 'circle'), u.id, 'member'
from (values
  ('00000000-0000-4000-8000-0000000000b7'::uuid),
  ('00000000-0000-4000-8000-0000000000c7'::uuid)
) u(id);

-- A message with a reaction, a pin and (in a poll) a vote from Ada.
with m as (
  insert into public.messages (conversation_id, sender_id, type, body)
  values (
    (select id from ids where name = 'group'),
    '00000000-0000-4000-8000-0000000000a7', 'text', 'hello'
  ) returning id
)
insert into ids select 'message', id from m;
insert into public.message_reactions (message_id, user_id, emoji, conversation_id)
select (select id from ids where name = 'message'),
  '00000000-0000-4000-8000-0000000000a7', '👍',
  (select id from ids where name = 'group');
insert into public.pinned_messages (conversation_id, message_id, pinned_by)
select (select id from ids where name = 'group'), (select id from ids where name = 'message'),
  '00000000-0000-4000-8000-0000000000a7';
insert into ids
select 'poll', public.create_poll(
  (select id from ids where name = 'group'), 'Where?', array['Park', 'Beach'], false, null
);
select pg_temp.as_user('00000000-0000-4000-8000-0000000000b7');
select public.vote_poll((select id from ids where name = 'poll'), array['o1']);
select pg_temp.as_user('00000000-0000-4000-8000-0000000000a7');
select public.vote_poll((select id from ids where name = 'poll'), array['o1']);

insert into storage.objects (bucket_id, name)
values ('profile-banners', '00000000-0000-4000-8000-0000000000a7/b.png');

-- What Ada's bio looks like to [viewer] on each path: true when the real text
-- comes back, false when it is empty or the path refuses.
create function pg_temp.bio_paths(viewer uuid)
returns table (path text, shown boolean)
language plpgsql as $$
declare
  grp uuid := (select id from ids where name = 'group');
  circle uuid := (select id from ids where name = 'circle');
  msg uuid := (select id from ids where name = 'message');
  poll uuid := (select id from ids where name = 'poll');
  ada uuid := '00000000-0000-4000-8000-0000000000a7';
  secret constant text := 'Ada secret bio';
  hit boolean;
begin
  perform pg_temp.as_user(viewer);

  path := 'rule';
  shown := public.can_view_profile_details(ada);
  return next;

  path := 'summary';
  select coalesce(bool_or(s.bio = secret), false) into shown
  from public.get_profile_summary(ada) s;
  return next;

  path := 'reactors';
  select coalesce(bool_or(r.bio = secret), false) into shown
  from public.list_message_reactors(msg, '👍') r where r.id = ada;
  return next;

  path := 'voters';
  select coalesce(bool_or(v.bio = secret), false) into shown
  from public.list_poll_voters(poll, 'o1') v where v.id = ada;
  return next;

  path := 'pinned';
  select coalesce(bool_or(p.sender ->> 'bio' = secret), false) into shown
  from public.list_pinned_messages(grp) p;
  return next;

  path := 'forum author';
  select coalesce(
    public.forum_post_payload(
      jsonb_populate_record(null::public.conversation_threads, jsonb_build_object(
        'id', gen_random_uuid(), 'conversation_id', gen_random_uuid(),
        'created_by', ada, 'created_at', now(), 'title', 't'
      )),
      jsonb_populate_record(null::public.circle_channels, jsonb_build_object(
        'id', gen_random_uuid(), 'circle_id', circle
      ))
    ) -> 'author' ->> 'bio' = secret,
    false
  ) into shown;
  return next;

  path := 'event profile';
  shown := coalesce(public.circle_event_profile(circle, ada) ->> 'bio' = secret, false);
  return next;

  -- Circle details only for members.
  if exists (
    select 1 from public.circle_members cm where cm.circle_id = circle and cm.user_id = viewer
  ) then
    path := 'circle detail';
    shown := position(secret in public.get_circle_detail(circle)::text) > 0;
    return next;
  end if;
end $$;

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a7';
  bob uuid := '00000000-0000-4000-8000-0000000000b7';
  cy uuid := '00000000-0000-4000-8000-0000000000c7';
  dee uuid := '00000000-0000-4000-8000-0000000000d7';
  eve uuid := '00000000-0000-4000-8000-0000000000e7';
  setting text;
  viewer record;
  seen record;
  expected boolean;
  paths integer;
  expected_paths integer;
  failures text := '';
begin
  foreach setting in array array['everyone', 'friends_and_circles', 'friends'] loop
    perform pg_temp.as_user(ada);
    perform public.set_profile_visibility(setting);

    for viewer in
      select * from (values
        (ada, 'ada'), (bob, 'bob'), (cy, 'cy'), (dee, 'dee'), (eve, 'eve')
      ) v(id, name)
    loop
      expected := case viewer.name
        when 'ada' then true
        when 'bob' then true
        when 'cy' then setting <> 'friends'
        when 'dee' then setting = 'everyone'
        else false
      end;
      paths := 0;
      for seen in select * from pg_temp.bio_paths(viewer.id) loop
        paths := paths + 1;
        if seen.shown is distinct from expected then
          failures := failures || format(
            E'\n%s sees Ada''s bio on "%s" = %s under %s, expected %s',
            viewer.name, seen.path, seen.shown, setting, expected
          );
        end if;
      end loop;
      -- Circle members get the circle detail path too.
      if viewer.name in ('ada', 'bob', 'cy') then
        expected_paths := 8;
      else
        expected_paths := 7;
      end if;
      if paths <> expected_paths then
        failures := failures || format(E'\n%s: %s paths checked', viewer.name, paths);
      end if;
    end loop;
  end loop;

  if failures <> '' then
    raise exception 'profile visibility checks failed:%', failures;
  end if;
end $$;

-- Direct reads of profiles: names are open, the profile-only fields are not.
create function pg_temp.as_role_count(user_id uuid, q text)
returns integer language plpgsql as $$
declare n integer;
begin
  perform pg_temp.as_user(user_id);
  execute 'set local role authenticated';
  begin
    execute q into n;
  exception when insufficient_privilege then
    n := -1;
  end;
  execute 'reset role';
  return n;
exception when others then
  execute 'reset role';
  raise;
end $$;

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a7';
  dee uuid := '00000000-0000-4000-8000-0000000000d7';
  n integer;
  failures text := '';
begin
  perform pg_temp.as_user(ada);
  perform public.set_profile_visibility('friends');

  for n in select pg_temp.as_role_count(dee, q) from (values
    ('select count(bio) from public.profiles'),
    ('select count(pronouns) from public.profiles'),
    ('select count(banner_url) from public.profiles'),
    ('select count(*) from (select * from public.profiles) p'),
    ('select count(*) from public.profiles where bio <> ''''')
  ) t(q) loop
    if n <> -1 then
      failures := failures || E'\na profile-only column was readable';
    end if;
  end loop;

  -- Everything chat needs still reads.
  n := pg_temp.as_role_count(dee,
    'select count(*) from (select id, username, display_name, avatar_url, created_at, updated_at, status_emoji, status_text, status_expires_at, deleted_at, display_circle_tag_id, is_bot from public.profiles) p');
  if n <> 5 then
    failures := failures || format(E'\nchat columns gave %s rows, expected 5', n);
  end if;
  n := pg_temp.as_role_count(dee,
    'select count(*) from public.profiles where deleted_at is null and is_bot = false and username ilike ''%ada%''');
  if n <> 1 then
    failures := failures || format(E'\nsearch gave %s rows, expected 1', n);
  end if;

  -- A message embeds the sender's names without the bio, as the app asks.
  n := pg_temp.as_role_count(dee,
    'select count(*) from public.messages m join public.profiles p on p.id = m.sender_id');
  if n < 1 then
    failures := failures || format(E'\nmessage sender join gave %s', n);
  end if;

  -- Own profile, all of it, through get_my_profile; nobody else's.
  perform pg_temp.as_user(ada);
  if not exists (
    select 1 from public.get_my_profile() m
    where m.bio = 'Ada secret bio' and m.pronouns = 'she/her' and m.banner_url is not null
  ) then
    failures := failures || E'\nget_my_profile misses Ada''s own fields';
  end if;
  perform pg_temp.as_user(dee);
  if (select count(*) from public.get_my_profile()) <> 1
    or exists (select 1 from public.get_my_profile() m where m.id <> dee or m.bio <> 'Dee bio')
  then
    failures := failures || E'\nget_my_profile returned someone else''s row';
  end if;
  perform pg_temp.as_user(null);
  if exists (select 1 from public.get_my_profile()) then
    failures := failures || E'\nget_my_profile answered without a caller';
  end if;

  -- Anonymous callers can't run the rule at all.
  begin
    set local role anon;
    perform public.can_view_profile_details(ada);
    failures := failures || E'\nanon could run can_view_profile_details';
  exception when insufficient_privilege then
    null;
  end;
  reset role;

  if failures <> '' then
    raise exception 'profile column checks failed:%', failures;
  end if;
end $$;

-- The banner file follows the same rule.
create function pg_temp.banner_count(viewer uuid)
returns integer language plpgsql as $$
declare n integer;
begin
  perform pg_temp.as_user(viewer);
  set local role authenticated;
  select count(*) into n from storage.objects o where o.bucket_id = 'profile-banners';
  reset role;
  return n;
exception when others then
  reset role;
  raise;
end $$;

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a7';
  bob uuid := '00000000-0000-4000-8000-0000000000b7';
  cy uuid := '00000000-0000-4000-8000-0000000000c7';
  dee uuid := '00000000-0000-4000-8000-0000000000d7';
  eve uuid := '00000000-0000-4000-8000-0000000000e7';
  failures text := '';
begin
  -- A file whose folder is not a user id is nobody's to read.
  insert into storage.objects (bucket_id, name) values ('profile-banners', 'stray/b.png');

  perform pg_temp.as_user(ada);
  perform public.set_profile_visibility('friends');
  if pg_temp.banner_count(ada) <> 1 or pg_temp.banner_count(bob) <> 1
     or pg_temp.banner_count(cy) <> 0 or pg_temp.banner_count(dee) <> 0
     or pg_temp.banner_count(eve) <> 0 then
    failures := failures || E'\nbanner under friends';
  end if;

  perform pg_temp.as_user(ada);
  perform public.set_profile_visibility('friends_and_circles');
  if pg_temp.banner_count(cy) <> 1 or pg_temp.banner_count(dee) <> 0 then
    failures := failures || E'\nbanner under friends_and_circles';
  end if;

  perform pg_temp.as_user(ada);
  perform public.set_profile_visibility('everyone');
  if pg_temp.banner_count(dee) <> 1 or pg_temp.banner_count(eve) <> 0 then
    failures := failures || E'\nbanner under everyone';
  end if;

  if failures <> '' then
    raise exception 'banner checks failed:%', failures;
  end if;
end $$;

-- Running the migration again changes nothing (it patches what is there).
\i supabase/migrations/202610170101_profile_visibility_enforced.sql

rollback;
