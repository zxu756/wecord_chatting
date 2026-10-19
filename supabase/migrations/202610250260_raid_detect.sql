-- Raid protection (C6), part 7 of 9: noticing a burst, locking down, and letting go.
--
-- * circle_raid_check(circle): counts the people who joined or asked to join
--   in the last ten minutes (not the owner, not bots; each person once), and
--   how many of them have an account younger than a day. It locks the circle
--   down when the count reaches the circle's threshold (20 by default,
--   circle_security.raid_threshold), or when half the threshold (at least 5)
--   are brand-new accounts. Off for a circle that switched protection off,
--   for a circle that is under a lockdown already, for one that a platform
--   admin has down (K1), and for a circle younger than an hour (creating a
--   circle adds its first members in one go).
--   It never raises: a failure here must not stop anybody from joining.
-- * circle_members_raid_watch and circle_join_requests_raid_watch: deferred
--   constraint triggers, so the check runs when the transaction commits, after
--   every row of a multi-person join is in. Locking the circle down in the
--   middle of "add these friends" would otherwise refuse the rest of them.
-- * start_circle_lockdown_internal / release_circle_lockdown_internal: what a
--   lockdown does (see 202610250250) and undoes. Both write the circle's audit
--   log (raid_lockdown, raid_release; no actor when it was automatic or
--   expired) and a circle_raid_events row. An automatic lockdown also posts an
--   AutoMod-style alert card to the alert channel of the circle's AutoMod
--   rules when it has one, and wakes scheduled-dispatch, which pushes the
--   moderators (202610250280).
-- * circles_join_mode_takeover: when anybody changes the join mode during a
--   lockdown, the lockdown forgets the mode it would restore. Their choice
--   stands.
-- * run_circle_safety_sweep: one pg_cron job, every minute, for the two
--   things that end on their own: bans with an expiry (202610250200) and
--   lockdowns. It replaces nothing: run_later_dispatch is untouched.

