-- "Download my data" (Settings -> Privacy), served by the data-export Edge
-- Function.
--
-- * Bucket data-exports (private): each export is one ZIP at
--   <user id>/<timestamp>.zip. Only the owner can read their folder (the
--   function hands out signed links); nobody can write through the API, the
--   function uses the service role.
-- * data_exports: one row per export attempt (working, ready, failed or
--   expired), with the stage and progress the app shows. People read their
--   own rows; the function writes them.
-- * begin_data_export(user): the function's first step. One export per 24
--   hours: an export that is working or ready, started less than 24 hours
--   ago, is returned instead of starting another. A working export that
--   has not finished after 20 minutes is marked failed and does not count.
-- * Files are deleted 7 days after the export was made: by the function
--   whenever someone starts an export, and by POSTing {"purge": true} to it
--   with the service role key from a scheduler (docs/data-export.md).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'data-exports',
  'data-exports',
  false,
  104857600,
  array['application/zip']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists data_exports_select_owner on storage.objects;
create policy data_exports_select_owner
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'data-exports'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create table if not exists public.data_exports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'working'
    check (status in ('working', 'ready', 'failed', 'expired')),
  stage text not null default 'queued',
  detail text,
  progress integer not null default 0 check (progress between 0 and 100),
  file_path text,
  byte_size bigint,
  error text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  expires_at timestamptz
);

create index if not exists data_exports_user_idx
  on public.data_exports (user_id, created_at desc);

create index if not exists data_exports_expiry_idx
  on public.data_exports (expires_at)
  where status = 'ready';

alter table public.data_exports enable row level security;

revoke all on public.data_exports from anon, authenticated;
grant select on public.data_exports to authenticated;

drop policy if exists data_exports_select_own on public.data_exports;
create policy data_exports_select_own
  on public.data_exports for select
  to authenticated
  using (user_id = auth.uid());

-- Starts an export for [target_user_id] unless one was started in the last
-- 24 hours. For the Edge Function (service role) only.
create or replace function public.begin_data_export(target_user_id uuid)
returns table (
  export_id uuid,
  started boolean,
  status text,
  retry_after_seconds integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  latest public.data_exports%rowtype;
  new_id uuid;
begin
  if target_user_id is null then
    raise exception 'A user is required' using errcode = '22023';
  end if;

  -- Two taps at once start one export.
  perform pg_advisory_xact_lock(hashtextextended('data-export:' || target_user_id::text, 0));

  select e.* into latest
  from public.data_exports e
  where e.user_id = target_user_id
    and e.status in ('working', 'ready')
    and e.created_at > now() - interval '24 hours'
  order by e.created_at desc
  limit 1;

  if latest.id is not null
    and latest.status = 'working'
    and latest.created_at < now() - interval '20 minutes'
  then
    update public.data_exports
    set status = 'failed', error = 'timeout', completed_at = now()
    where id = latest.id;
    latest := null;
  end if;

  if latest.id is not null then
    return query
    select
      latest.id,
      false,
      latest.status,
      greatest(
        1,
        ceil(extract(epoch from (latest.created_at + interval '24 hours' - now())))::integer
      );
    return;
  end if;

  insert into public.data_exports (user_id)
  values (target_user_id)
  returning id into new_id;

  return query select new_id, true, 'working'::text, 0;
end;
$$;

revoke execute on function public.begin_data_export(uuid) from public;
revoke execute on function public.begin_data_export(uuid) from anon;
revoke execute on function public.begin_data_export(uuid) from authenticated;
