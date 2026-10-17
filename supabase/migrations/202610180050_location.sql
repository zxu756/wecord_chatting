-- Sending a location and sharing it live.
--
-- * A location is a card in the chat: a 'text' message whose attachment is
--   {kind: 'location', lat, lng, name, address}, like the note and task cards
--   (share_note). Its body is a readable line ("📍 Name · Address"), so
--   previews, pushes, search and older apps show something sensible.
--   send_location validates and posts it.
-- * Live location: live_location_shares says who is sharing in a chat, until
--   when, and whether the position is precise or coarse. NO POSITIONS are
--   stored here or anywhere on the server: they travel as Realtime broadcast
--   messages on one private channel per share, 'live-location:<share id>', and
--   are gone as soon as they have been delivered.
-- * Who may send or listen is decided here, in the policies on
--   realtime.messages (a private channel asks them when it is joined): only
--   members of that chat, not the people the sharer blocked or who blocked
--   them, only while the share runs, and not while the card is waiting for
--   review (AI guard) or has been deleted. The sharer alone may send on it.
-- * A share ends at its time, when the sharer stops it (stop_live_location),
--   when they leave the chat (trigger below) or when the app stops it at
--   sign out (stop_my_live_locations).
--
-- Live sharing is for direct chats and groups; static locations work in every
-- chat.

-- The card -----------------------------------------------------------------