create or replace function public.circle_audit_as(
  target_circle_id uuid,
  acting_user_id uuid,
  audit_action text,
  audit_target_type text,
  audit_target_id uuid,
  audit_target_label text,
  audit_changes jsonb default '{}'::jsonb
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.circle_audit_log (
    circle_id, actor_id, action, target_type, target_id, target_label, changes
  )
  values (
    target_circle_id,
    acting_user_id,
    audit_action,
    audit_target_type,
    audit_target_id,
    audit_target_label,
    coalesce(audit_changes, '{}'::jsonb)
  );
$$;

revoke execute on function public.circle_audit_as(
  uuid, uuid, text, text, uuid, text, jsonb
) from public, anon, authenticated;

-- The channel the circle's AutoMod rules send their alerts to: the newest
-- enabled rule that names one. null when there is none.
create or replace function public.circle_alert_channel(target_circle_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select r.alert_channel_id
  from public.circle_automod_rules r
  join public.circle_channels cc
    on cc.id = r.alert_channel_id
    and cc.circle_id = r.circle_id
    and cc.kind <> 'forum'
  where r.circle_id = target_circle_id
    and r.enabled
    and r.alert_channel_id is not null
  order by r.updated_at desc
  limit 1;
$$;

revoke execute on function public.circle_alert_channel(uuid)
  from public, anon, authenticated;

create or replace function public.ensure_circle_security(target_circle_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.circle_security (circle_id)
  values (target_circle_id)
  on conflict (circle_id) do nothing;
$$;

revoke execute on function public.ensure_circle_security(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Locking down and letting go
-- ---------------------------------------------------------------------------

create or replace function public.start_circle_lockdown_internal(
  target_circle_id uuid,
  lock_source text,
  acting_user_id uuid,
  lock_hours integer,
  joined_count integer default null,
  new_account_count integer default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  sec public.circle_security%rowtype;
  circle public.circles%rowtype;
  previous_mode text;
  ends_at timestamptz := now() + make_interval(hours => lock_hours);
  alert_channel_id uuid;
  alert_conversation_id uuid;
begin
  perform public.ensure_circle_security(target_circle_id);

  select s.* into sec
  from public.circle_security s
  where s.circle_id = target_circle_id
  for update;

  if sec.lockdown_until is not null and sec.lockdown_until > now() then
    return false;
  end if;

  select c.* into circle
  from public.circles c
  where c.id = target_circle_id;

  if circle.id is null then
    return false;
  end if;

  if circle.join_mode = 'open' then
    perform set_config('wecord.raid_switch', '1', true);
    update public.circles set join_mode = 'apply' where id = target_circle_id;
    perform set_config('wecord.raid_switch', '', true);
    previous_mode := 'open';
  end if;

  update public.circle_security s
  set
    lockdown_until = ends_at,
    lockdown_started_at = now(),
    -- A burst the check noticed started up to ten minutes ago; a moderator's
    -- lockdown starts now.
    lockdown_window_from = case
      when lock_source = 'auto' then now() - interval '10 minutes'
      else now()
    end,
    lockdown_prev_mode = previous_mode,
    lockdown_source = lock_source,
    lockdown_joins = joined_count,
    lockdown_new_accounts = new_account_count,
    invites_paused_until = greatest(coalesce(s.invites_paused_until, ends_at), ends_at),
    updated_by = acting_user_id,
    updated_at = now()
  where s.circle_id = target_circle_id;

  insert into public.circle_raid_events (
    circle_id, kind, source, joins, new_accounts, actor_id
  )
  values (
    target_circle_id, 'lockdown', lock_source, joined_count,
    new_account_count, acting_user_id
  );

  perform public.circle_audit_as(
    target_circle_id,
    acting_user_id,
    'raid_lockdown',
    'circle',
    target_circle_id,
    circle.name,
    jsonb_strip_nulls(jsonb_build_object(
      'source', lock_source,
      'hours', lock_hours,
      'joins', joined_count,
      'new_accounts', new_account_count,
      'join_mode_switched', previous_mode is not null
    ))
  );

  if lock_source = 'auto' then
    alert_channel_id := public.circle_alert_channel(target_circle_id);
    if alert_channel_id is not null then
      select cc.conversation_id into alert_conversation_id
      from public.circle_channels cc
      where cc.id = alert_channel_id;

      insert into public.messages (
        conversation_id, sender_id, type, body, attachment
      )
      values (
        alert_conversation_id,
        circle.owner_id,
        'system',
        format(
          'Raid protection locked down this circle: %s people joined or asked to join in 10 minutes.',
          coalesce(joined_count, 0)
        ),
        jsonb_strip_nulls(jsonb_build_object(
          'kind', 'raid_alert',
          'joins', joined_count,
          'new_accounts', new_account_count,
          'until', ends_at,
          'hours', lock_hours
        ))
      );
    end if;
    perform public.wake_scheduled_dispatch();
  end if;

  return true;
end;
$$;

revoke execute on function public.start_circle_lockdown_internal(
  uuid, text, uuid, integer, integer, integer
) from public, anon, authenticated;

create or replace function public.release_circle_lockdown_internal(
  target_circle_id uuid,
  release_source text,
  acting_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  sec public.circle_security%rowtype;
  circle public.circles%rowtype;
  restored boolean := false;
begin
  select s.* into sec
  from public.circle_security s
  where s.circle_id = target_circle_id
  for update;

  if sec.circle_id is null or sec.lockdown_until is null then
    return false;
  end if;

  select c.* into circle
  from public.circles c
  where c.id = target_circle_id;

  -- Put the join mode back, if the lockdown changed it and nobody has since.
  if sec.lockdown_prev_mode is not null and circle.join_mode = 'apply' then
    perform set_config('wecord.raid_switch', '1', true);
    update public.circles
    set join_mode = sec.lockdown_prev_mode
    where id = target_circle_id;
    perform set_config('wecord.raid_switch', '', true);
    restored := true;
  end if;

  update public.circle_security s
  set
    lockdown_until = null,
    lockdown_started_at = null,
    lockdown_window_from = null,
    lockdown_prev_mode = null,
    lockdown_source = null,
    lockdown_joins = null,
    lockdown_new_accounts = null,
    -- Letting go also lets invites in again, unless a moderator paused them
    -- for longer on their own.
    invites_paused_until = case
      when s.invites_paused_until is not null
        and s.invites_paused_until <= s.lockdown_until
      then null
      else s.invites_paused_until
    end,
    raid_counted_from = now(),
    updated_by = acting_user_id,
    updated_at = now()
  where s.circle_id = target_circle_id;

  insert into public.circle_raid_events (circle_id, kind, source, actor_id)
  values (target_circle_id, 'release', release_source, acting_user_id);

  perform public.circle_audit_as(
    target_circle_id,
    acting_user_id,
    'raid_release',
    'circle',
    target_circle_id,
    circle.name,
    jsonb_build_object(
      'source', release_source,
      'join_mode_restored', restored
    )
  );

  return true;
end;
$$;

revoke execute on function public.release_circle_lockdown_internal(uuid, text, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Noticing a burst
-- ---------------------------------------------------------------------------

create or replace function public.circle_raid_check(target_circle_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  circle public.circles%rowtype;
  sec public.circle_security%rowtype;
  enabled boolean := true;
  threshold integer := 20;
  lock_hours integer := 1;
  counted_from timestamptz := now() - interval '10 minutes';
  joined integer;
  fresh integer;
begin
  select c.* into circle
  from public.circles c
  where c.id = target_circle_id;

  if circle.id is null
    or circle.disabled_at is not null
    or circle.created_at > now() - interval '1 hour'
  then
    return false;
  end if;

  select s.* into sec
  from public.circle_security s
  where s.circle_id = target_circle_id;

  if sec.circle_id is not null then
    enabled := sec.raid_enabled;
    threshold := sec.raid_threshold;
    lock_hours := sec.raid_lock_hours;
    if sec.lockdown_until is not null and sec.lockdown_until > now() then
      return false;
    end if;
    if sec.raid_counted_from is not null then
      counted_from := greatest(counted_from, sec.raid_counted_from);
    end if;
  end if;

  if not enabled then
    return false;
  end if;

  select count(*), count(*) filter (where w.account_created >= now() - interval '24 hours')
  into joined, fresh
  from (
    select cm.user_id, p.created_at as account_created
    from public.circle_members cm
    join public.profiles p on p.id = cm.user_id
    where cm.circle_id = target_circle_id
      and cm.created_at >= counted_from
      and cm.role <> 'owner'
      and not p.is_bot
    union
    select r.user_id, p.created_at
    from public.circle_join_requests r
    join public.profiles p on p.id = r.user_id
    where r.circle_id = target_circle_id
      and r.created_at >= counted_from
  ) w;

  if joined >= threshold or fresh >= greatest(5, ceil(threshold / 2.0)::integer) then
    return public.start_circle_lockdown_internal(
      target_circle_id, 'auto', null, lock_hours, joined, fresh);
  end if;
  return false;
exception when others then
  raise warning 'circle_raid_check failed: %', sqlerrm;
  return false;
end;
$$;

revoke execute on function public.circle_raid_check(uuid)
  from public, anon, authenticated;

create or replace function public.circle_raid_watch()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.circle_raid_check(new.circle_id);
  return null;
end;
$$;

revoke execute on function public.circle_raid_watch()
  from public, anon, authenticated;

drop trigger if exists circle_members_raid_watch on public.circle_members;
create constraint trigger circle_members_raid_watch
  after insert on public.circle_members
  deferrable initially deferred
  for each row execute function public.circle_raid_watch();

drop trigger if exists circle_join_requests_raid_watch on public.circle_join_requests;
create constraint trigger circle_join_requests_raid_watch
  after insert on public.circle_join_requests
  deferrable initially deferred
  for each row execute function public.circle_raid_watch();

-- Somebody changed the join mode: the lockdown no longer owns it.
create or replace function public.circles_join_mode_takeover()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(current_setting('wecord.raid_switch', true), '') <> '1' then
    update public.circle_security s
    set lockdown_prev_mode = null
    where s.circle_id = new.id
      and s.lockdown_prev_mode is not null;
  end if;
  return null;
end;
$$;

revoke execute on function public.circles_join_mode_takeover()
  from public, anon, authenticated;

drop trigger if exists circles_join_mode_takeover on public.circles;
create trigger circles_join_mode_takeover
  after update of join_mode on public.circles
  for each row
  when (old.join_mode is distinct from new.join_mode)
  execute function public.circles_join_mode_takeover();

-- ---------------------------------------------------------------------------
-- What ends by itself
-- ---------------------------------------------------------------------------

create or replace function public.run_circle_safety_sweep()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  ended record;
begin
  perform public.expire_circle_bans();

  for ended in
    select s.circle_id
    from public.circle_security s
    where s.lockdown_until is not null
      and s.lockdown_until <= now()
  loop
    perform public.release_circle_lockdown_internal(ended.circle_id, 'expired', null);
  end loop;
end;
$$;

revoke execute on function public.run_circle_safety_sweep()
  from public, anon, authenticated;
grant execute on function public.run_circle_safety_sweep() to service_role;

-- Creates (or replaces) the one-minute job when pg_cron is available. Run
-- `select public.install_circle_safety_schedule();` again after enabling
-- pg_cron in the dashboard if this migration found it missing.
create or replace function public.install_circle_safety_schedule()
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return 'pg_cron is not enabled';
  end if;
  perform cron.schedule(
    'wecord-circle-safety-sweep',
    '* * * * *',
    'select public.run_circle_safety_sweep()'
  );
  return 'scheduled';
end;
$$;

revoke execute on function public.install_circle_safety_schedule()
  from public, anon, authenticated;
grant execute on function public.install_circle_safety_schedule() to service_role;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    begin
      create extension if not exists pg_cron;
    exception when others then
      raise notice 'Could not enable pg_cron: %', sqlerrm;
    end;
  end if;
  raise notice 'Circle safety sweep: %', public.install_circle_safety_schedule();
exception when others then
  raise notice 'Could not schedule the circle safety sweep: %', sqlerrm;
end;
$$;
