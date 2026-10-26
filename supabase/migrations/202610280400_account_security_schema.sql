-- Two-step recovery codes and passkeys (roadmap G4), part 1 of 4: the tables.
--
-- * mfa_recovery_codes: the one-time codes that get an account past a lost
--   authenticator app. Only a salted SHA-256 of each code is kept (the code
--   itself is 10 random characters, about 50 bits, shown once). A code is
--   used once (used_at); making new codes deletes every old row.
-- * mfa_recovery_attempts: failed tries per account, for the limit on
--   guessing (5 failures lock recovery for 30 minutes).
-- * account_security_events: the account's own security record (G3's
--   Notifications -> Security chip shows them next to new-login alerts):
--   codes made, a code used, recovery locked, a passkey added or removed.
--   Each one is pushed to the person's devices and waits for "It was me" or
--   "Not me".
--
-- Nothing here is readable by clients: every table is closed, and the
-- functions in the next migrations are the only way in. Supabase Auth is not
-- touched: the passkeys themselves live in Auth (auth.webauthn_credentials)
-- and the factors in auth.mfa_factors.

create table if not exists public.mfa_recovery_codes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  salt text not null,
  code_hash text not null,
  created_at timestamptz not null default now(),
  used_at timestamptz
);

create index if not exists mfa_recovery_codes_user_idx
  on public.mfa_recovery_codes (user_id);

create table if not exists public.mfa_recovery_attempts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  failed_count integer not null default 0 check (failed_count >= 0),
  locked_until timestamptz,
  last_failed_at timestamptz
);

create table if not exists public.account_security_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (
    kind in (
      'recovery_codes_generated',
      'recovery_code_used',
      'recovery_locked',
      'passkey_added',
      'passkey_removed'
    )
  ),
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  push_claimed_at timestamptz,
  resolved_at timestamptz,
  resolution text check (resolution in ('confirmed', 'denied')),
  constraint account_security_events_resolution_pair check (
    (resolved_at is null) = (resolution is null)
  )
);

create index if not exists account_security_events_user_idx
  on public.account_security_events (user_id, created_at desc);

alter table public.mfa_recovery_codes enable row level security;
alter table public.mfa_recovery_attempts enable row level security;
alter table public.account_security_events enable row level security;

revoke all on public.mfa_recovery_codes from public, anon, authenticated;
revoke all on public.mfa_recovery_attempts from public, anon, authenticated;
revoke all on public.account_security_events from public, anon, authenticated;

-- Writes one event and wakes the push sender so it goes out within seconds.
-- Only the functions of this feature call it.
create or replace function public.record_account_security_event(
  target_user_id uuid,
  event_kind text,
  event_detail jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
begin
  insert into public.account_security_events (user_id, kind, detail)
  values (target_user_id, event_kind, coalesce(event_detail, '{}'::jsonb))
  returning id into new_id;

  perform public.wake_scheduled_dispatch();
  return new_id;
end;
$$;

revoke execute on function public.record_account_security_event(uuid, text, jsonb)
  from public, anon, authenticated;

-- Deleting an account (profiles.deleted_at) erases the codes, the attempts
-- and the record, as profiles_erase_honors (202610270200) does for honors;
-- prepare_account_deletion is not rewritten. The codes also go when the
-- login row is removed (on delete cascade).
create or replace function public.erase_account_security_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.mfa_recovery_codes where user_id = new.id;
  delete from public.mfa_recovery_attempts where user_id = new.id;
  delete from public.account_security_events where user_id = new.id;
  return new;
end;
$$;

revoke execute on function public.erase_account_security_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_erase_account_security on public.profiles;
create trigger profiles_erase_account_security
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_account_security_of_deleted_account();
