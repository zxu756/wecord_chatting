-- Reporting a public circle, with the reports table of identity safety
-- (202605190001) and its reasons.
--
-- * reports.target_circle_id: the reported circle. target_user_id is its
--   owner, who answers for it (so owners cannot report their own circle,
--   as reports_not_self already says).
-- * report_circle(circle_id, reason, details): any signed-in user, for a
--   public circle (or one they are a member of). An open report of the
--   same circle by the same user is reused (its reason and details are
--   updated), and a user files at most 10 circle reports an hour (PB429).

alter table public.reports
  add column if not exists target_circle_id uuid
    references public.circles(id) on delete set null;

create index if not exists reports_target_circle_created_idx
  on public.reports (target_circle_id, created_at desc)
  where target_circle_id is not null;

create or replace function public.report_circle(
  target_circle_id uuid,
  report_reason text,
  report_details text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  circle public.circles%rowtype;
  existing_report_id uuid;
  created_report_id uuid;
  clean_details text := left(btrim(coalesce(report_details, '')), 1000);
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select c.* into circle
  from public.circles c
  where c.id = target_circle_id;

  if circle.id is null
    or not (circle.is_public or public.is_current_user_circle_member(circle.id))
  then
    raise exception 'Circle not found' using errcode = 'P0002';
  end if;

  if circle.owner_id = current_user_id then
    raise exception 'Cannot report your own circle' using errcode = '22023';
  end if;

  if report_reason is null or report_reason not in (
    'spam', 'harassment', 'impersonation', 'unsafe_content', 'other'
  ) then
    raise exception 'Unknown reason' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('circle-report:' || current_user_id::text, 0));

  select r.id into existing_report_id
  from public.reports r
  where r.reporter_id = current_user_id
    and r.target_circle_id = circle.id
    and r.status = 'open'
  order by r.created_at desc
  limit 1;

  if existing_report_id is not null then
    update public.reports r
    set reason = report_reason, details = clean_details
    where r.id = existing_report_id;
    return existing_report_id;
  end if;

  if (
    select count(*)
    from public.reports r
    where r.reporter_id = current_user_id
      and r.target_circle_id is not null
      and r.created_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception 'Too many reports. Try again later.' using errcode = 'PB429';
  end if;

  insert into public.reports (
    reporter_id,
    target_user_id,
    target_circle_id,
    reason,
    details
  )
  values (
    current_user_id,
    circle.owner_id,
    circle.id,
    report_reason,
    clean_details
  )
  returning id into created_report_id;

  return created_report_id;
end;
$$;

revoke execute on function public.report_circle(uuid, text, text) from public, anon;
grant execute on function public.report_circle(uuid, text, text) to authenticated;
