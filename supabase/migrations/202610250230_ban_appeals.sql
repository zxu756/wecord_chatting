-- Moderator tools 2.0 (C5), part 4 of 9: appealing a ban.
--
-- A banned person can send the circle's moderators one appeal per ban, with a
-- message. The moderators who can ban (ban_members) see it in the Review
-- queue and approve it (the ban is lifted; the person still has to join
-- again by the circle's rules) or deny it, with an optional note the person
-- reads. "Per ban" means per circle_bans.created_at: a ban that is renewed
-- (a new ban over the old one) is a new ban and may be appealed again, and
-- the appeal of the old one is closed.
--
-- * circle_ban_appeals: the appeals; closed to clients, RPCs only.
-- * my_circle_bans(): the circles the caller is banned from, with when the
--   ban ends and how their appeal stands. The moderators' reason is NOT part
--   of it (the ban dialog promises "only moderators see it").
-- * submit_ban_appeal / list_ban_appeals / count_ban_appeals /
--   decide_ban_appeal. Deciding is audited (ban_appeal_approve /
--   ban_appeal_deny) and cannot overturn a ban made by somebody who still
--   ranks above the decider. All of it is refused while a platform admin
--   has the circle down (K1).
-- * list_circle_bans (202610140004) is rewritten to show when each ban ends
--   and whether it has a waiting appeal. Its other columns are as they were.

create table if not exists public.circle_ban_appeals (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  -- circle_bans.created_at of the ban this is about.
  ban_created_at timestamptz not null,
  message text not null check (char_length(btrim(message)) between 1 and 1000),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'denied', 'closed')),
  decided_by uuid references public.profiles(id) on delete set null,
  decided_at timestamptz,
  note text check (note is null or char_length(note) <= 500),
  created_at timestamptz not null default now(),
  -- The decision's push was handed to scheduled-dispatch (once).
  push_claimed_at timestamptz,
  constraint circle_ban_appeals_once_per_ban
    unique (circle_id, user_id, ban_created_at)
);

create index if not exists circle_ban_appeals_queue_idx
  on public.circle_ban_appeals (circle_id, created_at desc)
  where status = 'pending';

create index if not exists circle_ban_appeals_unpushed_idx
  on public.circle_ban_appeals (decided_at)
  where push_claimed_at is null and status in ('approved', 'denied');

alter table public.circle_ban_appeals enable row level security;
revoke all on public.circle_ban_appeals from public, anon, authenticated;

-- A ban that is lifted by any route closes the appeal waiting on it; a ban
-- that is made again closes the appeal of the old one.
create or replace function public.close_ban_appeals()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    update public.circle_ban_appeals a
    set status = 'closed', decided_at = now()
    where a.circle_id = old.circle_id
      and a.user_id = old.user_id
      and a.status = 'pending';
    return old;
  end if;

  if new.created_at is distinct from old.created_at then
    update public.circle_ban_appeals a
    set status = 'closed', decided_at = now()
    where a.circle_id = new.circle_id
      and a.user_id = new.user_id
      and a.status = 'pending'
      and a.ban_created_at <> new.created_at;
  end if;
  return new;
end;
$$;

revoke execute on function public.close_ban_appeals()
  from public, anon, authenticated;

drop trigger if exists circle_bans_close_appeals_delete on public.circle_bans;
create trigger circle_bans_close_appeals_delete
  after delete on public.circle_bans
  for each row execute function public.close_ban_appeals();

drop trigger if exists circle_bans_close_appeals_update on public.circle_bans;
create trigger circle_bans_close_appeals_update
  after update on public.circle_bans
  for each row execute function public.close_ban_appeals();

