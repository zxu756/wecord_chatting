-- Behaviour checks for privacy permissions 2.0 and new-login alerts
-- (migrations 202610210410, 202610210420 and 202610210430). Run by
-- test/supabase/privacy_permissions_test.dart against the local database
-- inside a transaction that is rolled back, so the database is left as it
-- was. It applies the earlier migrations it lacks, then these three, plays
-- several people and checks what each may do. Run from the repository root.
--
-- Cast:
--   ada  has the settings               bob  Ada's friend (and Eli's, Fay's)
--   cy   in a circle with Ada           dee  a stranger
--   eli  Bob's friend, so Ada's friend of a friend
--   fay  Ada's friend, starred by her
\set ON_ERROR_STOP on

begin;

-- One behaviour script at a time: they change the same tables.
do $$ begin perform pg_advisory_xact_lock(20261017); end $$;

\i supabase/migrations/202610170002_album_counts.sql
\i supabase/migrations/202610170003_album_summaries.sql
\i supabase/migrations/202610170004_album_push.sql
\i supabase/migrations/202610170005_push_language.sql
\i supabase/migrations/202610170010_scheduled_messages.sql
\i supabase/migrations/202610170011_message_reminders.sql
\i supabase/migrations/202610170012_saved_messages.sql
\i supabase/migrations/202610170020_disappearing_messages.sql
\i supabase/migrations/202610170021_view_once_media.sql
\i supabase/migrations/202610170022_device_sessions.sql
\i supabase/migrations/202610170023_poll_upgrade.sql
\i supabase/migrations/202610170024_profile_visibility.sql
\i supabase/migrations/202610170030_ai_usage.sql
\i supabase/migrations/202610170031_circle_ai_switch.sql
\i supabase/migrations/202610170040_call_links.sql
\i supabase/migrations/202610170050_chat_events.sql
\i supabase/migrations/202610170052_inactive_groups.sql
\i supabase/migrations/202610170053_data_export.sql
\i supabase/migrations/202610170060_notes.sql
\i supabase/migrations/202610170061_note_versions_files.sql
\i supabase/migrations/202610170062_task_lists.sql
\i supabase/migrations/202610170063_task_notifications.sql
\i supabase/migrations/202610170064_tasks_from_messages.sql
\i supabase/migrations/202610170065_conversation_workspace.sql
\i supabase/migrations/202610170070_dispatch_more.sql
\i supabase/migrations/202610170090_ai_guard.sql
\i supabase/migrations/202610170091_ai_guard_hidden.sql
\i supabase/migrations/202610170100_push_time_zone.sql
\i supabase/migrations/202610170101_profile_visibility_enforced.sql
\i supabase/migrations/202610170110_chat_wallpapers.sql
\i supabase/migrations/202610180030_user_qr_codes.sql
\i supabase/migrations/202610180031_group_qr_codes.sql
\i supabase/migrations/202610180032_pat.sql
\i supabase/migrations/202610180033_note_to_self.sql
\i supabase/migrations/202610180034_chat_list_pat_note.sql
\i supabase/migrations/202610180040_friend_tags_and_stars.sql
\i supabase/migrations/202610180041_moments.sql
\i supabase/migrations/202610180042_moments_feed.sql
\i supabase/migrations/202610180050_location.sql
\i supabase/migrations/202610180060_group_chains.sql
\i supabase/migrations/202610180070_merged_forward.sql
\i supabase/migrations/202610180071_contact_cards.sql
\i supabase/migrations/202610190010_security_attachment_paths.sql
\i supabase/migrations/202610190011_security_hidden_messages.sql
\i supabase/migrations/202610190012_security_chains.sql
\i supabase/migrations/202610190013_security_deleted_content.sql
\i supabase/migrations/202610190020_moments_realtime.sql
\i supabase/migrations/202610190021_moments_push.sql
\i supabase/migrations/202610190022_moments_video.sql
\i supabase/migrations/202610190023_data_export_more.sql
\i supabase/migrations/202610190030_client_errors.sql
\i supabase/migrations/202610190050_realtime_private.sql
\i supabase/migrations/202610190051_storage_limits.sql
\i supabase/migrations/202610190060_get_chains.sql
\i supabase/migrations/202610190061_conversation_capabilities.sql
\i supabase/migrations/202610190062_conversation_summary.sql
\i supabase/migrations/202610190070_presence_visibility.sql
\i supabase/migrations/202610190071_drop_online_users_policy.sql
\i supabase/migrations/202610200010_push_text_language.sql
\i supabase/migrations/202610200020_ai_guard_reason_zh.sql
\i supabase/migrations/202610210110_admin_foundation.sql
\i supabase/migrations/202610210120_circle_takedown.sql
\i supabase/migrations/202610210130_admin_rpcs.sql
\i supabase/migrations/202610210200_chat_folders.sql
\i supabase/migrations/202610210300_notification_settings.sql
\i supabase/migrations/202610210310_quiet_hours.sql
\i supabase/migrations/202610210410_privacy_permissions.sql
\i supabase/migrations/202610210420_group_invitations.sql
\i supabase/migrations/202610210430_login_alerts.sql

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

