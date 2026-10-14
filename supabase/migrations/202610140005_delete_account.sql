-- Account deletion.
--
-- The delete-account Edge Function calls prepare_account_deletion() as the
-- user, then removes their avatar files and their login (auth.users) with
-- the service role. Like on Discord, what they said in other people's chats
-- stays, under a "Deleted User" profile:
--
-- * profiles.deleted_at marks the profile of a deleted account. The profile
--   row stays so messages, posts and reactions keep an author, which is why
--   the profile no longer cascades from auth.users.
-- * prepare_account_deletion refuses while the user owns a circle with
--   other members (they must transfer it first) and deletes circles where
--   they are the only member, hands groups they solely own to the
--   member who joined first, leaves every circle and group, drops
--   friendships, requests, blocks, aliases, privacy settings and voice
--   states, and wipes the profile: username deleted_<id>, display name
--   "Deleted User", no avatar, bio or status. Direct chats stay so the other
--   person keeps the history, but nobody can message a deleted account.
-- * Friend requests to deleted accounts are refused.

alter table public.profiles
  add column if not exists deleted_at timestamptz;

alter table public.profiles
  drop constraint if exists profiles_id_fkey;

create or replace function public.prepare_account_deletion()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  membership record;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.circles c
    join public.circle_members other
      on other.circle_id = c.id
      and other.user_id <> current_user_id
    where c.owner_id = current_user_id
  ) then
    raise exception 'Transfer the circles you own to another member first'
      using errcode = '55000';
  end if;

  -- Circles nobody else is in go with the account, channels included.
  delete from public.conversations conv
  where conv.id in (
    select ct.conversation_id
    from public.conversation_threads ct
    join public.circle_channels cc
      on cc.conversation_id = ct.parent_conversation_id
    join public.circles c on c.id = cc.circle_id
    where c.owner_id = current_user_id
    union all
    select cc.conversation_id
    from public.circle_channels cc
    join public.circles c on c.id = cc.circle_id
    where c.owner_id = current_user_id
  );

  delete from public.circles c where c.owner_id = current_user_id;

  -- Groups they solely own pass to the member who joined first.
  update public.conversation_members cm
  set role = 'owner'
  from (
    select distinct on (other.conversation_id)
      other.conversation_id,
      other.user_id
    from public.conversation_members mine
    join public.conversations c
      on c.id = mine.conversation_id
      and c.type = 'group'
    join public.conversation_members other
      on other.conversation_id = mine.conversation_id
      and other.user_id <> current_user_id
    where mine.user_id = current_user_id
      and mine.role = 'owner'
      and not exists (
        select 1
        from public.conversation_members co_owner
        where co_owner.conversation_id = mine.conversation_id
          and co_owner.role = 'owner'
          and co_owner.user_id <> current_user_id
      )
    order by other.conversation_id, other.joined_at, other.user_id
  ) heir
  where cm.conversation_id = heir.conversation_id
    and cm.user_id = heir.user_id;

  delete from public.voice_states vs where vs.user_id = current_user_id;

  for membership in
    select cm.circle_id
    from public.circle_members cm
    where cm.user_id = current_user_id
  loop
    perform public.remove_circle_member_rows(
      membership.circle_id,
      current_user_id
    );
  end loop;

  delete from public.conversation_members cm
  using public.conversations c
  where c.id = cm.conversation_id
    and c.type = 'group'
    and cm.user_id = current_user_id;

  delete from public.friendships f
  where current_user_id in (f.user_low_id, f.user_high_id);

  delete from public.friend_requests fr
  where current_user_id in (fr.requester_id, fr.receiver_id);

  delete from public.blocks b
  where current_user_id in (b.blocker_id, b.blocked_id);

  delete from public.contact_aliases ca
  where current_user_id in (ca.owner_id, ca.friend_id);

  delete from public.user_privacy_settings ups
  where ups.user_id = current_user_id;

  delete from public.circle_post_likes l where l.user_id = current_user_id;

  update public.profiles p
  set
    username = 'deleted_' || substr(replace(p.id::text, '-', ''), 1, 15),
    display_name = 'Deleted User',
    avatar_url = null,
    bio = '',
    status_emoji = null,
    status_text = null,
    status_expires_at = null,
    deleted_at = coalesce(p.deleted_at, now()),
    updated_at = now()
  where p.id = current_user_id;
end;
$$;

revoke execute on function public.prepare_account_deletion() from public;
revoke execute on function public.prepare_account_deletion() from anon;
grant execute on function public.prepare_account_deletion() to authenticated;

-- Same as 202605190002_fix_identity_safety_blocking, but a deleted
-- account counts as blocked: nobody can message it.
create or replace function public.is_current_user_blocked_in_conversation(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.conversations c
    join public.conversation_members current_member
      on current_member.conversation_id = c.id
      and current_member.user_id = auth.uid()
    join public.conversation_members other_member
      on other_member.conversation_id = c.id
      and other_member.user_id <> auth.uid()
    join public.profiles other_profile
      on other_profile.id = other_member.user_id
    where c.id = target_conversation_id
      and c.type = 'direct'
      and (
        public.are_users_blocked(auth.uid(), other_member.user_id)
        or other_profile.deleted_at is not null
      )
  );
$$;

create or replace function public.reject_friend_request_to_deleted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.profiles p
    where p.id in (new.requester_id, new.receiver_id)
      and p.deleted_at is not null
  ) then
    raise exception 'This account was deleted' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function public.reject_friend_request_to_deleted() from public;

drop trigger if exists friend_requests_reject_deleted on public.friend_requests;
create trigger friend_requests_reject_deleted
  before insert on public.friend_requests
  for each row execute function public.reject_friend_request_to_deleted();