-- The circles the caller is banned from (bans that have not ended, circles
-- that are up): {circle_id, circle_name, circle_avatar_url, banned_at,
-- expires_at, appeal_id, appeal_status, appeal_note, appeal_decided_at}.
create or replace function public.my_circle_bans()
returns table (
  circle_id uuid,
  circle_name text,
  circle_avatar_url text,
  banned_at timestamptz,
  expires_at timestamptz,
  appeal_id uuid,
  appeal_status text,
  appeal_note text,
  appeal_decided_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    c.name,
    c.avatar_url,
    b.created_at,
    b.expires_at,
    a.id,
    a.status,
    a.note,
    a.decided_at
  from public.circle_bans b
  join public.circles c on c.id = b.circle_id
  left join public.circle_ban_appeals a
    on a.circle_id = b.circle_id
    and a.user_id = b.user_id
    and a.ban_created_at = b.created_at
  where b.user_id = auth.uid()
    and (b.expires_at is null or b.expires_at > now())
    and c.disabled_at is null
  order by b.created_at desc;
$$;

create or replace function public.submit_ban_appeal(
  target_circle_id uuid,
  appeal_message text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  ban_row public.circle_bans%rowtype;
  trimmed text := btrim(coalesce(appeal_message, ''));
  new_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  perform public.assert_circle_up(target_circle_id);

  select b.* into ban_row
  from public.circle_bans b
  where b.circle_id = target_circle_id
    and b.user_id = current_user_id
    and (b.expires_at is null or b.expires_at > now());

  if ban_row.user_id is null then
    raise exception 'You are not banned from this circle' using errcode = 'P0002';
  end if;

  if char_length(trimmed) not between 1 and 1000 then
    raise exception 'An appeal is 1 to 1000 characters' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.circle_ban_appeals a
    where a.circle_id = target_circle_id
      and a.user_id = current_user_id
      and a.ban_created_at = ban_row.created_at
  ) then
    raise exception 'You have already appealed this ban' using
      errcode = '23505', detail = 'appeal_used';
  end if;

  insert into public.circle_ban_appeals (
    circle_id, user_id, ban_created_at, message
  )
  values (target_circle_id, current_user_id, ban_row.created_at, trimmed)
  returning id into new_id;

  perform public.write_circle_audit(
    target_circle_id,
    'ban_appeal_submit',
    'member',
    current_user_id,
    public.circle_member_label(target_circle_id, current_user_id),
    '{}'::jsonb
  );

  return new_id;
end;
$$;

create or replace function public.count_ban_appeals(target_circle_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select case
    when public.current_user_has_circle_permission(target_circle_id, 'ban_members')
    then (
      select count(*)::integer
      from public.circle_ban_appeals a
      where a.circle_id = target_circle_id
        and a.status = 'pending'
    )
    else 0
  end;
$$;

create or replace function public.list_ban_appeals(target_circle_id uuid)
returns table (
  id uuid,
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  message text,
  ban_reason text,
  banned_at timestamptz,
  ban_expires_at timestamptz,
  banned_by_name text,
  created_at timestamptz
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
  if not public.current_user_has_circle_permission(
    target_circle_id, 'ban_members'
  ) then
    raise exception 'Only members who can ban members can see appeals'
      using errcode = '42501';
  end if;

  return query
  select
    a.id,
    a.user_id,
    p.username,
    p.display_name,
    p.avatar_url,
    a.message,
    b.reason,
    b.created_at,
    b.expires_at,
    case
      when b.banned_by is null then null
      else public.circle_member_label(target_circle_id, b.banned_by)
    end,
    a.created_at
  from public.circle_ban_appeals a
  join public.profiles p on p.id = a.user_id
  join public.circle_bans b
    on b.circle_id = a.circle_id
    and b.user_id = a.user_id
    and b.created_at = a.ban_created_at
  where a.circle_id = target_circle_id
    and a.status = 'pending'
  order by a.created_at;
end;
$$;

create or replace function public.decide_ban_appeal(
  target_appeal_id uuid,
  approve boolean,
  decision_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  appeal_row public.circle_ban_appeals%rowtype;
  ban_row public.circle_bans%rowtype;
  trimmed_note text := nullif(btrim(coalesce(decision_note, '')), '');
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select a.* into appeal_row
  from public.circle_ban_appeals a
  where a.id = target_appeal_id
  for update;

  if appeal_row.id is null then
    raise exception 'Appeal not found' using errcode = 'P0002';
  end if;

  if not public.current_user_has_circle_permission(
    appeal_row.circle_id, 'ban_members'
  ) then
    raise exception 'Only members who can ban members can decide appeals'
      using errcode = '42501';
  end if;

  perform public.assert_circle_up(appeal_row.circle_id);

  if appeal_row.status <> 'pending' then
    raise exception 'This appeal was already decided' using
      errcode = '55000', detail = 'appeal_decided';
  end if;

  if trimmed_note is not null and char_length(trimmed_note) > 500 then
    raise exception 'A note is up to 500 characters' using errcode = '22023';
  end if;

  select b.* into ban_row
  from public.circle_bans b
  where b.circle_id = appeal_row.circle_id
    and b.user_id = appeal_row.user_id
    and b.created_at = appeal_row.ban_created_at;

  -- Somebody else lifted or renewed the ban meanwhile.
  if ban_row.user_id is null then
    update public.circle_ban_appeals a
    set status = 'closed', decided_at = now()
    where a.id = appeal_row.id;
    raise exception 'The ban has changed since this appeal' using
      errcode = '55000', detail = 'appeal_decided';
  end if;

  -- A ban from somebody who still ranks above the decider is theirs to lift.
  if approve
    and ban_row.banned_by is not null
    and ban_row.banned_by <> current_user_id
    and public.circle_member_rank(appeal_row.circle_id, ban_row.banned_by)
      > public.circle_member_rank(appeal_row.circle_id, current_user_id)
  then
    raise exception 'Cannot overturn a ban by a member ranked above you'
      using errcode = '42501';
  end if;

  update public.circle_ban_appeals a
  set
    status = case when approve then 'approved' else 'denied' end,
    decided_by = current_user_id,
    decided_at = now(),
    note = trimmed_note
  where a.id = appeal_row.id;

  if approve then
    -- Deleting the ban closes no other appeal: this one is already decided.
    delete from public.circle_bans b
    where b.circle_id = appeal_row.circle_id
      and b.user_id = appeal_row.user_id;
  end if;

  perform public.write_circle_audit(
    appeal_row.circle_id,
    case when approve then 'ban_appeal_approve' else 'ban_appeal_deny' end,
    'member',
    appeal_row.user_id,
    public.circle_member_label(appeal_row.circle_id, appeal_row.user_id),
    jsonb_strip_nulls(jsonb_build_object('note', trimmed_note))
  );

  perform public.wake_scheduled_dispatch();
end;
$$;

-- list_circle_bans: 202610140004 plus when the ban ends and a waiting appeal.
drop function if exists public.list_circle_bans(uuid);

create or replace function public.list_circle_bans(target_circle_id uuid)
returns table (
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  reason text,
  banned_by_name text,
  created_at timestamptz,
  expires_at timestamptz,
  appeal_status text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.current_user_has_circle_permission(
    target_circle_id,
    'ban_members'
  ) then
    raise exception 'Only members who can ban members can see bans'
      using errcode = '42501';
  end if;

  return query
  select
    b.user_id,
    p.username,
    p.display_name,
    p.avatar_url,
    b.reason,
    case
      when b.banned_by is null then null
      else public.circle_member_label(target_circle_id, b.banned_by)
    end,
    b.created_at,
    b.expires_at,
    a.status
  from public.circle_bans b
  join public.profiles p on p.id = b.user_id
  left join public.circle_ban_appeals a
    on a.circle_id = b.circle_id
    and a.user_id = b.user_id
    and a.ban_created_at = b.created_at
  where b.circle_id = target_circle_id
    and (b.expires_at is null or b.expires_at > now())
  order by b.created_at desc;
end;
$$;

revoke execute on function public.my_circle_bans() from public, anon;
revoke execute on function public.submit_ban_appeal(uuid, text) from public, anon;
revoke execute on function public.count_ban_appeals(uuid) from public, anon;
revoke execute on function public.list_ban_appeals(uuid) from public, anon;
revoke execute on function public.decide_ban_appeal(uuid, boolean, text) from public, anon;
revoke execute on function public.list_circle_bans(uuid) from public, anon;
grant execute on function public.my_circle_bans() to authenticated;
grant execute on function public.submit_ban_appeal(uuid, text) to authenticated;
grant execute on function public.count_ban_appeals(uuid) to authenticated;
grant execute on function public.list_ban_appeals(uuid) to authenticated;
grant execute on function public.decide_ban_appeal(uuid, boolean, text) to authenticated;
grant execute on function public.list_circle_bans(uuid) to authenticated;
