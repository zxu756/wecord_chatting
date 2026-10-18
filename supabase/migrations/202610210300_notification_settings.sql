-- Notification settings on the server: quiet hours and important contacts.
--
-- Notification preferences used to live only in SharedPreferences, which the
-- server cannot see. Quiet hours need the server (it decides whether to push),
-- so they get a table of their own, and the device-local "message previews"
-- switch moves here too (show_previews; null = not moved yet, the app writes
-- its local value on first run).
--
-- * user_notification_settings: one row per person, owner-only.
--     timezone        IANA name the device reports ('Asia/Shanghai'); null
--                     falls back to the zone of the newest push subscription,
--                     then UTC (see notification_time_zone).
--     quiet_days      ISO weekdays (1 Monday .. 7 Sunday) on which the window
--                     STARTS. A 23:00-07:00 window on Monday runs into Tuesday
--                     morning, so Tuesday 03:00 is quiet when Monday is picked.
--     quiet_start/end wall-clock times in that zone. start > end crosses
--                     midnight; start = end is an empty window.
--     allow_*         what breaks through quiet hours (starred friends,
--                     @mentions of me, calls), vip_user_ids the friends chosen
--                     as important contacts.
-- * set_important_contact(friend, on): adds or removes one friend without the
--   app having to read and rewrite the whole array.
-- * Unfriending or blocking takes the friend out of both sides' lists.

create table if not exists public.user_notification_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  timezone text,
  quiet_enabled boolean not null default false,
  quiet_days integer[] not null default '{1,2,3,4,5,6,7}',
  quiet_start time not null default '22:00',
  quiet_end time not null default '07:00',
  allow_starred boolean not null default true,
  allow_mentions boolean not null default true,
  allow_calls boolean not null default true,
  vip_user_ids uuid[] not null default '{}',
  show_previews boolean,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_notification_settings_timezone_check
    check (timezone is null or timezone ~ '^[A-Za-z0-9_+./-]{1,64}$'),
  constraint user_notification_settings_days_check
    check (quiet_days <@ array[1, 2, 3, 4, 5, 6, 7] and cardinality(quiet_days) <= 7),
  constraint user_notification_settings_vip_check
    check (cardinality(vip_user_ids) <= 100)
);

alter table public.user_notification_settings enable row level security;

revoke all on public.user_notification_settings from anon, authenticated;
grant select, insert, update on public.user_notification_settings to authenticated;

drop policy if exists user_notification_settings_select_own on public.user_notification_settings;
create policy user_notification_settings_select_own
  on public.user_notification_settings for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists user_notification_settings_insert_own on public.user_notification_settings;
create policy user_notification_settings_insert_own
  on public.user_notification_settings for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists user_notification_settings_update_own on public.user_notification_settings;
create policy user_notification_settings_update_own
  on public.user_notification_settings for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Keeps the row tidy: days sorted and unique, no duplicate or own id among
-- the important contacts, an unknown time zone dropped to null, and newly
-- added important contacts must be friends.
create or replace function public.user_notification_settings_before_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  added uuid[];
begin
  new.quiet_days := coalesce(
    (select array_agg(distinct d order by d) from unnest(new.quiet_days) d),
    '{}'
  );
  new.vip_user_ids := coalesce(
    (
      select array_agg(distinct v)
      from unnest(new.vip_user_ids) v
      where v <> new.user_id
    ),
    '{}'
  );

  if new.timezone is not null then
    new.timezone := nullif(btrim(new.timezone), '');
  end if;
  if new.timezone is not null
    and not exists (select 1 from pg_timezone_names n where n.name = new.timezone)
  then
    -- A zone this database does not know is no reason to refuse the save.
    new.timezone := null;
  end if;

  if tg_op = 'UPDATE' then
    new.user_id := old.user_id;
    new.created_at := old.created_at;
    new.updated_at := now();
    added := array(
      select v from unnest(new.vip_user_ids) v
      except
      select v from unnest(old.vip_user_ids) v
    );
  else
    added := new.vip_user_ids;
  end if;

  -- The caller (not a trigger run by the service role) may only add friends.
  if auth.uid() is not null and cardinality(added) > 0 and exists (
    select 1
    from unnest(added) v
    where not exists (
      select 1
      from public.friendships f
      where f.user_low_id = least(new.user_id, v)
        and f.user_high_id = greatest(new.user_id, v)
    )
  ) then
    raise exception 'Important contacts must be friends' using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke execute on function public.user_notification_settings_before_write() from public, anon, authenticated;

drop trigger if exists user_notification_settings_before_write on public.user_notification_settings;
create trigger user_notification_settings_before_write
  before insert or update on public.user_notification_settings
  for each row execute function public.user_notification_settings_before_write();

-- Adds or removes one important contact, creating the row when needed.
create or replace function public.set_important_contact(
  target_friend_id uuid,
  important boolean
)
returns void
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
  if target_friend_id is null or target_friend_id = me then
    raise exception 'Choose a friend' using errcode = '22023';
  end if;

  if important then
    insert into public.user_notification_settings as s (user_id, vip_user_ids)
    values (me, array[target_friend_id])
    on conflict (user_id) do update
    set vip_user_ids = array_append(
      array_remove(s.vip_user_ids, target_friend_id),
      target_friend_id
    );
  else
    update public.user_notification_settings s
    set vip_user_ids = array_remove(s.vip_user_ids, target_friend_id)
    where s.user_id = me;
  end if;
end;
$$;

revoke execute on function public.set_important_contact(uuid, boolean) from public, anon;
grant execute on function public.set_important_contact(uuid, boolean) to authenticated;

-- Unfriending and blocking take the friend out of both people's lists.
create or replace function public.forget_important_contacts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.user_notification_settings s
  set vip_user_ids = array_remove(s.vip_user_ids, old.user_high_id)
  where s.user_id = old.user_low_id
    and old.user_high_id = any(s.vip_user_ids);
  update public.user_notification_settings s
  set vip_user_ids = array_remove(s.vip_user_ids, old.user_low_id)
  where s.user_id = old.user_high_id
    and old.user_low_id = any(s.vip_user_ids);
  return old;
end;
$$;

revoke execute on function public.forget_important_contacts() from public, anon, authenticated;

drop trigger if exists friendships_forget_important_contacts on public.friendships;
create trigger friendships_forget_important_contacts
  after delete on public.friendships
  for each row execute function public.forget_important_contacts();