insert into ids values
  ('ada', '00000000-0000-4000-8000-0000000000a1'),
  ('bob', '00000000-0000-4000-8000-0000000000b1'),
  ('cy',  '00000000-0000-4000-8000-0000000000c1'),
  ('dee', '00000000-0000-4000-8000-0000000000d1'),
  ('eli', '00000000-0000-4000-8000-0000000000e1'),
  ('fay', '00000000-0000-4000-8000-0000000000f1');

insert into auth.users (id, email, instance_id, aud, role)
select id, name || '@perm2.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
from ids;
insert into public.profiles (id, username, display_name)
select id, name || '_p2', initcap(name) from ids;

create function pg_temp.uid(who text) returns uuid language sql as $$
  select id from pg_temp.ids where name = who
$$;
grant execute on function pg_temp.uid(text) to public;

create function pg_temp.act_as(who text, session uuid default null) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  if who is not null then
    perform set_config('request.jwt.claim.sub', pg_temp.uid(who)::text, true);
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', pg_temp.uid(who), 'role', 'authenticated', 'session_id', session)::text,
      true
    );
    execute 'set local role authenticated';
  end if;
end;
$$;
grant execute on function pg_temp.act_as(text, uuid) to public;

create function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin
  if ok is distinct from true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok: %', label;
end;
$$;

