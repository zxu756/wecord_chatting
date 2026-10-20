-- Monitoring and alerts (K3), part 3 of 4: what the admin console's Alerts
-- tab calls. Roles as in 202610210130: owner and moderator may acknowledge
-- and close alerts; support (and the other two) may read. Acknowledging and
-- closing are written to the audit log (as a 'config' target with the alert
-- in the details).
--
-- * admin_list_ops_checks(): the latest result of every check and when the
--   checks last ran (the 'heartbeat' row), so the console can say "the checks
--   have not run for 20 minutes".
-- * admin_list_ops_alerts(status_filter, page_size, before_opened_at): 'open'
--   (default) or 'resolved', newest first.
-- * admin_ack_ops_alert(id): "I have seen it". It stays open until the
--   problem is gone, but it is marked, with who did it. An event alert (a
--   new kind of error) is closed by it.
-- * admin_resolve_ops_alert(id): closes it and takes the cards back. If the
--   problem is still there, the next check reopens the same alert quietly
--   (no new card, no push) within an hour.

create or replace function public.admin_list_ops_checks()
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

  select jsonb_build_object(
    'now', now(),
    'heartbeat_at', (select c.checked_at from public.ops_checks c where c.key = 'heartbeat'),
    'checks', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'key', c.key,
          'status', c.status,
          'detail', c.detail,
          'checked_at', c.checked_at,
          'changed_at', c.changed_at
        )
        order by c.key
      )
      from public.ops_checks c
      where c.key <> 'heartbeat'
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

create or replace function public.admin_list_ops_alerts(
  status_filter text default 'open',
  page_size integer default 30,
  before_opened_at timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  page integer := least(greatest(coalesce(page_size, 30), 1), 100);
  want_open boolean := coalesce(status_filter, 'open') <> 'resolved';
  result jsonb;
begin
  perform public.admin_require(array['owner', 'moderator', 'support']);

  select coalesce(jsonb_agg(e.entry order by e.opened_at desc), '[]'::jsonb)
  into result
  from (
    select
      jsonb_build_object(
        'id', a.id,
        'check_key', a.check_key,
        'kind', a.kind,
        'severity', a.severity,
        'title_en', a.title_en,
        'title_zh', a.title_zh,
        'body_en', a.body_en,
        'body_zh', a.body_zh,
        'detail', a.detail,
        'opened_at', a.opened_at,
        'updated_at', a.updated_at,
        'acknowledged_at', a.acknowledged_at,
        'acknowledged_by', ack.username,
        'resolved_at', a.resolved_at,
        'resolved_by', res.username,
        'resolution', a.resolution,
        'reopen_count', a.reopen_count
      ) as entry,
      a.opened_at
    from public.ops_alerts a
    left join public.profiles ack on ack.id = a.acknowledged_by
    left join public.profiles res on res.id = a.resolved_by
    where (a.resolved_at is null) = want_open
      and (before_opened_at is null or a.opened_at < before_opened_at)
    order by a.opened_at desc
    limit page
  ) e;
  return result;
end;
$$;

create or replace function public.admin_ack_ops_alert(target_alert_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  found_alert public.ops_alerts;
begin
  perform public.admin_require(array['owner', 'moderator']);

  select * into found_alert
  from public.ops_alerts a
  where a.id = target_alert_id and a.resolved_at is null
  for update;
  if not found then
    raise exception 'Alert not found or already closed' using errcode = 'P0002';
  end if;

  if found_alert.kind = 'event' then
    perform public.ops_close_alert(found_alert.check_key, auth.uid(), 'manual');
  else
    update public.ops_alerts a
    set acknowledged_at = coalesce(a.acknowledged_at, now()),
        acknowledged_by = coalesce(a.acknowledged_by, auth.uid()),
        updated_at = now()
    where a.id = target_alert_id;
  end if;

  perform public.admin_write_audit(
    'ack_ops_alert',
    'config',
    target_alert_id,
    null,
    jsonb_build_object(
      'title', coalesce(nullif(found_alert.title_en, ''), found_alert.title_zh),
      'area', 'ops_alert',
      'check', found_alert.check_key
    )
  );
end;
$$;

create or replace function public.admin_resolve_ops_alert(target_alert_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  found_alert public.ops_alerts;
begin
  perform public.admin_require(array['owner', 'moderator']);

  select * into found_alert
  from public.ops_alerts a
  where a.id = target_alert_id and a.resolved_at is null
  for update;
  if not found then
    raise exception 'Alert not found or already closed' using errcode = 'P0002';
  end if;

  perform public.ops_close_alert(found_alert.check_key, auth.uid(), 'manual');

  perform public.admin_write_audit(
    'resolve_ops_alert',
    'config',
    target_alert_id,
    null,
    jsonb_build_object(
      'title', coalesce(nullif(found_alert.title_en, ''), found_alert.title_zh),
      'area', 'ops_alert',
      'check', found_alert.check_key
    )
  );
end;
$$;

revoke execute on function public.admin_list_ops_checks() from public, anon;
revoke execute on function public.admin_list_ops_alerts(text, integer, timestamptz)
  from public, anon;
revoke execute on function public.admin_ack_ops_alert(uuid) from public, anon;
revoke execute on function public.admin_resolve_ops_alert(uuid) from public, anon;
grant execute on function public.admin_list_ops_checks() to authenticated;
grant execute on function public.admin_list_ops_alerts(text, integer, timestamptz)
  to authenticated;
grant execute on function public.admin_ack_ops_alert(uuid) to authenticated;
grant execute on function public.admin_resolve_ops_alert(uuid) to authenticated;
