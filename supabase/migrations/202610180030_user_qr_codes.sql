-- My QR code: https://wecord.jokebear.fyi/u/<code>.
--
-- Every user has one opaque, resettable code for their QR card. The code is
-- NOT the user id: it is 16 random symbols from a 32 symbol alphabet (80
-- bits, not guessable), made the first time the user asks for it. Anyone
-- who scans it (or opens the link while signed in) lands on the owner's
-- profile, where the usual Add friend / Message actions are.
--
-- * "Reset QR code" gives the user a new code; the old one stops working at
--   once (it is the same row, so there is nothing old left to find).
-- * Nothing is revealed for a code that does not exist, a deleted account,
--   or a pair of people where either blocked the other: all of them look
--   like "no such code".
-- * The table takes no direct reads or writes; get_my_qr_code,
--   reset_my_qr_code and resolve_user_qr_code are the only ways in.

create table if not exists public.user_qr_codes (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  code text not null unique,
  created_at timestamptz not null default now(),
  reset_at timestamptz
);

alter table public.user_qr_codes enable row level security;
revoke all on public.user_qr_codes from anon, authenticated;

-- 16 symbols from a 32 symbol alphabet (each random byte maps without
-- modulo bias).
create or replace function public.generate_user_qr_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  alphabet constant text := 'abcdefghijkmnpqrstuvwxyz23456789';
  random_bytes bytea := extensions.gen_random_bytes(16);
  generated_code text := '';
begin
  for byte_index in 0..15 loop
    generated_code := generated_code
      || substr(alphabet, (get_byte(random_bytes, byte_index) % 32) + 1, 1);
  end loop;
  return generated_code;
end;
$$;

revoke execute on function public.generate_user_qr_code() from public, anon, authenticated;

-- The caller's code, made on first use.
create or replace function public.get_my_qr_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  existing_code text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select q.code into existing_code
  from public.user_qr_codes q
  where q.user_id = current_user_id;
  if existing_code is not null then
    return existing_code;
  end if;

  loop
    begin
      insert into public.user_qr_codes (user_id, code)
      values (current_user_id, public.generate_user_qr_code())
      on conflict (user_id) do nothing;
      exit;
    exception when unique_violation then
      -- The (unlikely) clash of two random codes: try another.
      null;
    end;
  end loop;

  select q.code into existing_code
  from public.user_qr_codes q
  where q.user_id = current_user_id;
  return existing_code;
end;
$$;

-- Replaces the caller's code; the old one is invalid from now on.
create or replace function public.reset_my_qr_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  new_code text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  loop
    begin
      new_code := public.generate_user_qr_code();
      insert into public.user_qr_codes (user_id, code, reset_at)
      values (current_user_id, new_code, now())
      on conflict (user_id) do update
      set code = excluded.code,
        created_at = now(),
        reset_at = now();
      exit;
    exception when unique_violation then
      null;
    end;
  end loop;

  return new_code;
end;
$$;

-- Who a code belongs to: one row (id, username, name, avatar), or none when
-- the code is unknown, was reset, belongs to a deleted account, or either
-- side blocked the other. A user may resolve their own code.
create or replace function public.resolve_user_qr_code(qr_code text)
returns table (
  user_id uuid,
  username text,
  display_name text,
  avatar_url text
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.username, p.display_name, p.avatar_url
  from public.user_qr_codes q
  join public.profiles p on p.id = q.user_id
  where auth.uid() is not null
    and q.code = lower(btrim(coalesce(qr_code, '')))
    and p.deleted_at is null
    and (
      p.id = auth.uid()
      or not public.are_users_blocked(auth.uid(), p.id)
    );
$$;

revoke execute on function public.get_my_qr_code() from public, anon;
revoke execute on function public.reset_my_qr_code() from public, anon;
revoke execute on function public.resolve_user_qr_code(text) from public, anon;
grant execute on function public.get_my_qr_code() to authenticated;
grant execute on function public.reset_my_qr_code() to authenticated;
grant execute on function public.resolve_user_qr_code(text) to authenticated;