-- Runs [stmt] and fails unless it raises SQLSTATE [code].
create function pg_temp.refused(label text, stmt text, code text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    if sqlstate <> code then
      raise exception 'FAILED: % (wanted %, got % %)', label, code, sqlstate, sqlerrm;
    end if;
    raise notice 'ok: %', label;
    return;
  end;
  raise exception 'FAILED: % (nothing was refused)', label;
end;
$$;

-- Runs [stmt] and fails when it raises.
create function pg_temp.allowed(label text, stmt text) returns void language plpgsql as $$
begin
  execute stmt;
  raise notice 'ok: %', label;
exception when others then
  raise exception 'FAILED: % (%, %)', label, sqlstate, sqlerrm;
end;
$$;

create function pg_temp.befriend(a text, b text) returns void language sql as $$
  insert into public.friendships (user_low_id, user_high_id)
  values (least(pg_temp.uid(a), pg_temp.uid(b)), greatest(pg_temp.uid(a), pg_temp.uid(b)));
$$;

-- Friends: Ada-Bob, Ada-Fay, Bob-Eli, Bob-Fay. Ada and Cy share a circle.
select pg_temp.befriend('ada', 'bob');
select pg_temp.befriend('ada', 'fay');
select pg_temp.befriend('bob', 'eli');
select pg_temp.befriend('bob', 'fay');
insert into public.circles (id, name, owner_id)
values ('00000000-0000-4000-8000-00000000c100', 'Shared', pg_temp.uid('ada'));
insert into public.circle_members (circle_id, user_id)
values ('00000000-0000-4000-8000-00000000c100', pg_temp.uid('cy'))
on conflict do nothing;
insert into public.circle_members (circle_id, user_id)
values ('00000000-0000-4000-8000-00000000c100', pg_temp.uid('ada'))
on conflict do nothing;
insert into public.friend_stars (owner_id, friend_id)
values (pg_temp.uid('ada'), pg_temp.uid('fay'));

create function pg_temp.set_perm(who text, setting text, value text) returns void language plpgsql as $$
begin
  perform pg_temp.act_as(who);
  case setting
    when 'friend_request_from' then perform public.set_privacy_permissions(friend_request_from => value);
    when 'group_invite_from' then perform public.set_privacy_permissions(group_invite_from => value);
    when 'allow_calls_from' then perform public.set_privacy_permissions(allow_calls_from => value);
    when 'username' then perform public.set_privacy_permissions(discoverable_by_username => value::boolean);
    when 'qr' then perform public.set_privacy_permissions(discoverable_by_qr => value::boolean);
  end case;
  perform pg_temp.act_as(null);
end;
$$;

-- Tries a friend request from [who] to Ada and removes it again.
create function pg_temp.request_works(who text) returns boolean language plpgsql as $$
begin
  perform pg_temp.act_as(who);
  begin
    perform public.send_friend_request(pg_temp.uid('ada'));
  exception when sqlstate '42501' then
    perform pg_temp.act_as(null);
    return false;
  end;
  perform pg_temp.act_as(null);
  delete from public.friend_requests where receiver_id = pg_temp.uid('ada');
  return true;
end;
$$;

-- ------------------------------------------------------------ the setting

select pg_temp.act_as('ada');
select pg_temp.refused('a wrong value is refused',
  $q$select public.set_privacy_permissions(friend_request_from => 'bots')$q$, '22023');
select pg_temp.refused('a wrong group value is refused',
  $q$select public.set_privacy_permissions(group_invite_from => 'nobody')$q$, '22023');
select pg_temp.refused('a wrong call value is refused',
  $q$select public.set_privacy_permissions(allow_calls_from => 'everyone')$q$, '22023');
select pg_temp.act_as(null);
select pg_temp.act_as('dee');
select pg_temp.refused('someone else''s row cannot be read',
  $q$select 1 / (select count(*)::int from public.user_privacy_settings where user_id = '00000000-0000-4000-8000-0000000000a1')$q$,
  '22012');
select pg_temp.act_as(null);

-- ------------------------------------------------------- friend requests

-- everyone: the default, with no row at all
select pg_temp.check('everyone (no row): stranger may ask', pg_temp.request_works('dee'));
select pg_temp.check('everyone: friend of a friend may ask', pg_temp.request_works('eli'));
select pg_temp.check('everyone: circle mate may ask', pg_temp.request_works('cy'));

select pg_temp.set_perm('ada', 'friend_request_from', 'friends_of_friends');
select pg_temp.check('friends of friends: stranger is refused', not pg_temp.request_works('dee'));
select pg_temp.check('friends of friends: friend of a friend may ask', pg_temp.request_works('eli'));
select pg_temp.check('friends of friends: circle mate is refused', not pg_temp.request_works('cy'));

select pg_temp.set_perm('ada', 'friend_request_from', 'circle_members');
select pg_temp.check('circle members: stranger is refused', not pg_temp.request_works('dee'));
select pg_temp.check('circle members: friend of a friend is refused', not pg_temp.request_works('eli'));
select pg_temp.check('circle members: circle mate may ask', pg_temp.request_works('cy'));

select pg_temp.set_perm('ada', 'friend_request_from', 'nobody');
select pg_temp.check('nobody: stranger is refused', not pg_temp.request_works('dee'));
select pg_temp.check('nobody: friend of a friend is refused', not pg_temp.request_works('eli'));
select pg_temp.check('nobody: circle mate is refused', not pg_temp.request_works('cy'));
select pg_temp.check('the older column follows (nobody is none)',
  (select friend_request_policy = 'none' from public.user_privacy_settings
   where user_id = pg_temp.uid('ada')));

-- A plain table insert is held to it as well (the trigger, not the RPC;
-- clients cannot insert directly, but the rule must not depend on that).
select pg_temp.refused('nobody: a direct insert is refused too',
  format($q$insert into public.friend_requests (requester_id, receiver_id) values (%L, %L)$q$,
    pg_temp.uid('dee'), pg_temp.uid('ada')), '42501');
select pg_temp.set_perm('ada', 'friend_request_from', 'everyone');
select pg_temp.allowed('everyone: a direct insert works again',
  format($q$insert into public.friend_requests (requester_id, receiver_id) values (%L, %L)$q$,
    pg_temp.uid('dee'), pg_temp.uid('ada')));
delete from public.friend_requests;

-- Asking Ada does not depend on what Dee allows for herself, and Ada can
-- still ask others when she is set to nobody.
select pg_temp.set_perm('ada', 'friend_request_from', 'nobody');
select pg_temp.act_as('ada');
select pg_temp.allowed('nobody: Ada may still ask someone else',
  format($q$select public.send_friend_request(%L)$q$, pg_temp.uid('dee')));
select pg_temp.act_as(null);
delete from public.friend_requests;
select pg_temp.set_perm('ada', 'friend_request_from', 'everyone');

-- ------------------------------------------------------- username search

select pg_temp.act_as('dee');
select pg_temp.check('findable by username by default',
  exists (select 1 from public.search_users_by_username('ada_p2')));
select pg_temp.check('the search is case blind and partial',
  exists (select 1 from public.search_users_by_username('ADA')));
select pg_temp.check('the search does not return yourself',
  not exists (select 1 from public.search_users_by_username('dee_p2')));
select pg_temp.check('an empty search returns nothing',
  not exists (select 1 from public.search_users_by_username('  ')));
select pg_temp.check('% is not a wildcard',
  not exists (select 1 from public.search_users_by_username('%')));
select pg_temp.act_as(null);

select pg_temp.set_perm('ada', 'username', 'false');
select pg_temp.act_as('dee');
select pg_temp.check('hidden from username search: a stranger finds nothing',
  not exists (select 1 from public.search_users_by_username('ada_p2')));
select pg_temp.act_as('eli');
select pg_temp.check('hidden from username search: a friend of a friend finds nothing',
  not exists (select 1 from public.search_users_by_username('ada_p2')));
select pg_temp.act_as('cy');
select pg_temp.check('hidden from username search: a circle mate finds nothing',
  not exists (select 1 from public.search_users_by_username('ada_p2')));
select pg_temp.act_as('bob');
select pg_temp.check('hidden from username search: a friend still finds her',
  exists (select 1 from public.search_users_by_username('ada_p2')));
select pg_temp.act_as(null);
select pg_temp.set_perm('ada', 'username', 'true');

insert into public.blocks (blocker_id, blocked_id) values (pg_temp.uid('ada'), pg_temp.uid('dee'));
select pg_temp.act_as('dee');
select pg_temp.check('a blocked person does not find her either',
  not exists (select 1 from public.search_users_by_username('ada_p2')));
select pg_temp.act_as(null);
delete from public.blocks;

-- ---------------------------------------------------------------- QR code

select pg_temp.act_as('ada');
create temp table codes (name text primary key, code text not null);
grant all on codes to public;
insert into codes select 'ada', public.get_my_qr_code();
select pg_temp.act_as(null);

select pg_temp.act_as('dee');
select pg_temp.check('a stranger resolves her code by default',
  exists (select 1 from public.resolve_user_qr_code((select code from codes))));
select pg_temp.act_as(null);

select pg_temp.set_perm('ada', 'qr', 'false');
select pg_temp.act_as('dee');
select pg_temp.check('QR off: a stranger resolves nothing',
  not exists (select 1 from public.resolve_user_qr_code((select code from codes))));
select pg_temp.act_as('eli');
select pg_temp.check('QR off: a friend of a friend resolves nothing',
  not exists (select 1 from public.resolve_user_qr_code((select code from codes))));
select pg_temp.act_as('cy');
select pg_temp.check('QR off: a circle mate resolves nothing',
  not exists (select 1 from public.resolve_user_qr_code((select code from codes))));
select pg_temp.act_as('bob');
select pg_temp.check('QR off: a friend still resolves it',
  exists (select 1 from public.resolve_user_qr_code((select code from codes))));
select pg_temp.act_as('ada');
select pg_temp.check('QR off: she still resolves her own',
  exists (select 1 from public.resolve_user_qr_code((select code from codes))));
select pg_temp.act_as(null);
select pg_temp.set_perm('ada', 'qr', 'true');
select pg_temp.act_as('dee');
select pg_temp.check('QR on again: a stranger resolves it',
  exists (select 1 from public.resolve_user_qr_code((select code from codes))));
select pg_temp.act_as(null);

-- ------------------------------------------------------------------ calls

select pg_temp.act_as('ada');
create temp table convs (name text primary key, id uuid not null);
grant all on convs to public;
insert into convs select 'ada-bob', public.get_or_create_direct_conversation(pg_temp.uid('bob'));
select pg_temp.act_as('bob');
insert into convs select 'bob-eli', public.get_or_create_direct_conversation(pg_temp.uid('eli'));
select pg_temp.act_as(null);

select pg_temp.act_as('bob');
select pg_temp.check('friends: Bob may call Ada by default',
  public.can_current_user_call_in_conversation((select id from convs where name = 'ada-bob')));
select pg_temp.act_as(null);

select pg_temp.set_perm('ada', 'allow_calls_from', 'starred_friends');
select pg_temp.act_as('bob');
select pg_temp.check('starred only: an unstarred friend may not call',
  not public.can_current_user_call_in_conversation((select id from convs where name = 'ada-bob')));
select pg_temp.refused('starred only: starting the call is refused',
  format($q$select public.start_direct_call(%L)$q$, (select id from convs where name = 'ada-bob')), '42501');
select pg_temp.act_as('ada');
select pg_temp.check('starred only: Ada may still call Bob',
  public.can_current_user_call_in_conversation((select id from convs where name = 'ada-bob')));
select pg_temp.act_as(null);
insert into public.friend_stars (owner_id, friend_id) values (pg_temp.uid('ada'), pg_temp.uid('bob'));
select pg_temp.act_as('bob');
select pg_temp.check('starred only: a starred friend may call',
  public.can_current_user_call_in_conversation((select id from convs where name = 'ada-bob')));
select pg_temp.act_as(null);
delete from public.friend_stars where friend_id = pg_temp.uid('bob');

select pg_temp.set_perm('ada', 'allow_calls_from', 'nobody');
select pg_temp.act_as('bob');
select pg_temp.check('nobody: a friend may not call',
  not public.can_current_user_call_in_conversation((select id from convs where name = 'ada-bob')));
select pg_temp.act_as('eli');
select pg_temp.check('nobody: others'' calls with Bob are unaffected',
  public.can_current_user_call_in_conversation((select id from convs where name = 'bob-eli')));
select pg_temp.act_as(null);
select pg_temp.set_perm('ada', 'allow_calls_from', 'friends');
select pg_temp.act_as('bob');
select pg_temp.check('friends: Bob may call again',
  public.can_current_user_call_in_conversation((select id from convs where name = 'ada-bob')));
select pg_temp.act_as(null);

-- DMs stay friends-only whatever the settings say.
select pg_temp.act_as('dee');
select pg_temp.refused('a stranger still cannot open a direct chat',
  format($q$select public.get_or_create_direct_conversation(%L)$q$, pg_temp.uid('ada')), '42501');
select pg_temp.act_as(null);

-- --------------------------------------------------- group invitations

-- Bob makes a group of Fay and Eli with Ada set to ask first.
select pg_temp.set_perm('ada', 'group_invite_from', 'approval');
select pg_temp.act_as('bob');
create temp table groups (name text primary key, id uuid not null);
grant all on groups to public;
insert into groups select 'g1', public.create_group_conversation(
  'Weekend', array[pg_temp.uid('fay'), pg_temp.uid('eli')]);
select pg_temp.check('the creator is the owner',
  exists (select 1 from public.conversation_members
          where conversation_id = (select id from groups where name = 'g1')
            and user_id = pg_temp.uid('bob') and role = 'owner'));

-- Ada needs to approve: no membership, an invitation.
create temp table results (name text primary key, r jsonb);
grant all on results to public;
insert into results select 'add1', public.add_group_members(
  (select id from groups where name = 'g1'), array[pg_temp.uid('ada')]);
select pg_temp.check('approval: Ada was not added',
  not exists (select 1 from public.conversation_members
              where conversation_id = (select id from groups where name = 'g1')
                and user_id = pg_temp.uid('ada')));
select pg_temp.check('approval: the result lists her as invited',
  (select r->'invited' = to_jsonb(array[pg_temp.uid('ada')]) and r->'added' = '[]'::jsonb
   from results where name = 'add1'));
select pg_temp.act_as(null);
select pg_temp.check('one open invitation that lasts 7 days',
  (select count(*) = 1 and bool_and(expires_at - created_at = interval '7 days')
   from public.group_invitations
   where invitee_id = pg_temp.uid('ada') and status = 'pending'));

-- Asking twice keeps one.
select pg_temp.act_as('bob');
select public.add_group_members((select id from groups where name = 'g1'), array[pg_temp.uid('ada')]);
select pg_temp.act_as(null);
select pg_temp.check('asking again keeps a single invitation',
  (select count(*) = 1 from public.group_invitations where invitee_id = pg_temp.uid('ada')));

-- The card.
select pg_temp.act_as('ada');
select pg_temp.check('the card names the group and the inviter',
  (select count(*) = 1 and bool_and(group_title = 'Weekend' and inviter_name = 'Bob')
   from public.list_my_group_invitations()));
select pg_temp.act_as('dee');
select pg_temp.check('others do not see it', not exists (select 1 from public.list_my_group_invitations()));
select pg_temp.refused('others cannot answer it',
  format($q$select public.respond_group_invitation(%L, true)$q$,
    (select id from public.group_invitations where invitee_id = pg_temp.uid('ada'))), '42501');
select pg_temp.act_as('ada');
select pg_temp.check('Ada reads her own invitation row',
  (select count(*) = 1 from public.group_invitations));
select pg_temp.refused('the table takes no direct writes',
  $q$update public.group_invitations set status = 'accepted'$q$, '42501');

-- Accept.
create temp table answers (name text primary key, conv uuid);
grant all on answers to public;
insert into answers select 'ada', public.respond_group_invitation(
  (select id from public.group_invitations where invitee_id = pg_temp.uid('ada')), true);
select pg_temp.check('accepting returns the group and joins it',
  (select conv = (select id from groups where name = 'g1') from answers where name = 'ada')
  and exists (select 1 from public.conversation_members
              where conversation_id = (select id from groups where name = 'g1')
                and user_id = pg_temp.uid('ada') and role = 'member'));
select pg_temp.check('an answered invitation leaves the card list',
  not exists (select 1 from public.list_my_group_invitations()));
select pg_temp.refused('answering twice is refused',
  format($q$select public.respond_group_invitation(%L, true)$q$,
    (select id from public.group_invitations where invitee_id = pg_temp.uid('ada'))), '42501');
select pg_temp.act_as(null);

-- Decline.
select pg_temp.act_as('bob');
insert into groups select 'g2', public.create_group_conversation(
  'Trip', array[pg_temp.uid('fay'), pg_temp.uid('eli')]);
select public.add_group_members((select id from groups where name = 'g2'), array[pg_temp.uid('ada')]);
select pg_temp.act_as('ada');
select pg_temp.check('declining returns nothing',
  public.respond_group_invitation(
    (select id from public.group_invitations
     where invitee_id = pg_temp.uid('ada') and status = 'pending'), false) is null);
select pg_temp.check('declining does not join',
  not exists (select 1 from public.conversation_members
              where conversation_id = (select id from groups where name = 'g2')
                and user_id = pg_temp.uid('ada')));
select pg_temp.act_as(null);

-- Expiry after 7 days.
select pg_temp.act_as('bob');
insert into groups select 'g3', public.create_group_conversation(
  'Old', array[pg_temp.uid('fay'), pg_temp.uid('eli')]);
select public.add_group_members((select id from groups where name = 'g3'), array[pg_temp.uid('ada')]);
select pg_temp.act_as(null);
update public.group_invitations
set created_at = now() - interval '8 days', expires_at = now() - interval '1 day'
where conversation_id = (select id from groups where name = 'g3');
select pg_temp.act_as('ada');
select pg_temp.check('a lapsed invitation is not listed',
  not exists (select 1 from public.list_my_group_invitations()));
select pg_temp.refused('a lapsed invitation cannot be accepted',
  format($q$select public.respond_group_invitation(%L, true)$q$,
    (select id from public.group_invitations
     where conversation_id = (select id from groups where name = 'g3'))), '22023');
select pg_temp.act_as('bob');
select public.add_group_members((select id from groups where name = 'g3'), array[pg_temp.uid('ada')]);
select pg_temp.act_as(null);
select pg_temp.check('inviting again after it lapsed opens a fresh one',
  (select count(*) = 1 from public.group_invitations
   where conversation_id = (select id from groups where name = 'g3') and status = 'pending'
     and expires_at > now()));

-- Blocking after the invitation.
select pg_temp.act_as('bob');
insert into groups select 'g4', public.create_group_conversation(
  'Blocked', array[pg_temp.uid('fay'), pg_temp.uid('eli')]);
select public.add_group_members((select id from groups where name = 'g4'), array[pg_temp.uid('ada')]);
select pg_temp.act_as(null);
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.uid('ada'), pg_temp.uid('bob'));
select pg_temp.act_as('ada');
select pg_temp.check('an invitation from someone she blocked is hidden',
  not exists (select 1 from public.list_my_group_invitations()
              where group_title = 'Blocked'));
