-- Daily AI request counts, for the per-user limit of the `ai` Edge Function.
--
-- * ai_usage: one row per user and UTC day with the number of AI requests
--   made. Owners can read their own rows; nobody writes it directly.
-- * ai_consume_request(user, limit): counts one request unless the day's
--   limit is reached (allowed = false, nothing counted). ai_refund_request
--   gives one back when the provider failed; ai_requests_today reads the
--   count. All three are for the Edge Function (service role) only, so a
--   user cannot reset or inflate their own count. Only counts are kept, no
--   message content.

create table if not exists public.ai_usage (
  user_id uuid not null references public.profiles(id) on delete cascade,
  day date not null default ((now() at time zone 'utc')::date),
  requests integer not null default 0 check (requests >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

alter table public.ai_usage enable row level security;

drop policy if exists ai_usage_select_own on public.ai_usage;
create policy ai_usage_select_own
  on public.ai_usage for select
  to authenticated
  using (user_id = auth.uid());

revoke all on public.ai_usage from anon, authenticated;
grant select on public.ai_usage to authenticated;

create or replace function public.ai_consume_request(
  p_user_id uuid,
  p_limit integer
)
returns table (allowed boolean, used integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  today date := (now() at time zone 'utc')::date;
  new_count integer;
begin
  if p_user_id is null or p_limit is null or p_limit < 1 then
    raise exception 'A user and a positive limit are required' using errcode = '22023';
  end if;

  -- Old days are not needed.
  delete from public.ai_usage u
  where u.user_id = p_user_id and u.day < today - 30;

  insert into public.ai_usage as u (user_id, day, requests)
  values (p_user_id, today, 0)
  on conflict (user_id, day) do nothing;

  update public.ai_usage u
  set requests = u.requests + 1, updated_at = now()
  where u.user_id = p_user_id and u.day = today and u.requests < p_limit
  returning u.requests into new_count;

  if new_count is not null then
    return query select true, new_count;
  else
    return query
      select false, u.requests
      from public.ai_usage u
      where u.user_id = p_user_id and u.day = today;
  end if;
end;
$$;

create or replace function public.ai_refund_request(p_user_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.ai_usage u
  set requests = greatest(u.requests - 1, 0), updated_at = now()
  where u.user_id = p_user_id and u.day = (now() at time zone 'utc')::date;
$$;

create or replace function public.ai_requests_today(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select u.requests
      from public.ai_usage u
      where u.user_id = p_user_id and u.day = (now() at time zone 'utc')::date
    ),
    0
  );
$$;

revoke execute on function public.ai_consume_request(uuid, integer) from public;
revoke execute on function public.ai_consume_request(uuid, integer) from anon;
revoke execute on function public.ai_consume_request(uuid, integer) from authenticated;
grant execute on function public.ai_consume_request(uuid, integer) to service_role;

revoke execute on function public.ai_refund_request(uuid) from public;
revoke execute on function public.ai_refund_request(uuid) from anon;
revoke execute on function public.ai_refund_request(uuid) from authenticated;
grant execute on function public.ai_refund_request(uuid) to service_role;

revoke execute on function public.ai_requests_today(uuid) from public;
revoke execute on function public.ai_requests_today(uuid) from anon;
revoke execute on function public.ai_requests_today(uuid) from authenticated;
grant execute on function public.ai_requests_today(uuid) to service_role;