create or replace function public.send_location(
  target_conversation_id uuid,
  place_lat double precision,
  place_lng double precision,
  place_name text default null,
  place_address text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  clean_name text := left(btrim(coalesce(place_name, '')), 200);
  clean_address text := left(btrim(coalesce(place_address, '')), 400);
  line text;
  created_message_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if place_lat is null
    or place_lng is null
    or place_lat not between -90 and 90
    or place_lng not between -180 and 180
  then
    raise exception 'Not a position' using errcode = '22023';
  end if;
  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;
  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Cannot send messages in this conversation'
      using errcode = '42501';
  end if;

  line := concat_ws(
    ' · ',
    nullif(clean_name, ''),
    nullif(clean_address, '')
  );
  if line = '' then
    line := round(place_lat::numeric, 5)::text || ', ' || round(place_lng::numeric, 5)::text;
  end if;

  -- AutoMod (202610160035): a blocked message is dropped, not raised.
  perform set_config('wecord.automod_soft', 'on', true);

  -- The send trigger checks send_messages and slowmode in circle channels,
  -- and the AI guard may hold the card for review.
  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (
    target_conversation_id,
    current_user_id,
    'text',
    left('📍 ' || line, 1000),
    jsonb_build_object(
      'kind', 'location',
      'lat', place_lat,
      'lng', place_lng,
      'name', clean_name,
      'address', clean_address
    )
  )
  returning id into created_message_id;

  perform set_config('wecord.automod_soft', 'off', true);

  return created_message_id;
end;
$$;

-- Live shares --------------------------------------------------------------

create table if not exists public.live_location_shares (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null
    references public.conversations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  -- The card in the chat; null once it is deleted.
  message_id uuid references public.messages (id) on delete set null,
  -- Whether the sharer sends their exact position (otherwise a coarse one).
  precise boolean not null default false,
  started_at timestamptz not null default now(),
  ends_at timestamptz not null,
  stopped_at timestamptz,
  constraint live_location_shares_duration
    check (ends_at > started_at and ends_at <= started_at + interval '8 hours')
);

-- One running share per person and chat.
create unique index if not exists live_location_shares_one_running
  on public.live_location_shares (conversation_id, user_id)
  where stopped_at is null;
create index if not exists live_location_shares_conversation_idx
  on public.live_location_shares (conversation_id, ends_at desc);
create index if not exists live_location_shares_user_idx
  on public.live_location_shares (user_id, ends_at desc);

alter table public.live_location_shares enable row level security;

-- Whether the caller may know of the share: a member of its chat, not
-- blocked either way with the sharer, and its card is still there and not
-- waiting for review (the sharer always sees their own).
create or replace function public.can_see_live_location_share(
  target_share_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.live_location_shares s
    where s.id = target_share_id
      and auth.uid() is not null
      and public.is_current_user_conversation_member(s.conversation_id)
      and (
        s.user_id = auth.uid()
        or (
          not public.are_users_blocked(auth.uid(), s.user_id)
          and exists (
            select 1
            from public.messages m
            where m.id = s.message_id
              and m.recalled_at is null
              and m.review_state is null
          )
        )
      )
  );
$$;

-- Whether the caller may listen to the share's positions: they may know of
-- it and it is running.
create or replace function public.can_receive_live_location(
  target_share_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_see_live_location_share(target_share_id)
    and exists (
      select 1
      from public.live_location_shares s
      where s.id = target_share_id
        and s.stopped_at is null
        and s.ends_at > now()
    );
$$;

-- Whether the caller may send positions on the share: their own, running,
-- and they are still in the chat.
create or replace function public.can_send_live_location(
  target_share_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.live_location_shares s
    where s.id = target_share_id
      and s.user_id = auth.uid()
      and s.stopped_at is null
      and s.ends_at > now()
      and public.is_current_user_conversation_member(s.conversation_id)
  );
$$;

-- The share a private channel topic names, or null.
create or replace function public.live_location_topic_share(topic text)
returns uuid
language sql
immutable
set search_path = public
as $$
  select case
    when topic ~ '^live-location:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then substr(topic, 15)::uuid
  end;
$$;

drop policy if exists live_location_shares_select on public.live_location_shares;
create policy live_location_shares_select
  on public.live_location_shares for select
  to authenticated
  using (public.can_see_live_location_share(id));

revoke all on public.live_location_shares from public, anon, authenticated;
grant select on public.live_location_shares to authenticated;

-- Starts sharing in a chat: stops the caller's earlier share there, posts the
-- card and returns the share. [duration_minutes] is 1 to 480 (the app offers
-- 15, 60 and 480).
create or replace function public.start_live_location(
  target_conversation_id uuid,
  duration_minutes integer,
  precise boolean default false
)
returns table (share_id uuid, message_id uuid, ends_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  new_share_id uuid := gen_random_uuid();
  new_message_id uuid;
  new_ends_at timestamptz;
  chat_type text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if duration_minutes is null or duration_minutes not between 1 and 480 then
    raise exception 'Sharing lasts 1 minute to 8 hours' using errcode = '22023';
  end if;
  select c.type into chat_type
  from public.conversations c
  where c.id = target_conversation_id;
  if chat_type is null
    or not public.is_current_user_conversation_member(target_conversation_id)
  then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;
  if chat_type not in ('direct', 'group') then
    raise exception 'Live location is for direct chats and groups'
      using errcode = '22023';
  end if;
  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Cannot send messages in this conversation'
      using errcode = '42501';
  end if;
  if not public.can_current_user_send_in_conversation(target_conversation_id) then
    raise exception 'You cannot send messages here' using errcode = '42501';
  end if;

  -- Finished shares are not kept for long, and a new one replaces the
  -- caller's running one in this chat.
  delete from public.live_location_shares s
  where s.user_id = current_user_id
    and coalesce(s.stopped_at, s.ends_at) < now() - interval '2 days';
  update public.live_location_shares s
  set stopped_at = now()
  where s.conversation_id = target_conversation_id
    and s.user_id = current_user_id
    and s.stopped_at is null;

  new_ends_at := now() + make_interval(mins => duration_minutes);

  perform set_config('wecord.automod_soft', 'on', true);
  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (
    target_conversation_id,
    current_user_id,
    'text',
    '📍 Live location',
    jsonb_build_object(
      'kind', 'live_location',
      'share_id', new_share_id,
      'ends_at', new_ends_at,
      'precise', precise
    )
  )
  returning id into new_message_id;
  perform set_config('wecord.automod_soft', 'off', true);

  if new_message_id is null then
    raise exception 'Cannot send messages in this conversation'
      using errcode = '42501';
  end if;

  insert into public.live_location_shares (
    id, conversation_id, user_id, message_id, precise, started_at, ends_at
  )
  values (
    new_share_id,
    target_conversation_id,
    current_user_id,
    new_message_id,
    precise,
    now(),
    new_ends_at
  );

  share_id := new_share_id;
  message_id := new_message_id;
  ends_at := new_ends_at;
  return next;
end;
$$;

-- Stops one of the caller's shares (a share already over stays as it was).
create or replace function public.stop_live_location(target_share_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  update public.live_location_shares s
  set stopped_at = now()
  where s.id = target_share_id
    and s.user_id = auth.uid()
    and s.stopped_at is null;
end;
$$;

-- Stops all of the caller's running shares (signing out); returns how many.
create or replace function public.stop_my_live_locations()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  stopped integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  update public.live_location_shares s
  set stopped_at = now()
  where s.user_id = auth.uid()
    and s.stopped_at is null;
  get diagnostics stopped = row_count;
  return stopped;
end;
$$;

-- The shares running in a chat that the caller may see, with who shares.
create or replace function public.list_live_location_shares(
  target_conversation_id uuid
)
returns table (
  share_id uuid,
  user_id uuid,
  display_name text,
  avatar_url text,
  message_id uuid,
  precise boolean,
  started_at timestamptz,
  ends_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  return query
  select
    s.id,
    s.user_id,
    p.display_name,
    p.avatar_url,
    s.message_id,
    s.precise,
    s.started_at,
    s.ends_at
  from public.live_location_shares s
  join public.profiles p on p.id = s.user_id
  where s.conversation_id = target_conversation_id
    and s.stopped_at is null
    and s.ends_at > now()
    and public.can_see_live_location_share(s.id)
  order by s.started_at, s.id;
end;
$$;

-- The shares the caller has running, in any chat (an app that was restarted
-- within a share's time picks it up again).
create or replace function public.list_my_live_location_shares()
returns table (
  share_id uuid,
  conversation_id uuid,
  precise boolean,
  ends_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  return query
  select s.id, s.conversation_id, s.precise, s.ends_at
  from public.live_location_shares s
  where s.user_id = auth.uid()
    and s.stopped_at is null
    and s.ends_at > now()
    and public.is_current_user_conversation_member(s.conversation_id)
  order by s.started_at;
end;
$$;

-- Leaving (or being removed from) a chat ends the share there.
create or replace function public.stop_live_location_on_leave()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.live_location_shares s
  set stopped_at = now()
  where s.conversation_id = old.conversation_id
    and s.user_id = old.user_id
    and s.stopped_at is null;
  return old;
end;
$$;

drop trigger if exists conversation_members_stop_live_location
  on public.conversation_members;
create trigger conversation_members_stop_live_location
  after delete on public.conversation_members
  for each row execute function public.stop_live_location_on_leave();

revoke execute on function public.can_see_live_location_share(uuid) from public, anon;
revoke execute on function public.can_receive_live_location(uuid) from public, anon;
revoke execute on function public.can_send_live_location(uuid) from public, anon;
revoke execute on function public.send_location(uuid, double precision, double precision, text, text) from public, anon;
revoke execute on function public.start_live_location(uuid, integer, boolean) from public, anon;
revoke execute on function public.stop_live_location(uuid) from public, anon;
revoke execute on function public.stop_my_live_locations() from public, anon;
revoke execute on function public.list_live_location_shares(uuid) from public, anon;
revoke execute on function public.list_my_live_location_shares() from public, anon;
revoke execute on function public.stop_live_location_on_leave() from public, anon, authenticated;
grant execute on function public.can_see_live_location_share(uuid) to authenticated;
grant execute on function public.can_receive_live_location(uuid) to authenticated;
grant execute on function public.can_send_live_location(uuid) to authenticated;
grant execute on function public.live_location_topic_share(text) to authenticated;
grant execute on function public.send_location(uuid, double precision, double precision, text, text) to authenticated;
grant execute on function public.start_live_location(uuid, integer, boolean) to authenticated;
grant execute on function public.stop_live_location(uuid) to authenticated;
grant execute on function public.stop_my_live_locations() to authenticated;
grant execute on function public.list_live_location_shares(uuid) to authenticated;
grant execute on function public.list_my_live_location_shares() to authenticated;

-- Positions: private Realtime channels --------------------------------------
-- A private channel asks these policies when someone joins it (and again
-- when their token is refreshed). Only broadcast, only 'live-location:<id>'.

drop policy if exists live_location_receive on realtime.messages;
create policy live_location_receive
  on realtime.messages for select
  to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and public.can_receive_live_location(
      public.live_location_topic_share((select realtime.topic()))
    )
  );

drop policy if exists live_location_send on realtime.messages;
create policy live_location_send
  on realtime.messages for insert
  to authenticated
  with check (
    realtime.messages.extension = 'broadcast'
    and public.can_send_live_location(
      public.live_location_topic_share((select realtime.topic()))
    )
  );

-- Realtime: other members' banners follow the shares starting and stopping.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'live_location_shares'
    )
  then
    alter publication supabase_realtime add table public.live_location_shares;
  end if;
end $$;