select pg_temp.refused('and cannot be accepted',
  format($q$select public.respond_group_invitation(%L, true)$q$,
    (select id from public.group_invitations
     where conversation_id = (select id from groups where name = 'g4'))), '42501');
select pg_temp.act_as(null);
delete from public.blocks;

-- The other settings.
select pg_temp.set_perm('ada', 'group_invite_from', 'all_friends');
select pg_temp.set_perm('fay', 'group_invite_from', 'starred_friends');
select pg_temp.set_perm('eli', 'group_invite_from', 'approval');
select pg_temp.act_as('bob');
insert into groups select 'g5', public.create_group_conversation(
  'Mixed', array[pg_temp.uid('ada'), pg_temp.uid('fay'), pg_temp.uid('eli')]);
select pg_temp.act_as(null);
select pg_temp.check('all friends: Ada is added straight in',
  exists (select 1 from public.conversation_members
          where conversation_id = (select id from groups where name = 'g5') and user_id = pg_temp.uid('ada')));
select pg_temp.check('starred friends: Fay does not take an unstarred adder',
  not exists (select 1 from public.conversation_members
              where conversation_id = (select id from groups where name = 'g5') and user_id = pg_temp.uid('fay'))
  and exists (select 1 from public.group_invitations
              where conversation_id = (select id from groups where name = 'g5')
                and invitee_id = pg_temp.uid('fay') and status = 'pending'));
