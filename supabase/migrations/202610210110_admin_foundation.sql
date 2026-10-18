-- Admin console (K1), part 1 of 3: who the platform admins are, the audit
-- log, the columns that report handling needs, and user suspensions.
-- Part 2 (202610210120) enforces circle take-downs; part 3 (202610210130)
-- holds the admin RPCs.
--
-- * app_admins(user_id, role owner|moderator|support): the people who run
--   the platform. Nobody can read or write the table through the API; only
--   is_app_admin(), admin_my_role() and the admin RPCs look at it. The first
--   owner is added by hand in the SQL editor, never in a migration.
-- * admin_audit_log: every admin action, written by the admin RPCs.
--   Readable through admin_list_audit_log only.
-- * reports: handled_by, handled_at, resolution, and snapshot, a copy of
--   what was reported (the profile, the circle or the post as it was when
--   the report came in). Admins read the snapshot, never the live content,
--   so they see nothing but what was reported. A trigger fills it, so the
--   three report_* functions stay as they are. Messages reports (A1) add a
--   branch to report_kind and report_snapshot.
-- * app_user_suspensions(user_id, until, reason): a suspended person. The
--   Auth ban (admin Edge Function) is what stops sign-in; the table is what
--   the database checks for a token that is still valid.
-- * circles.disabled_at / disabled_mode / disabled_reason: a circle taken
--   down by an admin, enforced by part 2.

-- ---------------------------------------------------------------------------
-- Admins
-- ---------------------------------------------------------------------------

create table if not exists public.app_admins (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  role text not null check (role in ('owner', 'moderator', 'support')),
  created_at timestamptz not null default now()
);

alter table public.app_admins enable row level security;
revoke all on public.app_admins from public, anon, authenticated;

-- The caller's admin role, or null.
create or replace function public.admin_my_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select a.role
  from public.app_admins a
  where a.user_id = auth.uid();
$$;

create or replace function public.is_app_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.app_admins a
    where a.user_id = auth.uid()
  );
$$;

revoke execute on function public.admin_my_role() from public, anon;
revoke execute on function public.is_app_admin() from public, anon;
grant execute on function public.admin_my_role() to authenticated;
grant execute on function public.is_app_admin() to authenticated;

-- Raises unless the caller is an admin with one of [allowed_roles]
-- (42501). Returns the caller's role. Used by every admin RPC.
create or replace function public.admin_require(allowed_roles text[])
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  caller_role text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select a.role into caller_role
  from public.app_admins a
  where a.user_id = auth.uid();
  if caller_role is null or not (caller_role = any (allowed_roles)) then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  return caller_role;
end;
$$;

revoke execute on function public.admin_require(text[]) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Audit log
-- ---------------------------------------------------------------------------

create table if not exists public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  actor_role text not null,
  action text not null check (char_length(action) between 1 and 60),
  target_type text not null check (
    target_type in ('report', 'user', 'circle', 'circle_post', 'message')
  ),
  target_id uuid,
  report_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists admin_audit_log_created_idx
  on public.admin_audit_log (created_at desc);
create index if not exists admin_audit_log_target_idx
  on public.admin_audit_log (target_type, target_id, created_at desc);

alter table public.admin_audit_log enable row level security;
revoke all on public.admin_audit_log from public, anon, authenticated;

