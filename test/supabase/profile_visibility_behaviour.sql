-- Behaviour checks for profile visibility (migration 202610170024). Run by
-- test/supabase/profile_visibility_test.dart against the local database
-- inside a transaction that is rolled back. Run from the repository root.
\set ON_ERROR_STOP on

begin;

-- These scripts change the same tables; one at a time keeps them from
-- waiting on each other's locks when the tests run in parallel.
select pg_advisory_xact_lock(7770001);

\i supabase/migrations/202610170024_profile_visibility.sql

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@vis.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@vis.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@vis.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000d1', 'dee@vis.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e1', 'eve@vis.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name, bio, pronouns, banner_url)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_vis', 'Ada', 'Ada''s bio', 'she/her', 'profile-banners/00000000-0000-4000-8000-0000000000a1/b.png'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_vis', 'Bob', '', null, null),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_vis', 'Cy', '', null, null),
  ('00000000-0000-4000-8000-0000000000d1', 'dee_vis', 'Dee', '', null, null),
  ('00000000-0000-4000-8000-0000000000e1', 'eve_vis', 'Eve', '', null, null);

-- Ada is friends with Bob and Eve; Cy shares a circle with Ada; Dee is a
-- stranger. Bob and Eve are also friends (a mutual friend of Ada's and
-- Bob's would be Eve).
insert into public.friendships (user_low_id, user_high_id)
values
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000b1'),
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000e1'),
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000e1');

create function pg_temp.as_user(user_id uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_id, 'role', 'authenticated')::text,
    true
  );
end $$;

do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  cy uuid := '00000000-0000-4000-8000-0000000000c1';
  dee uuid := '00000000-0000-4000-8000-0000000000d1';
  circle uuid;
  summary record;
  failed boolean;
  failures text := '';
begin
  perform pg_temp.as_user(ada);
  circle := public.create_circle('Visible circle', array[]::uuid[]);
  insert into public.circle_members (circle_id, user_id, role)
  values (circle, cy, 'member'), (circle, bob, 'member');

  -- Default: everyone sees everything.
  perform pg_temp.as_user(dee);
  select * into summary from public.get_profile_summary(ada);
  if summary.bio <> 'Ada''s bio' or summary.pronouns is null or summary.banner_url is null
     or summary.profile_hidden then
    failures := failures || E'\neveryone should see the profile by default';
  end if;

  -- Friends and shared circles.
  perform pg_temp.as_user(ada);
  perform public.set_profile_visibility('friends_and_circles');
  perform pg_temp.as_user(dee);
  select * into summary from public.get_profile_summary(ada);
  if summary.bio <> '' or summary.pronouns is not null or summary.banner_url is not null
     or summary.mutual_friends <> '[]'::jsonb or summary.mutual_circles <> '[]'::jsonb
     or not summary.profile_hidden then
    failures := failures || format(E'\nstranger sees %s', summary);
  end if;
  -- Names and the relationship stay.
  if summary.display_name <> 'Ada' or summary.relationship_status <> 'none' then
    failures := failures || E'\nthe basics were hidden';
  end if;
  perform pg_temp.as_user(cy);
  select * into summary from public.get_profile_summary(ada);
  if summary.bio <> 'Ada''s bio' or summary.profile_hidden then
    failures := failures || E'\na person in a shared circle should see it';
  end if;
  if jsonb_array_length(summary.mutual_circles) <> 1 then
    failures := failures || E'\nthe mutual circle is missing';
  end if;
  perform pg_temp.as_user(bob);
  select * into summary from public.get_profile_summary(ada);
  if summary.bio <> 'Ada''s bio' or jsonb_array_length(summary.mutual_friends) <> 1 then
    failures := failures || E'\na friend should see it with mutuals';
  end if;

  -- Friends only: the circle member is out, the friend stays in.
  perform pg_temp.as_user(ada);
  perform public.set_profile_visibility('friends');
  perform pg_temp.as_user(cy);
  select * into summary from public.get_profile_summary(ada);
  if summary.bio <> '' or not summary.profile_hidden or summary.mutual_circles <> '[]'::jsonb then
    failures := failures || E'\na shared circle was enough for friends only';
  end if;
  perform pg_temp.as_user(bob);
  select * into summary from public.get_profile_summary(ada);
  if summary.bio <> 'Ada''s bio' or summary.profile_hidden then
    failures := failures || E'\na friend lost the profile under friends only';
  end if;

  -- People always see their own.
  perform pg_temp.as_user(ada);
  select * into summary from public.get_profile_summary(ada);
  if summary.bio <> 'Ada''s bio' or summary.profile_hidden or summary.relationship_status <> 'self' then
    failures := failures || E'\nAda cannot see her own profile';
  end if;

  -- Back to everyone.
  perform public.set_profile_visibility('everyone');
  perform pg_temp.as_user(dee);
  select * into summary from public.get_profile_summary(ada);
  if summary.bio <> 'Ada''s bio' then
    failures := failures || E'\nthe setting did not go back to everyone';
  end if;

  -- Only the three values; only for yourself.
  perform pg_temp.as_user(ada);
  failed := false;
  begin perform public.set_profile_visibility('nobody');
  exception when invalid_parameter_value then failed := true; end;
  if not failed then failures := failures || E'\nan unknown value was accepted'; end if;
  perform pg_temp.as_user(bob);
  perform public.set_profile_visibility('friends');
  if (select profile_visibility from public.user_privacy_settings where user_id = ada) <> 'everyone' then
    failures := failures || E'\nBob changed Ada''s setting';
  end if;

  if failures <> '' then
    raise exception 'profile visibility checks failed:%', failures;
  end if;
end $$;

rollback;