select pg_temp.check('approval: Eli gets an invitation when the group is made',
  not exists (select 1 from public.conversation_members
              where conversation_id = (select id from groups where name = 'g5') and user_id = pg_temp.uid('eli'))
  and exists (select 1 from public.group_invitations
              where conversation_id = (select id from groups where name = 'g5')
                and invitee_id = pg_temp.uid('eli') and status = 'pending'));

-- Starred by the invitee: added straight in.
insert into public.friend_stars (owner_id, friend_id) values (pg_temp.uid('fay'), pg_temp.uid('bob'));
select pg_temp.act_as('bob');
insert into groups select 'g6', public.create_group_conversation(
  'Starred', array[pg_temp.uid('ada'), pg_temp.uid('fay')]);
select pg_temp.act_as(null);
select pg_temp.check('starred friends: Fay is added straight in by someone she starred',
  exists (select 1 from public.conversation_members
          where conversation_id = (select id from groups where name = 'g6') and user_id = pg_temp.uid('fay')));

select pg_temp.act_as('bob');
select pg_temp.refused('only friends can be added (stranger)',
  format($q$select public.add_group_members(%L, array[%L::uuid])$q$,
    (select id from groups where name = 'g5'), pg_temp.uid('dee')), '42501');
select pg_temp.act_as('ada');
select pg_temp.refused('a plain member cannot add anyone',
  format($q$select public.add_group_members(%L, array[%L::uuid])$q$,
    (select id from groups where name = 'g5'), pg_temp.uid('fay')), '42501');
