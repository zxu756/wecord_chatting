-- Birthdays (B5), part 1 of 2: what is stored, who sees it.
--
-- A birthday is a month and a day. The year is never stored (nobody needs a
-- person's age to wish them well). It is private by default: only the
-- person's friends can see it, and only if they chose "friends"; "only me"
-- keeps it to oneself (and switches the reminders their friends get off).
--
-- Like bio and banner (202610170101), the columns are not granted to
-- clients: they are read through get_my_profile_extras (my own),
-- get_profile_extras (somebody else's, 202610230650), and
-- list_birthdays_today, which all apply the rule. Writing goes through
-- set_my_birthday; there is no update policy on profiles.
--
-- Also here: birthday_reminders, the reader's own switch for the "it is
-- X's birthday today" notice and push (part 2, 202610230620).
-- A deleted account keeps none of it. Data export reads the whole profile
-- row with the service role, so the birthday is in "Download my data".

alter table public.profiles
  add column if not exists birthday_month smallint,
  add column if not exists birthday_day smallint,
  add column if not exists birthday_visibility text not null default 'friends',
  add column if not exists birthday_reminders boolean not null default true;

alter table public.profiles
  drop constraint if exists profiles_birthday_check;
alter table public.profiles
  add constraint profiles_birthday_check check (
    (birthday_month is null) = (birthday_day is null)
    and (
      birthday_month is null
      or (
        birthday_month between 1 and 12
        and birthday_day between 1 and case birthday_month
          when 2 then 29
          when 4 then 30
          when 6 then 30
          when 9 then 30
          when 11 then 30
          else 31
        end
      )
    )
  );

alter table public.profiles
  drop constraint if exists profiles_birthday_visibility_check;
alter table public.profiles
  add constraint profiles_birthday_visibility_check check (
    birthday_visibility in ('friends', 'self')
  );

create index if not exists profiles_birthday_idx
  on public.profiles (birthday_month, birthday_day)
  where birthday_month is not null;

-- Whether a birthday falls on [on_date]: the same month and day, and a
-- February 29 birthday is kept on February 28 in years without one.
create or replace function public.birthday_falls_on(
  month smallint,
  day smallint,
  on_date date
)
returns boolean
language sql
immutable
as $$
  select month is not null and (
    (extract(month from on_date) = month and extract(day from on_date) = day)
    or (
      month = 2 and day = 29
      and extract(month from on_date) = 2
      and extract(day from on_date) = 28
      and extract(day from (make_date(extract(year from on_date)::integer, 3, 1) - 1)) = 28
    )
  );
$$;

-- Saves my birthday. A null month and day remove it. [visibility] and
-- [reminders] are only changed when given. Returns what is stored.
create or replace function public.set_my_birthday(
  p_month integer default null,
  p_day integer default null,
  p_visibility text default null,
  p_reminders boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if (p_month is null) <> (p_day is null) then
    raise exception 'Give both a month and a day' using errcode = '22023';
  end if;
  if p_month is not null and (
    p_month not between 1 and 12
    or p_day not between 1 and case p_month
      when 2 then 29
      when 4 then 30
      when 6 then 30
      when 9 then 30
      when 11 then 30
      else 31
    end
  ) then
    raise exception 'That date does not exist' using errcode = '22023';
  end if;
  if p_visibility is not null and p_visibility not in ('friends', 'self') then
    raise exception 'Choose friends or only me' using errcode = '22023';
  end if;

  update public.profiles p
  set birthday_month = p_month,
      birthday_day = p_day,
      birthday_visibility = coalesce(p_visibility, p.birthday_visibility),
      birthday_reminders = coalesce(p_reminders, p.birthday_reminders)
  where p.id = me and p.deleted_at is null;
  if not found then
    raise exception 'Profile not found' using errcode = '42501';
  end if;
  return public.get_my_profile_extras() -> 'birthday';
end;
$$;

revoke execute on function public.set_my_birthday(integer, integer, text, boolean)
  from public, anon;
grant execute on function public.set_my_birthday(integer, integer, text, boolean)
  to authenticated;

-- Whether the caller may see the birthday of [target]: their own, or a
-- friend's when the friend chose "friends". Someone who blocked the caller
-- shows nothing (a friendship ends with a block, but the rule does not rely
-- on it).
create or replace function public.can_view_birthday(target_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  viewer uuid := auth.uid();
  choice text;
begin
  if viewer is null or target_user_id is null then
    return false;
  end if;
  if viewer = target_user_id then
    return true;
  end if;
  if public.are_users_blocked(viewer, target_user_id) then
    return false;
  end if;
  select p.birthday_visibility into choice
  from public.profiles p
  where p.id = target_user_id and p.deleted_at is null;
  if choice is distinct from 'friends' then
    return false;
  end if;
  return exists (
    select 1
    from public.friendships f
    where f.user_low_id = least(viewer, target_user_id)
      and f.user_high_id = greatest(viewer, target_user_id)
  );
end;
$$;

revoke execute on function public.can_view_birthday(uuid) from public, anon;
grant execute on function public.can_view_birthday(uuid) to authenticated;

-- The caller's own birthday, reminders and status choice, for the editors.
create or replace function public.get_my_profile_extras()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'birthday', jsonb_build_object(
      'month', p.birthday_month,
      'day', p.birthday_day,
      'visibility', p.birthday_visibility,
      'reminders', p.birthday_reminders
    ),
    'status_visibility', p.status_visibility
  )
  from public.profiles p
  where p.id = auth.uid();
$$;

revoke execute on function public.get_my_profile_extras() from public, anon;
grant execute on function public.get_my_profile_extras() to authenticated;

-- Friends whose birthday is on [on_date] (the caller's own calendar date, so
-- the caller's time zone decides what "today" is), for the cards in
-- Notifications. Only birthdays the caller may see; not for people who turned
-- reminders off for themselves. Names are the caller's aliases.
create or replace function public.list_birthdays_today(on_date date)
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
  select
    p.id,
    p.username,
    coalesce(nullif(btrim(ca.alias), ''), p.display_name),
    p.avatar_url
  from public.profiles me
  join public.friendships f
    on auth.uid() in (f.user_low_id, f.user_high_id)
  join public.profiles p
    on p.id = case
      when f.user_low_id = auth.uid() then f.user_high_id
      else f.user_low_id
    end
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid() and ca.friend_id = p.id
  where me.id = auth.uid()
    and on_date is not null
    and me.birthday_reminders
    and p.deleted_at is null
    and not p.is_bot
    and p.birthday_visibility = 'friends'
    and public.birthday_falls_on(p.birthday_month, p.birthday_day, on_date)
    and not public.are_users_blocked(auth.uid(), p.id)
  order by lower(coalesce(nullif(btrim(ca.alias), ''), p.display_name));
$$;

revoke execute on function public.list_birthdays_today(date) from public, anon;
grant execute on function public.list_birthdays_today(date) to authenticated;

-- A deleted account keeps no birthday.
create or replace function public.clear_deleted_profile_birthday()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.deleted_at is not null then
    new.birthday_month := null;
    new.birthday_day := null;
    new.birthday_visibility := 'friends';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_clear_deleted_birthday on public.profiles;
create trigger profiles_clear_deleted_birthday
  before update of deleted_at on public.profiles
  for each row execute function public.clear_deleted_profile_birthday();
