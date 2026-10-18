-- Feature flags, gradual roll-out and a minimum app version (K4), part 1 of
-- 2: the tables, the audit log's new target types and the functions the app
-- calls at start. Part 2 (202610240610) holds the admin functions.
--
-- * app_config(key, value): settings for the whole app. Today one key,
--   'min_versions': {"web": "1.2.0", "ios": "", "all": ""}. An app whose
--   version is lower than the one for its platform (or for "all") shows the
--   "Please update" page.
-- * feature_flags(key, enabled, rollout_percent, allow_user_ids, min_version):
--   a flag is on for a person when it is enabled and
--     1. the app is at least min_version (when one is set), and
--     2. the person is on the allow list, or
--     3. rollout_percent is 100, or the person's bucket is below it.
--   The bucket is a number from 0 to 99 made from the person's id and the
--   flag's key (flag_bucket), so the same person always gets the same answer
--   and a roll-out only ever adds people when the percentage goes up.
--   "enabled" off is the one switch that turns a flag off for everybody.
-- * get_my_flags(platform, version): what the app asks at start. It answers
--   {flags: {key: true|false}, min_version: "1.2.0"}; granted to signed-out
--   callers too (they only get the minimum version and flags that are on for
--   everybody), so the update page also shows before sign-in.
--
-- Flags only decide what the app shows. Nothing in the database trusts a
-- flag: a rule that has to hold is a policy or a check, never a flag.
--
-- Nobody reads or writes the two tables through the API; the functions here
-- and the admin functions of part 2 (platform admins only) are the only way
-- in.

-- ---------------------------------------------------------------------------
-- Audit log: the new kinds of target
-- ---------------------------------------------------------------------------

alter table public.admin_audit_log
  drop constraint if exists admin_audit_log_target_type_check;
alter table public.admin_audit_log
  add constraint admin_audit_log_target_type_check check (
    target_type in (
      'report', 'user', 'circle', 'circle_post', 'message',
      'flag', 'config', 'announcement', 'feedback'
    )
  );

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.app_config (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint app_config_key_format check (key ~ '^[a-z][a-z0-9_]{0,39}$')
);

create table if not exists public.feature_flags (
  key text primary key,
  description text not null default '',
  enabled boolean not null default false,
  rollout_percent integer not null default 0,
  allow_user_ids uuid[] not null default '{}'::uuid[],
  min_version text not null default '',
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint feature_flags_key_format check (key ~ '^[a-z][a-z0-9_]{1,39}$'),
  constraint feature_flags_description_length check (
    char_length(description) <= 200
  ),
  constraint feature_flags_rollout_range check (
    rollout_percent between 0 and 100
  ),
  constraint feature_flags_allow_size check (
    cardinality(allow_user_ids) <= 200
  ),
  constraint feature_flags_min_version_length check (
    char_length(min_version) <= 40
  )
);

alter table public.app_config enable row level security;
alter table public.feature_flags enable row level security;
revoke all on public.app_config from public, anon, authenticated;
revoke all on public.feature_flags from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Versions
-- ---------------------------------------------------------------------------

-- "1.2.3", "1.2", "v1.2.3+45" and "1.2.3-beta" as {1,2,3}; null when the text
-- is not a version.
create or replace function public.version_parts(version_text text)
returns integer[]
language plpgsql
immutable
set search_path = public
as $$
declare
  core text;
  pieces text[];
  parts integer[] := '{}';
  piece text;
begin
  if version_text is null then
    return null;
  end if;
  core := btrim(version_text);
  core := regexp_replace(core, '^[vV]', '');
  core := split_part(split_part(core, '+', 1), '-', 1);
  if core !~ '^[0-9]{1,6}(\.[0-9]{1,6}){0,2}$' then
    return null;
  end if;
  pieces := string_to_array(core, '.');
  foreach piece in array pieces loop
    parts := parts || piece::integer;
  end loop;
  while cardinality(parts) < 3 loop
    parts := parts || 0;
  end loop;
  return parts;
end;
$$;

-- Whether [version_text] is at least [minimum]. No minimum, a minimum that is
-- not a version, or a version that is not one (a development build) all
-- count as "yes": a mistake in a setting must never lock people out.
create or replace function public.version_at_least(
  version_text text,
  minimum text
)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  have integer[] := public.version_parts(version_text);
  need integer[] := public.version_parts(minimum);
begin
  if need is null or have is null then
    return true;
  end if;
  return have >= need;
end;
$$;

-- ---------------------------------------------------------------------------
-- Buckets and flags
-- ---------------------------------------------------------------------------

-- The person's bucket for a flag: 0 to 99, always the same for the same
-- person and flag.
create or replace function public.flag_bucket(user_id uuid, flag_key text)
returns integer
language sql
immutable
set search_path = public
as $$
  select (
    ('x' || substr(md5(flag_key || ':' || user_id::text), 1, 8))::bit(32)::bigint
    % 100
  )::integer;
$$;

-- Whether [flag] is on for [uid] (null: nobody signed in) on an app of
-- [client_version]. Internal.
create or replace function public.flag_is_on(
  flag public.feature_flags,
  uid uuid,
  client_version text
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select case
    when not flag.enabled then false
    when not public.version_at_least(client_version, flag.min_version) then false
    when uid is not null and uid = any (flag.allow_user_ids) then true
    when flag.rollout_percent >= 100 then true
    when uid is null or flag.rollout_percent <= 0 then false
    else public.flag_bucket(uid, flag.key) < flag.rollout_percent
  end;
$$;

-- The minimum version for [client_platform]: the platform's own setting, else
-- the one for "all", else ''. Internal.
create or replace function public.min_version_for(client_platform text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(btrim(c.value ->> lower(btrim(coalesce(client_platform, '')))), ''),
    nullif(btrim(c.value ->> 'all'), ''),
    ''
  )
  from (
    select coalesce(
      (select a.value from public.app_config a where a.key = 'min_versions'),
      '{}'::jsonb
    ) as value
  ) c;
$$;

revoke execute on function public.min_version_for(text) from public, anon, authenticated;

-- What the app asks for at start.
create or replace function public.get_my_flags(
  client_platform text default null,
  client_version text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  flag_map jsonb;
begin
  select coalesce(jsonb_object_agg(f.key, public.flag_is_on(f, uid, client_version)), '{}'::jsonb)
  into flag_map
  from public.feature_flags f;

  return jsonb_build_object(
    'flags', flag_map,
    'min_version', public.min_version_for(client_platform)
  );
end;
$$;

revoke execute on function public.version_parts(text) from public;
revoke execute on function public.version_at_least(text, text) from public;
revoke execute on function public.flag_bucket(uuid, text) from public, anon, authenticated;
revoke execute on function public.flag_is_on(public.feature_flags, uuid, text)
  from public, anon, authenticated;
revoke execute on function public.get_my_flags(text, text) from public;
grant execute on function public.version_parts(text) to anon, authenticated;
grant execute on function public.version_at_least(text, text) to anon, authenticated;
grant execute on function public.get_my_flags(text, text) to anon, authenticated;