select pg_temp.act_as(null);

-- Voluntary paths are untouched: the group QR code gets Dee in, whatever
-- her setting.
select pg_temp.set_perm('dee', 'group_invite_from', 'approval');
select pg_temp.act_as('bob');
create temp table gcodes (name text primary key, code text not null);
grant all on gcodes to public;
insert into gcodes select 'g5', (public.get_group_qr((select id from groups where name = 'g5')))->>'code';
select pg_temp.act_as('dee');
create temp table joined (r jsonb);
grant all on joined to public;
insert into joined select public.join_group_by_qr((select code from gcodes where name = 'g5'));
select pg_temp.check('the group QR code still joins someone who wants approval',
  (select r->>'state' = 'joined' from joined)
  and exists (select 1 from public.conversation_members
              where conversation_id = (select id from groups where name = 'g5') and user_id = pg_temp.uid('dee')));
select pg_temp.act_as(null);

-- ---------------------------------------------------------- login alerts

insert into auth.sessions (id, user_id, created_at, updated_at, user_agent)
values
  ('00000000-0000-4000-8000-0000000000e2', pg_temp.uid('ada'), now() - interval '5 days', now() - interval '5 days', 'Safari'),
  ('00000000-0000-4000-8000-0000000000e3', pg_temp.uid('ada'), now(), now(), 'Chrome'),
  ('00000000-0000-4000-8000-0000000000e4', pg_temp.uid('bob'), now(), now(), 'Bob browser'),
  ('00000000-0000-4000-8000-0000000000e5', pg_temp.uid('ada'), now(), now(), 'Phone');

