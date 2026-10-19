-- Feature flags and the minimum version (K4), part 2 of 2: the admin
-- functions behind the console's "Flags" tab.
--
-- Same rules as the other admin functions (202610210130): security definer,
-- admin_require() first (42501 for anybody else), every change in the audit
-- log in the same transaction. Roles:
--   owner                        sets and deletes flags, sets the minimum
--                                version (they reach every user)
--   owner, moderator, support    read
-- The allow list is written with usernames and kept as ids.

-- All flags, newest first, with the allow list as usernames.
create or replace function public.admin_list_feature_flags()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  perform public.admin_require(array['owner', 'moderator', 'support']);

  select coalesce(jsonb_agg(row_json order by created_at desc), '[]'::jsonb)
  into result
  from (
    select
      jsonb_build_object(
        'key', f.key,
        'description', f.description,
        'enabled', f.enabled,
        'rollout_percent', f.rollout_percent,
        'allow_usernames', coalesce((
          select jsonb_agg(p.username order by p.username)
          from public.profiles p
          where p.id = any (f.allow_user_ids)
        ), '[]'::jsonb),
        'min_version', f.min_version,
        'updated_at', f.updated_at
      ) as row_json,
      f.created_at
    from public.feature_flags f
  ) rows;

  return result;
end;
$$;

-- Creates or changes a flag. [allow_usernames] must all exist.
create or replace function public.admin_set_feature_flag(
  flag_key text,
  flag_description text,
  flag_enabled boolean,
  flag_rollout_percent integer,
  allow_usernames text[] default '{}',
  flag_min_version text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_key text := lower(btrim(coalesce(flag_key, '')));
  clean_version text := btrim(coalesce(flag_min_version, ''));
  names text[];
  ids uuid[];
  existed boolean;
begin
  perform public.admin_require(array['owner']);

  if clean_key !~ '^[a-z][a-z0-9_]{1,39}$' then
    raise exception 'A flag key is lower-case letters, digits and underscores'
      using errcode = '22023';
  end if;
  if flag_rollout_percent is null or flag_rollout_percent not between 0 and 100 then
    raise exception 'The roll-out is a percentage from 0 to 100'
      using errcode = '22023';
  end if;
  if clean_version <> '' and public.version_parts(clean_version) is null then
    raise exception 'The version looks like 1.2.3' using errcode = '22023';
  end if;
  if char_length(coalesce(flag_description, '')) > 200 then
    raise exception 'The description is at most 200 characters'
      using errcode = '22023';
  end if;

  select coalesce(array_agg(distinct lower(btrim(n))), '{}')
  into names
  from unnest(coalesce(allow_usernames, '{}')) n
  where btrim(n) <> '';
  if cardinality(names) > 200 then
    raise exception 'At most 200 people on the allow list'
      using errcode = '22023';
  end if;
  select coalesce(array_agg(p.id), '{}')
  into ids
  from public.profiles p
  where p.username = any (names);
  if cardinality(ids) <> cardinality(names) then
    raise exception 'Some of those usernames do not exist'
      using errcode = '22023';
  end if;

  select exists (select 1 from public.feature_flags f where f.key = clean_key)
  into existed;

  insert into public.feature_flags as f (
    key, description, enabled, rollout_percent, allow_user_ids, min_version,
    updated_by
  )
  values (
    clean_key, btrim(coalesce(flag_description, '')), coalesce(flag_enabled, false),
    flag_rollout_percent, ids, clean_version, auth.uid()
  )
  on conflict (key) do update
  set description = excluded.description,
      enabled = excluded.enabled,
      rollout_percent = excluded.rollout_percent,
      allow_user_ids = excluded.allow_user_ids,
      min_version = excluded.min_version,
      updated_by = excluded.updated_by,
      updated_at = now();

  perform public.admin_write_audit(
    'set_feature_flag',
    'flag',
    null,
    null,
    jsonb_build_object(
      'title', clean_key,
      'created', not existed,
      'enabled', coalesce(flag_enabled, false),
      'rollout_percent', flag_rollout_percent,
      'allow_count', cardinality(ids),
      'min_version', clean_version
    )
  );
end;
$$;

create or replace function public.admin_delete_feature_flag(flag_key text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_key text := lower(btrim(coalesce(flag_key, '')));
  removed integer;
begin
  perform public.admin_require(array['owner']);
  delete from public.feature_flags f where f.key = clean_key;
  get diagnostics removed = row_count;
  if removed = 0 then
    raise exception 'Flag not found' using errcode = 'P0002';
  end if;
  perform public.admin_write_audit(
    'delete_feature_flag',
    'flag',
    null,
    null,
    jsonb_build_object('title', clean_key)
  );
end;
$$;

-- The minimum versions as {"web": "...", "all": "..."}; platforms without one
-- are left out.
create or replace function public.admin_get_min_versions()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.admin_require(array['owner', 'moderator', 'support']);
  return coalesce(
    (select a.value from public.app_config a where a.key = 'min_versions'),
    '{}'::jsonb
  );
end;
$$;

-- Sets the minimum version for one platform ('all' for every platform); an
-- empty [minimum] takes the requirement away.
create or replace function public.admin_set_min_version(
  client_platform text,
  minimum text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  platform text := lower(btrim(coalesce(client_platform, '')));
  clean text := btrim(coalesce(minimum, ''));
  existing_config jsonb;
  updated jsonb;
begin
  perform public.admin_require(array['owner']);

  if platform not in ('all', 'web', 'ios', 'android', 'macos', 'windows', 'linux') then
    raise exception 'Unknown platform' using errcode = '22023';
  end if;
  if clean <> '' and public.version_parts(clean) is null then
    raise exception 'The version looks like 1.2.3' using errcode = '22023';
  end if;

  select coalesce(
    (select a.value from public.app_config a where a.key = 'min_versions'),
    '{}'::jsonb
  )
  into existing_config;
  updated := case
    when clean = '' then existing_config - platform
    else existing_config || jsonb_build_object(platform, clean)
  end;

  insert into public.app_config as c (key, value, updated_by)
  values ('min_versions', updated, auth.uid())
  on conflict (key) do update
  set value = excluded.value,
      updated_by = excluded.updated_by,
      updated_at = now();

  perform public.admin_write_audit(
    'set_min_version',
    'config',
    null,
    null,
    jsonb_build_object('title', platform, 'min_version', clean)
  );
end;
$$;

revoke execute on function public.admin_list_feature_flags() from public, anon;
revoke execute on function public.admin_set_feature_flag(text, text, boolean, integer, text[], text)
  from public, anon;
revoke execute on function public.admin_delete_feature_flag(text) from public, anon;
revoke execute on function public.admin_get_min_versions() from public, anon;
revoke execute on function public.admin_set_min_version(text, text) from public, anon;
grant execute on function public.admin_list_feature_flags() to authenticated;
grant execute on function public.admin_set_feature_flag(text, text, boolean, integer, text[], text)
  to authenticated;
grant execute on function public.admin_delete_feature_flag(text) to authenticated;
grant execute on function public.admin_get_min_versions() to authenticated;
grant execute on function public.admin_set_min_version(text, text) to authenticated;
