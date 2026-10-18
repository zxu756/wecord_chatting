-- Invite tracking (C4), part 1 of 3: which invite, and which member, brought
-- each person into a circle.
--
-- circle_members gains two columns:
--
--   * joined_via_invite  the invite link's code, when the person joined with
--                        a link (including the 7-day contact card, which
--                        carries a link, and a request an invite link made
--                        that a moderator approved later);
--   * invited_by         the member behind it: the link's creator, or the
--                        member who added the person as a friend
--                        (invite_circle_members, also when that made a
--                        request that was approved later).
--
-- Both stay null for people who joined from Discover, by creating the circle,
-- or before this migration.
--
-- Nothing is rewritten. The three join paths of 202610220610 (C1) keep their
-- definitions; the columns are filled by triggers that watch what those paths
-- already do:
--
--   * accept_circle_invite spends the invite with "use_count = use_count + 1"
--     after it has added the member, or after it has made a request (apply
--     mode). The trigger on circle_invites credits the signed-in person: the
--     member row made in this very transaction, otherwise their waiting
--     request (circle_join_requests.invite_code, new).
--   * decide_join_request adds the approved person while the request is
--     still pending, so a BEFORE INSERT trigger on circle_members copies the
--     request's invite or inviter onto the new member. Only when somebody
--     else decides: nobody approves their own request.
--   * invite_circle_members writes a 'member_add' audit entry listing the
--     people it added, as the member who added them; a trigger on the audit
--     log credits exactly those (members made in this transaction).
--
-- A person who joins, leaves and joins again is credited each time: the log
-- circle_invite_joins keeps one row per joining (circle, person, time), so
-- "brought" keeps counting people who left, and "still here" asks whether the
-- member row of that very joining still exists.

alter table public.circle_members
  add column if not exists joined_via_invite text,
  add column if not exists invited_by uuid references public.profiles(id) on delete set null;

create index if not exists circle_members_invite_idx
  on public.circle_members (circle_id, joined_via_invite)
  where joined_via_invite is not null;

alter table public.circle_join_requests
  add column if not exists invite_code text;

-- ---------------------------------------------------------------------------
-- The log
-- ---------------------------------------------------------------------------

