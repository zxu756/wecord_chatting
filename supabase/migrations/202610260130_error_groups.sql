-- Error reports 2.0 (K5), part 1 of 2: grouping.
--
-- A device fingerprints a problem from the top five frames of its stack and
-- the message, so the same bug can be several fingerprints (a different
-- line, a different caller). The server adds one more name that is steadier:
-- the group, made of the kind of report, the type of the error and the FIRST
-- FRAME THAT IS WeCord'S OWN code (package:wecord/...). Digits and line
-- numbers do not count.
--
--   flutter_error | Bad state | _ChatState.build @ package:wecord/features/x.dart
--
-- A stack from a release build made with --split-debug-info has no names
-- (only addresses), so it has no app frame: those reports are grouped by the
-- kind, the type and the message, and `sh tool/errors_report.sh --symbolize`
-- turns them into named frames on the machine that kept the symbols.
--
-- * client_errors.group_key is filled by a before-insert trigger, so
--   report_client_errors() stays as it is. Rows already there get theirs
--   below.
-- * ops_error_groups remembers every group for 90 days after it was last
--   seen: the label, when and in which version it first showed up, and
--   whether the monitoring (K3) has already said "a new error" about it.
--   Groups that exist when this migration runs are marked as told, so the
--   first run does not raise an alert for every old error.
-- * admin_ops_error_groups(hours, max_rows) lists the biggest groups of the
--   last hours for the admin console: counts, the versions and when. No
--   message, no stack, no person.

alter table public.client_errors
  add column if not exists group_key text;

create index if not exists client_errors_group_idx
  on public.client_errors (group_key, created_at desc)
  where group_key is not null;

create table if not exists public.ops_error_groups (
  group_key text primary key check (group_key ~ '^[0-9a-f]{16}$'),
  label text not null,
  kind text not null,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  first_version text not null default '',
  last_version text not null default '',
  reports bigint not null default 0,
  alerted_at timestamptz
);

create index if not exists ops_error_groups_new_idx
  on public.ops_error_groups (first_seen_at)
  where alerted_at is null;

alter table public.ops_error_groups enable row level security;
revoke all on public.ops_error_groups from public, anon, authenticated;

-- The readable name of a group: "kind | type | function @ library", or
-- "kind | type | message" when the stack has no app frame.
create or replace function public.client_error_group_label(
  err_kind text,
  err_message text,
  err_stack text,
  err_context jsonb
)
returns text
language plpgsql
immutable
as $$
declare
  error_type text;
  frame text[];
  tail text;
begin
  error_type := nullif(btrim(coalesce(err_context->>'type', '')), '');
  if error_type is null then
    error_type := regexp_replace(left(coalesce(err_message, ''), 60), '[0-9]+', 'N', 'g');
  end if;
  error_type := left(regexp_replace(error_type, '\s+', ' ', 'g'), 80);

  frame := regexp_match(
    coalesce(err_stack, ''),
    '^#[0-9]+\s+(\S.*?)\s+\((package:wecord/[^:)\s]+)',
    'n'
  );
  if frame is not null then
    tail := left(frame[1], 80) || ' @ ' || left(frame[2], 100);
  else
    tail := left(regexp_replace(
      regexp_replace(coalesce(err_message, ''), '[0-9]+', 'N', 'g'),
      '\s+', ' ', 'g'
    ), 100);
  end if;
  return left(coalesce(err_kind, 'other') || ' | ' || error_type || ' | ' || tail, 300);
end;
$$;

revoke execute on function public.client_error_group_label(text, text, text, jsonb)
  from public, anon, authenticated;

create or replace function public.client_errors_set_group()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  label text;
begin
  label := public.client_error_group_label(new.kind, new.message, new.stack, new.context);
  new.group_key := substr(md5(label), 1, 16);

  insert into public.ops_error_groups as g (
    group_key, label, kind, first_version, last_version, reports
  )
  values (new.group_key, label, new.kind, new.app_version, new.app_version, 1)
  on conflict (group_key) do update
  set last_seen_at = now(),
      last_version = case
        when excluded.last_version = '' then g.last_version
        else excluded.last_version
      end,
      reports = g.reports + 1;
  return new;
end;
$$;

revoke execute on function public.client_errors_set_group()
  from public, anon, authenticated;

drop trigger if exists client_errors_set_group on public.client_errors;
create trigger client_errors_set_group
  before insert on public.client_errors
  for each row execute function public.client_errors_set_group();

-- The reports already there get a group, and the groups they make are
-- marked as told.
update public.client_errors e
set group_key = substr(
  md5(public.client_error_group_label(e.kind, e.message, e.stack, e.context)),
  1,
  16
)
where e.group_key is null;

insert into public.ops_error_groups (
  group_key, label, kind, first_seen_at, last_seen_at, first_version,
  last_version, reports, alerted_at
)
select
  x.group_key,
  x.label,
  x.kind,
  x.first_seen,
  x.last_seen,
  x.first_version,
  x.last_version,
  x.reports,
  now()
from (
  select
    e.group_key,
    (array_agg(public.client_error_group_label(e.kind, e.message, e.stack, e.context)
      order by e.created_at desc))[1] as label,
    (array_agg(e.kind order by e.created_at desc))[1] as kind,
    min(e.created_at) as first_seen,
    max(e.created_at) as last_seen,
    (array_agg(e.app_version order by e.created_at))[1] as first_version,
    (array_agg(e.app_version order by e.created_at desc))[1] as last_version,
    count(*) as reports
  from public.client_errors e
  where e.group_key is not null
  group by e.group_key
) x
on conflict (group_key) do nothing;

-- The biggest groups of the last [hours] hours: how often, how many people,
-- when, and in which versions. [is_new] says the group first showed up inside
-- the window.
create or replace function public.admin_ops_error_groups(
  hours integer default 24,
  max_rows integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  span interval := make_interval(hours => least(greatest(coalesce(hours, 24), 1), 720));
  lim integer := least(greatest(coalesce(max_rows, 20), 1), 100);
  result jsonb;
begin
  perform public.admin_require(array['owner', 'moderator', 'support']);

  select coalesce(jsonb_agg(r.entry order by r.occurrences desc, r.last_seen desc), '[]'::jsonb)
  into result
  from (
    select
      jsonb_build_object(
        'group_key', e.group_key,
        'label', coalesce(g.label, e.group_key),
        'kind', e.kind,
        'occurrences', sum(e.count),
        'reports', count(*),
        'people', count(distinct e.user_id),
        'first_seen_at', coalesce(g.first_seen_at, min(e.created_at)),
        'last_seen_at', max(e.created_at),
        'first_version', coalesce(g.first_version, ''),
        'latest_version', (array_agg(e.app_version order by e.created_at desc))[1],
        'is_new', coalesce(g.first_seen_at, min(e.created_at)) > now() - span
      ) as entry,
      sum(e.count) as occurrences,
      max(e.created_at) as last_seen
    from public.client_errors e
    left join public.ops_error_groups g on g.group_key = e.group_key
    where e.created_at > now() - span
      and e.group_key is not null
    group by e.group_key, e.kind, g.label, g.first_seen_at, g.first_version
    order by sum(e.count) desc, max(e.created_at) desc
    limit lim
  ) r;

  return result;
end;
$$;

revoke execute on function public.admin_ops_error_groups(integer, integer) from public, anon;
grant execute on function public.admin_ops_error_groups(integer, integer) to authenticated;