select pg_temp.act_as('ada', '00000000-0000-4000-8000-0000000000e2');
select public.register_device('Ada MacBook', 'macOS', '1.0');
select pg_temp.check('the first login raises no alert',
  not exists (select 1 from public.login_alerts));
select public.register_device('Ada MacBook', 'macOS', '1.0');
select pg_temp.check('registering again (a token refresh) raises none',
  not exists (select 1 from public.login_alerts));

select pg_temp.act_as('ada', '00000000-0000-4000-8000-0000000000e3');
select public.register_device('Ada iPhone', 'iOS', '1.0');
select pg_temp.act_as(null);
select pg_temp.check('a second device raises one alert with its name and platform',
  (select count(*) = 1 and bool_and(device_name = 'Ada iPhone' and platform = 'iOS'
      and session_id = '00000000-0000-4000-8000-0000000000e3' and resolved_at is null)
   from public.login_alerts where user_id = pg_temp.uid('ada')));

select pg_temp.act_as('ada', '00000000-0000-4000-8000-0000000000e3');
select public.register_device('Ada iPhone', 'iOS', '1.0.1');
select pg_temp.act_as(null);
select pg_temp.check('the new device registering again raises no second alert',
  (select count(*) = 1 from public.login_alerts where user_id = pg_temp.uid('ada')));

select pg_temp.act_as('bob', '00000000-0000-4000-8000-0000000000e4');
select public.register_device('Bob laptop', 'Web', '1.0');
select pg_temp.check('another person''s first device raises nothing for them',
  not exists (select 1 from public.list_my_login_alerts()));
select pg_temp.act_as('ada', '00000000-0000-4000-8000-0000000000e3');
select pg_temp.check('Ada lists her alert',
  (select count(*) = 1 from public.list_my_login_alerts()));
select pg_temp.act_as('bob');
select pg_temp.check('Bob does not see Ada''s',
  not exists (select 1 from public.list_my_login_alerts()));
select pg_temp.refused('the table is only readable for its owner (no rows for others)',
  $q$select 1 / (select count(*)::int from public.login_alerts)$q$, '22012');
select pg_temp.refused('the alert table takes no direct writes',
  $q$update public.login_alerts set resolution = 'dismissed'$q$, '42501');
select pg_temp.act_as(null);

-- Push: only to the subscriptions that existed at the time, in their language.
insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, language, created_at)
values
  (pg_temp.uid('ada'), 'https://push.example/old-zh', repeat('k', 60), repeat('a', 20), 'zh', now() - interval '1 hour'),
  (pg_temp.uid('ada'), 'https://push.example/old-en', repeat('k', 60), repeat('a', 20), 'en', now() - interval '1 day'),
  (pg_temp.uid('ada'), 'https://push.example/new-device', repeat('k', 60), repeat('a', 20), 'en', now() + interval '1 minute'),
  (pg_temp.uid('bob'), 'https://push.example/bob', repeat('k', 60), repeat('a', 20), 'en', now() - interval '1 hour');

