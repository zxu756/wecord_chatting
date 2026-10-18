-- Community guidelines, privacy policy and age declaration (G10): when a
-- person agreed to the Terms and Community Guidelines and declared that they
-- are old enough.
--
-- * profiles.accepted_terms_at and profiles.age_confirmed_at. Not readable by
--   clients (profiles has column-level select, 202610170101); a person reads
--   their own through get_my_terms_status().
-- * Sign-up: the app inserts the profile with both columns set; the trigger
--   replaces whatever time the client sent with the server's clock, so the
--   time is the server's. Nothing can change them afterwards through the
--   table API (profiles has no update policy).
-- * People who signed up before this: accept_terms() records the acceptance
--   once, when they agree in the app's one-time prompt. It never overwrites
--   an earlier time.
-- * The minimum age itself is not in the database. The age the person
--   declared is the app's `minimumAge` constant
--   (lib/features/legal/minimum_age.dart); the owner confirmed 13+ on
--   2026-10-18. Changing it needs no migration; the policy texts are in
--   assets/legal/.

alter table public.profiles
  add column if not exists accepted_terms_at timestamptz,
  add column if not exists age_confirmed_at timestamptz;

create or replace function public.profiles_stamp_consent()
returns trigger
language plpgsql
as $$
begin
  if new.accepted_terms_at is not null then
    new.accepted_terms_at := now();
  end if;
  if new.age_confirmed_at is not null then
    new.age_confirmed_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_stamp_consent on public.profiles;
create trigger profiles_stamp_consent
  before insert on public.profiles
  for each row execute function public.profiles_stamp_consent();

-- {accepted_terms_at, age_confirmed_at} of the caller; both null until they
-- agreed.
create or replace function public.get_my_terms_status()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'accepted_terms_at', p.accepted_terms_at,
    'age_confirmed_at', p.age_confirmed_at
  )
  from public.profiles p
  where p.id = auth.uid();
$$;

-- Records that the caller agreed to the Terms and Community Guidelines and
-- confirmed their age, now. Does nothing for a column that is already set.
create or replace function public.accept_terms()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.profiles p
  set accepted_terms_at = coalesce(p.accepted_terms_at, now()),
      age_confirmed_at = coalesce(p.age_confirmed_at, now())
  where p.id = auth.uid();

  return public.get_my_terms_status();
end;
$$;

revoke execute on function public.get_my_terms_status() from public, anon;
revoke execute on function public.accept_terms() from public, anon;
grant execute on function public.get_my_terms_status() to authenticated;
grant execute on function public.accept_terms() to authenticated;