create table if not exists public.circle_invite_joins (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  -- Null once the account is gone; the joining still counts.
  user_id uuid references public.profiles(id) on delete set null,
  -- circle_members.created_at of the joining this row is about.
  joined_at timestamptz not null,
  invite_code text,
  invited_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create unique index if not exists circle_invite_joins_joining_idx
  on public.circle_invite_joins (circle_id, user_id, joined_at);

create index if not exists circle_invite_joins_circle_idx
  on public.circle_invite_joins (circle_id, joined_at desc);

-- Read through the RPCs only.
alter table public.circle_invite_joins enable row level security;
revoke all on public.circle_invite_joins from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Credit a link's use (accept_circle_invite)
-- ---------------------------------------------------------------------------

create or replace function public.circle_invite_credit_use()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  who uuid := auth.uid();
  credited integer;
begin
  if who is null then
    return null;
  end if;

  -- Joined at once: the member row made by this transaction.
  update public.circle_members cm
  set joined_via_invite = new.code,
      invited_by = new.created_by
  where cm.circle_id = new.circle_id
    and cm.user_id = who
    and cm.joined_via_invite is null
    and cm.invited_by is null
    and cm.created_at = now();
  get diagnostics credited = row_count;

  -- Applied instead: the request remembers the link for the approval.
  if credited = 0 then
    update public.circle_join_requests r
    set invite_code = new.code
    where r.circle_id = new.circle_id
      and r.user_id = who
      and r.status = 'pending'
      and r.invite_code is null;
  end if;

  return null;
end;
$$;

revoke execute on function public.circle_invite_credit_use()
  from public, anon, authenticated;

drop trigger if exists circle_invites_credit_use on public.circle_invites;
create trigger circle_invites_credit_use
  after update of use_count on public.circle_invites
  for each row
  when (new.use_count > old.use_count)
  execute function public.circle_invite_credit_use();

-- ---------------------------------------------------------------------------
-- Credit an approval (decide_join_request)
-- ---------------------------------------------------------------------------

create or replace function public.circle_members_credit_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  request public.circle_join_requests%rowtype;
begin
  if new.joined_via_invite is not null
    or new.invited_by is not null
    or auth.uid() is null
    or auth.uid() = new.user_id
  then
    return new;
  end if;

  select r.* into request
  from public.circle_join_requests r
  where r.circle_id = new.circle_id
    and r.user_id = new.user_id
    and r.status = 'pending'
  limit 1;

  if request.id is null then
    return new;
  end if;

  if request.invite_code is not null then
    new.joined_via_invite := request.invite_code;
    new.invited_by := (
      select ci.created_by
      from public.circle_invites ci
      where ci.code = request.invite_code
    );
  elsif request.invited_by is not null then
    new.invited_by := request.invited_by;
  end if;

  return new;
end;
$$;

revoke execute on function public.circle_members_credit_request()
  from public, anon, authenticated;

drop trigger if exists circle_members_credit_request on public.circle_members;
create trigger circle_members_credit_request
  before insert on public.circle_members
  for each row execute function public.circle_members_credit_request();

-- ---------------------------------------------------------------------------
-- Credit friends added by a member (invite_circle_members)
-- ---------------------------------------------------------------------------

create or replace function public.circle_audit_credit_member_add()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.actor_id is null or jsonb_typeof(new.changes -> 'members') <> 'array' then
    return null;
  end if;

  update public.circle_members cm
  set invited_by = new.actor_id
  where cm.circle_id = new.circle_id
    and cm.user_id in (
      select (member.value ->> 'id')::uuid
      from jsonb_array_elements(new.changes -> 'members') member(value)
      where member.value ->> 'id' ~* '^[0-9a-f-]{36}$'
    )
    and cm.user_id <> new.actor_id
    and cm.joined_via_invite is null
    and cm.invited_by is null
    and cm.created_at = now();

  return null;
end;
$$;

revoke execute on function public.circle_audit_credit_member_add()
  from public, anon, authenticated;

drop trigger if exists circle_audit_log_credit_member_add on public.circle_audit_log;
create trigger circle_audit_log_credit_member_add
  after insert on public.circle_audit_log
  for each row
  when (new.action = 'member_add')
  execute function public.circle_audit_credit_member_add();

-- ---------------------------------------------------------------------------
-- The log follows the columns
-- ---------------------------------------------------------------------------

create or replace function public.circle_members_log_invite()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.circle_invite_joins (
    circle_id, user_id, joined_at, invite_code, invited_by
  )
  values (
    new.circle_id, new.user_id, new.created_at,
    new.joined_via_invite, new.invited_by
  )
  on conflict (circle_id, user_id, joined_at) do update
  set invite_code = excluded.invite_code,
      invited_by = excluded.invited_by;
  return null;
end;
$$;

revoke execute on function public.circle_members_log_invite()
  from public, anon, authenticated;

drop trigger if exists circle_members_log_invite_insert on public.circle_members;
create trigger circle_members_log_invite_insert
  after insert on public.circle_members
  for each row
  when (new.joined_via_invite is not null or new.invited_by is not null)
  execute function public.circle_members_log_invite();

drop trigger if exists circle_members_log_invite_update on public.circle_members;
create trigger circle_members_log_invite_update
  after update of joined_via_invite, invited_by on public.circle_members
  for each row
  when (new.joined_via_invite is not null or new.invited_by is not null)
  execute function public.circle_members_log_invite();

-- ---------------------------------------------------------------------------
-- Per invite numbers for the invite list
-- ---------------------------------------------------------------------------

-- "Brought 12 · still here 9" for each invite the caller can see in
-- list_circle_invites (everyone's with manage_channels, their own with
-- create_invites). [brought] counts the people who joined with the invite,
-- also those who left since; [remaining] those still in the circle from that
-- joining. Invites that brought nobody are listed with zeros.
create or replace function public.get_circle_invite_stats(target_circle_id uuid)
returns table (
  code text,
  brought integer,
  remaining integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  return query
  select
    ci.code,
    count(j.id)::integer,
    count(j.id) filter (
      where exists (
        select 1
        from public.circle_members cm
        where cm.circle_id = j.circle_id
          and cm.user_id = j.user_id
          and cm.created_at = j.joined_at
      )
    )::integer
  from public.circle_invites ci
  left join public.circle_invite_joins j
    on j.circle_id = ci.circle_id and j.invite_code = ci.code
  where ci.circle_id = target_circle_id
    and (
      public.current_user_has_circle_permission(target_circle_id, 'manage_channels')
      or (
        ci.created_by = auth.uid()
        and public.current_user_has_circle_permission(
          target_circle_id,
          'create_invites'
        )
      )
    )
  group by ci.code;
end;
$$;

revoke execute on function public.get_circle_invite_stats(uuid) from public, anon;
grant execute on function public.get_circle_invite_stats(uuid) to authenticated;