create temp table pushes as
select * from public.claim_security_alert_pushes();
select pg_temp.check('two older subscriptions of Ada are pushed, no one else''s',
  (select count(*) = 2 from pushes));
select pg_temp.check('the Chinese subscription gets Chinese text with a time token',
  (select title = '你的账号在新设备上登录' and body like 'Ada iPhone (iOS)，<t:%:f>。不是你%'
          and body like '%不是你%' and body ~ '<t:[0-9]+:f>'
   from pushes p join public.push_subscriptions s on s.id = p.subscription_id
   where s.endpoint = 'https://push.example/old-zh'));
select pg_temp.check('the English subscription gets English text',
  (select title = 'New sign-in to your account' and body like 'Ada iPhone (iOS), <t:%:f>. Not you?%'
   from pushes p join public.push_subscriptions s on s.id = p.subscription_id
   where s.endpoint = 'https://push.example/old-en'));
select pg_temp.check('the push opens Notifications',
  (select bool_and(url = '/#/notifications' and tag like 'security-%') from pushes));
select pg_temp.check('no address or location is in the text',
  (select bool_and(body !~* '(location|address|ip address|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)') from pushes where body like 'Ada%'));
select pg_temp.check('an alert is pushed once',
  not exists (select 1 from public.claim_security_alert_pushes()));

-- An alert that waited too long is closed without a push.
insert into public.login_alerts (user_id, session_id, device_name, platform, created_at)
values (pg_temp.uid('ada'), '00000000-0000-4000-8000-0000000000e5', 'Old', 'Web', now() - interval '1 hour');
select pg_temp.check('a stale alert is not pushed',
  not exists (select 1 from public.claim_security_alert_pushes()));
select pg_temp.check('and is marked claimed',
  (select push_claimed_at is not null from public.login_alerts where device_name = 'Old'));

-- Angle brackets in a device name cannot pass for a time token.
update public.login_alerts set push_claimed_at = null, created_at = now(), device_name = '<t:1:F>x'
where device_name = 'Old';
select pg_temp.check('a device name cannot smuggle a time token',
  (select count(*) = 2 and bool_and(body !~ '<t:1:F>') from public.claim_security_alert_pushes()));

-- Not me / It was me.
select pg_temp.act_as('bob');
select pg_temp.refused('another person cannot close the alert',
  format($q$select public.resolve_login_alert(%L, 'dismissed')$q$,
    (select id from public.login_alerts where session_id = '00000000-0000-4000-8000-0000000000e3')), '42501');
select pg_temp.act_as('ada', '00000000-0000-4000-8000-0000000000e2');
select pg_temp.refused('an unknown outcome is refused',
  format($q$select public.resolve_login_alert(%L, 'ignored')$q$,
    (select id from public.login_alerts where session_id = '00000000-0000-4000-8000-0000000000e3')), '22023');
select public.resolve_login_alert(
  (select id from public.login_alerts where session_id = '00000000-0000-4000-8000-0000000000e3'), 'revoked');
select pg_temp.check('"Not me" closes the alert as revoked',
  (select resolution = 'revoked' and resolved_at is not null
   from public.list_my_login_alerts() where session_id = '00000000-0000-4000-8000-0000000000e3'));

-- The sessions function's path ends that session (service role only).
select pg_temp.act_as(null);
select pg_temp.check('the new session is still there until it is ended',
  exists (select 1 from auth.sessions where id = '00000000-0000-4000-8000-0000000000e3'));
select public.delete_user_session('00000000-0000-4000-8000-0000000000e3', pg_temp.uid('ada'));
select pg_temp.check('ending the session removes it and its device record',
  not exists (select 1 from auth.sessions where id = '00000000-0000-4000-8000-0000000000e3')
  and not exists (select 1 from public.user_devices where session_id = '00000000-0000-4000-8000-0000000000e3'));
select pg_temp.check('the alert stays as a record',
  exists (select 1 from public.login_alerts where session_id = '00000000-0000-4000-8000-0000000000e3'));

-- After signing everything out, the next login is a first one again.
delete from auth.sessions where user_id = pg_temp.uid('ada');
insert into auth.sessions (id, user_id) values ('00000000-0000-4000-8000-0000000000e6', pg_temp.uid('ada'));
delete from public.login_alerts;
select pg_temp.act_as('ada', '00000000-0000-4000-8000-0000000000e6');
select public.register_device('Ada new phone', 'iOS', '1');
select pg_temp.act_as(null);
select pg_temp.check('with no other device left, a new login raises nothing',
  not exists (select 1 from public.login_alerts));

rollback;
