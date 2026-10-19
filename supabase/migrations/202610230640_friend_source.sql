-- How a friendship started (A14): "added through a group chat", "scanned my
-- QR code", and so on, shown on the profile of a friend, and on the request
-- of someone who wants to be one.
--
-- friend_requests.source is what the sender's app says when it sends the
-- request (set_friend_request_source, called right after send_friend_request
-- from the place the request was made); friendships.source is copied from
-- the accepted request by a trigger when the friendship is made. Neither
-- send_friend_request nor accept_friend_request is rewritten.
--
-- Sources: search (found by username), qr (scanned a QR code), group (from
-- a member list of a group chat), card (from a contact card in a chat),
-- circle (from a circle's member list). A claim that can be checked is
-- checked: "group" needs a group chat the two share and "circle" a circle
-- they share, else the source is left empty. Old friendships have none.
-- Only the two people involved can see a source.

alter table public.friend_requests
  add column if not exists source text;
alter table public.friendships
  add column if not exists source text;

alter table public.friend_requests
  drop constraint if exists friend_requests_source_check;
alter table public.friend_requests
  add constraint friend_requests_source_check check (
    source is null or source in ('search', 'qr', 'group', 'card', 'circle')
  );
alter table public.friendships
  drop constraint if exists friendships_source_check;
alter table public.friendships
  add constraint friendships_source_check check (
    source is null or source in ('search', 'qr', 'group', 'card', 'circle')
  );

-- Remembers where my pending request to [target_user_id] came from. Quietly
-- does nothing when there is no such request, or the claim does not hold.
create or replace function public.set_friend_request_source(
  target_user_id uuid,
  source text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  claimed text := set_friend_request_source.source;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if claimed is null
    or claimed not in ('search', 'qr', 'group', 'card', 'circle')
  then
    return;
  end if;

  if claimed = 'group' and not exists (
    select 1
    from public.conversation_members mine
    join public.conversation_members theirs
      on theirs.conversation_id = mine.conversation_id
      and theirs.user_id = target_user_id
    join public.conversations c on c.id = mine.conversation_id
    where mine.user_id = me and c.type = 'group'
  ) then
    return;
  end if;

  if claimed = 'circle' and not exists (
    select 1
    from public.circle_members mine
    join public.circle_members theirs
      on theirs.circle_id = mine.circle_id
      and theirs.user_id = target_user_id
    where mine.user_id = me
  ) then
    return;
  end if;

  update public.friend_requests r
  set source = claimed
  where r.requester_id = me
    and r.receiver_id = target_user_id
    and r.status = 'pending';
end;
$$;

revoke execute on function public.set_friend_request_source(uuid, text)
  from public, anon;
grant execute on function public.set_friend_request_source(uuid, text)
  to authenticated;

-- A new friendship takes the source of the request that made it.
create or replace function public.friendships_copy_request_source()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.source is null then
    select r.source into new.source
    from public.friend_requests r
    where r.status = 'accepted'
      and least(r.requester_id, r.receiver_id) = new.user_low_id
      and greatest(r.requester_id, r.receiver_id) = new.user_high_id
    order by r.updated_at desc
    limit 1;
  end if;
  return new;
end;
$$;

drop trigger if exists friendships_copy_request_source on public.friendships;
create trigger friendships_copy_request_source
  before insert on public.friendships
  for each row execute function public.friendships_copy_request_source();
