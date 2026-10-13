-- Shareable circle invite links. Codes are 10 characters from a 32-letter
-- alphabet without look-alike characters (no 0/o/1/l), so they survive being
-- read aloud or retyped. Rows are only written by the RPCs below.
create table if not exists public.circle_invites (
  code text primary key,
  circle_id uuid not null references public.circles(id) on delete cascade,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  max_uses integer,
  use_count integer not null default 0,
  revoked_at timestamptz,
  constraint circle_invites_code_format check (code ~ '^[a-z2-9]{10}$'),
  constraint circle_invites_max_uses_check check (
    max_uses is null or max_uses between 1 and 1000
  ),
  constraint circle_invites_use_count_check check (use_count >= 0)
);

create index if not exists circle_invites_circle_created_at_idx
  on public.circle_invites (circle_id, created_at desc);

alter table public.circle_invites enable row level security;

drop policy if exists circle_invites_select_manager on public.circle_invites;
create policy circle_invites_select_manager
  on public.circle_invites for select
  to authenticated
  using (public.current_user_circle_role(circle_id) in ('owner', 'admin'));

create or replace function public.generate_circle_invite_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  -- 32 symbols, so each random byte maps without modulo bias.
  alphabet constant text := 'abcdefghijkmnpqrstuvwxyz23456789';
  random_bytes bytea := extensions.gen_random_bytes(10);
  generated_code text := '';
begin
  for byte_index in 0..9 loop
    generated_code := generated_code
      || substr(alphabet, (get_byte(random_bytes, byte_index) % 32) + 1, 1);
  end loop;
  return generated_code;
end;
$$;

-- Why an invite can no longer be used, or null while it is still valid.
create or replace function public.circle_invite_invalid_reason(
  invite_row public.circle_invites
)
returns text
language sql
stable
set search_path = public
as $$
  select case
    when invite_row.revoked_at is not null then 'revoked'
    when invite_row.expires_at is not null
      and invite_row.expires_at <= now() then 'expired'
    when invite_row.max_uses is not null
      and invite_row.use_count >= invite_row.max_uses then 'exhausted'
    else null
  end;
$$;

revoke execute on function public.generate_circle_invite_code() from public;
revoke execute on function public.generate_circle_invite_code() from anon;
revoke execute on function public.generate_circle_invite_code() from authenticated;
revoke execute on function public.circle_invite_invalid_reason(public.circle_invites) from public;
revoke execute on function public.circle_invite_invalid_reason(public.circle_invites) from anon;
revoke execute on function public.circle_invite_invalid_reason(public.circle_invites) from authenticated;

