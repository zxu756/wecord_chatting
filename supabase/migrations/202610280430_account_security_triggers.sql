-- Two-step recovery codes and passkeys (roadmap G4), part 4 of 4: listening
-- to Supabase Auth.
--
-- Auth keeps the passkeys (auth.webauthn_credentials) and the factors
-- (auth.mfa_factors); the app talks to Auth directly, so the only place the
-- database learns that a passkey was added or removed, or that the
-- authenticator app was turned off, is a trigger on those tables:
--
--   * passkey added / removed  -> an event in the security record + a push;
--   * the last verified authenticator removed -> the recovery codes go too
--     (without two-step verification they open nothing).
--
-- Auth's tables belong to Auth and a hosted project may not let this
-- migration put a trigger on them, so each trigger is installed on a
-- best-effort basis: where it cannot be, the feature still works (the codes
-- are checked by the Edge Function against the factors the Admin API lists,
-- and a new set replaces the old one), and a notice says so. The trigger
-- functions never raise: Auth's own delete or insert must not fail because
-- of this record, and they skip accounts that are being deleted (the cascade
-- from auth.users removes the passkeys and factors after the profile has
-- been erased).

create or replace function public.passkey_security_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid;
  label text;
begin
  if tg_op = 'INSERT' then
    owner_id := new.user_id;
    label := new.friendly_name;
  else
    owner_id := old.user_id;
    label := old.friendly_name;
  end if;

  if exists (select 1 from auth.users u where u.id = owner_id)
    and exists (
      select 1 from public.profiles p
      where p.id = owner_id and p.deleted_at is null
    )
  then
    perform public.record_account_security_event(
      owner_id,
      case when tg_op = 'INSERT' then 'passkey_added' else 'passkey_removed' end,
      jsonb_build_object('name', left(coalesce(btrim(label), ''), 80))
    );
  end if;
  return null;
exception when others then
  return null;
end;
$$;

revoke execute on function public.passkey_security_event()
  from public, anon, authenticated;

create or replace function public.mfa_factor_removed_forget_codes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.factor_type::text = 'totp'
    and old.status::text = 'verified'
    and not exists (
      select 1
      from auth.mfa_factors f
      where f.user_id = old.user_id
        and f.id <> old.id
        and f.factor_type::text = 'totp'
        and f.status::text = 'verified'
    )
  then
    delete from public.mfa_recovery_codes where user_id = old.user_id;
    delete from public.mfa_recovery_attempts where user_id = old.user_id;
  end if;
  return null;
exception when others then
  return null;
end;
$$;

revoke execute on function public.mfa_factor_removed_forget_codes()
  from public, anon, authenticated;

do $$
begin
  if to_regclass('auth.webauthn_credentials') is not null then
    drop trigger if exists passkey_security_event on auth.webauthn_credentials;
    create trigger passkey_security_event
      after insert or delete on auth.webauthn_credentials
      for each row execute function public.passkey_security_event();
  else
    raise notice 'auth.webauthn_credentials is missing: passkey events are not recorded';
  end if;
exception when others then
  raise notice 'passkey trigger not installed (%): passkey events are not recorded', sqlerrm;
end;
$$;

do $$
begin
  if to_regclass('auth.mfa_factors') is not null then
    drop trigger if exists mfa_factor_removed_forget_codes on auth.mfa_factors;
    create trigger mfa_factor_removed_forget_codes
      after delete on auth.mfa_factors
      for each row execute function public.mfa_factor_removed_forget_codes();
  end if;
exception when others then
  raise notice 'factor trigger not installed (%): codes stay until replaced', sqlerrm;
end;
$$;
