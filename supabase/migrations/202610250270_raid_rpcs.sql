-- Raid protection (C6), part 8 of 9: what moderators call, and what a lockdown
-- does to the people who arrived in the burst.
--
-- Who may do what:
--   * read the state, pause or resume invites, start or end a lockdown:
--     members who can act on joining, kick_members or manage_circle (the
--     two permissions that review join requests and run the circle, and
--     the ones the alert goes to);
--   * change the automatic protection (on / off, threshold, how long it
--     lasts): manage_circle.
-- Every call is refused while a platform admin has the circle down (K1) and
-- is audited: invites_pause, invites_resume, raid_lockdown, raid_release
-- (both with no actor when the clock or the check did it), raid_settings_update.
--
-- During a lockdown the people who joined in the burst (circle_members
-- .created_at at or after circle_security.lockdown_window_from), except
-- anyone who moderates (manage_messages, kick_members or manage_circle) and
-- bots, are "raid newcomers":
--   * a text message of theirs with a link (http://, https:// or www.) is
--     refused (SQLSTATE 42501, detail raid_newcomer_links);
--   * when the circle uses the AI guard (and allows AI), their text messages
--     are checked by it whatever its own "who is new" rule says. The trigger
--     is named to fire right after messages_review_guard, and only sets
--     review_state to 'checking', which the guard's own AFTER INSERT trigger,
--     the AI function, the Review queue and the sweep then handle as they
--     always do. Without the guard nothing else is held back.
-- System notices and webhook posts are never touched.

create index if not exists circle_security_lockdown_idx
  on public.circle_security (lockdown_until)
  where lockdown_until is not null;

create or replace function public.assert_can_run_circle_safety(target_circle_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not (
    public.current_user_has_circle_permission(target_circle_id, 'kick_members')
    or public.current_user_has_circle_permission(target_circle_id, 'manage_circle')
  ) then
    raise exception 'Only moderators who review members can do that'
      using errcode = '42501';
  end if;
  perform public.assert_circle_up(target_circle_id);
end;
$$;

revoke execute on function public.assert_can_run_circle_safety(uuid)
  from public, anon, authenticated;

-- The circle's safety state:
-- {raid_enabled, raid_threshold, raid_lock_hours, can_manage, join_mode,
--  invites_paused_until, lockdown: null | {until, started_at, source, joins,
--  new_accounts, mode_switched}, recent_joins, recent_new_accounts}.
create or replace function public.get_circle_security(target_circle_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  sec public.circle_security%rowtype;
  counted_from timestamptz := now() - interval '10 minutes';
  joined integer;
  fresh integer;
  mode text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not (
    public.current_user_has_circle_permission(target_circle_id, 'kick_members')
    or public.current_user_has_circle_permission(target_circle_id, 'manage_circle')
  ) then
    raise exception 'Only moderators who review members can see this'
      using errcode = '42501';
  end if;

  select s.* into sec
  from public.circle_security s
  where s.circle_id = target_circle_id;
  select c.join_mode into mode from public.circles c where c.id = target_circle_id;

  if sec.raid_counted_from is not null then
    counted_from := greatest(counted_from, sec.raid_counted_from);
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

  return jsonb_build_object(
    'raid_enabled', coalesce(sec.raid_enabled, true),
    'raid_threshold', coalesce(sec.raid_threshold, 20),
    'raid_lock_hours', coalesce(sec.raid_lock_hours, 1),
    'can_manage', public.current_user_has_circle_permission(
      target_circle_id, 'manage_circle'),
    'join_mode', mode,
    'invites_paused_until', case
      when sec.invites_paused_until > now() then sec.invites_paused_until
    end,
    'lockdown', case
      when sec.lockdown_until > now() then jsonb_build_object(
        'until', sec.lockdown_until,
        'started_at', sec.lockdown_started_at,
        'source', sec.lockdown_source,
        'joins', sec.lockdown_joins,
        'new_accounts', sec.lockdown_new_accounts,
        'mode_switched', sec.lockdown_prev_mode is not null
      )
    end,
    'recent_joins', joined,
    'recent_new_accounts', fresh
  );
end;
$$;

create or replace function public.set_circle_raid_settings(
  target_circle_id uuid,
  protection_enabled boolean,
  join_threshold integer,
  lockdown_hours integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  old public.circle_security%rowtype;
  changes jsonb := '{}'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'Only members who can manage the circle can change this'
      using errcode = '42501';
  end if;
  perform public.assert_circle_up(target_circle_id);

  if protection_enabled is null
    or join_threshold is null or join_threshold not between 3 and 500
    or lockdown_hours is null or lockdown_hours not in (1, 24)
  then
    raise exception 'Invalid raid protection settings' using errcode = '22023';
  end if;

  perform public.ensure_circle_security(target_circle_id);
  select s.* into old
  from public.circle_security s
  where s.circle_id = target_circle_id
  for update;

  update public.circle_security s
  set
    raid_enabled = protection_enabled,
    raid_threshold = join_threshold,
    raid_lock_hours = lockdown_hours,
    updated_by = auth.uid(),
    updated_at = now()
  where s.circle_id = target_circle_id;

  if old.raid_enabled is distinct from protection_enabled then
    changes := changes || jsonb_build_object('enabled',
      jsonb_build_object('old', old.raid_enabled, 'new', protection_enabled));
  end if;
  if old.raid_threshold is distinct from join_threshold then
    changes := changes || jsonb_build_object('threshold',
      jsonb_build_object('old', old.raid_threshold, 'new', join_threshold));
  end if;
  if old.raid_lock_hours is distinct from lockdown_hours then
    changes := changes || jsonb_build_object('hours',
      jsonb_build_object('old', old.raid_lock_hours, 'new', lockdown_hours));
  end if;

  if changes <> '{}'::jsonb then
    perform public.write_circle_audit(
      target_circle_id,
      'raid_settings_update',
      'circle',
      target_circle_id,
      (select c.name from public.circles c where c.id = target_circle_id),
      changes
    );
  end if;
end;
$$;

create or replace function public.pause_circle_invites(
  target_circle_id uuid,
  pause_hours integer
)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  ends_at timestamptz;
begin
  perform public.assert_can_run_circle_safety(target_circle_id);

  if pause_hours is null or pause_hours not in (1, 24) then
    raise exception 'Invites can be paused for 1 or 24 hours' using errcode = '22023';
  end if;

  perform public.ensure_circle_security(target_circle_id);
  ends_at := now() + make_interval(hours => pause_hours);

  update public.circle_security s
  set
    -- Never shortens a pause that is already longer (a lockdown's).
    invites_paused_until = greatest(coalesce(s.invites_paused_until, ends_at), ends_at),
    updated_by = auth.uid(),
    updated_at = now()
  where s.circle_id = target_circle_id
  returning s.invites_paused_until into ends_at;

  perform public.write_circle_audit(
    target_circle_id,
    'invites_pause',
    'circle',
    target_circle_id,
    (select c.name from public.circles c where c.id = target_circle_id),
    jsonb_build_object('hours', pause_hours, 'until', ends_at)
  );

  return ends_at;
end;
$$;

create or replace function public.resume_circle_invites(target_circle_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  sec public.circle_security%rowtype;
begin
  perform public.assert_can_run_circle_safety(target_circle_id);

  select s.* into sec
  from public.circle_security s
  where s.circle_id = target_circle_id
  for update;

  if sec.lockdown_until is not null and sec.lockdown_until > now() then
    raise exception 'End the lockdown first' using
      errcode = '55000', detail = 'lockdown_active';
  end if;

  if sec.circle_id is null
    or sec.invites_paused_until is null
    or sec.invites_paused_until <= now()
  then
    return;
  end if;

  update public.circle_security s
  set invites_paused_until = null, updated_by = auth.uid(), updated_at = now()
  where s.circle_id = target_circle_id;

  perform public.write_circle_audit(
    target_circle_id,
    'invites_resume',
    'circle',
    target_circle_id,
    (select c.name from public.circles c where c.id = target_circle_id),
    '{}'::jsonb
  );
end;
$$;

create or replace function public.start_circle_lockdown(
  target_circle_id uuid,
  lockdown_hours integer
)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  ends_at timestamptz;
begin
  perform public.assert_can_run_circle_safety(target_circle_id);

  if lockdown_hours is null or lockdown_hours not in (1, 24) then
    raise exception 'A lockdown lasts 1 or 24 hours' using errcode = '22023';
  end if;

  perform public.start_circle_lockdown_internal(
    target_circle_id, 'manual', auth.uid(), lockdown_hours);

  select s.lockdown_until into ends_at
  from public.circle_security s
  where s.circle_id = target_circle_id;
  return ends_at;
end;
$$;

create or replace function public.end_circle_lockdown(target_circle_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_can_run_circle_safety(target_circle_id);
  return public.release_circle_lockdown_internal(
    target_circle_id, 'manual', auth.uid());
end;
$$;

-- ---------------------------------------------------------------------------
-- Newcomers of a burst
-- ---------------------------------------------------------------------------

create or replace function public.circle_raid_newcomer(
  target_circle_id uuid,
  target_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
      select 1
      from public.circle_security s
      join public.circle_members cm
        on cm.circle_id = s.circle_id
        and cm.user_id = target_user_id
      where s.circle_id = target_circle_id
        and s.lockdown_until > now()
        and cm.created_at >= s.lockdown_window_from
    )
    and not exists (
      select 1 from public.profiles p where p.id = target_user_id and p.is_bot
    )
    and not public.circle_member_has_permission(
      target_circle_id, target_user_id, 'manage_messages')
    and not public.circle_member_has_permission(
      target_circle_id, target_user_id, 'kick_members')
    and not public.circle_member_has_permission(
      target_circle_id, target_user_id, 'manage_circle');
$$;

revoke execute on function public.circle_raid_newcomer(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.messages_review_raid()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  channel_circle_id uuid;
begin
  if new.type = 'system'
    or new.webhook_id is not null
    or new.sender_id is null
  then
    return new;
  end if;

  -- The usual case, nothing under lockdown anywhere, costs one index probe.
  if not exists (
    select 1 from public.circle_security s where s.lockdown_until > now()
  ) then
    return new;
  end if;

  select cc.circle_id
  into channel_circle_id
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(new.conversation_id);
  if channel_circle_id is null
    or not public.circle_raid_newcomer(channel_circle_id, new.sender_id)
  then
    return new;
  end if;

  if new.type = 'text' and new.body ~* '(https?://|www\.)' then
    raise exception 'New members cannot post links while the circle is locked down'
      using errcode = '42501', detail = 'raid_newcomer_links';
  end if;

  if new.type = 'text'
    and new.review_state is null
    and btrim(coalesce(new.body, '')) <> ''
    and exists (
      select 1
      from public.circle_ai_guard g
      join public.circles c on c.id = g.circle_id
      where g.circle_id = channel_circle_id
        and g.enabled
        and c.ai_enabled
    )
  then
    new.review_state := 'checking';
  end if;
  return new;
end;
$$;

revoke execute on function public.messages_review_raid()
  from public, anon, authenticated;

-- Sorts right after messages_review_guard, which resets review_state first.
drop trigger if exists messages_review_raid on public.messages;
create trigger messages_review_raid
  before insert on public.messages
  for each row execute function public.messages_review_raid();

revoke execute on function public.get_circle_security(uuid) from public, anon;
revoke execute on function public.set_circle_raid_settings(uuid, boolean, integer, integer)
  from public, anon;
revoke execute on function public.pause_circle_invites(uuid, integer) from public, anon;
revoke execute on function public.resume_circle_invites(uuid) from public, anon;
revoke execute on function public.start_circle_lockdown(uuid, integer) from public, anon;
revoke execute on function public.end_circle_lockdown(uuid) from public, anon;
grant execute on function public.get_circle_security(uuid) to authenticated;
grant execute on function public.set_circle_raid_settings(uuid, boolean, integer, integer)
  to authenticated;
grant execute on function public.pause_circle_invites(uuid, integer) to authenticated;
grant execute on function public.resume_circle_invites(uuid) to authenticated;
grant execute on function public.start_circle_lockdown(uuid, integer) to authenticated;
grant execute on function public.end_circle_lockdown(uuid) to authenticated;