create or replace function public.create_circle_invite(
  target_circle_id uuid,
  expires_in_hours integer default null,
  max_uses integer default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  caller_role text;
  created_code text;
  attempt integer := 0;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select public.current_user_circle_role(target_circle_id) into caller_role;

  if caller_role is null or caller_role not in ('owner', 'admin') then
    raise exception 'Only circle owners and admins can create invites'
      using errcode = '42501';
  end if;

  if expires_in_hours is not null
    and (expires_in_hours < 1 or expires_in_hours > 8760)
  then
    raise exception 'Invite expiry must be between 1 hour and 1 year'
      using errcode = '22023';
  end if;

  if create_circle_invite.max_uses is not null
    and (create_circle_invite.max_uses < 1 or create_circle_invite.max_uses > 1000)
  then
    raise exception 'Invite max uses must be between 1 and 1000'
      using errcode = '22023';
  end if;

  loop
    attempt := attempt + 1;
    begin
      insert into public.circle_invites (
        code,
        circle_id,
        created_by,
        expires_at,
        max_uses
      )
      values (
        public.generate_circle_invite_code(),
        target_circle_id,
        current_user_id,
        case
          when expires_in_hours is null then null
          else now() + make_interval(hours => expires_in_hours)
        end,
        create_circle_invite.max_uses
      )
      returning code into created_code;
      return created_code;
    exception
      when unique_violation then
        if attempt >= 5 then
          raise;
        end if;
    end;
  end loop;
end;
$$;

-- Active invites only: revoked, expired and used-up links drop off the list.
create or replace function public.list_circle_invites(target_circle_id uuid)
returns table (
  code text,
  circle_id uuid,
  created_by uuid,
  created_by_name text,
  created_at timestamptz,
  expires_at timestamptz,
  max_uses integer,
  use_count integer
)
language sql
stable
security definer
set search_path = public
as $$
  select
    ci.code,
    ci.circle_id,
    ci.created_by,
    creator.display_name as created_by_name,
    ci.created_at,
    ci.expires_at,
    ci.max_uses,
    ci.use_count
  from public.circle_invites ci
  left join public.profiles creator on creator.id = ci.created_by
  where auth.uid() is not null
    and ci.circle_id = target_circle_id
    and public.current_user_circle_role(target_circle_id) in ('owner', 'admin')
    and public.circle_invite_invalid_reason(ci) is null
  order by ci.created_at desc, ci.code;
$$;

create or replace function public.revoke_circle_invite(invite_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_invite public.circle_invites%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select *
  into target_invite
  from public.circle_invites
  where code = lower(trim(coalesce(invite_code, '')))
  for update;

  if target_invite.code is null
    or coalesce(
      public.current_user_circle_role(target_invite.circle_id),
      ''
    ) not in ('owner', 'admin')
  then
    raise exception 'Invite not found or caller cannot revoke invites'
      using errcode = '42501';
  end if;

  update public.circle_invites
  set revoked_at = now()
  where code = target_invite.code
    and revoked_at is null;
end;
$$;

-- Any signed-in user may preview a code. Circle details are only included
-- while the invite is usable (or the caller is already a member), and an
-- invite whose creator and caller have blocked each other reads as not_found.
create or replace function public.get_circle_invite_preview(invite_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_code text := lower(trim(coalesce(invite_code, '')));
  target_invite public.circle_invites%rowtype;
  invalid_reason text;
  is_member boolean;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select *
  into target_invite
  from public.circle_invites
  where code = normalized_code;

  if target_invite.code is null
    or public.are_users_blocked(target_invite.created_by, current_user_id)
  then
    return jsonb_build_object(
      'code', normalized_code,
      'invalid_reason', 'not_found',
      'already_member', false,
      'circle', null
    );
  end if;

  invalid_reason := public.circle_invite_invalid_reason(target_invite);
  is_member := exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = target_invite.circle_id
      and cm.user_id = current_user_id
  );

  return jsonb_build_object(
    'code', target_invite.code,
    'invalid_reason', invalid_reason,
    'already_member', is_member,
    'expires_at', target_invite.expires_at,
    'circle', case
      when invalid_reason is null or is_member then (
        select jsonb_build_object(
          'id', c.id,
          'name', c.name,
          'avatar_url', c.avatar_url,
          'member_count', (
            select count(*)
            from public.circle_members cm
            where cm.circle_id = c.id
          )
        )
        from public.circles c
        where c.id = target_invite.circle_id
      )
      else null
    end
  );
end;
$$;

-- Joins the circle and every channel conversation the same way
-- invite_circle_members does. Accepting again as a member is a no-op that
-- returns the circle id without spending a use.
create or replace function public.accept_circle_invite(invite_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_invite public.circle_invites%rowtype;
  invalid_reason text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select *
  into target_invite
  from public.circle_invites
  where code = lower(trim(coalesce(invite_code, '')))
  for update;

  if target_invite.code is null
    or public.are_users_blocked(target_invite.created_by, current_user_id)
  then
    raise exception 'Invite not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = target_invite.circle_id
      and cm.user_id = current_user_id
  ) then
    return target_invite.circle_id;
  end if;

  invalid_reason := public.circle_invite_invalid_reason(target_invite);
  if invalid_reason is not null then
    raise exception 'Invite is %', invalid_reason using errcode = '22023';
  end if;

  insert into public.circle_members (circle_id, user_id, role)
  values (target_invite.circle_id, current_user_id, 'member')
  on conflict do nothing;

  insert into public.conversation_members (conversation_id, user_id, role)
  select cc.conversation_id, current_user_id, 'member'
  from public.circle_channels cc
  where cc.circle_id = target_invite.circle_id
  on conflict do nothing;

  update public.circle_invites
  set use_count = use_count + 1
  where code = target_invite.code;

  return target_invite.circle_id;
end;
$$;

grant execute on function public.create_circle_invite(uuid, integer, integer) to authenticated;
grant execute on function public.list_circle_invites(uuid) to authenticated;
grant execute on function public.revoke_circle_invite(text) to authenticated;
grant execute on function public.get_circle_invite_preview(text) to authenticated;
grant execute on function public.accept_circle_invite(text) to authenticated;