-- Writes one audit entry as the caller. Internal: only the admin RPCs call
-- it (they have checked the role already).
create or replace function public.admin_write_audit(
  audit_action text,
  audit_target_type text,
  audit_target_id uuid,
  audit_report_id uuid default null,
  audit_details jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  entry_id uuid;
begin
  insert into public.admin_audit_log (
    actor_id, actor_role, action, target_type, target_id, report_id, details
  )
  select
    a.user_id, a.role, audit_action, audit_target_type, audit_target_id,
    audit_report_id, coalesce(audit_details, '{}'::jsonb)
  from public.app_admins a
  where a.user_id = auth.uid()
  returning id into entry_id;
  if entry_id is null then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  return entry_id;
end;
$$;

revoke execute on function public.admin_write_audit(text, text, uuid, uuid, jsonb)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Reports
-- ---------------------------------------------------------------------------

alter table public.reports
  add column if not exists handled_by uuid
    references public.profiles(id) on delete set null,
  add column if not exists handled_at timestamptz,
  add column if not exists resolution text,
  add column if not exists snapshot jsonb;

alter table public.reports
  drop constraint if exists reports_resolution_length;
alter table public.reports
  add constraint reports_resolution_length check (
    resolution is null or char_length(resolution) between 1 and 40
  );

create index if not exists reports_status_created_idx
  on public.reports (status, created_at desc);

-- What a report is about: 'post', 'circle' or 'user' today. Message
-- reports (A1) put their own branch in front of these.
create or replace function public.report_kind(r public.reports)
returns text
language sql
immutable
as $$
  select case
    when r.target_post_id is not null then 'post'
    when r.target_circle_id is not null then 'circle'
    else 'user'
  end;
$$;

revoke execute on function public.report_kind(public.reports)
  from public, anon, authenticated;

-- A copy of what is reported, as it is now: {kind, title, ...}. The title
-- is a short label for lists. Live content is read here, at report time,
-- and never again by the admin RPCs.
create or replace function public.report_snapshot(r public.reports)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  kind text := public.report_kind(r);
  result jsonb;
begin
  if kind = 'post' then
    select jsonb_build_object(
      'kind', 'post',
      'title', left(regexp_replace(p.body, '\s+', ' ', 'g'), 80),
      'post_id', p.id,
      'body', p.body,
      'attachment', p.attachment,
      'created_at', p.created_at,
      'circle_id', p.circle_id,
      'circle_name', c.name,
      'author_id', p.author_id,
      'author_username', a.username,
      'author_display_name', a.display_name
    ) into result
    from public.circle_posts p
    left join public.circles c on c.id = p.circle_id
    left join public.profiles a on a.id = p.author_id
    where p.id = r.target_post_id;
  elsif kind = 'circle' then
    select jsonb_build_object(
      'kind', 'circle',
      'title', c.name,
      'circle_id', c.id,
      'name', c.name,
      'avatar_url', c.avatar_url,
      'description', c.discovery_description,
      'is_public', c.is_public,
      'owner_id', c.owner_id,
      'owner_username', o.username,
      'member_count', (
        select count(*) from public.circle_members m where m.circle_id = c.id
      ),
      'created_at', c.created_at
    ) into result
    from public.circles c
    left join public.profiles o on o.id = c.owner_id
    where c.id = r.target_circle_id;
  else
    select jsonb_build_object(
      'kind', 'user',
      'title', p.display_name || ' (@' || p.username || ')',
      'user_id', p.id,
      'username', p.username,
      'display_name', p.display_name,
      'avatar_url', p.avatar_url,
      'bio', p.bio,
      'created_at', p.created_at
    ) into result
    from public.profiles p
    where p.id = r.target_user_id;
  end if;
  return coalesce(
    result,
    jsonb_build_object('kind', kind, 'title', '', 'missing', true)
  );
end;
$$;

revoke execute on function public.report_snapshot(public.reports)
  from public, anon, authenticated;

create or replace function public.reports_capture_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.snapshot is null then
    new.snapshot := public.report_snapshot(new);
  end if;
  return new;
end;
$$;

revoke execute on function public.reports_capture_snapshot()
  from public, anon, authenticated;

drop trigger if exists reports_capture_snapshot on public.reports;
create trigger reports_capture_snapshot
  before insert on public.reports
  for each row execute function public.reports_capture_snapshot();

-- Reports already filed get the best snapshot there still is.
update public.reports r
set snapshot = public.report_snapshot(r)
where r.snapshot is null;

-- ---------------------------------------------------------------------------
-- Suspended users
-- ---------------------------------------------------------------------------

create table if not exists public.app_user_suspensions (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  until timestamptz,
  reason text not null default '',
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint app_user_suspensions_reason_length check (char_length(reason) <= 500)
);

alter table public.app_user_suspensions enable row level security;
revoke all on public.app_user_suspensions from public, anon, authenticated;

-- Whether [target_user_id] is suspended right now (no end date: for good).
create or replace function public.is_user_suspended(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.app_user_suspensions s
    where s.user_id = target_user_id
      and (s.until is null or s.until > now())
  );
$$;

revoke execute on function public.is_user_suspended(uuid)
  from public, anon, authenticated;

-- Ends every session of [owner_id]: their refresh tokens die with them. For
-- the admin Edge Function (service role) only, after it has checked the
-- caller is an admin and banned the account.
create or replace function public.delete_all_user_sessions(owner_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  removed integer;
begin
  delete from auth.sessions s where s.user_id = owner_id;
  get diagnostics removed = row_count;
  return removed;
end;
$$;

revoke execute on function public.delete_all_user_sessions(uuid)
  from public, anon, authenticated;
grant execute on function public.delete_all_user_sessions(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Circles taken down
-- ---------------------------------------------------------------------------

-- 'delist': hidden from Discover and closed to new members; the members
--   keep using the circle. 'suspend': nobody can enter or read; members
--   see a "This circle was suspended" state.
alter table public.circles
  add column if not exists disabled_at timestamptz,
  add column if not exists disabled_mode text,
  add column if not exists disabled_reason text;

alter table public.circles
  drop constraint if exists circles_disabled_mode_check;
alter table public.circles
  add constraint circles_disabled_mode_check check (
    (disabled_at is null and disabled_mode is null)
    or (disabled_at is not null and disabled_mode in ('delist', 'suspend'))
  );

create index if not exists circles_disabled_idx
  on public.circles (disabled_at)
  where disabled_at is not null;
