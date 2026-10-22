-- Two-step recovery codes and passkeys (roadmap G4), part 2 of 4: the codes.
--
-- Making codes (generate_mfa_recovery_codes, called by the signed-in person):
--   * the session must be at aal2 and have passed a code from the
--     authenticator app in the last 10 minutes (the "amr" claim of the access
--     token), so a stolen session that never held the authenticator cannot
--     make itself a way around it. aal2 also proves a verified factor exists.
--   * 10 new codes replace every old one (used or not) at once. At most 5
--     times an hour.
--   * the codes are returned once; only their salted hashes are kept.
--   * the record gets an event and the person's devices get a push.
--
-- Using one (consume_mfa_recovery_code + finish_mfa_recovery, called by the
-- mfa-recovery Edge Function with the service role after it has checked the
-- caller's token):
--   * 5 wrong codes lock recovery for 30 minutes (and raise an event + push);
--   * a right code is used up. The function then removes the authenticator
--     with the Auth Admin API; finish_mfa_recovery(success) records it,
--     deletes the rest of the codes (two-step is off, they mean nothing) and
--     pushes. If removing the authenticator failed, finish(false) gives the
--     code back.
--
-- Run-on notes: nothing here reads auth.mfa_factors, so it cannot break when
-- Auth changes that table; the Edge Function asks the Admin API instead.

-- 10 characters from an alphabet of 32 without look-alikes (no 0 O 1 I).
create or replace function public.new_recovery_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  bytes bytea := extensions.gen_random_bytes(10);
  code text := '';
  i integer;
begin
  for i in 0..9 loop
    -- 256 is a multiple of 32, so every character is equally likely.
    code := code || substr(alphabet, (get_byte(bytes, i) % 32) + 1, 1);
  end loop;
  return code;
end;
$$;

revoke execute on function public.new_recovery_code() from public, anon, authenticated;

-- Upper case, letters and digits only: what the person typed, with or
-- without the dash and spaces.
create or replace function public.normalize_recovery_code(raw text)
returns text
language sql
immutable
set search_path = public
as $$
  select upper(regexp_replace(coalesce(raw, ''), '[^A-Za-z0-9]', '', 'g'));
$$;

revoke execute on function public.normalize_recovery_code(text) from public, anon, authenticated;

create or replace function public.recovery_code_hash(salt text, code text)
returns text
language sql
immutable
set search_path = public
as $$
  select encode(extensions.digest(salt || code, 'sha256'), 'hex');
$$;

revoke execute on function public.recovery_code_hash(text, text) from public, anon, authenticated;

create or replace function public.generate_mfa_recovery_codes()
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  claims jsonb := coalesce(auth.jwt(), '{}'::jsonb);
  last_totp bigint;
  raw text;
  salt text;
  shown text[] := '{}';
  i integer;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if claims ->> 'aal' is distinct from 'aal2' then
    raise exception 'aal2_required' using errcode = '42501';
  end if;

  select max((e ->> 'timestamp')::bigint)
  into last_totp
  from jsonb_array_elements(
    case when jsonb_typeof(claims -> 'amr') = 'array'
      then claims -> 'amr' else '[]'::jsonb end
  ) e
  where e ->> 'method' = 'totp';
  if last_totp is null or last_totp < extract(epoch from now())::bigint - 600 then
    raise exception 'fresh_verification_required' using errcode = '42501';
  end if;

  if (
    select count(*)
    from public.account_security_events ev
    where ev.user_id = me
      and ev.kind = 'recovery_codes_generated'
      and ev.created_at > now() - interval '1 hour'
  ) >= 5 then
    raise exception 'rate_limited' using errcode = '54000';
  end if;

  -- The new set replaces the old one whole.
  delete from public.mfa_recovery_codes where user_id = me;
  delete from public.mfa_recovery_attempts where user_id = me;

  for i in 1..10 loop
    raw := public.new_recovery_code();
    salt := encode(extensions.gen_random_bytes(16), 'hex');
    insert into public.mfa_recovery_codes (user_id, salt, code_hash)
    values (me, salt, public.recovery_code_hash(salt, raw));
    shown := shown || (substr(raw, 1, 5) || '-' || substr(raw, 6, 5));
  end loop;

  perform public.record_account_security_event(
    me, 'recovery_codes_generated', jsonb_build_object('count', 10)
  );
  return shown;
end;
$$;

revoke execute on function public.generate_mfa_recovery_codes() from public, anon;
grant execute on function public.generate_mfa_recovery_codes() to authenticated;

-- How many codes are left (never the codes).
create or replace function public.my_mfa_recovery_status()
returns table (
  remaining integer,
  total integer,
  generated_at timestamptz,
  locked_until timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  return query
  select
    (count(*) filter (where c.used_at is null))::integer,
    count(*)::integer,
    min(c.created_at),
    (
      select a.locked_until
      from public.mfa_recovery_attempts a
      where a.user_id = me and a.locked_until > now()
    )
  from public.mfa_recovery_codes c
  where c.user_id = me;
end;
$$;

revoke execute on function public.my_mfa_recovery_status() from public, anon;
grant execute on function public.my_mfa_recovery_status() to authenticated;

-- Tries a code for [target_user_id]. Never raises for a wrong code (the
-- count of failures has to be saved), returns jsonb:
--   {ok: true, code_id, remaining}
--   {ok: false, reason: 'locked', retry_after_seconds}
--   {ok: false, reason: 'no_codes'}
--   {ok: false, reason: 'invalid', attempts_left}
create or replace function public.consume_mfa_recovery_code(
  target_user_id uuid,
  submitted_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  max_failures constant integer := 5;
  attempt public.mfa_recovery_attempts;
  normalized text := public.normalize_recovery_code(submitted_code);
  hit uuid;
  left_over integer;
begin
  if target_user_id is null then
    raise exception 'A user is required' using errcode = '22023';
  end if;

  insert into public.mfa_recovery_attempts (user_id)
  values (target_user_id)
  on conflict (user_id) do nothing;

  select * into attempt
  from public.mfa_recovery_attempts a
  where a.user_id = target_user_id
  for update;

  if attempt.locked_until is not null and attempt.locked_until > now() then
    return jsonb_build_object(
      'ok', false,
      'reason', 'locked',
      'retry_after_seconds',
      greatest(1, ceil(extract(epoch from attempt.locked_until - now()))::integer)
    );
  end if;

  if not exists (
    select 1
    from public.mfa_recovery_codes c
    where c.user_id = target_user_id and c.used_at is null
  ) then
    return jsonb_build_object('ok', false, 'reason', 'no_codes');
  end if;

  -- A lock that ran out starts the count again.
  if attempt.locked_until is not null then
    attempt.failed_count := 0;
  end if;

  select c.id
  into hit
  from public.mfa_recovery_codes c
  where c.user_id = target_user_id
    and c.used_at is null
    and length(normalized) = 10
    and c.code_hash = public.recovery_code_hash(c.salt, normalized)
  limit 1;

  if hit is not null then
    update public.mfa_recovery_codes set used_at = now() where id = hit;
    update public.mfa_recovery_attempts
    set failed_count = 0, locked_until = null
    where user_id = target_user_id;
    select count(*)::integer into left_over
    from public.mfa_recovery_codes c
    where c.user_id = target_user_id and c.used_at is null;
    return jsonb_build_object('ok', true, 'code_id', hit, 'remaining', left_over);
  end if;

  attempt.failed_count := attempt.failed_count + 1;
  if attempt.failed_count >= max_failures then
    update public.mfa_recovery_attempts
    set failed_count = 0,
        locked_until = now() + interval '30 minutes',
        last_failed_at = now()
    where user_id = target_user_id;
    if exists (
      select 1 from public.profiles p
      where p.id = target_user_id and p.deleted_at is null
    ) then
      perform public.record_account_security_event(
        target_user_id, 'recovery_locked', jsonb_build_object('minutes', 30)
      );
    end if;
    return jsonb_build_object(
      'ok', false,
      'reason', 'locked',
      'retry_after_seconds', 1800
    );
  end if;

  update public.mfa_recovery_attempts
  set failed_count = attempt.failed_count,
      locked_until = null,
      last_failed_at = now()
  where user_id = target_user_id;
  return jsonb_build_object(
    'ok', false,
    'reason', 'invalid',
    'attempts_left', max_failures - attempt.failed_count
  );
end;
$$;

revoke execute on function public.consume_mfa_recovery_code(uuid, text)
  from public, anon, authenticated;
grant execute on function public.consume_mfa_recovery_code(uuid, text) to service_role;

-- The second half of using a code, after the Edge Function tried to remove
-- the authenticator. [succeeded]: record it (with how many codes were left
-- over, as consume_mfa_recovery_code reported), delete the other codes and
-- push. Not: give the code back so the person can try again. The service
-- role calls it; the code row may already be gone on success (a trigger on
-- auth.mfa_factors forgets the codes when the authenticator is removed), so
-- success does not look for it.
create or replace function public.finish_mfa_recovery(
  target_user_id uuid,
  used_code_id uuid,
  succeeded boolean,
  codes_left integer default 0
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if target_user_id is null or used_code_id is null then
    raise exception 'A user and a code are required' using errcode = '22023';
  end if;

  if coalesce(succeeded, false) then
    delete from public.mfa_recovery_codes where user_id = target_user_id;

    if exists (
      select 1 from public.profiles p
      where p.id = target_user_id and p.deleted_at is null
    ) then
      perform public.record_account_security_event(
        target_user_id,
        'recovery_code_used',
        jsonb_build_object('remaining', greatest(coalesce(codes_left, 0), 0))
      );
    end if;
  else
    update public.mfa_recovery_codes
    set used_at = null
    where id = used_code_id
      and user_id = target_user_id
      and used_at is not null;
  end if;
end;
$$;

revoke execute on function public.finish_mfa_recovery(uuid, uuid, boolean, integer)
  from public, anon, authenticated;
grant execute on function public.finish_mfa_recovery(uuid, uuid, boolean, integer) to service_role;
